#!/usr/bin/env bash
# Build patched xray, mihomo, and the keqdroid-tun LaunchDaemon for macOS.
#
# Usage:
#   bash tool/build_macos_cores.sh          # build both arm64 and x86_64 separately
#   bash tool/build_macos_cores.sh native   # build host architecture only
#   bash tool/build_macos_cores.sh arm64    # Apple Silicon only
#   bash tool/build_macos_cores.sh x86_64   # Intel only
#
# Output goes to assets/bin/macos/<arch>/{xray,mihomo,keqdroid-tun} and
# assets/bin/macos/{geoip.dat,geosite.dat} (gitignored).

set -euo pipefail

export GOTOOLCHAIN=go1.27.3

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/assets/bin/macos"
PATCH_DIR="$REPO_ROOT/tool/patches"
DAEMON_DIR="$REPO_ROOT/tool/macos_tun_daemon"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"

DEFAULT_XRAY_VERSION="v1.260327.1-0.20261109052709-676eaf66f8f0"
if [ -z "${XRAY_VERSION:-}" ] && [ -f "$REPO_ROOT/../keqrnel/go.mod" ]; then
  XRAY_VERSION="$(awk '/github\.com\/xtls\/xray-core / {print $2; exit}' "$REPO_ROOT/../keqrnel/go.mod")"
fi
XRAY_MODULE="github.com/xtls/xray-core"
XRAY_VERSION="${XRAY_VERSION:-$DEFAULT_XRAY_VERSION}"

DEFAULT_MIHOMO_VERSION="$(awk -F '"' '/\[string\]\$Version = / {print $2; exit}' "$REPO_ROOT/tool/build_mihomo.ps1" | tr -d '\r')"
MIHOMO_MODULE="github.com/metacubex/mihomo"
MIHOMO_VERSION="${MIHOMO_VERSION:-${DEFAULT_MIHOMO_VERSION:-v1.19.34}}"
MIHOMO_TAGS="with_gvisor,no_tailscale,no_zerotier,no_easytier"

TARGET="${1:-all}"
case "$TARGET" in
  all) ARCHS=(arm64 x86_64) ;;
  native)
    case "$(uname -m)" in
      arm64) ARCHS=(arm64) ;;
      x86_64) ARCHS=(x86_64) ;;
      *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    ;;
  arm64) ARCHS=(arm64) ;;
  x86_64|amd64) ARCHS=(x86_64) ;;
  *)
    echo "Usage: $0 [all|native|arm64|x86_64]" >&2
    exit 1
    ;;
esac

for cmd in go git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required tool not found: $cmd" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keqdroid-macos-cores.XXXXXX")"
trap 'chmod -R u+w "$WORK_DIR" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUT_DIR"

goarch_for() {
  case "$1" in
    arm64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "Unsupported arch: $1" >&2; exit 1 ;;
  esac
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

sign_if_macos() {
  local path="$1"
  chmod 0755 "$path"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_IDENTITY" "$path"
  fi
}

apply_patches() {
  local src_dir="$1"
  local pattern="$2"
  local count=0
  for patch in "$PATCH_DIR"/$pattern; do
    [ -f "$patch" ] || continue
    echo "Applying $(basename "$patch") ..."
    git -C "$src_dir" apply --whitespace=nowarn "$patch"
    count=$((count + 1))
  done
  if [ "$count" -eq 0 ]; then
    echo "No patches matching $pattern found in $PATCH_DIR" >&2
    exit 1
  fi
}

download_module() {
  local module="$1"
  local version="$2"
  local dst="$3"
  local mod_dir="$WORK_DIR/mod-dl"
  mkdir -p "$mod_dir"
  if [ ! -f "$mod_dir/go.mod" ]; then
    (cd "$mod_dir" && go mod init keqdroid-macos-cores >/dev/null 2>&1)
  fi
  echo "Downloading ${module}@${version} ..."
  (cd "$mod_dir" && go mod download "${module}@${version}")
  local mod_cache
  mod_cache="$(go env GOMODCACHE)"
  local cached="$mod_cache/${module}@${version}"
  if [ ! -d "$cached" ]; then
    echo "Module not found in cache: $cached" >&2
    exit 1
  fi
  cp -R "$cached" "$dst"
  chmod -R u+w "$dst"
}

report_binary() {
  local path="$1"
  sign_if_macos "$path"
  echo "  -> $path ($(wc -c < "$path" | tr -d ' ') bytes)"
  if command -v lipo >/dev/null 2>&1; then
    lipo -info "$path"
  fi
}

# ---- Build xray ------------------------------------------------------------
XRAY_SRC="$WORK_DIR/xray-src"
download_module "$XRAY_MODULE" "$XRAY_VERSION" "$XRAY_SRC"
if [ -d "$REPO_ROOT/../keqrnel/patches" ]; then
  for patch in "$REPO_ROOT/../keqrnel/patches"/xray-*.patch; do
    [ -f "$patch" ] || continue
    echo "Applying keqrnel/$(basename "$patch") ..."
    git -C "$XRAY_SRC" apply --whitespace=nowarn "$patch"
  done
fi
apply_patches "$XRAY_SRC" "xray-*.patch"

for arch in "${ARCHS[@]}"; do
  goarch="$(goarch_for "$arch")"
  arch_dir="$OUT_DIR/$arch"
  mkdir -p "$arch_dir"
  echo "Building xray for darwin/$goarch ($arch) ..."
  (
    cd "$XRAY_SRC"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
      go build -trimpath -buildvcs=false \
      -ldflags "-s -w -checklinkname=0" \
      -o "$arch_dir/xray" \
      ./main
  )
  report_binary "$arch_dir/xray"
done

# ---- Build mihomo ----------------------------------------------------------
MIHOMO_SRC="$WORK_DIR/mihomo-src"
download_module "$MIHOMO_MODULE" "$MIHOMO_VERSION" "$MIHOMO_SRC"
apply_patches "$MIHOMO_SRC" "mihomo-*.patch"

SING_TUN_VERSION="$(awk '/github\.com\/metacubex\/sing-tun / {print $2; exit}' "$MIHOMO_SRC/go.mod")"
if [ -n "$SING_TUN_VERSION" ]; then
  SING_TUN_SRC="$WORK_DIR/sing-tun-$SING_TUN_VERSION"
  download_module "github.com/metacubex/sing-tun" "$SING_TUN_VERSION" "$SING_TUN_SRC"
  apply_patches "$SING_TUN_SRC" "sing-tun-*.patch"
  (
    cd "$MIHOMO_SRC"
    go mod edit -replace "github.com/metacubex/sing-tun=../sing-tun-$SING_TUN_VERSION"
  )
fi

for arch in "${ARCHS[@]}"; do
  goarch="$(goarch_for "$arch")"
  arch_dir="$OUT_DIR/$arch"
  mkdir -p "$arch_dir"
  echo "Building mihomo for darwin/$goarch ($arch) ..."
  (
    cd "$MIHOMO_SRC"
    GOTOOLCHAIN=go1.26.10 CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
      go build -trimpath -buildvcs=false \
      -tags "$MIHOMO_TAGS" \
      -ldflags "-s -w -checklinkname=0 -X github.com/metacubex/mihomo/constant.Version=$MIHOMO_VERSION" \
      -o "$arch_dir/mihomo" \
      .
  )
  report_binary "$arch_dir/mihomo"
done

# ---- Build keqdroid-tun LaunchDaemon ---------------------------------------
# Build after signing xray and mihomo so embedded SHA-256 digests match the exact signed bytes.
for arch in "${ARCHS[@]}"; do
  goarch="$(goarch_for "$arch")"
  arch_dir="$OUT_DIR/$arch"
  XRAY_SHA="$(sha256_file "$arch_dir/xray")"
  MIHOMO_SHA="$(sha256_file "$arch_dir/mihomo")"
  echo "Building keqdroid-tun for darwin/$goarch ($arch) [xray=${XRAY_SHA:0:12} mihomo=${MIHOMO_SHA:0:12}] ..."
  (
    cd "$DAEMON_DIR"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
      go build -trimpath -buildvcs=false \
      -ldflags "-s -w -X main.xraySHA256=$XRAY_SHA -X main.mihomoSHA256=$MIHOMO_SHA" \
      -o "$arch_dir/keqdroid-tun" \
      .
  )
  report_binary "$arch_dir/keqdroid-tun"
  printf '%s  xray\n%s  mihomo\n' "$XRAY_SHA" "$MIHOMO_SHA" > "$arch_dir/cores.sha256"
done

# ---- Geo databases ---------------------------------------------------------
for geo in geoip.dat geosite.dat; do
  if [ -f "$REPO_ROOT/assets/bin/linux/$geo" ]; then
    cp -f "$REPO_ROOT/assets/bin/linux/$geo" "$OUT_DIR/$geo"
  elif [ -f "$REPO_ROOT/assets/bin/windows/$geo" ]; then
    cp -f "$REPO_ROOT/assets/bin/windows/$geo" "$OUT_DIR/$geo"
  fi
done

echo "Done. macOS cores ready in $OUT_DIR (target: $TARGET)."

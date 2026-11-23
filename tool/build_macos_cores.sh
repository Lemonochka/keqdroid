#!/usr/bin/env bash
# Build patched xray and mihomo cores for macOS (arm64, x86_64, or universal).
#
# Usage:
#   bash tool/build_macos_cores.sh            # host architecture
#   bash tool/build_macos_cores.sh arm64      # Apple Silicon
#   bash tool/build_macos_cores.sh x86_64     # Intel
#   bash tool/build_macos_cores.sh universal  # arm64 + x86_64 via lipo
#
# Output goes to assets/bin/macos/ (gitignored) and is embedded into
# keqdroid.app/Contents/Resources/bin/ during Xcode build.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/assets/bin/macos"
PATCH_DIR="$REPO_ROOT/tool/patches"

# Pinned revisions matching tool/build_xray_cores.ps1 and tool/build_mihomo.ps1.
XRAY_MODULE="github.com/xtls/xray-core"
XRAY_VERSION="${XRAY_VERSION:-v1.260327.1-0.20261109052709-676eaf66f8f0}"
MIHOMO_MODULE="github.com/metacubex/mihomo"
MIHOMO_VERSION="${MIHOMO_VERSION:-v1.19.34}"
MIHOMO_TAGS="with_gvisor,no_tailscale,no_zerotier,no_easytier"

TARGET="${1:-native}"
case "$TARGET" in
  native)
    case "$(uname -m)" in
      arm64) ARCHS=(arm64) ;;
      x86_64) ARCHS=(amd64) ;;
      *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    ;;
  arm64) ARCHS=(arm64) ;;
  x86_64|amd64) ARCHS=(amd64) ;;
  universal) ARCHS=(arm64 amd64) ;;
  *)
    echo "Usage: $0 [native|arm64|x86_64|universal]" >&2
    exit 1
    ;;
esac

for cmd in go git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required tool not found: $cmd" >&2
    exit 1
  fi
done
if [ "${#ARCHS[@]}" -gt 1 ] && ! command -v lipo >/dev/null 2>&1; then
  echo "lipo is required for universal builds (install Xcode Command Line Tools)" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keqdroid-macos-cores.XXXXXX")"
trap 'chmod -R u+w "$WORK_DIR" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUT_DIR"

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

finalize_binary() {
  local name="$1"
  if [ "${#ARCHS[@]}" -eq 1 ]; then
    mv "$WORK_DIR/${name}-${ARCHS[0]}" "$OUT_DIR/$name"
  else
    lipo -create \
      "$WORK_DIR/${name}-arm64" \
      "$WORK_DIR/${name}-amd64" \
      -output "$OUT_DIR/$name"
  fi
  chmod 0755 "$OUT_DIR/$name"
  echo "  -> $OUT_DIR/$name ($(wc -c < "$OUT_DIR/$name" | tr -d ' ') bytes)"
  if command -v lipo >/dev/null 2>&1; then
    lipo -info "$OUT_DIR/$name"
  fi
}

# ---- Build xray ------------------------------------------------------------
XRAY_SRC="$WORK_DIR/xray-src"
download_module "$XRAY_MODULE" "$XRAY_VERSION" "$XRAY_SRC"
apply_patches "$XRAY_SRC" "xray-*.patch"

for arch in "${ARCHS[@]}"; do
  echo "Building xray for darwin/$arch ..."
  (
    cd "$XRAY_SRC"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" \
      go build -trimpath -buildvcs=false \
      -ldflags "-s -w -checklinkname=0" \
      -o "$WORK_DIR/xray-$arch" \
      ./main
  )
done
finalize_binary "xray"

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
  echo "Building mihomo for darwin/$arch ..."
  (
    cd "$MIHOMO_SRC"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" \
      go build -trimpath -buildvcs=false \
      -tags "$MIHOMO_TAGS" \
      -ldflags "-s -w -checklinkname=0 -X github.com/metacubex/mihomo/constant.Version=$MIHOMO_VERSION" \
      -o "$WORK_DIR/mihomo-$arch" \
      .
  )
done
finalize_binary "mihomo"

# ---- Geo databases ---------------------------------------------------------
for geo in geoip.dat geosite.dat; do
  if [ -f "$REPO_ROOT/assets/bin/linux/$geo" ]; then
    cp -f "$REPO_ROOT/assets/bin/linux/$geo" "$OUT_DIR/$geo"
  elif [ -f "$REPO_ROOT/assets/bin/windows/$geo" ]; then
    cp -f "$REPO_ROOT/assets/bin/windows/$geo" "$OUT_DIR/$geo"
  fi
done

echo "Done. macOS cores ready in $OUT_DIR (target: $TARGET)."

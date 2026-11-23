#!/usr/bin/env bash
# Build and package separate arm64 (Apple Silicon) and x86_64 (Intel) macOS DMGs
# in release/<version>/keqdroid-<version>-macos-<arch>.dmg.
#
# Usage:
#   bash tool/package_macos.sh [all|native|arm64|x86_64] [--skip-cores] [--skip-flutter]
#
# Environment variables:
#   MACOS_SIGN_IDENTITY  Code signing identity (default: "-" ad-hoc)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="all"
SKIP_CORES=0
SKIP_FLUTTER=0

for arg in "$@"; do
  case "$arg" in
    all|native|arm64|x86_64) TARGET="$arg" ;;
    --skip-cores) SKIP_CORES=1 ;;
    --skip-flutter) SKIP_FLUTTER=1 ;;
    *)
      echo "Usage: $0 [all|native|arm64|x86_64] [--skip-cores] [--skip-flutter]" >&2
      exit 1
      ;;
  esac
done

case "$TARGET" in
  all) ARCHS=(arm64 x86_64) ;;
  native) ARCHS=("$(uname -m)") ;;
  arm64) ARCHS=(arm64) ;;
  x86_64) ARCHS=(x86_64) ;;
esac

VERSION="$(awk '/^version:/ {sub(/\+.*/, "", $2); print $2; exit}' "$REPO_ROOT/pubspec.yaml")"
if [ -z "$VERSION" ]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
OUT_DIR="$REPO_ROOT/release/$VERSION"

if [ "$SKIP_CORES" -eq 0 ]; then
  bash "$REPO_ROOT/tool/build_macos_cores.sh" "$TARGET"
fi

if [ "$SKIP_FLUTTER" -eq 0 ]; then
  echo "Building Flutter macOS release ..."
  (
    cd "$REPO_ROOT"
    flutter pub get
    flutter build macos --release
  )
fi

APP_SRC="$REPO_ROOT/build/macos/Build/Products/Release/keqdroid.app"
if [ ! -d "$APP_SRC" ]; then
  echo "Built app bundle not found: $APP_SRC" >&2
  exit 1
fi

thin_bundle_to_arch() {
  local app_dir="$1"
  local arch="$2"
  while IFS= read -r -d '' file; do
    [ -L "$file" ] && continue
    local info
    info="$(lipo -info "$file" 2>/dev/null || true)"
    case "$info" in
      "Architectures in the fat file:"*)
        local tmp="${file}.thin.${arch}"
        lipo -thin "$arch" "$file" -output "$tmp"
        mv -f "$tmp" "$file"
        ;;
      "Non-fat file:"*)
        if [[ "$info" != *"is architecture: $arch" ]]; then
          echo "Unexpected single-arch binary for $arch build: $info" >&2
          exit 1
        fi
        ;;
    esac
  done < <(find "$app_dir" -type f -print0)
}

STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/keqdroid-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_ROOT"' EXIT

mkdir -p "$OUT_DIR"

for arch in "${ARCHS[@]}"; do
  STAGE_DIR="$STAGE_ROOT/$arch"
  mkdir -p "$STAGE_DIR"
  cp -R "$APP_SRC" "$STAGE_DIR/keqdroid.app"
  APP_DST="$STAGE_DIR/keqdroid.app"

  # Remove any cores copied during Xcode build before thinning and embedding target arch.
  BIN_DST="$APP_DST/Contents/Resources/bin"
  rm -rf "$BIN_DST"

  echo "Thinning keqdroid.app to $arch ..."
  thin_bundle_to_arch "$APP_DST" "$arch"

  mkdir -p "$BIN_DST"
  CORE_SRC="$REPO_ROOT/assets/bin/macos/$arch"
  for bin in xray mihomo; do
    if [ ! -f "$CORE_SRC/$bin" ]; then
      echo "Missing $arch core: $CORE_SRC/$bin (run tool/build_macos_cores.sh $arch)" >&2
      exit 1
    fi
    cp -f "$CORE_SRC/$bin" "$BIN_DST/$bin"
    chmod 0755 "$BIN_DST/$bin"
    codesign --force --sign "$SIGN_IDENTITY" "$BIN_DST/$bin"
  done
  for geo in geoip.dat geosite.dat; do
    if [ -f "$REPO_ROOT/assets/bin/macos/$geo" ]; then
      cp -f "$REPO_ROOT/assets/bin/macos/$geo" "$BIN_DST/$geo"
    fi
  done

  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DST"

  ln -s /Applications "$STAGE_DIR/Applications"
  DMG_PATH="$OUT_DIR/keqdroid-${VERSION}-macos-${arch}.dmg"
  rm -f "$DMG_PATH"

  echo "Creating $DMG_PATH ..."
  hdiutil create \
    -volname "keqdroid $VERSION ($arch)" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  echo "Done: $DMG_PATH ($(wc -c < "$DMG_PATH" | tr -d ' ') bytes)"
  rm -rf "$STAGE_DIR"
done

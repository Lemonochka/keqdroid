#!/usr/bin/env bash
# Build and package keqdroid for macOS into release/<version>/keqdroid-<version>-macos-<arch>.dmg.
#
# Usage:
#   bash tool/package_macos.sh [native|arm64|x86_64|universal] [--skip-cores]
#
# Environment variables:
#   MACOS_SIGN_IDENTITY  Code signing identity (default: "-" ad-hoc)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="universal"
SKIP_CORES=0

for arg in "$@"; do
  case "$arg" in
    native|arm64|x86_64|universal) TARGET="$arg" ;;
    --skip-cores) SKIP_CORES=1 ;;
    *)
      echo "Usage: $0 [native|arm64|x86_64|universal] [--skip-cores]" >&2
      exit 1
      ;;
  esac
done

if [ "$TARGET" = "native" ]; then
  TARGET="$(uname -m)"
fi

VERSION="$(awk '/^version:/ {sub(/\+.*/, "", $2); print $2; exit}' "$REPO_ROOT/pubspec.yaml")"
if [ -z "$VERSION" ]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
OUT_DIR="$REPO_ROOT/release/$VERSION"
DMG_NAME="keqdroid-${VERSION}-macos-${TARGET}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"

if [ "$SKIP_CORES" -eq 0 ]; then
  bash "$REPO_ROOT/tool/build_macos_cores.sh" "$TARGET"
fi

echo "Building Flutter macOS release ..."
(
  cd "$REPO_ROOT"
  flutter pub get
  flutter build macos --release
)

APP_SRC="$REPO_ROOT/build/macos/Build/Products/Release/keqdroid.app"
if [ ! -d "$APP_SRC" ]; then
  echo "Built app bundle not found: $APP_SRC" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keqdroid-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_SRC" "$STAGE_DIR/keqdroid.app"
APP_DST="$STAGE_DIR/keqdroid.app"

# Ensure cores are present inside the app bundle.
BIN_DST="$APP_DST/Contents/Resources/bin"
mkdir -p "$BIN_DST"
for file in xray mihomo geoip.dat geosite.dat; do
  if [ -f "$REPO_ROOT/assets/bin/macos/$file" ]; then
    cp -f "$REPO_ROOT/assets/bin/macos/$file" "$BIN_DST/$file"
  fi
done
for bin in xray mihomo; do
  if [ -f "$BIN_DST/$bin" ]; then
    chmod 0755 "$BIN_DST/$bin"
    codesign --force --sign "$SIGN_IDENTITY" "$BIN_DST/$bin"
  fi
done

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DST"

ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$OUT_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH ..."
hdiutil create \
  -volname "keqdroid $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Done: $DMG_PATH ($(wc -c < "$DMG_PATH" | tr -d ' ') bytes)"

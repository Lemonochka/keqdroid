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

goarch_for() {
  case "$1" in
    arm64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "Unsupported arch: $1" >&2; exit 1 ;;
  esac
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

VERSION="$(awk '/^version:/ {sub(/\+.*/, "", $2); print $2; exit}' "$REPO_ROOT/pubspec.yaml")"
if [ -z "$VERSION" ]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
OUT_DIR="$REPO_ROOT/release/$VERSION"

if [ "$SKIP_CORES" -eq 0 ]; then
  MACOS_SIGN_IDENTITY="$SIGN_IDENTITY" bash "$REPO_ROOT/tool/build_macos_cores.sh" "$TARGET"
fi

if [ "$SKIP_FLUTTER" -eq 0 ]; then
  echo "Building Flutter macOS release ..."
  (
    cd "$REPO_ROOT"
    flutter pub get
    BACKUP_KEY_DEFINE=()
    if [ -f secrets/backup_key.json ]; then
      BACKUP_KEY_DEFINE=(--dart-define-from-file=secrets/backup_key.json)
    else
      echo "Warning: secrets/backup_key.json missing; this build uses the public development backup key" >&2
    fi
    flutter build macos --release ${BACKUP_KEY_DEFINE[@]+"${BACKUP_KEY_DEFINE[@]}"}
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
ATTACHED_DEV=""
cleanup() {
  if [ -n "$ATTACHED_DEV" ]; then
    hdiutil detach "$ATTACHED_DEV" -force >/dev/null 2>&1 || true
    ATTACHED_DEV=""
  fi
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

create_styled_dmg() {
  local stage_dir="$1"
  local vol_name="$2"
  local dmg_path="$3"
  local rw_dmg="$STAGE_ROOT/rw.dmg"

  rm -f "$rw_dmg" "$dmg_path"

  local size_mb
  size_mb="$(( $(du -sm "$stage_dir" | awk '{print $1}') + 32 ))"

  hdiutil create \
    -volname "$vol_name" \
    -srcfolder "$stage_dir" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${size_mb}m" \
    -ov \
    "$rw_dmg"

  local attach_out mount_dir disk_name
  attach_out="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg")"
  ATTACHED_DEV="$(printf '%s\n' "$attach_out" | awk '/\/Volumes\// {print $1; exit}')"
  mount_dir="$(printf '%s\n' "$attach_out" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
  disk_name="$(basename "$mount_dir")"

  if [ -z "$ATTACHED_DEV" ] || [ -z "$mount_dir" ]; then
    echo "Failed to mount temporary DMG: $rw_dmg" >&2
    exit 1
  fi

  if ! osascript - "$disk_name" "$mount_dir" <<'APPLESCRIPT'
on run argv
  set diskName to item 1 of argv
  set mountDir to item 2 of argv
  set dsStore to quoted form of (mountDir & "/.DS_Store")

  tell application "Finder"
    tell disk diskName
      open
      set theX to 200
      set theY to 120
      set theW to 660
      set theH to 400

      tell container window
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set bounds to {theX, theY, theX + theW, theY + theH}
      end tell

      set opts to the icon view options of container window
      tell opts
        set icon size to 128
        set text size to 14
        set arrangement to not arranged
      end tell

      set extension hidden of item "keqdroid.app" to true
      set position of item "keqdroid.app" to {185, 185}
      set position of item "Applications" to {475, 185}

      close
      open
      delay 1
      tell container window
        set statusbar visible to false
        set bounds to {theX, theY, theX + theW - 10, theY + theH - 10}
      end tell
      delay 1
      tell container window
        set statusbar visible to false
        set bounds to {theX, theY, theX + theW, theY + theH}
      end tell
      update without registering applications
      delay 2
      close
    end tell

    repeat 15 times
      if (do shell script "[ -s " & dsStore & " ] && echo 1 || echo 0") is "1" then exit repeat
      delay 1
    end repeat
  end tell
end run
APPLESCRIPT
  then
    echo "Warning: Finder layout styling skipped (headless or AppleScript denied)" >&2
  fi

  rm -rf "$mount_dir/.fseventsd" "$mount_dir/.Trashes" 2>/dev/null || true
  sync
  sleep 1

  hdiutil detach "$ATTACHED_DEV" >/dev/null || hdiutil detach "$ATTACHED_DEV" -force >/dev/null
  ATTACHED_DEV=""

  hdiutil convert "$rw_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$dmg_path"

  rm -f "$rw_dmg"
}

mkdir -p "$OUT_DIR"

for arch in "${ARCHS[@]}"; do
  STAGE_DIR="$STAGE_ROOT/$arch"
  mkdir -p "$STAGE_DIR"
  cp -R "$APP_SRC" "$STAGE_DIR/keqdroid.app"
  APP_DST="$STAGE_DIR/keqdroid.app"

  BIN_DST="$APP_DST/Contents/Resources/bin"
  rm -rf "$BIN_DST"

  echo "Thinning keqdroid.app to $arch ..."
  thin_bundle_to_arch "$APP_DST" "$arch"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DST"

  mkdir -p "$BIN_DST"
  CORE_SRC="$REPO_ROOT/assets/bin/macos/$arch"
  for bin in xray mihomo keqdroid-tun; do
    if [ ! -f "$CORE_SRC/$bin" ]; then
      echo "Missing $arch binary: $CORE_SRC/$bin (run tool/build_macos_cores.sh $arch)" >&2
      exit 1
    fi
    cp -f "$CORE_SRC/$bin" "$BIN_DST/$bin"
    chmod 0755 "$BIN_DST/$bin"
  done

  # Re-sign cores and rebuild keqdroid-tun if needed so embedded SHA-256 always matches signed bytes.
  codesign --force --sign "$SIGN_IDENTITY" "$BIN_DST/xray"
  codesign --force --sign "$SIGN_IDENTITY" "$BIN_DST/mihomo"
  XRAY_SHA="$(sha256_file "$BIN_DST/xray")"
  MIHOMO_SHA="$(sha256_file "$BIN_DST/mihomo")"
  if command -v go >/dev/null 2>&1; then
    goarch="$(goarch_for "$arch")"
    (
      cd "$REPO_ROOT/tool/macos_tun_daemon"
      GOTOOLCHAIN=go1.27.3 CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
        go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.xraySHA256=$XRAY_SHA -X main.mihomoSHA256=$MIHOMO_SHA" \
        -o "$BIN_DST/keqdroid-tun" \
        .
    )
    chmod 0755 "$BIN_DST/keqdroid-tun"
  fi
  codesign --force --sign "$SIGN_IDENTITY" "$BIN_DST/keqdroid-tun"

  for geo in geoip.dat geosite.dat; do
    if [ -f "$REPO_ROOT/assets/bin/macos/$geo" ]; then
      cp -f "$REPO_ROOT/assets/bin/macos/$geo" "$BIN_DST/$geo"
    fi
  done

  # Sign outer app bundle without --deep so codesign seals Resources/bin without altering core bytes.
  # После переподписи file_picker снова проверяет entitlements внешнего бандла
  codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$REPO_ROOT/macos/Runner/Release.entitlements" \
    "$APP_DST"

  if [ "$(sha256_file "$BIN_DST/xray")" != "$XRAY_SHA" ] || [ "$(sha256_file "$BIN_DST/mihomo")" != "$MIHOMO_SHA" ]; then
    echo "Core binary checksum changed after bundle signing!" >&2
    exit 1
  fi
  codesign --verify --deep --strict "$APP_DST"

  ln -s /Applications "$STAGE_DIR/Applications"
  DMG_PATH="$OUT_DIR/keqdroid-${VERSION}-macos-${arch}.dmg"

  echo "Creating $DMG_PATH ..."
  create_styled_dmg "$STAGE_DIR" "keqdroid $VERSION" "$DMG_PATH"

  echo "Done: $DMG_PATH ($(wc -c < "$DMG_PATH" | tr -d ' ') bytes)"
  rm -rf "$STAGE_DIR"
done

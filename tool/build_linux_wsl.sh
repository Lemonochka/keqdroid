#!/usr/bin/env bash
#
# Build the Linux desktop release of keqdroid inside WSL (Ubuntu/Debian).
#
# Idempotent: installs the GTK toolchain and a NATIVE Linux Flutter SDK (the
# Windows SDK on /mnt/* cannot build Linux), then `flutter build linux`.
#
# Usage (from Windows):
#   wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/build_linux_wsl.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
export PATH="$FLUTTER_HOME/bin:$PATH"   # native SDK must win over any /mnt/* one

log() { echo ""; echo "==> $*"; }

# --- 1) toolchain --------------------------------------------------------
need_pkgs=()
for c in clang cmake ninja pkg-config; do command -v "$c" >/dev/null || need_pkgs+=("$c"); done
pkg-config --exists gtk+-3.0 2>/dev/null || need_pkgs+=(gtk3)
# tray_manager links libayatana-appindicator3 at build time.
pkg-config --exists ayatana-appindicator3-0.1 2>/dev/null || need_pkgs+=(appindicator)
if [ "${#need_pkgs[@]}" -gt 0 ]; then
  log "Installing build toolchain (${need_pkgs[*]})"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libayatana-appindicator3-dev \
    curl git unzip xz-utils
else
  log "Toolchain already present"
fi

# --- 2) native Flutter SDK ----------------------------------------------
git config --global --add safe.directory '*' || true
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  log "Cloning Flutter stable into $FLUTTER_HOME"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
else
  log "Flutter SDK present at $FLUTTER_HOME"
fi

log "Flutter version"
flutter --version
flutter config --enable-linux-desktop --no-analytics >/dev/null
flutter precache --linux

# --- 3) build ------------------------------------------------------------
cd "$REPO_DIR"
log "flutter pub get (in $REPO_DIR)"
flutter pub get

log "flutter build linux --release"
# Release key for backup files (tool/new_backup_key.dart), kept out of git.
# Without the file the build writes backups that any build can open.
BACKUP_KEY_DEFINE=()
if [ -f secrets/backup_key.json ]; then
  BACKUP_KEY_DEFINE=(--dart-define-from-file=secrets/backup_key.json)
else
  log "secrets/backup_key.json missing: backups from this build use the public key"
fi
flutter build linux --release ${BACKUP_KEY_DEFINE[@]+"${BACKUP_KEY_DEFINE[@]}"}

BUNDLE="$REPO_DIR/build/linux/x64/release/bundle"

# --- 4) icon font --------------------------------------------------------
# flutter build linux never shakes the icon font: tool_backend.dart passes
# -dTreeShakeIcons="true" with the quotes, and assemble reads that as not
# "true" - 1.6 MB instead of ~26 KB. Rerun the same assemble step with the flag
# spelled right, every other define as CMake used it, and put the shaken font
# into the bundle. Windows twin: tool/shake_icon_font.ps1.
log "Tree-shaking the icon font"
CFG="$REPO_DIR/linux/flutter/ephemeral/generated_config.cmake"
tool_env() { sed -n "s/^ *\"$1=\(.*\)\"\$/\1/p" "$CFG" | head -n 1; }
flutter assemble --no-version-check --output=build \
  -dTargetPlatform=linux-x64 \
  -dTrackWidgetCreation="$(tool_env TRACK_WIDGET_CREATION)" \
  -dBuildMode=release \
  -dTargetFile="$(tool_env FLUTTER_TARGET)" \
  -dTreeShakeIcons=true \
  -dDartObfuscation="$(tool_env DART_OBFUSCATION)" \
  --DartDefines="$(tool_env DART_DEFINES)" \
  release_bundle_linux-x64_assets
FONT="data/flutter_assets/fonts/MaterialIcons-Regular.otf"
SHAKEN="$REPO_DIR/build/flutter_assets/fonts/MaterialIcons-Regular.otf"
before="$(stat -c%s "$BUNDLE/$FONT")"
after="$(stat -c%s "$SHAKEN")"
# No smaller than the bundled one means the shaker did not run again.
[ "$after" -lt "$before" ] || { echo "icon font was not shaken ($after >= $before bytes)"; exit 1; }
cp -f "$SHAKEN" "$BUNDLE/$FONT"
echo "  icon font $before -> $after bytes"

log "Build finished"
echo "bundle: $BUNDLE"
ls -la "$BUNDLE" || true
echo ""
echo "bundled cores (next to the binary, installed by linux/CMakeLists.txt):"
ls -la "$BUNDLE"/xray "$BUNDLE"/mihomo "$BUNDLE"/*.dat 2>/dev/null \
  || echo "(cores missing -- check assets/bin/linux)"
echo ""
echo "DONE. Binary: $BUNDLE/keqdroid"

#!/usr/bin/env bash
#
# Package the built Linux desktop bundle into distributable artifacts:
#   release/<ver>/keqdroid_<ver>_amd64.deb            (Debian/Ubuntu)
#   release/<ver>/keqdroid-<ver>-x86_64.AppImage      (universal incl. Arch)
#   release/<ver>/keqdroid-<ver>-linux-x64.tar.gz     (portable; AUR source)
#   release/<ver>/PKGBUILD                            (Arch / AUR)
#   release/<ver>/*.sha256                            (matches the updater)
#
# Run inside WSL/Linux AFTER tool/build_linux_wsl.sh:
#   wsl -e bash /mnt/c/.../keqdroid/tool/package_linux.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

APP=keqdroid
GH_OWNER=Lemonochka
GH_REPO=keqdroid
MAINTAINER="Lemonochka <noreply@users.noreply.github.com>"
ARCH_DEB=amd64
ARCH_AI=x86_64

log() { echo ""; echo "==> $*"; }

VERSION="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
[ -n "$VERSION" ] || { echo "could not read version"; exit 1; }
TAG="v$VERSION"
log "Packaging $APP $TAG"

BUNDLE="$REPO_DIR/build/linux/x64/release/bundle"
if [ ! -x "$BUNDLE/$APP" ]; then
  log "Bundle missing — building first"
  bash "$REPO_DIR/tool/build_linux_wsl.sh"
fi

OUT="$REPO_DIR/release/$VERSION"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
mkdir -p "$OUT"

# --- staged payload (prune Windows cores; Linux build does not use them) ----
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD"
cp -a "$BUNDLE/." "$PAYLOAD/"
rm -rf "$PAYLOAD/data/flutter_assets/assets/bin/windows"
echo "payload size: $(du -sh "$PAYLOAD" | cut -f1)"

# --- bundle the AppIndicator library chain ----------------------------------
# tray_manager links libayatana-appindicator3 as NEEDED, and Flutter leaves the
# plugin's RUNPATH pointing at a build-time path. On distros that don't ship the
# lib (Arch/CachyOS) the app fails to even start. Copy the lib + its
# ayatana/dbusmenu deps next to the plugin and repoint RUNPATHs at $ORIGIN so
# the bundle is self-contained. (gtk/glib are assumed present on any desktop;
# the .deb also declares the dep — harmless there.)
log "bundling AppIndicator libs"
command -v patchelf >/dev/null || { apt-get update -y >/dev/null && apt-get install -y patchelf >/dev/null; }
PL_LIB="$PAYLOAD/lib"
_seen=" "
_stage_lib() {
  local name="$1" src dep
  case "$_seen" in *" $name "*) return 0 ;; esac
  _seen="$_seen$name "
  # No early `exit` in awk: it closes the pipe while ldconfig is still writing,
  # ldconfig dies on SIGPIPE, and `set -o pipefail` turns that into a fatal 141
  # for the whole script. Whether it happens is a race on ldconfig's output
  # timing, so it fails only sometimes. Read all input, keep the first match.
  src="$(ldconfig -p | awk -v n="$name" '$1 == n && !found { print $NF; found = 1 }')"
  if [ -z "$src" ] || [ ! -f "$src" ]; then echo "  WARN: $name not found on host"; return 0; fi
  cp -Lu "$src" "$PL_LIB/$name"
  patchelf --set-rpath '$ORIGIN' "$PL_LIB/$name" 2>/dev/null || true
  for dep in $(ldd "$src" 2>/dev/null | awk '/=>/{print $1}'); do
    case "$dep" in *ayatana*|*dbusmenu*) _stage_lib "$dep" ;; esac
  done
}
_stage_lib libayatana-appindicator3.so.1
# the tray plugin's RUNPATH is a stale build-time path -> point it at its own dir
if [ -f "$PL_LIB/libtray_manager_plugin.so" ]; then
  patchelf --set-rpath '$ORIGIN' "$PL_LIB/libtray_manager_plugin.so" 2>/dev/null || true
fi
echo "  bundled: $(ls "$PL_LIB" 2>/dev/null | grep -E 'ayatana|dbusmenu' | tr '\n' ' ')"

# --- icon -------------------------------------------------------------------
ICON_SRC="$REPO_DIR/assets/icon.png"
[ -f "$ICON_SRC" ] || ICON_SRC=""

write_desktop() { # $1 = exec name, $2 = dest file
  cat > "$2" <<EOF
[Desktop Entry]
Type=Application
Name=KeqDroid
Comment=KEQDIS proxy/VPN client
Exec=$1
Icon=$APP
Categories=Network;
Terminal=false
StartupWMClass=$APP
EOF
}

# ============================================================================
# 1) tar.gz (portable bundle)
# ============================================================================
log "tar.gz"
TARROOT="$WORK/$APP"
mkdir -p "$TARROOT"
cp -a "$PAYLOAD/." "$TARROOT/"
TARBALL="$OUT/$APP-$VERSION-linux-x64.tar.gz"
( cd "$WORK" && tar czf "$TARBALL" "$APP" )
echo "  -> $(basename "$TARBALL")"

# ============================================================================
# 2) .deb
# ============================================================================
log ".deb"
DEBROOT="$WORK/deb"
mkdir -p "$DEBROOT/DEBIAN" "$DEBROOT/opt/$APP" \
         "$DEBROOT/usr/bin" \
         "$DEBROOT/usr/share/applications" \
         "$DEBROOT/usr/share/icons/hicolor/256x256/apps"
cp -a "$PAYLOAD/." "$DEBROOT/opt/$APP/"
ln -s "/opt/$APP/$APP" "$DEBROOT/usr/bin/$APP"
write_desktop "$APP" "$DEBROOT/usr/share/applications/$APP.desktop"
[ -n "$ICON_SRC" ] && cp "$ICON_SRC" "$DEBROOT/usr/share/icons/hicolor/256x256/apps/$APP.png"

INSTALLED_KB="$(du -sk "$DEBROOT" | cut -f1)"
cat > "$DEBROOT/DEBIAN/control" <<EOF
Package: $APP
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH_DEB
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, zlib1g, libayatana-appindicator3-1
Recommends: polkit-1 | policykit-1, gnome-shell-extension-appindicator
Description: KEQDIS proxy/VPN client
 Xray / sing-box / AmneziaWG client with proxy and TUN modes.
 TUN mode requests root via pkexec (polkit) at connect time.
EOF
DEB="$OUT/${APP}_${VERSION}_${ARCH_DEB}.deb"
dpkg-deb --root-owner-group --build "$DEBROOT" "$DEB" >/dev/null
echo "  -> $(basename "$DEB")"

# ============================================================================
# 3) AppImage
# ============================================================================
log "AppImage"
command -v mksquashfs >/dev/null || { apt-get update -y >/dev/null && apt-get install -y squashfs-tools >/dev/null; }

APPIMAGETOOL="$WORK/appimagetool.AppImage"
curl -sSL --retry 5 --retry-all-errors -o "$APPIMAGETOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x "$APPIMAGETOOL"

APPDIR="$WORK/$APP.AppDir"
mkdir -p "$APPDIR/usr/lib/$APP"
cp -a "$PAYLOAD/." "$APPDIR/usr/lib/$APP/"
write_desktop "$APP" "$APPDIR/$APP.desktop"
if [ -n "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APPDIR/$APP.png"
else
  # appimagetool insists on an icon; drop a 1x1 placeholder.
  printf '' > "$APPDIR/$APP.png"
fi
cat > "$APPDIR/AppRun" <<EOF
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\$HERE/usr/lib/$APP/$APP" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

APPIMAGE="$OUT/$APP-$VERSION-$ARCH_AI.AppImage"
# Pre-fetch the type2 runtime ourselves: appimagetool's built-in downloader
# does not follow GitHub's 302 redirect and fails intermittently.
RUNTIME="$WORK/runtime-$ARCH_AI"
curl -sSL --retry 5 --retry-all-errors -o "$RUNTIME" \
  "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-$ARCH_AI"
# WSL has no FUSE -> extract-and-run; ARCH required by appimagetool.
ARCH=$ARCH_AI APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" \
  --no-appstream --runtime-file "$RUNTIME" "$APPDIR" "$APPIMAGE"
echo "  -> $(basename "$APPIMAGE")"

# ============================================================================
# 4) PKGBUILD (Arch / AUR) — builds from the release tar.gz
# ============================================================================
log "PKGBUILD"
TAR_SHA="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
cat > "$OUT/PKGBUILD" <<EOF
# Maintainer: $MAINTAINER
pkgname=$APP-bin
pkgver=$VERSION
pkgrel=1
pkgdesc="KEQDIS proxy/VPN client (Xray/sing-box/AmneziaWG, proxy + TUN)"
arch=('x86_64')
url="https://github.com/$GH_OWNER/$GH_REPO"
license=('custom')
depends=('gtk3' 'glibc' 'libayatana-appindicator')
optdepends=('polkit: TUN mode (root via pkexec)'
            'gnome-shell-extension-appindicator: tray icon on GNOME')
provides=('$APP')
conflicts=('$APP')
source=("\$pkgname-\$pkgver.tar.gz::https://github.com/$GH_OWNER/$GH_REPO/releases/download/v\$pkgver/$APP-\$pkgver-linux-x64.tar.gz")
sha256sums=('$TAR_SHA')

package() {
  install -dm755 "\$pkgdir/opt/$APP"
  cp -a "\$srcdir/$APP/." "\$pkgdir/opt/$APP/"
  install -dm755 "\$pkgdir/usr/bin"
  ln -s "/opt/$APP/$APP" "\$pkgdir/usr/bin/$APP"
  install -Dm644 /dev/stdin "\$pkgdir/usr/share/applications/$APP.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=KeqDroid
Comment=KEQDIS proxy/VPN client
Exec=$APP
Icon=$APP
Categories=Network;
Terminal=false
StartupWMClass=$APP
DESKTOP
}
EOF
echo "  -> PKGBUILD (tar sha256 $TAR_SHA)"

# ============================================================================
# 5) sha256 sidecars (ASCII, no BOM) for deb / AppImage / tar.gz
# ============================================================================
log "sha256 sidecars"
for f in "$DEB" "$APPIMAGE" "$TARBALL"; do
  sha256sum "$f" | cut -d' ' -f1 | tr -d '\n' > "$f.sha256"
  echo "  $(basename "$f").sha256 = $(cat "$f.sha256")"
done

log "Done. Artifacts in $OUT"
ls -la "$OUT"

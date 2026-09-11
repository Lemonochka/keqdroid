#!/usr/bin/env bash
#
# Push release/<ver>/aur/{PKGBUILD,.SRCINFO} to the AUR package keqdroid-bin.
#
# The PKGBUILD downloads the release tar.gz from GitHub, so publish the GitHub
# release first, then run this.
#
# Once per machine: an AUR account (https://aur.archlinux.org/register) with
# this machine's SSH public key added under "My Account". The first push
# creates the package, every later one updates it.
#
#   wsl -e bash /mnt/c/.../keqdroid/tool/publish_aur.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(grep -E '^version:' "$REPO_DIR/pubspec.yaml" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
SRC="$REPO_DIR/release/$VERSION/aur"
for f in PKGBUILD .SRCINFO; do
  [ -f "$SRC/$f" ] || { echo "missing $SRC/$f - run tool/make_release.ps1 first"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

git clone ssh://aur@aur.archlinux.org/keqdroid-bin.git "$WORK/aur"
cp "$SRC/PKGBUILD" "$SRC/.SRCINFO" "$WORK/aur/"
cd "$WORK/aur"
git add PKGBUILD .SRCINFO
if git diff --cached --quiet; then
  echo "AUR already has keqdroid-bin $VERSION"
  exit 0
fi
git -c user.name="${AUR_NAME:-Lemonochka}" \
    -c user.email="${AUR_EMAIL:-noreply@users.noreply.github.com}" \
    commit -q -m "Update to $VERSION"
git push origin HEAD:master
echo "keqdroid-bin $VERSION is on AUR"

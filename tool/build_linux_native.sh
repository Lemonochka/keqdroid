#!/usr/bin/env bash
#
# Build + package the Linux desktop app on the WSL NATIVE filesystem (lots of
# free space) instead of /mnt/c, then copy only the release artifacts back to
# the Windows project. Use when the C: drive is low on space.
#
#   wsl -e bash /mnt/c/Users/<you>/StudioProjects/keqdroid/tool/build_linux_native.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # /mnt/c/.../keqdroid
DST="$HOME/keqdroid_src"
export PATH="$HOME/flutter/bin:$PATH"

echo "==> Syncing project to native fs: $DST"
command -v rsync >/dev/null || { apt-get update -y && apt-get install -y rsync; }
mkdir -p "$DST"
rsync -a --delete \
  --exclude 'build/' --exclude '.dart_tool/' --exclude '.git/' \
  --exclude 'release/' --exclude '*.log' \
  "$SRC/" "$DST/"

cd "$DST"
# rsync бережёт исключённый build/ от --delete, и сборка шла поверх прошлой:
# устаревшие файлы из неё уезжали в пакеты, раздувая их. Релиз — с чистого.
echo "==> Removing the previous build in $DST"
rm -rf "$DST/build"

echo "==> Building + packaging in $DST"
bash tool/build_linux_wsl.sh
bash tool/package_linux.sh

VER="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
echo "==> Copying artifacts back to C: (release/$VER)"
mkdir -p "$SRC/release/$VER"
# С точкой, а не звёздочкой: иначе не доедут подкаталог aur/ и его .SRCINFO.
cp -rf "$DST/release/$VER/." "$SRC/release/$VER/"

echo "==> Done. Artifacts on C::"
ls -la "$SRC/release/$VER"

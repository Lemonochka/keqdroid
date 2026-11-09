#!/usr/bin/env bash
#
# Sign a release SHA256SUMS with the update signing key (Ed25519):
#
#   bash tool/sign_sums.sh release/<ver>/SHA256SUMS path/to/key.pem
#
# Writes SHA256SUMS.sig next to it: base64 of the raw 64-byte signature over
# the file exactly as published. The app (lib/services/release_signature.dart)
# refuses an update or geo base whose SHA256SUMS does not verify against one
# of its public keys. The signature is checked here against the public key
# the app knows before the script returns, so a key that is not in the app
# fails the release instead of every user's update.
#
# The key may also come in UPDATE_SIGNING_KEY (PEM text) with "-" as the path.
set -euo pipefail

SUMS="${1:?usage: sign_sums.sh SHA256SUMS key.pem|-}"
KEY="${2:?usage: sign_sums.sh SHA256SUMS key.pem|-}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$KEY" = "-" ]; then
  [ -n "${UPDATE_SIGNING_KEY:-}" ] || { echo "UPDATE_SIGNING_KEY is empty"; exit 1; }
  printf '%s\n' "$UPDATE_SIGNING_KEY" > "$WORK/key.pem"
  KEY="$WORK/key.pem"
fi

openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$SUMS" -out "$WORK/sig.bin"
[ "$(wc -c < "$WORK/sig.bin")" -eq 64 ] || { echo "not an Ed25519 signature"; exit 1; }
base64 -w0 "$WORK/sig.bin" > "$SUMS.sig"
printf '\n' >> "$SUMS.sig"

PUB="$(openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64 -w0)"
if ! grep -qF "'$PUB'" "$REPO_DIR/lib/services/release_signature.dart"; then
  echo "the key is not one of the public keys in lib/services/release_signature.dart"
  rm -f "$SUMS.sig"
  exit 1
fi
openssl pkey -in "$KEY" -pubout -out "$WORK/pub.pem"
openssl pkeyutl -verify -pubin -inkey "$WORK/pub.pem" -rawin -in "$SUMS" -sigfile "$WORK/sig.bin" >/dev/null
echo "signed $(basename "$SUMS") with key $PUB"

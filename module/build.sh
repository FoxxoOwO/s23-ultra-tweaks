#!/usr/bin/env bash
# Builds the KernelSU module zip: out/s23-ultra-tweaks-<version>.zip (macOS or Linux).
#   module/build.sh [--payload airdrop-payload-*.tar.gz]
# Without --payload it downloads the payload from the GitHub release, like install.sh. Either way the
# payload must match the SHA-256 pinned in install.sh. The version comes from module/module.prop.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd); M=$ROOT/module
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
if command -v sha256sum >/dev/null; then sha() { sha256sum "$1" | cut -d' ' -f1; }; else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi

payload=""
while [ $# -gt 0 ]; do
  case "$1" in
    --payload) [ $# -ge 2 ] || die "--payload needs a file"; payload=$2; shift 2 ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
command -v zip >/dev/null || die "zip not found"

# install.sh is the single source for the payload's name, release and checksum
var() { sed -n "s/^$1=\\([^ #]*\\).*/\\1/p" "$ROOT/install.sh" | head -n 1; }
REPO=$(var REPO); REL=$(var VERSION); PAYLOAD=$(var PAYLOAD); PAYLOAD_SHA256=$(var PAYLOAD_SHA256)
[ -n "$REPO" ] && [ -n "$REL" ] && [ -n "$PAYLOAD" ] && [ ${#PAYLOAD_SHA256} = 64 ] || die "could not read REPO/VERSION/PAYLOAD/PAYLOAD_SHA256 from install.sh"
VER=$(sed -n 's/^version=//p' "$M/module.prop" | head -n 1)
[ -n "$VER" ] || die "no version= in module/module.prop"
[ -f "$M/webroot/index.html" ] || die "module/webroot/index.html is missing (the module's settings page)"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
if [ -z "$payload" ]; then
  echo "Downloading $PAYLOAD ($REL)..."
  curl -fSL --progress-bar "https://github.com/$REPO/releases/download/$REL/$PAYLOAD" -o "$W/payload.tar.gz"
  payload=$W/payload.tar.gz
fi
[ -f "$payload" ] || die "payload not found: $payload"
[ "$(sha "$payload")" = "$PAYLOAD_SHA256" ] || die "payload checksum mismatch ($payload is not the one pinned in install.sh)"

# stage the module folder
S=$W/stage; mkdir -p "$S/airdrop"
for f in module.prop customize.sh service.sh action.sh uninstall.sh skip_mount; do
  [ -f "$M/$f" ] || die "module/$f missing"; cp "$M/$f" "$S/"
done
cp -R "$M/webroot" "$S/webroot"
cp "$ROOT/device/tweaks.sh" "$S/"
cp -R "$ROOT/device/files" "$S/files"
tar -xzf "$payload" -C "$S/airdrop"
for f in kiwi_v2.ko wonder.ko mhifix.ko bwfix.ko moseyrun sqlite3 pbflag fw mosey wifi7; do
  [ -e "$S/airdrop/$f" ] || die "payload has no $f"
done

# clean: no macOS metadata; modes as customize.sh sets them on the phone
find "$S" \( -name '._*' -o -name .DS_Store -o -name __MACOSX \) -prune -exec rm -rf {} +
find "$S" -type d -exec chmod 755 {} +
find "$S" -type f -exec chmod 644 {} +
for f in customize.sh service.sh action.sh uninstall.sh tweaks.sh airdrop/moseyrun airdrop/sqlite3 airdrop/pbflag; do
  chmod 755 "$S/$f"
done

mkdir -p "$ROOT/out"; Z=$ROOT/out/s23-ultra-tweaks-$VER.zip; rm -f "$Z"
# sorted names and fixed times, so the same inputs give the same zip
(cd "$S" && find . -exec touch -h -t 202601010000 {} + && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort |
  COPYFILE_DISABLE=1 zip -q -X -9 -@ "$Z")

size=$(wc -c < "$Z" | tr -d ' ')
echo "Built $Z"
echo "  size:    $size bytes ($(( (size + 524288) / 1048576 )) MB)"
echo "  sha256:  $(sha "$Z")"

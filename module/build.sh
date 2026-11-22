#!/usr/bin/env bash
# Builds the KernelSU module zip: out/s23-ultra-tweaks-<version>.zip (macOS or Linux).
#   module/build.sh
# The zip holds only scripts and the module page. Each tweak's files (the AirDrop driver, the S24 apps,
# Language Core) are downloaded by the phone from the GitHub release when that tweak is picked; their
# names and SHA-256s are pinned in device/tweaks.sh (PAYLOADS). The version comes from module/module.prop.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd); M=$ROOT/module
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
if command -v sha256sum >/dev/null; then sha() { sha256sum "$1" | cut -d' ' -f1; }; else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi
case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown argument: $1 (see --help)" ;;
esac
command -v zip >/dev/null || die "zip not found"

VER=$(sed -n 's/^version=//p' "$M/module.prop" | head -n 1)
[ -n "$VER" ] || die "no version= in module/module.prop"
[ -f "$M/webroot/index.html" ] || die "module/webroot/index.html is missing (the module's settings page)"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# stage the module folder
S=$W/stage; mkdir -p "$S"
for f in module.prop customize.sh service.sh action.sh uninstall.sh skip_mount; do
  [ -f "$M/$f" ] || die "module/$f missing"; cp "$M/$f" "$S/"
done
cp -R "$M/webroot" "$S/webroot"
cp "$ROOT/device/tweaks.sh" "$S/"
cp -R "$ROOT/device/files" "$S/files"

# clean: no macOS metadata; modes as customize.sh sets them on the phone
find "$S" \( -name '._*' -o -name .DS_Store -o -name __MACOSX \) -prune -exec rm -rf {} +
find "$S" -type d -exec chmod 755 {} +
find "$S" -type f -exec chmod 644 {} +
for f in customize.sh service.sh action.sh uninstall.sh tweaks.sh; do chmod 755 "$S/$f"; done

mkdir -p "$ROOT/out"; Z=$ROOT/out/s23-ultra-tweaks-$VER.zip; rm -f "$Z"
# sorted names and fixed times, so the same inputs give the same zip
(cd "$S" && find . -exec touch -h -t 202601010000 {} + && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort |
  COPYFILE_DISABLE=1 zip -q -X -9 -@ "$Z")

size=$(wc -c < "$Z" | tr -d ' ')
echo "Built $Z"
echo "  size:    $size bytes ($(( (size + 1023) / 1024 )) KB)"
echo "  sha256:  $(sha "$Z")"

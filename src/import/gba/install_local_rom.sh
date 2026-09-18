#!/usr/bin/env bash
# Install a FireRed/LeafGreen dump into baseroms/ without the launcher file picker.
# Usage:
#   ./sevii/gba/install_local_rom.sh [/path/to/rom.gba]
# Default: first *.gba in the mod root (gitignored).

set -euo pipefail

MOD_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASEROMS="$MOD_ROOT/baseroms"
SRC="${1:-}"

if [[ -z "$SRC" ]]; then
  # Prefer an existing firered-like name, else any .gba in mod root.
  for cand in \
    "$MOD_ROOT/firered.gba" \
    "$MOD_ROOT/leafgreen.gba" \
    "$MOD_ROOT/"*.gba
  do
    if [[ -f "$cand" ]]; then
      SRC="$cand"
      break
    fi
  done
fi

if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "Usage: $0 /path/to/firered.gba" >&2
  echo "No .gba found under $MOD_ROOT" >&2
  exit 1
fi

SIZE="$(wc -c < "$SRC" | tr -d ' ')"
if [[ "$SIZE" != "16777216" ]]; then
  echo "Refusing: expected 16777216 bytes, got $SIZE ($SRC)" >&2
  exit 1
fi

MD5="$(md5sum "$SRC" | awk '{print $1}')"
DEST_NAME="firered.gba"
case "$MD5" in
  612ca9473451fa42b51d1711031ed5f6|9d33a02159e018d09073e700e1fd10fd)
    DEST_NAME="leafgreen.gba"
    ;;
esac

mkdir -p "$BASEROMS"
cp -f "$SRC" "$BASEROMS/$DEST_NAME"

# Receipt is optional: the engine re-hashes on first mod.imports:info if missing.
# Writing one avoids a 16 MiB hash at boot when modtime matches.
MODTIME="$(stat -c %Y "$BASEROMS/$DEST_NAME" 2>/dev/null || stat -f %m "$BASEROMS/$DEST_NAME")"
IMPORT_ID="firered"
[[ "$DEST_NAME" == "leafgreen.gba" ]] && IMPORT_ID="leafgreen"
RECEIPT="$BASEROMS/.required-import-${IMPORT_ID}.validated"
printf 'v1\n%s\n%d\n%s\n' "$MD5" "$SIZE" "$MODTIME" > "$RECEIPT"
# Remove any prior "removed" marker
rm -f "$BASEROMS/.required-import-${IMPORT_ID}.removed"

echo "Installed $SRC"
echo "  → $BASEROMS/$DEST_NAME"
echo "  MD5 $MD5"
echo "  receipt $RECEIPT"
echo "Reload the mod / enable Sevii; no file picker needed."

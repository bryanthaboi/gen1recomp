#!/usr/bin/env bash
# Pack a Switch SD-ready zip: extract at microSD root (merge-safe update).
#
# Usage:
#   scripts/switch/pack_sd_zip.sh NRO_PATH VERSION OUT_ZIP
#
# Layout inside the zip (SD root):
#   switch/gen1recomp/gen1recomp.nro
#   switch/gen1recomp/INSTALL.txt
#   switch/gen1recomp/pokemon-love2d/imports/.../README.txt
#   switch/gen1recomp/pokemon-love2d/exports/.../README.txt
#
# Does not ship ROMs, saves, or mods. Re-extracting merges over an existing
# install and only overwrites the NRO + these text placeholders — keep
# pokemon-love2d/ to preserve progress.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

NRO_PATH="${1:-}"
VERSION="${2:-}"
OUT_ZIP="${3:-}"

[ -n "$NRO_PATH" ] && [ -n "$VERSION" ] && [ -n "$OUT_ZIP" ] \
  || fail "usage: scripts/switch/pack_sd_zip.sh NRO_PATH VERSION OUT_ZIP"

[ -f "$NRO_PATH" ] || fail "missing NRO at $NRO_PATH"

command -v zip >/dev/null 2>&1 || fail "need zip on PATH"

# Absolutize before any cd — relative OUT_ZIP would otherwise land inside the
# staging dir and vanish when the EXIT trap cleans up.
NRO_PATH="$(cd "$(dirname "$NRO_PATH")" && pwd)/$(basename "$NRO_PATH")"
OUT_DIR="$(dirname "$OUT_ZIP")"
mkdir -p "$OUT_DIR"
OUT_ZIP="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT_ZIP")"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-sd-zip.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

APP_DIR="$STAGE/switch/gen1recomp"
SAVE_ROOT="$APP_DIR/pokemon-love2d"
mkdir -p "$APP_DIR"
cp "$NRO_PATH" "$APP_DIR/gen1recomp.nro"

cat > "$APP_DIR/INSTALL.txt" <<EOF
gen1recomp Switch (v${VERSION})
===============================

First install or update (same steps):
  1. Extract this zip at the root of your microSD (merge folders if asked).
  2. Do NOT delete switch/gen1recomp/pokemon-love2d/ — that folder holds
     your saves, imported ROMs, mods, and options. Re-extracting only
     replaces gen1recomp.nro and these help files.
  3. Launch with title override (hold R on HOME, open any title → hbmenu).
  4. Copy a legal Pokemon Red/Blue .gb into:
       switch/gen1recomp/pokemon-love2d/imports/
     then use Scan again in the launcher if needed.

Inboxes (drop files here via MTP / SD / FTP):
  imports/                 — ROM .gb / .gbc
  imports/mods/            — community mod .zip
  imports/saves/red|blue|yellow/  — raw .sav import
  exports/red|blue|yellow/        — pull after Export save

Full guide: https://github.com/bryanthaboi/gen1recomp/blob/main/docs/switch-install.md
EOF

write_readme() {
  local path="$1"
  local body="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$body" > "$path"
}

write_readme "$SAVE_ROOT/imports/README.txt" \
  "Put a legal Pokemon Red or Blue .gb / .gbc here, then Scan again in the launcher."
write_readme "$SAVE_ROOT/imports/mods/README.txt" \
  "Put community mod .zip files here, then MODS → Scan again."
write_readme "$SAVE_ROOT/imports/saves/red/README.txt" \
  "Put a Red .sav (32 KB) here, then Red tab → SAVE FILES → Import save."
write_readme "$SAVE_ROOT/imports/saves/blue/README.txt" \
  "Put a Blue .sav (32 KB) here, then Blue tab → SAVE FILES → Import save."
write_readme "$SAVE_ROOT/imports/saves/yellow/README.txt" \
  "Put a Yellow .sav (32 KB) here, then Yellow tab → SAVE FILES → Import save."
write_readme "$SAVE_ROOT/exports/red/README.txt" \
  "After Export save (Red), copy the .sav out of this folder via MTP / SD / FTP."
write_readme "$SAVE_ROOT/exports/blue/README.txt" \
  "After Export save (Blue), copy the .sav out of this folder via MTP / SD / FTP."
write_readme "$SAVE_ROOT/exports/yellow/README.txt" \
  "After Export save (Yellow), copy the .sav out of this folder via MTP / SD / FTP."

rm -f "$OUT_ZIP"
(
  cd "$STAGE"
  zip -q -r "$OUT_ZIP" switch
)

[ -f "$OUT_ZIP" ] || fail "zip was not created at $OUT_ZIP"
[ -s "$OUT_ZIP" ] || fail "zip is empty: $OUT_ZIP"

LISTING="$(unzip -Z1 "$OUT_ZIP" 2>/dev/null || unzip -l "$OUT_ZIP")"
printf '%s\n' "$LISTING" | grep -q 'switch/gen1recomp/gen1recomp.nro' \
  || fail "zip missing switch/gen1recomp/gen1recomp.nro"

REQUIRED=(
  "switch/gen1recomp/INSTALL.txt"
  "switch/gen1recomp/pokemon-love2d/imports/README.txt"
  "switch/gen1recomp/pokemon-love2d/imports/mods/README.txt"
  "switch/gen1recomp/pokemon-love2d/imports/saves/red/README.txt"
  "switch/gen1recomp/pokemon-love2d/imports/saves/blue/README.txt"
  "switch/gen1recomp/pokemon-love2d/imports/saves/yellow/README.txt"
  "switch/gen1recomp/pokemon-love2d/exports/red/README.txt"
  "switch/gen1recomp/pokemon-love2d/exports/blue/README.txt"
  "switch/gen1recomp/pokemon-love2d/exports/yellow/README.txt"
)
for rel in "${REQUIRED[@]}"; do
  printf '%s\n' "$LISTING" | grep -Fq "$rel" || fail "zip missing $rel"
done

ZIP_SHA="$(sha256_file "$OUT_ZIP")"
printf '%s  %s\n' "$ZIP_SHA" "$OUT_ZIP" > "${OUT_ZIP}.sha256"
say "SD-ready zip: $OUT_ZIP"
printf '%s  %s\n' "$ZIP_SHA" "$OUT_ZIP"

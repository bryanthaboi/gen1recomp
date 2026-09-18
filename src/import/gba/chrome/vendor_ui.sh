#!/usr/bin/env bash
# Vendor pret pokefirered menu graphics into sevii/gba/chrome/menus/.
# Usage: ./vendor_ui.sh /path/to/pokefirered
# Local-dev only — do not ship Nintendo pixels in release zips.

set -euo pipefail

PRET="${1:-}"
if [[ -z "$PRET" || ! -d "$PRET/graphics" ]]; then
  echo "usage: $0 /path/to/pokefirered" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/menus"
mkdir -p "$OUT"/{bag,party,pokedex,options,save,trainer_card,pc,region_map}

copy_if() {
  local src="$1" dest="$2"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dest"
    echo "ok  $dest"
  else
    echo "skip missing $src" >&2
  fi
}

# Item / bag menu
copy_if "$PRET/graphics/item_menu/bag.png"            "$OUT/bag/bag.png"
copy_if "$PRET/graphics/item_menu/bag_male.png"       "$OUT/bag/bag_male.png"
copy_if "$PRET/graphics/item_menu/bag_female.png"     "$OUT/bag/bag_female.png"

# Party (pret graphics/party_menu — status balls = pokeball sheet)
copy_if "$PRET/graphics/party_menu/bg.png"            "$OUT/party/bg.png"
copy_if "$PRET/graphics/party_menu/pokeball.png"      "$OUT/party/status_balls.png"
copy_if "$PRET/graphics/party_menu/pokeball.png"      "$OUT/party/pokeball.png"
copy_if "$PRET/graphics/interface/status_icons.png"   "$OUT/party/status_icons.png"

# Pokédex
copy_if "$PRET/graphics/pokedex/bg.png"               "$OUT/pokedex/bg.png"
copy_if "$PRET/graphics/pokedex/list_bg.png"          "$OUT/pokedex/list_bg.png"

# Option / save / trainer card / PC (paths vary by pret revision)
copy_if "$PRET/graphics/misc/option_menu_buttons.png" "$OUT/options/buttons.png"
copy_if "$PRET/graphics/trainer_card/bg.png"          "$OUT/trainer_card/bg.png"
copy_if "$PRET/graphics/pokemon_storage/bg.png"       "$OUT/pc/bg.png"

# Text window already vendored beside this script; ensure present
copy_if "$PRET/graphics/text_window/menu_message.png" "$ROOT/menu_message.png"
copy_if "$PRET/graphics/text_window/std.png"          "$ROOT/std.png"
copy_if "$PRET/graphics/text_window/signpost.png"     "$ROOT/signpost.png"
copy_if "$PRET/graphics/fonts/latin_normal.png"       "$ROOT/fonts/latin_normal.png"
copy_if "$PRET/graphics/fonts/latin_small.png"        "$ROOT/fonts/latin_small.png"
copy_if "$PRET/graphics/fonts/down_arrows.png"        "$ROOT/fonts/down_arrows.png"

# Party slot tilemaps (baked into extract RGBA by party_chrome_extract)
copy_if "$PRET/graphics/party_menu/slot_main.bin"       "$OUT/party/slot_main.bin"
copy_if "$PRET/graphics/party_menu/slot_wide.bin"       "$OUT/party/slot_wide.bin"
copy_if "$PRET/graphics/party_menu/slot_wide_empty.bin" "$OUT/party/slot_wide_empty.bin"

echo "done — bake RGBA with your palette tool if needed"
echo "menus under $OUT"

#!/usr/bin/env bash
# Assemble loose-mode Switch dist: gen1recomp.nro + game.love side by side.
#
# Usage:
#   scripts/switch/assemble_loose.sh [path/to/game.love]
#
# Defaults game.love to .bazinga/work/game.love. Copies pinned love.nro from
# .bazinga/love-nx/11.5-nx1/love.nro → dist/switch/loose/gen1recomp.nro.
# Prints SHA-256 for both outputs. Exits non-zero if love.nro is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

LOVE_NRO="$ROOT/.bazinga/love-nx/11.5-nx1/love.nro"
GAME_LOVE="${1:-$ROOT/.bazinga/work/game.love}"
OUT_DIR="$ROOT/dist/switch/loose"
OUT_NRO="$OUT_DIR/gen1recomp.nro"
OUT_LOVE="$OUT_DIR/game.love"

if [ ! -f "$LOVE_NRO" ]; then
  fail_need_fetch "missing pinned love.nro at $LOVE_NRO"
fi

if [ ! -f "$GAME_LOVE" ]; then
  fail "missing game.love at $GAME_LOVE (build with scripts/build.sh first)"
fi

mkdir -p "$OUT_DIR"
cp "$LOVE_NRO" "$OUT_NRO"
cp "$GAME_LOVE" "$OUT_LOVE"

echo "assembled loose Switch dist:"
echo "  $OUT_NRO"
echo "  $OUT_LOVE"
echo ""
printf '%s  %s\n' "$(sha256_file "$OUT_NRO")" "$OUT_NRO"
printf '%s  %s\n' "$(sha256_file "$OUT_LOVE")" "$OUT_LOVE"

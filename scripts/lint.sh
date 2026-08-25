#!/usr/bin/env bash
# Static analysis for the engine Lua (config: .luacheckrc).
#
# Complements scripts/test.sh: the tests prove behavior, luacheck catches the
# defects that never run in a green test -- undefined globals/locals (the
# class that hid a music.volume crash: a hook read a `state` that was still
# the nil global), unused values, unreachable code. The .luacheckrc mutes the
# cosmetic categories the codebase lives with, so what prints is worth a look.
#
#   scripts/lint.sh            full advisory report over every shipped tree
#   scripts/lint.sh --gate     only the codes CI blocks on (0xx, 1xx, 511)
#   scripts/lint.sh src tools  lint specific paths
#
# Install once with:  luarocks install luacheck

set -uo pipefail
cd "$(dirname "$0")/.."

DEFAULT_PATHS=(main.lua conf.lua src data/scripts mods tools)

GATE=0
if [ "${1:-}" = "--gate" ]; then
  GATE=1
  shift
fi

if ! command -v luacheck >/dev/null 2>&1; then
  echo "luacheck not found on PATH (install: luarocks install luacheck)" >&2
  exit 2
fi

if [ "$#" -gt 0 ]; then
  PATHS=("$@")
else
  PATHS=("${DEFAULT_PATHS[@]}")
fi

if [ "$GATE" = "1" ]; then
  exec luacheck "${PATHS[@]}" -q --codes --only 0 1 511
fi

luacheck "${PATHS[@]}"

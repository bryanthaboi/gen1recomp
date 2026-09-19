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
#
# luacheck 1.2.0 (the newest release) predates Lua 5.5, which made generic-for
# control variables read-only. Under Lua 5.5 it dies while loading
# luacheck.standards, before it lints a single file, so it has to run under
# Lua <= 5.4. The version probe below turns that into a readable message
# instead of a raw Lua traceback.

set -uo pipefail
cd "$(dirname "$0")/.."

DEFAULT_PATHS=(main.lua conf.lua src data/scripts mods tools)

GATE=0
if [ "${1:-}" = "--gate" ]; then
  GATE=1
  shift
fi

export PATH="$(pwd)/node_modules/.bin:${HOME:-}/.luarocks/bin:$PATH"

if ! command -v luacheck >/dev/null 2>&1; then
  echo "luacheck not found on PATH (install: luarocks install luacheck)" >&2
  exit 2
fi

# luacheck 1.2.0 predates Lua 5.5, where generic-for control variables became
# read-only. Under Lua 5.5 it fails at module load, so the gate can never pass.
# Diagnose that here rather than leaking the loader's traceback.
LUACHECK_INSTALL_HINT="luarocks --lua-version=5.4 --tree /opt/homebrew install luacheck"

if ! LUACHECK_VERSION="$(luacheck --version 2>&1)"; then
  echo "luacheck is on PATH but cannot run:" >&2
  printf '%s\n' "$LUACHECK_VERSION" | sed 's/^/  /' >&2
  echo >&2
  echo "luacheck 1.2.0 is incompatible with Lua 5.5 (generic-for control" >&2
  echo "variables became read-only there). Install it against Lua 5.4:" >&2
  echo "  $LUACHECK_INSTALL_HINT" >&2
  echo "(adjust --tree to match your LuaRocks setup)" >&2
  exit 2
fi

case "$LUACHECK_VERSION" in
  *"Lua 5.5"*)
    echo "warning: luacheck is running under Lua 5.5, which luacheck 1.2.0" >&2
    echo "         predates; treat its results with suspicion. Prefer a 5.4 build:" >&2
    echo "  $LUACHECK_INSTALL_HINT" >&2
    ;;
esac

if [ "$#" -gt 0 ]; then
  PATHS=("$@")
else
  PATHS=("${DEFAULT_PATHS[@]}")
fi

if [ "$GATE" = "1" ]; then
  exec luacheck "${PATHS[@]}" -q --codes --only 0 1 511
fi

luacheck "${PATHS[@]}"

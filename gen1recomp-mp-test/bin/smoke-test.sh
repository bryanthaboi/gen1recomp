#!/usr/bin/env bash
# Run the repository's own end-to-end acceptance test against this relay.
#
# tests/drivers/online_relay_smoke.lua is the authority on what "working"
# means: it spawns server.js itself, connects two real clients, has them
# create and join a room, refuses a spectator whose profile differs, starts
# the match, plays a full Gen 1 battle over the relay's room session, reports
# from both sides, and checks the winner the relay announces.
#
#   ./bin/smoke-test.sh
#
# Exit code 0 means every check passed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SERVER_DIR="$HERE/server"
PORT="${POKEPORT_LINK_PORT:-17780}"

if [ ! -f "$SERVER_DIR/server.js" ]; then
  echo "missing $SERVER_DIR/server.js" >&2
  exit 1
fi

# The driver backgrounds the relay as a grandchild of its own subshell, so its
# `kill $(cat pidfile)` can miss.  A leftover relay on this port would serve
# the NEXT run and quietly make a broken server look healthy, so clear it.
leftover="$(lsof -ti "tcp:$PORT" 2>/dev/null || true)"
if [ -n "$leftover" ]; then
  echo "clearing a leftover relay on port $PORT (pid $leftover)"
  # shellcheck disable=SC2086
  kill $leftover 2>/dev/null || true
  sleep 1
fi

# The driver only ever runs after main.lua boots a real game, which needs an
# imported ROM cache.  LOVE keeps one per identity under the save directory.
#
# Run in a scratch identity of our own rather than a real one: LOVE writes
# settings and a save into whichever identity is active, and a test has no
# business touching the folder someone actually plays from.  Seed the scratch
# identity from the first donor that already has a red cache -- the default
# game identity first, since that is the one a player is most likely to have
# populated.
LOVE_SAVE="$HOME/Library/Application Support/LOVE"
SMOKE_IDENTITY="${POKEPORT_IDENTITY:-gen1recomp-mp-smoke}"

if [ ! -f "$LOVE_SAVE/$SMOKE_IDENTITY/red/rom-cache.complete" ]; then
  donor=""
  for candidate in "$LOVE_SAVE/pokemon-love2d" "$LOVE_SAVE"/*; do
    if [ -f "$candidate/red/rom-cache.complete" ]; then donor="$candidate"; break; fi
  done
  if [ -z "$donor" ]; then
    echo "no imported ROM cache found under $LOVE_SAVE." >&2
    echo "Launch the game once and import a ROM, then re-run this." >&2
    exit 1
  fi
  echo "seeding scratch identity '$SMOKE_IDENTITY' from $(basename "$donor")"
  mkdir -p "$LOVE_SAVE/$SMOKE_IDENTITY"
  cp -R "$donor/red" "$LOVE_SAVE/$SMOKE_IDENTITY/red"
  if [ -f "$donor/rom-cache.complete" ]; then
    cp "$donor/rom-cache.complete" "$LOVE_SAVE/$SMOKE_IDENTITY/rom-cache.complete"
  fi
fi

POKEPORT_IDENTITY="$SMOKE_IDENTITY"
echo "using LOVE identity: $POKEPORT_IDENTITY"

if ! command -v love >/dev/null 2>&1; then
  echo "love is not on PATH.  Install it with: brew install --cask love" >&2
  exit 1
fi

rm -f /tmp/pokeserver_smoke.log
cd "$REPO"

set +e
POKEPORT_IDENTITY="$POKEPORT_IDENTITY" \
POKEPORT_TOUCH=0 \
POKESERVER_DIR="$SERVER_DIR" \
POKEPORT_LINK_PORT="$PORT" \
POKEPORT_DRIVER=tests/drivers/online_relay_smoke.lua \
  love . 2>&1 | tee /tmp/gen1recomp-mp-test-smoke.log
status="${PIPESTATUS[0]}"
set -e

# The driver leaves its relay running (see the note above); clear it so the
# next run starts from a clean port.
leftover="$(lsof -ti "tcp:$PORT" 2>/dev/null || true)"
if [ -n "$leftover" ]; then
  # shellcheck disable=SC2086
  kill $leftover 2>/dev/null || true
fi

echo
if [ "$status" -eq 0 ]; then
  echo "PASS -- the relay served a full two-player battle end to end."
else
  echo "FAIL -- see the [driver] FAIL lines above and /tmp/pokeserver_smoke.log."
fi
exit "$status"

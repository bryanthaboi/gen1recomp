#!/usr/bin/env bash
# Prove two players can battle THROUGH the running relay container.
#
# bin/smoke-test.sh proves the server logic is correct, but it spawns its own
# server in-process -- it never crosses a container boundary.  This one starts
# nothing: it points two real game clients at the container's published port
# and plays a full battle through it, which is what a player actually does.
#
#   ./bin/container-test.sh                 # local container
#   ./bin/container-test.sh 192.168.0.134:17778   # someone else's
#
# Exit code 0 means two players joined the running server and battled.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TARGET="${1:-${POKEPORT_RELAY_ADDR:-127.0.0.1:17778}}"

case "$TARGET" in
  *:*) ;;
  *) echo "target must be host:port, got '$TARGET'" >&2; exit 2 ;;
esac
case "${TARGET##*:}" in
  ''|*[!0-9]*) echo "target must be host:port with a numeric port, got '$TARGET'" >&2; exit 2 ;;
esac

if ! command -v love >/dev/null 2>&1; then
  echo "love is not on PATH.  Install it with: brew install --cask love" >&2
  exit 1
fi

# The HTTP control port is the lobby port + 1, which is how the container
# publishes them too.
HTTP_PORT="$(( ${TARGET##*:} + 1 ))"
HEALTH_HOST="${TARGET%%:*}"
if [ "$HEALTH_HOST" = "$TARGET" ]; then HEALTH_HOST=127.0.0.1; fi

if ! curl -fsS --max-time 3 "http://$HEALTH_HOST:$HTTP_PORT/health" >/dev/null 2>&1; then
  echo "no relay answering at $TARGET (health check http://$HEALTH_HOST:$HTTP_PORT/health failed)." >&2
  echo "Start it first:  ./bin/relay.sh up" >&2
  exit 1
fi

echo "relay at $TARGET is healthy; running the battle through it"

# Same scratch-identity trick as smoke-test.sh: the driver only runs after a
# real game boots, which needs an imported ROM cache, and a test has no
# business writing to the folder someone actually plays from.
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

cd "$REPO"

set +e
POKEPORT_IDENTITY="$SMOKE_IDENTITY" \
POKEPORT_TOUCH=0 \
POKEPORT_RELAY_ADDR="$TARGET" \
POKEPORT_DRIVER=gen1recomp-mp-test/tests/container_battle.lua \
  love . 2>&1 | tee /tmp/gen1recomp-mp-test-container.log
status="${PIPESTATUS[0]}"
set -e

echo
if [ "$status" -eq 0 ]; then
  echo "PASS -- two players joined the running server and battled."
else
  echo "FAIL -- see the [driver] FAIL lines above and /tmp/gen1recomp-mp-test-container.log."
fi
exit "$status"

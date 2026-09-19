#!/usr/bin/env bash
# Launch the game pointed at the local relay container.
#
#   ./bin/play.sh                  -> 127.0.0.1:17778 (this Mac, one player)
#   ./bin/play.sh 192.168.0.134    -> another machine's relay on the LAN
#   RELAY_ADDR=192.168.0.134:17778 ./bin/play.sh
#
# The game reads the relay address from POKEPORT_RELAY_ADDR.  There is no
# in-game field for it, so it has to be set before the process starts -- which
# is exactly what this script is for.
#
# Two players on one Mac: run this twice.  The game sandboxes its save folder
# per POKEPORT_IDENTITY, so the second run needs its own identity or the two
# windows will fight over one save:
#
#   ./bin/play.sh
#   POKEPORT_IDENTITY=player2 ./bin/play.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

HOST_LOBBY_PORT="${HOST_LOBBY_PORT:-17778}"
RELAY_ADDR="${RELAY_ADDR:-${1:-127.0.0.1:$HOST_LOBBY_PORT}}"
export POKEPORT_RELAY_ADDR="$RELAY_ADDR"

if ! curl -fsS --max-time 2 \
    "http://127.0.0.1:${HOST_HTTP_PORT:-17779}/health" >/dev/null 2>&1; then
  echo "warning: nothing answered on the relay's /health port." >&2
  echo "         start it with: ./bin/relay.sh up" >&2
  echo "         (continuing anyway -- the relay may be on another machine)" >&2
fi

echo "relay address: $POKEPORT_RELAY_ADDR"

if [ -x /Applications/gen1recomp.app/Contents/MacOS/love ] \
   && [ "${USE_INSTALLED_APP:-0}" = "1" ]; then
  exec /Applications/gen1recomp.app/Contents/MacOS/love "$REPO"
fi

if ! command -v love >/dev/null 2>&1; then
  echo "love is not on PATH.  Install it with: brew install --cask love" >&2
  exit 1
fi

cd "$REPO"
exec love .

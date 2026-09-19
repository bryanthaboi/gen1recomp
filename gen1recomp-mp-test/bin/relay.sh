#!/usr/bin/env bash
# Start / stop / inspect the gen1recomp relay container.
#
#   ./bin/relay.sh up        build and start it in the background
#   ./bin/relay.sh logs      follow the log (Ctrl-C to stop watching)
#   ./bin/relay.sh status    is it healthy, and who is connected?
#   ./bin/relay.sh down      stop and remove it
#
# This talks to Orbstack through the normal `docker` CLI.  It never touches
# the `loghook` container.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

HOST_LOBBY_PORT="${HOST_LOBBY_PORT:-17778}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-17779}"

case "${1:-up}" in
  up)
    docker compose up -d --build
    printf '\nwaiting for the relay to answer on 127.0.0.1:%s ...\n' "$HOST_HTTP_PORT"
    for _ in $(seq 1 30); do
      if curl -fsS "http://127.0.0.1:$HOST_HTTP_PORT/health" >/dev/null 2>&1; then
        curl -sS "http://127.0.0.1:$HOST_HTTP_PORT/health"; echo
        printf '\nrelay is up.  Point the game at it with:\n'
        printf '  POKEPORT_RELAY_ADDR=<this-mac-ip>:%s\n' "$HOST_LOBBY_PORT"
        exit 0
      fi
      sleep 1
    done
    echo "the relay did not come up; check: ./bin/relay.sh logs" >&2
    exit 1
    ;;
  down)
    docker compose down
    ;;
  logs)
    docker compose logs -f relay
    ;;
  status)
    docker compose ps
    echo
    echo "--- /health"
    curl -sS "http://127.0.0.1:$HOST_HTTP_PORT/health" || echo "(no answer)"
    echo
    echo "--- /players"
    curl -sS "http://127.0.0.1:$HOST_HTTP_PORT/players" || echo "(no answer)"
    echo
    echo "--- /rooms"
    curl -sS "http://127.0.0.1:$HOST_HTTP_PORT/rooms" || echo "(no answer)"
    echo
    ;;
  *)
    echo "usage: $0 {up|down|logs|status}" >&2
    exit 2
    ;;
esac

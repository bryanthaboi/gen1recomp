#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
test_root="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$test_root"
}
trap cleanup EXIT

python3 tests/integration/http_fixture.py "$test_root/port" &
server_pid=$!
for _ in $(seq 1 50); do
  [ -s "$test_root/port" ] && break
  sleep 0.1
done
test -s "$test_root/port"
port="$(tr -cd '0-9' < "$test_root/port")"
test -n "$port"

runner=(love .)
if command -v xvfb-run >/dev/null 2>&1; then
  runner=(xvfb-run -a love .)
fi

env \
  POKEPORT_DATA_DIR=tests/fixture_data \
  POKEPORT_BOOT_OVERWORLD=1 \
  POKEPORT_SAFE_MODE=1 \
  POKEPORT_DRIVER=tests/drivers/fixture_workers.lua \
  POKEPORT_IDENTITY=fixture-workers-ci \
  POKEPORT_TOUCH=0 \
  POKEPORT_TEST_HTTP_URL="http://127.0.0.1:$port" \
  "${runner[@]}"

#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SLOW_DRIVERS="game3_daycare_egg game3_daycare_menu game3_daycare_deposit game3_import2_fresh_cache game3_import2_town_map game3_trade_scene game3_u8c_yesno_frame game3_u9c_catch_ball_open"
REALTIME_DRIVERS="battle_fanfare_speed_bug1952_test"

help_text() {
  cat <<HELP
usage: tools/run_driver.sh <version> <identity> <driver.lua> [shotdir]

Runs tools/driver_preflight.lua, reimports a stale identity with
tools/reimport.sh --force, then runs the driver under a watchdog:
  1. POKEPORT_SPEED=200 (caller's POKEPORT_SPEED wins; known 200x-sensitive
     drivers start at 10) with a RUN_DRIVER_LIMIT second limit (default 30,
     180 for the 10x drivers; RUN_DRIVER_ALARM is accepted as the old name).
  2. On timeout it kills only its own love and reruns once: at 200 if the
     first run was not 200, otherwise at 10.
  3. If the rerun also times out it prints BROKEN and exits 125.
Exit codes: 0 pass, the driver's code on failure, 125 broken, 124 alarm
from tools/pty_run.py outside the watchdog.
Relative driver and shotdir paths resolve against the current directory.
The window stays off screen with no Dock icon or focus change and the game
is muted (POKEPORT_BACKGROUND=1, the default); POKEPORT_BACKGROUND=0 opts out.
HELP
}

case "${1:-}" in
  -h|--help) help_text; exit 0 ;;
esac
if [ $# -lt 3 ]; then
  help_text >&2
  exit 2
fi
abspath() {
  local dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)"
  if [ -n "$dir" ]; then
    echo "$dir/$(basename "$1")"
    return
  fi
  case "$1" in
    /*) echo "$1" ;;
    *) echo "$PWD/$1" ;;
  esac
}
VERSION="$1"
IDENT="$2"
DRIVER="$3"
SHOTS="${4:-}"
LIMIT="${RUN_DRIVER_LIMIT:-${RUN_DRIVER_ALARM:-30}}"
case "$LIMIT" in
  ''|*[!0-9]*|0*) echo "RUN_DRIVER_LIMIT must be a positive integer" >&2; exit 2 ;;
esac
[ -z "$SHOTS" ] || SHOTS="$(abspath "$SHOTS")"
if [ ! -f "$DRIVER" ] && [ -f "$ROOT/$DRIVER" ]; then
  DRIVER="$ROOT/$DRIVER"
fi
DRIVER="$(abspath "$DRIVER")"
case "$DRIVER" in
  "$ROOT"/*) DRIVER="${DRIVER#"$ROOT"/}" ;;
esac

NAME="$(basename "$DRIVER" .lua)"
if [ -n "${POKEPORT_SPEED:-}" ]; then
  SPEED="$POKEPORT_SPEED"
else
  case " $REALTIME_DRIVERS " in
    *" $NAME "*) SPEED=1; [ -n "${RUN_DRIVER_LIMIT:-${RUN_DRIVER_ALARM:-}}" ] || LIMIT=300 ;;
    *) case " $SLOW_DRIVERS " in
         *" $NAME "*) SPEED=10; [ -n "${RUN_DRIVER_LIMIT:-${RUN_DRIVER_ALARM:-}}" ] || LIMIT=180 ;;
         *) SPEED=200 ;;
       esac ;;
  esac
fi

check="$(luajit "$ROOT/tools/driver_preflight.lua" "$IDENT" "$VERSION")"
echo "preflight $VERSION [$IDENT]: $check"
if [ "${check%% *}" != "READY" ]; then
  "$ROOT/tools/reimport.sh" "$VERSION" --identity "$IDENT" --force || exit 1
  check="$(luajit "$ROOT/tools/driver_preflight.lua" "$IDENT" "$VERSION")"
  echo "preflight $VERSION [$IDENT]: $check"
  [ "${check%% *}" = "READY" ] || exit 1
fi

[ -z "$SHOTS" ] || mkdir -p "$SHOTS"
cd "$ROOT" || exit 1

run_once() {
  env POKEPORT_IDENTITY="$IDENT" POKEPORT_VERSION="$VERSION" POKEPORT_DRIVER="$DRIVER" \
    POKEPORT_BACKGROUND="${POKEPORT_BACKGROUND:-1}" POKEPORT_SPEED="$1" \
    ${SHOTS:+POKEPORT_SHOT_DIR="$SHOTS"} \
    perl -e "alarm $LIMIT; exec @ARGV" python3 "$ROOT/tools/pty_run.py" love .
}

echo "driver $DRIVER: POKEPORT_SPEED=$SPEED, ${LIMIT}s limit"
start=$(date +%s)
run_once "$SPEED"
code=$?
if [ "$code" = 124 ]; then
  if [ "$SPEED" = 200 ]; then RETRY=10; else RETRY=200; fi
  echo "driver $DRIVER: timed out at ${SPEED}x after ${LIMIT}s, rerunning at ${RETRY}x"
  first="$SPEED"
  SPEED="$RETRY"
  start=$(date +%s)
  run_once "$SPEED"
  code=$?
  if [ "$code" = 124 ]; then
    echo "BROKEN $DRIVER (timed out at ${first}x and ${SPEED}x)"
    exit 125
  fi
fi
secs=$(( $(date +%s) - start ))
if [ "$code" = 0 ]; then
  echo "driver $DRIVER passed at ${SPEED}x (${secs}s)"
else
  echo "driver $DRIVER failed at ${SPEED}x (${secs}s)"
fi
echo "driver $DRIVER exited $code"
exit "$code"

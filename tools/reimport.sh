#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALL_VERSIONS="red blue yellow gold silver crystal firered leafgreen"

help_text() {
  cat <<EOF
usage: tools/reimport.sh <version|all> [--identity NAME] [--rom PATH] [--force] [--timeout SECONDS]

Imports a ROM into a POKEPORT_IDENTITY save dir through the real importer
(POKEPORT_IMPORT_ONLY=1) and checks the result with tools/driver_preflight.lua.

  version     one of: $ALL_VERSIONS
  --identity  save identity to import into (default <version>-YYMMDD)
  --rom       ROM path (single version only)
  --force     reimport even when the identity is already current
  --timeout   seconds before the import is killed (default 900)

ROM lookup: --rom, then tools/reimport.local (gitignored, version=path lines),
then POKEPORT_ROM_DIR (No-Intro style names, see docs/architecture.md).
The import window stays off screen (POKEPORT_BACKGROUND=0 shows it).
EOF
}

usage() {
  help_text >&2
  exit 2
}

[ $# -ge 1 ] || usage
case "$1" in
  -h|--help) help_text; exit 0 ;;
esac
TARGET="$1"
shift
IDENTITY=""
ROM=""
FORCE=0
TIMEOUT=900
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) [ $# -ge 2 ] || usage; IDENTITY="$2"; shift 2 ;;
    --rom) [ $# -ge 2 ] || usage; ROM="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --timeout) [ $# -ge 2 ] || usage; TIMEOUT="$2"; shift 2 ;;
    -h|--help) help_text; exit 0 ;;
    *) usage ;;
  esac
done

case "$TIMEOUT" in
  ''|*[!0-9]*|0*) echo "--timeout must be a positive integer" >&2; exit 2 ;;
esac

if [ "$TARGET" = "all" ]; then
  VERSIONS="$ALL_VERSIONS"
  [ -z "$ROM" ] || { echo "--rom only applies to a single version" >&2; exit 2; }
else
  case " $ALL_VERSIONS " in
    *" $TARGET "*) VERSIONS="$TARGET" ;;
    *) echo "unknown version: $TARGET" >&2; usage ;;
  esac
fi

rom_pattern() {
  case "$1" in
    red) echo "Pokemon - Red Version*.gb" ;;
    blue) echo "Pokemon - Blue Version*.gb" ;;
    yellow) echo "Pokemon - Yellow Version*.gbc" ;;
    gold) echo "Pokemon - Gold Version*.gbc" ;;
    silver) echo "Pokemon - Silver Version*.gbc" ;;
    crystal) echo "Pokemon - Crystal Version*.gbc" ;;
    firered) echo "Pokemon - Fire*Red Version*.gba" ;;
    leafgreen) echo "Pokemon - Leaf*Green Version*.gba" ;;
  esac
}

default_rom() {
  local dir="${POKEPORT_ROM_DIR:-}" pattern f
  [ -n "$dir" ] || { echo "(set POKEPORT_ROM_DIR, tools/reimport.local or --rom)"; return; }
  pattern="$(rom_pattern "$1")"
  for f in "$dir"/$pattern; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
  echo "$dir/$pattern"
}

find_rom() {
  local version="$1" line path
  if [ -n "$ROM" ]; then
    echo "$ROM"
    return
  fi
  if [ -f "$ROOT/tools/reimport.local" ]; then
    line="$(grep -E "^[[:space:]]*$version[[:space:]]*=" "$ROOT/tools/reimport.local" | tail -n 1)"
    if [ -n "$line" ]; then
      path="${line#*=}"
      path="$(echo "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      case "$path" in
        "~/"*) path="$HOME/${path#\~/}" ;;
        /*) ;;
        *) path="$ROOT/$path" ;;
      esac
      echo "$path"
      return
    fi
  fi
  default_rom "$version"
}

STAMP="$(date +%y%m%d)"
FAILED=0
ATTEMPTED=0

for version in $VERSIONS; do
  rom="$(find_rom "$version")"
  ident="${IDENTITY:-$version-$STAMP}"
  if [ ! -f "$rom" ]; then
    if [ "$TARGET" = "all" ]; then
      echo "$version [$ident]: skipped (no ROM at $rom)"
    else
      echo "$version [$ident]: FAILED (no ROM at $rom)"
      FAILED=1
    fi
    continue
  fi
  ATTEMPTED=1
  if [ "$FORCE" = 0 ] && luajit "$ROOT/tools/driver_preflight.lua" "$ident" "$version" --identity-only >/dev/null 2>&1; then
    echo "$version [$ident]: ready"
    continue
  fi
  log="$(mktemp "${TMPDIR:-/tmp}/reimport-$version.XXXXXX")"
  start=$(date +%s)
  (cd "$ROOT" && env POKEPORT_IDENTITY="$ident" POKEPORT_VERSION="$version" \
    POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM="$rom" POKEPORT_FORCE_IMPORT=1 \
    POKEPORT_BACKGROUND="${POKEPORT_BACKGROUND:-1}" \
    perl -e "alarm $TIMEOUT; exec @ARGV" python3 "$ROOT/tools/pty_run.py" love . >"$log" 2>&1)
  code=$?
  secs=$(( $(date +%s) - start ))
  check="$(luajit "$ROOT/tools/driver_preflight.lua" "$ident" "$version" --identity-only 2>&1)"
  if [ "$code" = 0 ] && [ "${check%% *}" = "READY" ]; then
    echo "$version [$ident]: imported (${secs}s)"
    rm -f "$log"
  else
    reason="$(grep -m 1 -E "import failed|Error|error:" "$log" | tr -d '\r')"
    [ "$code" = 124 ] && reason="timed out after ${TIMEOUT}s"
    [ -n "$reason" ] || reason="love exited $code"
    echo "$version [$ident]: FAILED ($reason; cache $check; log $log)"
    FAILED=1
  fi
done

if [ "$ATTEMPTED" = 0 ] && [ "$FAILED" = 0 ]; then
  echo "no ROMs found" >&2
  exit 1
fi
exit "$FAILED"

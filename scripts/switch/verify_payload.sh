#!/usr/bin/env bash
# Reject private / generated content inside a .love payload.
#
# Usage:
#   scripts/switch/verify_payload.sh <path/to/game.love>
#   scripts/switch/verify_payload.sh --self-test
#
# Fails on generated cache, ROM dumps (.gb/.gbc/.sav), rom-cache.complete,
# and save backup files (.bak). Never ships user ROMs or save data.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOVE_FILE=""
SELF_TEST=0

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
say()  { printf 'verify_payload: %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$LOVE_FILE" ]; then
        LOVE_FILE="$1"
      else
        fail "unknown argument: $1"
      fi
      shift
      ;;
  esac
done

verify_love() {
  local love="$1"
  local listing
  listing="$(mktemp "${TMPDIR:-/tmp}/love-listing.XXXXXX")"

  [ -f "$love" ] || { rm -f "$listing"; fail "missing love archive: $love"; }
  unzip -Z1 "$love" > "$listing"

  if grep -Eq '^(data|assets)/generated/|/(data|assets)/generated/' "$listing"; then
    rm -f "$listing"
    fail "forbidden generated cache path in $love"
  fi

  if grep -Eiq '\.(gb|gbc|sav)$' "$listing"; then
    rm -f "$listing"
    fail "forbidden ROM or save file extension in $love"
  fi

  if grep -Eq '(^|/)rom-cache\.complete$' "$listing"; then
    rm -f "$listing"
    fail "forbidden rom-cache.complete marker in $love"
  fi

  if grep -Eiq '\.bak$' "$listing"; then
    rm -f "$listing"
    fail "forbidden save backup (.bak) in $love"
  fi

  rm -f "$listing"
  say "OK $love"
}

run_self_test() {
  local work clean bad staging
  work="$(mktemp -d "${TMPDIR:-/tmp}/verify-payload.XXXXXX")"
  trap "rm -rf '$work'" EXIT

  clean="$work/clean.love"
  "$ROOT/scripts/pack_love.sh" --output "$clean" --listing "$work/clean-listing.txt" >/dev/null
  verify_love "$clean"

  bad="$work/bad.love"
  cp "$clean" "$bad"
  staging="$work/staging"
  mkdir -p "$staging/data/generated"
  echo "secret" > "$staging/data/generated/rom.bin"
  (cd "$staging" && zip -q "$bad" data/generated/rom.bin)

  if ( verify_love "$bad" >/dev/null 2>&1 ); then
    fail "self-test: expected forbidden generated path to fail"
  fi

  bad2="$work/bad2.love"
  cp "$clean" "$bad2"
  echo "x" > "$work/rom-cache.complete"
  (cd "$work" && zip -q "$bad2" rom-cache.complete)
  if ( verify_love "$bad2" >/dev/null 2>&1 ); then
    fail "self-test: expected rom-cache.complete to fail"
  fi

  say "self-test OK"
}

if [ "$SELF_TEST" -eq 1 ]; then
  run_self_test
  exit 0
fi

[ -n "$LOVE_FILE" ] || fail "usage: $0 <game.love> | --self-test"
verify_love "$LOVE_FILE"

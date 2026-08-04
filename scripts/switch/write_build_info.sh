#!/usr/bin/env bash
# Write build-info.json for Switch artifacts.
#
# Usage: scripts/switch/write_build_info.sh OUTPUT.json [VERSION]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOVE_NX_TAG="11.5-nx1"
MANIFEST="$ROOT/scripts/switch/love-nx-11.5-nx1.sha256"
OUTPUT="${1:-}"
VERSION="${2:-}"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -n "$OUTPUT" ] || fail "usage: $0 OUTPUT.json [VERSION]"
[ -f "$MANIFEST" ] || fail "missing love-nx manifest: $MANIFEST"

if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
fi

GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_SHORT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

read_manifest_hash() {
  local name="$1"
  local line hash
  line="$(grep -E "^${name}[[:space:]]+" "$MANIFEST" | head -1 || true)"
  [ -n "$line" ] || fail "manifest missing entry for $name"
  hash="$(printf '%s' "$line" | awk '{print $2}')"
  case "$hash" in
    TBD_*|"") fail "manifest hash for $name is not filled in ($hash)" ;;
  esac
  printf '%s' "$hash"
}

LOVE_NRO_SHA="$(read_manifest_hash love.nro)"
LOVE_ELF_SHA="$(read_manifest_hash love.elf)"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
{
  "version": "$VERSION",
  "gitCommit": "$GIT_SHORT",
  "gitCommitFull": "$GIT_COMMIT",
  "loveNxTag": "$LOVE_NX_TAG",
  "loveNxChecksums": {
    "love.nro": "$LOVE_NRO_SHA",
    "love.elf": "$LOVE_ELF_SHA"
  },
  "builtAt": "$BUILT_AT"
}
EOF

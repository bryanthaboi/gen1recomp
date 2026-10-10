#!/usr/bin/env bash
# Host-side check of a built libluajit-5.1.so.2 (works on macOS and Linux, no
# readelf needed).  Fails if the library is not the pinned LuaJIT, is the old
# 2.1.0-beta3, or needs a glibc newer than the pin allows.
#
# Usage: scripts/luajit/verify_luajit.sh <libluajit-5.1.so.2>

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=pins.sh
. "$HERE/pins.sh"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || fail "usage: verify_luajit.sh <libluajit-5.1.so.2>"
LIB="$1"
[ -f "$LIB" ] || fail "not a file: $LIB"

# 64-bit (byte 4 = 02), little-endian (byte 5 = 01), e_machine 0xb7 = aarch64.
hdr="$(od -An -tx1 -N20 "$LIB" | tr -d ' \n')"
[ "${hdr:0:8}" = "7f454c46" ] && [ "${hdr:8:2}" = "02" ] && [ "${hdr:10:2}" = "01" ] \
  && [ "${hdr:36:4}" = "b700" ] \
  || fail "$LIB is not a 64-bit little-endian aarch64 ELF"

grep -aqF "$LUAJIT_VERSION_STRING" "$LIB" \
  || fail "$LIB does not contain '$LUAJIT_VERSION_STRING'"
if grep -aq '2\.1\.0-beta' "$LIB"; then
  fail "$LIB contains '2.1.0-beta' (old LuaJIT)"
fi

# Built with PREFIX=/usr; a build-prefix path here means a stale or wrong build.
grep -aqF '/usr/share/luajit-2.1/?.lua' "$LIB" \
  || fail "$LIB does not contain the default module path /usr/share/luajit-2.1/?.lua"

# Compare dotted versions numerically without relying on sort -V.
ver_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = na > nb ? na : nb
    for (i = 1; i <= n; i++) {
      if ((x[i] + 0) > (y[i] + 0)) exit 0
      if ((x[i] + 0) < (y[i] + 0)) exit 1
    }
    exit 1
  }'
}

maxg=""
while IFS= read -r v; do
  v="${v#GLIBC_}"
  [ -n "$v" ] || continue
  if [ -z "$maxg" ] || ver_gt "$v" "$maxg"; then maxg="$v"; fi
done < <(grep -ao 'GLIBC_[0-9][0-9.]*' "$LIB" | sort -u)

[ -n "$maxg" ] || fail "$LIB has no GLIBC_ version strings"
if ver_gt "$maxg" "$LUAJIT_MAX_GLIBC"; then
  fail "$LIB requires GLIBC_$maxg > $LUAJIT_MAX_GLIBC"
fi
echo "verify_luajit ok: '$LUAJIT_VERSION_STRING', max GLIBC=$maxg (limit $LUAJIT_MAX_GLIBC)" >&2

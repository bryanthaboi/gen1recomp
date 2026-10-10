#!/usr/bin/env bash
# Offline test of scripts/luajit/portmaster_runtime.sh (no docker, no network).
# Usage: bash scripts/luajit/selftest_portmaster_runtime.sh
# Each case runs in a subshell with a stub fail() that exits that subshell, so
# failures can be asserted.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=pins.sh
. "$HERE/pins.sh"

say()  { :; }
warn() { :; }
fail() { printf 'stub fail: %s\n' "$*" >&2; exit 1; }
# shellcheck source=portmaster_runtime.sh
. "$HERE/portmaster_runtime.sh"

bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
# expect_ok NAME CMD...  /  expect_fail NAME CMD...: run CMD in a subshell.
expect_ok()   { local n="$1"; shift; ( "$@" ) >/dev/null 2>&1 || bad "$n: expected success"; }
expect_fail() { local n="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then bad "$n: expected failure"; fi; }

# Synthetic aarch64 "library" that passes verify_luajit.sh.
lj_make() {
  { printf '\177ELF\002\001'; head -c 12 /dev/zero; printf '\xb7\x00'
    printf '\0%s\0%s\0%s\0' "$LUAJIT_VERSION_STRING" '/usr/share/luajit-2.1/?.lua' GLIBC_2.17
  } > "$1"
}

mkdir -p "$TMP/good" "$TMP/nocopy" "$TMP/emptycopy"
lj_make "$TMP/good/libluajit-5.1.so.2"
echo "LuaJIT license" > "$TMP/good/COPYRIGHT"
lj_make "$TMP/nocopy/libluajit-5.1.so.2"
lj_make "$TMP/emptycopy/libluajit-5.1.so.2"
: > "$TMP/emptycopy/COPYRIGHT"
echo "other license" > "$TMP/alt-COPYRIGHT"

case_stage_without_select() { unset LUAJIT_LIB LUAJIT_COPYRIGHT; pm_stage_luajit "$TMP" "$TMP"; }
expect_fail "stage without select" case_stage_without_select

case_missing_lib() { GEN1RECOMP_LUAJIT_LIB="$TMP/nope.so" pm_select_luajit; }
expect_fail "missing GEN1RECOMP_LUAJIT_LIB" case_missing_lib

case_empty_copyright() {
  GEN1RECOMP_LUAJIT_LIB="$TMP/emptycopy/libluajit-5.1.so.2" GEN1RECOMP_LUAJIT_COPYRIGHT= pm_select_luajit
}
expect_fail "empty COPYRIGHT" case_empty_copyright

case_no_copyright_anywhere() {
  GEN1RECOMP_LUAJIT_LIB="$TMP/nocopy/libluajit-5.1.so.2" GEN1RECOMP_LUAJIT_COPYRIGHT= pm_select_luajit
}
expect_fail "no COPYRIGHT anywhere" case_no_copyright_anywhere

# Verification is really reached: a bad library is rejected.
printf 'not a library' > "$TMP/emptycopy/bad.so"
echo x > "$TMP/emptycopy/COPYRIGHT"
case_bad_lib() { GEN1RECOMP_LUAJIT_LIB="$TMP/emptycopy/bad.so" pm_select_luajit; }
expect_fail "bad library" case_bad_lib

case_env_copyright() {
  export GEN1RECOMP_LUAJIT_LIB="$TMP/nocopy/libluajit-5.1.so.2"
  export GEN1RECOMP_LUAJIT_COPYRIGHT="$TMP/alt-COPYRIGHT"
  pm_select_luajit
  [ "$LUAJIT_LIB" = "$GEN1RECOMP_LUAJIT_LIB" ] || exit 1
  [ "$LUAJIT_COPYRIGHT" = "$TMP/alt-COPYRIGHT" ] || exit 1
}
expect_ok "COPYRIGHT via env" case_env_copyright

# Stage + zip round trip.
build_tree() { # $1 = tree root
  mkdir -p "$1/port/libs.aarch64" "$1/port/licenses"
  GEN1RECOMP_LUAJIT_LIB="$TMP/good/libluajit-5.1.so.2" pm_select_luajit
  pm_stage_luajit "$1/port/libs.aarch64" "$1/port/licenses"
}
case_stage() {
  build_tree "$TMP/tree"
  cmp "$TMP/good/libluajit-5.1.so.2" "$TMP/tree/port/libs.aarch64/libluajit-5.1.so.2"
  cmp "$TMP/good/COPYRIGHT" "$TMP/tree/port/licenses/LuaJIT-COPYRIGHT"
}
expect_ok "stage copies both files" case_stage

command -v zip >/dev/null && command -v unzip >/dev/null || { echo "zip/unzip missing; skipping zip cases" >&2; echo "selftest_portmaster_runtime: ok (zip cases skipped)"; exit 0; }

( cd "$TMP/tree" && zip -q -r "$TMP/good.zip" port )
rm "$TMP/tree/port/licenses/LuaJIT-COPYRIGHT"
( cd "$TMP/tree" && zip -q -r "$TMP/nocopy.zip" port )

mkdir -p "$TMP/work"
expect_ok   "verify good zip"            pm_verify_zip "$TMP/good.zip" port "$TMP/work"
expect_fail "verify zip without COPYRIGHT" pm_verify_zip "$TMP/nocopy.zip" port "$TMP/work"

echo "selftest_portmaster_runtime: ok"

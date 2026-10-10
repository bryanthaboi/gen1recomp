#!/usr/bin/env bash
# Shared PortMaster zip helpers for build-linux-arm-sbc.sh and build-rg34xxsp.sh.
# Source this file; it has no side effects at source time.
# The caller must define ROOT, say, warn and fail.

# shellcheck source=scripts/luajit/pins.sh
. "$ROOT/scripts/luajit/pins.sh"
# shellcheck source=scripts/lib/fetch.sh
. "$ROOT/scripts/lib/fetch.sh"

# shellcheck disable=SC2034
LOVE_VERSION="${LOVE_VERSION:-11.5}"

# Official PortMaster LÖVE 11.5 aarch64 runtime (small love stub + liblove).
# Pinned to the last PortMaster-GUI commit that touched runtimes/love_11.5, and
# every file is sha256-checked. libluajit is deliberately NOT taken from
# here: that one is LuaJIT 2.1.0-beta3 (2017), which crashes with the JIT on.
PM_RUNTIME_COMMIT="715f50fd277febf942a66d59ac31e5a9c36c2f69"
PM_RUNTIME_BASE="https://raw.githubusercontent.com/PortsMaster/PortMaster-GUI/$PM_RUNTIME_COMMIT/PortMaster/runtimes/love_${LOVE_VERSION}"
PM_SHA_LOVE="c6c64453ed6163c8aeb14d303bad1e4d9ecc4d628097b3c6420ada2fa6a8690f"
PM_SHA_LIBLOVE="a50c83729cb0e1c4d8389eaaa827f0a6e7f3362814d0504ca84074dd0e47c379"
PM_SHA_MODPLUG="026b2287c9d68f920cf541b68b94f1a691168e4bbf301a8793f4114808aa8f95"
PM_SHA_OGG="66015f344b53895affd3ff153f402097ebaa2add33246bea2d7fca27b682e07a"

# pm_fetch_runtime CACHE_DIR: download + sha256-check the 4 runtime files.
pm_fetch_runtime() {
  local dir="$1"
  download_pinned "$PM_RUNTIME_BASE/love.aarch64" "$dir/love.aarch64" "$PM_SHA_LOVE"
  download_pinned "$PM_RUNTIME_BASE/libs.aarch64/liblove-11.5.so" "$dir/liblove-11.5.so" "$PM_SHA_LIBLOVE"
  download_pinned "$PM_RUNTIME_BASE/libs.aarch64/libmodplug.so.1" "$dir/libmodplug.so.1" "$PM_SHA_MODPLUG"
  download_pinned "$PM_RUNTIME_BASE/libs.aarch64/libogg.so.0" "$dir/libogg.so.0" "$PM_SHA_OGG"
}

# pm_select_luajit: a pinned modern build, never PortMaster's beta3. Either
# supplied via GEN1RECOMP_LUAJIT_LIB (CI release jobs) or built in a container.
# Sets LUAJIT_LIB and LUAJIT_COPYRIGHT.
pm_select_luajit() {
  if [ -n "${GEN1RECOMP_LUAJIT_LIB:-}" ]; then
    LUAJIT_LIB="$GEN1RECOMP_LUAJIT_LIB"
    [ -f "$LUAJIT_LIB" ] || fail "GEN1RECOMP_LUAJIT_LIB does not exist: $LUAJIT_LIB"
    LUAJIT_COPYRIGHT="$(dirname "$LUAJIT_LIB")/COPYRIGHT"
    [ -s "$LUAJIT_COPYRIGHT" ] || LUAJIT_COPYRIGHT="${GEN1RECOMP_LUAJIT_COPYRIGHT:-}"
    [ -s "$LUAJIT_COPYRIGHT" ] \
      || fail "LuaJIT COPYRIGHT not found next to $LUAJIT_LIB; set GEN1RECOMP_LUAJIT_COPYRIGHT"
  else
    say "building pinned LuaJIT $LUAJIT_COMMIT"
    LUAJIT_LIB="$("$ROOT/scripts/luajit/build_luajit.sh")" \
      || fail "LuaJIT build failed (needs an aarch64 host with docker/podman, or set GEN1RECOMP_LUAJIT_LIB)"
    LUAJIT_COPYRIGHT="$(dirname "$LUAJIT_LIB")/COPYRIGHT"
  fi
  [ -f "$LUAJIT_LIB" ] && [ -s "$LUAJIT_COPYRIGHT" ] || fail "LuaJIT library or COPYRIGHT missing"
  "$ROOT/scripts/luajit/verify_luajit.sh" "$LUAJIT_LIB" || fail "LuaJIT library failed verification: $LUAJIT_LIB"
}

# pm_stage_luajit LIBS_DIR LICENSES_DIR
pm_stage_luajit() {
  : "${LUAJIT_LIB:?call pm_select_luajit before pm_stage_luajit}"
  : "${LUAJIT_COPYRIGHT:?call pm_select_luajit before pm_stage_luajit}"
  cp "$LUAJIT_LIB" "$1/libluajit-5.1.so.2"
  cp "$LUAJIT_COPYRIGHT" "$2/LuaJIT-COPYRIGHT"
}

# pm_verify_zip ZIP PORT_DIR_NAME WORK_DIR: verify the LuaJIT that actually
# landed in the zip, not just the input file.
pm_verify_zip() {
  local zip="$1" port="$2" work="$3" vdir
  vdir="$(mktemp -d "$work/verify.XXXXXX")"
  unzip -q "$zip" -d "$vdir"
  "$ROOT/scripts/luajit/verify_luajit.sh" "$vdir/$port/libs.aarch64/libluajit-5.1.so.2" \
    || { rm -rf "$vdir"; fail "zip LuaJIT verification failed"; }
  [ -s "$vdir/$port/licenses/LuaJIT-COPYRIGHT" ] \
    || { rm -rf "$vdir"; fail "zip is missing licenses/LuaJIT-COPYRIGHT"; }
  rm -rf "$vdir"
}

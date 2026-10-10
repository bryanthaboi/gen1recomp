#!/usr/bin/env bash
# Compile the pinned LuaJIT. Runs INSIDE an aarch64 Linux container
# (debian:bullseye + build-essential; binutils for readelf).
#
# Usage: compile_luajit.sh <tarball> <prefix>
# Env:   LUAJIT_VERSION_STRING  string the built library must contain (required)
#        LUAJIT_MAX_GLIBC       highest GLIBC_x.y symbol allowed (required)
#
# No -mcpu flag: the validated recipe is plain `make amalg` with GC64.

set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || fail "usage: compile_luajit.sh <tarball> <prefix>"
TARBALL="$1"
PREFIX="$2"
[ -f "$TARBALL" ] || fail "tarball not found: $TARBALL"
: "${LUAJIT_VERSION_STRING:?LUAJIT_VERSION_STRING must be set}"
: "${LUAJIT_MAX_GLIBC:?LUAJIT_MAX_GLIBC must be set}"

SRC_TMP="$(mktemp -d)"
trap 'rm -rf "$SRC_TMP"' EXIT
tar -xzf "$TARBALL" -C "$SRC_TMP"
SRC="$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[ -n "$SRC" ] || fail "tarball had no top-level directory"

cd "$SRC"
# Compile with PREFIX=/usr, install with the real prefix. LuaJIT bakes
# LUA_ROOT=$(PREFIX) into its default package.path/cpath at compile time, so
# compiling with the install prefix would leak a build-time directory
# (/tmp/prefix, /cache/prefix-...) into the shipped library. The top-level
# install only depends on src/luajit, so it does not recompile.
make -j"$(nproc)" amalg PREFIX=/usr XCFLAGS=-DLUAJIT_ENABLE_GC64 >&2
# Install into a staging root first (luajit.pc still says prefix=$PREFIX), so a
# failed check below never leaves a half-trusted tree in $PREFIX.
STAGE="$(mktemp -d)"
trap 'rm -rf "$SRC_TMP" "$STAGE"' EXIT
make install PREFIX="$PREFIX" DESTDIR="$STAGE" >&2
mkdir -p "$STAGE$PREFIX/share/doc/luajit"
cp COPYRIGHT "$STAGE$PREFIX/share/doc/luajit/COPYRIGHT"

LIB="$(readlink -f "$STAGE$PREFIX/lib/libluajit-5.1.so.2")"
[ -f "$LIB" ] || fail "missing $STAGE$PREFIX/lib/libluajit-5.1.so.2"

soname="$(readelf -d "$LIB" | sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p')"
[ "$soname" = "libluajit-5.1.so.2" ] || fail "unexpected SONAME: $soname"
if grep -aqF "$PREFIX" "$LIB"; then
  fail "library contains the build prefix '$PREFIX' (baked-in module path)"
fi

# Version, module path, ELF class/arch and glibc ceiling: the same checks the
# host-side gate runs (verify_luajit.sh needs only od, grep and awk).
bash "$(dirname "$0")/verify_luajit.sh" "$LIB" >&2

# COPYRIGHT goes in last: callers treat it as the "install finished" marker, so
# an interrupted copy never looks like a complete cached prefix.
mv "$STAGE$PREFIX/share/doc/luajit/COPYRIGHT" "$STAGE/COPYRIGHT"
mkdir -p "$PREFIX/share/doc/luajit"
cp -a "$STAGE$PREFIX/." "$PREFIX/"
cp "$STAGE/COPYRIGHT" "$PREFIX/share/doc/luajit/COPYRIGHT"
echo "luajit ok: staged and installed to $PREFIX" >&2

#!/usr/bin/env bash
# Build the pinned LuaJIT for aarch64 Linux inside a debian:bullseye container.
#
# Usage: scripts/luajit/build_luajit.sh
# Prints the path of the library on stdout; progress goes to stderr.
# Output: .bazinga/cache/luajit/<commit>-<recipe hash>-<image digest>/{libluajit-5.1.so.2,COPYRIGHT}
#
# Must run on an aarch64 host (docker or podman). Emulated (qemu) aarch64
# builds have miscompiled LuaJIT before, so other hosts are refused.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=pins.sh
. "$HERE/pins.sh"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
# shellcheck source=../lib/fetch.sh
. "$ROOT/scripts/lib/fetch.sh"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail "LuaJIT must be built on an aarch64 host (got $(uname -m)); emulated builds are unreliable. Build on arm64 or pass GEN1RECOMP_LUAJIT_LIB to the zip scripts." ;;
esac

CACHE="$ROOT/.bazinga/cache/luajit"
# Keyed by the build recipe and the pinned image digest, so changing either rebuilds.
RECIPE_HASH="$(sha256_file "$HERE/compile_luajit.sh")"
IMAGE_DIGEST="${LUAJIT_BUILD_IMAGE##*sha256:}"
OUT_DIR="$CACHE/$LUAJIT_COMMIT-${RECIPE_HASH:0:12}-${IMAGE_DIGEST:0:12}"
OUT="$OUT_DIR/libluajit-5.1.so.2"
mkdir -p "$CACHE" "$OUT_DIR"

if [ -f "$OUT" ] && [ -s "$OUT_DIR/COPYRIGHT" ] \
   && "$HERE/verify_luajit.sh" "$OUT" >/dev/null 2>&1; then
  say "LuaJIT $LUAJIT_COMMIT already built"
  echo "$OUT"
  exit 0
fi

# Pinned tarball (a cache hit must still match the pin). curl's progress goes
# to stderr, but keep stdout clean regardless: it carries only the lib path.
TARBALL="$CACHE/$LUAJIT_TARBALL"
download_pinned "$LUAJIT_URL" "$TARBALL" "$LUAJIT_SHA256" >&2

RT="$(container_runtime)" \
  || fail "docker or podman is required to build LuaJIT (or set GEN1RECOMP_LUAJIT_LIB for the zip scripts)"

STAGE="$(mktemp -d "$CACHE/stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/out"

say "building LuaJIT $LUAJIT_COMMIT in $RT ($LUAJIT_BUILD_IMAGE, arm64)"
"$RT" run --rm --platform linux/arm64 \
  -e LUAJIT_VERSION_STRING="$LUAJIT_VERSION_STRING" \
  -e LUAJIT_MAX_GLIBC="$LUAJIT_MAX_GLIBC" \
  -e LUAJIT_APT_SOURCES="$LUAJIT_APT_SOURCES" \
  -v "$HERE:/luajit-scripts:ro" \
  -v "$TARBALL:/in/$LUAJIT_TARBALL:ro" \
  -v "$STAGE/out:/out" \
  "$LUAJIT_BUILD_IMAGE" bash -euo pipefail -c '
    # Bullseye is EOL; same sources/apt.conf as scripts/linux-arm64/Dockerfile.
    printf "%s\n" "$LUAJIT_APT_SOURCES" > /etc/apt/sources.list
    rm -f /etc/apt/sources.list.d/*
    printf "Acquire::Check-Valid-Until \"false\";\nAcquire::Retries \"5\";\nAcquire::http::Pipeline-Depth \"0\";\nAcquire::http::No-Cache \"true\";\n" > /etc/apt/apt.conf.d/99builder
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential binutils ca-certificates >/dev/null
    bash /luajit-scripts/compile_luajit.sh "/in/'"$LUAJIT_TARBALL"'" /tmp/prefix
    cp -L /tmp/prefix/lib/libluajit-5.1.so.2 /out/libluajit-5.1.so.2
    cp /tmp/prefix/share/doc/luajit/COPYRIGHT /out/COPYRIGHT
  ' >&2 || fail "LuaJIT container build failed"

"$HERE/verify_luajit.sh" "$STAGE/out/libluajit-5.1.so.2" || fail "built library failed verification"
[ -s "$STAGE/out/COPYRIGHT" ] || fail "built COPYRIGHT is missing or empty"
# Install: COPYRIGHT first, library last, so the cache-hit test is atomic.
mv -f "$STAGE/out/COPYRIGHT" "$OUT_DIR/COPYRIGHT"
mv -f "$STAGE/out/libluajit-5.1.so.2" "$OUT"
say "built $OUT"
echo "$OUT"

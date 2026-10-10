#!/usr/bin/env bash
# Builds the aarch64 (arm64) Linux AppImage.
#
# scripts/build.sh's `linux` target only produces x86_64: it unpacks LÖVE's
# official x86_64 AppImage and re-fuses it, and no aarch64 equivalent is
# published. This script compiles LÖVE 11.5 from the official linux-src
# tarball inside a Debian bullseye arm64 container and fuses game.love into a
# type-2 AppImage, so one artifact covers Raspberry Pi OS, Armbian, Ubuntu
# arm64 and the aarch64 handhelds.
#
# Usage:
#   scripts/build_linux_arm64.sh [--version X.Y.Z] [--game-love PATH]
#                                [--rebuild-image] [--clean-cache]
#
# Output:
#   dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage
#   dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage.sha256
#
# Requirements: docker or podman on an aarch64 host (a Raspberry Pi 5, an
# ubuntu-24.04-arm runner or Apple Silicon Docker all work). Nothing is
# cross-compiled and no qemu emulation is involved.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/linux-arm64/common.sh"

HERE="$ROOT/.bazinga"
CACHE="$HERE/cache/linux-arm64"
WORK="$HERE/work/linux-arm64"
DIST="$ROOT/dist/linux-arm64"

VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
GAME_LOVE=""
REBUILD_IMAGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift ;;
    --game-love) GAME_LOVE="${2:?--game-love needs a path}"; shift ;;
    --rebuild-image) REBUILD_IMAGE=1 ;;
    --clean-cache) rm -rf "$CACHE" ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift
done

# --------------------------------------------------------------- host checks
# aarch64 only. The container is arch-native; running it under qemu-user on an
# x86_64 host "works" but takes hours and has produced miscompiled LuaJIT
# before, so refuse rather than hand back a build nobody can trust.
host_arch="$(uname -m)"
case "$host_arch" in
  aarch64|arm64) ;;
  *) fail "this build must run on an aarch64 host (found: $host_arch).
   Use a Raspberry Pi 5 / arm64 VM / Apple Silicon, or the ubuntu-24.04-arm CI runner." ;;
esac

RUNTIME="$(container_runtime)" || fail_need_container
say "container runtime: $RUNTIME"

mkdir -p "$CACHE" "$WORK" "$DIST"

# --------------------------------------------------------------- game.love
# Shared packer, same include/exclude set and the same verification gates as
# every other platform, so this artifact can never drift from the desktop one.
if [ -n "$GAME_LOVE" ]; then
  [ -f "$GAME_LOVE" ] || fail "--game-love: no such file: $GAME_LOVE"
  say "using prebuilt payload: $GAME_LOVE"
else
  GAME_LOVE="$WORK/game.love"
  "$ROOT/scripts/pack_love.sh" \
    --output "$GAME_LOVE" \
    --listing "$WORK/love-listing.txt" \
    --version "$VERSION"
fi

# --------------------------------------------------------------- icon
# One source of truth for every platform's launcher icon (scripts/build.sh
# resizes the same file with sips on macOS). Pillow is already a project
# dependency via tools/build_data.py; without it, ship the 1024px original
# rather than failing the build over an icon.
IN_DIR="$WORK/in"
rm -rf "$IN_DIR"; mkdir -p "$IN_DIR"
ICON_SRC="$ROOT/assets/logo/gen1recomp_cover.png"
[ -f "$ICON_SRC" ] || fail "missing icon source: $ICON_SRC"
if ! python3 - "$ICON_SRC" "$IN_DIR/icon.png" <<'PY' 2>/dev/null
import sys
from PIL import Image
with Image.open(sys.argv[1]) as image:
    image.convert("RGBA").resize((512, 512), Image.LANCZOS).save(sys.argv[2])
PY
then
  warn "Pillow not available, shipping the unresized icon"
  cp "$ICON_SRC" "$IN_DIR/icon.png"
fi
cp "$GAME_LOVE" "$IN_DIR/game.love"

BRIDGE_LIB="liblibrashader_bridge.so"
BRIDGE_SRC="${SHADERFX_BRIDGE_LINUX_ARM64:-}"
if [ -z "$BRIDGE_SRC" ] && [ -f "$ROOT/dist/native/linux-arm64/$BRIDGE_LIB" ]; then
  BRIDGE_SRC="$ROOT/dist/native/linux-arm64/$BRIDGE_LIB"
fi
rm -f "$IN_DIR/$BRIDGE_LIB"
if [ -n "$BRIDGE_SRC" ] && [ -f "$BRIDGE_SRC" ]; then
  cp "$BRIDGE_SRC" "$IN_DIR/$BRIDGE_LIB"
  say "staged $BRIDGE_LIB for SHADER FX preset conversion"
elif [ "${SHADERFX_BRIDGE_REQUIRED:-}" = "1" ]; then
  fail "$BRIDGE_LIB not found: set SHADERFX_BRIDGE_LINUX_ARM64 or stage it at dist/native/linux-arm64/$BRIDGE_LIB"
else
  warn "$BRIDGE_LIB not found: this build can run converted presets but not CONVERT new ones"
fi

# --------------------------------------------------------------- downloads
# Fetched on the host and checksum-pinned here so the container never needs
# network access and every input is verified in exactly one place.
download_pinned "$LOVE_SRC_URL" "$CACHE/$LOVE_SRC_TARBALL" "$LOVE_SRC_SHA256"
download_pinned "$SDL2_URL" "$CACHE/$SDL2_TARBALL" "$SDL2_SHA256"
download_pinned "$OPENAL_URL" "$CACHE/$OPENAL_TARBALL" "$OPENAL_SHA256"
download_pinned "$THEORA_URL" "$CACHE/$THEORA_TARBALL" "$THEORA_SHA256"
download_pinned "$OGG_URL" "$CACHE/$OGG_TARBALL" "$OGG_SHA256"
download_pinned "$VORBIS_URL" "$CACHE/$VORBIS_TARBALL" "$VORBIS_SHA256"
download_pinned "$MPG123_URL" "$CACHE/$MPG123_TARBALL" "$MPG123_SHA256"
download_pinned "$LUAJIT_URL" "$CACHE/$LUAJIT_TARBALL" "$LUAJIT_SHA256"
download_pinned "$APPIMAGE_RUNTIME_URL" "$CACHE/$APPIMAGE_RUNTIME_NAME" \
  "$APPIMAGE_RUNTIME_SHA256"

# --------------------------------------------------------------- builder image
if [ "$REBUILD_IMAGE" = 1 ] || ! "$RUNTIME" image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
  say "building $BUILDER_IMAGE ($BUILDER_BASE_IMAGE)"
  "$RUNTIME" build -t "$BUILDER_IMAGE" \
    -f "$ROOT/scripts/linux-arm64/Dockerfile" "$ROOT/scripts/linux-arm64" \
    || fail "failed to build the $BUILDER_BASE_IMAGE builder image"
fi

# --------------------------------------------------------------- build
OUT_DIR="$WORK/out"
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"

# --user keeps the AppImage owned by the invoking user instead of root; podman
# maps root in the container to the host user already, so only docker needs it.
user_args=()
if [ "$RUNTIME" = "docker" ]; then
  user_args=(--user "$(id -u):$(id -g)")
fi

say "compiling and packaging inside $BUILDER_BASE_IMAGE"
"$RUNTIME" run --rm ${user_args[@]+"${user_args[@]}"} \
  -e LOVE_VERSION="$LOVE_VERSION" \
  -e SDL2_VERSION="$SDL2_VERSION" \
  -e SDL2_TARBALL="$SDL2_TARBALL" \
  -e OPENAL_VERSION="$OPENAL_VERSION" \
  -e OPENAL_TARBALL="$OPENAL_TARBALL" \
  -e THEORA_VERSION="$THEORA_VERSION" \
  -e THEORA_TARBALL="$THEORA_TARBALL" \
  -e OGG_VERSION="$OGG_VERSION" \
  -e OGG_TARBALL="$OGG_TARBALL" \
  -e VORBIS_VERSION="$VORBIS_VERSION" \
  -e VORBIS_TARBALL="$VORBIS_TARBALL" \
  -e MPG123_VERSION="$MPG123_VERSION" \
  -e MPG123_TARBALL="$MPG123_TARBALL" \
  -e LUAJIT_COMMIT="$LUAJIT_COMMIT" \
  -e LUAJIT_TARBALL="$LUAJIT_TARBALL" \
  -e LUAJIT_VERSION_STRING="$LUAJIT_VERSION_STRING" \
  -e LUAJIT_MAX_GLIBC="$LUAJIT_MAX_GLIBC" \
  -e BUILDER_HASH="$BUILDER_HASH" \
  -e APP_NAME="$APP_NAME" \
  -e VERSION="$VERSION" \
  -v "$CACHE:/cache" \
  -v "$IN_DIR:/in:ro" \
  -v "$OUT_DIR:/out" \
  -v "$ROOT/scripts/linux-arm64:/scripts:ro" \
  -v "$ROOT/scripts/luajit:/luajit-scripts:ro" \
  "$BUILDER_IMAGE" bash /scripts/build_appimage.sh

# --------------------------------------------------------------- publish
built="$OUT_DIR/$APP_NAME-$VERSION-linux-arm64.AppImage"
[ -f "$built" ] || fail "container produced no AppImage at $built"

# The runtime is a static-pie ELF and the payload starts where its section
# headers end; a truncated cat would still be "a file", so prove both halves
# survived before shipping.
head -c 4 "$built" | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' \
  || fail "built AppImage is not an ELF"
e_shoff=$(od -An -j40 -N8 -tu8 "$built" | tr -d ' ')
e_shentsize=$(od -An -j58 -N2 -tu2 "$built" | tr -d ' ')
e_shnum=$(od -An -j60 -N2 -tu2 "$built" | tr -d ' ')
sfs_offset=$((e_shoff + e_shentsize * e_shnum))
[ "$(dd if="$built" bs=1 skip="$sfs_offset" count=4 2>/dev/null)" = "hsqs" ] \
  || fail "no squashfs payload at offset $sfs_offset (runtime/payload fusion failed)"

out="$DIST/$(basename "$built")"
rm -f "$out" "$out.sha256"
mv "$built" "$out"
chmod +x "$out"
printf '%s  %s\n' "$(sha256_file "$out")" "$(basename "$out")" > "$out.sha256"

say "Linux arm64 build: $out ($(du -h "$out" | cut -f1))"
say "sha256: $(cut -d' ' -f1 "$out.sha256")"

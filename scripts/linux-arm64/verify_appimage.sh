#!/usr/bin/env bash
# Verifies a built arm64 AppImage is self-contained and bullseye-compatible.
# Usage: scripts/linux-arm64/verify_appimage.sh <AppImage>

set -euo pipefail

image="${1:?usage: verify_appimage.sh <AppImage>}"
[ -f "$image" ] || { echo "::error::no such AppImage: $image"; exit 1; }
image="$(cd "$(dirname "$image")" && pwd)/$(basename "$image")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

# --appimage-extract needs no FUSE, so this works on a runner
# without /dev/fuse and still exercises the real payload.
"$image" --appimage-extract >/dev/null
for required in AppRun bin/love game.love lib/liblove-11.5.so; do
  [ -e "squashfs-root/$required" ] \
    || { echo "::error::AppImage is missing $required"; exit 1; }
done

# Every bundled object must resolve once AppRun's LD_LIBRARY_PATH is
# applied; an unresolved soname here is a user-visible launch crash.
#
# This runs on a HEADLESS runner on purpose, and that is the point.
# The first version of this build bundled Debian's SDL2, which
# hard-links libpulse/libasound/libX11/libwayland, so it only ever
# started on a full desktop -- a bare runner is what exposed it.
missing="$(LD_LIBRARY_PATH="$PWD/squashfs-root/lib" \
  ldd squashfs-root/bin/love squashfs-root/lib/*.so* 2>/dev/null \
  | grep 'not found' || true)"
[ -z "$missing" ] || { echo "::error::unresolved deps:"; echo "$missing"; exit 1; }

# Nothing may hard-link a driver, session or audio-stack library:
# those must be reached through dlopen so the AppImage runs on a box
# with only ALSA, only Wayland, or only KMSDRM.
linked="$(for f in squashfs-root/bin/love squashfs-root/lib/*.so*; do
  objdump -p "$f" 2>/dev/null | awk '/NEEDED/{print $2}'
done | sort -u | grep -E '^lib(pulse|asound|X11|wayland|GL|EGL|drm|gbm|xcb|cairo|sndio|dbus)' || true)"
[ -z "$linked" ] \
  || { echo "::error::these must be dlopened, not linked:"; echo "$linked"; exit 1; }

# The whole point of compiling on bullseye. If a future change moves
# the builder to a newer base, the glibc floor silently rises and
# every user on an older distro gets "GLIBC_2.xx not found" -- catch
# it here instead of in a release.
floor="$(objdump -T squashfs-root/bin/love squashfs-root/lib/*.so* 2>/dev/null \
  | grep -o 'GLIBC_[0-9.]*' | sort -V | tail -1)"
echo "highest required glibc symbol version: $floor"
[ -n "$floor" ] \
  || { echo "::error::found no versioned glibc symbols -- objdump read nothing"; exit 1; }
highest="$(printf '%s\n' "$floor" "GLIBC_2.31" | sort -V | tail -1)"
[ "$highest" = "GLIBC_2.31" ] \
  || { echo "::error::AppImage requires $floor, above the bullseye 2.31 floor"; exit 1; }

echo "AppImage verified: $image"

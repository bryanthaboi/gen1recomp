#!/usr/bin/env bash
# Verifies a built arm64 AppImage is self-contained and bullseye-compatible.
# Usage: scripts/linux-arm64/verify_appimage.sh <AppImage>

set -euo pipefail

image="${1:?usage: verify_appimage.sh <AppImage>}"
[ -f "$image" ] || { echo "::error::no such AppImage: $image"; exit 1; }
image="$(cd "$(dirname "$image")" && pwd)/$(basename "$image")"

verify_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../luajit" && pwd)"

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

# The pinned LuaJIT, not bullseye's 2.1.0-beta3 (segfaults with the JIT on).
[ -f "squashfs-root/lib/libluajit-5.1.so.2" ] \
  || { echo "::error::AppImage is missing lib/libluajit-5.1.so.2"; exit 1; }
bash "$verify_dir/verify_luajit.sh" squashfs-root/lib/libluajit-5.1.so.2 \
  || { echo "::error::bundled LuaJIT is not the pinned build"; exit 1; }
[ -s "squashfs-root/LuaJIT-COPYRIGHT" ] \
  || { echo "::error::AppImage is missing LuaJIT-COPYRIGHT"; exit 1; }

bridge="squashfs-root/liblibrashader_bridge.so"
if [ "${SHADERFX_BRIDGE_REQUIRED:-}" = "1" ] && [ ! -e "$bridge" ]; then
  echo "::error::AppImage is missing liblibrashader_bridge.so"
  exit 1
fi

# Discovered, not enumerated: bin/love and lib/*.so* miss anything native at
# the AppDir root, which is where ShaderFX's bridge sits and where the next
# root-level library would land too.
scan=()
while IFS= read -r f; do
  scan+=("$f")
done < <(find squashfs-root -type f -exec sh -c \
  'head -c4 "$1" | od -An -tx1 | tr -d " \n" | grep -q "^7f454c46$"' _ {} \; -print | sort)
[ "${#scan[@]}" -gt 0 ] || { echo "::error::found no ELF objects in the AppDir"; exit 1; }
echo "scanning ${#scan[@]} ELF objects: ${scan[*]#squashfs-root/}"

# Every bundled object must resolve once AppRun's LD_LIBRARY_PATH is
# applied; an unresolved soname here is a user-visible launch crash.
#
# This runs on a HEADLESS runner on purpose, and that is the point.
# The first version of this build bundled Debian's SDL2, which
# hard-links libpulse/libasound/libX11/libwayland, so it only ever
# started on a full desktop -- a bare runner is what exposed it.
missing="$(LD_LIBRARY_PATH="$PWD/squashfs-root/lib" \
  ldd "${scan[@]}" 2>/dev/null \
  | grep 'not found' || true)"
[ -z "$missing" ] || { echo "::error::unresolved deps:"; echo "$missing"; exit 1; }

# Nothing may hard-link a driver, session or audio-stack library:
# those must be reached through dlopen so the AppImage runs on a box
# with only ALSA, only Wayland, or only KMSDRM.
linked="$(for f in "${scan[@]}"; do
  objdump -p "$f" 2>/dev/null | awk '/NEEDED/{print $2}'
done | sort -u | grep -E '^lib(pulse|asound|X11|wayland|GL|EGL|drm|gbm|xcb|cairo|sndio|dbus)' || true)"
[ -z "$linked" ] \
  || { echo "::error::these must be dlopened, not linked:"; echo "$linked"; exit 1; }

# The whole point of compiling on bullseye. If a future change moves
# the builder to a newer base, the glibc floor silently rises and
# every user on an older distro gets "GLIBC_2.xx not found" -- catch
# it here instead of in a release.
floor="$(objdump -T "${scan[@]}" 2>/dev/null \
  | grep -o 'GLIBC_[0-9.]*' | sort -V | tail -1)"
echo "highest required glibc symbol version: $floor"
[ -n "$floor" ] \
  || { echo "::error::found no versioned glibc symbols -- objdump read nothing"; exit 1; }
highest="$(printf '%s\n' "$floor" "GLIBC_2.31" | sort -V | tail -1)"
[ "$highest" = "GLIBC_2.31" ] \
  || { echo "::error::AppImage requires $floor, above the bullseye 2.31 floor"; exit 1; }

# The floor grep proves symbol versions; an actual dlopen additionally proves
# relocations and constructors. Native arch only, so it is skipped elsewhere.
if [ -e "$bridge" ] && [ "$(uname -m)" = "aarch64" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "import ctypes,sys; ctypes.CDLL(sys.argv[1])" "$PWD/$bridge" \
    || { echo "::error::liblibrashader_bridge.so failed to dlopen"; exit 1; }
  echo "librashader bridge dlopens cleanly"
fi

echo "AppImage verified: $image"

#!/usr/bin/env bash
# Shared helpers and pins for the aarch64 Linux AppImage build.
# Source from other scripts:  . "$(dirname "$0")/common.sh"

# shellcheck disable=SC2034
if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export ROOT

# ---------------------------------------------------------------- pins
# LÖVE ships no aarch64 binary of any kind -- the 11.5 release has win32/win64,
# macOS, Android, iOS and an x86_64 AppImage, and that is the whole list. So
# this port compiles the official linux-src tarball instead of unpacking a
# prebuilt image the way scripts/build.sh does for x86_64.
LOVE_VERSION="11.5"
LOVE_SRC_TARBALL="love-$LOVE_VERSION-linux-src.tar.gz"
LOVE_SRC_URL="https://github.com/love2d/love/releases/download/$LOVE_VERSION/$LOVE_SRC_TARBALL"
LOVE_SRC_SHA256="066e0843f71aa9fd28b8eaf27d41abb74bfaef7556153ac2e3cf08eafc874c39"

# SDL2 is built from source rather than taken from bullseye, and this is a
# correctness requirement, not a version preference. Debian's libSDL2 lists
# libpulse, libasound, libX11 and libwayland-client as DT_NEEDED -- hard links
# resolved by the loader at startup -- so an AppImage bundling it refuses to
# launch unless the host has ALL FOUR installed. That is wrong for an artifact
# whose whole job is to run on arbitrary arm64 systems: an ALSA-only handheld
# or a minimal Wayland box would die before main(). Built from source, SDL
# defaults to dlopening every audio and video backend (--enable-*-shared), so
# it loads whichever the host actually has and degrades gracefully.
# The newer version is a bonus: 2.30 has a far better controller database and
# real KMSDRM support, both of which matter on Pi-class and handheld hardware.
SDL2_VERSION="2.30.12"
SDL2_TARBALL="SDL2-$SDL2_VERSION.tar.gz"
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/$SDL2_TARBALL"
SDL2_SHA256="ac356ea55e8b9dd0b2d1fa27da40ef7e238267ccf9324704850d5d47375b48ea"

# libtheora likewise. Debian's libtheoradec.so.1 is linked against libcairo --
# a packaging artifact, since a video decoder has no business drawing vector
# graphics -- and cairo drags in libX11, libxcb, libfontconfig and libfreetype
# as hard dependencies. LOVE needs theora for love.video, so that link would
# put the entire X11 and font stack on the critical path at startup, and it is
# what caused the FT_Get_Transform crash this build hit on a trixie host.
# Upstream's tarball with --disable-examples produces a libtheoradec that
# needs only libogg.
THEORA_VERSION="1.1.1"
THEORA_TARBALL="libtheora-$THEORA_VERSION.tar.bz2"
THEORA_URL="https://downloads.xiph.org/releases/theora/$THEORA_TARBALL"
THEORA_SHA256="b6ae1ee2fa3d42ac489287d3ec34c5885730b1296f0801ae577a35193d3affbc"

# OpenAL for the same reason as SDL2, one level down. Debian's libopenal is
# openal-soft built with the sndio backend enabled, so it hard-links
# libsndio, which itself hard-links libasound -- reintroducing exactly the
# mandatory-ALSA dependency the SDL2 source build exists to remove. Upstream
# openal-soft dlopens its backends, so building it here leaves the shipped
# library with no audio-stack dependency at all.
OPENAL_VERSION="1.23.1"
OPENAL_TARBALL="openal-soft-$OPENAL_VERSION.tar.gz"
OPENAL_URL="https://github.com/kcat/openal-soft/archive/refs/tags/$OPENAL_VERSION.tar.gz"
OPENAL_SHA256="dfddf3a1f61059853c625b7bb03de8433b455f2f79f89548cbcbd5edca3d4a4a"

# The audio codecs are built from source for a third, different reason: SONAME
# collision with the host's audio stack.
#
# OpenAL dlopens ALSA, ALSA's config loads its PulseAudio hook plugin, and that
# plugin pulls the HOST's libsndfile into our process. libsndfile links
# libogg, libvorbis and libmpg123 -- the same three we bundle. The loader
# resolves a SONAME once per process, so the host's libsndfile binds to OUR
# copies, and a bullseye libmpg123 has no mpg123_info2 (added in 1.32):
#
#   openal -> libasound -> libasound_module_conf_pulse -> libsndfile (host)
#                                                            `-> mpg123_info2 -> libmpg123 (ours, bullseye)
#
# which failed to relocate and left the game with no audio device at all.
# Not bundling them instead would make libogg/libvorbis/libmpg123 mandatory
# host packages; building them current means our copies satisfy the host's
# libsndfile rather than starving it. libvorbisfile ships in the vorbis
# tarball.
OGG_VERSION="1.3.5"
OGG_TARBALL="libogg-$OGG_VERSION.tar.gz"
OGG_URL="https://downloads.xiph.org/releases/ogg/$OGG_TARBALL"
OGG_SHA256="0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664"

VORBIS_VERSION="1.3.7"
VORBIS_TARBALL="libvorbis-$VORBIS_VERSION.tar.gz"
VORBIS_URL="https://downloads.xiph.org/releases/vorbis/$VORBIS_TARBALL"
VORBIS_SHA256="0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab"

MPG123_VERSION="1.32.10"
MPG123_TARBALL="mpg123-$MPG123_VERSION.tar.bz2"
MPG123_URL="https://www.mpg123.de/download/$MPG123_TARBALL"
MPG123_SHA256="87b2c17fe0c979d3ef38eeceff6362b35b28ac8589fbf1854b5be75c9ab6557c"

# AppImage type-2 runtime: the ~900 KB static-pie ELF that gets prepended to
# the squashfs payload. Pinned to a dated tag, never "continuous", so a
# rebuild months from now produces the same bytes.
APPIMAGE_RUNTIME_TAG="20251108"
APPIMAGE_RUNTIME_NAME="runtime-aarch64"
APPIMAGE_RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/$APPIMAGE_RUNTIME_TAG/$APPIMAGE_RUNTIME_NAME"
APPIMAGE_RUNTIME_SHA256="00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444"

# Debian bullseye (glibc 2.31) is the compile environment, NOT a statement
# about where the artifact runs. glibc is backward compatible but not forward
# compatible, so linking against the oldest glibc we support is what lets one
# AppImage cover Raspberry Pi OS bullseye/bookworm/trixie, Ubuntu 20.04+ and
# the aarch64 handheld distros. Building on a newer base would silently
# restrict the artifact to that base and newer.
BUILDER_BASE_IMAGE="debian:bullseye"
BUILDER_IMAGE="${GEN1_LINUX_ARM64_IMAGE:-gen1recomp-linux-arm64-builder}"

APP_NAME="gen1recomp"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Print SHA-256 hex digest of PATH. Prefers sha256sum, falls back to shasum
# (same order-agnostic pair scripts/switch/common.sh uses).
sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "need sha256sum or shasum (install coreutils)"
  fi
}

# download_pinned URL DEST EXPECTED_SHA256
#
# A cache hit is only trusted if it still hashes to the pin: a download
# truncated by a network drop would otherwise be reused forever, which is the
# same trap scripts/build.sh guards for the win64 zip and the x86_64 AppImage.
download_pinned() {
  local url="$1" dest="$2" want="$3" got=""
  if [ -f "$dest" ]; then
    got="$(sha256_file "$dest")"
    if [ "$got" = "$want" ]; then
      return 0
    fi
    warn "cached $(basename "$dest") has the wrong digest, re-downloading"
    rm -f "$dest"
  fi
  say "downloading $(basename "$dest")"
  # --retry-all-errors because plain --retry skips TLS handshake failures,
  # which is how xiph.org drops these tarballs; the pin below still gates it.
  curl -fL --retry 5 --retry-delay 2 --retry-all-errors --progress-bar \
    "$url" -o "$dest.tmp" || fail "download failed: $url"
  got="$(sha256_file "$dest.tmp")"
  [ "$got" = "$want" ] || fail "$(printf '%s\n  expected %s\n  got      %s' \
    "checksum mismatch for $(basename "$dest")" "$want" "$got")"
  mv "$dest.tmp" "$dest"
}

# Echo the container runtime to use: docker, else podman.
container_runtime() {
  if [ -n "${GEN1_CONTAINER_RUNTIME:-}" ]; then
    printf '%s' "$GEN1_CONTAINER_RUNTIME"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf 'docker'
  elif command -v podman >/dev/null 2>&1; then
    printf 'podman'
  else
    return 1
  fi
}

fail_need_container() {
  fail "$(cat <<'EOF'
the aarch64 AppImage is compiled inside a Debian bullseye container and needs
docker or podman on an aarch64 host.

  Raspberry Pi OS / Debian / Ubuntu:  sudo apt install docker.io && sudo usermod -aG docker "$USER"
  Fedora / Asahi:                     sudo dnf install podman
  macOS (Apple Silicon):              brew install --cask docker

Override the runtime with GEN1_CONTAINER_RUNTIME=podman.
See docs/linux-arm64-build.md.
EOF
)"
}

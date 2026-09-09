# Build environment for the aarch64 Linux AppImage.
#
# Debian bullseye on purpose: it ships glibc 2.31, the oldest runtime we
# promise to support. Everything linked here therefore runs on bullseye and
# every later distro (glibc is backward compatible, not forward), which is
# what makes the resulting AppImage portable across Raspberry Pi OS, Armbian,
# Ubuntu 20.04+, and the aarch64 handheld distros.
#
# This image is arch-native: build it on an aarch64 host (Raspberry Pi 5,
# ubuntu-24.04-arm runner, Apple Silicon Docker) — no qemu emulation.
FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

# build-essential/autoconf: LÖVE 11.5's linux-src tarball is autotools.
# squashfs-tools: packs the AppDir into the AppImage payload.
#
# Note what is deliberately ABSENT: libsdl2-dev, libtheora-dev and
# libopenal-dev. All three are built from source instead (see common.sh for
# why), and having Debian's copies installed would let pkg-config hand LÖVE's
# configure the system ones and silently undo it.
#
# The remaining lib*-dev set is LÖVE's optional-module surface. A missing one
# does not fail configure, it silently drops a module (love.sound decoders,
# love.font, love.video), so they are pinned here deliberately and asserted
# after the build.
#
# The X11/Wayland/audio -dev packages are here for SDL2's *build*, not for
# runtime linkage: SDL detects each backend at compile time and then dlopens
# it, so these headers decide which backends exist at all while adding no
# DT_NEEDED entry to the shipped library.
RUN printf 'deb http://snapshot.debian.org/archive/debian/20260831T000000Z bullseye main\ndeb http://snapshot.debian.org/archive/debian-security/20260831T000000Z bullseye-security main\n' > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config autoconf automake libtool cmake \
      ca-certificates curl file xz-utils bzip2 zip unzip squashfs-tools \
      libogg-dev libvorbis-dev \
      libmodplug-dev libmpg123-dev libfreetype6-dev libluajit-5.1-dev \
      zlib1g-dev libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
      libasound2-dev libpulse-dev libudev-dev libdbus-1-dev \
      libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev \
      libxinerama-dev libxss-dev libxkbcommon-dev \
      libwayland-dev wayland-protocols libdrm-dev libgbm-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work

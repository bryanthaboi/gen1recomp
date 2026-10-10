#!/usr/bin/env bash
# Pinned LuaJIT for the aarch64 Linux builds (PortMaster zips, AppImage).
# Source this file; it only sets variables and has no side effects.
#
# Why: PortMaster's LOVE 11.5 runtime ships LuaJIT 2.1.0-beta3 (2017), which
# segfaulted 3/3 runs with the JIT on (TrimUI Brick). This pinned v2.1-branch
# commit ran a 26-minute JIT-on soak without a crash. See docs/linux-arm-sbc.md.
#
# The commit's .relver is already expanded, so the built library contains the
# string "LuaJIT 2.1.1788856981" (beta3 contains "LuaJIT 2.1.0-beta3").

# shellcheck disable=SC2034
LUAJIT_COMMIT="c6ffc141a8762b41703f9287d63d93622a13dd8f"
LUAJIT_URL="https://github.com/LuaJIT/LuaJIT/archive/$LUAJIT_COMMIT.tar.gz"
LUAJIT_SHA256="6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457"
LUAJIT_TARBALL="LuaJIT-$LUAJIT_COMMIT.tar.gz"
LUAJIT_VERSION_STRING="LuaJIT 2.1.1788856981"
# Built on debian:bullseye (glibc 2.31); the library must not need newer.
# The standalone build (build_luajit.sh) pins the image by digest so a re-tag
# cannot silently change the toolchain; the digest is part of its cache key.
# To re-pin: `docker buildx imagetools inspect debian:bullseye` -> the top-level
# "Digest:" line; put it here AND in the FROM line of
# scripts/linux-arm64/Dockerfile (the selftest checks the two are equal).
LUAJIT_BUILD_IMAGE="debian:bullseye@sha256:6f519a81440354a85eb592c5f32109ab80605f6b892455983a6f618bf87fabe9"
LUAJIT_MAX_GLIBC="2.31"
# apt sources for the build container (bullseye is EOL; security comes from a
# dated snapshot). Newline-separated; must match scripts/linux-arm64/Dockerfile
# so both LuaJIT builds see the same package state.
LUAJIT_APT_SOURCES="deb http://archive.debian.org/debian bullseye main
deb http://archive.debian.org/debian bullseye-updates main
deb http://snapshot.debian.org/archive/debian-security/20260831T000000Z bullseye-security main"

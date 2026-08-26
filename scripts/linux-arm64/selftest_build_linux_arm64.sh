#!/usr/bin/env bash
# Offline checks for the aarch64 Linux AppImage build.
#
# Runs anywhere -- no container, no network, no aarch64 host -- so PR CI can
# gate the parts of this build that do not need three minutes of compiling.
# The real build is exercised separately by the linux-arm64-build job.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}
require_command unzip
require_command zip

say "checking shell entry points"
bash -n "$ROOT/scripts/build_linux_arm64.sh" "$SCRIPT_DIR"/*.sh
help="$(bash "$ROOT/scripts/build_linux_arm64.sh" --help)"
printf '%s' "$help" | grep -q -- '--version X.Y.Z' \
  || fail "build help does not document --version"
printf '%s' "$help" | grep -q 'linux-arm64\.AppImage' \
  || fail "build help does not name the artifact it produces"

say "checking the host-architecture guard"
# The guard is what stops someone from kicking off a qemu-emulated build that
# takes hours and miscompiles LuaJIT. Prove it fires rather than trusting it.
# The guard is what stops someone from kicking off a qemu-emulated build that
# takes hours and has miscompiled LuaJIT before. Prove it fires by shadowing
# uname, rather than trusting the branch is reachable.
fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-fake-uname.XXXXXX")"
printf '#!/bin/sh\necho x86_64\n' > "$fake_bin/uname"
chmod +x "$fake_bin/uname"
guard_out="$(PATH="$fake_bin:$PATH" \
  bash "$ROOT/scripts/build_linux_arm64.sh" --version 0.0.0 2>&1 || true)"
rm -rf "$fake_bin"
printf '%s' "$guard_out" | grep -q 'aarch64 host' \
  || fail "build script does not refuse to run on a non-aarch64 host"

say "checking pinned inputs"
# Pins must be real digests, and the AppImage runtime must come from a dated
# tag: "continuous" is a moving target and would make rebuilds unreproducible.
for pin_name in LOVE_SRC_SHA256 SDL2_SHA256 OPENAL_SHA256 THEORA_SHA256 \
                OGG_SHA256 VORBIS_SHA256 MPG123_SHA256 APPIMAGE_RUNTIME_SHA256; do
  pin_value="${!pin_name}"
  printf '%s' "$pin_value" | grep -Eq '^[0-9a-f]{64}$' \
    || fail "$pin_name is not a sha256 digest: $pin_value"
done
if printf '%s' "$APPIMAGE_RUNTIME_URL" | grep -q '/continuous/'; then
  fail "the AppImage runtime is pinned to the moving 'continuous' tag"
fi
printf '%s' "$APPIMAGE_RUNTIME_URL" | grep -q "/$APPIMAGE_RUNTIME_TAG/$APPIMAGE_RUNTIME_NAME\$" \
  || fail "APPIMAGE_RUNTIME_URL does not match the pinned tag/asset"
printf '%s' "$LOVE_SRC_URL" | grep -q "/$LOVE_VERSION/$LOVE_SRC_TARBALL\$" \
  || fail "LOVE_SRC_URL does not match LOVE_VERSION/LOVE_SRC_TARBALL"

say "checking the builder base image"
# Building on anything newer than bullseye silently raises the glibc floor and
# strands every user on an older distro, with no symptom until they run it.
grep -q '^FROM debian:bullseye$' "$SCRIPT_DIR/Dockerfile" \
  || fail "Dockerfile no longer builds on debian:bullseye (that raises the glibc floor)"
[ "$BUILDER_BASE_IMAGE" = "debian:bullseye" ] \
  || fail "BUILDER_BASE_IMAGE disagrees with the Dockerfile"

say "checking the dependency exclude list"
# Extract the live regex from the build script and classify known sonames
# through it, so a future edit cannot quietly start bundling glibc or stop
# bundling the engine's own dependencies.
EXCLUDE_RE="$(
  # shellcheck disable=SC1090
  grep -m1 "^EXCLUDE_RE=" "$SCRIPT_DIR/build_appimage.sh" | sed "s/^EXCLUDE_RE='//; s/'\$//"
)"
[ -n "$EXCLUDE_RE" ] || fail "could not read EXCLUDE_RE out of build_appimage.sh"

must_exclude=(libc.so.6 ld-linux-aarch64.so.1 libstdc++.so.6 libgcc_s.so.1
              libGL.so.1 libEGL.so.1 libgbm.so.1 libdrm.so.2 libX11.so.6
              libwayland-client.so.0 libpulse.so.0 libasound.so.2
              libfreetype.so.6 libfontconfig.so.1 libpng16.so.16 libz.so.1)
must_bundle=(libSDL2-2.0.so.0 libopenal.so.1 libluajit-5.1.so.2 libmodplug.so.1
             libmpg123.so.0 libogg.so.0 libvorbis.so.0 libvorbisfile.so.3
             libtheoradec.so.1 liblove-11.5.so)

for soname in "${must_exclude[@]}"; do
  [[ "$soname" =~ $EXCLUDE_RE ]] \
    || fail "$soname must be host-provided but the exclude list would bundle it"
done
for soname in "${must_bundle[@]}"; do
  if [[ "$soname" =~ $EXCLUDE_RE ]]; then
    fail "$soname is an engine dependency but the exclude list drops it"
  fi
done

say "checking AppRun and the fusion contract"
# The AppImage must boot straight into the game. If AppRun ever loses --fused,
# users get vanilla LÖVE's "no game" screen instead, and nothing else catches
# that before someone downloads a release.
grep -qF -- '--fused "\$APPDIR/game.love"' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "AppRun no longer launches game.love with --fused"
grep -qF 'LD_LIBRARY_PATH="\$APPDIR/lib/' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "AppRun no longer puts the bundled lib directory on LD_LIBRARY_PATH"
grep -qF 'comp gzip -b 131072' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "squashfs payload is no longer gzip/128K (older type-2 runtimes cannot read it)"

say "checking the linked-module assertions"
# configure exits 0 when an optional -dev package is missing and just drops the
# module, so these assertions are the only thing standing between a missing
# build dependency and a release that cannot play sound.
for soname in libSDL2-2.0.so.0 libopenal.so.1 libfreetype.so.6 libmodplug.so.1 \
              libmpg123.so.0 libvorbisfile.so.3 libtheoradec.so.1; do
  grep -qF "$soname" "$SCRIPT_DIR/build_appimage.sh" \
    || fail "build_appimage.sh no longer asserts liblove links $soname"
done

say "checking the dlopen guarantees"
# SDL2, OpenAL and libtheora are compiled from source for correctness, not for
# a newer version number: Debian's builds hard-link libpulse/libasound/libX11/
# libwayland (SDL2), libsndio (OpenAL) and libcairo (libtheora), each of which
# turns an optional runtime capability into a mandatory startup dependency.
# If a future edit drops the source build and reaches for the -dev package
# again, the AppImage silently stops starting on lean systems.
for forbidden_pkg in libsdl2-dev libtheora-dev libopenal-dev; do
  if grep -qE "^ +.*\b$forbidden_pkg\b" "$SCRIPT_DIR/Dockerfile"; then
    fail "Dockerfile installs $forbidden_pkg; that library is built from source on purpose"
  fi
done
grep -qF -- '--enable-alsa-shared' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "SDL2 is no longer configured to dlopen its audio backends"
grep -qF -- '--enable-x11-shared' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "SDL2 is no longer configured to dlopen its video backends"
grep -qF 'ALSOFT_DLOPEN=ON' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "openal-soft is no longer configured to dlopen its backends"
grep -qF -- '--disable-examples' "$SCRIPT_DIR/build_appimage.sh" \
  || fail "libtheora is no longer built with --disable-examples (it regains the libcairo link)"

say "checking the host dependency contract"
# The shipped objects may require nothing from the host beyond glibc,
# libstdc++ and the font stack. Everything driver-, session- or audio-related
# has to be dlopened. This is the invariant a headless CI runner proved was
# broken the first time round.
HOST_ALLOWED_RE="$(
  grep -m1 "^HOST_ALLOWED_RE=" "$SCRIPT_DIR/build_appimage.sh" \
    | sed "s/^HOST_ALLOWED_RE='//; s/'\$//"
)"
[ -n "$HOST_ALLOWED_RE" ] || fail "could not read HOST_ALLOWED_RE out of build_appimage.sh"
for soname in libpulse.so.0 libasound.so.2 libX11.so.6 libwayland-client.so.0 \
              libGL.so.1 libcairo.so.2 libsndio.so.7.0 libdbus-1.so.3; do
  if [[ "$soname" =~ $HOST_ALLOWED_RE ]]; then
    fail "$soname is allowed as a hard host dependency; it must be dlopened"
  fi
done
for soname in libc.so.6 libstdc++.so.6 libfreetype.so.6 libz.so.1; do
  [[ "$soname" =~ $HOST_ALLOWED_RE ]] \
    || fail "$soname must be allowed as a host dependency but the contract rejects it"
done

say "checking the shared game.love payload"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-linux-arm64-selftest.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
"$ROOT/scripts/pack_love.sh" \
  --output "$temp_dir/game.love" \
  --listing "$temp_dir/love-listing.txt" \
  --version 1.2.3 \
  --dry-run >/dev/null
unzip -p "$temp_dir/game.love" src/core/Version.lua \
  | grep -Eq 'engine[[:space:]]*=[[:space:]]*"1\.2\.3"' \
  || fail "shared payload version was not stamped"
grep -qxF "tools/rom_manifest_gold.json" "$temp_dir/love-listing.txt" \
  || fail "shared payload is missing tools/rom_manifest_gold.json"
grep -qxF "tools/rom_manifest_silver.json" "$temp_dir/love-listing.txt" \
  || fail "shared payload is missing tools/rom_manifest_silver.json"
grep -qxF "tools/rom_manifest_crystal.json" "$temp_dir/love-listing.txt" \
  || fail "shared payload is missing tools/rom_manifest_crystal.json"

say "Linux arm64 self-test passed"

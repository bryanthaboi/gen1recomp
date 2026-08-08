#!/usr/bin/env bash
# Compiles LÖVE for aarch64 and fuses game.love into a self-contained
# AppImage. Runs INSIDE the Debian bullseye container from Dockerfile --
# scripts/build_linux_arm64.sh is the entry point on the host.
#
# Mounts the host provides:
#   /cache  pinned downloads + the compiled LÖVE prefix (persists between runs)
#   /in     read-only inputs: game.love, icon.png
#   /out    the finished AppImage lands here
#
# Environment:
#   LOVE_VERSION, APP_NAME, VERSION   passed through from the host script
#   JOBS                              make -j (defaults to nproc)

set -euo pipefail

LOVE_VERSION="${LOVE_VERSION:?}"
SDL2_VERSION="${SDL2_VERSION:?}"
SDL2_TARBALL="${SDL2_TARBALL:?}"
OPENAL_VERSION="${OPENAL_VERSION:?}"
OPENAL_TARBALL="${OPENAL_TARBALL:?}"
THEORA_VERSION="${THEORA_VERSION:?}"
THEORA_TARBALL="${THEORA_TARBALL:?}"
OGG_VERSION="${OGG_VERSION:?}"
OGG_TARBALL="${OGG_TARBALL:?}"
VORBIS_VERSION="${VORBIS_VERSION:?}"
VORBIS_TARBALL="${VORBIS_TARBALL:?}"
MPG123_VERSION="${MPG123_VERSION:?}"
MPG123_TARBALL="${MPG123_TARBALL:?}"
APP_NAME="${APP_NAME:?}"
VERSION="${VERSION:?}"
JOBS="${JOBS:-$(nproc)}"

CACHE="/cache"
IN="/in"
OUT="/out"
WORK="/tmp/build"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$WORK"

# --------------------------------------------------------------- prefix
# Everything we compile lands in one prefix, cached because the compiling is
# the only slow part (~5 min cold on a Pi 5) and is identical for every game
# version. The key includes every source version, so bumping any of them
# invalidates the cache instead of silently reusing a stale mix.
PREFIX="$CACHE/prefix-love$LOVE_VERSION-sdl$SDL2_VERSION-al$OPENAL_VERSION-theora$THEORA_VERSION-ogg$OGG_VERSION-vorbis$VORBIS_VERSION-mpg$MPG123_VERSION"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
# Our own libraries must win over the system ones during LÖVE's configure and
# link, or the whole point of building them is lost.
export LD_LIBRARY_PATH="$PREFIX/lib"

# ------------------------------------------------------ compile audio codecs
# Ordered by dependency: vorbis needs ogg, and theora needs ogg too. All three
# are small, plain autotools builds -- well under a minute each.
build_autotools() { # $1 = label  $2 = version  $3 = tarball  $4 = probe lib  $5.. = configure args
  local label="$1" version="$2" tarball="$3" probe="$4"; shift 4
  if [ -f "$PREFIX/lib/$probe" ]; then
    say "reusing cached $label $version"
    return 0
  fi
  say "compiling $label $version"
  local src="$WORK/$label-src"
  rm -rf "$src"; mkdir -p "$src"
  case "$tarball" in
    *.tar.bz2) tar -xjf "$CACHE/$tarball" -C "$src" --strip-components=1 ;;
    *)         tar -xzf "$CACHE/$tarball" -C "$src" --strip-components=1 ;;
  esac
  (
    cd "$src"
    # Several of these tarballs predate aarch64's entry in config.guess; the
    # distro's copies know about it, so refresh them or configure bails out
    # with "cannot guess build type".
    for helper in config.guess config.sub; do
      [ -f "$helper" ] && cp "/usr/share/misc/$helper" . 2>/dev/null
    done
    ./configure --prefix="$PREFIX" --disable-static "$@" >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
  )
}

build_autotools ogg "$OGG_VERSION" "$OGG_TARBALL" libogg.so.0
build_autotools vorbis "$VORBIS_VERSION" "$VORBIS_TARBALL" libvorbis.so.0
# mpg123's ports/ tree and the command-line player are irrelevant here; only
# libmpg123 gets linked, and --disable-modules keeps the output-backend
# plugins (and their dlopen of ALSA/pulse) out of the shipped library.
build_autotools mpg123 "$MPG123_VERSION" "$MPG123_TARBALL" libmpg123.so.0 \
  --disable-modules --with-audio=dummy --disable-lfs-alias

# The symbol that was missing when this was bullseye's copy. Assert it, so a
# version bump that quietly regresses below the host's expectations fails the
# build instead of silently killing audio again.
objdump -T "$PREFIX/lib/libmpg123.so.0" | grep -q 'mpg123_info2' \
  || fail "bundled libmpg123 lacks mpg123_info2; the host's libsndfile will fail to relocate"

# ------------------------------------------------------------ compile SDL2
# --enable-*-shared (the defaults, made explicit so a future SDL release
# cannot flip them under us) is the entire reason this is built from source:
# each backend is dlopened at runtime rather than becoming a DT_NEEDED entry,
# so the AppImage starts on a host with only ALSA, or only Wayland, or only
# KMSDRM, instead of demanding all of them at once the way Debian's build does.
if [ -f "$PREFIX/lib/libSDL2-2.0.so.0" ]; then
  say "reusing cached SDL2 $SDL2_VERSION"
else
  say "compiling SDL2 $SDL2_VERSION (jobs: $JOBS)"
  rm -rf "$WORK/sdl-src"; mkdir -p "$WORK/sdl-src"
  tar -xzf "$CACHE/$SDL2_TARBALL" -C "$WORK/sdl-src" --strip-components=1
  (
    cd "$WORK/sdl-src"
    ./configure --prefix="$PREFIX" --disable-static \
      --enable-alsa --enable-alsa-shared \
      --enable-pulseaudio --enable-pulseaudio-shared \
      --enable-video-x11 --enable-x11-shared \
      --enable-video-wayland --enable-wayland-shared \
      --enable-video-kmsdrm --enable-kmsdrm-shared \
      --enable-libudev --disable-sndio --disable-jack --disable-esd \
      --disable-arts --disable-nas --disable-oss >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
  )
fi

# Prove the dlopen intent actually took. If SDL ever hard-links an audio or
# video backend again, the AppImage silently regains a startup dependency on
# the host having that exact stack -- which is the bug this replaced.
sdl_lib="$PREFIX/lib/libSDL2-2.0.so.0"
[ -f "$sdl_lib" ] || fail "SDL2 build produced no libSDL2-2.0.so.0"
for forbidden in libpulse libasound libX11 libwayland libdrm libgbm libsndio; do
  if objdump -p "$sdl_lib" | grep -q "NEEDED.*$forbidden"; then
    fail "SDL2 hard-links $forbidden; it must dlopen its backends (--enable-*-shared)"
  fi
done

# ---------------------------------------------------- compile openal-soft
# ALSOFT_DLOPEN keeps the ALSA and PulseAudio backends behind dlopen, and
# sndio is switched off outright -- Debian enables it, which is what chained
# libopenal -> libsndio -> libasound into a mandatory startup dependency.
if [ -f "$PREFIX/lib/libopenal.so.1" ]; then
  say "reusing cached openal-soft $OPENAL_VERSION"
else
  say "compiling openal-soft $OPENAL_VERSION (jobs: $JOBS)"
  rm -rf "$WORK/openal-src"; mkdir -p "$WORK/openal-src"
  tar -xzf "$CACHE/$OPENAL_TARBALL" -C "$WORK/openal-src" --strip-components=1
  (
    cd "$WORK/openal-src"
    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DALSOFT_DLOPEN=ON \
      -DALSOFT_BACKEND_SNDIO=OFF \
      -DALSOFT_BACKEND_OSS=OFF \
      -DALSOFT_BACKEND_JACK=OFF \
      -DALSOFT_EXAMPLES=OFF \
      -DALSOFT_UTILS=OFF \
      -DALSOFT_TESTS=OFF \
      -DLIBTYPE=SHARED >/dev/null
    cmake --build build -j"$JOBS" >/dev/null
    cmake --install build >/dev/null
  )
fi

openal_lib="$PREFIX/lib/libopenal.so.1"
[ -f "$openal_lib" ] || fail "openal-soft build produced no libopenal.so.1"
for forbidden in libsndio libasound libpulse libjack; do
  if objdump -p "$openal_lib" | grep -q "NEEDED.*$forbidden"; then
    fail "openal hard-links $forbidden; backends must stay behind dlopen"
  fi
done

# --------------------------------------------------- compile libtheora
# --disable-examples is what drops Debian's libcairo link (and with it libX11,
# libxcb, libfontconfig and libfreetype as startup dependencies). The encoder
# is dead weight for a player, but libtheoradec is what LÖVE actually links.
if [ -f "$PREFIX/lib/libtheoradec.so.1" ]; then
  say "reusing cached libtheora $THEORA_VERSION"
else
  say "compiling libtheora $THEORA_VERSION"
  rm -rf "$WORK/theora-src"; mkdir -p "$WORK/theora-src"
  tar -xjf "$CACHE/$THEORA_TARBALL" -C "$WORK/theora-src" --strip-components=1
  (
    cd "$WORK/theora-src"
    # theora 1.1.1 predates the aarch64 config.guess, so refresh the autotools
    # helper scripts or configure rejects the host outright.
    for helper in config.guess config.sub; do
      cp "/usr/share/misc/$helper" . 2>/dev/null || true
    done
    ./configure --prefix="$PREFIX" --disable-static \
      --disable-examples --disable-spec --disable-doc >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
  )
fi

theora_lib="$PREFIX/lib/libtheoradec.so.1"
[ -f "$theora_lib" ] || fail "libtheora build produced no libtheoradec.so.1"
if objdump -p "$theora_lib" | grep -q "NEEDED.*libcairo"; then
  fail "libtheoradec still links libcairo (--disable-examples stopped working)"
fi

# ------------------------------------------------------------ compile LÖVE
if [ -x "$PREFIX/bin/love" ] && [ -f "$PREFIX/lib/liblove-$LOVE_VERSION.so" ]; then
  say "reusing cached LÖVE $LOVE_VERSION aarch64 build"
else
  say "compiling LÖVE $LOVE_VERSION for aarch64 (jobs: $JOBS)"
  rm -rf "$WORK/love-src"
  mkdir -p "$WORK/love-src"
  tar -xzf "$CACHE/love-$LOVE_VERSION-linux-src.tar.gz" \
    -C "$WORK/love-src" --strip-components=1
  (
    cd "$WORK/love-src"
    # No --disable-* flags on purpose: configure silently drops a love module
    # when its -dev package is absent, so the Dockerfile pins the full set and
    # the assertions below prove each one actually linked. CPPFLAGS/LDFLAGS
    # point at our prefix so the SDL2 and theora just built above win over
    # anything the base image might still provide.
    ./configure --prefix="$PREFIX" --disable-static \
      CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
    # Keep LÖVE's license inside the cached prefix: the unpacked source tree
    # is thrown away, so a later cache-hit run would otherwise have nothing
    # to ship and the AppImage would go out without its engine license.
    cp license.txt "$PREFIX/license.txt"
  )
fi

love_bin="$PREFIX/bin/love"
love_lib="$PREFIX/lib/liblove-$LOVE_VERSION.so"
[ -x "$love_bin" ] || fail "LÖVE build produced no bin/love"
[ -f "$love_lib" ] || fail "LÖVE build produced no lib/liblove-$LOVE_VERSION.so"
file "$love_bin" | grep -q 'ARM aarch64' \
  || fail "built love is not an aarch64 ELF (got: $(file -b "$love_bin"))"

# A configure run that lost an optional dependency still exits 0 and still
# builds -- the loss only shows up as a missing love module at runtime, i.e.
# in a shipped artifact. Assert the decoder/font/video libs really linked.
for soname in libSDL2-2.0.so.0 libopenal.so.1 libfreetype.so.6 \
              libmodplug.so.1 libmpg123.so.0 libvorbisfile.so.3 \
              libtheoradec.so.1 libluajit-5.1.so.2; do
  objdump -p "$love_lib" | grep -q "NEEDED.*$soname" \
    || fail "liblove is not linked against $soname (a -dev package went missing)"
done

# --------------------------------------------------------------- AppDir
# Layout mirrors LÖVE's own x86_64 AppImage exactly (bin/ lib/ share/ at the
# AppDir root, not usr/-prefixed), so the AppRun contract below -- and the
# FUSE_PATH fusion scripts/build.sh performs on the x86_64 image -- stay the
# same idea on both architectures.
APPDIR="$WORK/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/bin" "$APPDIR/lib" "$APPDIR/share"

cp "$love_bin" "$APPDIR/bin/love"
chmod +x "$APPDIR/bin/love"

# ------------------------------------------------------ bundle dependencies
# Walk the DT_NEEDED graph from love + liblove, copying in everything that is
# not host-provided. Recursion stops at excluded libraries, so the driver and
# session subtrees behind SDL2 are never pulled in.
#
# Three reasons a library MUST come from the host, and every entry below is
# one of them:
#
#  1. Driver/session coupled. A bundled libGL would bypass Mesa's V3D driver
#     on the Pi; a bundled libpulse/libdbus would fight the user's running
#     session. GL/EGL/gbm/drm, X11/xcb/wayland/xkbcommon, dbus, pulse, alsa,
#     systemd/udev. Note that after the source builds above, none of these are
#     DT_NEEDED of anything we ship -- SDL2 and OpenAL dlopen them, so they are
#     used when present and skipped when absent.
#
#  2. Loader coupled. glibc's pieces cannot be mixed with the host's ld.so at
#     all, and libstdc++/libgcc_s must be at least as new as the compiler --
#     bullseye's gcc 10 is older than any supported host's, so the host copy
#     always satisfies us.
#
#  3. The font/compression stack: freetype, fontconfig, libpng, brotli, zlib.
#     These are shared with whatever the host's own graphics libraries have
#     already loaded, and mixing vintages inside one process breaks the older
#     copy. Bundling a bullseye freetype 2.10.4 is what made a host cairo fail
#     to find FT_Get_Transform (added in 2.11) and killed the game at startup.
#     Leaving the whole stack to the host keeps it self-consistent, and
#     liblove -- compiled against 2.10.4 -- only ever asks for symbols every
#     supported host already has.
EXCLUDE_RE='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libresolv\.so\.2|libutil\.so\.1|libanl\.so\.1|libnsl\.so\.[0-9]+|libstdc\+\+\.so\.6|libgcc_s\.so\.1|lib(GL|GLX|GLdispatch|OpenGL|EGL|GLESv[12]|glapi|gbm|drm)\..*|libX[a-z0-9]*\..*|libxcb.*|libwayland-.*|libxkbcommon.*|libdbus-1\..*|libpulse.*|libasound\..*|libsndfile\..*|libFLAC\..*|libopus\..*|libsystemd\..*|libudev\..*|libselinux\..*|libcap\..*|libgcrypt\..*|libgpg-error\..*|liblzma\..*|libzstd\..*|liblz4\..*|libffi\..*|libexpat\..*|libbsd\..*|libmd\..*|libuuid\..*|libg(lib|object|module|thread)-2\..*|libfontconfig\..*|libfreetype\..*|libpng[0-9]*\..*|libbrotli.*|libz\.so\..*|libwrap\..*|libasyncns\..*|libtirpc\..*|lib(gssapi_krb5|krb5|k5crypto|com_err|krb5support|keyutils)\..*|libpcre.*)$'

# soname -> absolute path, harvested from the full ldd closure of both roots.
declare -A RESOLVED=()
while read -r soname _arrow path _addr; do
  [ -n "${path:-}" ] || continue
  [ -e "$path" ] || continue
  RESOLVED["$soname"]="$path"
done < <(ldd "$love_bin" "$love_lib" | awk '/=>/ {print $1, $2, $3, $4}')

declare -A BUNDLED=()
bundle_needed() { # $1 = ELF whose DT_NEEDED entries to walk
  local soname target
  while read -r soname; do
    [ -n "$soname" ] || continue
    if [[ "$soname" =~ $EXCLUDE_RE ]]; then continue; fi
    if [ -n "${BUNDLED[$soname]:-}" ]; then continue; fi
    target="${RESOLVED[$soname]:-}"
    [ -n "$target" ] || fail "cannot resolve $soname (needed by $(basename "$1"))"
    # Copy dereferenced and under the soname: the AppDir must not depend on
    # the builder's libSDL2-2.0.so.0 -> libSDL2-2.0.so.0.14.0 symlink chain.
    cp -L "$target" "$APPDIR/lib/$soname"
    chmod 0644 "$APPDIR/lib/$soname"
    BUNDLED["$soname"]=1
    bundle_needed "$APPDIR/lib/$soname"
  done < <(objdump -p "$1" | awk '/NEEDED/ {print $2}')
}

say "bundling shared libraries"
cp "$love_lib" "$APPDIR/lib/liblove-$LOVE_VERSION.so"
chmod 0644 "$APPDIR/lib/liblove-$LOVE_VERSION.so"
BUNDLED["liblove-$LOVE_VERSION.so"]=1
bundle_needed "$APPDIR/bin/love"
bundle_needed "$APPDIR/lib/liblove-$LOVE_VERSION.so"
say "bundled $(ls "$APPDIR/lib" | wc -l) libraries: $(ls "$APPDIR/lib" | tr '\n' ' ')"

# ------------------------------------------------- host dependency contract
# The portability promise, stated as an assertion instead of a paragraph in a
# README: these are the ONLY sonames the shipped objects may require from the
# host. Everything driver-, session- or audio-related has to be reached
# through dlopen, so the AppImage starts on a box with no PulseAudio, no X11
# or no ALSA and simply uses whatever it does find.
#
# The original build failed exactly here and nobody noticed until CI ran on a
# headless runner: Debian's SDL2 hard-links libpulse/libasound/libX11/
# libwayland, so the image only ever started on a full desktop.
HOST_ALLOWED_RE='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libatomic\.so\.1|libfreetype\.so\.6|libpng[0-9]*\.so\.[0-9]+|libz\.so\.1|libbrotli(dec|common)\.so\.1)$'

unexpected=""
for object in "$APPDIR/bin/love" "$APPDIR"/lib/*.so*; do
  while read -r soname; do
    [ -n "$soname" ] || continue
    # Satisfied from inside the AppDir, so not a host requirement at all.
    if [ -n "${BUNDLED[$soname]:-}" ]; then continue; fi
    if [[ "$soname" =~ $HOST_ALLOWED_RE ]]; then continue; fi
    unexpected="$unexpected  $(basename "$object") -> $soname"$'\n'
  done < <(objdump -p "$object" | awk '/NEEDED/ {print $2}')
done
[ -z "$unexpected" ] || fail "$(printf '%s\n%s' \
  "these objects hard-require host libraries outside the allowed set (they must be dlopened, not linked):" \
  "$unexpected")"
say "host dependency contract holds (glibc, libstdc++ and the font stack only)"

# LÖVE loads jit.* (jit.status, the profiler) through LUA_PATH; without these
# the modules are simply absent, so ship them the way upstream's image does.
jit_share="$(ls -d /usr/share/luajit-* 2>/dev/null | head -1)"
[ -n "$jit_share" ] || fail "luajit jit/*.lua modules not found under /usr/share"
LUAJIT_SHARE_DIR="$(basename "$jit_share")"
mkdir -p "$APPDIR/share/$LUAJIT_SHARE_DIR" "$APPDIR/share/lua/5.1" "$APPDIR/lib/lua/5.1"
cp -R "$jit_share/jit" "$APPDIR/share/$LUAJIT_SHARE_DIR/"

# --------------------------------------------------------------- branding
cp "$IN/game.love" "$APPDIR/game.love"
# The .desktop's Icon= resolves against the AppDir root by basename, and
# .DirIcon is what appimaged and file-manager thumbnailers read.
cp "$IN/icon.png" "$APPDIR/$APP_NAME.png"
cp "$IN/icon.png" "$APPDIR/.DirIcon"

cat > "$APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=gen1recomp
Comment=Pokémon Gen 1 recompilation
Exec=$APP_NAME
Icon=$APP_NAME
StartupWMClass=love
Categories=Game;
Terminal=false
EOF

# AppRun follows LÖVE's own, with FUSE_PATH committed to instead of shipped
# commented out: this image is a game, not the engine, so it must never fall
# through to LÖVE's "no game" screen.
cat > "$APPDIR/AppRun" <<EOF
#!/bin/sh
# gen1recomp aarch64 AppImage launcher.

if [ -z "\$APPDIR" ]; then
    APPDIR="\$(dirname "\$(readlink -f "\$0")")"
fi

export LD_LIBRARY_PATH="\$APPDIR/lib/:\$LD_LIBRARY_PATH"

if [ -z "\$XDG_DATA_DIRS" ]; then
    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"
fi
export XDG_DATA_DIRS="\$APPDIR/share/:\$XDG_DATA_DIRS"

if [ -z "\$LUA_PATH" ]; then
    LUA_PATH=";"
fi
export LUA_PATH="\$APPDIR/share/$LUAJIT_SHARE_DIR/?.lua;\$APPDIR/share/lua/5.1/?.lua;\$LUA_PATH"

if [ -z "\$LUA_CPATH" ]; then
    LUA_CPATH=";"
fi
export LUA_CPATH="\$APPDIR/lib/lua/5.1/?.so;\$LUA_CPATH"

exec "\$APPDIR/bin/love" --fused "\$APPDIR/game.love" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

[ -f "$PREFIX/license.txt" ] || fail "LÖVE license.txt missing from the build prefix"
cp "$PREFIX/license.txt" "$APPDIR/license.love2d.txt"

# --------------------------------------------------------------- fuse image
# An AppImage is just <runtime ELF><squashfs>. gzip at 128K blocks matches what
# LÖVE's official image uses and what every type-2 runtime can read; zstd would
# be smaller but is not universally supported by older runtimes users may have
# registered through appimaged.
say "packing squashfs"
sfs="$WORK/payload.squashfs"
rm -f "$sfs"
mksquashfs "$APPDIR" "$sfs" \
  -comp gzip -b 131072 -noappend -all-root -no-xattrs -quiet >/dev/null

out="$OUT/$APP_NAME-$VERSION-linux-arm64.AppImage"
rm -f "$out"
cat "$CACHE/runtime-aarch64" "$sfs" > "$out"
chmod +x "$out"

say "AppImage: $(basename "$out") ($(du -h "$out" | cut -f1))"

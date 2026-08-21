# Linux arm64 (aarch64) AppImage

Releases ship `gen1recomp-<version>-linux-arm64.AppImage` alongside the
existing x86_64 `gen1recomp-<version>-linux.zip`. It targets 64-bit ARM
desktop Linux: Raspberry Pi 4/5 running Raspberry Pi OS, Armbian and other
SBC distros, arm64 VMs on Apple Silicon, Ampere/Graviton desktops, and the
aarch64 handhelds that run a full distro.

> The Anbernic RG34XXSP has its own PortMaster-style pack
> (`gen1recomp-*-rg34xxsp-stockos64-mod.zip`, see
> [anbernic-rg34xxsp.md](anbernic-rg34xxsp.md)). That one bundles PortMaster's
> LÖVE runtime and expects the device's own SDL; this AppImage is the generic
> desktop-Linux artifact and shares nothing with it but the `game.love`.

## For players

```sh
chmod +x gen1recomp-*-linux-arm64.AppImage
./gen1recomp-*-linux-arm64.AppImage
```

Then use **Import ROM** in the launcher to point it at your own legal Red /
Blue / Yellow cartridge dump, exactly as on every other platform.

If your system has no FUSE (`dlopen(): error loading libfuse.so.2`), either
install it (`sudo apt install libfuse2`) or run without it:

```sh
./gen1recomp-*-linux-arm64.AppImage --appimage-extract-and-run
```

### What the host has to provide

Very little, and this is enforced by an assertion in the build rather than by
good intentions. The only libraries the AppImage requires at startup are:

```
glibc 2.29+   libstdc++   libfreetype6   zlib
```

Everything else — OpenGL/Mesa, X11, Wayland, KMSDRM, ALSA, PulseAudio — is
**dlopened**, so it is used when present and skipped when absent. That means
one image runs on a full desktop, on a Wayland-only session, on a
KMSDRM-only handheld with no X server, and on a box with ALSA but no
PulseAudio, without a different build for each.

That property does not come for free from Debian's packages, and getting it
is most of what the build below is doing; see
[Why five libraries are built from source](#why-five-libraries-are-built-from-source).

## For builders

```sh
scripts/build_linux_arm64.sh --version 0.1.0
```

Output:

```
dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage
dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage.sha256
```

Useful flags: `--game-love PATH` reuses an already-packed payload (CI does
this so every platform ships identical bytes), `--rebuild-image` forces the
builder container to rebuild, `--clean-cache` throws away the pinned
downloads and the compiled LÖVE prefix.

### Requirements

An **aarch64 host** with **docker or podman**. A Raspberry Pi 5 is the
reference machine (a cold build takes about 10 minutes on one — six libraries
plus the engine; rebuilds reuse the cached prefix and take seconds). Apple Silicon with Docker
Desktop and GitHub's `ubuntu-24.04-arm` runner both work too.

The script refuses to run on x86_64 rather than falling back to qemu-user
emulation: that path takes hours and has produced miscompiled LuaJIT.

### Why this is not just another `scripts/build.sh` target

`scripts/build.sh linux` downloads LÖVE's official `love-11.5-x86_64.AppImage`,
unpacks its squashfs, drops `game.love` in, and glues it back together. That
trick is not available here — **LÖVE publishes no aarch64 binary at all.** The
11.5 release has win32, win64, macOS, Android, iOS and one x86_64 AppImage,
and that is the entire list.

So this build compiles LÖVE 11.5 from the official `linux-src` tarball and
assembles the AppImage from scratch. Every pinned input — the LÖVE source, the
five libraries built alongside it, and the AppImage type-2 runtime — is
SHA-256 verified on the host before the container ever sees it, and the
container itself runs with no network access.

### Why the build happens in a Debian bullseye container

glibc is backward compatible but not forward compatible: a binary linked
against glibc 2.41 will not start on a system with 2.31, and there is no way
to fix that after the fact. Compiling on the oldest base we support is
therefore the only thing that makes one artifact work everywhere.

Bullseye (glibc 2.31) is that base. The resulting binaries actually come out
needing only **glibc 2.29** and **GLIBCXX_3.4.21**, so the AppImage covers
everything from Ubuntu 20.04 and Raspberry Pi OS bullseye through current
trixie.

This is a statement about the *compile environment*, not about where the
artifact runs — building on your own newer distro would silently raise that
floor and strand every user on an older one, with no symptom until they
download it. `scripts/linux-arm64/verify_appimage.sh` enforces the floor in
both CI (`linux-arm64-build`) and the release workflow: the build fails if
the highest required glibc symbol version climbs above 2.31.

### Why five libraries are built from source

SDL2, OpenAL, libtheora, libogg/libvorbis and libmpg123 are compiled rather
than installed from bullseye. In every case the reason is *correctness*, not
a newer version number — Debian builds these for a system where every
dependency is installed and co-versioned, which is the opposite of an
AppImage's situation. Each one broke the build in a different way, and all
three failure modes are now assertions that fail the build instead of
shipping.

**1. Hard-linked backends (SDL2, OpenAL).** Debian's `libSDL2` lists
`libpulse`, `libasound`, `libX11` and `libwayland-client` as `DT_NEEDED` —
resolved by the loader at startup, not dlopened. An AppImage bundling it
refuses to start unless the host has *all four*. It appeared to work in
testing only because a desktop Pi has all four; a headless CI runner is what
exposed it. Debian's OpenAL does the same via `libsndio`, which itself
hard-links `libasound`. Built from source with `--enable-*-shared` and
`ALSOFT_DLOPEN`, both dlopen their backends instead.

**2. A stray link (libtheora).** Debian's `libtheoradec.so.1` is linked
against `libcairo.so.2` — a packaging artifact, since a video decoder has no
business drawing vector graphics — and cairo drags in X11, xcb, fontconfig
and freetype. `--disable-examples` produces a `libtheoradec` needing only
`libogg`.

**3. SONAME collision with the host (ogg, vorbis, mpg123).** The subtle one.
OpenAL dlopens ALSA, ALSA's config loads its PulseAudio hook plugin, and that
plugin pulls the *host's* `libsndfile` into our process. `libsndfile` links
`libogg`, `libvorbis` and `libmpg123` — the same three we bundle. The loader
resolves a SONAME exactly once per process, so the host's `libsndfile` binds
to *our* copies:

```
openal -> libasound -> libasound_module_conf_pulse -> libsndfile (host, new)
                                                         `-> mpg123_info2 -> libmpg123 (ours, bullseye 1.26)
```

`mpg123_info2` arrived in mpg123 1.32, so the plugin failed to relocate, ALSA
config collapsed, and the game ran with **no audio device at all**. Not
bundling these instead would make `libogg`/`libvorbis`/`libmpg123` mandatory
host packages; building them current means our copies *satisfy* the host's
`libsndfile` rather than starving it.

The same collision is why the font stack — freetype, fontconfig, libpng,
brotli, zlib — is left to the host entirely. Bundling a bullseye freetype
2.10.4 meant a host `libcairo` could not find `FT_Get_Transform` (added in
2.11) and the game died at startup. Leaving the whole stack to the host keeps
it self-consistent, while `liblove` — compiled against 2.10.4 — only ever
asks for symbols every supported host already has.

The general rule this all reduces to: **never bundle a library the host's own
stack may also load, unless yours is at least as new as theirs.**

### CI

Three jobs, path-gated on `scripts/build_linux_arm64.sh`,
`scripts/linux-arm64/`, `scripts/pack_love.sh` and this document:

- **`linux-arm64-selftest`** (`ubuntu-latest`, x86_64) — offline gate. Checks
  the pins are real digests on a dated tag rather than the moving
  `continuous` one, that the Dockerfile still builds on bullseye, that the
  exclude list still classifies known sonames correctly, that AppRun still
  launches `game.love` with `--fused`, and that the host-arch guard actually
  fires. Needs no container and no arm64 machine.
- **`linux-arm64-build`** (`ubuntu-24.04-arm`) — the real build, then
  `scripts/linux-arm64/verify_appimage.sh` extracts the artifact and asserts
  the layout, that every bundled object resolves under AppRun's
  `LD_LIBRARY_PATH`, and that the glibc floor is still ≤ 2.31. Uploads the
  AppImage for 7 days.
- **release** — `linux-arm64` runs on `ubuntu-24.04-arm`, reuses the shared
  `game.love` from the `love-payload` job, runs the same
  `verify_appimage.sh` checks on the shipped image, and the AppImage is
  staged and published like every other release asset.

Unlike the Switch job, none of this needs secrets or self-hosted hardware, so
it runs on fork PRs too.

### Updating the pins

Both pins live in `scripts/linux-arm64/common.sh`:

- `LOVE_VERSION` / `LOVE_SRC_SHA256` — bumping any version invalidates the
  cached prefix automatically (its name is keyed by every source version at
  once, so a partial rebuild cannot mix vintages). Check that bullseye still
  has `-dev` packages new enough for the new release; `build_appimage.sh`
  asserts every optional module actually linked, because LÖVE's `configure`
  exits 0 and silently drops a module when one is missing.
- `SDL2_*`, `OPENAL_*`, `THEORA_*`, `OGG_*`, `VORBIS_*`, `MPG123_*` — the
  source-built libraries. Bumping these is usually safe and occasionally
  necessary: `libmpg123` in particular must stay at least as new as what a
  target host's `libsndfile` expects, which is asserted for `mpg123_info2`.
- `APPIMAGE_RUNTIME_TAG` / `APPIMAGE_RUNTIME_SHA256` — always a dated tag
  from [AppImage/type2-runtime](https://github.com/AppImage/type2-runtime/releases).
  The selftest fails the build if this ever points at `continuous`.

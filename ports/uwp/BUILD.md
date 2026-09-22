# Gen1Recomp Xbox UWP build notes

This is the Xbox Dev Mode package for Gen1Recomp.

The rough shape is:

- `Gen1RecompUWP.exe` starts LÖVE through SDL's WinRT wrapper
- the bundled LÖVE 11.5 UWP backend provides LuaJIT and the Xbox file picker
- the bundled SDL2 runtime contains the Xbox controller mapping
- ANGLE provides OpenGL ES over D3D11
- the bundled runtime contains the audio, font, video, and compression libraries

## What You Need

The tested toolchain is:

- Visual Studio 2022 17.14
- MSVC v143 x64/x86 build tools
- C++ Universal Windows Platform tools
- Windows 11 SDK `10.0.26100.0`
- CMake 3.24 or newer
- Git for Windows
- Info-ZIP `zip` and `unzip`

Use Visual Studio Installer to add **Universal Windows Platform development**, the v143 C++ tools, CMake tools for Windows, and Windows SDK `10.0.26100.0`.

The x64 UWP dependencies are committed under `third_party`. Their versions,
source revisions, licences, and hashes are recorded in `third_party/manifest.json`.
No additional checkout or environment variable is required for a normal game
build.

## Rebuild the Dependencies

Run the dependency rebuild from the repository root:

```powershell
.\scripts\xbox-uwp\rebuild_dependencies.ps1
```

The script clones the pinned SDL2, LÖVE, LuaJIT, vcpkg, depot_tools, and ANGLE
sources when they are missing. It applies the Xbox SDL2 patch and the LÖVE
picker patch (`third_party/love/patches/gba-file-picker.patch`, which adds
`.gba` to the ROM file picker), builds the x64 UWP Release libraries, stages
the required DLLs, import libraries, headers, and licences under `third_party`,
updates every SHA-256 entry in the manifest, then builds the Release MSIX.
The `love.dll` already in `third_party` includes that `.gba` filter as an
in-place patch, so a package built from the committed binaries offers it
without this rebuild. A from-source rebuild compiles the same filter in.

The generated source checkouts are ignored by Git. A fresh ANGLE sync is about
10 GB, so allow at least 20 GB of free disk space for all sources and build
outputs. Use `-SkipAngle` to retain the existing pinned ANGLE runtime while
rebuilding SDL2, LÖVE, LuaJIT, and the vcpkg libraries. Use `-SkipPackage` when
only the dependency bundle needs to be refreshed. The rebuild stops if a source
checkout has local changes. Remove that generated `source` directory to restore
the pinned revision.

## Build the MSIX

Run the Xbox build from Git Bash at the repository root:

```bash
scripts/build_xbox_uwp.sh --release --version 1.2.3
```

The build uses `scripts/pack_love.sh` to create and verify the same ROM-free
`game.love` payload used by the other release targets. It then links the UWP
host and stages LÖVE, LuaJIT, SDL2, ANGLE, and the vcpkg runtime DLLs.

Use `--relwithdebinfo` for a package with symbols. To package a `.love` produced
by another build or downloaded from CI, pass `--game-love path/to/game.love`.
The upstream `X.Y.Z` release becomes `X.Y.Z.0` in the generated MSIX manifest.
Neither the manifest template nor `src/core/Version.lua` is edited in place.

The manifest publisher must match the signing certificate subject. Pass it
when preparing a signed package:

```bash
scripts/build_xbox_uwp.sh --release --version 1.2.3 \
  --publisher "CN=Gen1Recomp"
```

The normal build is unsigned. Release CI supplies the private PFX and password
from `XBOX_UWP_SIGNING_CERTIFICATE` and `XBOX_UWP_SIGNING_PASSWORD`; neither may
be committed. The public certificate is safe to include with the release.

Run the offline packaging checks from Git Bash:

```bash
bash scripts/xbox-uwp/selftest_build_xbox_uwp.sh
```

## Build Output

Visual Studio package output lands under:

```text
ports\uwp\build\release\AppPackages\Gen1RecompUWP
```

The build also stages the distributable archive and checksum under:

```text
dist\xbox-uwp\gen1recomp-X.Y.Z-xbox-uwp.zip
dist\xbox-uwp\gen1recomp-X.Y.Z-xbox-uwp.zip.sha256
```

The archive contains the MSIX, framework dependencies, build provenance and,
for a signed release, the public certificate. The third-party notices are
packaged inside the MSIX. Install the MSIX and dependency packages through
Xbox Device Portal.

## Runtime Data

The package contains no ROM, generated cache, save or mod data. The Xbox file
picker copies user-selected files into LocalState and the launcher imports them
from there. Saves, ROM cache and installed mods remain under the LÖVE save
directory in LocalState.

The launcher also checks `LocalState\pokemon-love2d\baseroms` once at startup
for clean Red, Blue, and Yellow ROMs. Compatible files are offered on their
launcher tabs and remain in `baseroms` after import. The file picker remains
available when no compatible ROM is found.

LuaJIT requires the `codeGeneration` capability. `removableStorage` exposes
external media to the Xbox picker. The network capabilities support relay play
and direct hosting. The package does not request full trust or broad filesystem
access.

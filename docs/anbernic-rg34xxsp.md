# Anbernic RG34XXSP (Stock OS 64-bit MOD)

Download `gen1recomp-*-rg34xxsp-stockos64-mod.zip` from
[Releases](https://github.com/bryanthaboi/gen1recomp/releases). This build
targets **Stock OS 64-bit MOD** on the RG34XXSP with PortMaster installed
(TF1).

## Install

1. Unzip the release on your computer. You get `Gen1recomp.sh` and a
   `gen1recomp/` folder.
2. Copy **both** onto the SD card under **`Roms/PORTS/`** so the layout is:

   ```
   Roms/PORTS/Gen1recomp.sh
   Roms/PORTS/gen1recomp/
   ```

   On the device that path is `/mnt/mmc/Roms/PORTS/`. Keep the launcher and
   the `gen1recomp/` folder as siblings — do not nest the `.sh` inside the
   folder.
3. Put your legal US Red and/or Blue `.gb` files inside the game folder:

   ```
   Roms/PORTS/gen1recomp/lovegame/
   ```

   Example: `Roms/PORTS/gen1recomp/lovegame/Pokemon - Red Version.gb`
4. Eject the card, boot the handheld, open **Ports → Gen1recomp**.
5. On the launcher, move the cursor with the D-pad or left stick, press **A**
   to click. Choose the Red or Blue tab, then **Choose ROM** — with no file
   picker on stock OS, that scans `lovegame/` for the `.gb` you dropped in.

The port ships with `portable.txt` already in place, so after import the
saves and ROM-derived cache stay next to the game on the SD card. See
[Portable Mode](../README.md#portable-mode) for what that means.

Only the canonical 1 MiB US carts import:

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`

## Updating

The port updates itself from the launcher. When a newer release exists the
footer chip reads **Update vX.Y.Z**: press it to download the new version, then
press **Restart to update** to relaunch and start using it. Nothing inside the
port folder is rewritten, so an update that fails or is interrupted still boots
the version you already had.

An update replaces the game's code and data. It cannot replace the LÖVE runtime
the port ships, so a release that needs a newer runtime is applied differently:
the chip then reads **Download port update** and saves
`gen1recomp-<version>-rg34xxsp-stockos64-mod.zip` into

```
Roms/PORTS/gen1recomp/conf/love/pokemon-love2d/updates/
```

That case is finished on a computer — unzip the file and copy the
`Gen1recomp.sh` and `gen1recomp/` it contains over the copies on the SD card,
exactly as in [Install](#install) above. Your saves sit beside the game
(`portable.txt`) and are untouched by either kind of update.

The launcher exports `POKEPORT_RG34XXSP=1`, which is how the updater knows this
is the RG34XXSP port and offers the matching port package rather than a desktop
AppImage.

## Launcher controls

| Input              | Action             |
| ------------------ | ------------------ |
| D-pad / left stick | Move cursor        |
| A                  | Click              |
| L1 / R1            | Switch tabs        |
| Right stick        | Scroll lists       |
| Start / Select     | Play or Choose ROM |

In-game controls use the normal PortMaster / SDL pad map, rebindable under
**OPTIONS → CONTROLS**.

## Notes

**PERFORMANCE defaults to LOW here.** The OPTIONS → PERFORMANCE tier defaults
to AUTO, which reads this device as an ARM Linux handheld and resolves to
**LOW**: the 3D tilt and survey zoom stay off and the frame rate is capped,
so the overworld runs smoothly on the H700 out of the box. Bump it to
BALANCED or HIGH from OPTIONS if you want the extras and your device keeps
up; see [Performance tier](new-features.md#performance-tier-low-end-devices).

The pack bundles the LÖVE 11.5 aarch64 runtime from
[PortMaster](https://portmaster.games/), so the device does not need a
separate `love_11.5` runtime download on first launch. The launcher resolves
paths relative to its own directory rather than PortMaster's `$directory`,
because stock Anbernic firmware runs ports out of `roms/PORTS/` with its own
casing and mount points.

If a launch fails, `Roms/PORTS/gen1recomp/log.txt` holds the output of the
last run.

## Bundled LuaJIT

The pack does not use PortMaster's `libluajit-5.1.so.2`. That one is LuaJIT
2.1.0-beta3 (2017), which segfaulted 3 of 3 runs with the JIT on (TrimUI
Brick). The pack ships a pinned LuaJIT 2.1 build instead (commit
`c6ffc141a8762b41703f9287d63d93622a13dd8f`, MIT, license in
`licenses/LuaJIT-COPYRIGHT`). It is compiled from source in a Debian bullseye
aarch64 container (glibc 2.31, GC64, `make amalg`) by
`scripts/luajit/build_luajit.sh`, and the build checks the version string and
the glibc requirement before and after zipping. On the TrimUI Brick it ran a
26-minute JIT-on soak with no crash.

The JIT still stays **off by default** on these builds: LÖVE turns it off on
arm64, and nothing here sets `POKEPORT_JIT`. It has only been validated on one
device (TrimUI Brick, A133P). Enabling `POKEPORT_JIT=1` by default needs
stability testing on H700, RK3566 and A133P devices first.

Existing installs keep their old LuaJIT until the zip is re-extracted: in-app
updates replace only the game's code, not the runtime libraries.

Building the port now needs an aarch64 host with docker or podman (non-aarch64
hosts are refused), or a prebuilt library passed with
`GEN1RECOMP_LUAJIT_LIB=/path/to/libluajit-5.1.so.2` (with its `COPYRIGHT` next
to it, or `GEN1RECOMP_LUAJIT_COPYRIGHT`). The remaining PortMaster runtime
files are pinned to a PortMaster-GUI commit and sha256-checked.

## Building the port

Release runs build this automatically (see `.github/workflows/release.yml`).
To build it by hand:

```sh
./build-rg34xxsp.sh --version 0.1.0   # -> dist/rg34xxsp/gen1recomp-rg34xxsp-stockos64-mod.zip
```

`install-rg34xxsp.sh` copies that pack straight onto a mounted SD card for
local testing.

Stock OS 64-bit MOD comes from
[cbepx-me](https://github.com/cbepx-me/Anbernic-H700-RG-xx-StockOS-Modification).

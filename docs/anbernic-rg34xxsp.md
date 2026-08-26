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

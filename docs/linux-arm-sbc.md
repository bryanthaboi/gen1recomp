# Linux ARM SBC Handhelds (PortMaster)

Download `gen1recomp-*-sbc-portmaster.zip` from the [Gen1Recomp releases](https://github.com/bryanthaboi/gen1recomp/releases). This build targets 64-bit Linux ARM handhelds with PortMaster, including compatible H700 devices.

## Install

1. Unzip the release. It contains `gen1recomp-sbc.sh` and a `gen1recomp-sbc/` folder.
2. Copy both as siblings into your device's PortMaster ports directory, commonly `Roms/Ports (PORTS)/` or `Roms/PORTS/`.
3. Install PortMaster for your firmware and refresh the Ports list.
4. Copy your legally owned canonical US Red or Blue `.gb` file into `gen1recomp-sbc/lovegame/`.
5. Launch **gen1recomp-sbc** from Ports and choose the ROM.

The pack includes `portable.txt`, so saves and ROM-derived cache remain beside the game on the SD card. The build never ships ROM-derived bytes.

Canonical US cart SHA-1 values:

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
`gen1recomp-<version>-sbc-portmaster.zip` into

```
gen1recomp-sbc/conf/love/pokemon-love2d/updates/
```

That case is finished on a computer — unzip the file and copy the
`gen1recomp-sbc.sh` and `gen1recomp-sbc/` it contains over the copies on the SD
card, exactly as in [Install](#install) above. Your saves sit beside the game
(`portable.txt`) and are untouched by either kind of update.

The launcher exports `POKEPORT_PORTMASTER=1`, which is how the updater knows
this is the PortMaster port and offers the port package rather than a desktop
AppImage.

## Controls

| Input | Action |
| --- | --- |
| D-pad | Move cursor |
| A | Click / confirm |
| L1 / R1 | Switch tabs |
| Start / Select | Play or choose ROM |

In-game controls use the normal PortMaster/SDL mapping and can be rebound in **OPTIONS → CONTROLS**.

## Runtime and suspend

The package bundles PortMaster's LÖVE 11.5 aarch64 runtime. The launcher sources `control.txt`, calls `get_controls`, applies an optional CFW override, invokes `pm_platform_helper`, and calls `pm_finish` on exit. Paths are relative to the launcher, allowing different firmware mount points.

Suspend/resume uses the existing LÖVE focus/visibility lifecycle: input is reset on focus loss and the game resumes when the window becomes visible again. Exact power-button behavior remains firmware-dependent; hardware validation has been performed on the TrimUI Brick, not every SBC or H700 device.

## Power and Performance Tuning

The handheld build applies several optimizations to reduce power draw while keeping smooth frame pacing on low-power ARM SoCs:

- **PresentSync / driver vsync**: Handheld builds keep driver vsync enabled so the unified present-sync stack can probe cadence and pace through the panel (KMSDRM page-flip wait). Disabling vsync here bypassed that path and forced the FrameCap 1 ms polling loop at 60 FPS.
- **Idle Render Governor**: After `POKEPORT_IDLE_AFTER` seconds without input on static in-game screens, presentation drops to `POKEPORT_IDLE_FPS` while game logic and audio stay at full speed. Any button press restores full framerate on the next frame.
- **Sample Rate Scaling**: Audio synthesis is tuned to 22.05 kHz by default (`POKEPORT_AUDIO_RATE=22050`), halving synthesis CPU overhead on Cortex-A53 cores with no audible quality loss on handheld speakers. The synth engine and its queueable source are built for one rate, so changing PERFORMANCE across the LOW boundary in OPTIONS switches the rate live and replays the current song from the start of its section; the rate never changes on its own during play.
- **Dynamic CPU Governor**: Defaults to `schedutil` instead of pinning `performance` on all cores, reducing thermals and extending battery life.

Environment variables for fine-tuning (configured in `gen1recomp-sbc.sh`):

| Variable | Default | Description |
| --- | --- | --- |
| `POKEPORT_IDLE_AFTER` | `10` | Seconds without input before an idle screen drops presentation rate |
| `POKEPORT_IDLE_FPS` | `6` | Framerate while idle |
| `POKEPORT_AUDIO_RATE` | `22050` | Chip-synth sample rate (set to `44100` for full rate) |
| `POKEPORT_CPU_GOVERNOR` | `schedutil` | CPU scaling governor (`schedutil`, `performance`, `ondemand`) |


## Building

Release workflows build this automatically. Standalone builds resolve the latest published Gen1Recomp release by default:

```sh
./build-linux-arm-sbc.sh --version 0.1.75
```

For development, package a local checkout explicitly:

```sh
GEN1RECOMP_SOURCE_DIR="$PWD" ./build-linux-arm-sbc.sh --version 0.1.0
# or: ./build-linux-arm-sbc.sh --source "$PWD" --version 0.1.0
```

The generated `port.json` records the source release tag. `install-linux-arm-sbc.sh` is a macOS helper for copying a built pack to a mounted SD card.

PortMaster device support and runtime integration are maintained in the [PortMaster](https://github.com/PortsMaster/PortMaster-New) ecosystem.

# Install Gen1Recomp on Nintendo Switch

Every GitHub Release that includes Switch support ships an SD-ready zip:
`gen1recomp-*-switch.zip`. Extract it at the root of your microSD (install
or update, same steps), launch with **title override**, then import your
own legal `.gb` / `.gbc` ROM.

> You need a console that can run Switch homebrew (custom firmware / hbmenu).
> This project does not help you set that up.

Prefer building from source? See [switch-build.md](switch-build.md).

Port by [andrewqsantos](https://github.com/andrewqsantos). Community testing
help from [booshankles](https://github.com/booshankles).

## 1. Download the zip

1. Open
   [Releases](https://github.com/bryanthaboi/gen1recomp/releases).
2. Download `gen1recomp-*-switch.zip` for the version you want.
   (Optional: verify against `sha256sums.txt` in the same release.)

## 2. Extract onto the microSD

Extract the zip at the **root** of the microSD so you get:

```text
sdmc:/switch/gen1recomp/gen1recomp.nro          # native OTA launcher (hbmenu entry)
sdmc:/switch/gen1recomp/gen1recomp-game.nro     # fused LÖVE game
sdmc:/switch/gen1recomp/version.txt
sdmc:/switch/gen1recomp/pokemon-love2d/imports/
sdmc:/switch/gen1recomp/pokemon-love2d/imports/mods/
sdmc:/switch/gen1recomp/pokemon-love2d/imports/saves/...
```

Older single-NRO zips only had `gen1recomp.nro` (the fused game). Current
releases use the dual-NRO layout above. Open `gen1recomp` in hbmenu (the
launcher).

Merge folders if your OS asks. Any method works: **MTP** (DBI → Run MTP
responder + a client), **direct SD** (Hekate UMS or a card reader), or **FTP**.
Exit MTP / unmount / stop FTP cleanly before launching. Step-by-step for
macOS, Linux, and Windows: [switch-transfer.md](switch-transfer.md).

### Updating

#### Native OTA launcher (in-console)

Switch OTA runs in a separate **native launcher NRO** (libnx + curl), not the
LÖVE self-updater (`src/update/Check.lua`). hbmenu opens `gen1recomp.nro`.

When a newer release exists, the launcher downloads the same install zip
(`gen1recomp-*-switch.zip`), checks SHA-256 against `sha256sums.txt`, replaces
both `gen1recomp-game.nro` and `gen1recomp.nro` (keeps NACP version in sync
for hbmenu and Sphaira), then loads the game with `envSetNextLoad`.

If you are up to date or offline, it skips straight to the game with no
prompt. If an update is available, you get a short prompt styled like the
in-game launcher: black background, RGB rail, logo, A/B buttons. Saves under
`pokemon-love2d/` are not touched. See `src/update/SwitchOta.lua` for the
wire format.

The LÖVE self-updater stays **disabled** on NX (`networkValidated == false`).

**Sphaira forwarder (HOME shortcut):** Sphaira copies name/version/icon into
the installed forwarder at creation time. After an OTA (or zip) update, the
`.nro` on the microSD already has the new version, but the HOME shortcut
keeps the old badge until you **reinstall the forwarder once** in Sphaira
(Install Forwarder again on `gen1recomp.nro`). Browsing the NRO in Sphaira /
hbmenu always shows the live file version.

#### Manual zip (fallback)

Use the **same** extract/merge of `gen1recomp-*-switch.zip`. It replaces the
NROs (and the small help `README.txt` / `INSTALL.txt` files). Saves,
imported ROMs, mods, and options live under `pokemon-love2d/`. **Do not
delete that folder** when updating, or you will lose progress.

## 3. Launch with title override

**Applet Mode is not supported** for this game (not enough memory).

1. On the Switch HOME menu, highlight any installed title.
2. Hold **R** and launch that title. This opens hbmenu with full memory
   (title override).
3. From hbmenu, open `gen1recomp`.

Do **not** launch from the Album applet path for normal play.

## 4. Import your ROM

This project ships **no** game data. On first launch:

1. Put your own legally obtained Pokémon Red, Blue (`.gb`), Yellow, or
   Gold (`.gbc`) dump into `switch/gen1recomp/pokemon-love2d/imports/` (the
   launcher also shows the live save-dir path). All four can sit in the
   same folder.
2. Use **Scan again** on that game's tab (Red / Blue / Yellow / Gold).
   Rescan matches by ROM SHA-1 for the open tab only. A Red dump never
   imports from the Yellow tab (and vice versa). Gold is Beta in the
   launcher; a clean US Gold dump is enough to Play.

## 5. Import / Export a raw `.sav`

Continue a cart or PC battery save (or pull a slot off-console) via MTP /
SD / FTP, same transfer methods as ROMs. Paths are **per game**:

| Game | Import inbox | Export folder |
| ---- | ------------ | ------------- |
| Red | `imports/saves/red/` | `exports/red/` |
| Blue | `imports/saves/blue/` | `exports/blue/` |
| Yellow | `imports/saves/yellow/` | `exports/yellow/` |
| Gold | `imports/saves/gold/` | `exports/gold/` |

(Under the save dir `pokemon-love2d/`. The zip already creates these folders.
Gold cart `.sav` import/export is not supported yet -- the folders exist so
MTP browsing matches the other games. Gold progress still saves in-engine.)

1. Copy a Gen 1 `.sav` (32 KB) into that game's inbox under the save dir
   ([switch-transfer.md](switch-transfer.md)).
2. With the game's ROM already imported, open **that game's tab** →
   **SAVE FILES** → **Import save**. Only that folder is scanned.
3. A successful import retires the file to `*.sav.imported` and records its
   content hash so pressing **Import save** again does not clone slots.
   Failed imports leave the original `.sav` in place.
4. To pull a slot off the console, use **Export save**, then copy the file
   from that game's **`exports/<game>/`** folder via MTP / SD / FTP.

Do not put `.sav` files into git. Prefer clean copies. Some MTP clients
create `._*.sav` AppleDouble sidecars that are not real saves.

## Controls

### Gameplay

| Control | Action |
| ------- | ------ |
| D-pad / left stick | Move |
| **A** | Confirm |
| **B** | Cancel |
| **+** (Start) | Start |
| **−** (Select) | Select |
| **R** (no Select held) | Cycle game speed up |
| **L** (no Select held) | Cycle game speed down |

### Launcher

| Control | Action |
| ------- | ------ |
| D-pad / left stick | Move virtual cursor |
| **A** | Click at cursor |
| **L** / **R** | Previous / next tab |
| **Start** / **Select** | Play if a ROM is ready; otherwise Choose ROM |

### System

| Control | Action |
| ------- | ------ |
| Hold **R** on HOME, then open from hbmenu | Title override (full memory) |

## Community mods

Mods install from a zip inbox (same transfer methods as ROMs):

1. Copy a release `.zip` into the save-dir **`imports/mods/`** path the
   launcher shows (MTP / SD / FTP. See [switch-transfer.md](switch-transfer.md)).
2. In the launcher, open **MODS** → **Scan again** → enable the mod →
   **Play**.

Remote **FIND MODS** / GitHub download stays **off** on Switch. Do not put
mod zips into git. Community mods ship their own OPTIONS / rebinds. This port
does not document third-party control tables.

### Joy-Con shortcuts (Select + face)

Hold **Select** (−) and press a face/shoulder button. Without Select, A/B stay
normal gameplay confirm/cancel. These chords are the stock engine display
hotkeys (`2`/`3`/`5` are claimed before any mod pipeline hotkey runs).

| Chord | Same as PC key | Stock engine effect |
| ----- | -------------- | ------------------- |
| Select + **A** | `2` | COLORS |
| Select + **B** | `3` | TILT |
| Select + **Y** | `5` | GBC FX |
| Select + **X** | `6` | Mod pipeline hotkey (if a mod registers `6`) |
| Select + **L** | `7` | Mod pipeline hotkey (if a mod registers `7`) |

If the handheld stutters with extras on, try **OPTIONS → PERFORMANCE** →
`LOW` or `BALANCED`.

## Limitations

- You need homebrew (custom firmware, hbmenu). This project does not set that
  up.
- Launch with title override (hold **R** on a title). Applet Mode (Album) is
  not supported. The game needs full memory.
- ROMs, mods, and saves are copied manually via MTP, direct SD, or FTP. There
  is no automated deploy.
- Updates use the native OTA launcher only. The LÖVE self-updater and remote
  **FIND MODS** stay off on Switch.
- Tested on Switch OLED. Switch V1 / Erista boot confirmed by the community.
  Other models may work but are less tested.

## Prefer building it yourself?

Building the fused NRO (and SD-ready zip) from source is covered in
[switch-build.md](switch-build.md). Copying artifacts and inbox files
(MTP / SD / FTP on macOS, Linux, Windows): [switch-transfer.md](switch-transfer.md).

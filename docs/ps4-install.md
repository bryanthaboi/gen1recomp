# Install Gen1Recomp on PlayStation 4

Releases that include PS4 support ship `gen1recomp-*-ps4.pkg`: the game and its
runtime in one installable package. Install it, then import your own legal
`.gb` / `.gbc` ROM.

> You need a PS4 that runs homebrew (GoldHEN). This project does not help you
> set that up.

PS4 port by [Tomas Morello](https://github.com/tomasmorello), on
[LÖVE for PS4](https://github.com/tomasmorello/love-ps4) (LÖVE 11.5).

**Tested on real hardware:** Pokemon Red, Blue and Yellow (ROM import, play,
save and load, mods, returning to the launcher). **Not tested yet:** Gold,
Silver, Crystal, FireRed and LeafGreen. They may work; reports are welcome.

## 1. Install the package

1. Open [Releases](https://github.com/bryanthaboi/gen1recomp/releases) and
   download `gen1recomp-*-ps4.pkg` (optionally check it against its `.sha256`).
2. Copy it to a USB drive formatted **exFAT** and plug it into the console.
3. **Settings → Debug Settings → Game → Package Installer**, pick the file.
4. Launch **Gen1Recomp** from the home screen.

Updating: install the newer `.pkg` the same way; it installs over the old one.
Saves, imported ROMs and mods live in `/data/love/pokemon-love2d/`, outside the
package. **Do not delete that folder** when updating.

## 2. Import your ROM

The PS4 has no file picker, so the launcher reads an inbox folder, like the
Switch build:

1. Enable GoldHEN's FTP server (GoldHEN menu), port **2121**.
2. With any FTP client, copy your `.gb` / `.gbc` into
   `/data/love/pokemon-love2d/imports/`.
3. In the launcher, press **Scan again**.

The other inboxes work the same way (copy over FTP, then **Scan again** in
that screen), all under `/data/love/pokemon-love2d/`:

| What | Folder |
|---|---|
| Mods (`.zip`) | `imports/mods/` |
| Saves (`.sav`) | `imports/saves/<game>/`, e.g. `imports/saves/red/` |
| Custom Carts (`.g1rcart`) | `imports/carts/` |

## 3. Controls

The launcher uses **D-pad focus navigation**: the highlighted option is the
selected one; Cross confirms, Circle goes back. **Triangle** switches to the
virtual cursor and back. In game, the pad maps like on every other platform.

To quit, use the **PS button** and close the application, like any PS4 app.

⚠ **START + SHARE** belongs to GoldHEN (it opens its menu), so the "hold
START + SELECT" force-quit shortcut does not reach the game on PS4.

## 4. Already have LÖVE for PS4?

`scripts/build_ps4.sh --loose` produces a plain `game.love`: copy it to
`/data/love/game.love` and start **LÖVE for PS4** instead of installing the
standalone package.

## Building

```bash
scripts/build_ps4.sh --fetch --fused --version X.Y.Z
```

Needs the OpenOrbis PS4 Toolchain v0.5.4 packaging tools (`OO_PS4_TOOLCHAIN`)
and bash 4+. The runtime is downloaded from a pinned LÖVE for PS4 release and
verified against `scripts/ps4/love-ps4-runtime.sha256`.

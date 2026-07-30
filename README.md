# Gen1LuaReimplementation

A native LÖVE2D recreation of Poke Red, Blue and Yellow. The engine and map
behavior are converted to Lua using a LLM; game data and graphics are decoded from a ROM
supplied by the player.

## AI disclosure

This project was created with heavy use of LLMs which did the grunt work of converting the disassembly code into Lua. Note that this project is completely untested, and any issues reported will be sent back to the LLM, which will attempt a fix and this will also be merged untested. What this means it that this is not a suitable way to actually play the game and should remain a curiosity. If you want a playable version of the game, please play literally any other version. 

<p align="center"><img src="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/refs/heads/dev/assets/logo/logo.png"></p>

**SUPPORT / ANNOUNCEMENTS / MODS:** [Discord](https://bois.icu)

<p align="center">

<a href="https://www.youtube.com/@bryanthaboi">
  <img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="YouTube">
</a>
<a href="https://www.tiktok.com/@bryanthaboi">
  <img src="https://img.shields.io/badge/TikTok-000000?style=for-the-badge&logo=tiktok&logoColor=white" alt="TikTok">
</a>
<a href="https://x.com/bryanthaboi">
  <img src="https://img.shields.io/badge/X-000000?style=for-the-badge&logo=x&logoColor=white" alt="X">
</a>
<a href="https://bsky.app/profile/bryanthaboi.live">
  <img src="https://img.shields.io/badge/Bluesky-0285FF?style=for-the-badge&logo=bluesky&logoColor=white" alt="Bluesky">
</a>
<a href="https://www.instagram.com/bryanthaboi">
  <img src="https://img.shields.io/badge/Instagram-E4405F?style=for-the-badge&logo=instagram&logoColor=white" alt="Instagram">
</a>

</p>


<p align="center"> <a href="https://www.polygon.com/pokemon-red-blue-3d-voxel-mod-battle-pixels-gameplay-footage-remake/"> <img src="https://img.shields.io/badge/AS%20SEEN%20ON-POLYGON-ea2e49?style=for-the-badge" alt="As seen on Polygon"> </a> 
<a href="https://kotaku.com/pokemon-red-blue-recompilation-project-voxel-3d-mod-2000720281"> <img src="https://img.shields.io/badge/AS%20SEEN%20ON-KOTAKU-ea2e49?style=for-the-badge" alt="As seen on KOTAKU"> </a> 

  <a href="https://www.digitalfoundry.net/news/2026/07/pokemon-yellow-voxel-mod-turns-the-original-gameboy-code-into-a-stunning-world">
    <img src="https://img.shields.io/badge/AS%20SEEN%20ON-DIGITAL%20FOUNDRY-ea2e49?style=for-the-badge" alt="As seen on Digital Foundry">
  </a>
  <a href="https://www.androidauthority.com/unofficial-android-port-pokemon-red-blue-yellow-3692724/">
  <img src="https://img.shields.io/badge/AS%20SEEN%20ON-ANDROID%20AUTHORITY-ea2e49?style=for-the-badge" alt="As seen on Android Authority">
</a>

<a href="https://www.xda-developers.com/this-amazing-pokemon-red-and-blue-voxel-mod-adds-a-3d-perspective-without-an-emulator/">
  <img src="https://img.shields.io/badge/AS%20SEEN%20ON-XDA%20DEVELOPERS-ea2e49?style=for-the-badge" alt="As seen on XDA Developers">
</a>
</p>

### Watch the latest update video

[![Watch the latest update video](https://img.youtube.com/vi/8IOgqbe4YvA/maxresdefault.jpg)](https://www.youtube.com/watch?v=8IOgqbe4YvA)


This project does not include a ROM, emulate the Game Boy, transpile assembly,
or download a disassembly. A canonical US Poke Red or Blue ROM is the only
game content input.

The ROM is verified, used during import, and then released from memory. It is
not copied into the cache. Later launches load the private generated cache and
do not ask for the ROM again. Red and Blue can both be imported and played
side by side.

## Quick Start

Open the desktop app. On first boot, choose your legally obtained `.gb` file
or drop it onto the window. Import takes a few seconds and the game starts
automatically.

Only the canonical 1 MiB US Red and Blue ROMs are accepted. The importer
verifies SHA-1 before creating any game data:

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`

The packaged app contains neither a ROM nor pre-extracted game data. Music,
sound effects, and cries are synthesized while the game runs from compact
audio channel programs copied out of the verified ROM.

## Controls


| Action | Keyboard          | Controller         |
| ------ | ----------------- | ------------------ |
| Move   | Arrow keys / WASD | D-pad / left stick |
| A      | Z / Enter / Space | A                  |
| B      | X / Backspace     | B                  |
| Start  | Escape            | Start              |
| Select | Tab / Shift       | Back / Select      |


Rebind any of these in-game under **OPTIONS → CONTROLS**. Controllers are
supported out of the box.

### Hotkeys


| Key       | What it does                                         |
| --------- | ---------------------------------------------------- |
| `-` / `=` | Zoom out / in (overworld; also mouse wheel)          |
| `2`       | Cycle COLORS                                         |
| `3`       | Cycle TILT (free-roam overworld)                     |
| `4`       | Cycle ZOOM through every level (free-roam overworld) |
| `5`       | Cycle GBC FX                                         |
| `F1`      | Save                                                 |
| `F2`      | Load                                                 |
| `F10`     | Open / close the mod manager                         |


COLORS, TILT, ZOOM, GBC FX, and VOID FILL are also in the Options menu
and persist in `options.lua`.

### Rulesets

**OPTIONS → RULESET** picks which set of Gen 1 battle behaviors to run.
Both rulesets share the same damage formulas; they differ only in whether
the original's quirks are kept. The setting persists in `options.lua`, and
mods can register their own.

`gen1_faithful` is the default and reproduces the original cartridge,
famous bugs included:

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | A 100%-accurate move still misses on a roll of 255     |
| `critUsesBaseSpeed`         | Crit rate reads base speed, not the current stat       |
| `critIgnoresStages`         | Crit rate ignores stat stages                          |
| `focusEnergyBug`            | FOCUS ENERGY quarters the crit rate instead of x4      |
| `enemyUnlimitedPP`          | Enemies never spend PP, so they never Struggle         |
| `hyperBeamSkipRechargeOnKO` | HYPER BEAM skips its recharge when the target faints   |
| `randMin` / `randMax`       | Damage random factor 217-255                           |

`modern_clean` keeps the formulas but removes the notorious quirks:

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | Off: a 100%-accurate move always hits                  |
| `critUsesBaseSpeed`         | Unchanged: crit rate still reads base speed            |
| `critIgnoresStages`         | Off: stat stages count toward the crit rate            |
| `focusEnergyBug`            | Off: FOCUS ENERGY raises the crit rate as intended     |
| `enemyUnlimitedPP`          | Off: enemies deplete PP and Struggle when empty        |
| `hyperBeamSkipRechargeOnKO` | Off: HYPER BEAM always recharges, like Gen 2+          |
| `randMin` / `randMax`       | Damage random factor 217-255, same as faithful         |

## Running From Source

Requires LÖVE 11.x. Place a Red or Blue ROM in the project folder and
double-click `Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Poke Red.gb"   # or Poke Blue.gb
scripts/run.sh
```

then `love .` for later launches. Windows PowerShell scripts, the optional
developer data build, test suites, and cache management are covered in
[Developer Setup](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Developer-Setup).

## Portable Mode

By default the game keeps your save, options, and the private ROM-derived
data cache in your OS's normal per-user app data folder. To keep everything
next to the game instead (handy for a USB stick or portable drive you carry
between computers), drop an empty file named `portable.txt` next to the app
(next to `gen1recomp.app`/`.exe`, or next to `main.lua`/`conf.lua` when
running from source), then launch the game. Portable mode is desktop-only
(Windows, Linux, macOS); it has no effect on Android or iOS, where the app
runs from a read-only package.

With `portable.txt` present:

- `save.lua`, `save.lua.bak`, and `options.lua` are read from and written to
that same folder instead of the OS save directory.
- A ROM import writes the generated `data/generated` and `assets/generated`
cache straight into that folder too (nothing is left in the OS save
directory), so a later launch reuses it without asking for the ROM again
even on a different computer, as long as the same folder comes along.
- Deleting `portable.txt` switches back to the normal OS save directory; nothing
already written to either location is touched automatically, so copy files
over yourself if you want to carry existing progress across the switch.

## Handhelds

A PortMaster-style port for the **Anbernic RG34XXSP** on Stock OS 64-bit MOD
ships with every release as `gen1recomp-*-rg34xxsp-stockos64-mod.zip`.
Install steps, controls, and troubleshooting live in
[docs/anbernic-rg34xxsp.md](docs/anbernic-rg34xxsp.md).

## Modding

The game ships a native mod platform: content registries, events and hooks,
per-mod saves and options, and an in-game manager. The full modding book —
getting started, a twelve-rung tutorial ladder, a cookbook, and the generated
reference — lives on the
[project wiki](https://github.com/bryanthaboi/gen1recomp/wiki).

Shipped example mods, one per kind of author, live in `[mods/](mods/)`.

Maps can be edited in our own build of [Tiled](https://www.mapeditor.org),
[bryanthaboi/tiled_gen1recomp](https://github.com/bryanthaboi/tiled_gen1recomp/releases),
and exported back out as a mod; see
[docs/tiled-map-editing.md](docs/tiled-map-editing.md).

## Bugs and Ideas

Found a bug? A warp dropping you somewhere it shouldn't, a battle doing math
that looks wrong, text in the wrong box, anything that does not match the
original game.
[Open a bug report](https://github.com/bryanthaboi/gen1recomp/issues/new?template=bug_report.yml).
Attach a screenshot if you can. It saves a lot of back and forth, and if you
can't get one, the form asks you to describe what you saw instead.

Thought of a feature that could be good, or a way to improve one that already
exists?
[Open a feature request](https://github.com/bryanthaboi/gen1recomp/issues/new?template=feature_request.yml).
Say what you want, why it is worth doing, and how you picture it working. A
request with real detail is one that can actually get built.

## More

- [Link play](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Link-Play)
— START > LINK connects two copies directly over UDP.
- [Save editor](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Save-Editor)
— edit party, boxes, items, events, and Pokédex flags outside the game.
- `docs/architecture.md` — runtime details;
`docs/behavior-porting-notes.md` — formula provenance.



## Special Thanks

This project would not be possible without [pret](https://github.com/pret) >
the pret band of decompiling maniacs > and their
[pokered](https://github.com/pret/pokered) disassembly.

<p align="center"><a href="https://boisclub.games"><img src="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/refs/heads/dev/assets/logo/bcg.png"></a></p>

# Gen1Recomp

A native LÖVE2D recreation of Poke Red, Blue and Yellow. The engine and map
behavior are hand-written Lua; game data and graphics are decoded from a ROM
supplied by the player.

And before you say, "that's not a recomp", you're wrong. Recomp is an acronym. ***Reverse Engineering Causes Obsessive Mental Problems***

[Click Here for the AI Use Disclosure!](AIDisclosure.md)

> [!CAUTION]
> **We are NOT affiliated with the website `gen1recomp[.]com`** That website is not run by this project, was not authorized by us, and we have no idea who operates it. It is impersonating this project; do not download anything from it, and treat anything it hosts or claims as untrustworthy. Even if the site currently links back to this repository, the people behind it can change its content at any time, so nothing on it should ever be trusted. This GitHub repository and the Discord linked below are the only official sources for this project. Also, as I assumed would eventually happen, the idiot that made that website now pumped it full of adware. Please stay away from that website.

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
or download a disassembly. A canonical US Poke Red, Blue, Yellow, or Gold ROM
is the only game content input.

The ROM is verified, used during import, and then released from memory. It is
not copied into the cache. Later launches load the private generated cache and
do not ask for the ROM again. Red, Blue, Yellow, and Gold can all be imported
side by side. Gold is Gen 2 Phase 1 (import + launcher; see
`docs/gold-phase1.md`): the Gen 2 engine is still under construction.

## Quick Start

Open the desktop app. On first boot, choose your legally obtained `.gb` /
`.gbc` file or drop it onto the window. Import takes a few seconds and the
game starts automatically.

Only the canonical US Red, Blue, Yellow (1 MiB), and Gold (2 MiB) ROMs are
accepted. The importer verifies SHA-1 before creating any game data:

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`
- Yellow: `cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1`
- Gold: `d8b8a3600a465308c9953dfa04f0081c05bdcb94`

The packaged app contains neither a ROM nor pre-extracted game data. Music,
sound effects, and cries are synthesized while the game runs from compact
audio channel programs copied out of the verified ROM.

### A note on Windows Defender warnings

Windows Defender sometimes flags the Windows build with a generic
machine-learning detection such as `Trojan:Win32/Wacatac!ml` (#621). This is
a known false positive: the exe is the official LÖVE runtime with the game
archive appended (the standard way LÖVE games ship), and Defender's
heuristics distrust unsigned executables with appended data. Every release
publishes SHA-256 checksums (`sha256sums.txt`) so you can verify your
download, and you can confirm a flagged file yourself on
[VirusTotal](https://www.virustotal.com), where these builds come back clean
on every engine except Defender's heuristic. False positives are reported to
Microsoft as they come up.

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
| `1`       | Cycle GAME SPEED up (controller: R2 faster, L2 slower) |
| `2`       | Cycle COLORS                                         |
| `3`       | Cycle TILT (free-roam overworld)                     |
| `4`       | Cycle ZOOM through every level (free-roam overworld) |
| `5`       | Cycle GBC FX                                         |
| `F1`      | Save                                                 |
| `F2`      | Load                                                 |
| `F10`     | Open / close the mod manager                         |


COLORS, TILT, ZOOM, GBC FX, GAME SPEED, and VOID FILL are also in the
Options menu and persist in `options.lua`.

### Low-end devices

**OPTIONS → PERFORMANCE** scales the port's optional extras for weaker
hardware: **HIGH** (everything on), **BALANCED** (no 3D tilt or GBC FX),
**LOW** (also no survey zoom, FPS capped), or **AUTO** — the default, which
picks a tier from your device (ARM handhelds → LOW, phones → BALANCED,
normal desktops → HIGH, unchanged). It only scales presentation; the
fixed-step game logic is identical on every tier, and a lower tier hides
your tilt/zoom/GBC-FX preferences without forgetting them. Details in
[docs/new-features.md](docs/new-features.md#performance-tier-low-end-devices).

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

Requires LÖVE 11.x. Place a Red, Blue, or Yellow ROM in the project folder and
double-click `Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Poke Red.gb"   # or Blue.gb / Yellow.gbc
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

## Launch Options

By default the app opens the launcher so you can pick a game. Launch options
skip it and start one game directly, which is what you want for a one-click
entry: a desktop shortcut per game, a Steam entry, or a handheld frontend.

| Option | Effect |
| --- | --- |
| `--game=red` | boot Red, skipping the launcher (`blue` and `yellow` too, or just `r` / `b` / `y`) |
| `--slot=2` | load that save slot; takes a slot number or a slot id |
| `--launcher` | open the launcher anyway, so you can edit a shortcut you already made |


## Linux on arm64 (Raspberry Pi)

Alongside the x86_64 `gen1recomp-*-linux.zip`, every release ships
`gen1recomp-*-linux-arm64.AppImage` for 64-bit ARM desktop Linux — Raspberry
Pi 4/5, Armbian and other SBC distros, and arm64 VMs on Apple Silicon:

```sh
chmod +x gen1recomp-*-linux-arm64.AppImage
./gen1recomp-*-linux-arm64.AppImage
```

LÖVE publishes no aarch64 binary of any kind, so this artifact compiles the
engine — and SDL2, OpenAL and the codecs — from source inside a Debian
bullseye arm64 container. It needs only glibc 2.29+, libstdc++, freetype and
zlib on the host; OpenGL, X11, Wayland, KMSDRM, ALSA and PulseAudio are all
dlopened, so the same image runs on a full desktop, a Wayland-only session or
a KMSDRM handheld with no X server. Build instructions and the reasoning are
in [docs/linux-arm64-build.md](docs/linux-arm64-build.md).


## iOS

Every release ships `gen1recomp++-*-ios.ipa`. Sideload it with AltStore
(Windows or Mac) — see [docs/ios-sideload.md](docs/ios-sideload.md). To
build and install from source on a Mac instead, see
[docs/ios-install.md](docs/ios-install.md).

<div>
    <a href="https://intradeus.github.io/http-protocol-redirector?r=sidestore://source?url=https://github.com/bryanthaboi/gen1recomp/raw/refs/heads/main/mobile/ios/app-repo.json"><img src="./.github/resources/sidestore-badge.png" alt="Add to SideStore" height="60"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=feather://source/https://github.com/bryanthaboi/gen1recomp/raw/refs/heads/main/mobile/ios/app-repo.json"><img src="./.github/resources/feather-badge.png" alt="Add to Feather" height="60"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=altstore://source?url=https://github.com/bryanthaboi/gen1recomp/raw/refs/heads/main/mobile/ios/app-repo.json"><img src="./.github/resources/altstore-badge.png" alt="Add to AltStore" height="60"></a>
    &nbsp;
    <a href="https://github.com/bryanthaboi/gen1recomp/releases/latest"><img src="./.github/resources/github-badge.png" alt="Download from GitHub" height="60"></a>
</div>

## Xbox Dev Mode

Every release ships `gen1recomp-*-xbox-uwp.zip` for Xbox One and Xbox Series
consoles in Developer Mode. It cannot be installed in retail mode.

Extract the archive, then use Xbox Device Portal to install the `.msix` and
the x64 package under `Dependencies`.

### External setup

1. Put your legally obtained Red, Blue, or Yellow ROMs on an external drive.
   Mod ZIPs can go on the same drive.
2. Connect the drive to the Xbox and open Gen1Recomp.
3. Select **Import ROM** or **Import Mod**, then choose the file with the Xbox
   file picker.
4. Repeat the ROM import for each version you want to use.

### Internal setup

1. Create a folder named `baseroms` on your PC and place your legally obtained
   Red, Blue, or Yellow ROMs inside it.
2. ZIP the folder, keeping `baseroms` at the top level of the archive.
3. Launch Gen1Recomp once, then close it.
4. Open Xbox Device Portal and upload the ZIP to
   `Gen1Recomp/LocalState/pokemon-love2d/`.
5. Choose **Yes** when Device Portal asks whether to extract the archive.
6. Open Gen1Recomp. The launcher checks baseroms once at startup. When it finds a compatible ROM, that game’s tab shows ROM FOUND and an Import detected ROM button.

ROMs, generated game data, saves, and mods remain in LocalState and are not
included in the app.

Source builds and package details are covered in
[the Xbox UWP build notes](ports/uwp/BUILD.md).

## Handhelds

A PortMaster-style port for the **Anbernic RG34XXSP** on Stock OS 64-bit MOD
ships with every release as `gen1recomp-*-rg34xxsp-stockos64-mod.zip`.
Install steps, controls, and troubleshooting live in
[docs/anbernic-rg34xxsp.md](docs/anbernic-rg34xxsp.md).

## Nintendo Switch

Releases ship an SD-ready `gen1recomp-*-switch.zip`. Runtime target is pinned
[love-nx](https://github.com/retronx-team/love-nx) `11.5-nx1`. Requires a
console that can run Switch homebrew.

- Players: [docs/switch-install.md](docs/switch-install.md). Download the
  zip, extract at the microSD root (install or update), title-override
  launch, import your own legal ROM, Joy-Con controls and shortcuts.
- Builders: [docs/switch-build.md](docs/switch-build.md). `--fetch` /
  `--loose` / `--fused`, toolchain, Docker fallback, and CI vs release
  (path-gated ubuntu selftest, fused PR artifact on the main repo, release
  hard-fail).
- File transfer (MTP / SD / FTP): [docs/switch-transfer.md](docs/switch-transfer.md).

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
`docs/behavior-porting-notes.md` — formula provenance;
`docs/link-security.md` — what link play defends against, and what it doesn't.



## Special Thanks

This project would not be possible without [pret](https://github.com/pret) >
the pret band of decompiling maniacs > and their
[pokered](https://github.com/pret/pokered) disassembly.

<p align="center"><a href="https://boisclub.games"><img src="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/refs/heads/dev/assets/logo/bcg.png"></a></p>

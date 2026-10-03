# G1R Deluxe aka Gen1Recomp

A native LÖVE2D recreation of Poke Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, LeafGreen, and Emerald.
The engine and map behavior are hand-written Lua; game data and graphics are 
decoded from a ROM supplied by the player.

And before you say, "that's not a recomp", you're wrong. Recomp is an acronym. ***Reverse Engineering Causes Obsessive Mental Problems***

[Click Here for the AI Use Disclosure!](AIDisclosure.md)

> [!CAUTION]
> **We are NOT affiliated with the website `gen1recomp[.]com`** That website is not run by this project, was not authorized by us, and we have no idea who operates it. It is impersonating this project; do not download anything from it, and treat anything it hosts or claims as untrustworthy. Even if the site currently links back to this repository, the people behind it can change its content at any time, so nothing on it should ever be trusted. This GitHub repository, the Discord, and https://gen1re.com are the only official sources for this project. Also, as I assumed would eventually happen, the idiot that made that website now pumped it full of adware. Please stay away from that website.

<p align="center"><img src="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/refs/heads/dev/assets/logo/logo.png"></p>

# [SUPPORT / ANNOUNCEMENTS / MODS ALL FOUND ON THE DISCORD](https://bois.icu)

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

<a href="https://youtu.be/Q87iK8u_52o">
  <img src="https://img.youtube.com/vi/Q87iK8u_52o/maxresdefault.jpg" width="320" alt="Watch the latest update video">
</a>


## What this is

G1R Deluxe aka Gen1Recomp is a native LÖVE2D recreation of Pokemon Red, Blue, Yellow, Gold,
Silver, Crystal, FireRed, LeafGreen, and Emerald. The engine and map behavior are
hand-written Lua, ported from the [pret](https://github.com/pret)
disassemblies & C. Game data, graphics, and audio programs are decoded on first
launch from a ROM you supply.

The project does not include a ROM, emulate the Game Boy, transpile assembly,
or download a disassembly. Your ROM is verified, used during import, and
released from memory. It is never copied into the cache, and later launches
load the private generated cache without asking for it again. Music, sound
effects, and cries are synthesized while the game runs. All nine games can be
imported side by side. Gen 2 support is still under construction.

## Quick Start

1. Download the build for your platform from the
   [latest release](https://github.com/bryanthaboi/gen1recomp/releases/latest).
2. Launch it. The packaged app contains no ROM and no game data, so the
   launcher will ask for one.
3. Choose your legally obtained `.gb` / `.gbc` / `.gba` file, or drop it onto
   the window. Import takes a few seconds and the game starts automatically.
4. Repeat for any other game you own. Each one gets its own tab in the launcher.

Only the canonical US English ROMs below are accepted. The importer checks the
SHA-1 before creating any game data. FireRed, LeafGreen, and Emerald support is in beta.

| Game | Revision | ROM size | SHA-1 |
| --- | --- | --- | --- |
| Red | - | 1 MiB | `ea9bcae617fdf159b045185467ae58b2e4a48b9a` |
| Blue | - | 1 MiB | `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2` |
| Yellow | - | 1 MiB | `cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1` |
| Gold | - | 2 MiB | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver | - | 2 MiB | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Crystal | 1.0 | 2 MiB | `f4cd194bdee0d04ca4eac29e09b8e4e9d818c133` |
| Crystal | 1.1 | 2 MiB | `f2f52230b536214ef7c9924f483392993e226cfb` |
| FireRed | 1.0 | 16 MiB | `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` |
| FireRed | 1.1 | 16 MiB | `dd5945db9b930750cb39d00c84da8571feebf417` |
| LeafGreen | 1.0 | 16 MiB | `574fa542ffebb14be69902d1d36f1ec0a4afd71e` |
| LeafGreen | 1.1 | 16 MiB | `7862c67bdecbe21d1d69ce082ce34327e1c6ed5e` |
| Emerald | 1.0 | 16 MiB | `f3ae088181bf583e55daf962a92bb46f4f1d07b7` |

**Platform notes:** [Linux](docs/platforms/linux.md),
[iOS](docs/platforms/ios.md), [Xbox Dev Mode](docs/platforms/xbox.md),
[handhelds](docs/platforms/handhelds.md),
[Nintendo Switch](docs/platforms/switch.md), and
[PlayStation 4](docs/platforms/ps4.md) each have their own install steps.

**Windows Defender:** it sometimes flags the Windows build with a generic
detection such as `Trojan:Win32/Wacatac!ml` (#621). This is a known false
positive: the exe is the official LÖVE runtime with the game archive appended,
and Defender distrusts unsigned executables with appended data. Every release
publishes `sha256sums.txt` so you can verify your download, and you can check
a flagged file on [VirusTotal](https://www.virustotal.com).

## Controls

| Action | Keyboard          | Controller         |
| ------ | ----------------- | ------------------ |
| Move   | Arrow keys / WASD | D-pad / left stick |
| A      | Z / Enter / Space | A                  |
| B      | X / Backspace     | B                  |
| Start  | Escape            | Start              |
| Select | Tab / Shift       | Back / Select      |

Rebind any of these in-game under **OPTIONS > CONTROLS**.

| Key       | What it does                                           |
| --------- | ------------------------------------------------------ |
| `-` / `=` | Zoom out / in (overworld; also mouse wheel)            |
| `1`       | Cycle GAME SPEED up (controller: R2 faster, L2 slower) |
| `2`       | Cycle COLORS                                           |
| `3`       | Cycle TILT (free-roam overworld)                       |
| `4`       | Cycle ZOOM through every level (free-roam overworld)   |
| `F1`      | Save                                                   |
| `F2`      | Load                                                   |
| `F10`     | Open / close the mod manager                           |

COLORS, TILT, ZOOM, SHADER FX, GAME SPEED, and VOID FILL are also in the
Options menu and persist in `options.lua`.

**Low-end devices:** **OPTIONS > PERFORMANCE** scales the optional extras for
weaker hardware (HIGH, BALANCED, LOW, or AUTO, the default). It only changes
presentation; game logic is identical on every tier. Details in
[docs/new-features.md](docs/new-features.md).

## Documentation

Everything else lives in the [docs folder](docs/README.md) or on the
[project wiki](https://github.com/bryanthaboi/gen1recomp/wiki), which has the
modding book, link play, save editor, and developer setup guides:

- [Rulesets](docs/guides/rulesets.md): faithful Gen 1 quirks or modern cleanups
- [Online play](docs/guides/online-play.md): lobby, battles, tournaments, trading
- [Launch options](docs/guides/launch-options.md): one-click shortcuts and URLs
- [Portable mode](docs/guides/portable-mode.md): run from a USB drive
- [Running from source](docs/guides/running-from-source.md)
- [Modding](docs/modding-overview.md): mod platform, example mods, Tiled map editing
- [Architecture](docs/architecture.md)

## Bugs

Found a bug? A warp dropping you somewhere it shouldn't, a battle doing math
that looks wrong, text in the wrong box, anything that does not match the
original game.
[Open a bug report](https://github.com/bryanthaboi/gen1recomp/issues/new?template=bug_report.yml).
Attach a screenshot if you can. It saves a lot of back and forth, and if you
can't get one, the form asks you to describe what you saw instead.

## License

See [LICENSE.MD](LICENSE.MD).

## Special Thanks

This project would not be possible without [pret](https://github.com/pret) >
the pret band of decompiling maniacs > and their
[pokered](https://github.com/pret/pokered) disassembly.

<p align="center"><a href="https://boisclub.games"><img src="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/refs/heads/dev/assets/logo/bcg.png"></a></p>

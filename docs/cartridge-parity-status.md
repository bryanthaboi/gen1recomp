# Cartridge parity status

This project treats the public `pret/pokered` and `pret/pokegold`
disassemblies as the behavioral source of truth. Tests cite the routine or
data table they transcribe; screenshots alone cannot verify timing, hidden
state, random branches, or negative paths.

## What is verified automatically

- Gen 1 extraction is constrained by `tools/rom_manifest.json` and the pinned
  `POKERED_REVISION` in `tools/make_rom_manifest.py`. The ROM-backed content
  tier additionally validates imported data when a user-owned ROM cache is
  available.
- Gen 2's ROM-free fixture tier contains 107 independently isolated suites.
  Tests that inspect disassembly tables accept `POKEGOLD=/path/to/pokegold`;
  they validate that checkout directly and skip only private ROM/cache
  assertions when those inputs are absent.
- Shared timing tests cover text cadence and control commands, menu input
  holds, transitions, battle entry, common battle waits, and HP-bar drain.
- Real LÖVE fixtures exercise boot, rendering, worker extraction failure,
  save recovery, and disk-backed mod lifecycle rather than only Lua stubs.

## ROM-backed audit

The supported US Red, Blue, Yellow, Gold, and Silver revisions have also been
exercised without placing any ROM or generated cache in the repository:

- Red (`ea9bcae617fdf159b045185467ae58b2e4a48b9a`) completed the desktop
  importer, all three Red-pinned content suites, and a real-LÖVE overworld and
  battle render pass.
- Blue (`d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`) completed the desktop
  importer, loaded 222 maps, 151 species, and 165 moves, booted through real
  LÖVE, and passed the original-Blue palette/overworld render driver on Route
  1 and Pallet Town.
- Yellow (`cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1`) completed the desktop
  importer, loaded its 223-map dataset, passed the full failing-catch tutorial
  path (including the three-shake breakout and losing-my-touch branch), and
  reached the title music from the Yellow intro.
- Gold (`d8b8a3600a465308c9953dfa04f0081c05bdcb94`) completed the desktop
  importer and all 107 cache-backed Gen 2 suites. Its real-LÖVE extractor
  driver also passed the vending-menu, elevator, special-phone-call, and
  in-game-trade paths against the extracted cartridge tables.
- Silver (`49b163f7e57702bc939d642a18f591de55d92dae`) completed the desktop
  importer, all 107 cache-backed Gen 2 suites, and the same real-LÖVE menu,
  elevator, phone, and trade driver. This run additionally caught and covered
  Silver's relocated field-move `callasm` targets.

Crystal is not currently a supported version and has no extraction manifest.
Its US ROM (`f4cd194bdee0d04ca4eac29e09b8e4e9d818c133`) is rejected without
creating a cache; it is not treated as Gold or Silver.

These runs verify the importer and representative runtime paths for the Gen 1
editions and the broad cache-backed suite for Gold and Silver. They are
evidence of parity, not a claim that every reachable game state or hardware
peripheral has been tested.

### Repeating the local ROM matrix

Keep canonical, legally obtained US ROM dumps outside the repository, then
run:

```sh
scripts/test_local_rom_matrix.sh --rom-dir /path/to/private/roms
```

With no argument the runner checks
`${XDG_DATA_HOME:-~/.local/share}/gen1recomp-test-roms`, or
`POKEPORT_ROM_DIR` may name another directory. Filenames do not matter: SHA-1
identifies Red, Blue, Yellow, Gold, Silver, and the Crystal negative input. The
command imports each supported cartridge through real LÖVE into a temporary
identity, validates the generated
dataset and audio census, runs the complete Red content aggregate and all 107
cache-backed Gen 2 suites for both Gold and Silver, boots and renders every
edition, and verifies that Crystal is rejected without a complete or partial
cache. Temporary caches are deleted on exit; `--keep` retains them for
diagnosis, and `--verify-only` performs only the checksum/discovery phase. The
full run requires `love`, `xvfb-run`, `luajit`, and `sha1sum`; checksum-only
verification needs only `sha1sum`.

## Pull-request verification snapshot

The current parity/test changes were checked through both supported developer
data paths. A fresh `tools/build_data.py` Red dataset completed every tier in
`scripts/test.sh`, including content behavior, all save-editor panels, the
loopback link suite, and the independent Lua 5.4 oversize-save oracle. A full
LÖVE Red import was then substituted for that dataset and the content
aggregate passed again with its optional audio assertions active (154 cries).

The aggregate content runner now gives each self-contained mod/parity suite a
fresh Lua process. Runtime hooks, generated `Data`, screen registries, and LOVE
stubs are process-global; sharing them made a suite's result depend on which
unrelated suite ran first. UI assertions that are not timing tests explicitly
advance past `DisplayListMenuID`'s cartridge opening delay, while the timing
suite remains responsible for pinning that delay. Negative coverage includes
unsupported Crystal/version routing, corrupt and interrupted save recovery,
malformed link traffic, missing optional audio, menu cancellation, and the
old-man scripted menu refusing player input.

The `OverworldTownMap` path additionally has a real-LÖVE Gold driver at
`tests/drivers/gold_overworld_town_map.lua`. It boots a cartridge cache with no
MAP-card ownership, renders the view-only map, proves A cannot close it, and
proves B pops the screen and resumes its caller exactly once.

The PR-equivalent offline packaging checks also pass for Switch (including SD
payload verification), Xbox UWP, and Linux arm64. The committed-mod lint,
ROM-free fixture boot/worker tests, and the rendered fixture golden are green.

## Deliberate platform substitutions

These are not silently treated as implemented cartridge features:

- Gen 2 link-cable rooms and the Time Capsule require a second game endpoint.
- Mystery Gift requires the Game Boy Color infrared protocol.
- Game Boy Printer output is unavailable. The on-cartridge Diploma, Photo
  Studio portrait, and Unown stamp viewer remain testable; only printing is
  omitted.
- SGB/VRAM-loading-only routines may be no-ops where the renderer already
  draws the equivalent frame. Every such row has a reason in
  `src/script/gen2/CallAsm.lua` or `src/script/gen2/Specials.lua`.

`OverworldTownMap` is not in that category: it is normal single-player
gameplay. Wall maps and the bedroom poster now open the view-only `_TownMap`
screen and block the script until B closes it, without requiring the POKéGEAR
MAP card.

## Remaining verification boundary

A green ROM-free suite proves the transcribed rules and fixture integration;
it does not prove that every byte of every retail ROM has been imported. Run
the content tier with legally obtained Red/Blue/Yellow/Gold/Silver ROM caches
before calling a release cartridge-complete. Hardware-peripheral parity also
requires explicit protocol implementations and two-endpoint or device tests,
not a local stub assertion.

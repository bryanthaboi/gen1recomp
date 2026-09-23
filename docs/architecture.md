# Architecture

```text
packaged first boot
user-provided Pokemon Red ROM
        |
        v
RomImporter + RomExtractor (Lua)
        |
        +--> private data/generated/*.lua
        +--> private assets/generated/**/*.png
        +--> private assets/generated/audio/programs.bin
        |
        v
LÖVE2D engine + ChipAudio
```

The importer validates the ROM SHA-1, decodes tables and graphics using
bundled address/name metadata, and writes a private cache. It releases the ROM
after import and does not copy it into the cache. Normal gameplay reads only
the generated files.

`tools/build_data.py` is a separate Python/Pillow developer path that writes
the same core data and graphics into the source tree for verification.

## Runtime layout

| Area | Files | Role |
| --- | --- | --- |
| import | `src/import/RomImporter.lua` | first-boot UI, ROM validation, cache ownership |
| | `src/import/RomExtractor.lua` | ROM tables, text, pictures, PNGs, audio programs |
| core | `src/core/Game.lua` | service owner: data, input, renderer, stack, save |
| | `src/core/Data.lua` | loads `data/generated/*`, resolves TEXT_* pointers |
| | `src/core/ChipAudio.lua` | streams ROM music programs and synthesizes SFX/cries |
| | `src/core/FixedStep.lua` | 60 Hz fixed-step loop |
| | `src/core/Input.lua` | GB button abstraction, per-step edge detection |
| | `src/core/StateStack.lua` | stack of states; top updates, draws bottom-up from the last opaque state |
| | `src/core/SaveData.lua` | Lua-serialized save in the LÖVE save dir |
| render | `src/render/Renderer.lua` | 160x144 canvas, integer nearest scaling |
| | `src/render/TileRenderer.lua` | one SpriteBatch per map (8x8 quads) + border-block ring |
| | `src/render/SpriteRenderer.lua` | variable-size anchored sprite sheets, 6-frame walkers and flipped right facing |
| | `src/render/Font.lua` | glyph rendering via charmap (greedy longest match) |
| | `src/render/TextBox.lua` | dialogue box: typewriter, `\n` line, `\v` scroll, `\f` page |
| | `src/render/Camera.lua`, `Transition.lua` | follow camera, warp fades |
| world | `src/world/Map.lua` | cell queries: walkable/grass/door/warp/sign (bottom-left-tile rule) |
| | `src/world/MapLoader.lua` | generated def -> runtime Map, cached |
| | `src/world/Player.lua`, `NPC.lua` | grid movement, walk animation, wander AI |
| | `src/world/Collision.lua` | tile + entity + bounds checks |
| | `src/world/Warp.lua` | arrive-on-door and walk-off-edge warp rules, LAST_MAP |
| | `src/world/Encounter.lua` | Gen 1 encounter rate + slot buckets |
| | `src/world/OverworldController.lua` | the overworld state: input, interactions, connections, encounters |
| script | `src/script/ScriptRunner.lua` | coroutine executor for command lists |
| | `src/script/Commands.lua` | show_text, flags, battles, warps, movement, objects... |
| | `src/script/Flags.lua` | named event flags in the save |
| pokemon | `src/pokemon/*` | instances, Gen 1 stat calc, growth curves, party |
| battle | `src/battle/BattleState.lua` | battle flow + menus + message queue |
| | `src/battle/Damage.lua` | Gen 1 damage/crit/accuracy formulas |
| | `src/battle/TypeChart.lua`, `TurnOrder.lua`, `Status.lua`, `MoveEffects.lua` | subsystems |
| | `src/battle/Experience.lua`, `Catching.lua`, `TrainerAI.lua` | exp/levels, Gen 1 catch algorithm, AI |
| | `src/battle/rulesets/` | `gen1_faithful` (default) vs `modern_clean` |
| ui | `src/ui/*` | start menu, generic menu, yes/no box, party/bag lists |
| | `tools/save-editor/` | Save editor: shipped in every build, opened from the launcher's Edit button or standalone with `love . --editor` |

## Online play

Online play is owned by the launcher, not by a running game. `src/online/`
holds one persistent relay connection for the life of the process
(`main.lua` pumps it every frame, whether the launcher or a game is on
screen), and a battle is run by **arena booting** the game: no splash, no
title, no overworld, just the lockstep battle, then straight back to the
launcher with the room still selected. In-game link (`src/link/LinkState.lua`)
stays as it was and is LAN only. The relay lives in its own repo,
`../pokeserver`; `docs/link-security.md` describes protocol v2 and what it
does and does not guarantee.

- `src/online/Client.lua` - process singleton: connection, heartbeat,
  reconnect with session resume, the inbox, and the local model (presence,
  room, match, tournament). `Client.roomSession()` hands `LinkBattle` the
  same shape a LAN `Session` does.
- `src/online/Protocol2.lua` - relay protocol v2 message builders; the
  matching schemas live with the v1 ones in `src/link/Wire.lua`.
- `src/online/ArenaData.lua` - computes an ArenaProfile (engine, version,
  engine/api version, fingerprint, ruleset, vanilla or sealed cart) headless
  by mounting a version's cache, and compares two profiles
  (`equal`, `describeMismatch`).
- `src/online/ArenaBoot.lua` - the ArenaSpec: profile, role, slot, team,
  seed, parties, session, `onDone`; plus the battle options a spec turns
  into.
- `src/online/TeamPick.lua` - headless slot read, rule validation and party
  packing. `src/online/Convert.lua` - Gen 1 <-> Gen 2 mon conversion with
  Time Capsule refusals. `src/online/Trade.lua` - launcher-side trade with a
  two-file commit. `src/online/OnlineSprites.lua` - the cached party icons
  and front sprites those pickers draw.
- Boot path: `main.lua` `bootGame(version, cartId, { arena = spec })` ->
  `Game:load` / `Game2:load` skip the intro and push
  `src/ui/ArenaState.lua` or `src/ui/gen2/ArenaState.lua`, which build
  `src/link/LinkBattle.lua` (Gen 1) or `src/link/LinkBattle2.lua` (Gen 2),
  host, guest or spectator, and return the result.
- Mods in an arena: `Loader:load(data, { mode = ... })` runs `disableAll`
  (verified translations only) for a vanilla arena and `cartOnly` for a
  sealed-cart one, without touching the player's saved enable state.
- `src/import/OnlinePanel.lua` plus `src/import/online/` are the launcher's
  ONLINE tab: a small stack of screens (home, play, setup, room, watch,
  tournaments, trade) drawn from `Client`, `ArenaData` and `TeamPick`.

## Map scripts

Map-specific behavior lives in `data/scripts/<map>.lua`, keyed by the
TEXT_* constants from the map's object events. The engine dispatches a
talk interaction to (in order):

1. a hand-ported script in `data/scripts/` (`{ talk = { TEXT_X = {...} } }`),
2. the generic trainer path (object has trainer args from `object_event`),
3. the extracted plain text via the map's text pointer table.

Scripts are arrays of `{ "command", args... }` rows executed by a
coroutine so `show_text`, `ask`, `start_battle`, `warp`, `wait` block
naturally. Every hand-ported script cites its pokered source file.

## Coordinates

- **block**: 32x32 px, the unit of `.blk` layouts (`map.width/height`)
- **cell**: 16x16 px walk grid, the unit of all object/warp coordinates
- **tile**: 8x8 px graphics; a cell is 2x2 tiles, a block 4x4

A cell's behavior (collision, grass, door, warp tile) is decided by its
bottom-left 8x8 tile, matching the original engine's "tile at the
sprite's feet" checks.

## Verification

- `luajit tests/run_tests.lua` - headless behavior suite over real
  generated data (collision, warps, text, stats, damage, growth, type
  chart, encounters, a full scripted battle, save round-trip) using a
  `love` API stub.
- `luajit tests/run_save_editor_tests.lua` (plus the task-specific suites)
  - save editor pure logic and panel click tests.
- `POKEPORT_AUTOPILOT=1 love .` - scripted end-to-end run (walk Pallet
  Town, read the sign, enter Oak's Lab, take a starter, beat the rival,
  exit, cross into Route 1, win a wild battle) that captures screenshots.
- `POKEPORT_DRIVER=tests/drivers/audio_runtime_test.lua love .` - imports
  and queues title music, a sound effect, and a Pokemon cry.

### Headless caches and driver runs

- `tools/reimport.sh <version|all> [--identity NAME] [--rom PATH] [--force]`
  imports a ROM into a `POKEPORT_IDENTITY` save dir through the real
  importer (`POKEPORT_IMPORT_ONLY=1`), then checks the result against
  `CacheContract`. Default identity is `<version>-<YYMMDD>`; an identity
  that is already current prints `ready` unless `--force`. ROMs come from
  `--rom`, then `tools/reimport.local` (gitignored, `version=path` lines,
  relative paths resolve against the repo root), then the first file in
  `$POKEPORT_ROM_DIR` matching the version's No-Intro style name:
  `Pokemon - Red Version*.gb`, `Pokemon - Blue Version*.gb`,
  `Pokemon - Yellow Version*.gbc`, `Pokemon - Gold Version*.gbc`,
  `Pokemon - Silver Version*.gbc`, `Pokemon - Crystal Version*.gbc`,
  `Pokemon - Fire*Red Version*.gba`, `Pokemon - Leaf*Green Version*.gba`.
  The importer still SHA-checks whatever file is found. `--timeout` (default
  900) must be a positive integer. Each tool prints its usage with `--help`.
- `luajit tools/driver_preflight.lua <identity> <version>` prints `READY` or
  `STALE <reason>` using the same checks as `RomImporter.isReady`.
- `tools/run_driver.sh <version> <identity> <driver.lua> [shotdir]` runs the
  preflight, reimports a stale identity, then runs the driver under a
  watchdog. The first run uses `POKEPORT_SPEED=200` (a caller's
  `POKEPORT_SPEED` wins; the known 200x-sensitive drivers `game3_daycare_egg`,
  `game3_daycare_menu`, `game3_daycare_deposit`, `game3_import2_fresh_cache`
  and `game3_import2_town_map` start at 10) with a `RUN_DRIVER_LIMIT` second
  limit (default 30; `RUN_DRIVER_ALARM` is the old name). On timeout it kills
  only its own `love` and reruns once, at 200 if the first run was not 200,
  otherwise at 10. A second timeout prints `BROKEN <driver> (timed out at
  200x and 10x)` and exits 125: the driver hangs, waits for input or never
  quits. Otherwise it prints the speed that ran and exits with the driver's
  code (0 pass). Relative driver and shotdir paths resolve against the
  caller's directory.
  `tools/pty_run.py` is the pty wrapper both scripts use: it kills only the
  `love` it spawned and passes its exit status through.
- Both scripts set `POKEPORT_BACKGROUND=1` unless the caller already set it
  (`POKEPORT_BACKGROUND=0` shows the window and plays sound). On macOS
  `conf.lua` then sets SDL's `SDL_MAC_BACKGROUND_APP` hint through the FFI
  (no Dock icon, no focus change) and opens the normal-size window borderless
  at (-30000, -30000). It still renders and presents every frame, so `U.shot`
  captures the same 1024x768 backbuffer as a visible run. On every platform
  `love.load` sets the master volume to 0 and locks `love.audio.setVolume`;
  the audio device stays real, so `isPlaying`, SE hooks and cry lengths
  behave as in a normal run. A bare `love .` driver run stays visible and
  audible unless `POKEPORT_BACKGROUND=1` is set by hand.

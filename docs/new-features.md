# New features (deliberate additions beyond the original)

Intentional enhancements this port adds on top of faithful Pokémon Red
behavior. They have no Game Boy equivalent and are kept by design.
Genuine divergences from the original (things still missing, wrong, or
approximated) live in docs/known-differences.md; faithfully-ported
behavior is in docs/behavior-porting-notes.md.

## Survey zoom

The mouse wheel (or `-`/`=`), the Options **ZOOM** row, or hotkey `4`
zooms the overworld between 1 pixel per world pixel (full survey) and 2×
the window fit scale (close-up), in crisp integer steps. This has no Game
Boy equivalent:

- Connected maps render their full bodies, and their NPCs appear as
  visual-only "ghosts",  they wander but have no sight lines, triggers,
  dialogue, or collision until the map is actually entered.
- Menus, text boxes, and battles draw at normal scale on top of the
  zoomed world. Zoom input is ignored while a script, menu, or battle is
  active; the zoom offset is persisted as `save.options.zoom` (default
  `0` = FIT) and survives New Game via `options.lua`.
- Hotkey `4` ticks through every integer zoom level (survey → FIT →
  close-up → wrap). The Options row shows `FIT` / `OUTn` / `INn`.
- Beyond the border ring the void fill repeats indefinitely (see VOID
  FILL below); interiors keep their own border block. Each visible map
  area is colorized with its own SGB palette (the original recolored the
  whole screen per map).
- Neighbor maps load two connection hops out so corner-adjacent maps
  don't pop in and out, and ghost NPCs share instances with the real ones
  so their wander positions persist across seamless connection crossings
  (a warp or fresh map entry still respawns everything at its script
  position, like the original's per-entry sprite init).

## VOID FILL

The Options **VOID FILL** row picks what paints the infinite beyond-edge
space on OVERWORLD-tileset maps during survey zoom:

- **TREES** (default): solid tree wall block `$0F`.
- **WATER**: animated water tile `$14` (same hshift cycle as on-map water).
- **BLACK**: solid black.

Other tilesets are unchanged (house/cave borders stay as authored).
Persisted as `save.options.voidFill`.

## Tilt mode

The `3` key (and the Options menu TILT row) cycles a visual-only perspective
tilt of the overworld through **OFF → 15° → 35° → 50° → OFF** for an HD-2D /
diorama look. Like survey zoom this is purely presentational and has no
Game Boy equivalent:

- The entire map tilts as one rigid ground plane,  paths, grass, water,
  floors, and every background-tile structure (buildings, trees, fences,
  signs; in Gen 1 these are baked into the tile layer, not sprites),  so
  rows above the player recede and rows below come toward the viewer. Only
  things that actually *stand* on the ground draw as upright billboards,
  unscaled and pixel-identical to flat mode: the player, NPCs, item balls,
  and the standing FX attached to them (emote bubbles, the fishing rod,
  the FLY bird). The Poké Center heal-machine overlay stays on the ground
  plane with the machine tiles (it is OAM glued to a BG graphic, not a
  standing sprite). An earlier revision tried
  billboarding buildings/trees/signs too (cutting them out of the ground
  per hand-curated per-tileset tables); that chased an endless tail of
  special cases,  dense tree canopy, fences fused into grass, building
  facades with their own baked-in fake perspective,  because Gen 1's art
  was never drawn with a clean seam between ground and standing scenery. It
  wasn't merged; tilting everything but the characters as one plane is the
  simpler, shipped tradeoff (buildings recede/foreshorten with the ground
  like a photo of a diorama, rather than standing fully upright next to
  a full-height character).
- Cycling tweens the angle between levels over ~0.25s rather than snapping;
  with tilt fully off the world pass drops back onto the flat blit path, so
  flat rendering stays pixel-identical to tilt-off and off costs nothing.
- Tilt input is gated exactly like survey zoom,  honored only while
  free-roaming, ignored while a script, menu, or battle is active,  and it
  composes with survey zoom (the zoom scale feeds the projection). The tilt
  level is persisted in `save.options.tilt` (default OFF).
- It applies everywhere the overworld draws, interiors and caves included.
  Menus, text boxes, and battles render flat on top, unaffected, and the
  infinite beyond-the-border-ring fill stays flat by design.
- Collision, movement, sight lines, triggers, encounters, and scripts are
  untouched; nothing about the tilt reaches gameplay.

## Colors mode

The `2` key (and the Options menu COLORS row) cycles the display mode
through **OG RED → SGB → ADVANCED → OG → OG INV → SGB INV → CLASSIC → OG RED**
(on Blue the first slot labels **OG BLUE**; on Yellow, **OG YELLOW**).
The first three are the real colorizations; the rest are DMG-shade novelties:

- **OG RED** / **OG BLUE**: the Game Boy Color boot-ROM look for that cart --
  one global BG palette + one OBJ palette, every map, no per-map variation
  (Red/Blue ship no CGB code, so on a GBC the boot ROM colors them globally).
  The player/NPCs keep the boot-ROM OBJ color over the terrain via the OBP
  bake + post-zone redraw (`PaletteFX.GBC_BG` / `GBC_OBJ`, or Blue's blue/pink
  pair).
- **OG YELLOW** (Yellow playthrough, same `ogred` save id): Pokemon Yellow's
  authentic GBC look from `CGBBasePalettes` (`data/palettes_yellow.lua`,
  sourced from pret/pokeyellow). Per-map / per-species colors, not a single
  boot-ROM ramp -- Yellow was CGB-enhanced.
- **SGB** (default): the per-map Super Game Boy region palettes
  (`data/sgb/sgb_palettes.asm`). Sprites tint with the region palette, as on
  real SGB. (This is the mode formerly mislabeled "GBC".)
- **ADVANCED**: pokered-gbc SuperPalettes -- real per-tile GBC coloring plus
  per-species mon colors (`data/palettes_gbc.lua`). (Formerly labeled
  "RED++"; it is the richest colorization rather than anything Red-specific.)
- **OG**: force the four DMG grays (colorization off).
- **OG INV**: inverted DMG grays.
- **SGB INV**: each SGB zone palette with shade order reversed.
- **CLASSIC**: original Game Boy pea-soup greens
  (`#9BBC0F` / `#8BAC0F` / `#306230` / `#0F380F`).

The shade-remap transform is applied centrally in `PaletteFX.sendColors`, so
it covers overworld, menus, battles, and tilt upright billboards. OG RED's
global BG palette is supplied by `OverworldState:overworldBgColors` (per-map
override in the overworld pass). Persisted as `save.options.colors`; the
`gbc` / `gbc_inv` / `redpp` save ids are kept for back-compat under the new
labels.

## GBC FX

The `5` key (and the Options menu GBC FX row) cycles a "played on real
unlit-GBC hardware" post-process through **OFF → 1 → 2 → 3 → 4**. The
levels are a cumulative ladder:

- **1**: reflective-screen backing transparency.
- **2**: + LCD pixel grid.
- **3**: + pixel drop shadows.
- **4**: + sunlight glare and rainbow shimmer with a drifting light.

It runs as a final present pass after world + UI composite in
`Renderer:endFrame`, inspired by the Pixel Transparency RetroArch shader
([github.com/mattakins/Pixel_Transparency](https://github.com/mattakins/Pixel_Transparency)).
Default OFF; persisted as `save.options.gbcfx`.

Mobile GPUs often compile the pass but present a black frame, so Android and
iOS hide the row entirely, pin the level to OFF, and rewrite a level already
persisted in `options.lua` (issue #136). `POKEPORT_GBCFX` overrides that
decision either way, same tri-state as `POKEPORT_TOUCH`: `=0` refuses the
effect, `=1` forces it available. The Anbernic handheld pack exports `0` from
its launcher because the device reports `"Linux"` while its GPU is in the
phone class (see [Anbernic RG34XXSP](anbernic-rg34xxsp.md)).

## Performance tier (low-end devices)

The Options **PERFORMANCE** row scales the port's optional presentation
extras down for weaker hardware. The extras it governs are the three
heaviest things the port adds on top of the original -- the whole-screen 3D
**TILT** (transforms the entire map as a ground plane), the **GBC FX**
post-process shader (a fullscreen pass), and survey **ZOOM** (zooming out
renders the connected neighbor maps, a lot of extra overdraw) -- plus a hard
FPS ceiling. None of this touches game logic, which is fixed-step off `dt`
(`src/core/FixedStep.lua`), so every tier plays identically; they differ
only in how much eye-candy the renderer is allowed to do.

| Tier         | TILT | GBC FX | Survey ZOOM | Extra FPS ceiling |
| ------------ | ---- | ------ | ----------- | ----------------- |
| **HIGH**     | on   | on     | on          | none              |
| **BALANCED** | off  | off    | on          | none              |
| **LOW**      | off  | off    | off         | 60                |
| **AUTO**     | picks a default from the device (below) |||

- **AUTO** (the default) reads the device once at boot: ARM Linux handhelds
  (e.g. the RG34XXSP) resolve to **LOW**, phones/tablets and very-low-core
  desktops to **BALANCED**, and everything else -- a normal desktop, and
  every existing `options.lua` that predates this option -- to **HIGH**,
  so the common case is unchanged. See `src/core/Performance.detect`.
- AUTO only chooses the *default*; all four tiers are selectable, so a
  wrong guess is one row away from being overridden.
- The clamps are applied **live** against your stored options and never
  rewrite them (`Game:applyOptions`), so a lower tier hides your TILT / GBC
  FX / ZOOM without forgetting them -- raising the tier restores exactly
  what you had. (This is why the TILT / GBC FX / ZOOM rows still show your
  saved choice on a clamped tier: it's your preference, waiting for a tier
  that can afford it.)
- Persisted as `save.options.performance` (`auto` | `high` | `balanced` |
  `low`); unit-tested in `tests/engine/performance_tiers.lua`.

## Peer-to-peer link play (lua-enet)

Trades and link battles connect two copies of the game directly over
lua-enet (ENet ships inside LÖVE,  nothing to install, no server to run)
on a reliable-ordered channel, replacing the original standalone Python
room-code relay (`tools/relay_server.py`, deleted). HOST A GAME shows the
host's LAN address (UDP 7777; `POKEPORT_LINK_PORT` overrides); JOIN A
GAME enters it. Closing performs a graceful ENet disconnect so the final
confirm/bye always lands; a vanished peer exits with "The link was
broken." Internet play needs a forwarded UDP port or a VPN (deliberate
tradeoff vs. the relay). Headless tests drive the protocol over an
in-memory loopback (`Net.loopbackPair`); under LÖVE the same test file
also exercises real UDP pairing.

Red, Blue, and Yellow copies link with each other, as the real cable
does. The compatibility fingerprint hashes only data a link mode can
actually read, so Yellow's Dragonair/Dragonite catch-rate retunes (the
only R/B/Y link-surface difference) no longer read as different games
(issue #511). Moving the fingerprint is a link parity change: builds
from before this fix will refuse to pair with builds after it.

## Fair play in link and online matches

A link session is decided by the battle and nothing else, so for its
duration:

- **Game speed is pinned to normal.** The GAME SPEED option and
  `POKEPORT_SPEED` are ignored from the moment LINK PLAY opens until it
  closes, and apply again after. Fast-forward otherwise runs one peer's
  queue faster than the peer it is locked to and drains a tournament shot
  clock faster than the opponent racing it.
- **Online play runs vanilla, except for your language.** Picking ONLINE
  MATCH or TOURNAMENT with mods enabled offers to switch the gameplay ones
  off and relaunch (mods merge at boot, so a restart is the only way). The
  restart is confirmed, not silent. They stay listed as disabled, ready to
  switch back on. A mod that declares itself a translation and provably
  writes nothing but text stays on: the two games hash the same link
  surface, so a Spanish install and an English one can battle and trade,
  each reading the game in its own language and naming the other player's
  party out of its own text.
- **Only a meaningful split ends a match.** The per-turn state signature
  both peers exchange is split three ways: `actives` and `bench` carry
  species, HP, status, stat stages, PP and the rest of the party, and a
  divergence there ends the match as a draw. `volatile` carries per-turn
  flags both sides recompute anyway - a divergence there is logged and
  reported to mods, and play continues.

The relay logs which component diverged on which turn, so a desync report
names something specific.

## Custom boot text

The boot sequence replaces the Nintendo / GAME FREAK identifiers with
"bois club" / "bryanthaboi",  a deliberate branding customization. The
rest of the boot beats (copyright splash, "presents" shooting-star, the
Nidorino-vs-Gengar attract scene) mirror the original.


## Custom Options

Options persist in a standalone `options.lua` (separate from the game
progress `save.lua`), so audio/display/battle preferences survive New Game
and aren't wiped when a save slot is cleared. Changing a row in the Options
menu or cycling hotkeys `2`/`3`/`4`/`5` writes immediately; an in-game save also
flushes the live options. Old saves that still embed an `options` table are
migrated once into `options.lua` on load.

- Music / SFX volume
- PIKACHU VOL (0-7, Yellow only): trims Pikachu's PCM voice clips under the
  SFX level, so the follower's constant chatter, the title-screen cry and
  every in-battle "Pika!" can be pulled down (or muted at 0) without
  quieting the rest of the sound effects. The row is hidden on Red/Blue,
  which have no voice clips.
- Music Filter
- OG GLITCHES on / off (Gen 1 quirks vs. modern-clean battle rules)
- BATTLE LAYOUT (OG / WIDE); see "Widescreen battle layout" below
- COLORS (OG RED / SGB / ADVANCED / OG / OG INV / SGB INV / CLASSIC),  also
  hotkey `2` (OG RED = GBC boot-ROM look; ADVANCED uses pokered-gbc
  SuperPalettes + per-species mon colors)
- TILT (OFF / 15 / 35 / 50),  also hotkey `3` while free-roaming
- ZOOM (FIT / OUTn / INn),  also hotkey `4` while free-roaming; wheel and
  `-`/`=` step one level and save
- VOID FILL (TREES / WATER / BLACK) for OVERWORLD beyond-edge space
- GBC FX (OFF / 1 / 2 / 3 / 4),  also hotkey `5`
- MAX FPS (30 / 40 / 50 / 60 / 75 / 90 / 100 / 120 / 144 / 160, default 60),
  a hard render frame-rate cap (`save.options.fpsCap`).

## Battle transition cascade + white battle letterbox

Into-battle wipes still run the original eight styles inside the classic
160×144 letterbox. On wide/tall windows (survey zoom), matching black 8×8
blocks cascade outward from that square into the surrounding world so the
void outside the OG wipe fills in lockstep. Once the battle state is up,
letterbox voids around the battle canvas fill **white** instead of black
so the whole window reads as one continuous battle screen.

## Widescreen battle layout

Options **BATTLE LAYOUT** picks the battle screen's composition: **OG**
(the default: the original 160×144 arrangement, unchanged) or **WIDE**,
which gives battles a 304×144 native-pixel surface and a Gen 3-style
arrangement on it:

- the foe's status box upper left, the foe's picture upper right;
- the player's picture lower left, the player's status box lower right,
  with a longer HP bar and the numeric HP under it;
- a full-width message window;
- a split "What will X do?" prompt / 2×2 command window;
- a 2×2 move menu, navigated with all four directions, with a PP and type
  panel attached to its right.

Only the composition changes. Pictures, palettes, HP-bar colors, font
pages, window borders, sounds, animations, timing and every battle rule
stay the engine's, so a COLORS mode or an asset mod still owns the look.
Each side's picture keeps its original pixels and placement math and is
composited into its own region of the wider battlefield -- nothing is
scaled or squeezed -- and animations, which are authored in the original
160-pixel space, shift as one rigid group onto whichever side they play
on. The whole screen is drawn at the window's integer fit scale for the
wider surface, so a 304-pixel screen is drawn a step smaller than a
160-pixel one in the same window.

The wide surface is live only while the battle itself is the screen on
top: a party menu, the bag or a nickname prompt is a 160×144 screen and
brings the classic surface back with it.

## On-screen touch controls (mobile)

On Android/iOS the game draws a translucent d-pad (bottom-left), A/B
buttons (bottom-right, Game Boy diagonal), and +/- START/SELECT (bottom
center) over the frame, using Xelu's CC0 controller prompts
(`assets/touch/`). Real buttons, not gestures: press lands the frame the
finger does, sliding on the d-pad changes direction without lifting, and
multi-touch chords (e.g. hold a direction + tap B) work. The overlay only
appears while no controller is being used: the first gamepad button or
stick push hides it, the next screen touch brings it back, and unplugging
the last controller restores it immediately. Layout re-derives from the
window size on rotation. Desktop testing: `POKEPORT_TOUCH=1 love .` forces
the overlay on and lets the mouse act as a finger (`=0` forces it off).

The launcher's **Touch Controls** button opens a drag editor: move each
button freely, resize the whole pad with **-/+** (60% to 160%), **Disable**
to hide the overlay permanently (for controllers / emulation handhelds --
distinct from the temporary gamepad auto-hide), **Reset** for defaults,
**Done** to save into `options.lua` as normalized window fractions so a
different screen keeps the relative placement.

Portrait and landscape are edited and saved separately (#633): the editor
follows whichever orientation is on screen, and **Reset** only clears that
one, so a layout that works held upright does not have to double as the
one used sideways. An `options.lua` from before this split keeps its single
layout in both orientations until one of them is edited. In-game, Options →
**TOUCH PAD** toggles the same on/off flag without leaving a play session.

## Screen orientation lock (Android)

Options → **ORIENTATION** (also in the launcher's gear menu) locks the
screen to **PORTRAIT**, **LANDSCAPE** (either landscape, following the
device), or **REVERSE LANDSCAPE**, or leaves it on **AUTO** (#592). AUTO
allows every orientation but defers to the system: with auto-rotate turned
off in Android's quick settings, the game stays put instead of following
the sensor (#716). Changes apply immediately -- the screen rotates as the
row is stepped -- and persist in `options.lua`. Android only: iOS follows
the app's fixed orientation list, and desktop windows rotate nothing.

## Translation support

Every string the player can read is now reachable from a mod, so a
translation is an ordinary content mod rather than a fork.

Two things had to change. Text layout stopped counting bytes: the dialogue
box measures a line in glyphs (charmap sequences), so a 3-byte character
costs one column, a cut never lands inside a character, and a page with a
non-default `advance` re-measures instead of overflowing. That also fixed
25 vanilla English lines that were wrapping early because `é` in POKéMON
and POKéDEX costs two bytes ("I study POKéMON as" is 19 bytes and 18
glyphs, and the box was breaking it).

Second, the text the engine writes itself - battle messages, item results,
menu labels, the link-play screens - moved behind `src/core/Strings.lua`
and the new `strings` registry. Extracted script text was already
overridable through `text`; this covers the other half. Entries are keyed
by the English source, so a translation that has not reached a string yet
keeps rendering in English and a half-finished translation stays playable.

Authors generate the whole thing:

```sh
python3 tools/modkit.py translation francais --language "Francais"
```

That scaffolds a mod with every translatable string as an empty catalog,
plus a glyph-page and charmap stub, a naming-grid stub, and a
`francais-worksheet/` directory holding the English to translate from
(deliberately outside the mod: extracted text is ROM content and must not
be packed). `--refresh` re-harvests after an engine update, keeping
existing translations and parking orphaned keys rather than dropping them.

See the wiki's Translations guide.

## Save editor (bundled, reachable from the launcher)

The save editor ships inside every build instead of being a developer-only
script, and the launcher's SAVE SLOT card grows an **Edit** label next to
Delete on every slot that actually holds a save. Edit suspends the
launcher, opens that slot's file in the editor, and **Close** hands the
process back to the launcher with the slot list re-read (a rename, a badge
or a dex change shows up on the row immediately). Unsaved edits arm a
confirm first, so leaving cannot lose work. `love . --editor` still opens
it standalone, where Close quits instead; `--save <path>` points it at any
file, and a save can be dragged onto the window.

The editor now wears the launcher's visual language - the same navy radial
field, 16px translucent cards, tri-colour version rail and green/yellow/red
semantics - so the two windows read as one app. Six tabs:

- **Party**: the roster with sprites, HP bars and level chips on the left,
  and the mon inspector permanently docked on the right instead of floating
  over the list. Species, level, DVs and moves all round-trip through the
  Gen 1 formulas, so the inspector can never show illegal stats.
- **Boxes**: the 12 PC boxes as a 5x4 grid with a fill meter per box and a
  party dock, so deposit and withdraw live in one place. Empty slots are
  clickable and create a mon there.
- **Items**: money, a searchable item picker (replacing the arrows that
  cycled one id at a time through ~250 items), the configurable bag (20 slots
  by default), PC storage
  with no slot cap, and the eight badges as toggle chips. The picker, the bag
  and PC storage all scroll under the mouse wheel, so the whole catalog is
  reachable one-handed without typing a query.
- **Events**: flags, defeated trainers, taken items and per-map object
  toggles, with a real filter field and a two-column paged grid.
- **Map**: any map rendered with the game's own renderer, warps followable,
  and the player / lastHeal / lastOutdoor spawn points settable by clicking
  a cell. Setting lastOutdoor on a map the game would not accept as an
  outdoor source is refused with the reason.
- **Dex**: seen / owned completion meters and a four-column grid; owning
  implies seen and un-seeing clears owned, exactly as the game requires.

Two rules run through all of it. Every mutation goes through one funnel
that sets the dirty flag and writes the status line together, so nothing
changes silently and no branch can quietly no-op - "Party is full", "Bag is
full", "click a cell first" all say so. And every destructive verb (Remove,
Release, Clear all, Wipe dex) arms on the first click and commits on the
second, relabelling itself to `Confirm?` in between.

A validation pill in the tab rail mirrors what the running game would
quarantine on load; clicking it jumps to the tab holding the first problem.

## Tiled map editing (mod authoring)

`tools/tiled_export.py` turns the imported ROM cache into a Tiled workspace,
so maps can be edited in a real map editor and exported back out as a mod.
It has its own document: docs/tiled-map-editing.md.

## Pokédex diploma (both versions)

The Celadon Mansion 3F game designer shows the dex-completion diploma
once 150 species are owned. On Yellow, the graphic artist next to him
then offers to print it, saving the certificate as a PNG under `prints/`
in the save directory, and Bill's PC gains Yellow's PRINT BOX item which
exports the current box list the same way.

## Pokédex printing (Yellow)

Yellow's Game Boy Printer PRNT option in the Pokédex side menu is stood in
for by an image export: choosing PRNT renders the mon's entry page (sprite,
kind, number, height/weight, dex text) to a PNG at 4x scale under
`prints/` in the save directory, then reports the filename in a dialog.
No printer hardware or link cable emulation involved; the file is the
printout.

## Find Mods (community mod indexes)

A FIND MODS tab sits beside MODS in the launcher and browses a published
mod index: a metadata-only feed listing mods that live in their authors'
own repositories. The project's own index
(`bryanthaboi/gen1recomp-mod-index`) ships pre-added for every install,
so the tab opens on the official listing right away; paste another index
URL or its `owner/repo` and it is remembered in `options.lua`. More than
one index can be added, and the listings merge (the first source wins on
a duplicate mod id). Removing the official index opts out of it for good
-- it will not come back on the next launch -- and removing any index
drops its cached listing with it.

## Soft reset (all versions)

Holding A, B, START and SELECT together restarts the game the way flicking
a Game Boy's power switch did, dropping straight back to the title screen.
It works from anywhere, including mid-battle, which the QUIT entry on the
start menu cannot do: the original combo is how stationary and gift
Pokemon get their stats rerolled without sitting through a full relaunch.
Unsaved progress is discarded, exactly as on hardware.

As on the original, the four buttons have to stay held for 16 straight
polls (better than a quarter of a second) and any direction in the mix
cancels it, so it is hard to hit by accident -- including on the on-screen
touch controls, where it would take four fingers held on four separate
controls.

## Controls rebinding (CONTROLS screen)

OPTIONS -> CONTROLS lists every Game Boy button with its current keyboard
key and controller button side by side (Z/A). Press A on a row, then press
and release the key or pad button you want; the rebind commits on the
release. If that input already belongs to another row, the two rows swap,
so no button is ever stranded without an input and no input ever serves
two buttons. Holding a second key or pad button while the first is still
down backs out of the capture without touching a keyboard; Escape still
cancels too. SELECT clears one row back to its default, and START resets
every binding after a confirmation.

Controllers a system has no mapping for (common on Linux handhelds and
off-brand pads) report bare button numbers rather than names. Those are
rebindable on the same screen and show up as JOY1, JOY2 and so on in the
controller column. Recognized controllers are read only through their
named buttons, so a rebind on those is never shadowed by the factory
layout underneath it.

## Mod profiles (#593)

The mod manager's PROFILES tab holds named setups. A profile remembers which
mods are on, every mod's own options, and which save slot each game version
plays, so swapping profiles swaps the whole playthrough and not just the mod
list. The setup that existed before profiles shipped becomes PROFILE 1 the
first time the manager opens.

EXPORT.. writes the selected profile to `profiles/<NAME>.g1rmodlist` in the
save directory; drop a `.g1rmodlist` someone shared into that folder and
IMPORT.. adds it. Imported profiles never overwrite an existing one (a name
clash gets a number). Mods the shared profile names but that are not installed
are reported when the profile is applied; installing them is still a manual
trip through the mods list or Find Mods.

## Windows: no console windows on launcher actions

Checking for updates, browsing a mod index, adding a mod repo, installing a
mod and picking a ROM all run a host tool (curl, PowerShell) in a child
process. On Windows those children used to each open their own console
window, so a session could end up buried under half a dozen of them. The
game now claims one console for itself at boot and hides it; the children
inherit that invisible console and nothing pops up. Nothing else changes:
file pickers are ordinary desktop dialogs and still appear normally, and a
run started from a terminal (`lovec.exe`, what `scripts\run.ps1` prefers)
keeps its terminal and its printed output. Set `POKEPORT_CONSOLE=1` to opt
out.

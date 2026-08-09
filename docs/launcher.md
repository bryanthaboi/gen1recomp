# Launcher

The launcher is `src/import/RomImporter.lua`, the first-run / title screen
that runs before `Game:load`. Besides ROM import (see the file's own header)
it hosts a tabbed shell covering per-game save slots and a mod manager. This
file documents the runtime model; the visual spec lives separately.

## Interface localization

Launcher-owned text uses `src/core/AppLocale.lua`, independently of gameplay
and mod `Strings()` catalogs. `main.lua` applies the saved application locale
before the first launcher frame. Settings records the locale generation used
to build its rows, and `LauncherView` rebuilds the open model after a language
change so labels update immediately.

Service-layer mod-index messages use locale-neutral `AppMessage` descriptors;
`RomImporter` translates them only at the UI boundary. Index descriptions,
mod metadata, and other third-party content remain untouched. English is `en`
and the first translated catalog is Spain Spanish (`es-ES`). See
[`localization.md`](localization.md) for the architecture and contribution
rules.

## Android multi-ROM / mod / save import

On Android, `love.system.pickFile([kind])` opens the Storage Access Framework
picker (`GameActivity.showFilePicker`); the chosen file is copied into the app
save directory as:

| `kind` | Destination |
| --- | --- |
| nil / `"rom"` | `picked_rom.gb` (open) |
| `"mod"` | `picked_mod.zip` (open) |
| `"sav"` / `"save"` | `picked_save.sav` (open) |

Export uses a separate API: `love.system.createFile(suggestedName)` →
`GameActivity.showCreateDocument` (`ACTION_CREATE_DOCUMENT`), which copies
staged `pending_export.sav` to the user-chosen URI and writes `export_done.flag`
for the launcher to acknowledge on refocus.

`RomImporter` then imports on refocus / Choose:

- **ROMs** via `findPendingRom`: only a 1 MiB `.gb` whose SHA-1 maps to a
  version that is **not** yet ready counts as pending. A leftover
  `picked_rom.gb` from Red therefore cannot block Blue's Choose (issue #167).
- **Mods** via `findPendingMod`: Prefer `picked_mod.zip`, or (on Choose) any
  other `.zip` at the save-dir root (USB copy).
- **Saves** via `findPendingSav`: Prefer `picked_save.sav`, or (on Choose) any
  other `.sav` at the save-dir root.

After a successful import the consumed save-dir file is removed.

**Manual check (device/emulator):** import Red → switch to Blue → Choose →
system file picker must appear (not a silent Red re-extract) → pick Blue →
Blue becomes ready beside Red. On the MODS tab, Import mod .zip must open the
same system picker and install the chosen archive on return.

## Tab structure

`self.tab` is one of `"red"`, `"blue"`, `"yellow"`, `"mods"`. The tab bar
draws one chip per game plus a MODS chip and rebuilds `self.tabRects` every
frame so `mousepressed` can dispatch clicks; switching tabs mid-import is
allowed (a dropped ROM still routes by SHA-1 regardless of which tab shows).
On **NX**, **Scan again** is stricter: it only starts an import whose SHA-1
matches the open game tab, so a shared `imports/` folder with Red+Yellow
cannot jump Yellow → Red.

- A game tab (`_drawGamePanel`) shows the ROM card, the SAVE FILES card, the
  Play button, and the SAVE SLOT card in a responsive two-column grid (see
  Responsiveness). The MODS tab (`_drawModsPanel`) shows the mod list instead.
- The self-updater banner (`self.Check`, see `docs/updater.md`) draws as a
  centered pill in a reserved band just above the footer, on every tab. That
  position is unchanged by this redesign, so `docs/updater.md` needed no edits.

## Save slot model

All slot I/O lives in `src/core/SaveData.lua` and goes through the same fs
abstraction (`persistFs`) every other save/options call uses, so portable
mode (an `io.*` filesystem used when `portable.txt` marks the install)
keeps working unchanged.

- **Files.** A version's playthroughs live under `saves/<version>/`, one file
  per slot: `saves/<version>/slot1.lua` plus a rolling `.bak` and staged
  `.tmp` witness (`slotNames`), mirroring the write/recovery discipline
  `SaveData.save`/`load` already use for the flat legacy file. Slot ids match
  `slot%d+`; `createSlot` allocates one past the highest existing number so a
  reused id can never collide with a lingering file.
- **Registry.** The ordered slot list and which one is active persist in
  `options.lua` (via the existing `SaveData.loadOptions`/`saveOptions`):
  `options.saveSlots = { [version] = { list = {"slot1", ...}, active = "slot1" } }`.
  Custom slot labels (#205) live alongside them in the same registry:
  `options.saveSlots[version].names = { slot1 = "Nuzlocke" }`, written by
  `SaveData.renameSlot` (trimmed; an empty label clears it) and surfaced on
  each `listSlots` row as `label` (the launcher row shows `label`, falling
  back to the player name). `deleteSlot` drops the label with the slot.
  Renaming never touches the save file, so an empty slot can be labeled.
  On desktop, right-clicking a slot row opens the inline rename modal
  (Enter commits, Esc cancels); touch has no secondary button, so the
  affordance is desktop-only.
- **Active slot resolution.** `saveNames(version)`, the function every
  existing caller (`TitleState` hasSave/load/save, recovery order) already
  goes through, now resolves the *active* slot instead of a fixed flat name.
  Resolved once per version per process (`ensureVersionSlots`, cached in
  `activeSlotCache`/`slotsChecked`): a registry entry wins; otherwise a lazy
  legacy migration may create one; otherwise the flat legacy path is used
  (`save.lua` / `save_blue.lua`), so a pre-slots install keeps working as before.
- **Legacy migration.** One-time per version, lazy on first
  `listSlots`/`load`/`saveNames` call (`tryMigrateLegacy`): if a flat legacy
  file exists and no `saves/<version>/` registry does, its main + `.bak` are
  copied into `saves/<version>/slot1.lua(.bak)`, verified readable
  (`decodeSlot`: main, then `.tmp`, then `.bak`), and only then are the
  originals removed and `slot1` registered as active. A copy that fails to
  verify leaves the originals in place; migration never loses data.

The launcher-facing API:
- `SaveData.listSlots(version)` -> array of `{id, exists, name, meta}` for
  every registered slot. `name` is the save's player name, or `nil` for an
  empty slot; `meta` is `{badges, timeText, dexCount}` (the same fields the
  title screen's `ContinueInfo` shows) or `nil`. The pure part,
  `SaveData.slotSummary(save)`, is unit-testable with no filesystem.
- `SaveData.setActiveSlot(version, slotId)` registers the id if new, persists
  it as active, and updates the process cache so the very next save/load
  lands there. The launcher calls this the moment a slot row is clicked
  (`RomImporter:_selectSlot`); pressing Play needs no signature change, since
  `Game.lua`/`main.lua` still just call `SaveData.load()`/`save()`.
- `SaveData.createSlot(version)` -> new slot id, registered but with **no
  save file written**. An empty slot means the title screen offers NEW GAME
  only, which needs no further changes.
- `SaveData.deleteSlot(version, slotId)` removes the slot's
  main/`.bak`/`.tmp` files, drops it from the registry, and if it was active
  points active at another remaining slot (or clears active when the list is
  empty). The launcher's SAVE SLOT panel Delete control calls this.

## Launcher mod manager

`src/mods/LauncherMods.lua` is a launcher-only read of the mod set. It runs
before `Game:load`, so **it never loads a mod's entry chunk**; only
`manifest.json` is read and validated (`src/mods/Manifest.validate`), the way
`Loader:_discover` finds mods without running them. The real loader
(`src/mods/Loader.lua`) still owns the actual load at boot.

- `LauncherMods.list()` scans `mods/` one level deep (first id wins on a
  duplicate) and returns one row per mod:
  `{id, name, version, badge, description, enabled, status, statusDetail}`.
  `badge` is the manifest's `category`, falling back to `profile`, then
  `"MOD"`, uppercased. `enabled` reads `options.mods[id]` (missing means
  enabled, matching the loader's own default).
- `status` is `"ok"`, `"warn"`, or `"conflict"`, computed by the pure
  `LauncherMods.deriveList`/`statusFor` against `ManagerState.resolveToggle`
  and the validated manifests: `conflict` when enabling this mod collides
  with another enabled one; `warn` for an out-of-range `game_version` or an
  absent/disabled/wrong-version hard dependency; `ok` otherwise. Having no
  `love.*` calls, this half is table-driven by the test suite on its own.
- `LauncherMods.setEnabled(id, bool)` persists `options.mods[id]` as a plain
  boolean, the exact shape `Loader:_saveState` writes, so the running game
  and the in-game `ManagerState` see the change on next boot. The mods panel
  calls this on every toggle and re-derives the list right away
  (`RomImporter:_refreshMods`) so a status change (e.g. a new conflict)
  shows without waiting for a reload.
- `LauncherMods.installZip(path)` mounts the archive with
  `love.filesystem.mount`, locates the mod root via `locateRoot` (manifest at
  the zip root, or inside one top-level folder), validates its manifest, and
  copies the tree into the save-dir `mods/<id>/` before unmounting. Rejects a
  duplicate of an already-installed mod id, and accepts either an external
  path string or a LOVE `DroppedFile`, staging a dropped file into a save-dir
  temp first (mount only reaches save-dir-relative paths), the same way
  `RomImporter` handles a dropped ROM. A failed copy rolls its partial tree
  back, and every path unmounts and clears the staged temp file.
- `LauncherMods.uninstall(id)` removes `mods/<id>/` and clears
  `options.mods[id]` so a later reinstall starts from the loader's default
  (enabled). The mods panel Delete control calls this and re-derives the list.
- A mod that declares `github` shows its total GitHub downloads (every
  release's summed asset `download_count`, from the same cached release
  fetch the update check uses) as a highlighted body line like "12,345
  downloads across all releases - Released 2024-05-31 - Updated 2026-07-01"
  (first and latest `published_at`). Old cache entries written before the
  counts existed show no line rather than a wrong zero; a manual check
  refreshes them.
- The MODS panel sorts its rows by Name, Popularity (downloads),
  Release date (first release), or Last updated, chosen by chips under the
  header and persisted in `options.modSort`. Mods without release data
  (no `github` field, or a stale cache) sink to the bottom of data sorts.

## Import / Export save

The SAVE FILES card wires a raw Gen1 `.sav` battery image to the save slots
through `src/import/SaveFileIO.lua`, which sits on top of
`src/save_convert/SaveConvert.lua` and the slot API in `SaveData`.

- **Import save** is live once the game's ROM is imported (playable).
  On desktop it opens a native `.sav` picker (`chooseSav`); on Android,
  `love.system.pickFile("sav")` → `picked_save.sav`, same SAF path as ROMs.
  On **NX (Switch)** there is no picker: copy a `.sav` into
  `getSaveDirectory()/imports/saves/<red|blue|yellow>/` via MTP / SD / FTP
  (one folder per game), then press **Import save** on that game’s tab to
  ensure the inbox and rescan (same pattern as the ROM `imports/` and mod
  `imports/mods/` inboxes). Hidden `._*.sav` AppleDouble sidecars are skipped.
  `SaveFileIO.importToSlot` reads the bytes (an absolute path, a save-dir
  relative name, a dropped LOVE file, or raw bytes),
  guards the 32768-byte size, runs `SaveConvert.importSav` (which also rejects
  a bad main-data checksum), then registers a fresh slot (`SaveData.createSlot`),
  writes it (`SaveData.writeSlot`), and makes it active (`SaveData.setActiveSlot`).
  The meta stamp is re-stamped off `gen1_import` to the current numeric format
  so `SaveData.load`'s migration pass accepts the slot. On success the SAVE SLOT
  panel is refreshed with the new slot selected. On **NX**, a successful inbox
  import retires the file to `*.sav.imported` and records a content hash in
  `imports/saves/<game>/.imported-sha1` so a second **Import save** (or the same
  bytes under a new name) does not clone slots; failures leave the original
  `.sav`. Only that game’s folder is scanned.
- **Export save** is live only when the active slot actually holds a save
  (checked against `listSlots`). `SaveFileIO.exportActiveSlot` loads the active
  slot, encodes it back with `SaveConvert.exportSav` (a slot never keeps
  `rawImport`, so this is a zero-filled template export, which is valid), and
  writes `exports/<version>/gen1recomp-<version>-<slotId>.sav` under the same
  root `persistFs` writes slots to: the portable game folder when `portable.txt`
  marks the install, otherwise the save directory (`exports/` and
  `exports/<version>/` are created as needed; #752). On desktop it returns the
  absolute path (`SaveData.portableBaseDir()` when portable, else
  `love.filesystem.getSaveDirectory()`), which the notice line shows with an
  "Open folder" affordance (`love.system.openURL("file://" .. dir)`).
  On Android the bytes are also staged as `pending_export.sav` and
  `love.system.createFile(suggestedName)` opens `ACTION_CREATE_DOCUMENT` so the
  player can save to Downloads / Drive / etc.; on return `export_done.flag`
  makes focus show "Save exported."
  On **NX**, export success sets a notice with the `exports/<game>/` path and an
  MTP-oriented hint — no `openURL` / Open folder (pull the file via MTP /
  SD / FTP instead).
- **Drag-drop.** `filedropped` routes a `.sav` to the import path for the
  currently active game tab; when a non-game tab (mods, or the locked yellow
  placeholder) is showing it defaults to red, the always-present first game
  (`_savedropTarget`). `.gb` (ROM) and `.zip` (mod) routing is unchanged.
- **Failure UX.** Every error path (wrong size, bad checksum, write failure,
  nothing to export, ROM not imported yet) surfaces as a red notice line on the
  card. Nothing raises and nothing silently no-ops.

`SaveFileIO` is love-free enough to unit-test through the same in-memory
filesystem stub the slot backend uses (`tests/engine/save_file_io_tests.lua`).

## Responsiveness

Every measurement derives from `love.graphics.getDimensions()` each frame
plus the existing global scale `s = clamp(height / 768, 0.7, 1.6)`; nothing
assumes a fixed window size. The game panel's two-column grid (ROM/SAVE
FILES/Play on the left, SAVE SLOT on the right) collapses to one stacked
column, slot card below Play, when the window is too narrow for both
`~300 * s`-wide columns. The save-slot list and the mod list both scroll
(wheel, or drag on touch/desktop) clamped to their own content extent,
recomputed every draw. The tab bar labels only the active chip so it stays
narrow-safe, and content caps out at `~1440 * s` wide, centered.

The desktop window has a floor of 480x360 (`conf.lua` `minwidth`/`minheight`),
under which the cards stop being readable at all. Mobile ignores it: those
windows are fullscreen.

### Page scroll

Two columns fit any window the launcher is likely to open in; one stacked
column does not. On a phone-shaped window the ROM card, SAVE FILES, Play and
SAVE SLOT together run past the bottom, and a footer pinned to the window
bottom painted over them with the overflow unreachable.

So the whole column under the tab bar -- panel, updater banner, footer --
scrolls as one page whenever it is taller than the room below the tab bar:

- The strip, logo and tab bar stay pinned, so navigation is always on screen.
  Everything else draws at `contentTop - pageScroll` inside a scissor, and the
  footer is laid out downward from `footerTop` right after the content instead
  of upward from the window bottom.
- `RomImporter.pageScrollFor(naturalH, viewportH, scroll)` is the whole
  decision, pure and pinned by `tests/engine/launcher_page_scroll.lua`. A
  window that grows back drags the offset down with it, so the page can never
  stay parked past its own end.
- The panels report their natural height as they draw (`_drawGamePanel` and
  `_drawModsPanel` return it), so the decision reads the previous frame's
  measurement -- the same one-frame settle the two lists already rely on.
- **One scroll axis at a time.** While the page scrolls, the panels draw
  `paged`: the slot and mod lists take their natural height, keep no inner
  scroll region and report a max of 0, so the wheel, the right stick and a drag
  all move the page and never fight a list for the same gesture. Two-column
  layouts do not overflow, `paged` stays false, and every one of these behaves
  exactly as it did before.
- Hit testing follows the clip: `inside` (clicks) and `_ptIn` (hover) reject a
  rect that scrolled out of the viewport, so a control that slid under the tab
  bar cannot be clicked through it. Tab chips carry `pinned = true` and are
  exempt. `pageScroll` resets on a tab change, each tab being a different
  length.
- A press on empty background pans the page, resolved in `_updateSlotDrag` like
  every other drag here.

### Dragging on Android

The launcher is handed no move events on any platform: `main.lua` forwards
neither `touchmoved` nor `mousemoved` while it is up, which is why every drag
here is resolved by polling inside `draw` instead. Desktop polls the mouse;
Android used to poll nothing at all ("no reliable pointer polling" meant its
mouse emulation), so it had no scroll gesture whatsoever -- fine while every
scroll region was an inner list with a wheel alternative, useless the moment
the page itself became the thing that scrolls, since a phone is exactly where
it overflows.

`love.touch` is pollable, so `_pointerHold` reads the first active touch there
and hands `_updateSlotDrag` the same (held, y) pair the mouse gives on desktop.
Consequences:

- Slot rows and mod toggles ARM on press and commit on release on Android too,
  matching desktop, so a swipe that starts on a card scrolls instead of
  selecting the row it started on.
- `touchPollable` (set once in `new`) gates all of it. Where `love.touch` is
  missing, every Android path is exactly what it was: act on press, never arm,
  no drag.

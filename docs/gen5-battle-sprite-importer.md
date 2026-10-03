# Black/White battle sprite importer

Open **IMPORTERS â†’ Pokemon Black / White** and choose your own untrimmed 256 MiB
Black or White `.nds` cartridge dump. Unzip it first. The importer runs inside
the engine: no Windows decoder, download, or separate Python tool is required.
It reads the ROM locally and writes a shared pack in the save directory at
`asset_packs/gen5_bw/battle_sprites`. No ROM or extracted artwork ships with this
change or the provider example.

This beta accepts structurally valid original Black/White archives with game
codes beginning `IRA` or `IRB`, and records the source MD5. It does not use an
MD5 allowlist. Black (IRBO, USA/Europe) was tested; White and other regions have
not yet been verified. Black 2 / White 2 and trimmed dumps are unsupported.

The pack exports national dex 1â€“649 base forms, front/back, normal/shiny and
female variants. Missing female graphics use the source's male/unisex graphics.
Exporter 1.0.1 reuses the same atlas file for those identical gender variants,
keeping all entry IDs available. On tested Black this removes 2,212 duplicate
PNG encodes/writes out of 5,192 while preserving the artwork and timing.
Alternate forms, portraits, overworld sprites, audio and battle renderer changes
are outside this importer. NMAR selects the idle multicell map; the separate
wait/break sequences are not combined with that idle animation.

## Public pack contract

Declare an optional dependency to keep native graphics available when no pack
has been imported:

```json
"optional_assets": [
  { "importer": "gen5_bw", "pack": "battle_sprites", "version": ">=1.0.0" }
]
```

Use `mod.packs:info`, `mod.packs:entries`, `mod.packs:entry` and `mod.packs:read`.
Entry IDs are `normal/025/front`, `shiny/025/back` and their `/female` variants.
Each entry has `width`/`height` for the whole PNG atlas, `frames`, and a `sprite`
table containing frame `width`/`height`, `columns`, `frames`, `tickRate = 60`,
integer `durations` in ticks, zero-based `loopStartFrame`, `cycleTicks`,
`cycleCapped`, `anchorX` and `anchorY`. Cells are row-major with a common opaque
union and transparent background. Play the introduction once, then repeat the
suffix starting at `loopStartFrame`; seconds per frame are `duration / tickRate`.

Atlas exports are bounded to 240 ticks. `cycleCapped = true` means the source's
full cycle exceeds that bound; consumers should not loop the truncated atlas.
Tested Black has 180 such side/gender variants across 56 species. Their parts
have short loops, but the combined loop can be very long (664,224 ticks for one
sprite), so baking it is not practical.

## Part tracks (exporter 1.1.0)

Exporter 1.1.0 keeps every capped atlas and its `cycleCapped = true` flag
unchanged, and also publishes the complete animation as independent part
tracks. The capped entry's `sprite` gains `partsEntry` (for example
`parts/305/front`, with `/female` for genuine female art) and `partsPalette`
(`normal` or `shiny`). One `parts/...` entry serves both palettes:

- Its PNG is a palette-index atlas: red holds the source palette index and
  alpha 255 marks an opaque pixel. Its `sprite` is an inert atlas descriptor
  (`kind = "parts"`, 64-pixel rows, `cycleCapped = true`) so 1.0 consumers
  validate and skip it.
- Its `metadata` file (read with `mod.packs:metadata`) holds `format =
  "gen5-parts"`, `version = 1`, `tickRate = 60`, the union `width`/`height`
  and anchors, both palettes, `pieces` (six integers each: x, y, w, h, atlas x,
  atlas y, union-relative) and one track per multicell record. A track has
  `intro`, `period`, run-length `runs` (length, state) covering intro plus one
  loop, and `states` (nine integers each: has-canvas flag, canvas x0, y0, x1, y1,
  then the piece for OAM priorities 0 to 3, or 0).

A track's local tick is `t` during the intro, then
`intro + (t - intro) % period`. Paint priority groups 3 down to 0, and inside
each group records last to first, clipped to the union of the current states'
canvas boxes. This reproduces the source compositor's global order (priority,
then reverse insertion index) and its per-tick canvas exactly. Pieces are
rendered by the same compositor, one record, frame and priority at a time. A variant
that exceeds a part-track bound (65,536 ticks per track, 4,096 states per track,
8,192 states or 4,096 pieces in all, a 256-pixel union, or the 8 MiB entry
limit) keeps only its capped atlas and native fallback; the job result lists it
in `partTracksSkipped` and the import continues. None are skipped on tested
Black.
On tested Black all 104 capped graphics variants (90 male sides and 14
genuine female sides) matched the per-tick compositor pixel for pixel at
sampled ticks up to 2^31. All 2,596 side/gender variants parsed and composed
successfully; this is separate from White or physical Quest verification.

`mods/examples/gen5_battle_sprites` exposes the shared provider API for Gen 1,
Gen 2, Gen 3 and renderer adapters. It does not replace battle art by itself.
A voxel renderer opts in through its adapter, so importing a pack has no
gameplay or rendering effect with no consumer installed.

## Original-resolution provider output (provider 2.0.0)

Provider API and capability contract version 2 return original pixels for every
`frame(request)` call, with no resolution selector or 64×64 sampling path.
The returned `width` and `height` are the original animation-union canvas
dimensions, bounded to 256 pixels per side, for both ordinary atlas frames
and complete part-track animations. Transparent margins stay in place; the
provider does not crop each pose or change the canvas between frames.
`groundOffset = height / 2` locates the bottom anchor relative to image center.
Renderers must accept `apiVersion == 2`, use the returned dimensions and anchor,
and choose the display scale. Capabilities advertise `nativeResolution = true`,
`variableDimensions = true`, `maxFrameWidth = 256`, and `maxFrameHeight = 256`;
the fixed `frameWidth`/`frameHeight` fields are removed. The shared simulation
clock, battler identity, bounded caches, session cleanup and fallback remain.

Existing exporter 1.1 packs already store these original pixels and require no
ROM reimport. Importing a pack or enabling this provider alone does not update
battle rendering; the consuming adapter must support the version 2 contract.
The manifest's `api = 2` identifies the engine mod API separately from the
provider's renderer contract.

## Import lifecycle and distribution

Android transfers run on a background worker and publish the final picker filename
only after a complete copy. Assembly slices yield after at most eight ticks or
a soft 4 ms limit between compositions. The launcher batches these slices within
a soft 6 ms budget, with at most 24 resumes per update; a failure stops the job. Assets use source MD5
and exporter version paths, and `pack.lua` is written after all entries. A failed
first import has no published pack. A reimport of the same source/version uses
the same paths; this is not a transactional filesystem replacement.

Distribute importer/provider code only. Every player imports their own dump.
Keep the port's MIT attribution in `src/import/gen5/PROVENANCE.md` and
`ANIMAENGINE_LICENSE`. Source/pixel parity evidence and private imported packs
are local verification materials, not repository fixtures.

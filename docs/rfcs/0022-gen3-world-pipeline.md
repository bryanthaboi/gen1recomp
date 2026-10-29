# RFC 0022: a world pass for Gen 3 render pipelines

## Status

Proposed.

## Motivation

`render_pipelines` lets a mod own the overworld's world pass on Gen 1
(`OverworldController`) and Gen 2 (`World:drawPipeline`): `drawWorld`
replaces the field, `worldPresent` grades it before the UI composites. On
Gen 3 the same record is inert. `Pipelines.install` sets `worldPass = false`
for a Gen 3 dataset, so a `drawWorld` pipeline gets no options row, its level
is forced to OFF, and the field plane never asks it. A mod can only reach
the finished frame through `present`, which already contains the text box,
the menus and the map-name popup.

That rules out every display mode that has to own the world on FireRed,
LeafGreen, Ruby, Sapphire and Emerald: a 3D diorama, a voxel or paper
rendition of the field, or simply a depth-of-field that must not blur the
dialog box. The motivating mod renders the overworld as a voxel / paper /
HD-2D diorama from the player's own tiles on Gen 1 and Gen 2 and can offer
Gen 3 only a full-frame colour grade today.

## The decision it extends

The `render_pipelines` registry and its spec (`docs/modding.md`,
"Rendering pipelines"; `src/render/Pipelines.lua`) and its Gen 2 extension
(`World:drawPipeline`, documented in `docs/mod-api-gen2-compat.md`). This RFC
adds the Gen 3 call site with the same contract: one finished image or nil,
`worldPresent` folded over it, a throw retires the pipeline.

## Exact API delta

No new registry, field, event or hook. The `render_pipelines` record is
unchanged. What changes:

1. **`src/render/Pipelines.lua`**: the Gen 3 inert rule is removed. A
   `drawWorld` pipeline can be switched on, restored from options, toggled
   by its hotkey and selected by `Pipelines.worldPipeline()` on Gen 3 like
   on Gen 1 and Gen 2.
2. **`src/core/game3/display.lua` `presentPlanes`**: before drawing the field
   plane it asks `Pipelines.worldPipeline()`. A returned canvas goes through
   `Pipelines.worldPresent` and is composited by `Renderer:endFrame` exactly
   like Gen 1's `worldOverride`; nil (or a non-canvas) draws the vanilla
   plane. While the battle transition or the barn-door wipe runs, the vanilla
   plane is kept, because both paint onto the world canvas.
3. **`ctx` on Gen 3** (same keys as Gen 1 / Gen 2 where they mean the same
   thing):

   | key | meaning |
   | --- | --- |
   | `generation` | `3` |
   | `cam` | `{ x, y }` top-left of the view in world pixels (`FieldView.camera`) |
   | `vw`, `vh` | world view in world pixels |
   | `width`, `height` | playfield in LÖVE units; the result canvas is `width·dpi × height·dpi` |
   | `scale` | screen pixels per world pixel (`Renderer:fitScale()`) |
   | `level` | the pipeline's level |
   | `map` | current map id |
   | `drawField(opts)` | draws the vanilla field plane (tiles, sprites, field effects, OAM included) into the current canvas at world-pixel scale; `opts.skipActors` / `opts.actorsOnly` split it into ground and actors. Sprite animation ticks on the first call per frame only. |

   There is no `ctx.drawFx` on Gen 3: field effects are actors of the field
   plane there and come with `drawField`.
4. **`FieldView.camera(game, w, h)`**: the camera `FieldView.draw` tracks,
   exposed so the context and a pipeline agree on it.
5. **`src/ui/game3/option_rows.lua`**: every pipeline gets its OPTION row,
   not only `present` pipelines.

## Migration

Nothing. A pipeline with `drawWorld` that was registered for Gen 1 / Gen 2
only already guards on `ctx.state` or the generation; on Gen 3 it now gets a
row and can be switched on. A mod that cannot draw Gen 3 answers `nil` from
`drawWorld` (the vanilla plane draws) or `false` from `available`.

## Backward compatibility

- No v1 surface is touched: `content.X:register/override/get`, `events:on`,
  `hooks:wrap`, `mod.log`, `mod:read`, the manifest fields and
  `pokemon.before_give` are unchanged; `mods/example_mew_starter` loads as
  before.
- Gen 1 and Gen 2 are unchanged: the removed rule only ever applied to a
  Gen 3 dataset. `tests/drivers/gold_pipeline_shots.lua` (Gold, 22 checks)
  and a Gen 1 voxel pipeline run unchanged.
- With no world pipeline switched on, a Gen 3 frame is the frame it was:
  `presentPlanes` takes the old branch and `setWorldOverride(nil)` is a no-op.

## Verification

- **No-mod test** (`tests/mod_render_tests.lua`, Gen 3 section): a Gen 3
  dataset with the pipeline off leaves `worldPipeline()` nil and calls no
  draw callback; the existing mod-free checks still hold.
- **Mod-API test** (same section): a mod loaded through the public loader
  registers a `drawWorld` pipeline; bound to Gen 3 it can be switched on,
  owns the world pass, receives `ctx.generation == 3`, honours its own
  `gate`, and restores from options. These checks fail on the old code
  (4 assertions) and pass now.
- `tests/engine/game3_shaderfx_options_test.lua`: the assertion that a
  world-only pipeline gets no Gen 3 row is turned into the new rule.
- **In-engine** (`tests/drivers/game3_pipeline_shots.lua`, FireRed): with
  logic frozen between an off/on pair, a pipeline that draws
  `ctx.drawField()` and scales it to the window is **pixel-identical** to the
  vanilla frame; ground-then-actors is pixel-identical too; sprite animation
  ticks at the same rate with one or two `drawField` calls; a declining and a
  throwing pipeline both leave the vanilla frame, and the thrower is retired.

## Scope, and what is deliberately not in this change

- The flat fallback path (`presentFlat`, used only when the plane path has
  failed) stays vanilla.
- Battles, full-screen menus and the shop camera stay vanilla: like Gen 1 and
  Gen 2, a pipeline owns the overworld field.

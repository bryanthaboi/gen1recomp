# Pokemon Recolor

Gives each species its own colour palette, repainting the battle sprites
your ROM already produced. Nothing else in the game is touched.

Vanilla shares ten hand-tuned palettes across all 151 species: every
starter line is one green, twenty-four species share a single grey. This
mod derives a palette per species instead — currently from Gen 3 artwork,
though the pipeline does not care where the reference colours come from.

## Try it

```sh
python3 tools/modkit.py validate mods/pokemon_recolor
```

```sh
luajit mods/pokemon_recolor/tests/pokemon_recolor_test.lua
```

Enable it (`pokemon_recolor = true` under `mods` in `options.lua`, or the F10
manager) and **start a game** — not just the launcher, since the transform
runs at boot. It derives its art once into `save/mod-derived/pokemon_recolor/`.

## What it does

Nothing is replaced; the sprites are **recoloured**. The Game Boy pic is
already the right size, the right silhouette, and already on your disk from
your own ROM import. All it lacks is colour.

So instead of importing Gen 3 sprites, the mod imports Gen 3 *palettes* —
four RGB triples per species — and repaints your own art with them.
`ramps.lua` is a table of integers. **The mod carries no images at all.**

Vanilla shares ten hand-tuned palettes across all 151 species: every
starter line is one green, twenty-four species share a single grey. This
gives 120 of them a ramp derived from their own Gen 3 artwork.

## Choosing per species

`ramps.lua` is both the record of what was chosen and the input that
preserves it. Each species carries a `variant`, and the ramp below it is
what that choice produced:

```lua
{ id = "CHARMANDER",  variant = 4,
  ramp = { {255,246,223}, {255,156,79}, {173,64,25}, {39,13,0} },
  front = "battle/front/charmander.png",     back = "battle/back/charmanderb.png" },
{ id = "VENUSAUR",    variant = 1 },
```

| | |
|---|---|
| `1` | leave it on its vanilla palette — recorded, never repainted |
| `2`, `4` | `kmeans` — cluster the Gen 3 colours by luminance |
| `3` | `histogram` — match the two colour distributions in step |

Currently 80 kmeans, 40 histogram, 31 vanilla, reviewed by eye across the
whole dex. To change any of it, edit the `variant` and re-run:

```sh
cd mods/pokemon_recolor && python3 tools/derive_palettes.py ~/pokeemerald/graphics/pokemon
```

The tool works out both where your data lives and which game to read.

For the directory: `portable.txt` beside `main.lua` if you run portable,
otherwise the per-user path for your OS (`~/Library/Application
Support/LOVE/` on macOS, `%APPDATA%\LOVE\` on Windows,
`~/.local/share/love/` elsewhere), under the identity from `conf.lua`.
`--cache` or `POKEPORT_SAVE_DIR` override it.

For the version: it looks for a complete import of Red, Blue or Yellow and
uses it if there is exactly one. With several it stops and asks for
`--version` rather than picking — the battle pics differ between versions,
so guessing wrong would produce ramps quietly matched against the wrong
artwork instead of a visible failure. (Red keeps its cache at the root
while Blue and Yellow use a subdirectory; the tool knows.)

The tool reads the existing variants before regenerating, so your choices
survive. It is idempotent: running it twice in a row produces a
byte-identical file. `--reset` throws the choices away and rebuilds
everything with `--matcher`.

The two matchers differ in how they pick four colours out of the fifteen a
Gen 3 sprite may use. `histogram` walks both cumulative distributions in
step, so each Game Boy tone lands on the Gen 3 colour holding the same
tonal position by area — good when the artwork shades smoothly. `kmeans`
groups colours belonging to the same region and takes each group's bulk —
better when a species is built from two strong separated colours.

Both then get four visually distinct steps and are rescaled onto the
near-white/near-black anchors the engine's own palettes use. That last step
matters more than it sounds: without it the ramps keep only ~74% of
vanilla's contrast and read washed out at 40px.

## Two engine details worth knowing

**`trueColor`** is set on every repainted species. Without it the renderer
re-shades the sheet into the active palette's four greys on its way to the
screen and the colour is thrown away.

**The Pokedex needs a hook.** Most pic consumers (`PartyMenu`,
`HallOfFame`, `TrainerCard`, `OakSpeech`) load through `Assets.resolve` and
pick up derived art for free, but `DexEntryMenu` calls
`love.graphics.newImage` on the raw path and would show the untouched
original. `main.lua` works around it through the `pokemon.sprite` hook,
which runs inside `Sprites.path` — a code path the dex does go through.

## Changing a variant? Re-run the tool

`AssetTransform` only ever writes; it has no notion of a file it used to
produce and no longer does. A species you switch back to vanilla would keep
its old repaint on disk, the resolver would go on finding it, and — with
`trueColor` now off — the engine would re-quantise that coloured sprite
into four greys. It looks broken and the cause is three steps away.

The tool clears `save/mod-derived/pokemon_recolor/` on every run so this cannot
happen. `--keep-derived` opts out, with that caveat.

## Empty state

No ROM imported? `ctx.exists()` is false for every pic, the transform
writes nothing, the mod still loads, and `main.lua` logs what to do. It
never errors.

## Legal posture

This mod carries no ROM-derived bytes, and `modkit lint` can prove it,
because it carries no images at all. The ramps are numbers computed from
artwork; the sprites they repaint are decoded on your machine from your own
cartridge dump and never leave it.

## Credits

- pret/pokered — the battle pic layout this repaints.

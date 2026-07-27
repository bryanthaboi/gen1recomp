# Silly Oak Intro Example

Hooks Oak's NEW GAME speech: extra questions, sprite swaps (Oak, rival,
player, MEW, and a custom Toast Kid pic), and answers stored in `mod.save`.

## Try it (play through yourself)

```sh
rm -rf mods/example_silly_oak
cp -r mods/examples/example_silly_oak mods/
love .
```

Then **NEW GAME** and mash A / pick the menus. Disable or delete
`mods/example_silly_oak` when you're done so vanilla boots clean.

## Headless check

```sh
luajit mods/examples/example_silly_oak/tests/example_silly_oak_test.lua
```

## Auto driver (screenshots + save asserts)

```sh
rm -rf mods/example_silly_oak
cp -r mods/examples/example_silly_oak mods/
SHOT_DIR=/tmp/silly_oak POKEPORT_IDENTITY=silly_oak_driver_test \
  POKEPORT_DRIVER=tests/drivers/silly_oak_intro_test.lua POKEPORT_SPEED=8 love .
```

`POKEPORT_IDENTITY` keeps this run's save out of your normal slot.

## What it demonstrates

| Seam | Where |
|---|---|
| `hooks:wrap("intro.oak_speech.build")` | `main.lua` — reshape the step list |
| `mod.ui.insertStepAfter` / `insertStepBefore` | `main.lua` — anchored on vanilla step ids |
| step kinds `say` / `yesno` / `choice` | `main.lua` |
| pics: `"oak"`, `"rival"`, `"player"`, pokemon, custom image | `main.lua` |
| `events:on("intro.oak_speech.answered")` | `main.lua` → `mod.save` |
| `events:on("intro.oak_speech.finished")` | `main.lua` |

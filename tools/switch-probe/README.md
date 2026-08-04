# switch-probe — love-nx hardware probe

**NOT FOR RELEASE.** This package is a developer-only diagnostic for Nintendo Switch (love-nx). Do not ship it inside `game.love` or release NRO payloads.

## Purpose

Validate Phase 0 runtime facts on real Switch hardware before running the full Gen1Recomp launcher:

- `love.system.getOS()` (expect `NX` on Switch)
- Window dimensions (`love.graphics.getDimensions()`)
- Save directory path (`love.filesystem.getSaveDirectory()`)
- Gamepad / joystick / touch event logging

To date this probe has only been run on **Switch OLED** (see `docs/switch-hardware-evidence.md`); other models are untested. Deploy beside `gen1recomp.nro` remains **manual** (MTP); see `docs/switch-development.md`.

## Fields shown on screen

| Field | Source |
| ----- | ------ |
| OS name | `love.system.getOS()` |
| Dimensions | `love.graphics.getDimensions()` |
| Save directory | `love.filesystem.getSaveDirectory()` |
| `love._os` | Engine boot hint (when available) |
| Event log | Last 24 `gamepad*`, `joystick*`, `touch*` events |

## Build `.love` (from repo root)

```bash
(cd tools/switch-probe && zip -9 -r ../../.bazinga/work/switch-probe.love main.lua conf.lua)
```

Or:

```bash
mkdir -p .bazinga/work
zip -9 -j .bazinga/work/switch-probe.love tools/switch-probe/main.lua tools/switch-probe/conf.lua
```

Deploy beside `gen1recomp.nro` (loose mode) per `docs/switch-development.md`, renaming to `game.love` only for a probe run — use a separate SD folder so probe and game builds do not mix.

## Desktop smoke (optional)

```bash
love tools/switch-probe
```

Expect desktop `getOS()`; input events appear when using keyboard/gamepad/touch (if available).

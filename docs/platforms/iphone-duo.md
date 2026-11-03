# iPhone Duo (foldable) layouts

On a device that reports a hinge (the iPhone Duo on iOS 27.1+), the game and
the touch pad get their own areas for each posture instead of sharing one
screen. Ordinary iPhones, iPads and desktops are unchanged.

| Posture | Game | Touch pad |
| --- | --- | --- |
| Half open, clamshell (window taller than wide) | top half | bottom half |
| Half open, book (window wider than tall) | left page | right page |
| Open flat, portrait | top | underneath |
| Open flat, landscape | centre | a rail for each thumb |
| Closed, cover screen, portrait | top | underneath |
| Closed, cover screen, landscape | full screen | standard overlay |

Nothing is placed on the fold. The layouts use the whole panel, including
the cover display's camera column and the home-indicator band; only the
cover display in landscape keeps its safe area, because content under its
camera column does not show. Positions and size edited in the touch layout
editor are saved per posture and stay inside the posture's control area.
The ... menu row opens along the bottom edge of the game picture, clear of
the controls.

## Build requirement

None beyond the usual iOS build. `GRHingeBridge.swift` looks up
`UIHingeInteraction` (added in iOS 27.1) at run time instead of naming it, so
the app builds with any Xcode. On earlier iOS versions and on devices without
a hinge the bridge reports no hinge and nothing else changes for them. Duo
behaviour has been verified with builds from Xcode 27.1.

## How it works

- `mobile/ios/native/GRHingeBridge.swift` attaches a `UIHingeInteraction`
  to the key window and exposes it to Lua as `love.system.getHinge()`
  (`"closed"|"partial"|"open"|"unknown", angle`), or nil without a hinge.
- `src/core/DuoPosture.lua` resolves the posture from the hinge and window
  geometry (outer display = long side under 760 pt; the fold is the middle
  of the inner display) and returns the game rect and control areas.
- `src/render/GameViewport.lua` uses the game rect as the default
  `render.viewport`; `src/core/TouchControls.lua` lays the pad out in the
  control areas, drawing the standard buttons there.

## Testing without a Duo

`POKEPORT_DUO_HINGE=closed|partial|open[:angle]` forces a hinge reading
(`off` disables the layouts). With `POKEPORT_TOUCH=1` and a desktop window
of the inner display's size (for example 669x951 for the clamshell), every
posture can be previewed on a desktop. Headless checks (also run by
`scripts/test.sh`):

```bash
luajit tests/engine/duo_posture_test.lua
luajit tests/engine/duo_touch_controls_test.lua
```

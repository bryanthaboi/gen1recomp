# Save Editor

Ships inside every build. Two ways in:

**From the launcher.** Every SAVE SLOT row that holds a save carries an
**Edit** label next to Delete. Edit suspends the launcher and opens that
slot's file; **Close** hands the process back with the slot list re-read.
This is the path most people use, and it is wired in `main.lua`
(`openEditor` / `closeEditor`).

**Standalone**, where Close quits instead:

```bash
# from repo root, game closed
love . --editor
# or
POKEPORT_EDITOR=1 love .
# open a specific save (any path)
love . --editor --save "/path/to/save.lua"
```

By default it loads the game's active save slot under the LÖVE save
directory (same identity as the game, deliberately: the editor edits the
game's saves and reads the game's ROM cache):

- macOS: `~/Library/Application Support/LOVE/pokemon-love2d/`
- Linux: `~/.local/share/love/pokemon-love2d/`
- Windows: `%APPDATA%\love\pokemon-love2d\`

If the file isn't there (or you want another copy), use **Open...**, drop a
`save.lua` onto the window, or pass `--save`. Each write makes
`save.lua.bak-YYYYMMDD-HHMMSS` first.

## Layout

| file | role |
| --- | --- |
| `Theme.lua` | the launcher's palette + drawing primitives (cards, glow, dashed outlines, letterspaced captions) |
| `Kit.lua` | immediate-mode widgets built on Theme: buttons, rows, meters, chips, checkboxes, a real text field, pagers |
| `PadInput.lua` | virtual cursor for Switch / gamepads (stick move, A click, B close, shoulders cycle tabs) |
| `Ops.lua` | **every mutation**, behind one funnel that sets dirty + status together |
| `App.lua` | chrome (version rail, title bar, tab rail, status bar) and the panel router |
| `panels/` | one file per tab; pure layout that dispatches into Ops |

`panels/SpeciesPicker.lua` is the one exception to "one file per tab": it is
the modal species search the inspector opens, drawn by `App.draw` after the
panel rather than routed through the tab table. Kit has no z-order, so while
it is up `Kit.blockClicks` shields every widget underneath it.

### Switch / gamepad

On Nintendo Switch (and any gamepad without a mouse), the editor uses the same
virtual-cursor idea as the launcher: left stick / D-pad moves a pointer, **A**
clicks, **B** closes (with the usual unsaved confirm), L/R cycle tabs, and the
right stick scrolls lists. Touch taps forward as clicks. Without that path the
editor soft-locked until HOME — `main.lua` used to drop all pad/touch events
while `editorMode` was set.

The design reference is the `SaveEditor.dc.html` mockup that this port
transcribes; its measurements are in the same pixel space `App.lua` draws in.

Two rules the code enforces and the tests assert:

1. `Ops.mark(S, msg)` is the only thing that sets `S.dirty`, and it always
   writes the status line at the same time. Refusals go through `Ops.say`,
   which speaks without dirtying. No branch may silently no-op.
2. Destructive verbs go through `Ops.arm(S, id, msg)`: the first call arms
   and returns false, a second within `Ops.ARM_SECONDS` commits.
   `Ops.armLabel` relabels the button to `Confirm?` in between.

## Headless tests

Run from repo root (`luajit`, or the same interpreter as
`tests/run_tests.lua`). All four run in CI as their own tiers in
`scripts/test.sh`:

```bash
luajit tests/run_save_editor_tests.lua      # SaveIO, App load/save/close, party + inspector, all-tab draw smoke
luajit tests/save_editor_task6_tests.lua    # Boxes + Items rules
luajit tests/save_editor_task7_tests.lua    # Events + Dex rules
luajit tests/save_editor_task8_tests.lua    # map browser + spawn points
luajit tests/save_editor_mod_tests.lua      # modded species/items stay editable
luajit tests/save_editor_pad_input_test.lua # pad cursor / NX input routing
```

They drive `Ops.lua` rather than clicking pixel coordinates. The panels are
layout over Ops, so a redesign moves every coordinate but none of the
rules; asserting against Ops is what keeps the suites meaningful across one.

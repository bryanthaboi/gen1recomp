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

## Editing and mobile layout

Party, Boxes, Items, Events, Map, Pokédex, Trainer and Checks are separate pages.
The Pokemon inspector has Main, Stats, Moves, Origin, Extras and Checks sections.
Wide windows show the roster beside the inspector; phones stack a party grid
above it on one scrolling page. The inspector opens with the Pokemon's sprite,
types, level and HP, then section tabs (a dropdown when the tabs do not fit),
the section form and a row of tools for that section. Numbers have a typed
value box and a slider that commits when released. Buttons share the launcher's painter and font scale,
with a minimum 44px target. Pages and screen sections use dropdown popup
choosers on both phones and desktop. The current page stays in place behind
the scrim; choosing a destination closes the popup and slides to that section.
Popups support finger/wheel scrolling, keyboard selection, Escape, a close icon
and outside-tap dismissal. They shield the page underneath from clicks and scrolling.
Short screens use compact storage
actions and an item Tools menu. Map browsing splits into Maps and View
sections on phones; Player, Heal (Spawn in Gen 2) and Outdoor (Gen 1) buttons
sit on top of the map in every layout and act on the selected cell; storage and
inventory actions stay in their viewport.
Safe-area margins protect controls around notches.
Short landscape map views have an expand icon that gives the map the editor's
full content area; the back icon restores the editor chrome.
Sections use the launcher's directional slides and saved reduced-motion option.
Selected controls keep the same dark face, corner shape and icon/text layout;
an inset accent outline indicates selection. Every editor button is flat with
a visible 14px corner radius, explicit curve segments and smooth opaque fill edges,
including green and blue actions, hover, selection and disabled states.
Scrollbars sit in the card padding rather than covering button edges.
Lucide icons replace character arrows, dropdown carets and action glyphs.
Buttons retain their complete labels, wrapping between words when needed;
layouts measure the font and reflow controls rather than adding ellipses or
hiding their text. Only explicitly icon-only controls, such as steppers and
close icons, omit labels. Inventory and storage actions reserve space for
the full confirmation label before they are armed.
Pokédex cards put fully spelled out Seen and Owned controls below the species
name. Bulk tools, sorting and the National Pokédex toggle use a labeled popup
so they leave room for the species list on phones.

On phones, **More** opens Reload, Open and Close. Lists and forms scroll by wheel,
right stick or finger drag. A drag does not activate the control under its release.
Tapping outside a text field lowers the mobile keyboard. **Set** or Enter applies
a form value; Escape cancels typing. Navigation also clears text focus.

Main edits species, nickname, level, exact experience, current HP, status,
held item, friendship, nature, ability, gender and shininess where the generation
supports them. Stats edits DVs/stat experience or IVs/EVs and shows calculated
stats. Moves edits each move, PP and PP Ups. Origin exposes OT identity,
PID/SID, language, met data, ball, markings, egg and fateful flags; Crystal
also exposes caught data. Extras exposes Gen 3 contest conditions and ribbons.
Trainer edits name, IDs, gender and wallet. Items separates Bag, PC, Wallet and
Badges. Boxes supports storage, deposit, withdraw, clone, inspect and release.
Crystal also shows Buena points in Trainer and Items / Wallet. The Blue Card
balance accepts whole numbers from 0 to 30 through the numeric popup and supports
Undo/Redo; it preserves the password, daily state and Blue Card inventory.
FireRed, LeafGreen and Emerald also show Berry Powder in Trainer and Items /
Wallet. It accepts whole numbers from 0 to 99999 and supports Undo/Redo; the
.sav export re-encrypts it with the save's key. Ruby and Sapphire have no Berry
Powder, so the row is hidden there.
Ruby, Sapphire and Emerald also show Volcanic Ash in Trainer and Items / Wallet.
It accepts whole numbers from 0 to 9999 and supports Undo/Redo. Edits update
`VAR_ASH_GATHER_COUNT`, the Soot Sack currency spent at the Glass Workshop;
Lua saves and cartridge `.sav` export preserve that same variable. Other
editions do not show the row.
Emerald also shows Battle Points in Trainer and Items / Wallet: the Battle
Frontier balance spent at the Exchange Service Corner. It accepts whole numbers
from 0 to 9999 and supports Undo/Redo; the `.sav` export writes the Frontier
`battlePoints` word and leaves the trainer card's earned-BP total alone.

**Undo/Redo** and Ctrl/Cmd+Z (Shift+Z to redo) retain up to eight session snapshots.
Snapshots preserve unknown metadata. Saving establishes the clean history point;
reload/open resets history. Each file write still makes a backup first.

## Property checks

Checks audits party and storage; selecting a result opens that Pokemon's details.
It checks numeric ranges, game catalogs and name glyphs, IV/DV/stat experience,
total EVs, calculated stats/HP, level/experience, moves/PP/PP Ups, held items,
PID-derived traits, OT/met fields, egg rules, Pokerus, markings and ribbon ranks.
Input forms refuse malformed numbers and values outside their stated ranges.

This is **not full PKHeX legality parity**. Encounter matching, evolution and
breeding move combinations, event distributions, transfer provenance and PID/IV
RNG correlation are not fully verified. A record without property errors remains
**unchecked**, never certified legal. Ribbon/event and unusual move origins are
shown as warnings. Checks is read-only and does not rewrite provenance.

## Modules

| File | Role |
| --- | --- |
| `Theme.lua`, `Kit.lua` | Shared launcher faces with editor input and clipped scrolling |
| `Chooser.lua`, `Motion.lua` | Popup navigation and launcher transitions |
| `Properties.lua`, `Legality.lua` | Property schema and read-only reports |
| `History.lua`, `Ops.lua` | Session undo and save mutations |
| `InspectorBody.lua` | Generation-aware inspector forms |
| `App.lua`, `panels/` | Adaptive chrome, pages and modal pickers |
| `PadInput.lua` | Switch/gamepad pointer, actions and scrolling |

Switch/gamepad controls: left stick/D-pad moves, A clicks, B closes with the
unsaved confirmation, L/R cycles tabs, right stick scrolls. Mouse/touch takes
control from the pad pointer. All modal pickers and moving pages shield controls
underneath them. Destructive UI actions require a second tap within the arming
window; `Ops.armLabel` shows **Confirm?** in between.

## Verification

The save-editor suites run as tiers in `scripts/test.sh`, including
`save_editor_mobile_properties_tests.lua` (phone/landscape/desktop control bounds,
keyboard, touch and transitions), `save_editor_property_legality_test.lua`
(Gen 3 properties and native persistence), Gen 2, Gen 3 IV/EV/PP and the existing
party/storage/item/map/event/dex tests. Tests using imported data skip explicitly
when the required ROM cache is unavailable.
CI always runs mobile layout, keyboard/touch, Gen 3 IV/EV/PP, wheel and pad
checks with committed fixtures; these do not depend on an imported Red ROM.
Native property checks use an available FireRed cache independently of Red.
The required luacheck gate includes all shipped editor modules.

For real LÖVE captures on a scratch save, use
`tests/drivers/save_editor_mobile_redesign.lua` with `tools/run_driver.sh`.
The driver captures all pages, inspector sections, desktop/landscape layouts and
navigation popups and intermediate slide frames. It also checks pixels on an
MSAA-disabled canvas for all four corners and smooth edges across 80 button
variants (blue/green, selected, disabled, hovered and compact icon actions).
Every painted label is checked against real font metrics for complete text
and adequate width/height, including 320px screens and armed confirmations.
Headless and desktop captures do not prove physical
iOS/Android keyboard or device behavior.

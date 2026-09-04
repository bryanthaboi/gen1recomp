# New Features

Features intentionally added beyond the original Pokémon Red, Blue, and Yellow games:

* **Survey zoom** with connected-map rendering and configurable void fill
* **Perspective tilt mode** for an HD-2D-style overworld
* **Multiple color modes**, including original, SGB, advanced GBC, monochrome, and classic green
* **Optional GBC screen effects**, including pixel grids, shadows, glare, and transparency
* **Performance presets** and configurable FPS limits
* **V-SYNC row and a DISPLAY frame cap**, for panels whose refresh is not a multiple of 60Hz
* **LOGIC CLOCK option** (60HZ or the cart's 59.73HZ vblank rate) on every game's options screen
* **Peer-to-peer LAN link play** for trades and battles between Red, Blue, and Yellow
* **Online lobby** in the launcher for battles, spectating and tournaments
* **Persistent custom options** stored separately from game saves
* **Optional widescreen battle layout**
* **Mobile touch controls** with editable layouts, vibration, and orientation settings
* **Screen position setting** (center, upper, top) shared across all games, for clamp-on controllers that cover the lower screen
* **Touch skins** in RetroArch overlay format and Delta `.deltaskin` (including PDF-wrapped bezel art), with per-button press states and Super Game Boy borders
* **Pokédex diploma and printer image exports**
* **Shareable mod lists** over save sync, optionally carrying the options set for those mods, which the receiving device is asked about before anything is changed
* **Custom carts**, a named mod set saved from the mods tab and picked from a game's page, with its own shell colour, label art, save slots and export file
* **Install required mods**, one press on a cart that will not start, fetching every pinned mod at the pinned version and refusing any archive whose hash is not the one the cart recorded
* **Browse carts in Find mods**, a Mods / Carts switch on the same community index, searched and filtered by base game, installing the cart file straight into that game's cart list
* **Filter Find mods by game**, a generation or single-game filter of its own, with every listing showing the games and tags it declares
* **Update all** in one press from the MODS tab, installing every outdated mod and every installed cart the index lists ahead of it, with a summary of what failed
* **Rebindable GAME SPEED shortcuts**, SPEED - / SPEED + rows in CONTROLS that move the shoulder hotkeys to any pad button or switch them off
* **Key bar on the touch pad**, a corner toggle that slides out SAVE, LOAD, SPEED, COLOR, TILT and ZOOM for phones with no keyboard
* **Save editor item verbs**, sorting the bag and PC by item number or name, filling one stack or every stack to x99, and a coin editor on every game
* **Shortcuts sync before they boot**, a `--game` launch syncing saves (and, with `--update`, taking a release) first, skippable with any button

## Gen 2 Specifics

* **Pokémon Silver** as an importable, launcher-selectable version alongside Gold
* **Pokémon Crystal** as an importable, launcher-selectable version alongside Gold and Silver
* **Mod manager** with Gen 1 mod adapters, per-game targeting, and `modkit gen2check`
* **Followers** for mods, plus Gen 2-only registries and hooks
* **Battle screen options** on Gold, Silver and Crystal: BATTLE SIZE (fixed or window-filling) and BATTLE BG (white, black or the dimmed map as the surround)
* **Widescreen battle layout** on Gold, Silver and Crystal: BATTLE LAYOUT -> WIDE spreads the HUDs and bottom windows across a 304-wide screen

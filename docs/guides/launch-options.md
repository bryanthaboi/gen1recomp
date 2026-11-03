# Launch options

By default the app opens the launcher so you can pick a game. Launch options
skip it and start one game directly, which is what you want for a one-click
entry: a desktop shortcut per game, a Steam entry, or a handheld frontend.

| Option | Effect |
| --- | --- |
| `--game=red` | boot Red, skipping the launcher (`blue`, `yellow`, `gold`, `silver`, `crystal`, `firered`, `leafgreen`, `ruby`, `sapphire` and `emerald` too, or just `r` / `b` / `y` / `g` / `s` / `c` / `fr` / `lg` / `ru` / `sa` / `em`) |
| `--cart=id` | boot the installed custom cart with that id |
| `--slot=2` | load that save slot; takes a slot number or a slot id |
| `--launcher` | open the launcher anyway, so you can edit a shortcut you already made |
| `POKEPORT_DUO_HINGE=closed\|partial\|open[:angle]` | environment variable: pretend a foldable hinge is in that state, to preview the [iPhone Duo layouts](../platforms/iphone-duo.md) on a desktop (`off` disables them) |
| `--no-sync` | skip the save sync a linked device otherwise runs before the game boots (`POKEPORT_LAUNCH_SYNC=0`) |
| `--update` | check for a release first, and restart once into it if one is ready (`POKEPORT_LAUNCH_UPDATE=1`; `-update` works too) |
| `--update-mods` | run the MODS tab's Update all (mods and custom carts) without the confirm, then boot; stays on the launcher if an update fails (`POKEPORT_LAUNCH_UPDATE_MODS=1`; `--updatemods` works too) |

If this device is linked for save sync, a shortcut syncs before it boots so
CONTINUE never loads a save another device has already moved past. The screen
shows what it is doing and any button skips straight into the game; a sync
conflict opens the launcher so you can pick a copy rather than booting over
one.

## URL launch (Android and iOS)

Android and iOS accept the same launch request as a URL:

```text
gen1recomp++://launch?game=red
```

| URL | Effect |
| --- | --- |
| `gen1recomp++://launch?game=red` | boot Red directly |
| `gen1recomp++://launch?game=red&cart=my_cart` | boot the installed custom cart `my_cart` |
| `gen1recomp++://launch?game=red&slot=2` | boot Red and select save slot 2 |
| `gen1recomp++://launch?game=red&launcher=1` | open the launcher on Red instead |
| `gen1recomp++://launch?game=red&sync=0` | skip save sync |
| `gen1recomp++://launch?game=red&update=1` | check for an update before booting |
| `gen1recomp++://launch?game=red&update_mods=1` | update mods and carts before booting |

The `game` value accepts the same full names and aliases as `--game`. Boolean
parameters accept `1`/`0`, `true`/`false`, `yes`/`no`, and `on`/`off`.
Percent-encode values that contain characters reserved by URLs; the app
decodes query values before applying them. `cart` is the installed cart id
shown in the Custom Carts screen. Unknown parameters are ignored, and an
invalid game or cart falls back to the launcher.

To test a link on Android, use the installed application package:

```sh
adb shell am start -a android.intent.action.VIEW \
  -d 'gen1recomp++://launch?game=red' \
  com.theboisclub.pokemonred
```

To test a link in the iOS Simulator:

```sh
xcrun simctl openurl booted 'gen1recomp++://launch?game=red'
```

On a physical iPhone or iPad, open the URL from another app that can hand off
custom URLs, such as Notes, Messages, or Safari.

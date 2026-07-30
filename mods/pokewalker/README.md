# Pokéwalker (Apple Health) — a Gen1Recomp mod

Your real-world steps become EXP for your Pokémon party — the HeartGold/
SoulSilver Pokéwalker, except it's the iPhone already in your pocket.

A mod for [gen1recomp](https://github.com/bryanthaboi/gen1recomp)
(the Gen 1 Recompilation Project). Opt-in, data-safe, and dormant on any
platform that doesn't provide the native step source (see
[Requirements](#requirements)).

## Install

Grab `pokewalker-<version>.modpkg` from
[Releases](https://github.com/mresnick67/Gen1ReComp-Pokewalker/releases)
(or use GitHub's *Code → Download ZIP* — the importer handles both), then:

- **In the launcher:** MODS tab → **Import mod .zip** → pick the file, or
  drag it onto the window on desktop.
- **iOS:** you can also drop the zip into the app's folder in the Files
  app; it installs on next launch.

Then, in the **mod manager → POKEWALKER → options**, turn on **SYNC
STEPS**. iOS asks for read-only access to your step count the first time.

## Options

| Option | Values | Default |
|---|---|---|
| SYNC STEPS | on / off | **off** |
| STEPS PER EXP | 10 / 20 / 50 | 20 |
| GIVE EXP TO | lead mon / whole party (split) | lead mon |

## Mechanics & guardrails

- EXP applies through the engine's own growth curves and rare-candy stat
  math, so levels, stats, and HP top-ups are exact.
- Steps are anchored to the last sync — the same walk is never credited
  twice — and any single sync is clamped to 50,000 steps.
- The engine `levelCap` constant is respected.
- Credits land at quiet moments (save load, map change, battle end) with a
  walk-report textbox.

## Requirements

The Lua mod is platform-neutral, but it feeds on a **native step bridge**
that currently ships in an iOS build of gen1recomp. Without the bridge the
mod loads and stays dormant — safe to install anywhere.

### The bridge contract (for porters)

Any platform can light this mod up by providing:

- `love.system.syncHealthSteps()` → `boolean` — kick off an async step
  query (requesting OS permission on first use). On completion, write
  **`steps_pending.json`** to the LÖVE save directory:

  ```json
  { "steps": 4312, "from": "2026-07-30T08:00:00Z", "to": "2026-07-30T17:00:00Z" }
  ```

  Count steps from a persisted anchor (last successful sync) so a walk is
  never delivered twice, and **merge** with an unconsumed pending file
  rather than overwriting it. The mod consumes and deletes the file.

The reference iOS implementation is a small Swift class (HealthKit
`HKStatisticsQuery` over `stepCount`) exposed to Lua through a one-line
`wrap_System.cpp` addition. Open an issue here if you're porting the
bridge (Android: Health Connect / Google Fit would slot straight in).

## Known limitations (v1)

- Level-ups granted while walking don't prompt for new moves, and level
  evolutions wait for the next in-battle level — same behavior as
  over-leveling with rare candies.
- Steps sync on launch/activation; no background delivery yet.

## Developing

From a gen1recomp checkout with this mod at `mods/pokewalker` and an
imported data cache:

```sh
luajit mods/pokewalker/tests/pokewalker_test.lua
python3 tools/modkit.py validate mods/pokewalker --base imported
python3 tools/modkit.py pack mods/pokewalker
```

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Nintendo, Game Freak,
or The Pokémon Company. This mod contains no ROM-derived content
(`modkit lint` clean).

# Modern Type Chart

Modernizes the move types that changed after Generation I and corrects the
Ghost-versus-Psychic matchup without changing vanilla play.

**Persona: the modernizer.** A player who likes the original campaign and
mechanics but expects familiar move typings and type effectiveness.

## Try it

```sh
python3 tools/modkit.py validate mods/examples/modern_type_chart --base imported
luajit mods/examples/modern_type_chart/tests/modern_type_chart_test.lua
python3 tools/modkit.py pack mods/examples/modern_type_chart
```

Then copy `mods/examples/modern_type_chart` to `mods/modern_type_chart` and
enable it in the F10 mod manager.

## Changes

| Move | Generation I | Updated |
|---|---|---|
| Gust | Normal/physical | Flying/special |
| Karate Chop | Normal/physical | Fighting/physical |
| Sand-Attack | Normal/status | Ground/status |
| Bite | Normal/physical | Dark/physical |

The mod also adds Dark's relevant type-chart relationships and changes Ghost
against Psychic from ineffective to super effective. Psychic attacks remain
super effective against the Gastly family because they are also Poison type.

It deliberately does not add Steel or Fairy, retype Pokemon, or change
Struggle. Struggle remains classified as Normal after Generation I even though
later games calculate its damage without type effectiveness.

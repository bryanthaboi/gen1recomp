# Translating into Español

Everything the player can read is one of two kinds of string, and they live
in different places for a reason.

| lang/ file | What it is | Key |
|---|---|---|
| `dialogue.lua` | Every line of extracted script text | the original label, e.g. `_PalletTownText1` |
| `strings.lua` | Text the engine itself writes: battle messages, menus, link play | the English source string |
| `species.lua` `moves.lua` `items.lua` `trainers.lua` | Names | the vanilla id |
| `statuses.lua` | `PSN`, `BRN`, ... as they appear in the HUD | the status id |
| `font.lua` `charmap.lua` | Your glyph sheet and what draws what | see below |
| `naming.lua` | The letter grid for entering names | - |

Fill in a value and it takes effect. Leave it `""` and that string stays in
English, so the game is playable at every point along the way.

## Where the English is

The catalogs hold keys and *your* text, never the original English. The
English lives next door, in `traduccion_es-worksheet/`, one tab-separated file per
catalog:

```
"_AbandonLearningText"	"Abandon learning\n{RAM:wStringBuffer}?"
```

That directory is deliberately outside the mod. Extracted script text and
the vanilla names are ROM content, and `modkit pack` zips everything under
the mod directory, so a worksheet kept inside would end up in your release
whatever a `.gitignore` said. Keep it beside the mod, never in it.

`lang/strings.lua` is the exception: those sources are the engine's own Lua
rather than anything out of the ROM, so there the key *is* the English and
you can translate straight from it.

## Start with the font, not the text

The fast path: scaffold with `--pixel-font` (or uncomment the
`mod.content.font:register("ttf", {})` line in `main.lua`) and the game
renders text through the engine's bundled Plain Pixel TTF, which already
covers Latin with diacritics, Cyrillic, kana and CJK.  No glyph sheet, no
charmap; `lang/font.lua` and `lang/charmap.lua` can stay empty.  The rest
of this section is for translations that want the hand-drawn tile look
instead.

The engine draws from **glyph pages**: an image of 8x8 cells plus a charmap
saying which byte sequence draws which cell. The vanilla pages sit at `$60`
and `$80`. Anything from `0x100` up is free, so a new alphabet is added
rather than swapped in:

```lua
-- lang/font.lua
return {
  traduccion_es = {
    image = "assets/font/traduccion_es.png",
    base = 0x100,        -- first code this page owns
    glyphsPerRow = 16,
    -- advance = 8,      -- set this if your glyphs are not 8px wide
  },
}
```

```lua
-- lang/charmap.lua: sequence -> code, in the same order as the sheet
return {
  ["A"] = 0x100,
  ["B"] = 0x101,
}
```

The sheet is a plain PNG, 16 glyphs to a row by default, each cell 8x8,
black on white like `assets/generated/font.png`. Codes run left to right,
top to bottom from `base`.

Sequences are matched **longest first**, so a multi-byte character and a
multi-character ligature both work and neither shadows the other:

```lua
["\u{3042}"] = 0x120,   -- one 3-byte character, one glyph
["ch"] = 0x121,          -- two ASCII letters, one glyph
```

## Line length is counted in glyphs

The dialogue box fits 18 glyphs a line, not 18 bytes. A 3-byte character
costs one column, and the engine will never cut a character in half. Your
own `\n` line breaks are respected exactly as written, so break lines where
they read best rather than where they fit English.

If your glyphs are not 8px wide, set `advance` on the page and the box
re-measures.

## Format directives must survive

Some sources carry `%s` or `%d`:

```lua
["Wild %s\nappeared!"] = "...",
```

Keep every directive, in a count that matches. Word order is yours to
change; the engine substitutes in the order the directives appear, so if
your language needs the name last, write the sentence with the `%s` last.
A translation whose directive count does not match the English is refused
at runtime and the English is drawn instead, with a line in the log saying
so - it will not crash a battle.

## Checking your work

```sh
python3 tools/modkit.py validate traduccion_es --base imported
python3 tools/modkit.py translation traduccion_es --refresh   # pick up new engine strings
POKEPORT_DEV=1 scripts/run.sh                          # F5 hot-reloads lang/
```

`--refresh` rewrites the catalogs from the current engine, keeping every
translation you have already written and reporting what changed. Run it
after pulling a new engine version.

-- ADVANCED (redpp) must use pokered-gbc's GEN 1 species->palette map.
--
-- pokered-gbc's data/pokemon/palettes.asm carries TWO tables:
--
--   IF GEN_2_GRAPHICS      db PAL_BULBASAUR / PAL_SQUIRTLE / ...  (per species)
--   ELSE                   db PAL_GREENMON  ; BULBASAUR
--                          db PAL_CYANMON   ; SQUIRTLE            (Gen 1's own)
--   ENDC
--
-- The per-species palettes are authored for GEN 2 sprite art, whose shading
-- puts different regions on different 2bpp shades.  This port extracts Gen 1
-- pics from the ROM, so the ELSE branch is the matching one.
--
-- data/palettes_gbc.lua had imported the GEN_2_GRAPHICS table, which pointed
-- every species at colours shaded for art it does not use.  Bulbasaur wore
-- PAL_BULBASAUR's red-orange (255,82,49) across 231 pixels of a sprite that
-- has no red on it at all, and Squirtle wore PAL_SQUIRTLE's shell brown on
-- his head instead of blue.  It looked least wrong on mons whose two mid
-- tones are close in hue, which is why it survived so long.
--
-- The palette VALUES are untouched -- ADVANCED keeps pokered-gbc's richer
-- colours.  Only the species -> name mapping changed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local pack = require("data.palettes_gbc")

T.check(pack and pack.pokemon, "the ADVANCED pack carries a species map")

local n = 0
for _ in pairs(pack.pokemon) do n = n + 1 end
T.eq(n, 151, "every species is mapped")

-- Gen 1's palette set: the ten MonsterPalettes names plus nothing else.  A
-- per-species name here means the GEN_2_GRAPHICS table crept back in.
local GEN1_NAMES = {
  MEWMON = true, BLUEMON = true, REDMON = true, CYANMON = true,
  PURPLEMON = true, BROWNMON = true, GREENMON = true, PINKMON = true,
  YELLOWMON = true, GRAYMON = true,
}

local strays = {}
for species, name in pairs(pack.pokemon) do
  if not GEN1_NAMES[name] then strays[#strays + 1] = species .. "->" .. name end
end
table.sort(strays)
T.eq(#strays, 0,
  "no species points at a Gen-2-only per-species palette (" ..
  table.concat(strays, ", ", 1, math.min(#strays, 6)) .. ")")

-- the four the bug was reported on, plus their lines
local EXPECT = {
  BULBASAUR = "GREENMON", IVYSAUR = "GREENMON", VENUSAUR = "GREENMON",
  CHARMANDER = "REDMON", CHARMELEON = "REDMON", CHARIZARD = "REDMON",
  SQUIRTLE = "CYANMON", WARTORTLE = "CYANMON", BLASTOISE = "CYANMON",
  MEW = "MEWMON", MEWTWO = "MEWMON", JYNX = "MEWMON",
  LAPRAS = "CYANMON",
}
for species, want in pairs(EXPECT) do
  T.eq(pack.pokemon[species], want, species .. " uses " .. want)
end

-- Bulbasaur's palette must contain no red channel dominance in either mid --
-- the concrete symptom that was reported ("he shouldn't have red anywhere").
local green = pack.palettes[pack.pokemon.BULBASAUR]
T.check(green ~= nil, "GREENMON resolves to colours")
for _, i in ipairs({ 2, 3 }) do
  local c = green[i]
  T.check(c[2] > c[1], ("GREENMON mid %d is green-dominant, not red (%d,%d,%d)")
    :format(i - 1, c[1], c[2], c[3]))
end

-- and Squirtle's mids must be blue-dominant
local cyan = pack.palettes[pack.pokemon.SQUIRTLE]
for _, i in ipairs({ 2, 3 }) do
  local c = cyan[i]
  T.check(c[3] >= c[1], ("CYANMON mid %d is blue-dominant (%d,%d,%d)")
    :format(i - 1, c[1], c[2], c[3]))
end

T.finish("advanced palette map")

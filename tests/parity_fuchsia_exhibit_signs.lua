-- Parity: the Fuchsia City exhibit signs open the exhibited species' Pokédex
-- entry and mark it seen (pokered/scripts/FuchsiaCity.asm).  The fossil sign
-- shows the fossil the player did NOT take at Mt. Moon, and opens no entry
-- at all before either fossil is picked up.
package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("parity fuchsia exhibit signs")
local check, eq = S.check, S.eq

local scripts = require("data.scripts.init")

local exhibits = {
  TEXT_FUCHSIACITY_CHANSEY_SIGN = { "_FuchsiaCityChanseySignText", "CHANSEY" },
  TEXT_FUCHSIACITY_VOLTORB_SIGN = { "_FuchsiaCityVoltorbSignText", "VOLTORB" },
  TEXT_FUCHSIACITY_KANGASKHAN_SIGN = { "_FuchsiaCityKangaskhanSignText", "KANGASKHAN" },
  TEXT_FUCHSIACITY_SLOWPOKE_SIGN = { "_FuchsiaCitySlowpokeSignText", "SLOWPOKE" },
  TEXT_FUCHSIACITY_LAPRAS_SIGN = { "_FuchsiaCityLaprasSignText", "LAPRAS" },
}

for textConst, exhibit in pairs(exhibits) do
  local script = scripts.talkScript("FUCHSIA_CITY", textConst)
  check(script ~= nil, textConst .. " has a talk script")
  if script then
    eq(script[1][1], "show_text", textConst .. " prints its line first")
    eq(script[1][2], exhibit[1], textConst .. " prints its own sign text")
    eq(script[2][1], "mark_seen", textConst .. " marks the species seen")
    eq(script[2][2], exhibit[2], textConst .. " marks " .. exhibit[2] .. " seen")
    eq(script[3][1], "push_screen", textConst .. " opens the Pokédex entry")
    eq(script[3][2], "DexEntryMenu", textConst .. " uses DexEntryMenu")
    eq(script[3][3], exhibit[2], textConst .. " shows " .. exhibit[2])
  end
end

local fossil = scripts.talkScript("FUCHSIA_CITY", "TEXT_FUCHSIACITY_FOSSIL_SIGN")
check(fossil ~= nil, "the fossil sign has a talk script")
if fossil then
  eq(fossil[1][1], "check_flag", "the fossil sign checks the Dome Fossil event")
  eq(fossil[1][2], "EVENT_GOT_DOME_FOSSIL", "Dome Fossil event first")
  eq(fossil[3][1], "check_flag", "the fossil sign checks the Helix Fossil event")
  eq(fossil[3][2], "EVENT_GOT_HELIX_FOSSIL", "Helix Fossil event second")

  -- neither fossil taken: only the undetermined line, no dex entry
  eq(fossil[5][1], "show_text", "the undetermined branch prints its line")
  eq(fossil[5][2], "_FuchsiaCityFossilSignUndeterminedText",
    "the undetermined branch uses the undetermined text")
  eq(fossil[6][1], "jump", "the undetermined branch stops there")
  check(fossil[6][2] == "end", "the undetermined branch never reaches a dex entry")

  -- Dome Fossil taken: the exhibit holds Omanyte
  eq(fossil[2][1], "jump_if_true", "the Dome branch jumps when the event is set")
  eq(fossil[2][2], 7, "the Dome branch lands on the Omanyte rows")
  eq(fossil[7][2], "_FuchsiaCityFossilSignOmanyteText", "Dome taken: Omanyte text")
  eq(fossil[8][1], "mark_seen", "Dome taken: marks the exhibited species seen")
  eq(fossil[8][2], "OMANYTE", "Dome taken: marks Omanyte seen")
  eq(fossil[9][1], "push_screen", "Dome taken: opens the Pokédex entry")
  eq(fossil[9][3], "OMANYTE", "Dome taken: shows Omanyte")

  -- Helix Fossil taken: the exhibit holds Kabuto
  eq(fossil[4][1], "jump_if_true", "the Helix branch jumps when the event is set")
  eq(fossil[4][2], 11, "the Helix branch lands on the Kabuto rows")
  eq(fossil[11][2], "_FuchsiaCityFossilSignKabutoText", "Helix taken: Kabuto text")
  eq(fossil[12][2], "KABUTO", "Helix taken: marks Kabuto seen")
  eq(fossil[13][3], "KABUTO", "Helix taken: shows Kabuto")
end

local save = { pokedex = { seen = {}, owned = {} } }
require("src.script.Commands").mark_seen({ save = save }, "OMANYTE")
check(save.pokedex.seen.OMANYTE, "the preview records the species as seen")
check(not save.pokedex.owned.OMANYTE, "the preview does not mark it owned")

S.finish()

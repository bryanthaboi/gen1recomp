#!/usr/bin/env luajit
-- ../pokefirered/src/pokemon_summary_screen.c:2088

package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
Cache.mountOrSkip("game3_stitchuid_summary_dexno_test", "pokemon/national.lua")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

local FrlgFont = require("src.ui.game3.frlg_font")
local drawn = {}
FrlgFont.draw = function(str, x, y)
  drawn[#drawn + 1] = { s = tostring(str), x = x, y = y }
end
package.loaded["src.core.game3.audio"] = {
  playCry = function() end,
  playSe = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local Strings = require("src.core.Strings")
local UNKNOWN = Strings("???", "game3.summary.dexNo")

local NATIONAL_OFF = { name = "RED" }
local NATIONAL_ON = { name = "RED", national_dex_unlocked = true }

-- ../pokefirered/include/constants/species.h:5,155,159,286,299
-- ../pokefirered/include/constants/pokedex.h:8,158,160,261,274
local BULBASAUR, MEW, CHIKORITA, TREECKO, WURMPLE = 1, 151, 152, 277, 290

print("[test] 1. The INFO page draws the pokedex number in the No field")
local function summary_no_field(species, session)
  drawn = {}
  SummaryMenu.openMenu({
    { species = species, level = 5, hp = 20, maxHp = 20, personality = 0x1234, moves = { 33 }, pp = { 35 } },
  }, 1, { session = session })
  SummaryMenu.draw()
  local coords = (SummaryChrome.manifest() or {}).coords or {}
  local at = coords.dexNo or { x = 167, y = 21 }
  local field, others = nil, {}
  for _, d in ipairs(drawn) do
    if d.x == at.x and d.y == at.y then field = d.s else others[#others + 1] = d.s end
  end
  SummaryMenu.close()
  return field, table.concat(others, "|")
end

local offField, offRest = summary_no_field(WURMPLE, NATIONAL_OFF)
eq(offField, UNKNOWN, "WURMPLE No field with the national dex off")
eq(offRest:find("290", 1, true), nil, "290 is drawn nowhere on the page")
local onField, onRest = summary_no_field(WURMPLE, NATIONAL_ON)
eq(onField, "265", "WURMPLE No field with the national dex on")
eq(onRest:find("290", 1, true), nil, "290 is still drawn nowhere on the page")
local kantoField = summary_no_field(BULBASAUR, NATIONAL_OFF)
eq(kantoField, "001", "BULBASAUR No field with the national dex off")

print("[test] 2. Kanto species print their dex number with the national dex off")
eq(SummaryMenu.dexNoText({ species = BULBASAUR }, NATIONAL_OFF), "001", "BULBASAUR -> 001")
eq(SummaryMenu.dexNoText({ species = MEW }, NATIONAL_OFF), "151", "MEW -> 151")

print("[test] 3. Above KANTO_SPECIES_END with the national dex off prints ???")
eq(SummaryMenu.dexNoText({ species = CHIKORITA }, NATIONAL_OFF), UNKNOWN, "CHIKORITA -> ???")
eq(SummaryMenu.dexNoText({ species = WURMPLE }, NATIONAL_OFF), UNKNOWN, "WURMPLE -> ???")

print("[test] 4. With the national dex on, the national number is printed")
eq(SummaryMenu.dexNoText({ species = CHIKORITA }, NATIONAL_ON), "152", "CHIKORITA -> 152")
eq(SummaryMenu.dexNoText({ species = TREECKO }, NATIONAL_ON), "252", "TREECKO -> 252")
eq(SummaryMenu.dexNoText({ species = WURMPLE }, NATIONAL_ON), "265", "WURMPLE -> 265")

print("[test] 5. The internal species id is never printed")
eq(SummaryMenu.dexNoText({ species = WURMPLE }, NATIONAL_ON) ~= "290", true, "WURMPLE is not 290")
eq(SummaryMenu.dexNoText({ species = TREECKO }, NATIONAL_ON) ~= "277", true, "TREECKO is not 277")
eq(SummaryMenu.dexNumber(WURMPLE, NATIONAL_ON), 265, "dexNumber(WURMPLE) is 265")
eq(SummaryMenu.dexNumber(WURMPLE, NATIONAL_OFF), nil, "dexNumber(WURMPLE) is nil with the national dex off")

print("[test] 5b. SPECIES_NONE keeps pret's zero")
-- ../pokefirered/src/pokemon.c:5212-5213
eq(SummaryMenu.dexNumber(0, NATIONAL_OFF), 0, "dexNumber(SPECIES_NONE) is 0")
eq(SummaryMenu.dexNoText({ species = 0 }, NATIONAL_OFF), "000", "SPECIES_NONE -> 000")

print("[test] 6. A party mon carries its species through speciesOf")
local mon = { species = WURMPLE, level = 5, hp = 20, maxHp = 20, personality = 0x1234 }
eq(SummaryMenu.dexNoText(mon, NATIONAL_ON), "265", "party mon -> 265")
eq(SummaryMenu.dexNoText(mon, NATIONAL_OFF), UNKNOWN, "party mon -> ??? with the national dex off")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

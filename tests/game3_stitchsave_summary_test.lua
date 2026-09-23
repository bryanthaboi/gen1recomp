#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local SummaryData = require("src.core.game3.summary_data")

local AILMENT_NONE, AILMENT_PSN, AILMENT_PKRS, AILMENT_FNT = 0, 1, 6, 7

local function memoLine(mon, playerState)
  local lines = SummaryData.formatTrainerMemo(mon, playerState)
  return lines and lines[2] or ""
end

print("[test] 1. CheckPartyPokerus reads the low nibble only")
do
  -- pokefirered/src/pokemon.c:5630
  eq(SummaryData.statusAilment({ pokerus = 0 }), AILMENT_NONE, "never infected is no ailment")
  eq(SummaryData.statusAilment({ pokerus = 0x41 }), AILMENT_PKRS, "strain 4 with 1 day left is PKRS")
  eq(SummaryData.statusAilment({ pokerus = 0x04 }), AILMENT_PKRS, "4 days left is PKRS")
  eq(SummaryData.statusAilment({ pokerus = 0x0F }), AILMENT_PKRS, "15 days left is PKRS")
  eq(SummaryData.statusAilment({ pokerus = 0x10 }), AILMENT_NONE, "strain 1, cured, is not PKRS")
  eq(SummaryData.statusAilment({ pokerus = 0x40 }), AILMENT_NONE, "strain 4, cured, is not PKRS")
  eq(SummaryData.statusAilment({ pokerus = 0xF0 }), AILMENT_NONE, "strain 15, cured, is not PKRS")
end

print("[test] 2. The cured badge is the summary dot, not the PKRS icon")
do
  local Pokemon = require("src.core.game3.pokemon")
  for _, byte in ipairs({ 0x10, 0x40, 0xF0 }) do
    local mon = { pokerus = byte }
    check(Pokemon.hasPokerus(mon) == false,
      string.format("CheckPartyPokerus is false for 0x%02X", byte))
    check(Pokemon.hasHadPokerus(mon) == true,
      string.format("CheckPartyHasHadPokerus is true for 0x%02X", byte))
    eq(SummaryData.statusAilment(mon), AILMENT_NONE,
      string.format("and the status icon stays clear for 0x%02X", byte))
  end
  local sick = { pokerus = 0x41 }
  check(Pokemon.hasPokerus(sick) == true, "an infected mon is still infected")
  eq(SummaryData.statusAilment(sick), AILMENT_PKRS, "and still draws the PKRS icon")
end

print("[test] 3. A real ailment still outranks pokerus")
do
  -- pokefirered/src/party_menu.c:1758 GetMonAilment
  eq(SummaryData.statusAilment({ pokerus = 0x41, hp = 0 }), AILMENT_FNT, "fainted wins")
  eq(SummaryData.statusAilment({ pokerus = 0x41, hp = 10, status = 0x08 }), AILMENT_PSN,
    "poison wins")
  eq(SummaryData.statusAilment({ pokerus = 0x10, hp = 10, status = 0x08 }), AILMENT_PSN,
    "and a cured mon shows only the poison")
end

if not require("tests.game3_cache").mount() then
  print("[skip] tests 4-9 read ROM map section names: " .. tostring(require("tests.game3_cache").reason))
  print(string.format("[test] %d passed, %d failed", passed, failed))
  os.exit(failed > 0 and 1 or 0)
end

print("[test] 4. The met location comes from the map section, not a PALLET TOWN default")
do
  -- pokefirered/src/pokemon_summary_screen.c:2632 GetMapNameGeneric_(mapNameStr, metLocation)
  local cases = {
    { 88, "PALLET TOWN" },
    { 89, "VIRIDIAN CITY" },
    { 94, "CELADON CITY" },
    { 101, "ROUTE 1" },
    { 127, "MT. MOON" },
    { 136, "SAFARI ZONE" },
    { 143, "ONE ISLAND" },
    { 196, "CELADON DEPT." },
  }
  for _, case in ipairs(cases) do
    local line = memoLine({ metLocation = case[1], metLevel = 7, personality = 3 })
    check(line:find(case[2], 1, true) ~= nil,
      string.format("mapsec %d reads %s (%s)", case[1], case[2], line:gsub("\n", " ")))
  end
end

print("[test] 5. Outside Kanto and the Sevii Islands the memo says a trade")
do
  -- pokefirered/src/pokemon_summary_screen.c:5213 MapSecIsInKantoOrSevii,
  -- pokefirered/src/pokemon_summary_screen.c:2737 gText_PokeSum_ATrade
  local outside = { 0, 1, 87, 197, 253, 254 }
  for _, sec in ipairs(outside) do
    local line = memoLine({ metLocation = sec, metLevel = 7, personality = 3 })
    check(line:find("a trade", 1, true) ~= nil,
      string.format("mapsec %d is outside the region (%s)", sec, line:gsub("\n", " ")))
    check(line:find("PALLET TOWN", 1, true) == nil,
      string.format("and mapsec %d does not claim PALLET TOWN", sec))
  end
  local none = memoLine({ metLevel = 7, personality = 3 })
  check(none:find("a trade", 1, true) ~= nil, "a mon with no met location says a trade")
  check(none:find("PALLET TOWN", 1, true) == nil, "and does not claim PALLET TOWN")
end

print("[test] 6. A stamped name still overrides the lookup")
do
  local line = memoLine({ metLocation = 101, metLocationName = "TREASURE BEACH",
    metLevel = 7, personality = 3 })
  check(line:find("TREASURE BEACH", 1, true) ~= nil, "the stamped name wins")
  check(line:find("ROUTE 1", 1, true) == nil, "the mapsec name is not used as well")
end

print("[test] 7. CELADON CITY reads CELADON DEPT. inside the store")
do
  -- pokefirered/src/region_map.c:3782 IsCeladonDeptStoreMapsec
  local mon = { metLocation = 94, metLevel = 7, personality = 3 }
  local inStore = memoLine(mon, { map = "FR_CELADON_CITY_DEPARTMENT_STORE_3F" })
  check(inStore:find("CELADON DEPT.", 1, true) ~= nil,
    "standing in the store the memo reads CELADON DEPT. (" .. inStore:gsub("\n", " ") .. ")")
  local outside = memoLine(mon, { map = "FR_CELADON_CITY" })
  check(outside:find("CELADON CITY", 1, true) ~= nil, "outside it reads CELADON CITY")
  check(outside:find("DEPT", 1, true) == nil, "and not the store name")
  local elsewhereMon = { metLocation = 101, metLevel = 7, personality = 3 }
  local elsewhere = memoLine(elsewhereMon, { map = "FR_CELADON_CITY_DEPARTMENT_STORE_3F" })
  check(elsewhere:find("ROUTE 1", 1, true) ~= nil,
    "a mon met elsewhere keeps its own section in the store")
end

print("[test] 8. A script gift mon names the map it was handed over on")
do
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")

  local session = Schema.newGame({ rngSeed = 0x3C3C })
  -- pokefirered/src/pokemon.c:1816 CreateBoxMon MON_DATA_MET_LOCATION
  session.regionMapSectionId = 98
  -- pokefirered/src/script_pokemon_util.c:48 ScriptGiveMon
  local code, mon = Party.giveMonToPlayer(session, 106, 25, "HITMONLEE")
  eq(code, Party.MON_GIVEN_TO_PARTY, "the dojo prize went to the party")
  eq(tonumber(mon.metLocation), 98, "stamped with the current map section")
  eq(mon.metLocationName, nil, "and with no stamped place name")

  local line = memoLine(mon, session)
  check(line:find("SAFFRON CITY", 1, true) ~= nil,
    "the memo names SAFFRON CITY (" .. line:gsub("\n", " ") .. ")")
  check(line:find("PALLET TOWN", 1, true) == nil, "not PALLET TOWN")
end

print("[test] 9. A pre-round save keeps what it used to print for the player's own mons")
do
  local Schema = require("src.core.game3.save_schema_firered")
  -- pokefirered/include/constants/region_map_sections.h:211 KANTO_MAPSEC_START
  local old = {
    schemaVersion = 1, engine = "game3", version = "firered",
    name = "RED", rivalName = "BLUE", gender = 0, money = 3000, trainerId = 31337,
    party = {
      { species = 4, speciesId = 4, level = 9, hp = 20, maxHp = 20, metLevel = 5,
        otName = "RED", otId = 31337, personality = 0x12345678 },
      { species = 63, speciesId = 63, level = 9, hp = 20, maxHp = 20, metLevel = 9,
        otName = "REYLEY", otId = 1985, personality = 0x00009cae },
      { species = 25, speciesId = 25, level = 12, hp = 30, maxHp = 30, metLevel = 3,
        metLocation = 101, otName = "RED", otId = 31337, otSecretId = 777,
        personality = 0x22223333 },
    },
    dex = { seen = {}, owned = {} },
    map = "FR_VIRIDIAN_CITY", x = 5, y = 6, facing = "down", flags = {}, vars = {},
  }
  local loaded = Schema.fromSaveTable(old)
  eq(tonumber(loaded.party[1].metLocation), 88,
    "an own-OT mon with no met location is stamped PALLET TOWN on load")
  local own = memoLine(loaded.party[1], loaded)
  check(own:find("PALLET TOWN", 1, true) ~= nil,
    "and the memo reads what it read before the round (" .. own:gsub("\n", " ") .. ")")
  check(own:find("a trade", 1, true) == nil, "the player's own starter is not a trade")

  eq(loaded.party[2].metLocation, nil, "a foreign-OT mon is left alone")
  local traded = memoLine(loaded.party[2], loaded)
  check(traded:find("Met in a trade.", 1, true) ~= nil,
    "and still reads as a trade (" .. traded:gsub("\n", " ") .. ")")

  eq(tonumber(loaded.party[3].metLocation), 101, "a stamped met location is not overwritten")

  local rolled = Schema.newGame({ rngSeed = 0x1111 })
  local secretSave = {
    schemaVersion = 1, engine = "game3", version = "firered",
    name = "RED", trainerId = 31337, secretId = rolled.secretId,
    party = {
      { species = 25, speciesId = 25, level = 5, metLevel = 5, metLocation = 101,
        otName = "RED", otId = 31337, otSecretId = ((rolled.secretId or 0) + 1) % 0x10000,
        personality = 1 },
      { species = 63, speciesId = 63, level = 5, metLevel = 5, metLocation = 101,
        otName = "REYLEY", otId = 1985, otSecretId = 4242, personality = 2 },
    },
    dex = { seen = {}, owned = {} }, flags = {}, vars = {},
  }
  local fixed = Schema.fromSaveTable(secretSave)
  eq(fixed.party[1].otSecretId, rolled.secretId,
    "a stale per-boot secret id on an own mon is repaired")
  local ownLine = memoLine(fixed.party[1], fixed)
  check(ownLine:find("a trade", 1, true) == nil,
    "so it stops reading as a trade (" .. ownLine:gsub("\n", " ") .. ")")
  eq(fixed.party[2].otSecretId, 4242, "a foreign mon keeps its own secret half")
end

print(string.format("[test] %d passed, %d failed", passed, failed))
if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

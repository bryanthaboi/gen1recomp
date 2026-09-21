#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/evolutions.lua")
if not cacheRoot then
  print("[skip] game3_growth_evolution_test: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local ItemsData = require("src.core.game3.items_data")
ItemsData.ensureLoaded()
local Evolution = require("src.core.game3.evolution")
local Schema = require("src.core.game3.save_schema_firered")
local Storage = require("src.core.game3.storage")

local EEVEE, ESPEON, UMBREON, VAPOREON = 133, 196, 197, 134
local WURMPLE, SILCOON, CASCOON = 290, 291, 293
local NINCADA, NINJASK = 301, 302
local GOLBAT, CROBAT = 42, 169
local SWAMPERT, ARON, KYOGRE = 285, 382, 404
local OLD_UNOWN_J = 260
local ITEM_WATER_STONE = 97

local national = { national_dex_unlocked = true }
local kantoOnly = { national_dex_unlocked = false }

local function mon(t)
  local m = {
    species = t.species,
    speciesId = t.species,
    level = t.level or 50,
    friendship = t.friendship or 70,
    personality = t.personality or 0,
    beauty = t.beauty or 0,
    item = t.item or 0,
  }
  if t.numbering then m.speciesNumbering = t.numbering end
  return m
end

print("[test] 1. EVO_FRIENDSHIP_DAY / EVO_FRIENDSHIP_NIGHT are dead on this cart")
local eeveeRows = Pokemon.evolutions(EEVEE)
local hasDay, hasNight = false, false
for _, row in ipairs(eeveeRows) do
  local m = tonumber(row.method or row[1]) or 0
  if m == Evolution.EVO_FRIENDSHIP_DAY then hasDay = true end
  if m == Evolution.EVO_FRIENDSHIP_NIGHT then hasNight = true end
end
check(hasDay, "the pack carries EEVEE's EVO_FRIENDSHIP_DAY row (method 2, ESPEON)")
check(hasNight, "the pack carries EEVEE's EVO_FRIENDSHIP_NIGHT row (method 3, UMBREON)")

local realDate, realTime = os.date, os.time
local function atHour(hour, fn)
  os.date = function(fmt, when)
    if fmt == "*t" or fmt == "!*t" then
      local t = realDate("*t", when)
      t.hour = hour
      return t
    end
    if type(fmt) == "string" and (fmt == "%H" or fmt == "!%H") then
      return string.format("%02d", hour)
    end
    return realDate(fmt, when)
  end
  os.time = function(t) return realTime(t) end
  local ok, res = pcall(fn)
  os.date, os.time = realDate, realTime
  if not ok then error(res, 0) end
  return res
end

for _, hour in ipairs({ 13, 1 }) do
  local lit = (hour == 13) and "13:00" or "01:00"
  local target = atHour(hour, function()
    return Evolution.levelTarget(mon({ species = EEVEE, friendship = 255 }), national)
  end)
  eq(target, nil, "at " .. lit .. " a friendship 255 EEVEE still does not evolve")
  check(target ~= ESPEON and target ~= UMBREON,
    "at " .. lit .. " neither ESPEON nor UMBREON is reachable")
end

eq(Evolution.itemTarget(mon({ species = EEVEE }), ITEM_WATER_STONE, national), VAPOREON,
  "EEVEE's live EVO_ITEM arm still gives VAPOREON")
eq(Evolution.levelTarget(mon({ species = GOLBAT, friendship = 220 }), national), CROBAT,
  "plain EVO_FRIENDSHIP still evolves GOLBAT at 220")
eq(Evolution.levelTarget(mon({ species = GOLBAT, friendship = 219 }), national), nil,
  "and not at 219")

print("[test] 2. a bare species id reads as the internal SPECIES it is")
eq(Pokemon.speciesOf(mon({ species = WURMPLE })), WURMPLE,
  "untagged 290 is WURMPLE, not national 290 NINCADA")
eq(Pokemon.name(Pokemon.speciesOf(mon({ species = WURMPLE }))), "WURMPLE", "and it is named WURMPLE")
eq(Pokemon.speciesOf(mon({ species = ARON })), ARON,
  "untagged 382 is ARON, not national 382 KYOGRE")
eq(Pokemon.speciesOf(mon({ species = EEVEE })), EEVEE, "Kanto ids are unchanged")
eq(Pokemon.speciesOf(mon({ species = 251 })), 251, "and so is the Johto end of the range")

print("[test] 3. the numbering tag is what disambiguates")
eq(Pokemon.speciesOf(mon({ species = WURMPLE, numbering = Pokemon.NUMBERING_INTERNAL })), WURMPLE,
  "internal 290 stays WURMPLE")
eq(Pokemon.speciesOf(mon({ species = WURMPLE, numbering = Pokemon.NUMBERING_NATIONAL })), NINCADA,
  "national 290 resolves to internal NINCADA")
eq(Pokemon.speciesOf(mon({ species = ARON, numbering = Pokemon.NUMBERING_NATIONAL })), KYOGRE,
  "national 382 resolves to internal KYOGRE")
eq(Pokemon.speciesOf(mon({ species = EEVEE, numbering = Pokemon.NUMBERING_NATIONAL })), EEVEE,
  "national 133 is internal 133")
check(Pokemon.isInternalSpecies(WURMPLE), "290 is a named internal species")
check(not Pokemon.isInternalSpecies(OLD_UNOWN_J),
  "260 is an OLD_UNOWN placeholder, not a species")
eq(Pokemon.speciesOf(mon({ species = OLD_UNOWN_J })), SWAMPERT,
  "so an untagged 260 falls through to national 260 SWAMPERT")
eq(Pokemon.numberingOf(mon({ species = WURMPLE })), nil, "an untagged mon reports no numbering")
eq(Pokemon.numberingOf(Pokemon.tagNumbering(mon({ species = WURMPLE }))), Pokemon.NUMBERING_INTERNAL,
  "tagNumbering defaults to internal")

print("[test] 4. the Hoenn evolution methods now reach the right rows")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 0 }), national), SILCOON,
  "a level 7 WURMPLE with upper % 10 <= 4 gives SILCOON")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 5 * 65536 }), national),
  CASCOON, "and with upper % 10 > 4 it gives CASCOON")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 6, personality = 0 }), national), nil,
  "below level 7 nothing matches")
eq(Evolution.levelTarget(
  mon({ species = WURMPLE, level = 20, numbering = Pokemon.NUMBERING_NATIONAL }), national),
  NINJASK, "the same id tagged national is NINCADA and gives NINJASK at 20")

print("[test] 5. levelTarget still gates on the national dex flag")
eq(Evolution.levelTarget(mon({ species = GOLBAT, friendship = 220 }), kantoOnly), nil,
  "CROBAT is blocked while the national dex is locked")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7 }), kantoOnly), nil,
  "SILCOON is blocked too")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7 }), national), SILCOON,
  "and both come back once it is unlocked")

print("[test] 6. an old save's mons are stamped on load")
local legacy = {
  schemaVersion = 1,
  engine = "game3",
  version = "firered",
  name = "RED",
  party = { { species = WURMPLE, speciesId = WURMPLE, level = 7, hp = 10, maxHp = 10 } },
  storage = Storage.serialize(Storage.new()),
}
legacy.storage.boxes[1] = {
  name = "BOX 1",
  wallpaper = 1,
  mons = { [1] = { species = ARON, speciesId = ARON, level = 5, hp = 10, maxHp = 10 } },
}
local loaded = Schema.fromSaveTable(legacy)
eq(loaded.party[1].speciesNumbering, Pokemon.NUMBERING_INTERNAL, "the party mon is tagged internal")
eq(Pokemon.speciesOf(loaded.party[1]), WURMPLE, "and it is still WURMPLE")
local boxed = loaded.storage.boxes[1].mons[1]
eq(boxed.speciesNumbering, Pokemon.NUMBERING_INTERNAL, "the boxed mon is tagged internal")
eq(Pokemon.speciesOf(boxed), ARON, "and it is still ARON")
local again = Schema.fromSaveTable(Schema.toSaveTable(loaded))
eq(again.party[1].speciesNumbering, Pokemon.NUMBERING_INTERNAL, "the tag survives a save round trip")

local hostSave = {
  schemaVersion = 1,
  party = { { species = "WURMPLE", level = 7, hp = 10, maxHp = 10 } },
}
local hostLoaded = Schema.fromSaveTable(hostSave)
eq(hostLoaded.party[1].speciesNumbering, nil, "a host mon keyed by name is left untagged")
eq(Pokemon.speciesOf(hostLoaded.party[1]), WURMPLE, "and still resolves by name")

print("[test] 7. a mon handed over by a script is stamped when it is built")
local Party = require("src.core.game3.party")
local session = Schema.newGame({ name = "RED" })
local ok, code, given = Party.giveMon(session, WURMPLE, 7)
check(ok, "giveMon accepted WURMPLE")
eq(code, Party.MON_GIVEN_TO_PARTY, "it went to the party")
eq(given.speciesNumbering, Pokemon.NUMBERING_INTERNAL, "and it carries the internal tag")
eq(Pokemon.speciesOf(given), WURMPLE, "so it reads back as WURMPLE")

print("[test] 8. an evolved mon carries an internal id, whatever it carried before")
local natMon = mon({ species = 265, level = 7, numbering = Pokemon.NUMBERING_NATIONAL })
natMon.hp, natMon.maxHp = 20, 20
eq(Pokemon.speciesOf(natMon), WURMPLE, "national 265 is internal WURMPLE")
Evolution.apply(natMon, SILCOON, { party = { natMon } }, nil, "levelup")
eq(natMon.speciesNumbering, Pokemon.NUMBERING_INTERNAL, "applying an evolution retags it internal")
eq(Pokemon.speciesOf(natMon), SILCOON, "so it reads as SILCOON, not national 291")
eq(Pokemon.name(Pokemon.speciesOf(natMon)), "SILCOON", "and it is named SILCOON")

local NINCADA_L20 = mon({ species = NINCADA, level = 20, numbering = Pokemon.NUMBERING_INTERNAL })
NINCADA_L20.hp, NINCADA_L20.maxHp = 25, 25
local shedParty = { NINCADA_L20 }
Evolution.apply(NINCADA_L20, NINJASK, { party = shedParty }, nil, "levelup")
eq(#shedParty, 2, "the SHEDINJA copy was added")
eq(shedParty[2].speciesNumbering, Pokemon.NUMBERING_INTERNAL, "the copy is tagged internal too")
eq(Pokemon.name(Pokemon.speciesOf(shedParty[2])), "SHEDINJA", "and it is SHEDINJA")

finish()

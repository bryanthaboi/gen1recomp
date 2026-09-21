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
  print("[skip] game3_evolution_methods_test: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local ItemsData = require("src.core.game3.items_data")
ItemsData.ensureLoaded()
local Evolution = require("src.core.game3.evolution")

local TYROGUE, HITMONLEE, HITMONCHAN, HITMONTOP = 236, 106, 107, 237
local WURMPLE, SILCOON, CASCOON = 290, 291, 293
local NINCADA, NINJASK, SHEDINJA = 301, 302, 303
local FEEBAS, MILOTIC = 328, 329
local GOLBAT, CROBAT = 42, 169
local HAUNTER, GENGAR = 93, 94
local SCYTHER, SCIZOR = 123, 212
local EEVEE, VAPOREON = 133, 134
local PIKACHU, RAICHU = 25, 26
local ITEM_EVERSTONE, ITEM_METAL_COAT = 195, 199
local ITEM_THUNDER_STONE, ITEM_WATER_STONE = 96, 97

local NAME_OF = {}
for _, id in ipairs({ TYROGUE, WURMPLE, NINCADA, FEEBAS, GOLBAT, HAUNTER, SCYTHER, EEVEE, PIKACHU }) do
  NAME_OF[id] = Pokemon.name(id)
end

local national = { national_dex_unlocked = true }
local kantoOnly = { national_dex_unlocked = false }

local function mon(t)
  local key = NAME_OF[t.species] or t.species
  local m = {
    species = key,
    speciesId = key,
    level = t.level or 20,
    friendship = t.friendship or 70,
    personality = t.personality or 0,
    beauty = t.beauty or 0,
    item = t.item or 0,
  }
  m.ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  m.evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  local stats = Pokemon.calcStats(Pokemon.speciesOf(m), m.level, m.ivs, m.evs, m.personality)
  m.maxHp, m.hp = stats.maxHp, stats.maxHp
  m.attack, m.atk = t.atk or stats.attack, t.atk or stats.attack
  m.defense, m.def = t.def or stats.defense, t.def or stats.defense
  return m
end

print("[test] 1. EVO_LEVEL_ATK_GT_DEF / _EQ_ / _LT_ (Tyrogue, pokemon.c:5079)")
eq(Evolution.levelTarget(mon({ species = TYROGUE, level = 20, atk = 40, def = 20 }), national),
  HITMONLEE, "atk > def gives HITMONLEE")
eq(Evolution.levelTarget(mon({ species = TYROGUE, level = 20, atk = 30, def = 30 }), national),
  HITMONTOP, "atk == def gives HITMONTOP")
eq(Evolution.levelTarget(mon({ species = TYROGUE, level = 20, atk = 20, def = 40 }), national),
  HITMONCHAN, "atk < def gives HITMONCHAN")
eq(Evolution.levelTarget(mon({ species = TYROGUE, level = 19, atk = 40, def = 20 }), national),
  nil, "below the level param nothing matches")

print("[test] 2. EVO_LEVEL_SILCOON / _CASCOON personality (pokemon.c:5094)")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 3 * 65536 }), national),
  SILCOON, "upper %% 10 == 3 gives SILCOON")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 4 * 65536 }), national),
  SILCOON, "upper %% 10 == 4 gives SILCOON")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 5 * 65536 }), national),
  CASCOON, "upper %% 10 == 5 gives CASCOON")
eq(Evolution.levelTarget(mon({ species = WURMPLE, level = 7, personality = 19 * 65536 }), national),
  CASCOON, "upper %% 10 == 9 gives CASCOON")

print("[test] 3. EVO_LEVEL_NINJASK evolves, EVO_LEVEL_SHEDINJA never does")
eq(Evolution.levelTarget(mon({ species = NINCADA, level = 20 }), national),
  NINJASK, "Nincada at 20 targets NINJASK, not SHEDINJA")
local rows = Pokemon.evolutions(NINCADA)
eq(rows[2] and rows[2].method, Evolution.EVO_LEVEL_SHEDINJA, "row 2 really is EVO_LEVEL_SHEDINJA")

print("[test] 4. CreateShedinja needs only a party slot (evolution_scene.c:550)")
local nincada = mon({ species = NINCADA, level = 20 })
local session = { party = { nincada }, dex = { seen = {}, owned = {} } }
check(Evolution.apply(nincada, NINJASK, session, nil, "level"), "apply() evolves Nincada")
eq(#session.party, 2, "a second party member appeared with no Poke Ball in the bag")
local shed = session.party[2]
eq(shed and shed.species, SHEDINJA, "the new party member is SHEDINJA")
eq(shed and shed.maxHp, 1, "SHEDINJA maxHp is 1")
eq(shed and shed.hp, 1, "SHEDINJA hp is 1")
eq(Pokemon.calcStats(SHEDINJA, 50, {}, {}, 0).maxHp, 1, "calcStats forces SHEDINJA maxHp to 1")
check(Pokemon.calcStats(292, 50, {}, {}, 0).maxHp > 1, "species 292 (BEAUTIFLY) is not treated as SHEDINJA")

local full = { party = {}, dex = { seen = {}, owned = {} } }
for _ = 1, 5 do full.party[#full.party + 1] = mon({ species = PIKACHU, level = 10 }) end
local nincada2 = mon({ species = NINCADA, level = 20 })
full.party[6] = nincada2
Evolution.apply(nincada2, NINJASK, full, nil, "level")
eq(#full.party, 6, "a full party gets no Shedinja")

print("[test] 5. Wurmple does not spawn a bonus mon (evolution_scene.c:552)")
local wurmple = mon({ species = WURMPLE, level = 7, personality = 3 * 65536 })
local wSession = { party = { wurmple }, dex = { seen = {}, owned = {} } }
Evolution.apply(wurmple, SILCOON, wSession, nil, "level")
eq(#wSession.party, 1, "Wurmple -> Silcoon adds nothing to the party")

print("[test] 6. EVO_BEAUTY (Feebas, pokemon.c:5106)")
eq(Evolution.levelTarget(mon({ species = FEEBAS, level = 20, beauty = 170 }), national),
  MILOTIC, "beauty 170 gives MILOTIC")
eq(Evolution.levelTarget(mon({ species = FEEBAS, level = 20, beauty = 169 }), national),
  nil, "beauty 169 does not")
eq(Evolution.levelTarget(mon({ species = FEEBAS, level = 20, beauty = 0 }), national),
  nil, "the default beauty of 0 does not")

print("[test] 7. FRLG dropped the day/night friendship methods (pokemon.c:5060)")
local eevee = mon({ species = EEVEE, level = 30, friendship = 255 })
eq(Evolution.levelTarget(eevee, national), nil, "a maxed-friendship Eevee never evolves on its own")
local hasDay, hasNight = false, false
for _, e in ipairs(Pokemon.evolutions(EEVEE)) do
  if e.method == Evolution.EVO_FRIENDSHIP_DAY then hasDay = true end
  if e.method == Evolution.EVO_FRIENDSHIP_NIGHT then hasNight = true end
end
check(hasDay and hasNight, "Eevee really carries the ESPEON / UMBREON rows")
eq(Evolution.targetSpecies(eevee, Evolution.EVO_MODE_NORMAL), 0, "EVO_MODE_NORMAL returns none")

print("[test] 8. EVO_FRIENDSHIP + the National Dex gate (evolution_scene.c:641)")
eq(Evolution.levelTarget(mon({ species = GOLBAT, level = 30, friendship = 220 }), national),
  CROBAT, "friendship 220 with the National Dex gives CROBAT")
eq(Evolution.levelTarget(mon({ species = GOLBAT, level = 30, friendship = 219 }), national),
  nil, "friendship 219 does not")
eq(Evolution.levelTarget(mon({ species = GOLBAT, level = 30, friendship = 220 }), kantoOnly),
  nil, "CROBAT is blocked without the National Dex")
eq(Evolution.levelTarget(mon({ species = GOLBAT, level = 30 }), national),
  nil, "a default-friendship Golbat does not evolve")

print("[test] 9. Everstone blocks every mode but EVO_MODE_ITEM_CHECK (pokemon.c:5044)")
local stoned = mon({ species = PIKACHU, level = 30, item = ITEM_EVERSTONE })
eq(Evolution.itemTarget(stoned, ITEM_THUNDER_STONE, national), nil,
  "a Thunder Stone does nothing to an Everstone holder")
eq(Evolution.itemCheck(stoned, ITEM_THUNDER_STONE), RAICHU,
  "EVO_MODE_ITEM_CHECK still reports RAICHU so the party box shows no description")
local stonedHaunter = mon({ species = HAUNTER, level = 30, item = ITEM_EVERSTONE })
eq(Evolution.tradeTarget(stonedHaunter, national), nil, "Everstone blocks a trade evolution")
local everstoneGolbat = mon({ species = GOLBAT, level = 30, friendship = 255, item = ITEM_EVERSTONE })
eq(Evolution.levelTarget(everstoneGolbat, national), nil, "Everstone blocks a friendship evolution")

print("[test] 10. EVO_ITEM only, never EVO_TRADE_ITEM (pokemon.c:5139)")
eq(Evolution.itemTarget(mon({ species = PIKACHU, level = 5 }), ITEM_THUNDER_STONE, national),
  RAICHU, "a Thunder Stone on Pikachu gives RAICHU")
eq(Evolution.itemTarget(mon({ species = EEVEE, level = 5 }), ITEM_WATER_STONE, national),
  VAPOREON, "a Water Stone on Eevee gives VAPOREON")
eq(Evolution.itemTarget(mon({ species = SCYTHER, level = 30, item = 0 }), ITEM_METAL_COAT, national),
  nil, "a Metal Coat used from the bag does NOT evolve Scyther")
eq(Evolution.itemCheck(mon({ species = SCYTHER, level = 30 }), ITEM_METAL_COAT),
  nil, "and the party box says so")

print("[test] 11. EVO_TRADE / EVO_TRADE_ITEM (pokemon.c:5114)")
eq(Evolution.tradeTarget(mon({ species = HAUNTER, level = 30 }), national), GENGAR,
  "trading Haunter gives GENGAR")
eq(Evolution.levelTarget(mon({ species = HAUNTER, level = 100 }), national), nil,
  "Haunter never evolves by level")
local scyther = mon({ species = SCYTHER, level = 30, item = ITEM_METAL_COAT })
eq(Evolution.tradeTarget(scyther, national), SCIZOR, "Scyther holding a Metal Coat gives SCIZOR")
eq(scyther.item, 0, "the Metal Coat is consumed by the trade")
local scyther2 = mon({ species = SCYTHER, level = 30, item = ITEM_METAL_COAT })
eq(Evolution.tradeTarget(scyther2, kantoOnly), nil, "SCIZOR is blocked without the National Dex")
eq(scyther2.item, ITEM_METAL_COAT, "and the blocked trade keeps the Metal Coat")
eq(Evolution.tradeTarget(mon({ species = SCYTHER, level = 30, item = 0 }), national), nil,
  "a bare Scyther is unchanged by a trade")

print("[test] 12. EVO_MODE_* are distinct entry points")
eq(Evolution.EVO_MODE_NORMAL, 0, "EVO_MODE_NORMAL")
eq(Evolution.EVO_MODE_TRADE, 1, "EVO_MODE_TRADE")
eq(Evolution.EVO_MODE_ITEM_USE, 2, "EVO_MODE_ITEM_USE")
eq(Evolution.EVO_MODE_ITEM_CHECK, 3, "EVO_MODE_ITEM_CHECK")
eq(Evolution.targetSpecies(mon({ species = HAUNTER, level = 30 }), Evolution.EVO_MODE_NORMAL), 0,
  "EVO_MODE_NORMAL ignores EVO_TRADE rows")
eq(Evolution.targetSpecies(mon({ species = PIKACHU, level = 5 }), Evolution.EVO_MODE_TRADE), 0,
  "EVO_MODE_TRADE ignores EVO_ITEM rows")

print("[test] 13. The party box 'No use.' gate covers all six stones (items.h:97)")
do
  local PartyMenu = require("src.ui.game3.party_menu")
  check(type(PartyMenu.itemIsEvolutionStone) == "function", "the party menu exposes its gate")
  local NAMES = {
    [93] = "SUN STONE", [94] = "MOON STONE", [95] = "FIRE STONE",
    [96] = "THUNDERSTONE", [97] = "WATER STONE", [98] = "LEAF STONE",
  }
  for id = 93, 98 do
    check(PartyMenu.itemIsEvolutionStone(id), "item " .. id .. " is a stone")
    eq((ItemsData.info(id) or {}).name, NAMES[id], "and the cache names it")
  end
  check(not PartyMenu.itemIsEvolutionStone(99), "unused item 99 is not a stone")
  check(not PartyMenu.itemIsEvolutionStone(100), "unused item 100 is not a stone")
  check(not PartyMenu.itemIsEvolutionStone(340), "HM02 is not a stone")
  check(not PartyMenu.itemIsEvolutionStone(341), "HM03 is not a stone")
  check(not PartyMenu.itemIsEvolutionStone(nil), "and no item at all is not a stone")
  local NIDORINA, NIDOQUEEN = 30, 31
  eq(Evolution.itemCheck(mon({ species = NIDORINA, level = 20 }), 94), NIDOQUEEN,
    "EVO_MODE_ITEM_CHECK says a Moon Stone works on NIDORINA")
  eq(Evolution.itemCheck(mon({ species = PIKACHU, level = 20 }), 94), nil,
    "and not on PIKACHU, which is the slot that reads 'No use.'")
end

finish()

-- A Gen 1 party mon carries one Special word (macros/ram.asm:28-37) and
-- CalcStats writes all NUM_STATS stats or none (home/move_mon.asm:33-48,
-- constants/battle_constants.asm:11-17), so a block missing a key is not a
-- Gen 1 record and the load-time repair must rebuild it.  Gen 2 splits it
-- into SpclAtk/SpclDef (pokegold macros/ram.asm:29-42).  #1517

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Stats = require("src.pokemon.Stats")
local SaveData = require("src.core.SaveData")

local data = {
  pokemon = { FIXMON_A = { id = "FIXMON_A", name = "FIXMON A", types = { "GRASS" },
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 } } },
  moves = { FIX_TACKLE = { id = "FIX_TACKLE", name = "TACKLE", pp = 35 } },
  items = {}, maps = { FIXMAP = { id = "FIXMAP" } },
  constants = { fallbackMove = "FIX_TACKLE" },
}
local DEF = data.pokemon.FIXMON_A
local DVS = { hp = 15, attack = 9, defense = 8, speed = 8, special = 8 }

-- src/battle/gen2/Mon.lua Mon.stats' shape: no `special`
local function gen2Shaped()
  return {
    species = "FIXMON_A", level = 21, hp = 62, exp = 9000,
    dvs = { hp = 15, attack = 9, defense = 8, speed = 8, special = 8 },
    statExp = {},
    stats = { hp = 62, attack = 27, defense = 29, speed = 37,
              specialAttack = 8, specialDefense = 8 },
    moves = { { id = "FIX_TACKLE", pp = 35 } },
  }
end

do
  local mon = gen2Shaped()
  eq(mon.stats.special, nil, "premise: a Gen 2 block has no `special`")
  Stats.ensure(DEF, mon)
  local want = Stats.calc(DEF, 21, DVS, {})
  for _, key in ipairs(Stats.ORDER) do
    eq(mon.stats[key], want[key], "ensure rebuilds " .. key .. " from CalcStats")
  end
  eq(mon.stats.specialAttack, nil, "and drops the Gen 2 keys")
  eq(mon.stats.specialDefense, nil, "both of them")
end

do
  local mon = gen2Shaped()
  local save = { party = { mon }, boxes = {}, inventory = {}, pcItems = {},
                 player = { map = "FIXMAP", x = 1, y = 1, name = "RED", id = 1 } }
  SaveData.validate(save, data)
  check(type(save.party[1].stats.special) == "number",
        "validate repairs a party mon carrying a Gen 2 stat block")
  local ok = pcall(string.format, "%3d", save.party[1].stats.special)
  check(ok, "SummaryMenu's ('%3d'):format over stats.special no longer raises")
  ok = pcall(Stats.applyStage, save.party[1].stats.special, 0)
  check(ok, "and Damage's applyStage over curStats.special no longer raises")
end

-- a box mon reached through the same pass
do
  local save = { party = {}, boxes = { { gen2Shaped() } }, inventory = {},
                 pcItems = {},
                 player = { map = "FIXMAP", x = 1, y = 1, name = "RED", id = 1 } }
  SaveData.validate(save, data)
  check(type(save.boxes[1][1].stats.special) == "number",
        "the repair reaches box mons too")
end

do -- a complete block is never rewritten
  local want = Stats.calc(DEF, 21, DVS, {})
  local mon = { species = "FIXMON_A", level = 21, hp = 5, dvs = DVS, statExp = {},
                stats = { hp = want.hp, attack = 999, defense = want.defense,
                          speed = want.speed, special = want.special },
                moves = { { id = "FIX_TACKLE", pp = 35 } } }
  Stats.ensure(DEF, mon)
  eq(mon.stats.attack, 999, "a complete block is returned untouched")
  eq(mon.hp, 5, "and a stored current HP below the max is kept")
end

do -- a mon with no block at all still gets one (#233, #304 unchanged)
  local mon = { species = "FIXMON_A", level = 21, dvs = DVS, statExp = {} }
  Stats.ensure(DEF, mon)
  local want = Stats.calc(DEF, 21, DVS, {})
  eq(mon.stats.special, want.special, "a box mon with no stats still gets them")
  eq(mon.hp, want.hp, "and a missing current HP fills to the maximum")
end

do -- no species definition: nothing to rebuild from, so leave it alone
  local mon = { species = "MISSINGNO", level = 21,
                stats = { hp = 62, attack = 27 } }
  Stats.ensure(nil, mon)
  eq(mon.stats.attack, 27, "an unknown species leaves a partial block as-is")
  eq(mon.stats.special, nil, "rather than inventing one")
end

T.finish()

-- ../pokecrystal/engine/events/odd_egg.asm:1, engine/events/dratini.asm:1,
-- engine/events/poke_seer.asm:357, data/items/buena_prizes.asm:1,
-- mobile/mobile_5f.asm:484 against the booted game's own events.lua.
--
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_cached_specials_f3.lua
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local Specials = require("src.script.gen2.Specials")

return function(game)
  local fails = 0
  local function line(cond, label)
    if not cond then fails = fails + 1 end
    print(("[driver] %s %s"):format(cond and "PASS" or "FAIL", label))
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")
  local tables = game.data and game.data.gen2EventTables or {}

  local save = game.save
  save.player = save.player or {}
  save.player.id = save.player.id or 30000
  save.inventory = save.inventory or {}

  local function vm(scriptVar)
    return { scriptVar = scriptVar or 0, specials = world:specialHooks() }
  end

  local odd = tables.oddEggs
  line(odd ~= nil and #odd.rows == 14, "oddEggs carries 14 rows")
  local prior = Specials.random
  local want = { 8, 1, 16, 3, 16, 3, 14, 2, 10, 2, 12, 2, 10, 1 }
  local got = {}
  for index = 1, 14 do
    local roll = (index == 1) and 0 or (odd.rows[index - 1].probability + 1)
    Specials.random = function(n)
      if n == 0x10000 then return roll + 1 end
      return prior(n)
    end
    save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
    save.inventory.EGG_TICKET = 1
    Specials.HANDLERS.GiveOddEgg(vm())
    local egg = save.party[2]
    got[index] = egg and egg.otId or "nil"
    line(egg ~= nil and egg.isEgg == true and egg.ot == "ODD"
      and egg.nickname == "EGG" and egg.species == odd.rows[index].species,
      ("odd egg %d is an ODD %s EGG"):format(index, odd.rows[index].species))
  end
  Specials.random = prior
  line(table.concat(got, ",") == table.concat(want, ","),
    "odd egg MON_IDs are " .. table.concat(got, ","))
  line((save.inventory.EGG_TICKET or 0) == 0, "the EGG TICKET was tossed")

  save.party = { Mon.new(game.data, "DRATINI", 15) }
  Specials.HANDLERS.GiveDratini(vm(0))
  local ids = {}
  for _, move in ipairs(save.party[1].moves or {}) do ids[#ids + 1] = move.id end
  line(table.concat(ids, ",") == "WRAP,THUNDER_WAVE,TWISTER,EXTREMESPEED",
    "GiveDratini 0 is .Moveset0 (" .. table.concat(ids, ",") .. ")")
  line(save.party[1].moves[4].pp == 5, "EXTREMESPEED has 5 PP")

  local prizes = tables.buenaPrizes or {}
  line(#prizes == 9 and prizes[1].item == "ULTRA_BALL" and prizes[9].item == "HP_UP",
    "buenaPrizes is the nine-row BuenaPrizeItems")

  local seer = tables.pokeSeer or {}
  local levels = {}
  for _, row in ipairs(seer.advice or {}) do levels[#levels + 1] = row.level end
  line(table.concat(levels, ",") == "9,29,59,89,100,255",
    "SeerAdviceTexts levels " .. table.concat(levels, ","))
  line(seer.times and table.concat(seer.times, ",") == "Morning,Day,Night",
    "GetCaughtTime.times")

  local menu = tables.battleTowerMenus and tables.battleTowerMenus.challengeMenu
  line(menu ~= nil and table.concat(menu.rows, ",") == "Challenge,Explanation,Cancel",
    "MenuData_ChallengeExplanationCancel rows")

  print(("[driver] %s crystal cached specials"):format(fails == 0 and "PASS" or "FAIL"))
  love.event.quit(fails == 0 and 0 or 1)
end

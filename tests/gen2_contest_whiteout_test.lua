-- engine/events/whiteout.asm:9-25, engine/events/std_scripts.asm:308-315
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 contest whiteout")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Screens = require("src.ui.Screens")
local Events = require("src.world.gen2.Events")
local Save = require("src.core.gen2.Save")
local BugContest = require("src.core.gen2.BugContest")

local DATA = {
  pokemon = {
    CATERPIE = { id = "CATERPIE", name = "CATERPIE", index = 10, baseExp = 53,
      growthRate = "MEDIUM_FAST", stats = { hp = 45, attack = 30,
        defense = 35, speed = 45, specialAttack = 20, specialDefense = 20 },
      types = { "BUG" } },
    RATTATA = { id = "RATTATA", name = "RATTATA", index = 19, baseExp = 57,
      growthRate = "MEDIUM_FAST", stats = { hp = 30, attack = 56,
        defense = 35, speed = 72, specialAttack = 25, specialDefense = 35 },
      types = { "NORMAL" } },
  },
  moves = {},
}

local function mon(species, level, hp)
  return { species = species, name = species, nickname = species,
    level = level, hp = hp, maxHp = 30,
    stats = { hp = 30, attack = 10, defense = 10, speed = 10,
      specialAttack = 10, specialDefense = 10 },
    moves = {}, experience = 0, statExp = {}, dvs = {} }
end

local function contestSave()
  local save = Save.normalize({ party = { mon("RATTATA", 10, 0) },
    player = { name = "GOLD", money = 3000 } })
  BugContest.start(save)
  return save
end

local function contestWorld(save)
  local captured, log = {}, {}
  Screens.invalidate()
  local game = {
    data = {
      pokemon = DATA.pokemon, moves = DATA.moves,
      screens = {
        Gen2BattleState = function(_, opts)
          captured.opts = opts
          return { screenId = "Gen2BattleState" }
        end,
      },
    },
    save = save,
    stack = { push = function() end, pop = function() end },
  }
  local world = World.new(game)
  game.world = world
  world.map = { def = { id = "NATIONAL_PARK" } }
  world.maps = { NATIONAL_PARK = world.map.def }
  world.events = Events.new()
  world.playBattleMusic = function() end
  world.battleMusicContext = function() return nil end
  world.pushBattleTransition = function() return nil end
  world.restoreMapMusic = function() end
  world.roamMonsAfterBattle = function() end
  world.healParty = function() log[#log + 1] = "heal" end
  world.runMapSetup = function(_, _, fn) log[#log + 1] = "mapsetup" fn() end
  world.warpToSpawn = function() log[#log + 1] = "spawn" end
  world.bugContestResults = function() log[#log + 1] = "results" return true end
  world.bugContestOver = function() log[#log + 1] = "over" return true end
  world.showText = function(_, _, onDone) if onDone then onDone() end end
  return world, captured, log
end

local function has(log, entry)
  for _, e in ipairs(log) do if e == entry then return true end end
  return false
end

do
  local save = contestSave()
  local world, captured, log = contestWorld(save)
  world:startBattle({ wild = mon("CATERPIE", 7, 20), contest = true })
  check(captured.opts ~= nil, "a contest encounter pushes the battle screen")
  captured.opts.onDone("lose")
  check(has(log, "heal"), "the party is healed")
  check(has(log, "results"),
    "a contest wipe runs BugContestResultsWarpScript")
  check(not has(log, "spawn"), "and does not warp to the last Pokecenter")
  check(not has(log, "over"), "and does not also run the out-of-balls script")
  eq(save.player.money, 3000, "nor halve the wallet")
end

do
  local save = Save.normalize({ party = { mon("RATTATA", 10, 0) },
    player = { name = "GOLD", money = 3000 } })
  local world, captured, log = contestWorld(save)
  world:startBattle({ wild = mon("CATERPIE", 7, 20) })
  captured.opts.onDone("lose")
  check(has(log, "spawn"), "outside the contest a wipe still warps home")
  check(not has(log, "results"), "and never runs the contest results")
  eq(save.player.money, 1500, "and halves the wallet")
end

do
  local save = contestSave()
  local world, _, log = contestWorld(save)
  world:whiteOut()
  check(has(log, "results"),
    "a poison wipe in the park also goes to the contest results")
  check(not has(log, "spawn"), "rather than to the last Pokecenter")
  eq(save.player.money, 3000, "and keeps the wallet whole")
end

Screens.invalidate()

return S.finish()

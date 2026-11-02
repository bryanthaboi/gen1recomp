-- engine/battle/effect_commands.asm:5421 (#2101)
-- engine/battle_anims/bg_effects.asm:377

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
}

local MOVES = {
  DIG = { id = "DIG", name = "DIG", power = 60, type = "GROUND",
    accuracy = 100, pp = 10, effect = "EFFECT_FLY" },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  DIGGER = {
    id = "DIGGER", index = 50, name = "DIGGER",
    baseStats = { hp = 40, attack = 55, defense = 40, speed = 60,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 50,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "DIG" } },
    evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {},
}

local dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }

local function newScreen()
  Input:init()
  local player = Mon.new(DATA, "DIGGER", 20, { dvs = dvs })
  player.moves = { { id = "DIG", pp = 10, maxPp = 10 } }
  local wild = Mon.new(DATA, "DIGGER", 20, { dvs = dvs })
  wild.moves = { { id = "DIG", pp = 10, maxPp = 10 } }
  local save = { party = { player }, inventory = {} }
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = { push = function() end, pop = function() end,
      top = function() return nil end },
  }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = function() return 0 end })
  local screen = BattleState.new(game, { battle = battle, save = save })
  screen.queue = {}
  screen.phase = "resolving"
  return screen
end

local function strike(side, missed)
  return { kind = "move", side = side, move = "DIG", wasVanished = true,
    missed = missed or nil, text = side .. " DIG" }
end

local function noLatch(screen)
  return screen.vanishReveal.player == nil and screen.vanishReveal.enemy == nil
end

local idle = { wasPressed = function() return false end }

local function fakeAnim(screen)
  local runs = {}
  screen.animForMove = function(self)
    local anim = { animId = "DIG", bg = { picSize = {} },
      step = function() return false end,
      done = function() return true end }
    runs[#runs + 1] = anim
    self.anim = anim
    return true
  end
  return runs
end

for _, order in ipairs({ { "player", "enemy" }, { "enemy", "player" } }) do
  local screen = newScreen()
  screen:pushAll({ strike(order[1]), strike(order[2]) })
  eq(screen.picHidden.player, true, order[1] .. " first: player box empty")
  eq(screen.picHidden.enemy, true, order[1] .. " first: enemy box empty")
  screen:advanceQueue()
  eq(screen.picHidden[order[1]], false,
    order[1] .. " first: the faster mon comes back on its own strike")
  eq(screen.picHidden[order[2]], true,
    order[1] .. " first: the slower one is still down")
  screen:advanceQueue()
  eq(screen.picHidden[order[2]], false,
    order[1] .. " first: the slower mon comes back on its strike")
  check(noLatch(screen), order[1] .. " first: no latch is left behind")
end

do
  local screen = newScreen()
  screen:pushAll({ strike("player", true), strike("enemy") })
  screen:advanceQueue()
  eq(screen.picHidden.player, false, "a missed strike still reveals the user")
  eq(screen.picHidden.enemy, true, "and leaves the foe's latch alone")
  screen:advanceQueue()
  eq(screen.picHidden.enemy, false, "the foe's own strike reveals it")
  check(noLatch(screen), "miss: no latch is left behind")
end

for _, order in ipairs({ { "player", "enemy" }, { "enemy", "player" } }) do
  local screen = newScreen()
  local runs = fakeAnim(screen)
  screen:pushAll({ strike(order[1]), strike(order[2]) })
  screen:advanceQueue()
  eq(#runs, 1, order[1] .. " anim: the first strike starts its script")
  eq(screen.vanishReveal[order[1]].anim, runs[1],
    order[1] .. " anim: the latch is armed on that script")
  check(screen.vanishReveal[order[2]]
    and screen.vanishReveal[order[2]].anim == nil,
    order[1] .. " anim: the other latch stays unarmed")
  eq(screen.picHidden[order[1]], true,
    order[1] .. " anim: the box stays empty while the script runs")
  screen:stepAnim(idle)
  eq(screen.picHidden[order[1]], false,
    order[1] .. " anim: the script's end brings the mon back")
  eq(screen.picHidden[order[2]], true,
    order[1] .. " anim: the other mon is still down")
  screen:advanceQueue()
  eq(#runs, 2, order[1] .. " anim: the second strike starts its script")
  screen:stepAnim(idle)
  eq(screen.picHidden[order[2]], false,
    order[1] .. " anim: the second script's end brings that mon back")
  check(noLatch(screen), order[1] .. " anim: no latch is left behind")
end

do
  local screen = newScreen()
  local runs = fakeAnim(screen)
  screen:pushAll({ strike("player"), strike("enemy") })
  screen:advanceQueue()
  runs[1].bg.picSize.enemy = 1
  screen:revealVanished()
  eq(screen.picHidden.player, true,
    "the foe's pic size in the user's script reveals nothing")
  runs[1].bg.picSize.player = 1
  screen:revealVanished()
  eq(screen.picHidden.player, false, "the user's own ENTER_MON reveals it")
  eq(screen.picHidden.enemy, true, "and the foe stays down")
  check(screen.vanishReveal.enemy ~= nil, "with its latch intact")
end

T.finish("gen2 vanish reveal both sides bug 2101")

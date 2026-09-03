-- engine/battle/effect_commands.asm:5432, :5456-5459 (#2101)
--
--   luajit tests/gen2_dig_anim_2101_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 dig anim events")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
}

local MOVES = {
  DIG = { id = "DIG", name = "DIG", power = 60, type = "GROUND",
    accuracy = 100, pp = 10, effect = "EFFECT_FLY" },
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  DIGGER = {
    id = "DIGGER", index = 50, name = "DIGGER",
    baseStats = { hp = 40, attack = 55, defense = 40, speed = 60,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 50,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "DIG" } },
    evolutions = {},
  },
  TARGET = {
    id = "TARGET", index = 51, name = "TARGET",
    baseStats = { hp = 60, attack = 40, defense = 45, speed = 10,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 50,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}

local function zeroRandom() return 0 end

local dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
local player = Mon.new(DATA, "DIGGER", 20, { dvs = dvs })
player.moves = { { id = "DIG", pp = 10, maxPp = 10 } }
local wild = Mon.new(DATA, "TARGET", 10, { dvs = dvs })
wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }

local battle = Battle.new({
  data = DATA, party = { player }, wild = wild, random = zeroRandom,
})

local function playerMove(events)
  for _, ev in ipairs(events or {}) do
    if ev.kind == "move" and ev.side == "player" then return ev end
  end
  return nil
end

local turn1 = battle:takeTurn({ kind = "move", move = "DIG" })
local mv = playerMove(turn1)
check(mv ~= nil, "turn 1 emits the player's move event")
eq(mv and mv.animParam, 1, "the charge turn runs the anim's param-1 branch")
check(mv and mv.afterAnim == nil, "and zeroes the after-anim")
check(mv and not mv.wasVanished, "with no reveal flag on the way down")
eq(battle:volatile(player).vanished, true, "the user is underground")
eq(battle:volatile(player).chargeMove, "DIG", "with the attack stored")

local turn2 = battle:takeTurn({ kind = "move", move = "DIG" })
local mv2 = playerMove(turn2)
check(mv2 ~= nil, "turn 2 emits the stored attack's move event")
eq(mv2 and mv2.wasVanished, true, "flagged as the reveal turn")
check(mv2 and mv2.animParam == nil, "on the anim's hit branch")
eq(mv2 and mv2.afterAnim, "damage", "with the hit shake intact")
check(battle:volatile(player).vanished == nil, "and the substatus is gone")
check(battle:volatile(player).chargeMove == nil, "with nothing left stored")

S.finish()

-- The battle stat items: XItemEffect, XAccuracyEffect, DireHitEffect and
-- GuardSpecEffect (engine/items/item_effects.asm:2079-2146).
--
--   luajit tests/gen2_x_items_test.lua
--
-- ROM-free.  The four X items raise one stage of their stat (X SPECIAL is
-- SP_ATTACK in Gen 2); X ACCURACY, DIRE HIT and GUARD SPEC set a substatus
-- bit -- accuracy-roll bypass, +1 critical level, Mist -- each refusing a
-- second use without spending the item or the turn.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 x items")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Damage = require("src.battle.gen2.Damage")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local ITEMS = {
  X_ATTACK = { id = "X_ATTACK", name = "X ATTACK", pocket = "ITEM" },
  X_DEFEND = { id = "X_DEFEND", name = "X DEFEND", pocket = "ITEM" },
  X_SPEED = { id = "X_SPEED", name = "X SPEED", pocket = "ITEM" },
  X_SPECIAL = { id = "X_SPECIAL", name = "X SPECIAL", pocket = "ITEM" },
  X_ACCURACY = { id = "X_ACCURACY", name = "X ACCURACY", pocket = "ITEM" },
  DIRE_HIT = { id = "DIRE_HIT", name = "DIRE HIT", pocket = "ITEM" },
  GUARD_SPEC = { id = "GUARD_SPEC", name = "GUARD SPEC.", pocket = "ITEM" },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = ITEMS,
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function rolls(queue, fill)
  local at = 0
  return function(n)
    at = at + 1
    local value = queue[at]
    if value == nil then value = fill or 0 end
    return value % math.max(1, n or 1)
  end
end

local function newScreen(opts)
  opts = opts or {}
  Input:init()
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = { player },
    inventory = opts.inventory or { X_ATTACK = 2, DIRE_HIT = 2,
      X_ACCURACY = 1, GUARD_SPEC = 1, X_SPECIAL = 1 } }
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = { push = function() end, pop = function() end,
      top = function() return nil end },
  }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    save = save, random = opts.random or rolls({}, 1) })
  local screen = BattleState.new(game, { battle = battle, save = save })
  return screen, battle, player, wild, save
end

-- ---- the X items raise their stage and spend the turn ---------------------
do
  local screen, battle, _, _, save = newScreen()
  local turn0 = battle.turn
  screen:useItem("X_ATTACK")
  eq(battle.stages.player.attack, 1, "X ATTACK raises Attack one stage")
  eq(save.inventory.X_ATTACK, 1, "and one left the bag")
  eq(battle.turn, turn0 + 1, "the use costs the turn")

  screen:useItem("X_SPECIAL")
  eq(battle.stages.player.specialAttack, 1,
    "X SPECIAL raises Special ATTACK (data/items/x_stats.asm)")
  eq(battle.stages.player.specialDefense, 0, "and not Special Defense")
end

-- ---- Dire Hit: SUBSTATUS_FOCUS_ENERGY -------------------------------------
do
  local screen, battle, player, _, save = newScreen()
  screen:useItem("DIRE_HIT")
  eq(battle:volatile(player).focusEnergy, true,
    "DIRE HIT sets the focus-energy bit")
  eq(save.inventory.DIRE_HIT, 1, "and is spent")

  -- The second one is refused: WontHaveAnyEffect_NotUsedMessage.
  local turn1 = battle.turn
  screen:useItem("DIRE_HIT")
  eq(screen.message, "It won't have any\neffect.", "a re-use is refused")
  eq(save.inventory.DIRE_HIT, 1, "without spending the item")
  eq(battle.turn, turn1, "or the turn")

  -- engine/battle/effect_commands.asm:1201
  eq(Damage.criticalLevel({ focusEnergy = true }), 1, "+1 critical level")
  battle.random = function(n) return n == 256 and 31 or 0 end
  local _, info = battle:hitOnce(player, battle.enemy, MOVES.TACKLE)
  eq(info.critical, true, "Dire Hit crits on byte 31 (threshold 32)")
  battle.random = function(n) return n == 256 and 32 or 0 end
  _, info = battle:hitOnce(player, battle.enemy, MOVES.TACKLE)
  eq(info.critical, false, "and not on byte 32")
end

-- ---- X Accuracy: the roll bypass ------------------------------------------
do
  -- engine/battle/effect_commands.asm:1605
  local screen, battle, player, wild = newScreen({
    random = rolls({}, 244) })
  local before = wild.hp
  battle:useMove(player, wild, "TACKLE")
  eq(wild.hp, before, "roll 244 misses TACKLE bare")

  screen, battle, player, wild = newScreen({ random = rolls({}, 244) })
  screen:useItem("X_ACCURACY")
  eq(battle:volatile(player).xAccuracy, true, "the bit is set")
  before = wild.hp
  battle:useMove(player, wild, "TACKLE")
  check(wild.hp < before,
    "and the same roll connects: CheckHit's .XAccuracy skips the roll")
end

-- ---- Guard Spec: Mist -----------------------------------------------------
do
  local screen, battle, player, wild = newScreen()
  screen:useItem("GUARD_SPEC")
  eq(battle:volatile(player).mist, true, "GUARD SPEC sets SUBSTATUS_MIST")

  battle:useMove(wild, player, "GROWL")
  eq(battle.stages.player.attack, 0,
    "the foe's GROWL is turned away by the Mist")
  local shielded = false
  for _, event in ipairs(battle:takeEvents()) do
    if event.text == battle:romText("ProtectedByMistText", wild, player) then
      shielded = true
    end
  end
  check(shielded, "with ProtectedByMistText")

  -- The holder's own drops still land: Mist only answers the foe.
  battle:useMove(player, wild, "GROWL")
  eq(battle.stages.enemy.attack, -1,
    "the holder can still lower the ENEMY's stats")
end

-- ---- the substatus drops on switch ----------------------------------------
do
  local screen, battle, player = newScreen()
  screen:useItem("DIRE_HIT")
  eq(battle:volatile(player).focusEnergy, true, "armed")
  battle:clearVolatile(player)
  eq((player.volatile or {}).focusEnergy, nil,
    "a switch clears it with the rest of SUBSTATUS4")
end

S.finish()

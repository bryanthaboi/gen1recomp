-- engine/battle/effect_commands.asm:1553-1614 BattleCommand_CheckHit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Effects = require("src.battle.gen2.Effects")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FIGHTING = { id = "FIGHTING", index = 1, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SWIFT = { id = "SWIFT", name = "SWIFT", power = 60, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_ALWAYS_HIT" },
  VITAL_THROW = { id = "VITAL_THROW", name = "VITAL THROW", power = 70,
    type = "FIGHTING", accuracy = 100, accuracyRaw = 255, pp = 10,
    effect = "EFFECT_ALWAYS_HIT" },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  MACHOP = {
    id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {
    BRIGHTPOWDER = { id = "BRIGHTPOWDER", name = "BRIGHTPOWDER",
      heldEffect = "HELD_BRIGHTPOWDER", heldParameter = 51 },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function alwaysHighRoll(n)
  return math.max(1, n or 1) - 1
end

local function newBattle()
  local player = Mon.new(DATA, "MACHOP", 15, { dvs = perfect })
  player.moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "SWIFT", pp = 20, maxPp = 20 },
    { id = "VITAL_THROW", pp = 10, maxPp = 10 },
  }
  local wild = Mon.new(DATA, "MACHOP", 15, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return Battle.new({ data = DATA, party = { player }, wild = wild,
    random = alwaysHighRoll }), player, wild
end

local function moveEvent(events)
  for _, event in ipairs(events or {}) do
    if event.kind == "move" then return event end
  end
  return nil
end

local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and event.text == text then return true end
  end
  return false
end

local function use(battle, player, wild, moveId)
  wild.hp = wild.maxHp
  battle:useMove(player, wild, moveId)
  local events = battle:takeEvents()
  return (moveEvent(events) or {}).missed == true, events
end

do
  local battle, player, wild = newBattle()
  battle.stages.enemy.evasion = Effects.MAX_STAGE
  T.check(use(battle, player, wild, "TACKLE"),
    "at +6 evasion a 100-accuracy move misses on a high roll")
  T.check(not use(battle, player, wild, "SWIFT"),
    "SWIFT ignores the evasion stage")
  T.check(wild.hp < wild.maxHp, "and the hit lands damage")
  T.check(not use(battle, player, wild, "VITAL_THROW"),
    "VITAL THROW carries the same effect")
end

do
  local battle, player, wild = newBattle()
  battle.stages.player.accuracy = -Effects.MAX_STAGE
  T.check(use(battle, player, wild, "TACKLE"),
    "at -6 accuracy a 100-accuracy move misses on a high roll")
  T.check(not use(battle, player, wild, "SWIFT"),
    "SWIFT ignores the accuracy stage")
end

do
  local battle, player, wild = newBattle()
  wild.item = "BRIGHTPOWDER"
  T.check(use(battle, player, wild, "TACKLE"),
    "BRIGHTPOWDER alone is enough to miss on a 99 roll")
  T.check(not use(battle, player, wild, "SWIFT"),
    "the `ret z` sits ahead of .BrightPowder too")
end

do
  local battle, player, wild = newBattle()
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "FLY"
  local missed, events = use(battle, player, wild, "SWIFT")
  T.check(missed, "a FLY target still dodges SWIFT")
  T.check(findText(events, battle:romText("AttackMissedText", player)),
    "with CheckHit's .Miss")
  T.eq(wild.hp, wild.maxHp, "and takes nothing")
end

do
  local battle, player, wild = newBattle()
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  T.check(use(battle, player, wild, "SWIFT"), "a DIG target dodges it too")
end

do
  local battle, player, wild = newBattle()
  battle:volatile(wild).protect = true
  local missed, events = use(battle, player, wild, "SWIFT")
  T.check(missed, "PROTECT still turns SWIFT aside")
  T.check(findText(events, battle:romText("ProtectingItselfText", player, wild)),
    "with .Protect's line")
  T.eq(wild.hp, wild.maxHp, "and takes nothing")
end

do
  local battle, player, wild = newBattle()
  T.check(not use(battle, player, wild, "SWIFT"),
    "with no stage moved at all SWIFT still hits")
  T.check(not use(battle, player, wild, "TACKLE"),
    "and a plain move only fails the 99 roll once a stage has moved")
end

T.finish("gen2 always-hit bug 1272")

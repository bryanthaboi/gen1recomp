-- Held items with an in-battle consult point: Quick Claw (turn order),
-- Focus Band (lethal-hit survival), King's Rock (held flinch), BrightPowder
-- (accuracy) and the Berserk Gene (switch-in Attack surge plus confusion).
--
--   luajit tests/gen2_held_items_test.lua
--
-- ROM-free: the item rows carry the ItemAttributes heldEffect/heldParameter
-- pairs exactly as the extractor writes them (engine/battle/core.asm
-- `.equal_priority`, effect_commands.asm BattleCommand_ApplyDamage /
-- BattleCommand_HeldFlinch / `.BrightPowder`, core.asm HandleBerserkGene).

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 held items")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SWIFT = { id = "SWIFT", name = "SWIFT", power = 60, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_ALWAYS_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  MACHOP = {
    id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

-- The extractor's item rows: heldEffect out of ItemAttributes, parameter
-- beside it (data/items/attributes.asm).
local ITEMS = {
  QUICK_CLAW = { id = "QUICK_CLAW", name = "QUICK CLAW",
    heldEffect = "HELD_QUICK_CLAW", heldParameter = 60 },
  FOCUS_BAND = { id = "FOCUS_BAND", name = "FOCUS BAND",
    heldEffect = "HELD_FOCUS_BAND", heldParameter = 30 },
  KINGS_ROCK = { id = "KINGS_ROCK", name = "KING'S ROCK",
    heldEffect = "HELD_FLINCH", heldParameter = 30 },
  BRIGHTPOWDER = { id = "BRIGHTPOWDER", name = "BRIGHTPOWDER",
    heldEffect = "HELD_BRIGHTPOWDER", heldParameter = 20 },
  -- The gene's attribute byte is HELD_NONE on the cart: HandleBerserkGene
  -- checks the ITEM id.
  BERSERK_GENE = { id = "BERSERK_GENE", name = "BERSERK GENE",
    heldEffect = "HELD_NONE", heldParameter = 0 },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = ITEMS,
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- A scripted roller: feeds the queue in order, then falls back to `fill`.
local function rolls(queue, fill)
  local at = 0
  return function(n)
    at = at + 1
    local value = queue[at]
    if value == nil then value = fill or 0 end
    return value % math.max(1, n or 1)
  end
end

local function newBattle(opts)
  opts = opts or {}
  -- MACHOP (speed 35) always loses the speed race to PIDGEY (speed 56).
  local player = Mon.new(DATA, "MACHOP", 15, { dvs = perfect,
    item = opts.playerItem })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 15, { dvs = perfect,
    item = opts.wildItem })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = opts.random })
  return battle, player, wild
end

local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and event.text == text then return true end
  end
  return false
end

-- ---- Quick Claw -----------------------------------------------------------
do
  local battle = newBattle({})
  eq(battle:orderOf("TACKLE", "TACKLE"), "enemy",
    "bare hands: the faster PIDGEY moves first")

  -- Claw roll 59 < 60: first strike for the slow side.
  battle = newBattle({ playerItem = "QUICK_CLAW", random = rolls({ 59 }) })
  eq(battle:orderOf("TACKLE", "TACKLE"), "player",
    "a roll under the claw's 60 steals the turn")

  -- Claw roll 60: no dice, speed decides again.
  battle = newBattle({ playerItem = "QUICK_CLAW", random = rolls({ 60 }) })
  eq(battle:orderOf("TACKLE", "TACKLE"), "enemy",
    "a roll at 60 fails and Speed decides")

  -- The enemy's claw, symmetric.
  battle = newBattle({ wildItem = "QUICK_CLAW", random = rolls({ 59 }) })
  eq(battle:orderOf("TACKLE", "TACKLE"), "enemy",
    "the enemy's claw fires the same way")

  -- Both hold one: the ENEMY's roll is consulted first
  -- (`.both_have_quick_claw`, non-link order).
  battle = newBattle({ playerItem = "QUICK_CLAW", wildItem = "QUICK_CLAW",
    random = rolls({ 10 }) })
  eq(battle:orderOf("TACKLE", "TACKLE"), "enemy",
    "with two claws the enemy's roll goes first")
  battle = newBattle({ playerItem = "QUICK_CLAW", wildItem = "QUICK_CLAW",
    random = rolls({ 200, 10 }) })
  eq(battle:orderOf("TACKLE", "TACKLE"), "player",
    "the player's roll answers second")
end

-- ---- Focus Band -----------------------------------------------------------
do
  local battle, _, wild = newBattle({ wildItem = "FOCUS_BAND",
    random = rolls({ 29 }) })
  wild.hp = 10
  local dealt = battle:dealDamage(battle.player, wild, 50, {})
  eq(wild.hp, 1, "a roll under 30 leaves the holder at exactly 1 HP")
  eq(dealt, 9, "the clamp is the False Swipe clamp: hp - 1")
  check(findText(battle:takeEvents(),
    battle:romText("HungOnText", battle.player, wild, "FOCUS BAND")),
    "and HungOnText names the item")

  battle, _, wild = newBattle({ wildItem = "FOCUS_BAND",
    random = rolls({ 30 }) })
  wild.hp = 10
  battle:dealDamage(battle.player, wild, 50, {})
  eq(wild.hp, 0, "a roll at 30 fails and the holder faints")

  -- A non-lethal hit never consults the band.
  battle, _, wild = newBattle({ wildItem = "FOCUS_BAND",
    random = rolls({ 255 }) })
  wild.hp = 30
  battle:dealDamage(battle.player, wild, 10, {})
  eq(wild.hp, 20, "a survivable hit passes through untouched")
end

-- ---- King's Rock ----------------------------------------------------------
do
  -- Rolls in useMove order: accuracy, crit, variation, then the flinch
  -- byte.  A fill of 1 hits, never crits, and lands 1 < 30 on the flinch.
  local battle, player, wild = newBattle({ playerItem = "KINGS_ROCK",
    random = rolls({ 1, 128, 1, 1 }, 1) })
  battle:useMove(player, wild, "TACKLE")
  eq(battle:volatile(wild).flinched, true,
    "a damaging hit with the rock held sets the flinch, silently")
  eq(battle:canAct(wild), false, "the target's turn is eaten")
  check(findText(battle:takeEvents(), "Enemy PIDGEY\nflinched!"),
    "with FlinchedText at the moment it tries to move")
  eq(battle:volatile(wild).flinched, nil, "and the flag is consumed")

  -- Roll at the parameter: no flinch.
  battle, player, wild = newBattle({ playerItem = "KINGS_ROCK",
    random = rolls({ 1, 128, 1, 30 }) })
  battle:useMove(player, wild, "TACKLE")
  eq(battle:volatile(wild).flinched, nil, "a roll at 30 does nothing")

  -- A Substitute blocks it (CheckSubstituteOpp).
  battle, player, wild = newBattle({ playerItem = "KINGS_ROCK",
    random = rolls({ 1, 128, 1, 1 }, 1) })
  battle:volatile(wild).substitute = 20
  battle:useMove(player, wild, "TACKLE")
  eq(battle:volatile(wild).flinched, nil,
    "the substitute soaks the hit and the rock with it")

  -- Bare hands: nothing.
  battle, player, wild = newBattle({ random = rolls({ 1, 128, 1, 1 }, 1) })
  battle:useMove(player, wild, "TACKLE")
  eq(battle:volatile(wild).flinched, nil, "no rock, no flinch")
end

-- ---- BrightPowder ---------------------------------------------------------
do
  local battle, player, wild = newBattle({ wildItem = "BRIGHTPOWDER" })
  local tackle = battle:moveDef("TACKLE")
  local raw = tackle.accuracyRaw
  battle.random = function() return raw - 21 end
  eq(battle:accuracyRoll(tackle, player, wild), true,
    "the powder leaves raw - 20 to roll under")
  battle.random = function() return raw - 20 end
  eq(battle:accuracyRoll(tackle, player, wild), false,
    "the powder takes 20 off the accuracy byte")
  eq(battle:accuracyRoll(tackle, wild, player), true,
    "a bare defender changes nothing")
  player.moves = { { id = "SWIFT", pp = 20, maxPp = 20 } }
  battle.random = function(n) return (n or 256) - 1 end
  local swiftBefore = wild.hp
  battle:useMove(player, wild, "SWIFT")
  check(wild.hp < swiftBefore, "a sure-hit move stays sure against the powder")

  -- Through the real roll: 90 hits a bare PIDGEY (90 < 95) and misses a
  -- powdered one (90 >= 88).
  battle, player, wild = newBattle({ random = rolls({ 230 }, 1) })
  local before = wild.hp
  battle:useMove(player, wild, "TACKLE")
  check(wild.hp < before, "roll 90 connects without the powder")

  battle, player, wild = newBattle({ wildItem = "BRIGHTPOWDER",
    random = rolls({ 230 }, 1) })
  before = wild.hp
  battle:useMove(player, wild, "TACKLE")
  eq(wild.hp, before, "and misses against it")
  check(findText(battle:takeEvents(), battle:romText("AttackMissedText", player)),
    "with the ordinary miss line")
end

-- ---- Berserk Gene ---------------------------------------------------------
do
  local battle, player = newBattle({ playerItem = "BERSERK_GENE",
    random = rolls({}, 1) })
  local events = battle:takeTurn({ kind = "skip" })
  eq(player.item, nil, "the gene is consumed the turn its holder is out")
  eq(battle.stages.player.attack, 2,
    "Attack jumps two stages (BattleCommand_AttackUp2)")
  -- Confusion is SUBSTATUS_CONFUSED, a volatile: the cart's gene sets the
  -- bit without writing the count, the near-permanent lock the port models
  -- as Battle.BERSERK_GENE_CONFUSE_TURNS.
  eq(player.volatile.confuseCount, Battle.BERSERK_GENE_CONFUSE_TURNS,
    "and the holder is confused, no count -- the lock")
  eq(player.status, nil, "the status byte stays free for a real status")
  check(findText(events, battle:romText("BattleText_UsersStringBuffer1Activated",
    player, player, "BERSERK GENE")), "UsersStringBuffer1Activated announces it")

  -- One shot: the next turn has nothing left to fire.
  battle:takeTurn({ kind = "skip" })
  eq(battle.stages.player.attack, 2, "no second surge")

  -- The enemy's gene works on the enemy.
  local wild
  battle, player, wild = newBattle({ wildItem = "BERSERK_GENE",
    random = rolls({}, 1) })
  battle:takeTurn({ kind = "skip" })
  eq(wild.item, nil, "the wild side's gene is consumed too")
  eq(battle.stages.enemy.attack, 2, "its Attack surges")
  -- The wild side took its turn through canAct, which decrements the count
  -- once before rolling the self-hit.
  eq(wild.volatile.confuseCount, Battle.BERSERK_GENE_CONFUSE_TURNS - 1,
    "and it confuses itself")
end

S.finish()

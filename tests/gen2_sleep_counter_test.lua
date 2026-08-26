-- The counter a sleep MOVE writes: BattleCommand_SleepTarget's .random_loop
-- (engine/battle/effect_commands.asm:3591-3598), which masks with SLP_MASK,
-- rerolls 0 and SLP_MASK and only then does `inc a` -- so 2-7, never 1 (#1707).
-- Rest and the disobedience nap keep their own counters and are the controls.
--
--   luajit tests/gen2_sleep_counter_test.lua   -- ROM-free

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 sleep counter")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  PSYCHIC = { id = "PSYCHIC", index = 24, category = "special" },
}

local MATCHUPS = {}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  -- data/moves/moves.asm: SPORE and HYPNOSIS are both EFFECT_SLEEP.
  SPORE = { id = "SPORE", name = "SPORE", power = 0, type = "GRASS",
    accuracy = 100, pp = 15, effect = "EFFECT_SLEEP" },
  HYPNOSIS = { id = "HYPNOSIS", name = "HYPNOSIS", power = 0,
    type = "PSYCHIC", accuracy = 100, pp = 20, effect = "EFFECT_SLEEP" },
  REST = { id = "REST", name = "REST", power = 0, type = "PSYCHIC",
    accuracy = 100, pp = 10, effect = "EFFECT_HEAL" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local POKEMON = {
  growthRates = GROWTH,
  -- Fast enough to move first against the PIDGEY below at these levels.
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "FIRE", "FIRE" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = MATCHUPS },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- BattleRandom(n) -> 0..n-1, pinned to one value.
local function zeroRandom() return 0 end
local function fixedRandom(value)
  return function(n) return math.min(value, (n or 1) - 1) end
end

local function newBattle(opts)
  opts = opts or {}
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = {
    { id = "SPORE", pp = 15, maxPp = 15 },
    { id = "TACKLE", pp = 35, maxPp = 35 },
  }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({
    data = DATA,
    party = { player },
    wild = wild,
    random = opts.random or zeroRandom,
  })
  battle:takeEvents()
  return battle, player, wild
end

local function texts(events)
  local out = {}
  for _, event in ipairs(events or {}) do
    if event.text then out[#out + 1] = event.text end
  end
  return out
end

local function found(events, needle)
  for _, text in ipairs(texts(events)) do
    if text:find(needle, 1, true) then return true end
  end
  return false
end

-- ------------------------------------------------------- the roll's range

-- The whole roll space against .random_loop's window: 2..7 inclusive, six
-- outcomes, no 1 and no 8 (effect_commands.asm:3591-3598).
do
  local seen, low, high = {}, math.huge, -math.huge
  for roll = 0, 7 do
    local battle, _, wild = newBattle({ random = fixedRandom(roll) })
    battle:useMove(battle.player, wild, "SPORE")
    eq(wild.status, "sleep", "roll " .. roll .. " slept the target")
    local turns = wild.statusTurns or 0
    seen[turns] = true
    low, high = math.min(low, turns), math.max(high, turns)
  end
  eq(low, 2, "the shortest sleep a sleep move can roll is two turns")
  eq(high, 7, "the longest is seven, SLP_MASK itself never being written")
  check(not seen[1], "one turn is unreachable, so no free-action sleep")
  check(not seen[0], "and zero is unreachable")
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  eq(count, 6, "six distinct counters, the width of the cart's window")
end

do
  local battle, _, wild = newBattle()
  battle:useMove(battle.player, wild, "SPORE")
  eq(wild.statusTurns, 2, "the lowest roll writes two, not one")
end

-- ------------------------------------------- slept by a faster foe (#1707)

-- CheckPlayerTurn decrements before the sleeper acts, so the round the sleep
-- landed in is the one a 1 would have cost nothing.
do
  local battle, player, wild = newBattle()
  local hpBefore = player.hp
  local events = battle:takeTurn({ kind = "move", move = "SPORE" })
  eq(wild.status, "sleep", "the slower foe is asleep")
  check(found(events, "is fast asleep!"),
    "and spends the same round's action asleep")
  check(not found(events, "woke up!"),
    "it cannot wake in the round it was slept")
  eq(wild.statusTurns, 1, "one turn of the counter was spent")
  eq(player.hp, hpBefore, "so the sleeper landed no attack of its own")
end

-- The counter still runs out on the next round.
do
  local battle, _, wild = newBattle()
  battle:takeTurn({ kind = "move", move = "SPORE" })
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  check(found(events, "woke up!"), "the next round wakes it")
  eq(wild.status, nil, "and clears the status byte")
  eq(wild.statusTurns, nil, "and the counter with it")
end

-- Hypnosis shares EFFECT_SLEEP, so it shares the window.
do
  local battle, _, wild = newBattle()
  battle.player.moves[1] = { id = "HYPNOSIS", pp = 20, maxPp = 20 }
  battle:useMove(battle.player, wild, "HYPNOSIS")
  eq(wild.status, "sleep", "hypnosis slept the target")
  eq(wild.statusTurns, 2, "off the same .random_loop")
end

-- ------------------------------------------------------------- the controls

-- Rest writes REST_SLEEP_TURNS + 1 straight into the status byte, no roll
-- (effect_commands.asm:6015-6027).
do
  local battle, player, wild = newBattle()
  player.moves = { { id = "REST", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 } }
  player.hp = 1
  battle:useMove(player, wild, "REST")
  eq(player.status, "sleep", "rest slept the user")
  eq(player.statusTurns, 3, "rest is still exactly three")
  eq(player.hp, player.maxHp, "and still a full heal")

  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  check(found(events, "is fast asleep!"), "the first turn after rest is lost")
  events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  check(found(events, "is fast asleep!"), "so is the second")
  events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  check(found(events, "woke up!"), "and it acts on the third")
end

-- The disobedience nap rerolls only 0 and has no `inc a`, so 1 is legal
-- there (effect_commands.asm:778-785) and the two rolls are not shared.
do
  local record = Battle.STATUSES.sleep
  check(type(record.onInflict) == "function", "sleep still has an onInflict")
  local mon = {}
  record.onInflict({ random = zeroRandom }, mon)
  eq(mon.statusTurns, 2, "the status record's own floor is two")
end

S.finish()

-- What ends a round, a hit, and a battle in Gen 2.
--
--   luajit tests/gen2_battle_end_test.lua
--
-- ROM-free.  Four rules the turn loop and ExitBattle carry, each one only
-- visible at the seam between two halves of a turn:
--
--   * `.wild_force_flee` ends the ROUND wherever it lands: a wild mon blown
--     away by a faster player's ROAR does not get to answer.
--   * BattleCommand_ApplyDamage runs the Endure clamp unconditionally, so a
--     mon braced at exactly 1 HP takes nothing and holds.
--   * SpikesDamage checks both type slots against FLYING before it chips.
--   * CleanUpBattleRAM: the substatus area is battle RAM, and this port keeps
--     it on the party record the save file owns, so a battle may not leave a
--     single bit behind on the way out.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle end")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  ROAR = { id = "ROAR", name = "ROAR", power = 0, type = "NORMAL",
    accuracy = 100, pp = 20, effect = "EFFECT_FORCE_SWITCH" },
  ENDURE = { id = "ENDURE", name = "ENDURE", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_ENDURE" },
  SPIKES = { id = "SPIKES", name = "SPIKES", power = 0, type = "NORMAL",
    accuracy = 100, pp = 20, effect = "EFFECT_SPIKES" },
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
  RATTATA = {
    id = "RATTATA", index = 19, name = "RATTATA",
    baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 51,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  -- The Flying half of SpikesDamage's two `cp FLYING` tests: PIDGEY carries it
  -- in the second slot, MURKROW in the first.
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  MURKROW = {
    id = "MURKROW", index = 198, name = "MURKROW",
    baseStats = { hp = 60, attack = 85, defense = 42, speed = 91,
      specialAttack = 85, specialDefense = 42 },
    types = { "FLYING", "NORMAL" }, catchRate = 30, baseExp = 107,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local ITEMS = {
  DIRE_HIT = { id = "DIRE_HIT", name = "DIRE HIT", pocket = "ITEM" },
  X_ACCURACY = { id = "X_ACCURACY", name = "X ACCURACY", pocket = "ITEM" },
  GUARD_SPEC = { id = "GUARD_SPEC", name = "GUARD SPEC.", pocket = "ITEM" },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = ITEMS,
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function mon(species, level, moves)
  local m = Mon.new(DATA, species, level, { dvs = perfect })
  m.moves = {}
  for _, id in ipairs(moves or { "TACKLE" }) do
    m.moves[#m.moves + 1] = { id = id, pp = MOVES[id].pp,
      maxPp = MOVES[id].pp }
  end
  return m
end

-- The smallest roll that neither crits nor misses, and that lets a
-- ProtectChance roll through.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

local function textsOf(events)
  local out = {}
  for _, event in ipairs(events) do
    if event.text then out[#out + 1] = event.text end
  end
  return out
end

local function saidSomethingLike(events, fragment)
  for _, text in ipairs(textsOf(events)) do
    if text:find(fragment, 1, true) then return true end
  end
  return false
end

-- ---- a wild Roar ends the round in the player's half ----------------------
do
  local player = mon("CYNDAQUIL", 20, { "ROAR", "TACKLE" })
  local wild = mon("PIDGEY", 5)
  local save = { party = { player }, player = { id = 1, badges = {} } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    save = save, random = detRandom })
  check(battle:effectiveSpeed(player) > battle:effectiveSpeed(wild),
    "the player's mon is the faster of the two")
  local hpBefore = player.hp
  local events = battle:takeTurn({ kind = "move", move = "ROAR" })
  check(saidSomethingLike(events, "fled in fear!"),
    "FledInFearText: the wild mon is blown away")
  -- EFFECT_FORCE_SWITCH is priority 0, below BASE_PRIORITY
  -- (data/moves/effects_priorities.asm:5): Roar goes last (#1475)
  check(saidSomethingLike(events, "used TACKLE!"),
    "so the wild mon takes its half of the turn first, Speed regardless")
  check(player.hp < hpBefore, "and its hit landed before the blow-away")
  eq(battle.over, true, "the battle is over")
  eq(battle.outcome, "fled", "as the cart's DRAW")
end

-- ---- Endure holds at exactly 1 HP -----------------------------------------
do
  local player = mon("CYNDAQUIL", 10, { "ENDURE", "TACKLE" })
  local wild = mon("RATTATA", 10)
  local save = { party = { player }, player = { id = 1, badges = {} } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    save = save, random = detRandom })
  player.hp = 1
  battle:useMove(player, wild, "ENDURE")
  eq(battle:volatile(player).endure, true, "the brace is up")
  battle:takeEvents()
  battle:useMove(wild, player, "TACKLE")
  local events = battle:takeEvents()
  eq(player.hp, 1, "FalseSwipe's clamp leaves the holder on its last point")
  check(saidSomethingLike(events, "endured the hit!"), "with EnduredText")

  -- The same brace at 2 HP still ends on 1: the clamp is MonHP - 1 either way.
  local other = mon("CYNDAQUIL", 10, { "ENDURE", "TACKLE" })
  local save2 = { party = { other }, player = { id = 1, badges = {} } }
  local battle2 = Battle.new({ data = DATA, party = { other },
    wild = mon("RATTATA", 10), save = save2, random = detRandom })
  other.hp = 2
  battle2:useMove(other, battle2.enemy, "ENDURE")
  battle2:useMove(battle2.enemy, other, "TACKLE")
  eq(other.hp, 1, "and a 2 HP brace ends on 1")
end

-- ---- Spikes: both type slots are checked against FLYING -------------------
do
  local lead = mon("CYNDAQUIL", 10)
  local flyer = mon("PIDGEY", 10)
  local firstSlot = mon("MURKROW", 10)
  local grounded = mon("RATTATA", 10)
  local party = { lead, flyer, firstSlot, grounded }
  local save = { party = party, player = { id = 1, badges = {} } }
  local battle = Battle.new({ data = DATA, party = party,
    wild = mon("RATTATA", 10, { "SPIKES", "TACKLE" }), save = save,
    random = detRandom })

  -- The enemy lays them on the side that will be switching into them.
  battle:useMove(battle.enemy, lead, "SPIKES")
  eq(battle.spikes.player, true, "SCREENS_SPIKES is on the player's side")
  battle:takeEvents()

  local flyerHp = flyer.hp
  battle:switch(2)
  local events = battle:takeEvents()
  eq(flyer.hp, flyerHp, "a second-slot FLYING type takes nothing")
  check(not saidSomethingLike(events, "hurt by SPIKES!"),
    "and the line is not printed either")

  local crowHp = firstSlot.hp
  battle:switch(3)
  battle:takeEvents()
  eq(firstSlot.hp, crowHp, "a first-slot FLYING type takes nothing either")

  local ratHp = grounded.hp
  battle:switch(4)
  local grounding = battle:takeEvents()
  eq(grounded.hp, ratHp - math.max(1, math.floor(grounded.maxHp / 8)),
    "and anything else takes GetEighthMaxHP")
  check(saidSomethingLike(grounding, "hurt by SPIKES!"),
    "with BattleText_UserHurtBySpikes")
end

-- ---- CleanUpBattleRAM: nothing rides the party out of the battle ----------
do
  Input:init()
  local player = mon("CYNDAQUIL", 20)
  local party = { player }
  local save = { party = party, player = { id = 1, name = "GOLD", badges = {} },
    inventory = { DIRE_HIT = 2, X_ACCURACY = 1, GUARD_SPEC = 1 } }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local wild = mon("RATTATA", 3)
  -- One byte under 50 percent + 1 is the confusion self-hit, and this leg is
  -- confused on purpose: a high byte still hits and never crits, and it lets
  -- the mon act.
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = save,
    random = function(n)
      if n == 256 then return 200 end
      if (n or 1) <= 1 then return 0 end
      return 1
    end })
  local screen = BattleState.new(game, { battle = battle, save = save })
  local outcome
  screen.onDone = function(result) outcome = result end

  -- Battle lines end in `prompt` and PromptButton waits on A/B with no
  -- countdown (home/joypad.asm:383-412), so the drain presses.
  local function drain(cap)
    for _ = 1, (cap or 3000) do
      local waiting = (screen.messageTimer or 0) > 0
      if waiting then Input:overlayPressed("a") end
      Input:step()
      screen:update(1 / 60)
      if waiting then Input:overlayReleased("a") end
      if screen.phase == "menu" or screen.phase == "done" then return true end
    end
    return false
  end
  check(drain(), "the intro drains to the battle menu")

  screen:useItem("DIRE_HIT")
  check(drain(), "DIRE HIT resolves")
  screen:useItem("X_ACCURACY")
  check(drain(), "X ACCURACY resolves")
  screen:useItem("GUARD_SPEC")
  check(drain(), "GUARD SPEC resolves")
  battle:volatile(player).confuseCount = 4
  eq(battle:volatile(player).focusEnergy, true, "the three bits are up")

  -- Win it: the enemy is one hit from fainting, and ExitBattle runs on the way
  -- out of the queue.
  wild.hp = 1
  screen:submit({ kind = "move", move = "TACKLE" })
  check(drain(), "the win drains out")
  eq(screen.phase, "done", "ExitBattle finished")
  eq(outcome, "win", "with the battle won")
  eq(player.volatile, nil, "and the party mon carries no substatus out")

  -- Which is the whole point: the next battle starts clean, and the item that
  -- refuses a repeat use is usable again.
  local next_ = Battle.new({ data = DATA, party = party,
    wild = mon("RATTATA", 3), save = save, random = detRandom })
  eq(next_:volatile(player).focusEnergy, nil, "no DIRE HIT rung carried over")
  eq(next_:volatile(player).xAccuracy, nil, "no accuracy bypass either")
  eq(next_:volatile(player).mist, nil, "and no Mist")
  eq(next_:volatile(player).confuseCount, nil, "nor a confusion count")
  eq(next_:useBattleItem("DIRE_HIT"), true,
    "so a DIRE HIT is accepted in the next battle")
end

-- ---- and a battle built over a party that WAS dirty cleans it up ----------
do
  local player = mon("CYNDAQUIL", 10)
  -- A save written before the cleanup existed, or a battle torn down without
  -- its screen: the bits are on the party record when the battle opens.
  player.volatile = { focusEnergy = true, confuseCount = 3, wrapCount = 2 }
  local save = { party = { player }, player = { id = 1, badges = {} } }
  local battle = Battle.new({ data = DATA, party = { player },
    wild = mon("RATTATA", 3), save = save, random = detRandom })
  eq(player.volatile, nil,
    "NewBattleMonStatus opens the battle on an empty area")
  eq(battle:volatile(player).confuseCount, nil, "nothing survived the send-out")
end

S.finish()

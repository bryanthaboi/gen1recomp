-- Bide on Gold, against the two carve-outs the cart makes for it.
--
-- PP (#1664): the doturn command returns early when the user's substatus
-- carries SUBSTATUS_BIDE (engine/battle/effect_commands.asm:978-979), and
-- StoreEnergy's continuation skips straight to unleashenergy on every turn
-- after the first (engine/battle/move_effects/bide.asm:61-62), so the whole
-- run costs the one PP the opening turn spent.
--
-- Lock-in (#1665): the player's menu is skipped while SUBSTATUS_BIDE is set
-- (engine/battle/core.asm:574-576) and CheckEnemyLockedIn masks the same bit
-- (:5648-5651), so neither side can pick anything else while bide stores.
-- Gen 1 already holds the menu this way, at BattleState:fightLockedAction.
--
--   luajit tests/engine/gen2_bide_lock_and_pp.lua
--
-- ROM-free: the fixtures below are the extractor's shapes.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local check, eq = T.check, T.eq

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  BIDE = { id = "BIDE", name = "BIDE", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_BIDE" },
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local function species(id, index)
  return { id = id, index = index, name = id,
    baseStats = { hp = 60, attack = 60, defense = 60, speed = 60,
      specialAttack = 60, specialDefense = 60 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 60,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end

local POKEMON = {
  growthRates = GROWTH,
  MACHOP = species("MACHOP", 66),
  RATTATA = species("RATTATA", 19),
}

local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = {} }, items = {} }

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- The smallest roll that is neither a critical hit nor a miss.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

-- A level 50 player against a level 5 foe, so nothing faints mid-run and the
-- turn count is the only thing under test.  The foe attacks so bide banks
-- something real.
local function newBattle()
  local player = Mon.new(DATA, "MACHOP", 50, { dvs = perfect })
  player.moves = {
    { id = "BIDE", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 },
  }
  local wild = Mon.new(DATA, "RATTATA", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = detRandom })
  return battle, player
end

local function slot(mon, id)
  for _, move in ipairs(mon.moves or {}) do
    if move.id == id then return move end
  end
end

local function said(events)
  local out = {}
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and event.text then out[#out + 1] = event.text end
  end
  return table.concat(out, " | ")
end

-- Run bide to its unleash, picking `pick` every turn.  Returns the number of
-- turns it took and the text of the last one.
local function runBide(battle, pick)
  local turns, last = 0, ""
  for _ = 1, 8 do
    turns = turns + 1
    last = said(battle:takeTurn({ kind = "move", move = pick }))
    if last:find("unleashed energy!", 1, true) then break end
  end
  return turns, last
end

-- ---- #1664: the whole run costs one PP ------------------------------------
do
  local battle, player = newBattle()
  local bide = slot(player, "BIDE")
  local turns = runBide(battle, "BIDE")
  check(turns > 1, "bide stored for at least one turn before unleashing")
  eq(bide.pp, bide.maxPp - 1,
    ("bide spent one PP across %d turns, not one per turn"):format(turns))
end

-- ---- #1665: the menu is held while bide stores ----------------------------
do
  local battle, player = newBattle()
  battle:takeTurn({ kind = "move", move = "BIDE" })

  eq(battle:lockedInMove(player), "BIDE",
    "lockedInMove holds the user on bide while it stores")
  eq(battle:forcedMove(player), "BIDE",
    "and forcedMove reports the same, which is what the menu reads")

  local usable = battle:usableMoves(player)
  eq(#usable, 1, "only one move is selectable while bide stores")
  eq(usable[1] and usable[1].id, "BIDE", "and it is bide")
end

-- ---- #1665: picking something else cannot strand the counter --------------
-- Without the lock the menu's TACKLE ran, bideTurns never reached zero and
-- bideStored kept banking, so the next bide unleashed an inflated hit.
do
  local battle, player = newBattle()
  local tackle = slot(player, "TACKLE")
  battle:takeTurn({ kind = "move", move = "BIDE" })
  local turns = runBide(battle, "TACKLE")

  check(turns <= 7, "bide still reaches its unleash when the menu says TACKLE")
  eq(tackle.pp, tackle.maxPp, "and the move the menu named was never spent")
  eq(battle:volatile(player).bideTurns, nil,
    "the counter is cleared rather than stranded")
end

-- ---- the lock ends with the unleash ---------------------------------------
do
  local battle, player = newBattle()
  runBide(battle, "BIDE")
  eq(battle:lockedInMove(player), nil, "the lock lifts once bide unleashes")
  eq(battle:volatile(player).bideStored, nil, "and the store is cleared with it")
end

T.finish("gold bide lock-in and pp")

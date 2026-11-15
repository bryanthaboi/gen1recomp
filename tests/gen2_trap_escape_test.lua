-- The no-escape web around a Gen 2 battle: Mean Look's CANT_RUN pin, the
-- Bind class wrap count, the FORCESHINY / TRAP battle types, and Roar and
-- Whirlwind's force switch -- including a wild mon's own Roar ending the
-- battle as a draw so a roamer banks its HP.
--
--   luajit tests/gen2_trap_escape_test.lua
--
-- ROM-free.  pokegold: core.asm TryToRunAwayFromBattle / TryEnemyFlee /
-- TryPlayerSwitch, effect_commands.asm BattleCommand_ArenaTrap /
-- BattleCommand_ForceSwitch, and BattleEnd_HandleRoamMons' non-WIN arm
-- (src/core/gen2/Roamers.endBattle).

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 trap escape")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local Roamers = require("src.core.gen2.Roamers")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  ELECTRIC = { id = "ELECTRIC", index = 23, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  MEAN_LOOK = { id = "MEAN_LOOK", name = "MEAN LOOK", power = 0,
    type = "NORMAL", accuracy = 100, accuracyRaw = 255, pp = 5, effect = "EFFECT_MEAN_LOOK" },
  WRAP = { id = "WRAP", name = "WRAP", power = 15, type = "NORMAL",
    accuracy = 85, accuracyRaw = 216, pp = 20, effect = "EFFECT_TRAP_TARGET" },
  ROAR = { id = "ROAR", name = "ROAR", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_FORCE_SWITCH" },
  WHIRLWIND = { id = "WHIRLWIND", name = "WHIRLWIND", power = 0,
    type = "NORMAL", accuracy = 100, accuracyRaw = 255, pp = 20,
    effect = "EFFECT_FORCE_SWITCH" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local function species(id, index, speed)
  return {
    id = id, index = index, name = id,
    baseStats = { hp = 70, attack = 80, defense = 50, speed = speed or 35,
      specialAttack = 65, specialDefense = 65 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 100,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  }
end

local POKEMON = {
  growthRates = GROWTH,
  MACHOP = species("MACHOP", 66, 35),
  PIDGEY = species("PIDGEY", 16, 56),
  -- The one species name that matters: Roamers.ALWAYS_FLEE keys off it.
  RAIKOU = species("RAIKOU", 243, 115),
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {},
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

local function mon(id, level, moves)
  local built = Mon.new(DATA, id, level, { dvs = perfect })
  local list = {}
  for i, moveId in ipairs(moves or { "TACKLE" }) do
    list[i] = { id = moveId, pp = 20, maxPp = 20 }
  end
  built.moves = list
  return built
end

local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if (event.kind == "message" or event.kind == "run"
        or event.kind == "send") and event.text == text then
      return true
    end
  end
  return false
end

-- ---- Mean Look pins a roamer ----------------------------------------------
do
  local player = mon("MACHOP", 45, { "MEAN_LOOK", "TACKLE" })
  local raikou = mon("RAIKOU", 40)
  local battle = Battle.new({ data = DATA, party = { player }, wild = raikou,
    roaming = 1, random = rolls({}, 1) })

  -- AlwaysFleeMons: with no pin the beast is gone before it can be fought.
  eq(battle:tryEnemyFlee(), true, "an unpinned RAIKOU always flees")
  battle.over, battle.outcome = false, nil

  battle:useMove(player, raikou, "MEAN_LOOK")
  eq(player.volatile.trapsTarget, true,
    "ArenaTrap: CANT_RUN lives on the USER's side")
  check(findText(battle:takeEvents(), battle:romText("CantEscapeNowText", player, raikou)),
    "CantEscapeNowText")
  eq(battle:tryEnemyFlee(), false,
    "TryEnemyFlee reads the player's substatus and stays")

  -- The pin dies with its user: a switch drops the volatile.
  battle:clearVolatile(player)
  eq(battle:tryEnemyFlee(), true, "with the user gone the beast flees again")
end

-- ---- a wrap pins the flee and the run -------------------------------------
do
  local player = mon("MACHOP", 45, { "WRAP" })
  local raikou = mon("RAIKOU", 40)
  local battle = Battle.new({ data = DATA, party = { player }, wild = raikou,
    roaming = 1, random = rolls({ 1, 0, 0, 1 }, 1) })
  battle:useMove(player, raikou, "WRAP")
  eq(raikou.volatile.wrapCount, 4, "the wrap count is live")
  eq(battle:tryEnemyFlee(), false, "wEnemyWrapCount pins the flee")

  -- The mirrored gate: a WRAPPED PLAYER cannot run or switch voluntarily.
  local player2 = mon("MACHOP", 45)
  local bench = mon("PIDGEY", 40)
  local wild = mon("PIDGEY", 40, { "WRAP" })
  local battle2 = Battle.new({ data = DATA, party = { player2, bench },
    wild = wild, random = rolls({ 1, 0, 0, 1 }, 1) })
  battle2:useMove(wild, player2, "WRAP")
  eq(player2.volatile.wrapCount, 4, "the player's mon is wrapped")
  eq(battle2:tryRun(), false, "TryToRunAwayFromBattle refuses")
  check(findText(battle2:takeEvents(), "Can't escape!"),
    "with the cart's line")
  eq(battle2:switchLocked(), true,
    "TryPlayerSwitch's .check_trapped refuses the voluntary switch")
end

-- ---- Mean Look on the player pins the run and the switch -------------------
do
  local player = mon("MACHOP", 45)
  local bench = mon("PIDGEY", 40)
  local wild = mon("PIDGEY", 40, { "MEAN_LOOK" })
  local battle = Battle.new({ data = DATA, party = { player, bench },
    wild = wild, random = rolls({}, 1) })
  battle:useMove(wild, player, "MEAN_LOOK")
  eq(wild.volatile.trapsTarget, true, "the wild side pinned the player")
  eq(battle:tryRun(), false, "no running from a Mean Look")
  eq(battle:switchLocked(), true, "and no voluntary switch either")

  -- Battle:switch (the faint path's entry too) breaks every trap on send.
  battle:switch(2)
  eq(battle:switchLocked(), false, "a send-out clears the pin")
end

-- ---- FORCESHINY and TRAP forbid running -----------------------------------
do
  for _, battleType in ipairs({ Battle.BATTLETYPE_FORCESHINY,
      Battle.BATTLETYPE_TRAP }) do
    local player = mon("MACHOP", 45)
    local wild = mon("PIDGEY", 30)
    local battle = Battle.new({ data = DATA, party = { player },
      wild = wild, battleType = battleType, random = rolls({}, 1) })
    eq(battle:tryRun(), false,
      "battle type " .. battleType .. " jumps straight to .cant_escape")
    check(findText(battle:takeEvents(), "Can't escape!"),
      "with the cart's line for type " .. battleType)
    eq(battle.over, false, "the battle goes on")

    -- BattleCommand_ForceSwitch fails for the same two types.
    player.moves = { { id = "ROAR", pp = 20, maxPp = 20 } }
    battle:useMove(player, wild, "ROAR")
    eq(battle.over, false, "Roar cannot end a type-" .. battleType .. " battle")
    check(findText(battle:takeEvents(), "But it failed!"),
      "ForceSwitch's .fail for type " .. battleType)
  end
end

-- ---- a wild mon's own Roar ends the battle --------------------------------
do
  -- The wild PIDGEY is level 40 against a level 40 player: `cp` with the
  -- user's level at or above the target's succeeds outright.
  local save = {}
  local roamEncounters = require("tests.fixtures.gen2_roamers").encounters("gold")
  Roamers.init(save, { encounters = roamEncounters })
  local player = mon("MACHOP", 40)
  local wild = mon("PIDGEY", 40, { "ROAR" })
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rolls({}, 1) })
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  eq(battle.over, true, "the wild Roar ends the battle")
  eq(battle.outcome, "fled", "as the DRAW that banks a roamer's HP")
  check(findText(events, battle:romText("FledInFearText", wild, player)),
    "FledInFearText names the mon sent away")

  -- BattleEnd_HandleRoamMons' non-WIN arm: the outcome banks the HP.
  Roamers.endBattle(save, 1, battle.outcome, 120, nil, rolls({}, 1),
    roamEncounters)
  eq(Roamers.slot(save, 1).hp, 120, "the roamer slot banked the HP")
  check(Roamers.slot(save, 1).species ~= nil, "and the beast is NOT retired")
end

-- ---- the player's Roar on a wild mon --------------------------------------
do
  local player = mon("MACHOP", 45, { "ROAR" })
  local wild = mon("PIDGEY", 30)
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rolls({}, 1) })
  battle:useMove(player, wild, "ROAR")
  eq(battle.over, true, "a higher-level Roar sends the wild mon off")
  eq(battle.outcome, "fled", "as a draw, not a win")
  check(findText(battle:takeEvents(), battle:romText("FledInFearText", player, wild)),
    "FledInFearText")
end

-- ---- trainer Roar drags a bench mon out -----------------------------------
do
  local player = mon("MACHOP", 45)
  local bench = mon("PIDGEY", 40)
  local roarer = mon("PIDGEY", 40, { "ROAR" })
  local battle = Battle.new({ data = DATA, party = { player, bench },
    trainer = { class = "FALKNER_X", name = "TESTER", party = { roarer } },
    random = rolls({}, 1) })

  -- The user must be moving SECOND (wEnemyGoesFirst): with the player first,
  -- the enemy's Roar drags the player's bench mon out.
  battle.firstMover = "player"
  battle:useMove(roarer, player, "ROAR")
  eq(battle.player, bench, "the bench PIDGEY was dragged out")
  eq(battle.participants[2], true, "and counts as a participant")
  check(findText(battle:takeEvents(), battle:romText("DraggedOutText", bench)),
    "DraggedOutText")
  eq(battle.over, false, "a trainer battle goes on")

  -- Moving first, the same Roar fails.
  local battle2 = Battle.new({ data = DATA,
    party = { mon("MACHOP", 45), mon("PIDGEY", 40) },
    trainer = { class = "FALKNER_X", name = "TESTER",
      party = { mon("PIDGEY", 40, { "ROAR" }) } },
    random = rolls({}, 1) })
  battle2.firstMover = "enemy"
  battle2:useMove(battle2.enemy, battle2.player, "ROAR")
  eq(battle2.player, battle2.party[1], "moving first, the Roar moves nobody")
  check(findText(battle2:takeEvents(), "But it failed!"),
    "ForceSwitch's `.switch_fail` needs the user to move second")

  -- With nothing on the bench there is nobody to drag.
  local battle3 = Battle.new({ data = DATA, party = { mon("MACHOP", 45) },
    trainer = { class = "FALKNER_X", name = "TESTER",
      party = { mon("PIDGEY", 40, { "ROAR" }) } },
    random = rolls({}, 1) })
  battle3.firstMover = "player"
  battle3:useMove(battle3.enemy, battle3.player, "ROAR")
  check(findText(battle3:takeEvents(), "But it failed!"),
    "CheckPlayerHasMonToSwitchTo carries: no bench, no drag")
end

S.finish()

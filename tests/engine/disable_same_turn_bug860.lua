-- Disable blocks the move the slower mon ALREADY selected, on the very
-- turn the Disable lands (#860).  pokered runs the test at execution
-- time, not at selection time: CheckPlayerStatusConditions
-- .TriedToUseDisabledMoveCheck (engine/battle/core.asm:3437-3447) compares
-- wPlayerDisabledMoveNumber against wPlayerSelectedMove and jumps to
-- ExecutePlayerMoveDone when they match -- "prevents a disabled move that
-- was selected before being disabled from being used", in the asm's own
-- comment.  The enemy copy is .checkIfTriedToUseDisabledMove
-- (core.asm:5752+).  The port only refused a disabled move at menu time,
-- so the second mover still fired the move it had latched before the
-- Disable resolved.
--
-- The check sits after the confusion block and before the paralysis roll,
-- so this suite also pins the neighbours: the counter tick that clears an
-- expired Disable still runs first, and a move that was never disabled is
-- untouched.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

-- the fixture dataset has no status move; this dataset is this file's own
-- copy (fixtures.fresh), so registering one here cannot leak into another
-- case.  Accuracy 100 keeps DisableEffect's MoveHitTest out of the way.
Data.moves.FIX_DISABLE = {
  id = "FIX_DISABLE", index = 90, name = "FIX DISABLE",
  type = "NORMAL", power = 0, accuracy = 100, pp = 20,
  effect = "DISABLE_EFFECT",
}

-- Deterministic rolls: the minimum of every range, except DisableEffect's
-- own "1-8 turns disabled" roll (effects.asm:1343-1345), which is pinned
-- at 4.  A rolled 1 would be spent by the disabled mon's own counter tick
-- in the same CheckStatusConditions pass -- vanilla behaviour, but it
-- clears the disable before .TriedToUseDisabledMoveCheck can see it, so it
-- is not the case this suite is about.  rng(0, 255) -> 0 makes every
-- accuracy roll hit.
local function rolls(disableTurns)
  return function(a, b)
    if a == 1 and b == 8 then return disableTurns end
    if a then return a end
    return 0
  end
end

-- playerFirst decides who lands the Disable; the other side is the one
-- whose already-selected move has to die.  Both mons get FIX_TACKLE in
-- slot 1 (the slot DisableEffect picks with the min roll) and FIX_SCRATCH
-- in slot 2 as the never-disabled control.
local function newBattle(playerFirst, disableTurns)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.rng = rolls(disableTurns or 4)

  local function loadout(battler)
    battler.mon.moves = {
      { id = "FIX_TACKLE", pp = 35 },
      { id = "FIX_SCRATCH", pp = 35 },
      { id = "FIX_DISABLE", pp = 20 },
    }
    battler.curMoves = battler.mon.moves
  end
  loadout(battle.player)
  loadout(battle.enemy)

  -- no speed tie to resolve: the disabler outruns its target outright
  battle.player.curStats.speed = playerFirst and 200 or 1
  battle.enemy.curStats.speed = playerFirst and 1 or 200
  return battle
end

-- the move instances the sides actually own, so PP decrements land on
-- the party copy the way DecrementPP mutates wBattleMonPP
local function slot(battler, i) return battler.curMoves[i] end

-- consume the queue the way updateQueue does, minus the presentation
local function drain(battle)
  local rows = {}
  for _ = 1, 400 do
    local item = table.remove(battle.queue, 1)
    if not item then return rows end
    if item.text then rows[#rows + 1] = { text = item.text } end
    if item.fn then
      battle.nextInsert = 0
      item.fn()
    end
  end
  error("the turn queue never drained")
end

local function saidWith(rows, needle)
  for i, row in ipairs(rows) do
    if row.text and row.text:find(needle, 1, true) then return i end
  end
  return nil
end

-- "X's / MOVE is / disabled!" (PrintMoveIsDisabledText) versus
-- DisableEffect's own "MOVE was / disabled!" -- the two lines differ only
-- in that verb, so match on it
local function blocked(rows) return saidWith(rows, "is\vdisabled!") end
local function landed(rows) return saidWith(rows, "was\vdisabled!") end
local function usedTackle(rows) return saidWith(rows, "used FIX TACKLE!") end

-- ---------------------------------------------------------------------
-- the player Disables first; the foe's latched FIX TACKLE dies this turn
-- ---------------------------------------------------------------------
do
  local battle = newBattle(true)
  battle.enemyAction = function() return slot(battle.enemy, 1) end
  local hpBefore = battle.player.mon.hp

  battle:resolveTurn(slot(battle.player, 3))
  local rows = drain(battle)

  T.check(landed(rows) ~= nil, "the Disable lands")
  T.eq(battle.enemy.disabledSlot, 1, "and latches onto the foe's slot 1")
  T.check(blocked(rows) ~= nil,
    "the foe's already-selected move reports as disabled")
  T.check(landed(rows) and blocked(rows) and landed(rows) < blocked(rows),
    "in that order: disabled first, then the blocked attempt")
  T.check(usedTackle(rows) == nil,
    "the disabled move is never announced, so it never executed")
  T.eq(battle.player.mon.hp, hpBefore, "and it deals no damage")
  T.eq(battle.enemy.disabledTurns, 3,
    "the counter ticked once for this turn and the disable is still live")
end

-- ---------------------------------------------------------------------
-- the same, mirrored: the foe Disables first and the player's latched
-- move dies (core.asm:5752 .checkIfTriedToUseDisabledMove)
-- ---------------------------------------------------------------------
do
  local battle = newBattle(false)
  battle.enemyAction = function() return slot(battle.enemy, 3) end
  local hpBefore = battle.enemy.mon.hp
  local ppBefore = slot(battle.player, 1).pp

  battle:resolveTurn(slot(battle.player, 1))
  local rows = drain(battle)

  T.check(landed(rows) ~= nil, "the foe's Disable lands")
  T.eq(battle.player.disabledSlot, 1, "on the player's slot 1")
  T.check(blocked(rows) ~= nil, "the player's latched move reports as disabled")
  T.check(usedTackle(rows) == nil, "and is never announced")
  T.eq(battle.enemy.mon.hp, hpBefore, "the foe takes no damage")
  T.eq(slot(battle.player, 1).pp, ppBefore,
    "and the move that never executed spends no PP (DecrementPP is inside "
    .. "the move, past the status gauntlet)")
end

-- ---------------------------------------------------------------------
-- no regression on the turns after: the disable keeps blocking that move
-- while its counter runs, and a different move still works
-- ---------------------------------------------------------------------
do
  local battle = newBattle(true)
  battle.enemyAction = function() return slot(battle.enemy, 1) end
  battle:resolveTurn(slot(battle.player, 3))
  drain(battle)
  T.eq(battle.enemy.disabledTurns, 3, "the disable is live going into turn 2")

  -- turn 2: the foe picks the disabled move with no Disable in flight
  local hpBefore = battle.player.mon.hp
  battle:resolveTurn(slot(battle.player, 2))
  local rows = drain(battle)
  T.check(blocked(rows) ~= nil, "turn 2 still blocks the disabled move")
  T.check(usedTackle(rows) == nil, "still no execution")
  T.eq(battle.player.mon.hp, hpBefore, "still no damage")
  T.eq(battle.enemy.disabledTurns, 2, "and the counter keeps ticking down")

  -- turn 3: the foe picks its OTHER move, which was never disabled
  battle.enemyAction = function() return slot(battle.enemy, 2) end
  hpBefore = battle.player.mon.hp
  rows = (function() battle:resolveTurn(slot(battle.player, 2)); return drain(battle) end)()
  T.check(blocked(rows) == nil, "an undisabled move is not blocked")
  T.check(saidWith(rows, "used FIX SCRATCH!") ~= nil, "it is announced")
  T.check(battle.player.mon.hp < hpBefore, "and it deals damage")
end

-- ---------------------------------------------------------------------
-- the counter tick still runs ahead of the check: a disable that expires
-- on this turn frees the move it was holding (.DisabledCheck precedes
-- .TriedToUseDisabledMoveCheck)
-- ---------------------------------------------------------------------
do
  local battle = newBattle(true)
  battle.enemy.disabledSlot, battle.enemy.disabledTurns = 1, 1
  battle.enemyAction = function() return slot(battle.enemy, 1) end
  local hpBefore = battle.player.mon.hp

  battle:resolveTurn(slot(battle.player, 2))
  local rows = drain(battle)

  T.check(saidWith(rows, "disabled no more!") ~= nil, "the disable expires")
  T.check(blocked(rows) == nil, "so the move is not blocked")
  T.check(usedTackle(rows) ~= nil, "it executes")
  T.check(battle.player.mon.hp < hpBefore, "and deals damage")
end

T.finish("disable blocks the already-selected move (#860)")

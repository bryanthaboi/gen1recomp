-- A mon halfway through a two-turn move must not choose again.
--
--   luajit tests/gen2_charge_lock_test.lua
--
-- Found by the Gold route bot (tests/drivers/gold_bot.lua), which lost to
-- ELITE FOUR BRUNO seventeen times running at levels 62 through 85 and could
-- not have won at any level:
--
--   ELITE FOUR BRUNO sent out HITMONLEE!
--   HITMONLEE used DIG!
--   HITMONLEE flew up high!
--   TYPHLOSION used STRENGTH!
--   TYPHLOSION's attack missed!
--   HITMONLEE used HI JUMP KICK!
--   TYPHLOSION used STRENGTH!
--   TYPHLOSION's attack missed!          <- forever
--
-- On the cart the charge sets SUBSTATUS_CHARGED and CheckEnemyTurn reuses
-- wEnemySelectedMove, so the second turn IS the stored move. The port asked the
-- AI again. That skips the stored attack, and because `vanished` is only
-- cleared by the branch in Battle:useMove that recognises the second half, the
-- mon stays semi-invulnerable for the rest of the battle -- untouchable by
-- anything, while still attacking every turn.
--
-- DIG and FLY are one effect in Gen 2 (EFFECT_FLY), which is also why DIG
-- announced itself with Fly's line; BattleCommand_Fly picks the text off the
-- move (`cp DIG`), not the effect.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 charge lock")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")

-- Battle:enemyMove reads exactly two things before the lock returns, so the
-- lock can be driven against a stub. `asked` records whether the AI was
-- consulted at all -- on the second turn it must not be.
local function enemyStub(chargeMove, pool)
  local asked = { count = 0 }
  local volatiles = { enemy = { chargeMove = chargeMove } }
  local self_ = {
    enemy = { moves = pool, hp = 100 },
    random = function() return 0 end,
    volatile = function(_, mon) return volatiles.enemy end,
    usableMoves = function()
      asked.count = asked.count + 1
      return pool
    end,
    moveDef = function(_, id) return { name = id } end,
    trainer = nil,
  }
  return self_, asked
end

local POOL = { { id = "HI_JUMP_KICK", pp = 10 }, { id = "DIG", pp = 10 } }

-- The bug: mid-charge, the AI is asked and answers something else.
do
  local self_, asked = enemyStub("DIG", POOL)
  local chosen = Battle.enemyMove(self_)
  eq(chosen, "DIG", "a charging enemy uses the move it stored")
  eq(asked.count, 0, "and the AI is never consulted for the second turn")
end

-- Not charging: the AI still runs. Without a trainer, flagsOf is 0 and the
-- choice is the random branch, which with a zeroed rng is the first move.
do
  local self_, asked = enemyStub(nil, POOL)
  local chosen = Battle.enemyMove(self_)
  eq(asked.count, 1, "with no stored charge the AI is consulted")
  check(chosen == "HI_JUMP_KICK" or chosen == "DIG",
        "and it picks from the pool")
end

-- The other half of the invariant, in the real code: useMove's second-turn
-- branch is what clears `vanished`, and it only fires when the move it is
-- handed equals the stored one. This is the line the missing lock bypassed.
do
  local Effects = require("src.battle.gen2.Effects")
  check(Effects.CHARGE.EFFECT_FLY ~= nil,
        "EFFECT_FLY is a charge effect")
  check(Effects.CHARGE.EFFECT_FLY.vanish == true,
        "and it is the one that makes the user untargetable")
end

-- DIG's own announcement. Same effect as FLY, different line.
do
  local Effects = require("src.battle.gen2.Effects")
  local data = { text = require("tests.fixture_data.gen2_rom_text_s7_b").text() }
  eq(Effects.chargeText(data, "EFFECT_FLY", "DIG", "DIGLETT"),
     "DIGLETT\ndug a hole!",
     "DIG's charge text is chosen off the move, not the effect")
  eq(Effects.chargeText(data, "EFFECT_FLY", "FLY", "PIDGEY"),
     "PIDGEY\nflew up high!",
     "and FLY keeps the effect's own _BattleFlewText")
end

-- ---------------------------------------------------------------------------
-- The other free turn: HYPER BEAM's recharge.
--
-- BattleCommand_RechargeNextTurn sets SUBSTATUS_RECHARGE; CheckPlayerTurn and
-- CheckEnemyTurn spend the following turn clearing it and printing
-- MustRechargeText. The port had none of it, so HYPER BEAM was 150 power at no
-- cost -- and CHAMPION LANCE's three DRAGONITE all carry it, firing it every
-- turn instead of every other one.
local function actorStub(vol, status)
  local said = {}
  local self_ = {
    data = { text = require("tests.gen2_battle_text_fixture")() },
    mon = { status = status },
    volatile = function() return vol end,
    monName = function() return "DRAGONITE" end,
    battlerName = function() return "DRAGONITE" end,
    romText = Battle.romText,
    emit = function(_, ev) said[#said + 1] = ev.text end,
    random = function() return 1 end,
  }
  return self_, said
end

do
  local vol = { recharge = true }
  local self_, said = actorStub(vol)
  local acted = Battle.canAct(self_, self_.mon)
  eq(acted, false, "a recharging mon loses its turn")
  eq(said[1], "DRAGONITE\nmust recharge!", "and says so")
  check(vol.recharge == nil, "the flag is consumed, not sticky")
  -- The very next turn it is free again: this is the half that makes it cost
  -- one turn rather than end the mon's participation.
  eq(Battle.canAct(self_, self_.mon), true, "and the turn after, it acts")
end

-- Recharge is read BEFORE status, so a mon that is both recharging and asleep
-- spends this turn recharging (and does not burn a sleep turn).
do
  local vol = { recharge = true }
  local self_ = actorStub(vol, "sleep")
  self_.mon.statusTurns = 3
  eq(Battle.canAct(self_, self_.mon), false, "recharge wins over sleep")
  eq(self_.mon.statusTurns, 3, "and the sleep counter is untouched")
end

-- The setter. Driving Battle:useMove needs a whole battle, so pin the wiring
-- at the source: the effect that sets it, and the field canAct consumes.
do
  local src = io.open("src/battle/gen2/Battle.lua"):read("*a")
  check(src:find('EFFECT_HYPER_BEAM', 1, true) ~= nil,
        "HYPER BEAM's effect is handled in the damage path")
  check(src:find('state.recharge = true', 1, true) ~= nil,
        "and it arms the recharge the cart arms")
end

S.finish()

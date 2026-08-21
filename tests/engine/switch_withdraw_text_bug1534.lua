-- SwitchPlayerMon (engine/battle/core.asm:2419-2423) prints RetreatMon and
-- holds 50 frames BEFORE the outgoing pic is recalled, and only then does
-- SendOutMon shout "Go! X!" (#1534).  The port queued the send-out line
-- alone, so the withdraw box never existed.  PlayerMon2Text's adjective
-- (engine/battle/common_text.asm:167-243) reads the ENEMY HP lost since
-- this mon switched in, from wLastSwitchInEnemyMonHP.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Timing = require("src.core.Timing")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30), Pokemon.new(Data, "FIXMON_B", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.rng = function() return 0 end
  battle.enemyAction = function() return { id = "FIX_SCRATCH", pp = 35 } end
  return battle
end

-- drain the queue the way updateQueue does, recording rows in order plus
-- who was in the player slot when each row was emitted
local function drain(battle)
  local rows = {}
  for _ = 1, 400 do
    local item = table.remove(battle.queue, 1)
    if not item then return rows end
    rows[#rows + 1] = { text = item.text, anim = item.anim,
                        auto = item.auto, autoDelay = item.autoDelay,
                        playerSpecies = battle.player.mon.species }
    if item.fn then
      battle.nextInsert = 0
      item.fn()
    end
  end
  error("the queue never drained")
end

local function indexOf(rows, pred)
  for i, row in ipairs(rows) do
    if pred(row) then return i end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- the voluntary party-menu switch: withdraw line, then the send-out
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  drain(battle) -- the intro stamps lastSwitchInEnemyHP through sendOutText
  local outgoing = battle.player.mon.species
  local oldNick = battle.player.name
  battle.queue, battle.nextInsert = {}, 0
  battle:resolveSwitch(battle.game.save.party[2])
  local rows = drain(battle)

  local wIdx = indexOf(rows, function(r)
    return r.text and r.text:find("Come back!", 1, true) ~= nil
  end)
  T.check(wIdx ~= nil, "the withdraw line is queued")
  T.eq(rows[wIdx].text, oldNick .. " enough!\nCome back!",
    "an untouched foe gives the `enough!` variant")
  T.eq(rows[wIdx].auto, true, "the page ends `done`, so it never waits on A")
  T.eq(rows[wIdx].autoDelay, Timing.SWITCH_PLAYER_MON,
    "it holds the 50 frames DelayFrames pays (core.asm:2421-2422)")
  T.eq(rows[wIdx].playerSpecies, outgoing,
    "the outgoing mon is still in the slot while the line prints")

  local sIdx = indexOf(rows, function(r)
    return r.text and r.text:find("! ", 1, true) and r.text:find("Come back!", 1, true) == nil
  end)
  T.check(sIdx ~= nil and sIdx > wIdx, "the send-out shout follows the withdraw line")
  T.eq(rows[sIdx].auto, true, "the send-out page ends `done` too (#1472)")
  T.neq(rows[sIdx].playerSpecies, outgoing, "the swap happened between the two")
end

-- ---------------------------------------------------------------------
-- the adjective branches on enemy HP lost since the switch-in
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  drain(battle)
  local nick = battle.player.name
  local max = battle.enemy.mon.stats.hp
  local quarter = math.floor(max / 4)
  local function withdrawAt(dropPercent)
    battle.lastSwitchInEnemyHP = max
    battle.enemy.mon.hp = max - math.floor(dropPercent * quarter / 25)
    return battle:withdrawText(nick)
  end
  T.eq(withdrawAt(0), nick .. " enough!\nCome back!", "no damage -> `enough!`")
  T.eq(withdrawAt(50), nick .. " OK!\nCome back!", "30-69 -> `OK!`")
  T.eq(withdrawAt(80), nick .. " good!\nCome back!", "70+ -> `good!`")
  T.eq(withdrawAt(10), nick .. " \nCome back!", "1-29 -> no adjective at all")
end

-- ---------------------------------------------------------------------
-- ChooseNextMon (core.asm:1086-1128) calls SendOutMon with NO RetreatMon
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  drain(battle)
  battle.queue, battle.nextInsert = {}, 0
  battle.player.mon.hp = 0
  battle:openReplacementMenu()
  local rows = drain(battle)
  T.check(indexOf(rows, function(r)
    return r.text and r.text:find("Come back!", 1, true) ~= nil
  end) == nil, "the post-faint replacement prints no withdraw line")
end

T.finish("switch withdraw text (#1534)")

-- _TrainerSentOutText (data/text/text_2.asm:923) and the
-- Go!/Do it!/Get'm! chain ending in _PlayerMon1Text (:1274-1294) end in
-- `done`, not `prompt`: PrintText returns and the flow runs straight into
-- AnimateSendingOutMon + PlayCry (engine/battle/core.asm:1421-1434,
-- :1723-1765).  _AIBattleWithdrawText (:1-7) does end in `prompt` and
-- keeps its button wait.  The port made every send-out box wait (#1472).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
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

local function rowWith(battle, needle)
  for _, item in ipairs(battle.queue) do
    if item.text and item.text:find(needle, 1, true) then return item end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- the voluntary switch: the shout auto-continues into the send-out anim
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:resolveSwitch(battle.game.save.party[2])
  -- run the first act so the nested switch rows land in the queue
  local first = table.remove(battle.queue, 1)
  battle.nextInsert = 0
  first.fn()
  local withdraw = rowWith(battle, "Come back!")
  T.check(withdraw ~= nil, "the withdraw line is queued")
  T.eq(withdraw.auto, true, "RetreatMon's page ends `done` (#1534)")
  local swap = table.remove(battle.queue, 2)
  battle.nextInsert = 1
  swap.fn()
  local shout = rowWith(battle, battle.player.name)
  T.check(shout ~= nil, "the send-out shout is queued")
  T.eq(shout.auto, true, "_PlayerMon1Text ends `done`, so no button wait")
end

-- ---------------------------------------------------------------------
-- the AI switch: the sent-out box goes auto, the withdraw box does not,
-- and EnemySendOut's grow-in + cry now follow it
-- ---------------------------------------------------------------------
do
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.rng = function() return 0 end
  battle.enemyParty = { Pokemon.new(Data, "FIXMON_B", 30),
                        Pokemon.new(Data, "FIXMON_C", 30) }
  battle.enemyIndex = 1
  battle.enemy = battle.enemy or nil
  battle.queue, battle.nextInsert = {}, 0
  battle:executeAction(battle.enemy, battle.player,
                       { special = "aiSwitch", index = 2 })
  local withdrew = rowWith(battle, "with-")
  local sent = rowWith(battle, "sent")
  T.check(withdrew ~= nil, "the AI withdraw line is queued")
  T.eq(withdrew.auto, nil, "_AIBattleWithdrawText ends `prompt` and still waits")
  T.check(sent ~= nil, "the sent-out line is queued")
  T.eq(sent.auto, true, "_TrainerSentOutText ends `done`")
  T.eq(battle.enemySendingOut, true,
    "the new pic stays hidden until AnimateSendingOutMon")
  local acts = 0
  for _, item in ipairs(battle.queue) do
    if item.fn then acts = acts + 1 end
  end
  T.check(acts >= 1, "EnemySendOut queues the grow-in act after the text")
end

-- ---------------------------------------------------------------------
-- the post-faint replacement (ChooseNextMon -> SendOutMon, core.asm:1124)
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  local pushedUI
  battle.game.stack.push = function(_, s) pushedUI = s end
  battle.queue, battle.nextInsert = {}, 0
  battle.player.mon.hp = 0
  battle:openReplacementMenu()
  local onSwitch
  for _, item in ipairs(battle.queue) do
    if item.ui then
      local screen = item.ui()
      onSwitch = screen and screen.onSwitch
    end
  end
  onSwitch = onSwitch or (pushedUI and pushedUI.onSwitch)
  if onSwitch then
    battle.nextInsert = 0
    onSwitch(battle.game.save.party[2])
    local shout = rowWith(battle, battle.player.name)
    T.check(shout ~= nil, "the replacement shout is queued")
    T.eq(shout.auto, true, "SendOutMon's message ends `done` here too")
  else
    T.check(false, "the replacement menu offers an onSwitch callback")
  end
end

T.finish("trainer send-out boxes (#1472)")

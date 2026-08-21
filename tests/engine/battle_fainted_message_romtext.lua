-- BattleState:onFaint's "%s\nfainted!" collapsed two distinct ROM
-- strings (_EnemyMonFaintedText already carries its own "Enemy" wording;
-- _PlayerMonFaintedText does not) into one literal, substituted with
-- displayName(battler) -- which itself runs the enemy name through a
-- SEPARATE Strings("Enemy %s", ...) call. The fix passes the raw
-- battler.name and lets each label supply its own wording. This test
-- fakes both labels and checks the raw name reaches the right one, with
-- no "Enemy" ever duplicated.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function mkbattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 10) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  return BattleState.newWild(game, "FIXMON_C", 8)
end

-- finds the queued say-message text (onFaint queues several entries: a
-- wait, then the say)
local function findText(battle)
  for _, entry in ipairs(battle.queue) do
    if entry.text then return entry.text end
  end
  return nil
end

-- enemy: translated _EnemyMonFaintedText reaches onFaint, raw name only
do
  local battle = mkbattle()
  Data.text._EnemyMonFaintedText = "FAKE-ENEMY {RAM:wEnemyMonNick} FAKE!"
  battle:onFaint(battle.enemy)
  T.eq(findText(battle), "FAKE-ENEMY " .. battle.enemy.name .. " FAKE!",
    "a translated _EnemyMonFaintedText reaches the enemy faint message")
  Data.text._EnemyMonFaintedText = nil
end

-- enemy vanilla: the English literal already carries "Enemy " itself
do
  local battle = mkbattle()
  battle:onFaint(battle.enemy)
  T.eq(findText(battle), "Enemy " .. battle.enemy.name .. "\nfainted!",
    "no catalog entry falls back to the English literal, Enemy included")
end

-- player: translated _PlayerMonFaintedText reaches onFaint
do
  local battle = mkbattle()
  Data.text._PlayerMonFaintedText = "FAKE-PLAYER {RAM:wBattleMonNick} FAKE!"
  battle:onFaint(battle.player)
  T.eq(findText(battle), "FAKE-PLAYER " .. battle.player.name .. " FAKE!",
    "a translated _PlayerMonFaintedText reaches the player faint message")
  Data.text._PlayerMonFaintedText = nil
end

T.finish("battle_fainted_message_romtext")

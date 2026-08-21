-- HandleSelfConfusionDamage (engine/battle/core.asm:3672-3714, enemy side
-- :5806-5811) (#1578)
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
  save.party = { Pokemon.new(Data, "FIXMON_A", 40) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  -- cp 50 percent + 1: rand < 128 hurts the user
  battle.rng = function() return 0 end
  return battle
end

local function rowsOf(battle)
  local out = {}
  for _, item in ipairs(battle.queue) do
    if item.anim then out[#out + 1] = item end
  end
  return out
end

do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.player.confusedTurns = 3
  T.eq(battle:statusInterrupt(battle.player, battle.enemy, nil), true,
    "the self-hit interrupts the player's action")
  local anims = rowsOf(battle)
  T.eq(#anims, 2, "the IsConfusedText onomatopoeia, then the self-hit's own")
  T.eq(anims[1].anim, "CONF_PLAYER_ANIM", "CONF_PLAYER_ANIM rides IsConfusedText")
  T.eq(anims[2].anim, "POUND", "wAnimationID 1 is POUND")
  T.eq(anims[2].attackerIsPlayer, false,
    "hWhoseTurn is flipped to the opponent, so it plays against the player")
  T.check(anims[2].hit == nil, "wAnimationType 0 adds no shake or blink layer")
  local text, anim
  for i, item in ipairs(battle.queue) do
    if item.text and item.text:find("confusion", 1, true) then text = text or i end
    if item.anim == "POUND" then anim = i end
  end
  T.check(text and anim and text < anim, "HurtItselfText prints before the animation")
end

do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.enemy.confusedTurns = 3
  battle:statusInterrupt(battle.enemy, battle.player, nil)
  local anims = rowsOf(battle)
  T.eq(anims[#anims].anim, "POUND", "the enemy side animates too")
  T.eq(anims[#anims].attackerIsPlayer, true, "from the player's side of hWhoseTurn")
end

T.finish("confusion self-hit animation (#1578)")

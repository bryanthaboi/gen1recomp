-- Parity test: Substitute's failure branches play no animation (#644).
-- SUBSTITUTE_EFFECT is a ResidualEffects1 entry
-- (data/battle/residual_effects_1.asm), so the caller never plays the move
-- animation; SubstituteEffect_ (engine/battle/move_effects/substitute.asm)
-- reaches PlayCurrentMoveAnimation / AnimationSubstitute only after
-- `set HAS_SUBSTITUTE_UP, [hl]`, while .alreadyHasSubstitute and
-- .notEnoughHP jump straight to PrintText.  The animation opens with
-- SE_SLIDE_MON_OFF, which hides the user's pic until the doll replaces it,
-- so a failed Substitute that still animated left the user invisible.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.moves and Data.moves.SUBSTITUTE) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity substitute anim")
local check, eq = S.check, S.eq

local function freshBattle()
  Game.save.party = { Pokemon.new(Data, "BULBASAUR", 20) }
  local tb = BattleState.newWild(Game, "PIDGEY", 10)
  tb.queue, tb.nextInsert = {}, 0
  return tb
end

local function anyAnim(tb, name)
  for _, row in ipairs(tb.queue) do
    if row.anim == name then return true end
  end
  return false
end

local function anyText(tb, needle)
  for _, row in ipairs(tb.queue) do
    if row.text and row.text:gsub("\n", " "):find(needle, 1, true) then return true end
  end
  return false
end

do
  local anims = Data.battle_anims and Data.battle_anims.moveAnims
  check(anims ~= nil, "battle_anims carries moveAnims")
  check(anims == nil or anims.SUBSTITUTE ~= nil, "SUBSTITUTE has an animation")
end

-- success: the doll animation plays and the substitute stands
do
  local tb = freshBattle()
  tb.enemy.mon.hp = tb.enemy.mon.stats.hp
  tb:performMove(tb.enemy, tb.player, { id = "SUBSTITUTE", pp = 10 }, false)
  check(tb.enemy.substituteHP ~= nil, "a healthy user builds its substitute")
  check(anyAnim(tb, "SUBSTITUTE"), "and the doll animation plays")
end

-- .notEnoughHP: text only, no animation, and no dangling row
do
  local tb = freshBattle()
  tb.enemy.mon.hp = math.floor(tb.enemy.mon.stats.hp / 4) - 1
  tb:performMove(tb.enemy, tb.player, { id = "SUBSTITUTE", pp = 10 }, false)
  check(tb.enemy.substituteHP == nil, "too little HP fails the substitute")
  check(not anyAnim(tb, "SUBSTITUTE"),
        "a failed substitute plays no animation (#644)")
  check(tb.moveAnimRow == nil, "the peeled move-anim row is not left dangling")
  check(anyText(tb, "SUBSTITUTE"), "the failure text still prints")
end

-- Exact quarter HP is also not enough: accepting it would leave the user at
-- 0 HP with substituteHP set, so the next trainer-battle turn cannot advance.
do
  local tb = freshBattle()
  local cost = math.floor(tb.enemy.mon.stats.hp / 4)
  tb.enemy.mon.hp = cost
  tb:performMove(tb.enemy, tb.player, { id = "SUBSTITUTE", pp = 10 }, false)
  check(tb.enemy.substituteHP == nil and tb.enemy.mon.hp == cost,
        "exact quarter HP cannot create a zero-HP substitute")
  check(not anyAnim(tb, "SUBSTITUTE"),
        "the exact-boundary failure plays no animation")
end

-- .alreadyHasSubstitute: same, with a doll already standing
do
  local tb = freshBattle()
  tb.enemy.mon.hp = tb.enemy.mon.stats.hp
  tb.enemy.substituteHP = 10
  tb:performMove(tb.enemy, tb.player, { id = "SUBSTITUTE", pp = 10 }, false)
  eq(tb.enemy.substituteHP, 10, "the standing substitute is untouched")
  check(not anyAnim(tb, "SUBSTITUTE"),
        "a second substitute plays no animation (#644)")
  check(tb.moveAnimRow == nil, "and peels its anim row")
end

S.finish()

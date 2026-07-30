-- Parity test: wAnimationType, the applying-attack animation pokered plays
-- after every move's own animation (#354).  PlayApplyingAttackAnimation
-- (engine/battle/animations.asm:475) dispatches through
-- AnimationTypePointerTable (:490-497) on six types: 1 enemy damaging plain
-- (vertical shake b=8), 2 enemy damaging with an added effect (fast
-- horizontal shake b=8), 3 enemy non-damaging (slow creep b=6 c=2), 4 player
-- damaging plain (blink the enemy pic), 5 player damaging with an added
-- effect (fast horizontal shake b=2), 6 player non-damaging (slow creep b=3
-- c=2).  GetPlayerAnimationType / GetEnemyAnimationType (core.asm:3159 /
-- :5555) pick 4/5 and 1/2 off wPlayerMoveEffect; the primary status handlers
-- that end in PlayCurrentMoveAnimation2 (effects.asm:1448) set 6/3.  Only 1
-- and 4 were wired, so Bubblebeam blinked instead of shaking and Hypnosis
-- showed nothing.  The shake generators themselves are
-- PredefShakeScreenHorizontally (engine/gfx/screen_effects.asm) and
-- AnimationShakeScreenHorizontallySlow (animations.asm:526-547).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.moves and Data.moves.BUBBLEBEAM) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity applying attack anim")
local check, eq = S.check, S.eq

-- rng floor: accuracyRoll compares rng(0, 255) against the scaled accuracy,
-- so the lowest roll lands HYPNOSIS (60%) every run
local function freshBattle()
  Game.save.options.animations = true
  Game.save.party = { Pokemon.new(Data, "SQUIRTLE", 30) }
  local tb = BattleState.newWild(Game, "PIDGEY", 10)
  tb.queue, tb.nextInsert = {}, 0
  tb.rng = function(a) return a end
  return tb
end

-- the hit rows a turn queued, in order (each carries sfx + animType)
local function hitRows(tb)
  local out = {}
  for _, row in ipairs(tb.queue) do
    if row.hit then out[#out + 1] = row.hit end
  end
  return out
end

local function typeOf(moveId, isPlayer)
  local tb = freshBattle()
  local user = isPlayer and tb.player or tb.enemy
  local target = isPlayer and tb.enemy or tb.player
  tb:performMove(user, target, { id = moveId, pp = 10 }, false)
  local rows = hitRows(tb)
  return rows[1] and rows[1].animType, #rows, rows
end

-- ------------------------------------------------- damaging moves, both sides
-- TACKLE is NO_ADDITIONAL_EFFECT; BUBBLEBEAM is SPEED_DOWN_SIDE_EFFECT and
-- CONFUSION is CONFUSION_SIDE_EFFECT, the two moves named in the report
do
  eq(Data.moves.TACKLE.effect, "NO_ADDITIONAL_EFFECT",
     "TACKLE has no added effect")
  eq(Data.moves.BUBBLEBEAM.effect, "SPEED_DOWN_SIDE_EFFECT",
     "BUBBLEBEAM drops SPEED as a side effect")
  eq(Data.moves.CONFUSION.effect, "CONFUSION_SIDE_EFFECT",
     "CONFUSION confuses as a side effect")

  eq(typeOf("TACKLE", true), 4, "player TACKLE blinks the enemy pic (type 4)")
  eq(typeOf("TACKLE", false), 1, "enemy TACKLE shakes vertically (type 1)")
  eq(typeOf("BUBBLEBEAM", true), 5,
     "player BUBBLEBEAM shakes horizontally light (type 5, #354)")
  eq(typeOf("BUBBLEBEAM", false), 2,
     "enemy BUBBLEBEAM shakes horizontally heavy (type 2)")
  eq(typeOf("CONFUSION", true), 5, "player CONFUSION is type 5 too (#354)")
  eq(typeOf("CONFUSION", false), 2, "and type 2 from the foe")
  eq(select(2, typeOf("BUBBLEBEAM", true)), 1,
     "one applying-attack row per hit, not one per stat drop")
end

-- the damage sound still rides the row (PlayApplyingAttackSound off
-- wDamageMultipliers), and every damaging type keeps a blink target so a
-- type-4 turn can still use it
do
  local _, _, rows = typeOf("BUBBLEBEAM", true)
  eq(rows[1].sfx, "Damage", "the row carries the damage sound")
  local _, _, plain = typeOf("TACKLE", true)
  check(plain[1].blink ~= nil, "a type-4 row carries the pic to blink")
end

-- ------------------------------------------------- primary status moves
-- PlayCurrentMoveAnimation2 call sites: SleepEffect (effects.asm:64),
-- PoisonEffect (:150), ConfusionSideEffectSuccess's primary branch (:1150),
-- DisableEffect (:1352), UpdateLoweredStatDone (:685)
do
  eq(typeOf("HYPNOSIS", true), 6, "HYPNOSIS creeps the screen (type 6, #354)")
  eq(typeOf("HYPNOSIS", false), 3, "and type 3 from the foe")
  eq(typeOf("GROWL", true), 6, "GROWL is a primary stat drop: type 6")
  eq(typeOf("TAIL_WHIP", true), 6, "so is TAIL_WHIP")
  eq(typeOf("SAND_ATTACK", false), 3, "the foe's SAND-ATTACK is type 3")
  eq(typeOf("POISONPOWDER", true), 6, "POISONPOWDER is type 6")
  eq(typeOf("CONFUSE_RAY", true), 6, "CONFUSE RAY is type 6")
  eq(typeOf("DISABLE", true), 6, "DISABLE is type 6")
end

-- effects whose handler uses PlayCurrentMoveAnimation, which zeroes
-- wAnimationType: no applying animation at all
do
  eq(typeOf("THUNDER_WAVE", true), nil,
     "FreezeBurnParalyzeEffect zeroes the type (effects.asm:196)")
  eq(typeOf("LEECH_SEED", true), nil, "LeechSeedEffect leaves it at 0")
  eq(typeOf("SWORDS_DANCE", true), nil,
     "StatModifierUpEffect leaves it at 0 (effects.asm:485)")
  eq(typeOf("HARDEN", true), nil, "a stat-up move stays animation-free")
end

-- a failed status effect prints AlreadyAsleep / NothingHappened with no
-- animation, so the row is peeled and nothing shakes
do
  local tb = freshBattle()
  tb.enemy.mon.status = "SLP"
  tb.enemy.mon.sleepTurns = 3
  tb:performMove(tb.player, tb.enemy, { id = "HYPNOSIS", pp = 10 }, false)
  eq(#hitRows(tb), 0, "a refused sleep queues no applying animation")
end

-- ------------------------------------------------- what each type looks like
-- one entry per type: the pokered routine's own frame budget and amplitude.
-- 4*b*c for the slow creeps (2-frame delay up and down), 9*b for the fast
-- ones (5 frames out, 4 home, b counting down).  stepProgram spends one
-- extra frame settling the tail, which SE_SHAKE_SCREEN already does.
local SHAPES = {
  { t = 1, axis = "y", peak = 8, frames = 49, wait = 48,
    what = "ShakeScreenVertically, PredefShakeScreenVertically b=8" },
  { t = 2, axis = "x", peak = 8, frames = 73, wait = 72,
    what = "ShakeScreenHorizontallyHeavy, b=8" },
  { t = 3, axis = "x", peak = 6, frames = 49, wait = 48,
    what = "ShakeScreenHorizontallySlow, b=6 c=2" },
  { t = 5, axis = "x", peak = 2, frames = 19, wait = 18,
    what = "ShakeScreenHorizontallyLight, b=2" },
  { t = 6, axis = "x", peak = 3, frames = 25, wait = 24,
    what = "ShakeScreenHorizontallySlow2, b=3 c=2" },
}

-- run the armed program to exhaustion; returns how many frames it held the
-- screen off-centre and the largest offset on each axis
local function runShake(tb)
  local frames, peakX, peakY = 0, 0, 0
  for _ = 1, 400 do
    if not (tb.fx and tb.fx.shakeProg) then break end
    tb:updateFx()
    frames = frames + 1
    peakX = math.max(peakX, math.abs(tb.fx.shakeX or 0))
    peakY = math.max(peakY, math.abs(tb.fx.shakeY or 0))
  end
  return frames, peakX, peakY
end

for _, s in ipairs(SHAPES) do
  local tb = freshBattle()
  tb:applyHitFx({ animType = s.t, sfx = "Damage" })
  check(tb.fx and tb.fx.shakeProg ~= nil,
        ("type %d arms a shake program (%s)"):format(s.t, s.what))
  eq(tb.fx.blink, nil, ("type %d does not blink a pic"):format(s.t))
  eq(tb.waitFrames, s.wait,
     ("type %d holds the queue %d frames"):format(s.t, s.wait))
  local frames, peakX, peakY = runShake(tb)
  eq(frames, s.frames, ("type %d moves the screen for %d frames")
                         :format(s.t, s.frames))
  if s.axis == "x" then
    eq(peakX, s.peak, ("type %d peaks at %dpx sideways"):format(s.t, s.peak))
    eq(peakY, 0, ("type %d never moves vertically"):format(s.t))
  else
    eq(peakY, s.peak, ("type %d peaks at %dpx down"):format(s.t, s.peak))
    eq(peakX, 0, ("type %d never moves sideways"):format(s.t))
  end
end

-- type 4 is the odd one out: the enemy pic blinks and the screen holds still
do
  local tb = freshBattle()
  tb:applyHitFx({ animType = 4, sfx = "Damage", blink = tb.enemy })
  eq(tb.fx.shakeProg, nil, "type 4 arms no shake (#354 must not regress it)")
  check(tb.fx.blink ~= nil and tb.fx.blink.target == tb.enemy,
        "type 4 blinks the enemy pic")
  eq(tb.waitFrames, 20, "for the 20 frames AnimationBlinkEnemyMon takes")
end

-- the OPTIONS animation toggle still gates the whole thing; the sound does not
do
  local tb = freshBattle()
  Game.save.options.animations = false
  tb:applyHitFx({ animType = 5, sfx = "Damage" })
  eq(tb.fx.shakeProg, nil, "animations off arms no shake")
  eq(tb.fx.blink, nil, "and no blink")
  Game.save.options.animations = true
end

-- rows queued without an animType (older save-state queues, mods) still get
-- the pre-#354 behavior off blink.isPlayer
do
  local tb = freshBattle()
  tb:applyHitFx({ blink = tb.enemy })
  check(tb.fx.blink ~= nil, "a bare enemy blink row still blinks")
  local tb2 = freshBattle()
  tb2:applyHitFx({ blink = tb2.player })
  check(tb2.fx.shakeProg ~= nil, "a bare player blink row still shakes")
  local _, _, peakY = runShake(tb2)
  eq(peakY, 8, "vertically, by 8px")
end

S.finish()

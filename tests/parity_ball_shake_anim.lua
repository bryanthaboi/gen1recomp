-- Parity test: the ball-shake pause keeps the resting ball on screen.
--
-- PlaySubanimation draws the frame block and only then runs
-- DoSpecialEffectByAnimationId (engine/battle/animations.asm:623-627), so
-- DoBallShakeSpecialEffects' SFX_TINK + DelayFrames 40 (animations.asm:
-- 739-747) lands with the ball already drawn.  The port paused first and
-- showed 40 blank frames per wobble (#1853).
--
-- Self-contained; run via `luajit tests/parity_ball_shake_anim.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity ball shake anim")
local check, eq = S.check, S.eq

local AnimPlayer = require("src.battle.AnimPlayer")
local Data = require("src.core.Data")
if not Data.battle_anims then Data:load() end
local player = AnimPlayer.new(Data.battle_anims)
player:start("SHAKE_ANIM", true, { shakes = 3 })

local tinks = {}
for _, e in ipairs(player.events) do
  if e.effect == "SFX_TINK" then tinks[#tinks + 1] = e.frame end
end
eq(#tinks, 3, "one SFX_TINK per requested shake")

-- the step a given frame falls in
local function stepAt(frame)
  local at = 0
  for _, st in ipairs(player.steps) do
    if frame >= at and frame < at + st.dur then return st end
    at = at + st.dur
  end
end

for i, frame in ipairs(tinks) do
  local st = stepAt(frame)
  check(st ~= nil, "shake " .. i .. " has a step at its tink frame")
  eq(st.dur, 40, "shake " .. i .. " pauses 40 frames on the tink")
  check(#st.sprites > 0,
    "shake " .. i .. " shows the resting ball through that pause")
end

check(tinks[1] > 0,
  "the first tink is not the very first thing the animation does")

S.finish()

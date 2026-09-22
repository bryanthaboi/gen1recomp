-- Parity test: SE_WAVY_SCREEN is timed in displayed frames.
--
-- AnimationWavyScreen's `ld c, $ff` counts outer passes, and the inner
-- loop only exits when rLY reaches 143, which happens twice per displayed
-- frame (engine/battle/animations.asm:1884-1903).  The port ran it for
-- 255 frames, roughly twice as long as the original (#1848).
--
-- Self-contained; run via `luajit tests/parity_wavy_screen.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity wavy screen")
local check, eq = S.check, S.eq

local AnimPlayer = require("src.battle.AnimPlayer")
local Data = require("src.core.Data")
if not Data.battle_anims then Data:load() end
local player = AnimPlayer.new(Data.battle_anims)
player:start("NIGHT_SHADE", true)

local wavy
for _, e in ipairs(player.events) do
  if e.effect == "SE_WAVY_SCREEN" then wavy = e end
end
check(wavy ~= nil, "NIGHT_SHADE plays SE_WAVY_SCREEN")
eq(wavy.dur, 128, "255 outer passes at two a frame is 128 displayed frames")

local BattleState = require("src.battle.BattleState")
local side = setmetatable({}, { __index = BattleState })
BattleState.applyAnimEffect(side, { effect = "SE_WAVY_SCREEN" })
check(side.fx and side.fx.wavy ~= nil, "the effect arms the wave")
eq(side.fx.wavy.left, wavy.dur,
  "the fx layer and the animation player agree on the length")
eq(side.fx.wavy.phase, 0, "the offset pointer starts at the table head")

S.finish()

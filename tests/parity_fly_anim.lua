-- Parity: the Fly overworld animation (#702).
--
-- Oracle: engine/overworld/player_animations.asm.  Departure
-- (_LeaveMapAnim .flyAnimation) flaps the bird in place for 8 x Delay3,
-- plays SFX_FLY, flies FlyAnimationScreenCoords1 up and off to the right
-- (12 pairs, 3 frames each), waits 40 frames, then exits over the
-- top-left along FlyAnimationScreenCoords2 (11 pairs).  Arrival
-- (EnterMapAnim .flyAnimation) plays SFX_FLY again and swoops in along
-- FlyAnimationEnterScreenCoords (12 pairs), and only then does
-- LoadPlayerSpriteGraphics bring the player back.
--
-- Self-contained: `luajit tests/parity_fly_anim.lua`; also globbed by
-- tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity fly anim (#702)")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()

-- record SFX without touching the audio backend
local plays = {}
local Sound = require("src.core.Sound")
local realPlay = Sound.play
Sound.play = function(_, key) plays[#plays + 1] = key end

local function popAll() while Game.stack:top() do Game.stack:pop() end end
local function frame()
  Input.pressed = {}
  StateStack:update(1 / 60)
end
local function frames(n) for _ = 1, n do frame() end end

Game.stack:push(OW, "ROUTE_17", 4, 10, "down")
local ow = Game.stack:top()

ow:flyTo("PALLET_TOWN")
check(ow.flyAnim ~= nil, "the bird lead-in starts on FLY")
eq(ow.flyAnim and ow.flyAnim.phase, "flap", "the bird flaps in place first")
eq(ow.player.inputLocked, true, "input is locked for the flight")
eq(#plays, 0, "no SFX during the in-place flap")

frames(23)
eq(ow.flyAnim and ow.flyAnim.phase, "flap", "still flapping 23 frames in")
frame()
eq(ow.flyAnim and ow.flyAnim.phase, "path1",
   "the up-right path starts after 8 x Delay3")
eq(plays[#plays], "Fly", "SFX_FLY plays as the bird takes off")

frames(36)
eq(ow.flyAnim and ow.flyAnim.phase, "hold",
   "the bird parks off screen after the 12-pair path")
frames(40)
eq(ow.flyAnim and ow.flyAnim.phase, "path2",
   "the top-left exit follows the 40-frame beat")
frames(33)
check(ow.flyAnim == nil, "the departure ends after the 11-pair exit")

-- the warp transition runs its fade out/in; the map switches inside it
local guard = 0
while ow.map.id == "ROUTE_17" and guard < 400 do
  guard = guard + 1
  frame()
end
eq(ow.map.id, "PALLET_TOWN", "the warp lands in Pallet Town")
check(ow.flyArrive ~= nil, "the landing swoop starts on arrival")
eq(plays[#plays], "Fly", "SFX_FLY plays again for the landing")
eq(ow.player.inputLocked, true, "input stays locked for the swoop")

frames(35)
check(ow.flyArrive ~= nil, "the swoop is still flying 35 frames in")
frame()
check(ow.flyArrive == nil, "the swoop ends after the 12-pair path")
eq(ow.player.inputLocked, false, "and hands input back")

Sound.play = realPlay
S.finish()

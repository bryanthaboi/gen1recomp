-- pokeyellow engine/pikachu/pikachu_movement.asm:153

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check = T.check

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local npc = {
  pikachuFollower = true, cellX = 4, cellY = 6, px = 64, py = 96,
  facing = "up", passable = true,
}
local ow = {
  map = {
    id = "VIRIDIAN_POKECENTER",
    isCounterCell = function(_, _, y) return y == 3 end,
  },
  npcs = { npc }, entities = { npc },
  player = {
    cellX = 4, cellY = 4, facing = "up",
    facingCell = function(self) return self.cellX, self.cellY - 1 end,
  },
}

local done = false
PikachuFollower.hopToCounter(ow, function() done = true end)
check(ow.pikaHop ~= nil, "standing below the player queues the two-leg hop")
check(#ow.pikaHop.legs == 2, "PikaMovementData1 is a slide then a hop")
check(ow.pikaHop.legs[1].hop == nil, "the slide leg is not a jump")
check(ow.pikaHop.legs[2].hop == true, "the second leg is the jump")

local slideShadow, hopShadow, hopGround, liftSeen = false, 0, true, 0
for _ = 1, 32 * 3 do
  PikachuFollower.updateHop(ow)
  local h = ow.pikaHop
  local leg = h and h.legs[h.leg]
  if leg and not leg.hop and npc.hopShadowY then slideShadow = true end
  if leg and leg.hop and npc.hopShadowY then
    hopShadow = hopShadow + 1
    local lift = npc.hopShadowY - npc.py
    if lift > liftSeen then liftSeen = lift end
    if lift <= 0 then hopGround = false end
  end
end

check(not slideShadow, "the slide leg draws no shadow ($2b is func2 $02)")
check(hopShadow > 20, "the airborne leg publishes a shadow y most of the arc",
  "frames " .. hopShadow)
check(hopGround, "the shadow y stays below the lifted sprite y")
check(liftSeen == 8, "the arc peaks at HOP_HEIGHT", "peak " .. liftSeen)

check(ow.pikaHop == nil, "the hop ends")
check(done, "and hands control back")
check(npc.hopShadowY == nil, "the shadow is cleared once the hop lands")
check(npc.cellX == 4 and npc.cellY == 4,
  "and the companion sits on the counter cell in front of the player")

npc.hopShadowY = 99
npc.cellX, npc.cellY, npc.px, npc.py = 4, 6, 64, 96
PikachuFollower.hopToCounter(ow, function() end)
check(npc.hopShadowY == nil, "starting a hop clears any stranded shadow")
ow.pikaHop = nil

GameVersion.set("red")
T.finish("pikachu_counter_shadow_2196")

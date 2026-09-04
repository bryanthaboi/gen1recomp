-- Parity test: Victory Road 3F hole at (23,15) dungeon-warps the player
-- to VICTORY_ROAD_2F (22,16).
--
-- scripts/VictoryRoad3F.asm VictoryRoad3FDefaultScript feeds
-- .SwitchOrHoleCoords into IsPlayerOnDungeonWarp with destination
-- VICTORY_ROAD_2F; data/maps/special_warps.asm DungeonWarpList entry
-- (VICTORY_ROAD_2F, 2) lands at DungeonWarpData (22, 16).  The same cell
-- also drops a boulder (onBoulderMoved), but the player fall was missing
-- -- CAVERN $22 is walkable, so without onStep Red stood on the hole
-- (GitHub #86).
--
-- Self-contained; run via `luajit tests/parity_victory_road_hole.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity victory road hole")
local check, eq = S.check, S.eq

local M = dofile("data/scripts/story.lua")
local vr3 = M.VICTORY_ROAD_3F
check(vr3 ~= nil and vr3.onStep ~= nil, "VICTORY_ROAD_3F has an onStep hole trigger")

local function owRecording()
  local warps = {}
  return {
    player = { facing = "right" },
    -- player_animations.asm:204
    fallThroughHole = function(_, mapId, x, y, facing)
      warps[#warps + 1] = { mapId = mapId, x = x, y = y, facing = facing }
    end,
    startWarpTo = function()
      error("a hole fall must not take the plain door-warp path (#2182)")
    end,
    _warps = warps,
  }, warps
end

-- Stepping onto the hole falls through to 2F at the dungeon-warp landing.
do
  local ow, warps = owRecording()
  local handled = vr3.onStep({}, ow, 23, 15)
  check(handled, "stepping on (23,15) is consumed")
  eq(#warps, 1, "exactly one dungeon warp fires")
  eq(warps[1].mapId, "VICTORY_ROAD_2F", "destination is VICTORY_ROAD_2F")
  eq(warps[1].x, 22, "lands at x=22")
  eq(warps[1].y, 16, "lands at y=16")
  eq(warps[1].facing, "right", "facing is preserved across the fall")
end

-- Any other cell is ignored (switch at 3,5 is boulder-only).
do
  local ow, warps = owRecording()
  eq(vr3.onStep({}, ow, 3, 5), false, "the switch cell does not dungeon-warp")
  eq(vr3.onStep({}, ow, 22, 15), false, "a neighboring floor cell is ignored")
  eq(#warps, 0, "no warp fires off the hole")
end

-- The hole collision tile stays walkable (fall, do not block).
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.VICTORY_ROAD_3F) then Data:load() end
local MapLoader = require("src.world.MapLoader")
local map = MapLoader.load(Data, "VICTORY_ROAD_3F")
check(map:isWalkableCell(23, 15), "CAVERN hole tile at (23,15) is walkable")
eq(map:warpPadOrHoleAt(23, 15), "hole", "collision tile is the CAVERN hole ($22)")
check(map:warpAtCell(23, 15) == nil,
      "the hole is a dungeon warp, not a map warp event")

S.finish()

-- Parity test: the Seafoam Islands floor holes drop the PLAYER a floor,
-- not just the boulders (#599).
--
-- scripts/SeafoamIslands1F.asm / B1F.asm / B2F.asm / B3F.asm each set
-- wDungeonWarpDestinationMap and call IsPlayerOnDungeonWarp with their
-- SeafoamNHolesCoords list; data/maps/special_warps.asm DungeonWarpList /
-- DungeonWarpData turn (destination map, wCoordIndex) into the landing
-- cell.  CAVERN $22 is walkable, so without an onStep the player just
-- stood on the hole.
--
-- Self-contained; run via `luajit tests/parity_seafoam_holes.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity seafoam holes")
local check, eq = S.check, S.eq
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.SEAFOAM_ISLANDS_1F) then Data:load() end

local M = require("data.scripts.seafoam")

local function owRecording()
  local warps = {}
  return {
    player = { facing = "up" },
    startWarpTo = function(_, mapId, x, y, facing)
      warps[#warps + 1] = { mapId = mapId, x = x, y = y, facing = facing }
    end,
  }, warps
end

-- hole cell -> map, landing cell (DungeonWarpData)
local CASES = {
  { "SEAFOAM_ISLANDS_1F", 17, 6, "SEAFOAM_ISLANDS_B1F", 18, 7 },
  { "SEAFOAM_ISLANDS_1F", 24, 6, "SEAFOAM_ISLANDS_B1F", 23, 7 },
  { "SEAFOAM_ISLANDS_B1F", 18, 6, "SEAFOAM_ISLANDS_B2F", 19, 7 },
  { "SEAFOAM_ISLANDS_B1F", 23, 6, "SEAFOAM_ISLANDS_B2F", 22, 7 },
  { "SEAFOAM_ISLANDS_B2F", 19, 6, "SEAFOAM_ISLANDS_B3F", 18, 7 },
  { "SEAFOAM_ISLANDS_B2F", 22, 6, "SEAFOAM_ISLANDS_B3F", 19, 7 },
  { "SEAFOAM_ISLANDS_B3F", 3, 16, "SEAFOAM_ISLANDS_B4F", 4, 14 },
  { "SEAFOAM_ISLANDS_B3F", 6, 16, "SEAFOAM_ISLANDS_B4F", 5, 14 },
}

for _, c in ipairs(CASES) do
  local hooks = M[c[1]]
  check(hooks ~= nil and hooks.onStep ~= nil, c[1] .. " has an onStep hole trigger")
  local ow, warps = owRecording()
  check(hooks.onStep({ data = Data }, ow, c[2], c[3]),
        c[1] .. " consumes the hole step")
  eq(#warps, 1, c[1] .. " fires exactly one fall")
  eq(warps[1].mapId, c[4], c[1] .. " falls to " .. c[4])
  eq(warps[1].x, c[5], c[1] .. " lands at x=" .. c[5])
  eq(warps[1].y, c[6], c[1] .. " lands at y=" .. c[6])
  eq(warps[1].facing, "up", "facing is preserved across the fall")
end

-- a neighboring floor cell is ignored
do
  local ow, warps = owRecording()
  eq(M.SEAFOAM_ISLANDS_1F.onStep({ data = Data }, ow, 18, 6), false,
     "a floor cell is ignored")
  eq(#warps, 0, "no fall fires off the hole")
end

-- the hole tiles stay walkable CAVERN holes, and are not map warp events
local MapLoader = require("src.world.MapLoader")
for _, c in ipairs(CASES) do
  local map = MapLoader.load(Data, c[1])
  check(map:isWalkableCell(c[2], c[3]), c[1] .. " hole tile is walkable")
  eq(map:warpPadOrHoleAt(c[2], c[3]), "hole", c[1] .. " collision tile is CAVERN $22")
  check(map:warpAtCell(c[2], c[3]) == nil, c[1] .. " hole is not a map warp event")
end

S.finish()

-- engine/overworld/player_animations.asm:204
-- door warp.  home/overworld.asm:689-703
-- SFX_GO_INSIDE only on $0B; pokeyellow home/overworld.asm:667-671
-- Self-contained; run via `luajit tests/parity_dungeon_warp_holes.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity dungeon warp holes")
local check, eq = S.check, S.eq

local M = dofile("data/scripts/story6.lua")
local m3 = M.POKEMON_MANSION_3F
check(m3 ~= nil and m3.onStep ~= nil, "POKEMON_MANSION_3F has an onStep hole trigger")

local function owRecording()
  local warps = {}
  return {
    player = { facing = "down" },
    fallThroughHole = function(_, mapId, x, y, facing)
      warps[#warps + 1] = { mapId = mapId, x = x, y = y, facing = facing }
    end,
    startWarpTo = function()
      error("a hole fall must not take the plain door-warp path (#2182)")
    end,
  }, warps
end

local CASES = {
  { 16, 14, "POKEMON_MANSION_1F", 16, 14 },
  { 17, 14, "POKEMON_MANSION_1F", 16, 14 },
  { 19, 14, "POKEMON_MANSION_2F", 18, 14 },
}

for _, c in ipairs(CASES) do
  local ow, warps = owRecording()
  check(m3.onStep({}, ow, c[1], c[2]),
        "stepping on (" .. c[1] .. "," .. c[2] .. ") is consumed")
  eq(#warps, 1, "exactly one dungeon warp fires from " .. c[1] .. "," .. c[2])
  eq(warps[1].mapId, c[3], "falls to " .. c[3])
  eq(warps[1].x, c[4], "lands at x=" .. c[4])
  eq(warps[1].y, c[5], "lands at y=" .. c[5])
  eq(warps[1].facing, "down", "facing is preserved across the fall")
end

do
  local ow, warps = owRecording()
  eq(m3.onStep({}, ow, 18, 14), false, "a neighbouring floor cell is ignored")
  eq(#warps, 0, "no warp fires off the hole")
end

-- engine/overworld/player_animations.asm:43
local Timing = require("src.core.Timing")
eq(Timing.DUNGEON_WARP_ARRIVAL, 50, "the dungeon-warp arrival hold is 50 frames")

-- home/overworld.asm:689-703
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local MapLoader = require("src.world.MapLoader")
local FieldDefaults = require("src.world.FieldDefaults")

local rule = FieldDefaults.field(Data, "mapChangeSound")
check(rule ~= nil, "field.mapChangeSound exists")
eq(rule.doorTile, 0x0B, "the inside cue is gated on tile $0B")
local exempt = {}
for _, ts in ipairs(rule.exemptTilesets or {}) do exempt[ts] = true end
check(exempt.FACILITY and exempt.CEMETERY,
      "pokeyellow exempts FACILITY and CEMETERY")

local function topLeft(mapId, cx, cy)
  local map = MapLoader.load(Data, mapId)
  return map:tileAt(cx * 2, cy * 2)
end

local function findDoorCell(mapId)
  local map = MapLoader.load(Data, mapId)
  for cy = 0, map.heightCells - 1 do
    for cx = 0, map.widthCells - 1 do
      if map:isDoorTileCell(cx, cy) then return cx, cy end
    end
  end
end

do
  local cx, cy = findDoorCell("PALLET_TOWN")
  check(cx ~= nil, "PALLET_TOWN has a door cell")
  if cx then
    eq(topLeft("PALLET_TOWN", cx, cy), 0x0B,
       "an outdoor door cell is $0B-topped (Go_Inside)")
  end
end

local INSIDE_CELLS = {
  { "REDS_HOUSE_1F", "stairs" },
  { "ROCK_TUNNEL_B1F", "cave ladder" },
  { "INDIGO_PLATEAU_LOBBY", "league lobby exit" },
}
for _, c in ipairs(INSIDE_CELLS) do
  local map = MapLoader.load(Data, c[1])
  local hit = false
  for cy = 0, map.heightCells - 1 do
    for cx = 0, map.widthCells - 1 do
      if map:isWarpTileCell(cx, cy) and map:tileAt(cx * 2, cy * 2) == 0x0B then
        hit = true
      end
    end
  end
  check(not hit, c[1] .. " has no $0B-topped warp cell (" .. c[2] .. ")")
end

S.finish()

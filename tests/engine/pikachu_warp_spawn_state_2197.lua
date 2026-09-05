-- pokeyellow home/overworld.asm:476,503,507
-- engine/pikachu/pikachu_follow.asm:59,148

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check = T.check

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local state = PikachuFollower.warpSpawnState

-- engine/pikachu/pikachu_follow.asm:185
local outside = {
  { "ROUTE_16", "ROUTE_16_GATE_1F", "right", 4 },
  { "ROUTE_11", "ROUTE_11_GATE_1F", "up", 4 },
  { "ROUTE_23", "VICTORY_ROAD_2F", "up", 4 },
  { "ROUTE_25", "BILLS_HOUSE", "up", 1 },
  { "PALLET_TOWN", "REDS_HOUSE_1F", "up", 1 },
  { "PALLET_TOWN", "OAKS_LAB", "up", 6 },
  { "ROUTE_22", "ROUTE_22_GATE", "down", 3 },
  { "ROUTE_22", "ROUTE_22_GATE", "left", 1 },
  { "ROUTE_4", "MT_MOON_B1F", "up", 3 },
  { "ROUTE_10", "ROCK_TUNNEL_1F", "up", 3 },
  { "CERULEAN_CITY", "CERULEAN_BADGE_HOUSE", "down", 3 },
  { "CERULEAN_CITY", "CERULEAN_BADGE_HOUSE", "up", 1 },
  { "VERMILION_CITY", "VERMILION_DOCK", "left", 1 },
}
for _, case in ipairs(outside) do
  local got = state(true, case[1], case[2], false, case[3])
  check(got == case[4], "outside " .. case[1] .. " -> " .. case[2] .. " facing "
    .. case[3] .. " is spawn state " .. case[4] .. " (got " .. tostring(got) .. ")")
end

-- engine/pikachu/pikachu_follow.asm:257
local indoor = {
  { "REDS_HOUSE_1F", "REDS_HOUSE_2F", "up", 0 },
  { "CELADON_MART_1F", "CELADON_MART_ELEVATOR", "up", 1 },
  { "VIRIDIAN_FOREST_NORTH_GATE", "VIRIDIAN_FOREST", "down", 1 },
  { "VIRIDIAN_FOREST", "VIRIDIAN_FOREST_NORTH_GATE", "up", 1 },
  { "VIRIDIAN_FOREST", "VIRIDIAN_FOREST_NORTH_GATE", "down", 0 },
  { "VIRIDIAN_FOREST", "VIRIDIAN_FOREST_SOUTH_GATE", "down", 0 },
  { "VIRIDIAN_FOREST", "VIRIDIAN_FOREST_SOUTH_GATE", "up", 1 },
}
for _, case in ipairs(indoor) do
  local got = state(false, case[1], case[2], false, case[3])
  check(got == case[4], "indoor " .. case[1] .. " -> " .. case[2] .. " facing "
    .. case[3] .. " is spawn state " .. case[4] .. " (got " .. tostring(got) .. ")")
end

-- engine/pikachu/pikachu_follow.asm:305
check(state(false, "REDS_HOUSE_1F", "PALLET_TOWN", true, "down") == 3,
  "an exit mat back outside is spawn state 3")
check(state(false, "ROUTE_2_GATE", "ROUTE_2", true, "up") == 1,
  "the Route 2 Gate back door walked through facing up is state 1")
check(state(false, "ROUTE_2_GATE", "ROUTE_2", true, "down") == 3,
  "and any other facing out of it is state 3")
check(state(false, "ROUTE_22_GATE", "ROUTE_22", true, "up") == 1,
  "the Route 22 Gate back door facing up is state 1 too")

local walls = {}
local function makeOw(facing)
  return {
    map = {
      id = "TEST_MAP",
      inBounds = function(_, x, y) return x >= 0 and y >= 0 end,
      isWalkableCell = function(_, x, y) return not walls[x .. "," .. y] end,
    },
    npcs = {}, entities = {},
    player = { cellX = 5, cellY = 5, facing = facing or "right" },
  }
end

local game = {
  save = {
    flags = { EVENT_GOT_STARTER = true,
              EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true },
    party = { { species = "PIKACHU", hp = 12 } },
  },
  data = { sprites = { SPRITE_PIKACHU = {} } },
}
local NPC = require("src.world.NPC")
local realNew = NPC.new
NPC.new = function(_, mapId, def)
  return { mapId = mapId, cellX = def.x, cellY = def.y, def = def,
           px = def.x * 16, py = def.y * 16 }
end

local function spawn(facing, spawnState)
  local ow = makeOw(facing)
  PikachuFollower.onMapEntered(game, ow, { pikachuSpawn = spawnState }, true)
  return ow.npcs[1], ow
end

local placements = {
  { 0, "right", 5, 5, "right" },
  { 1, "up", 6, 5, "up" },
  { 2, "right", 4, 5, "right" },
  { 3, "right", 5, 5, "down" },
  { 4, "right", 5, 6, "right" },
  { 5, "up", 5, 4, "up" },
  { 6, "up", 4, 5, "up" },
  { 7, "up", 5, 4, "down" },
}
for _, case in ipairs(placements) do
  local npc = spawn(case[2], case[1])
  check(npc and npc.cellX == case[3] and npc.cellY == case[4]
        and npc.facing == case[5],
    "spawn state " .. case[1] .. " facing " .. case[2] .. " places at ("
    .. case[3] .. "," .. case[4] .. ") facing " .. case[5]
    .. " (got " .. tostring(npc and npc.cellX) .. ","
    .. tostring(npc and npc.cellY) .. " " .. tostring(npc and npc.facing) .. ")")
end

walls["6,5"] = true
local npc = spawn("up", 1)
check(npc.cellX == 5 and npc.cellY == 5,
  "a walled state-1 cell falls back to the player's own cell")
walls = {}

local bootOw = makeOw("up")
PikachuFollower.onMapEntered(game, bootOw, { via = "boot" }, true)
check(bootOw.npcs[1].cellX == 5 and bootOw.npcs[1].cellY == 5,
  "a stateless map load still spawns on the player's cell")

local midOw = makeOw("up")
PikachuFollower.onMapEntered(game, midOw, nil, false)
check(midOw.npcs[1].cellX == 5 and midOw.npcs[1].cellY == 6,
  "a mid-map respawn stays behind the player's facing")

NPC.new = realNew
GameVersion.set("red")
T.finish("pikachu_warp_spawn_state_2197")

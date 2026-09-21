#!/usr/bin/env luajit
-- src/event_object_movement.c:4835, src/fieldmap.c:357, src/field_control_avatar.c:987

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local NativePack = require("src.import.gba.native_pack")
local Permissions = require("src.world.gen2.Permissions")
local ScriptColl = require("src.core.game3.scripting.collision")

local BLOCKED = ScriptColl.seed("BLOCKED")
local CAVE = ScriptColl.seed("CAVE")

print("[test] 1. the layout collision bit wins over the metatile classify")
-- src/event_object_movement.c:4835
local RULE = {
  { CAVE, 0, nil, CAVE, "a cave floor with collision 0 keeps COLL_CAVE" },
  { CAVE, 1, nil, BLOCKED, "a cave wall with collision 1 is blocked" },
  { CAVE, 2, nil, BLOCKED, "collision 2 blocks as well" },
  { ScriptColl.seed("TALL_GRASS"), 1, nil, BLOCKED, "grass with collision 1 is blocked" },
  { ScriptColl.seed("TOWN_PATH"), 1, nil, BLOCKED, "path with collision 1 is blocked" },
  { ScriptColl.seed("ROCK_DECK"), 1, nil, BLOCKED, "a mountain top with collision 1 is blocked" },
  { BLOCKED, 1, nil, BLOCKED, "an already blocked cell stays blocked" },
  { ScriptColl.seed("SIGN"), 1, nil, ScriptColl.seed("SIGN"), "a sign keeps COLL_SIGN" },
  { ScriptColl.seed("PC"), 1, nil, ScriptColl.seed("PC"), "a PC keeps COLL_PC" },
  { ScriptColl.seed("COUNTER"), 1, nil, ScriptColl.seed("COUNTER"), "a counter keeps its byte" },
  { ScriptColl.seed("WATER"), 1, nil, ScriptColl.seed("WATER"), "water keeps COLL_WATER" },
  { ScriptColl.seed("LEDGE", "S"), 1, nil, ScriptColl.seed("LEDGE", "S"),
    "a ledge keeps its hop byte, the jump is checked after the collision" },
  -- src/field_control_avatar.c:987
  { ScriptColl.seed("DOOR"), 1, true, ScriptColl.seed("DOOR"),
    "a door with a warp event stays enterable" },
  { ScriptColl.seed("DOOR"), 1, nil, BLOCKED, "a door with no warp event is a wall" },
  { ScriptColl.seed("DOOR", nil, "indoor"), 1, true, ScriptColl.seed("DOOR", nil, "indoor"),
    "an indoor door mat with a warp event keeps its byte" },
  { ScriptColl.seed("DOOR", nil, "indoor"), 1, nil, BLOCKED,
    "an indoor door mat with no warp event is a wall" },
  { CAVE, 1, true, BLOCKED, "a warp event does not open a non-warp metatile" },
}
for _, row in ipairs(RULE) do
  eq(NativePack.resolveLayoutColl(row[1], row[2], row[3]), row[4], row[5])
end
eq(NativePack.warpKey(7, 2), 2 * NativePack.WARP_KEY_STRIDE + 7, "warpKey packs y then x")
check(NativePack.WARP_KEY_STRIDE > 1024,
  "the warp key stride clears the widest FRLG layout")

print("[test] 2. writeExtract applies the rule to the cells it bakes")
local writes = {}
local fakeCache = {
  write = function(_, rel, blob) writes[rel] = blob end,
  read = function() return nil end,
}
local BEH_CAVE = 0x08
local grid = {
  width = 2, height = 2, kind = "indoor", pair = "p", map_id = "M",
  cells = {
    { mid = 860, coll = 1, elev = 0 }, { mid = 641, coll = 0, elev = 3 },
    { mid = 641, coll = 0, elev = 3 }, { mid = 641, coll = 1, elev = 3 },
  },
}
NativePack.writeExtract(fakeCache, "root", { p = {} }, { M = grid },
  { M = { width = 1, height = 1, mids = { 0 } } }, {}, nil,
  function() return BEH_CAVE end, ScriptColl.fromCell, nil,
  { M = { [NativePack.warpKey(1, 0)] = true } })
local baked = NativePack.decodeMidLayout(writes["root/native/layouts/M.mid"])
check(baked ~= nil, "writeExtract baked the layout")
if baked then
  eq(baked.cells[1].coll, BLOCKED, "the collision 1 cave cell baked as blocked")
  eq(baked.cells[2].coll, CAVE, "the collision 0 cave cell kept COLL_CAVE")
  eq(baked.cells[3].coll, CAVE, "the second floor cell kept COLL_CAVE")
  eq(baked.cells[4].coll, BLOCKED, "the collision 1 floor cell baked as blocked")
end

print("[test] 3. the baked Mt Ember braille wall")
local Cache = require("tests.game3_cache")
local root = Cache.root("native/manifest.lua", { native = true })
if not root then
  print("[skip] the baked layout checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function layoutOf(mapId)
  local blob = slurp(root .. "/native/layouts/" .. mapId .. ".mid")
  return blob and NativePack.decodeMidLayout(blob)
end

local function collAt(dec, x, y)
  local c = dec.cells[y * dec.width + x + 1]
  return c and c.coll
end

local B5F = "FR_MT_EMBER_RUBY_PATH_B5F"
local ember = layoutOf(B5F)
check(ember ~= nil, B5F .. " is baked")
if ember then
  eq(collAt(ember, 7, 2), BLOCKED, "the braille wall at (7,2) is impassable")
  check(not Permissions.isWalkable(collAt(ember, 7, 2)),
    "Permissions agrees the braille wall is not land")
  local row = 0
  for x = 0, (ember.trueWidth or ember.width) - 1 do
    for y = 0, 2 do
      if Permissions.isWalkable(collAt(ember, x, y)) then row = row + 1 end
    end
  end
  eq(row, 0, "no cell in rows y=0..2 is walkable, map.bin gives them all collision 1")
  eq(collAt(ember, 7, 3), CAVE, "the cave floor the player stands on is untouched")
  eq(collAt(ember, 5, 3), CAVE, "the floor beside it is untouched too")
  check(Permissions.isWalkable(collAt(ember, 7, 3)),
    "the player can still stand in front of the braille wall")
end

print("[test] 4. every baked coll plane agrees with map.bin's collision bit")
local PRET = "../pokefirered"
local layoutsJson = slurp(PRET .. "/data/layouts/layouts.json")
if not layoutsJson then
  print("[skip] the pret sweep: " .. PRET .. "/data/layouts/layouts.json is not present")
  finish()
end

local warps = {}
do
  local src = slurp(root .. "/warps.lua")
  local chunk = src and (loadstring or load)(src)
  local ok, t = pcall(chunk or function() end)
  if ok and type(t) == "table" then warps = t end
end
check(next(warps) ~= nil, "warps.lua loaded, the door exception needs it")

local MapCatalog = require("src.import.gba.map_catalog")
MapCatalog.rebuildIndex()

local SAMPLE = {
  "DiglettsCave_B1F", "NavelRock_Fork", "PowerPlant", "VictoryRoad_1F",
  "FourIsland_IcefallCave_Entrance", "SixIsland_AlteringCave",
  "MtEmber_RubyPath_B3F", "OneIsland_KindleRoad_EmberSpa",
  "MtEmber_RubyPath_1F", "FourIsland_IcefallCave_Back",
  "MtEmber_RubyPath_B5F", "CeladonCity", "PalletTown", "ViridianForest",
  "CeladonCity_DepartmentStore_1F", "UndergroundPath_NorthSouthTunnel",
}

local function layoutBlock(layoutId)
  local body
  for chunk in layoutsJson:gmatch("{(.-)}") do
    if chunk:find('"id"%s*:%s*"' .. layoutId .. '"') then body = chunk end
  end
  return body
end

local function pretGrid(mapName)
  local mapJson = slurp(PRET .. "/data/maps/" .. mapName .. "/map.json")
  if not mapJson then return nil end
  local layoutId = mapJson:match('"layout"%s*:%s*"([%w_]+)"')
  local body = layoutId and layoutBlock(layoutId)
  if not body then return nil end
  local w = tonumber(body:match('"width"%s*:%s*(%d+)'))
  local h = tonumber(body:match('"height"%s*:%s*(%d+)'))
  local blocks = slurp(PRET .. "/" .. (body:match('"blockdata_filepath"%s*:%s*"([^"]+)"') or ""))
  if not (w and h and blocks and #blocks >= w * h * 2) then return nil end
  return w, h, blocks
end

local checkedMaps, checkedCells, openCells = 0, 0, 0
for _, mapName in ipairs(SAMPLE) do
  local mapId = MapCatalog.resolve(mapName)
  local dec = mapId and layoutOf(mapId)
  local w, h, blocks = pretGrid(mapName)
  if dec and w then
    checkedMaps = checkedMaps + 1
    local mapWarps = {}
    for _, warp in ipairs(warps[mapId] or {}) do
      mapWarps[warp.y * NativePack.WARP_KEY_STRIDE + warp.x] = true
    end
    local bad = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = (y * w + x) * 2
        local word = blocks:byte(i + 1) + blocks:byte(i + 2) * 256
        local mapColl = math.floor(word / 1024) % 4
        local coll = collAt(dec, x, y)
        if mapColl ~= 0 and coll then
          checkedCells = checkedCells + 1
          local doorWarp = mapWarps[y * NativePack.WARP_KEY_STRIDE + x]
            and coll >= 0x60 and coll <= 0x7F
          if doorWarp then
            openCells = openCells + 1
          elseif Permissions.isWalkable(coll) and not Permissions.isLedge(coll) then
            bad = bad + 1
          end
        end
      end
    end
    eq(bad, 0, mapName .. " has no walkable cell where map.bin says collision 1")
  else
    check(false, mapName .. " resolved to a baked layout and a pret map.bin")
  end
end
eq(checkedMaps, #SAMPLE, "every sampled map was checked")
check(checkedCells > 15000,
  "the sweep read a real number of collision 1 cells (" .. checkedCells .. ")")
check(openCells > 0,
  "the door exception kept " .. openCells .. " warp cells enterable")

finish()

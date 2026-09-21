#!/usr/bin/env luajit

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

local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")
local Versions = require("src.import.gba.versions")

-- include/constants/battle.h:287
local PRET_KEYS = {
  [0] = "grass", "long_grass", "sand", "underwater", "water", "pond", "mountain",
  "cave", "building", "plain", "link", "gym", "leader", "indoor_2", "indoor_1",
  "lorelei", "bruno", "agatha", "lance", "champion",
}

print("[test] 1. every sBattleTerrainTable id has a sheet key")
local keys = BattleChromeExtract.TERRAIN_KEYS or {}
local count = 0
for _ in pairs(keys) do count = count + 1 end
check(count == 20, "20 terrain ids are named (" .. count .. ")")
for id = 0, 19 do
  check(keys[id] == PRET_KEYS[id],
    string.format("terrain %d is %s (%s)", id, tostring(PRET_KEYS[id]), tostring(keys[id])))
end

print("[test] 2. the terrain table is read out of the ROM")
check(type(BattleChromeExtract.terrainTable) == "function"
  and tonumber(BattleChromeExtract.TERRAIN_ENTRY_SIZE) ~= nil
  and tonumber(BattleChromeExtract.TERRAIN_TABLE) ~= nil,
  "battle_chrome_extract reads sBattleTerrainTable")
if type(BattleChromeExtract.terrainTable) ~= "function"
  or not BattleChromeExtract.TERRAIN_ENTRY_SIZE then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
local grass = Versions.BATTLE_UI.terrain_grass
local base = BattleChromeExtract.TERRAIN_TABLE
local bytes = {}
local function poke32(off, value)
  for i = 0, 3 do
    bytes[off + i] = math.floor(value / 256 ^ i) % 256
  end
end
local function entry(id, tiles, tilemap, pal)
  local off = base + id * BattleChromeExtract.TERRAIN_ENTRY_SIZE
  poke32(off, tiles + 0x08000000)
  poke32(off + 4, tilemap + 0x08000000)
  poke32(off + 8, 0x08000000)
  poke32(off + 12, 0x08000000)
  poke32(off + 16, pal + 0x08000000)
end
entry(0, grass.tiles, grass.tilemap, grass.pal)
for id = 1, 19 do
  entry(id, 0x100000 + id * 0x1000, 0x200000 + id * 0x1000, 0x300000 + id * 0x100)
end
local function get(off) return bytes[off] or 0 end

local table_ = BattleChromeExtract.terrainTable(get)
check(type(table_) == "table" and #table_ == 20, "20 entries parsed (" ..
  tostring(type(table_) == "table" and #table_ or table_) .. ")")
if type(table_) == "table" and #table_ == 20 then
  check(table_[1].key == "grass" and table_[1].cfg.tiles == grass.tiles,
    "entry 0 is the pinned grass set")
  check(table_[8].key == "cave" and table_[8].cfg.tiles == 0x100000 + 7 * 0x1000,
    "entry 7 is cave (" .. tostring(table_[8].key) .. ")")
  check(table_[5].key == "water" and table_[5].cfg.pal == 0x300000 + 4 * 0x100,
    "entry 4 is water (" .. tostring(table_[5].key) .. ")")
  check(table_[20].key == "champion", "entry 19 is champion (" .. tostring(table_[20].key) .. ")")
end

print("[test] 3. a table that does not match the pinned grass set is refused")
entry(0, grass.tiles + 4, grass.tilemap, grass.pal)
check(BattleChromeExtract.terrainTable(get) == nil, "a shifted entry 0 falls back")
entry(0, grass.tiles, grass.tilemap, grass.pal)
poke32(base + 4 * BattleChromeExtract.TERRAIN_ENTRY_SIZE, 0)
check(BattleChromeExtract.terrainTable(get) == nil, "a null tilemap pointer falls back")
local okRequire, requireErr = pcall(BattleChromeExtract.requireTerrainTable, get)
check(okRequire == false and tostring(requireErr):find("sBattleTerrainTable") ~= nil,
  "the bake refuses a table it cannot decode instead of writing a partial terrain set")
entry(4, 0x100000 + 4 * 0x1000, 0x200000 + 4 * 0x1000, 0x300000 + 4 * 0x100)
local okAll, allTerrains = pcall(BattleChromeExtract.requireTerrainTable, get)
check(okAll and type(allTerrains) == "table" and #allTerrains == 20,
  "a decodable table bakes all 20 sets")

print("[test] 4. baked terrain sheets in an imported cache")
local Cache = require("tests.game3_cache")
local root = Cache.root("pokemon/battle/manifest.lua")
if not root then
  print("[skip] baked terrains: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/pokemon/battle/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local manifestSrc = readFile("manifest.lua")
local manifest = manifestSrc and loadstring(manifestSrc)
manifest = manifest and manifest()
if type(manifest) ~= "table" or (tonumber(manifest.format) or 0) < 6 then
  print("[skip] baked terrains: cache manifest is format " ..
    tostring(manifest and manifest.format) .. ", the terrain bake needs 6")
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local baked = manifest.terrains or {}
for id = 0, 19 do
  local key = PRET_KEYS[id]
  local info = baked[key]
  check(type(info) == "table" and info.w == 256 and info.h == 256,
    "manifest lists terrain " .. key)
  local sheet = readFile("terrain_" .. key .. ".rgba")
  check(sheet ~= nil and #sheet == 256 * 256 * 4,
    string.format("terrain_%s.rgba is %s bytes", key, tostring(sheet and #sheet)))
  for _, layer in ipairs({ "bg", "enemy", "player" }) do
    local split = readFile("terrain_" .. layer .. "_" .. key .. ".rgba")
    check(split ~= nil and #split == 256 * 160 * 4,
      string.format("terrain_%s_%s.rgba is %s bytes", layer, key, tostring(split and #split)))
  end
end

local cave = readFile("terrain_cave.rgba")
local water = readFile("terrain_water.rgba")
local building = readFile("terrain_building.rgba")
check(cave ~= building, "the cave sheet is not the building sheet")
check(water ~= building and water ~= cave, "the water sheet is its own art")
local opaque = 0
for i = 4, #cave, 4 do
  if cave:byte(i) == 255 then opaque = opaque + 1 end
end
check(opaque > 256 * 100, "the cave sheet is opaque battle art (" .. opaque .. " pixels)")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

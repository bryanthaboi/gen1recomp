#!/usr/bin/env luajit
-- pokefirered/src/scrcmd.c:711

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

local okAlt, AltLayouts = pcall(require, "src.import.gba.alt_layouts")
if not okAlt then
  AltLayouts = {
    ROWS = {},
    KEY_PREFIX = "alt_",
    key = function(id) return "alt_" .. tostring(id) end,
  }
end
local Versions = require("src.import.gba.versions")
local MapCatalog = require("src.import.gba.map_catalog")
local NativePack = require("src.import.gba.native_pack")
MapCatalog.rebuildIndex()

-- pokefirered/include/constants/layouts.h:253,267,268,308
local EXPECT = {
  [264] = {
    map = "SevenIsland_House_Room1", w = 11, h = 9,
    diffCells = 17,
    -- pokefirered/include/constants/metatile_behaviors.h:72
    behavior = 0x60, baseCount = 0, altCount = 1,
  },
  [278] = {
    map = "SeafoamIslands_B3F", w = 38, h = 24,
    diffCells = 92,
    -- pokefirered/include/constants/metatile_behaviors.h:62-65
    behavior = "current", baseCount = 56, altCount = 22,
  },
  [279] = {
    map = "SeafoamIslands_B4F", w = 38, h = 24,
    diffCells = 176,
    behavior = "current", baseCount = 173, altCount = 15,
  },
  [319] = {
    map = "ThreeIsland_DunsparceTunnel", w = 30, h = 7,
    diffCells = 152,
    -- pokefirered/include/constants/metatile_behaviors.h:8
    behavior = 0x08, baseCount = 164, altCount = 86,
  },
}

local ORDER = { 264, 278, 279, 319 }

print("[test] 1. the alt-layout contract")

check(okAlt, "src/import/gba/alt_layouts.lua is loadable")
eq(#AltLayouts.ROWS, 4, "four gMapLayouts entries are seeded")
for _, row in ipairs(AltLayouts.ROWS) do
  local want = EXPECT[row.id]
  check(want ~= nil, "layout " .. tostring(row.id) .. " is one of the four pret ids")
  if want then
    eq(row.map, want.map, "layout " .. row.id .. " owner map")
    eq(row.width .. "x" .. row.height, want.w .. "x" .. want.h,
      "layout " .. row.id .. " pret dimensions")
  end
end
eq(AltLayouts.key(278), "alt_278", "cache key is alt_<layoutId>")
check(Versions.G_MAP_LAYOUTS ~= nil, "Versions.G_MAP_LAYOUTS is pinned")

print("[test] 2. CacheContract rejects a cache without them")
local Contract = require("src.import.CacheContract")
local required = {}
for _, path in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.firered or {}) do
  required[path] = true
end
for _, id in ipairs(ORDER) do
  check(required["data/generated/gba/native/layouts/" .. AltLayouts.key(id) .. ".mid"],
    "firered required list carries " .. AltLayouts.key(id) .. ".mid")
end

print("[test] 3. AltLayouts.build over the real ROM")
local ROM = "../pokefirered/pokefirered.gba"
local romFile = okAlt and io.open(ROM, "rb")
if not okAlt then
  check(false, "AltLayouts.build reads gMapLayouts")
elseif not romFile then
  print("[skip] " .. ROM .. " not present; ROM section skipped")
else
  romFile:close()
  local FileIO = require("src.import.gba.file_io")
  local imports = FileIO.makeImports(
    ROM, "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "firered")
  local rom = assert(require("src.import.gba.rom").open(imports, "firered"))
  local version = assert(Versions.lookup(rom.md5))
  local MapTree = require("src.import.gba.map_tree")
  local Maps = require("src.import.gba.maps")
  local Extract = require("src.import.gba.extract_island1")

  local census = assert(MapTree.walk(rom, version))
  local order, byEngine = MapCatalog.allOrder(census)
  MapCatalog.registerOrder(rom, version, order, byEngine)

  local grids, borders = {}, {}
  for _, id in ipairs(ORDER) do
    local ownerId = MapCatalog.resolve(EXPECT[id].map)
    local spec = Versions.MAPS[ownerId]
    local layoutSpec = spec and version.layouts and version.layouts[spec.layout]
    if layoutSpec then
      local grid = Maps.loadGrid(rom, layoutSpec)
      grid.map_id = ownerId
      grid.kind = spec.kind
      grid.pair = spec.pair
      grid.environment = spec.environment
      grids[ownerId] = Extract.padEven(grid)
    end
  end

  local added = AltLayouts.build(rom, version, grids, borders, Extract.padEven)
  eq(#added, 4, "build seeded four alt layouts")

  for _, id in ipairs(ORDER) do
    local want = EXPECT[id]
    local key = AltLayouts.key(id)
    local alt = grids[key]
    local ownerId = MapCatalog.resolve(want.map)
    local owner = grids[ownerId]
    if not (alt and owner) then
      check(false, key .. " built")
    else
      eq(alt.pair, owner.pair, key .. " renders in " .. tostring(ownerId) .. "'s pair")
      eq(alt.width .. "x" .. alt.height, owner.width .. "x" .. owner.height,
        key .. " matches the owner's padded size")
      eq(alt.altOwner, ownerId, key .. " records its owner")
      local tw = (alt.padded_from and alt.padded_from.width) or alt.width
      local th = (alt.padded_from and alt.padded_from.height) or alt.height
      eq(tw .. "x" .. th, want.w .. "x" .. want.h, key .. " true size is pret's")
      local diff = 0
      for y = 0, th - 1 do
        for x = 0, tw - 1 do
          local i = y * alt.width + x + 1
          local a, b = alt.cells[i], owner.cells[i]
          if a.mid ~= b.mid or a.coll ~= b.coll or a.elev ~= b.elev then
            diff = diff + 1
          end
        end
      end
      eq(diff, want.diffCells, key .. " differs from the base layout in cells")
      check(borders[key] ~= nil and #(borders[key].mids or {}) > 0,
        key .. " carries its own border block")
    end
  end
  imports:_close()
end

print("[test] 4. the baked cache")
local Cache = require("tests.game3_cache")
local root = Cache.root("native/manifest.lua")
if not root then
  print("[skip] " .. tostring(Cache.reason))
else
  local function readFile(rel)
    local f = io.open(root .. "/" .. rel, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  local function loadLua(rel)
    local src = readFile(rel)
    if not src then return nil end
    local chunk = load(src, "@" .. rel, "t", {})
    return chunk and chunk() or nil
  end

  if not readFile("native/layouts/" .. AltLayouts.key(ORDER[1]) .. ".mid") then
    print("[skip] cache at " .. root ..
      " predates alt-layout baking; reimport it before this test can check it")
  else
    local manifest = loadLua("native/manifest.lua") or {}
    local midIndex = loadLua("mid_index.lua") or {}
    local strays = {}
    for mapId in pairs(manifest.layouts or {}) do
      if mapId:sub(1, #AltLayouts.KEY_PREFIX) == AltLayouts.KEY_PREFIX then
        strays[#strays + 1] = mapId
      end
    end
    eq(#strays, 0, "alt layouts stay out of manifest.layouts")

    local function behaviorOf(pair, mid)
      local row = midIndex[pair] and midIndex[pair][mid]
      return row and row.behavior
    end
    local function countBehavior(decoded, pair, want)
      local tw = decoded.trueWidth or decoded.width
      local th = decoded.trueHeight or decoded.height
      local n = 0
      for y = 0, th - 1 do
        for x = 0, tw - 1 do
          local b = behaviorOf(pair, decoded.cells[y * decoded.width + x + 1].mid)
          if b and ((want == "current" and b >= 0x50 and b <= 0x53) or b == want) then
            n = n + 1
          end
        end
      end
      return n
    end

    local pairAtlas = {}
    local function atlasMids(pair)
      if pairAtlas[pair] == nil then
        local blob = readFile("native/" .. pair .. "/mids.idx")
        local idx = blob and NativePack.decodeIdx(blob)
        local set = {}
        for _, mid in ipairs(idx and idx.midIds or {}) do set[mid] = true end
        pairAtlas[pair] = set
      end
      return pairAtlas[pair]
    end

    for _, id in ipairs(ORDER) do
      local want = EXPECT[id]
      local key = AltLayouts.key(id)
      local ownerId = MapCatalog.resolve(want.map)
      local info = (manifest.layouts or {})[ownerId]
      local altBlob = readFile("native/layouts/" .. key .. ".mid")
      local baseBlob = readFile("native/layouts/" .. ownerId .. ".mid")
      local alt = altBlob and NativePack.decodeMidLayout(altBlob)
      local base = baseBlob and NativePack.decodeMidLayout(baseBlob)
      if not (alt and base and info) then
        check(false, key .. " and " .. tostring(ownerId) .. " are both baked")
      else
        eq(alt.width .. "x" .. alt.height, info.width .. "x" .. info.height,
          key .. " passes the size gate in ops_a set_map_layout")
        eq((alt.trueWidth or 0) .. "x" .. (alt.trueHeight or 0), want.w .. "x" .. want.h,
          key .. " keeps pret's true size")

        local missing = 0
        local atlas = atlasMids(info.pair)
        for _, cell in ipairs(alt.cells) do
          if not atlas[cell.mid] then missing = missing + 1 end
        end
        eq(missing, 0, key .. " mids are all in the " .. info.pair .. " atlas")

        local swapped = 0
        for i = 1, alt.width * alt.height do
          local a, b = alt.cells[i], base.cells[i]
          if a.mid ~= b.mid or a.coll ~= b.coll or a.elev ~= b.elev then
            swapped = swapped + 1
          end
        end
        check(swapped > 0, key .. " swaps " .. swapped .. " cells into " .. ownerId)

        eq(countBehavior(base, info.pair, want.behavior), want.baseCount,
          ownerId .. " base behavior cells")
        eq(countBehavior(alt, info.pair, want.behavior), want.altCount,
          key .. " behavior cells")
      end
    end
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

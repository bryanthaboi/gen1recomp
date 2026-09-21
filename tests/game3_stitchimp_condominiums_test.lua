#!/usr/bin/env luajit
-- pokefirered/include/global.fieldmap.h:80

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

local Versions = require("src.import.gba.versions")
local MapCatalog = require("src.import.gba.map_catalog")
local NativePack = require("src.import.gba.native_pack")

local ONE_F = "FR_CELADON_CITY_CONDOMINIUMS_1F"
local TWO_F = "FR_CELADON_CITY_CONDOMINIUMS_2F"
local THREE_F = "FR_CELADON_CITY_CONDOMINIUMS_3F"
local ROOF = "FR_CELADON_CITY_CONDOMINIUMS_ROOF"
local HIDEOUT = "FR_ROCKET_HIDEOUT_B2F"
local FLOORS = { ONE_F, TWO_F, THREE_F, ROOF }

local PRET = "../pokefirered"
local LAYOUT_ID = {
  [ONE_F] = "LAYOUT_CELADON_CITY_CONDOMINIUMS_1F",
  [TWO_F] = "LAYOUT_CELADON_CITY_CONDOMINIUMS_2F",
  [THREE_F] = "LAYOUT_CELADON_CITY_CONDOMINIUMS_3F",
  [ROOF] = "LAYOUT_CELADON_CITY_CONDOMINIUMS_ROOF",
}

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function attributesOf(symbol)
  local snake = symbol:gsub("^gTileset_", ""):gsub("(%l)(%u)", "%1_%2")
    :gsub("(%a)(%d)", "%1_%2"):lower()
  for _, kind in ipairs({ "primary", "secondary" }) do
    local blob = slurp(PRET .. "/data/tilesets/" .. kind .. "/" .. snake
      .. "/metatile_attributes.bin")
    if blob then return blob end
  end
  return nil
end

-- pokefirered/include/fieldmap.h:8
local NUM_PRIMARY_METATILES = 640
local function pretExpect()
  local json = slurp(PRET .. "/data/layouts/layouts.json")
  if not json then return nil end
  local out = {}
  for mapId, layoutId in pairs(LAYOUT_ID) do
    local obj
    for body in json:gmatch("{(.-)}") do
      if body:find('"id"%s*:%s*"' .. layoutId .. '"', 1, false) then obj = body end
    end
    if not obj then return nil end
    local w = tonumber(obj:match('"width"%s*:%s*(%d+)'))
    local h = tonumber(obj:match('"height"%s*:%s*(%d+)'))
    local primary = attributesOf(obj:match('"primary_tileset"%s*:%s*"([%w_]+)"') or "")
    local secondary = attributesOf(obj:match('"secondary_tileset"%s*:%s*"([%w_]+)"') or "")
    local blocks = slurp(PRET .. "/" .. (obj:match('"blockdata_filepath"%s*:%s*"([^"]+)"') or ""))
    if not (w and h and primary and secondary and blocks) then return nil end
    local behavior = {}
    for i = 0, w * h - 1 do
      local cell = blocks:byte(2 * i + 1) + blocks:byte(2 * i + 2) * 256
      local mid = cell % 1024
      local attrs, index = primary, mid
      if mid >= NUM_PRIMARY_METATILES then
        attrs, index = secondary, mid - NUM_PRIMARY_METATILES
      end
      local b = attrs:byte(4 * index + 1)
      behavior[b] = (behavior[b] or 0) + 1
    end
    out[mapId] = { w = w, h = h, behavior = behavior }
  end
  return out
end

local EXPECT = pretExpect()
if not EXPECT then
  print("[skip] " .. PRET .. " layouts or tileset attributes not present; "
    .. "the size and behavior checks against pret are skipped")
end

-- pokefirered/include/constants/metatile_behaviors.h:66-69
local SPIN_LO, SPIN_HI = 0x54, 0x57

print("[test] 1. two tileset structs that share a tiles blob stay two tilesets")

local BASE = 0x09000000
local function fakeRom(structs)
  local bytes, words = {}, {}
  for _, s in ipairs(structs) do
    local o = s.ptr - 0x08000000
    bytes[o] = 1
    bytes[o + 1] = s.secondary and 1 or 0
    words[o + 4] = s.tiles
    words[o + 8] = s.palettes
    words[o + 12] = s.metatiles
    words[o + 16] = 0
    words[o + 20] = s.attributes
  end
  return {
    get = function(_, o) return bytes[o] or 0 end,
    u32 = function(_, o) return words[o] or 0 end,
    ptrOffset = function(_, p)
      if p < 0x08000000 or p >= 0x0A000000 then return nil end
      return p - 0x08000000
    end,
  }
end

local PRIMARY = { ptr = BASE + 0x0000, secondary = false,
  tiles = BASE + 0x100000, palettes = BASE + 0x140000,
  metatiles = BASE + 0x200000, attributes = BASE + 0x204000 }
local SHARED_TILES, SHARED_PALS = BASE + 0x300000, BASE + 0x340000
local SEC_A = { ptr = BASE + 0x0100, secondary = true,
  tiles = SHARED_TILES, palettes = SHARED_PALS,
  metatiles = BASE + 0x400000, attributes = BASE + 0x404000 }
local SEC_B = { ptr = BASE + 0x0200, secondary = true,
  tiles = SHARED_TILES, palettes = SHARED_PALS,
  metatiles = BASE + 0x500000, attributes = BASE + 0x504000 }
local SEC_A_AGAIN = { ptr = BASE + 0x0300, secondary = true,
  tiles = SHARED_TILES, palettes = SHARED_PALS,
  metatiles = SEC_A.metatiles, attributes = SEC_A.attributes }

local rom = fakeRom({ PRIMARY, SEC_A, SEC_B, SEC_A_AGAIN })
local nameA = MapCatalog.tilesetNameForPtr(rom, SEC_A.ptr)
local nameB = MapCatalog.tilesetNameForPtr(rom, SEC_B.ptr)
local nameC = MapCatalog.tilesetNameForPtr(rom, SEC_A_AGAIN.ptr)
check(nameA ~= nil and nameB ~= nil, "both secondary structs resolve to a name")
check(nameA ~= nameB,
  "different metatiles + attributes give different names (" ..
  tostring(nameA) .. " vs " .. tostring(nameB) .. ")")
eq(nameC, nameA, "the same metatiles + attributes still dedupe to one name")
eq(Versions.TILESETS[nameB] and Versions.TILESETS[nameB].attributes,
  SEC_B.attributes - 0x08000000, "the second struct registers its own attributes")

local pairA = MapCatalog.pairForLayout(rom,
  { primaryTilesetPtr = PRIMARY.ptr, secondaryTilesetPtr = SEC_A.ptr })
local pairB = MapCatalog.pairForLayout(rom,
  { primaryTilesetPtr = PRIMARY.ptr, secondaryTilesetPtr = SEC_B.ptr })
check(pairA ~= pairB,
  "the two layouts land in different pairs (" .. tostring(pairA) ..
  " vs " .. tostring(pairB) .. ")")

print("[test] 2. the census over the real ROM")
local ROM = "../pokefirered/pokefirered.gba"
local romFile = io.open(ROM, "rb")
if not romFile then
  print("[skip] " .. ROM .. " not present; ROM section skipped")
else
  romFile:close()
  local FileIO = require("src.import.gba.file_io")
  local imports = FileIO.makeImports(
    ROM, "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "firered")
  local realRom = assert(require("src.import.gba.rom").open(imports, "firered"))
  local version = assert(Versions.lookup(realRom.md5))
  local MapTree = require("src.import.gba.map_tree")
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(realRom, version))
  local order, byEngine = MapCatalog.allOrder(census)
  MapCatalog.registerOrder(realRom, version, order, byEngine)

  local hideout = Versions.MAPS[HIDEOUT]
  check(hideout ~= nil, HIDEOUT .. " is registered")
  local condoPair = nil
  for _, id in ipairs(FLOORS) do
    local spec = Versions.MAPS[id]
    if not spec then
      check(false, id .. " is registered")
    else
      condoPair = condoPair or spec.pair
      eq(spec.pair, condoPair, id .. " shares one Condominiums pair")
      check(hideout == nil or spec.pair ~= hideout.pair,
        id .. " does not borrow " .. HIDEOUT .. "'s pair (" .. tostring(spec.pair) .. ")")
      local want = EXPECT and EXPECT[id]
      if want then
        eq(spec.width .. "x" .. spec.height, want.w .. "x" .. want.h,
          id .. " keeps pret's layout size")
      end
    end
  end

  local condoSpec = condoPair and Versions.TILESET_PAIRS[condoPair]
  local hideoutSpec = hideout and Versions.TILESET_PAIRS[hideout.pair]
  local condoSec = condoSpec and Versions.TILESETS[condoSpec.secondary]
  local hideoutSec = hideoutSpec and Versions.TILESETS[hideoutSpec.secondary]
  if condoSec and hideoutSec then
    eq(condoSec.tiles, hideoutSec.tiles,
      "both secondaries really do share one tiles blob")
    check(condoSec.metatiles ~= hideoutSec.metatiles,
      "their metatile blocks differ")
    check(condoSec.attributes ~= hideoutSec.attributes,
      "their attribute blocks differ")
  else
    check(false, "both secondary tilesets are registered")
  end
  imports:_close()
end

print("[test] 3. the baked cache")
local Cache = require("tests.game3_cache")
local root = Cache.root("native/manifest.lua")
if not root then
  print("[skip] " .. tostring(Cache.reason))
else
  print("[info] FireRed cache at " .. root)
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

  local manifest = loadLua("native/manifest.lua") or {}
  local midIndex = loadLua("mid_index.lua") or {}

  local function histogram(mapId)
    local info = (manifest.layouts or {})[mapId]
    local blob = readFile("native/layouts/" .. mapId .. ".mid")
    local decoded = blob and NativePack.decodeMidLayout(blob)
    if not (info and decoded) then return nil end
    local tw = decoded.trueWidth or decoded.width
    local th = decoded.trueHeight or decoded.height
    local hist, spins = {}, 0
    for y = 0, th - 1 do
      for x = 0, tw - 1 do
        local mid = decoded.cells[y * decoded.width + x + 1].mid
        local row = midIndex[info.pair] and midIndex[info.pair][mid]
        local b = row and row.behavior or -1
        hist[b] = (hist[b] or 0) + 1
        if b >= SPIN_LO and b <= SPIN_HI then spins = spins + 1 end
      end
    end
    return hist, spins, tw, th, info.pair
  end

  local hideoutHist, hideoutSpins, _, _, hideoutPair = histogram(HIDEOUT)
  check(hideoutHist ~= nil, HIDEOUT .. " is baked")
  check((hideoutSpins or 0) > 0,
    HIDEOUT .. " still has its spinners, " .. tostring(hideoutSpins) .. " cells")

  for _, id in ipairs(FLOORS) do
    local want = EXPECT and EXPECT[id]
    local hist, spins, tw, th, pair = histogram(id)
    if not hist then
      check(false, id .. " is baked")
    else
      check(pair ~= hideoutPair,
        id .. " renders in its own pair (" .. tostring(pair) .. ")")
      eq(spins, 0, id .. " has no spin-tile behaviors")
      if want then
        eq(tw .. "x" .. th, want.w .. "x" .. want.h, id .. " true size is pret's")
        local seen, diff = {}, 0
        for b in pairs(hist) do seen[b] = true end
        for b in pairs(want.behavior) do seen[b] = true end
        for b in pairs(seen) do
          local got, exp = hist[b] or 0, want.behavior[b] or 0
          if got ~= exp then
            diff = diff + 1
            print(string.format("      behavior 0x%02x: cache %d, pret %d", b, got, exp))
          end
        end
        eq(diff, 0, id .. " behavior histogram matches pret")
      end
    end
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")

local ROUND_KEYS = {
  "data/generated/gba/scripts/multichoice.lua",
  "data/generated/gba/pokemon/battle/terrain_grass.rgba",
  "data/generated/gba/pokemon/battle/terrain_cave.rgba",
  "data/generated/gba/pokemon/battle/terrain_water.rgba",
  "data/generated/gba/pokemon/battle/terrain_champion.rgba",
  "data/generated/gba/pokemon/battle/terrain_bg_cave.rgba",
  "data/generated/gba/pokemon/pokedex/paper_bg.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/1.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/bulbasaur.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/question_mark.rgba",
  "data/generated/gba/chrome/fonts/japanese_normal_fg.rgba",
  "data/generated/gba/chrome/fonts/japanese_small_fg.rgba",
  "data/generated/gba/chrome/fonts/japanese_widths.lua",
  "data/generated/gba/chrome/fonts/braille_fg.rgba",
  "data/generated/gba/chrome/fonts/braille_shadow.rgba",
  "data/generated/gba/chrome/fonts/braille.lua",
  "data/generated/gba/seagallop/manifest.lua",
  "data/generated/gba/seagallop/water.4bpp",
  "data/generated/gba/seagallop/ferry.4bpp",
  "data/generated/gba/seagallop/wake.4bpp",
  "data/generated/gba/seagallop/wb_tilemap.bin",
  "data/generated/gba/seagallop/eb_tilemap.bin",
  "data/generated/gba/seagallop/wb.rgba",
  "data/generated/gba/seagallop/eb.rgba",
}

print("[test] 1. the cache version carries this round's importer output")
local CURRENT = Versions.CACHE_VERSION
check(type(CURRENT) == "number" and CURRENT >= 106,
  "Versions.CACHE_VERSION carries the round (" .. tostring(CURRENT) .. ")")

print("[test] 2. every key this round added is in the firered required list")
local required, isOverride = CacheContract.requiredFilesFor("firered")
check(isOverride == true, "firered has its own required list")
local have = {}
for _, path in ipairs(required) do have[path] = true end
for _, path in ipairs(ROUND_KEYS) do
  check(have[path] == true, "the firered contract requires " .. path)
end

print("[test] 3. a cache missing one of them is incomplete")
for _, path in ipairs(ROUND_KEYS) do
  local fs = {
    prefix = "",
    exists = function(candidate) return candidate ~= path end,
  }
  local complete, missing = CacheContract.allRequiredFilesExist("firered", fs)
  check(complete == false and missing == path,
    "a cache without " .. path .. " is incomplete (" .. tostring(missing) .. ")")
end

print("[test] 4. the staleness gate rejects an older cache")
local META = "data/generated/gba/meta.json"
local stamp = CURRENT
local stampFs = {
  prefix = "",
  exists = function() return true end,
  read = function(rel)
    if rel == CacheContract.MARKER_PATH then return CacheContract.markerFor("firered") end
    if rel == META then
      return '{"md5":"x","cache_version":' .. tostring(stamp) .. ',"native_version":6}'
    end
    return nil
  end,
}
check(CacheContract.cacheVersionCurrent("firered", stampFs) == true,
  "a current meta.json is current")
check(CacheContract.isReady("firered", stampFs) == true,
  "a complete current cache is ready")
stamp = CURRENT - 1
check(CacheContract.cacheVersionCurrent("firered", stampFs) == false,
  "a meta.json one version back is stale")
check(CacheContract.isReady("firered", stampFs) == false,
  "a complete cache one version back is not ready, so it re-imports")
stamp = CURRENT - 2
check(CacheContract.isReady("firered", stampFs) == false,
  "a complete cache two versions back is not ready either")
stamp = CURRENT

print("[test] 5. an imported cache walks the whole required list")
local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] cache walk: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local metaRaw = readFile("meta.json") or ""
check(metaRaw:find('"cache_version"%s*:%s*' .. tostring(CURRENT)) ~= nil,
  "the imported cache is stamped " .. tostring(CURRENT))

local base = root:gsub("/data/generated/gba$", "")
check(base ~= root, "the cache root sits under a version directory (" .. base .. ")")

local function present(rel)
  local f = io.open(base .. "/" .. rel, "rb")
  if f then f:close(); return true end
  return false
end

local missing, walked = {}, 0
for _, path in ipairs(required) do
  walked = walked + 1
  if not present(path) then missing[#missing + 1] = path end
end
check(walked >= 100, "the walk covered the whole firered contract (" .. walked .. ")")
check(#missing == 0, "no required key is missing (" .. (missing[1] or "none") .. ")")

local liveFs = { prefix = "", exists = present }
local complete, firstMissing = CacheContract.allRequiredFilesExist("firered", liveFs)
check(complete == true,
  "CacheContract calls the imported cache complete (" .. tostring(firstMissing) .. ")")

finish()

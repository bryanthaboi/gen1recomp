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

local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")

print("[test] 1. the importer advertises a whole cache version")
local V = Versions.CACHE_VERSION
check(type(V) == "number" and V == math.floor(V) and V > 0,
  "Versions.CACHE_VERSION is a positive integer, got " .. tostring(V))

print("[test] 2. cacheVersionCurrent rejects the previous cache version")

local function metaFs(version)
  return {
    prefix = nil,
    read = function(path)
      if path == "data/generated/gba/meta.json" then
        return string.format('{"cache_version":%d,"native_version":%d}',
          version, Versions.NATIVE_VERSION)
      end
      return nil
    end,
    exists = function() return true end,
  }
end

check(CacheContract.cacheVersionCurrent("firered", metaFs(V)) == true,
  "a meta.json at the importer's own version is current")
check(CacheContract.cacheVersionCurrent("firered", metaFs(V - 1)) == false,
  "a meta.json one version behind is rejected as stale")
check(CacheContract.cacheVersionCurrent("firered", metaFs(V + 1)) == false,
  "a meta.json from a newer importer is rejected too")

local noMeta = { prefix = nil, read = function() return nil end, exists = function() return true end }
check(CacheContract.cacheVersionCurrent("firered", noMeta) == false,
  "a cache with no meta.json is rejected")

print("[test] 3. the stitch round's new keys are in the firered required list")

local required = CacheContract.requiredFilesFor("firered")
local have = {}
for _, path in ipairs(required) do have[path] = true end

local NEW_KEYS = {
  -- src/region_map.c:425
  "data/generated/gba/region_map/fly_icon.rgba",
  "data/generated/gba/region_map/fly_icon.png",
  -- src/heal_location.c:62, src/region_map.c:4023
  "data/generated/gba/region_map/heal_locations.lua",
  "data/generated/gba/region_map/fly_destinations.lua",
  -- src/scrcmd.c:711
  "data/generated/gba/native/layouts/alt_264.mid",
  "data/generated/gba/native/layouts/alt_278.mid",
  "data/generated/gba/native/layouts/alt_279.mid",
  "data/generated/gba/native/layouts/alt_319.mid",
  -- src/data/field_effects/field_effect_objects.h:99,565,1203
  "data/generated/gba/field_effects/ripple.rgba",
  "data/generated/gba/field_effects/splash.rgba",
  "data/generated/gba/field_effects/hot_springs_water.rgba",
  "data/generated/gba/field_effects/fly_bird.rgba",
  "data/generated/gba/field_effects/rock_smash.rgba",
}
for _, path in ipairs(NEW_KEYS) do
  check(have[path] == true, "required: " .. path)
end

print("[test] 4. an imported cache at this version walks with zero missing keys")

local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] cache half: " .. tostring(Cache.reason))
else
  print("[info] FireRed cache at " .. root)
  local base = root:gsub("/data/generated/gba$", "")
  local diskFs = {
    prefix = nil,
    read = function(path)
      local f = io.open(base .. "/" .. path, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    exists = function(path)
      local f = io.open(base .. "/" .. path, "rb")
      if not f then return false end
      f:close()
      return true
    end,
  }
  check(CacheContract.cacheVersionCurrent("firered", diskFs) == true,
    "the imported cache passes the staleness gate")
  local complete, missing = CacheContract.allRequiredFilesExist("firered", diskFs)
  check(complete == true, "zero missing required keys, first missing: " .. tostring(missing))
end

if failed > 0 then
  print(string.format("[result] %d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("[result] all checks passed")
os.exit(0)

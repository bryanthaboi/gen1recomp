#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local GameCache = require("tests.game3_cache")
local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local NativePack = require("src.import.gba.native_pack")
local cache = GameCache.cache()

local failed, checked = 0, 0
local function check(cond, msg)
  checked = checked + 1
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function stamp(root, key)
  local src = cache:read(root .. "/meta.json")
  return src and tonumber(src:match('"' .. key .. '"%s*:%s*(%d+)'))
end

local function candidates(id)
  local list = {}
  local home = os.getenv("HOME")
  local identity = os.getenv("POKEPORT_IDENTITY")
  if home and identity and identity ~= "" then
    list[#list + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/" .. id .. "/data/generated/gba"
    list[#list + 1] = home .. "/.local/share/love/" .. identity .. "/" .. id .. "/data/generated/gba"
  end
  if id == "firered" then
    list[#list + 1] = os.getenv("POKEPORT_GBA_CACHE")
    list[#list + 1] = "data/generated/gba"
  end
  return list
end

local function mounted(id)
  local game = Versions.forGame(id)
  for _, root in ipairs(candidates(id)) do
    if cache:exists(root .. "/native/manifest.lua") and cache:exists(root .. "/objects/pack.lua")
      and stamp(root, "cache_version") == game.CACHE_VERSION
      and stamp(root, "native_version") == game.NATIVE_VERSION then
      return root
    end
  end
end

local function loadLua(root, rel)
  local src = cache:read(root .. "/" .. rel)
  local chunk = src and load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local function checkVersion(id, root)
  local manifest = loadLua(root, "native/manifest.lua")
  local pack = loadLua(root, "objects/pack.lua")
  check(manifest and manifest.pairs, id .. " native manifest loads")
  check(pack and pack.behaviors, id .. " objects pack loads")
  if not (manifest and manifest.pairs and pack and pack.behaviors) then return end
  local pairsSeen = 0
  for name, info in pairs(manifest.pairs) do
    pairsSeen = pairsSeen + 1
    local idx = NativePack.decodeIdx(cache:read(root .. "/native/" .. name .. "/mids.idx"))
    check(idx ~= nil, ("%s %s has an atlas"):format(id, name))
    local packed = {}
    for _, mid in ipairs(idx and idx.midIds or {}) do packed[mid] = true end
    local defined, missing = 0, {}
    for mid in pairs(pack.behaviors[name] or {}) do
      defined = defined + 1
      if not packed[mid] then missing[#missing + 1] = mid end
    end
    check(defined > 0, ("%s %s defines metatiles"):format(id, name))
    check(#missing == 0, ("%s %s packs every defined metatile (%d missing, first %s)")
      :format(id, name, #missing, tostring(missing[1])))
    check(info.midCount == defined, ("%s %s midCount %s equals its %d defined metatiles")
      :format(id, name, tostring(info.midCount), defined))
  end
  check(pairsSeen > 0, id .. " manifest lists tileset pairs")
  print(("[info] %s: %d pairs at %s"):format(id, pairsSeen, root))
end

local seen = {}
for _, id in ipairs(GameVersion.ORDER) do
  local info = GameVersion.VERSIONS[id]
  if info and info.generation == 3 then
    local root = mounted(id)
    if root then
      seen[#seen + 1] = id
      checkVersion(id, root)
    end
  end
end
if #seen == 0 then
  print("[skip] game3_pair_atlas_full_test: no current Gen 3 cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY")))
  os.exit(0)
end
print(("[info] %s, %d checks"):format(table.concat(seen, ", "), checked))
if failed > 0 then
  print(("FAIL %d of %d"):format(failed, checked))
  os.exit(1)
end
print("[ok] every pair atlas packs every defined metatile")

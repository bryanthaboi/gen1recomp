package.path = "./?.lua;./?/init.lua;" .. package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local version = os.getenv("POKEPORT_VERSION") or "ruby"
local GameVersion = require("src.core.GameVersion")
GameVersion.set(version)
require("src.import.gba.versions").select(version)

local function readMeta(root)
  local f = root and io.open(root .. "/meta.json", "rb")
  if not f then return nil end
  local src = require("src.import.CacheBlob").decode(root .. "/meta.json", f:read("*a")) or ""
  f:close()
  return tonumber(src:match('"cache_version"%s*:%s*(%d+)'))
end

local want = require("src.import.gba.versions").CACHE_VERSION
local home = os.getenv("HOME")
local root = os.getenv("POKEPORT_GBA_CACHE")
if not root and home then
  for _, id in ipairs({ os.getenv("POKEPORT_IDENTITY") or "", "g1r-" .. version }) do
    local at = home .. "/Library/Application Support/LOVE/" .. id .. "/" .. version .. "/data/generated/gba"
    if id ~= "" and readMeta(at) == want then root = at break end
  end
end
if readMeta(root) ~= want then
  print("[skip] save_editor nature: no current " .. version .. " cache")
  os.exit(0)
end
local Dataset = require("src.core.game3.dataset")
Dataset.cacheRootOverride = root
Dataset.mountExtractRoots()

local Gen = require("Gen")
if not Gen.game3CacheReady() then
  print("[skip] save_editor nature: " .. version .. " cache has no text tables")
  os.exit(0)
end

local Ops = require("Ops")
local SummaryData = require("src.core.game3.summary_data")

-- pokeruby/src/data/text/nature_names_en.h:27
local want = { [0] = "HARDY", [3] = "ADAMANT", [24] = "QUIRKY" }
for id, name in pairs(want) do
  local ok, got = pcall(function() return SummaryData.NATURES[id] end)
  check(ok, version .. " SummaryData.NATURES[" .. id .. "] resolves: " .. tostring(got))
  if ok then eq(got, name, version .. " nature " .. id .. " name") end
end
local ok, id, name = pcall(SummaryData.nature, { personality = 3 })
check(ok, version .. " SummaryData.nature resolves: " .. tostring(id))
if ok then eq(name, "ADAMANT", version .. " nature from personality") end

local mon = { species = 25, speciesId = 25, personality = 0, otId = 0, nature = 0 }
local S = { data = { version = version, party = { mon } }, dirty = false }
local okSet, err = pcall(Ops.setNature, S, mon, 3)
check(okSet, version .. " Ops.setNature does not raise: " .. tostring(err))
eq((tonumber(mon.personality) or 0) % 25, 3, version .. " personality now gives ADAMANT")

T.finish("game3_save_editor_nature_test (" .. version .. ")")

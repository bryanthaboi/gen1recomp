local T = require("tests.harness")
local Contract = require("src.import.CacheContract")
local Version = require("src.core.GameVersion")

local files = {}
local fs = { prefix = "" }
function fs.exists(path) return files[fs.prefix .. path] ~= nil end
function fs.read(path) return files[fs.prefix .. path] end

local REQUIRED = { "data/generated/palettes.lua", "data/generated/trainers.lua",
  "data/generated/pokedex.lua", "data/generated/menu_gfx.lua",
  "data/generated/font.lua", "data/generated/credits.lua",
  "data/generated/trade.lua", "data/generated/icons.lua" }

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local prefix = Version.cachePrefix(version)
  local listed = {}
  for _, path in ipairs(Contract.requiredFiles(version)) do
    listed[path] = true
    files[prefix .. path] = "fixture"
  end
  local revisions = Version.revisions(version)
  local sha1 = revisions and revisions[1] and revisions[1].sha1 or nil
  files[prefix .. Contract.MARKER_PATH] = Contract.markerFor(version, sha1)
  T.check(Contract.isReady(version, fs), version .. " complete cache is ready")
  for _, path in ipairs(REQUIRED) do
    T.check(listed[path], version .. " REQUIRED lists " .. path)
    local held = files[prefix .. path]
    files[prefix .. path] = nil
    T.check(not Contract.isReady(version, fs), version .. " without " .. path .. " is not ready")
    files[prefix .. path] = held
  end
end

T.finish("Gen 2 generated tables required")

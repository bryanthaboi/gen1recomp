-- Imported semantic modules are opened without eager reads and are decoded
-- once, on first use, through the same public facade mods receive.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")
local DatasetViews = require("src.mods.DatasetViews")
local GameVersion = require("src.core.GameVersion")
local SaveSerializer = require("src.core.SaveSerializer")

local files = {}
Fixture.cache(files, "gold")
local fs = T.sdk.memfs(files)
local rawRead = fs.read
local reads = {}
fs.read = function(path)
  reads[path] = (reads[path] or 0) + 1
  return rawRead(path)
end
local decodes = 0
local service = DatasetViews.new(fs, require, function(source, limits)
  decodes = decodes + 1
  return SaveSerializer.decode(source, limits)
end)
local pokemonPath = GameVersion.cachePrefix("gold")
  .. "data/generated/pokemon.lua"
local movesPath = GameVersion.cachePrefix("gold")
  .. "data/generated/moves.lua"

local view, reason = service:open("gold")
T.eq(reason, nil, "marker-valid Gold dataset opens")
T.check(view ~= nil, "open returns the lazy view")
T.eq(reads[pokemonPath] or 0, 0, "open does not read an unused root")
T.eq(reads[movesPath] or 0, 0, "open does not read another unused root")
T.eq(decodes, 0, "open decodes no semantic root")

local first = view and view.content.pokemon:get("FIXMON")
T.eq(first and first.name, "FIXMON", "first access decodes a valid root")
T.check(decodes > 0, "first root access performs bounded decoding")
T.eq(reads[movesPath] or 0, 0, "pokemon access leaves moves unused")
local afterFirst = decodes
local second = view and view.content.pokemon:get("FIXMON")
T.eq(second and second.name, "FIXMON", "repeated access remains available")
T.eq(decodes, afterFirst, "repeated access does not re-decode cached roots")

T.finish("dataset_views_lazy_validation")

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

eq(package.loaded["src.import.gba.extract_island1"], nil,
  "precondition: the extractor is not loaded yet")

local Pokemon = require("src.core.game3.pokemon")
check(Pokemon ~= nil, "pokemon loads")

eq(package.loaded["src.import.gba.extract_island1"], nil,
  "loading pokemon no longer pulls the ROM extractor (I8 cycle broken)")

local CachePaths = require("src.core.game3.cache_paths")
eq(CachePaths.CACHE_ROOT, "data/generated/gba",
  "the shared CachePaths module still carries the default root")

package.loaded["src.import.gba.extract_island1"] = nil
local Extract = require("src.import.gba.extract_island1")
eq(Extract.CACHE_ROOT, CachePaths.CACHE_ROOT,
  "extract_island1 forwards CACHE_ROOT from CachePaths")
CachePaths.setRoot("tmp/other_root")
eq(Extract.CACHE_ROOT, "tmp/other_root", "an external root change is visible through the forward")
CachePaths.reset()
eq(Extract.CACHE_ROOT, "data/generated/gba", "reset restores the packaged default")

T.finish("game3_pokemon_no_extractor_require_test")

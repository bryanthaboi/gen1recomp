package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local CachePaths = require("src.core.game3.cache_paths")

eq(CachePaths.CACHE_ROOT, "data/generated/gba", "the packaged cache root")
eq(CachePaths.NATIVE_ROOT, "data/generated/gba/native", "native root is derived")
eq(CachePaths.NATIVE_ROOT, CachePaths.CACHE_ROOT .. "/native",
  "NATIVE_ROOT is CACHE_ROOT/native")

check(CachePaths.setRoot("data/generated/gba-rse") == true, "setRoot accepts a root")
eq(CachePaths.CACHE_ROOT, "data/generated/gba-rse", "setRoot writes CACHE_ROOT")
eq(CachePaths.NATIVE_ROOT, "data/generated/gba-rse/native", "setRoot derives NATIVE_ROOT")
check(CachePaths.setRoot("") == false, "setRoot rejects an empty root")
check(CachePaths.setRoot(nil) == false, "setRoot rejects nil")
eq(CachePaths.CACHE_ROOT, "data/generated/gba-rse", "a rejected setRoot changes nothing")

CachePaths.reset()
eq(CachePaths.CACHE_ROOT, "data/generated/gba", "reset restores the packaged root")
eq(CachePaths.NATIVE_ROOT, "data/generated/gba/native", "reset restores the native root")

do
  local f = io.open("src/import/gba/extract_island1.lua", "r")
  check(f ~= nil, "extract_island1.lua is readable")
  if f then
    local src = f:read("*a")
    f:close()
    local pinned = src:find('Extract.CACHE_ROOT = "data/generated/gba"', 1, true) ~= nil
    local wired = src:find("cache_paths", 1, true) ~= nil
    check(pinned or wired,
      "extract_island1 either pins the default or reads CachePaths (T6.3 handoff)")
  end
end

do
  local f = io.open("src/import/gba/extract_island1.lua", "r")
  if f then
    local src = f:read("*a")
    f:close()
    if src:find('Extract.CACHE_ROOT = "data/generated/gba"', 1, true) then
      eq(CachePaths.CACHE_ROOT, "data/generated/gba",
        "CachePaths.CACHE_ROOT equals the extractor's pinned default")
      eq(CachePaths.NATIVE_ROOT, "data/generated/gba/native",
        "CachePaths.NATIVE_ROOT equals the extractor's pinned default")
    end
  end
end

T.finish("game3_cache_paths_test")

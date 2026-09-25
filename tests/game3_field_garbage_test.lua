-- Per-frame garbage on the FireRed field.  Walking Viridian City allocated
-- ~145 KB a frame (~8.5 MB/s at 60 fps), so the collector ran a full cycle
-- every ~20-30 s over a 500+ MB heap and dropped frames.  These pin the hot
-- paths that produced most of it to zero allocation, and the behavior they
-- must keep:
--   * the mod require gate (src/mods/Loader.lua) built a debug.getinfo table
--     on every engine require -- engine code requires on hot paths each frame
--   * LayoutNative:midAt/collAt/elevAt built a cell table per border cell
--   * Map.worldMidAt built a closure per call
--   * the Quest Log re-copied its ~220 sampled tiles every 6 ticks
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
-- measure the interpreter: compiled traces can sink allocations the
-- interpreter still makes
if jit then jit.off() end

local checks = 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then error("FAIL " .. msg, 2) end
end

local function allocated(n, fn)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, n do fn(i) end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  return kb
end

-- ------- the mod require gate
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path) return files[path] and { type = "file" } or nil end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function() return {} end,
  }
end
local loader = Loader.new({ fs = memfs({}), generation = 3, version = "firered" })
loader:_installDevShim()
Runtime.currentMod, Runtime.modRequire = nil, nil

-- engine code (a chunk named under the engine's own src/, as the Loader
-- sees it: "src/" in the game, "./src/" under this package.path)
local enginePrefix = (debug.getinfo(Loader.new, "S").source or "")
  :gsub("^@", ""):gsub("mods[/\\]Loader%.lua$", "")
-- (not a tail call: the gate names the caller by its stack frame)
local engineChunk = assert(loadstring([[
  local name = ...
  local module = require(name)
  return module
]], "@" .. enginePrefix .. "core/game3/garbage_probe.lua"))
check(engineChunk("src.core.game3.layout_native") == package.loaded["src.core.game3.layout_native"],
  "engine require still returns the loaded module")
local kb = allocated(2000, function() engineChunk("src.core.game3.layout_native") end)
check(kb < 16, ("2000 engine requires allocate nothing (got %.1f KB)"):format(kb))
check(engineChunk("io") == io, "engine code may still require io")

-- mod code keeps every denial: a lazy require with no mod on record is
-- still caught by the caller's chunk name, and a recorded owner by id
local modChunk = assert(loadstring([[
  return pcall(function(name)
    local module = require(name)
    return module
  end, ...)
]], "@mods/nosy/main.lua"))
local ok, err = modChunk("io")
check(not ok and tostring(err):find("is not available to mods", 1, true),
  "a mod chunk requiring io is denied with no owner on record")
local okOs = modChunk("os")
check(not okOs, "a mod chunk requiring os is denied with no owner on record")
check(select(1, modChunk("src.core.game3.layout_native")),
  "a mod chunk may still require an ordinary engine module")
Runtime.currentMod = "nosy"
local okOwned, errOwned = pcall(engineChunk, "io")
check(not okOwned and tostring(errOwned):find("[nosy]", 1, true),
  "a require made while a mod is current is attributed and denied")
Runtime.currentMod = nil

-- ------- LayoutNative field reads
local LayoutNative = require("src.core.game3.layout_native")
local cells = {}
for i = 1, 4 * 3 do cells[i] = { mid = 100 + i, coll = i % 2, elev = i % 5 } end
cells[6] = nil -- a hole inside the map
local layout = LayoutNative.fromDecoded({
  width = 4, height = 3, cells = cells,
  borderMids = { 7, 8, 9, 10 }, borderWidth = 2, borderHeight = 2,
}, "TEST_MAP", "test_pair")
layout.overrides[1 * 1024 + 2] = { mid = 555, coll = 3, elev = 4 }
for y = -5, 7 do
  for x = -5, 8 do
    local cell = layout:cellAt(x, y)
    check(layout:midAt(x, y) == cell.mid and layout:collAt(x, y) == cell.coll
      and layout:elevAt(x, y) == cell.elev,
      ("field reads match cellAt at %d,%d"):format(x, y))
  end
end
kb = allocated(20000, function(i)
  layout:midAt(-3 - i % 7, 9); layout:collAt(40, -2); layout:elevAt(-1, -1)
end)
check(kb < 16, ("border field reads allocate nothing (got %.1f KB)"):format(kb))
-- a layout whose cellAt was replaced keeps going through it
local patched = LayoutNative.fromDecoded({ width = 1, height = 1, cells = { { mid = 1 } } }, "P", "p")
patched.cellAt = function() return { mid = 42, coll = 1, elev = 2 } end
check(patched:midAt(0, 0) == 42 and patched:collAt(0, 0) == 1 and patched:elevAt(0, 0) == 2,
  "a replaced cellAt still answers the field reads")

-- ------- Map.worldMidAt
local Map = require("src.core.game3.map")
local savedNeighbors, savedWorld = Map.neighbors, Map.world
local east = LayoutNative.fromDecoded({ width = 2, height = 3,
  cells = { { mid = 1 }, { mid = 2 }, { mid = 3 }, { mid = 4 }, { mid = 5 }, { mid = 6 } } },
  "EAST", "east_pair")
local primary = { midLayout = layout, pair = "test_pair" }
Map.neighbors = { east = { def = { midLayout = east }, offset = 0 } }
Map.world = {}
local mid, pair = Map.worldMidAt(4, 1, primary)
check(mid == 3 and pair == "east_pair", "east neighbor cell resolves through the connection")
mid, pair = Map.worldMidAt(1, 0, primary)
check(mid == 102 and pair == "test_pair", "in-map cell resolves from the primary layout")
local _, _, isVoid = Map.worldMidAt(-3, -3, primary)
check(isVoid == true, "a cell with no neighbor falls back to the border")
kb = allocated(20000, function(i)
  Map.worldMidAt(4 + i % 2, i % 3, primary); Map.worldMidAt(-2, -2, primary)
end)
check(kb < 16, ("worldMidAt allocates nothing (got %.1f KB)"):format(kb))
Map.neighbors, Map.world = savedNeighbors, savedWorld

-- ------- Quest Log tile sampling
local Q = require("src.core.game3.quest_log")
local s = { name = "RED", map = "FR_A", x = 1, y = 2 }
Q.record(s, "ArrivedInLocation", { [1] = "A" }, { x = 16, y = 32, actors = {} })
local tiles = {}
for y = 0, 12 do for x = 0, 16 do tiles[x .. "," .. y] = { 100 + x, "pair" } end end
Q.addTiles(s, tiles)
local scene = s.questLog.scenes[#s.questLog.scenes]
local kept = scene.tiles["3,4"]
check(kept ~= tiles["3,4"] and kept[1] == 103, "recorded tiles are copies")
kb = allocated(200, function() Q.addTiles(s, tiles) end)
check(kb < 16, ("re-sampling unchanged tiles allocates nothing (got %.1f KB)"):format(kb))
check(scene.tiles["3,4"] == kept, "an unchanged tile keeps its recorded copy")
tiles["3,4"] = { 999, "other" }
Q.addTiles(s, tiles)
check(scene.tiles["3,4"] ~= kept and scene.tiles["3,4"][1] == 999
  and scene.tiles["3,4"][2] == "other" and scene.tiles["3,4"] ~= tiles["3,4"],
  "a changed tile is re-recorded as a copy")

print(("PASS field garbage: %d checks"):format(checks))

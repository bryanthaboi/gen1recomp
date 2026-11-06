package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
require("src.core.Logger").warn = function() end
local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")
local MapAttrGrid = require("src.world.gen2.MapAttrGrid")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")

local G = love.graphics
local log = nil
local activeSet = "none"
local saved = {
  newCanvas = G.newCanvas, draw = G.draw, clear = G.clear,
  available = GbcPalette.available, with = GbcPalette.with,
  bgSet = Palettes.bgSet, build = MapAttrGrid.build,
}

G.newCanvas = function(w, h)
  local c = { w = w, h = h, released = false, chunks = 0 }
  function c.setFilter() end
  function c:release() self.released = true end
  function c:renderTo(fn)
    self.chunks = self.chunks + 1
    local prev = log
    log = self
    fn()
    log = prev
  end
  c.ops = {}
  return c
end
G.draw = function(_, quad, x, y)
  if log then
    log.ops[#log.ops + 1] = activeSet .. ":" .. tostring(quad and quad.tile)
      .. ":" .. tostring(x) .. ":" .. tostring(y)
  end
end
G.clear = function()
  if log then log.ops[#log.ops + 1] = "clear" end
end
GbcPalette.available = function() return true end
GbcPalette.with = function(colors, body)
  local prev = activeSet
  activeSet = colors and colors.name or "?"
  body()
  activeSet = prev
end
Palettes.bgSet = function()
  local set = {}
  for slot = 1, 8 do set[slot] = { name = "pal" .. slot, { 255, 255, 255 } } end
  return set
end

local function tileset()
  local blocks, tilePalettes = {}, {}
  for b = 1, 8 do
    local block = {}
    for i = 1, 16 do block[i] = ((b - 1) * 16 + i - 1) % 64 end
    blocks[b] = block
  end
  for t = 1, 64 do tilePalettes[t] = (t % 8) + 1 end
  return {
    blocks = blocks, tilePalettes = tilePalettes, tilesPerRow = 16,
    anim = { frames = { { func = "AnimateWaterTile", tile = 70 } } },
  }
end

local TS = tileset()
local ATLAS = { getDimensions = function() return 128, 64 end }

local function def(id, w, h, border, conns)
  local blocks = {}
  for i = 1, w * h do blocks[i] = (i * 7) % 8 end
  return { id = id, width = w, height = h, blocks = blocks, tileset = "T",
    borderBlock = border, connections = conns or {} }
end

local MAPS = {
  A = def("A", 20, 18, 1, { east = { mapId = "B", offset = 0 },
    north = { mapId = "C", offset = 0 } }),
  B = def("B", 10, 9, 2, { west = { mapId = "A", offset = 0 } }),
  C = def("C", 10, 9, 3, { south = { mapId = "A", offset = 0 } }),
}

local function world(crystal)
  local w = setmetatable({ maps = MAPS, tilesets = { T = TS }, mapImages = {},
    animCells = {}, bgSets = {}, viewW = 160, viewH = 144, daytime = "DAY",
    flickerPhase = 1, palettes = {}, animTimer = 2 }, World)
  w.atlasFor = function(_, d)
    if not d then return nil end
    return ATLAS, TS
  end
  w.isCrystal = function() return crystal == true end
  w.animSheets = function() return { water = { name = "water" } } end
  w.animLayers = function() return nil end
  w.map = Map.new(MAPS.A, TS)
  w.neighbors = {}
  return w
end

local function sorted(list)
  local out = {}
  for i, v in ipairs(list) do
    if v ~= "clear" then out[#out + 1] = v end
    if v == "clear" then T.eq(i, 1, "the wash is cleared before any tile") end
  end
  table.sort(out)
  return table.concat(out, "\n")
end

local w = world(false)
local map = Map.new(MAPS.A, TS)
local whole = w:bakeMapImage(map, "DAY", 1)
T.eq(whole.chunks, 1, "the one-shot bake is a single pass")

local job = w:beginMapBake(map, "DAY", 1)
local steps, maxTiles, done = 0, 0, false
while not done do
  local tiles
  done, tiles = w:bakeMapChunk(job, 48)
  steps = steps + 1
  if tiles > maxTiles then maxTiles = tiles end
end
T.eq(steps, math.ceil(20 * 18 / 3), "a 48 tile budget is three blocks a step")
T.check(maxTiles <= 48, "no chunk draws past its budget (" .. maxTiles .. ")")
local clears = 0
for _, op in ipairs(job.canvas.ops) do if op == "clear" then clears = clears + 1 end end
T.eq(clears, 1, "the chunked bake clears once")
T.eq(#job.canvas.ops, #whole.ops, "same number of draws as the one-shot bake")
T.eq(sorted(job.canvas.ops), sorted(whole.ops),
  "chunked draws are the one-shot bake's tile, position and palette set")

local defaultJob = w:beginMapBake(map, "DAY", 1)
local _, firstTiles = w:bakeMapChunk(defaultJob, World.BAKE_TILES_PER_STEP)
T.check(firstTiles <= World.BAKE_TILES_PER_STEP, "default budget holds")

local pumped = world(false)
pumped:queueNeighborBakes()
pumped.bakeQueue = { "B" }
pumped.borderQueue, pumped.attrQueue = {}, {}
pumped.bakeHold = nil
local key = pumped:mapCacheKey("B")
local pumps = 0
while pumped:pumpBakes() do
  pumps = pumps + 1
  if pumped.bakeJob then
    T.check(pumped.mapImages[key] == nil, "a partial bake is never published")
  end
  if pumps > 100 then break end
end
T.eq(pumps, math.ceil(10 * 9 / (World.BAKE_TILES_PER_STEP / 16)),
  "a queued map takes its chunk count in pump steps")
T.check(pumped.mapImages[key] ~= nil, "the finished bake is published")

local early = world(false)
early.bakeQueue = { "B" }
early.borderQueue, early.attrQueue = {}, {}
early:pumpBakes()
T.check(early.bakeJob ~= nil and early.bakeJob.id == "B", "B's bake is in progress")
local canvas = early.bakeJob.canvas
local got = early:imageFor("B")
T.check(got == canvas, "imageFor on an in-progress bake finishes that canvas")
T.check(early.bakeJob == nil, "and the job is gone")
T.eq(early.bakeJob, nil, "nothing left running")
T.check(early.mapImages[early:mapCacheKey("B")] == canvas, "and it is published")

local dropped = world(false)
dropped.bakeQueue = { "C" }
dropped.borderQueue, dropped.attrQueue = {}, {}
dropped:pumpBakes()
local stale = dropped.bakeJob.canvas
dropped:dropMapImages("C")
T.check(dropped.bakeJob == nil and stale.released, "a block edit drops the running bake")

local borders = world(false)
borders:queueNeighborBakes()
local rows = {}
for _, j in ipairs(borders.borderQueue) do rows[#rows + 1] = j.id .. j.row end
T.eq(table.concat(rows, ","), "A0,C0,B0", "one row-0 border job per map when no border is water")
TS.blocks[3][5] = 70
borders = world(false)
borders:queueNeighborBakes()
rows = {}
for _, j in ipairs(borders.borderQueue) do rows[#rows + 1] = j.id .. j.row end
T.eq(table.concat(rows, ","), "A0,C0,B2,B3,B4,B1",
  "the current map and each connection queue every water row, current row first")
TS.blocks[3][5] = 36

local builds = 0
local savedStore, savedStep = World.storeAttrGrid, World.attrJobStep
World.storeAttrGrid = function(...)
  builds = builds + 1
  return savedStore(...)
end
local stepCells = 0
World.attrJobStep = function(self, job, budget)
  local before = job.cells or 0
  local done = savedStep(self, job, budget)
  stepCells = stepCells + (job.cells - before)
  return done
end
local attr = world(true)
attr:queueNeighborBakes()
T.eq(table.concat(attr.attrQueue, ","), "C,B", "connection attr grids are queued")
attr.bakeHold = nil
attr.bakeQueue, attr.borderQueue = {}, {}
local attrSteps, maxCells = 0, 0
while true do
  stepCells = 0
  if not attr:pumpBakes() then break end
  attrSteps = attrSteps + 1
  if stepCells > maxCells then maxCells = stepCells end
  if attrSteps > 100 then break end
end
T.eq(builds, 2, "both connection attr grids are built by the pump")
T.check(maxCells > 0 and maxCells <= World.BAKE_TILES_PER_STEP,
  "an attr pump step never builds more than the tile budget (" .. maxCells .. ")")
local perMap = 1 + math.ceil(9 * 4 / math.floor(World.BAKE_TILES_PER_STEP / (10 * 4)))
T.eq(attrSteps, 2 * perMap, "an attr grid takes a begin step plus its chunk steps")
for _, id in ipairs({ "B", "C" }) do
  local want = saved.build(Map.new(MAPS[id], TS), TS)
  local got = attr.attrGrids[id].grid
  local same = got.cols == want.cols and got.rows == want.rows
  for i = 1, want.cols * want.rows do
    local a, b = got.cells[i], want.cells[i]
    if (a == nil) ~= (b == nil) or (a and (a.tileId ~= b.tileId or a.rawTileId ~= b.rawTileId
        or a.attr.palette ~= b.attr.palette or a.attr.vramBank ~= b.attr.vramBank
        or a.attr.priority ~= b.attr.priority or a.attr.xFlip ~= b.attr.xFlip
        or a.attr.yFlip ~= b.attr.yFlip)) then
      same = false
    end
  end
  T.check(same, "the chunked attr grid of " .. id .. " equals MapAttrGrid.build")
end
World.attrJobStep = savedStep
local partial = world(true)
partial:queueNeighborBakes()
partial.bakeHold = nil
partial.bakeQueue, partial.borderQueue = {}, {}
partial:pumpBakes()
partial:pumpBakes()
T.check(partial.attrJob ~= nil and (partial.attrGrids or {}).C == nil,
  "a part-built attr grid is never stored")
partial.map = Map.new(MAPS.C, TS)
partial:rebuildAttrGrid()
T.check(partial.attrJob == nil and partial.attrGrid ~= nil
  and partial.attrGrids.C ~= nil, "crossing mid-build finishes the grid at once")
builds = 0
attr.map = Map.new(MAPS.B, TS)
attr:rebuildAttrGrid()
T.eq(builds, 0, "crossing into a prebuilt map builds no attr grid")
attr.map:setBlock(0, 0, 5)
attr.map = Map.new(MAPS.A, TS)
attr.map = Map.new(MAPS.B, TS)
attr:rebuildAttrGrid()
T.eq(builds, 1, "a setBlock edit invalidates the cached grid")
attr:rebuildAttrGrid()
T.eq(builds, 1, "and the rebuilt grid is cached again")
attr.mapImage = {}
attr.dropMapImages = function() end
attr.imageFor = function() return {} end
attr.rebuildNeighbors = function() end
attr:refreshMapImages()
T.eq(builds, 2, "refreshMapImages rebuilds the grid")

G.newCanvas, G.draw, G.clear = saved.newCanvas, saved.draw, saved.clear
GbcPalette.available, GbcPalette.with = saved.available, saved.with
Palettes.bgSet, MapAttrGrid.build = saved.bgSet, saved.build
World.storeAttrGrid = savedStore

local capMap, capBorder = World.MAP_IMAGE_CAP, World.BORDER_IMAGE_CAP
World.MAP_IMAGE_CAP, World.BORDER_IMAGE_CAP = 3, 2
local trim = world(false)
trim.map = nil
trim.mapImageUse = {}
local stamp = 0
local function put(key)
  stamp = stamp + 1
  trim.mapImages[key] = { release = function() end }
  trim.mapImageUse[key] = stamp
end
for i = 1, 3 do put("M" .. i .. "|DAY") end
for i = 1, 5 do put("B" .. i .. "|DAY|border") end
T.eq(trim:trimMapImages(), 3, "only the border keys over their own cap are dropped")
local maps, borders = 0, 0
for key in pairs(trim.mapImages) do
  if World.isBorderKey(key) then borders = borders + 1 else maps = maps + 1 end
end
T.check(maps == 3 and borders == 2, "border bakes never evict a map image")
T.check(trim.mapImages["B5|DAY|border"] and not trim.mapImages["B1|DAY|border"],
  "the oldest border bakes go first")
World.MAP_IMAGE_CAP, World.BORDER_IMAGE_CAP = capMap, capBorder

T.finish("gen2 chunked bake")

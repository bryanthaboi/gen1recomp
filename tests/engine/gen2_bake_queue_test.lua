package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
require("src.core.Logger").warn = function() end
local World = require("src.world.gen2.World")

local function map(id, conns)
  return { id = id, width = 10, height = 9, connections = conns or {} }
end

local MAPS = {
  A = map("A", { east = { mapId = "B", offset = 0 }, north = { mapId = "F", offset = 0 } }),
  B = map("B", { west = { mapId = "A", offset = 0 }, east = { mapId = "C", offset = 0 } }),
  C = map("C", { west = { mapId = "B", offset = 0 }, east = { mapId = "D", offset = 0 } }),
  D = map("D", { west = { mapId = "C", offset = 0 }, east = { mapId = "E", offset = 0 } }),
  E = map("E", { west = { mapId = "D", offset = 0 } }),
  F = map("F", { south = { mapId = "A", offset = 0 }, north = { mapId = "G", offset = 0 } }),
  G = map("G", { south = { mapId = "F", offset = 0 }, north = { mapId = "H", offset = 0 } }),
  H = map("H", { south = { mapId = "G", offset = 0 } }),
}

local function image(id)
  return { id = id, released = false, release = function(self) self.released = true end }
end

local function world()
  local w = setmetatable({ maps = MAPS, map = { id = "A" }, mapImages = {},
    animCells = {}, bgSets = {}, viewW = 160, viewH = 144, daytime = "DAY",
    flickerPhase = 1 }, World)
  w.bakes = {}
  w.imageFor = function(self, id)
    local key = self:mapCacheKey(id)
    local img = self.mapImages[key]
    if not img then
      img = image(id)
      self.mapImages[key] = img
      self.bakes[#self.bakes + 1] = id
    end
    self:touchMapImage(key)
    return img
  end
  w.neighbors = {}
  for _, n in ipairs(World.computeNeighbors(MAPS, "A", 2, w.viewW, w.viewH)) do
    w.neighbors[#w.neighbors + 1] = { id = n.id, image = w:imageFor(n.id) }
  end
  w.mapImage = w:imageFor("A")
  w.bakes = {}
  return w
end

local w = world()
local current = {}
for _, nb in ipairs(w.neighbors) do current[nb.id] = true end
T.check(current.B and current.C and current.F and current.G, "A's neighbors are B, C, F, G")

local queue = w:queueNeighborBakes()
T.eq(table.concat(queue, ","), "H,D", "the ring is one crossing out, north before east")

w.mapImages[w:mapCacheKey("D")] = image("D")
queue = w:queueNeighborBakes()
T.eq(table.concat(queue, ","), "H", "an already baked map is not queued")
w.mapImages[w:mapCacheKey("D")] = nil

w:queueNeighborBakes()
T.eq(w:pumpBakes(), false, "the step that queued does not bake")
T.eq(#w.bakes, 0, "nothing baked on the queueing step")
T.eq(w:pumpBakes(), true, "next step bakes")
T.eq(table.concat(w.bakes, ","), "H", "exactly one map, nearest first")
T.eq(w:pumpBakes(), true, "following step bakes the next")
T.eq(table.concat(w.bakes, ","), "H,D", "one per step")
T.eq(w:pumpBakes(), false, "drained queue does nothing")
T.eq(#w.bakes, 2, "and bakes nothing")

local deferred = world()
local old = deferred.neighbors[1]
deferred:queueNeighborBakes({ old.id })
deferred.mapImages[deferred:mapCacheKey(old.id)] = nil
deferred.bakeHold = nil
T.eq(deferred:pumpBakes(), true, "a deferred neighbor bakes first")
T.eq(deferred.bakes[1], old.id, "it is the deferred one")
T.check(old.image == deferred.mapImages[deferred:mapCacheKey(old.id)],
  "the neighbor is re-pointed at the new bake")

local trim = world()
World.MAP_IMAGE_CAP = 6
local spare = {}
for _, id in ipairs({ "D", "E", "H" }) do
  spare[id] = trim:imageFor(id)
end
trim:touchMapImage(trim:mapCacheKey("A"))
T.eq(trim:trimMapImages(), 2, "over the cap by two")
T.check(spare.D.released and spare.E.released, "the two least recently used are released")
T.check(not spare.H.released, "the newest spare stays")
T.check(trim.mapImages[trim:mapCacheKey("D")] == nil, "and leaves the store")
for _, nb in ipairs(trim.neighbors) do
  T.check(not nb.image.released, "a drawn neighbor is never evicted: " .. nb.id)
end
T.check(not trim.mapImage.released, "the current map is never evicted")

World.MAP_IMAGE_CAP = 48
local roll = world()
local before = roll.bakeClock
local stale = roll:imageFor("H")
local stamp = roll.bakeClock
roll.daytime = "NITE"
roll.rolloverStamp = stamp
roll.bakeQueue, roll.bakeHold = {}, nil
for _, nb in ipairs(roll.neighbors) do nb.image = roll:imageFor(nb.id) end
roll.mapImage = roll:imageFor("A")
T.eq(roll:pumpBakes(), false, "drained after the rollover")
T.check(stale.released, "an unused old-daytime bake is released once the queue drains")
local kept = 0
for _ in pairs(roll.mapImages) do kept = kept + 1 end
T.eq(kept, 5, "only the new-daytime bakes remain")
T.check(before ~= nil, "bake clock runs")

T.finish("gen2 bake queue")

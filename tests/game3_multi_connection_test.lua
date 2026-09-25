package.path = "./?.lua;./?/init.lua;" .. package.path

local Connections = require("src.core.game3.connections")
local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")
local Itemfinder = require("src.core.game3.itemfinder")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function layout(tag, w, h)
  local L = { width = w, height = h, pair = tag }
  function L:midAt(x, y) return tag .. ":" .. x .. "," .. y end
  function L:collAt() return 0 end
  return L
end

local function def(tag, w, h, conns)
  return { id = tag, midLayout = layout(tag, w, h), pair = tag, connections = conns or {} }
end

local maps = {
  SRC = def("SRC", 24, 100, {
    { dir = "west", map = "GREEN", offset = 0 },
    { dir = "west", map = "SIX", offset = 40 },
    { dir = "west", map = "RUIN", offset = 80 },
    { dir = "north", map = "TOP", offset = 0 },
  }),
  GREEN = def("GREEN", 72, 20),
  SIX = def("SIX", 24, 30, { { dir = "east", map = "SRC", offset = -40 } }),
  RUIN = def("RUIN", 48, 40),
  TOP = def("TOP", 24, 10),
  KEYED = def("KEYED", 10, 10, { east = { map = "SIX", offset = 2 }, left = { map = "GREEN", offset = 0 } }),
}
local game = { data = { maps = maps } }

local each = Connections.each(maps.SRC)
check(#each == 4 and each[1].map == "GREEN" and each[2].map == "SIX" and each[3].map == "RUIN"
  and each[4].dir == "north", "list form keeps ROM order")
local keyed = Connections.each(maps.KEYED)
check(#keyed == 2 and keyed[1].dir == "east" and keyed[1].offset == 2
  and keyed[2].dir == "west" and keyed[2].map == "GREEN", "keyed form still resolves")

local function destOf(id) return maps[id] end
for _, row in ipairs({ { 10, "GREEN" }, { 50, "SIX" }, { 90, "RUIN" } }) do
  local c = Connections.incoming(maps.SRC, "left", 0, row[1], destOf)
  check(c and c.map == row[2], "incoming west row " .. row[1] .. " -> " .. row[2])
end
check(Connections.incoming(maps.SRC, "west", 0, 30, destOf) == nil, "incoming gap row 30 has no connection")
check(Connections.incoming(maps.SRC, "east", 23, 10, destOf) == nil, "incoming east with no east connection")
local c20 = Connections.incoming(maps.SRC, "west", 0, 20, destOf)
check(c20 and c20.map == "GREEN", "incoming bound is inclusive like fieldmap.c:724")

Map.loadNeighborsDepth1(game, maps.SRC)
check(#Map.neighborList == 4, "neighborList has every connection")
check(Map.neighbors.west and Map.neighbors.west.map == "GREEN", "neighbors[dir] keeps the first entry")
check(Map.worldMidAt(-1, 10, maps.SRC) == "GREEN:71,10", "west row 10 draws Green Path")
check(Map.worldMidAt(-1, 50, maps.SRC) == "SIX:23,10", "west row 50 draws Six Island")
check(Map.worldMidAt(-3, 95, maps.SRC) == "RUIN:45,15", "west row 95 draws Ruin Valley")
local _, _, void = Map.worldMidAt(-1, 30, maps.SRC)
check(void == true, "west gap row draws border")

local world = Map.computeWorld(maps, "SRC", 1, nil, nil)
local placed = {}
for _, e in ipairs(world) do placed[e.id] = e end
check(placed.GREEN and placed.GREEN.ox == -72 and placed.GREEN.oy == 0, "computeWorld places Green Path")
check(placed.SIX and placed.SIX.ox == -24 and placed.SIX.oy == 40, "computeWorld places Six Island")
check(placed.RUIN and placed.RUIN.ox == -48 and placed.RUIN.oy == 80, "computeWorld places Ruin Valley")

local conn = Connections.incoming(maps.SRC, "west", 0, 50, destOf)
local lx, ly = Collision.connectionLanding(maps.SIX, conn, "left", 0, 50)
check(lx == 23 and ly == 10, "landing on Six Island at (23,10)")
check(Collision.connectionLanding(maps.SIX, conn, "left", 0, 70) == nil, "landing outside the span is refused, not clamped")
local back = Connections.incoming(maps.SIX, "right", 23, 10, destOf)
local bx, by = Collision.connectionLanding(maps.SRC, back, "right", 23, 10)
check(back and back.map == "SRC" and bx == 0 and by == 50, "Six Island east lands on the source at row 50")

local n, nx, ny = Connections.atPos(Map.neighborList, -2, 45, 24, 100)
check(n and n.map == "SIX" and nx == 22 and ny == 5, "atPos resolves the covering west connection")
check(Connections.atPos(Map.neighborList, -2, 75, 24, 100) == nil, "atPos gap row has none")

local events = {
  SIX = { { type = "hidden_item", x = 22, y = 5 } },
  GREEN = {},
  RUIN = { { type = "hidden_item", x = 47, y = 1 } },
}
local scan = Itemfinder.scan({
  px = 1, py = 46, events = {}, flagSet = function() return false end,
  width = 24, height = 100, neighborList = Map.neighborList,
  eventsFor = function(id) return events[id] or {} end,
})
check(scan ~= nil, "itemfinder sees a hidden item on the middle west connection")
local scanRuin = Itemfinder.scan({
  px = 1, py = 84, events = {}, flagSet = function() return false end,
  width = 24, height = 100, neighborList = Map.neighborList,
  eventsFor = function(id) return events[id] or {} end,
})
check(scanRuin ~= nil, "itemfinder sees a hidden item on the last west connection")

check(Map.worldMidAt(2, -2, maps.SRC) == "TOP:2,8", "north row draws the north connection")

require("src.core.GameVersion").set("firered")
local Cache = require("tests.game3_cache")
if not Cache.mount("connections.lua", { native = true }) then
  print("[skip] game3_multi_connection_test cache section: " .. tostring(Cache.reason))
  os.exit(failures == 0 and 0 or 1)
end

local Dataset = require("src.core.game3.dataset")
local Player = require("src.core.game3.player")
local Runtime = require("src.core.game3.runtime")
local Field = require("src.core.game3.field")
local Ghosts = require("src.core.game3.ghosts")
local Space = require("src.core.game3.scripting.space")
local rgame = { data = {}, save = {}, session = { flags = {}, vars = {} } }
Dataset.hydrate(rgame)
Runtime.session = rgame.session
Field._game, Field._session, Field.running = rgame, rgame.session, true
Space.runEnterScripts = function() end
Space.vm = nil

local function setup(map, x, y, dir)
  Ghosts.clear()
  Map.load(nil, rgame, map, { x = x, y = y, facing = dir })
  rgame.session = Runtime.getSession()
  rgame.session.x, rgame.session.y = Player.cellX, Player.cellY
  Field.locked = false
  Player.surfing, Player.elevation = false, 3
end
local function finishStep()
  Player._onStepDone = function() end
  for _ = 1, 32 do
    if not Player.moving then break end
    Player.tick(rgame)
  end
end

local WP = "FR_SIX_ISLAND_WATER_PATH"
local wpDef = rgame.data.maps[WP]
local west = {}
for _, c in ipairs(Connections.each(wpDef)) do
  if c.dir == "west" then west[#west + 1] = c.map .. "@" .. c.offset end
end
check(table.concat(west, " ") == "FR_SIX_ISLAND_GREEN_PATH@0 FR_SIX_ISLAND@40 FR_SIX_ISLAND_RUIN_VALLEY@80",
  "cache Water Path west connections in ROM order")

setup("FR_SIX_ISLAND", 23, 12, "right")
check(Player.tryMove("right", rgame, false) == "connection", "Six Island east crosses")
finishStep()
check(Map.current == WP and Player.cellX == 0 and Player.cellY == 52, "Six Island east lands on Water Path (0,52)")
check(#Map.neighborList == 3, "Water Path loads all three west neighbors")
local mid, _, void = Map.worldMidAt(-1, 52, wpDef)
check(mid ~= nil and not void and mid == rgame.data.maps.FR_SIX_ISLAND.midLayout:midAt(23, 12),
  "Water Path west of row 52 draws Six Island")

for _, r in ipairs({
  { 52, "FR_SIX_ISLAND", 23, 12 },
  { 10, "FR_SIX_ISLAND_GREEN_PATH", 71, 10 },
  { 90, "FR_SIX_ISLAND_RUIN_VALLEY", 47, 10 },
}) do
  setup(WP, 0, r[1], "left")
  check(Player.tryMove("left", rgame, false) == "connection", "Water Path row " .. r[1] .. " crosses west")
  finishStep()
  check(Map.current == r[2] and Player.cellX == r[3] and Player.cellY == r[4],
    "Water Path row " .. r[1] .. " lands on " .. r[2])
end

os.exit(failures == 0 and 0 or 1)

#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Plaza = require("src.core.game3.link.union_plaza_map")

print("[test] contract")
eq(Plaza.MAP_ID, "FR_UNION_ROOM_PLAZA", "map id")
eq(Plaza.CAP, 40, "cap")
eq(#Plaza.CELLS, 41, "41 cells on the grid")
eq(#Plaza.ROLES, 25, "role grid is 25 rows")
local badRow = nil
for y, row in ipairs(Plaza.ROLES) do
  if #row ~= 25 then badRow = y end
  for i = 1, #row do
    if not Plaza.SOURCE[row:sub(i, i)] then badRow = y end
  end
end
check(badRow == nil, "every role row is 25 wide with a known role: " .. tostring(badRow))

print("[test] slot table")
local seen, unique = {}, 0
for slot = 1, Plaza.CAP do
  local x, y, facing = Plaza.cellFor(slot)
  check(x ~= nil and y ~= nil and facing ~= nil, "slot " .. slot .. " has a cell")
  local k = tostring(x) .. "," .. tostring(y)
  if not seen[k] then unique = unique + 1 end
  seen[k] = true
  eq(Plaza.slotAt(x, y), slot, "slotAt inverts slot " .. slot)
end
eq(unique, 40, "40 unique cells")
check(Plaza.cellFor(0) == nil and Plaza.cellFor(41) == nil, "slots outside 1..40 have no cell")
check(Plaza.slotAt(12, 24) == nil and Plaza.slotAt(0, 0) == nil, "slotAt is nil off the cell table")

local ex, ey = Plaza.entry()
local function dist(slot)
  local x, y = Plaza.cellFor(slot)
  return math.abs(x - ex) + math.abs(y - (ey - 1))
end
local sorted = true
for slot = 2, Plaza.CAP do
  if dist(slot) < dist(slot - 1) then sorted = false end
end
check(sorted, "fill order moves outward from the entrance")
local x1, y1 = Plaza.cellFor(1)
eq(x1, 12, "slot 1 sits on the entrance column")
eq(y1, 17, "slot 1 is the first cell up from the door")
local sx, sy = Plaza.cellFor(40)
check(sy == 5, "slot 40 is on the far row")

print("[test] geometry")
eq(ex, 12, "entry x")
eq(ey, 24, "entry y")
eq(Plaza.roleAt(ex, ey), "X", "entry is the exit mat")
local attX, attY = 3, 2
local blocked = {}
local function key(x, y) return y * 64 + x end
for _, c in ipairs(Plaza.CELLS) do blocked[key(c.x, c.y)] = true end
blocked[key(attX, attY)] = true
local function walkable(x, y)
  local r = Plaza.roleAt(x, y)
  return r ~= nil and not Plaza.BLOCKED[r] and not blocked[key(x, y)]
end
local reach = { [key(ex, ey)] = true }
local queue = { { ex, ey } }
local head = 1
while queue[head] do
  local p = queue[head]
  head = head + 1
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local nx, ny = p[1] + d[1], p[2] + d[2]
    if walkable(nx, ny) and not reach[key(nx, ny)] then
      reach[key(nx, ny)] = true
      queue[#queue + 1] = { nx, ny }
    end
  end
end
local allSides, onBad = true, {}
for _, c in ipairs(Plaza.CELLS) do
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    if not reach[key(c.x + d[1], c.y + d[2])] then
      allSides = false
      print(("  cell %d,%d side %d,%d unreachable"):format(c.x, c.y, d[1], d[2]))
    end
  end
  local r = Plaza.roleAt(c.x, c.y)
  if Plaza.BLOCKED[r] or c.y <= 3 or c.y >= 23 or (c.x == ex and c.y >= 19) then
    onBad[#onBad + 1] = c.x .. "," .. c.y
  end
end
check(allSides, "every cell is reachable from all 4 sides with the room full")
eq(#onBad, 0, "no cell on a wall, the counter rows or the exit lane")
check(reach[key(2, 2)] == true, "the trading board spot below the counter is reachable")
check(reach[key(3, 3)] == true, "the attendant is reachable from the front")

print("[test] a cache that cannot build the plaza is a hard error")
eq(Plaza.shouldUse, nil, "no switch back to the cart room")
local function fails(game, want, msg)
  local ok, err = pcall(Plaza.ensure, game)
  check(not ok and tostring(err):find(want, 1, true) ~= nil, msg .. ": " .. tostring(err))
end
local realMap = package.loaded["src.core.game3.map"]
package.loaded["src.core.game3.map"] = { ensureMidLayout = function() end }
fails({ data = {} }, "no map table", "no map table")
fails({ data = { maps = {} } }, "FR_UNION_ROOM is missing from the cache", "no FR_UNION_ROOM")
fails({ data = { maps = { FR_UNION_ROOM = { warps = {} } } } }, "FR_UNION_ROOM has no layout",
  "FR_UNION_ROOM without a layout")
local tiny = { width = 4, height = 4, cellAt = function() return { mid = 1, coll = 0, elev = 0 } end }
fails({ data = { maps = { FR_UNION_ROOM = { warps = {}, midLayout = tiny } } } }, "layout has no cell",
  "a truncated FR_UNION_ROOM layout")
local Adapters = require("src.core.game3.scripting.adapters")
local broken = Adapters.host(nil, { data = { maps = { FR_UNION_ROOM = { warps = {} } } } }, nil)
local realVersions = package.loaded["src.import.gba.versions"]
package.loaded["src.import.gba.versions"] = {
  frMapFor = function() return "FR_UNION_ROOM" end,
  seviiMapFor = function() return nil end,
}
local okWarp, warpErr = pcall(broken.warp, 1, 1, 0xFF, 7, 11, function() end, "warpspinenter")
package.loaded["src.import.gba.versions"] = realVersions
package.loaded["src.core.game3.map"] = realMap
check(not okWarp and tostring(warpErr):find("FR_UNION_ROOM has no layout", 1, true) ~= nil,
  "the Union Room warp errors instead of landing in the cart room: " .. tostring(warpErr))

print("[test] built from the imported cache")
local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json", { native = true })
if not root then
  print("[skip] plaza cache build: " .. tostring(Cache.reason))
else
  local Dataset = require("src.core.game3.dataset")
  local maps = Dataset.buildMaps()
  local src = maps.FR_UNION_ROOM
  check(src ~= nil, "FR_UNION_ROOM is in the cache")
  Dataset.attachMidLayouts({ FR_UNION_ROOM = src }, Cache.cache())
  local game = { data = { maps = maps } }
  local def = Plaza.ensure(game)
  check(def ~= nil and maps[Plaza.MAP_ID] == def, "ensure registers the plaza def")
  eq(Plaza.ensure(game), def, "ensure is idempotent")
  if def and src and src.midLayout then
    local L = def.midLayout
    eq(L.width, 25, "layout width")
    eq(L.height, 25, "layout height")
    eq(def.width, 25, "def width")
    eq(def.height, 25, "def height")
    eq(def.pair, src.pair, "same tileset pair as the cart room")
    local srcMids = {}
    local SL = src.midLayout
    for y = 0, (SL.trueHeight or SL.height) - 1 do
      for x = 0, (SL.trueWidth or SL.width) - 1 do
        srcMids[SL:midAt(x, y)] = true
      end
    end
    local foreign, collMismatch = 0, 0
    for y = 0, 24 do
      for x = 0, 24 do
        if not srcMids[L:midAt(x, y)] then foreign = foreign + 1 end
        local c = L:collAt(x, y)
        local r = Plaza.roleAt(x, y)
        if (c ~= 0) ~= (Plaza.BLOCKED[r] == true or r == "X") then
          collMismatch = collMismatch + 1
        end
      end
    end
    eq(foreign, 0, "every metatile comes from the Union Room layout")
    eq(collMismatch, 0, "blocked roles match the cart collision")
    for slot = 1, Plaza.CAP do
      local x, y = Plaza.cellFor(slot)
      if L:collAt(x, y) ~= 0 then check(false, "slot " .. slot .. " cell is floor") end
    end
    eq(#def.warps, 1, "one warp")
    local w, sw = def.warps[1], src.warps[1]
    eq(w.x, 12, "warp x")
    eq(w.y, 24, "warp y")
    eq(w.mapGroup, sw.mapGroup, "warp group matches FR_UNION_ROOM")
    eq(w.mapNum, sw.mapNum, "warp num matches FR_UNION_ROOM")
    eq(w.destWarp, sw.destWarp, "warp dest matches FR_UNION_ROOM")
    eq(w.destMap, sw.destMap, "warp destMap matches FR_UNION_ROOM")
    eq(L:collAt(12, 24), SL:collAt(7, 11), "exit tile keeps the cart warp collision")
    eq(def.music, src.music, "music copied")
  end
end

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] union plaza map")

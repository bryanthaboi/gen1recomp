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

local Objects = require("src.core.game3.objects")

local CITY = "FR_CERULEAN_CITY"
local ROUTE4 = "FR_ROUTE_4"
local LID_POLICEMAN, LID_SLOWBRO, LID_LASS = 1, 5, 6

local function cityDef()
  return {
    midLayout = { width = 48, height = 40 },
    objects = {
      { localId = LID_POLICEMAN, graphicsId = 25, x = 31, y = 12, movementType = 8 },
      { localId = LID_SLOWBRO, graphicsId = 88, x = 32, y = 29, movementType = 8 },
      { localId = LID_LASS, graphicsId = 15, x = 33, y = 29, movementType = 9 },
    },
  }
end

local function route4Def()
  return {
    midLayout = { width = 45, height = 20 },
    objects = {
      { localId = 1, graphicsId = 15, x = 20, y = 6, movementType = 8 },
    },
  }
end

local function xy(lid)
  local eo = Objects.find(lid)
  if not eo then return nil, nil end
  return eo.cellX, eo.cellY
end

-- pokefirered/data/maps/CeruleanCity/scripts.inc:10
local function blockExits()
  Objects.setObjectXY(LID_POLICEMAN, 30, 12)
  Objects.setObjectXY(LID_SLOWBRO, 26, 31)
  Objects.setObjectXY(LID_LASS, 27, 31)
end

local function resetObjects()
  if type(Objects.reset) == "function" then Objects.reset() end
end

check(type(Objects.reset) == "function", "Objects.reset exists")
check(type(Objects.setObjectXY) == "function", "Objects.setObjectXY exists")

print("[test] 1. first entry without FLAG_GOT_SS_TICKET parks the cop on the door")
resetObjects()
Objects.loadMap(nil, CITY, cityDef())
local px, py = xy(LID_POLICEMAN)
check(px == 31 and py == 12,
  string.format("cop spawns at his header cell (31,12), got (%s,%s)", tostring(px), tostring(py)))
blockExits()
px, py = xy(LID_POLICEMAN)
check(px == 30 and py == 12,
  string.format("BlockExits puts the cop on the house door (30,12), got (%s,%s)",
    tostring(px), tostring(py)))
local sx, sy = xy(LID_SLOWBRO)
local lx, ly = xy(LID_LASS)
check(sx == 26 and sy == 31 and lx == 27 and ly == 31,
  string.format("slowbro/lass park on the Route 5 road, got (%s,%s)/(%s,%s)",
    tostring(sx), tostring(sy), tostring(lx), tostring(ly)))

print("[test] 2. leave to Route 4 and come back with the ticket: no BlockExits call")
Objects.loadMap(nil, ROUTE4, route4Def())
Objects.loadMap(nil, CITY, cityDef())
px, py = xy(LID_POLICEMAN)
check(px == 31 and py == 12,
  string.format("cop is back on his map-header cell (31,12), got (%s,%s)",
    tostring(px), tostring(py)))
sx, sy = xy(LID_SLOWBRO)
lx, ly = xy(LID_LASS)
check(sx == 32 and sy == 29 and lx == 33 and ly == 29,
  string.format("slowbro/lass are back beside the Cut tree, got (%s,%s)/(%s,%s)",
    tostring(sx), tostring(sy), tostring(lx), tostring(ly)))
check(Objects._perm[CITY] == nil,
  "the Cerulean perm bucket was dropped on re-entry (LoadObjEventTemplatesFromHeader)")

print("[test] 3. a same-map rebind must not undo an in-flight BlockExits")
blockExits()
Objects.loadMap(nil, CITY, cityDef())
px, py = xy(LID_POLICEMAN)
check(px == 30 and py == 12,
  string.format("cop stays on the door across a same-map rebind, got (%s,%s)",
    tostring(px), tostring(py)))

print("[test] 4. the block is undone for the rest of the session, not just once")
for i = 1, 3 do
  Objects.loadMap(nil, ROUTE4, route4Def())
  Objects.loadMap(nil, CITY, cityDef())
  px, py = xy(LID_POLICEMAN)
  check(px == 31 and py == 12,
    string.format("round trip %d leaves the cop aside, got (%s,%s)", i, tostring(px), tostring(py)))
end

print("[test] 5. movement types come back from the header too")
Objects.setMovementType(LID_LASS, 8)
check(Objects.find(LID_LASS).movementType == 8, "lass movement type overridden")
Objects.loadMap(nil, ROUTE4, route4Def())
Objects.loadMap(nil, CITY, cityDef())
check(Objects.find(LID_LASS).movementType == 9,
  "lass movement type rebuilt from the header after a round trip")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

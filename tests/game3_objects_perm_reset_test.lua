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

local LAB = "FR_OAKS_LAB"
local TOWN = "FR_PALLET_TOWN"
local RIVAL = 8

local function labDef()
  return {
    midLayout = { width = 13, height = 13 },
    objects = {
      { localId = 4, graphicsId = 11, x = 6, y = 11, movementType = 8 },
      { localId = RIVAL, graphicsId = 72, x = 5, y = 4, movementType = 8 },
    },
  }
end

local function townDef()
  return {
    midLayout = { width = 20, height = 18 },
    objects = {
      { localId = 1, graphicsId = 12, x = 5, y = 15, movementType = 7 },
    },
  }
end

local function rivalXY()
  local eo = Objects.find(RIVAL)
  if not eo then return nil, nil end
  return eo.cellX, eo.cellY
end

local function countPerm()
  local n = 0
  for _ in pairs(Objects._perm) do n = n + 1 end
  return n
end

local hasReset = type(Objects.reset) == "function"
local function resetObjects()
  if hasReset then Objects.reset() end
end

print("[test] 1. template position before any perm")
check(hasReset, "Objects.reset exists")
resetObjects()
Objects.loadMap(nil, LAB, labDef())
local x, y = rivalXY()
check(x == 5 and y == 4, string.format("rival spawns at template (5,4), got (%s,%s)", tostring(x), tostring(y)))

print("[test] 2. setobjectxyperm moves him and a same-map rebind keeps it")
Objects.setObjectXY(RIVAL, 6, 10)
x, y = rivalXY()
check(x == 6 and y == 10, string.format("rival at (6,10) after setObjectXY, got (%s,%s)", tostring(x), tostring(y)))
Objects.loadMap(nil, LAB, labDef())
x, y = rivalXY()
check(x == 6 and y == 10,
  string.format("same-map rebind keeps the in-flight perm, got (%s,%s)", tostring(x), tostring(y)))

print("[test] 3. leaving and re-entering rebuilds the template from the header")
Objects.loadMap(nil, TOWN, townDef())
Objects.loadMap(nil, LAB, labDef())
x, y = rivalXY()
check(x == 5 and y == 4,
  string.format("rival back at (5,4) after a round trip, got (%s,%s)", tostring(x), tostring(y)))
check(Objects._perm[LAB] == nil, "perm bucket for the re-entered map was dropped")

print("[test] 4. Objects.reset drops every perm and the map binding")
Objects.setObjectXY(RIVAL, 6, 10)
x, y = rivalXY()
check(x == 6 and y == 10, "rival displaced again before the reset")
check(countPerm() > 0, "a perm bucket exists before the reset")
resetObjects()
check(countPerm() == 0, "Objects.reset empties _perm")
check(Objects._mapId == nil, "Objects.reset clears _mapId so the next enter is not a same-map rebind")
check(next(Objects._byId) == nil, "Objects.reset drops spawned objects")

print("[test] 5. a fresh session re-enters the same map at the template")
Objects.loadMap(nil, LAB, labDef())
x, y = rivalXY()
check(x == 5 and y == 4,
  string.format("rival at (5,4) in the new session, got (%s,%s)", tostring(x), tostring(y)))

print("[test] 6. movement-type perms follow the same lifetime")
Objects.setMovementType(RIVAL, 7)
check(Objects.find(RIVAL).movementType == 7, "setobjectmovementtype applied")
Objects.loadMap(nil, TOWN, townDef())
Objects.loadMap(nil, LAB, labDef())
check(Objects.find(RIVAL).movementType == 8, "movement type back to the header value after a round trip")

print("[test] 7. Game3:reset and Game3:returnToTitle reach Objects.reset")
local Game3 = require("src.core.Game3")
local function teardownDropsPerm(name)
  resetObjects()
  Objects.loadMap(nil, LAB, labDef())
  Objects.setObjectXY(RIVAL, 6, 10)
  check(countPerm() > 0, "a perm bucket exists before Game3:" .. name)
  local stub = setmetatable({}, { __index = Game3 })
  local ok, err = pcall(Game3[name], stub)
  check(ok, "Game3:" .. name .. " runs on a stub" .. (ok and "" or (": " .. tostring(err))))
  check(countPerm() == 0, "Game3:" .. name .. " empties Objects._perm")
  check(Objects._mapId == nil, "Game3:" .. name .. " clears Objects._mapId")
  Objects.loadMap(nil, LAB, labDef())
  local rx, ry = rivalXY()
  check(rx == 5 and ry == 4,
    string.format("rival at (5,4) after Game3:%s, got (%s,%s)", name, tostring(rx), tostring(ry)))
end
teardownDropsPerm("reset")
teardownDropsPerm("returnToTitle")

print("[test] 8. the player's house needs no perm special case")
local HOUSE = "FR_PLAYERS_HOUSE_1F"
local function houseDef()
  return {
    midLayout = { width = 13, height = 10 },
    objects = {
      { localId = 1, graphicsId = 20, x = 8, y = 4, movementType = 9 },
    },
  }
end
resetObjects()
Objects.loadMap(nil, HOUSE, houseDef())
Objects.setObjectXY(1, 3, 3)
Objects.loadMap(nil, TOWN, townDef())
Objects.loadMap(nil, HOUSE, houseDef())
local mom = Objects.find(1)
check(mom ~= nil and mom.cellX == 8 and mom.cellY == 4,
  string.format("Mom back at (8,4) after a round trip, got (%s,%s)",
    tostring(mom and mom.cellX), tostring(mom and mom.cellY)))
check(Objects._perm[HOUSE] == nil, "house perm bucket dropped on entry")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

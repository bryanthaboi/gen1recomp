#!/usr/bin/env luajit
-- Test for Issue #2361:
-- 1. Cerulean City Policeman moves aside (31, 12) after receiving SS Anne Ticket from Bill.
-- 2. Bill in Sea Cottage returns to desk (7, 5) instead of standing inside teleporter (3, 3).

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

print("=== Issue #2361: Cerulean Policeman & Bill Sea Cottage Position Tests ===")

local Objects = require("src.core.game3.objects")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Adapters = require("src.core.game3.scripting.adapters")

-- Setup mock map objects
local ceruleanObjects = {
  { localId = 1, index = 1, x = 31, y = 12, movementType = 8, graphicsId = "OBJ_EVENT_GFX_POLICEMAN" },
}

local seaCottageObjects = {
  { localId = 1, index = 1, x = 7, y = 5, movementType = 8, graphicsId = "OBJ_EVENT_GFX_BILL", flag = 0x80 },
  { localId = 2, index = 2, x = 10, y = 6, movementType = 8, graphicsId = "OBJ_EVENT_GFX_CLEFAIRY", flag = 0x81 },
}

local ceruleanMapDef = {
  objects = ceruleanObjects,
  midLayout = { width = 40, height = 40 },
}

local seaCottageMapDef = {
  objects = seaCottageObjects,
  midLayout = { width = 20, height = 20 },
}

print("[test] 1. Initial Cerulean City load with setobjectxyperm moves policeman to (30, 12)")
Objects.loadMap(nil, "CERULEAN_CITY", ceruleanMapDef)
local police = Objects.find(1)
check(police ~= nil, "policeman found")
check(police.cellX == 31 and police.cellY == 12, "default pos is (31, 12)")

-- Simulate OnTransition calling setobjectxyperm
Objects.setObjectXY(1, 30, 12)
check(police.cellX == 30 and police.cellY == 12, "policeman moved to (30, 12) blocking door")
check(ceruleanObjects[1].x == 31 and ceruleanObjects[1].y == 12, "original mapDef object was not mutated")

print("[test] 2. Map transition to Route 25 Sea Cottage with setobjectxyperm moves Bill to (3, 3)")
Objects.loadMap(nil, "ROUTE25_SEA_COTTAGE", seaCottageMapDef)
local bill = Objects.find(1)
check(bill ~= nil, "bill found")
check(bill.cellX == 7 and bill.cellY == 5, "default bill pos is (7, 5)")

-- Simulate OnTransition calling setobjectxyperm for Bill into teleporter
Objects.setObjectXY(1, 3, 3)
check(bill.cellX == 3 and bill.cellY == 3, "bill moved to (3, 3) inside teleporter")
check(seaCottageObjects[1].x == 7 and seaCottageObjects[1].y == 5, "original seaCottage mapDef object was not mutated")

print("[test] 3. Returning to Cerulean City after SS Ticket resets policeman to default (31, 12)")
Objects.loadMap(nil, "CERULEAN_CITY", ceruleanMapDef)
local policeReturned = Objects.find(1)
check(policeReturned ~= nil, "policeman found on return")
check(policeReturned.cellX == 31 and policeReturned.cellY == 12,
  string.format("policeman at (31, 12) beside door, got (%d, %d)", policeReturned.cellX, policeReturned.cellY))

print("[test] 4. Returning to Sea Cottage after helping Bill resets Bill to (7, 5)")
Objects.loadMap(nil, "ROUTE25_SEA_COTTAGE", seaCottageMapDef)
local billReturned = Objects.find(1)
check(billReturned ~= nil, "bill found on return")
check(billReturned.cellX == 7 and billReturned.cellY == 5,
  string.format("bill at (7, 5) at his desk, got (%d, %d)", billReturned.cellX, billReturned.cellY))

print("[test] 5. Adapters setObjectState does not poison npc.def in host engine")
local hostNpcDef = { x = 31, y = 12, index = 1 }
local hostNpc = { cellX = 31, cellY = 12, x = 31 * 16, y = 12 * 16, def = hostNpcDef, index = 1 }
local mockWorld = { npcs = { hostNpc } }

-- Test setObjectState via adapter
-- Ensure useGame3Objects returns nil in pure host test by temporarily clearing mapId
local savedMapId = Objects._mapId
Objects._mapId = nil
local hostAdapter = Adapters.host({}, { overworld = mockWorld }, mockWorld)
hostAdapter.setObjectState("setobjectxyperm", { 1, 30, 12 })
Objects._mapId = savedMapId

check(hostNpc.cellX == 30 and hostNpc.cellY == 12, "host npc cell updated to (30, 12)")
check(hostNpcDef.x == 31 and hostNpcDef.y == 12, "host npc.def preserved at (31, 12)")

if failed > 0 then
  print(string.format("=== FAILED: %d test(s) failed ===", failed))
  os.exit(1)
else
  print("=== ALL CERULEAN POLICEMAN & BILL TESTS PASSED ===")
end

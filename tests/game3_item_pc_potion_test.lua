#!/usr/bin/env luajit
-- Test: Game 3 Player Item PC starting Potion fidelity (pokefirered player_pc.c:100-101)

local Storage = require("src.core.game3.storage")
local Schema = require("src.core.game3.save_schema_firered")
local Bag = require("src.core.game3.bag")
local Bridge = require("src.core.game3.bridge")

local failures = 0
local function check(cond, msg)
  if cond then
    print("[PASS] " .. msg)
  else
    failures = failures + 1
    print("[FAIL] " .. msg)
  end
end

print("=== [TEST 1] Storage.new() starts with 1 Potion ===")
local s = Storage.new()
check(#s.items == 1, "Storage.new has 1 PC item")
check(s.items[1].id == 13 and s.items[1].qty == 1, "Storage.new item is POTION x1 (id 13)")

print("=== [TEST 2] Storage.ensure() seeds 1 Potion for fresh sessions ===")
local sess1 = {}
Storage.ensure(sess1)
check(sess1.storage and #sess1.storage.items == 1, "Storage.ensure populated storage.items")
check(sess1.storage.items[1].id == 13 and sess1.storage.items[1].qty == 1, "Storage.ensure item is POTION x1")

local sess2 = { storage = { currentBox = 1, boxes = {} } }
Storage.ensure(sess2)
check(sess2.storage and #sess2.storage.items == 1, "Storage.ensure populated missing items list")
check(sess2.storage.items[1].id == 13 and sess2.storage.items[1].qty == 1, "Storage.ensure item is POTION x1")

print("=== [TEST 3] Storage.restore() handles fresh, legacy, and pcItems ===")
local rNil = Storage.restore(nil, nil, nil)
check(rNil and #rNil.items == 1 and rNil.items[1].id == 13, "Storage.restore(nil, nil, nil) has POTION x1")

local rMap = Storage.restore(nil, nil, { POTION = 1 })
check(rMap and #rMap.items == 1 and rMap.items[1].id == 13 and rMap.items[1].qty == 1, "Storage.restore from host pcItems={POTION=1}")

local rIdMap = Storage.restore(nil, nil, { [13] = 1 })
check(rIdMap and #rIdMap.items == 1 and rIdMap.items[1].id == 13 and rIdMap.items[1].qty == 1, "Storage.restore from id pcItems={[13]=1}")

print("=== [TEST 4] Schema.newGame() starts with 1 Potion ===")
local ng = Schema.newGame({ rngSeed = 100 })
check(ng.storage and #ng.storage.items == 1, "Schema.newGame has 1 PC item")
check(ng.storage.items[1].id == 13 and ng.storage.items[1].qty == 1, "Schema.newGame PC item is POTION x1")

print("=== [TEST 5] Schema.fromSaveTable() round-trip and legacy migration ===")
local saved = Schema.toSaveTable(ng)
local loaded = Schema.fromSaveTable(saved)
check(loaded.storage and #loaded.storage.items == 1 and loaded.storage.items[1].id == 13, "fromSaveTable loaded saved storage")

local legacySave = { map = "FR_PLAYERS_HOUSE_2F", x = 1, y = 2, pcItems = { POTION = 1 } }
local legacyLoaded = Schema.fromSaveTable(legacySave)
check(legacyLoaded.storage and #legacyLoaded.storage.items == 1 and legacyLoaded.storage.items[1].id == 13, "fromSaveTable migrated legacy pcItems")

print("=== [TEST 6] Bridge.enterFromHost() starts with 1 Potion ===")
local hostSave = {
  playerName = "RED",
  party = {},
  inventory = {},
  pcItems = { POTION = 1 },
}
local bridgeSession = Bridge.enterFromHost(nil, { save = hostSave }, { map = "FR_PLAYERS_HOUSE_2F" })
check(bridgeSession.storage and #bridgeSession.storage.items == 1, "Bridge session has 1 PC item")
check(bridgeSession.storage.items[1].id == 13 and bridgeSession.storage.items[1].qty == 1, "Bridge session item is POTION x1")

print("=== [TEST 7] Withdrawing Potion leaves PC empty and persists after save ===")
check(Storage.withdrawItem(ng, 1, 1) == true, "Withdrew POTION from PC")
check(Bag.has(ng.bag, 13, 1), "Bag has POTION")
check(#ng.storage.items == 0, "PC is now empty")

local savedEmpty = Schema.toSaveTable(ng)
local loadedEmpty = Schema.fromSaveTable(savedEmpty)
check(#loadedEmpty.storage.items == 0, "Empty PC remains empty after save/load")

if failures == 0 then
  print("\nALL ITEM PC POTION TESTS PASSED (100%)")
  os.exit(0)
else
  print(string.format("\n%d test(s) failed", failures))
  os.exit(1)
end

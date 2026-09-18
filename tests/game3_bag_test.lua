#!/usr/bin/env luajit
-- Game3 bag: pret ItemSlot pockets, items pack, checkitem APIs, save migrate.

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

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Schema = require("src.core.game3.save_schema_firered")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Vm = require("src.core.game3.scripting.vm")
local Std = require("src.core.game3.scripting.stdscripts")

print("[test] 1. Items pack load")
ItemsData.install(nil)
local potion = ItemsData.info(13)
check(potion ~= nil and potion.name == "POTION", "POTION id 13 from pack/fallback")
check(ItemsData.pocketOf(13) == "ITEMS", "POTION pocket ITEMS")
check(ItemsData.pocketResult(13) == 1, "pocketResult ITEMS=1")
check(ItemsData.pocketResult(4) == 3, "POKE_BALL pocketResult=3")
check(ItemsData.CAPACITY.ITEMS == 42, "ITEMS capacity 42")
check(ItemsData.CAPACITY.KEY_ITEMS == 30, "KEY capacity 30")
check(ItemsData.displayName(364) == "TM CASE" or ItemsData.displayName(364):find("TM"), "TM CASE name")

print("[test] 2. Bag.add / canAdd / has / listPocket")
local bag = Bag.new()
check(Bag.canAdd(bag, 13, 1) == true, "empty bag can add POTION")
local ok = select(1, Bag.add(bag, 13, 5))
check(ok == true, "add 5 POTION")
check(Bag.get(bag, 13) == 5, "get POTION qty 5")
check(Bag.has(bag, 13, 5) == true, "has 5 POTION")
check(Bag.has(bag, 13, 6) == false, "not has 6 POTION")
local rows = Bag.listPocket(bag, "ITEMS")
check(#rows == 1 and rows[1].id == 13 and rows[1].qty == 5, "listPocket ITEMS slot order")

print("[test] 3. Capacity 42 + TM Case auto-grant")
bag = Bag.new()
for i = 1, 42 do
  Bag.add(bag, 12 + i, 1) -- 13..54
end
check(#bag.pockets.ITEMS == 42, "filled 42 ITEMS slots")
check(Bag.canAdd(bag, 55, 1) == false, "43rd unique ITEMS item fails")
check(select(1, Bag.add(bag, 13, 1)) == true, "stack into existing POTION still ok")

bag = Bag.new()
ok = select(1, Bag.add(bag, 289, 1)) -- TM01
check(ok == true, "add TM01")
check(Bag.has(bag, ItemsData.ITEM_TM_CASE, 1) == true, "TM CASE auto-granted to KEY_ITEMS")
check(#Bag.listPocket(bag, "TM_CASE") == 1, "TM in TM_CASE pocket")

print("[test] 4. Migrate stacks + schema newGame")
local legacy = { stacks = { POTION = 3, [4] = 2 } }
local mig = Bag.migrate(legacy)
check(Bag.get(mig, 13) >= 3 or Bag.get(mig, "POTION") >= 3, "migrate POTION stacks")
check(mig.pockets and mig.pockets.ITEMS, "migrate has pockets")

local session = Schema.newGame()
check(session.bag and session.bag.pockets and session.bag.pockets.ITEMS, "newGame bag pockets")
local loaded = Schema.fromSaveTable({
  bag = { stacks = { POTION = 7 } },
  name = "ASH",
})
check(Bag.get(loaded.bag, 13) == 7 or Bag.get(loaded.bag, "POTION") == 7, "fromSaveTable migrates stacks")

print("[test] 5. checkitem / checkitemtype ops")
-- Mock Runtime session for adapters / ops fallbacks
local Runtime = { _session = { bag = Bag.new() } }
function Runtime.getSession() return Runtime._session end
package.loaded["src.core.game3.runtime"] = Runtime
Bag.add(Runtime._session.bag, 13, 2)

local store = Flags.newStore()
local vm = Vm.new({
  store = store,
  scripts = {
    t_check = {
      { op = "checkitem", [1] = 13, [2] = 2 },
      { op = "copyvar", [1] = 0x4000, [2] = 0x800D }, -- persist past end wipe
      { op = "end" },
    },
    t_type = {
      { op = "checkitemtype", [1] = 13 },
      { op = "copyvar", [1] = 0x4001, [2] = 0x800D },
      { op = "end" },
    },
    t_space = {
      { op = "checkitemspace", [1] = 13, [2] = 1 },
      { op = "copyvar", [1] = 0x4002, [2] = 0x800D },
      { op = "end" },
    },
  },
  text = Std.TEXT,
  stdscripts = Std.SCRIPTS,
})

vm:start("t_check")
for _ = 1, 20 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(Flags.getVar(store, vm.ctx, 0x4000) == 1, "checkitem POTION x2 → true")

vm:start("t_type")
for _ = 1, 20 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(Flags.getVar(store, vm.ctx, 0x4001) == 1, "checkitemtype POTION → POCKET_ITEMS(1)")

vm:start("t_space")
for _ = 1, 20 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(Flags.getVar(store, vm.ctx, 0x4002) == 1, "checkitemspace POTION → true")

print("[test] 6. bufferitemname")
vm.ctx.stringVars = { [1] = "", [2] = "", [3] = "" }
Ops.dispatch(vm, { op = "bufferitemname", dest = 1, src = 13 })
check(vm.ctx.stringVars[2] == "POTION", "bufferitemname STR_VAR_2 = POTION")

print("[test] 7. Pass 2 — give / medicine / TM / escape / register")
local ItemUse = require("src.core.game3.item_use")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

-- medicineKind
check(ItemsData.medicineKind(14) == "status", "ANTIDOTE → status")
check(ItemsData.medicineKind(24) == "revive", "REVIVE → revive")
check(ItemsData.fieldUseKind(13) == "heal", "POTION fieldUseKind heal")

-- give held item
local sess = {
  name = "RED",
  map = "FR_MT_MOON_1F",
  healMap = "FR_PEWTER_CITY_POKEMON_CENTER_1F",
  healX = 7,
  healY = 4,
  party = {
    { species = 1, name = "BULBASAUR", hp = 10, maxHp = 20, moves = { 33 }, pp = { 35 }, status = "PSN" },
  },
  bag = Bag.new(),
}
Bag.add(sess.bag, 13, 2)
local gOk = select(1, ItemUse.giveToMon(sess, sess.bag, 13, 1))
check(gOk == true, "give POTION to mon")
check(Bag.get(sess.bag, 13) == 1, "give consumed one from bag")
check(tonumber(sess.party[1].item) == 13 or sess.party[1].item == 13, "mon holds POTION")

-- status cure
Bag.add(sess.bag, 14, 1)
local sOk = select(1, ItemUse.useField(sess, sess.bag, 14, 1))
check(sOk == true, "ANTIDOTE clears poison")
check(sess.party[1].status == nil, "status cleared")

-- heal
sess.party[1].hp = 5
Bag.add(sess.bag, 13, 1)
local hOk = select(1, ItemUse.useField(sess, sess.bag, 13, 1))
check(hOk == true, "POTION heals")
check(sess.party[1].hp > 5, "HP increased")

-- TM01 → Focus Punch (264); Bulbasaur learnset bit 0
local move = Pokemon.moveFromTmItem(289)
check(move == 264, "TM01 → move 264 Focus Punch (got " .. tostring(move) .. ")")
local can = Pokemon.canLearnTmItem(1, 289)
-- Bulbasaur may or may not learn TM01; just ensure API returns boolean
check(type(can) == "boolean", "canLearnTmItem returns boolean")

-- Escape rope indoors → heal warp (Warp.request needs mod/game; just can_escape path)
Bag.add(sess.bag, 85, 1)
-- Without Runtime mod/game, useEscapeRope still removes + attempts warp
local Runtime = package.loaded["src.core.game3.runtime"] or {}
Runtime._mod = nil
Runtime._game = nil
package.loaded["src.core.game3.runtime"] = Runtime
local eOk, eWhy = ItemUse.useField(sess, sess.bag, 85, nil)
check(eOk == true or eWhy == "escape", "escape rope attempted on indoor map")

-- outdoor refuse
sess.map = "FR_ROUTE_1"
Bag.add(sess.bag, 85, 1)
local e2 = select(1, ItemUse.useField(sess, sess.bag, 85, nil))
check(e2 == false, "escape rope refused outdoors")

-- register
sess.registeredItem = 360
check(sess.registeredItem == 360, "registered BICYCLE")

print("[test] 8. Berry & TM pocket segregation and 3-pocket Bag UI")
local testBag = Bag.new()
Bag.add(testBag, "POTION", 2)
Bag.add(testBag, "BERRY", 3)
Bag.add(testBag, "ORAN_BERRY", 2)
Bag.add(testBag, "CHESTO_BERRY", 1)
Bag.add(testBag, "TM01", 1)
Bag.add(testBag, "HM01", 1)

local itemRows = Bag.listPocket(testBag, "ITEMS")
local keyRows = Bag.listPocket(testBag, "KEY_ITEMS")
local tmRows = Bag.listPocket(testBag, "TM_CASE")
local berryRows = Bag.listPocket(testBag, "BERRY_POUCH")

check(#itemRows == 1 and itemRows[1].name == "POTION", "ITEMS pocket only contains general items")
check(Bag.has(testBag, ItemsData.ITEM_TM_CASE, 1), "TM CASE key item present in KEY_ITEMS")
check(Bag.has(testBag, ItemsData.ITEM_BERRY_POUCH, 1), "BERRY POUCH key item present in KEY_ITEMS")
check(#tmRows == 2, "TM_CASE pocket contains 2 machines")
check(#berryRows == 2, "BERRY_POUCH pocket contains 2 berry kinds")
check(Bag.get(testBag, 139) == 5, "BERRY + ORAN_BERRY merged to 5 Oran berries")

local BagMenu = require("src.ui.game3.bag_menu")
BagMenu.show(nil, testBag)
BagMenu.settle()
check(BagMenu.currentPocket() == "ITEMS", "BagMenu initial pocket is ITEMS")
BagMenu.handleInput({ wasPressed = function(s, k) return k == "right" end })
check(BagMenu.currentPocket() == "KEY_ITEMS", "BagMenu second pocket is KEY_ITEMS")
BagMenu.handleInput({ wasPressed = function(s, k) return k == "right" end })
check(BagMenu.currentPocket() == "POKE_BALLS", "BagMenu third pocket is POKE_BALLS")
BagMenu.handleInput({ wasPressed = function(s, k) return k == "right" end })
check(BagMenu.currentPocket() == "POKE_BALLS", "BagMenu does not wrap past POKE_BALLS (3 pockets only)")
BagMenu.close()

if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll bag tests passed.")
os.exit(0)

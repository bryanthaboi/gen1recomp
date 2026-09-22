-- Test suite for ItemUse and Oak's Lab parcel delivery scene.

require("tests.game3_cache").requireData("game3_item_use_and_parcel_test")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Space = require("src.core.game3.scripting.space")

print("[test] 1. ItemUse.needsPartyTarget")
assert(ItemUse.needsPartyTarget("POTION") == true, "Potion needs party target")
assert(ItemUse.needsPartyTarget(13) == true, "Potion numeric ID needs party target")
assert(ItemUse.needsPartyTarget("SUPER_POTION") == true, "Super Potion needs party target")
assert(ItemUse.needsPartyTarget("ANTIDOTE") == true, "Antidote needs party target")
assert(ItemUse.needsPartyTarget("REVIVE") == true, "Revive needs party target")
assert(ItemUse.needsPartyTarget("RARE_CANDY") == true, "Rare Candy needs party target")
assert(ItemUse.needsPartyTarget("FIRE_STONE") == true, "Fire Stone needs party target")
assert(ItemUse.needsPartyTarget("TM01") == true, "TM01 needs party target")
assert(ItemUse.needsPartyTarget("BICYCLE") == false, "Bicycle does not need party target")
assert(ItemUse.needsPartyTarget("ESCAPE_ROPE") == false, "Escape rope does not need party target")
assert(ItemUse.needsPartyTarget("REPEL") == false, "Repel does not need party target")
print("[ok] needsPartyTarget correctly identifies party items vs field items")

print("[test] 2. ItemUse on party Pokémon")
Pokemon.install(nil)
local session = {
  name = "RED",
  party = {
    {
      species = 1, -- Bulbasaur
      speciesId = 1,
      level = 5,
      hp = 10,
      maxHp = 20,
      status = "PSN",
      sleep = 0,
      moves = { { id = 33, pp = 35 } },
    },
    {
      species = 4, -- Charmander
      speciesId = 4,
      level = 5,
      hp = 0,
      maxHp = 19,
      moves = { { id = 10, pp = 35 } },
    }
  }
}
local bag = Bag.new()
Bag.add(bag, "POTION", 2)
Bag.add(bag, "ANTIDOTE", 1)
Bag.add(bag, "REVIVE", 1)
Bag.add(bag, "RARE_CANDY", 1)

-- Heal Mon 1 with Potion
local ok, res = ItemUse.useField(session, bag, "POTION", 1)
assert(ok == true, "Potion used successfully")
assert(session.party[1].hp == 20, "HP restored to max (10+20 capped at 20)")
assert(Bag.get(bag, "POTION") == 1, "1 Potion remaining in bag")

-- Clear status on Mon 1 with Antidote
ok, res = ItemUse.useField(session, bag, "ANTIDOTE", 1)
assert(ok == true, "Antidote used successfully")
assert(session.party[1].status == nil, "Poison cleared")
assert(Bag.get(bag, "ANTIDOTE") == 0, "Antidote consumed")

-- Revive Mon 2
ok, res = ItemUse.useField(session, bag, "REVIVE", 2)
assert(ok == true, "Revive used successfully")
assert(session.party[2].hp == 9, "Half HP restored on faint mon")
assert(Bag.get(bag, "REVIVE") == 0, "Revive consumed")

-- Rare Candy Mon 1
ok, res = ItemUse.useField(session, bag, "RARE_CANDY", 1)
assert(ok == true, "Rare Candy used successfully")
assert(session.party[1].level == 6, "Level increased to 6")
assert(Bag.get(bag, "RARE_CANDY") == 0, "Rare Candy consumed")

print("[ok] party healing, status cure, reviving, and rare candy all passed")

print("[test] 3. VAR_FACING preservation in Vm")
local vm = Vm.new({
  store = Flags.newStore(),
  scripts = {
    test_facing = {
      { op = "compare_var_to_value", var = Ctx.VAR_FACING, value = 2 },
      { op = "call_if", cond = 1, target = "matched_north" },
      { op = "end" },
    },
    matched_north = {
      { op = "setvar", var = 0x4000, value = 99 },
      { op = "return" },
    }
  }
})
vm:startTalk("test_facing", 1, 2) -- Facing DIR_NORTH (2)
assert(Flags.getVar(vm.store, vm.ctx, 0x4000) == 99, "VAR_FACING branch correctly executed")
print("[ok] VAR_FACING correctly passed and matched conditional branches")

print("[test] 4. Script extraction chunk size and complete ReceiveDexScene")
local Dataset = require("src.core.game3.dataset")
Dataset.mountExtractRoots()
local bundle = Space.ensureBundle(nil)
assert(bundle and bundle.scripts, "Bundle scripts exist")
local receiveDex = bundle.scripts["g3:0816961e"]
assert(receiveDex, "ReceiveDexScene script exists in bundle")
local lastOp = receiveDex[#receiveDex]
assert(lastOp and lastOp.op == "end", "ReceiveDexScene ends with 'end' (not truncated mid-script)")

-- Check that the end of ReceiveDexScene contains removeobject (8) and setvar (PALLET_TOWN_PROFESSOR_OAKS_LAB = 6)
local hasRemoveObject8 = false
local hasSetVarOakLab = false
for _, row in ipairs(receiveDex) do
  if row.op == "removeobject" and (row.localId == 8 or row[1] == 8) then
    hasRemoveObject8 = true
  end
  if row.op == "setvar" and (row.var == 0x4055 or row[1] == 0x4055 or row.var == 16469 or row[1] == 16469) and (row.value == 6 or row[2] == 6) then
    hasSetVarOakLab = true
  end
end
assert(hasRemoveObject8, "ReceiveDexScene contains removeobject 8 (Rival exits)")
assert(hasSetVarOakLab, "ReceiveDexScene contains setvar VAR_MAP_SCENE_PALLET_TOWN_PROFESSOR_OAKS_LAB, 6")
print("[ok] ReceiveDexScene is fully extracted and non-truncated")

print("[test] 5. PartyMenu item usage, give, take, and message dismiss")
local PartyMenu = require("src.ui.game3.party_menu")
local BagMenu = require("src.ui.game3.bag_menu")

-- Setup mock input
local mockInput = {
  _pressed = {},
  wasPressed = function(self, key) return self._pressed[key] == true end,
  press = function(self, key) self._pressed = { [key] = true } end,
  clear = function(self) self._pressed = {} end,
}

-- Test Give to Mon
local testParty = {
  { species = 1, hp = 10, maxHp = 20, level = 5 },
  { species = 4, hp = 19, maxHp = 19, level = 5 },
}
local testBag = Bag.new()
Bag.add(testBag, "ORAN_BERRY", 2)
Bag.add(testBag, "POTION", 1)

local closed = false
PartyMenu.show(testParty, nil, {
  session = { party = testParty, bag = testBag },
  bag = testBag,
  item = "ORAN_BERRY",
  mode = "give",
  onClose = function() closed = true end,
})
assert(PartyMenu.isOpen() == true, "PartyMenu is open")
assert(PartyMenu.mode == "give", "PartyMenu is in give mode")

-- Press A on Mon 1 to give item
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu.mode == "message", "Transitions to message mode with give result")
assert(testParty[1].heldItem ~= nil, "Mon 1 now holds item")
assert(Bag.get(testBag, "ORAN_BERRY") == 1, "1 berry consumed from bag")

-- Press A to dismiss message -> should close and invoke onClose
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu.isOpen() == false, "PartyMenu closed after give message dismissed")
assert(closed == true, "onClose invoked")

-- Test Take from Mon via ItemUse
local takeOk, _, takeMsg = ItemUse.takeFromMon({ party = testParty }, testBag, 1)
assert(takeOk == true, "takeFromMon succeeds")
assert(testParty[1].heldItem == nil, "Item taken from Mon 1")
assert(Bag.get(testBag, "ORAN_BERRY") == 2, "Berry returned to bag")

-- Test Use Potion via PartyMenu
PartyMenu.show(testParty, nil, {
  session = { party = testParty, bag = testBag },
  bag = testBag,
  item = "POTION",
  mode = "use",
})
assert(PartyMenu.mode == "use", "PartyMenu is in use mode")
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu._hpAnim ~= nil, "HP bar animation started")
-- Step animation to completion
PartyMenu.update(1.0)
assert(PartyMenu._hpAnim == nil, "HP bar animation completed")
assert(PartyMenu.mode == "message", "Transitions to message mode showing heal")
assert(testParty[1].hp == 20, "Mon 1 healed to full 20 HP")
assert(Bag.get(testBag, "POTION") == 0, "Potion consumed")

-- Dismiss message (depleted potion -> closes)
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu.isOpen() == false, "PartyMenu closed after single potion used")
print("[ok] PartyMenu item use, give, take, and message lifecycle passed")

print("[test] 6. BagMenu USE Potion opens PartyMenu and heals with HP lerp")
testParty[1].hp = 5
Bag.add(testBag, "POTION", 1)
BagMenu.show({ party = testParty, bag = testBag }, { bag = testBag })
assert(BagMenu.isOpen() == true, "BagMenu is open")
BagMenu.settle()
BagMenu.mode = "action"
BagMenu.actionCursor = 1 -- USE
mockInput:press("a")
BagMenu.handleInput(mockInput)
BagMenu.settle()
assert(PartyMenu.isOpen() == true, "PartyMenu opened from BagMenu USE")
assert(PartyMenu.mode == "use", "PartyMenu is in use mode")
-- Select Mon 1 with A
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu._hpAnim ~= nil, "PartyMenu HP animation active")
PartyMenu.update(1.0)
assert(PartyMenu.mode == "message", "PartyMenu shows heal message")
assert(testParty[1].hp == 20, "Mon 1 healed to 20")
-- Dismiss message
mockInput:press("a")
PartyMenu.handleInput(mockInput)
assert(PartyMenu.isOpen() == false, "PartyMenu closed after potion used")
assert(BagMenu.mode == "list", "BagMenu returned to list mode")
print("[ok] BagMenu USE Potion -> PartyMenu -> heal passed")

print("[test] 7. Ground item ball pickup via std:1 sets object flag and removes object")
local Space = require("src.core.game3.scripting.space")
local Objects = require("src.core.game3.objects")
local Flags = require("src.core.game3.scripting.flags")

Space.store = Flags.newStore()
Space.active = true

local itemBallDef = {
  localId = 5,
  index = 5,
  x = 17,
  y = 54,
  flag = 340,
  graphics = 92,
  graphicsId = 92,
  sprite = "SPRITE_POKE_BALL",
  scriptKey = "test_item_ball",
}
Objects.loadMap(nil, "TEST_MAP", { objects = { itemBallDef } })
local spawned = Objects.find(5)
assert(spawned ~= nil, "Item ball spawned")
assert(spawned.visible == true, "Item ball initially visible")
assert(Space.objectVisible(itemBallDef) == true, "objectVisible true before pickup")

local testItemScript = {
  { op = "setorcopyvar", [1] = 0x8000, [2] = 34 }, -- Great Ball
  { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
  { op = "callstd", [1] = 1, std = 1 },
  { op = "end" },
}

local Field = require("src.core.game3.field")
Field._session = { bag = testBag }

local Adapters = require("src.core.game3.scripting.adapters")
local adapters = Adapters.host(nil, nil, nil)
Space.vm = Vm.new({
  store = Space.store,
  scripts = { test_item_ball = testItemScript },
  adapters = adapters,
})

local prevCount = Bag.get(testBag, 34) or 0
Space.startScript("test_item_ball", 5, 1)

assert(Bag.get(testBag, 34) == prevCount + 1, "Great Ball added to bag")
assert(Flags.getFlag(Space.store, nil, 340) == true, "Flag 340 set by item pickup")
assert(spawned.visible == false, "Item ball object hidden")
assert(Space.objectVisible(itemBallDef) == false, "objectVisible false after pickup")
print("[ok] Ground item pickup sets flag and removes object")

print("[test] all passed successfully!")


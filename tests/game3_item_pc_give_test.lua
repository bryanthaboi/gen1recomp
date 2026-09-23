#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i) return n .. "[" .. i .. "]" end, at = function(n, i) return n .. "[" .. i .. "]" end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}
package.loaded["src.ui.game3.stack"] = { push = function() end, pop = function() end, busy = function() return false end, drawOrder = function() return {} end }
package.loaded["src.core.game3.audio"] = { playSe = function() end, playCry = function() end }
local quest = {}
package.loaded["src.core.game3.quest_log_recorder"] = { event = function(_, key, args) quest[#quest + 1] = { key = key, args = args } end }

local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local ItemsData = require("src.core.game3.items_data")

local shown
package.loaded["src.ui.game3.party_menu"] = {
  show = function(_, _, opts) shown = opts end,
}
local ItemPc = require("src.ui.game3.item_pc")

local failures = 0
local function check(cond, msg)
  if cond then print("[PASS] " .. msg) else failures = failures + 1; print("[FAIL] " .. msg) end
end

local function fakeInput(pressed)
  return { wasPressed = function(_, k) return k == pressed end, isDown = function() return false end }
end
local function step(pressed) ItemPc.handleInput(fakeInput(pressed)) end

local POTION = ItemsData.toNumericId("POTION")
local ANTIDOTE = ItemsData.toNumericId("ANTIDOTE")

local function pcQty(session, id)
  for _, e in ipairs(Storage.ensure(session).items) do
    if e.id == id then return e.qty end
  end
  return 0
end

local function openGive(session)
  shown = nil
  ItemPc.show({ session = session })
  for _ = 1, 40 do step(nil) end
  step("a")
  step("down")
  step("a")
  return shown
end

local function newSession(held, pcItems, bagFill)
  local bag = Bag.new()
  for id, qty in pairs(bagFill or {}) do Bag.add(bag, id, qty) end
  local session = { bag = bag, party = { { species = 1, speciesId = 1, level = 5, hp = 20, maxHp = 20, item = held, nickname = "BULBA" } } }
  Storage.ensure(session).items = pcItems
  return session
end

-- src/party_menu.c:5487 GiveItemToSelectedMon
do
  local s = newSession(nil, { { id = POTION, qty = 2 } }, { [POTION] = 1 })
  local opts = openGive(s)
  check(opts and opts.mode == "give" and opts.giveSource, "item PC GIVE opens the party menu with a PC give source")
  check(pcQty(s, POTION) == 2 and Bag.get(s.bag, POTION) == 1, "nothing moves before a mon is chosen")
  check(ItemUse.checkGive(s, POTION, 1) == "give", "empty-handed mon takes the item directly")
  quest = {}
  local txt = ItemUse.giveHeld(s, s.bag, POTION, 1, opts.giveSource)
  opts.onClose()
  check(txt == "gText_PkmnWasGivenItem", "given message")
  check(pcQty(s, POTION) == 1 and Bag.get(s.bag, POTION) == 1 and s.party[1].item == POTION, "held none: PC -1, bag unchanged, mon holds POTION")
  check(quest[1] and quest[1].key == "GaveMonHeldItemFromPC", "quest log records GaveMonHeldItemFromPC")
end

-- src/party_menu.c:5563 Task_HandleSwitchItemsFromBagYesNoInput
do
  local s = newSession(POTION, { { id = POTION, qty = 2 } }, { [POTION] = 1 })
  local opts = openGive(s)
  local kind, prev, prompt = ItemUse.checkGive(s, POTION, 1)
  check(kind == "switch" and prev == POTION and prompt == "gText_PkmnAlreadyHoldingItemSwitch", "held same: asks to switch")
  local ok, txt = ItemUse.switchHeld(s, s.bag, POTION, 1, opts.giveSource)
  opts.onClose()
  check(ok and txt == "gText_SwitchedPkmnItem", "switched message")
  check(pcQty(s, POTION) == 1 and Bag.get(s.bag, POTION) == 2 and s.party[1].item == POTION, "held same: PC -1, bag +1")
end

do
  local s = newSession(ANTIDOTE, { { id = POTION, qty = 1 }, { id = ANTIDOTE, qty = 3 } }, {})
  local opts = openGive(s)
  local ok = ItemUse.switchHeld(s, s.bag, POTION, 1, opts.giveSource)
  opts.onClose()
  check(ok and pcQty(s, POTION) == 0 and #Storage.ensure(s).items == 1, "held other: last PC POTION leaves the list")
  check(Bag.get(s.bag, ANTIDOTE) == 1 and s.party[1].item == POTION and pcQty(s, ANTIDOTE) == 3, "held other: old item to bag, PC ANTIDOTE untouched")
end

do
  local s = newSession(POTION, { { id = POTION, qty = 2 } }, { [POTION] = 1 })
  openGive(s)
  shown.onClose()
  check(pcQty(s, POTION) == 2 and Bag.get(s.bag, POTION) == 1 and s.party[1].item == POTION, "cancel/No: nothing changes")
end

local function fullItemsBag()
  local bag = Bag.new()
  local n = 0
  for id = 1, 400 do
    if n >= 42 then break end
    if id ~= POTION and id ~= ANTIDOTE and ItemsData.pocketOf(id) == "ITEMS" and ItemsData.toNumericId(id) ~= 0 then
      if Bag.add(bag, id, 1) then n = n + 1 end
    end
  end
  return bag
end

do
  local s = newSession(nil, { { id = POTION, qty = 1 } }, {})
  s.bag = fullItemsBag()
  check(not Bag.canAdd(s.bag, POTION, 1), "fixture: ITEMS pocket is full")
  local opts = openGive(s)
  ItemUse.giveHeld(s, s.bag, POTION, 1, opts.giveSource)
  opts.onClose()
  check(pcQty(s, POTION) == 0 and s.party[1].item == POTION, "full bag: PC item still reaches the mon")
end

do
  local s = newSession(ANTIDOTE, { { id = POTION, qty = 1 } }, {})
  s.bag = fullItemsBag()
  local opts = openGive(s)
  local ok, txt = ItemUse.switchHeld(s, s.bag, POTION, 1, opts.giveSource)
  opts.onClose()
  check(not ok and txt == "gText_BagFullCouldNotRemoveItem", "full bag switch: refused with bag-full text")
  check(pcQty(s, POTION) == 1 and Storage.ensure(s).items[1].id == POTION and s.party[1].item == ANTIDOTE, "full bag switch: PC item returned to its slot, mon keeps its item")
end

-- src/party_menu.c:5455 TryGiveItemOrMailToSelectedMon
do
  local s = newSession(121, { { id = POTION, qty = 1 } }, {})
  check(ItemUse.checkGive(s, POTION, 1) == "mail", "mail holder: must remove mail first")
end

do
  local s = newSession(ANTIDOTE, {}, { [POTION] = 1 })
  quest = {}
  local ok = ItemUse.switchHeld(s, s.bag, POTION, 1)
  check(ok and Bag.get(s.bag, POTION) == 0 and Bag.get(s.bag, ANTIDOTE) == 1 and s.party[1].item == POTION, "bag switch: bag -POTION +ANTIDOTE")
  check(quest[1] and quest[1].key == "SwappedHeldItemsOnMon", "bag switch quest event")
  s = newSession(nil, {}, { [POTION] = 1 })
  quest = {}
  ItemUse.giveHeld(s, s.bag, POTION, 1)
  check(Bag.get(s.bag, POTION) == 0 and quest[1] and quest[1].key == "GaveMonHeldItem2", "bag give: GaveMonHeldItem2")
  -- src/party_menu.c:1579
  s = newSession(nil, {}, { [POTION] = 1 })
  quest = {}
  ItemUse.giveHeld(s, s.bag, POTION, 1, ItemUse.partyGiveSource(s.bag))
  check(Bag.get(s.bag, POTION) == 0 and quest[1] and quest[1].key == "GaveMonHeldItem", "party ITEM>GIVE: GaveMonHeldItem")
end

-- src/item_menu.c:1563 Task_WaitAB_RedrawAndReturnToBag
do
  local s = newSession(nil, {}, { [POTION] = 3 })
  check(Storage.addPcItem(s, POTION, 2) and pcQty(s, POTION) == 2 and Bag.get(s.bag, POTION) == 3, "addPcItem adds to the PC without touching the bag")
  Storage.ensure(s).items = { { id = POTION, qty = 998 } }
  check(not Storage.addPcItem(s, POTION, 2) and pcQty(s, POTION) == 998, "addPcItem refuses a stack past 999")
end

-- src/party_menu.c:5554 Task_SwitchItemsFromBagYesNo
do
  package.loaded["src.ui.game3.party_menu"] = nil
  local PartyMenu = require("src.ui.game3.party_menu")
  local function press(k) PartyMenu.handleInput(fakeInput(k)) end
  local s = newSession(ANTIDOTE, {}, { [POTION] = 1 })
  s.party[2] = { species = 1, speciesId = 1, level = 5, hp = 20, maxHp = 20, isEgg = true }
  local closed = 0
  local function open()
    PartyMenu.show(s.party, nil, { session = s, bag = s.bag, item = POTION, mode = "give", onClose = function() closed = closed + 1 end })
  end
  open()
  press("a")
  check(PartyMenu.mode == "yesno" and PartyMenu._yesNoPrompt == "gText_PkmnAlreadyHoldingItemSwitch", "party give: holder gets the switch Yes/No")
  press("down")
  press("a")
  check(closed == 1 and s.party[1].item == ANTIDOTE and Bag.get(s.bag, POTION) == 1, "party give: No closes without switching")
  open()
  press("a")
  press("a")
  check(PartyMenu.mode == "message" and PartyMenu._messageText == "gText_SwitchedPkmnItem", "party give: Yes shows the switched message")
  check(s.party[1].item == POTION and Bag.get(s.bag, POTION) == 0 and Bag.get(s.bag, ANTIDOTE) == 1, "party give: Yes switches through the bag")
  press("a")
  check(closed == 2, "party give: message dismiss closes")
  Bag.add(s.bag, POTION, 1)
  open()
  PartyMenu.cursor = 2
  press("a")
  check(PartyMenu.mode == "give" and PartyMenu.isOpen() and Bag.get(s.bag, POTION) == 1, "party give: egg only buzzes and stays in the chooser")
end

-- src/party_menu.c:3424 CB2_SelectBagItemToGive
do
  package.loaded["src.ui.game3.party_menu"] = nil
  local PartyMenu = require("src.ui.game3.party_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local s = newSession(nil, {}, { [POTION] = 1 })
  local function give_from_bag(location)
    local opened
    local realShow = PartyMenu.show
    PartyMenu.show = function(party, overlay, opts) opened = opts; return realShow(party, overlay, opts) end
    BagMenu.show(s, { bag = s.bag, location = location })
    BagMenu._open = nil
    BagMenu.mode = "action"
    BagMenu.actionCursor = 2
    BagMenu.handleInput(fakeInput("a"))
    BagMenu.settle()
    PartyMenu.show = realShow
    BagMenu.close()
    return opened
  end
  local opts = give_from_bag("party")
  check(opts and opts.mode == "give" and opts.giveSource ~= nil, "party-location bag GIVE opens the chooser with the party source")
  quest = {}
  if opts and opts.giveSource then ItemUse.giveHeld(s, s.bag, POTION, 1, opts.giveSource) end
  check(quest[1] and quest[1].key == "GaveMonHeldItem", "party-location bag GIVE logs GaveMonHeldItem")
  PartyMenu.close()
  s.party[1].item = nil
  Bag.add(s.bag, POTION, 1)
  opts = give_from_bag(nil)
  check(opts and opts.mode == "give" and opts.giveSource == nil, "plain bag GIVE keeps the bag source")
end

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("PASS game3_item_pc_give_test")

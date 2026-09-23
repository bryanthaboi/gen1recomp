-- Automated Test Suite for Game 3 FRLG PC & Pokémon Storage System.
require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")
local Catching = require("src.core.game3.battle/catching")
local PcMenu = require("src.ui.game3.pc_menu")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")
local ReleaseSeq = require("src.ui.game3.release_seq")
local SummaryMenu = require("src.ui.game3.summary_menu")
local Dex = require("src.core.game3.dex")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", msg or "", tostring(b), tostring(a)), 2)
  end
end

local function assert_true(val, msg)
  if not val then
    error(string.format("ASSERTION FAILED: %s (expected true, got %s)", msg or "", tostring(val)), 2)
  end
end

local function assert_false(val, msg)
  if val then
    error(string.format("ASSERTION FAILED: %s (expected false, got %s)", msg or "", tostring(val)), 2)
  end
end

local function make_input(pressedMap)
  pressedMap = pressedMap or {}
  return {
    wasPressed = function(self, key) return pressedMap[key] == true end,
    isDown = function(self, key) return pressedMap[key] == true end,
  }
end

print("=== [TEST 1] Storage Initialization (14 Boxes × 30 Slots = 420 Capacity, 50-Slot Item PC) ===")
local s = Storage.new()
assert_eq(#s.boxes, 14, "14 boxes initialized")
assert_eq(s.currentBox, 1, "Initial currentBox is 1")
assert_eq(Storage.countTotalMons(s), 0, "Initial mon count is 0")
for b = 1, 14 do
  assert_eq(s.boxes[b].name, string.format("BOX %d", b), "Box name correct")
  assert_eq(s.boxes[b].wallpaper, ((b - 1) % 16) + 1, "Box wallpaper initialized")
  assert_eq(Storage.countBoxMons(s, b), 0, "Box starts empty")
end
assert_eq(#s.items, 1, "PC starts with 1 item (Potion)")
assert_eq(s.items[1].id, 13, "PC starts with Potion (id 13)")
assert_eq(s.items[1].qty, 1, "PC starts with 1 Potion")
print("[ok] 14 boxes and 50-slot PC initialized successfully")

print("=== [TEST 2] The PC Heal Exploit ===")
-- Create damaged, status-afflicted, low PP mon
local sickMon = {
  species = 25, -- PIKACHU
  level = 20,
  hp = 1,
  maxHp = 50,
  status = "POISON",
  statusAilment = "PSN",
  fainted = false,
  moves = {
    { id = 85, pp = 0, maxPp = 15 }, -- THUNDERBOLT
    { id = 98, pp = 2, maxPp = 30 }, -- QUICK ATTACK
  },
}
local session = {
  name = "RED",
  party = {
    { species = 1, level = 10, hp = 30, maxHp = 30 },
    sickMon,
  },
  storage = Storage.new(),
  bag = Bag.new(),
}

-- Deposit Pikachu (party slot 2) into Box 1
local okDep, bId, sId = Storage.deposit(session, 2, 1)
assert_true(okDep, "Pikachu deposited into Box 1")
assert_eq(#session.party, 1, "Party has 1 mon left")
assert_eq(Storage.countBoxMons(session.storage, 1), 1, "Box 1 has 1 mon")

-- Verify Pikachu is completely healed
local boxedMon = Storage.getBoxMon(session.storage, 1, sId)
assert_eq(boxedMon.hp, 50, "HP fully restored to 50")
assert_eq(boxedMon.moves[1].pp, 15, "Move 1 PP fully restored to 15")
assert_eq(boxedMon.moves[2].pp, 30, "Move 2 PP fully restored to 30")
assert_eq(boxedMon.status, nil, "Poison status condition cleared")
assert_eq(boxedMon.statusAilment, nil, "Status ailment cleared")
print("[ok] PC Heal Exploit verified: HP, PP, and status fully restored upon deposit")

print("=== [TEST 3] Party Deposit / Withdraw Boundary Rules ===")
-- Prevent depositing last Pokémon
local okLast, errLast = Storage.deposit(session, 1, 1)
assert_false(okLast, "Cannot deposit last remaining party Pokémon")
assert_eq(errLast, "last_pokemon", "Error is last_pokemon")

-- Withdraw Pikachu back to party
local okWd, pIdx = Storage.withdraw(session, 1, sId)
assert_true(okWd, "Withdrew Pikachu to party")
assert_eq(#session.party, 2, "Party has 2 mons")
assert_eq(Storage.countBoxMons(session.storage, 1), 0, "Box 1 is empty again")

-- Fill party to 6 mons
for i = 3, 6 do
  session.party[i] = { species = i, level = 5, hp = 20, maxHp = 20 }
end
assert_eq(#session.party, 6, "Party is full (6 mons)")

-- Deposit 1 mon to box, then try to withdraw when party is full
Storage.deposit(session, 6, 1)
assert_eq(#session.party, 5, "Party has 5 mons")
session.party[6] = { species = 99, level = 5, hp = 20, maxHp = 20 } -- refill to 6
local okWdFull, errWdFull = Storage.withdraw(session, 1, 1)
assert_false(okWdFull, "Cannot withdraw into full party")
assert_eq(errWdFull, "party_full", "Error is party_full")
print("[ok] Deposit/withdraw boundary rules passed")

print("=== [TEST 4] Circular Automatic Spillover across 14 Boxes (420 Mons) ===")
local spillSession = {
  name = "ASH",
  party = {
    { species = 25, level = 50, hp = 100, maxHp = 100 },
    { species = 1, level = 50, hp = 100, maxHp = 100 },
    { species = 4, level = 50, hp = 100, maxHp = 100 },
    { species = 7, level = 50, hp = 100, maxHp = 100 },
    { species = 16, level = 50, hp = 100, maxHp = 100 },
    { species = 19, level = 50, hp = 100, maxHp = 100 },
  },
  storage = Storage.new(),
  dex = Dex.new(),
}
assert_eq(#spillSession.party, 6, "Party is full (6)")

-- Fill Box 1 completely (30 slots)
for s = 1, 30 do
  spillSession.storage.boxes[1].mons[s] = { species = 10, level = 3, hp = 15, maxHp = 15 }
end
assert_eq(Storage.countBoxMons(spillSession.storage, 1), 30, "Box 1 is full (30 mons)")

-- Catch wild Caterpie (species 10) with full party and full Box 1
local foe = { species = 10, mon = { species = 10, level = 4, hp = 5, maxHp = 16 } }
local resCatch = Catching.storeCaught(spillSession, foe, 4)
assert_true(resCatch.success, "Catch successful")
assert_eq(resCatch.location, "pc", "Sent to PC storage")
assert_eq(resCatch.box, 2, "Silently spilled over to Box 2")
assert_eq(resCatch.slot, 1, "Placed in Box 2 Slot 1")
assert_eq(Storage.countBoxMons(spillSession.storage, 2), 1, "Box 2 received mon")

-- Test full 420-slot storage capacity
for b = 1, 14 do
  for sl = 1, 30 do
    spillSession.storage.boxes[b].mons[sl] = { species = 1, level = 5, hp = 20, maxHp = 20 }
  end
end
assert_eq(Storage.countTotalMons(spillSession.storage), 420, "All 420 box slots filled")
local bOpen, sOpen = Storage.findOpenSlot(spillSession.storage)
assert_eq(bOpen, nil, "findOpenSlot returns nil when all 420 slots full")

local resFull = Catching.storeCaught(spillSession, foe, 4)
assert_false(resFull.success, "Catch rejected when all 420 slots full")
assert_eq(resFull.reason, "storage_full", "Reason is storage_full")
print("[ok] Circular automatic spillover and 420-mon cap verified")

print("=== [TEST 5] Player PC 50-Item Storage Capacity & Bag Interop ===")
local pcItemSession = {
  bag = Bag.new(),
  storage = Storage.new(),
}
pcItemSession.storage.items = {}
-- Give 50 Poké Balls to Bag
Bag.add(pcItemSession.bag, 4, 50) -- POKE_BALL = 4
assert_eq(Bag.get(pcItemSession.bag, 4), 50, "Bag has 50 Poké Balls")

-- Deposit 20 Poké Balls into PC
local okDepItem = Storage.depositItem(pcItemSession, "POKE_BALLS", 1, 20)
assert_true(okDepItem, "Deposited 20 Poké Balls into PC")
assert_eq(Bag.get(pcItemSession.bag, 4), 30, "Bag now has 30 Poké Balls")
assert_eq(#pcItemSession.storage.items, 1, "PC items list has 1 entry")
assert_eq(pcItemSession.storage.items[1].qty, 20, "PC holds 20 Poké Balls")

-- Withdraw 5 Poké Balls back to Bag
local okWdItem = Storage.withdrawItem(pcItemSession, 1, 5)
assert_true(okWdItem, "Withdrew 5 Poké Balls from PC")
assert_eq(Bag.get(pcItemSession.bag, 4), 35, "Bag now has 35 Poké Balls")
assert_eq(pcItemSession.storage.items[1].qty, 15, "PC holds 15 Poké Balls")

-- Toss 5 Poké Balls from PC
local okToss = Storage.tossItem(pcItemSession, 1, 5)
assert_true(okToss, "Tossed 5 Poké Balls from PC")
assert_eq(pcItemSession.storage.items[1].qty, 10, "PC holds 10 Poké Balls")

-- Test 50 unique items cap
for i = 1, 50 do
  pcItemSession.storage.items[i] = { id = i, qty = 10 }
end
assert_eq(#pcItemSession.storage.items, 50, "PC holds 50 unique items")
Bag.add(pcItemSession.bag, 99, 1)
local ok51, err51 = Storage.depositItem(pcItemSession, "ITEMS", 1, 1)
assert_false(ok51, "Cannot deposit 51st unique item into PC")
assert_eq(err51, "pc_items_full", "Error is pc_items_full")
print("[ok] Player PC 50-item storage and bag interop passed")

print("=== [TEST 6] Move Items Bag-Full Protection ===")
local heldMon = {
  species = 25,
  level = 20,
  heldItem = 13, -- POTION = 13
}
local fullBagSession = {
  bag = Bag.new(),
  storage = Storage.new(),
}
-- Fill Items pocket (42 items cap) with unique items from ITEMS pocket
for i = 1, 42 do
  Bag.add(fullBagSession.bag, 13 + i, 1)
end
assert_false(Bag.canAdd(fullBagSession.bag, 13, 1), "Bag items pocket is completely full")

-- Attempt to detach item when bag is full
local okDetachFull, errDetachFull = Storage.detachHeldItem(fullBagSession, heldMon)
assert_false(okDetachFull, "Item detachment blocked when Bag is full")
assert_eq(errDetachFull, "bag_full", "Error reason is bag_full")
assert_eq(heldMon.heldItem, 13, "Held item was preserved on mon without being voided")

-- Make room in bag and detach
Bag.remove(fullBagSession.bag, 14, 1)
local okDetachSpace, detachedId = Storage.detachHeldItem(fullBagSession, heldMon)
assert_true(okDetachSpace, "Item successfully detached when Bag has space")
assert_eq(detachedId, 13, "Detached item was Potion")
assert_eq(heldMon.heldItem, nil, "Mon held item cleared")
assert_eq(Bag.get(fullBagSession.bag, 13), 1, "Bag received Potion")
print("[ok] Move Items bag-full protection verified")

print("=== [TEST 7] The Emotional Release Sequence Animation ===")
local relSession = {
  storage = Storage.new(),
}
relSession.storage.boxes[1].mons[1] = { species = 25, level = 10, nickname = "SPARKY" }
local seqDone = false
ReleaseSeq.start({
  session = relSession,
  mon = relSession.storage.boxes[1].mons[1],
  boxId = 1,
  slotIdx = 1,
  onComplete = function(released) seqDone = released end,
})
assert_true(ReleaseSeq.isActive(), "Release sequence active")
assert_eq(ReleaseSeq.state, "confirm", "Initial state is confirm")

-- Confirm YES
ReleaseSeq.handleInput(make_input({ up = true }))
assert_eq(ReleaseSeq.yesNoCursor, 1, "YES selected")
ReleaseSeq.handleInput(make_input({ a = true }))
assert_eq(ReleaseSeq.state, "anim", "Entered upward float/shrink animation state")

-- Tick animation past 0.8s
ReleaseSeq.update(1.0)
assert_eq(ReleaseSeq.state, "released", "Entered 'SPARKY was released.' state")
assert_eq(relSession.storage.boxes[1].mons[1], nil, "Box slot data cleared")

ReleaseSeq.handleInput(make_input({ a = true }))
assert_eq(ReleaseSeq.state, "bye", "Entered 'Bye-bye, SPARKY!' state")

-- Dismiss dialogue
ReleaseSeq.handleInput(make_input({ a = true }))
assert_false(ReleaseSeq.isActive(), "Release sequence completed")
assert_true(seqDone, "Callback fired with released = true")
print("[ok] Emotional Release sequence animation state machine passed")

print("=== [TEST 8] Sparse Serialization & Deserialization Footprint ===")
local sparseStorage = Storage.new()
sparseStorage.boxes[1].mons[3] = { species = 1, level = 5 }
sparseStorage.boxes[1].mons[15] = { species = 4, level = 5 }
sparseStorage.boxes[3].mons[1] = { species = 7, level = 5 }
sparseStorage.items[1] = { id = 4, qty = 20 }

local serialized = Storage.serialize(sparseStorage)
assert_true(serialized ~= nil, "Serialized table generated")
assert_eq(serialized.boxes[2], nil, "Empty Box 2 completely omitted from serialization")
assert_eq(serialized.boxes[4], nil, "Empty Box 4 completely omitted from serialization")
assert_eq(#serialized.items, 1, "Serialized 1 item entry")
assert_true(serialized.boxes[1].mons[3] ~= nil, "Box 1 Slot 3 present")
assert_true(serialized.boxes[1].mons[15] ~= nil, "Box 1 Slot 15 present")
assert_true(serialized.boxes[3].mons[1] ~= nil, "Box 3 Slot 1 present")

-- Restore from sparse data
local deserialized = Storage.deserialize(serialized)
assert_eq(#deserialized.boxes, 14, "Deserialized all 14 boxes")
assert_eq(deserialized.boxes[1].mons[3].species, 1, "Restored Box 1 Slot 3")
assert_eq(deserialized.boxes[1].mons[15].species, 4, "Restored Box 1 Slot 15")
assert_eq(deserialized.boxes[3].mons[1].species, 7, "Restored Box 3 Slot 1")
assert_eq(Storage.countTotalMons(deserialized), 3, "Total mon count exactly 3")
print("[ok] Sparse serialization preserves lean disk footprint")

print("=== [TEST 9] Context-Aware Summary Screen Pagination in Box Mode ===")
local boxMonsList = {
  { species = 1, level = 5 },
  { species = 4, level = 5 },
  { species = 7, level = 5 },
}
SummaryMenu.openMenu(boxMonsList, 2, { context = "box" })
assert_true(SummaryMenu.isOpen(), "SummaryMenu open")
assert_eq(SummaryMenu._context, "box", "Context is box mode")
assert_eq(SummaryMenu._cursor, 2, "Cursor on Charmander (index 2)")

-- Cycle to Squirtle (index 3)
SummaryMenu.handleInput(make_input({ down = true }))
assert_eq(SummaryMenu._cursor, 3, "Navigated to Squirtle (index 3)")
SummaryMenu.close()
assert_false(SummaryMenu.isOpen(), "SummaryMenu closed cleanly")
print("[ok] Context-aware SummaryScreen in Box mode passed")

print("=== [TEST 10] BoxStorageUI Navigation & Hover Bounce ===")
local uiSession = {
  party = { { species = 25, level = 10, hp = 30, maxHp = 30 } },
  storage = Storage.new(),
}
uiSession.storage.boxes[1].mons[1] = { species = 1, level = 5 }
uiSession.storage.boxes[1].mons[2] = { species = 4, level = 5 }

BoxStorageUI.show({ session = uiSession })
assert_true(BoxStorageUI.isOpen(), "BoxStorageUI is open")
assert_eq(BoxStorageUI.cursorSlot, 1, "Cursor on slot 1")
assert_eq(BoxStorageUI.hoverFrame, 0, "Initial hoverFrame is 0")

-- Update hover bounce timer
BoxStorageUI.update(0.15)
assert_eq(BoxStorageUI.hoverFrame, 1, "Hover bounce toggled to frame 1")
BoxStorageUI.update(0.15)
assert_eq(BoxStorageUI.hoverFrame, 0, "Hover bounce toggled back to frame 0")

-- Navigate right to slot 2
BoxStorageUI.handleInput(make_input({ right = true }))
assert_eq(BoxStorageUI.cursorSlot, 2, "Cursor moved to slot 2")

-- Switch box with R trigger
BoxStorageUI.handleInput(make_input({ r = true }))
assert_eq(uiSession.storage.currentBox, 2, "Switched to Box 2")

BoxStorageUI.close()
assert_false(BoxStorageUI.isOpen(), "BoxStorageUI closed")
print("[ok] BoxStorageUI navigation and hover bounce passed")

print("=== [TEST 11] PcMenu Root Navigation & Submenu Lifecycle ===")
local pcSession = {
  name = "RED",
  flags = { [0x828] = true, [0x82C] = true }, -- BILL'S PC unlocked
  party = { { species = 25, level = 10, hp = 30, maxHp = 30 } },
  storage = Storage.new(),
  bag = Bag.new(),
}
local pcClosed = false
PcMenu.show({ session = pcSession, onClose = function() pcClosed = true end })
assert_true(PcMenu.isOpen(), "PcMenu is open")
assert_eq(PcMenu.mode, "root", "Mode is root")

-- Move to LOG OFF (index 5) and press A
for _ = 1, 4 do
  PcMenu.handleInput(make_input({ down = true }))
end
assert_eq(PcMenu.cursor, 5, "Cursor on LOG OFF")
PcMenu.handleInput(make_input({ a = true }))
assert_false(PcMenu.isOpen(), "PcMenu closed")
assert_true(pcClosed, "onClose callback invoked")
print("[ok] PcMenu lifecycle passed")

print("=== [TEST 12] 1:1 Storage Submenu Flow & Validation Checks ===")
local storageSubSession = {
  name = "RED",
  flags = { [0x828] = true }, -- BILL'S PC
  party = {
    { species = 25, level = 10, hp = 30, maxHp = 30 },
  },
  storage = Storage.new(),
  bag = Bag.new(),
}
PcMenu.show({ session = storageSubSession })
assert_eq(PcMenu.mode, "root", "Started in root menu")

-- Select BILL'S PC (index 1)
PcMenu.handleInput(make_input({ a = true }))
assert_eq(PcMenu.mode, "storage_menu", "Entered storage_menu")
assert_eq(PcMenu.cursor, 1, "Cursor on WITHDRAW POKéMON")
assert_eq(PcMenu._status, "gText_WithdrawMonDescription", "Description matches WITHDRAW POKéMON")

-- Navigate down to DEPOSIT POKéMON (index 2)
PcMenu.handleInput(make_input({ down = true }))
assert_eq(PcMenu.cursor, 2, "Cursor on DEPOSIT POKéMON")
assert_eq(PcMenu._status, "gText_DepositMonDescription", "Description matches DEPOSIT POKéMON")

-- Navigate down to MOVE POKéMON (index 3)
PcMenu.handleInput(make_input({ down = true }))
assert_eq(PcMenu.cursor, 3, "Cursor on MOVE POKéMON")
assert_eq(PcMenu._status, "gText_MoveMonDescription", "Description matches MOVE POKéMON")

-- Navigate down to MOVE ITEMS (index 4)
PcMenu.handleInput(make_input({ down = true }))
assert_eq(PcMenu.cursor, 4, "Cursor on MOVE ITEMS")
assert_eq(PcMenu._status, "gText_MoveItemsDescription", "Description matches MOVE ITEMS")

-- Navigate down to SEE YA! (index 5)
PcMenu.handleInput(make_input({ down = true }))
assert_eq(PcMenu.cursor, 5, "Cursor on SEE YA!")
assert_eq(PcMenu._status, "gText_SeeYaDescription", "Description matches SEE YA!")

-- Test DEPOSIT validation when party is 1
PcMenu.handleInput(make_input({ up = true, up = true, up = true })) -- index 2
PcMenu.cursor = 2
PcMenu.handleInput(make_input({ a = true }))
assert_eq(PcMenu.mode, "msg", "Blocked deposit due to single party Pokémon")
assert_eq(PcMenu._status, "gText_JustOnePkmn", "Error status matches FRLG text")
PcMenu.handleInput(make_input({ a = true }))
assert_eq(PcMenu.mode, "storage_menu", "Returned to storage_menu")

-- Test WITHDRAW validation when party is full (6)
for i = 2, 6 do
  storageSubSession.party[i] = { species = i, level = 5, hp = 20, maxHp = 20 }
end
assert_eq(#storageSubSession.party, 6, "Party is now full (6 mons)")
PcMenu.cursor = 1
PcMenu.handleInput(make_input({ a = true }))
assert_eq(PcMenu.mode, "msg", "Blocked withdraw due to full party")
assert_eq(PcMenu._status, "gText_PartyFull", "Error status matches FRLG text")
PcMenu.handleInput(make_input({ a = true }))
assert_eq(PcMenu.mode, "storage_menu", "Returned to storage_menu")

-- Press B to return to root PC menu
PcMenu.handleInput(make_input({ b = true }))
assert_eq(PcMenu.mode, "root", "Returned to root PC menu")
PcMenu.close()
assert_false(PcMenu.isOpen(), "PC Menu closed")
print("[ok] 1:1 Storage Submenu flow and boundary validations verified")

print("=== [TEST 13] Authentic Party Drawer Navigation & Coordinates ===")
local PcChrome = require("src.ui.game3.pc_chrome")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")

-- Check GBA cursor coords
local x1, y1 = PcChrome.getPartyCursorCoords(1)
assert_eq(x1, 104, "Slot 1 (Lead) X is 104")
assert_eq(y1, 52, "Slot 1 (Lead) Y is 52")

local x2, y2 = PcChrome.getPartyCursorCoords(2)
assert_eq(x2, 152, "Slot 2 X is 152")
assert_eq(y2, 4, "Slot 2 Y is 4")

local x6, y6 = PcChrome.getPartyCursorCoords(6)
assert_eq(x6, 152, "Slot 6 X is 152")
assert_eq(y6, 100, "Slot 6 Y is 100")

local x7, y7 = PcChrome.getPartyCursorCoords(7)
assert_eq(x7, 152, "CANCEL button (Slot 7) X is 152")
assert_eq(y7, 132, "CANCEL button (Slot 7) Y is 132")

-- Test UI party drawer navigation
local partyDrawerSession = {
  party = {
    { species = 1, nickname = "BULBASAUR", level = 5, hp = 20, maxHp = 20 },
    { species = 19, nickname = "RATTATA", level = 3, hp = 15, maxHp = 15 },
  },
  storage = Storage.new(),
}
BoxStorageUI.show({ session = partyDrawerSession })
BoxStorageUI.mode = "party_drawer"
BoxStorageUI.partyCursor = 1

-- Press Right from slot 1 moves to previous vertical slot (2)
BoxStorageUI.handleInput(make_input({ right = true }))
assert_eq(BoxStorageUI.partyCursor, 2, "Moved from Lead (1) to Slot 2")

-- Press Left from slot 2 moves back to Lead (1)
BoxStorageUI.handleInput(make_input({ left = true }))
assert_eq(BoxStorageUI.partyCursor, 1, "Moved from Slot 2 to Lead (1)")

-- Press Up from slot 1 wraps to CANCEL (7)
BoxStorageUI.handleInput(make_input({ up = true }))
assert_eq(BoxStorageUI.partyCursor, 7, "Wrapped Up from Slot 1 to CANCEL (7)")

-- Press Down from CANCEL (7) wraps to Slot 1
BoxStorageUI.handleInput(make_input({ down = true }))
assert_eq(BoxStorageUI.partyCursor, 1, "Wrapped Down from CANCEL (7) to Slot 1")

-- Press Right from slot 1 -> slot 2, then Right again exits to Box
BoxStorageUI.handleInput(make_input({ right = true }))
assert_eq(BoxStorageUI.partyCursor, 2, "On Slot 2")
BoxStorageUI.handleInput(make_input({ right = true }))
assert_eq(BoxStorageUI.mode, "browse", "Exited party drawer to Box browse mode")
assert_eq(BoxStorageUI.cursorSlot, 1, "Cursor reset to Box slot 1")

BoxStorageUI.close()
print("[ok] Party Drawer authentic navigation and coordinates verified")

print("=== [TEST 14] Party Drawer Action Menu & Drawer Visibility ===")
local partyActionSession = {
  party = {
    { species = 1, nickname = "BULBASAUR", level = 5, hp = 20, maxHp = 20 },
    { species = 19, nickname = "RATTATA", level = 3, hp = 15, maxHp = 15 },
  },
  storage = Storage.new(),
}
BoxStorageUI.show({ session = partyActionSession, subMode = "withdraw" })

-- Navigate to PARTY POKéMON button (-10) and press A
BoxStorageUI.cursorSlot = -10
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "party_drawer", "Entered party drawer")
assert_true(BoxStorageUI.drawerOpen, "Party drawer is marked open")

-- Press A on Lead Mon (1) to open action menu
BoxStorageUI.partyCursor = 1
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "action_menu", "Action menu opened for party mon")
assert_true(BoxStorageUI.drawerOpen, "Party drawer stays open under action menu")
assert_eq(BoxStorageUI._actionSource, "party", "Action source is party")
assert_true(BoxStorageUI._actionTarget ~= nil, "Action target recorded")
assert_eq(BoxStorageUI._actionTarget.mon.nickname, "BULBASAUR", "Action target is Bulbasaur")

-- Test CANCEL from action menu returns to party drawer (drawer stays open)
BoxStorageUI.actionCursor = #BoxStorageUI._activeActions -- CANCEL
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "party_drawer", "CANCEL returned to party_drawer mode")
assert_true(BoxStorageUI.drawerOpen, "Drawer is still open")

-- Open action menu again and test STORE
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "action_menu", "Action menu re-opened")
BoxStorageUI.actionCursor = 1 -- STORE
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "party_drawer", "STORE completed and returned to party_drawer")
assert_eq(#partyActionSession.party, 1, "Party now has 1 mon")
assert_eq(partyActionSession.party[1].nickname, "RATTATA", "Remaining mon is Rattata")
assert_eq(partyActionSession.storage.boxes[1].mons[1].nickname, "BULBASAUR", "Bulbasaur stored in box 1")

-- Try to STORE last mon (Rattata) -> should show error message and return to party_drawer
BoxStorageUI.partyCursor = 1
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "action_menu", "Action menu opened on Rattata")
BoxStorageUI.actionCursor = 1 -- STORE
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "message", "Entered message mode on last mon store attempt")
assert_eq(BoxStorageUI._status, "gText_JustOnePkmn", "Error status matches")

-- Dismiss message -> returns to party_drawer
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "party_drawer", "Dismissing error message returned to party_drawer")
assert_true(BoxStorageUI.drawerOpen, "Party drawer remains open")

-- Test MOVE on party mon
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "action_menu", "Action menu opened on Rattata")
BoxStorageUI.actionCursor = 3 -- MOVE
BoxStorageUI.handleInput(make_input({ a = true }))
assert_eq(BoxStorageUI.mode, "party_drawer", "MOVE returned to party_drawer")
assert_true(BoxStorageUI.holdingMon ~= nil, "Holding mon is active")
assert_eq(BoxStorageUI.holdingMon.nickname, "RATTATA", "Holding Rattata")
assert_eq(BoxStorageUI.holdingSource.loc, "party", "Holding source is party")

-- Place back down on slot 1
BoxStorageUI.handleInput(make_input({ a = true }))
assert_true(BoxStorageUI.holdingMon == nil, "Mon placed down")
assert_eq(partyActionSession.party[1].nickname, "RATTATA", "Rattata back in slot 1")

BoxStorageUI.close()
print("[ok] Party Drawer Action Menu interaction and persistence verified")

print("=== [TEST 15] Storage Chrome & Wallpapers Extraction and Manifest Integrity ===")
local StorageChromeExtract = require("src.import.gba.storage_chrome_extract")
local Cache = require("tests.game3_cache")
local storageRoot = Cache.root("pokemon/storage/wallpapers/forest.png")
if not storageRoot then
  print("[skip] TEST 15: no imported FireRed cache with storage chrome")
else
local chromeDir = storageRoot .. "/" .. StorageChromeExtract.CACHE_SUB
assert_true(StorageChromeExtract.ready(nil, storageRoot), "StorageChromeExtract ready check passed")

local manifestChunk = assert(loadfile(chromeDir .. "/manifest.lua"))
local manifest = manifestChunk()
assert_eq(manifest.version, 3, "Manifest version is 3")
assert_true(manifest.textures.cursor ~= nil, "Manifest includes cursor texture")
assert_true(manifest.textures.party_drawer_bg ~= nil, "Manifest includes party_drawer_bg")
assert_true(manifest.textures.scrolling_bg ~= nil, "Manifest includes scrolling_bg")
assert_true(manifest.wallpapers.forest ~= nil, "Manifest includes forest wallpaper")
assert_true(manifest.wallpapers.stars ~= nil, "Manifest includes stars wallpaper")
assert_true(manifest.wallpapers.simple ~= nil, "Manifest includes simple wallpaper")

local function assert_png(path, label)
  local f = io.open(path, "rb")
  assert_true(f ~= nil, label .. " exists on disk")
  local header = f:read(8)
  f:close()
  assert_true(header ~= nil and header:sub(2, 4) == "PNG", label .. " is a valid PNG")
end

local assetCount = 0
for _, tex in ipairs(StorageChromeExtract.TEXTURE_FILES) do
  assert_eq(manifest.textures[tex.key], tex.file, "Texture " .. tex.key .. " present in manifest")
  assert_png(chromeDir .. "/" .. tex.file, "Texture " .. tex.file)
  assetCount = assetCount + 1
end
for _, wpName in ipairs(PcChrome.WALLPAPER_NAMES) do
  assert_eq(manifest.wallpapers[wpName], "wallpapers/" .. wpName .. ".png",
    "Wallpaper " .. wpName .. " present in manifest")
  assert_png(chromeDir .. "/wallpapers/" .. wpName .. ".png", "Wallpaper " .. wpName .. ".png")
  assetCount = assetCount + 1
end
assert_eq(assetCount, 30, "14 UI textures + 16 box wallpapers (total 30 assets)")
print("[ok] All 14 UI textures and 16 wallpapers validated in manifest and file system")
end

print("=== [TEST 16] Party-to-Box Move Compacts a Holed Party ===")
do
  local function mk(n) return { species = 1, nickname = n, level = 5, hp = 10, maxHp = 10, moves = {} } end
  local A, B, C = mk("A"), mk("B"), mk("C")
  local holed = { party = { [1] = A, [2] = B, [4] = C }, storage = Storage.new(), bag = Bag.new() }
  local okMove = Storage.moveMon(holed, "party", 2, "box", 1)
  assert_true(okMove, "Party slot 2 moved into the box")
  assert_eq(holed.party[1], A, "Slot 1 keeps A")
  assert_eq(holed.party[2], C, "C compacts into slot 2")
  assert_eq(holed.party[3], nil, "No third party mon")
  assert_eq(holed.party[4], nil, "Old slot 4 cleared")
  assert_eq(Storage.getBoxMon(holed.storage, holed.storage.currentBox, 1), B, "B landed in the box")
  print("[ok] Holed party compacted without dropping mons")
end

print("\n========================================================")
print("ALL 16 POKÉMON STORAGE & PC SYSTEM TESTS PASSED CLEANLY!")
print("========================================================")

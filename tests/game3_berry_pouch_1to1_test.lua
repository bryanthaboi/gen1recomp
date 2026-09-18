-- Test suite for Berry Pouch 1:1 authentic layout and mechanics.

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local BerryPouch = require("src.ui.game3.berry_pouch")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("Assertion failed: %s (expected %s, got %s)", msg or "", tostring(b), tostring(a)), 2)
  end
end

local function run_tests()
  print("[berry_pouch_1to1_test] Starting Berry Pouch 1:1 tests...")

  -- 1. Berry Identification and Numbering
  assert_eq(ItemsData.isBerry(133), true, "Cheri Berry is berry")
  assert_eq(ItemsData.berryNumber(133), 1, "Cheri Berry is #01")
  assert_eq(ItemsData.isBerry(134), true, "Chesto Berry is berry")
  assert_eq(ItemsData.berryNumber(134), 2, "Chesto Berry is #02")
  assert_eq(ItemsData.isBerry(175), true, "Enigma Berry is berry")
  assert_eq(ItemsData.berryNumber(175), 43, "Enigma Berry is #43")
  assert_eq(ItemsData.isBerry(1), false, "Master Ball is not berry")
  assert_eq(ItemsData.isBerry(289), false, "TM01 is not berry")

  -- 2. Bag Berry Storage & Max Cap (999)
  local bag = Bag.new()
  local okAdd, count = Bag.add(bag, 133, 500)
  assert_eq(okAdd, true, "Add 500 Cheri Berries")
  assert_eq(count, 500, "500 Cheri Berries added")
  local okAdd2, count2 = Bag.add(bag, 133, 499)
  assert_eq(okAdd2, true, "Add 499 Cheri Berries (total 999)")
  local berries = Bag.listPocket(bag, "BERRY_POUCH")
  assert_eq(#berries, 1, "1 berry in pocket")
  assert_eq(berries[1].qty, 999, "Quantity is 999")

  -- 3. Berry Pouch Open & Wobble Timer
  local session = { bag = bag, party = {} }
  BerryPouch.show(session, bag)
  assert_eq(BerryPouch.isOpen(), true, "Berry Pouch is open")
  assert_eq(BerryPouch.wobbleTimer > 0, true, "Affine wobble starts active on open")
  assert_eq(BerryPouch.cursor, 1, "Cursor initialized at 1")
  assert_eq(BerryPouch.scroll, 0, "Scroll initialized at 0")

  -- 4. 7-Row List Menu & CLOSE option
  -- Add 10 different berries to test scrolling past 7 rows
  for id = 134, 143 do
    Bag.add(bag, id, 1)
  end
  local rows = Bag.listPocket(bag, "BERRY_POUCH")
  assert_eq(#rows, 11, "11 unique berries in pocket")

  -- Mock Input helper
  local function makeInput(key)
    return {
      wasPressed = function(_, k) return k == key end,
      isDown = function(_, k) return k == key end,
    }
  end

  -- Cursor starts at 1. Total items = 11 + 1 (CLOSE) = 12.
  -- Press UP to wrap to CLOSE option (item 12)
  BerryPouch.handleInput(makeInput("up"))
  assert_eq(BerryPouch.cursor, 12, "Wrapping up navigates to CLOSE option")
  assert_eq(BerryPouch.scroll, 5, "Scroll adjusted so row 12 is visible (max scroll = 12 - 7 = 5)")

  -- Press DOWN to wrap back to row 1
  BerryPouch.handleInput(makeInput("down"))
  assert_eq(BerryPouch.cursor, 1, "Wrapping down navigates to row 1")
  assert_eq(BerryPouch.scroll, 0, "Scroll resets to 0")

  -- 5. Context Action Menu
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.mode, "action", "A button on item opens context action menu")
  assert_eq(BerryPouch.actionCursor, 1, "Action cursor starts at USE")

  -- Move action cursor down to TOSS (index 3)
  BerryPouch.handleInput(makeInput("down")) -- GIVE (2)
  assert_eq(BerryPouch.actionCursor, 2, "Action cursor is GIVE")
  BerryPouch.handleInput(makeInput("down")) -- TOSS (3)
  assert_eq(BerryPouch.actionCursor, 3, "Action cursor is TOSS")

  -- Press A on TOSS -> Quantity Select Mode (since Cheri Berry qty is 999 > 1)
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.mode, "toss_select", "Entering toss quantity selection mode")
  assert_eq(BerryPouch.tossQty, 1, "Initial toss quantity is 1")

  -- Test D-Pad Wrap: Down from 1 should wrap to max stack size (999)
  BerryPouch.handleInput(makeInput("down"))
  assert_eq(BerryPouch.tossQty, 999, "Down on 1 wraps to max stack quantity 999")

  -- Test D-Pad Wrap: Up from 999 should wrap back to 1
  BerryPouch.handleInput(makeInput("up"))
  assert_eq(BerryPouch.tossQty, 1, "Up on 999 wraps to 1")

  -- Increase to 5
  for _ = 1, 4 do
    BerryPouch.handleInput(makeInput("up"))
  end
  assert_eq(BerryPouch.tossQty, 5, "Toss quantity is 5")

  -- Press A to confirm quantity -> YES/NO modal
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.mode, "toss_confirm", "Entered toss confirmation mode")
  assert_eq(BerryPouch.yesNoCursor, 1, "YesNo cursor is YES")

  -- Press A on YES to execute toss
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.mode, "message", "Toss complete shows message modal")
  assert_eq(BerryPouch.messageText:find("Threw away 5") ~= nil, true, "Message confirms 5 items thrown away")

  -- Verify Bag has 999 - 5 = 994 Cheri Berries
  local cheriRow = Bag.listPocket(bag, "BERRY_POUCH")[1]
  assert_eq(cheriRow.qty, 994, "Quantity correctly reduced in Bag")

  -- Press A to dismiss message and return to list
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.mode, "list", "Returned to list mode")

  -- 6. Close Berry Pouch via CLOSE option
  BerryPouch.cursor = 12
  BerryPouch.handleInput(makeInput("a"))
  assert_eq(BerryPouch.isOpen(), false, "A on CLOSE closes Berry Pouch")

  print("[berry_pouch_1to1_test] ALL TESTS PASSED!")
end

run_tests()

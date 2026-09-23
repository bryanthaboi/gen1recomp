-- Storage.depositItem must not destroy items when the PC stack is at the cap.
--
-- Regression: the existing-stack branch capped the PC quantity with
-- math.min(MAX_ITEM_QTY, curQty + qty) and then removed the FULL qty from the
-- bag.  With a PC stack already at 999, depositing more stored nothing but
-- still deleted the items from the bag -- silent item loss (reachable from
-- PcMenu's deposit action).
--
-- Fix contract: a deposit that does not fit is refused (like the 50-slot cap),
-- so the bag keeps the items.  The caller already maps any failure to
-- "The PC is full.".
--   luajit tests/engine/game3_pc_item_capacity_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("game3_pc_item_capacity_test")

local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")

local POTION = 13

local function session_with(pcQty, bagQty)
  local s = { bag = Bag.new(), storage = Storage.new() }
  s.storage.items = {}
  if pcQty and pcQty > 0 then s.storage.items[1] = { id = POTION, qty = pcQty } end
  if bagQty and bagQty > 0 then Bag.add(s.bag, POTION, bagQty) end
  return s
end

-- 1. The bug: a full PC stack must refuse, not swallow the items.
local s = session_with(Storage.MAX_ITEM_QTY, 5)
local ok, err = Storage.depositItem(s, "ITEMS", 1, 5)
check(ok == false, "depositing into a stack at MAX_ITEM_QTY is refused (err=" .. tostring(err) .. ")")
eq(s.storage.items[1].qty, Storage.MAX_ITEM_QTY, "the PC stack stays at the cap")
eq(Bag.get(s.bag, POTION), 5, "the bag keeps the items -- they are not destroyed")

-- 2. A stack with too little room for the whole deposit is refused too.
s = session_with(995, 5)
ok = Storage.depositItem(s, "ITEMS", 1, 5)
check(ok == false, "a deposit that does not fit in the stack is refused")
eq(s.storage.items[1].qty, 995, "the partial stack is unchanged")
eq(Bag.get(s.bag, POTION), 5, "the bag keeps the items when the deposit is refused")

-- 3. A deposit that exactly fills the stack succeeds and moves the items once.
s = session_with(994, 5)
ok = Storage.depositItem(s, "ITEMS", 1, 5)
check(ok == true, "a deposit that exactly fills the stack succeeds")
eq(s.storage.items[1].qty, Storage.MAX_ITEM_QTY, "the stack reaches the cap")
eq(Bag.get(s.bag, POTION), 0, "the bag is debited exactly once")

-- 4. Regression: the ordinary deposit path is unchanged.
s = session_with(0, 20)
ok = Storage.depositItem(s, "ITEMS", 1, 20)
check(ok == true, "an ordinary deposit succeeds")
eq(s.storage.items[1].qty, 20, "the new stack holds the deposited quantity")
eq(Bag.get(s.bag, POTION), 0, "the bag is emptied by the deposit")

-- 5. Regression: more than the bag holds still fails without touching the PC.
s = session_with(0, 4)
local ok5, err5 = Storage.depositItem(s, "ITEMS", 1, 5)
check(ok5 == false and err5 == "insufficient_bag_qty", "over-depositing the bag fails")
eq(Bag.get(s.bag, POTION), 4, "a refused deposit leaves the bag intact")

T.finish("game3_pc_item_capacity_test")

#!/usr/bin/env luajit
-- Shop & Bag chrome extraction, contract, state machine, and interaction unit tests.

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

print("[test] 1. Versions Offsets for Bag & Shop")
local Versions = require("src.import.gba.versions")
check(Versions.BAG_BG_GFX == 0xE830CC, "BAG_BG_GFX = 0xE830CC")
check(Versions.BAG_BG_TILEMAP == 0xE832C0, "BAG_BG_TILEMAP = 0xE832C0")
check(Versions.BAG_BG_PAL == 0xE835B4, "BAG_BG_PAL = 0xE835B4")
check(Versions.BAG_MALE_GFX == 0xE8362C, "BAG_MALE_GFX = 0xE8362C")
check(Versions.BAG_FEMALE_GFX == 0xE83DBC, "BAG_FEMALE_GFX = 0xE83DBC")
check(Versions.BAG_SPRITE_PAL == 0xE84560, "BAG_SPRITE_PAL = 0xE84560")
check(Versions.ITEM_ICON_TABLE == 0x3D4294, "ITEM_ICON_TABLE = 0x3D4294")
check(Versions.ITEMS_COUNT == 375, "ITEMS_COUNT = 375")

check(Versions.SHOP_BG_GFX == 0xE85DC8, "SHOP_BG_GFX = 0xE85DC8")
check(Versions.SHOP_BG_TILEMAP == 0xE85EFC, "SHOP_BG_TILEMAP = 0xE85EFC")
check(Versions.SHOP_BG_TM_TILEMAP == 0xE86038, "SHOP_BG_TM_TILEMAP = 0xE86038")
check(Versions.SHOP_BG_PAL == 0xE86170, "SHOP_BG_PAL = 0xE86170")

print("[test] 2. Cache Contract for Bag & Shop")
local CacheContract = require("src.import.CacheContract")
local req = CacheContract.requiredFilesFor("firered")
local reqSet = {}
for _, f in ipairs(req) do reqSet[f] = true end
check(reqSet["data/generated/gba/items/bag/manifest.lua"] == true, "contract has bag manifest.lua")
check(reqSet["data/generated/gba/items/bag/bg.rgba"] == true, "contract has bag bg.rgba")
check(reqSet["data/generated/gba/items/shop/manifest.lua"] == true, "contract has shop manifest.lua")
check(reqSet["data/generated/gba/items/shop/bg.rgba"] == true, "contract has shop bg.rgba")

print("[test] 3. BagMenu Lifecycle & Pockets")
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local testBag = Bag.new()
Bag.add(testBag, 1, 5) -- Master Ball (POKE_BALLS)
Bag.add(testBag, 4, 10) -- Poke Ball (POKE_BALLS)
Bag.add(testBag, 13, 3) -- Potion (ITEMS)
Bag.add(testBag, 360, 1) -- Bicycle (KEY_ITEMS)
Bag.add(testBag, 361, 1) -- Town Map (KEY_ITEMS)

local playedSe = {}
local Audio = require("src.core.game3.audio")
local origPlaySe = Audio.playSe
Audio.playSe = function(id)
  table.insert(playedSe, id)
  if origPlaySe then pcall(origPlaySe, id) end
end

local closed = false
local session = {
  bag = testBag,
  money = 5000,
  party = { { name = "PIKACHU", hp = 20, maxHp = 25 } },
}
BagMenu.show(testBag, {
  session = session,
  onClose = function() closed = true end,
})
BagMenu.settle()
check(BagMenu.isOpen() == true, "bag menu is open")
check(BagMenu.currentPocket() == "ITEMS", "starts in ITEMS pocket")

local itemsList = BagMenu.list("ITEMS")
check(#itemsList >= 1, "ITEMS list has items")

local ballsList = BagMenu.list("POKE_BALLS")
check(#ballsList >= 2, "POKE_BALLS list has Poké Balls")

-- Input step simulation
local mockInput = {
  _pressed = {},
  wasPressed = function(self, k) return self._pressed[k] == true end,
  set = function(self, k) self._pressed = { [k] = true } end,
  clear = function(self) self._pressed = {} end,
}

playedSe = {}
mockInput:set("right")
BagMenu.handleInput(mockInput)
check(BagMenu.currentPocket() == "KEY_ITEMS", "right advances to KEY_ITEMS pocket")
check(#playedSe > 0 and playedSe[#playedSe] == 246, "SE_BAG_POCKET (246) played on pocket switch right")

playedSe = {}
mockInput:set("right")
BagMenu.handleInput(mockInput)
check(BagMenu.currentPocket() == "POKE_BALLS", "right advances to POKE_BALLS pocket")
check(#playedSe > 0 and playedSe[#playedSe] == 246, "SE_BAG_POCKET (246) played on second pocket switch right")

playedSe = {}
mockInput:set("left")
BagMenu.handleInput(mockInput)
check(BagMenu.currentPocket() == "KEY_ITEMS", "left advances to KEY_ITEMS pocket")
check(#playedSe > 0 and playedSe[#playedSe] == 246, "SE_BAG_POCKET (246) played on pocket switch left")

-- Vertical cursor movement
BagMenu.settle()
playedSe = {}
mockInput:set("down")
BagMenu.handleInput(mockInput)
check(#playedSe > 0 and playedSe[#playedSe] == 245, "SE_BAG_CURSOR (245) played on cursor move down")

BagMenu.settle()
mockInput:set("b")
BagMenu.handleInput(mockInput)
BagMenu.settle()
check(BagMenu.isOpen() == false, "B closes bag menu")
check(closed == true, "onClose called")

Audio.playSe = origPlaySe

print("[test] 4. ShopMenu Purchasing, Selling, and Premier Ball Bonus")
local ShopMenu = require("src.ui.game3.shop_menu")
local shopClosed = false
local shopSession = {
  bag = Bag.new(),
  money = 3000,
}
ShopMenu.show({
  items = { 4, 13, 17 }, -- Poke Ball (200), Potion (300), Antidote (100)
  session = shopSession,
  onClose = function() shopClosed = true end,
})
check(ShopMenu.isOpen() == true, "shop menu is open")
check(ShopMenu.mode == "root", "shop menu starts in root mode")

-- Enter BUY mode
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "buy", "A enters buy mode")

-- Select Poké Ball (index 1)
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "buy_qty", "A enters buy_qty mode")

-- Increase qty to 10
ShopMenu.qty = 10
check(ShopMenu.qty == 10, "qty set to 10")

-- Press A to enter buy confirmation ("...and that'll be ¥2000. OK?")
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "buy_confirm", "A enters buy_confirm mode")

-- Confirm buy of 10 Poké Balls (10 * 200 = 2000)
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(shopSession.money == 1000, "money reduced by 2000 to 1000")
check(Bag.has(shopSession.bag, 4, 10) == true, "bag received 10 Poké Balls")
check(Bag.has(shopSession.bag, 12, 1) == true, "bag received 1 PREMIER BALL bonus for buying 10 Poké Balls!")

-- Enter SELL mode
ShopMenu.mode = "sell"
ShopMenu.cursor = 1
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "sell_qty", "A on bag item enters sell_qty mode")

-- Sell 5 units of the selected item
ShopMenu.qty = 5
local itemPrice = (ShopMenu._pending and ShopMenu._pending.price) or 100
local expectedMoney = 1000 + (itemPrice * 5)
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "sell_confirm", "A enters sell_confirm mode")

-- Confirm sell
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(shopSession.money == expectedMoney, string.format("selling 5 added %d to money (%d)", itemPrice * 5, expectedMoney))

-- Dismiss sell message
mockInput:set("a")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "sell", "A dismisses sell message back to sell mode")

mockInput:set("b")
ShopMenu.handleInput(mockInput)
check(ShopMenu.mode == "root", "B from sell returns to root")

mockInput:set("b")
ShopMenu.handleInput(mockInput)
check(ShopMenu.isOpen() == false, "B closes shop menu")
check(shopClosed == true, "onClose called")

if failed > 0 then
  print(string.format("[FAIL] %d test(s) failed", failed))
  os.exit(1)
else
  print("[test] all passed")
end

-- pokefirered/src/item_menu.c:1059
-- pokeemerald/src/item_menu.c:1228

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Screens = require("src.ui.game3.screens")
local Stack = require("src.ui.game3.stack")
local SaveData = require("src.core.SaveData")
local Schema = require("src.core.game3.save_schema_firered")

local POTION, ANTIDOTE, REPEL = 13, 14, 86

local function item(name, pocket, extra)
  local t = { name = name, pocket = pocket, fieldUse = "none", price = 0 }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function press(key, session)
  local inp = {
    wasPressed = function(_, k) return k == key end,
    isDown = function() return false end,
  }
  Screens.handleInput("bag", BagMenu, inp, session)
end

local function ids(bag, pocket)
  local out = {}
  for i, r in ipairs(Bag.listPocket(bag, pocket)) do out[i] = ItemsData.toNumericId(r.id) end
  return table.concat(out, ",")
end

local function open(session, opts)
  opts = opts or {}
  opts.session = session
  BagMenu.show(session.bag, opts)
  BagMenu.settle()
  BagMenu.cursor, BagMenu.scroll = opts.cursor or 1, 0
end

local function close()
  BagMenu.close()
  Stack.clear()
end

local function setup(version, pack)
  Profile.reset()
  GameVersion.set(version)
  ItemsData.applyProfile(version)
  ItemsData.installPack(pack)
end

print("[test] FireRed field bag")
setup("firered", {
  count = 375,
  items = {
    [0] = item("????????", "ITEMS"),
    [4] = item("POKe BALL", "POKE_BALLS"),
    [POTION] = item("POTION", "ITEMS"),
    [ANTIDOTE] = item("ANTIDOTE", "ITEMS"),
    [REPEL] = item("REPEL", "ITEMS"),
    [360] = item("BICYCLE", "KEY_ITEMS", { importance = 1, registrability = 1 }),
    [361] = item("TOWN MAP", "KEY_ITEMS", { importance = 1, registrability = 1 }),
  },
})

local function frlgSession()
  local bag = Bag.new()
  Bag.add(bag, POTION, 3)
  Bag.add(bag, ANTIDOTE, 2)
  Bag.add(bag, REPEL, 1)
  return { version = "firered", bag = bag }
end

do
  local s = frlgSession()
  eq(ids(s.bag, "ITEMS"), "13,14,86", "starting order POTION, ANTIDOTE, REPEL")
  open(s, { pocket = "ITEMS" })
  press("select", s)
  eq(BagMenu.mode, "move", "SELECT on an item starts the move (item_menu.c:1065)")
  eq(BagMenu.moveFrom, 1, "origin row is the selected item")
  press("down", s)
  press("down", s)
  eq(BagMenu.cursor, 3, "cursor walks two rows down while moving")
  eq(ids(s.bag, "ITEMS"), "13,14,86", "nothing moves before the drop")
  press("select", s)
  eq(BagMenu.mode, "list", "SELECT drops the item (item_menu.c:1248)")
  eq(ids(s.bag, "ITEMS"), "14,13,86", "POTION inserted above REPEL (MoveItemSlotInList)")
  eq(BagMenu.cursor, 2, "cursor follows the moved item (item_menu.c:1286)")

  local saved = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  local loaded = Schema.fromSaveTable(saved)
  eq(ids(loaded.bag, "ITEMS"), "14,13,86", "moved order survives save and reload")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS" })
  press("select", s)
  for _ = 1, 3 do press("down", s) end
  eq(BagMenu.cursor, 4, "cursor reaches CLOSE BAG while moving")
  press("a", s)
  eq(BagMenu.open, true, "A on CLOSE BAG while moving does not close the bag")
  eq(ids(s.bag, "ITEMS"), "14,86,13", "A on CLOSE BAG drops the item at the end")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS", cursor = 3 })
  press("select", s)
  press("up", s)
  press("up", s)
  press("a", s)
  eq(ids(s.bag, "ITEMS"), "86,13,14", "moving up inserts at the target row")
  eq(BagMenu.cursor, 1, "no cursor fixup when moving up")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS" })
  press("select", s)
  press("down", s)
  press("down", s)
  press("b", s)
  eq(BagMenu.mode, "list", "B cancels the move (item_menu.c:1260)")
  eq(ids(s.bag, "ITEMS"), "13,14,86", "B leaves the order alone")
  eq(BagMenu.cursor, 2, "cancel still steps the cursor up (item_menu.c:1300)")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS" })
  press("select", s)
  press("down", s)
  press("select", s)
  eq(ids(s.bag, "ITEMS"), "13,14,86", "dropping just below the origin is a no-op (item_menu.c:1277)")
  eq(BagMenu.cursor, 1, "cursor returns to the item")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS", cursor = 4 })
  press("select", s)
  eq(BagMenu.mode, "list", "SELECT on CLOSE BAG does nothing (item_menu.c:1062)")
  close()
end

do
  local s = frlgSession()
  Bag.add(s.bag, 361, 1)
  Bag.add(s.bag, 360, 1)
  open(s, { pocket = "KEY_ITEMS" })
  press("select", s)
  eq(BagMenu.mode, "move", "Key Items move too")
  eq(s.registeredItem, nil, "SELECT never registers a key item")
  press("down", s)
  press("down", s)
  press("select", s)
  eq(ids(s.bag, "KEY_ITEMS"), "360,361", "key items reorder")
  close()
end

do
  local s = frlgSession()
  open(s, { pocket = "ITEMS", battle = true })
  press("select", s)
  eq(BagMenu.mode, "list", "FireRed battle bag never moves (ITEMMENULOCATION_FIELD only)")
  close()
  open(s, { pocket = "ITEMS", location = "shop" })
  press("select", s)
  eq(BagMenu.mode, "list", "shop bag never moves")
  close()
end

print("[test] Emerald bag")
setup("emerald", {
  count = 377,
  items = {
    [0] = item("????????", "ITEMS"),
    [4] = item("POKe BALL", "POKE_BALLS"),
    [POTION] = item("POTION", "ITEMS"),
    [ANTIDOTE] = item("ANTIDOTE", "ITEMS"),
    [REPEL] = item("REPEL", "ITEMS"),
    [133] = item("CHERI BERRY", "BERRIES"),
    [134] = item("CHESTO BERRY", "BERRIES"),
    [289] = item("TM01", "TM_HM"),
    [290] = item("TM02", "TM_HM"),
  },
})
require("src.ui.game3.rse.bag_menu").reset()

local function emSession()
  local bag = Bag.new()
  Bag.add(bag, POTION, 3)
  Bag.add(bag, ANTIDOTE, 2)
  Bag.add(bag, REPEL, 1)
  Bag.add(bag, 289, 1)
  Bag.add(bag, 290, 1)
  Bag.add(bag, 133, 1)
  Bag.add(bag, 134, 1)
  return { version = "emerald", bag = bag }
end

check(Screens.skin("bag", emSession()) ~= nil, "Emerald routes the bag through its skin")

do
  local s = emSession()
  open(s, { pocket = "ITEMS" })
  press("select", s)
  eq(BagMenu.mode, "move", "Emerald SELECT starts a swap (item_menu.c:1236)")
  press("down", s)
  press("down", s)
  eq(BagMenu.cursor, 3, "skin moves the cursor while swapping")
  press("select", s)
  eq(ids(s.bag, "ITEMS"), "14,13,86", "Emerald DoItemSwap reorders the pocket")
  eq(BagMenu.cursor, 2, "cursor follows the item (item_menu.c:1503)")
  local saved = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  eq(ids(Schema.fromSaveTable(saved).bag, "ITEMS"), "14,13,86", "Emerald order survives save and reload")
  close()
end

do
  local s = emSession()
  open(s, { pocket = "TM_CASE" })
  press("select", s)
  eq(BagMenu.mode, "list", "TM/HM pocket refuses (CanSwapItems)")
  close()
  open(s, { pocket = "BERRY_POUCH" })
  press("select", s)
  eq(BagMenu.mode, "list", "Berries pocket refuses (CanSwapItems)")
  close()
end

do
  local s = emSession()
  open(s, { pocket = "ITEMS", battle = true })
  press("select", s)
  eq(BagMenu.mode, "move", "Emerald battle bag swaps (ITEMMENULOCATION_BATTLE)")
  press("down", s)
  press("down", s)
  press("a", s)
  eq(ids(s.bag, "ITEMS"), "14,13,86", "battle bag swap reorders")
  close()
end

GameVersion.set("firered")
Profile.reset()
T.finish()

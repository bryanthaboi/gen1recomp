-- pokeemerald/src/battle_pyramid_bag.c:1605
-- pokeemerald/src/player_pc.c:1339
-- pokeemerald/src/menu_helpers.c:434

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local ItemsData = require("src.core.game3.items_data")
local RomText = require("src.core.game3.rom_text")
local FrlgFont = require("src.ui.game3.frlg_font")
local Stack = require("src.ui.game3.stack")
local Pyramid = require("src.core.game3.rse.frontier.pyramid")
local PBag = require("src.ui.game3.rse.pyramid_bag")
local ItemStorage = require("src.ui.game3.rse.item_storage")
local Storage = require("src.core.game3.storage")

local POTION, ANTIDOTE, REPEL = 13, 14, 86

local function item(name, pocket)
  return { name = name, pocket = pocket, fieldUse = "none", price = 0, description = name .. " DESC" }
end

Profile.reset()
GameVersion.set("emerald")
ItemsData.applyProfile("emerald")
ItemsData.installPack({
  count = 377,
  items = {
    [0] = item("????????", "ITEMS"),
    [POTION] = item("POTION", "ITEMS"),
    [ANTIDOTE] = item("ANTIDOTE", "ITEMS"),
    [REPEL] = item("REPEL", "ITEMS"),
  },
})

local realPlain, realManifest = RomText.plain, Pyramid.manifest
RomText.plain = function(key) return key end
Pyramid.manifest = function() return { bagReturnTo = {} } end

local function call(t, name, ...)
  local fn = t[name]
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

local function sprite(list, i)
  return type(list) == "table" and list[i] or {}
end

print("[test] Emerald Battle Pyramid bag swap line")

local sess = { version = "emerald" }
local function pyramidOrder()
  local items = Pyramid.bagLists(sess)
  return table.concat({ items[1], items[2], items[3] }, ",")
end

local function pyramidOpen()
  local items, qty = Pyramid.bagLists(sess)
  for i = 1, Pyramid.BAG_ITEMS_COUNT do items[i], qty[i] = 0, 0 end
  items[1], qty[1] = POTION, 3
  items[2], qty[2] = ANTIDOTE, 2
  items[3], qty[3] = REPEL, 1
  Pyramid.bagCursor = { cursor = 0, scroll = 0 }
  PBag.show({ session = sess, location = "field" })
  for _ = 1, 10 do PBag.update() end
end

local function pyramidPress(key)
  PBag._st.input = { new = { [key] = true }, held = { [key] = true }, rep = { [key] = true } }
  PBag.update()
end

local function pyramidClose()
  PBag.reset()
  Stack.clear()
end

do
  pyramidOpen()
  eq(call(PBag, "swapLine"), nil, "no swap line outside move mode")
  pyramidPress("select")
  eq(PBag._st.mode, "swap", "SELECT starts the move (battle_pyramid_bag.c:890)")
  local line = call(PBag, "swapLine")
  eq(type(line) == "table" and #line or 0, 8, "8 swap line sprites (battle_pyramid_bag.h:20)")
  eq(sprite(line, 1).frame, 0, "first sprite is the arrow frame (menu_helpers.c:47)")
  eq(sprite(line, 2).frame, 4, "the rest are the dash frame (menu_helpers.c:53)")
  eq(sprite(line, 1).x, 120, "line starts at x 120 (battle_pyramid_bag.c:1607)")
  eq(sprite(line, 7).x, 216, "sprite 7 at x 120 + 6*16")
  eq(sprite(line, 8).x, 224, "last sprite pulled 8px left by the margin (menu_helpers.c:446)")
  eq(sprite(line, 1).y, 17, "line on row 0 at y 1 + 16")
  eq(call(PBag, "iconItem"), POTION, "icon shows the moved item")
  PBag._st.shake = nil
  pyramidPress("down")
  eq(Pyramid.bagCursor.cursor, 1, "cursor moves while swapping")
  check(PBag._st.shake ~= nil, "cursor move shakes the bag while swapping (battle_pyramid_bag.c:639)")
  eq(sprite(call(PBag, "swapLine"), 1).y, 33, "line follows the cursor to row 1")
  eq(call(PBag, "iconItem"), POTION, "icon stays on the moved item (battle_pyramid_bag.c:641)")
  pyramidPress("b")
  eq(PBag._st.mode, "list", "B cancels the move")
  eq(pyramidOrder(), "13,14,86", "B leaves the order alone")
  eq(Pyramid.bagCursor.cursor, 0, "cancel steps the cursor up (battle_pyramid_bag.c:1395)")
  eq(call(PBag, "swapLine"), nil, "line hidden after cancel")
  pyramidClose()
end

do
  pyramidOpen()
  pyramidPress("select")
  pyramidPress("down")
  pyramidPress("a")
  eq(pyramidOrder(), "13,14,86", "drop one row below is a no-op")
  eq(Pyramid.bagCursor.cursor, 0, "no-op drop still steps the cursor up (battle_pyramid_bag.c:1368)")
  pyramidClose()
end

do
  pyramidOpen()
  pyramidPress("select")
  pyramidPress("down")
  pyramidPress("down")
  pyramidPress("a")
  eq(pyramidOrder(), "14,13,86", "POTION inserted above REPEL")
  eq(Pyramid.bagCursor.cursor, 1, "cursor follows the moved item")
  pyramidClose()
end

print("[test] Emerald PC item storage swap line")

local function pressFn(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function() return false end,
  }
end

local function storageOpen(version)
  local s = { version = version }
  local st = Storage.ensure(s)
  st.items = { { id = POTION, qty = 3 }, { id = ANTIDOTE, qty = 2 }, { id = REPEL, qty = 1 } }
  ItemStorage.show({ session = s })
  return s
end

local function storageClose()
  ItemStorage.reset()
  Stack.clear()
end

do
  storageOpen("emerald")
  eq(call(ItemStorage, "swapLine"), nil, "no swap line outside move mode")
  ItemStorage.handleInput(pressFn("select"))
  eq(ItemStorage.state, "swap", "SELECT starts the move (player_pc.c:1216)")
  local line = call(ItemStorage, "swapLine")
  eq(type(line) == "table" and #line or 0, 7, "7 swap line sprites (player_pc.c:88)")
  eq(sprite(line, 1).frame, 0, "first sprite is the arrow frame")
  eq(sprite(line, 2).frame, 4, "the rest are the dash frame")
  eq(sprite(line, 1).x, 128, "line starts at x 128 (player_pc.c:1341)")
  eq(sprite(line, 7).x, 224, "no margin: last sprite at x 128 + 6*16")
  eq(sprite(line, 1).y, 17, "line on row 0 at y 1 + 16")
  eq(call(ItemStorage, "iconItem"), POTION, "icon shows the moved item")
  ItemStorage.handleInput(pressFn("down"))
  eq(ItemStorage.row, 1, "cursor moves while swapping")
  eq(sprite(call(ItemStorage, "swapLine"), 1).y, 33, "line follows the cursor to row 1")
  eq(call(ItemStorage, "iconItem"), POTION, "icon stays on the moved item (player_pc.c:1019)")
  local c = ItemStorage.SWAP_ARROW_COLORS or {}
  check(c.fg == FrlgFont.STDPAL[3] and c.shadow == FrlgFont.STDPAL[2],
    "moved-item arrow is light gray on dark gray (player_pc.c:356)")
  ItemStorage.handleInput(pressFn("b"))
  eq(ItemStorage.state, "list", "B cancels the move")
  eq(call(ItemStorage, "swapLine"), nil, "line hidden after cancel")
  storageClose()
end

do
  storageOpen("ruby")
  ItemStorage.handleInput(pressFn("select"))
  eq(ItemStorage.state, "swap", "RS SELECT starts the switch")
  eq(call(ItemStorage, "swapLine"), nil, "RS draws no sprite swap line (pokeruby/src/player_pc.c:506)")
  storageClose()
end

RomText.plain, Pyramid.manifest = realPlain, realManifest
GameVersion.set("firered")
Profile.reset()
T.finish()

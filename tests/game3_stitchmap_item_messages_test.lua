#!/usr/bin/env luajit
-- pokefirered/src/item_use.c:182 DisplayItemMessageInCurrentContext
-- pokefirered/src/item_menu.c:1018 DisplayItemMessageInBag
-- pokefirered/src/new_menu_helpers.c:641 DisplayItemMessageOnField

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_stitchmap_item_messages_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

package.loaded["src.core.game3.collision"] = {
  isWater = function() return false end,
  behavior = function() return nil end,
  behaviorOn = function() return nil end,
  isSurfable = function() return false end,
  cell = function() return 0xff end,
}

local fieldMessages = {}
package.loaded["src.ui.game3.message"] = {
  show = function(text) fieldMessages[#fieldMessages + 1] = tostring(text) end,
  showStay = function(text) fieldMessages[#fieldMessages + 1] = tostring(text) end,
  close = function() end,
  isOpen = function() return false end,
}

local ItemsData = require("src.core.game3.items_data")
ItemsData.install(nil)
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local ItemUse = require("src.core.game3.item_use")
local Player = require("src.core.game3.player")
local Strings = require("src.core.Strings")
local Game3 = require("src.core.Game3")

local ITEM_OLD_ROD = "OLD_ROD" -- pokefirered/include/constants/items.h:273

local input = {
  _p = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function() return false end,
  press = function(self, key) self._p = { [key] = true } end,
}

local selectInput = {
  wasPressed = function(_, key) return key == "select" end,
  isDown = function() return false end,
}

local function row_index(id)
  local want = ItemsData.toNumericId(id)
  for i, r in ipairs(BagMenu.list()) do
    if tostring(r.id) == tostring(id)
        or (want and ItemsData.toNumericId(r.id) == want) then
      return i
    end
  end
  return nil
end

local function use_from_bag(session, id, pocket)
  BagMenu.show(session, { session = session, bag = session.bag, pocket = pocket })
  BagMenu.settle()
  local i = row_index(id)
  if not i then return false end
  BagMenu.cursor = i
  input:press("a")
  BagMenu.handleInput(input)
  if BagMenu.mode ~= "action" then return false end
  for k, a in ipairs(BagMenu.ACTIONS) do
    if a == "USE" then BagMenu.actionCursor = k end
  end
  input:press("a")
  BagMenu.handleInput(input)
  BagMenu.settle()
  return true
end

local function new_session()
  local s = { name = "RED", party = {}, bag = Bag.new(), map = "FR_PALLET_TOWN",
    flags = {}, vars = {} }
  return s
end

-- pokefirered/src/item_use.c:294 PrintNotTheTimeToUseThat
local REFUSAL = Strings("OAK: %s!\nThis isn't the time to use that!", "RED")

print("[test] 1. a rod out of water keeps its refusal inside the bag")
Player.cellX, Player.cellY, Player.facing, Player.surfing = 5, 5, "down", false
local s1 = new_session()
Bag.add(s1.bag, ITEM_OLD_ROD, 1)
fieldMessages = {}
check(use_from_bag(s1, ITEM_OLD_ROD, "KEY_ITEMS"), "the rod reached USE in the bag")
check(BagMenu.isOpen() == true, "the bag is still open")
check(BagMenu.mode == "message", "the bag is showing a message (got "
  .. tostring(BagMenu.mode) .. ")")
check(BagMenu.messageText == REFUSAL,
  "and it carries gText_OakForbidsUseOfItemHere (got " .. tostring(BagMenu.messageText) .. ")")
check(#fieldMessages == 0,
  "nothing was printed on the field (got " .. tostring(fieldMessages[1]) .. ")")

print("[test] 2. ItemUse.useRod returns that same line instead of printing it")
local ok, kind, text = ItemUse.useRod(s1, ITEM_OLD_ROD)
check(ok == false and kind == "rod", "useRod refuses the rod")
check(text == REFUSAL, "useRod hands the caller the refusal text")
check(BagMenu.messageText == REFUSAL, "the bag message is unchanged")
check(#fieldMessages == 0, "and useRod printed nothing by itself")
input:press("b")
BagMenu.handleInput(input)
check(BagMenu.mode == "list", "B pages out of the message back to the item list")
BagMenu.close()

print("[test] 3. showFieldMessage prefers the bag while the bag is open")
local s3 = new_session()
Bag.add(s3.bag, ITEM_OLD_ROD, 1)
BagMenu.show(s3, { session = s3, bag = s3.bag, pocket = "KEY_ITEMS" })
BagMenu.settle()
fieldMessages = {}
local shown = ItemUse.showFieldMessage(REFUSAL)
check(shown == true, "showFieldMessage reports it printed")
check(BagMenu.mode == "message" and BagMenu.messageText == REFUSAL,
  "the line went into the bag's message window")
check(#fieldMessages == 0, "and not to the field message box")
BagMenu.close()

print("[test] 4. with the bag closed the same call goes to the field box")
fieldMessages = {}
check(ItemUse.showFieldMessage(REFUSAL) == true, "showFieldMessage still prints")
check(fieldMessages[1] == REFUSAL,
  "the field message box got the line (got " .. tostring(fieldMessages[1]) .. ")")

print("[test] 5. a SELECT-registered rod prints its refusal through the Hud")
local s5 = new_session()
Bag.add(s5.bag, ITEM_OLD_ROD, 1)
s5.registeredItem = ITEM_OLD_ROD
fieldMessages = {}
-- pokefirered/src/item_menu.c:2022 UseRegisteredKeyItemOnField
Game3._handleRegisteredItem({ input = selectInput, session = s5 })
check(BagMenu.isOpen() == false, "no bag is involved")
check(fieldMessages[1] == REFUSAL,
  "the refusal reached src/ui/game3/hud.lua openMessage (got "
  .. tostring(fieldMessages[1]) .. ")")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

#!/usr/bin/env luajit
-- pokefirered/src/item_use.c:622 ItemUseOutOfBattle_EscapeRope
-- pokefirered/src/item_use.c:634 ItemUseOnFieldCB_EscapeRope
-- pokefirered/src/item_use.c:642 Task_UseDigEscapeRopeOnField

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local warps = {}
package.loaded["src.core.game3.warp"] = {
  request = function(_mod, _game, mapId, x, y, facing)
    warps[#warps + 1] = { map = mapId, x = x, y = y, facing = facing }
    return true
  end,
  isBusy = function() return false end,
}

local fieldMessages = {}
local fieldDone = nil
package.loaded["src.ui.game3.message"] = {
  show = function(text, opts)
    fieldMessages[#fieldMessages + 1] = tostring(text)
    fieldDone = type(opts) == "table" and opts.done or (type(opts) == "function" and opts or nil)
  end,
  showStay = function(text) fieldMessages[#fieldMessages + 1] = tostring(text) end,
  close = function() end,
  isOpen = function() return false end,
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
Cache.mountOrSkip("escape rope message + warp order", "map_tree/census.json")

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local ItemsData = require("src.core.game3.items_data")
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Runtime = require("src.core.game3.runtime")
local Strings = require("src.core.Strings")

local ITEM_ESCAPE_ROPE = 85 -- pokefirered/include/constants/items.h:89

local game = { data = {} }
Dataset.hydrate(game)
Runtime._game = game
Runtime._mod = {}

local CAVE = MapCatalog.pretToEngine("MtMoon_1F")
local HOUSE = MapCatalog.pretToEngine("PalletTown_PlayersHouse_1F")
check(CAVE ~= nil and game.data.maps[CAVE] ~= nil, "MtMoon_1F is in the cache")
check(HOUSE ~= nil and game.data.maps[HOUSE] ~= nil, "PalletTown_PlayersHouse_1F is in the cache")
if not (CAVE and HOUSE) then finish() end

local input = {
  _p = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function() return false end,
  press = function(self, key) self._p = { [key] = true } end,
}

local function new_session(mapId)
  return {
    name = "RED", map = mapId, party = {}, flags = {}, vars = {},
    healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5,
    bag = Bag.new(),
  }
end

local function use_from_bag(session, id)
  BagMenu.show(session, { session = session, bag = session.bag, pocket = "ITEMS" })
  BagMenu.settle()
  local want = ItemsData.toNumericId(id)
  for i, r in ipairs(BagMenu.list()) do
    if ItemsData.toNumericId(r.id) == want then BagMenu.cursor = i end
  end
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

-- pokefirered/src/strings.c:197 gText_PlayerUsedVar2
local USED = Strings("%s used\nESCAPE ROPE.", "RED")

print("[test] 1. the bag fades out before the rope's line prints")
local s1 = new_session(CAVE)
Bag.add(s1.bag, ITEM_ESCAPE_ROPE, 1)
warps, fieldMessages, fieldDone = {}, {}, nil
check(use_from_bag(s1, ITEM_ESCAPE_ROPE), "the rope reached USE in the bag")
check(BagMenu.isOpen() == false, "the bag is gone before the line shows")
check(BagMenu.messageText ~= USED,
  "the line is not in the bag's own frame (got " .. tostring(BagMenu.messageText) .. ")")
check(fieldMessages[1] == USED,
  "DisplayItemMessageOnField carries gText_PlayerUsedVar2 (got "
    .. tostring(fieldMessages[1]) .. ")")
check(#warps == 0, "and nothing warped while the message was up")
-- pokefirered/src/item_use.c:573 RemoveUsedItem
check(Bag.get(s1.bag, ITEM_ESCAPE_ROPE) == 0, "the rope was consumed")

print("[test] 2. dismissing the field box warps exactly once")
check(type(fieldDone) == "function", "the field box carries the follow-up task")
if type(fieldDone) == "function" then fieldDone() end
check(#warps == 1, "Warp.request ran exactly once (got " .. #warps .. ")")
check(warps[1] and warps[1].map == "FR_PLAYERS_HOUSE_1F"
  and warps[1].x == 8 and warps[1].y == 5,
  "it warps to the last heal spot")

print("[test] 3. with the bag closed the line goes to the field box first")
local s3 = new_session(CAVE)
Bag.add(s3.bag, ITEM_ESCAPE_ROPE, 1)
warps, fieldMessages, fieldDone = {}, {}, nil
local ok, kind, text = ItemUse.useField(s3, s3.bag, ITEM_ESCAPE_ROPE, nil)
check(ok == true and kind == "escape", "useField accepts the rope in a cave")
check(text == USED, "it hands the caller the same line")
check(fieldMessages[1] == USED,
  "the field message box got it (got " .. tostring(fieldMessages[1]) .. ")")
check(#warps == 0, "no warp while the box is open")
check(type(fieldDone) == "function", "the box carries the follow-up task")
fieldDone()
check(#warps == 1, "closing the box runs the warp (got " .. #warps .. ")")

print("[test] 4. a map with allowEscaping 0 refuses it and moves nothing")
local s4 = new_session(HOUSE)
Bag.add(s4.bag, ITEM_ESCAPE_ROPE, 1)
warps, fieldMessages = {}, {}
local okH, kindH, textH = ItemUse.useField(s4, s4.bag, ITEM_ESCAPE_ROPE, nil)
check(okH == false and kindH == "escape", "the rope is refused indoors")
check(textH == Strings("OAK: This isn't the\ntime to use that!"), "with OAK's refusal")
check(#warps == 0, "nothing warped")
check(Bag.get(s4.bag, ITEM_ESCAPE_ROPE) == 1, "and the rope was not consumed")

print("[test] 5. a recorded escape warp beats the heal spot")
-- pokefirered/src/field_effect.c:2126 SetWarpDestinationToEscapeWarp
local s5 = new_session(CAVE)
-- pokefirered/src/overworld.c:651 SetEscapeWarp
s5.escapeWarp = { map = MapCatalog.pretToEngine("Route4"), warpId = 255, x = 16, y = 6 }
Bag.add(s5.bag, ITEM_ESCAPE_ROPE, 1)
warps, fieldMessages, fieldDone = {}, {}, nil
check(ItemUse.useField(s5, s5.bag, ITEM_ESCAPE_ROPE, nil) == true, "the rope is accepted")
if type(fieldDone) == "function" then fieldDone() end
check(#warps == 1, "it warped once (got " .. #warps .. ")")
check(warps[1] and warps[1].map == s5.escapeWarp.map
  and warps[1].x == 16 and warps[1].y == 6,
  "to the doorstep UpdateEscapeWarp recorded, got " .. tostring(warps[1] and warps[1].map))

finish()

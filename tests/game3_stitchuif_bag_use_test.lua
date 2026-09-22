#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_stitchuif_bag_use_test")

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

local water = {}
package.loaded["src.core.game3.collision"] = {
  isWater = function(cx, cy) return water[cx .. "," .. cy] == true end,
  behavior = function() return nil end,
  behaviorOn = function() return nil end,
  isSurfable = function() return false end,
  cell = function() return 0xff end,
}

local mapShown = 0
package.loaded["src.ui.game3.region_map"] = {
  show = function() mapShown = mapShown + 1 end,
  isOpen = function() return false end,
  close = function() end,
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
local Field = require("src.core.game3.field")
local Player = require("src.core.game3.player")
local Strings = require("src.core.Strings")

local input = {
  _p = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function() return false end,
  press = function(self, key) self._p = { [key] = true } end,
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
  fieldMessages = {}
  BagMenu.show(session, { session = session, bag = session.bag, pocket = pocket })
  BagMenu.settle()
  local i = row_index(id)
  if not i then return nil, "not in " .. tostring(pocket) end
  BagMenu.cursor = i
  input:press("a")
  BagMenu.handleInput(input)
  if BagMenu.mode ~= "action" then return nil, "no action menu" end
  for k, a in ipairs(BagMenu.ACTIONS) do
    if a == "USE" then BagMenu.actionCursor = k end
  end
  input:press("a")
  BagMenu.handleInput(input)
  local exiting = BagMenu._exit ~= nil
  BagMenu.settle()
  return exiting
end

local function new_session()
  return { name = "RED", party = {}, bag = Bag.new(), map = "FR_PALLET_TOWN" }
end

print("[test] 1. REPEL prints its message in the bag (item_use.c:569)")
local s1 = new_session()
Bag.add(s1.bag, "REPEL", 2)
local exiting = use_from_bag(s1, "REPEL", "ITEMS")
check(exiting == false, "repel does not exit the bag")
check(BagMenu.isOpen() == true, "bag stays open")
check(BagMenu.mode == "message", "bag is in message mode (got " .. tostring(BagMenu.mode) .. ")")
check(BagMenu.messageText == Strings("The repelling effect wore\non for a while."),
  "repel text is on screen (got " .. tostring(BagMenu.messageText) .. ")")
check(s1.repelSteps == 100, "repel step counter armed")
check(Bag.get(s1.bag, "REPEL") == 1, "one REPEL consumed")
input:press("b")
BagMenu.handleInput(input)
check(BagMenu.mode == "list" and BagMenu.messageText == nil,
  "B returns to the item list (item_use.c:186 Task_ReturnToBagFromContextMenu)")
BagMenu.close()

print("[test] 2. A key item with no field use prints OAK's refusal (item_use.c:193)")
local s2 = new_session()
Bag.add(s2.bag, "SILPH_SCOPE", 1)
use_from_bag(s2, "SILPH_SCOPE", "KEY_ITEMS")
check(BagMenu.mode == "message", "refusal shows in the bag")
check(BagMenu.messageText == Strings("OAK: This isn't the\ntime to use that!"),
  "OAK refusal text (got " .. tostring(BagMenu.messageText) .. ")")
check(Bag.get(s2.bag, "SILPH_SCOPE") == 1, "key item not consumed")
BagMenu.close()

print("[test] 3. ESCAPE ROPE with nowhere to go refuses in the bag (item_use.c:622)")
local s3 = new_session()
Bag.add(s3.bag, "ESCAPE_ROPE", 1)
use_from_bag(s3, "ESCAPE_ROPE", "ITEMS")
check(BagMenu.mode == "message", "escape refusal shows in the bag")
check(BagMenu.messageText == Strings("OAK: This isn't the\ntime to use that!"),
  "escape refusal text")
check(Bag.get(s3.bag, "ESCAPE_ROPE") == 1, "escape rope not consumed")
BagMenu.close()

print("[test] 4. TOWN MAP opens the region map without a bag message (item_use.c:649)")
local s4 = new_session()
Bag.add(s4.bag, "TOWN_MAP", 1)
mapShown = 0
use_from_bag(s4, "TOWN_MAP", "KEY_ITEMS")
check(mapShown == 1, "region map opened")
check(BagMenu.mode == "list", "bag stays on the item list")
check(BagMenu.messageText == nil, "no message text leaks into the bag")
BagMenu.close()

print("[test] 5. A rod out of water refuses in the bag (item_use.c:294)")
water = {}
Player.cellX, Player.cellY, Player.facing, Player.surfing = 5, 5, "down", false
local s5 = new_session()
Bag.add(s5.bag, "OLD_ROD", 1)
use_from_bag(s5, "OLD_ROD", "KEY_ITEMS")
check(BagMenu.messageText == Strings("OAK: %s!\nThis isn't the time to use that!", "RED"),
  "rod refusal text is kept (got " .. tostring(BagMenu.messageText) .. ")")
check(BagMenu.isOpen() == true and BagMenu.mode == "message",
  "the rod refusal keeps the bag open (item_use.c:186)")
check(#fieldMessages == 0,
  "and prints nothing on the field (got " .. tostring(fieldMessages[1]) .. ")")
check(Field.isFishing() == false, "no fishing started")
BagMenu.close()

print("[test] 6. A rod facing water exits the bag and fishes (item_use.c:286)")
water = { ["5,6"] = true }
Player.cellX, Player.cellY, Player.facing, Player.surfing = 5, 5, "down", false
local s6 = new_session()
Bag.add(s6.bag, "OLD_ROD", 1)
local rodExit = use_from_bag(s6, "OLD_ROD", "KEY_ITEMS")
check(rodExit == true, "rod USE schedules the bag exit")
check(BagMenu.isOpen() == false, "bag is closed once the exit runs")
check(Field.isFishing() == true, "fishing task is running")
check(#fieldMessages == 0, "and the rod prints no field message on the way out")

print("[test] 7. the POKé FLUTE plays in the bag (item_use.c:381)")
local s7 = new_session()
s7.party = { { species = 16, level = 5, hp = 10, maxHp = 10, status = nil } }
Bag.add(s7.bag, 350, 1)
local fluteExit = use_from_bag(s7, 350, "KEY_ITEMS")
check(fluteExit == false, "the flute does not exit the bag")
check(BagMenu.isOpen() == true, "the bag is still open after the flute")
check(BagMenu.mode == "message", "the flute message is in the bag (got "
  .. tostring(BagMenu.mode) .. ")")
check(BagMenu.messageText == Strings("Played the POKé FLUTE."),
  "the first page is gText_PlayedPokeFlute (got " .. tostring(BagMenu.messageText) .. ")")
check(#fieldMessages == 0,
  "nothing was printed on the field (got " .. tostring(fieldMessages[1]) .. ")")
input:press("a")
BagMenu.handleInput(input)
check(BagMenu.mode == "message"
  and tostring(BagMenu.messageText):find("catchy tune", 1, true) ~= nil,
  "A turns to the second page in the same window (got " .. tostring(BagMenu.messageText) .. ")")
input:press("b")
BagMenu.handleInput(input)
check(BagMenu.mode == "list" and BagMenu.isOpen(),
  "the last page drops back to the item list with the bag still open")
BagMenu.close()

print("[test] 8. the WHITE FLUTE prints in the bag too (item_use.c:610)")
local s8 = new_session()
Bag.add(s8.bag, 43, 1)
use_from_bag(s8, 43, "ITEMS")
check(BagMenu.isOpen() == true and BagMenu.mode == "message",
  "the white flute keeps the bag open with its message")
check(BagMenu.messageText == Strings("%s used the\n%s.", "RED", "WHITE FLUTE"),
  "the first page names the item used (got " .. tostring(BagMenu.messageText) .. ")")
input:press("a")
BagMenu.handleInput(input)
check(tostring(BagMenu.messageText):find("lured", 1, true) ~= nil,
  "gText_UsedVar2WildLured is the second page (got " .. tostring(BagMenu.messageText) .. ")")
check(#fieldMessages == 0, "and the field printed nothing")
BagMenu.close()

print("[test] 9. the BICYCLE refusal indoors prints in the bag (item_use.c:266)")
local s9 = new_session()
s9.map = "FR_PLAYERS_HOUSE_1F"
Bag.add(s9.bag, 360, 1)
local bikeExit = use_from_bag(s9, 360, "KEY_ITEMS")
check(bikeExit == false, "a refused bike does not exit the bag")
check(BagMenu.isOpen() == true and BagMenu.mode == "message",
  "the bike refusal keeps the bag open")
check(BagMenu.messageText == Strings("OAK: This isn't the\ntime to use that!"),
  "the refusal text is the bag message (got " .. tostring(BagMenu.messageText) .. ")")
check(#fieldMessages == 0, "and nothing was printed on the field")
BagMenu.close()

print("[test] 10. the BICYCLE outdoors still exits the bag to the field (item_use.c:159)")
local s10 = new_session()
Bag.add(s10.bag, 360, 1)
local bikeOn = use_from_bag(s10, 360, "KEY_ITEMS")
check(bikeOn == true, "the bike schedules the bag exit")
check(BagMenu.isOpen() == false, "the bag is closed once the exit runs")
check(Player.biking == true, "the player is on the bike")
check(#fieldMessages == 0, "and no message is printed at all (item_use.c:253)")
check(BagMenu.messageText == nil, "not even in the bag")
Player.biking = false

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

#!/usr/bin/env luajit
-- pokefirered/src/item_menu.c:2022 UseRegisteredKeyItemOnField
-- pokefirered/src/item_use.c:348 FieldUseFunc_PowderJar
-- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback

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

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

local fieldMessages = {}
package.loaded["src.ui.game3.message"] = {
  show = function(text) fieldMessages[#fieldMessages + 1] = tostring(text) end,
  showStay = function(text) fieldMessages[#fieldMessages + 1] = tostring(text) end,
  close = function() end,
  isOpen = function() return false end,
}

local seekerUses = 0
local seekerAllowed = true
package.loaded["src.core.game3.vs_seeker"] = {
  ITEM_VS_SEEKER = 362,
  use = function() seekerUses = seekerUses + 1 return true end,
  canUseHere = function() return seekerAllowed end,
  notTimeText = function() return "OAK: RED!\nThis isn't the time to use that!" end,
  onStep = function() return false end,
}

local ItemsData = require("src.core.game3.items_data")
ItemsData.install(nil)
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local ItemUse = require("src.core.game3.item_use")
local Player = require("src.core.game3.player")
local Strings = require("src.core.Strings")
local Game3 = require("src.core.Game3")

local ITEM_POWDER_JAR = 372 -- pokefirered/include/constants/items.h:444
local ITEM_VS_SEEKER = 362 -- pokefirered/include/constants/items.h:434
local ITEM_BICYCLE = 360 -- pokefirered/include/constants/items.h:432

local selectInput = {
  wasPressed = function(_, key) return key == "select" end,
  isDown = function() return false end,
}
local idleInput = {
  wasPressed = function() return false end,
  isDown = function() return false end,
}

local function new_session(item)
  local s = { name = "RED", party = {}, bag = Bag.new(), map = "FR_PALLET_TOWN",
    flags = {}, vars = {}, berryPowder = 0 }
  if item then
    Bag.add(s.bag, item, 1)
    s.registeredItem = item
  end
  return s
end

local function press_select(session)
  fieldMessages = {}
  Game3._handleRegisteredItem({ input = selectInput, session = session })
end

print("[test] 1. SELECT on a registered POWDER JAR prints its line")
local s1 = new_session(ITEM_POWDER_JAR)
s1.berryPowder = 1234
press_select(s1)
-- pokefirered/src/strings.c:202 gText_PowderQty
check(fieldMessages[1] == Strings("POWDER QTY: %d", 1234),
  "the jar's count is on screen (got " .. tostring(fieldMessages[1]) .. ")")
check(Bag.get(s1.bag, ITEM_POWDER_JAR) == 1, "and the jar is not consumed")

print("[test] 2. no SELECT press, no message")
fieldMessages = {}
Game3._handleRegisteredItem({ input = idleInput, session = s1 })
check(#fieldMessages == 0, "nothing printed without the button")

print("[test] 3. a registered item the bag no longer holds unregisters itself")
local s3 = new_session(ITEM_POWDER_JAR)
Bag.remove(s3.bag, ITEM_POWDER_JAR, 1)
press_select(s3)
check(s3.registeredItem == nil, "the registration was dropped")
check(#fieldMessages == 0, "and nothing printed")

print("[test] 4. the VS SEEKER arm keeps its own behaviour")
local s4 = new_session(ITEM_VS_SEEKER)
seekerUses, seekerAllowed = 0, true
press_select(s4)
check(seekerUses == 1, "an allowed VS SEEKER runs VsSeeker.use (got " .. seekerUses .. ")")
check(#fieldMessages == 0, "and prints no message of its own")
seekerAllowed = false
press_select(s4)
check(seekerUses == 1, "a refused one does not run")
check(fieldMessages[1] ~= nil and fieldMessages[1]:find("time to use that", 1, true) ~= nil,
  "it prints the refusal instead (got " .. tostring(fieldMessages[1]) .. ")")

print("[test] 5. mounting the bike from SELECT stays silent")
local s5 = new_session(ITEM_BICYCLE)
Player.biking = false
press_select(s5)
-- pokefirered/src/item_use.c:276 ItemUseOnFieldCB_Bicycle
check(Player.biking == true, "the player got on the bike")
check(#fieldMessages == 0,
  "and no message was printed (got " .. tostring(fieldMessages[1]) .. ")")
s5.map = "FR_PLAYERS_HOUSE_1F"
Player.biking = false
press_select(s5)
check(Player.biking == false, "indoors the bike is refused")
check(fieldMessages[1] == Strings("OAK: This isn't the\ntime to use that!"),
  "and the refusal does print (got " .. tostring(fieldMessages[1]) .. ")")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

#!/usr/bin/env luajit

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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return { setFilter = function() end, getDimensions = function() return 8, 8 end } end
_G.love = { graphics = gfx }

local Storage = require("src.core.game3.storage")
local Flags = require("src.core.game3.scripting.flags")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")

-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037
-- pokefirered/include/constants/flags.h:1401
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local activeSession = nil
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return activeSession end,
}

local function new_session()
  local session = { party = {}, store = Flags.newStore(), dex = { seen = {}, owned = {} } }
  Storage.ensure(session)
  activeSession = session
  return session
end

local function getVar(session)
  return Flags.getVar(session.store, nil, VAR_PC_BOX_TO_SEND_MON)
end

local function getFlag(session)
  return Flags.getFlag(session.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE) and true or false
end

local key = nil
local input = { wasPressed = function(_, k) return key == k end }

local function press(k)
  key = k
  BoxStorageUI.handleInput(input)
  key = nil
end

local function fill_box(session, boxId)
  local box = session.storage.boxes[boxId]
  for s = 1, Storage.IN_BOX_COUNT do
    box.mons[s] = { species = 19, speciesId = 19, level = 3, hp = 12, maxHp = 12 }
  end
end

print("[test] 1. leaving the PC on another box moves the send target (pokemon_storage_system_tasks.c:2763)")
local s1 = new_session()
s1.storage.currentBox = 3
Flags.setVar(s1.store, nil, VAR_PC_BOX_TO_SEND_MON, 2)
Flags.setFlag(s1.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
BoxStorageUI.show({ session = s1 })
check(BoxStorageUI.isOpen(), "the storage screen opened")
press("r")
eq(s1.storage.currentBox, 4, "R scrolled to the next box")
eq(getVar(s1), 2, "the send target is untouched while the screen is still up")
eq(getFlag(s1), true, "and so is the box-was-full latch")
press("b")
check(not BoxStorageUI.isOpen(), "B closed the storage screen")
eq(getVar(s1), 3, "leaving on BOX 4 writes its 0-based id")
eq(getFlag(s1), false, "and clears FLAG_SHOWN_BOX_WAS_FULL_MESSAGE")

print("[test] 2. leaving on the box you entered on changes nothing")
local s2 = new_session()
s2.storage.currentBox = 3
Flags.setVar(s2.store, nil, VAR_PC_BOX_TO_SEND_MON, 9)
Flags.setFlag(s2.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
BoxStorageUI.show({ session = s2 })
press("r")
press("l")
eq(s2.storage.currentBox, 3, "the player scrolled away and back")
press("b")
check(not BoxStorageUI.isOpen(), "the storage screen closed")
eq(getVar(s2), 9, "sLastUsedBox matched, so the send target is left alone")
eq(getFlag(s2), true, "and the latch stays set")

print("[test] 3. the CLOSE BOX button takes the same exit")
local s3 = new_session()
s3.storage.currentBox = 1
Flags.setVar(s3.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
Flags.setFlag(s3.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
BoxStorageUI.show({ session = s3 })
press("l")
eq(s3.storage.currentBox, Storage.TOTAL_BOXES_COUNT, "L wrapped round to the last box")
BoxStorageUI.cursorSlot = -20
press("a")
check(not BoxStorageUI.isOpen(), "CLOSE BOX closed the screen")
eq(getVar(s3), Storage.TOTAL_BOXES_COUNT - 1, "the send target follows the box the player left on")
eq(getFlag(s3), false, "and the latch is cleared")

print("[test] 4. the box the player left on is the one reported full")
local s4 = new_session()
s4.storage.currentBox = 3
Flags.setVar(s4.store, nil, VAR_PC_BOX_TO_SEND_MON, 2)
fill_box(s4, 4)
BoxStorageUI.show({ session = s4 })
press("r")
eq(s4.storage.currentBox, 4, "the player scrolled onto the full BOX 4")
press("b")
local ok, bId = Storage.sendMonToPC(s4, { species = 16, speciesId = 16, level = 5, hp = 20, maxHp = 20 })
check(ok, "a caught mon still reached the PC")
eq(bId, 5, "it spilled over into BOX 5")
local text = Storage.pcTransferMessage(s4, "MAGIKARP")
check(type(text) == "string" and text:find("was full", 1, true) ~= nil,
  "the transfer line reports a full box (" .. tostring(text) .. ")")
check(text:find("BOX “BOX 4”", 1, true) ~= nil or text:find("BOX 4", 1, true) ~= nil,
  "BOX 4 is named as the full one")
check(text:find("BOX 3", 1, true) == nil,
  "the box the player entered the PC on is not blamed")
check(text:find("BOX 5", 1, true) ~= nil, "and BOX 5 is named as the destination")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")

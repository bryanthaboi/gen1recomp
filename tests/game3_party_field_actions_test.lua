package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

require("src.core.GameVersion").set("firered")
package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end, playSong = function() end, stopAll = function() end,
}
package.loaded["src.core.game3.map"] = { currentDef = function() return {} end }
package.loaded["src.core.game3.collision"] = {
  isWater = function() return false end, isGrass = function() return false end,
  behavior = function() return 0 end,
}
package.loaded["src.core.game3.objects"] = { at = function() return nil end }
package.loaded["src.core.game3.scripting.space"] = { store = nil }
package.loaded["src.core.game3.field"] = { executeFieldMove = function() end }

local PartyMenu = require("src.ui.game3.party_menu")
PartyMenu.heldItemSheet = function() return nil end
local Mail = require("src.core.game3.mail")

local function input(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function(_, k) return k == key end }
end
local function press(key) PartyMenu.handleInput(input(key)) end

local TACKLE = 33
local ORANGE_MAIL = 121
local function newMon(extra)
  local m = { species = 6, level = 40, hp = 100, maxHp = 100, stats = { hp = 100 }, moves = { TACKLE }, pp = { 35 } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local function rows(party, session)
  PartyMenu.show(party, nil, { session = session or {} })
  press("a")
  local out = {}
  for i, act in ipairs(PartyMenu.ACTIONS) do out[i] = type(act) == "table" and act.action or act end
  return table.concat(out, ","), out
end

local one = rows({ newMon() })
check(one == "SUMMARY,ITEM,CANCEL", "one-mon party lists no SWITCH (" .. one .. ")")
PartyMenu.close()

local two = rows({ newMon(), newMon() })
check(two == "SUMMARY,SWITCH,ITEM,CANCEL", "two-mon party lists SWITCH (" .. two .. ")")
PartyMenu.close()

local egg = rows({ newMon({ isEgg = true }), newMon() })
check(egg == "SUMMARY,SWITCH,CANCEL", "an egg lists SUMMARY, SWITCH, CANCEL (" .. egg .. ")")
PartyMenu.close()

local session = { mail = {} }
local mailMon = newMon({ item = ORANGE_MAIL, heldItem = ORANGE_MAIL })
local mailId = Mail.giveMailToMon(session, mailMon, ORANGE_MAIL)
check(mailId == 0, "mail record attached to the mon")
local withMail, list = rows({ mailMon, newMon() }, session)
check(withMail == "SUMMARY,SWITCH,MAIL,CANCEL", "a mon holding MAIL lists MAIL, not ITEM (" .. withMail .. ")")

local mailIndex
for i, act in ipairs(list) do if act == "MAIL" then mailIndex = i end end
PartyMenu.actionCursor = mailIndex or 1
press("a")
check(PartyMenu.mode == "item_action", "MAIL opens the mail submenu")
check(table.concat(PartyMenu.ITEM_ACTIONS, ",") == "READ,TAKE_MAIL,CANCEL2",
  "FRLG mail submenu is READ / TAKE MAIL / CANCEL (" .. table.concat(PartyMenu.ITEM_ACTIONS, ",") .. ")")
check(PartyMenu._actionTextsFor(PartyMenu.ITEM_ACTIONS)[1] == "sCursorOptions[8]",
  "READ label is sCursorOptions[CURSOR_OPTION_READ]")
check(PartyMenu._actionTextsFor(PartyMenu.ITEM_ACTIONS)[2] == "sCursorOptions[7]",
  "TAKE MAIL label is sCursorOptions[CURSOR_OPTION_TAKE_MAIL]")

local readArgs
package.loaded["src.ui.game3.mail"] = { read = function(mail, opts) readArgs = { mail = mail, opts = opts } end }
PartyMenu.itemActionCursor = 1
press("a")
check(readArgs == nil and PartyMenu._fadeDir == 1, "READ fades the party to black before the reader opens")
local fadeFrames = 0
for _ = 1, 16 do
  if readArgs then break end
  PartyMenu.update(1 / 60)
  fadeFrames = fadeFrames + 1
end
check(readArgs ~= nil and fadeFrames == 4, "the party fade out takes 4 frames (" .. fadeFrames .. ")")
readArgs.opts.onClose()
check(PartyMenu.mode == "action" and PartyMenu._fade == 16, "closing the mail returns to a black action list")
press("b")
check(PartyMenu.mode == "action", "input waits for the fade in")
for _ = 1, 4 do PartyMenu.update(1 / 60) end
check(PartyMenu._fade == 0 and PartyMenu._fadeDir == 0, "the party fades back in")
package.loaded["src.ui.game3.mail"] = nil
PartyMenu.actionCursor = mailIndex or 1
press("a")
check(PartyMenu.mode == "item_action", "MAIL reopens the mail submenu after the fade in")

PartyMenu.itemActionCursor = #PartyMenu.ITEM_ACTIONS
press("a")
check(PartyMenu.mode == "action", "mail CANCEL returns to the action list")

PartyMenu.actionCursor = mailIndex or 1
press("a")
PartyMenu.itemActionCursor = 2
press("a")
check(PartyMenu.mode == "yesno" and PartyMenu._yesNoPrompt == "gText_SendMailToPC",
  "TAKE MAIL opens the send-to-PC YES/NO with no extra A press")
PartyMenu._yesNoCallback(false)
check(PartyMenu.mode == "yesno" and PartyMenu._yesNoPrompt == "gText_MailMessageWillBeLost",
  "NO opens the lose-message YES/NO with no extra A press")
PartyMenu._yesNoCallback(false)
check(PartyMenu.mode == "list" and (tonumber(mailMon.item) or 0) == ORANGE_MAIL, "NO again keeps the mail on the mon")
press("a")
PartyMenu.actionCursor = mailIndex or 1
press("a")
PartyMenu.itemActionCursor = 2
press("a")
local cb = PartyMenu._yesNoCallback
PartyMenu.mode = "list"
cb(true)
check(PartyMenu._messageText == "gText_MailSentToPC", "YES sends the mail to the PC")
check((tonumber(mailMon.item) or 0) == 0 and mailMon.mail == Mail.MAIL_NONE, "the mon no longer holds the mail")
check(Mail.get(session, 6) ~= nil and Mail.get(session, 0) == nil, "the mail moved to the first PC mailbox slot")
PartyMenu.close()

if failed > 0 then print(failed .. " failure(s)") os.exit(1) end
print("all passed")

local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_party_mail_f21",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_mail_f21")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Mail = require("src.core.game3.mail")
  local Screens = require("src.ui.game3.screens")
  local session = Runtime.getSession()
  local version = session.version
  local rse = require("src.core.game3.profile").family(session) == "rse"
  local C = require("src.core.game3.constants").of(version)
  F.settle(game, 300)

  session.party = {}
  Party.giveMon(session, C:require("species", rse and "SPECIES_ZIGZAGOON" or "SPECIES_RATTATA"), 10)
  local function rows()
    local out = {}
    local PartyMenu = Screens.get("party", session)
    for i, act in ipairs(PartyMenu.ACTIONS or {}) do out[i] = type(act) == "table" and act.action or act end
    return table.concat(out, ",")
  end

  local PartyMenu = Screens.get("party", session)
  PartyMenu.show(session.party, session.move_overlay, { session = session })
  U.wait(20)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  S.check(rows() == "SUMMARY,ITEM,CANCEL", "f21 " .. version .. " one-mon party has no SWITCH (" .. rows() .. ")")
  S.still(game, "f21_" .. version .. "_01_one_mon_no_switch.png")
  PartyMenu.close()
  U.wait(20)

  Party.giveMon(session, C:require("species", rse and "SPECIES_WURMPLE" or "SPECIES_PIDGEY"), 10)
  local mail = C:require("items", rse and "ITEM_ORANGE_MAIL" or "ITEM_ORANGE_MAIL")
  local mon = session.party[1]
  local id = Mail.giveMailToMon(session, mon, mail)
  S.check(id ~= Mail.MAIL_NONE, "f21 " .. version .. " mail attached to the lead mon")
  PartyMenu.show(session.party, session.move_overlay, { session = session })
  U.wait(20)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  S.check(rows() == "SUMMARY,SWITCH,MAIL,CANCEL", "f21 " .. version .. " mail holder lists SWITCH and MAIL (" .. rows() .. ")")
  PartyMenu.actionCursor = 3
  U.tap(game, "a")
  U.wait(10)
  local sub = table.concat(PartyMenu.ITEM_ACTIONS or {}, ",")
  S.check(sub == "READ,TAKE_MAIL,CANCEL2",
    "f21 " .. version .. " mail submenu (" .. sub .. ")")
  S.still(game, "f21_" .. version .. "_02_mail_submenu.png")

  do
    PartyMenu.itemActionCursor = 1
    U.tap(game, "a")
    U.wait(60)
    local MailRead = require(rse and "src.ui.game3.rse.mail" or "src.ui.game3.mail")
    S.check(MailRead.isOpen(), "f21 " .. version .. " READ opens the held mail")
    S.still(game, "f21_" .. version .. "_03_read_mail.png")
    for _ = 1, 120 do
      if not MailRead.isOpen() then break end
      U.tap(game, "b")
      U.wait(5)
    end
    U.wait(30)
    S.check(not MailRead.isOpen() and PartyMenu.mode == "action", "f21 " .. version .. " closing the mail returns to the action list")
    PartyMenu.actionCursor = 3
    U.tap(game, "a")
    U.wait(10)
  end

  PartyMenu.itemActionCursor = 2
  U.tap(game, "a")
  for _ = 1, 300 do
    if PartyMenu.mode ~= "item_action" then break end
    U.wait(1)
  end
  S.check(PartyMenu.mode == "yesno", "f21 " .. version .. " TAKE MAIL opens the send-to-PC YES/NO with no extra A press")
  U.wait(30)
  S.still(game, "f21_" .. version .. "_04_take_mail_yesno.png")
  PartyMenu._yesNoCursor = 1
  U.tap(game, "a")
  U.wait(30)
  S.check((tonumber(mon.item) or 0) == 0 and Mail.get(session, 6) ~= nil,
    "f21 " .. version .. " YES moves the mail to the PC mailbox")
  for _ = 1, 120 do
    if PartyMenu.mode ~= "message" then break end
    U.tap(game, "a")
    U.wait(5)
  end
  PartyMenu.close()
  S.finish()
end

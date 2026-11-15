local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_frlg_mail_f27",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_frlg_mail_f27")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Mail = require("src.core.game3.mail")
  local Bag = require("src.core.game3.bag")
  local Screens = require("src.ui.game3.screens")
  local EasyChatText = require("src.core.game3.easy_chat_text")
  local session = Runtime.getSession()
  local version = session.version
  local C = require("src.core.game3.constants").of(version)
  F.settle(game, 300)

  local cache = require("src.core.game3.dataset").cache()
  local manifest = cache:read("data/generated/gba/mail/manifest.lua")
  if not S.check(type(manifest) == "string" and #manifest > 0, "f27 " .. version .. " cache has the mail graphics") then
    return S.finish()
  end
  local okReader, MailRead = pcall(require, "src.ui.game3.mail")
  if not S.check(okReader and type(MailRead) == "table" and MailRead.read ~= nil, "f27 " .. version .. " FRLG mail reader exists") then
    return S.finish()
  end
  local Mailbox = require("src.ui.game3.mailbox")
  local PcMenu = require("src.ui.game3.pc_menu")

  local BEAD = C:require("items", "ITEM_BEAD_MAIL")
  local DREAM = C:require("items", "ITEM_DREAM_MAIL")
  local WORDS = EasyChatText.DEFAULT_PROFILE
  local function setWords(record)
    for i = 1, Mail.MAIL_WORDS_COUNT do record.words[i] = WORDS[(i - 1) % #WORDS + 1] end
  end
  local function expectLine(record)
    return EasyChatText.word(record.words[1]) .. " " .. EasyChatText.word(record.words[2])
  end
  local function waitOpen(mod, open, n)
    for _ = 1, n or 200 do
      if mod.isOpen() == open and (not open or (mod._fade or 0) == 0) then return true end
      U.wait(1)
    end
    return false
  end
  local function waitFade(mod)
    for _ = 1, 60 do
      if (mod._fadeDir or 0) == 0 and (mod._fade or 0) == 0 then return true end
      U.wait(1)
    end
    return false
  end

  session.name = "RED"
  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_BULBASAUR"), 10)
  Party.giveMon(session, C:require("species", "SPECIES_PIDGEY"), 10)
  local mon = session.party[1]
  local id = Mail.giveMailToMon(session, mon, BEAD)
  S.check(id ~= Mail.MAIL_NONE, "f27 " .. version .. " BEAD MAIL attached to the lead mon")
  local partyMail = Mail.get(session, id)
  setWords(partyMail)

  local PartyMenu = Screens.get("party", session)
  PartyMenu.show(session.party, session.move_overlay, { session = session })
  U.wait(20)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  PartyMenu.actionCursor = 3
  U.tap(game, "a")
  U.wait(10)
  local sub = table.concat(PartyMenu.ITEM_ACTIONS or {}, ",")
  S.check(sub == "READ,TAKE_MAIL,CANCEL2", "f27 " .. version .. " party MAIL submenu has READ (" .. sub .. ")")
  S.still(game, "f27_" .. version .. "_01_party_mail_submenu.png")

  PartyMenu.itemActionCursor = 1
  U.tap(game, "a")
  S.check(not MailRead.isOpen() and PartyMenu._fadeDir == 1, "f27 " .. version .. " party READ fades to black first")
  S.check(waitOpen(MailRead, true), "f27 " .. version .. " party READ opens the FRLG mail reader")
  S.check(MailRead._design == 6 and MailRead._hasText, "f27 " .. version .. " BEAD MAIL design with its message")
  S.check(MailRead._lines[1] == expectLine(partyMail), "f27 " .. version .. " first line is the mail's words ("
    .. tostring(MailRead._lines[1]) .. ")")
  S.check(MailRead._icon == C:require("species", "SPECIES_BULBASAUR") and MailRead._iconPos[1] == 0x60,
    "f27 " .. version .. " BEAD MAIL shows the sender mon icon at 0x60,0x80")
  S.check(MailRead._author ~= "RED" and MailRead._author:find("\xEF\xBC", 1, true) ~= nil,
    "f27 " .. version .. " a name under six letters prints in the Japanese font")
  S.still(game, "f27_" .. version .. "_02_party_read_bead_mail.png")
  U.tap(game, "b")
  S.check(waitOpen(MailRead, false), "f27 " .. version .. " B closes the mail")
  S.check(waitFade(PartyMenu), "f27 " .. version .. " the party fades back in")
  S.check(PartyMenu.mode == "action", "f27 " .. version .. " closing the mail returns to the action list")

  PartyMenu.actionCursor = 3
  U.tap(game, "a")
  U.wait(10)
  PartyMenu.itemActionCursor = 2
  U.tap(game, "a")
  for _ = 1, 300 do
    if PartyMenu.mode == "yesno" then break end
    if PartyMenu.mode == "message" then U.tap(game, "a") end
    U.wait(2)
  end
  PartyMenu._yesNoCursor = 1
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 120 do
    if PartyMenu.mode ~= "message" then break end
    U.tap(game, "a")
    U.wait(5)
  end
  S.check((tonumber(mon.item) or 0) == 0 and Mail.get(session, 6) ~= nil,
    "f27 " .. version .. " TAKE MAIL sent the mail to the PC mailbox")
  PartyMenu.close()
  U.wait(20)

  local pool = Mail.pool(session)
  local dream = Mail.clear(pool[Mail.PARTY_SIZE + 2])
  dream.itemId, dream.design = DREAM, Mail.designOf(DREAM)
  dream.playerName = "LEAFGRN"
  dream.species = C:require("species", "SPECIES_PIKACHU")
  setWords(dream)

  PcMenu.show({ session = session })
  U.wait(10)
  PcMenu.mode = "player_pc"
  PcMenu.cursor = 2
  U.tap(game, "a")
  U.wait(10)
  S.check(Mailbox.isOpen() and Mailbox.count() == 2, "f27 " .. version .. " PC MAILBOX lists the two stored mails")
  S.check(Mailbox.state == "list", "f27 " .. version .. " mailbox opens on its list")
  S.still(game, "f27_" .. version .. "_03_mailbox_list.png")

  U.tap(game, "a")
  U.wait(10)
  S.check(Mailbox.state == "options" and tostring(Mailbox._status):find("MAIL", 1, true) ~= nil,
    "f27 " .. version .. " selecting a mail asks what to do with it")
  S.still(game, "f27_" .. version .. "_04_mailbox_options.png")
  U.tap(game, "a")
  S.check(not MailRead.isOpen() and Mailbox._fadeDir == 1, "f27 " .. version .. " mailbox READ fades to black first")
  S.check(waitOpen(MailRead, true), "f27 " .. version .. " mailbox READ opens the reader")
  S.check(MailRead._mail == Mail.get(session, 6), "f27 " .. version .. " mailbox READ shows the selected mail")
  S.still(game, "f27_" .. version .. "_05_mailbox_read_bead.png")
  U.tap(game, "a")
  S.check(waitOpen(MailRead, false), "f27 " .. version .. " A closes the mail")
  S.check(Mailbox.isOpen() and Mailbox.state == "list", "f27 " .. version .. " closing the mail returns to the mailbox list")
  U.wait(3)
  S.still(game, "f27_" .. version .. "_05b_mailbox_fading_in.png")
  S.check(waitFade(Mailbox), "f27 " .. version .. " the mailbox fades back in")

  U.tap(game, "down")
  U.wait(5)
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  S.check(waitOpen(MailRead, true) and MailRead._design == 9, "f27 " .. version .. " second mail reads as DREAM MAIL")
  S.check(MailRead._iconPos and MailRead._iconPos[1] == 0x28 and MailRead._author == "LEAFGRN",
    "f27 " .. version .. " DREAM MAIL icon at 0x28,0x80 and a seven-letter name in the Latin font")
  S.still(game, "f27_" .. version .. "_06_mailbox_read_dream.png")
  U.tap(game, "b")
  waitOpen(MailRead, false)
  waitFade(Mailbox)

  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "down")
  U.wait(5)
  U.tap(game, "a")
  U.wait(10)
  S.check(Mailbox.state == "confirm", "f27 " .. version .. " MOVE TO BAG asks to confirm")
  U.tap(game, "a")
  U.wait(10)
  S.check(Mailbox.state == "message" and Bag.has(session.bag, DREAM, 1) and Mailbox.count() == 1,
    "f27 " .. version .. " YES returns the DREAM MAIL to the bag and erases it")
  S.still(game, "f27_" .. version .. "_07_mail_returned_to_bag.png")
  U.tap(game, "a")
  U.wait(5)
  S.check(Mailbox.state == "list", "f27 " .. version .. " the message returns to the list")
  U.tap(game, "b")
  U.wait(5)
  S.check(not Mailbox.isOpen() and PcMenu.mode == "player_pc", "f27 " .. version .. " B leaves the mailbox for the PC menu")
  PcMenu.close()
  U.wait(10)
  S.finish()
end

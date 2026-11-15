local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_mailbox_give",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mailbox_give")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Mail = require("src.core.game3.mail")
  local RomText = require("src.core.game3.rom_text")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local PartyMenu = require("src.ui.game3.party_menu")
  local session = Runtime.getSession()
  local version = session.version
  local rse = require("src.core.game3.profile").family(session) == "rse"
  local Mailbox = require(rse and "src.ui.game3.rse.mailbox" or "src.ui.game3.mailbox")
  local C = require("src.core.game3.constants").of(version)
  local tag = "give " .. version .. " "
  F.settle(game, 300)

  local species = C:require("species", rse and "SPECIES_ZIGZAGOON" or "SPECIES_RATTATA")
  local ORANGE = C:require("items", "ITEM_ORANGE_MAIL")
  local HARBOR = C:require("items", "ITEM_HARBOR_MAIL")
  session.party = {}
  Party.giveEgg(session, species)
  Party.giveMon(session, species, 10)
  Party.giveMon(session, species, 10)
  local egg, plain, holder = session.party[1], session.party[2], session.party[3]
  holder.item = C:require("items", "ITEM_POTION")
  S.check(#session.party == 3 and egg.isEgg == true, tag .. "party is egg, plain mon, mon holding a POTION")

  local pool = Mail.pool(session)
  local function stash(slot, item, name)
    local m = Mail.clear(pool[Mail.PARTY_SIZE + slot])
    m.itemId, m.design = item, Mail.designOf(item)
    m.playerName = name
    m.species = species
    return m
  end
  stash(1, ORANGE, "MAY")
  stash(2, HARBOR, "WALLY")

  local played = {}
  local realSe = Audio.playSe
  Audio.playSe = function(id, ...)
    played[#played + 1] = id
    return realSe(id, ...)
  end
  local drawn = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, ...)
    drawn[tostring(text)] = true
    return realDraw(text, ...)
  end

  Mailbox.show({ session = session })
  U.wait(10)
  S.check(Mailbox.isOpen() and Mailbox.count() == 2, tag .. "mailbox lists the two stored mails")

  local rsUi = rse and require("src.ui.game3.rs.player_pc_policy").matches(session)
  local function settled()
    for _ = 1, 120 do
      local fading = (PartyMenu._fadeDir or 0) ~= 0
        or (rsUi and not require("src.ui.game3.rs.party_chrome").inputAllowed())
      if not fading then return end
      U.wait(1)
    end
  end

  local function mailboxSettled()
    for _ = 1, 60 do
      if (Mailbox._fadeDir or 0) == 0 then return true end
      U.wait(1)
    end
  end

  local function openOption(down)
    mailboxSettled()
    U.tap(game, "a")
    U.wait(8)
    for _ = 1, down do
      U.tap(game, "down")
      U.wait(4)
    end
    U.tap(game, "a")
  end

  local function openGive(shotName)
    openOption(2)
    S.check(not PartyMenu.open and (Mailbox._fadeDir or 0) > 0,
      tag .. "GIVE fades the mailbox to black before the party opens")
    if shotName then
      U.wait(3)
      S.still(game, shotName)
    end
    for _ = 1, 60 do
      if PartyMenu.open then break end
      U.wait(1)
    end
    U.wait(10)
    settled()
  end

  openOption(0)
  S.check(Mailbox.state == "options" and (Mailbox._fadeDir or 0) > 0,
    tag .. "READ fades the mailbox to black before the reader opens")
  U.wait(3)
  S.still(game, "mailbox_give_" .. version .. "_00a_read_fading_out.png")
  for _ = 1, 60 do
    if Mailbox.state == "reading" then break end
    U.wait(1)
  end
  S.check(Mailbox.state == "reading", tag .. "the reader opens once the fade ends")
  U.wait(40)
  for i = 1, 120 do
    if Mailbox.state == "list" then break end
    if Mailbox.state == "reading" and i % 10 == 1 then U.tap(game, "b") end
    U.wait(1)
  end
  S.check(Mailbox.state == "list" and (Mailbox._fade or 0) > 0,
    tag .. "closing the reader returns to a black mailbox list (" .. tostring(Mailbox._fade) .. ")")
  U.wait(3)
  S.still(game, "mailbox_give_" .. version .. "_00b_list_fading_in.png")
  S.check(mailboxSettled() and Mailbox._fade == 0, tag .. "the mailbox fades back in after the reader")

  openGive("mailbox_give_" .. version .. "_00c_give_fading_out.png")
  S.check(PartyMenu.open and PartyMenu.mode == "choose", tag .. "GIVE opens the party in choose mode (" .. tostring(PartyMenu.mode) .. ")")
  if not S.check(PartyMenu._party == session.party, tag .. "GIVE opens the party menu on the player's party") then
    Audio.playSe, FrlgFont.draw = realSe, realDraw
    return S.finish()
  end
  drawn = {}
  S.still(game, "mailbox_give_" .. version .. "_01_give_to_which_pokemon.png")
  local rs = rsUi
  local function rsPrompt(id)
    local key = RomText.key("PartyMenuPromptTexts", id)
    if RomText.has(key) then return RomText.plain(key, { stringVars = { "" } }) end
    return require("src.ui.game3.rse.scene_kit").manifest("rse/party").prompts[id + 1]
  end
  local giveText = rs and rsPrompt(4) or RomText.plain("gText_GiveToWhichPokemon")
  local chooseText = rs and rsPrompt(0) or RomText.plain("gText_ChoosePokemon")
  S.check(drawn[giveText] == true, tag .. "the party prompt is " .. tostring(giveText))
  S.check(next(drawn) ~= nil and drawn[chooseText] == nil,
    tag .. "the party prompt is not the plain choose prompt")

  played = {}
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(6)
  S.check(#played == 1 and played[1] == SE.resolve("SE_FAILURE"),
    tag .. "an egg plays SE_FAILURE alone (" .. table.concat(played, ",") .. ")")
  S.check(PartyMenu.open and PartyMenu.mode == "choose" and (tonumber(egg.item) or 0) == 0,
    tag .. "the egg stays in choose mode and gets no mail")

  played = {}
  PartyMenu.cursor = 3
  U.tap(game, "a")
  U.wait(6)
  S.check(played[1] == SE.resolve("SE_SELECT"), tag .. "a mon plays SE_SELECT")
  local holdText = RomText.box(rse and require("src.ui.game3.rs.player_pc_policy").matches(session)
    and "gOtherText_PokeHoldingItemCantMail" or "gText_PkmnHoldingItemCantHoldMail")
  S.check(PartyMenu.mode == "message" and holdText:find(tostring(PartyMenu._messageText), 1, true) ~= nil,
    tag .. "a mon holding an item cannot hold the mail (" .. tostring(PartyMenu._messageText) .. ")")
  S.check(Mailbox.count() == 2 and holder.item == C:require("items", "ITEM_POTION"), tag .. "the held POTION and the mail are untouched")
  for _ = 1, 60 do
    if not PartyMenu.open then break end
    U.tap(game, "a")
    U.wait(4)
  end
  S.check(not PartyMenu.open and Mailbox.isOpen() and Mailbox.state == "list" and (Mailbox._fade or 0) > 0,
    tag .. "the message closes the party back to a black mail list")
  U.wait(3)
  S.still(game, "mailbox_give_" .. version .. "_01b_list_fading_in_after_party.png")
  S.check(mailboxSettled() and Mailbox._fade == 0, tag .. "the mailbox fades back in after the party")

  openGive()
  PartyMenu.cursor = 2
  U.tap(game, "a")
  U.wait(6)
  local doneText = RomText.box(rse and require("src.ui.game3.rs.player_pc_policy").matches(session)
    and "gOtherText_MailTransferredMailbox" or "gText_MailTransferredFromMailbox")
  S.check(PartyMenu.mode == "message" and doneText:find(tostring(PartyMenu._messageText), 1, true) ~= nil,
    tag .. "the mail is transferred from the mailbox (" .. tostring(PartyMenu._messageText) .. ")")
  S.still(game, "mailbox_give_" .. version .. "_02_mail_transferred.png")
  S.check(plain.item == ORANGE and Mail.get(session, plain.mail) ~= nil, tag .. "the mon holds the ORANGE MAIL with its letter")
  for _ = 1, 60 do
    if not PartyMenu.open then break end
    U.tap(game, "a")
    U.wait(4)
  end
  U.wait(10)
  S.check(Mailbox.isOpen() and Mailbox.state == "list" and Mailbox.count() == 1,
    tag .. "back on the mail list with one mail left")
  S.check(pool[Mail.PARTY_SIZE + 1].playerName == "WALLY", tag .. "the list compacts the remaining mail to the top")

  Audio.playSe, FrlgFont.draw = realSe, realDraw
  Mailbox.close()
  U.wait(5)
  S.finish()
end

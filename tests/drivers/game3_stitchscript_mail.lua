local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchscript_mail"

-- pokefirered/data/maps/CeruleanCity_House3/scripts.inc:8
local TRADE_HOUSE = "FR_CERULEAN_CITY_HOUSE3"
local DONTAE_X, DONTAE_Y = 2, 2
-- pokefirered/data/scripts/day_care.inc:1
local DAY_CARE = "FR_ROUTE_5_POKEMON_DAY_CARE"
local DAYCARE_X, DAYCARE_Y = 4, 4

local SPECIES_POLIWHIRL = 61
local SPECIES_JYNX = 124
local SPECIES_BULBASAUR = 1
local ITEM_FAB_MAIL = 131

-- pokefirered/src/data/ingame_trades.h:184 sInGameTradeMailMessages
local ZYNX_WORDS = { 3613, 4128, 5147, 10876, 3072, 4102, 5183, 4143, 4137 }

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchscript_mail")
    love.event.quit(0)
  else
    print("FAIL stitchscript_mail failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Mail = require("src.core.game3.mail")
  local Daycare = require("src.core.game3.scripting.natives_daycare")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Audio = require("src.core.game3.audio")
  local TradeSceneUi = require("src.ui.game3.trade_scene")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMonToPlayer(session, SPECIES_POLIWHIRL, 20)
  Party.giveMonToPlayer(session, SPECIES_BULBASAUR, 20)
  session.money = 9999
  result(#session.party == 2, "the player has a POLIWHIRL and a spare, " ..
    tostring(#session.party) .. " mons")

  local function scriptRunning()
    return (Space.vm and Space.vm.isRunning and Space.vm:isRunning()) or false
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function talkUntilRunning()
    for _ = 1, 24 do
      if scriptRunning() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return scriptRunning()
  end

  local function pumpUntil(pred, frames)
    local budget = frames or 900
    while budget > 0 do
      if pred() then return true end
      if Audio.isSePlaying() then
        U.wait(4)
      elseif PartyMenu.isOpen and PartyMenu.isOpen() then
        U.tap(game, "a")
        U.wait(24)
      elseif Choice.active or (Message.isWaiting and Message.isWaiting())
        or (Message.isOpen and Message.isOpen()) or TradeSceneUi.isOpen() then
        U.tap(game, "a")
        U.wait(10)
      else
        U.wait(4)
      end
      if not Audio.isSePlaying() then budget = budget - 1 end
    end
    return pred()
  end

  local function shotOnMessage(path, frames)
    for _ = 1, frames or 400 do
      if Message.isOpen and Message.isOpen() then
        U.wait(10)
        U.shot(game, path)
        return true
      end
      U.wait(4)
    end
    return false
  end

  local function wordsOf(record)
    local out = {}
    for i = 1, Mail.MAIL_WORDS_COUNT do
      out[i] = tostring(record and record.words and record.words[i])
    end
    return table.concat(out, ",")
  end

  goTo(TRADE_HOUSE, DONTAE_X, DONTAE_Y + 1, "up")
  result(talkUntilRunning(), "DONTAE answers in Cerulean House 3")
  U.wait(30)
  U.shot(game, DIR .. "/stitchscript_mail_01_trade_offer.png")

  local traded = pumpUntil(function()
    local mon = session.party[1]
    return mon ~= nil and (mon.species or mon.speciesId) == SPECIES_JYNX
  end, 1800)
  result(traded, "the POLIWHIRL became ZYNX")

  local zynx = session.party[1]
  result(zynx ~= nil and zynx.item == ITEM_FAB_MAIL,
    "ZYNX arrived holding FAB MAIL, got " .. tostring(zynx and zynx.item))
  result(Mail.monHasMail(zynx), "MonHasMail sees the letter DONTAE attached")
  local letter = Mail.get(session, zynx and zynx.mail)
  result(letter ~= nil, "the letter is in the player's mail pool")
  result(wordsOf(letter) == table.concat(ZYNX_WORDS, ","),
    "with sInGameTradeMailMessages[0], got " .. wordsOf(letter))
  result(letter ~= nil and letter.playerName == "DONTAE",
    "signed DONTAE, got " .. tostring(letter and letter.playerName))
  result(letter ~= nil and letter.trainerId == 36728,
    "with DONTAE's trainer id, got " .. tostring(letter and letter.trainerId))

  result(shotOnMessage(DIR .. "/stitchscript_mail_02_trade_thanks.png"),
    "DONTAE says his piece after the swap")

  for _ = 1, 240 do
    if not scriptRunning() then break end
    U.tap(game, "a")
    U.wait(8)
  end

  goTo(DAY_CARE, DAYCARE_X, DAYCARE_Y + 1, "up")
  result(talkUntilRunning(), "the Route 5 day-care man answers")
  U.wait(30)
  U.shot(game, DIR .. "/stitchscript_mail_03_daycare_offer.png")

  local deposited = pumpUntil(function()
    local r5 = Daycare.route5Of(session)
    return r5 ~= nil and r5.mon ~= nil
  end, 1800)
  result(deposited, "ZYNX went into the day care")

  local r5 = Daycare.route5Of(session)
  result(r5 ~= nil and r5.mon ~= nil and (r5.mon.item == 0 or r5.mon.item == nil),
    "TakeMailFromMon emptied its hands on the way in, got " ..
    tostring(r5 and r5.mon and r5.mon.item))
  result(r5 ~= nil and r5.mail ~= nil, "the letter moved into the day-care slot")
  result(r5 ~= nil and r5.mail ~= nil and r5.mail.monName == "ZYNX",
    "DayCareMail.monName is ZYNX, got " .. tostring(r5 and r5.mail and r5.mail.monName))
  result(Mail.get(session, 0) == nil, "and the mail pool slot is free while it is away")

  for _ = 1, 240 do
    if not scriptRunning() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  U.wait(60)

  result(talkUntilRunning(), "the day-care man answers again for the pick-up")
  local back = pumpUntil(function()
    for _, mon in ipairs(session.party) do
      if (mon.species or mon.speciesId) == SPECIES_JYNX then return true end
    end
    return false
  end, 1800)
  result(back, "ZYNX came back out of the day care")

  local returned = nil
  for _, mon in ipairs(session.party) do
    if (mon.species or mon.speciesId) == SPECIES_JYNX then returned = mon end
  end
  result(returned ~= nil and returned.item == ITEM_FAB_MAIL,
    "GiveMailToMon2 put the FAB MAIL back in its hands, got " ..
    tostring(returned and returned.item))
  result(Mail.monHasMail(returned), "and it holds its letter again")
  local backLetter = Mail.get(session, returned and returned.mail)
  result(wordsOf(backLetter) == table.concat(ZYNX_WORDS, ","),
    "the nine words survived the day care, got " .. wordsOf(backLetter))
  result(Daycare.route5Of(session).mail == nil, "the day-care slot kept no copy")
  result(shotOnMessage(DIR .. "/stitchscript_mail_04_daycare_return.png"),
    "the day-care man hands ZYNX back")

  for _ = 1, 240 do
    if not scriptRunning() then break end
    U.tap(game, "a")
    U.wait(8)
  end

  finish()
end

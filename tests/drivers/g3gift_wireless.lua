local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3gift_wireless"
local TEST_PUBKEY = os.getenv("G3GIFT_TEST_PUBKEY")

-- pokefirered/include/constants/flags.h:1391
local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS g3gift_wireless")
    love.event.quit(0)
  else
    print("FAIL g3gift_wireless failures=" .. failures)
    love.event.quit(1)
  end
end

local function now()
  return love.timer.getTime()
end

return function(game)
  print("PASS driver started")
  if not result(type(TEST_PUBKEY) == "string" and #TEST_PUBKEY == 64,
    "G3GIFT_TEST_PUBKEY names the local test key") then
    return finish()
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Boot = require("src.ui.game3.boot")
  local Ui = require("src.ui.game3.mystery_gift")
  local MysteryGift = require("src.core.game3.mystery_gift")
  local WirelessIcon = require("src.ui.game3.wireless_icon")
  local SyncClient = require("src.sync.SyncClient")

  result(MysteryGift.GIFT_PUBKEY == "2cecc61cc4d4ea70fc6802a66643e659a0f2c344eec6391ccf20b434ab280ffd",
    "the build carries the owner's gift key")
  print("[driver] sync url " .. tostring(SyncClient.DEFAULT_URL))
  result(tostring(SyncClient.DEFAULT_URL):match("^http://127%.0%.0%.1:%d+$") ~= nil,
    "the feed comes from the local test server")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end
  -- pokefirered/data/scripts/questionnaire.inc:26
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_SYS_MYSTERY_GIFT_ENABLED, true)
  result(game:saveGame() ~= false, "the game saved")
  U.wait(30)
  game:returnToTitle()
  U.wait(60)

  local function phase() return game.boot and game.boot.phase end
  for _ = 1, 60 do
    if phase() == Boot.PHASE.MENU then break end
    U.tap(game, "start")
    U.wait(30)
  end
  for _ = 1, 120 do
    if (game.boot.fadeT or 0) == 0 then break end
    U.wait(1)
  end
  U.wait(10)
  local rows = Boot.menuItems(game.boot)
  result(rows[3] == "MYSTERY GIFT", "the MYSTERY GIFT row is on the main menu")
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "a")
  for _ = 1, 400 do
    if phase() == Boot.PHASE.MYSTERY_GIFT then break end
    U.wait(1)
  end
  if not result(phase() == Boot.PHASE.MYSTERY_GIFT, "the Mystery Gift screen opened") then
    return finish()
  end
  local st = game.boot.gift
  local S = Ui.STATE

  local function advance(pred, seconds)
    local deadline = now() + (seconds or 10)
    while now() < deadline do
      if pred() then return true end
      local m = st.msg
      if m and m.revealed >= m.total and not m.auto and not m.hold then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return pred()
  end

  local function atMenu()
    return st.state == S.MAIN_MENU and not st.msg
  end

  local function searchFromPicker(label)
    if not result(advance(function() return st.state == S.SOURCE_INPUT end),
      label .. ": the source picker opened") then return false end
    result(st.cursor == 1, label .. ": the cursor starts on WIRELESS COMMUNICATION")
    U.tap(game, "a")
    result(st.state == S.SEARCHING, label .. ": WIRELESS COMMUNICATION starts the search")
    return true
  end

  local function waitList(label)
    return result(advance(function() return st.state ~= S.SEARCHING end, 15) and st.state == S.OFFER_LIST,
      label .. ": the signed feed verified and listed, state=" .. tostring(st.state)
      .. " err=" .. tostring(st.lastError))
  end

  local function pickRow(row)
    for _ = 2, row do
      U.tap(game, "down")
      U.wait(4)
    end
    U.tap(game, "a")
  end

  U.tap(game, "a")
  result(st.state == S.DONT_HAVE_ANY, "WONDER CARDS with no card asks for one")
  if not searchFromPicker("owner key") then return finish() end
  result(advance(function() return st.state ~= S.SEARCHING end, 15) and st.lastError == "bad_signature",
    "a feed not signed by the owner's key is refused, err=" .. tostring(st.lastError))
  U.wait(90)
  result(WirelessIcon.anim() == "error", "the icon shows the error")
  U.still(game, DIR .. "/g3gift_communication_error.png")
  result(advance(atMenu, 15), "the error returns to the Mystery Gift menu")
  result(not MysteryGift.validateSavedCard(st.session), "nothing was installed")

  MysteryGift.GIFT_PUBKEY = TEST_PUBKEY

  U.tap(game, "a")
  result(st.state == S.DONT_HAVE_ANY, "WONDER CARDS with no card asks for one")
  if not searchFromPicker("card") then return finish() end
  U.wait(8)
  result(WirelessIcon.anim() == "searching", "the wireless icon is searching")
  result(st.state == S.SEARCHING, "the searching text holds")
  U.still(game, DIR .. "/g3gift_searching.png")
  if not waitList("card") then return finish() end
  U.wait(12)
  local labels = {}
  for i, entry in ipairs(st.offers or {}) do labels[i] = tostring(entry.label) end
  print("[driver] card rows: " .. table.concat(labels, " | "))
  result(labels[1] == "MYSTIC TICKET" and labels[2] == "MEW" and labels[3] == "STAMP CARD",
    "the list carries the published cards in feed order")
  result(WirelessIcon.anim() == "3bars", "the icon shows the link")
  U.still(game, DIR .. "/g3gift_card_list.png")

  pickRow(2)
  result(advance(function() return st.state == S.COMM_COMPLETED end), "MEW: communication completes")
  result(advance(function() return st.state == S.RESULT_MSG end), "MEW: the result message is up")
  print("[driver] result: " .. tostring(st.msg and st.msg.text))
  result(advance(atMenu, 15), "MEW: saved and back on the Mystery Gift menu")
  local sess = st.session
  local card = MysteryGift.getSavedCard(sess)
  result(card ~= nil and card.idNumber == 7 and card.titleText == "MEW", "the MEW Wonder Card is installed")
  result(MysteryGift.hasClaimedCard(sess, 7), "and claimed on this save")

  U.tap(game, "a")
  result(st.state == S.GIFT_INPUT, "WONDER CARDS opens the received card")
  U.wait(10)
  U.still(game, DIR .. "/g3gift_received_wonder_card.png")
  U.tap(game, "b")
  U.wait(6)

  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  result(st.state == S.DONT_HAVE_ANY and st.isNews, "WONDER NEWS with no news asks for one")
  if not searchFromPicker("news") then return finish() end
  if not waitList("news") then return finish() end
  labels = {}
  for i, entry in ipairs(st.offers or {}) do labels[i] = tostring(entry.label) end
  print("[driver] news rows: " .. table.concat(labels, " | "))
  result(#labels == 1, "one news item is published")
  U.wait(6)
  U.still(game, DIR .. "/g3gift_news_list.png")
  pickRow(1)
  result(advance(atMenu, 15), "news: saved and back on the Mystery Gift menu")
  result(MysteryGift.validateSavedNews(sess), "the Wonder News is installed")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  result(st.state == S.GIFT_INPUT and st.isNews, "WONDER NEWS opens the received news")
  U.wait(10)
  U.still(game, DIR .. "/g3gift_wonder_news.png")
  U.tap(game, "b")
  U.wait(6)

  U.tap(game, "a")
  U.wait(4)
  U.tap(game, "a")
  result(st.state == S.GIFT_SELECT, "the card menu is up")
  local tossRow
  for i, a in ipairs(st.giftActions or {}) do if a == "toss" then tossRow = i end end
  pickRow(tossRow or 2)
  result(st.state == S.ASK_TOSS, "TOSS asks first")
  U.tap(game, "a")
  if st.state == S.ASK_TOSS_UNRECEIVED then U.tap(game, "a") end
  result(advance(atMenu, 15), "the MEW card is tossed")
  result(not MysteryGift.validateSavedCard(sess), "no card is held")
  U.tap(game, "a")
  if not searchFromPicker("reclaim") then return finish() end
  if not waitList("reclaim") then return finish() end
  pickRow(2)
  result(advance(function() return st.state == S.RESULT_MSG end), "reclaim: the result message is up")
  U.wait(60)
  print("[driver] reclaim: " .. tostring(st.msg and st.msg.text))
  result(st.msg ~= nil and tostring(st.msg.text):find("already") ~= nil, "a second MEW is refused as already had")
  U.still(game, DIR .. "/g3gift_already_had.png")
  result(advance(atMenu, 15), "back on the menu")
  result(not MysteryGift.validateSavedCard(sess), "and nothing was installed")

  U.tap(game, "a")
  if not searchFromPicker("stamp") then return finish() end
  if not waitList("stamp") then return finish() end
  pickRow(3)
  result(advance(atMenu, 15), "stamp: saved and back on the menu")
  card = MysteryGift.getSavedCard(sess)
  result(card ~= nil and card.type == MysteryGift.CARD_TYPE_STAMP, "the STAMP CARD is installed")
  MysteryGift.trySaveStamp(sess, { species = 25, id = 11111 })
  MysteryGift.trySaveStamp(sess, { species = 4, id = 22222 })
  U.tap(game, "a")
  result(st.state == S.GIFT_INPUT, "the STAMP CARD opens")
  U.wait(10)
  U.still(game, DIR .. "/g3gift_stamp_card.png")
  U.tap(game, "b")
  U.wait(6)

  local SaveData = require("src.core.SaveData")
  local okLoad, saved = pcall(SaveData.load)
  local rec = okLoad and type(saved) == "table" and type(saved.modData) == "table"
    and saved.modData.mysteryGift or nil
  local claims = rec and rec.claims or {}
  local have7 = false
  for _, id in ipairs(claims.cards or {}) do if tonumber(id) == 7 then have7 = true end end
  result(have7, "the MEW claim is on the save file")
  result(rec ~= nil and rec.news ~= nil, "the news is on the save file")

  U.tap(game, "b")
  for _ = 1, 400 do
    if phase() == Boot.PHASE.MENU then break end
    U.wait(1)
  end
  result(phase() == Boot.PHASE.MENU, "B leaves for the main menu")
  result(WirelessIcon.anim() ~= "searching" and WirelessIcon.anim() ~= "3bars", "the icon is released")
  finish()
end

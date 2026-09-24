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

love = love or require("tests.love_stub")

local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  local LIST_ROWS = { sListMenuItems_CardsOrNews = 3, sListMenuItems_ReceiveSendToss = 4, sListMenuItems_ReceiveToss = 3,
    sListMenuItems_WirelessOrFriend = 3 }
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function(n) return LIST_ROWS[n] or 0 end,
    list = function(n)
      local out = {}
      for i = 0, (LIST_ROWS[n] or 0) - 1 do out[i + 1] = n .. "[" .. i .. "]" end
      return out
    end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end
local function teq(a, b, msg)
  if romBundle then eq(a, b, msg) else print("[skip] ROM text: " .. msg) end
end
local function tcheck(cond, msg)
  if romBundle then check(cond, msg) else print("[skip] ROM text: " .. msg) end
end

local ListStub = {}
ListStub.__index = ListStub
ListStub.COLOR_WHITE = { fg = "ur_white" }
function ListStub.new(opts)
  local lm = setmetatable({ opts = opts, items = opts.items, cursor = 1, draws = 0 }, ListStub)
  ListStub.last = lm
  return lm
end
function ListStub:handleInput(input)
  if input:wasPressed("down") and self.cursor < #self.items then
    self.cursor = self.cursor + 1
    return "move"
  elseif input:wasPressed("up") and self.cursor > 1 then
    self.cursor = self.cursor - 1
    return "move"
  elseif input:wasPressed("a") then
    return "select"
  elseif input:wasPressed("b") then
    return "cancel"
  end
  return nil
end
function ListStub:selected() return self.items[self.cursor], self.cursor end
function ListStub:update() end
function ListStub:draw() self.draws = self.draws + 1 end
package.loaded["src.ui.game3.list_menu"] = ListStub

local fanfares = {}
package.loaded["src.core.game3.audio"] = setmetatable({
  playFanfare = function(id) fanfares[#fanfares + 1] = id return true end,
  isFanfareFinished = function() return true end,
}, { __index = function() return function() end end })

local Boot = require("src.ui.game3.boot")
local Ui = require("src.ui.game3.mystery_gift")
local MysteryGift = require("src.core.game3.mystery_gift")
local WirelessIcon = require("src.ui.game3.wireless_icon")

local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839

local FIXTURE_PUB = "58c5b57e548789c3d231a9537f172bcf515a39b053f58a90c7b0096967a746ba"
local FIXTURE_BODY = [==[{"v":1,"payload":"{\"cards\":[{\"bgType\":2,\"bodyText\":[\"Thank you for using the MYSTERY\",\"GIFT System.\",\"There is a ticket here for you.\",\"It is for use at VERMILION CITY port.\"],\"flagId\":1001,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"haveFlags\":[680,754,755],\"item\":370,\"kind\":\"item\",\"quantity\":1,\"setFlags\":[2122,680]},\"iconSpecies\":0,\"idNumber\":1,\"key\":\"mystic_ticket\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"MYSTIC TICKET\",\"type\":0},{\"bgType\":7,\"bodyText\":[\"A mythical POKéMON has been\",\"sent to you from the\",\"POKéMON CENTER.\",\"Please take good care of it.\"],\"flagId\":1007,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"kind\":\"mon\",\"level\":10,\"moves\":{\"1\":1},\"otId\":20078,\"otName\":\"AURA\",\"species\":151},\"iconSpecies\":151,\"idNumber\":7,\"key\":\"mew\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"MEW\",\"type\":0},{\"bgType\":4,\"bodyText\":[\"Thank you for using the STAMP CARD\",\"System.\",\"Trade with other TRAINERS to fill\",\"your STAMP CARD.\"],\"flagId\":1004,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"kind\":\"none\"},\"iconSpecies\":0,\"idNumber\":4,\"key\":\"stamp_card\",\"maxStamps\":7,\"sendType\":1,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"STAMP CARD\",\"type\":1}],\"issued\":0,\"news\":[{\"bgType\":1,\"bodyText\":[\"Welcome to the POKéMON\",\"WIRELESS CLUB news.\",\"Look for new WONDER CARDS.\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"],\"id\":1,\"key\":\"launch_news\",\"sendType\":0,\"titleText\":\"WONDER NEWS\"}],\"v\":1}","sig":"44aa8146ee6d745efe81afc3427aaf84d07b4c64bacb6922c8d9ff27fa779e3d628c55cd623ab49c9afc2fc84f02be8942350cae4ae08c1e4e01955a671d7009","key":"58c5b57e548789c3d231a9537f172bcf515a39b053f58a90c7b0096967a746ba"}]==]

local function transport(reply)
  local t = { calls = 0 }
  function t:begin() self.calls = self.calls + 1 return self.calls end
  function t:poll()
    if type(reply) == "function" then return reply() end
    return reply
  end
  function t:release() end
  function t:cancel() self.canceled = true end
  return t
end

local function okFeed()
  return transport({ status = "ok", code = 200, body = FIXTURE_BODY })
end

MysteryGift.GIFT_PUBKEY = FIXTURE_PUB

local function driver(st)
  local keys = {}
  local function pressed(k) return keys[k] == true end
  local d = {}
  function d.step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(st, pressed, 1 / 60)
  end
  function d.waitFor(pred, key, limit)
    for _ = 1, limit or 2000 do
      if pred() then return true end
      if st.msg and st.msg.revealed >= st.msg.total and not st.msg.auto and not st.msg.hold then
        d.step(key or "a")
      else
        d.step(nil)
      end
    end
    return pred()
  end
  function d.finishMessage()
    for _ = 1, 2000 do
      if not st.msg then return end
      if st.msg.revealed >= st.msg.total and not st.msg.auto and not st.msg.hold then
        d.step("a")
        return
      end
      d.step(nil)
    end
  end
  return d
end

local function giftSession(save)
  local sess = MysteryGift.sessionFromSave(save)
  MysteryGift.enable(sess)
  return sess
end

local function openWireless(st, d, isNews)
  if isNews then
    d.step("down")
    d.step("a")
    return
  end
  d.step("a")
  d.waitFor(function() return st.state == Ui.STATE.SEARCHING end)
end

print("[test] 1. The main menu rows")
do
  local noSave = Boot.new()
  Boot.setHasContinue(noSave, false)
  local rows = Boot.menuItems(noSave)
  eq(#rows, 2, "no save file gives two rows")
  eq(rows[1], "NEW GAME", "row 1 is NEW GAME")

  local plain = Boot.new()
  Boot.setHasContinue(plain, true)
  Boot.setContinueInfo(plain, { name = "RED", mysteryGift = false })
  rows = Boot.menuItems(plain)
  eq(#rows, 4, "any save file gets the MYSTERY GIFT row")
  eq(rows[3], "MYSTERY GIFT", "even without the passphrase flag")
  eq(rows[4], "EXIT", "EXIT follows it")
  check(Boot.hasMysteryGift(plain), "a save alone opens the Mystery Gift layout")

  local gift = Boot.new()
  Boot.setHasContinue(gift, true)
  Boot.setContinueInfo(gift, { name = "RED", mysteryGift = true })
  rows = Boot.menuItems(gift)
  -- pokefirered/src/main_menu.c:370 MAIN_MENU_MYSTERYGIFT
  eq(#rows, 4, "the Mystery Gift layout keeps EXIT as a fourth row")
  eq(rows[1], "CONTINUE", "row 1 is CONTINUE")
  eq(rows[2], "NEW GAME", "row 2 is NEW GAME")
  eq(rows[3], "MYSTERY GIFT", "MYSTERY GIFT takes the third window")
  eq(rows[4], "EXIT", "EXIT is always on the menu")
  check(Boot.hasMysteryGift(gift), "the flag selects the Mystery Gift layout")

  -- pokefirered/src/main_menu.c:21 enum MainMenuType
  local sawOption = false
  for _, state in ipairs({ noSave, plain, gift }) do
    for _, row in ipairs(Boot.menuItems(state)) do
      if row == "OPTION" then sawOption = true end
    end
  end
  check(not sawOption, "no layout carries an OPTION row")
end

print("[test] 2. The flag comes off the save file")
do
  local off = Boot.continueInfoFromSave({ name = "RED", flags = {} })
  check(off.mysteryGift == false, "a save without the flag reads false")
  local on = Boot.continueInfoFromSave({
    name = "RED",
    flags = { [tostring(FLAG_SYS_MYSTERY_GIFT_ENABLED)] = true },
  })
  check(on.mysteryGift == true, "FLAG_SYS_MYSTERY_GIFT_ENABLED reads true")
end

print("[test] 3. Picking MYSTERY GIFT reaches the front end")
do
  local state = Boot.new()
  Boot.setHasContinue(state, true)
  Boot.setContinueInfo(state, { name = "RED", mysteryGift = true })
  state.phase = Boot.PHASE.MENU
  state.menuIndex = 3
  state.fadeT, state.fadeTarget = 0, 0
  local key = nil
  local input = { wasPressed = function(_, k) return k == key end }
  key = "a"
  Boot.update(state, input, 1 / 60)
  eq(state.fadeThen, "mystery_gift", "the MYSTERY GIFT row starts the fade")
  key = nil
  for _ = 1, 400 do
    if state.phase == Boot.PHASE.MYSTERY_GIFT then break end
    Boot.update(state, input, 1 / 60)
  end
  eq(state.phase, Boot.PHASE.MYSTERY_GIFT, "the fade hands over to the Mystery Gift screen")
  check(type(state.gift) == "table", "a front-end state was built")
  eq(state.gift.state, Ui.STATE.MAIN_MENU, "the front end opens on its own menu")
  local okDraw, err = pcall(Boot.draw, state)
  tcheck(okDraw, "the Mystery Gift screen draws: " .. tostring(err))

  key = "b"
  Boot.update(state, input, 1 / 60)
  eq(state.phase, Boot.PHASE.MENU, "B leaves the front end for the main menu")
end

print("[test] 4. The front end receives a card and saves it")
local save, sess, st, saves
do
  save = {}
  sess = giftSession(save)
  saves = 0
  local feedTransport = okFeed()
  st = Ui.new({
    session = sess,
    fetch = { transport = feedTransport },
    onSave = function(s)
      saves = saves + 1
      return MysteryGift.applyToSave(s, save)
    end,
  })

  local d = driver(st)
  local step, finishMessage = d.step, d.finishMessage

  -- pokefirered/src/mystery_gift_menu.c:197 sListMenuItems_CardsOrNews
  local rows = Ui.mainRows()
  teq(rows[1], "WONDER CARDS", "the front end opens on WONDER CARDS")
  teq(rows[2], "WONDER NEWS", "WONDER NEWS is the second row")
  teq(rows[3], "EXIT", "EXIT is the third row")

  step("a")
  eq(st.state, Ui.STATE.SEARCHING, "WONDER CARDS fetches the card list at once")
  eq(feedTransport.calls, 1, "one request goes out")
  eq(WirelessIcon.anim(), "searching", "the wireless icon plays its searching anim")
  tcheck(type(st.prompt) == "string" and st.prompt:find("Searching for a WIRELESS"),
    "with the cart's searching text")
  d.waitFor(function() return st.state ~= Ui.STATE.SEARCHING end)
  eq(st.state, Ui.STATE.OFFER_LIST, "the verified feed opens the card list")
  eq(WirelessIcon.anim(), "3bars", "the icon shows the link")
  local lm = ListStub.last
  check(lm ~= nil and lm.opts.template.left == 1 and lm.opts.template.top == 3,
    "the list sits at sWindowTemplate_GroupList")
  eq(lm and #lm.items, 3, "every card in the feed is listed")
  eq(lm and lm.items[1].label, "MYSTIC TICKET", "row 1 is the MYSTIC TICKET")
  eq(lm and lm.items[2].label, "MEW", "row 2 is MEW")
  eq(lm and lm.opts.maxShowed, 5, "five rows show at once")
  step("a")
  eq(st.state, Ui.STATE.GIFT_INPUT, "pressing a card shows it first")
  eq(Ui.card(st).titleText, "MYSTIC TICKET", "the preview is the picked card")
  check(not MysteryGift.validateSavedCard(sess), "a preview installs nothing")
  local okDraw, err = pcall(Ui.draw, st)
  tcheck(okDraw, "the preview draws: " .. tostring(err))
  step("a")
  eq(st.state, Ui.STATE.RESULT_MSG, "A receives it at once")
  eq(WirelessIcon.anim(), nil, "the icon goes away when the link ends")
  check(MysteryGift.validateSavedCard(sess), "the card is installed")
  tcheck(st.msg ~= nil and tostring(st.msg.text):find("WONDER CARD"), "the received message names the card")
  check(st.msg ~= nil and st.msg.hold == Ui.SUCCESS_FRAMES, "the success message holds for the fanfare")
  eq(fanfares[#fanfares], 258, "MUS_OBTAIN_ITEM plays")
  d.waitFor(function() return st.state == Ui.STATE.SAVE and not st.msg end)
  eq(st.state, Ui.STATE.SAVE, "and the game saves")
  step(nil)
  eq(st.state, Ui.STATE.SAVE_DONE, "the save runs once")
  eq(saves, 1, "onSave was called exactly once")
  finishMessage()
  eq(st.state, Ui.STATE.MAIN_MENU, "then back to the Mystery Gift menu")

  check(MysteryGift.validateSavedCard(sess), "the card is on the session")
  check(type(save.modData) == "table" and type(save.modData.mysteryGift) == "table",
    "the record reached the save table")
  check(save.flags[tostring(FLAG_SYS_MYSTERY_GIFT_ENABLED)] == true,
    "FLAG_SYS_MYSTERY_GIFT_ENABLED reached the save table")
end

print("[test] 5. The list marks the held card and opens it")
do
  local d = driver(st)
  d.step("a")
  eq(st.state, Ui.STATE.SEARCHING, "WONDER CARDS fetches again")
  d.waitFor(function() return st.state ~= Ui.STATE.SEARCHING end)
  eq(st.state, Ui.STATE.OFFER_LIST, "the list opens")
  local lm = ListStub.last
  -- pokefirered/src/union_room.c:4072
  eq(lm and lm.items[1].colors, ListStub.COLOR_WHITE, "the MYSTIC TICKET shows as already had")
  eq(lm and lm.items[2].colors, nil, "MEW does not")
  d.step("a")
  eq(st.state, Ui.STATE.GIFT_INPUT, "pressing the held card opens it")
  local card = Ui.card(st)
  eq(card.titleText, "MYSTIC TICKET", "the saved card is the MYSTIC TICKET")
  eq(#card.bodyText, 4, "the card carries four body lines")
  local okDraw, err = pcall(Ui.draw, st)
  tcheck(okDraw, "the card view draws: " .. tostring(err))
  d.step("b")
  eq(st.state, Ui.STATE.OFFER_LIST, "B goes back to the list")
  d.step("b")
  eq(st.state, Ui.STATE.MAIN_MENU, "B on the list goes back to the menu")
  check(MysteryGift.validateSavedCard(sess), "the held card stays")
end

print("[test] 6. Wonder News paging")
do
  local body = {}
  for i = 1, 10 do body[i] = "LINE " .. i end
  local nst = Ui.new({ session = giftSession({}), onSave = function() return true end })
  local keys = {}
  local function pressed(k) return keys[k] == true end
  local function step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(nst, pressed, 1 / 60)
  end
  nst.isNews = true
  nst.viewNews = { id = 7, bgType = 1, titleText = "WONDER NEWS", bodyText = body }
  nst.newsScroll = 0
  nst.state = Ui.STATE.NEWS_VIEW
  step("down")
  eq(nst.newsScroll, 1, "down scrolls one line")
  step("down")
  eq(nst.newsScroll, 2, "down scrolls again")
  step("down")
  -- pokefirered/src/mystery_gift_show_news.c:346 scrollEnd counts lines past the eighth
  eq(nst.newsScroll, 2, "ten lines over an eight-line window stop at two")
  step("up")
  eq(nst.newsScroll, 1, "up scrolls back")
  local okDraw, err = pcall(Ui.draw, nst)
  tcheck(okDraw, "the news view draws: " .. tostring(err))
  step("b")
  eq(nst.state, Ui.STATE.OFFER_LIST, "B goes back to the news list")
  check(nst.viewNews == nil, "and drops the news it showed")
end

local function freshScreen(t, save)
  save = save or {}
  local sess2 = giftSession(save)
  local st2 = Ui.new({
    session = sess2,
    fetch = { transport = t },
    onSave = function(s) return MysteryGift.applyToSave(s, save) end,
  })
  return st2, driver(st2), sess2, save
end

local function searchResult(st2, d)
  d.waitFor(function() return st2.state ~= Ui.STATE.SEARCHING end)
end

print("[test] 7. Wonder News over WIRELESS COMMUNICATION")
do
  local st2, d, sess2 = freshScreen(okFeed())
  openWireless(st2, d, true)
  eq(st2.state, Ui.STATE.SEARCHING, "WONDER NEWS fetches the list at once")
  searchResult(st2, d)
  eq(st2.state, Ui.STATE.OFFER_LIST, "the news list opens")
  eq(#ListStub.last.items, 1, "only news rows are listed")
  eq(ListStub.last.items[1].label, "WONDER NEWS", "the news title is the row")
  d.step("a")
  eq(st2.state, Ui.STATE.NEWS_VIEW, "pressing a row opens that news")
  eq(st2.viewNews and st2.viewNews.titleText, "WONDER NEWS", "the picked news is the one shown")
  check(not MysteryGift.validateSavedNews(sess2), "reading saves nothing")
  d.step("b")
  eq(st2.state, Ui.STATE.OFFER_LIST, "B goes back to the list")
  d.step("b")
  eq(st2.state, Ui.STATE.MAIN_MENU, "B on the list goes back to the menu")
end

print("[test] 8. Cards you had before stay marked and can be switched back to")
do
  local save = {}
  local st2, d, sess2 = freshScreen(okFeed(), save)
  openWireless(st2, d, false)
  searchResult(st2, d)
  d.step("down")
  d.step("a")
  d.step("a")
  d.waitFor(function() return st2.state == Ui.STATE.MAIN_MENU and not st2.msg end)
  eq(MysteryGift.getSavedCard(sess2).idNumber, 7, "the MEW card is installed")
  local giftFlag = MysteryGift.receivedGiftFlag(MysteryGift.getSavedCard(sess2).flagId)
  check(giftFlag ~= nil, "the MEW card has a received-gift flag")
  MysteryGift.setFlag(sess2, giftFlag, true)
  MysteryGift.clearCardAndRelated(sess2)
  check(not MysteryGift.validateSavedCard(sess2), "then tossed")

  openWireless(st2, d, false)
  searchResult(st2, d)
  eq(ListStub.last.items[2].colors, ListStub.COLOR_WHITE,
    "the claimed card prints greyed in the list")
  d.step("down")
  d.step("a")
  d.step("a")
  d.waitFor(function() return st2.state == Ui.STATE.MAIN_MENU and not st2.msg end)
  eq(MysteryGift.getSavedCard(sess2).idNumber, 7, "a card you had before installs again")
  check(not MysteryGift.isGiftNotReceived(sess2), "and a gift already collected stays collected")

  local reopened, d2, sess3 = freshScreen(okFeed(), save)
  check(MysteryGift.hasClaimedCard(sess3, 7), "the claim was saved with the game")
  openWireless(reopened, d2, false)
  searchResult(reopened, d2)
  eq(ListStub.last.items[2].colors, ListStub.COLOR_WHITE, "and still prints greyed after a reload")
  d2.step("a")
  d2.step("a")
  d2.waitFor(function() return reopened.state == Ui.STATE.ASK_REPLACE end)
  d2.step("a")
  if reopened.state == Ui.STATE.ASK_REPLACE_UNRECEIVED then d2.step("a") end
  d2.waitFor(function() return reopened.state == Ui.STATE.SAVE end)
  eq(MysteryGift.getSavedCard(sess3).idNumber, 1, "switching to another card replaces the held one")
end

print("[test] 9. Replacing a held card asks first")
do
  local st2, d, sess2 = freshScreen(okFeed())
  MysteryGift.receiveCard(sess2, MysteryGift.builtins()[2].card)
  d.step("a")
  eq(st2.state, Ui.STATE.SEARCHING, "WONDER CARDS fetches the list")
  searchResult(st2, d)
  d.step("a")
  d.step("a")
  d.waitFor(function() return st2.state == Ui.STATE.ASK_REPLACE end)
  check(st2.yesno ~= nil, "the cart's throw-away question is up")
  d.step("a")
  eq(st2.state, Ui.STATE.ASK_REPLACE_UNRECEIVED, "an uncollected gift asks again")
  d.step("b")
  eq(st2.state, Ui.STATE.OFFER_LIST, "declining goes back to the list")
  eq(MysteryGift.getSavedCard(sess2).idNumber, 2, "the held card stays")
end

print("[test] 10. Offline, forged and empty feeds")
do
  local st2, d, sess2 = freshScreen(transport({ status = "error", err = "could not connect" }))
  openWireless(st2, d, false)
  searchResult(st2, d)
  eq(st2.state, Ui.STATE.RESULT_MSG, "no network ends the search")
  eq(WirelessIcon.anim(), "error", "the icon shows the error")
  tcheck(st2.msg ~= nil and tostring(st2.msg.text):find("Wireless Adapter"), "with the cart's not-connected text")
  d.waitFor(function() return st2.state == Ui.STATE.MAIN_MENU end)
  eq(st2.state, Ui.STATE.MAIN_MENU, "and it goes back to the menu")
  eq(WirelessIcon.anim(), nil, "with the icon gone")

  local body = FIXTURE_BODY:gsub('\\"item\\":370', '\\"item\\":371')
  check(body ~= FIXTURE_BODY, "the forged body differs")
  local forged, fd, fsess = freshScreen(transport({ status = "ok", code = 200, body = body }))
  openWireless(forged, fd, false)
  searchResult(forged, fd)
  eq(forged.state, Ui.STATE.RESULT_MSG, "a forged feed ends the search")
  eq(forged.lastError, "bad_signature", "because the signature failed")
  tcheck(forged.msg ~= nil and tostring(forged.msg.text):find("error"), "with the cart's communication error")
  check(not MysteryGift.validateSavedCard(fsess), "and nothing is installed")
  fd.waitFor(function() return forged.state == Ui.STATE.MAIN_MENU and not forged.msg end)
  eq(forged.state, Ui.STATE.MAIN_MENU, "back to the Mystery Gift menu")

  MysteryGift.GIFT_PUBKEY = "2cecc61cc4d4ea70fc6802a66643e659a0f2c344eec6391ccf20b434ab280ffd"
  local real, rd, rsess = freshScreen(okFeed())
  openWireless(real, rd, false)
  searchResult(real, rd)
  eq(real.lastError, "bad_signature", "a feed not signed by the owner's key is refused")
  check(not MysteryGift.validateSavedCard(rsess), "and installs nothing")
  MysteryGift.GIFT_PUBKEY = FIXTURE_PUB

  local noNews = [==[{"v":1,"payload":"{\"cards\":[],\"issued\":0,\"news\":[],\"v\":1}","sig":"4725a7934bfa21b943699b2b155d55235f598a7cc75531c4da36123848e296b590636ed33c3fcc7c4e19b0f604f5ea6e47fd5102676e365bfadfa5d6567a1c01"}]==]
  MysteryGift.GIFT_PUBKEY = "6130adae42fe6c943b91dc721db1cc1ba2296de882f919b2380f6fc3a2f4cec8"
  local empty, ed = freshScreen(transport({ status = "ok", code = 200, body = noNews }))
  openWireless(empty, ed, true)
  searchResult(empty, ed)
  MysteryGift.GIFT_PUBKEY = FIXTURE_PUB
  eq(empty.state, Ui.STATE.RESULT_MSG, "an empty news set ends the search")
  -- pokefirered/src/union_room.c:2559
  tcheck(empty.msg ~= nil and tostring(empty.msg.text):find("NEWS"), "with the cart's no-news-shared text")
  ed.waitFor(function() return empty.state == Ui.STATE.MAIN_MENU end)
  eq(empty.state, Ui.STATE.MAIN_MENU, "and it goes back to the menu")

  local slow = transport({ status = "pending" })
  local canceled, cd = freshScreen(slow)
  openWireless(canceled, cd, false)
  for _ = 1, 10 do cd.step(nil) end
  cd.step("b")
  check(slow.canceled == true, "B cancels the request")
  eq(canceled.state, Ui.STATE.RESULT_MSG, "B stops the search")
  tcheck(canceled.msg ~= nil and tostring(canceled.msg.text):find("canceled"), "with the cart's search-canceled text")

end

print("[test] 11. The save message runs the save with no button press")
do
  local saves = 0
  local st2 = Ui.new({
    session = giftSession({}),
    fetch = { transport = okFeed() },
    onSave = function() saves = saves + 1 return true end,
  })
  local d = driver(st2)
  local step = d.step
  openWireless(st2, d, false)
  searchResult(st2, d)
  step("a")
  step("a")
  d.waitFor(function() return st2.state == Ui.STATE.RESULT_MSG end)
  eq(st2.state, Ui.STATE.RESULT_MSG, "the card arrives")
  for _ = 1, 1200 do
    if st2.state ~= Ui.STATE.RESULT_MSG then break end
    step(nil)
  end
  eq(st2.state, Ui.STATE.SAVE, "the save message is up without a button press")
  -- pokefirered/src/mystery_gift_menu.c:860 SaveOnMysteryGiftMenu
  for _ = 1, 600 do
    if saves > 0 then break end
    step(nil)
  end
  eq(saves, 1, "the save ran with no button press")
  eq(st2.state, Ui.STATE.SAVE_DONE, "and the completed message follows")
  tcheck(st2.msg ~= nil and tostring(st2.msg.text):find("press the A Button"),
    "which is the one that waits for A")
end

print("[test] 12. EXIT stays on the menu under the MYSTERY GIFT row")
do
  local gift = Boot.new()
  Boot.setHasContinue(gift, true)
  Boot.setContinueInfo(gift, { name = "RED", mysteryGift = true })
  gift.phase = Boot.PHASE.MENU
  gift.fadeT, gift.fadeTarget = 0, 0
  local rows = Boot.menuItems(gift)
  local sawExitRow = false
  for _, row in ipairs(rows) do
    if row == "EXIT" then sawExitRow = true end
  end
  check(sawExitRow, "the EXIT row is still there with MYSTERY GIFT on the menu")
  local key = "select"
  Boot.update(gift, { wasPressed = function(_, k) return k == key end }, 1 / 60)
  check(gift.fadeThen ~= "exit", "SELECT is not a hidden exit")
  for _ = 1, 3 do
    key = "down"
    Boot.update(gift, { wasPressed = function(_, k) return k == key end, isDown = function() return false end }, 1 / 60)
  end
  eq(gift.menuIndex, 4, "three downs reach the EXIT row")
  check((gift.menuScroll or 0) > 0, "and the menu scrolled to show it")
  key = "a"
  Boot.update(gift, { wasPressed = function(_, k) return k == key end }, 1 / 60)
  eq(gift.fadeThen, "exit", "A on EXIT starts the exit fade")
  key = nil
  local action = nil
  for _ = 1, 400 do
    action = Boot.update(gift, { wasPressed = function(_, k) return k == key end }, 1 / 60)
    if action then break end
  end
  eq(type(action) == "table" and action.action or nil, "exit", "and it reaches the launcher exit action")
end

print("[test] 13. WONDER CARDS waits for the questionnaire passphrase")
do
  local locked = Ui.new({ session = MysteryGift.sessionFromSave({}), onSave = function() return true end })
  eq(#locked.rows, 2, "without the passphrase only WONDER NEWS and EXIT show")
  teq(locked.rows[1], "WONDER NEWS", "row 1 is WONDER NEWS")
  teq(locked.rows[2], "EXIT", "row 2 is EXIT")
  Ui.update(locked, function(k) return k == "a" end, 1 / 60)
  check(locked.isNews, "the first row opens the news branch")
  eq(locked.state, Ui.STATE.SEARCHING, "which fetches the news list")

  local open = Ui.new({ session = giftSession({}), onSave = function() return true end })
  eq(#open.rows, 3, "the passphrase adds WONDER CARDS back")
  teq(open.rows[1], "WONDER CARDS", "on the first row")
end

if failed == 0 then
  print("PASS game3_gift_menu")
else
  print("FAIL game3_gift_menu failures=" .. failed)
  os.exit(1)
end

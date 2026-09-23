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
  local LIST_ROWS = { sListMenuItems_CardsOrNews = 3, sListMenuItems_ReceiveSendToss = 4, sListMenuItems_ReceiveToss = 3 }
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

local Boot = require("src.ui.game3.boot")
local Ui = require("src.ui.game3.mystery_gift")
local MysteryGift = require("src.core.game3.mystery_gift")

local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839

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
  eq(#rows, 3, "a save without the Mystery Gift flag gives three rows")
  eq(rows[1], "CONTINUE", "row 1 is CONTINUE")
  eq(rows[2], "NEW GAME", "row 2 is NEW GAME")
  eq(rows[3], "EXIT", "row 3 is EXIT")
  check(not Boot.hasMysteryGift(plain), "no MYSTERY GIFT row without the flag")

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
  check(okDraw, "the Mystery Gift screen draws: " .. tostring(err))

  key = "b"
  Boot.update(state, input, 1 / 60)
  eq(state.phase, Boot.PHASE.MENU, "B leaves the front end for the main menu")
end

print("[test] 4. The front end receives a card and saves it")
local save, sess, st, saves
do
  save = {}
  sess = MysteryGift.sessionFromSave(save)
  saves = 0
  st = Ui.new({
    session = sess,
    onSave = function(s)
      saves = saves + 1
      return MysteryGift.applyToSave(s, save)
    end,
  })

  local keys = {}
  local function pressed(k) return keys[k] == true end
  local function step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(st, pressed, 1 / 60)
  end
  local function finishMessage()
    for _ = 1, 600 do
      if not st.msg then break end
      if st.msg.revealed >= st.msg.total then step("a") else step(nil) end
    end
  end

  -- pokefirered/src/mystery_gift_menu.c:197 sListMenuItems_CardsOrNews
  local rows = Ui.mainRows()
  teq(rows[1], "WONDER CARDS", "the front end opens on WONDER CARDS")
  teq(rows[2], "WONDER NEWS", "WONDER NEWS is the second row")
  teq(rows[3], "EXIT", "EXIT is the third row")

  step("a")
  eq(st.state, Ui.STATE.DONT_HAVE_ANY, "no card saved takes the input branch")
  check(st.msg ~= nil, "it says so first")
  finishMessage()
  eq(st.state, Ui.STATE.SOURCE_PROMPT, "then asks where to read one from")
  step(nil)
  eq(st.state, Ui.STATE.SOURCE_INPUT, "the source picker opens")
  tcheck(type(st.prompt) == "string" and st.prompt:find("WONDER CARD"),
    "the prompt names the WONDER CARD")

  local mystic = nil
  for i, entry in ipairs(st.sources) do
    if entry.key == "mystic_ticket" then mystic = i end
  end
  check(mystic ~= nil, "the MYSTIC TICKET is one of the sources")
  teq(st.rows[#st.rows], "CANCEL", "the picker ends in CANCEL")
  for _ = 2, mystic do step("down") end
  eq(st.cursor, mystic, "the cursor reached the MYSTIC TICKET row")
  step("a")
  eq(st.state, Ui.STATE.RESULT_MSG, "the card arrives")
  finishMessage()
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

print("[test] 5. The card view and its menu")
do
  local keys = {}
  local function pressed(k) return keys[k] == true end
  local function step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(st, pressed, 1 / 60)
  end
  local function confirmMessage()
    for _ = 1, 600 do
      if not st.msg then return end
      if st.msg.revealed >= st.msg.total then
        step("a")
        return
      end
      step(nil)
    end
  end

  step("a")
  eq(st.state, Ui.STATE.GIFT_INPUT, "WONDER CARDS now opens the card")
  local card = Ui.card(st)
  eq(card.titleText, "MYSTIC TICKET", "the saved card is the MYSTIC TICKET")
  eq(#card.bodyText, 4, "the card carries four body lines")

  step("a")
  eq(st.state, Ui.STATE.GIFT_SELECT, "A opens the card menu")
  -- pokefirered/src/mystery_gift_menu.c:237 sListMenuItems_ReceiveToss
  eq(#st.rows, 3, "a card that may not be sent shows three rows")
  teq(st.rows[1], "RECEIVE", "row 1 is RECEIVE")
  teq(st.rows[2], "TOSS", "row 2 is TOSS")
  teq(st.rows[3], "CANCEL", "row 3 is CANCEL")

  step("down")
  step("a")
  eq(st.state, Ui.STATE.ASK_TOSS, "TOSS asks first")
  tcheck(st.yesno ~= nil and st.yesno.text:find("event won't happen"),
    "and warns that the event will not happen")
  step("a")
  eq(st.state, Ui.STATE.ASK_TOSS_UNRECEIVED, "an uncollected gift asks a second time")
  step("a")
  eq(st.state, Ui.STATE.SAVE, "yes tosses the card and saves")
  confirmMessage()
  step(nil)
  eq(st.state, Ui.STATE.SAVE_DONE, "the toss is saved too")
  confirmMessage()
  eq(st.state, Ui.STATE.TOSSED, "the thrown-away message follows the save")
  tcheck(st.msg ~= nil and st.msg.text:find("thrown away"), "and it names the WONDER CARD")
  confirmMessage()
  eq(st.state, Ui.STATE.MAIN_MENU, "then back to the Mystery Gift menu")
  check(not MysteryGift.validateSavedCard(sess), "the saved card is gone")
  check(MysteryGift.applyToSave(sess, save), "the cleared record writes back")
  check(save.modData.mysteryGift.card == nil, "the save table lost the card")
end

print("[test] 6. Wonder News paging")
do
  local newsSave = {}
  local newsSess = MysteryGift.sessionFromSave(newsSave)
  local body = {}
  for i = 1, 10 do body[i] = "LINE " .. i end
  check(MysteryGift.receiveNews(newsSess, {
    id = 7,
    sendType = MysteryGift.SEND_TYPE_ALLOWED,
    bgType = 1,
    titleText = "WONDER NEWS",
    bodyText = body,
  }), "the news saves")
  local nst = Ui.new({ session = newsSess, onSave = function() return true end })
  local keys = {}
  local function pressed(k) return keys[k] == true end
  local function step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(nst, pressed, 1 / 60)
  end
  step("down")
  step("a")
  eq(nst.state, Ui.STATE.GIFT_INPUT, "WONDER NEWS opens the news")
  check(nst.isNews, "the news branch is active")
  eq(nst.newsScroll, 0, "the news starts unscrolled")
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
  check(okDraw, "the news view draws: " .. tostring(err))
end

print("[test] 7. The source picker only offers sources for the mode it is in")
do
  local realSources = MysteryGift.sources
  local newsEntry = {
    id = 11,
    sendType = MysteryGift.SEND_TYPE_ALLOWED,
    bgType = 2,
    titleText = "WONDER NEWS",
    bodyText = { "NEWS LINE" },
  }
  local cardEntry = MysteryGift.builtins()[1].card
  MysteryGift.sources = function()
    return {
      { key = "card_only", label = "CARD ONLY", origin = "builtin", card = cardEntry },
      { key = "news_only", label = "NEWS ONLY", origin = "file", news = newsEntry },
    }
  end

  local function openPicker(isNews)
    local st2 = Ui.new({ session = MysteryGift.sessionFromSave({}), onSave = function() return true end })
    local keys = {}
    local function pressed(k) return keys[k] == true end
    local function step(k)
      keys = {}
      if k then keys[k] = true end
      Ui.update(st2, pressed, 1 / 60)
    end
    if isNews then step("down") end
    step("a")
    for _ = 1, 600 do
      if not st2.msg then break end
      if st2.msg.revealed >= st2.msg.total then step("a") else step(nil) end
    end
    step(nil)
    return st2, step
  end

  local cardSt = openPicker(false)
  eq(cardSt.state, Ui.STATE.SOURCE_INPUT, "WONDER CARDS opens the picker")
  eq(#cardSt.sources, 1, "it offers only the card source")
  eq(cardSt.sources[1].key, "card_only", "and that source is the card one")

  local newsSt, newsStep = openPicker(true)
  eq(newsSt.state, Ui.STATE.SOURCE_INPUT, "WONDER NEWS opens the picker")
  eq(#newsSt.sources, 1, "it offers only the news source")
  eq(newsSt.sources[1].key, "news_only", "and that source is the news one")
  newsStep("a")
  eq(newsSt.state, Ui.STATE.RESULT_MSG, "picking it delivers rather than looping")
  tcheck(newsSt.msg ~= nil and tostring(newsSt.msg.text):find("received"),
    "the news arrives: " .. tostring(newsSt.msg and newsSt.msg.text))

  MysteryGift.sources = function()
    return { { key = "card_only", label = "CARD ONLY", origin = "builtin", card = cardEntry } }
  end
  local emptySt, emptyStep = openPicker(true)
  eq(emptySt.state, Ui.STATE.RESULT_MSG, "no news source opens no picker")
  -- pokefirered/src/strings.c:1304 gText_NothingSentOver
  tcheck(emptySt.msg ~= nil and tostring(emptySt.msg.text):find("Nothing was sent over"),
    "it says nothing was sent over instead")
  for _ = 1, 600 do
    if not emptySt.msg then break end
    if emptySt.msg.revealed >= emptySt.msg.total then emptyStep("a") else emptyStep(nil) end
  end
  eq(emptySt.state, Ui.STATE.MAIN_MENU, "and returns to the Mystery Gift menu instead of looping")

  MysteryGift.sources = realSources
end

print("[test] 8. The save message runs the save with no button press")
do
  local realSources = MysteryGift.sources
  local cardEntry = MysteryGift.builtins()[1].card
  MysteryGift.sources = function()
    return { { key = "card_only", label = "CARD ONLY", origin = "builtin", card = cardEntry } }
  end
  local saves = 0
  local st2 = Ui.new({
    session = MysteryGift.sessionFromSave({}),
    onSave = function() saves = saves + 1 return true end,
  })
  local keys = {}
  local function pressed(k) return keys[k] == true end
  local function step(k)
    keys = {}
    if k then keys[k] = true end
    Ui.update(st2, pressed, 1 / 60)
  end
  step("a")
  for _ = 1, 600 do
    if st2.state == Ui.STATE.SOURCE_INPUT then break end
    if st2.msg and st2.msg.revealed >= st2.msg.total then step("a") else step(nil) end
  end
  step("a")
  eq(st2.state, Ui.STATE.RESULT_MSG, "the card arrives")
  for _ = 1, 600 do
    if st2.state ~= Ui.STATE.RESULT_MSG then break end
    if st2.msg and st2.msg.revealed >= st2.msg.total then step("a") else step(nil) end
  end
  eq(st2.state, Ui.STATE.SAVE, "the save message is up")
  -- pokefirered/src/mystery_gift_menu.c:860 SaveOnMysteryGiftMenu
  for _ = 1, 600 do
    if saves > 0 then break end
    step(nil)
  end
  eq(saves, 1, "the save ran with no button press")
  eq(st2.state, Ui.STATE.SAVE_DONE, "and the completed message follows")
  tcheck(st2.msg ~= nil and tostring(st2.msg.text):find("press the A Button"),
    "which is the one that waits for A")
  MysteryGift.sources = realSources
end

print("[test] 9. EXIT stays on the menu under the MYSTERY GIFT row")
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

if failed == 0 then
  print("PASS game3_gift_menu")
else
  print("FAIL game3_gift_menu failures=" .. failed)
  os.exit(1)
end

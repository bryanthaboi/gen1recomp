-- pokefirered/src/mystery_gift_menu.c:1113 Task_MysteryGift

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local MysteryGift = require("src.core.game3.mystery_gift")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local Ui = {}

local T = 8
local CACHE_SUB = "mystery_gift"

Ui.STATE = {
  MAIN_MENU = "main_menu",
  DONT_HAVE_ANY = "dont_have_any",
  SOURCE_PROMPT = "source_prompt",
  SOURCE_INPUT = "source_input",
  ASK_REPLACE = "ask_replace",
  ASK_REPLACE_UNRECEIVED = "ask_replace_unreceived",
  RESULT_MSG = "result_msg",
  SAVE = "save",
  SAVE_DONE = "save_done",
  GIFT_INPUT = "gift_input",
  GIFT_SELECT = "gift_select",
  ASK_TOSS = "ask_toss",
  ASK_TOSS_UNRECEIVED = "ask_toss_unreceived",
  TOSSED = "tossed",
  NO_LINK = "no_link",
  EXIT = "exit",
}

-- pokefirered/src/mystery_gift_menu.c:88 sMainWindows
local TOP_WIN = Window.template(0, 0, 30, 2)
local MSG_WIN = Window.template(1, 15, 28, 4)
-- pokefirered/src/mystery_gift_menu.c:147 sWindowTemplate_ThreeOptions
local THREE_WIN = Window.template(8, 5, 14, 5)
-- pokefirered/src/mystery_gift_menu.c:157 sWindowTemplate_YesNoBox
local YESNO_WIN = Window.template(23, 15, 6, 4)
-- pokefirered/src/mystery_gift_menu.c:167 sWindowTemplate_GiftSelect_3Options
local GIFT3_WIN = Window.template(22, 12, 7, 7)
-- pokefirered/src/mystery_gift_menu.c:177 sWindowTemplate_GiftSelect_2Options
local GIFT2_WIN = Window.template(22, 14, 7, 5)
-- pokefirered/src/mystery_gift_show_card.c:67 sWindowTemplates
local CARD_HEADER = Window.template(1, 1, 25, 4)
local CARD_BODY = Window.template(1, 6, 28, 8)
local CARD_FOOTER = Window.template(1, 14, 28, 5)
-- pokefirered/src/mystery_gift_show_news.c:51 sWindowTemplates
local NEWS_TITLE = Window.template(1, 0, 28, 3)
local NEWS_BODY = Window.template(1, 3, 28, 20)

-- pokefirered/src/mystery_gift_show_card.c:60 sFooterTextOffsets
local FOOTER_OFFSET = {
  [MysteryGift.CARD_TYPE_GIFT] = 7,
  [MysteryGift.CARD_TYPE_STAMP] = 4,
  [MysteryGift.CARD_TYPE_LINK_STAT] = 7,
}

-- pokefirered/src/mystery_gift_show_news.c:346 scrollEnd
local NEWS_VISIBLE_LINES = 8
local LINE_PITCH = 16
-- pokefirered/src/list_menu.c:365 yMultiplier = FONTATTR_MAX_LETTER_HEIGHT
local ROW_PITCH = 14

local TEXT = { fg = FrlgFont.STDPAL[2], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] }
local TOP_TEXT = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
-- pokefirered/src/mystery_gift_menu.c:492 MG_DrawCheckerboardPattern
local CHECKER_A = FrlgFont.STDPAL[3]
local CHECKER_B = FrlgFont.STDPAL[11]
local TOP_BAR = FrlgFont.STDPAL[2]

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local ok, d = pcall(function() return Dataset.cache():read(rel) end)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local ok, d = pcall(CacheFs.readActive, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local ok, d = pcall(love.filesystem.read, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function art_root()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  return root .. "/" .. CACHE_SUB
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local okI, data = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okI and data) then return nil end
  local okG, img = pcall(love.graphics.newImage, data)
  if not okG then return nil end
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

Ui._images = {}

local function art(rel)
  if Ui._images[rel] == nil then
    local bytes = read_bytes(art_root() .. "/" .. rel)
    Ui._images[rel] = (bytes and rgba_to_image(bytes, 240, 160)) or false
  end
  return Ui._images[rel] or nil
end

function Ui.reloadAssets()
  Ui._images = {}
end

-- pokefirered/src/mystery_gift_show_card.c:150 sCardGraphics
function Ui.cardBackground(bgType)
  local n = tonumber(bgType) or 0
  if n < 0 or n >= MysteryGift.NUM_WONDER_BGS then n = 0 end
  return art(string.format("card_bg%d.rgba", n))
end

-- pokefirered/src/mystery_gift_show_news.c:99 sNewsGraphics
function Ui.newsBackground(bgType)
  local n = tonumber(bgType) or 0
  if n < 0 or n >= MysteryGift.NUM_WONDER_BGS then n = 0 end
  return art(string.format("news_bg%d.rgba", n))
end

local function session(st)
  return st.session
end

-- pokefirered/src/mystery_gift_menu.c:197 sListMenuItems_CardsOrNews
function Ui.mainRows()
  return RomText.list("sListMenuItems_CardsOrNews")
end

-- pokefirered/src/mystery_gift_menu.c:203 sListMenuItems_WirelessOrFriend
function Ui.sourceRows(st)
  local rows = {}
  local carried = {}
  for _, entry in ipairs(MysteryGift.sources()) do
    if (st.isNews and entry.news) or (not st.isNews and entry.card) then
      carried[#carried + 1] = entry
      rows[#rows + 1] = entry.label
    end
  end
  st.sources = carried
  rows[#rows + 1] = RomText.at("sListMenuItems_WirelessOrFriend", 2)
  return rows
end

-- pokefirered/src/mystery_gift_menu.c:230 sListMenuItems_ReceiveSendToss
function Ui.giftRows(st)
  local allowed = st.isNews and MysteryGift.isSendingNewsAllowed(session(st))
    or (not st.isNews and MysteryGift.isSendingCardAllowed(session(st)))
  local name = allowed and "sListMenuItems_ReceiveSendToss" or "sListMenuItems_ReceiveToss"
  st.giftActions = allowed and { "receive", "send", "toss", "cancel" } or { "receive", "toss", "cancel" }
  return RomText.list(name)
end

-- pokefirered/src/list_menu.c:331 maxShowed
local function setRows(st, rows, cursor, visible)
  st.rows = rows
  st.cursor = math.min(math.max(tonumber(cursor) or 1, 1), #rows)
  st.visible = math.min(tonumber(visible) or #rows, #rows)
  st.scroll = 0
end

local function say(st, text, after, auto)
  st.msg = {
    text = text,
    revealed = 0,
    total = FrlgFont.countChars(text) + 1,
    after = after,
    auto = auto and true or nil,
  }
end

local function ask(st, text, onYes, onNo)
  st.yesno = { text = text, cursor = 1, onYes = onYes, onNo = onNo }
end

function Ui.new(opts)
  opts = opts or {}
  local st = {
    session = opts.session,
    onSave = opts.onSave,
    state = Ui.STATE.MAIN_MENU,
    isNews = false,
    cursor = 1,
    scroll = 0,
    newsScroll = 0,
    rows = nil,
    msg = nil,
    yesno = nil,
    sources = nil,
  }
  setRows(st, Ui.mainRows(), 1)
  return st
end

function Ui.card(st)
  return MysteryGift.getSavedCard(session(st))
end

function Ui.news(st)
  return MysteryGift.getSavedNews(session(st))
end

-- pokefirered/src/mystery_gift_menu.c:1153 MG_STATE_DONT_HAVE_ANY
local function toSourcePrompt(st)
  st.state = Ui.STATE.SOURCE_PROMPT
end

-- pokefirered/src/mystery_gift_menu.c:855 SaveOnMysteryGiftMenu
local function beginSave(st, nextState)
  st.saveNext = nextState
  st.state = Ui.STATE.SAVE
  -- pokefirered/src/strings.c:1321 gText_DataWillBeSaved
  say(st, RomText.plain("gText_DataWillBeSaved"), nil, true)
end

-- pokefirered/src/mystery_gift_menu.c:1153 gText_DontHaveCardNewOneInput
local function dontHaveAny(st)
  st.state = Ui.STATE.DONT_HAVE_ANY
  if st.isNews then
    say(st, RomText.plain("gText_DontHaveNewsNewOneInput"), toSourcePrompt)
  else
    say(st, RomText.plain("gText_DontHaveCardNewOneInput"), toSourcePrompt)
  end
end

-- pokefirered/src/mystery_gift_menu.c:1159 MG_STATE_LOAD_GIFT
local function loadGift(st)
  st.state = Ui.STATE.GIFT_INPUT
  st.newsScroll = 0
  st.msg = nil
end

local function toMainMenu(st)
  st.state = Ui.STATE.MAIN_MENU
  st.isNews = false
  st.msg = nil
  st.yesno = nil
  setRows(st, Ui.mainRows(), 1)
end

-- pokefirered/src/mystery_gift_client.c:208 CLI_SAVE_CARD
local function receiveFrom(st, entry)
  local sess = session(st)
  local ok
  if st.isNews then
    ok = entry.news ~= nil
      and MysteryGift.receiveNews(sess, entry.news, MysteryGift.WONDER_NEWS_RECV_WIRELESS)
  else
    ok = entry.card ~= nil and MysteryGift.receiveCard(sess, entry.card)
  end
  st.state = Ui.STATE.RESULT_MSG
  if not ok then
    -- pokefirered/src/strings.c:1304 gText_NothingSentOver
    say(st, RomText.plain("gText_NothingSentOver"), function(s) toSourcePrompt(s) end)
    return false
  end
  if st.isNews then
    -- pokefirered/src/strings.c:1294 gText_WonderNewsReceived
    say(st, RomText.plain("gText_WonderNewsReceived"), function(s)
      beginSave(s, Ui.STATE.MAIN_MENU)
    end)
  else
    -- pokefirered/src/strings.c:1293 gText_WonderCardReceived
    say(st, RomText.plain("gText_WonderCardReceived"), function(s)
      beginSave(s, Ui.STATE.MAIN_MENU)
    end)
  end
  return true
end

-- pokefirered/src/mystery_gift_menu.c:1292 MG_STATE_CLIENT_ASK_TOSS
local function pickSource(st, entry)
  local sess = session(st)
  local held = st.isNews and MysteryGift.validateSavedNews(sess)
    or (not st.isNews and MysteryGift.validateSavedCard(sess))
  if not held then return receiveFrom(st, entry) end
  st.state = Ui.STATE.ASK_REPLACE
  -- pokefirered/src/strings.c:1289 gText_ThrowAwayWonderCard
  ask(st, RomText.plain("gText_ThrowAwayWonderCard"), function(s)
    if not s.isNews and MysteryGift.isGiftNotReceived(session(s)) then
      s.state = Ui.STATE.ASK_REPLACE_UNRECEIVED
      -- pokefirered/src/strings.c:1290 gText_HaventReceivedCardsGift
      ask(s, RomText.plain("gText_HaventReceivedCardsGift"), function(s2)
        receiveFrom(s2, entry)
      end, function(s2)
        s2.state = Ui.STATE.SOURCE_INPUT
      end)
      return
    end
    receiveFrom(s, entry)
  end, function(s)
    s.state = Ui.STATE.SOURCE_INPUT
  end)
end

-- pokefirered/src/mystery_gift_menu.c:1484 MG_STATE_TOSS
local function tossGift(st)
  local sess = session(st)
  if st.isNews then
    MysteryGift.clearNewsAndRelated(sess)
  else
    MysteryGift.clearCardAndRelated(sess)
  end
  beginSave(st, Ui.STATE.TOSSED)
end

-- pokefirered/src/mystery_gift_menu.c:839 AskDiscardGift
local function askToss(st)
  st.state = Ui.STATE.ASK_TOSS
  local text = st.isNews
    and RomText.plain("gText_OkayToDiscardNews")
    or RomText.plain("gText_IfThrowAwayCardEventWontHappen")
  ask(st, text, function(s)
    if not s.isNews and MysteryGift.isGiftNotReceived(session(s)) then
      s.state = Ui.STATE.ASK_TOSS_UNRECEIVED
      -- pokefirered/src/strings.c:1320 gText_HaventReceivedGiftOkayToDiscard
      ask(s, RomText.plain("gText_HaventReceivedGiftOkayToDiscard"), tossGift, function(s2)
        s2.state = Ui.STATE.GIFT_SELECT
      end)
      return
    end
    tossGift(s)
  end, function(s)
    s.state = Ui.STATE.GIFT_SELECT
  end)
end

local function tickMsg(st, pressed)
  local m = st.msg
  if m.revealed < m.total then
    m.revealed = m.revealed + 1
    return
  end
  -- pokefirered/src/mystery_gift_menu.c:860 case 0 falls through to the save with no input
  if m.auto then
    st.msg = nil
    if m.after then m.after(st) end
    return
  end
  if not pressed("a") and not pressed("b") then return end
  se(5)
  st.msg = nil
  if m.after then m.after(st) end
end

local function tickYesNo(st, pressed)
  local y = st.yesno
  if pressed("up") and y.cursor > 1 then y.cursor = 1 end
  if pressed("down") and y.cursor < 2 then y.cursor = 2 end
  if pressed("a") then
    se(5)
    st.yesno = nil
    if y.cursor == 1 then
      if y.onYes then y.onYes(st) end
    elseif y.onNo then
      y.onNo(st)
    end
  elseif pressed("b") then
    se(5)
    st.yesno = nil
    if y.onNo then y.onNo(st) end
  end
end

local function clampScroll(st)
  local visible = st.visible or #(st.rows or {})
  st.scroll = st.scroll or 0
  if st.cursor <= st.scroll then st.scroll = st.cursor - 1 end
  if st.cursor > st.scroll + visible then st.scroll = st.cursor - visible end
  if st.scroll < 0 then st.scroll = 0 end
end

local function tickList(st, pressed)
  local n = #(st.rows or {})
  if n < 1 then return nil end
  if pressed("up") and st.cursor > 1 then
    se(5)
    st.cursor = st.cursor - 1
    clampScroll(st)
  elseif pressed("down") and st.cursor < n then
    se(5)
    st.cursor = st.cursor + 1
    clampScroll(st)
  elseif pressed("a") then
    se(5)
    return st.cursor
  elseif pressed("b") then
    se(5)
    return -1
  end
  return nil
end

-- pokefirered/src/mystery_gift_show_news.c:292 WonderNews_GetInput
local function tickNewsScroll(st, pressed)
  local news = Ui.news(st)
  local lines = (news and news.bodyText) or {}
  local last = 0
  for i = 1, #lines do
    if lines[i] ~= "" then last = i end
  end
  local maxScroll = math.max(0, last - NEWS_VISIBLE_LINES)
  if pressed("up") and st.newsScroll > 0 then st.newsScroll = st.newsScroll - 1 end
  if pressed("down") and st.newsScroll < maxScroll then st.newsScroll = st.newsScroll + 1 end
end

function Ui.update(st, pressed, dt)
  if type(st) ~= "table" then return "exit" end
  if type(pressed) ~= "function" then return nil end
  if st.msg then
    tickMsg(st, pressed)
    if st.state == Ui.STATE.SAVE and not st.msg then return nil end
    return nil
  end
  if st.yesno then
    tickYesNo(st, pressed)
    return nil
  end

  local S = Ui.STATE
  if st.state == S.MAIN_MENU then
    local pick = tickList(st, pressed)
    if pick == 1 or pick == 2 then
      st.isNews = (pick == 2)
      local held = st.isNews and MysteryGift.validateSavedNews(session(st))
        or (not st.isNews and MysteryGift.validateSavedCard(session(st)))
      if held then loadGift(st) else dontHaveAny(st) end
    elseif pick == 3 or pick == -1 then
      st.state = S.EXIT
      return "exit"
    end
    return nil
  end

  if st.state == S.SOURCE_PROMPT then
    local rows = Ui.sourceRows(st)
    if #(st.sources or {}) == 0 then
      st.prompt = nil
      st.state = S.RESULT_MSG
      -- pokefirered/src/strings.c:1304 gText_NothingSentOver
      say(st, RomText.plain("gText_NothingSentOver"), toMainMenu)
      return nil
    end
    setRows(st, rows, 1, 5)
    st.state = S.SOURCE_INPUT
    -- pokefirered/src/strings.c:1282 gText_WhereShouldCardBeAccessed
    st.prompt = st.isNews
      and RomText.plain("gText_WhereShouldNewsBeAccessed")
      or RomText.plain("gText_WhereShouldCardBeAccessed")
    return nil
  end

  if st.state == S.SOURCE_INPUT then
    local pick = tickList(st, pressed)
    if pick and pick > 0 and pick <= #(st.sources or {}) then
      pickSource(st, st.sources[pick])
    elseif pick then
      st.prompt = nil
      local held = st.isNews and MysteryGift.validateSavedNews(session(st))
        or (not st.isNews and MysteryGift.validateSavedCard(session(st)))
      if held then loadGift(st) else toMainMenu(st) end
    end
    return nil
  end

  if st.state == S.SAVE then
    local ok = true
    if st.onSave then ok = st.onSave(session(st)) ~= false end
    local nextState = st.saveNext
    st.saveNext = nil
    st.state = S.SAVE_DONE
    -- pokefirered/src/strings.c:1322 gText_SaveCompletedPressA
    say(st, ok and RomText.plain("gText_SaveCompletedPressA")
      or Strings("Save failed."), function(s)
      if nextState == S.TOSSED then
        s.state = S.TOSSED
        -- pokefirered/src/strings.c:1323 gText_WonderCardThrownAway
        say(s, s.isNews and RomText.plain("gText_WonderNewsThrownAway")
          or RomText.plain("gText_WonderCardThrownAway"), toMainMenu)
      else
        toMainMenu(s)
      end
    end)
    return nil
  end

  if st.state == S.GIFT_INPUT then
    if st.isNews then tickNewsScroll(st, pressed) end
    if pressed("a") then
      se(5)
      st.state = S.GIFT_SELECT
      setRows(st, Ui.giftRows(st), 1)
    elseif pressed("b") then
      se(5)
      toMainMenu(st)
    end
    return nil
  end

  if st.state == S.GIFT_SELECT then
    local pick = tickList(st, pressed)
    if not pick then return nil end
    local action = (pick > 0) and (st.giftActions or {})[pick] or nil
    if pick == -1 or action == "cancel" then
      st.state = S.GIFT_INPUT
    elseif action == "receive" then
      toSourcePrompt(st)
    elseif action == "send" then
      st.state = S.NO_LINK
      -- pokefirered/src/strings.c:24 gText_WirelessNotConnected
      say(st, RomText.plain("gText_WirelessNotConnected"), function(s)
        s.state = S.GIFT_SELECT
        setRows(s, Ui.giftRows(s), 1)
      end)
    elseif action == "toss" then
      askToss(st)
    end
    return nil
  end

  return nil
end

local function drawChecker()
  love.graphics.setColor(TOP_BAR[1], TOP_BAR[2], TOP_BAR[3], 1)
  love.graphics.rectangle("fill", 0, 0, 240, 2 * T)
  for row = 0, 17 do
    for col = 0, 29 do
      local c = ((row % 2) ~= (col % 2)) and CHECKER_A or CHECKER_B
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.rectangle("fill", col * T, (row + 2) * T, T, T)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/mystery_gift_menu.c:466 PrintMysteryGiftOrEReaderTopMenu
local function drawTopBar(st)
  love.graphics.setColor(TOP_BAR[1], TOP_BAR[2], TOP_BAR[3], 1)
  love.graphics.rectangle("fill", 0, 0, 240, TOP_WIN.height * T)
  love.graphics.setColor(1, 1, 1, 1)
  Window.printPx(RomText.plain("gText_MysteryGift2"), 2, 2, { colors = TOP_TEXT })
  local hint = (st.state == Ui.STATE.SOURCE_INPUT)
    and RomText.plain("gText_PickOKExit")
    or RomText.plain("gText_PickOKCancel")
  local okC, PokedexChrome = pcall(require, "src.ui.game3.pokedex_chrome")
  if okC and PokedexChrome and PokedexChrome.drawControlInfo then
    PokedexChrome.drawControlInfo(hint, 222, 2)
  else
    Window.printPx(hint, 120, 2, { colors = TOP_TEXT, small = true })
  end
end

-- pokefirered/src/list_menu.c:370 item_X, :384 cursor_X
local function drawList(st, tpl)
  Window.stdFrame(tpl)
  local x = tpl.left * T
  local y = tpl.top * T
  local rows = st.rows or {}
  local scroll = st.scroll or 0
  local visible = math.min(st.visible or #rows, #rows)
  for i = 1, visible do
    local row = rows[i + scroll]
    if row then
      Window.printPx(row, x + 8, y + (i - 1) * ROW_PITCH, { colors = TEXT })
    end
  end
  Window.cursorPx(x, y + (st.cursor - scroll - 1) * ROW_PITCH, { colors = TEXT })
end

local function drawMessage(text, revealed)
  Window.stdFrame(MSG_WIN)
  Window.printPx(text, MSG_WIN.left * T, MSG_WIN.top * T + 2, {
    colors = TEXT,
    maxWidth = MSG_WIN.width * T,
    limitChars = revealed,
  })
end

local function drawYesNo(st)
  local y = st.yesno
  drawMessage(y.text, nil)
  Window.stdFrame(YESNO_WIN)
  local x = YESNO_WIN.left * T
  local y0 = YESNO_WIN.top * T
  Window.printPx(RomText.plain("gText_Yes"), x + 8, y0, { colors = TEXT })
  Window.printPx(RomText.plain("gText_No"), x + 8, y0 + ROW_PITCH, { colors = TEXT })
  Window.cursorPx(x, y0 + (y.cursor - 1) * ROW_PITCH, { colors = TEXT })
end

local function drawMonIcon(species, cx, cy)
  if not species or species == 0 then return end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not okP then return end
  local okI, icon = pcall(Pokemon.icon, species)
  if not (okI and icon and icon.image) then return end
  local quad = icon.quads and icon.quads[0]
  if quad then
    love.graphics.draw(icon.image, quad, cx - 16, cy - 16)
  else
    love.graphics.draw(icon.image, cx - 16, cy - 16)
  end
end

-- pokefirered/src/mystery_gift_show_card.c:390 DrawCardWindow
function Ui.drawCard(st)
  local card = Ui.card(st)
  if not card then return end
  local bg = Ui.cardBackground(card.bgType)
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    drawChecker()
    Window.stdFrame(Window.template(1, 1, 28, 18))
  end

  local hx, hy = CARD_HEADER.left * T, CARD_HEADER.top * T
  Window.printPx(card.titleText or "", hx, hy + 1, { colors = TEXT })
  local subW = FrlgFont.measure(card.subtitleText or "") or 0
  local sx = 160 - subW
  if sx < 0 then sx = 0 end
  Window.printPx(card.subtitleText or "", hx + sx, hy + 17, { colors = TEXT })
  if (tonumber(card.idNumber) or 0) ~= 0 then
    Window.printPx(tostring(card.idNumber), hx + 166, hy + 17, { colors = TEXT })
  end

  local bx, by = CARD_BODY.left * T, CARD_BODY.top * T
  for i = 1, 4 do
    Window.printPx((card.bodyText or {})[i] or "", bx, by + LINE_PITCH * (i - 1) + 2, { colors = TEXT })
  end

  local fx, fy = CARD_FOOTER.left * T, CARD_FOOTER.top * T
  local off = FOOTER_OFFSET[tonumber(card.type) or 0] or 7
  Window.printPx(card.footerLine1Text or "", fx, fy + off, { colors = TEXT })
  if (tonumber(card.type) or 0) ~= MysteryGift.CARD_TYPE_LINK_STAT then
    Window.printPx(card.footerLine2Text or "", fx, fy + off + 16, { colors = TEXT })
  else
    local meta = MysteryGift.getSavedCardMetadata(session(st))
    local line = string.format("%03d - %03d - %03d",
      math.min(tonumber(meta.battlesWon) or 0, MysteryGift.MAX_WONDER_CARD_STAT),
      math.min(tonumber(meta.battlesLost) or 0, MysteryGift.MAX_WONDER_CARD_STAT),
      math.min(tonumber(meta.numTrades) or 0, MysteryGift.MAX_WONDER_CARD_STAT))
    Window.printPx(line, fx, fy + off + 16, { colors = TEXT })
  end

  local meta = MysteryGift.getSavedCardMetadata(session(st))
  drawMonIcon(tonumber(meta.iconSpecies), 220, 20)
  -- pokefirered/src/mystery_gift_show_card.c:460 CreateCardSprites
  local maxStamps = tonumber(card.maxStamps) or 0
  if maxStamps > 0 and (tonumber(card.type) or 0) == MysteryGift.CARD_TYPE_STAMP then
    for i = 1, maxStamps do
      local x = 216 - 32 * (i - 1)
      love.graphics.setColor(TEXT.shadow[1], TEXT.shadow[2], TEXT.shadow[3], 1)
      love.graphics.rectangle("fill", x - 16, 136 - 8, 32, 16)
      love.graphics.setColor(1, 1, 1, 1)
      drawMonIcon(tonumber(meta.stampData.species[i]), x, 136)
    end
  end
end

-- pokefirered/src/mystery_gift_show_news.c:353 DrawNewsWindows
function Ui.drawNews(st)
  local news = Ui.news(st)
  if not news then return end
  local bg = Ui.newsBackground(news.bgType)
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    drawChecker()
    Window.stdFrame(Window.template(1, 0, 28, 19))
  end
  local tw = FrlgFont.measure(news.titleText or "") or 0
  local x = math.floor((224 - tw) / 2)
  if x < 0 then x = 0 end
  Window.printPx(news.titleText or "", NEWS_TITLE.left * T + x, NEWS_TITLE.top * T + 6, { colors = TEXT })
  local by = NEWS_BODY.top * T
  for i = 1, NEWS_VISIBLE_LINES do
    local line = (news.bodyText or {})[i + st.newsScroll] or ""
    Window.printPx(line, NEWS_BODY.left * T, by + LINE_PITCH * (i - 1) + 2, { colors = TEXT })
  end
end

function Ui.draw(st)
  local S = Ui.STATE
  if st.state == S.GIFT_INPUT or st.state == S.GIFT_SELECT
    or st.state == S.ASK_TOSS or st.state == S.ASK_TOSS_UNRECEIVED
    or st.state == S.NO_LINK then
    if st.isNews then Ui.drawNews(st) else Ui.drawCard(st) end
  else
    drawChecker()
    drawTopBar(st)
  end

  if st.state == S.MAIN_MENU then
    drawList(st, THREE_WIN)
  elseif st.state == S.SOURCE_INPUT then
    if st.prompt then drawMessage(st.prompt, nil) end
    local shown = math.min(st.visible or #(st.rows or {}), #(st.rows or {}))
    local h = math.ceil(shown * ROW_PITCH / T)
    drawList(st, Window.template(5, 3, 20, math.max(h, 2)))
  elseif st.state == S.GIFT_SELECT then
    drawList(st, (#(st.rows or {}) > 3) and GIFT3_WIN or GIFT2_WIN)
  end

  if st.yesno then
    drawYesNo(st)
  elseif st.msg then
    drawMessage(st.msg.text, math.min(st.msg.revealed, st.msg.total))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Ui

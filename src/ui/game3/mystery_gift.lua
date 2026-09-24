-- pokefirered/src/mystery_gift_menu.c:1113 Task_MysteryGift

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local MysteryGift = require("src.core.game3.mystery_gift")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local WirelessIcon = require("src.ui.game3.wireless_icon")

local Ui = {}

local T = 8
local CACHE_DIR = "data/generated/gba/mystery_gift/"

-- pokefirered/include/constants/songs.h:265
local MUS_OBTAIN_ITEM = 258
local SE_BOO = 22
local SE_POKENAV_ON = 103

-- pokefirered/src/union_room.c:2471
Ui.SEARCH_MIN_FRAMES = 120
Ui.COMMUNICATING_FRAMES = 30
-- pokefirered/src/mystery_gift_menu.c:604
Ui.COMPLETED_FRAMES = 120
-- pokefirered/src/mystery_gift_menu.c:968
Ui.SUCCESS_FRAMES = 240

Ui.STATE = {
  MAIN_MENU = "main_menu",
  DONT_HAVE_ANY = "dont_have_any",
  SOURCE_PROMPT = "source_prompt",
  SOURCE_INPUT = "source_input",
  SEARCHING = "searching",
  OFFER_LIST = "offer_list",
  COMMUNICATING = "communicating",
  COMM_COMPLETED = "comm_completed",
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
local MSG_WIN = Window.template(1, 15, 28, 4)
-- pokefirered/src/mystery_gift_menu.c:147 sWindowTemplate_ThreeOptions
local THREE_WIN = Window.template(8, 5, 14, 5)
-- pokefirered/src/data/union_room.h:105
local OFFER_WIN = Window.template(1, 3, 17, 10)
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

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function fanfare(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playFanfare then Audio.playFanfare(id) end
  end)
end

local function fanfareDone()
  local Audio = package.loaded["src.core.game3.audio"]
  if not (Audio and Audio.isFanfareFinished) then return true end
  local ok, done = pcall(Audio.isFanfareFinished)
  return not ok or done ~= false
end

local function cacheRead(rel)
  local Dataset = require("src.core.game3.dataset")
  local bytes = Dataset.cache():read(CACHE_DIR .. rel)
  assert(type(bytes) == "string" and #bytes > 0, "mystery_gift/" .. rel .. " is missing from the cache")
  return bytes
end

Ui._images = {}
Ui._manifest = nil

function Ui.manifest()
  if not Ui._manifest then
    local src = cacheRead("manifest.lua")
    local fn = assert(loadstring(src, "@mystery_gift/manifest.lua"))
    setfenv(fn, {})
    Ui._manifest = fn()
  end
  return Ui._manifest
end

local function artSize(key)
  local manifest = Ui.manifest()
  local row = manifest[key]
  if type(row) ~= "table" then
    for _, entry in ipairs(manifest.entries) do
      if entry.key == key then row = manifest break end
    end
  end
  assert(type(row) == "table", "mystery_gift/manifest.lua has no row for " .. key)
  local w, h = tonumber(row.width), tonumber(row.height)
  assert(w and h, "mystery_gift/manifest.lua has no size for " .. key)
  return w, h
end

local function art(key)
  if not (love and love.image and love.graphics and love.graphics.newImage) then return nil end
  if Ui._images[key] == nil then
    local w, h = artSize(key)
    local bytes = cacheRead(key .. ".rgba")
    assert(#bytes >= w * h * 4, "mystery_gift/" .. key .. ".rgba is truncated")
    local img = love.graphics.newImage(love.image.newImageData(w, h, "rgba8", bytes))
    img:setFilter("nearest", "nearest")
    Ui._images[key] = img
  end
  return Ui._images[key]
end

function Ui.reloadAssets()
  Ui._images = {}
  Ui._manifest = nil
end

-- pokefirered/src/mystery_gift_show_card.c:150 sCardGraphics
function Ui.cardBackground(bgType)
  local n = tonumber(bgType) or 0
  if n < 0 or n >= MysteryGift.NUM_WONDER_BGS then n = 0 end
  return art(string.format("card_bg%d", n))
end

-- pokefirered/src/mystery_gift_show_card.c:55
function Ui.textColors(key, field)
  for _, entry in ipairs(Ui.manifest().entries or {}) do
    if entry.key == key then
      return tonumber(entry[field]) == 1 and TOP_TEXT or TEXT
    end
  end
  return TEXT
end

function Ui.stamps()
  local stamps = Ui.manifest().stamps
  assert(type(stamps) == "table", "mystery_gift/manifest.lua has no stamps row")
  return stamps
end

-- pokefirered/src/mystery_gift_show_card.c:150
function Ui.stampShadow(bgType)
  local n = tonumber(bgType) or 0
  if n < 0 or n >= MysteryGift.NUM_WONDER_BGS then n = 0 end
  local manifest = Ui.manifest()
  local pal = tonumber(manifest.entries[n + 1].stampShadowPal)
  assert(pal, "mystery_gift/manifest.lua entry " .. n .. " has no stampShadowPal")
  local prefix = Ui.stamps().key_prefix
  assert(type(prefix) == "string", "mystery_gift/manifest.lua stamps has no key_prefix")
  return art(prefix .. pal)
end

-- pokefirered/src/mystery_gift_show_news.c:99 sNewsGraphics
function Ui.newsBackground(bgType)
  local n = tonumber(bgType) or 0
  if n < 0 or n >= MysteryGift.NUM_WONDER_BGS then n = 0 end
  return art(string.format("news_bg%d", n))
end

local function session(st)
  return st.session
end

-- pokefirered/src/mystery_gift_menu.c:197 sListMenuItems_CardsOrNews
function Ui.mainRows()
  return RomText.list("sListMenuItems_CardsOrNews")
end

-- pokefirered/src/mystery_gift_menu.c:203 sListMenuItems_WirelessOrFriend
function Ui.sourceRows()
  return RomText.list("sListMenuItems_WirelessOrFriend")
end

-- pokefirered/src/mystery_gift_menu.c:630
function Ui.threeOptionTemplate(rows)
  local width = 0
  for _, row in ipairs(rows or {}) do
    local w = FrlgFont.measure(row) or 0
    if w > width then width = w end
  end
  local final = math.floor((width + 9) / 8) + 2
  final = final - (final % 2)
  return Window.template(math.floor((30 - final) / 2), THREE_WIN.top, final, THREE_WIN.height)
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

local function say(st, text, after, auto, hold)
  st.msg = {
    text = text,
    revealed = 0,
    total = FrlgFont.countChars(text) + 1,
    after = after,
    auto = auto and true or nil,
    hold = tonumber(hold),
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
    fetchOpts = opts.fetch,
    state = Ui.STATE.MAIN_MENU,
    isNews = false,
    cursor = 1,
    scroll = 0,
    newsScroll = 0,
    rows = nil,
    msg = nil,
    yesno = nil,
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
  st.prompt = nil
end

local function toMainMenu(st)
  st.state = Ui.STATE.MAIN_MENU
  st.isNews = false
  st.msg = nil
  st.prompt = nil
  st.yesno = nil
  setRows(st, Ui.mainRows(), 1)
end

local function iconOff()
  WirelessIcon.force(false)
end

local function closeOffers(st)
  st.offers = nil
  st.list = nil
  st.prompt = nil
end

local function toSourcePromptOffline(st)
  iconOff()
  toSourcePrompt(st)
end

local function toMainMenuOffline(st)
  iconOff()
  toMainMenu(st)
end

-- pokefirered/src/mystery_gift_menu.c:1352
local function clientResult(st, textKey, success)
  st.state = Ui.STATE.RESULT_MSG
  if success then
    fanfare(MUS_OBTAIN_ITEM)
    say(st, RomText.plain(textKey), function(s)
      beginSave(s, Ui.STATE.MAIN_MENU)
    end, true, Ui.SUCCESS_FRAMES)
  else
    say(st, RomText.plain(textKey), toMainMenu)
  end
end

-- pokefirered/src/mystery_gift_menu.c:1344
local function commCompleted(st, textKey, success)
  iconOff()
  st.state = Ui.STATE.COMM_COMPLETED
  st.prompt = RomText.plain("gText_CommunicationCompleted")
  st.timer = 0
  st.pendingResult = { key = textKey, success = success }
end

-- pokefirered/src/mystery_gift_client.c:208 CLI_SAVE_CARD
local function receiveFrom(st, entry)
  local sess = session(st)
  local ok
  if st.isNews then
    ok = entry.news ~= nil
      and MysteryGift.receiveNews(sess, entry.news, MysteryGift.WONDER_NEWS_RECV_WIRELESS)
    if ok then MysteryGift.claimNews(sess, entry.news) end
  else
    ok = entry.card ~= nil and MysteryGift.receiveCard(sess, entry.card)
    if ok then MysteryGift.claimCard(sess, entry.card) end
  end
  if not ok then
    -- pokefirered/src/mystery_gift_menu.c:935
    commCompleted(st, "gText_CommunicationError", false)
    return false
  end
  -- pokefirered/src/mystery_gift_menu.c:899
  commCompleted(st, st.isNews and "gText_WonderNewsReceived" or "gText_WonderCardReceived", true)
  return true
end

local function canceledClient(st)
  -- pokefirered/src/mystery_gift_menu.c:927
  commCompleted(st, "gText_CommunicationCanceled", false)
end

-- pokefirered/src/mystery_gift_menu.c:1292 MG_STATE_CLIENT_ASK_TOSS
local function deliverOffer(st, entry)
  local sess = session(st)
  if st.isNews then
    -- pokefirered/src/mystery_gift_menu.c:919
    if MysteryGift.hasClaimedNews(sess, entry.news) then
      return commCompleted(st, "gText_AlreadyHadNews", false)
    end
    return receiveFrom(st, entry)
  end
  -- pokefirered/src/mystery_gift_menu.c:911
  if MysteryGift.hasClaimedCard(sess, entry.card) then
    return commCompleted(st, "gText_AlreadyHadCard", false)
  end
  if not MysteryGift.validateSavedCard(sess) then return receiveFrom(st, entry) end
  st.state = Ui.STATE.ASK_REPLACE
  st.prompt = nil
  -- pokefirered/src/strings.c:1289 gText_ThrowAwayWonderCard
  ask(st, RomText.plain("gText_ThrowAwayWonderCard"), function(s)
    if MysteryGift.isGiftNotReceived(session(s)) then
      s.state = Ui.STATE.ASK_REPLACE_UNRECEIVED
      -- pokefirered/src/strings.c:1290 gText_HaventReceivedCardsGift
      ask(s, RomText.plain("gText_HaventReceivedCardsGift"), function(s2)
        receiveFrom(s2, entry)
      end, canceledClient)
      return
    end
    receiveFrom(s, entry)
  end, canceledClient)
end

function Ui.offerRows(st)
  local sess = session(st)
  local ListMenu = require("src.ui.game3.list_menu")
  local items = {}
  for i, entry in ipairs(st.offers or {}) do
    local claimed = st.isNews and MysteryGift.hasClaimedNews(sess, entry.news)
      or (not st.isNews and MysteryGift.hasClaimedCard(sess, entry.card))
    items[i] = {
      label = entry.label,
      id = i,
      entry = entry,
      -- pokefirered/src/union_room.c:4072
      colors = claimed and ListMenu.COLOR_WHITE or nil,
    }
  end
  return items
end

local function inputAdapter(pressed)
  return {
    pressed = pressed,
    wasPressed = function(_, k) return pressed(k) end,
    isDown = function() return false end,
  }
end

-- pokefirered/src/union_room.c:2458
local function openOffers(st, list)
  st.offers = st.isNews and list.news or list.cards
  if #(st.offers or {}) == 0 then
    se(SE_BOO)
    closeOffers(st)
    st.state = Ui.STATE.RESULT_MSG
    -- pokefirered/src/union_room.c:2560
    say(st, RomText.at("gTexts_UR_NoWonderShared", st.isNews and 1 or 0), toSourcePromptOffline)
    return
  end
  se(SE_POKENAV_ON)
  WirelessIcon.force("3bars")
  st.state = Ui.STATE.OFFER_LIST
  -- pokefirered/src/union_room.c:2521
  st.prompt = RomText.plain("gText_UR_WirelessLinkEstablished")
  local ListMenu = require("src.ui.game3.list_menu")
  st.list = ListMenu.new({
    template = OFFER_WIN,
    frame = "fixed",
    items = Ui.offerRows(st),
    maxShowed = 5,
    itemX = 8,
    cursorX = 0,
    upTextY = 0,
    rowHeight = 16,
    scrollMultiple = "lr",
    sound = true,
  })
end

-- pokefirered/src/union_room.c:2423
local function startSearch(st)
  st.prompt = RomText.plain("gText_UR_SearchingForWirelessSystemWait")
  st.state = Ui.STATE.SEARCHING
  st.timer = 0
  st.lastError = nil
  st.job = MysteryGift.fetchOnline(st.fetchOpts)
  WirelessIcon.force("searching")
end

-- pokefirered/src/mystery_gift_menu.c:1240
local function pickOffer(st, entry)
  st.list = nil
  st.offer = entry
  st.state = Ui.STATE.COMMUNICATING
  st.timer = 0
  st.prompt = RomText.plain("gText_Communicating")
end

function Ui.close(st)
  if type(st) == "table" and st.job then
    MysteryGift.cancelOnline(st.job)
    st.job = nil
  end
  WirelessIcon.force(nil)
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
  -- pokefirered/src/mystery_gift_menu.c:956
  if m.hold then
    m.held = (m.held or 0) + 1
    if m.held <= m.hold or not fanfareDone() then return end
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
  WirelessIcon.update(tonumber(dt) or (1 / 60))
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
      Ui.close(st)
      return "exit"
    end
    return nil
  end

  if st.state == S.SOURCE_PROMPT then
    setRows(st, Ui.sourceRows(), 1)
    st.state = S.SOURCE_INPUT
    -- pokefirered/src/strings.c:1282 gText_WhereShouldCardBeAccessed
    st.prompt = st.isNews
      and RomText.plain("gText_WhereShouldNewsBeAccessed")
      or RomText.plain("gText_WhereShouldCardBeAccessed")
    return nil
  end

  -- pokefirered/src/mystery_gift_menu.c:1176
  if st.state == S.SOURCE_INPUT then
    local pick = tickList(st, pressed)
    if pick == 1 then
      startSearch(st)
    elseif pick == 2 then
      st.prompt = nil
      st.state = S.RESULT_MSG
      -- pokefirered/src/strings.c:24
      say(st, RomText.plain("gText_WirelessNotConnected"), toSourcePrompt)
    elseif pick then
      st.prompt = nil
      local held = st.isNews and MysteryGift.validateSavedNews(session(st))
        or (not st.isNews and MysteryGift.validateSavedCard(session(st)))
      if held then loadGift(st) else toMainMenu(st) end
    end
    return nil
  end

  -- pokefirered/src/union_room.c:2458
  if st.state == S.SEARCHING then
    st.timer = (st.timer or 0) + 1
    if pressed("b") then
      MysteryGift.cancelOnline(st.job)
      st.job = nil
      closeOffers(st)
      st.state = S.RESULT_MSG
      -- pokefirered/src/union_room.c:2551
      say(st, RomText.plain("gText_UR_WirelessSearchCanceled"), toSourcePromptOffline)
      return nil
    end
    local status, result = MysteryGift.pollOnline(st.job)
    if status == "pending" or st.timer <= Ui.SEARCH_MIN_FRAMES then return nil end
    st.job = nil
    if status == "ok" then
      openOffers(st, result)
      return nil
    end
    closeOffers(st)
    st.state = S.RESULT_MSG
    WirelessIcon.force("error")
    st.lastError = result
    if result == "offline" then
      -- pokefirered/src/strings.c:24
      say(st, RomText.plain("gText_WirelessNotConnected"), toSourcePromptOffline)
    else
      -- pokefirered/src/mystery_gift_menu.c:1590
      say(st, RomText.plain("gText_CommunicationError"), toMainMenuOffline)
    end
    return nil
  end

  if st.state == S.OFFER_LIST then
    local list = st.list
    if list and list.update then list:update(tonumber(dt) or (1 / 60)) end
    local verdict = list and list:handleInput(inputAdapter(pressed)) or nil
    if verdict == "select" then
      local item = list:selected()
      if item and item.entry then pickOffer(st, item.entry) end
    elseif verdict == "cancel" then
      closeOffers(st)
      st.state = S.RESULT_MSG
      -- pokefirered/src/union_room.c:2551
      say(st, RomText.plain("gText_UR_WirelessSearchCanceled"), toSourcePromptOffline)
    end
    return nil
  end

  if st.state == S.COMMUNICATING then
    st.timer = (st.timer or 0) + 1
    if st.timer >= Ui.COMMUNICATING_FRAMES then
      local entry = st.offer
      st.offer = nil
      deliverOffer(st, entry)
    end
    return nil
  end

  if st.state == S.COMM_COMPLETED then
    st.timer = (st.timer or 0) + 1
    if st.timer > Ui.COMPLETED_FRAMES then
      local r = st.pendingResult or {}
      st.pendingResult = nil
      closeOffers(st)
      clientResult(st, r.key or "gText_CommunicationError", r.success)
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

-- pokefirered/src/mystery_gift_menu.c:492
local function drawMenuBg()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(art("menu_bg"), 0, 0)
end

-- pokefirered/src/mystery_gift_menu.c:466 PrintMysteryGiftOrEReaderTopMenu
local function drawTopBar(st)
  Window.printPx(RomText.plain("gText_MysteryGift2"), 2, 2, { colors = TOP_TEXT })
  local S = Ui.STATE
  local useExit = st.state == S.SOURCE_INPUT or st.state == S.SEARCHING
    or st.state == S.OFFER_LIST or st.state == S.COMMUNICATING
  local hint = useExit
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

-- pokefirered/src/mystery_gift_menu.c:529
local function drawMessage(text, revealed)
  Window.fixedStdFrame(MSG_WIN)
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
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Ui.cardBackground(card.bgType), 0, 0)

  local key = "card_bg" .. (tonumber(card.bgType) or 0)
  local titleColors = Ui.textColors(key, "titleTextPal")
  local bodyColors = Ui.textColors(key, "bodyTextPal")
  local footerColors = Ui.textColors(key, "footerTextPal")
  local hx, hy = CARD_HEADER.left * T, CARD_HEADER.top * T
  Window.printPx(card.titleText or "", hx, hy + 1, { colors = titleColors })
  local subW = FrlgFont.measure(card.subtitleText or "") or 0
  local sx = 160 - subW
  if sx < 0 then sx = 0 end
  Window.printPx(card.subtitleText or "", hx + sx, hy + 17, { colors = titleColors })
  if (tonumber(card.idNumber) or 0) ~= 0 then
    Window.printPx(tostring(card.idNumber), hx + 166, hy + 17, { colors = titleColors })
  end

  local bx, by = CARD_BODY.left * T, CARD_BODY.top * T
  for i = 1, 4 do
    Window.printPx((card.bodyText or {})[i] or "", bx, by + LINE_PITCH * (i - 1) + 2, { colors = bodyColors })
  end

  local fx, fy = CARD_FOOTER.left * T, CARD_FOOTER.top * T
  local off = FOOTER_OFFSET[tonumber(card.type) or 0] or 7
  Window.printPx(card.footerLine1Text or "", fx, fy + off, { colors = footerColors })
  -- pokefirered/src/mystery_gift_show_card.c:330
  if (tonumber(card.type) or 0) == MysteryGift.CARD_TYPE_GIFT then
    Window.printPx(card.footerLine2Text or "", fx, fy + off + 16, { colors = footerColors })
  elseif (tonumber(card.type) or 0) == MysteryGift.CARD_TYPE_LINK_STAT then
    local meta = MysteryGift.getSavedCardMetadata(session(st))
    local line = string.format("%03d - %03d - %03d",
      math.min(tonumber(meta.battlesWon) or 0, MysteryGift.MAX_WONDER_CARD_STAT),
      math.min(tonumber(meta.battlesLost) or 0, MysteryGift.MAX_WONDER_CARD_STAT),
      math.min(tonumber(meta.numTrades) or 0, MysteryGift.MAX_WONDER_CARD_STAT))
    Window.printPx(line, fx, fy + off + 16, { colors = footerColors })
  end

  local meta = MysteryGift.getSavedCardMetadata(session(st))
  drawMonIcon(tonumber(meta.iconSpecies), 220, 20)
  -- pokefirered/src/mystery_gift_show_card.c:460 CreateCardSprites
  local maxStamps = tonumber(card.maxStamps) or 0
  if maxStamps > 0 and (tonumber(card.type) or 0) == MysteryGift.CARD_TYPE_STAMP then
    local stamps = Ui.stamps()
    local shadow = Ui.stampShadow(card.bgType)
    local sw, sh = stamps.width, stamps.height
    local sy, iy = stamps.slot_y, stamps.icon_y
    for i = 1, math.min(maxStamps, MysteryGift.MAX_STAMP_CARD_STAMPS) do
      local x = stamps.slot_x[i]
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(shadow, x - sw / 2, sy - sh / 2)
      drawMonIcon(tonumber(meta.stampData.species[i]), x, iy)
    end
  end
end

-- pokefirered/src/mystery_gift_show_news.c:353 DrawNewsWindows
function Ui.drawNews(st)
  local news = Ui.news(st)
  if not news then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Ui.newsBackground(news.bgType), 0, 0)
  local tw = FrlgFont.measure(news.titleText or "") or 0
  local x = math.floor((224 - tw) / 2)
  if x < 0 then x = 0 end
  local key = "news_bg" .. (tonumber(news.bgType) or 0)
  Window.printPx(news.titleText or "", NEWS_TITLE.left * T + x, NEWS_TITLE.top * T + 6,
    { colors = Ui.textColors(key, "titleTextPal") })
  local bodyColors = Ui.textColors(key, "bodyTextPal")
  local by = NEWS_BODY.top * T
  for i = 1, NEWS_VISIBLE_LINES do
    local line = (news.bodyText or {})[i + st.newsScroll] or ""
    Window.printPx(line, NEWS_BODY.left * T, by + LINE_PITCH * (i - 1) + 2, { colors = bodyColors })
  end
end

function Ui.draw(st)
  local S = Ui.STATE
  if st.state == S.GIFT_INPUT or st.state == S.GIFT_SELECT
    or st.state == S.ASK_TOSS or st.state == S.ASK_TOSS_UNRECEIVED
    or st.state == S.NO_LINK then
    if st.isNews then Ui.drawNews(st) else Ui.drawCard(st) end
  else
    drawMenuBg()
    drawTopBar(st)
  end

  if st.state == S.MAIN_MENU then
    drawList(st, Ui.threeOptionTemplate(st.rows))
  elseif st.state == S.SOURCE_INPUT then
    drawList(st, Ui.threeOptionTemplate(st.rows))
  elseif st.state == S.OFFER_LIST and st.list then
    st.list:draw()
  elseif st.state == S.GIFT_SELECT then
    drawList(st, (#(st.rows or {}) > 3) and GIFT3_WIN or GIFT2_WIN)
  end

  if st.yesno then
    drawYesNo(st)
  elseif st.msg then
    drawMessage(st.msg.text, math.min(st.msg.revealed, st.msg.total))
  elseif st.prompt then
    drawMessage(st.prompt, nil)
  end
  if WirelessIcon._forced then WirelessIcon.draw(WirelessIcon.X, WirelessIcon.Y) end
  love.graphics.setColor(1, 1, 1, 1)
end

return Ui

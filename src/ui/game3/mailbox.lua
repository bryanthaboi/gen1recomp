-- pokefirered/src/player_pc.c:227 Task_PlayerPcMailbox

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local Mail = require("src.core.game3.mail")

local Mailbox = { isMenu = true }

Mailbox.open = false

-- pokefirered/src/mailbox_pc.c:16 sWindowTemplates
local WIN = {
  title = Window.template(1, 1, 10, 2),
  list = Window.template(19, 1, 10, 18),
  options = Window.template(1, 1, 15, 8),
}
Mailbox.WIN = WIN
-- pokefirered/src/new_menu_helpers.c:48 sYesNo_WindowTemplate
local YES_NO = Window.template(21, 9, 6, 4)
-- pokefirered/src/mailbox_pc.c:113
local MAX_SHOWED, UP_TEXT_Y, ROW_H, ITEM_X = 8, 10, 16, 8
-- pokefirered/src/player_pc.c:532
local MENU_TOP, MENU_ROW_H = 2, 16
-- pokefirered/src/mailbox_pc.c:134
local ARROW_X, ARROW_UP_Y, ARROW_DOWN_Y = 0xC2, 0x0C, 0x94
-- pokefirered/src/mailbox_pc.c:88
local JAPANESE_NAME_MAX = 5

-- pokefirered/src/palette.c:162
local FADE_STEP = 2

local function begin_fade(dir, done)
  Mailbox._fade = dir > 0 and 0 or 16
  Mailbox._fadeDir, Mailbox._fadeDone = dir, done
end

function Mailbox.update()
  local dir = Mailbox._fadeDir or 0
  if not Mailbox.open or dir == 0 then return end
  Mailbox._fade = Mailbox._fade + dir * FADE_STEP
  if (dir > 0 and Mailbox._fade < 16) or (dir < 0 and Mailbox._fade > 0) then return end
  Mailbox._fade, Mailbox._fadeDir = dir > 0 and 16 or 0, 0
  local cb = Mailbox._fadeDone
  Mailbox._fadeDone = nil
  if cb then cb() end
end

local function se(name)
  local SE = require("src.core.game3.se_ids")
  pcall(function() require("src.core.game3.audio").playSe(SE[name]) end)
end

local function pool()
  return Mail.pool(Mailbox._session)
end

-- pokefirered/src/player_pc.c:435 PCMailCompaction
local function compact()
  local p = pool()
  for i = Mail.PARTY_SIZE + 1, Mail.MAIL_COUNT - 1 do
    for j = i + 1, Mail.MAIL_COUNT do
      if Mail.isEmpty(p[i]) then p[i], p[j] = p[j], p[i] end
    end
  end
end
Mailbox.compact = compact

-- pokefirered/src/player_pc.c:422 CountPCMail
function Mailbox.countFor(session)
  local p, n = Mail.pool(session), 0
  for i = Mail.PARTY_SIZE + 1, Mail.MAIL_COUNT do
    if not Mail.isEmpty(p[i]) then n = n + 1 end
  end
  return n
end

local function count()
  return Mailbox.countFor(Mailbox._session)
end
Mailbox.count = count

-- pokefirered/src/player_pc.c:409 Task_SetPageItemVars
local function page_items()
  local n = count()
  return n >= MAX_SHOWED and MAX_SHOWED or n + 1
end

local function pos()
  return Mailbox.scroll + Mailbox.row
end

-- pokefirered/src/player_pc.c:40 SELECTED_MAIL
local function selected_mail()
  return pool()[Mail.PARTY_SIZE + pos() + 1]
end
Mailbox.selectedMail = selected_mail

-- pokefirered/src/player_pc.c:681
local function clamp()
  local total, shown = count() + 1, page_items()
  if Mailbox.scroll ~= 0 and Mailbox.scroll + shown > total then Mailbox.scroll = total - shown end
  if Mailbox.scroll < 0 then Mailbox.scroll = 0 end
  if Mailbox.scroll + Mailbox.row >= total then Mailbox.row = total - 1 - Mailbox.scroll end
  if Mailbox.row < 0 then Mailbox.row = 0 end
end

-- pokefirered/src/mailbox_pc.c:82 ItemPrintFunc
function Mailbox.senderName(mail)
  local name = tostring(mail and mail.playerName or "")
  local n = 0
  for _ in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
  if n <= JAPANESE_NAME_MAX then return require("src.ui.game3.mail").japaneseName(name) end
  return name
end

local function status(key, vars)
  Mailbox._status = key and RomText.plain(key, { stringVars = vars }) or nil
end

function Mailbox.show(opts)
  opts = opts or {}
  Mailbox.open = true
  Mailbox._session = opts.session
  Mailbox._onClose = opts.onClose
  -- pokefirered/src/player_pc.c:237
  Mailbox.scroll, Mailbox.row = 0, 0
  Mailbox.state = "list"
  Mailbox.optCursor = 1
  Mailbox.yesCursor = 1
  Mailbox._fade, Mailbox._fadeDir, Mailbox._fadeDone = 0, 0, nil
  compact()
  clamp()
  status(nil)
  Stack.push("mailbox", Mailbox, { hideBelow = false })
end

function Mailbox.isOpen()
  return Mailbox.open
end

function Mailbox.close()
  if not Mailbox.open then return end
  Mailbox.open = false
  Stack.pop("mailbox")
  local cb = Mailbox._onClose
  Mailbox._onClose = nil
  if cb then cb() end
end

function Mailbox.reset()
  Mailbox.open = false
  Mailbox._onClose = nil
  Stack.pop("mailbox")
end

-- pokefirered/src/list_menu.c:438 ListMenuUpdateSelectedRowIndexAndScrollOffset
local function step(down)
  local n, shown = count() + 1, page_items()
  local row, scroll = Mailbox.row, Mailbox.scroll
  if not down then
    local newRow = shown == 1 and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      Mailbox.row = row - 1
    elseif row > newRow then
      Mailbox.row = row - 1
    else
      Mailbox.row, Mailbox.scroll = newRow, scroll - 1
    end
  else
    local newRow = shown == 1 and 0 or (math.floor(shown / 2) + shown % 2)
    if scroll == n - shown then
      if row >= shown - 1 then return false end
      Mailbox.row = row + 1
    elseif row < newRow then
      Mailbox.row = row + 1
    else
      Mailbox.row, Mailbox.scroll = newRow, scroll + 1
    end
  end
  return true
end

-- pokefirered/src/player_pc.c:729 Task_PlayerPcExitMailSubmenu
local function back_to_list()
  Mailbox.state = "list"
  status(nil)
  clamp()
end

local function message(key, vars)
  status(key, vars)
  Mailbox.state = "message"
end

-- pokefirered/src/player_pc.c:556 Task_PlayerPcReadMail
local function read_mail()
  local mail = selected_mail()
  -- pokefirered/src/player_pc.c:562 Task_WaitFadeAndReadSelectedMail
  begin_fade(1, function()
    Mailbox.state = "reading"
    status(nil)
    require("src.ui.game3.mail").read(mail, {
      session = Mailbox._session,
      -- pokefirered/src/player_pc.c:579 CB2_ReturnToMailbox
      onClose = function()
        back_to_list()
        begin_fade(-1)
      end,
    })
  end)
end

-- pokefirered/src/player_pc.c:630 Task_TryPutMailInBag_DestroyMsgIfSuccessful
local function move_to_bag()
  local mail = selected_mail()
  local Bag = require("src.core.game3.bag")
  local bag = assert(Mailbox._session and Mailbox._session.bag, "mailbox: session has no bag")
  if not Bag.add(bag, mail.itemId, 1) then
    return message("gText_BagIsFull")
  end
  Mail.clear(mail)
  compact()
  clamp()
  message("gText_MailReturnedToBagMessageErased")
end

-- pokefirered/src/party_menu.c:5630 TryGiveMailToSelectedMon
local function give_to(PartyMenu, mon)
  local held = tonumber(mon and (mon.item or mon.heldItem)) or 0
  if held ~= 0 then
    return PartyMenu.showMessage(RomText.box("gText_PkmnHoldingItemCantHoldMail"), function() PartyMenu.close() end)
  end
  local mail = selected_mail()
  Mail.giveMailToMon2(Mailbox._session, mon, Mail.copy(mail))
  Mail.clear(mail)
  PartyMenu.showMessage(RomText.box("gText_MailTransferredFromMailbox"), function() PartyMenu.close() end)
end

-- pokefirered/src/player_pc.c:657 Task_PlayerPcGiveMailToMon
local function give()
  local party = Mailbox._session and Mailbox._session.party or {}
  if #party == 0 then
    -- pokefirered/src/player_pc.c:716 Task_Error_NoPokemon
    return message("gText_ThereIsNoPokemon")
  end
  -- pokefirered/src/player_pc.c:670 Task_WaitFadeAndGoToPartyMenu
  begin_fade(1, function()
    Mailbox.state = "party"
    status(nil)
    local PartyMenu = require("src.ui.game3.party_menu")
    -- pokefirered/src/party_menu.c:5625 ChooseMonToGiveMailFromMailbox
    PartyMenu.show(party, nil, {
      session = Mailbox._session,
      mode = "choose",
      promptMode = "give",
      eggFails = true,
      fadeIn = true,
      onChoose = function(_, mon) give_to(PartyMenu, mon) end,
      -- pokefirered/src/player_pc.c:681 CB2_ReturnToMailboxPc_UpdateScrollVariables
      onClose = function()
        compact()
        back_to_list()
        begin_fade(-1)
      end,
    })
  end)
end

local OPTIONS = {
  read_mail,
  -- pokefirered/src/player_pc.c:601 Task_PlayerPcMoveMailToBag
  function()
    status("gText_MessageWillBeLost")
    Mailbox.yesCursor = 1
    Mailbox.state = "confirm"
  end,
  give,
  back_to_list,
}

-- pokefirered/src/player_pc.c:105 sMenuActions_MailSubmenu
local OPTION_KEYS = { "gOtherText_Read", "gOtherText_MoveToBag", "gOtherText_Give2", "gOtherText_Exit" }

function Mailbox.handleInput(input)
  if not Mailbox.open or not input or (Mailbox._fadeDir or 0) ~= 0 then return end
  local st = Mailbox.state
  if st == "list" then
    -- pokefirered/src/player_pc.c:464 Task_MailboxPcHandleInput
    if input:wasPressed("up") then
      if step(false) then se("SE_SELECT") end
    elseif input:wasPressed("down") then
      if step(true) then se("SE_SELECT") end
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      if pos() >= count() then
        Mailbox.close()
      else
        -- pokefirered/src/player_pc.c:494 Task_PrintWhatToDoWithSelectedMail
        status("gText_WhatWouldYouLikeToDoWithPlayersMail", { Mailbox.senderName(selected_mail()) })
        Mailbox.optCursor = 1
        Mailbox.state = "options"
      end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      Mailbox.close()
    end
  elseif st == "options" then
    -- pokefirered/src/player_pc.c:538 Task_MailSubmenuHandleInput
    if input:wasPressed("up") then
      Mailbox.optCursor = Mailbox.optCursor == 1 and #OPTIONS or Mailbox.optCursor - 1
      se("SE_SELECT")
    elseif input:wasPressed("down") then
      Mailbox.optCursor = Mailbox.optCursor == #OPTIONS and 1 or Mailbox.optCursor + 1
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      OPTIONS[Mailbox.optCursor]()
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      back_to_list()
    end
  elseif st == "confirm" then
    -- pokefirered/src/player_pc.c:612 Task_MoveToBagYesNoMenuHandleInput
    if input:wasPressed("up") and Mailbox.yesCursor ~= 1 then
      Mailbox.yesCursor = 1
      se("SE_SELECT")
    elseif input:wasPressed("down") and Mailbox.yesCursor ~= 2 then
      Mailbox.yesCursor = 2
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      if Mailbox.yesCursor == 1 then move_to_bag() else back_to_list() end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      back_to_list()
    end
  elseif st == "message" then
    if input:wasPressed("a") or input:wasPressed("b") then
      back_to_list()
    end
  end
end

local function draw_status()
  if not Mailbox._status then return end
  Window.dialogueFrame()
  local lines = {}
  for line in Mailbox._status:gmatch("[^\n]+") do lines[#lines + 1] = line end
  if lines[1] then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
  if lines[2] then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
end

-- pokefirered/src/player_pc.c:453 Task_DrawMailboxPcMenu
local function draw_list()
  local t = WIN.title
  Window.stdFrame(t)
  local title = RomText.plain("gText_Mailbox")
  Window.printPx(title, t.left * 8 + math.floor((80 - FrlgFont.measure(title)) / 2), t.top * 8 + 2)
  local l = WIN.list
  Window.stdFrame(l)
  local ox, oy = l.left * 8, l.top * 8
  local shown = page_items()
  local p = pool()
  for i = 0, shown - 1 do
    local idx = Mailbox.scroll + i
    local y = oy + UP_TEXT_Y + i * ROW_H
    if idx >= count() then
      -- pokefirered/src/mailbox_pc.c:102
      Window.printPx(RomText.plain("gFameCheckerText_Cancel"), ox + ITEM_X, y)
    else
      Window.printPx(Mailbox.senderName(p[Mail.PARTY_SIZE + idx + 1]), ox + ITEM_X, y)
    end
  end
  Window.cursorPx(ox, oy + UP_TEXT_Y + Mailbox.row * ROW_H)
  local total = count() + 1
  if total > shown then
    local BagChrome = require("src.ui.game3.bag_chrome")
    if Mailbox.scroll > 0 then BagChrome.drawArrow("up", ARROW_X - 8, ARROW_UP_Y - 8) end
    if Mailbox.scroll < total - shown then BagChrome.drawArrow("down", ARROW_X - 8, ARROW_DOWN_Y - 8) end
  end
end

local function draw_fade()
  local f = Mailbox._fade or 0
  if f <= 0 then return end
  love.graphics.setColor(0, 0, 0, f / 16)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_menu()
  local st = Mailbox.state
  if st == "list" then return draw_list() end
  local o = WIN.options
  Window.stdFrame(o)
  for i, key in ipairs(OPTION_KEYS) do
    local y = o.top * 8 + MENU_TOP + (i - 1) * MENU_ROW_H
    Window.printPx(RomText.plain(key), o.left * 8 + 8, y)
    if st == "options" and i == Mailbox.optCursor then Window.cursorPx(o.left * 8, y) end
  end
  if st == "confirm" then
    Window.stdFrame(YES_NO)
    Window.printPx(RomText.plain("gText_Yes"), YES_NO.left * 8 + 8, YES_NO.top * 8 + 2)
    Window.printPx(RomText.plain("gText_No"), YES_NO.left * 8 + 8, YES_NO.top * 8 + 2 + MENU_ROW_H)
    Window.cursorPx(YES_NO.left * 8, YES_NO.top * 8 + 2 + (Mailbox.yesCursor - 1) * MENU_ROW_H)
  end
  draw_status()
end

function Mailbox.draw()
  if not Mailbox.open then return end
  local st = Mailbox.state
  if st == "reading" or st == "party" then return end
  draw_menu()
  draw_fade()
end

return Mailbox

-- FRLG Easy Chat / Profile word-selection modal (pret easy_chat_2.c & easy_chat_3.c).
-- 1:1 Authentic UI matching FireRed/LeafGreen graphics, palettes, and layout.

local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local Stack = require("src.ui.game3.stack")
local Audio = require("src.core.game3.audio")
local EasyChatData = require("src.core.game3.easy_chat_data")
local EasyChatText = require("src.core.game3.easy_chat_text")
local Chrome = require("src.ui.game3.chrome")
local Strings = require("src.core.Strings")

local EasyChat = {}

EasyChat.openFlag = false
EasyChat._state = nil

-- Positions matching pret sPhraseFrameDimensions[0]
local SLOTS_LAYOUT = {
  { x = 36, y = 34, w = 84, h = 16 },
  { x = 126, y = 34, w = 84, h = 16 },
  { x = 36, y = 52, w = 84, h = 16 },
  { x = 126, y = 52, w = 84, h = 16 },
}

-- The cart's own words fit the boxes they are drawn in -- the widest is
-- 72 px -- a translated one need not, so every word is clipped to its box.
-- In the picker that box is the red selection rectangle, which starts 12 px
-- left of the pen and is 92 px wide.  In the phrase frame it is the slot's
-- own frame (SLOTS_LAYOUT), which also keeps a left word clear of the right
-- slot's cursor.  Group names get the room up to the scroll arrows (centred
-- at +112, 8 px wide) instead: an official translation already needs it --
-- the French cart's VIE QUOTIDIEN. is 83 px.
local CELL_WIDTH = 80
local GROUP_CELL_WIDTH = 88

local function slotWidth(index, penX)
  local frame = SLOTS_LAYOUT[index]
  return frame.x + frame.w - penX
end

-- Strings.source, not Strings: this table is built at require time, before a
-- catalog is loaded, so the draw below looks each label up at use time.
local FOOTER_BTNS = {
  { id = "DEL_ALL", label = Strings.source("DEL. ALL"), textX = 32, cursorX = 22, y = 88 },
  { id = "CANCEL", label = Strings.source("CANCEL"), textX = 119, cursorX = 109, y = 88 },
  { id = "OK", label = Strings.source("OK"), textX = 195, cursorX = 185, y = 88 },
}
EasyChat.FOOTER_BTNS = FOOTER_BTNS

local function play_se(id)
  local ok, Aud = pcall(require, "src.core.game3.audio")
  if ok and Aud and Aud.playSE then
    Aud.playSE(id)
  end
end

function EasyChat.open(opts)
  opts = opts or {}
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.clear then
    Fade.clear()
  end

  local initialWords = {}
  local srcWords = opts.words or EasyChatData.DEFAULT_PROFILE
  for i = 1, 4 do
    initialWords[i] = tonumber(srcWords[i]) or EasyChatData.DEFAULT_PROFILE[i] or EasyChatData.EC_WORD_UNDEFINED
  end

  local groupList = {}
  for gid = 0, 21 do
    local g = EasyChatData.GROUPS[gid]
    if g and g.words and #g.words > 0 then
      table.insert(groupList, g)
    end
  end

  local title = Strings("PROFILE")
  local instr1 = Strings("Combine four words or phrases")
  local instr2 = Strings("and make your profile.")
  local confirm1 = Strings("Your profile")
  local confirm2 = Strings("is as shown. Okay?")

  if opts.type == 14 then -- QUESTIONNAIRE
    title = Strings("QUESTIONNAIRE")
    instr1 = Strings("Combine four words or phrases")
    instr2 = Strings("and fill out the questionnaire.")
    confirm1 = Strings("The answer")
    confirm2 = Strings("is as shown. Okay?")
  elseif opts.type == 1 then -- BATTLE START
    title = Strings("At the battle's start:")
    instr1 = Strings("Make a message of six phrases.")
    instr2 = Strings("Max two 12-letter phrases/line.")
    confirm1 = Strings("Your feeling at the battle's start")
    confirm2 = Strings("is as shown. Okay?")
  end

  local st = {
    type = opts.type or 0,
    title = title,
    instr1 = instr1,
    instr2 = instr2,
    confirm1 = confirm1,
    confirm2 = confirm2,
    words = initialWords,
    origWords = { initialWords[1], initialWords[2], initialWords[3], initialWords[4] },
    selectedSlot = 1,
    mode = "SLOT", -- "SLOT", "FOOTER", "GROUP", "WORD", "CONFIRM", "CANCEL_CONFIRM", "DEL_ALL_CONFIRM"
    footerIdx = 3, -- 1 = DEL ALL, 2 = CANCEL, 3 = OK
    groups = groupList,
    groupCursor = 1,
    groupScroll = 0,
    wordCursor = 1,
    wordPage = 0,
    confirmChoice = 1, -- 1 = YES, 2 = NO
    animTimer = 0,
    onDone = opts.onDone,
    session = opts.session,
  }

  EasyChat._state = st
  EasyChat.openFlag = true
  Stack.push("easy_chat", EasyChat, { hideBelow = true })
  return st
end

function EasyChat.isOpen()
  return EasyChat.openFlag
end

function EasyChat.close(confirmed, words)
  local st = EasyChat._state
  local cb = st and st.onDone
  EasyChat.openFlag = false
  EasyChat._state = nil
  Stack.pop("easy_chat")
  if cb then
    cb(confirmed, words)
  end
end

function EasyChat.update(dt)
  if not EasyChat.openFlag or not EasyChat._state then return end
  EasyChat._state.animTimer = (EasyChat._state.animTimer or 0) + (dt or (1 / 60))
end

function EasyChat.handleInput(inp)
  if not EasyChat.openFlag or not inp then return end
  local st = EasyChat._state
  if not st then return end

  -- Confirmation Popups (CONFIRM, CANCEL_CONFIRM, DEL_ALL_CONFIRM)
  if st.mode == "CONFIRM" or st.mode == "CANCEL_CONFIRM" or st.mode == "DEL_ALL_CONFIRM" then
    if inp:wasPressed("up") or inp:wasPressed("down") then
      st.confirmChoice = (st.confirmChoice == 1) and 2 or 1
      play_se(5) -- SE_SELECT
    elseif inp:wasPressed("a") then
      play_se(5)
      if st.mode == "CONFIRM" then
        if st.confirmChoice == 1 then
          EasyChat.close(true, st.words)
        else
          st.mode = "SLOT"
        end
      elseif st.mode == "CANCEL_CONFIRM" then
        if st.confirmChoice == 1 then
          EasyChat.close(false, st.origWords)
        else
          st.mode = "SLOT"
        end
      elseif st.mode == "DEL_ALL_CONFIRM" then
        if st.confirmChoice == 1 then
          for i = 1, 4 do st.words[i] = EasyChatData.EC_WORD_UNDEFINED end
        end
        st.mode = "SLOT"
      end
    elseif inp:wasPressed("b") then
      play_se(5)
      st.mode = "SLOT"
    end
    return
  end

  -- Global shortcut: START opens OK confirmation
  if inp:wasPressed("start") then
    play_se(5)
    st.confirmChoice = 1
    st.mode = "CONFIRM"
    return
  end

  -- Slot Navigation
  if st.mode == "SLOT" then
    if inp:wasPressed("left") then
      if st.selectedSlot % 2 == 0 then
        st.selectedSlot = st.selectedSlot - 1
        play_se(5)
      end
    elseif inp:wasPressed("right") then
      if st.selectedSlot % 2 == 1 then
        st.selectedSlot = st.selectedSlot + 1
        play_se(5)
      end
    elseif inp:wasPressed("up") then
      if st.selectedSlot > 2 then
        st.selectedSlot = st.selectedSlot - 2
        play_se(5)
      end
    elseif inp:wasPressed("down") then
      if st.selectedSlot <= 2 then
        st.selectedSlot = st.selectedSlot + 2
        play_se(5)
      else
        st.mode = "FOOTER"
        st.footerIdx = (st.selectedSlot == 3) and 1 or 3
        play_se(5)
      end
    elseif inp:wasPressed("a") then
      play_se(5)
      st.mode = "GROUP"
    elseif inp:wasPressed("b") then
      play_se(5)
      st.confirmChoice = 2
      st.mode = "CANCEL_CONFIRM"
    end

  -- Footer Navigation (DEL. ALL, CANCEL, OK)
  elseif st.mode == "FOOTER" then
    if inp:wasPressed("left") then
      if st.footerIdx > 1 then
        st.footerIdx = st.footerIdx - 1
        play_se(5)
      end
    elseif inp:wasPressed("right") then
      if st.footerIdx < 3 then
        st.footerIdx = st.footerIdx + 1
        play_se(5)
      end
    elseif inp:wasPressed("up") then
      st.mode = "SLOT"
      st.selectedSlot = (st.footerIdx <= 1) and 3 or 4
      play_se(5)
    elseif inp:wasPressed("a") then
      play_se(5)
      if st.footerIdx == 1 then -- DEL. ALL
        st.confirmChoice = 2
        st.mode = "DEL_ALL_CONFIRM"
      elseif st.footerIdx == 2 then -- CANCEL
        st.confirmChoice = 2
        st.mode = "CANCEL_CONFIRM"
      elseif st.footerIdx == 3 then -- OK
        st.confirmChoice = 1
        st.mode = "CONFIRM"
      end
    elseif inp:wasPressed("b") then
      play_se(5)
      st.mode = "SLOT"
    end

  -- Group Selection Mode
  elseif st.mode == "GROUP" then
    local numG = #st.groups
    local curIndex = st.groupCursor
    local row = math.floor((curIndex - 1) / 2)
    local col = (curIndex - 1) % 2
    local totalRows = math.ceil(numG / 2)

    if inp:wasPressed("up") then
      if row > 0 then
        row = row - 1
        st.groupCursor = math.min(numG, row * 2 + col + 1)
        play_se(5)
      end
    elseif inp:wasPressed("down") then
      if row < totalRows - 1 then
        row = row + 1
        st.groupCursor = math.min(numG, row * 2 + col + 1)
        play_se(5)
      end
    elseif inp:wasPressed("left") then
      if col > 0 then
        st.groupCursor = st.groupCursor - 1
        play_se(5)
      end
    elseif inp:wasPressed("right") then
      if col < 1 and (st.groupCursor + 1) <= numG then
        st.groupCursor = st.groupCursor + 1
        play_se(5)
      end
    elseif inp:wasPressed("a") then
      play_se(5)
      st.mode = "WORD"
      st.wordCursor = 1
      st.wordPage = 0
    elseif inp:wasPressed("b") then
      play_se(5)
      st.mode = "SLOT"
    end

  -- Word Selection Mode
  elseif st.mode == "WORD" then
    local curGroup = st.groups[st.groupCursor]
    local wordsList = (curGroup and curGroup.words) or {}
    local totalWords = #wordsList
    local pageSize = 8
    local maxPages = math.max(1, math.ceil(totalWords / pageSize))
    local pageOffset = st.wordPage * pageSize
    local curIndexOnPage = st.wordCursor -- 1..8
    local row = math.floor((curIndexOnPage - 1) / 2)
    local col = (curIndexOnPage - 1) % 2

    if inp:wasPressed("up") then
      if row > 0 then
        row = row - 1
        st.wordCursor = row * 2 + col + 1
        play_se(5)
      elseif st.wordPage > 0 then
        st.wordPage = st.wordPage - 1
        st.wordCursor = 3 * 2 + col + 1
        play_se(5)
      end
    elseif inp:wasPressed("down") then
      if row < 3 and (pageOffset + (row + 1) * 2 + col + 1) <= totalWords then
        row = row + 1
        st.wordCursor = row * 2 + col + 1
        play_se(5)
      elseif st.wordPage < maxPages - 1 then
        st.wordPage = st.wordPage + 1
        st.wordCursor = col + 1
        play_se(5)
      end
    elseif inp:wasPressed("left") then
      if col > 0 then
        st.wordCursor = st.wordCursor - 1
        play_se(5)
      elseif st.wordPage > 0 then
        st.wordPage = st.wordPage - 1
        st.wordCursor = 1
        play_se(5)
      end
    elseif inp:wasPressed("right") then
      if col < 1 and (pageOffset + curIndexOnPage + 1) <= totalWords then
        st.wordCursor = st.wordCursor + 1
        play_se(5)
      elseif st.wordPage < maxPages - 1 then
        st.wordPage = st.wordPage + 1
        st.wordCursor = 1
        play_se(5)
      end
    elseif inp:wasPressed("select") then
      -- Page down shortcut
      if st.wordPage < maxPages - 1 then
        st.wordPage = st.wordPage + 1
        st.wordCursor = 1
        play_se(5)
      end
    elseif inp:wasPressed("a") then
      local chosenIdx = pageOffset + st.wordCursor
      local wEntry = wordsList[chosenIdx]
      if wEntry then
        st.words[st.selectedSlot] = wEntry.id
        play_se(5)
        -- Advance slot to next
        st.selectedSlot = (st.selectedSlot % 4) + 1
        st.mode = "SLOT"
      end
    elseif inp:wasPressed("b") then
      play_se(5)
      st.mode = "GROUP"
    end
  end
end

--- Draw framed box with authentic FRLG orange/gold rounded border (text_input_frame_orange.pal).
local function drawOrangeFrame(x, y, w, h)
  -- Outer shadow (dark orange 205, 98, 0)
  love.graphics.setColor(205 / 255, 98 / 255, 0 / 255, 1)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3, 3)
  -- Main border (medium orange 255, 139, 57)
  love.graphics.setColor(255 / 255, 139 / 255, 57 / 255, 1)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2, 2, 2)
  -- Inner highlight (light orange 255, 189, 115)
  love.graphics.setColor(255 / 255, 189 / 255, 115 / 255, 1)
  love.graphics.rectangle("line", x, y, w, h)
  -- Interior fill (pure white)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
end

--- Draw standard FRLG white dialog window frame (menu / text window border).
local function drawDialogFrame(x, y, w, h)
  -- Outer drop shadow
  love.graphics.setColor(64 / 255, 72 / 255, 80 / 255, 0.4)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3, 3)
  -- Outer border
  love.graphics.setColor(96 / 255, 112 / 255, 128 / 255, 1)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 2, 2)
  -- Inner light border
  love.graphics.setColor(192 / 255, 208 / 255, 224 / 255, 1)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2, 1, 1)
  -- Interior fill (pure white)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- Draw authentic FireRed 8x8 red triangle cursor (sSpriteTemplate_TriangleCursor) with bounce animation.
local function drawTriangleCursor(x, y, timer)
  local bounce = 0
  if timer then
    bounce = math.floor((timer * 6) % 4)
    if bounce == 3 then bounce = 1 end
  end
  local cx = x + bounce
  local cy = y
  -- Outer border
  love.graphics.setColor(128 / 255, 0, 0, 1)
  love.graphics.polygon("fill", {
    cx - 1, cy - 1,
    cx + 7, cy + 3,
    cx - 1, cy + 7,
  })
  -- Red fill
  love.graphics.setColor(230 / 255, 8 / 255, 8 / 255, 1)
  love.graphics.polygon("fill", {
    cx, cy,
    cx + 6, cy + 3,
    cx, cy + 6,
  })
  -- Light red/orange highlight
  love.graphics.setColor(255 / 255, 189 / 255, 115 / 255, 1)
  love.graphics.line(cx, cy, cx + 5, cy + 3)
end

--- Draw authentic scroll indicators (sSpriteTemplate_ScrollIndicator).
local function drawScrollArrow(cx, cy, isUp)
  love.graphics.setColor(230 / 255, 8 / 255, 8 / 255, 1)
  if isUp then
    love.graphics.polygon("fill", {
      cx, cy - 3,
      cx + 4, cy + 3,
      cx - 4, cy + 3,
    })
  else
    love.graphics.polygon("fill", {
      cx - 4, cy - 3,
      cx + 4, cy - 3,
      cx, cy + 3,
    })
  end
end

function EasyChat.draw()
  if not EasyChat.openFlag then return end
  local st = EasyChat._state
  if not st then return end

  -- 1. Main Background (Authentic Light Teal / Soft Sea Green #73C5A4 from text_input_frame_orange.pal)
  love.graphics.setColor(115 / 255, 197 / 255, 164 / 255, 1)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)

  -- Subtle background grid pattern
  love.graphics.setColor(98 / 255, 180 / 255, 148 / 255, 0.4)
  for gx = 0, Display.W, 16 do
    love.graphics.line(gx, 0, gx, Display.H)
  end
  for gy = 0, Display.H, 16 do
    love.graphics.line(0, gy, Display.W, gy)
  end

  -- 2. Top Header Ribbon (Centered blue header box: tilemapLeft=7, top=0, width=16, height=2 -> x=56, y=2, w=128, h=16)
  local headerW, headerH = 128, 16
  local headerX = 56
  local headerY = 2
  -- Outer shadow & border
  love.graphics.setColor(24 / 255, 61 / 255, 130 / 255, 1)
  love.graphics.rectangle("fill", headerX - 1, headerY, headerW + 2, headerH, 3, 3)
  -- Blue fill
  love.graphics.setColor(57 / 255, 138 / 255, 230 / 255, 1)
  love.graphics.rectangle("fill", headerX, headerY + 1, headerW, headerH - 2, 2, 2)

  -- Title Text centered in header with title_text.pal colors (cyan 57, 205, 255 with purple-white 172, 172, 238)
  -- Centred like the cart, but never started left of the ribbon: the longest
  -- English title fills 118 of the header's 128 px, so a longer translation
  -- would otherwise spill out of the blue fill on both sides.
  local titleW = FrlgFont.measure(st.title)
  local titleX = headerX + math.max(0, math.floor((headerW - titleW) / 2))
  FrlgFont.draw(st.title, titleX, headerY + 2, {
    colors = { fg = { 1, 1, 1, 1 }, shadow = { 24 / 255, 61 / 255, 130 / 255, 1 }, bg = { 0, 0, 0, 0 } },
  })

  -- 3. Top Phrase Frame Box (pret sPhraseFrameDimensions[0]: tile x=2, y=3, w=26, h=6 -> pixel x=16, y=24, w=208, h=48)
  local pX, pY, pW, pH = 16, 24, 208, 48
  drawOrangeFrame(pX, pY, pW, pH)

  -- Draw the 4 slots inside the phrase frame (pret easy_chat_3.c: PrintECFields & ECInterfaceCmd_02)
  -- Column 0: x = 41 (cursor at 31)
  -- Column 1: x = 136 (cursor at 126)
  -- Row 0: y = 34 (cursor at 37)
  -- Row 1: y = 50 (cursor at 53)
  local slotPositions = {
    { x = 41, y = 34, cursorX = 31, cursorY = 37 },
    { x = 136, y = 34, cursorX = 126, cursorY = 37 },
    { x = 41, y = 50, cursorX = 31, cursorY = 53 },
    { x = 136, y = 50, cursorX = 126, cursorY = 53 },
  }

  for i = 1, 4 do
    local s = slotPositions[i]
    local wid = st.words[i]
    local isSelected = (st.mode == "SLOT" and st.selectedSlot == i)

    -- Slot cursor (red bouncing triangle)
    if isSelected then
      drawTriangleCursor(s.cursorX, s.cursorY, st.animTimer)
    end

    if not wid or wid == EasyChatData.EC_WORD_UNDEFINED or wid == 0xFFFF then
      -- 7 Red underscores matching pret CHAR_EXTRA_SYMBOL + CHAR_UNDERSCORE (7 glyphs in FONT_NORMAL_COPY_1)
      FrlgFont.draw("_______", s.x, s.y, { colors = FrlgFont.COLOR.RED })
    else
      local wText = EasyChatText.word(wid)
      if wText and wText ~= "" then
        FrlgFont.draw(wText, s.x, s.y, { maxWidth = slotWidth(i, s.x), colors = FrlgFont.COLOR.NORMAL })
      else
        FrlgFont.draw("_______", s.x, s.y, { colors = FrlgFont.COLOR.RED })
      end
    end
  end

  -- 4. Middle Action Footer (DEL. ALL at x=32, CANCEL at x=119, OK at x=196 at y=88, cursor at y=91)
  for i, btn in ipairs(FOOTER_BTNS) do
    local isCur = (st.mode == "FOOTER" and st.footerIdx == i)
    if isCur then
      drawTriangleCursor(btn.cursorX, 91, st.animTimer)
    end
    FrlgFont.draw(Strings(btn.label), btn.textX, 88, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- 5. Bottom Workspace or Instruction Box
  if st.mode == "SLOT" or st.mode == "FOOTER" or st.mode == "CONFIRM" or st.mode == "CANCEL_CONFIRM" or st.mode == "DEL_ALL_CONFIRM" then
    -- Instruction Dialog Frame (pret sEasyChatWindowTemplates[1] with border: x=8, y=106, w=224, h=46)
    local dX, dY, dW, dH = 8, 106, 224, 46
    drawDialogFrame(dX, dY, dW, dH)

    if st.mode == "CONFIRM" then
      FrlgFont.draw(st.confirm1, dX + 8, dY + 6, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(st.confirm2, dX + 8, dY + 22, { colors = FrlgFont.COLOR.NORMAL })
    elseif st.mode == "CANCEL_CONFIRM" then
      FrlgFont.draw(Strings("Quit editing?"), dX + 8, dY + 6, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(Strings("The edited words will not be saved."), dX + 8, dY + 22, { colors = FrlgFont.COLOR.NORMAL })
    elseif st.mode == "DEL_ALL_CONFIRM" then
      FrlgFont.draw(Strings("All the text being edited will"), dX + 8, dY + 6, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(Strings("be deleted. Is that okay?"), dX + 8, dY + 22, { colors = FrlgFont.COLOR.NORMAL })
    else
      -- Standard instructions
      FrlgFont.draw(st.instr1, dX + 8, dY + 6, { colors = FrlgFont.COLOR.NORMAL })
      FrlgFont.draw(st.instr2, dX + 8, dY + 22, { colors = FrlgFont.COLOR.NORMAL })
    end

    -- YES / NO Menu for confirm states (pret sEasyChatYesNoWindowTemplate: x=184, y=64, w=48, h=38)
    if st.mode == "CONFIRM" or st.mode == "CANCEL_CONFIRM" or st.mode == "DEL_ALL_CONFIRM" then
      local ynX, ynY, ynW, ynH = 184, 64, 48, 38
      drawDialogFrame(ynX, ynY, ynW, ynH)
      -- YES
      if st.confirmChoice == 1 then
        drawTriangleCursor(ynX + 4, ynY + 8, st.animTimer)
      end
      FrlgFont.draw(Strings("YES"), ynX + 16, ynY + 5, { colors = FrlgFont.COLOR.NORMAL })
      -- NO
      if st.confirmChoice == 2 then
        drawTriangleCursor(ynX + 4, ynY + 22, st.animTimer)
      end
      FrlgFont.draw(Strings("NO"), ynX + 16, ynY + 19, { colors = FrlgFont.COLOR.NORMAL })
    end

  -- Group Selection Sub-window (pret sEasyChatWindowTemplates[2]: x=8, y=76, w=224, h=78)
  elseif st.mode == "GROUP" then
    local gX, gY, gW, gH = 8, 76, 224, 78
    drawOrangeFrame(gX, gY, gW, gH)

    -- Top instruction in frame
    FrlgFont.draw(Strings("Select a group."), gX + 8, gY + 4, { colors = FrlgFont.COLOR.NORMAL })

    local numG = #st.groups
    local curRow = math.floor((st.groupCursor - 1) / 2)
    local startRow = math.max(0, curRow - 1)
    if startRow + 3 > math.ceil(numG / 2) then
      startRow = math.max(0, math.ceil(numG / 2) - 3)
    end

    -- Scroll indicators
    if startRow > 0 then
      drawScrollArrow(gX + 112, gY + 8, true)
    end
    if startRow + 3 < math.ceil(numG / 2) then
      drawScrollArrow(gX + 112, gY + gH - 8, false)
    end

    for r = 0, 2 do
      local rowIdx = startRow + r
      local yPos = gY + 18 + r * 16
      for c = 0, 1 do
        local gIdx = rowIdx * 2 + c + 1
        if gIdx <= numG then
          local grp = st.groups[gIdx]
          local xPos = (c == 0) and (gX + 18) or (gX + 120)
          local isCur = (st.groupCursor == gIdx)

          if isCur then
            -- Red selection rectangle outline around active group (pret rectangle_cursor)
            love.graphics.setColor(224 / 255, 32 / 255, 32 / 255, 1)
            love.graphics.rectangle("line", xPos - 12, yPos - 1, 92, 14, 2, 2)
            drawTriangleCursor(xPos - 10, yPos + 3, st.animTimer)
            FrlgFont.draw(EasyChatText.groupName(grp), xPos, yPos, { maxWidth = GROUP_CELL_WIDTH, colors = FrlgFont.COLOR.NORMAL })
          else
            FrlgFont.draw(EasyChatText.groupName(grp), xPos, yPos, { maxWidth = GROUP_CELL_WIDTH, colors = FrlgFont.COLOR.NORMAL })
          end
        end
      end
    end

  -- Word Selection Sub-window (pret sEasyChatWindowTemplates[2]: x=8, y=76, w=224, h=78)
  elseif st.mode == "WORD" then
    local wX, wY, wW, wH = 8, 76, 224, 78
    drawOrangeFrame(wX, wY, wW, wH)

    local curGroup = st.groups[st.groupCursor]
    local wordsList = (curGroup and curGroup.words) or {}
    local totalWords = #wordsList
    local pageSize = 8
    local maxPages = math.max(1, math.ceil(totalWords / pageSize))
    local pageOffset = st.wordPage * pageSize

    -- Top group title
    local grpHeader = EasyChatText.groupName(curGroup)
    FrlgFont.draw(grpHeader, wX + 8, wY + 4, { colors = FrlgFont.COLOR.NORMAL })

    -- Page indicator
    local pageStr = string.format("%d/%d", st.wordPage + 1, maxPages)
    FrlgFont.draw(pageStr, wX + wW - 32, wY + 4, { colors = FrlgFont.COLOR.NORMAL })

    -- Scroll indicators
    if st.wordPage > 0 then
      drawScrollArrow(wX + 112, wY + 8, true)
    end
    if st.wordPage < maxPages - 1 then
      drawScrollArrow(wX + 112, wY + wH - 8, false)
    end

    for r = 0, 2 do
      local yPos = wY + 18 + r * 16
      for c = 0, 1 do
        local idxOnPage = r * 2 + c + 1
        local wIdx = pageOffset + idxOnPage
        if wIdx <= totalWords then
          local wEntry = wordsList[wIdx]
          local xPos = (c == 0) and (wX + 18) or (wX + 120)
          local isCur = (st.wordCursor == idxOnPage)

          if isCur then
            -- Red selection outline
            love.graphics.setColor(224 / 255, 32 / 255, 32 / 255, 1)
            love.graphics.rectangle("line", xPos - 12, yPos - 1, 92, 14, 2, 2)
            drawTriangleCursor(xPos - 10, yPos + 3, st.animTimer)
            FrlgFont.draw(EasyChatText.wordInGroup(wEntry, curGroup), xPos, yPos, { maxWidth = CELL_WIDTH, colors = FrlgFont.COLOR.NORMAL })
          else
            FrlgFont.draw(EasyChatText.wordInGroup(wEntry, curGroup), xPos, yPos, { maxWidth = CELL_WIDTH, colors = FrlgFont.COLOR.NORMAL })
          end
        end
      end
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return EasyChat

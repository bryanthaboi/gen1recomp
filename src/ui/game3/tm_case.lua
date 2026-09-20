-- FRLG TM Case Sub-Container UI (item_menu.c / tm_case.c).
-- 1:1 layout matching pret pokefirered:
-- - WIN_TITLE: (0, 1, 10, 2) -> (0, 8, 80, 16), centered title "TM CASE"
-- - WIN_LIST: (10, 1, 19, 10) -> (80, 8, 152, 80), 5 visible rows on dashed lines
-- - WIN_DESCRIPTION: (12, 12, 18, 8) -> (96, 96, 144, 64), text at (98, 100)
-- - WIN_MOVE_INFO_LABELS: (1, 13, 5, 6) -> (8, 104, 40, 48), TYPE / POWER / ACCURACY / PP
-- - WIN_MOVE_INFO: (7, 13, 5, 6) -> (56, 104, 40, 48), Type Badge & right-aligned values
-- - Disc Sprite: centered at (41, 46) -> top-left at (25, 30)
-- - WIN_USE_GIVE_EXIT: (22, 13, 7, 6) -> (176, 104, 56, 48)

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Pokemon = require("src.core.game3.pokemon")
local SummaryData = require("src.core.game3.summary_data")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local Strings = require("src.core.Strings")

local TmCase = {}

TmCase.open = false
TmCase.cursor = 1
TmCase.scroll = 0
TmCase.mode = "list" -- "list" | "action" | "message"
TmCase.actionCursor = 1
TmCase.messageText = nil

local VISIBLE = 5 -- 1:1 pret sTMCaseDynamicResources->maxTMsShown = 5
local ACTIONS = { "USE", "GIVE", "EXIT" }

-- Disc Type Palette mapping for disc render fallback
local TYPE_DISC_COLORS = {
  NORMAL   = { 0.65, 0.65, 0.55 },
  FIGHTING = { 0.75, 0.20, 0.15 },
  FLYING   = { 0.60, 0.70, 0.90 },
  POISON   = { 0.60, 0.25, 0.60 },
  GROUND   = { 0.85, 0.75, 0.40 },
  ROCK     = { 0.70, 0.60, 0.25 },
  BUG      = { 0.60, 0.70, 0.15 },
  GHOST    = { 0.45, 0.35, 0.60 },
  STEEL    = { 0.70, 0.70, 0.80 },
  FIRE     = { 0.95, 0.50, 0.20 },
  WATER    = { 0.35, 0.55, 0.90 },
  GRASS    = { 0.45, 0.80, 0.30 },
  ELECTRIC = { 0.95, 0.80, 0.20 },
  PSYCHIC  = { 0.95, 0.35, 0.55 },
  ICE      = { 0.55, 0.85, 0.85 },
  DRAGON   = { 0.45, 0.20, 0.95 },
  DARK     = { 0.40, 0.30, 0.25 },
}

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

function TmCase.isOpen()
  return TmCase.open
end

function TmCase.list()
  local bag = TmCase._bag
  if not bag then return {} end
  local rows = Bag.listPocket(bag, "TM_CASE")
  return rows or {}
end

local function get_total_count()
  local rows = TmCase.list()
  return #rows + 1 -- +1 for Cancel
end

local function clamp_cursor()
  local rows = TmCase.list()
  local total = #rows + 1
  if total < 1 then
    TmCase.cursor = 1
    TmCase.scroll = 0
    return rows
  end
  if TmCase.cursor > total then TmCase.cursor = total end
  if TmCase.cursor < 1 then TmCase.cursor = 1 end
  if TmCase.cursor <= TmCase.scroll then
    TmCase.scroll = TmCase.cursor - 1
  end
  if TmCase.cursor > TmCase.scroll + VISIBLE then
    TmCase.scroll = TmCase.cursor - VISIBLE
  end
  if TmCase.scroll < 0 then TmCase.scroll = 0 end
  return rows
end

function TmCase.show(session, bag, opts)
  opts = opts or {}
  TmCase.open = true
  TmCase._session = session or opts.session
  TmCase._bag = bag or opts.bag or (session and session.bag)
  TmCase._onClose = opts.onClose
  TmCase.cursor = opts.cursor or 1
  TmCase.scroll = opts.scroll or 0
  TmCase.mode = "list"
  TmCase.actionCursor = 1
  TmCase.messageText = nil
  clamp_cursor()
  Stack.push("tm_case", TmCase, { hideBelow = true })
end

function TmCase.close()
  TmCase.open = false
  Stack.pop("tm_case")
  local cb = TmCase._onClose
  TmCase._onClose = nil
  if cb then cb() end
end

function TmCase.handleInput(input)
  if TmCase.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      TmCase.mode = "list"
      TmCase.messageText = nil
      clamp_cursor()
    end
    return
  end

  if TmCase.mode == "action" then
    if input:wasPressed("up") then
      TmCase.actionCursor = ((TmCase.actionCursor - 2) % #ACTIONS) + 1
      se(5)
    elseif input:wasPressed("down") then
      TmCase.actionCursor = (TmCase.actionCursor % #ACTIONS) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local act = ACTIONS[TmCase.actionCursor]
      local rows = clamp_cursor()
      local row = rows[TmCase.cursor]
      if act == "EXIT" or not row then
        TmCase.mode = "list"
      elseif act == "GIVE" then
        TmCase.mode = "message"
        TmCase.messageText = Strings("This item can't be held.")
      elseif act == "USE" then
        local party = (TmCase._session and TmCase._session.party) or {}
        if #party == 0 then
          TmCase.mode = "message"
          TmCase.messageText = Strings("There is no POKéMON.")
        else
          local PartyMenu = require("src.ui.game3.party_menu")
          PartyMenu.show(party, TmCase._session and TmCase._session.moveOverlay, {
            session = TmCase._session,
            bag = TmCase._bag,
            item = row.id,
            mode = "use",
            onClose = function()
              TmCase.mode = "list"
              clamp_cursor()
            end,
          })
        end
      end
    elseif input:wasPressed("b") then
      se(9)
      TmCase.mode = "list"
    end
    return
  end

  -- List mode navigation
  local rows = clamp_cursor()
  local total = #rows + 1

  if input:wasPressed("up") then
    if total > 0 then
      TmCase.cursor = ((TmCase.cursor - 2) % total) + 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("down") then
    if total > 0 then
      TmCase.cursor = (TmCase.cursor % total) + 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("left") or input:wasPressed("l") then
    if total > 0 then
      TmCase.cursor = math.max(1, TmCase.cursor - VISIBLE)
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("right") or input:wasPressed("r") then
    if total > 0 then
      TmCase.cursor = math.min(total, TmCase.cursor + VISIBLE)
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("a") then
    if TmCase.cursor == total then
      -- Clicked CANCEL
      se(9)
      TmCase.close()
    else
      local row = rows[TmCase.cursor]
      if row then
        TmCase.mode = "action"
        TmCase.actionCursor = 1
        se(5)
      end
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(9)
    TmCase.close()
  end
end

local function draw_disc_fallback(cx, cy, moveType)
  if not (love and love.graphics) then return end
  local col = TYPE_DISC_COLORS[moveType or "NORMAL"] or TYPE_DISC_COLORS.NORMAL
  
  -- Outer disc ring (32x32 centered at cx, cy)
  love.graphics.setColor(col[1] * 0.7, col[2] * 0.7, col[3] * 0.7, 1)
  love.graphics.circle("fill", cx, cy, 16)
  love.graphics.setColor(col[1], col[2], col[3], 1)
  love.graphics.circle("fill", cx, cy, 14)
  
  -- Metallic shine arc
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.arc("fill", cx, cy, 14, -math.pi * 0.7, -math.pi * 0.2)
  
  -- Center spindle hole
  love.graphics.setColor(0.15, 0.15, 0.15, 1)
  love.graphics.circle("fill", cx, cy, 5)
  love.graphics.setColor(0.3, 0.3, 0.3, 1)
  love.graphics.circle("line", cx, cy, 5)
end

function TmCase.draw()
  if not TmCase.open then return end
  local rows = clamp_cursor()
  local total = #rows + 1
  local isCancel = (TmCase.cursor == total)
  local sel = not isCancel and rows[TmCase.cursor] or nil

  local okC, TmCaseChrome = pcall(require, "src.ui.game3.tm_case_chrome")
  local hasChrome = okC and TmCaseChrome and TmCaseChrome.ready and TmCaseChrome.ready()
  local isFemale = false
  local session = TmCase._session
  if session and (session.gender == 1 or session.gender == "female" or session.playerGender == 1) then
    isFemale = true
  end

  -- 1. Background (240x160) - BG2 Base
  if hasChrome then
    TmCaseChrome.drawBg(0, 0, { female = isFemale })
  else
    love.graphics.setColor(0.18, 0.42, 0.58, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    Window.stdFrame(Window.template(1, 4, 11, 15))
    Window.stdFrame(Window.template(13, 1, 16, 18))
  end

  -- 2. Disc Sprite (in between BG2 and BG1)
  if sel then
    local moveId = Pokemon.moveFromTmItem(sel.id)
    local moveRow = Pokemon.battleMove(moveId) or {}
    local moveType = tostring(moveRow.type or "NORMAL"):upper()
    local typeIdx = SummaryChrome.TYPE_NAMES and SummaryChrome.TYPE_NAMES[moveType] or 0
    local isHm = ItemsData.isHm(sel.id)
    local tmNum = ItemsData.tmNumber(sel.id) or 1
    local tmIdx = isHm and (tmNum - 1) or (tmNum - 1 + 8)

    -- 1:1 dynamic rack positioning formula from pokefirered SetDiscSpritePosition:
    local cx = 41 - math.floor((14 * tmIdx) / 58)
    local cy = 46 + math.floor((8 * tmIdx) / 58)

    local drawn = hasChrome and TmCaseChrome.drawDisc(typeIdx, cx - 16, cy - 16, isHm)
    if not drawn then
      draw_disc_fallback(cx, cy, moveType)
    end
  end

  -- 3. Pocket Cover Overlay (BG1 Priority 0 over Disc Sprite)
  if hasChrome then
    TmCaseChrome.drawCover(0, 0, { female = isFemale })
  end

  -- 4. Header Title: "TM CASE" (WIN_TITLE: 0, 1, 10, 2 -> 72px center at y=9)
  local title = Strings("TM CASE")
  local tw = FrlgFont.measure(title)
  local tx = math.floor((72 - tw) / 2) + 4
  FrlgFont.draw(title, tx, 9, { colors = FrlgFont.COLOR.LIGHT })


  -- 4. Left Pane: Move Details (WIN_MOVE_INFO_LABELS & WIN_MOVE_INFO: y=104..152)
  -- Row 0: TYPE (y = 104)
  FrlgFont.draw(Strings("TYPE"), 8, 104, { colors = FrlgFont.COLOR.DARK_GRAY })
  -- Row 1: POWER (y = 116)
  FrlgFont.draw(Strings("POWER"), 8, 116, { colors = FrlgFont.COLOR.DARK_GRAY })
  -- Row 2: ACCURACY (y = 128)
  FrlgFont.draw(Strings("ACCURACY"), 8, 128, { colors = FrlgFont.COLOR.DARK_GRAY })
  -- Row 3: PP (y = 140)
  FrlgFont.draw(Strings("PP"), 8, 140, { colors = FrlgFont.COLOR.DARK_GRAY })

  if sel then
    local moveId = Pokemon.moveFromTmItem(sel.id)
    local moveRow = Pokemon.battleMove(moveId) or {}
    local moveType = tostring(moveRow.type or "NORMAL"):upper()
    local power = tonumber(moveRow.power) or 0
    local accuracy = tonumber(moveRow.accuracy) or 0
    local pp = tonumber(moveRow.pp) or 0

    -- Type Badge (32x12 at x=44, y=104)
    SummaryChrome.drawTypeBadge(moveType, 44, 104)

    -- Values (x=52..68, right-aligned)
    local powStr = power >= 2 and string.format("%3d", power) or "---"
    local accStr = accuracy > 0 and string.format("%3d", accuracy) or "---"
    local ppStr = pp > 0 and string.format("%3d", pp) or "---"

    FrlgFont.draw(powStr, 56, 116, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(accStr, 56, 128, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(ppStr, 56, 140, { colors = FrlgFont.COLOR.NORMAL })
  else
    -- Cancel / Empty selected
    FrlgFont.draw("---", 56, 104, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("---", 56, 116, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("---", 56, 128, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("---", 56, 140, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- 5. Right Pane: List Menu (WIN_LIST: 10, 1, 19, 10 -> x=80, y=8, 5 visible rows)
  if TmCase.scroll > 0 then
    FrlgFont.draw("▲", 160, 4, { colors = FrlgFont.COLOR.DARK_GRAY })
  end
  if TmCase.scroll + VISIBLE < total then
    FrlgFont.draw("▼", 160, 88, { colors = FrlgFont.COLOR.DARK_GRAY })
  end

  for i = 1, VISIBLE do
    local idx = TmCase.scroll + i
    if idx > total then break end
    local y = 10 + (i - 1) * 16

    -- Selector Cursor
    if idx == TmCase.cursor and TmCase.mode == "list" then
      Window.cursorPx(84, y)
    end

    if idx <= #rows then
      local r = rows[idx]
      local tmNum = ItemsData.tmNumber(r.id)
      local isHm = ItemsData.isHm(r.id)
      local mId = Pokemon.moveFromTmItem(r.id)
      local mName = Pokemon.moveName(mId) or r.name or "MOVE"

      if isHm then
        -- HM icon + HM number
        local okHm = hasChrome and TmCaseChrome.drawHmIcon(92, y + 1)
        if not okHm then
          FrlgFont.draw(Strings("HM"), 92, y, { colors = FrlgFont.COLOR.DARK_GRAY })
        end
        FrlgFont.draw(string.format("%02d", tmNum or 0), 108, y, { colors = FrlgFont.COLOR.DARK_GRAY })
      else
        -- TM number
        FrlgFont.draw(string.format("%02d", tmNum or 0), 96, y, { colors = FrlgFont.COLOR.DARK_GRAY })
      end

      -- Move Name
      FrlgFont.draw(mName, 122, y, { maxWidth = 76, colors = FrlgFont.COLOR.NORMAL })

      -- Quantity (TMs only)
      if not isHm then
        FrlgFont.draw(string.format("×%2d", r.qty or 1), 206, y, { colors = FrlgFont.COLOR.NORMAL })
      end
    else
      -- CANCEL Row
      FrlgFont.draw(Strings("CANCEL"), 92, y, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- 6. Bottom Description Pane (WIN_DESCRIPTION: 12, 12, 18, 8 -> text at 98, 100)
  if TmCase.mode ~= "action" then
    local descText
    if isCancel then
      descText = Strings("The TM CASE will be\nput away.")
    elseif sel then
      local moveId = Pokemon.moveFromTmItem(sel.id)
      local moveName = Pokemon.moveName(moveId) or "---"
      descText = SummaryData.moveDescription(moveId, moveName)
      if not descText or descText == "---" then
        descText = sel.description or ItemsData.description(sel.id)
      end
    end
    if descText then
      local wrapped = FrlgFont.wrap(descText, 136)
      FrlgFont.draw(wrapped, 98, 100, { maxWidth = 136, linePitch = 14, colors = FrlgFont.COLOR.LIGHT })
    end
  end

  -- 7. Action Pop-up Menu (WIN_USE_GIVE_EXIT: 22, 13, 7, 6 -> 176, 104, 56, 48)
  if TmCase.mode == "action" and sel then
    -- Bottom left prompt window (WIN_SELECTED_MSG: 5, 15, 15, 4 -> 40, 120, 120, 32)
    Window.stdFrame(Window.template(5, 15, 15, 4))
    local tmLabel = sel.name or ItemsData.displayName(sel.id) or "TM"
    FrlgFont.draw(Strings("%s is\nselected.", tmLabel), 44, 122, { maxWidth = 112, linePitch = 14, colors = FrlgFont.COLOR.NORMAL })

    local popX = 22
    local popY = 13
    local popW = 7
    local popH = 6
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == TmCase.actionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(Strings(act), popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- 8. Message Modal
  if TmCase.mode == "message" and TmCase.messageText then
    Window.stdFrame(Window.template(2, 15, 26, 4))
    local wrapped = FrlgFont.wrap(TmCase.messageText, 192)
    FrlgFont.draw(wrapped, 20, 122, { maxWidth = 192, linePitch = 14, colors = FrlgFont.COLOR.NORMAL })
  end
end

return TmCase

-- Yes/No + multichoice (pret yesnobox / multichoice / multichoicegrid). Writes VAR_RESULT via callback.

local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")
local RomText = require("src.core.game3.rom_text")

local Choice = {}

Choice.active = false
Choice.kind = nil -- "yesno" | "multi"
Choice.options = nil
Choice.cursor = 1
Choice.done = nil
Choice.left = nil
Choice.top = nil
Choice.cols = 1
Choice.ignoreBPress = false

function Choice.isOpen()
  return Choice.active and true or false
end

-- pokefirered/src/main.c:480
function Choice.reset()
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cursor = 1
  Choice.done = nil
  Choice.left = nil
  Choice.top = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.style = nil
  return true
end

function Choice.yesNo(cb, layout)
  Choice.active = true
  Choice.kind = "yesno"
  layout = layout or {}
  Choice.style = layout.style
  if layout.style == "battle" then
    -- pokefirered/src/battle_message.c:1288
    local yes, no = RomText.plain("gText_BattleYesNoChoice"):match("^(.-)\n(.*)$")
    Choice.options = { yes, no }
  else
    -- pokefirered/src/strings.c:414
    Choice.options = { RomText.plain("gText_Yes"), RomText.plain("gText_No") }
  end
  Choice.cursor = 1
  Choice.done = cb
  -- pret WIN_INTRO_YESNO at tiles (2,2); field default near dialogue right.
  Choice.left = tonumber(layout.left) or (Display.COLS - 8)
  Choice.top = tonumber(layout.top) or 8
  Choice.maxRight = nil
  Choice.cols = 1
  Choice.ignoreBPress = layout.ignoreBPress or false
end

function Choice.multi(options, defaultIdx, cb, layout)
  Choice.active = true
  Choice.kind = "multi"
  Choice.style = nil
  Choice.options = options or {}
  Choice.cursor = (tonumber(defaultIdx) or 0) + 1
  if Choice.cursor < 1 then Choice.cursor = 1 end
  if Choice.cursor > #Choice.options then Choice.cursor = 1 end
  Choice.done = cb
  layout = layout or {}
  Choice.left = tonumber(layout.left) or (Display.COLS - 10)
  Choice.top = tonumber(layout.top) or 5
  Choice.maxRight = tonumber(layout.maxRight)
  Choice.cols = tonumber(layout.cols) or 1
  Choice.ignoreBPress = layout.ignoreBPress or false
end

function Choice.move(dy, dx)
  if not Choice.active or not Choice.options then return end
  local n = #Choice.options
  if n < 1 then return end
  local cols = Choice.cols or 1
  if cols <= 1 then
    local delta = dy or 0
    if delta == 0 and dx then delta = dx end
    if delta ~= 0 then
      Choice.cursor = ((Choice.cursor - 1 + delta) % n) + 1
      pcall(function() require("src.core.game3.audio").playSe(5) end)
    end
    return
  end

  -- 2D Grid navigation
  local rows = math.ceil(n / cols)
  local cur = Choice.cursor - 1
  local curCol = cur % cols
  local curRow = math.floor(cur / cols)

  if dy and dy ~= 0 then
    curRow = (curRow + dy) % rows
  end
  if dx and dx ~= 0 then
    curCol = (curCol + dx) % cols
  end

  local target = curRow * cols + curCol
  if target >= n then
    target = n - 1
  end
  if target + 1 ~= Choice.cursor then
    Choice.cursor = target + 1
    pcall(function() require("src.core.game3.audio").playSe(5) end)
  end
end

function Choice.confirm()
  if not Choice.active then return end
  pcall(function() require("src.core.game3.audio").playSe(5) end)
  local cb = Choice.done
  local kind = Choice.kind
  local cursor = Choice.cursor
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.done = nil
  if not cb then return end
  if kind == "yesno" then
    cb(cursor == 1)
  else
    cb(cursor - 1)
  end
end

function Choice.cancel()
  if not Choice.active then return end
  if Choice.ignoreBPress then
    return
  end
  pcall(function() require("src.core.game3.audio").playSe(5) end) -- pokefirered/src/menu_helpers.c:57
  local cb = Choice.done
  local kind = Choice.kind
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
  Choice.cols = 1
  Choice.ignoreBPress = false
  Choice.done = nil
  if not cb then return end
  if kind == "yesno" then
    cb(false)
  else
    cb(127) -- FRLG B-cancel often 0x7F
  end
end

function Choice.autoPick(indexOrYes)
  if not Choice.active then return end
  if Choice.kind == "yesno" then
    Choice.cursor = indexOrYes and 1 or 2
  else
    Choice.cursor = (tonumber(indexOrYes) or 0) + 1
  end
  Choice.confirm()
end

function Choice.draw()
  if not Choice.active or not Choice.options then return end
  if Choice.style == "battle" and Choice.kind == "yesno" then
    -- pokefirered/src/battle_script_commands.c:9775
    local L, Tp = Choice.left, Choice.top
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    local session = okR and type(Runtime) == "table" and Runtime.getSession and Runtime.getSession()
    local opts = type(session) == "table" and session.options or nil
    local frameType = tonumber(type(opts) == "table" and opts.frameType or nil) or 0
    -- pokefirered/src/battle_bg.c:693
    Window.userFrame(Window.template(L, Tp, 5, 4), frameType)
    for i, lab in ipairs(Choice.options) do
      local rowPx = (Tp + (i - 1) * 2) * 8
      if i == Choice.cursor then Window.cursorPx(L * 8, rowPx) end
      -- pokefirered/src/battle_message.c:2574
      Window.printPx(lab, (L + 1) * 8, rowPx + 2)
    end
    return
  end

  local n = #Choice.options
  local cols = Choice.cols or 1
  if cols <= 1 then
    local tw = 8
    for _, lab in ipairs(Choice.options) do
      local need = math.min(18, math.max(6, math.floor(#tostring(lab) * 0.7) + 2))
      if need > tw then tw = need end
    end
    local th = math.max(2, math.ceil((n * Window.OPTION_HEIGHT) / 8))
    local tx = Choice.left or (Display.COLS - tw - 2)
    if Choice.kind == "multi" and Choice.maxRight and tx + tw > Choice.maxRight then
      tx = Choice.maxRight - tw
    end
    local ty = Choice.top or 5
    Window.stdFrame(Window.template(tx, ty, tw, th))
    local leftPx = tx * 8
    local topPx = ty * 8
    for i, lab in ipairs(Choice.options) do
      local yPx = Window.menuRowPx(topPx, i)
      if i == Choice.cursor then Window.cursorPx(leftPx, yPx) end
      Window.printPx(lab, leftPx + Window.CURSOR_WIDTH, yPx)
    end
  else
    -- Multi-column grid
    local rows = math.ceil(n / cols)
    local colTileWidths = {}
    for c = 1, cols do
      local maxW = 4
      for r = 1, rows do
        local idx = (r - 1) * cols + c
        if idx <= n then
          local lab = tostring(Choice.options[idx] or "")
          local need = math.floor(#lab * 0.7) + 2
          if need > maxW then maxW = need end
        end
      end
      colTileWidths[c] = maxW
    end
    local totalTileW = 0
    for c = 1, cols do
      totalTileW = totalTileW + colTileWidths[c]
    end
    local th = math.max(2, math.ceil((rows * Window.OPTION_HEIGHT) / 8))
    local tx = Choice.left or 2
    if Choice.maxRight and tx + totalTileW > Choice.maxRight then
      tx = Choice.maxRight - totalTileW
    end
    if tx < 0 then tx = 0 end
    local ty = Choice.top or 5
    Window.stdFrame(Window.template(tx, ty, totalTileW, th))

    local topPx = ty * 8
    for i, lab in ipairs(Choice.options) do
      local idx0 = i - 1
      local c = (idx0 % cols) + 1
      local r = math.floor(idx0 / cols) + 1

      local colOffsetTiles = 0
      for prevC = 1, c - 1 do
        colOffsetTiles = colOffsetTiles + colTileWidths[prevC]
      end
      local colLeftPx = (tx + colOffsetTiles) * 8
      local yPx = Window.menuRowPx(topPx, r)

      if i == Choice.cursor then
        Window.cursorPx(colLeftPx, yPx)
      end
      Window.printPx(lab, colLeftPx + Window.CURSOR_WIDTH, yPx)
    end
  end
end

return Choice

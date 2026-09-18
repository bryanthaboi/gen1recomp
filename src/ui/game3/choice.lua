-- Yes/No + multichoice (pret yesnobox / multichoice). Writes VAR_RESULT via callback.

local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")

local Choice = {}

Choice.active = false
Choice.kind = nil -- "yesno" | "multi"
Choice.options = nil
Choice.cursor = 1
Choice.done = nil
Choice.left = nil
Choice.top = nil

function Choice.yesNo(cb, layout)
  Choice.active = true
  Choice.kind = "yesno"
  layout = layout or {}
  Choice.style = layout.style
  if layout.style == "battle" then
    -- pokefirered/src/battle_message.c:1288
    Choice.options = { "Yes", "No" }
  else
    Choice.options = { "YES", "NO" }
  end
  Choice.cursor = 1
  Choice.done = cb
  -- pret WIN_INTRO_YESNO at tiles (2,2); field default near dialogue right.
  Choice.left = tonumber(layout.left) or (Display.COLS - 8)
  Choice.top = tonumber(layout.top) or 8
  Choice.maxRight = nil
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
end

function Choice.move(delta)
  if not Choice.active or not Choice.options then return end
  local n = #Choice.options
  if n < 1 then return end
  Choice.cursor = ((Choice.cursor - 1 + delta) % n) + 1
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
  pcall(function() require("src.core.game3.audio").playSe(9) end)
  local cb = Choice.done
  local kind = Choice.kind
  Choice.active = false
  Choice.kind = nil
  Choice.options = nil
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
end

return Choice

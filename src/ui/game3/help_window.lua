-- src/new_menu_helpers.c:701-705, src/new_menu_helpers.c:707-710, src/help_message.c:23-31, src/help_message.c:13-19, src/start_menu.c:332, src/help_system.c

local Window = require("src.ui.game3.window")

local HelpWindow = {}

-- src/help_message.c:13-19
HelpWindow.OUTER = { left = 0, top = 15, width = 30, height = 5, paletteNum = 15 }
HelpWindow.CONTENT = { left = 1, top = 16, width = 28, height = 3 }
-- src/help_message.c:95-98
HelpWindow.TEXT_OFFSET = { x = 2, y = 5 }

local open = false
local text = ""

local function contentTemplate()
  local c = HelpWindow.CONTENT
  return Window.template(c.left, c.top, c.width, c.height,
    { paletteNum = HelpWindow.OUTER.paletteNum })
end

function HelpWindow.show(value)
  text = type(value) == "string" and value or ""
  open = true
  return true
end

function HelpWindow.close()
  open = false
  text = ""
  return true
end

function HelpWindow.isOpen()
  return open
end

function HelpWindow.getText()
  return text
end

function HelpWindow.draw()
  if not open then return false end
  local tpl = contentTemplate()
  -- src/help_message.c:41
  Window.fill(tpl, 1, 1, 1, 1)
  Window.stdFrame(tpl)
  if text ~= "" then
    local c = HelpWindow.CONTENT
    local off = HelpWindow.TEXT_OFFSET
    Window.printPx(text, c.left * 8 + off.x, c.top * 8 + off.y, {
      maxWidth = c.width * 8 - off.x * 2,
    })
  end
  return true
end

function HelpWindow.reset()
  HelpWindow.close()
end

return HelpWindow

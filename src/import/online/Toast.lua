local Kit = require("src.ui.kit.Kit")
local Transition = require("src.ui.kit.Transition")
local Strings = require("src.core.Strings")

local Toast = {}

Toast.ID = "online-toast"

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end

local opts = { id = Toast.ID, icon = "mail" }

function Toast.current(imp)
  if type(imp) ~= "table" or not imp._online then return nil end
  return OP().toast(imp)
end

function Toast.occlude(imp)
  local rect = type(imp) == "table" and imp._toastRect or nil
  if rect and rect.shown and Toast.current(imp) then
    Kit.occlude(rect[1], rect[2], rect[3], rect[4])
  else
    Kit.occlude(nil)
  end
end

function Toast.draw(imp, m, top, blocked)
  local invite = Toast.current(imp)
  if not invite then
    if imp._toastRect then imp._toastRect.shown = false end
    Kit.occlude(nil)
    return false
  end
  local OnlinePanel = OP()
  opts.text = invite.line or OnlinePanel.inviteLine(invite)
  opts.accept = Strings("Accept")
  opts.decline = Strings("Decline")
  opts.progress = OnlinePanel.inviteLeft(invite)
  opts.slide = Transition.progress("toast")
  opts.W = m.W
  opts.top = top
  opts.blocked = blocked
  local action, x, y, w, h = Kit.toast(opts)
  local rect = imp._toastRect
  if not rect then
    rect = {}
    imp._toastRect = rect
  end
  rect[1], rect[2], rect[3], rect[4], rect.shown = x, y, w, h, true
  if action then
    LV().queueAction(imp, Toast.ID .. "-" .. action, function()
      OnlinePanel.toastAction(imp, action)
    end)
  end
  return true
end

return Toast

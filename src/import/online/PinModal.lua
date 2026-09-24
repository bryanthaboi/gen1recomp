local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local PinModal = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end

function PinModal.draw(imp, m)
  local OnlinePanel = OP()
  local mo = OnlinePanel.pinModal(imp)
  if not mo then return false end
  local pad = math.floor(18 * m.s)
  local gap = math.floor(8 * m.s)
  local tiny = math.floor(4 * m.s)
  local w = math.floor(380 * m.s)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local locked = OnlinePanel.pinLocked(imp)
  local target = type(mo.target) == "table" and mo.target or {}
  local sub = target.name
    and Strings("%s's lobby is private.", tostring(target.name))
    or Strings("This lobby is private.")
  local errText = locked and OnlinePanel.retryAtText(mo.retryAt) or mo.error
  local innerW = w - 2 * pad
  local errH = errText and Kit.wrapHeight("small", errText, innerW, 2) or 0
  local h = pad + Kit.textHeight("button") + gap
    + Kit.wrapHeight("small", sub, innerW, 2) + gap
    + Kit.textHeight("small") + tiny + btnH + tiny
    + math.max(errH, Kit.textHeight("small")) + gap + btnH + pad
  local px, py, pw = LV().modalPanel(m, w, h)
  innerW = pw - 2 * pad
  local x = px + pad
  local cy = py + pad

  local icon = Kit.textHeight("button")
  Ui.lock(x, cy, icon, PAL.yellow)
  Kit.textBold("button", Strings("Enter the PIN"), x + icon + gap, cy,
    PAL.heading)
  cy = cy + Kit.textHeight("button") + gap
  cy = cy + Kit.textWrapped("small", sub, x, cy, innerW, PAL.muted, 2) + gap

  cy = cy + Ui.label(Strings("PIN"), x, cy) + tiny
  local field = OnlinePanel.PIN_FIELD
  local fieldW = math.min(innerW, math.floor(180 * m.s))
  Ui.field(imp, x, cy, fieldW, btnH, field, mo.pin or "", Strings("4 digits"),
    imp._onlineFocus == field,
    function(text)
      mo.pin = OnlinePanel.sanitizePin(text)
    end,
    { mask = true, digits = true, maxLen = OnlinePanel.PIN_LEN })
  cy = cy + btnH + tiny
  if errText then
    Kit.textWrapped("small", errText, x, cy, innerW, PAL.red, 2)
  end
  cy = cy + math.max(errH, Kit.textHeight("small")) + gap

  local half = math.floor((innerW - gap) / 2)
  LV().btn(imp, x, cy, half, btnH, OnlinePanel.PIN_CANCEL, Strings("Cancel"),
    { kind = "ghost", font = "small",
      action = function() OnlinePanel.pinClose(imp) end })
  local canEnter = not locked and OnlinePanel.pinValid(mo.pin)
  LV().btn(imp, x + half + gap, cy, innerW - half - gap, btnH,
    OnlinePanel.PIN_ENTER, Strings("Enter"),
    { kind = "primary", font = "small", enabled = canEnter, emboss = canEnter,
      icon = locked and "lock" or nil,
      action = function() OnlinePanel.pinSubmit(imp) end })
  return true
end

return PinModal

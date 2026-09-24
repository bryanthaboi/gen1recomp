local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")

local PAL = Theme.PAL

local Ui = {}

local function LV()
  return require("src.import.LauncherView")
end

local function OP()
  return require("src.import.OnlinePanel")
end

Ui.LV = LV
Ui.OP = OP

function Ui.pads(m)
  local s = m.s
  return math.floor(14 * s), math.floor(8 * s), math.floor(4 * s)
end

function Ui.label(text, x, y, color)
  Kit.text("small", text, x, y, color or PAL.muted)
  return Kit.textHeight("small")
end

function Ui.dots(n, x, y, h, color)
  local r = math.max(2, math.floor(4 * Kit.scale))
  local step = r * 3
  for i = 0, n - 1 do
    Theme.fillRounded(x + i * step, y + (h - 2 * r) / 2, 2 * r, 2 * r,
      color or PAL.heading, 1, r)
  end
  return n * step
end

function Ui.field(imp, x, y, w, h, key, text, placeholder, focused, set, opts)
  Kit._audit("control", x, y, w, h, key)
  local ring = Kit.focusable(key, x, y, w, h)
  Theme.fill(x, y, w, h, PAL.bg, 1)
  Theme.stroke(x, y, w, h, PAL.line,
    (focused or ring) and Theme.A.focus
      or (Kit.hover(x, y, w, h) and Theme.A.hover or Theme.A.hairline),
    focused and 2 or 1)
  local pad = math.floor(10 * Kit.scale)
  local ty = y + (h - Kit.textHeight("button")) / 2
  if (text or "") == "" and not focused then
    Kit.text("button", Kit.ellipsize("button", placeholder or "", w - 2 * pad),
      x + pad, ty, PAL.faint)
  else
    local tw
    if opts and opts.mask then
      tw = Ui.dots(#(text or ""), x + pad, y, h, PAL.heading)
    else
      local shown = Kit.ellipsizeLeft("button", text or "", w - 2 * pad)
      tw = Kit.text("button", shown, x + pad, ty, PAL.heading)
    end
    if focused and ((imp.pulse or 0) * 2 % 1) < 0.5 then
      Theme.fill(x + pad + tw + 2, ty, math.max(1, Kit.scale),
        Kit.textHeight("button"), PAL.ink, 1)
    end
  end
  if Kit.press(x, y, w, h) or Kit._activateId == key then
    imp._onlineFieldHit = true
    if Kit.VirtualKeyboard then
      Kit.VirtualKeyboard.open({
        text = text or "",
        targetId = key,
        title = placeholder or "Enter Text",
        digits = opts and opts.digits or nil,
        maxLen = opts and opts.maxLen or nil,
        onDone = function(newText, confirmed)
          if confirmed then set(newText) end
        end,
      })
    end
    LV().queueAction(imp, key, function() imp:_focusOnlineField(key) end)
  end
end

function Ui.lock(x, y, size, color, open)
  require("src.ui.kit.Icons").draw(open and "lock-open" or "lock", x, y, size,
    color or PAL.yellow, 1)
  return size
end

function Ui.lockTag(x, y, h, label, color)
  local s = Kit.scale
  local icon = math.floor(h * 0.7)
  local pad = math.floor(6 * s)
  local w = pad + icon + math.floor(4 * s) + Kit.textWidth("micro", label) + pad
  color = color or PAL.yellow
  Theme.strokeRounded(x, y, w, h, color, 0.7, 1)
  Ui.lock(x + pad, y + (h - icon) / 2, icon, color)
  Kit.text("micro", label, x + pad + icon + math.floor(4 * s),
    y + (h - Kit.textHeight("micro")) / 2, color)
  return w
end

function Ui.lockTagWidth(h, label)
  local s = Kit.scale
  return math.floor(6 * s) * 2 + math.floor(h * 0.7) + math.floor(4 * s)
    + Kit.textWidth("micro", label)
end

function Ui.chooser(imp, x, y, w, h, key, text, onPrev, onNext)
  local bw = math.max(Kit.tapMin(), math.floor(28 * Kit.scale))
  local gap = math.floor(4 * Kit.scale)
  LV().btn(imp, x, y, bw, h, key .. "-prev", "<",
    { kind = "ghost", font = "small", action = onPrev })
  LV().btn(imp, x + w - bw, y, bw, h, key .. "-next", ">",
    { kind = "ghost", font = "small", action = onNext })
  local inner = math.max(0, w - 2 * bw - 2 * gap)
  Kit.textCenter("small", Kit.ellipsize("small", text, inner),
    x + bw + gap, y + (h - Kit.textHeight("small")) / 2, inner, PAL.heading)
end

function Ui.indexOf(list, value)
  for i = 1, #list do
    if list[i] == value or (list[i] == false and value == nil) then return i end
  end
  return 1
end

function Ui.cycle(list, value, delta)
  local at = Ui.indexOf(list, value)
  local to = ((at - 1 + delta) % #list) + 1
  local picked = list[to]
  if picked == false then return nil end
  return picked
end

function Ui.header(imp, x, y, w, m, title, pill, pillColor)
  local _, gap = Ui.pads(m)
  local h = math.max(m.btnH, Kit.tapMin())
  local backW = math.floor(82 * m.s)
  LV().btn(imp, x, y, backW, h, "online-back", Strings("Back"),
    { kind = "ghost", font = "small",
      action = function() OP().back(imp) end })
  local right = 0
  if pill and pill ~= "" then
    right = math.min(math.floor(w * 0.4),
      Kit.textWidth("micro", pill) + math.floor(22 * m.s))
    Kit.tag(x + w - right, y + (h - math.floor(18 * m.s)) / 2, right,
      math.floor(18 * m.s), pill, pillColor or PAL.line)
  end
  local tx = x + backW + 2 * gap
  Kit.textBold("button",
    Kit.ellipsize("button", title,
      math.max(0, w - backW - 3 * gap - right)),
    tx, y + (h - Kit.textHeight("button")) / 2, PAL.heading)
  return h + gap
end

function Ui.statusLine(imp, x, y, w, m)
  local st = OP().state(imp)
  if not st.status then return 0 end
  local _, gap = Ui.pads(m)
  return Kit.textWrapped("small", tostring(st.status), x, y, w,
    st.statusOk and PAL.green or PAL.yellow, 2) + gap
end

function Ui.entryCard(imp, x, y, w, h, key, title, note, enabled, action)
  local pad = math.floor(12 * Kit.scale)
  local clicked, hot = Kit.row(x, y, w, h, false, enabled and key or nil)
  local ink = enabled and (hot or PAL.heading) or PAL.faint
  Kit.textBold("button", Kit.ellipsize("button", title, w - 2 * pad),
    x + pad, y + pad, ink)
  Kit.textWrapped("small", note, x + pad,
    y + pad + Kit.textHeight("button") + math.floor(4 * Kit.scale),
    w - 2 * pad, enabled and PAL.muted or PAL.faint, 2)
  if clicked and enabled and action then
    LV().queueAction(imp, key, action)
  end
end

return Ui

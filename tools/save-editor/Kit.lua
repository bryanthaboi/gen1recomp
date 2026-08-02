-- Immediate-mode widget kit for the save editor, drawn in the launcher's
-- visual language (see Theme.lua and SaveEditor.dc.html).
--
-- Call Kit.beginFrame(mx, my, clicked, wheel) once per love.draw() before any
-- widget and Kit.endFrame() after the last one; widgets read the frame's mouse
-- state to decide hover / click, and endFrame retires the text-input queue so a
-- keystroke is never applied twice.  The wheel notches accumulated since the
-- last frame arrive the same way and are retired the same way: an unclaimed
-- notch dies with the frame rather than scrolling something later (#595).
--
-- Hit testing is a plain rect with no z-order, so panels must draw
-- overlapping controls in dispatch order and every target is >= 26px tall
-- (rule 6 of the design spec) -- that sizing is the whole accessibility story
-- here.

local Theme = require("Theme")
local PAL = Theme.PAL

local Kit = {}
Kit.mouseX, Kit.mouseY = 0, 0
Kit.mouseClicked = false  -- left button pressed this frame
Kit.wheelY = 0            -- wheel notches queued since the last frame (#595)
Kit.focus = nil           -- id of the text field receiving keystrokes
Kit.time = 0
Kit.fonts = {}
Kit.scale = 1

local G = love and love.graphics or nil
local edits = {}          -- queued textinput / backspace since the last frame
local kbField = nil       -- id of the field the OS soft keyboard is raised for

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is
-- active, and that call is what raises the Android/iOS soft keyboard; the
-- rect keeps the focused field visible above it.  Desktop has text input on
-- by default and the launcher hosting this editor depends on that -- the
-- launcher's own fields (slot rename #205, mod index prompt, find search)
-- follow the same rule since #578: arm on open, lower only on mobile -- so
-- neither side ever turns desktop text input off, since setTextInput is
-- global SDL state, not per-widget (#529).
local function mobile()
  local osName = love and love.system and love.system.getOS
    and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

local function syncSoftKeyboard(id, x, y, w, h)
  if not (love and love.keyboard and love.keyboard.setTextInput) then return end
  if id then
    if kbField ~= id then
      kbField = id
      love.keyboard.setTextInput(true, math.floor(x), math.floor(y),
        math.ceil(w), math.ceil(h))
    end
  elseif kbField then
    kbField = nil
    if mobile() then love.keyboard.setTextInput(false) end
  end
end

local function canPrintf()
  return G and type(G.printf) == "function"
end

function Kit.beginFrame(mx, my, clicked, wheel)
  Kit.mouseX, Kit.mouseY = mx, my
  Kit.mouseClicked = clicked
  Kit.wheelY = wheel or 0
  if love and love.timer and love.timer.getTime then
    Kit.time = love.timer.getTime()
  end
end

-- Retire this frame's keystrokes.  Anything typed while no field had focus is
-- dropped here rather than replayed into the next field that gets clicked.
-- A wheel notch no list claimed retires with them, for the same reason.
function Kit.endFrame()
  for i = #edits, 1, -1 do edits[i] = nil end
  Kit.wheelY = 0
end

-- Rebuild the font set when the window size changes.  `s` matched the
-- launcher's height/768 scale alone until #497: a phone in portrait
-- (720x1560) is TALLER than the desktop reference and barely half as wide, so
-- a height-only scale drew a 1.6x desktop layout into a 720px window and every
-- right-aligned cluster in the chrome landed on top of the block to its left.
-- The layout needs roughly 1000 logical px of width, so the window now pays
-- for both axes.  Every desktop and landscape size still lands on the height
-- term, which is why they stay pixel-identical to before.
function Kit.layout(width, height)
  local s = Theme.clamp(math.min(width / 1000, height / 768), 0.62, 1.6)
  local key = ("%dx%d"):format(width, height)
  if Kit._fontKey ~= key then
    Kit._fontKey = key
    Kit.fonts = Theme.fonts(s)
  end
  Kit.scale = s
  return s
end

-- ------------------------------------------------------------ input plumbing
-- App forwards love.textinput / love.keypressed here so Kit.textfield can be a
-- real editable field.  Events arrive before draw, so they queue and the
-- focused field drains them while it renders.
function Kit.textinput(text)
  if not Kit.focus then return false end
  edits[#edits + 1] = text
  return true
end

-- Returns true when the key was consumed by the focused field, so App can
-- leave its own shortcuts alone while the user is typing.
function Kit.keypressed(key)
  if not Kit.focus then return false end
  if key == "backspace" then
    edits[#edits + 1] = "\b"
    return true
  elseif key == "return" or key == "kpenter" or key == "escape" then
    edits[#edits + 1] = "\r"
    return true
  end
  -- other keys (arrows, shortcuts) fall through to App while a field is hot
  return false
end

function Kit.blur()
  Kit.focus = nil
  syncSoftKeyboard(nil)  -- the soft keyboard follows focus down too (#529)
end

-- ------------------------------------------------------------- hit testing
function Kit.hit(x, y, w, h)
  return Kit.mouseX >= x and Kit.mouseX <= x + w
     and Kit.mouseY >= y and Kit.mouseY <= y + h
end

function Kit.hover(x, y, w, h)
  return Kit.hit(x, y, w, h)
end

-- Kit hit-tests without a z-order, so an overlay cannot just be drawn last:
-- every widget underneath it would still take the same click.  A modal raises
-- this shield over the layers it covers (App.draw does it around the chrome
-- and the panel while the species picker is up) and lowers it for its own
-- layer (#541).
Kit.blockClicks = false

function Kit.press(x, y, w, h)
  if Kit.blockClicks then return false end
  return Kit.mouseClicked and Kit.hit(x, y, w, h)
end

-- ------------------------------------------------------------------- text
local function font(name)
  return Kit.fonts[name] or Kit.fonts.small
end

function Kit.text(name, str, x, y, c, a)
  if not G then return 0 end
  local f = font(name)
  if not f then return 0 end
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  G.print(tostring(str), x, y)
  return f:getWidth(tostring(str))
end

function Kit.textRight(name, str, x2, y, c, a)
  local f = font(name)
  if not f then return end
  Kit.text(name, str, x2 - f:getWidth(tostring(str)), y, c, a)
end

function Kit.textCenter(name, str, x, y, w, c, a)
  if not G then return end
  local f = font(name)
  if not f then return end
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  if canPrintf() then
    G.printf(tostring(str), x, y, w, "center")
  else
    G.print(tostring(str), x + (w - f:getWidth(tostring(str))) / 2, y)
  end
end

function Kit.textHeight(name)
  local f = font(name)
  return f and f:getHeight() or 12
end

function Kit.textWidth(name, str)
  local f = font(name)
  return f and f:getWidth(tostring(str)) or 0
end

function Kit.ellipsize(name, str, maxW)
  return Theme.ellipsize(font(name), str, maxW)
end

-- 12px / 2px-tracked uppercase section caption -- the design's one and only
-- section header.  Returns the caption's height so callers can stack below.
function Kit.caption(x, y, str, c)
  if not G then return Kit.textHeight("caption") end
  local f = font("caption")
  if not f then return 12 end
  G.setFont(f)
  Theme.col(c or PAL.caption, 1)
  Theme.spaced(f, str, x, y, 2 * Kit.scale)
  return f:getHeight()
end

function Kit.captionWidth(str)
  return Theme.spacedWidth(font("caption"), str, 2 * Kit.scale)
end

-- --------------------------------------------------------------- surfaces
function Kit.card(x, y, w, h, r)
  Theme.card(x, y, w, h, r or 16 * Kit.scale)
end

-- A list row.  `selected` rings it in the accent colour (green for "this is
-- the thing you are editing", blue for "this is the thing you are browsing")
-- instead of filling it, so sprites and HP colours stay readable.  Returns
-- true when the row was clicked this frame.
function Kit.row(x, y, w, h, selected, accent, r)
  r = r or 12 * Kit.scale
  if not G then return Kit.press(x, y, w, h) end
  accent = accent or PAL.green
  if selected then Theme.glow(x, y, w, h, r, accent, 0.45) end
  Theme.row(x, y, w, h, r, 0.6)
  if selected then
    Theme.stroke(x, y, w, h, r, accent, 0.85, 1.5 * Kit.scale)
  end
  return Kit.press(x, y, w, h)
end

function Kit.meter(x, y, w, h, pct, c)
  Theme.meter(x, y, w, h, pct, c)
end

-- Dashed empty-state box with a centred hint.
function Kit.emptyBox(x, y, w, h, message)
  if not G then return end
  Theme.col(PAL.cardBorder, 0.4)
  if G.setLineWidth then G.setLineWidth(math.max(1, 1 * Kit.scale)) end
  Theme.dashed(x, y, w, h, 12 * Kit.scale, 7 * Kit.scale, 5 * Kit.scale)
  if G.setLineWidth then G.setLineWidth(1) end
  local f = font("button")
  if not f then return end
  Kit.textCenter("button", message, x + 12 * Kit.scale,
    y + h / 2 - f:getHeight() / 2, w - 24 * Kit.scale, PAL.muted)
end

-- --------------------------------------------------------------- buttons
-- Button kinds, straight out of the spec's colour semantics:
--   primary  green gradient  -- the single "commit this" control (Save)
--   ghost    glassy white    -- neutral verbs (Reload, Open, Add)
--   accent   blue tint       -- steppers, pagers, in-panel navigation
--   good     green tint      -- safe helpers (Full heal, max a DV)
--   danger   red tint        -- destructive verbs, always two-click
--   disabled steel           -- never hidden, always explained in the status bar
local KINDS = {
  primary  = { fillTop = PAL.green, fillBot = PAL.greenDark, aTop = 1, aBot = 1,
               ink = PAL.greenInk, border = nil, glow = PAL.green },
  ghost    = { fillTop = { 255, 255, 255 }, fillBot = { 255, 255, 255 },
               aTop = 0.14, aBot = 0.03, ink = PAL.heading,
               border = { 255, 255, 255 }, borderA = 0.18 },
  accent   = { flat = PAL.blue, flatA = 0.14, ink = PAL.blueInk,
               border = PAL.cardBorder, borderA = 0.35 },
  good     = { flat = PAL.green, flatA = 0.1, ink = PAL.green,
               border = PAL.green, borderA = 0.45 },
  danger   = { flat = PAL.red, flatA = 0.12, ink = PAL.redSoft,
               border = PAL.red, borderA = 0.45 },
  disabled = { flat = { 120, 132, 158 }, flatA = 0.22, ink = PAL.steel,
               border = PAL.steel, borderA = 0.3 },
}

-- opts: { kind, font, enabled, align, radius, glow }
-- Returns true when clicked (never when disabled).
function Kit.button(x, y, w, h, label, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local kind = KINDS[enabled and (opts.kind or "ghost") or "disabled"]
  local r = opts.radius or 10 * Kit.scale
  local hot = enabled and Kit.hover(x, y, w, h)

  if G then
    if opts.glow and enabled then
      Theme.glow(x, y, w, h, r, kind.glow or PAL.green, opts.glow)
    end
    if kind.flat then
      Theme.col(kind.flat, kind.flatA * (hot and 1.6 or 1))
      G.rectangle("fill", x, y, w, h, r, r)
    else
      Theme.gradRounded(x, y, w, h, r, kind.fillTop, kind.fillBot,
        kind.aTop * (hot and 1.4 or 1), kind.aBot * (hot and 1.6 or 1))
    end
    if kind.border then
      Theme.stroke(x, y, w, h, r, kind.border, kind.borderA * (hot and 1.5 or 1), 1)
    end
    local f = font(opts.font or "button")
    if f then
      G.setFont(f)
      Theme.col(kind.ink, 1)
      local ty = y + (h - f:getHeight()) / 2
      if opts.align == "left" then
        G.print(label, x + 10 * Kit.scale, ty)
      elseif canPrintf() then
        G.printf(label, x, ty, w, "center")
      else
        G.print(label, x + (w - f:getWidth(label)) / 2, ty)
      end
    end
  end
  return enabled and Kit.press(x, y, w, h) or false
end

-- A small square control: the +/- steppers, the arrow cyclers, the row ✕.
function Kit.stepper(x, y, w, h, glyph, opts)
  opts = opts or {}
  opts.kind = opts.kind or "accent"
  opts.font = opts.font or "small"
  opts.radius = opts.radius or 6 * Kit.scale
  return Kit.button(x, y, w, h, glyph, opts)
end

-- A pill toggle (badges, dex SEEN/OWN, event sub-tabs).  `on` colours it;
-- returns true when clicked.
function Kit.chip(x, y, w, h, label, on, onColor, offColor)
  local c = on and (onColor or PAL.green) or (offColor or PAL.steel)
  if G then
    local r = 6 * Kit.scale
    Theme.col(c, on and 0.16 or 0.06)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, PAL.cardBorder, Kit.hover(x, y, w, h) and 0.5 or 0.28, 1)
    Kit.textCenter("micro", label, x, y + (h - Kit.textHeight("micro")) / 2, w,
      c, on and 1 or 0.75)
  end
  return Kit.press(x, y, w, h)
end

-- Checkbox row: a 20px box plus a mono label, the Events grid's unit.
-- Returns (newChecked, changed) so callers can write true/nil on a flip.
function Kit.checkbox(x, y, w, h, checked, label, labelColor)
  local clicked = Kit.row(x, y, w, h, false, nil, 9 * Kit.scale)
  local box = 20 * Kit.scale
  local bx, by = x + 12 * Kit.scale, y + (h - box) / 2
  if G then
    Theme.col(checked and PAL.green or PAL.rowBg, checked and 1 or 0.9)
    G.rectangle("fill", bx, by, box, box, 5 * Kit.scale, 5 * Kit.scale)
    Theme.stroke(bx, by, box, box, 5 * Kit.scale, PAL.cardBorder, 0.4, 1)
    if checked then
      Kit.textCenter("small", "X", bx, by + (box - Kit.textHeight("small")) / 2,
        box, PAL.greenInk)
    end
    local lx = bx + box + 12 * Kit.scale
    Kit.text("mono", Kit.ellipsize("mono", label, x + w - lx - 10 * Kit.scale), lx,
      y + (h - Kit.textHeight("mono")) / 2, labelColor or (checked and PAL.text or PAL.muted))
  end
  if clicked then return not checked, true end
  return checked, false
end

-- --------------------------------------------------------------- text field
-- A real editable field.  The Events filter used to edge-detect love.keyboard
-- state because Kit had no input widget; this replaces that hack, and App
-- routes love.textinput / love.keypressed in through Kit.textinput /
-- Kit.keypressed.  Returns the (possibly edited) value; the caller stores it.
function Kit.textfield(id, x, y, w, h, value, placeholder)
  value = tostring(value or "")
  if Kit.press(x, y, w, h) then Kit.focus = id end
  local focused = (Kit.focus == id)
  if focused then
    -- raise (or hand off) the soft keyboard while this field owns focus (#529)
    syncSoftKeyboard(id, x, y, w, h)
    for _, e in ipairs(edits) do
      if e == "\b" then
        value = value:sub(1, -2)
      elseif e == "\r" then
        Kit.blur()  -- commit/cancel also lowers the soft keyboard (#529)
        focused = false
      else
        value = value .. e
      end
    end
  end
  if G then
    local r = 8 * Kit.scale
    Theme.col(PAL.rowBg, 0.7)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, focused and PAL.blue or PAL.cardBorder,
      focused and 0.8 or 0.3, focused and 1.5 * Kit.scale or 1)
    local pad = 10 * Kit.scale
    local ty = y + (h - Kit.textHeight("mono")) / 2
    if value == "" and not focused then
      Kit.text("mono", placeholder or "", x + pad, ty, PAL.faint)
    else
      local shown = Theme.ellipsizeLeft(font("mono"), value, w - 2 * pad)
      local tw = Kit.text("mono", shown, x + pad, ty, PAL.heading)
      -- caret: blinks only while focused, parked at the end of the text
      if focused and (Kit.time % 1) < 0.55 then
        Theme.col(PAL.blue, 1)
        G.rectangle("fill", x + pad + tw + 2, ty, math.max(1, Kit.scale),
          Kit.textHeight("mono"))
      end
    end
  end
  return value
end

-- ------------------------------------------------------------------ pager
-- Prev / Next / "1-12 of 151".  Drawn even when there is a single page, so a
-- list is never silently truncated (rule 5 of the design spec).  Returns the
-- new offset.
function Kit.pager(x, y, w, offset, total, perPage)
  local h = 30 * Kit.scale
  local bw = 74 * Kit.scale
  local maxOffset = math.max(0, total - perPage)
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.button(x, y, bw, h, "Prev", { kind = "accent", font = "small",
      enabled = offset > 0, radius = 8 * Kit.scale }) then
    offset = math.max(0, offset - perPage)
  end
  if Kit.button(x + bw + 10 * Kit.scale, y, bw, h, "Next", { kind = "accent",
      font = "small", enabled = offset < maxOffset, radius = 8 * Kit.scale }) then
    offset = math.min(maxOffset, offset + perPage)
  end
  local shown = math.min(perPage, math.max(0, total - offset))
  local label = ("%d-%d of %d"):format(total > 0 and offset + 1 or 0,
    offset + shown, total)
  Kit.text("mono", label, x + 2 * bw + 20 * Kit.scale,
    y + (h - Kit.textHeight("mono")) / 2, PAL.caption)
  return offset, h
end

-- ----------------------------------------------------------------- scroll
-- Mouse wheel over a list body (#595): same offset contract as Kit.pager, so
-- a list can carry both and stay on one page counter.  Three rules, all of
-- them consequences of Kit having no z-order:
--   * only the list the pointer is inside takes the notch,
--   * the notch is consumed, so two stacked lists cannot both eat it,
--   * Kit.blockClicks shields it exactly as it shields Kit.press, or the
--     panel under an open species picker would scroll through the modal.
local SCROLL_ROWS = 3

function Kit.scroll(x, y, w, h, offset, total, perPage)
  local maxOffset = math.max(0, (total or 0) - (perPage or 0))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks or (Kit.wheelY or 0) == 0 then return offset end
  if not Kit.hit(x, y, w, h) then return offset end
  -- LOVE reports wheel-up as positive y; up moves the window toward the top
  -- of the list, which is a smaller offset.
  local rows = math.max(1, math.min(SCROLL_ROWS, perPage or SCROLL_ROWS))
  local step = (Kit.wheelY > 0) and -rows or rows
  Kit.wheelY = 0
  return Theme.clamp(offset + step, 0, maxOffset)
end

-- Clip drawing to a rect (list bodies).  No-ops under the headless stub.
function Kit.pushClip(x, y, w, h)
  -- A compact mobile viewport can leave a panel with no room for a list.
  -- LÖVE rejects negative scissor dimensions, so treat an exhausted clip
  -- region as empty instead of passing invalid geometry through to it.
  Kit._clipActive = G and G.setScissor ~= nil
  if Kit._clipActive then
    if w <= 0 or h <= 0 then
      G.setScissor(0, 0, 0, 0)
    else
      G.setScissor(math.floor(x), math.floor(y), math.ceil(w), math.ceil(h))
    end
  end
end

function Kit.popClip()
  if Kit._clipActive and G and G.setScissor then G.setScissor() end
  Kit._clipActive = false
end

return Kit

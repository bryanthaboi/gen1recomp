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
  -- Held-button state is polled, not evented: the editor is hosted both
  -- standalone and inside the launcher, and neither routes mousereleased
  -- here.  Touch drag scrolling (#715) rides this poll, so it works in both
  -- hosts without new plumbing.  The stub has no love.mouse.isDown; a frame
  -- without it simply has no drags.
  local down = false
  if love and love.mouse and love.mouse.isDown then
    down = love.mouse.isDown(1) and true or false
  end
  Kit.mouseDown = down
  if not down then Kit._drag = nil end
  Kit.resetClip()
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
--
-- The #497 answer was to shrink the whole layout down to fit the width
-- (floor 0.62), which #715 showed is its own failure: a small window got a
-- complete but unreadably tiny desktop layout, and the panels still assumed
-- their columns fit.  Shrink-to-fit is gone.  The scale now never dips below
-- 0.9, so text and the 26px tap targets stay readable everywhere, and a
-- narrow window is answered by REFLOW instead: every panel compares its real
-- pixel width against what its columns need (Party/Boxes/Items stack their
-- cards, Dex/Events drop grid columns, the chrome wraps its button row) and
-- whatever no longer fits vertically scrolls through Kit.scroll /
-- Kit.scrollPixels.  The width term survives only to keep a portrait phone
-- from inflating to the 1.6 cap its height alone would buy: 640 real px is
-- the narrowest the single-row chrome fits at scale 1.  Desktop sizes
-- (width >= 640 * height / 768) still land on the height term, so they stay
-- pixel-identical to before.
function Kit.layout(width, height)
  local s = Theme.clamp(math.min(width / 640, height / 768), 0.9, 1.6)
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
-- A widget inside a scrolled clip region can sit at coordinates outside the
-- visible rect (#715: stacked panels scroll in pixels), so the active clip
-- bounds the hit: what the user cannot see cannot take the tap.
function Kit.hit(x, y, w, h)
  local c = Kit._clipRect
  if c and not (Kit.mouseX >= c.x and Kit.mouseX <= c.x + c.w
      and Kit.mouseY >= c.y and Kit.mouseY <= c.y + c.h) then
    return false
  end
  return Kit.mouseX >= x and Kit.mouseX <= x + w
     and Kit.mouseY >= y and Kit.mouseY <= y + h
end

-- ------------------------------------------------------------ layout audit
-- #715 reflow tests: when a test sets Kit.audit to a table, every control
-- that could take a click this frame appends its rect (plus the clip that
-- bounds it), so a window-size sweep can assert that no two controls
-- overlap and none escapes the window.  Shielded widgets are skipped: under
-- a modal they cannot take the tap, and the modal legitimately covers them.
Kit.audit = nil

local function audit(class, x, y, w, h, label)
  local a = Kit.audit
  if not a or Kit.blockClicks then return end
  local c = Kit._clipRect
  a[#a + 1] = { class = class, x = x, y = y, w = w, h = h,
    label = tostring(label or ""),
    clip = c and { x = c.x, y = c.y, w = c.w, h = c.h } or nil }
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
  audit("row", x, y, w, h, "row")
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
  -- disabled buttons audit too: rule 3 keeps them visible, so they still
  -- must not paint over a neighbour (#715)
  audit("control", x, y, w, h, label)
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
  audit("control", x, y, w, h, label)
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
  audit("control", x, y, w, h, id)
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
  -- the counter clips to the width the caller granted: a panel parking a
  -- button on the pager line passes a reduced w and the text yields instead
  -- of running underneath it (#715)
  local labelX = x + 2 * bw + 20 * Kit.scale
  Kit.text("mono", Kit.ellipsize("mono", label, math.max(0, x + w - labelX)),
    labelX, y + (h - Kit.textHeight("mono")) / 2, PAL.caption)
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

-- `step` is optional and exists for grids: a 4-column dex page must move in
-- multiples of 4 or the columns shear.  Lists leave it nil and keep the old
-- behaviour bit for bit (wheel notch = 3 rows, drag = 1 row per row height).
function Kit.scroll(x, y, w, h, offset, total, perPage, step)
  local maxOffset = math.max(0, (total or 0) - (perPage or 0))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks then return offset end

  -- Touch drag (#715): a phone has no wheel and the pagers are small
  -- targets, so a held pointer dragging vertically over the list body
  -- scrolls it.  The drag is keyed to the rect it started in and follows the
  -- pointer even once it leaves, like every native scroll view; the press
  -- frame itself still dispatches as a click, which is the pre-existing
  -- press-on-down contract, so a tap keeps selecting rows.
  local dragStep = math.max(1, step or 1)
  if Kit.mouseDown and maxOffset > 0 and h > 0 and (perPage or 0) > 0 then
    local key = math.floor(x) .. ":" .. math.floor(y)
    local d = Kit._drag
    if not d and Kit.hit(x, y, w, h) then
      Kit._drag = { key = key, startY = Kit.mouseY, base = offset }
    elseif d and d.key == key then
      local visRows = math.max(1, math.floor(perPage / dragStep))
      local rowPx = math.max(1, h / visRows)
      local moved = math.floor((d.startY - Kit.mouseY) / rowPx + 0.5) * dragStep
      offset = Theme.clamp(d.base + moved, 0, maxOffset)
    end
  end

  if (Kit.wheelY or 0) == 0 then return offset end
  if not Kit.hit(x, y, w, h) then return offset end
  -- LOVE reports wheel-up as positive y; up moves the window toward the top
  -- of the list, which is a smaller offset.
  local rows = step or math.max(1, math.min(SCROLL_ROWS, perPage or SCROLL_ROWS))
  local notch = (Kit.wheelY > 0) and -rows or rows
  Kit.wheelY = 0
  return Theme.clamp(offset + notch, 0, maxOffset)
end

-- Pixel-unit sibling of Kit.scroll for a whole stacked card column (#715
-- reflow): `offset` is a pixel offset into `contentH` pixels of laid-out
-- content shown through an `h`-pixel viewport.  Same three rules as
-- Kit.scroll (pointer-inside only, notch consumed, shielded by
-- Kit.blockClicks), same drag contract (a tap still dispatches as a click).
-- Call it AFTER the content so any inner Kit.scroll list gets first claim on
-- a wheel notch or drag that lands over it.
function Kit.scrollPixels(x, y, w, h, offset, contentH)
  local maxOffset = math.max(0, (contentH or 0) - math.max(0, h))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks then return offset end

  if Kit.mouseDown and maxOffset > 0 and h > 0 then
    local key = "px:" .. math.floor(x) .. ":" .. math.floor(y)
    local d = Kit._drag
    if not d and Kit.hit(x, y, w, h) then
      Kit._drag = { key = key, startY = Kit.mouseY, base = offset }
    elseif d and d.key == key then
      offset = Theme.clamp(d.base + (d.startY - Kit.mouseY), 0, maxOffset)
    end
  end

  if (Kit.wheelY or 0) == 0 then return offset end
  if not Kit.hit(x, y, w, h) then return offset end
  local notch = 48 * Kit.scale
  local delta = (Kit.wheelY > 0) and -notch or notch
  Kit.wheelY = 0
  return Theme.clamp(offset + delta, 0, maxOffset)
end

-- Thin overlay scrollbar along the right edge of a list body, drawn after
-- the rows so it stays visible.  Pure indicator (the drag above and the
-- pager are the controls): on a phone the old layout looked "stuck" because
-- nothing said the list continued past the fold (#715).
function Kit.scrollbar(x, y, w, h, offset, total, perPage)
  if not G then return end
  total, perPage = total or 0, perPage or 0
  if total <= perPage or h <= 0 or perPage <= 0 then return end
  local bw = 3 * Kit.scale
  local bx = x + w - bw
  Theme.col(PAL.cardBorder, 0.22)
  G.rectangle("fill", bx, y, bw, h, bw / 2, bw / 2)
  local maxOffset = total - perPage
  local th = math.max(18 * Kit.scale, h * perPage / total)
  local ty = y + (h - th) * (Theme.clamp(offset or 0, 0, maxOffset) / maxOffset)
  Theme.col(PAL.blue, 0.55)
  G.rectangle("fill", bx, ty, bw, th, bw / 2, bw / 2)
end

-- Clip drawing to a rect (list bodies, scrolled cards).  A stack since #715:
-- a stacked panel scrolls its whole column inside one clip and the lists
-- inside it push their own, so pushes nest by intersecting with the rect
-- above and a pop restores that rect rather than clearing the scissor.  The
-- tracked rect also bounds Kit.hit, so a widget scrolled out of view is
-- inert instead of taking taps aimed at whatever is drawn where it left.
-- Under the headless stub the scissor is a no-op but the rect tracking (and
-- so the hit fencing) still runs.
local clipStack = {}

local function applyClip(rect)
  Kit._clipRect = rect
  if not (G and G.setScissor) then return end
  if not rect then
    G.setScissor()
  elseif rect.w <= 0 or rect.h <= 0 then
    -- A compact mobile viewport can leave a panel with no room for a list.
    -- LÖVE rejects negative scissor dimensions, so treat an exhausted clip
    -- region as empty instead of passing invalid geometry through to it.
    G.setScissor(0, 0, 0, 0)
  else
    G.setScissor(math.floor(rect.x), math.floor(rect.y),
      math.ceil(rect.w), math.ceil(rect.h))
  end
end

function Kit.pushClip(x, y, w, h)
  local prev = clipStack[#clipStack]
  local x2, y2 = x + math.max(0, w), y + math.max(0, h)
  if prev then
    x, y = math.max(x, prev.x), math.max(y, prev.y)
    x2 = math.min(x2, prev.x + prev.w)
    y2 = math.min(y2, prev.y + prev.h)
  end
  local rect = { x = x, y = y, w = math.max(0, x2 - x), h = math.max(0, y2 - y) }
  clipStack[#clipStack + 1] = rect
  applyClip(rect)
end

function Kit.popClip()
  clipStack[#clipStack] = nil
  applyClip(clipStack[#clipStack])
end

-- A pcall-ed draw that raised mid-clip must not leak the stack into later
-- frames (every hit test would stay fenced to the dead rect), so the frame
-- boundary clears it.
function Kit.resetClip()
  for i = #clipStack, 1, -1 do clipStack[i] = nil end
  applyClip(nil)
end

return Kit

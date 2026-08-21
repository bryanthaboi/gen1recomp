-- Immediate-mode widget kit shared by the launcher and the save editor.
--
-- This is the replacement for the vendored FlexLove tree that the launcher
-- used to rebuild every frame.  The contract that mattered there is kept --
-- the UI is rebuilt from owner state each frame, so it can never drift --
-- but without a retained element tree, per-element id hashing, or a
-- property snapshot pass.  Measured effect on the launcher's build+draw:
-- ~9.2ms/frame down to well under 1ms (see POKEPORT_LAUNCHER_PROF).
--
-- Usage, once per love.draw():
--     Kit.layout(w, h)                     -- fonts + scale, only on resize
--     Kit.beginFrame(mx, my, clicked, wheel)
--     ... widgets ...
--     Kit.endFrame()
--
-- WHY IT IS FAST (the rules any new widget must follow):
--  1. No allocation in the steady state.  Widgets take and return scalars;
--     the per-frame tables that do exist (nav list, audit) are reused and
--     truncated, never rebuilt.  LuaJIT's GC is the difference between a
--     6ms frame and a 0.6ms one when a list has 200 rows.
--  2. Text is cached as love.graphics.Text objects keyed by font+string
--     (Kit.text).  G.print re-shapes the string every call; a Text object
--     shapes once and then costs one batched draw.  Colour is applied at
--     draw time, which does NOT break the batch -- switching FONTS does,
--     which is the other reason the cache pays.
--  3. Measurement (font:getWidth, ellipsize) is memoised per font+string.
--     Ellipsising is O(glyphs) with a getWidth per step and list rows do it
--     for every visible cell, every frame, on strings that never change.
--  4. Lists PAGINATE.  Row count is bounded by the page size, so a 500-mod
--     index costs exactly what a 10-mod one does.  There is no virtualised
--     scroller and no momentum integrator to run.
--  5. Draw flat.  No stencil, no mesh, no canvas, no shader, no blend-mode
--     change -- every one is a pipeline flush.  Rounded corners, the emboss
--     and a card's drop shadow are allowed because they only add VERTICES at
--     the same pipeline state (see Theme.lua's header for the full rule).
--
-- ACCESSIBILITY / INPUT: every control is reachable four ways -- mouse,
-- touch (>= 30px targets), keyboard (spatial focus ring, arrows + Enter),
-- and gamepad (the same ring, driven by the d-pad, plus a virtual cursor).
-- Hit testing is a plain rect with no z-order, so overlapping layers must be
-- drawn in dispatch order and a modal raises Kit.blockClicks over what it
-- covers.

local Theme = require("src.ui.kit.Theme")
local PAL = Theme.PAL

local Kit = {}
Kit.Theme = Theme
Kit.PAL = PAL

Kit.mouseX, Kit.mouseY = 0, 0
Kit.mouseClicked = false   -- left button pressed this frame
Kit.mouseDown = false      -- held, polled (drag / press-and-hold)
Kit.wheelY = 0             -- wheel notches queued since the last frame
Kit.focus = nil            -- id of the text field receiving keystrokes
Kit.focusId = nil          -- id of the keyboard/gamepad focus ring target
Kit.time = 0
Kit.fonts = {}
Kit.scale = 1
Kit.blockClicks = false
Kit.audit = nil

local G = love and love.graphics or nil
local edits = {}           -- queued textinput / backspace since the last frame
local kbField = nil        -- id of the field the soft keyboard is raised for

local function has(name)
  return Theme.probe(name)
end

-- ------------------------------------------------------------ soft keyboard
-- Mobile LOVE only delivers love.textinput while setTextInput(true) is
-- active, and that call is what raises the Android/iOS soft keyboard; the
-- rect keeps the focused field visible above it.  setTextInput is global SDL
-- state, not per-widget, so desktop text input is never turned off (#529).
local function mobile()
  local osName = love and love.system and love.system.getOS
    and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end
Kit.isMobile = mobile

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

-- ------------------------------------------------------------- text caching
-- Two caches, both keyed by font name + string, both cleared wholesale when
-- the font set is rebuilt (a resize).  A wholesale clear is correct and
-- cheap: an LRU would cost more bookkeeping per lookup than it saves, and
-- the working set of a UI is small and stable between resizes.
local textCache, textCacheN = {}, 0
local widthCache = {}
local ellipsisCache = {}
local CACHE_MAX = 1024

local wrapCacheRef  -- forward declaration; the table is defined below
local function clearCaches()
  textCache, textCacheN = {}, 0
  widthCache = {}
  ellipsisCache = {}
  if wrapCacheRef then
    for k in pairs(wrapCacheRef) do wrapCacheRef[k] = nil end
  end
end
Kit.clearCaches = clearCaches

local function font(name)
  return Kit.fonts[name] or Kit.fonts.small
end
Kit.font = font

-- Rebuild the font set when the window size changes.  The scale never dips
-- below 0.9 so text and the 30px tap targets stay readable on a phone; a
-- narrow window is answered by REFLOW (see Layout.lua), never by shrinking.
-- Global size multiplier.  Everything in the UI derives from Kit.scale, so
-- one factor here moves text, tap targets, padding and row heights together
-- and nothing drifts out of proportion.  1.3 because the launcher is read at
-- couch distance as often as at desk distance, and the old sizing was tuned
-- for the latter only.
local UI_SCALE = 1.3

function Kit.layout(width, height)
  local s = Theme.clamp(math.min(width / 640, height / 768), 0.9, 1.6) * UI_SCALE
  -- Two numbers, not a formatted key: this runs once per frame and the
  -- string:format allocated on every one of them.
  local kw, kh = math.floor(width), math.floor(height)
  if Kit._fontW ~= kw or Kit._fontH ~= kh then
    Kit._fontW, Kit._fontH = kw, kh
    Kit.fonts = Theme.fonts(s)
    clearCaches()   -- every cached Text/width belongs to the old font set
  end
  Kit.scale = s
  Kit.width, Kit.height = width, height
  return s
end

function Kit.textWidth(name, str)
  str = tostring(str)
  local key = name .. "\0" .. str
  local w = widthCache[key]
  if w then return w end
  local f = font(name)
  -- Never let a malformed string (a mod name from a third-party index) throw
  -- out of a measurement: an unmeasurable string is treated as zero-width and
  -- the ellipsis logic clips it away.
  if f then
    local ok, got = pcall(f.getWidth, f, str)
    w = ok and got or 0
  else
    w = 0
  end
  widthCache[key] = w
  return w
end

function Kit.textHeight(name)
  local f = font(name)
  return f and f:getHeight() or 12
end

function Kit.ellipsize(name, str, maxW)
  str = tostring(str or "")
  local key = name .. "\0" .. math.floor(maxW) .. "\0" .. str
  local c = ellipsisCache[key]
  if c then return c end
  c = Theme.ellipsize(font(name), str, maxW)
  ellipsisCache[key] = c
  return c
end

function Kit.ellipsizeLeft(name, str, maxW)
  str = tostring(str or "")
  local key = name .. "\1" .. math.floor(maxW) .. "\0" .. str
  local c = ellipsisCache[key]
  if c then return c end
  c = Theme.ellipsizeLeft(font(name), str, maxW)
  ellipsisCache[key] = c
  return c
end

-- A cached, pre-shaped Text object.  Falls back to G.print under a stub or
-- when the cache is saturated.
local function textObject(name, str)
  if not (G and has("newText")) then return nil end
  local key = name .. "\0" .. str
  local t = textCache[key]
  if t then return t end
  if textCacheN >= CACHE_MAX then clearCaches() end
  local f = font(name)
  if not f then return nil end
  local ok, obj = pcall(G.newText, f, str)
  if not ok then return nil end
  textCache[key] = obj
  textCacheN = textCacheN + 1
  return obj
end

-- Bold text: the same cached run drawn twice, one pixel apart.  The UI face
-- has a single weight, so this is the only way to get emphasis without
-- shipping a second font -- and it keeps the measurement identical, which
-- matters because every layout here is measured, not flowed.
function Kit.textBold(name, str, x, y, c, a)
  local w = Kit.text(name, str, x, y, c, a)
  Kit.text(name, str, x + Theme.BOLD_OFFSET, y, c, a)
  return w
end

function Kit.textCenterBold(name, str, x, y, w, c, a)
  local tw = Kit.textWidth(name, tostring(str))
  return Kit.textBold(name, str, x + (w - tw) / 2, y, c, a)
end

-- Draw a string.  Returns its width, so callers can lay out inline runs
-- without a second measurement.
function Kit.text(name, str, x, y, c, a)
  if not G then return 0 end
  str = tostring(str)
  Theme.col(c or PAL.text, a or 1)
  local obj = textObject(name, str)
  if obj then
    G.draw(obj, Theme.snap(x), Theme.snap(y))
  else
    local f = font(name)
    if not f then return 0 end
    G.setFont(f)
    -- Same guard as the measurement path: a string LOVE cannot shape must
    -- not take the whole frame down with it.
    pcall(G.print, str, Theme.snap(x), Theme.snap(y))
  end
  return Kit.textWidth(name, str)
end

function Kit.textRight(name, str, x2, y, c, a)
  return Kit.text(name, str, x2 - Kit.textWidth(name, tostring(str)), y, c, a)
end

function Kit.textCenter(name, str, x, y, w, c, a)
  return Kit.text(name, str, x + (w - Kit.textWidth(name, tostring(str))) / 2,
    y, c, a)
end

-- Word-wrapped text.  Font:getWrap re-shapes the whole string every call and
-- list rows ask for the same (font, width, string) every frame, so the line
-- split is memoised alongside the other measurement caches.  `maxLines`
-- truncates with an ellipsis rather than overflowing the box the caller
-- reserved -- an immediate-mode layout has no way to grow after the fact.
local wrapCache = {}
wrapCacheRef = wrapCache

function Kit.wrapLines(name, str, w)
  str = tostring(str or "")
  if str == "" or w <= 0 then return nil end
  local key = name .. "\0" .. math.floor(w) .. "\0" .. str
  local lines = wrapCache[key]
  if lines then return lines end
  local f = font(name)
  if not f then return nil end
  local ok, _, wrapped = pcall(f.getWrap, f, str, w)
  lines = (ok and wrapped) or { str }
  wrapCache[key] = lines
  return lines
end

-- Returns the height consumed.
function Kit.textWrapped(name, str, x, y, w, c, maxLines, a)
  local lines = Kit.wrapLines(name, str, w)
  if not lines then return 0 end
  local lh = Kit.textHeight(name)
  local n = #lines
  if maxLines and n > maxLines then n = maxLines end
  for i = 1, n do
    local line = lines[i]
    if maxLines and i == maxLines and #lines > maxLines then
      line = Kit.ellipsize(name, line .. "...", w)
    end
    Kit.text(name, line, x, y + (i - 1) * lh, c, a)
  end
  return n * lh
end

-- Height a wrapped run will need, without drawing it.  Panels call this to
-- reserve space before laying the block out.
function Kit.wrapHeight(name, str, w, maxLines)
  local lines = Kit.wrapLines(name, str, w)
  if not lines then return 0 end
  local n = #lines
  if maxLines and n > maxLines then n = maxLines end
  return n * Kit.textHeight(name)
end

-- 12px / 2px-tracked uppercase section caption -- the design's one and only
-- section header.  Returns its height so callers can stack below.
function Kit.caption(x, y, str, c)
  if not G then return Kit.textHeight("caption") end
  local f = font("caption")
  if not f then return 12 end
  G.setFont(f)
  Theme.col(c or PAL.caption, 1)
  Theme.spaced(f, str, Theme.snap(x), Theme.snap(y), 2 * Kit.scale)
  return f:getHeight()
end

function Kit.captionWidth(str)
  return Theme.spacedWidth(font("caption"), str, 2 * Kit.scale)
end

-- ------------------------------------------------------------- frame cycle
function Kit.beginFrame(mx, my, clicked, wheel)
  Kit.mouseX, Kit.mouseY = mx or 0, my or 0
  Kit.mouseClicked = clicked and true or false
  Kit.wheelY = wheel or 0
  local down = false
  if love and love.mouse and love.mouse.isDown then
    down = love.mouse.isDown(1) and true or false
  end
  Kit.mouseDown = down
  if not down then Kit._drag = nil end
  Kit.resetClip()
  Kit.blockClicks = false
  if love and love.timer and love.timer.getTime then
    Kit.time = love.timer.getTime()
  end
  -- Resolve any queued focus-ring movement against LAST frame's geometry.
  -- Immediate mode has no geometry until the frame is built, and the ring
  -- must move before widgets test themselves against it.
  Kit._resolveNav()
  -- Start collecting this frame's focusables.
  Kit._navN = 0
end

-- Retire this frame's keystrokes, wheel notches and one-shot activations.
-- Anything typed while no field had focus is dropped here rather than
-- replayed into the next field that gets clicked.
function Kit.endFrame()
  for i = #edits, 1, -1 do edits[i] = nil end
  Kit.wheelY = 0
  Kit._activateId = nil
  -- This frame's focusables become next frame's navigation graph.
  local n = Kit._navN or 0
  Kit._navPrevN = n
  -- If the focused id vanished (panel switch, list repaged), park the ring
  -- on the first focusable so the keyboard is never stranded.
  if Kit.focusId and not Kit._navSeen[Kit.focusId] and n > 0 then
    Kit.focusId = Kit._nav[1] and Kit._nav[1].id or nil
  end
  for k in pairs(Kit._navSeen) do Kit._navSeen[k] = nil end
end

-- ------------------------------------------------------------ focus ring
-- Spatial navigation.  Every focusable control registers its rect as it
-- draws; a queued direction picks the nearest candidate in that direction
-- from the previous frame's set.  Spatial rather than index-order because
-- the launcher is a multi-column layout: tab-order would zigzag between
-- columns, while "press right, go right" is what both a keyboard and a
-- d-pad user expects.
Kit._nav = {}
Kit._navN = 0
Kit._navPrevN = 0
Kit._navSeen = {}
Kit._navQueue = nil
Kit._activateId = nil
Kit._ringShown = false

-- Register a focusable.  Returns true when it currently holds the ring.
-- Shielded widgets do not register: while a modal owns the frame the ring
-- must not wander through (or Enter-activate) the controls underneath it.
function Kit.focusable(id, x, y, w, h)
  if Kit.blockClicks then return false end
  local n = (Kit._navN or 0) + 1
  Kit._navN = n
  local slot = Kit._nav[n]
  if not slot then slot = {}; Kit._nav[n] = slot end
  slot.id, slot.x, slot.y, slot.w, slot.h = id, x, y, w, h
  Kit._navSeen[id] = true
  -- First focusable ever drawn adopts the ring, so keyboard users start
  -- somewhere rather than nowhere.
  if Kit.focusId == nil then Kit.focusId = id end
  return Kit._ringShown and Kit.focusId == id
end

function Kit.navigate(dir)
  Kit._navQueue = dir
  Kit._ringShown = true
end

function Kit.activateFocused()
  if Kit.focusId then Kit._activateId = Kit.focusId end
end

function Kit.setFocus(id)
  Kit.focusId = id
  Kit._ringShown = id ~= nil
end

-- Pick the nearest focusable in `dir` from the current one.  Candidates must
-- lie in the half-plane of the direction; the score prefers a small step
-- along the axis of travel and penalises drift across it, which keeps a
-- column walk inside its column.
function Kit._resolveNav()
  local dir = Kit._navQueue
  Kit._navQueue = nil
  local n = Kit._navPrevN or 0
  if not dir or n == 0 then return end
  local cur
  for i = 1, n do
    if Kit._nav[i].id == Kit.focusId then cur = Kit._nav[i] break end
  end
  if not cur then
    Kit.focusId = Kit._nav[1].id
    return
  end
  local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
  local best, bestScore
  for i = 1, n do
    local c = Kit._nav[i]
    if c.id ~= cur.id then
      local dx = (c.x + c.w / 2) - cx
      local dy = (c.y + c.h / 2) - cy
      local along, across
      if dir == "left" then along, across = -dx, math.abs(dy)
      elseif dir == "right" then along, across = dx, math.abs(dy)
      elseif dir == "up" then along, across = -dy, math.abs(dx)
      else along, across = dy, math.abs(dx) end
      -- A control merely overlapping on the travel axis is not "in that
      -- direction"; require real separation so a tall row's neighbours do
      -- not all qualify.
      if along > 1 then
        local score = along + across * 2
        if not bestScore or score < bestScore then best, bestScore = c, score end
      end
    end
  end
  if best then Kit.focusId = best.id end
end

-- ------------------------------------------------------------ input plumbing
function Kit.textinput(text)
  if not Kit.focus then return false end
  edits[#edits + 1] = text
  return true
end

-- Returns true when the key was consumed, so the host can leave its own
-- shortcuts alone while the user is typing or driving the ring.
function Kit.keypressed(key)
  if Kit.focus then
    if key == "backspace" then edits[#edits + 1] = "\b" return true
    elseif key == "return" or key == "kpenter" or key == "escape" then
      edits[#edits + 1] = "\r" return true
    end
    -- printable keys arrive through textinput; everything else falls through
    return false
  end
  if key == "up" or key == "down" or key == "left" or key == "right" then
    Kit.navigate(key)
    return true
  elseif key == "return" or key == "kpenter" or key == "space" then
    Kit.activateFocused()
    return true
  end
  return false
end

-- Gamepad d-pad / stick, routed by the host's pad handling.
function Kit.gamepadpressed(button)
  if button == "dpup" then Kit.navigate("up") return true
  elseif button == "dpdown" then Kit.navigate("down") return true
  elseif button == "dpleft" then Kit.navigate("left") return true
  elseif button == "dpright" then Kit.navigate("right") return true
  elseif button == "a" then Kit.activateFocused() return true end
  return false
end

function Kit.blur()
  Kit.focus = nil
  syncSoftKeyboard(nil)
end

-- -------------------------------------------------------------- hit testing
-- A widget inside a clip region can sit at coordinates outside the visible
-- rect, so the active clip bounds the hit: what the user cannot see cannot
-- take the tap.
function Kit.hit(x, y, w, h)
  local c = Kit._clipRect
  if c and not (Kit.mouseX >= c.x and Kit.mouseX <= c.x + c.w
      and Kit.mouseY >= c.y and Kit.mouseY <= c.y + c.h) then
    return false
  end
  return Kit.mouseX >= x and Kit.mouseX <= x + w
     and Kit.mouseY >= y and Kit.mouseY <= y + h
end

function Kit.hover(x, y, w, h)
  -- Shielded widgets (drawn while a modal owns the frame) must not glow
  -- either: a hover highlight under the scrim reads as "still clickable".
  if Kit.blockClicks then return false end
  return Kit.hit(x, y, w, h)
end

function Kit.press(x, y, w, h)
  if Kit.blockClicks then return false end
  return Kit.mouseClicked and Kit.hit(x, y, w, h)
end

-- Layout audit: when a test sets Kit.audit to a table, every control that
-- could take a click this frame appends its rect (plus the clip that bounds
-- it), so a window-size sweep can assert no two controls overlap and none
-- escapes the window.  Shielded widgets are skipped: under a modal they
-- cannot take the tap, and the modal legitimately covers them.
local function audit(class, x, y, w, h, label)
  local a = Kit.audit
  if not a or Kit.blockClicks then return end
  local c = Kit._clipRect
  a[#a + 1] = { class = class, x = x, y = y, w = w, h = h,
    label = tostring(label or ""),
    clip = c and { x = c.x, y = c.y, w = c.w, h = c.h } or nil }
end
Kit._audit = audit

-- ------------------------------------------------------------------ metrics
-- Minimum tap target.  30px at scale 1 (up from the editor's 26) because the
-- launcher is the first thing a phone user touches and these are the only
-- controls that matter.
function Kit.tapMin() return math.floor(30 * Kit.scale) end

-- ---------------------------------------------------------------- surfaces
function Kit.card(x, y, w, h, variant)
  Theme.card(x, y, w, h, variant)
end

function Kit.row(x, y, w, h, selected, id)
  audit("row", x, y, w, h, id or "row")
  local focused = id and Kit.focusable(id, x, y, w, h) or false
  local hot = Kit.hover(x, y, w, h)
  local state = selected and "selected" or (hot and "hover" or nil)
  local ink = Theme.row(x, y, w, h, state)
  -- The focus ring is a second inset outline, so it reads on both a black
  -- row and a white selected one.
  if focused then
    Theme.strokeRounded(x + 2, y + 2, w - 4, h - 4,
      selected and PAL.inverse or PAL.lineStrong, Theme.A.focus, 1,
      Theme.radius())
  end
  local clicked = Kit.press(x, y, w, h)
    or (id ~= nil and Kit._activateId == id)
  return clicked, ink
end

-- Empty-state box: hairline outline and a centred hint.  (The old dashed
-- border sampled a rounded path into a polyline every frame; a solid
-- hairline says the same thing for one rect.)
function Kit.emptyBox(x, y, w, h, message)
  if not G then return end
  Theme.card(x, y, w, h, "empty")
  Kit.textCenter("button", Kit.ellipsize("button", message, w - 24 * Kit.scale),
    x, y + (h - Kit.textHeight("button")) / 2, w, PAL.muted)
end

-- ----------------------------------------------------------------- buttons
-- Button kinds.  In a black/white theme the semantics live in the OUTLINE
-- and INK colour; the fill is black until the control is hot or focused, at
-- which point it inverts to a solid fill with dark ink.  That inversion is
-- the single strongest contrast signal available and costs one rect.
-- `solid` means the control is filled even at rest: reserved for the single
-- most important action on a screen (Play), which should not have to be
-- hovered before it looks like the answer.
-- Buttons are COLOUR-CODED by what they do, so a control's job is readable
-- before its label is.  The button IS the colour: a solid fill with black
-- ink, not an outline with coloured text.  Against a black field a filled
-- chip is the strongest, fastest-to-scan signal available, and every accent
-- in this palette is high-luminance, so black ink on it clears contrast
-- requirements comfortably.
--   primary   green    -- the commit action (Play, Save, Install)
--   good      green    -- safe helpers
--   accent    blue     -- navigation / information (Details, Edit, Import)
--   warn      yellow   -- attention (an update is waiting)
--   danger    red      -- destructive, always two-press
--   ghost     white    -- neutral verbs with no better colour
--   disabled  grey     -- never hidden, always still readable
-- Hover/focus is a white ring around the fill (plus a slight lift), which
-- reads on every colour without needing a second shade of each.
local KINDS = {
  primary  = { fill = PAL.green,  ink = PAL.inverse },
  good     = { fill = PAL.green,  ink = PAL.inverse },
  accent   = { fill = PAL.blue,   ink = PAL.inverse },
  warn     = { fill = PAL.yellow, ink = PAL.inverse },
  danger   = { fill = PAL.red,    ink = PAL.inverse },
  ghost    = { fill = PAL.ink,    ink = PAL.inverse },
  disabled = { fill = PAL.steel,  ink = PAL.inverse, flat = true },
}
Kit.KINDS = KINDS
local NO_OPTS = {}

function Kit.button(x, y, w, h, label, opts)
  opts = opts or NO_OPTS
  local enabled = opts.enabled ~= false
  audit("control", x, y, w, h, label)
  local focused = enabled and opts.id
    and Kit.focusable(opts.id, x, y, w, h) or false
  local hot = enabled and Kit.hover(x, y, w, h)
  local face = opts.face or "fill"
  local B = Theme.BUTTON
  local radius = opts.radius or B.radius
  local active = opts.active or opts.on
  local invert = false
  local fill, ink, stroke, strokeA, doEmboss, doRing, glowA
  if face == "invert" then
    invert = hot
    fill = invert and (opts.hotFill or PAL.ink) or (opts.fill or PAL.surface)
    ink = invert and (opts.hotInk or PAL.inverse) or (opts.ink or PAL.heading)
    stroke = opts.stroke or PAL.line
    strokeA = invert and Theme.A.focus or Theme.A.hairline
    doRing = focused and not hot
  elseif face == "tab" then
    invert = active or focused or hot
    local tint = opts.color or opts.fill or PAL.ink
    fill = invert and tint or PAL.surface
    ink = invert and PAL.inverse or (opts.color or PAL.text)
    if not invert then
      stroke = tint
      strokeA = opts.color and Theme.A.hover or Theme.A.hairline
    end
  elseif face == "chip" then
    local c = opts.color or PAL.line
    invert = active and true or false
    if active then
      fill = c
      ink = PAL.inverse
      doEmboss = true
    else
      fill = PAL.bg
      ink = c
      stroke = c
      strokeA = (focused or hot) and Theme.A.focus or Theme.A.hover
    end
    doRing = focused or hot
  else
    local kind = KINDS[enabled and (opts.kind or "ghost") or "disabled"]
    fill = (enabled and opts.fill) or kind.fill
    ink = (enabled and opts.ink) or kind.ink
    doEmboss = true
    doRing = hot or focused
    if opts.glow and enabled and not doRing then
      glowA = B.glowBase + B.glowAmp * (0.5 + 0.5 * math.sin(Kit.time * B.glowHz))
    end
  end
  if opts.emboss ~= nil then doEmboss = opts.emboss end
  if opts.ring ~= nil then doRing = opts.ring end
  if G then
    Theme.fillRounded(x, y, w, h, fill, enabled and 1 or B.disabledA, radius)
    if doEmboss then
      local es = enabled and ((hot or focused) and B.embossHot or B.embossRest)
        or B.embossDisabled
      Theme.emboss(x, y, w, h, es)
    end
    if strokeA then
      Theme.strokeRounded(x, y, w, h, stroke, strokeA, 1, radius)
    end
    if doRing then
      Theme.strokeRounded(x - B.ringPad, y - B.ringPad,
        w + 2 * B.ringPad, h + 2 * B.ringPad, PAL.lineStrong,
        Theme.A.focus, B.ringWidth, radius + B.ringPad)
    elseif glowA then
      Theme.strokeRounded(x - B.ringPad, y - B.ringPad,
        w + 2 * B.ringPad, h + 2 * B.ringPad, PAL.lineStrong,
        glowA, B.ringWidth, radius + B.ringPad)
    end
    local fname = opts.font or ((face == "chip") and "micro" or "button")
    local ty = y + (h - Kit.textHeight(fname)) / 2
    local image = opts.image
    local drawFn = opts.drawFn
    local letter = opts.letter
    local hasLabel = label and label ~= ""
    local bold = opts.bold
    if bold == nil then bold = face ~= "tab" end
    if image then
      local box = h
      local boxX, boxY = x, y
      if not hasLabel then
        box = math.min(w, h)
        boxX = x + (w - box) / 2
        boxY = y + (h - box) / 2
      end
      local iw, ih = image:getDimensions()
      local pad = math.floor(box * (opts.iconPad or B.iconPad))
      local s = math.min((box - 2 * pad) / iw, (box - 2 * pad) / ih)
      if invert then Theme.col(PAL.inverse, 1)
      else Theme.col(PAL.ink, B.iconRestA) end
      G.draw(image, Theme.snap(boxX + (box - iw * s) / 2),
        Theme.snap(boxY + (box - ih * s) / 2), 0, s, s)
      if hasLabel then
        local lx = x + h + B.letterGap * Kit.scale
        if bold then Kit.textBold(fname, label, lx, ty, ink)
        else Kit.text(fname, label, lx, ty, ink) end
      end
    elseif drawFn then
      drawFn(x, y, w, h, invert or hot or focused)
    elseif letter then
      Kit.textCenter(fname, letter, x, ty, h, ink)
      if hasLabel then
        local lx = x + h + B.letterGap * Kit.scale
        if bold then Kit.textBold(fname, label, lx, ty, ink)
        else Kit.text(fname, label, lx, ty, ink) end
      end
    elseif hasLabel then
      local shown = Kit.ellipsize(fname, label, w - B.labelInset * Kit.scale)
      if opts.align == "left" then
        local lx = x + B.labelPad * Kit.scale
        if bold then Kit.textBold(fname, shown, lx, ty, ink)
        else Kit.text(fname, shown, lx, ty, ink) end
      elseif bold then
        Kit.textCenterBold(fname, shown, x, ty, w, ink)
      else
        Kit.textCenter(fname, shown, x, ty, w, ink)
      end
    end
  end
  if not enabled then return false end
  return Kit.press(x, y, w, h)
    or (not Kit.blockClicks and opts.id ~= nil
      and Kit._activateId == opts.id)
end

function Kit.stepper(x, y, w, h, glyph, opts)
  opts = opts or {}
  opts.kind = opts.kind or "ghost"
  opts.font = opts.font or "small"
  return Kit.button(x, y, w, h, glyph, opts)
end

local CHIP_OPTS = { face = "chip", font = "micro" }

function Kit.chip(x, y, w, h, label, on, color, id)
  CHIP_OPTS.active = on
  CHIP_OPTS.color = color
  CHIP_OPTS.id = id
  return Kit.button(x, y, w, h, label, CHIP_OPTS)
end

-- A status label with no interaction: outlined text, the "INSTALLED"/"UPDATE"
-- markers on mod rows.
function Kit.tag(x, y, w, h, label, color)
  if not G then return end
  Theme.strokeRounded(x, y, w, h, color or PAL.line, 0.7, 1)
  Kit.textCenter("micro", label, x, y + (h - Kit.textHeight("micro")) / 2, w,
    color or PAL.muted)
end

-- Checkbox row.  Returns (newChecked, changed).
function Kit.checkbox(x, y, w, h, checked, label, id, labelColor)
  local clicked, ink = Kit.row(x, y, w, h, false, id)
  local box = 20 * Kit.scale
  local bx, by = x + 12 * Kit.scale, y + (h - box) / 2
  if G then
    local br = math.min(Theme.radius(), box / 3)
    if checked then
      Theme.fillRounded(bx, by, box, box, PAL.ink, 1, br)
      Kit.textCenter("small", "X", bx,
        by + (box - Kit.textHeight("small")) / 2, box, PAL.inverse)
    else
      Theme.strokeRounded(bx, by, box, box, PAL.line, Theme.A.hover, 1, br)
    end
    local lx = bx + box + 12 * Kit.scale
    Kit.text("mono", Kit.ellipsize("mono", label, x + w - lx - 10 * Kit.scale),
      lx, y + (h - Kit.textHeight("mono")) / 2,
      labelColor or ink or PAL.text)
  end
  if clicked then return not checked, true end
  return checked, false
end

-- A two-state switch, for the settings ladders.
function Kit.toggle(x, y, w, h, on, id)
  audit("control", x, y, w, h, "toggle")
  local focused = id and Kit.focusable(id, x, y, w, h) or false
  if G then
    -- Track, then a knob inset inside it, so the control reads as a switch
    -- rather than as a white square with a word next to it.  The label sits
    -- in the empty half, which is the half that says what pressing does.
    local r = math.min(Theme.radius(), h / 2)
    Theme.fillRounded(x, y, w, h, PAL.rowBg, 1, r)
    Theme.strokeRounded(x, y, w, h, PAL.line,
      (focused or Kit.hover(x, y, w, h)) and Theme.A.focus or Theme.A.hover, 1, r)
    local inset = 3
    local knob = w / 2 - inset
    Theme.fillRounded(on and (x + w / 2) or (x + inset), y + inset, knob,
      h - 2 * inset, PAL.ink, 1, math.min(r, (h - 2 * inset) / 2))
    Kit.textCenter("micro", on and "ON" or "OFF",
      on and x or (x + w / 2), y + (h - Kit.textHeight("micro")) / 2, w / 2,
      PAL.text)
  end
  local hitTaken = Kit.press(x, y, w, h) or (id ~= nil and Kit._activateId == id)
  if hitTaken then return not on, true end
  return on, false
end

-- A determinate progress bar with an optional caption.
function Kit.progress(x, y, w, h, frac, label)
  Theme.meter(x, y, w, h, (frac or 0) * 100, PAL.ink)
  if label then
    Kit.text("micro", label, x, y + h + 4 * Kit.scale, PAL.muted)
  end
end

-- --------------------------------------------------------------- text field
function Kit.textfield(id, x, y, w, h, value, placeholder)
  audit("control", x, y, w, h, id)
  local focusRing = Kit.focusable(id, x, y, w, h)
  value = tostring(value or "")
  if Kit.press(x, y, w, h) or (Kit._activateId == id) then Kit.focus = id end
  local focused = (Kit.focus == id)
  if focused then
    syncSoftKeyboard(id, x, y, w, h)
    for _, e in ipairs(edits) do
      if e == "\b" then
        value = value:sub(1, -2)
      elseif e == "\r" then
        Kit.blur()
        focused = false
      else
        value = value .. e
      end
    end
  end
  if G then
    Theme.fillRounded(x, y, w, h, PAL.bg, 1)
    Theme.strokeRounded(x, y, w, h, PAL.line,
      (focused or focusRing) and Theme.A.focus or Theme.A.hairline,
      focused and 2 or 1)
    local pad = 10 * Kit.scale
    local ty = y + (h - Kit.textHeight("mono")) / 2
    if value == "" and not focused then
      Kit.text("mono", placeholder or "", x + pad, ty, PAL.faint)
    else
      local shown = Kit.ellipsizeLeft("mono", value, w - 2 * pad)
      local tw = Kit.text("mono", shown, x + pad, ty, PAL.heading)
      if focused and (Kit.time % 1) < 0.55 then
        Theme.fill(x + pad + tw + 2, ty, math.max(1, Kit.scale),
          Kit.textHeight("mono"), PAL.ink, 1)
      end
    end
  end
  return value
end

-- -------------------------------------------------------------------- pager
-- Prev / Next / "1-12 of 151".  Drawn even for a single page, so a list is
-- never silently truncated.  A long list still PAGES rather than scrolling:
-- no momentum, bounded row count per frame.
-- Returns the new page (1-based) and the row height consumed.
local pagerLabels = {}

function Kit.pager(x, y, w, page, total, perPage, idPrefix)
  local h = math.max(Kit.tapMin(), 30 * Kit.scale)
  local bw = 74 * Kit.scale
  local pages = math.max(1, math.ceil(total / math.max(1, perPage)))
  page = math.floor(Theme.clamp(page or 1, 1, pages))
  local gap = 8 * Kit.scale
  idPrefix = idPrefix or "pager"

  if Kit.button(x, y, bw, h, "< Prev", { kind = "ghost", font = "small",
      enabled = page > 1, id = idPrefix .. ":prev" }) then
    page = math.max(1, page - 1)
  end
  if Kit.button(x + bw + gap, y, bw, h, "Next >", { kind = "ghost",
      font = "small", enabled = page < pages, id = idPrefix .. ":next" }) then
    page = math.min(pages, page + 1)
  end

  local first = total > 0 and ((page - 1) * perPage + 1) or 0
  local last = math.min(total, page * perPage)
  -- One memo per pager id.  The counts only change when the user pages or the
  -- list does; formatting them every frame minted a new string that then
  -- missed the width / ellipsis / Text caches by content.
  local memo = pagerLabels[idPrefix]
  if not memo then memo = {}; pagerLabels[idPrefix] = memo end
  if memo.first ~= first or memo.last ~= last or memo.total ~= total
      or memo.page ~= page or memo.pages ~= pages then
    memo.first, memo.last, memo.total = first, last, total
    memo.page, memo.pages = page, pages
    memo.label = ("%d-%d of %d   (page %d/%d)")
      :format(first, last, total, page, pages)
  end
  local label = memo.label
  local labelX = x + 2 * bw + 2 * gap + gap
  Kit.text("mono", Kit.ellipsize("mono", label, math.max(0, x + w - labelX)),
    labelX, y + (h - Kit.textHeight("mono")) / 2, PAL.caption)
  return page, h
end

-- Slice helper so callers never hand-roll page arithmetic (and never draw a
-- row that is off the page -- the entire performance claim rests on this).
function Kit.pageBounds(page, total, perPage)
  local pages = math.max(1, math.ceil(total / math.max(1, perPage)))
  page = math.floor(Theme.clamp(page or 1, 1, pages))
  local first = (page - 1) * perPage + 1
  local last = math.min(total, page * perPage)
  return first, last, page, pages
end

-- How many rows of `rowH` (plus `gap`) fit in `h` pixels.  Panels call this
-- to derive perPage from the real viewport instead of a magic number, so a
-- tall window shows more rows and a phone shows fewer -- with no scrolling
-- either way.
function Kit.rowsThatFit(h, rowH, gap, minRows, maxRows)
  local per = math.floor((h + (gap or 0)) / math.max(1, rowH + (gap or 0)))
  return math.max(minRows or 1, math.min(maxRows or 99, per))
end

Kit.dragX = nil
Kit.dragY = nil
Kit.dragAccum = 0

function Kit.dragBegin(x, y)
  Kit.dragX, Kit.dragY, Kit.dragAccum = x, y, 0
end

function Kit.dragAdd(dy)
  if Kit.dragX then Kit.dragAccum = Kit.dragAccum + (dy or 0) end
end

function Kit.dragEnd()
  Kit.dragX, Kit.dragY, Kit.dragAccum = nil, nil, 0
end

local function dragOriginIn(x, y, w, h)
  if not Kit.dragX then return false end
  local x1, y1, x2, y2 = x, y, x + w, y + h
  local c = Kit._clipRect
  if c then
    x1, y1 = math.max(x1, c.x), math.max(y1, c.y)
    x2, y2 = math.min(x2, c.x + c.w), math.min(y2, c.y + c.h)
  end
  return Kit.dragX >= x1 and Kit.dragX <= x2
    and Kit.dragY >= y1 and Kit.dragY <= y2
end

-- Mouse wheel over a paginated list turns PAGES.  The wheel still has to do
-- something (users expect it), but it moves a bounded page index rather than
-- driving a pixel offset, so there is no scroll state and no interpolation.
function Kit.wheelPage(x, y, w, h, page, total, perPage)
  if Kit.blockClicks then return page end
  local pages = math.max(1, math.ceil(total / math.max(1, perPage)))
  local out = page
  if (Kit.wheelY or 0) ~= 0 and Kit.hit(x, y, w, h) then
    out = math.floor(Theme.clamp((out or 1) + (Kit.wheelY > 0 and -1 or 1),
      1, pages))
    Kit.wheelY = 0
  end
  local acc = Kit.dragAccum or 0
  if acc ~= 0 and dragOriginIn(x, y, w, h) then
    local stepPx = math.max(1, math.floor((h or 0) / 2))
    local flips = acc >= 0 and math.floor(acc / stepPx)
      or -math.floor(-acc / stepPx)
    if flips ~= 0 then
      local want = (out or 1) + flips
      out = math.floor(Theme.clamp(want, 1, pages))
      Kit.dragAccum = out ~= want and 0 or acc - flips * stepPx
    end
  end
  return out
end

function Kit.scrollExtent(contentH, viewH)
  return math.max(0, (contentH or 0) - math.max(0, viewH or 0))
end

function Kit.scrollClamp(offset, maxScroll)
  return math.max(0, math.min(offset or 0, math.max(0, maxScroll or 0)))
end

function Kit.scrollStep(scale)
  return math.floor(48 * (scale or Kit.scale))
end

function Kit.scrollBarW(scale)
  return math.max(2, math.floor(4 * (scale or Kit.scale)))
end

function Kit.scrollGutter(scale)
  return Kit.scrollBarW(scale) + math.max(2, math.floor(4 * (scale or Kit.scale)))
end

function Kit.scrollHandoff(offset, maxScroll, delta)
  local want = (offset or 0) + (delta or 0)
  local at = Kit.scrollClamp(want, maxScroll)
  return at, want - at
end

function Kit.scrollWheel(offset, maxScroll, x, y, w, h, step)
  local at = Kit.scrollClamp(offset, maxScroll)
  local wheel = Kit.wheelY or 0
  if Kit.blockClicks or wheel == 0 or (maxScroll or 0) <= 0 then
    return at, false
  end
  if not Kit.hit(x, y, w, h) then return at, false end
  local moved = Kit.scrollClamp(at - wheel * (step or Kit.scrollStep()),
    maxScroll)
  if moved == at then return at, false end
  Kit.wheelY = 0
  return moved, true
end

function Kit.scrollBegin(x, y, w, h, offset, maxScroll)
  Kit.pushClip(x, y, math.max(0, w or 0), math.max(0, h or 0))
  return y - Kit.scrollClamp(offset, maxScroll)
end

function Kit.scrollEnd(x, y, w, h, offset, maxScroll)
  Kit.popClip()
  if (maxScroll or 0) <= 0 or (h or 0) <= 0 or (w or 0) <= 0 then return end
  local barW = Kit.scrollBarW()
  local barX = x + w - barW
  local at = Kit.scrollClamp(offset, maxScroll)
  local thumbH = math.max(math.floor(20 * Kit.scale),
    math.floor(h * (h / (h + maxScroll))))
  local thumbY = y + (h - thumbH) * (at / maxScroll)
  Theme.fill(barX, y, barW, h, PAL.bg, 0.35)
  Theme.fill(barX, thumbY, barW, thumbH, PAL.muted, 0.7)
end

-- ------------------------------------------------------------------ spinner
-- The one animated element in the UI: a rotating arc of ticks.  Drawn as N
-- short lines at descending alpha, which needs no shader, no canvas and no
-- blend-mode change.  `t` defaults to the frame clock so every spinner on
-- screen stays in phase.
function Kit.spinner(cx, cy, r, t)
  if not G or not has("line") then return end
  t = t or Kit.time
  local ticks = 12
  local step = (math.pi * 2) / ticks
  local head = math.floor((t * 10) % ticks)
  if has("setLineWidth") then G.setLineWidth(math.max(2, 2 * Kit.scale)) end
  for i = 0, ticks - 1 do
    local a = ((ticks - ((i - head) % ticks)) / ticks)
    local ang = i * step - math.pi / 2
    local c, s = math.cos(ang), math.sin(ang)
    Theme.col(PAL.ink, a * a)
    G.line(cx + c * r * 0.55, cy + s * r * 0.55, cx + c * r, cy + s * r)
  end
  if has("setLineWidth") then G.setLineWidth(1) end
end

-- ------------------------------------------------------------------- clip
-- Clip drawing to a rect.  A stack: pushes intersect with the rect above and
-- a pop restores that rect rather than clearing the scissor, so a nested
-- region can never unclip its parent.  The tracked rect also bounds Kit.hit,
-- so a widget clipped out of view is inert instead of taking taps aimed at
-- whatever is drawn where it left.
-- The stack rects are pooled by depth and fully overwritten on every push,
-- so a frame that clips a dozen lists allocates nothing.
local clipStack = {}
local clipPool = {}

local function applyClip(rect)
  Kit._clipRect = rect
  if not (G and G.setScissor) then return end
  if not rect then
    G.setScissor()
  elseif rect.w <= 0 or rect.h <= 0 then
    -- LOVE rejects negative scissor dimensions; an exhausted clip region is
    -- empty, not invalid.
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
  local n = #clipStack + 1
  local rect = clipPool[n]
  if not rect then rect = {}; clipPool[n] = rect end
  rect.x, rect.y = x, y
  rect.w, rect.h = math.max(0, x2 - x), math.max(0, y2 - y)
  clipStack[n] = rect
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

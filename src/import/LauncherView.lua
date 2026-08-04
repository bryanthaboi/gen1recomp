-- The launcher's FlexLove view.  RomImporter owns every piece of state and
-- all import/platform logic; this module rebuilds the immediate-mode element
-- tree from that state once per frame, so the UI can never drift from the
-- importer and every window size lays out fresh (no cached geometry, no hand
-- hit-testing).  Flat design: solid fills and hairline borders only, no
-- gradients or glows.
--
-- Interaction contract with RomImporter:
--   * every click handler only QUEUES work (imp._uiActions); update() drains
--     the queue after FlexLove.update, so a handler that tears the view down
--     (Play, Edit save) never destroys the tree that is dispatching it.
--   * clicks are deduped per control key (a touch tap can surface as both a
--     touch release and a synthesized mouse click; one action must not fire
--     twice -- the shape of #553's double import).
--   * hover state lives in imp._hot, written by events this frame and read
--     by styles next frame (immediate mode recreates elements every frame).
--   * the gamepad virtual cursor clicks through clickAt(), which dispatches
--     a synthetic event to the element under the pad pointer.

local FlexLove = require("libs.flexlove.FlexLove")
local Color = FlexLove.Color
local SafeArea = require("src.core.SafeArea")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")

local LauncherView = {}

-- ------- palette (flat; alpha per use site)
local function rgba(r, g, b, a)
  return Color.new(r / 255, g / 255, b / 255, a or 1)
end
local PAL = {
  bg        = { 10, 15, 34 },
  card      = { 16, 23, 48 },
  rowBg     = { 9, 14, 34 },
  border    = { 120, 150, 220 },
  red       = { 255, 60, 72 },
  blue      = { 70, 150, 255 },
  gold      = { 255, 203, 5 },
  green     = { 62, 224, 138 },
  greenDark = { 22, 163, 90 },
  greenInk  = { 6, 32, 18 },
  white     = { 255, 255, 255 },
  detail    = { 198, 208, 230 },
  warn      = { 159, 176, 208 },
  gray      = { 143, 163, 200 },
  disabled  = { 120, 132, 158 },
  link      = { 127, 208, 255 },
  danger    = { 255, 83, 97 },
  chipModTop = { 61, 74, 109 },
}
local function C(name, a)
  local c = PAL[name]
  return rgba(c[1], c[2], c[3], a)
end

-- Non-scroll elements refuse to flex-shrink: the engine otherwise compresses
-- auto-height children inside height-constrained columns until their text
-- overlaps (the portrait single-column layout was the visible case).  Scroll
-- regions are the opposite — they MUST shrink to the viewport, or their
-- height grows with content, maxScrollY stays 0, and drag/wheel do nothing.
-- horizontal padding of a props table, for content-width bookkeeping
local function propsPadH(p)
  local pad = p.padding
  if type(pad) == "number" then return pad * 2 end
  if type(pad) == "table" then
    return (pad.left or pad.horizontal or 0) + (pad.right or pad.horizontal or 0)
  end
  return 0
end

local function isScrollOverflow(props)
  local o = props.overflowY or props.overflowX or props.overflow
  return o == "scroll" or o == "auto"
end

local function mk(props)
  if props.flexShrink == nil then
    props.flexShrink = isScrollOverflow(props) and 1 or 0
  end
  if isScrollOverflow(props) then
    if props.minHeight == nil then props.minHeight = 0 end
    -- Every launcher list scrolls like a native one: interpolated wheel
    -- steps instead of hard 20px jumps, and a bigger per-notch distance so
    -- long save/mod lists don't take dozens of notches to traverse.
    if props.smoothScrollEnabled == nil then props.smoothScrollEnabled = true end
    if props.scrollSpeed == nil then props.scrollSpeed = 60 end
  end
  -- Resolve "100%" here, against the parent's CONTENT width: the engine
  -- resolves a percentage against the parent's border box and ignores its
  -- padding, so every percent child of a padded container overflowed to the
  -- right by exactly that padding (the clipped LOADED/Delete chips).
  -- Parents are always created before their children in this view, so the
  -- tracked inner width is available by the time a child asks.
  if props.width == "100%" and props.parent and props.parent._innerW then
    props.width = props.parent._innerW
  end
  local el = FlexLove.new(props)
  if el then
    if type(props.width) == "number" then
      el._innerW = props.width - propsPadH(props)
    elseif props.parent and props.parent._innerW then
      el._innerW = props.parent._innerW - propsPadH(props)
    end
  end
  return el
end

local COMMUNITY_URL = "https://bois.icu"

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- FlexLove's addChild auto-sizing only propagates one ancestor while this
-- immediate-mode tree is assembled. Reconcile a completed nested container
-- with the same height box model used by Element:resize.
local function refreshAutoHeight(el)
  if type(el) ~= "table" or type(el.autosizing) ~= "table"
      or not el.autosizing.height
      or type(el.calculateAutoHeight) ~= "function" then
    return false
  end
  local ok, contentHeight = pcall(el.calculateAutoHeight, el)
  if not ok or type(contentHeight) ~= "number"
      or contentHeight ~= contentHeight
      or contentHeight == math.huge or contentHeight == -math.huge then
    return false
  end
  local padding = el.padding or {}
  local top, bottom = padding.top or 0, padding.bottom or 0
  local borderBoxHeight = clamp(contentHeight + top + bottom,
    el.minHeight or -math.huge, el.maxHeight or math.huge)
  el._borderBoxHeight = borderBoxHeight
  el.height = clamp(math.max(0, borderBoxHeight - top - bottom),
    el.minHeight or -math.huge, el.maxHeight or math.huge)
  if type(el.invalidateLayout) == "function" then
    el:invalidateLayout()
  end
  return borderBoxHeight
end

LauncherView._refreshAutoHeight = refreshAutoHeight


-- ------- lifecycle

-- All platforms: FlexLove used to map `performanceMonitoring = false` to
-- true (`false or true`), leaving layout/render timers + memory sampling on
-- every immediate-mode frame (pad-cursor lag on NX, scroll drag on desktop).
-- The vendored init is fixed, but force the flags off here too so a hot
-- reload against an already-inited FlexLove stays clean. Exported so the
-- engine tier can assert the guards without drawing the full tree.
function LauncherView.applyNxPerfGuards(imp)
  if not (imp and FlexLove.isReady() and FlexLove._Performance) then
    return false
  end
  FlexLove._Performance.enabled = false
  local mp = FlexLove._Performance._memoryProfiler
  if mp then mp.enabled = false end
  -- Immediate-mode rebuilds allocate a full tree every frame; the default
  -- "auto" GC strategy triggers a full blocking collect past 100 MB, a
  -- visible hitch mid-scroll. Less frequent steps, higher threshold, on
  -- every platform (was NX-only; desktop hit the same hitch, see the
  -- scroll-sluggishness investigation).
  if FlexLove._gcConfig then
    FlexLove._gcConfig.strategy = "periodic"
    FlexLove._gcConfig.interval = 90
    FlexLove._gcConfig.stepSize = 40
    FlexLove._gcConfig.memoryThreshold = 180
  end
  return true
end

local function ensureFlex(imp)
  if not FlexLove.isReady() then
    FlexLove.init({
      immediateMode = true,
      performanceMonitoring = false,
      keyboardNavigation = false,
    })
  end
  -- Re-apply on every ensure: FlexLove may already be ready from a prior
  -- init (hot reload / editor round-trip). No-op when not NX.
  LauncherView.applyNxPerfGuards(imp)
  if not imp._flex then
    imp._flex = true
    imp._hot = imp._hot or {}
    imp._actAt = imp._actAt or {}
    imp._uiActions = imp._uiActions or {}
    -- Held backspace/arrows must repeat in the text fields; restored on
    -- detach because the game's Input does its own per-step edge detection
    -- and never expects repeated keypressed events.
    if love.keyboard and love.keyboard.setKeyRepeat then
      pcall(love.keyboard.setKeyRepeat, true)
    end
  end
end

-- Tear the tree down before handing the screen to the game / editor: the
-- engine draws with raw love.graphics and must not share canvases or input
-- polling with a live UI toolkit.
function LauncherView.detach(imp)
  -- Restore the NX mouse shim even if _flex was never set (bridge can
  -- install on the first update before the first draw).
  if imp and imp.parkNxPointerForHost then
    pcall(imp.parkNxPointerForHost, imp)
  elseif imp and imp._restoreNxPointerBridge then
    pcall(imp._restoreNxPointerBridge, imp)
  end
  if not imp or not imp._flex then return end
  imp._flex = nil
  if love.keyboard and love.keyboard.setKeyRepeat then
    pcall(love.keyboard.setKeyRepeat, false)
  end
  pcall(FlexLove.destroy)
end

function LauncherView.update(imp, dt)
  if not imp._flex then return end
  FlexLove.update(dt)
  -- Drain the action queue OUTSIDE FlexLove's dispatch, so an action is free
  -- to destroy the view (Play/Edit) or block in a native picker.  The batch
  -- is resolved by RomImporter:runActions so the drop/disarm rules are
  -- testable without a live FlexLove tree (#780).
  local queue = imp._uiActions
  if queue and #queue > 0 then
    imp._uiActions = {}
    imp:runActions(queue)
  end
end

-- One dedup window covers a touch release plus the mouse click SDL
-- synthesizes for the same tap.
local ACT_DEDUP = 0.35
-- Finger travel past this (px) is a scroll drag, not a tap — so dragging a
-- list row does not also fire that row's button.
local TAP_SLOP2 = 16 * 16

function LauncherView.wheelmoved(imp, dx, dy)
  if not imp._flex then return end
  pcall(FlexLove.wheelmoved, dx, dy)
end

-- Touch drag scroll: FlexLove's ScrollManager only moves when these are
-- hooked. Clicks still come from EventHandler's love.touch / mouse polling;
-- the view's action dedupe covers a tap that also synthesizes a mouse click,
-- and a drag past TAP_SLOP suppresses the click that would otherwise fire
-- on the row under the finger.
function LauncherView.touchpressed(imp, id, x, y, dx, dy, pressure)
  if not imp._flex then return end
  imp._touchAt = imp._touchAt or {}
  imp._touchAt[tostring(id)] = { x = x, y = y }
  pcall(FlexLove.touchpressed, id, x, y, dx, dy, pressure)
end

function LauncherView.touchmoved(imp, id, x, y, dx, dy, pressure)
  if not imp._flex then return end
  local start = imp._touchAt and imp._touchAt[tostring(id)]
  if start then
    local ddx, ddy = x - start.x, y - start.y
    if ddx * ddx + ddy * ddy > TAP_SLOP2 then
      imp._suppressClickUntil = love.timer.getTime() + ACT_DEDUP
    end
  end
  pcall(FlexLove.touchmoved, id, x, y, dx, dy, pressure)
end

function LauncherView.touchreleased(imp, id, x, y, dx, dy, pressure)
  if not imp._flex then return end
  if imp._touchAt then imp._touchAt[tostring(id)] = nil end
  pcall(FlexLove.touchreleased, id, x, y, dx, dy, pressure)
end

-- Synthetic click for the gamepad virtual cursor: find the element under the
-- pad pointer and run its handler with a click-shaped event.
function LauncherView.clickAt(imp, x, y)
  if not imp._flex then return end
  local ok, el = pcall(FlexLove.getElementAtPosition, x, y)
  if not ok then return end
  while el and not el.onEvent do el = el.parent end
  if el and el.onEvent then
    pcall(el.onEvent, el, { type = "click", button = 1, x = x, y = y,
      modifiers = {}, clickCount = 1 })
  end
end

-- ------- shared widget helpers

local function queueAction(imp, key, fn, keepArm)
  local now = love.timer.getTime()
  local last = imp._actAt[key]
  if last and now - last < ACT_DEDUP then return end
  imp._actAt[key] = now
  -- Any press that is not a Delete's own second click disarms the pending
  -- delete confirm (#433's rule, preserved from the hit-rect launcher).  The
  -- disarm itself is applied by RomImporter:runActions when the batch drains,
  -- not here: one touch lands on a row AND on the chip inside it, and
  -- clearing the arm as the row queued left Delete stuck on its first press
  -- (#780).
  imp._uiActions[#imp._uiActions + 1] = { key = key, fn = fn, keepArm = keepArm }
end

local function handler(imp, key, action, keepArm)
  return function(_, ev)
    if ev.type == "hover" then
      imp._hot[key] = true
    elseif ev.type == "unhover" then
      imp._hot[key] = nil
    elseif action and (ev.type == "click" or ev.type == "touchrelease") then
      if ev.type == "touchrelease" then
        local dx, dy = ev.dx or 0, ev.dy or 0
        if dx * dx + dy * dy > TAP_SLOP2 then
          imp._suppressClickUntil = love.timer.getTime() + ACT_DEDUP
          return
        end
      end
      local untilT = imp._suppressClickUntil
      if untilT and love.timer.getTime() < untilT then return end
      queueAction(imp, key, action, keepArm)
    end
  end
end

-- Shared measuring fonts, cached by integer size: control widths and heights
-- come from the same faces the elements render with.  Estimating them from
-- character counts broke at every scale except the one it was tuned on
-- (clipped Delete chips, button rows spilling out of their cards).
local measureFonts = {}
local function mfont(size)
  size = math.max(8, math.floor(size + 0.5))
  local f = measureFonts[size]
  if not f then
    f = love.graphics.newFont(size)
    measureFonts[size] = f
  end
  return f
end
local function textWidth(size, text) return mfont(size):getWidth(text) end
local function textHeight(size) return mfont(size):getHeight() end

-- wrapped text height at a width, from the same font the element renders.
-- Memoized: the immediate-mode rebuild asks for the same (size, width,
-- text) every frame for every visible row, and Font:getWrap re-shapes the
-- whole string each time - one of the hottest calls in the frame on mobile.
-- The key space is small (mod summaries and notes at a handful of widths).
local wrapHeightCache = {}
local function wrapHeight(size, text, width)
  if not text or text == "" or (width or 0) <= 0 then return 0 end
  local key = size .. ":" .. width .. ":" .. text
  local h = wrapHeightCache[key]
  if h then return h end
  local f = mfont(size)
  local _, lines = f:getWrap(text, width)
  h = math.max(1, #lines) * f:getHeight()
  wrapHeightCache[key] = h
  return h
end

-- Every text size in this file is already scaled by m.s, so FlexLove's own
-- viewport text scaling must stay off: with it on, the layout boxes shrink
-- away from the rendered glyphs on non-reference window sizes and lines
-- overlap.
local function label(parent, text, size, color, props)
  -- integer sizes only: the measuring fonts are integer-sized, and a
  -- fractional rendered size drifting a few percent wider than its measure
  -- is exactly how button rows crept out of their cards on some displays
  size = math.floor(size + 0.5)
  local p = {
    parent = parent, text = text, textSize = size, textColor = color,
    textWrap = "word", autoScaleText = false,
    -- id keyed by the text: the engine's Persistable behavior snapshots
    -- every scalar prop (text included) per id and stomps it back onto the
    -- recreated element, freezing any label whose text changes between
    -- frames (typed search text stuck on its first letter).  A new text is
    -- a new id, so it always renders fresh.
    id = "lbl:" .. tostring(text),
  }
  for k, v in pairs(props or {}) do p[k] = v end
  return mk(p)
end

-- kinds: primary (solid green), accent (green outline), danger (red outline),
-- dangerArmed (solid red), neutral (translucent white), disabled (inert)
local function button(imp, parent, key, text, opts)
  opts = opts or {}
  local hot = imp._hot[key]
  local kind = opts.kind or "neutral"
  local bgc, fgc, brc
  if kind == "primary" then
    bgc = hot and C("green") or C("greenDark")
    fgc, brc = C("greenInk"), C("green", 0.9)
  elseif kind == "accent" then
    bgc = C("green", hot and 0.30 or 0.12)
    fgc, brc = hot and C("white") or C("green"), C("green", 0.7)
  elseif kind == "danger" then
    bgc = C("danger", hot and 0.30 or 0.12)
    fgc, brc = hot and C("white") or C("danger"), C("danger", 0.7)
  elseif kind == "dangerArmed" then
    bgc, fgc, brc = C("danger"), C("white"), C("danger")
  elseif kind == "disabled" then
    bgc = C("disabled", 0.22)
    fgc, brc = C("disabled"), C("disabled", 0.35)
  else
    bgc = C("white", hot and 0.22 or 0.10)
    fgc, brc = C("white"), C("white", hot and 0.4 or 0.2)
  end
  -- Explicit measured size always: the layout engine measures an auto-sized
  -- button as zero-height while its parent card is auto-sizing, which let
  -- bottom action rows spill past their card's edge.
  local size = math.floor((opts.size or 14) + 0.5)
  local pad = opts.pad or { horizontal = 12, vertical = 6 }
  local padX = pad.horizontal or 12
  local padY = pad.vertical or 6
  local w = opts.w
  if not w and not opts.flex then
    w = math.ceil(textWidth(size, text)) + 2 * padX + 2
  end
  local h = opts.h or (math.ceil(textHeight(size)) + 2 * padY + 2)
  local p = {
    parent = parent,
    -- same Persistable-stomp guard as label(): a button whose caption
    -- changes (Delete -> Sure?, Update ladders) must not keep frame one's
    id = "btn:" .. key .. ":" .. tostring(text),
    width = w, height = h,
    flex = opts.flex,
    backgroundColor = bgc,
    border = 1, borderColor = brc,
    cornerRadius = opts.r or 8,
    text = text, textColor = fgc, textSize = size,
    textAlign = "center-center", autoScaleText = false,
  }
  if kind ~= "disabled" and opts.action then
    p.onEvent = handler(imp, key, opts.action, opts.keepArm)
  elseif kind ~= "disabled" then
    p.onEvent = handler(imp, key, nil)
  end
  return mk(p)
end

-- Measured single-row width of a header's labels and buttons, using the
-- same integer-sized fonts label()/button() render with (button() adds
-- 12px horizontal padding + 1px border per side).  Tab headers use this to
-- decide between one row and a split title/buttons pair: flexWrap cannot
-- save a narrow window here, because the engine does not grow an
-- auto-sized parent for wrapped children (#748 family), so a wrapped
-- button used to land on top of whatever followed the header.
local function headNeededW(m, items)
  local w, n = 0, 0
  for _, it in ipairs(items) do
    local size = math.floor(it.size + 0.5)
    local tw = math.ceil(textWidth(size, it.text))
    w = w + (it.btn and (tw + 26) or tw)
    n = n + 1
  end
  -- inter-item gaps, plus one gap of slack where the flex spacer sits
  return w + n * (10 * m.s)
end

-- One header row when everything fits, otherwise a title row and a
-- right-aligned button row stacked under it.  Returns the row for the
-- title/status labels and a function to call AFTER adding them, which
-- returns the row for the buttons (inserting the flex spacer so buttons
-- sit flush right in both shapes).
local function headRows(parent, m, items)
  local split = headNeededW(m, items) > (parent._innerW or m.contentW)
  local function row()
    return mk({ parent = parent, width = "100%",
      positioning = "flex", flexDirection = "horizontal",
      alignItems = "center", gap = 10 * m.s })
  end
  local titleRow = row()
  return titleRow, function()
    local btnRow = split and row() or titleRow
    mk({ parent = btnRow, flex = 1 })
    return btnRow
  end
end

local function card(parent, props)
  local p = {
    parent = parent,
    width = "100%",
    backgroundColor = C("card", 0.75),
    border = 1, borderColor = C("border", 0.28),
    cornerRadius = 14,
    positioning = "flex", flexDirection = "vertical",
  }
  for k, v in pairs(props or {}) do p[k] = v end
  return mk(p)
end

local function pill(parent, text, colName, size)
  size = math.floor((size or 12) + 0.5)
  local h = math.ceil(textHeight(size)) + 8
  return mk({
    parent = parent, text = text, textColor = C(colName),
    id = "pill:" .. tostring(text),
    textSize = size, textAlign = "center-center", autoScaleText = false,
    width = math.ceil(textWidth(size, text)) + 20, height = h,
    backgroundColor = C(colName, 0.12),
    border = 1, borderColor = C(colName, 0.55),
    cornerRadius = h / 2,
  })
end

local function progressBar(parent, frac, colName, h)
  h = h or 10
  frac = clamp(frac or 0, 0, 1)
  local track = mk({
    parent = parent, width = "100%", height = h,
    backgroundColor = C("bg", 0.9), cornerRadius = h / 2,
  })
  mk({
    parent = track, width = (frac * 100) .. "%",
    -- id keyed by the fraction, or Persistable pins the bar at frame one
    id = "prog:" .. math.floor(frac * 1000),
    height = "100%", backgroundColor = C(colName), cornerRadius = h / 2,
  })
  return track
end

-- Flat toggle switch (read-only visual; the pressable area is the caller's).
-- The knob is flex-aligned rather than absolutely positioned: absolute
-- children resolve in screen space here, not against the parent.
local function toggleSwitch(parent, on, w, h, idKey)
  w, h = w or 46, h or 24
  local track = mk({
    parent = parent, width = w, height = h,
    -- state-keyed id: justifyContent is a persisted scalar, and a stale
    -- snapshot would hold the knob on its frame-one side after a toggle
    id = idKey and (idKey .. (on and ":on" or ":off")) or nil,
    backgroundColor = on and C("greenDark") or C("disabled", 0.4),
    border = 1, borderColor = on and C("green", 0.8) or C("disabled", 0.6),
    cornerRadius = h / 2,
    positioning = "flex", flexDirection = "horizontal",
    alignItems = "center",
    justifyContent = on and "flex-end" or "flex-start",
    padding = 3,
  })
  mk({
    parent = track,
    width = h - 6, height = h - 6,
    backgroundColor = C("white"), cornerRadius = (h - 6) / 2,
  })
  return track
end

-- a darkened copy of a palette color, for the embossed chips' bottom ledge
local function darken(name, f, a)
  local c = PAL[name]
  return rgba(c[1] * f, c[2] * f, c[3] * f, a or 1)
end

-- Hand-rolled text field: the importer owns the string (textinput /
-- keypressed routing), this draws it.  The field clips its content, keeps
-- the TAIL of the text visible while typing (the interesting end), and
-- shows a font-height caret on the importer's pulse clock.
local function dropFirstChar(t)
  local i = 2
  while i <= #t do
    local b = t:byte(i)
    if b < 0x80 or b >= 0xC0 then break end
    i = i + 1
  end
  return t:sub(i)
end

local function textField(imp, parent, key, rawText, placeholder, focused, action)
  local size = 14
  local h = math.max(36, math.ceil(textHeight(size)) + 18)
  local field = mk({
    parent = parent, width = "100%", height = h,
    backgroundColor = C("bg", focused and 1 or 0.85),
    border = focused and 2 or 1,
    borderColor = focused and C("green", 0.85)
      or C("border", imp._hot[key] and 0.7 or 0.4),
    cornerRadius = 8, overflow = "hidden",
    positioning = "flex", flexDirection = "horizontal",
    alignItems = "center", gap = 2,
    padding = { horizontal = 12 },
    onEvent = action and handler(imp, key, action) or nil,
  })
  local avail = (field._innerW or 200) - 6
  local shown = rawText or ""
  local f = mfont(size)
  while #shown > 1 and f:getWidth(shown) > avail do
    shown = dropFirstChar(shown)
  end
  if shown ~= "" then
    label(field, shown, size, C("white"), { textWrap = false })
  elseif placeholder and not focused then
    label(field, placeholder, size, C("disabled"), { textWrap = false })
  end
  if focused and (imp.pulse * 2 % 1) < 0.5 then
    mk({ parent = field, width = 2,
      height = math.ceil(textHeight(size)) + 2,
      backgroundColor = C("green"), cornerRadius = 1 })
  end
  return field
end

-- ------- status derivations shared with the old panels

local function modStatusChip(status)
  if status == "ok" then return Strings("Ready"), "green" end
  if status == "conflict" then return Strings("Conflict"), "danger" end
  return Strings("Incompatible"), "gold"
end

local function findActionFor(entry, installedVersion)
  local ModIndex = require("src.mods.ModIndex")
  if not ModIndex.canInstall(entry) then
    return nil, Strings("Not installable from this index")
  end
  if not installedVersion then return Strings("Install"), nil end
  local listed = ModIndex.displayVersion(entry)
  local ModUpdate = require("src.mods.ModUpdate")
  if type(installedVersion) == "string"
      and ModUpdate.isNewer(installedVersion, listed) then
    return Strings("Update"), "Installed v" .. installedVersion
  end
  return Strings("Reinstall"), "Installed v" .. tostring(installedVersion)
end

local DELETE_LABEL = function(armed)
  return armed and Strings("Sure?") or Strings("Delete")
end

local function deleteArmed(imp, kind, id, version)
  local a = imp._confirmDelete
  return a ~= nil and a.kind == kind and a.id == id and a.version == version
end

-- ------- header: strip, logo row (with the settings gear), tab bar

local function buildHeader(imp, root, m)
  -- tricolor strip
  local strip = mk({
    parent = root, width = "100%", height = math.max(4, 5 * m.s),
    positioning = "flex", flexDirection = "horizontal",
  })
  for _, name in ipairs({ "red", "blue", "gold" }) do
    mk({ parent = strip, flex = 1, height = "100%",
      backgroundColor = C(name) })
  end

  -- logo row: spacer / centered logo / settings gear, so the logo stays
  -- centered while the gear holds the app's top-right corner
  local gearSize = math.max(34, 40 * m.s)
  local row = mk({
    parent = root, width = "100%", height = m.logoH + 12 * m.s,
    positioning = "flex", flexDirection = "horizontal",
    alignItems = "center", gap = 8 * m.s,
    padding = { horizontal = m.pad },
  })
  mk({ parent = row, width = gearSize, height = 1 })
  local mid = mk({ parent = row, flex = 1,
    positioning = "flex", justifyContent = "center", alignItems = "center" })
  mk({
    parent = mid, image = imp.logo, objectFit = "contain",
    width = math.min(320 * m.s, m.w * 0.6), height = m.logoH,
  })
  imp._gearIcon = imp._gearIcon
    or love.graphics.newImage("assets/launcher/gear.png")
  mk({
    parent = row,
    width = gearSize, height = gearSize,
    backgroundColor = C("white", imp._hot.gear and 0.20 or 0.07),
    border = 1, borderColor = C("border", imp._hot.gear and 0.85 or 0.4),
    cornerRadius = 10,
    image = imp._gearIcon, objectFit = "contain",
    imageTint = imp._hot.gear and C("white") or C("detail"),
    padding = math.floor(gearSize * 0.18),
    onEvent = handler(imp, "gear", function()
      imp:_openSettings()
    end),
  })

  -- tab bar
  local bar = mk({
    parent = root, width = "100%",
    positioning = "flex", flexDirection = "horizontal", flexWrap = "wrap",
    alignItems = "center", gap = 8 * m.s,
    padding = { horizontal = m.pad, vertical = 8 * m.s },
  })
  imp._modsIcon = imp._modsIcon
    or love.graphics.newImage("assets/launcher/mods.png")
  imp._findIcon = imp._findIcon
    or love.graphics.newImage("assets/launcher/find.png")
  local tabs = {
    { id = "red", letter = "R", col = "red", ink = "white", labelText = Strings("RED") },
    { id = "blue", letter = "B", col = "blue", ink = "white", labelText = Strings("BLUE") },
    { id = "yellow", letter = "Y", col = "gold", ink = "bg", labelText = Strings("YELLOW") },
    { id = "mods", icon = imp._modsIcon, col = "chipModTop", ink = "white", labelText = Strings("MODS") },
    { id = "find", icon = imp._findIcon, col = "chipModTop", ink = "white", labelText = Strings("FIND MODS") },
  }
  for _, t in ipairs(tabs) do
    if t.id == "mods" then
      mk({ parent = bar, width = 1, height = m.chip * 0.8,
        backgroundColor = C("border", 0.3) })
    end
    local active = imp.tab == t.id
    local key = "tab-" .. t.id
    local labelSize = 13 * m.s + 4
    local hot = imp._hot[key]
    -- embossed chip: a darker base ledge under the face gives the tab a
    -- raised look; hover lifts the face brightness and rims it white
    local ledge = math.max(2, math.floor(3 * m.s))
    local baseEl = mk({
      parent = bar, width = m.chip, height = m.chip + ledge,
      backgroundColor = darken(t.col, 0.35, active and 1 or 0.8),
      cornerRadius = 10,
      onEvent = handler(imp, key, function()
        imp:_switchTab(t.id)
      end),
    })
    local face = {
      parent = baseEl, width = "100%", height = m.chip,
      backgroundColor = C(t.col, active and 1 or (hot and 0.75 or 0.42)),
      border = (active or hot) and 1 or false,
      borderColor = C("white", active and 0.6 or 0.35),
      cornerRadius = 10,
    }
    if t.icon then
      face.image = t.icon
      face.objectFit = "contain"
      face.padding = math.floor(m.chip * 0.2)
      face.imageTint = C("white", active and 1 or 0.85)
    else
      face.text = t.letter
      -- the gold chip's dark ink only reads on the full-strength active
      -- fill; dimmed inactive chips all take light ink
      face.textColor = (active and t.ink == "bg") and C("bg") or C("white")
      face.textSize = math.floor(m.chip * 0.45)
      face.textAlign = "center-center"
      face.autoScaleText = false
    end
    mk(face)
    if active then
      -- explicit width: a percentage inside this auto-sized wrap would not
      -- resolve (LayoutEngine LAY_004), so the underline takes the label's
      -- measured pixel width
      local lw = math.ceil(textWidth(labelSize, t.labelText)) + 2
      local wrap = mk({ parent = bar, width = lw,
        positioning = "flex", flexDirection = "vertical", gap = 3 * m.s })
      label(wrap, t.labelText, labelSize, C("white"), { textWrap = false })
      mk({ parent = wrap, width = lw, height = 3,
        backgroundColor = C(t.col) })
    end
  end
  -- "N of 3 ready" right-aligned filler
  local ready = 0
  for _, v in ipairs(GameVersion.ORDER) do
    if imp.ready[v] then ready = ready + 1 end
  end
  mk({ parent = bar, flex = 1 })
  label(bar, Strings("%d of 3 ready", ready), 12 * m.s + 2, C("gray"),
    { textWrap = false })
  mk({ parent = root, width = "100%", height = 1,
    backgroundColor = C("border", 0.22) })
end

-- ------- game panel

local function buildRomCard(imp, parent, m, version, info, ready, locked)
  local dropHint = imp.isNX and Strings("Copy the .gb/.gbc via MTP into imports/.")
    or (imp.android and Strings("Copy the .gb/.gbc via USB.")
      or Strings("Or drop the .gb/.gbc file here."))
  local importLabel = imp.isNX and Strings("Scan again") or Strings("Import ROM")
  local romState, romDetail, romBtnLabel, romBtnEnabled, romProgress
  if locked then
    romState, romDetail = Strings("Not supported yet"),
      Strings("Support for this game is on the way.")
    romBtnLabel, romBtnEnabled = Strings("Import unavailable"), false
  else
    local importing = imp.importing == version
    local erroring = imp.workState == "error" and imp.errorVersion == version
    local notice = imp.notice and imp.notice.version == version and imp.notice
    if importing and (imp.workState == "working" or imp.workState == "complete") then
      romState = imp.status or Strings("Importing")
      romDetail = imp.detail or ""
      romProgress = imp.progress or 0
    elseif ready then
      romState = imp.romName[version] or Strings("ROM imported")
      romDetail = Strings("Verified.")
      romBtnLabel, romBtnEnabled = Strings("Re-import ROM"), true
    elseif erroring then
      romState = Strings("Import failed")
      romDetail = imp.detail or Strings("That ROM could not be imported.")
      romBtnLabel, romBtnEnabled = importLabel, true
    elseif notice then
      romState = Strings("No ROM imported")
      romDetail = ((notice.status or "") .. " " .. (notice.detail or ""))
        :gsub("^%s+", ""):gsub("%s+$", "")
      romBtnLabel, romBtnEnabled = importLabel, true
    elseif imp.returning[version] then
      romState = Strings("Update required")
      romDetail = Strings("This build needs a few more things from your ")
        .. info.label .. Strings(" ROM. Re-import to continue.")
      romBtnLabel, romBtnEnabled = Strings("Re-import ROM"), true
    else
      romState = Strings("No ROM imported")
      romDetail = Strings("The ROM is verified before any files are created. ")
        .. dropHint
      romBtnLabel, romBtnEnabled = importLabel, true
    end
  end

  local accent = version == "yellow" and "gold" or version
  local c = card(parent, { padding = m.cardPad, gap = 8 * m.s })
  label(c, Strings("ROM"), 12 * m.s + 1, C("gray"))
  label(c, romState, 15 * m.s + 2, C("white"))
  label(c, romDetail, 12 * m.s + 2, C("detail"))
  if romProgress ~= nil then
    progressBar(c, romProgress, accent, math.max(8, 10 * m.s))
  else
    button(imp, c, "rom-" .. version, romBtnLabel, {
      w = "100%", h = m.btnH, size = 14 * m.s,
      kind = romBtnEnabled and "neutral" or "disabled",
      action = romBtnEnabled and function()
        if imp.ready[version] then imp:reimport(version)
        else imp:choose(version) end
      end or nil,
    })
  end
end

local function buildSaveFilesCard(imp, parent, m, version, ready, locked)
  local sfImportEnabled, sfExportEnabled = false, false
  if not locked then
    imp:_ensureSlots(version)
    sfImportEnabled = ready and true or false
    local activeId = imp.activeSlot[version]
    for _, sl in ipairs(imp.slots[version] or {}) do
      if sl.id == activeId and sl.exists then sfExportEnabled = true break end
    end
  end
  local sfNotice = (not locked) and imp.saveNotice[version] or nil
  local hintText, hintCol
  if sfNotice then
    hintText, hintCol = sfNotice.text, (sfNotice.ok and "green" or "danger")
  elseif locked then
    hintText, hintCol = Strings("Not available yet."), "warn"
  else
    hintText = imp:_savesDefaultHint(version)
    hintCol = "warn"
  end
  local savImportLabel = imp.isNX and Strings("Scan again") or Strings("Import save")

  local c = card(parent, { padding = m.cardPad, gap = 8 * m.s })
  label(c, Strings("SAVE FILES"), 12 * m.s + 1, C("gray"))
  local row = mk({ parent = c, width = "100%",
    positioning = "flex", flexDirection = "horizontal", gap = 10 * m.s })
  -- explicit halves rather than flex growth, which mis-distributed inside
  -- an auto-height card
  local halfW = math.floor((m.colW - 32 - 10 * m.s) / 2)
  button(imp, row, "sav-import-" .. version, savImportLabel, {
    w = halfW, h = m.btnH, size = 13 * m.s + 1,
    kind = sfImportEnabled and "neutral" or "disabled",
    action = sfImportEnabled and function()
      imp:chooseSaveImport(version)
    end or nil,
  })
  button(imp, row, "sav-export-" .. version, Strings("Export save"), {
    w = halfW, h = m.btnH, size = 13 * m.s + 1,
    kind = sfExportEnabled and "neutral" or "disabled",
    action = sfExportEnabled and function()
      imp:exportSave(version)
    end or nil,
  })
  label(c, hintText, 12 * m.s + 1, C(hintCol))
  if sfNotice and sfNotice.dir then
    local dir = sfNotice.dir
    label(c, Strings("Open folder"), 12 * m.s + 1,
      C("link", imp._hot["sav-folder-" .. version] and 1 or 0.85), {
        onEvent = handler(imp, "sav-folder-" .. version, function()
          love.system.openURL(imp:fileUrl(dir))
        end),
      })
  end
end

local function buildSlotCard(imp, parent, m, version)
  imp:_ensureSlots(version)
  local slots = imp.slots[version] or {}
  local active = imp.activeSlot[version]
  local n = #slots

  local c = card(parent, { padding = m.cardPad, gap = 10 * m.s })
  local head = mk({ parent = c, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    justifyContent = "space-between", alignItems = "center" })
  label(head, Strings("SAVE SLOT"), 12 * m.s + 1, C("gray"), { textWrap = false })
  label(head, n == 1 and Strings("1 slot") or Strings("%d slots", n),
    12 * m.s + 1, C("gray"), { textWrap = false })

  if n == 0 then
    local box = mk({
      parent = c, width = "100%", height = 90 * m.s,
      border = 1, borderColor = C("border", 0.45), cornerRadius = 12,
      positioning = "flex", justifyContent = "center", alignItems = "center",
      padding = { horizontal = 12 },
    })
    label(box, Strings("No saves yet - start a new game or import one."),
      12 * m.s + 2, C("warn"), { textAlign = "center" })
  end

  -- Taller stacked rows: name + LOADED line, meta line, then the action
  -- buttons on their own full-width line, so no control can ever clip
  -- against the card's right edge at any scale.  Every line height is
  -- measured, and the row height is their explicit sum: the engine's
  -- auto-height came up short on some displays and let the button row fall
  -- out of the card.
  local chipSize = math.floor(11 * m.s + 1.5)
  local nameSize = math.floor(14 * m.s + 2.5)
  local metaSize = math.floor(11 * m.s + 2.5)
  local pillSize = math.floor(10 * m.s + 1.5)
  local btnH = math.ceil(textHeight(chipSize)) + 14
  local headH = math.max(math.ceil(textHeight(nameSize)),
    math.ceil(textHeight(pillSize)) + 8)
  local metaH = math.ceil(textHeight(metaSize))
  local rowH = 10 + headH + 5 + metaH + 8 + btnH + 10
  -- Fixed-height scroller so 40 slots actually overflow (page-level flex
  -- scroll alone was growing with content, leaving nothing to drag).
  local listParent = c
  if n > 0 then
    local listH = math.floor(clamp(m.h * (m.twoCol and 0.58 or 0.42), 200, 720))
    listParent = mk({
      parent = c, id = "slots-" .. version, width = "100%", height = listH,
      overflowY = "scroll", hideScrollbars = true,
      positioning = "flex", flexDirection = "vertical", gap = 10 * m.s,
      padding = { right = 4 },
    })
  end
  for _, slot in ipairs(slots) do
    local selected = slot.id == active
    local rowKey = "slot-" .. version .. "-" .. slot.id
    local row = mk({
      parent = listParent, width = "100%", height = rowH,
      backgroundColor = C("rowBg", imp._hot[rowKey] and 0.85 or 0.6),
      border = 1,
      borderColor = selected and C("green", 0.9) or C("border", 0.25),
      cornerRadius = 12,
      positioning = "flex", flexDirection = "vertical", gap = 5,
      padding = { horizontal = 12, vertical = 10 },
      onEvent = handler(imp, rowKey, function()
        imp:_selectSlot(version, slot.id)
      end),
    })
    local rowInner = row._innerW
    local headRow = mk({ parent = row, width = rowInner, height = headH,
      positioning = "flex", flexDirection = "horizontal",
      justifyContent = "space-between", alignItems = "center" })
    local name = slot.label or slot.name or Strings("NEW GAME")
    local pillW = selected
      and (math.ceil(textWidth(pillSize, Strings("LOADED"))) + 20) or 0
    label(headRow, name, nameSize, C("white"),
      { width = rowInner - pillW - 8,
        textWrap = false, textOverflow = "ellipsis" })
    if selected then pill(headRow, Strings("LOADED"), "green", pillSize) end
    local metaTxt
    if slot.exists and slot.meta then
      metaTxt = Strings("%d badges - %s - %d caught", slot.meta.badges or 0,
        slot.meta.timeText or "0:00", slot.meta.dexCount or 0)
    else
      metaTxt = Strings("empty slot")
    end
    label(row, metaTxt, metaSize, C("warn"),
      { width = rowInner, textWrap = false, textOverflow = "ellipsis" })

    local btnRow = mk({ parent = row, width = rowInner, height = btnH,
      positioning = "flex", flexDirection = "horizontal",
      justifyContent = "flex-end", gap = 6 })
    if not imp.android then
      button(imp, btnRow, rowKey .. "-rename", Strings("Rename"), {
        size = chipSize, kind = "neutral",
        action = function() imp:_beginRename(version, slot.id) end,
      })
    end
    if imp.onEditSave and slot.exists then
      button(imp, btnRow, rowKey .. "-edit", Strings("Edit"), {
        size = chipSize, kind = "accent",
        action = function() imp.onEditSave(version, slot.id) end,
      })
    end
    local armed = deleteArmed(imp, "slot", slot.id, version)
    -- width pinned so arming to "Sure?" never reflows the row under the
    -- pointer (#433).  Pinned to the wider of the two captions, not to the
    -- unarmed one: English "Delete" is the longer of the pair, but a
    -- translation need not keep that order (Japanese さくじょ is shorter than
    -- よろしい？), and pinning to the shorter one clips the other.
    button(imp, btnRow, rowKey .. "-del", DELETE_LABEL(armed), {
      w = math.ceil(math.max(textWidth(chipSize, DELETE_LABEL(false)),
                             textWidth(chipSize, DELETE_LABEL(true)))) + 26,
      size = chipSize, kind = armed and "dangerArmed" or "danger",
      keepArm = true,
      action = function()
        imp:pressDelete("slot", slot.id, version, function()
          imp:_deleteSlot(version, slot.id)
        end)
      end,
    })
  end

  button(imp, c, "slot-new-" .. version, Strings("+ New save slot"), {
    w = "100%", h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
    action = function() imp:_newSlot(version) end,
  })
end

local function buildGamePanel(imp, parent, m, version)
  imp.panelVersion = version
  local info = GameVersion.info(version)
  local locked = info == nil
  local gameName = info and (info.launcherName or info.displayName)
    or tostring(version)
  local ready = (not locked) and imp.ready[version] or false

  -- header: name + status pill
  local head = mk({ parent = parent, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    alignItems = "center", gap = 12 * m.s })
  label(head, gameName, 22 * m.s + 4, C("white"), { textWrap = false })
  if ready then pill(head, Strings("GOOD TO GO"), "green", 11 * m.s + 1)
  elseif locked then pill(head, Strings("COMING SOON"), "disabled", 11 * m.s + 1)
  else pill(head, Strings("ROM REQUIRED"), "gold", 11 * m.s + 1) end

  -- Two columns get explicit pixel widths (percentage children inside a
  -- flex-grown column do not resolve, LayoutEngine LAY_004).  Single-column
  -- mode adds the cards straight to the page instead of nesting columns:
  -- the engine under-measures a vertical column-of-columns' auto height,
  -- which pushed the footer up over the save-slot card on phone shapes.
  local grid, left, right
  if m.twoCol then
    grid = mk({ parent = parent, width = "100%",
      positioning = "flex", flexDirection = "horizontal",
      gap = m.colGap, alignItems = "flex-start" })
    left = mk({ parent = grid, width = m.colW,
      positioning = "flex", flexDirection = "vertical", gap = 12 * m.s })
    right = mk({ parent = grid, width = m.colW,
      positioning = "flex", flexDirection = "vertical" })
  else
    left, right = parent, parent
  end
  buildRomCard(imp, left, m, version, info, ready, locked)
  buildSaveFilesCard(imp, left, m, version, ready, locked)
  if imp.onEditTouchControls then
    button(imp, left, "touch-controls", Strings("Touch Controls"), {
      w = "100%", h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
      action = function() imp.onEditTouchControls() end,
    })
  end
  button(imp, left, "play-" .. version,
    ready and (Strings("Play ") .. gameName)
      or (locked and Strings("Coming soon") or Strings("Import a ROM to play")),
    {
      w = "100%", h = math.max(48, 52 * m.s), size = 18 * m.s + 2,
      kind = ready and "primary" or "disabled",
      action = ready and function() imp:play(version) end or nil,
    })

  if not locked then
    buildSlotCard(imp, right, m, version)
  end
  -- The right subtree may have grown after FlexLove last measured its
  -- grandparent. Refresh only the desktop grid once both columns are complete.
  if grid then refreshAutoHeight(grid) end
end

-- ------- mods panel

local function buildModsPanel(imp, parent, m)
  imp:_ensureMods()
  local ModUpdate = require("src.mods.ModUpdate")
  local mods = imp.mods or {}
  local enabledCount = 0
  for _, mod in ipairs(mods) do
    if mod.enabled then enabledCount = enabledCount + 1 end
  end

  local title = Strings("Mods")
  local count = Strings("%d of %d enabled", enabledCount, #mods)
  local importLabel = imp:_modsImportButtonLabel()
  local items = {
    { size = 22 * m.s + 4, text = title },
    { size = 12 * m.s + 2, text = count },
    { size = 13 * m.s + 1, text = importLabel, btn = true },
  }
  if #mods > 0 then
    items[#items + 1] = { size = 11 * m.s + 1, text = Strings("Enable all"), btn = true }
    items[#items + 1] = { size = 11 * m.s + 1, text = Strings("Disable all"), btn = true }
  end
  local head, buttonsRow = headRows(parent, m, items)
  label(head, title, 22 * m.s + 4, C("white"), { textWrap = false })
  label(head, count, 12 * m.s + 2, C("warn"), { textWrap = false })
  local btnRow = buttonsRow()
  if #mods > 0 then
    button(imp, btnRow, "mods-enable-all", Strings("Enable all"), {
      size = 11 * m.s + 1, kind = "neutral",
      action = function() imp:_setAllMods(true) end,
    })
    button(imp, btnRow, "mods-disable-all", Strings("Disable all"), {
      size = 11 * m.s + 1, kind = "neutral",
      action = function() imp:_setAllMods(false) end,
    })
  end
  button(imp, btnRow, "mods-import", importLabel, {
    h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
    action = function() imp:chooseMod() end,
  })

  if imp.modNotice then
    label(parent, imp.modNotice.text, 12 * m.s + 2,
      C(imp.modNotice.ok and "green" or "danger"))
  else
    label(parent, imp:_modsDefaultHint(), 12 * m.s + 2, C("warn"))
  end

  if #mods == 0 then
    local box = mk({
      parent = parent, width = "100%", height = 110 * m.s,
      backgroundColor = C("card", 0.4),
      border = 1, borderColor = C("border", 0.3), cornerRadius = 14,
      positioning = "flex", justifyContent = "center", alignItems = "center",
      padding = { horizontal = 16 },
    })
    label(box, imp:_modsEmptyHint(),
      math.floor(12 * m.s + 2.5), C("detail"), { textAlign = "center" })
    return
  end

  -- Sort row: Name / Popularity / Release date / Last updated.  The choice
  -- persists in options.modSort; data-less mods (no github field, or a
  -- cache that predates the feature) sink to the bottom of data sorts.
  local sortKey = imp.modSort or "name"
  if imp.modSort == nil then
    local ok, opts = pcall(require("src.core.SaveData").loadOptions)
    if ok and type(opts) == "table" and type(opts.modSort) == "string" then
      sortKey = opts.modSort
      imp.modSort = sortKey
    end
  end
  local sortRow = mk({ parent = parent, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    flexWrap = "wrap", alignItems = "center", gap = 6 * m.s })
  label(sortRow, Strings("Sort:"), 11 * m.s + 2, C("detail"), { textWrap = false })
  local sorts = {
    { key = "name", label = Strings("Name") },
    { key = "popularity", label = Strings("Popularity") },
    { key = "release", label = Strings("Release date") },
    { key = "updated", label = Strings("Last updated") },
  }
  for _, s in ipairs(sorts) do
    local active = sortKey == s.key
    local key = "mod-sort-" .. s.key
    mk({
      parent = sortRow, text = s.label,
      textColor = active and C("green")
        or (imp._hot[key] and C("white") or C("detail")),
      textSize = 11 * m.s + 2, textAlign = "center-center", autoScaleText = false,
      backgroundColor = active and C("green", 0.18) or C("border", 0.10),
      border = 1,
      borderColor = active and C("green", 0.6) or C("border", 0.35),
      cornerRadius = 999,
      padding = { horizontal = 10, vertical = 4 },
      onEvent = handler(imp, key, function()
        imp.modSort = s.key
        pcall(function()
          local SaveData = require("src.core.SaveData")
          local opts = SaveData.loadOptions()
          opts.modSort = s.key
          SaveData.saveOptions(opts)
        end)
      end),
    })
  end

  -- Immediate mode rebuilds this panel every frame; re-sorting the whole
  -- mod list per frame (with lowercased-string allocations in the
  -- comparator) fed the GC for nothing. Cache the sorted array, keyed on
  -- the list identity/length, the sort mode, and the update-info revision
  -- that _syncModUpdateInfo bumps when release data changes.
  local cache = imp._modSortCache
  if cache and cache.src == mods and cache.n == #mods
      and cache.key == sortKey and cache.rev == (imp._modUpdateRev or 0) then
    mods = cache.list
  else
  local sorted = {}
  for i, v in ipairs(mods) do sorted[i] = v end
  table.sort(sorted, function(a, b)
    local function value(mod)
      if sortKey == "name" then return (mod.name or ""):lower() end
      local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)
      if sortKey == "popularity" then
        return info and info.downloads and info.downloads.total or -1
      end
      local date = info and info.dates
      if sortKey == "release" then
        return date and date.first or "0000-00-00"
      end
      return date and date.latest or "0000-00-00"
    end
    local va, vb = value(a), value(b)
    if va ~= vb then
      if sortKey == "name" then return va < vb end
      return va > vb  -- data sorts newest / most popular first
    end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
  imp._modSortCache = { src = mods, n = #mods, key = sortKey,
    rev = imp._modUpdateRev or 0, list = sorted }
  mods = sorted
  end

  -- Explicit column widths AND heights: a flex-grown container collapses
  -- its children's layout in this engine, and card auto-height came up
  -- short on some displays, dropping the bottom action row out of the card.
  -- Everything is measured with the same integer-sized fonts the labels
  -- render with, and the card gets the exact sum.
  local innerW = m.contentW - 32
  local clusterW = math.max(96, math.floor(110 * m.s))
  local bodyW = innerW - clusterW - 10
  local nameSize = math.floor(15 * m.s + 2.5)
  local smallSize = math.floor(12 * m.s + 1.5)
  local badgeSize = math.floor(10 * m.s + 1.5)
  local chipSize = math.floor(11 * m.s + 1.5)
  local btnH = math.ceil(textHeight(chipSize)) + 14
  local badgeH = math.ceil(textHeight(badgeSize)) + 6
  local toggleH = math.floor(24 * m.s + 2) + 8
  local pillH = math.ceil(textHeight(chipSize)) + 8
  local clusterH = pillH + 6 + toggleH
  for _, mod in ipairs(mods) do
    local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)
    local checkLine, checkCol
    if info and info.status == "available" then
      checkLine = Strings("Checked for updates - v%s available",
        tostring(info.latest))
      checkCol = "green"
    elseif info and info.status == "current" then
      checkLine, checkCol = Strings("Checked for updates - up to date"), "green"
    elseif info and info.status == "error" then
      checkLine, checkCol = Strings("Checked for updates - failed"), "danger"
    elseif mod.github and mod.github ~= "" then
      checkLine, checkCol = Strings("Not checked for updates yet"), "warn"
    end
    -- Total downloads plus first/latest release dates, all from the same
    -- cached release fetch.  Only shown once that data actually carries
    -- counts, so a pre-downloads cache entry costs the line, not a wrong "0".
    local dlLine
    if info and info.downloads then
      local d = info.dates
      dlLine = ModUpdate.statsLine(info.downloads.total,
        d and d.first, d and d.latest)
    end

    -- measure the body: name (with the badge beside it only when it fits),
    -- version, check line, wrapped description
    local badgeW = math.ceil(textWidth(badgeSize, mod.badge)) + 14
    local nameH = math.ceil(textHeight(nameSize))
    local badgeBesideName =
      math.ceil(textWidth(nameSize, mod.name)) + 8 + badgeW <= bodyW
    local bodyH = badgeBesideName and math.max(nameH, badgeH)
      or (nameH + 4 + badgeH)
    bodyH = bodyH + 4 + math.ceil(textHeight(smallSize))
    if checkLine then
      bodyH = bodyH + 4 + wrapHeight(smallSize, checkLine, bodyW)
    end
    if dlLine then
      bodyH = bodyH + 4 + wrapHeight(smallSize, dlLine, bodyW)
    end
    if mod.description ~= "" then
      bodyH = bodyH + 4 + wrapHeight(smallSize, mod.description, bodyW)
    end
    local rowH = math.max(bodyH, clusterH)

    -- how many lines the right-aligned action row needs
    local btnRowW = math.ceil(textWidth(chipSize, DELETE_LABEL(false))) + 26
    local updLabel, updKind = Strings("Check for updates"), "neutral"
    if info and info.status == "available" then
      updLabel, updKind = Strings("Update"), "accent"
    elseif info and info.status == "current" then
      updLabel = Strings("Check again")
    end
    if mod.github and mod.github ~= "" then
      btnRowW = btnRowW + math.ceil(textWidth(chipSize, updLabel)) + 26 + 6
        + math.ceil(textWidth(chipSize, Strings("Versions"))) + 26 + 6
    end
    local btnLines = math.max(1, math.ceil(btnRowW / innerW))
    local cardH = 28 + rowH + 8 + btnLines * btnH + (btnLines - 1) * 6

    local c = card(parent, { padding = m.cardPad, gap = 8, height = cardH })
    local row = mk({ parent = c, width = "100%", height = rowH,
      positioning = "flex", flexDirection = "horizontal",
      gap = 10, alignItems = "flex-start" })
    local body = mk({ parent = row, width = bodyW, height = rowH,
      positioning = "flex", flexDirection = "vertical", gap = 4 })
    local function badge(parent2)
      mk({
        parent = parent2, text = mod.badge, autoScaleText = false,
        textColor = mod.experimental and C("gold") or C("warn"),
        textSize = badgeSize, textAlign = "center-center",
        width = badgeW, height = badgeH,
        border = 1, borderColor = C("border", 0.5), cornerRadius = 5,
      })
    end
    if badgeBesideName then
      local nameRow = mk({ parent = body, width = "100%",
        height = math.max(nameH, badgeH),
        positioning = "flex", flexDirection = "horizontal",
        alignItems = "center", gap = 8 })
      label(nameRow, mod.name, nameSize, C("white"), { textWrap = false })
      badge(nameRow)
    else
      label(body, mod.name, nameSize, C("white"),
        { width = "100%", textWrap = false, textOverflow = "ellipsis" })
      badge(body)
    end
    label(body, "v" .. tostring(mod.version or "?"), smallSize, C("detail"))
    if checkLine then
      label(body, checkLine, smallSize, C(checkCol), { width = "100%" })
    end
    if dlLine then
      label(body, dlLine, smallSize, C("gold"), { width = "100%" })
    end
    if mod.description ~= "" then
      label(body, mod.description, smallSize, C("detail"), { width = "100%" })
    end

    local cluster = mk({ parent = row, width = clusterW, height = clusterH,
      positioning = "flex", flexDirection = "vertical",
      alignItems = "flex-end", gap = 6 })
    local chipText, chipCol = modStatusChip(mod.status)
    pill(cluster, chipText, chipCol, chipSize)
    local togKey = "mod-toggle-" .. mod.id
    local togWrap = mk({ parent = cluster,
      width = math.floor(46 * m.s + 4) + 8, height = toggleH,
      padding = 4,
      onEvent = handler(imp, togKey, function() imp:_toggleMod(mod.id) end),
    })
    toggleSwitch(togWrap, mod.enabled, math.floor(46 * m.s + 4),
      math.floor(24 * m.s + 2), "tog:" .. mod.id)

    local btnRow = mk({ parent = c, width = "100%",
      height = btnLines * btnH + (btnLines - 1) * 6,
      positioning = "flex", flexDirection = "horizontal",
      justifyContent = "flex-end", flexWrap = "wrap", gap = 6 })
    if mod.github and mod.github ~= "" then
      button(imp, btnRow, "mod-upd-" .. mod.id, updLabel, {
        size = chipSize, kind = updKind,
        action = function() imp:_modGithubAction(mod.id, "update") end,
      })
      button(imp, btnRow, "mod-ver-" .. mod.id, Strings("Versions"), {
        size = chipSize, kind = "neutral",
        action = function() imp:_modGithubAction(mod.id, "versions") end,
      })
    end
    local armed = deleteArmed(imp, "mod", mod.id, nil)
    button(imp, btnRow, "mod-del-" .. mod.id, DELETE_LABEL(armed), {
      w = math.ceil(textWidth(chipSize, DELETE_LABEL(false))) + 26,
      size = chipSize, kind = armed and "dangerArmed" or "danger",
      keepArm = true,
      action = function()
        imp:pressDelete("mod", mod.id, nil, function()
          imp:_deleteMod(mod.id)
        end)
      end,
    })
  end
end

-- ------- find mods panel

local function buildFindPanel(imp, parent, m)
  imp._findThumbFetched = false
  imp:_ensureFind()
  imp:_ensureMods()
  local ModIndex = require("src.mods.ModIndex")
  local sources = imp.findSources or {}
  local rows = imp:_findRows()
  local total = #((imp.findIndex and imp.findIndex.mods) or {})

  local title = Strings("Find Mods")
  local count = (#sources > 0) and ((#rows == total) and Strings("%d mods listed", total)
    or Strings("%d of %d mods", #rows, total)) or nil
  local addLabel = (#sources == 0) and Strings("Add an index") or Strings("Add index")
  local items = {
    { size = 22 * m.s + 4, text = title },
    { size = 13 * m.s + 1, text = addLabel, btn = true },
  }
  if count then items[#items + 1] = { size = 12 * m.s + 2, text = count } end
  if #sources > 0 then
    items[#items + 1] = { size = 13 * m.s + 1, text = Strings("Refresh"), btn = true }
  end
  local head, buttonsRow = headRows(parent, m, items)
  label(head, title, 22 * m.s + 4, C("white"), { textWrap = false })
  if count then
    label(head, count, 12 * m.s + 2, C("warn"), { textWrap = false })
  end
  local btnRow = buttonsRow()
  if #sources > 0 then
    button(imp, btnRow, "find-refresh", Strings("Refresh"), {
      h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
      action = function()
        imp._findSearchFocus = false
        imp:_disarmTextInput()
        imp:_refreshFind(true)
      end,
    })
  end
  button(imp, btnRow, "find-add", addLabel, {
    h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
    action = function() imp:_promptAddIndex() end,
  })

  if imp.findNotice then
    label(parent, imp.findNotice.text, 12 * m.s + 2,
      C(imp.findNotice.ok and "green" or "danger"))
  else
    label(parent, Strings(
      "Mods here are listed, not reviewed - read the source and trust the author."),
      12 * m.s + 2, C("warn"))
  end

  if #sources == 0 then
    local box = mk({
      parent = parent, width = "100%", height = 150 * m.s,
      border = 1, borderColor = C("border", 0.45), cornerRadius = 14,
      positioning = "flex", flexDirection = "vertical",
      justifyContent = "center", alignItems = "center", gap = 6 * m.s,
      padding = { horizontal = 20 },
    })
    label(box, Strings("No mod index added"), 15 * m.s + 2, C("white"),
      { textAlign = "center", width = "100%" })
    label(box, Strings(
      "Add an index to browse mods. An index is a published list; paste its URL or its owner/repo."),
      12 * m.s + 1, C("warn"), { textAlign = "center", width = "100%" })
    return
  end

  for _, source in ipairs(sources) do
    local srow = mk({ parent = parent, width = "100%",
      positioning = "flex", flexDirection = "horizontal",
      alignItems = "center", gap = 8 * m.s })
    label(srow, source.label or source.feed, 12 * m.s + 1, C("detail"),
      { width = m.contentW
          - (math.ceil(textWidth(11 * m.s + 1, Strings("Remove"))) + 26)
          - 8 * m.s,
        textWrap = false, textOverflow = "ellipsis" })
    button(imp, srow, "find-src-rm-" .. tostring(source.feed), Strings("Remove"), {
      size = 11 * m.s + 1, kind = "danger",
      action = function() imp:_removeIndex(source.feed) end,
    })
  end

  -- search field (hand-rolled text state, same routing as the rename modal)
  textField(imp, parent, "find-search",
    imp.findQuery or "", Strings("Search mods"),
    imp._findSearchFocus == true,
    function()
      imp:_toggleFindSearchFocus()
    end)

  local cats = (imp.findIndex and imp.findIndex.categories) or {}
  if #cats > 0 then
    local catRow = mk({ parent = parent, width = "100%",
      positioning = "flex", flexDirection = "horizontal",
      flexWrap = "wrap", gap = 6 * m.s })
    local function catChip(name, id, active)
      local key = "find-cat-" .. id
      mk({
        parent = catRow, text = name,
        textColor = active and C("green")
          or (imp._hot[key] and C("white") or C("detail")),
        textSize = 11 * m.s + 2, textAlign = "center-center", autoScaleText = false,
        backgroundColor = active and C("green", 0.18) or C("border", 0.10),
        border = 1,
        borderColor = active and C("green", 0.6) or C("border", 0.35),
        cornerRadius = 999,
        padding = { horizontal = 10, vertical = 4 },
        onEvent = handler(imp, key, function()
          imp.findCategory = (id ~= "" and imp.findCategory ~= id) and id or nil
        end),
      })
    end
    catChip(Strings("All"), "", imp.findCategory == nil)
    for _, cat in ipairs(cats) do
      catChip(cat, cat, imp.findCategory == cat)
    end
  end

  if #rows == 0 then
    local box = mk({
      parent = parent, width = "100%", height = 130 * m.s,
      backgroundColor = C("card", 0.4),
      border = 1, borderColor = C("border", 0.3), cornerRadius = 14,
      positioning = "flex", flexDirection = "vertical",
      justifyContent = "center", alignItems = "center", gap = 8,
      padding = { horizontal = 20 },
    })
    mk({ parent = box, width = math.floor(30 * m.s),
      height = math.floor(30 * m.s),
      image = imp._findIcon, objectFit = "contain",
      imageTint = C("gray", 0.6) })
    label(box, (total == 0) and Strings("This index lists no mods yet.")
      or Strings("No mods match that search."),
      math.floor(13 * m.s + 1.5), C("detail"), { textAlign = "center" })
    if total > 0 then
      label(box,
        Strings("Try a different search, or clear the category filter."),
        math.floor(11 * m.s + 1.5), C("warn"), { textAlign = "center" })
    end
    return
  end

  local installed = imp:_findInstalledMap()
  local thumbW = 64 * m.s
  -- Explicit measured widths AND heights, same reasoning as the mods card:
  -- the engine's card auto-height dropped the Details/Source/Install row
  -- past the card's bottom edge on some displays.
  local innerW = m.contentW - 32
  local bodyW = innerW - thumbW - 10
  local titleSize = math.floor(15 * m.s + 2.5)
  local smallSize = math.floor(12 * m.s + 1.5)
  local chipSize = math.floor(11 * m.s + 1.5)
  local btnH = math.ceil(textHeight(chipSize)) + 14
  for _, entry in ipairs(rows) do
    local action, note = findActionFor(entry, installed[entry.id])
    -- Feed-published release stats (downloads, first/last release date) in
    -- the same gold line the MODS tab uses; absent until a feed carries them.
    local statsLine
    if entry.downloads ~= nil or entry.first_release or entry.last_release then
      statsLine = ModUpdate.statsLine(entry.downloads,
        entry.first_release, entry.last_release)
    end

    local bodyH = math.ceil(textHeight(titleSize))
      + 4 + math.ceil(textHeight(smallSize))
    if statsLine then bodyH = bodyH + 4 + wrapHeight(smallSize, statsLine, bodyW) end
    if note then bodyH = bodyH + 4 + wrapHeight(smallSize, note, bodyW) end
    if entry.summary and entry.summary ~= "" then
      bodyH = bodyH + 4 + wrapHeight(smallSize, entry.summary, bodyW)
    end
    local rowH = math.max(thumbW, bodyH)
    local btnRowW = math.ceil(textWidth(chipSize, Strings("Details"))) + 26
    if entry.repo then
      btnRowW = btnRowW + 6 + math.ceil(textWidth(chipSize, Strings("Source"))) + 26
    end
    if action then
      btnRowW = btnRowW + 6 + math.ceil(textWidth(chipSize, action)) + 26
    else
      btnRowW = btnRowW + 6
        + math.ceil(textWidth(chipSize, Strings("Unavailable"))) + 20
    end
    local btnLines = math.max(1, math.ceil(btnRowW / innerW))
    local cardH = 28 + rowH + 8 + btnLines * btnH + (btnLines - 1) * 6

    local c = card(parent, { padding = m.cardPad, gap = 8, height = cardH })
    local row = mk({ parent = c, width = "100%", height = rowH,
      positioning = "flex", flexDirection = "horizontal",
      gap = 10, alignItems = "flex-start" })
    local image = imp:_findThumb(entry)
    if image then
      mk({ parent = row, image = image, objectFit = "contain",
        width = thumbW, height = thumbW, cornerRadius = 8 })
    else
      mk({ parent = row, width = thumbW, height = thumbW,
        backgroundColor = C("border", 0.18), cornerRadius = 8,
        text = "MOD", textColor = C("disabled"),
        textSize = math.floor(10 * m.s + 1.5), textAlign = "center-center",
        autoScaleText = false })
    end
    local body = mk({ parent = row, width = bodyW, height = rowH,
      positioning = "flex", flexDirection = "vertical", gap = 4 })
    label(body, entry.title or entry.id, titleSize, C("white"),
      { width = "100%", textWrap = false, textOverflow = "ellipsis" })
    local meta = "v" .. tostring(ModIndex.displayVersion(entry))
    if entry.author then meta = meta .. "  -  " .. entry.author end
    if entry.categories and entry.categories[1] then
      meta = meta .. "  -  " .. entry.categories[1]
    end
    label(body, meta, smallSize, C("detail"),
      { width = "100%", textWrap = false, textOverflow = "ellipsis" })
    if statsLine then
      label(body, statsLine, smallSize, C("gold"), { width = "100%" })
    end
    if note then label(body, note, smallSize, C("green"), { width = "100%" }) end
    if entry.summary and entry.summary ~= "" then
      label(body, entry.summary, smallSize, C("detail"), { width = "100%" })
    end

    local btnRow = mk({ parent = c, width = "100%",
      height = btnLines * btnH + (btnLines - 1) * 6,
      positioning = "flex", flexDirection = "horizontal",
      justifyContent = "flex-end", flexWrap = "wrap", gap = 6 })
    if not action then
      pill(btnRow, Strings("Unavailable"), "gold", chipSize)
    end
    button(imp, btnRow, "find-det-" .. entry.id, Strings("Details"), {
      size = chipSize, kind = "neutral",
      action = function() imp:_findShowDetails(entry) end,
    })
    if entry.repo then
      button(imp, btnRow, "find-repo-" .. entry.id, Strings("Source"), {
        size = chipSize, kind = "neutral",
        action = function() love.system.openURL(entry.repo) end,
      })
    end
    if action then
      button(imp, btnRow, "find-inst-" .. entry.id, action, {
        size = chipSize, kind = "accent",
        action = function() imp:_findConfirmInstall(entry) end,
      })
    end
  end
end

-- ------- updater banner + footer

local function buildBanner(imp, parent, m)
  if not imp.Check then return end
  local ok, st = pcall(imp.Check.state)
  st = (ok and type(st) == "table") and st or nil
  local status = st and st.status
  if status ~= "available" and status ~= "downloading"
      and status ~= "ready" and status ~= "needs_full" then
    return
  end
  local c = card(parent, {
    padding = { horizontal = 16, vertical = 12 },
    borderColor = C("gold", 0.5), gap = 8 * m.s,
  })
  local row = mk({ parent = c, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    alignItems = "center", gap = 10 * m.s })
  if status == "downloading" then
    label(row, Strings("Downloading update"), 13 * m.s + 1, C("detail"),
      { flex = 1 })
    progressBar(c, st.progress, "gold", math.max(8, 10 * m.s))
  else
    local msg, btnLabel, action
    if status == "available" then
      msg = st.latest and (Strings("Update v") .. st.latest .. Strings(" available"))
        or Strings("An update is available")
      btnLabel = Strings("Update")
      action = function() pcall(imp.Check.download) end
    elseif status == "needs_full" then
      msg = Strings("A new version needs a fresh download")
      btnLabel = Strings("Open releases")
      action = function() love.system.openURL(imp.Check.releaseUrl()) end
    else
      msg = Strings("Update downloaded")
      btnLabel = Strings("Restart to update")
      action = function() require("src.core.HostShell").restart() end
    end
    label(row, msg, 13 * m.s + 1, C("white"), { flex = 1 })
    button(imp, row, "updater", btnLabel, {
      h = m.btnH, size = 13 * m.s, kind = "primary", action = action,
    })
  end
end

local TRUST_WARNING = "if you did not get this from bryanthaboi's github "
  .. "or a link from the discord that bryanthaboi himself posted, just know "
  .. "it might have been tampered with. go to the discord to verify "
  .. COMMUNITY_URL .. " (or click the logo above)"

local function buildFooter(imp, parent, m)
  mk({ parent = parent, width = "100%", height = 1,
    backgroundColor = C("border", 0.18) })
  -- The BCG mark is dark ink; invert it to white for the dark panel.
  imp.invertShader = imp.invertShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
    }
  ]])
  local bw, bh = imp.bcg:getDimensions()
  local scale = math.min((180 * m.s) / bw, (44 * m.s) / bh)
  mk({
    parent = parent, width = bw * scale, height = bh * scale,
    alignSelf = "center",
    customDraw = function(el)
      love.graphics.setShader(imp.invertShader)
      love.graphics.setColor(1, 1, 1, imp._hot.bcg and 1 or 0.85)
      love.graphics.draw(imp.bcg, el.x, el.y, 0,
        el.width / bw, el.height / bh)
      love.graphics.setShader()
    end,
    onEvent = handler(imp, "bcg", function()
      love.system.openURL(COMMUNITY_URL)
    end),
  })
  label(parent, TRUST_WARNING, 10 * m.s + 2, C("warn"),
    { width = "100%", textAlign = "center" })
  -- the link gets a full-width, center-aligned row of its own: alignSelf on
  -- an auto-width label was not honored and left it hugging the margin
  local linkRow = mk({ parent = parent, width = "100%",
    positioning = "flex", justifyContent = "center",
    padding = { bottom = 18 } })
  label(linkRow, COMMUNITY_URL, 11 * m.s + 2,
    C("link", imp._hot.bois and 1 or 0.85), {
      textWrap = false,
      onEvent = handler(imp, "bois", function()
        love.system.openURL(COMMUNITY_URL)
      end),
    })
end

-- ------- modals

local function modalOverlay(imp, m, closeKey, onClose)
  local overlay = mk({
    z = 1000,
    x = 0, y = 0, width = m.W, height = m.H,
    backgroundColor = rgba(4, 6, 16, 0.72),
    positioning = "flex", justifyContent = "center", alignItems = "center",
    onEvent = onClose and handler(imp, closeKey, onClose) or function() end,
  })
  return overlay
end

local function modalPanel(overlay, m, w, props)
  local p = {
    parent = overlay,
    width = math.min(w, m.W - 24),
    backgroundColor = rgba(12, 17, 38, 0.98),
    border = 1, borderColor = C("border", 0.5),
    cornerRadius = 12,
    positioning = "flex", flexDirection = "vertical",
    gap = 10 * m.s, padding = { horizontal = 16, vertical = 14 },
    -- swallow clicks so the overlay's close handler stays outside the panel
    onEvent = function() end,
  }
  for k, v in pairs(props or {}) do p[k] = v end
  return mk(p)
end

-- Shared prompt: title, hand-rolled text field, hint, action row.
local function buildPrompt(imp, m, spec)
  local overlay = modalOverlay(imp, m, spec.key .. "-out")
  local panel = modalPanel(overlay, m, spec.w or 460 * m.s)
  label(panel, spec.title, 15 * m.s + 2, C("white"))
  if spec.hint then
    label(panel, spec.hint, 12 * m.s + 1, C("detail"))
  end
  textField(imp, panel, spec.key .. "-field", spec.text or "", nil, true)
  local btnRow = mk({ parent = panel, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    justifyContent = "flex-end", gap = 8 * m.s })
  if spec.paste then
    button(imp, btnRow, spec.key .. "-paste", Strings("Paste"), {
      size = 12 * m.s + 1, kind = "accent", action = spec.paste,
    })
    mk({ parent = btnRow, flex = 1 })
  end
  button(imp, btnRow, spec.key .. "-cancel", Strings("Cancel"), {
    size = 12 * m.s + 1, kind = "neutral", action = spec.cancel,
  })
  button(imp, btnRow, spec.key .. "-ok", spec.okLabel or Strings("Save"), {
    size = 12 * m.s + 1, kind = "primary", action = spec.commit,
  })
  if spec.footnote then
    label(panel, spec.footnote, 11 * m.s + 1, C("warn"))
  end
end

local function buildConfirmModal(imp, m)
  local c = imp._modConfirm
  local overlay = modalOverlay(imp, m, "confirm-out")
  local panel = modalPanel(overlay, m, 420 * m.s)
  label(panel, c.title or Strings("Confirm"), 15 * m.s + 2, C("white"))
  for _, line in ipairs(c.lines or {}) do
    label(panel, line, 12 * m.s + 1, C("detail"))
  end
  local btnRow = mk({ parent = panel, width = "100%",
    positioning = "flex", flexDirection = "horizontal", gap = 10 * m.s })
  button(imp, btnRow, "confirm-yes", c.yesLabel or Strings("OK"), {
    flex = 1, h = m.btnH, size = 13 * m.s + 1, kind = "primary",
    action = function()
      imp._modConfirm = nil
      if c.indexEntry then
        imp:_findInstall(c.indexEntry)
      elseif c.kind == "update" then
        imp:_confirmModUpdate(c.id, c.release)
      elseif c.kind == "enableAll" then
        imp:_setAllMods(true, true)
      else
        imp:_toggleMod(c.id, true)
      end
    end,
  })
  button(imp, btnRow, "confirm-no", Strings("Cancel"), {
    flex = 1, h = m.btnH, size = 13 * m.s + 1, kind = "neutral",
    action = function() imp._modConfirm = nil end,
  })
end

local function buildTextModal(imp, m, title, body, closeFn, scrollId)
  local overlay = modalOverlay(imp, m, "textmodal-out")
  local panel = modalPanel(overlay, m, 520 * m.s)
  label(panel, title, 15 * m.s + 2, C("white"))
  local scroller = mk({
    parent = panel, id = scrollId, width = "100%",
    height = math.min(m.H * 0.5, 340 * m.s),
    overflowY = "scroll", hideScrollbars = true,
    positioning = "flex", flexDirection = "vertical",
    padding = { right = 8 },
  })
  label(scroller, body, 12 * m.s + 1, C("detail"), { width = "100%" })
  button(imp, panel, "textmodal-close", Strings("Close"), {
    w = "100%", h = m.btnH, size = 13 * m.s, kind = "neutral",
    action = closeFn,
  })
end

local function buildVersionsModal(imp, m)
  local ModUpdate = require("src.mods.ModUpdate")
  local v = imp._modVersions
  local overlay = modalOverlay(imp, m, "versions-out")
  local panel = modalPanel(overlay, m, 520 * m.s)
  label(panel, Strings("Other versions: ") .. tostring(v.name),
    15 * m.s + 2, C("white"))
  local info = imp:_modUpdateInfo(v.id)
  local statusTxt = Strings("Installed: v") .. tostring(v.current)
  local statusCol = "detail"
  if info and info.status == "available" then
    statusTxt = statusTxt .. "  -  " .. Strings("Update v") .. tostring(info.latest)
    statusCol = "green"
  elseif info and info.status == "current" then
    statusTxt = statusTxt .. "  -  " .. Strings("Up to date")
    statusCol = "green"
  end
  label(panel, statusTxt, 12 * m.s + 1, C(statusCol))
  local scroller = mk({
    parent = panel, id = "modversions", width = "100%",
    height = math.min(m.H * 0.5, 320 * m.s), overflowY = "scroll", hideScrollbars = true,
    positioning = "flex", flexDirection = "vertical", gap = 6 * m.s,
    padding = { right = 8 },
  })
  for i, rel in ipairs(v.releases) do
    local row = mk({ parent = scroller, width = "100%",
      backgroundColor = C("bg", 0.5),
      border = 1, borderColor = C("border", 0.35), cornerRadius = 8,
      positioning = "flex", flexDirection = "horizontal",
      alignItems = "center", gap = 8 * m.s,
      padding = { horizontal = 10, vertical = 8 } })
    local text = "v" .. rel.version
    if rel.version == v.current then text = text .. Strings(" (installed)") end
    if rel.prerelease then text = text .. " pre" end
    local body = mk({ parent = row, flex = 1,
      positioning = "flex", flexDirection = "vertical", gap = 2 * m.s })
    label(body, text, 12 * m.s + 1,
      rel.version == v.current and C("warn") or C("white"),
      { textWrap = false })
    local preview = ModUpdate.previewLine(rel.body or "", 90)
    if preview ~= "" then
      label(body, preview, 11 * m.s + 1, C("detail"),
        { textWrap = false, textOverflow = "ellipsis" })
    end
    if type(rel.body) == "string" and rel.body:match("%S") then
      button(imp, row, "ver-notes-" .. i, Strings("Read more"), {
        size = 11 * m.s, kind = "neutral",
        action = function()
          imp._modReleaseNotes = { version = rel.version,
            body = rel.body or "", scroll = 0 }
        end,
      })
    end
    if rel.version ~= v.current then
      button(imp, row, "ver-inst-" .. i, Strings("Install"), {
        size = 11 * m.s, kind = "accent",
        action = function() imp:_installModVersion(v.id, rel) end,
      })
    end
  end
  button(imp, panel, "versions-close", Strings("Close"), {
    w = "100%", h = m.btnH, size = 13 * m.s, kind = "neutral",
    action = function() imp._modVersions = nil end,
  })
end

local function buildSettingsModal(imp, m)
  local model = imp._settings
  local overlay = modalOverlay(imp, m, "settings-out")
  local panel = modalPanel(overlay, m, 640 * m.s, {
    height = math.min(m.H - 40, m.H * 0.88),
  })
  local head = mk({ parent = panel, width = "100%",
    positioning = "flex", flexDirection = "horizontal",
    justifyContent = "space-between", alignItems = "center" })
  label(head, Strings("Settings"), 17 * m.s + 3, C("white"), { textWrap = false })
  button(imp, head, "settings-close", Strings("Close"), {
    size = 12 * m.s + 1, kind = "neutral",
    action = function() imp:_closeSettings() end,
  })
  label(panel, Strings(
    "Saved to your options file; the game applies these on its next start."),
    11 * m.s + 2, C("warn"))
  local scroller = mk({
    parent = panel, id = "settings-scroll", width = "100%",
    flex = 1, overflowY = "scroll", hideScrollbars = true,
    positioning = "flex", flexDirection = "vertical", gap = 6 * m.s,
    padding = { right = 8 },
  })
  for si, section in ipairs(model.sections) do
    label(scroller, section.title, 12 * m.s + 2, C("gray"), {
      width = "100%",
      margin = { top = si == 1 and 0 or 12 },
    })
    for ri, row in ipairs(section.rows) do
      local key = "set-" .. si .. "-" .. ri
      local rowEl = mk({ parent = scroller, width = "100%",
        backgroundColor = C("rowBg", 0.6),
        border = 1, borderColor = C("border", 0.22), cornerRadius = 8,
        positioning = "flex", flexDirection = "horizontal",
        alignItems = "center", gap = 8 * m.s,
        padding = { horizontal = 12, vertical = 8 } })
      label(rowEl, row.label, 13 * m.s + 1, C("white"),
        { flex = 1, textWrap = false, textOverflow = "ellipsis" })
      if row.editText then
        label(rowEl, row.value(), 13 * m.s + 1, C("detail"), { textWrap = false })
        button(imp, rowEl, key .. "-edit", Strings("Edit"), {
          size = 11 * m.s + 1, kind = "accent",
          action = function()
            imp._settingsText = { row = row, text = tostring(row.value() or ""),
              maxLen = row.editText.maxLen }
            imp:_armTextInput()
          end,
        })
      else
        button(imp, rowEl, key .. "-prev", "<", {
          size = 13 * m.s + 1, kind = "neutral", pad = { horizontal = 10, vertical = 4 },
          action = function()
            if row.step and row.step(-1) then model.save() end
          end,
        })
        label(rowEl, row.value(), 13 * m.s + 1, C("green"), {
          width = 110 * m.s, textAlign = "center", textWrap = false,
        })
        button(imp, rowEl, key .. "-next", ">", {
          size = 13 * m.s + 1, kind = "neutral", pad = { horizontal = 10, vertical = 4 },
          action = function()
            if row.step and row.step(1) then model.save() end
          end,
        })
      end
    end
  end
end

local function buildModals(imp, m)
  if imp._settingsText then
    local st = imp._settingsText
    buildPrompt(imp, m, {
      key = "settext", title = st.row.label,
      text = st.text,
      okLabel = Strings("Save"),
      commit = function() imp:_commitSettingsText() end,
      cancel = function()
        imp._settingsText = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel"),
    })
    return
  end
  if imp._settings then
    buildSettingsModal(imp, m)
    return
  end
  if imp._rename then
    buildPrompt(imp, m, {
      key = "rename", title = Strings("Name save slot"),
      text = imp._rename.text,
      okLabel = Strings("Save"),
      commit = function() imp:_commitRename() end,
      cancel = function()
        imp._rename = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel - empty clears"),
    })
    return
  end
  if imp._indexPrompt then
    buildPrompt(imp, m, {
      key = "index", title = Strings("Add a mod index"),
      hint = Strings("Paste the index URL, or its owner/repo."),
      text = imp._indexPrompt.text or "",
      okLabel = Strings("Add"),
      commit = function() imp:_commitAddIndex() end,
      cancel = function()
        imp._indexPrompt = nil
        imp:_disarmTextInput()
      end,
      paste = function() imp:_pasteIndexUrl() end,
      footnote = Strings("Enter to add - Esc to cancel"),
    })
    return
  end
  if imp._modConfirm then
    buildConfirmModal(imp, m)
    return
  end
  if imp._modReleaseNotes then
    local ModUpdate = require("src.mods.ModUpdate")
    local n = imp._modReleaseNotes
    local body = ModUpdate.cleanBody(n.body or "", 0)
    if body == "" then body = Strings("(No release notes.)") end
    buildTextModal(imp, m, "v" .. tostring(n.version) .. Strings(" notes"),
      body, function() imp._modReleaseNotes = nil end, "release-notes")
    return
  end
  if imp._findDetails then
    local ModUpdate = require("src.mods.ModUpdate")
    local d = imp._findDetails
    local body = ModUpdate.cleanBody(d.body or "", 0)
    if body == "" then body = Strings("(No description.)") end
    buildTextModal(imp, m, d.title, body,
      function() imp._findDetails = nil end, "find-details")
    return
  end
  if imp._modVersions then
    buildVersionsModal(imp, m)
    return
  end
end

-- ------- pad cursor overlay (drawn after FlexLove, plain love.graphics)

local function drawPadCursor(imp)
  if not imp._padCursorActive then return end
  -- Pixel-snap on NX: subpixel polygon edges shimmer on the 720p Switch
  -- framebuffer when the stick advances by fractional pixels each frame.
  local x, y = imp._padCursor.x, imp._padCursor.y
  if imp.isNX then
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.polygon("fill",
    x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
    x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.polygon("fill",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.setColor(0.05, 0.07, 0.12, 1)
  love.graphics.polygon("line",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.pop()
end

-- ------- frame assembly

function LauncherView.draw(imp)
  ensureFlex(imp)

  local W, H = love.graphics.getDimensions()
  if imp._lastW ~= W or imp._lastH ~= H then
    imp._lastW, imp._lastH = W, H
    pcall(FlexLove.resize)
    -- Persisted immediate-mode state (scroll offsets and the scroll
    -- manager's cached geometry) survives a resize keyed by element id, so
    -- the old window's scissors and scrollbar metrics kept clipping the new
    -- layout.  Drop it all; losing the scroll position on a resize is the
    -- lesser cost.
    pcall(FlexLove.clearAllStates)
  end

  -- flat backdrop, painted before the element tree renders over it
  love.graphics.setColor(C("bg"):toRGBA())
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)

  local ox, oy, sw, sh = SafeArea.rect()
  local s = clamp(sh / 768, 0.62, 1.5)
  local appW = math.min(sw, 1200 * s)
  local m = {
    W = W, H = H, s = s,
    x = ox + (sw - appW) / 2, top = oy,
    w = appW, h = sh,
    pad = clamp(appW * 0.03, 10, 24),
    chip = math.max(34, 42 * s),
    logoH = clamp(sh * 0.11, 40, 96),
    btnH = math.max(34, 40 * s),
    cardPad = { horizontal = 16, vertical = 14 },
    twoCol = appW >= 640,
  }
  m.colGap = 16 * m.s
  -- scrollbars are hidden (wheel and touch drag still scroll); the slim
  -- gutter is breathing room so content never touches the window edge
  m.gutter = 8
  m.contentW = appW - 2 * m.pad - m.gutter
  m.colW = m.twoCol and math.floor((m.contentW - m.colGap) / 2) or m.contentW

  local root = mk({
    x = m.x, y = m.top, width = m.w, height = m.h,
    positioning = "flex", flexDirection = "vertical",
  })
  buildHeader(imp, root, m)

  -- One scroll region per tab (stable id keeps its offset across frames and
  -- separate per tab), holding the panel, the updater banner and the footer.
  -- flexShrink/minHeight keep this viewport-sized so overflowY can scroll.
  local page = mk({
    parent = root, id = "page-" .. imp.tab,
    width = "100%", flex = 1, flexShrink = 1, minHeight = 0,
    overflowY = "scroll", hideScrollbars = true,
    positioning = "flex", flexDirection = "vertical",
    gap = 12 * m.s,
    padding = { left = m.pad, right = m.pad + m.gutter,
      top = 14 * m.s, bottom = 10 * m.s },
  })
  if imp.tab == "mods" then
    buildModsPanel(imp, page, m)
  elseif imp.tab == "find" then
    buildFindPanel(imp, page, m)
  else
    buildGamePanel(imp, page, m, imp.tab)
  end
  buildBanner(imp, page, m)
  buildFooter(imp, page, m)

  buildModals(imp, m)

  FlexLove.draw()
  drawPadCursor(imp)

  -- Dev harness: POKEPORT_LAUNCHER_DUMP=1 prints the laid-out tree once
  -- (id/text, x, y, w, h) so geometry bugs are read off numbers instead of
  -- guessed from screenshots.
  if os.getenv("POKEPORT_LAUNCHER_DUMP") == "1" and not imp._dumped
      and imp._shotTimer and imp._shotTimer > 1.0 then
    imp._dumped = true
    local function walk(el, depth)
      local tag = el.id or (el.text and ("%q"):format(
        tostring(el.text):sub(1, 24))) or "-"
      print(("%s%s x=%.0f y=%.0f w=%.0f h=%.0f"):format(
        ("  "):rep(depth), tag, el.x or -1, el.y or -1,
        el.width or -1, el.height or -1))
      for _, ch in ipairs(el.children or {}) do walk(ch, depth + 1) end
    end
    for _, el in ipairs(FlexLove.topElements or {}) do walk(el, 0) end
  end
end

return LauncherView

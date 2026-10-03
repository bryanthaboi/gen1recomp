-- assets/touch/README.md).  Replaces the old touch gesture recognizer:
-- every control is a real button under the thumb, so there is no
-- tap-vs-swipe classification, no deferred-A double-tap window, and no
-- added latency.
--
-- Mobile only, and only while no controller is being used: the overlay
-- shows on Android/iOS, disappears the moment a gamepad button or stick
-- is used, and comes back on the next screen touch (Game routes both
-- events here).  POKEPORT_TOUCH=1 forces it on for desktop testing
-- (main.lua then drives it with the mouse); POKEPORT_TOUCH=0 forces it
-- off everywhere.
--
-- BOTH GENERATIONS, one module.  Red/Blue/Yellow reach it from
-- src/core/Game.lua and Gold from src/core/Game2.lua, through the same six
-- seams in the same order: init + applyOptions at boot, touchpressed /
-- touchmoved / touchreleased ahead of the mod pointer hook (the pad keeps
-- first refusal, #807), noteGamepad on any controller input, joystickremoved
-- when the last pad goes away, reset on focus/visibility loss, and draw as the
-- last thing in the frame -- after the post passes, so the controls are never
-- inside the CRT/GBC grid the picture is being shown through.  One
-- options.touchControls block serves both games, so a layout edited in the
-- launcher's editor is the layout Gold draws.
--
-- Player preferences (options.touchControls) can permanently disable the
-- overlay and/or override per-control positions as normalized window
-- fractions.  Positions and a size multiplier are stored per orientation
-- (#633): options.touchControls.layouts.portrait / .landscape, picked from
-- the safe rect's aspect, so laying the pad out in landscape never moves
-- the portrait one.  The launcher editor (src/ui/TouchControlsEditor.lua)
-- writes those; applyOptions reads them at boot and whenever options
-- change.
--
-- Controls press GB buttons through Input:overlayPressed/Released -- their
-- own input source, not a keyboard alias -- so a held overlay direction
-- merges cleanly with a keyboard key or stick holding the same button,
-- and a player rebind can never detach the overlay.

local Input = require("src.core.Input")
local SafeArea = require("src.core.SafeArea")
local TouchSkin = require("src.core.TouchSkin")

local TouchControls = {}

-- idle vs pressed overlay opacity
local ALPHA = 0.65
local ALPHA_PRESSED = 0.95
-- translucent backing disc behind each control: the prompt art is dark
-- gray, so without it the controls melt into dark map areas
local BACK = 0.24
local BACK_PRESSED = 0.38

-- neutral zone at the d-pad center, as a fraction of the d-pad width;
-- inside it no direction is held (keeps a resting thumb from jittering)
local DPAD_DEAD = 0.16

-- hit slop: how far past the visible edge a press still counts, as a
-- multiplier on the control's half-width.  START/SELECT get more because
-- the glyphs are small.
local SLOP = { a = 1.3, b = 1.3, start = 1.4, select = 1.4, l = 1.25, r = 1.25 }
local HOTBAR_SLOP = 1.4

local BUTTONS_GB = { "a", "b", "start", "select" }
local BUTTONS_GBA = { "a", "b", "start", "select", "l", "r" }
local BUTTONS = BUTTONS_GB
local CONTROLS = { "dpad", "a", "b", "start", "select", "hotbar", "l", "r" }

local HOTBAR = {
  { spec = "key:f1", label = "SAVE" },
  { spec = "key:f2", label = "LOAD" },
  { spec = "key:1", label = "SPEED" },
  { spec = "key:2", label = "COLOR" },
  { spec = "key:3", label = "TILT" },
  { spec = "key:4", label = "ZOOM" },
}

-- Per-orientation layout buckets (#633).  Orientation comes from the safe
-- rect, not the device: sw > sh is landscape, so a resized desktop window
-- under POKEPORT_TOUCH exercises the same path a phone rotation does.
local ORIENTATIONS = { "portrait", "landscape" }

-- Control size multiplier bounds for the editor's -/+ (#633).  1.0 is the
-- historical size, so an install that never touches it draws as before.
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 1.6, 0.1

local IMAGES = {
  dpad = "assets/touch/dpad.png",
  dpad_up = "assets/touch/dpad_up.png",
  dpad_down = "assets/touch/dpad_down.png",
  dpad_left = "assets/touch/dpad_left.png",
  dpad_right = "assets/touch/dpad_right.png",
  a = "assets/touch/a.png",
  b = "assets/touch/b.png",
  l = "assets/touch/l.png",
  r = "assets/touch/r.png",
  start = "assets/touch/start.png",
  select = "assets/touch/select.png",
}

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function clampScale(v)
  if type(v) ~= "number" or v ~= v then return 1 end
  if v < SCALE_MIN then return SCALE_MIN end
  if v > SCALE_MAX then return SCALE_MAX end
  return v
end

-- Haptic feedback (#806): a short vibration the instant a control takes a GB
-- button, the way every mobile emulator front-end does it -- the pad has no
-- edges under a thumb, so the buzz is the only confirmation a press landed.
-- Persisted as options.haptics (src/core/SaveData.lua defaultOptions), NOT
-- under options.touchControls: TouchControls:config() is the launcher
-- editor's save snapshot and only emits enabled + layouts, so a nested key
-- would be dropped on every editor save.
-- love.system.vibrate takes a duration and nothing else, so "intensity" is a
-- duration preset: Android runs the platform vibrator for exactly that long,
-- while iOS maps each duration to a matching Taptic Engine impact.
TouchControls.HAPTICS = { "off", "light", "normal", "strong" }
TouchControls.HAPTIC_DEFAULT = "light"

local HAPTIC_SECONDS = {
  off = 0, light = 0.012, normal = 0.025, strong = 0.045,
}
local HAPTIC_LABELS = {
  off = "OFF", light = "LIGHT", normal = "NORMAL", strong = "STRONG",
}

function TouchControls.normalizeHaptics(level)
  if level == "physical" then return "light" end
  if level == "medium" then return "normal" end
  if level == "heavy" then return "strong" end
  if HAPTIC_SECONDS[level] then return level end
  return TouchControls.HAPTIC_DEFAULT
end

function TouchControls.hapticLabel(level)
  return HAPTIC_LABELS[TouchControls.normalizeHaptics(level)]
end

function TouchControls.cycleHaptics(level, dir)
  local cur, idx = TouchControls.normalizeHaptics(level), 1
  for i, m in ipairs(TouchControls.HAPTICS) do
    if m == cur then idx = i break end
  end
  local n = #TouchControls.HAPTICS
  return TouchControls.HAPTICS[(idx - 1 + (dir or 1)) % n + 1]
end

-- One pulse at the given level.  Feature-guarded rather than platform-gated:
-- love.system.vibrate is a no-op on desktop and absent from the headless love
-- stubs, so the press path below stays identical everywhere and the tests
-- never reach a vibrator.
function TouchControls.buzz(level)
  local secs = HAPTIC_SECONDS[TouchControls.normalizeHaptics(level)]
  if not secs or secs <= 0 then return false end
  if not (love and love.system and love.system.vibrate) then return false end
  pcall(love.system.vibrate, secs)
  return true
end

-- Copy a persisted positions table, dropping unknown / non-numeric entries.
-- Always a fresh table: two orientations seeded from the same pre-#633
-- layout must not alias, or dragging one would still move the other.
local function normalizePositions(src)
  if type(src) ~= "table" then return nil end
  local pos = {}
  for _, name in ipairs(CONTROLS) do
    local p = src[name]
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
      pos[name] = { x = clamp01(p.x), y = clamp01(p.y) }
    end
  end
  if not next(pos) then return nil end
  return pos
end

local function orientationFor(sw, sh)
  return (sw or 0) > (sh or 0) and "landscape" or "portrait"
end

local function wantsOverlay()
  local env = os.getenv("POKEPORT_TOUCH")
  if env == "1" then return true end
  if env == "0" then return false end
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Normalize a persisted touchControls table into
-- {enabled, layouts = {portrait = {positions, scale}, landscape = {...}}}.
-- Unknown / garbage keys are dropped so a bad options.lua cannot brick
-- the overlay.  Pre-#633 files stored one top-level positions table and no
-- scale; that layout seeds both orientations, so an upgrading player keeps
-- what they had until they edit one of them.
function TouchControls.normalizeConfig(tc)
  local out = { enabled = true, layouts = { portrait = {}, landscape = {} } }
  -- a nil / garbage table still yields full buckets (scale defaulted), so
  -- no caller ever has to nil-check a bucket's scale
  if type(tc) ~= "table" then tc = {} end
  if tc.enabled == false then out.enabled = false end
  if type(tc.skin) == "string" and tc.skin ~= "" then out.skin = tc.skin end
  local saved = type(tc.layouts) == "table" and tc.layouts or nil
  for _, o in ipairs(ORIENTATIONS) do
    local b = saved and saved[o]
    if type(b) ~= "table" then b = { positions = tc.positions, scale = tc.scale } end
    out.layouts[o] = {
      positions = normalizePositions(b.positions),
      scale = clampScale(b.scale),
    }
  end
  return out
end

function TouchControls:buttons()
  if self and (self.shoulders or self.generation == 3) then return BUTTONS_GBA end
  return BUTTONS_GB
end

function TouchControls:controls()
  if self and (self.shoulders or self.generation == 3) then return CONTROLS end
  return { "dpad", "a", "b", "start", "select", "hotbar" }
end

-- Pure default layout in LOVE units for a usable rect of size ww x wh at
-- origin (ox, oy).  Shared by layout() and the editor's Reset path so
-- defaults stay in one place.  ox/oy default to 0 for the headless tests
-- and for callers that already pass a full-window size.  scale (#633) is
-- the orientation's size multiplier: every width and the margin derive
-- from dpadW, so scaling it moves the default centers with the art
-- instead of letting bigger buttons hang off the edge.
function TouchControls.defaultLayout(ww, wh, ox, oy, scale, shoulders)
  ox, oy = ox or 0, oy or 0
  local short = math.min(ww, wh)
  local dpadW = math.min(180, short * 0.34) * clampScale(scale)
  local abW = dpadW * 0.46
  local lrW = dpadW * 0.56
  local lrH = lrW * 0.50
  local ssW = dpadW * 0.30
  local margin = dpadW * 0.12
  local isLandscape = (ww > wh)
  local out = {
    dpad = { cx = ox + margin + dpadW / 2, cy = oy + wh - margin - dpadW / 2, w = dpadW },
    a = { cx = ox + ww - margin - abW * 0.55, cy = oy + wh - margin - abW * 1.75, w = abW },
    b = { cx = ox + ww - margin - abW * 1.60, cy = oy + wh - margin - abW * 0.55, w = abW },
    start = { cx = ox + ww / 2 + ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
    select = { cx = ox + ww / 2 - ssW * 0.60, cy = oy + wh - margin - ssW * 0.95, w = ssW },
    hotbar = { cx = ox + ww - margin - ssW * 0.70, cy = oy + margin + ssW * 0.70, w = ssW },
  }
  if isLandscape then
    -- Landscape: Float L and R comfortably above the D-pad and A/B cluster (+ 9% height clearance)
    local shoulderY = oy + wh - margin - dpadW - lrH * 0.65 - wh * 0.09
    out.l = { cx = ox + margin + lrW * 0.65, cy = shoulderY, w = lrW, h = lrH, shape = "squircle" }
    out.r = { cx = ox + ww - margin - lrW * 0.65, cy = shoulderY, w = lrW, h = lrH, shape = "squircle" }
  else
    -- Portrait: Place L and R in the control deck above D-pad and A/B clusters with ample clearance (+ 9% height clearance)
    local shoulderY = oy + wh - margin - dpadW - lrH * 0.90 - wh * 0.09
    out.l = { cx = ox + margin + lrW * 0.65, cy = shoulderY, w = lrW, h = lrH, shape = "squircle" }
    out.r = { cx = ox + ww - margin - lrW * 0.65, cy = shoulderY, w = lrW, h = lrH, shape = "squircle" }
  end
  return out
end

local function loadImages()
  local img = {}
  for name, path in pairs(IMAGES) do
    local ok, im = pcall(love.graphics.newImage, path)
    if not ok then return nil end
    im:setFilter("linear", "linear")
    img[name] = im
  end
  return img
end

function TouchControls:init()
  self.active = wantsOverlay()
  TouchSkin.setOverlayLive(self.active)
  self.enabled = true
  self.generation = nil
  self.shoulders = false
  -- vibration level for presses (#806); applyOptions overwrites it from
  -- options.haptics, this is the value a harness that never applies options
  -- runs with
  self.haptics = TouchControls.HAPTIC_DEFAULT
  -- per-orientation buckets (#633); self.positions / self.scale mirror the
  -- one currently on screen so layout(), the editor and the tests keep a
  -- single lookup
  self.layouts = { portrait = {}, landscape = {} }
  self.orientation = nil
  self.positions = nil
  self.scale = 1
  self.preview = false
  self.controllerHidden = false
  self.touches = {}
  -- per-GB-button owner count: two fingers on A must not double-press it,
  -- and lifting one of them must not release the other's hold
  self.held = {}
  self.dpadTouch = nil
  self.layoutW, self.layoutH = nil, nil
  self.skinId = nil
  self.skinError = nil
  self.hotkeysHeld = {}
  self.hotbarEnabled = true
  self.hotbarOpen = false
  self.hotbarControls = nil
  TouchSkin.setActive(nil)
  self.img = nil
  -- Images load whenever the platform wants the overlay OR the launcher
  -- editor forces a preview (desktop testing of the editor).
  if self.active then
    self.img = loadImages()
  end
end

-- Ensure art is loaded for the launcher editor even when wantsOverlay()
-- is false (desktop without POKEPORT_TOUCH).
function TouchControls:ensureImages()
  if self.img then return true end
  self.img = loadImages()
  return self.img ~= nil
end

-- Apply options.touchControls.  Called from Game:applyOptions and from
-- the launcher editor after a save.
function TouchControls:applyOptions(opts)
  local cfg = TouchControls.normalizeConfig(opts and opts.touchControls)
  self.enabled = cfg.enabled
  self.generation = opts and (opts.generation or (opts.version and require("src.core.GameVersion").generation(opts.version))) or self.generation
  if self.generation == nil then
    local ok, GV = pcall(require, "src.core.GameVersion")
    if ok and GV and GV.generation then self.generation = GV.generation() end
  end
  self.shoulders = (self.generation == 3) or (opts and opts.shoulders == true)
  -- haptics is a plain top-level option, not part of the layout config the
  -- launcher editor round-trips through config() (#806)
  self.haptics = TouchControls.normalizeHaptics(opts and opts.haptics)
  self.hotbarEnabled = not (opts and opts.hotbar == false)
  if not self.hotbarEnabled then self.hotbarOpen = false end
  TouchSkin.setOverlayLive(self.active)
  -- Off means off everywhere: do not leave a hidden selected skin behind to
  -- influence renderer placement on desktop or with a controller attached.
  self:selectSkin(cfg.enabled and cfg.skin or nil)
  self.layouts = cfg.layouts
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
  -- prime positions/scale for the orientation on screen so callers that
  -- read them before the next layout() (editor chrome, tests) see the file
  self:currentBucket()
  if not self.enabled then
    self.controllerHidden = false
    self:reset()
  end
end

-- Snapshot for the editor's save path: enabled plus both orientation
-- buckets, matching what options.lua stores (#633).
function TouchControls:config()
  local out = { enabled = self.enabled ~= false, skin = self.skinId, layouts = {} }
  for _, o in ipairs(ORIENTATIONS) do
    local b = self.layouts and self.layouts[o] or nil
    out.layouts[o] = {
      positions = b and b.positions or nil,
      scale = clampScale(b and b.scale),
    }
  end
  return out
end

-- Preview mode: force-draw the overlay for the layout editor, ignoring
-- platform / enabled / gamepad gates.  Gameplay input still respects
-- enabled via touchpressed.
function TouchControls:setPreview(on)
  self.preview = on and true or false
  if on then
    self:ensureImages()
    self.controllerHidden = false
  end
end

function TouchControls:visible()
  local art = TouchSkin.active ~= nil or self.img ~= nil
  if self.preview then return art end
  if self.enabled == false or not art then return false end
  -- A selected skin is also a desktop/TV bezel.  Input remains gated in
  -- touchpressed, but the artwork must not disappear when a controller is
  -- connected or the platform is not touch-first.
  if TouchSkin.active then return true end
  return self.active and not self.controllerHidden
end

local function surfaceRect()
  local r = TouchSkin.surfaceRect
  if r then return r.w, r.h, r.x, r.y end
  if love and love.graphics and love.graphics.getDimensions then
    local w, h = love.graphics.getDimensions()
    return w, h, 0, 0
  end
  return 0, 0, 0, 0
end

TouchControls.surfaceRect = surfaceRect

function TouchControls:selectSkin(id)
  if id == self.skinId and TouchSkin.active then return TouchSkin.active end
  self:reset()
  self.skinError = nil
  if not id or id == "" then
    self.skinId = nil
    TouchSkin.setActive(nil)
    return nil
  end
  local skin, err = TouchSkin.select(id)
  if not skin then
    self.skinId = nil
    self.skinError = err
    TouchSkin.setActive(nil)
    return nil, err
  end
  self.skinId = id
  return skin
end

function TouchControls:skin()
  if not self:visible() then return nil end
  return TouchSkin.active
end

function TouchControls:setHotkeyHandler(fn)
  self.hotkeyHandler = type(fn) == "function" and fn or nil
end

local skinHitSet, applySkinSet

-- Keep a control fully inside the usable rect [x0,y0]..[x1,y1].
local function clampZone(zone, x0, y0, x1, y1)
  local halfW = zone.w * 0.5
  local halfH = (zone.h or zone.w) * 0.5
  zone.cx = math.max(x0 + halfW, math.min(x1 - halfW, zone.cx))
  zone.cy = math.max(y0 + halfH, math.min(y1 - halfH, zone.cy))
end

-- The bucket for the orientation currently on screen (#633), created on
-- demand.  Mirrors it into self.orientation / self.positions / self.scale,
-- which layout(), the editor chrome and the tests read.
function TouchControls:currentBucket()
  local _, _, sw, sh = SafeArea.windowRect()
  local o = orientationFor(sw, sh)
  self.layouts = self.layouts or { portrait = {}, landscape = {} }
  local b = self.layouts[o]
  if type(b) ~= "table" then
    b = {}
    self.layouts[o] = b
  end
  b.scale = clampScale(b.scale)
  self.orientation = o
  self.positions = b.positions
  self.scale = b.scale
  return b
end

-- Layout in LOVE units (density-independent on mobile), recomputed when
-- the window or safe area changes (rotation, resize, notch insets).
-- Default: d-pad bottom-left, B/A bottom-right with A above B (the Game Boy
-- diagonal), START/SELECT flanking the bottom center -- all inside the
-- device safe area so thumbs clear the home indicator / cutouts.
-- Custom positions (normalized 0..1 within the safe rect) override centers
-- while sizes stay derived from the short edge, times the orientation's
-- size setting (#633).
function TouchControls:layout()
  local ox, oy, sw, sh = SafeArea.windowRect()
  if self.layoutW == sw and self.layoutH == sh
     and self.layoutOx == ox and self.layoutOy == oy and self.L then
    return self.L
  end
  self.layoutW, self.layoutH = sw, sh
  self.layoutOx, self.layoutOy = ox, oy
  -- orientation picks which saved layout applies; rotating swaps buckets
  -- because sw/sh swapped, which is already the cache key above (#633)
  local bucket = self:currentBucket()
  self.L = TouchControls.defaultLayout(sw, sh, ox, oy, bucket.scale, self.shoulders)
  if bucket.positions then
    for _, name in ipairs(self:controls()) do
      local p = bucket.positions[name]
      local zone = self.L[name]
      if p and zone then
        zone.cx = ox + p.x * sw
        zone.cy = oy + p.y * sh
        clampZone(zone, ox, oy, ox + sw, oy + sh)
      end
    end
  end
  local ssW = self.L.start.w
  local fontSize = math.max(8, math.floor(ssW * 0.26))
  if not self.labelFont or self.fontSize ~= fontSize then
    self.fontSize = fontSize
    self.labelFont = love.graphics.newFont(fontSize)
  end
  return self.L
end

-- Move one control to a screen-space point and persist its normalized
-- position within the safe rect.  Used by the layout editor while dragging.
function TouchControls:setControlCenter(name, cx, cy)
  local ox, oy, sw, sh = SafeArea.windowRect()
  local L = self:layout()
  local zone = L[name]
  if not zone then return end
  zone.cx, zone.cy = cx, cy
  clampZone(zone, ox, oy, ox + sw, oy + sh)
  -- writes land in the orientation on screen only (#633)
  local bucket = self:currentBucket()
  bucket.positions = bucket.positions or {}
  self.positions = bucket.positions
  bucket.positions[name] = {
    x = sw > 0 and (zone.cx - ox) / sw or 0,
    y = sh > 0 and (zone.cy - oy) / sh or 0,
  }
end

-- Editor Reset: defaults for the orientation on screen only (#633), so
-- resetting landscape never throws away the portrait layout.
function TouchControls:clearPositions()
  local bucket = self:currentBucket()
  bucket.positions = nil
  bucket.scale = 1
  self.positions = nil
  self.scale = 1
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
end

-- Control size multiplier for the orientation on screen (#633).  Widths and
-- the default centers both derive from it in defaultLayout; custom centers
-- keep their normalized spot and re-clamp inside the safe rect on the next
-- layout().
function TouchControls:setScale(scale)
  local bucket = self:currentBucket()
  bucket.scale = clampScale(scale)
  self.scale = bucket.scale
  self.layoutW, self.layoutH = nil, nil
  self.layoutOx, self.layoutOy = nil, nil
  return self.scale
end

function TouchControls:nudgeScale(delta)
  return self:setScale((self.scale or 1) + delta)
end

local function inCircle(zone, x, y, slop)
  local r = zone.w * 0.5 * slop
  local dx, dy = x - zone.cx, y - zone.cy
  return dx * dx + dy * dy <= r * r
end

local function inSquircle(zone, x, y, slop)
  slop = slop or 1.25
  local halfW = zone.w * 0.54 * slop
  local halfH = (zone.h or (zone.w * 0.50)) * 0.54 * slop
  return math.abs(x - zone.cx) <= halfW and math.abs(y - zone.cy) <= halfH
end

function TouchControls:hotbarItems()
  if self.hotbarControls then return self.hotbarControls end
  local out = {}
  for i, entry in ipairs(HOTBAR) do
    local ctl = TouchSkin.newControl(entry.spec, 0, 0, 0, 0, "rect")
    ctl.label = entry.label
    out[i] = ctl
  end
  self.hotbarControls = out
  return out
end

function TouchControls:hotbarShown()
  return self.hotbarEnabled ~= false and not TouchSkin.active
end

function TouchControls:hotbarStrip()
  local L = self:layout()
  local zone = L and L.hotbar
  local items = self:hotbarItems()
  if not zone or #items == 0 then return nil end
  local ox, oy, sw, sh = SafeArea.windowRect()
  local h = zone.w * 0.95
  local pad = h * 0.14
  local cw = h * 1.9
  if self.labelFont then
    for _, ctl in ipairs(items) do
      cw = math.max(cw, self.labelFont:getWidth(ctl.label) + pad * 3)
    end
  end
  local total = math.min(sw - pad * 2, cw * #items)
  cw = total / #items
  local x0 = math.max(ox + pad,
                      math.min(zone.cx - total, ox + sw - pad - total))
  local y0 = math.min(zone.cy + zone.w * 0.80, oy + sh - h)
  local cells = {}
  for i, ctl in ipairs(items) do
    cells[i] = { ctl = ctl, label = ctl.label, h = h,
                 x = x0 + (i - 1) * cw, y = y0, w = cw - pad }
  end
  return cells
end

function TouchControls:hotbarCellAt(x, y)
  if not (self.hotbarOpen and self:hotbarShown()) then return nil end
  for _, cell in ipairs(self:hotbarStrip() or {}) do
    if x >= cell.x and x <= cell.x + cell.w
       and y >= cell.y and y <= cell.y + cell.h then
      return cell
    end
  end
  return nil
end

-- Which control (if any) contains (x, y).  Prefer face buttons over the
-- d-pad when they overlap, matching touchpressed's order.
function TouchControls:hitTest(x, y)
  local page = TouchSkin.page()
  if page then
    local ww, wh, ox, oy = surfaceRect()
    for i = #page.controls, 1, -1 do
      local ctl = page.controls[i]
      if TouchSkin.hits(page, ctl, ww, wh, x, y, ox, oy) then return ctl.spec, ctl end
    end
    return nil
  end
  local L = self:layout()
  if self:hotbarShown() and inCircle(L.hotbar, x, y, HOTBAR_SLOP) then
    return "hotbar"
  end
  for _, btn in ipairs(self:buttons()) do
    local zone = L[btn]
    if zone then
      local isSq = zone.shape == "squircle" or zone.shape == "rect" or btn == "l" or btn == "r"
      local hit = isSq and inSquircle(zone, x, y, SLOP[btn] or 1.25)
                       or inCircle(zone, x, y, SLOP[btn] or 1.3)
      if hit then return btn end
    end
  end
  local dz = L.dpad
  local half = dz.w * 0.65
  if math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    return "dpad"
  end
  return nil
end

local function dpadDir(zone, x, y)
  local dx, dy = x - zone.cx, y - zone.cy
  local dead = zone.w * DPAD_DEAD
  if math.abs(dx) < dead and math.abs(dy) < dead then return nil end
  if math.abs(dx) >= math.abs(dy) then
    return dx > 0 and "right" or "left"
  end
  return dy > 0 and "down" or "up"
end

local function pressBtn(self, btn)
  local n = (self.held[btn] or 0) + 1
  self.held[btn] = n
  -- Buzz only on the 0 -> 1 edge, the same edge that presses the GB button:
  -- a second finger landing on a button that is already held, and a d-pad
  -- finger resting inside one direction, must not retrigger it.  Sliding the
  -- d-pad to a new direction does, which is the point (#806).
  if n == 1 then
    Input:overlayPressed(btn)
    TouchControls.buzz(self.haptics)
  end
end

local function releaseBtn(self, btn)
  local n = self.held[btn]
  if not n then return end
  if n > 1 then
    self.held[btn] = n - 1
  else
    self.held[btn] = nil
    Input:overlayReleased(btn)
  end
end

-- the d-pad touch's held direction changed (or ended): swap the GB hold
local function setDpad(self, touch, dir)
  if touch.dir == dir then return end
  if touch.dir then releaseBtn(self, touch.dir) end
  touch.dir = dir
  if dir then pressBtn(self, dir) end
end

local function pressKey(key, down)
  local fn = down and love.keypressed or love.keyreleased
  if type(fn) == "function" then pcall(fn, key, key, false) end
end

local function fireHotkey(self, action, pressed, ctl)
  if action == "overlay_next" then
    if pressed then TouchSkin.nextPage(ctl and ctl.nextTarget) end
    return pressed
  end
  if action == "overlay_prev" then
    if pressed then TouchSkin.setPage(TouchSkin.pageIndex - 1) end
    return pressed
  end
  self.hotkeysHeld = self.hotkeysHeld or {}
  local n = (self.hotkeysHeld[action] or 0) + (pressed and 1 or -1)
  if n < 0 then n = 0 end
  self.hotkeysHeld[action] = n > 0 and n or nil
  local edge = (pressed and n == 1) or (not pressed and n == 0)
  if edge and self.hotkeyHandler then
    pcall(self.hotkeyHandler, action, pressed)
  end
  return false
end

local function enterControl(self, ctl)
  local buzzed = false
  for _, btn in ipairs(ctl.buttons) do
    if not self.held[btn] then buzzed = true end
    pressBtn(self, btn)
  end
  for _, key in ipairs(ctl.keys) do pressKey(key, true) end
  local switched = false
  for _, action in ipairs(ctl.hotkeys) do
    if fireHotkey(self, action, true, ctl) then switched = true end
  end
  if not buzzed and (ctl.keys[1] or ctl.hotkeys[1]) then
    TouchControls.buzz(self.haptics)
  end
  return switched
end

local function exitControl(self, ctl)
  for _, btn in ipairs(ctl.buttons) do releaseBtn(self, btn) end
  for _, key in ipairs(ctl.keys) do pressKey(key, false) end
  for _, action in ipairs(ctl.hotkeys) do fireHotkey(self, action, false, ctl) end
end

function skinHitSet(self, x, y, prev)
  local page = TouchSkin.page()
  if not page then return nil end
  local ww, wh, ox, oy = surfaceRect()
  local set = nil
  for _, ctl in ipairs(page.controls) do
    local held = (prev and prev[ctl]) == true
    if not ctl.decorative
       and TouchSkin.hits(page, ctl, ww, wh, x, y, ox, oy, held) then
      set = set or {}
      set[ctl] = true
    end
  end
  return set
end

function applySkinSet(self, touch, set)
  local prev = touch.set or {}
  local switched = false
  for ctl in pairs(prev) do
    if not (set and set[ctl]) then exitControl(self, ctl) end
  end
  for ctl in pairs(set or {}) do
    if not prev[ctl] then
      if enterControl(self, ctl) then switched = true end
    end
  end
  touch.set = set
  if switched then
    for ctl in pairs(touch.set or {}) do exitControl(self, ctl) end
    touch.set = nil
  end
end

-- Returns true when this touch was captured by a virtual control -- the
-- pad's first refusal on the gameplay pointer seam (#807).  Capture is
-- decided here, at press, and rides self.touches[id] for the touch's
-- whole lifecycle; an uncaptured touch is never tracked, so wandering
-- across a control later neither presses it nor hides the touch from mods.
function TouchControls:touchpressed(id, x, y)
  -- preview mode is layout-edit only: never press GB buttons
  if self.preview then return end
  if not (self.active and self.enabled ~= false
          and (TouchSkin.active or self.img)) then return end
  -- a controller hid the overlay; the first touch only brings it back
  -- (uncaptured: it began on no control, so mods may still see it)
  if self.controllerHidden then
    self.controllerHidden = false
    return
  end
  if TouchSkin.active then
    local set = skinHitSet(self, x, y, nil)
    if not set then return end
    local touch = { control = "skin" }
    self.touches[id] = touch
    applySkinSet(self, touch, set)
    return true
  end
  local L = self:layout()
  if self:hotbarShown() then
    local cell = self:hotbarCellAt(x, y)
    if cell then
      self.touches[id] = { control = "hotkey", ctl = cell.ctl }
      enterControl(self, cell.ctl)
      return true
    end
    if inCircle(L.hotbar, x, y, HOTBAR_SLOP) then
      self.hotbarOpen = not self.hotbarOpen
      self.touches[id] = { control = "hotbarToggle" }
      TouchControls.buzz(self.haptics)
      return true
    end
  end
  for _, btn in ipairs(self:buttons()) do
    local zone = L[btn]
    if zone and inCircle(zone, x, y, SLOP[btn] or 1.3) then
      self.touches[id] = { control = btn }
      pressBtn(self, btn)
      return true
    end
  end
  -- square hit zone a bit past the cross art; one owning finger at a time
  local dz = L.dpad
  local half = dz.w * 0.65
  if not self.dpadTouch
     and math.abs(x - dz.cx) <= half and math.abs(y - dz.cy) <= half then
    self.dpadTouch = id
    local touch = { control = "dpad", dir = nil }
    self.touches[id] = touch
    setDpad(self, touch, dpadDir(dz, x, y))
    return true
  end
end

function TouchControls:touchmoved(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  if touch.control == "skin" then
    applySkinSet(self, touch, skinHitSet(self, x, y, touch.set))
    return
  end
  -- only the d-pad tracks movement (slide between directions without
  -- lifting); buttons hold until release wherever the finger wanders
  if touch.control ~= "dpad" then return end
  setDpad(self, touch, dpadDir(self:layout().dpad, x, y))
end

function TouchControls:touchreleased(id, x, y)
  if self.preview then return end
  local touch = self.touches[id]
  if not touch then return end
  self.touches[id] = nil
  if touch.control == "skin" then
    applySkinSet(self, touch, nil)
  elseif touch.control == "hotkey" then
    if touch.ctl then exitControl(self, touch.ctl) end
  elseif touch.control == "hotbarToggle" then
  elseif touch.control == "dpad" then
    setDpad(self, touch, nil)
    self.dpadTouch = nil
  else
    releaseBtn(self, touch.control)
  end
end

-- LÖVE has no touchcancelled: a touch interrupted by the OS (app
-- backgrounded, a system gesture stealing the finger) never fires
-- touchreleased and would strand its button held forever.  Called from
-- Game alongside Input:reset() on focus/visibility loss.
function TouchControls:reset()
  for _, touch in pairs(self.touches or {}) do
    if touch.control == "skin" and touch.set then
      for ctl in pairs(touch.set) do exitControl(self, ctl) end
    elseif touch.control == "hotkey" and touch.ctl then
      exitControl(self, touch.ctl)
    end
  end
  for action in pairs(self.hotkeysHeld or {}) do
    if self.hotkeyHandler then pcall(self.hotkeyHandler, action, false) end
  end
  self.hotkeysHeld = {}
  for btn in pairs(self.held or {}) do
    Input:overlayReleased(btn)
  end
  self.held = {}
  self.touches = {}
  self.dpadTouch = nil
  self.hotbarOpen = false
end

-- a gamepad is being used: hide the overlay (dropping anything it held)
-- until the next screen touch asks for it back.  No-op when the player
-- permanently disabled the overlay -- there is nothing to hide, and a
-- later accidental touch must not resurrect it.
function TouchControls:noteGamepad()
  if not self.active or self.enabled == false or self.controllerHidden then
    return
  end
  self.controllerHidden = true
  self:reset()
end

-- last controller unplugged: show the overlay again immediately instead
-- of requiring a blind first tap
function TouchControls:joystickremoved()
  self:reset()
  if love.joystick and love.joystick.getJoystickCount
     and love.joystick.getJoystickCount() == 0 then
    self.controllerHidden = false
  end
end

local function drawIcon(img, zone, pressed, alphaMul)
  alphaMul = alphaMul or 1
  love.graphics.setColor(1, 1, 1, (pressed and BACK_PRESSED or BACK) * alphaMul)
  if zone.shape == "squircle" or zone.shape == "rect" then
    local bw = zone.w * 1.08
    local bh = (zone.h or (zone.w * 0.50)) * 1.08
    local radius = bh * 0.32
    love.graphics.rectangle("fill", zone.cx - bw / 2, zone.cy - bh / 2, bw, bh, radius, radius)
  else
    love.graphics.circle("fill", zone.cx, zone.cy, zone.w * 0.58)
  end
  local scale = zone.w / img:getWidth()
  love.graphics.setColor(1, 1, 1, (pressed and ALPHA_PRESSED or ALPHA) * alphaMul)
  love.graphics.draw(img, zone.cx - zone.w / 2,
                     zone.cy - img:getHeight() * scale / 2, 0, scale, scale)
end

local function drawOverlayImage(img, x, y, w, h, alpha)
  if not img or alpha <= 0 then return end
  local sx, sy = TouchSkin.imageFit(img:getWidth(), img:getHeight(), w, h)
  if not sx then return end
  love.graphics.setColor(1, 1, 1, math.min(1, alpha))
  love.graphics.draw(img, x, y, 0, sx, sy)
end

function TouchControls:drawSkin(alphaMul)
  local page = TouchSkin.page()
  if not page then return false end
  local ww, wh, sox, soy = surfaceRect()
  local bx, by, bw, bh = TouchSkin.pageBox(page, ww, wh, sox, soy)
  local opacity = (self.skinOpacity or 1) * alphaMul

  love.graphics.push("all")
  love.graphics.origin()
  drawOverlayImage(page.image, bx, by, bw, bh, opacity)

  local pressed = {}
  for _, touch in pairs(self.touches or {}) do
    for ctl in pairs(touch.set or {}) do pressed[ctl] = true end
  end

  for _, ctl in ipairs(page.controls) do
    local down = pressed[ctl] == true
    local img = (down and ctl.pressedImage) or ctl.image
    if img then
      local cx, cy, halfW, halfH =
        TouchSkin.controlGeometry(page, ctl, ww, wh, sox, soy)
      local alpha = opacity
      if down and not ctl.pressedImage then alpha = opacity * ctl.alphaMod end
      drawOverlayImage(img, cx - halfW, cy - halfH, halfW * 2, halfH * 2, alpha)
    end
  end

  love.graphics.pop()
  return true
end

-- OS-window space, called after GameViewport.finish so the overlay rides on
-- top of the game, companion composition and post-processing without being
-- captured or scaled with any game viewport. Also used by the launcher layout
-- editor under preview mode.
function TouchControls:draw()
  if not self:visible() then return end
  if TouchSkin.active then
    local mul = (self.preview and self.enabled == false) and 0.45 or 1
    if self:drawSkin(mul) then return end
  end
  local L = self:layout()
  -- when the player disabled the overlay but the editor is previewing,
  -- draw dimmed so the layout is still editable
  local alphaMul = (self.preview and self.enabled == false) and 0.45 or 1
  love.graphics.push("all")
  love.graphics.origin()

  local dpadTouch = self.dpadTouch and self.touches[self.dpadTouch]
  local dir = dpadTouch and dpadTouch.dir
  drawIcon(dir and self.img["dpad_" .. dir] or self.img.dpad, L.dpad,
           dir ~= nil, alphaMul)
  for _, btn in ipairs(self:buttons()) do
    if self.img[btn] and L[btn] then
      drawIcon(self.img[btn], L[btn], self.held[btn] ~= nil, alphaMul)
    end
  end

  -- the +/- glyphs alone don't say which is which; shadowed so the text
  -- reads on both the black letterbox and battle's white one.  Each label
  -- tracks its own control's cy/w so dragging START cannot move SELECT.
  love.graphics.setFont(self.labelFont)
  local function label(text, zone)
    local ly = zone.cy + zone.w * 0.66
    local w = self.labelFont:getWidth(text)
    love.graphics.setColor(0, 0, 0, 0.6 * alphaMul)
    love.graphics.print(text, zone.cx - w / 2 + 1, ly + 1)
    love.graphics.setColor(1, 1, 1, (ALPHA + 0.2) * alphaMul)
    love.graphics.print(text, zone.cx - w / 2, ly)
  end
  label("START", L.start)
  label("SELECT", L.select)

  if self:hotbarShown() then
    local z = L.hotbar
    local r = z.w * 0.5
    love.graphics.setColor(0.15, 0.15, 0.15, 0.55 * alphaMul)
    love.graphics.circle("fill", z.cx, z.cy, r * 1.16)
    love.graphics.setColor(1, 1, 1, (ALPHA + 0.2) * alphaMul)
    local dot = r * 0.16
    for i = -1, 1 do
      love.graphics.circle("fill", z.cx + i * r * 0.5, z.cy, dot)
    end
    if self.hotbarOpen and not self.preview then
      local pressed = {}
      for _, touch in pairs(self.touches or {}) do
        if touch.control == "hotkey" and touch.ctl then pressed[touch.ctl] = true end
      end
      local cells = self:hotbarStrip() or {}
      local first, last = cells[1], cells[#cells]
      if first and last then
        local pad = first.h * 0.14
        love.graphics.setColor(0.15, 0.15, 0.15, 0.55 * alphaMul)
        love.graphics.rectangle("fill", first.x - pad, first.y - pad,
                                last.x + last.w - first.x + pad * 2,
                                first.h + pad * 2, first.h * 0.3)
      end
      for _, cell in ipairs(cells) do
        local down = pressed[cell.ctl] == true
        love.graphics.setColor(0.3, 0.3, 0.3,
          (down and 0.85 or 0.6) * alphaMul)
        love.graphics.rectangle("fill", cell.x, cell.y, cell.w, cell.h,
                                cell.h * 0.25)
        local tw = self.labelFont:getWidth(cell.label)
        local ty = cell.y + (cell.h - self.labelFont:getHeight()) * 0.5
        love.graphics.setColor(0, 0, 0, 0.6 * alphaMul)
        love.graphics.print(cell.label,
                            cell.x + (cell.w - tw) * 0.5 + 1, ty + 1)
        love.graphics.setColor(1, 1, 1,
          (down and ALPHA_PRESSED or (ALPHA + 0.2)) * alphaMul)
        love.graphics.print(cell.label, cell.x + (cell.w - tw) * 0.5, ty)
      end
    end
  end

  love.graphics.pop()
end

TouchControls.CONTROLS = CONTROLS
TouchControls.ORIENTATIONS = ORIENTATIONS
TouchControls.SCALE_MIN, TouchControls.SCALE_MAX = SCALE_MIN, SCALE_MAX
TouchControls.SCALE_STEP = SCALE_STEP

return TouchControls

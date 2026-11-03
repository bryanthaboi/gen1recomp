-- Foldable layouts for the iPhone Duo (any device whose host reports a
-- hinge).  The iOS bridge (love.system.getHinge) gives "closed" | "partial"
-- | "open" plus an angle in degrees but no fold position, so the layout is
-- derived from the window: the cover display is the one whose long side is
-- under 760 pt, and the inner display folds across its middle (horizontally
-- when taller than wide, vertically when wider than tall).
--
-- Each posture splits the window into a game rect (the render.viewport
-- default) and a control area for the touch pad, with nothing on the fold.
-- Devices without a hinge, and any window over 1.7:1, resolve to nil and
-- keep the stock behaviour.
--
-- POKEPORT_DUO_HINGE=closed|partial|open[:angle] forces a reading (off
-- disables the layouts); with POKEPORT_TOUCH=1 and a window of the inner
-- display's size (e.g. 669x951) every posture previews on a desktop.

local DuoPosture = {}

DuoPosture.OUTER_LONG_MAX = 760   -- pt; outer 466x678, inner ~626x890+
DuoPosture.PHONE_ASPECT = 1.7     -- longer than this = an ordinary phone
DuoPosture.FOLD_GAP = 24          -- pt kept clear across the fold
DuoPosture.CACHE_SECONDS = 0.1    -- hinge poll interval

DuoPosture.IDS = {
  "duo_clamshell", "duo_book",
  "duo_flat_portrait", "duo_flat_landscape",
  "duo_cover_portrait", "duo_cover_landscape",
}

-- "closed" | "partial" | "open" | "unknown", angle (degrees) -- or nil when
-- the host has no hinge.  DuoPosture.forced = {status=, angle=} is the test
-- seam; the env override wins over both.
function DuoPosture.hinge()
  local env = os.getenv("POKEPORT_DUO_HINGE")
  if env and env ~= "" then
    if env == "0" or env == "off" then return nil end
    local status, angle = env:match("^(%a+):?([%d%.]*)$")
    if status then
      local default = status == "closed" and 0
        or status == "partial" and 110 or 180
      return status, tonumber(angle) or default
    end
  end
  local f = DuoPosture.forced
  if f then return f.status, f.angle or 0 end
  local sys = love and love.system
  if sys and sys.getHinge then
    local ok, status, angle = pcall(sys.getHinge)
    if ok and type(status) == "string" and status ~= "" then
      return status, tonumber(angle) or 0
    end
  end
  return nil
end

-- Height / width of the game screen: 160x144 for Game Boy, 240x160 for GBA.
function DuoPosture.gameAspect(generation)
  if generation == 3 then return 160 / 240 end
  return 144 / 160
end

local function rect(x, y, w, h)
  return { x = x, y = y, w = math.max(1, w), h = math.max(1, h) }
end

-- The Duo's whole panel is usable (camera column, home-indicator band and
-- inner insets included), except the cover display in landscape, where
-- content under the leading camera column is hidden.  Pure; returns x, y, w, h.
function DuoPosture.widenCover(ww, wh, x, y, w, h)
  local long, short = math.max(ww, wh), math.min(ww, wh)
  if short <= 0 or long / short > DuoPosture.PHONE_ASPECT then return x, y, w, h end
  if long < DuoPosture.OUTER_LONG_MAX and wh < ww then return x, y, w, h end
  return 0, 0, ww, wh
end

-- Pure resolver.  ww, wh = full window (LOVE units); safe = {x,y,w,h} usable
-- rect; status/angle from hinge(); opts.generation picks the screen aspect,
-- opts.swap puts the book-mode game on the right page.  Returns nil (stock
-- layout) or:
--   { id, status, angle, inner, tall,
--     game = rect|nil,            -- nil = full window, as on any phone
--     controls = {rect, ...}|nil, -- nil = stock overlay layout
--     fold = rect|nil }           -- the band across the hinge (inner only)
function DuoPosture.resolve(ww, wh, safe, status, angle, opts)
  if not status or status == "" then return nil end
  opts = opts or {}
  ww, wh = ww or 0, wh or 0
  local long, short = math.max(ww, wh), math.min(ww, wh)
  if short <= 0 or long / short > DuoPosture.PHONE_ASPECT then return nil end
  safe = safe or { x = 0, y = 0, w = ww, h = wh }
  local sx, sy, sw, sh = DuoPosture.widenCover(ww, wh, safe.x, safe.y, safe.w, safe.h)
  local tall = wh >= ww
  local inner = long >= DuoPosture.OUTER_LONG_MAX
  local aspect = DuoPosture.gameAspect(opts.generation)
  local gap = DuoPosture.FOLD_GAP
  local p = { status = status, angle = angle or 0, inner = inner, tall = tall }

  if inner then
    if tall then
      p.fold = rect(0, wh / 2 - gap / 2, ww, gap)
    else
      p.fold = rect(ww / 2 - gap / 2, 0, gap, wh)
    end
  end

  if not inner then
    if tall then
      -- cover, portrait: game across the top, deck underneath
      p.id = "duo_cover_portrait"
      local gh = math.floor(math.min(sh * 0.6, sw * aspect, sh - 280))
      p.game = rect(sx, sy, sw, gh)
      p.controls = { rect(sx, sy + gh, sw, sh - gh) }
    else
      -- cover, landscape: too short for a separate deck; the stock overlay
      -- (inside the safe area, clear of the camera strip) is the best fit
      p.id = "duo_cover_landscape"
    end
  elseif status == "partial" then
    if tall then
      -- clamshell: the top half is the screen, the bottom half the pad
      p.id = "duo_clamshell"
      local foldTop, foldBottom = p.fold.y, p.fold.y + p.fold.h
      p.game = rect(sx, sy, sw, foldTop - sy)
      p.controls = { rect(sx, foldBottom, sw, sy + sh - foldBottom) }
    else
      -- book: one page is the screen, the other the pad
      p.id = "duo_book"
      local foldL, foldR = p.fold.x, p.fold.x + p.fold.w
      local left = rect(sx, sy, foldL - sx, sh)
      local right = rect(foldR, sy, sx + sw - foldR, sh)
      if opts.swap then
        p.game, p.controls = right, { left }
      else
        p.game, p.controls = left, { right }
      end
    end
  else
    if tall then
      p.id = "duo_flat_portrait"
      local gh = math.floor(math.min(sh * 0.6, sw * aspect, sh - 280))
      p.game = rect(sx, sy, sw, gh)
      p.controls = { rect(sx, sy + gh, sw, sh - gh) }
    else
      -- flat landscape: game in the middle, a rail for each thumb
      p.id = "duo_flat_landscape"
      local rail = (sw - sh / aspect) / 2
      rail = math.floor(math.max(170, math.min(rail, sw * 0.24)))
      p.game = rect(sx + rail, sy, sw - rail * 2, sh)
      p.controls = {
        rect(sx, sy, rail, sh),
        rect(sx + sw - rail, sy, rail, sh),
      }
    end
  end
  return p
end

local function clampScale(scale)
  scale = tonumber(scale) or 1
  return math.max(0.6, math.min(1.6, scale))
end

-- Fit a whole control cluster inside c, shrinking the base size until the
-- cluster's natural footprint fits.  Returns zones in TouchControls' format
-- ({cx, cy, w[, h, shape]}).
-- Round controls draw a backing disc of radius 0.58w (TouchControls
-- drawIcon), so every fit below works in visual widths: DISC * w.
local DISC = 1.16

local function deckLayout(c, scale, shoulders)
  local pad = math.max(16, math.floor(math.min(c.w, c.h) * 0.05))
  local wide = c.w >= c.h
  -- three rows: shoulders + hotbar / main (d-pad left, A/B diagonal right)
  -- / START + SELECT.  Start from the size the area suggests, scaled by the
  -- player's size setting, then shrink until the rows and columns fit.
  local dpadW = math.min(230, c.w * 0.34, (c.h - pad * 2) * 0.55)
  dpadW = dpadW * clampScale(scale)
  local abW, ssW, lrW, lrH, mainTop, mainBottom
  for _ = 1, 60 do
    abW = dpadW * 0.46
    ssW = math.max(26, dpadW * 0.27)
    lrW = dpadW * 0.56
    lrH = lrW * 0.5
    local topBand = math.max(shoulders and lrH * 1.08 or 0, ssW * DISC)
    mainTop = c.y + pad + topBand + pad * 0.5
    mainBottom = c.y + c.h - pad - ssW * 1.9
    local fitsH = dpadW * DISC <= (mainBottom - mainTop)
    -- d-pad + gap + A/B diagonal (B's left edge to A's right edge)
    local fitsW = dpadW * DISC + pad + abW * (1.22 + DISC) <= c.w - pad * 2
    if fitsH and fitsW then break end
    dpadW = dpadW * 0.95
  end
  local topRow = c.y + pad
  local bottomRow = c.y + c.h - pad
  local midY = (mainTop + mainBottom) / 2
  if not wide then
    -- a tall page: keep the pad in the lower part, under the thumbs
    midY = math.max(midY, c.y + c.h * 0.58)
    midY = math.min(midY, mainBottom - dpadW * DISC / 2)
  end
  local out = {}
  out.dpad = { cx = c.x + pad + dpadW * DISC / 2, cy = midY, w = dpadW }
  local ax = c.x + c.w - pad - abW * DISC / 2
  out.a = { cx = ax, cy = midY - abW * 0.6, w = abW }
  out.b = { cx = ax - abW * 1.22, cy = midY + abW * 0.6, w = abW }
  local ssY = bottomRow - ssW * 1.15
  local mid = c.x + c.w / 2
  out.select = { cx = mid - ssW * 0.8, cy = ssY, w = ssW }
  out.start = { cx = mid + ssW * 0.8, cy = ssY, w = ssW }
  out.hotbar = { cx = mid, cy = topRow + ssW * DISC / 2, w = ssW }
  out.l = { cx = c.x + pad + lrW * 0.54, cy = topRow + lrH * 0.54,
            w = lrW, h = lrH, shape = "squircle" }
  out.r = { cx = c.x + c.w - pad - lrW * 0.54, cy = topRow + lrH * 0.54,
            w = lrW, h = lrH, shape = "squircle" }
  return out
end

-- Two thumb rails (flat landscape): d-pad, L and SELECT on the left; A/B,
-- R, START and the hotbar on the right.
local function railLayout(left, right, scale, shoulders)
  local pad = math.max(14, math.floor(left.w * 0.08))
  local inner = left.w - pad * 2
  local dpadW = math.min(inner / DISC, 200 * clampScale(scale))
  local abW = math.min(dpadW * 0.5, inner / (DISC + 1.2))
  local ssW = math.max(26, dpadW * 0.27)
  local lrW = math.min(dpadW * 0.6, inner / 1.08)
  local lrH = lrW * 0.5
  local midY = left.y + left.h * 0.55
  local out = {}
  out.dpad = { cx = left.x + left.w / 2, cy = midY, w = dpadW }
  out.a = { cx = right.x + right.w - pad - abW * DISC / 2, cy = midY - abW * 0.62, w = abW }
  out.b = { cx = right.x + pad + abW * DISC / 2, cy = midY + abW * 0.62, w = abW }
  local ssY = left.y + left.h - pad - ssW * 1.15
  out.select = { cx = left.x + left.w / 2, cy = ssY, w = ssW }
  out.start = { cx = right.x + right.w / 2, cy = ssY, w = ssW }
  local lrY = left.y + pad + lrH * 0.54
  out.l = { cx = left.x + left.w / 2, cy = lrY, w = lrW, h = lrH, shape = "squircle" }
  out.r = { cx = right.x + right.w / 2, cy = lrY, w = lrW, h = lrH, shape = "squircle" }
  -- the hotbar opens leftward over the game, so it sits at the top of the
  -- right rail (below R on GBA)
  out.hotbar = { cx = right.x + right.w / 2,
                 cy = shoulders and (lrY + lrH * 0.54 + pad * 0.5 + ssW * DISC / 2)
                   or (right.y + pad + ssW * DISC / 2),
                 w = ssW }
  return out
end

-- Default control zones for a resolved posture, or nil when the posture
-- keeps the stock overlay.
function DuoPosture.controlLayout(p, scale, shoulders)
  if not (p and p.controls) then return nil end
  if #p.controls >= 2 then
    return railLayout(p.controls[1], p.controls[2], scale, shoulders)
  end
  return deckLayout(p.controls[1], scale, shoulders)
end

-- Bounding rect of every control area (custom positions clamp inside it).
function DuoPosture.controlBounds(p)
  if not (p and p.controls) then return nil end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs(p.controls) do
    x0, y0 = math.min(x0, c.x), math.min(y0, c.y)
    x1, y1 = math.max(x1, c.x + c.w), math.max(y1, c.y + c.h)
  end
  return rect(x0, y0, x1 - x0, y1 - y0)
end

-- Live posture for this frame, or nil.  Cached for CACHE_SECONDS so the
-- bridge is polled ~10 times a second, and re-resolved at once when the
-- window size or generation changes.
DuoPosture.enabled = true
DuoPosture.swap = false

local cache = { t = -math.huge }

function DuoPosture.invalidate()
  cache = { t = -math.huge }
end

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

-- Without a bridge, the env override or the test seam there is nothing to
-- poll, so every frame returns at once.
local ENV_SET = (os.getenv("POKEPORT_DUO_HINGE") or "") ~= ""
local function hingeSource()
  if DuoPosture.forced or ENV_SET then return true end
  local sys = love and love.system
  return sys ~= nil and sys.getHinge ~= nil
end

-- Full window plus the usable rect, through SafeArea.windowRect so the
-- pixel-vs-unit repair (#810) lives in one place.  Lazy require: SafeArea
-- requires GameViewport, which requires this module.
local SafeArea
local function windowGeometry()
  local G = love and love.graphics
  if not (G and G.getDimensions) then return nil end
  local ww, wh = G.getDimensions()
  SafeArea = SafeArea or require("src.core.SafeArea")
  local sx, sy, sw, sh = SafeArea.windowRect()
  return ww, wh, { x = sx, y = sy, w = sw, h = sh }
end

-- SafeArea.windowRect's hook: widens only while a hinge is reported, so an
-- ordinary iPhone keeps its real safe area.  The hinge read is cached.
local hingeCache = { t = -1, status = nil }
function DuoPosture.adjustSafe(ww, wh, x, y, w, h)
  if not (DuoPosture.enabled and hingeSource()) then return x, y, w, h end
  local t = now()
  if t - hingeCache.t > DuoPosture.CACHE_SECONDS or t < hingeCache.t then
    hingeCache.t = t
    hingeCache.status = DuoPosture.hinge()
  end
  if not hingeCache.status then return x, y, w, h end
  return DuoPosture.widenCover(ww, wh, x, y, w, h)
end

function DuoPosture.current(generation)
  if not (DuoPosture.enabled and hingeSource()) then return nil end
  if generation == nil then generation = cache.generation end
  local ww, wh, safe = windowGeometry()
  if not ww then return nil end
  local t = now()
  if cache.ww == ww and cache.wh == wh and cache.generation == generation
     and cache.swap == DuoPosture.swap
     and t - cache.t < DuoPosture.CACHE_SECONDS then
    return cache.p
  end
  -- A "closed" or "unknown" reading while the app is already on the inner
  -- display (the hand-off between panels is not instant) resolves to the
  -- flat layouts, the safest fit for a whole panel.
  local status, angle = DuoPosture.hinge()
  local p = DuoPosture.resolve(ww, wh, safe, status, angle,
                               { generation = generation, swap = DuoPosture.swap })
  cache = { t = t, ww = ww, wh = wh, generation = generation,
            swap = DuoPosture.swap, p = p }
  return p
end

return DuoPosture

-- Usable window rect for mobile chrome (notch / Dynamic Island / home
-- indicator / Android display cutouts).  Wraps love.window.getSafeArea when
-- the engine provides it; otherwise the full graphics window.
--
-- Desktop and headless stubs return the full window, so callers can always
-- layout against this rect without platform branches.  Interactive chrome
-- (touch overlay, launcher) should prefer this over getDimensions; the game
-- canvas may still letterbox into the full framebuffer for immersion.

local GameViewport = require("src.render.GameViewport")

local SafeArea = {}

-- Lazy: DuoPosture is required here only when a rect is asked for, since it
-- requires this module back (through GameViewport) while the pad lays out.
local DuoPosture

function SafeArea.windowRect()
  local ww, wh = 0, 0
  if love and love.graphics and love.graphics.getDimensions then
    ww, wh = GameViewport.fullDimensions()
  end
  if ww <= 0 then ww = 1 end
  if wh <= 0 then wh = 1 end

  if not (love and love.window and love.window.getSafeArea) then
    return 0, 0, ww, wh
  end

  local x, y, w, h = love.window.getSafeArea()
  if type(x) ~= "number" or type(y) ~= "number"
     or type(w) ~= "number" or type(h) ~= "number"
     or w <= 0 or h <= 0 then
    return 0, 0, ww, wh
  end

  -- A safe rect that cannot fit the window's unit space is a backend
  -- reporting framebuffer PIXELS -- the iOS build (LOVE 12 + SDL3) did this
  -- in portrait on iOS 16, and clamping it as-is kept a DPI-inflated top
  -- inset that pushed the whole launcher a band down the screen (#810).
  -- Convert back to units with per-axis ratios; the axes can disagree on
  -- forced-rotation devices (see displayMetrics in src/render/Renderer.lua,
  -- #208).
  if (w > ww + 0.5 or h > wh + 0.5)
     and love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    local dx = (pw and pw > 0) and (pw / ww) or 1
    local dy = (ph and ph > 0) and (ph / wh) or 1
    if dx > 1.01 or dy > 1.01 then
      x, w = x / dx, w / dx
      y, h = y / dy, h / dy
    end
  end

  -- Clamp to the drawable window so a bad / mid-rotation backend cannot
  -- push layout outside the surface.
  x = math.max(0, math.min(x, ww))
  y = math.max(0, math.min(y, wh))
  w = math.max(1, math.min(w, ww - x))
  h = math.max(1, math.min(h, wh - y))
  -- Foldables light their whole panel (src/core/DuoPosture.lua); a no-op
  -- unless a hinge is reported.
  DuoPosture = DuoPosture or require("src.core.DuoPosture")
  x, y, w, h = DuoPosture.adjustSafe(ww, wh, x, y, w, h)
  return x, y, w, h
end

function SafeArea.rect()
  return GameViewport.localSafeRect(SafeArea.windowRect())
end

return SafeArea

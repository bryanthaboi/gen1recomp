-- Overworld survey zoom: integer pixels-per-world-pixel scales stepped
-- by the mouse wheel, Options ZOOM row, or hotkey `4`.  Stored as an
-- offset from the window fit scale S so a resize keeps the relative
-- zoom.  Persisted as save.options.zoom (default 0 = FIT).
-- Spec: docs/new-features.md (survey zoom)

local Runtime = require("src.mods.Runtime")

local Zoom = {}

Zoom.offset = 0

-- Survey zoom (zooming out past FIT, which renders connected neighbor maps)
-- is the port's most expensive optional extra.  The performance tier sets
-- this false on LOW hardware (Game:applyOptions); offsetRange then floors
-- the range at FIT so the option row, hotkey, and mouse wheel all stop at
-- close-up.  Nil/true keeps the historical full range.
Zoom.allowSurvey = true

-- The deepest legal survey step (offset = 1-S, effective scale s' = S+lo =
-- 1 px/world px) plus an active SHADER FX chain crashes the app on real
-- hardware (Pixel 10 Pro XL, "OUT7" == this exact step at that device's own
-- fit scale of 8 -- reported by the user, 2026-08-21). A quantifying repro
-- (TrueFX/zoom-mem-scan/) ruled out ShaderFX's own per-pass canvases as the
-- driver (worst real-corpus case at that step: ~31MB, not crash-sized) --
-- the actual cost is almost certainly the world canvas/tile-render path
-- itself at that resolution (a preexisting cost of deep survey zoom,
-- unrelated to ShaderFX), which a shader chain reading that same
-- full-resolution canvas as its own input then pushes over some real
-- device/driver ceiling this project cannot measure without the device
-- in hand. Removing just the single deepest step while a preset is active
-- is the smallest change that directly targets what was actually reported
-- ("OUT7 + any shader", not "OUT7 alone" and not "OUT6 or shallower") --
-- not a guessed-at general zoom restriction. Needs the user's own on-device
-- confirmation; extend the margin (currently 1 step) if OUT6 turns out to
-- be risky too.
local ShaderFX

-- legal offset range for a given fit scale (vanilla: survey at 1 px/world
-- through 2× fit).  zoom.range may widen or shrink the window.
-- When the window only fits 1×, 1-S is 0 and there would be no OUT
-- levels; keep three survey steps so OPTIONS always has zoom-out.
function Zoom.offsetRange(S)
  S = math.max(1, math.floor(tonumber(S) or 1))
  local lo, hi = 1 - S, S
  if Runtime.wantsHook("zoom.range") then
    lo, hi = Runtime.call("zoom.range", function(a, b) return a, b end, lo, hi, S)
    lo = math.floor(tonumber(lo) or (1 - S))
    hi = math.floor(tonumber(hi) or S)
    if lo > hi then lo, hi = hi, lo end
  end
  -- LOW performance tier: no survey (negative offsets), even if a mod's
  -- zoom.range widened it.  == false so nil/true stays permissive.
  if Zoom.allowSurvey == false then
    if lo < 0 then lo = 0 end
  elseif lo > -3 then
    lo = -3
  end
  -- SHADER FX + the single deepest survey step: see the comment above.
  -- The floor is one step above the deepest this call would otherwise
  -- allow, so the three-step minimum above still keeps a zoom-out.
  ShaderFX = ShaderFX or require("src.render.ShaderFX")
  if ShaderFX.active() then
    local floor = math.min(2 - S, lo + 1)
    if lo < floor then lo = floor end
  end
  return lo, hi
end

-- effective scale s' = S + offset, clamped to the (possibly modded) range.
-- Vanilla stays in [1, 2*S].  A zoom.range wrapper that lowers `lo` below
-- 1-S permits sub-1 survey scales so the whole region can fit on screen.
function Zoom.scale(S)
  local lo, hi = Zoom.offsetRange(S)
  local s = S + Zoom.offset
  local minScale = S + lo
  local maxScale = math.max(minScale, S + hi)
  if s < minScale then s = minScale end
  if s > maxScale then s = maxScale end
  -- Integer offset below 1px/world (OPTIONS OUT on a 1× window): 1/2, 1/4, …
  if s < 1 then s = 0.5 ^ (1 - s) end
  if s < 0.25 then s = 0.25 end
  return s
end

function Zoom.clampOffset(offset, S)
  local lo, hi = Zoom.offsetRange(S)
  offset = math.floor(tonumber(offset) or 0)
  if offset < lo then return lo end
  if offset > hi then return hi end
  return offset
end

function Zoom.step(delta, S)
  Zoom.offset = Zoom.clampOffset(Zoom.offset + delta, S)
  return Zoom.offset
end

-- Advance one zoom level toward max close-up, then wrap to full survey.
-- Returns the new offset.
function Zoom.cycle(S)
  local lo, hi = Zoom.offsetRange(S)
  local next = Zoom.offset + 1
  if next > hi then next = lo end
  Zoom.offset = next
  return Zoom.offset
end

function Zoom.reset()
  Zoom.offset = 0
end

function Zoom.applyOptions(opts)
  Zoom.offset = math.floor(tonumber(opts and opts.zoom) or 0)
end

-- Integer fit used when OPTIONS has no live renderer (launcher, title).
function Zoom.windowFitScale()
  if love and love.graphics and love.graphics.getDimensions then
    local ww, wh = love.graphics.getDimensions()
    ww, wh = tonumber(ww) or 0, tonumber(wh) or 0
    if ww >= 160 and wh >= 144 then
      return math.max(1, math.floor(math.min(ww / 160, wh / 144)))
    end
  end
  return 1
end

-- One step of the OPTIONS ZOOM row (dir +1 in, -1 out).  Shared by Red
-- and Gold so both ladders offer OUT / FIT / IN.
function Zoom.nudgeOptions(options, dir, S)
  S = math.max(1, math.floor(tonumber(S) or Zoom.windowFitScale()))
  local lo, hi = Zoom.offsetRange(S)
  local off = math.floor(tonumber(options and options.zoom) or 0) + (dir or 1)
  if off > hi then off = lo elseif off < lo then off = hi end
  if options then options.zoom = off end
  Zoom.offset = off
  return off
end

-- FIT / OUT1 / OUT2 / … / IN1 / IN2 / …
function Zoom.offsetLabel(offset)
  offset = math.floor(tonumber(offset) or 0)
  if offset == 0 then return "FIT" end
  if offset < 0 then return "OUT" .. tostring(-offset) end
  return "IN" .. tostring(offset)
end

-- world pixels covered by a w x h letterbox viewport at fit scale S
-- (legacy GB-framed size; prefer fillViewSize for the live world pass)
function Zoom.viewSize(S, w, h)
  local s = Zoom.scale(S)
  return math.ceil(w * S / s), math.ceil(h * S / s)
end

-- world pixels needed to fill a ww x wh window at the current zoom scale
-- (fills letterbox "black voids" with more map,  phones, tall windows)
function Zoom.fillViewSize(s, ww, wh)
  return math.ceil(ww / s), math.ceil(wh / s)
end

-- zoom input is honored only while free-roaming the overworld
function Zoom.gateOK(top, overworld)
  if top == nil or top ~= overworld then return false end
  if top.transitioning then return false end
  if top.runner and top.runner.isRunning and top.runner:isRunning() then
    return false
  end
  return true
end

return Zoom

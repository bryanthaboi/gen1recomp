-- Overworld survey zoom: integer pixels-per-world-pixel scales stepped
-- by the mouse wheel, Options ZOOM row, or hotkey `4`.  Stored as an
-- offset from the window fit scale S so a resize keeps the relative
-- zoom.  Persisted as save.options.zoom (default 0 = FIT).
-- Spec: docs/new-features.md (survey zoom)

local Runtime = require("src.mods.Runtime")

local Zoom = {}

Zoom.offset = 0

-- legal offset range for a given fit scale (vanilla: survey at 1 px/world
-- through 2× fit).  zoom.range may widen or shrink the window.
function Zoom.offsetRange(S)
  S = math.max(1, math.floor(tonumber(S) or 1))
  local lo, hi = 1 - S, S
  if Runtime.wantsHook("zoom.range") then
    lo, hi = Runtime.call("zoom.range", function(a, b) return a, b end, lo, hi, S)
    lo = math.floor(tonumber(lo) or (1 - S))
    hi = math.floor(tonumber(hi) or S)
    if lo > hi then lo, hi = hi, lo end
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

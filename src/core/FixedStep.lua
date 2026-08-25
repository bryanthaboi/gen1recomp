-- Fixed-step update loop at the Game Boy's ~60Hz.  Game logic advances in
-- whole steps regardless of the display refresh rate, which keeps movement,
-- text speed and battle timing deterministic.

local FixedStep = {}

FixedStep.STEP = 1 / 60
local MAX_ACCUM = 0.25 -- avoid spiral of death after a stall
local SMOOTH_FRAMES = 4
local SMOOTH_MAX = 1 / 60 * 2.5
local STEP_EPS = 1 / 60 * 0.02

-- Phase the accumulator is re-seeded with once an absorbed hitch frame has
-- been paid for.  Half a step is the balanced point: a frame has to come in
-- ~8ms short before it drops a step and ~8ms long before it doubles one up.
-- Zero -- what this used to leave behind -- has no margin at all on the long
-- side, so the accumulator settles a hair BELOW one step and parks there, and
-- ordinary sub-millisecond vsync wobble then flips it between 0 and 2 steps
-- every few frames for the rest of the session.  That is why pacing stayed
-- visibly broken after a route/city seam and nowhere else: crossConnection in
-- src/world/OverworldController.lua is the only caller of discardCatchup, and
-- warps go through Transition instead (issue #487).
local RESEED_PHASE = 0.5

function FixedStep:init(callback)
  self.accum = 0
  self.callback = callback
  self.suppressCatchup = false
  self.dtHistory, self.dtSum = nil, 0
end

-- The anti-spiral clamp doubles as a steps-per-frame ceiling (0.25s = 15
-- steps), which silently throttled the high fast-forward levels: at 100X
-- a 60fps frame wants ~100 steps. Game:update raises this to fit the
-- current speed target; a stall still cannot snowball past one frame's
-- intended budget.
FixedStep.maxAccum = MAX_ACCUM

function FixedStep:update(dt)
  -- A hitch's oversized dt lands on the frame AFTER discardCatchup was
  -- called (the hitch itself already ran inside the current step); absorb
  -- that one frame as a single step instead of the normal accumulator so
  -- the burst it would otherwise release doesn't play out as a slide.
  if self.suppressCatchup then
    self.suppressCatchup = false
    self.dtHistory, self.dtSum = nil, 0
    self.accum = self.STEP * RESEED_PHASE
    self.callback(self.STEP)
    return
  end
  if dt > 0 and dt <= SMOOTH_MAX then
    local hist = self.dtHistory
    if not hist then hist = {}; self.dtHistory = hist; self.dtSum = 0 end
    hist[#hist + 1] = dt
    self.dtSum = self.dtSum + dt
    if #hist > SMOOTH_FRAMES then
      self.dtSum = self.dtSum - hist[1]
      table.remove(hist, 1)
    end
    dt = self.dtSum / #hist
  else
    self.dtHistory, self.dtSum = nil, 0
  end
  self.accum = math.min(self.accum + dt, self.maxAccum or MAX_ACCUM)
  while self.accum >= self.STEP - STEP_EPS do
    self.accum = self.accum - self.STEP
    self.callback(self.STEP)
  end
end

-- Drop any pending catch-up steps and arm the one-frame clamp above.  A
-- hitch inside one logic step (map seam setMap / song start) makes the
-- next real-time dt huge; without this the while-loop above would advance
-- many walk frames before the next draw, which looks like a slide with no
-- leg animation (issue #93).
function FixedStep:discardCatchup()
  self.accum = 0
  self.suppressCatchup = true
end

return FixedStep

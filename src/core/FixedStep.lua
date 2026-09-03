-- Fixed-step update loop at the Game Boy's ~60Hz.  Game logic advances in
-- whole steps regardless of the display refresh rate, which keeps movement,
-- text speed and battle timing deterministic.

local FixedStep = {}

FixedStep.GB_HZ = 4194304 / 70224
FixedStep.STEP = 1 / 60
-- Hard ceiling on catch-up debt (seconds of logic time drained in one
-- rendered frame).  0.25s = 15 GB steps.  Game:update may lower this for the
-- current speed target but must never raise it: a hitch at high multipliers
-- cannot dump unbounded steps and starve input / spiral the frame.
FixedStep.MAX_ACCUM = 0.25
local MAX_ACCUM = FixedStep.MAX_ACCUM
local SMOOTH_FRAMES = 4
local SMOOTH_MAX = 1 / 60 * 2.5
local STEP_EPS = 1 / 60 * 0.02

function FixedStep.setHz(hz)
  hz = tonumber(hz)
  if not hz or hz <= 0 then hz = 60 end
  FixedStep.STEP = 1 / hz
  SMOOTH_MAX = FixedStep.STEP * 2.5
  STEP_EPS = FixedStep.STEP * 0.02
  FixedStep.phasedFor = nil
  return hz
end

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

FixedStep.refreshPeriod = nil

local PHASE_PROBE = 600

local function phaseOffset(period, step)
  local residuals, seen, accum = {}, {}, 0
  for _ = 1, PHASE_PROBE do
    accum = accum + period
    while accum >= step - STEP_EPS do accum = accum - step end
    local key = math.floor(accum / step * 1e6 + 0.5)
    if seen[key] then break end
    seen[key] = true
    residuals[#residuals + 1] = accum
  end
  if #residuals == 0 then return 0 end
  table.sort(residuals)
  local bestGap, bestCentre = -1, 0
  for i = 1, #residuals do
    local a = residuals[i]
    local b = (i < #residuals) and residuals[i + 1] or (residuals[1] + step)
    if b - a > bestGap then bestGap, bestCentre = b - a, (a + b) * 0.5 end
  end
  return (step - bestCentre) % step
end

function FixedStep:init(callback)
  self.accum = 0
  self.callback = callback
  self.suppressCatchup = false
  self.dtHistory, self.dtSum = nil, 0
  self.phasedFor = nil
end

-- The anti-spiral clamp is the steps-per-frame ceiling.  Game:update sets
-- maxAccum to the current speed's one-frame budget, hard-capped at MAX_ACCUM
-- so high fast-forward cannot turn a hitch into input starvation.
FixedStep.maxAccum = MAX_ACCUM

-- Compute the live catch-up ceiling for a logic-speed multiplier.
-- Always ≤ MAX_ACCUM; at least two steps so ordinary vsync wobble can recover.
function FixedStep.catchupLimit(speed)
  speed = tonumber(speed) or 1
  if speed < 1 then speed = 1 end
  local target = speed * FixedStep.STEP * 1.5
  local floor = FixedStep.STEP * 2
  if target < floor then target = floor end
  if target > MAX_ACCUM then target = MAX_ACCUM end
  return target
end

function FixedStep:update(dt, speed)
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
  -- Snap/smooth against the wall-clock frame dt first.  Game speed is a
  -- multiplier on how many logic steps that real frame buys — applying it
  -- before refresh-period snap made 2–4X look like multi-period frames and
  -- destabilized pacing under DISPLAY sync.
  speed = tonumber(speed) or 1
  if speed < 1 then speed = 1 end
  -- Pathological wall-clock stalls: do not let dt alone exceed the catch-up
  -- ceiling before speed is applied (speed amplify would just hit the clamp).
  if dt > MAX_ACCUM then dt = MAX_ACCUM end
  local period = self.refreshPeriod
  local snapped = false
  if period and dt > 0 then
    local frames = math.floor(dt / period + 0.5)
    if frames >= 1 and frames * period <= SMOOTH_MAX
       and math.abs(frames * period - dt) < period * 0.25 then
      dt = frames * period
      snapped = true
    end
  end
  if snapped then
    self.dtHistory, self.dtSum = nil, 0
  elseif dt > 0 and dt <= SMOOTH_MAX then
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
  if period and self.phasedFor ~= period then
    self.phasedFor = period
    local target = phaseOffset(period, self.STEP)
    self.accum = self.accum - self.accum % self.STEP + target
  end
  self.accum = math.min(self.accum + dt * speed, self.maxAccum or MAX_ACCUM)
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

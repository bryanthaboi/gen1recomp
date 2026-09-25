package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FixedStep = require("src.core.FixedStep")
local GameSpeed = require("src.core.GameSpeed")
local STEP = FixedStep.STEP

local function run(speed, fps, frames, clock, period)
  local now = 0
  local steps, maxPerFrame, maxAccum = 0, 0, 0
  FixedStep.refreshPeriod = period
  FixedStep:init(function()
    steps = steps + 1
    if clock == "ms" then now = now + 0.001 end
  end)
  FixedStep.clock = function() return now end
  local dt = 1 / fps
  for _ = 1, frames do
    local before = steps
    FixedStep.maxAccum = FixedStep.catchupLimit(speed, dt)
    FixedStep:update(dt, speed)
    if clock == "ms" then now = now + 0.004 end
    if steps - before > maxPerFrame then maxPerFrame = steps - before end
    if FixedStep.accum > maxAccum then maxAccum = FixedStep.accum end
  end
  FixedStep.clock = nil
  FixedStep.refreshPeriod = nil
  return steps, maxPerFrame, maxAccum
end

for _, speed in ipairs(GameSpeed.LEVELS) do
  local steps = run(speed, 60, 60, "frozen")
  check(math.abs(steps - 60 * speed) <= 1,
    ("%dX at 60fps: %d logic steps a second (want %d)"):format(speed, steps, 60 * speed))
  local slow = run(speed, 30, 30, "frozen")
  check(math.abs(slow - 60 * speed) <= 1,
    ("%dX at 30fps: %d logic steps a second (want %d)"):format(speed, slow, 60 * speed))
  local mid = run(speed, 45, 45, "frozen")
  check(math.abs(mid - 60 * speed) <= 1,
    ("%dX at 45fps: %d logic steps a second (want %d)"):format(speed, mid, 60 * speed))
end

local fast = run(200, 60, 60, "frozen")
local ten = run(10, 60, 60, "frozen")
check(fast >= ten * 15,
  ("200X runs far more logic than 10X on a fast frame (%d vs %d)"):format(fast, ten))

local steps, perFrame, carried = run(200, 60, 60, "ms", 1 / 60)
check(perFrame >= 11 and perFrame <= 14,
  ("200X on a slow device stops at the frame budget (%d steps a frame)"):format(perFrame))
check(carried < STEP,
  ("the unpaid debt is dropped, not carried (max accum %.4f)"):format(carried))
check(steps >= 60 * 11,
  ("and still runs as fast as the device allows (%d steps)"):format(steps))

local oneX = run(1, 60, 60, "ms", 1 / 60)
eq(oneX, 60, "1X ignores the work budget")

local function hitchBurst(speed, hitch)
  local n = 0
  FixedStep.refreshPeriod = nil
  FixedStep.clock = function() return 0 end
  FixedStep:init(function() n = n + 1 end)
  for _ = 1, 30 do
    FixedStep.maxAccum = FixedStep.catchupLimit(speed, 1 / 60)
    FixedStep:update(1 / 60, speed)
  end
  n = 0
  FixedStep.maxAccum = FixedStep.catchupLimit(speed, hitch)
  FixedStep:update(hitch, speed)
  FixedStep.clock = nil
  return n
end

for _, speed in ipairs({ 1, 2, 4, 10 }) do
  local cap = math.max(2, math.floor(speed * 1.5 + 1e-9))
  for _, hitch in ipairs({ 0.05, 0.1, 0.25, 1.0 }) do
    local n = hitchBurst(speed, hitch)
    check(n <= cap,
      ("%dX: a %.0fms hitch is not repaid as a burst (%d steps, max %d)"):format(speed, hitch * 1000, n, cap))
  end
end
eq(hitchBurst(1, 0.25), 2, "1X after a 250ms hitch runs 2 steps, like before the budget")

FixedStep:init(function() end)
FixedStep.maxAccum = FixedStep.MAX_ACCUM

T.finish("fast forward rate bug 2471")

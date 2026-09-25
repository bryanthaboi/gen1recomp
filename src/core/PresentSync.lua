-- Cross-platform present sync: layered fail-safe for vsync / frame pacing.
--
-- Defense in depth:
--   1. Probe isolation — calibration runs with FrameCap OFF and no FixedStep
--      refresh snap.  Cadence between presents is the signal (Wayland often
--      returns from present() immediately and waits on the next frame).
--   2. Tight classification — stable, panel-aligned cadence only; jitter /
--      unknown rates fail closed.
--   3. Fallback cascade — ungated / failed / abandoned waits force FrameCap
--      immediately; logic never snaps to panel Hz unless sync is confirmed.

local PresentSync = {}

local function probe()
  return require("src.core.PresentProbe")
end

function PresentSync.waitBeforePresent()
  probe().waitBeforePresent()
end

function PresentSync.notePresent()
  probe().notePresent()
end

-- True while DISPLAY+vsync still has no gated/ungated verdict.
function PresentSync.probingDisplaySync()
  local status = probe().status()
  if status.gated ~= nil then return false end
  local FrameCap = require("src.core.FrameCap")
  local VSync = require("src.core.VSync")
  return FrameCap.current == FrameCap.DISPLAY and VSync.isOn()
end

-- Software FrameCap is required only after sync has failed (or a bound wait
-- was abandoned).  During probe we deliberately do NOT soft-cap: the
-- calibration must observe the raw swapchain, not our own limiter.
function PresentSync.needsSoftwareCap()
  return probe().needsSoftwareCap() == true
end

-- Hardware gating is trusted only after a finished probe says gated and the
-- fallback flag is clear.  Probing or failed → not confirmed.
function PresentSync.displaySyncConfirmed()
  if PresentSync.needsSoftwareCap() then return false end
  local status = probe().status()
  return status.gated == true
end

-- True when confirmed display sync already gates at or above the numeric
-- cap, so FrameCap sleep adds nothing.  Requires a finished gated probe —
-- never skip the limiter during warmup or on a guessed refresh rate.
function PresentSync.hardwarePacesCap(cap)
  cap = tonumber(cap)
  if not cap or cap <= 0 then return false end
  if not PresentSync.displaySyncConfirmed() then return false end
  local hz = require("src.core.RefreshRate").hz()
  if not hz or hz <= 0 then return false end
  return cap >= hz
end

-- Vsync cannot be turned on usefully once the probe has failed; the row still
-- allows stepping to OFF.  Warmup does not block the row.
function PresentSync.vsyncEnableBlocked()
  local VSync = require("src.core.VSync")
  if not VSync.isOn() then return false end
  return PresentSync.needsSoftwareCap()
end

function PresentSync.vsyncStepAllowed(mode, dir)
  if not PresentSync.vsyncEnableBlocked() then return true end
  local VSync = require("src.core.VSync")
  return VSync.cycle(mode, dir) == "off"
end

function PresentSync.onDisplayChange()
  probe().onDisplayChange()
end

function PresentSync.reprobe()
  probe().reprobe()
end

function PresentSync.reset()
  probe().reset()
end

function PresentSync.status()
  return probe().status()
end

-- FixedStep.refreshPeriod only when display sync is confirmed working.
-- Never during probe, never when FrameCap is the live pacing path (#1958).
function PresentSync.logicRefreshPeriod()
  local FrameCap = require("src.core.FrameCap")
  local VSync = require("src.core.VSync")
  local RefreshRate = require("src.core.RefreshRate")
  local cap = FrameCap.current

  if cap == FrameCap.DISPLAY then
    if not VSync.isOn() then return nil end
    if not PresentSync.displaySyncConfirmed() then return nil end
    return RefreshRate.period()
  end

  if not cap or cap <= 0 then return nil end
  -- Numeric cap matching panel Hz may snap; still withhold while a DISPLAY
  -- probe failure forced the software limiter (cap may still read DISPLAY
  -- until main.lua overrides the live sleep budget).
  if PresentSync.needsSoftwareCap() then return nil end

  local hz = RefreshRate.hz()
  if hz and cap == hz then return 1 / hz end
  return nil
end

function PresentSync.applyFixedStepPeriod()
  require("src.core.FixedStep").refreshPeriod = PresentSync.logicRefreshPeriod()
end

return PresentSync

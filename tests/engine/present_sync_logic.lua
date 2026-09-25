package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
_G.POKEPORT_LOOP_PANEL_SYNC = true
local FrameCap = require("src.core.FrameCap")
local RefreshRate = require("src.core.RefreshRate")
local VSync = require("src.core.VSync")
local PresentSync = require("src.core.PresentSync")
local FixedStep = require("src.core.FixedStep")
local PresentProbe = require("src.core.PresentProbe")

RefreshRate.reset()
VSync.reset()
PresentSync.reset()
PresentProbe.reset()

local function measure(hz)
  RefreshRate.reset()
  for _ = 1, 31 do RefreshRate.sample(1 / hz) end
end

measure(144)
T.eq(RefreshRate.mismatch(), 144, "144Hz is not a multiple of 60")

FrameCap.apply(FrameCap.DISPLAY)
VSync.reset()
love.window.getVSync = function() return 0 end
love.window.setVSync = function() end
VSync.apply("off")
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "DISPLAY with vsync off does not snap logic to the panel (#1958)")

VSync.reset()
love.window.getVSync = function() return 1 end
VSync.apply("on")
PresentProbe._testSetState({ osLinux = false, ready = true, gated = false,
  needsSoftwareCap = true, nest = "windows" })
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "DISPLAY with broken sync falls back to software cap, not panel snap")
T.check(PresentSync.needsSoftwareCap(), "failed sync trips the FrameCap cascade")
T.check(not PresentSync.displaySyncConfirmed(), "and is not treated as confirmed")

PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
T.eq(PresentSync.logicRefreshPeriod(), 1 / 144,
  "DISPLAY with working sync tracks the panel")
T.check(PresentSync.displaySyncConfirmed(), "gated+clear softcap is confirmed sync")

FrameCap.apply(60)
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "a 60 cap on a 144Hz panel leaves refresh snapping off")
T.check(not PresentSync.hardwarePacesCap(60),
  "60 on 144Hz still needs software pacing headroom")

measure(60)
FrameCap.apply(60)
PresentProbe._testSetState({ osLinux = true, ready = true, gated = true,
  needsSoftwareCap = false, nest = "kmsdrm" })
T.check(PresentSync.hardwarePacesCap(60),
  "60 on 60Hz with working vsync skips the software pacer")
FrameCap.apply(30)
T.check(not PresentSync.hardwarePacesCap(30),
  "30 on 60Hz still needs software pacing")

-- Warmup must not skip FrameCap on a guessed panel rate.
PresentProbe._testSetState({ osLinux = false, ready = true, clearGated = true,
  needsSoftwareCap = false, nest = "android" })
FrameCap.apply(60)
T.check(not PresentSync.hardwarePacesCap(60),
  "Android still probing does not skip FrameCap via hardwarePacesCap")
PresentProbe._testSetState({ nest = "uwp", clearGated = true,
  needsSoftwareCap = false })
T.check(not PresentSync.hardwarePacesCap(60),
  "UWP still probing does not skip FrameCap via hardwarePacesCap")

measure(144)
PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
FrameCap.apply(144)
T.eq(PresentSync.logicRefreshPeriod(), 1 / 144,
  "a 144 cap on a 144Hz panel may snap logic to the panel")

PresentSync.applyFixedStepPeriod()
T.eq(FixedStep.refreshPeriod, 1 / 144, "applyFixedStepPeriod writes the module field")

-- Probe isolation: during calibration we do NOT soft-cap (raw cadence),
-- and we never snap logic until sync is confirmed.
FrameCap.apply(FrameCap.DISPLAY)
VSync.apply("on")
PresentProbe._testSetState({ osLinux = false, ready = true, clearGated = true,
  needsSoftwareCap = false, nest = "windows" })
T.check(PresentSync.probingDisplaySync(), "DISPLAY+vsync probes before a verdict")
T.check(not PresentSync.needsSoftwareCap(),
  "probe isolation: FrameCap is not forced during calibration")
T.check(not PresentSync.displaySyncConfirmed(), "unconfirmed while still probing")
T.eq(PresentSync.logicRefreshPeriod(), nil, "and does not snap logic during warmup")

PresentProbe._testSetState({ gated = true, needsSoftwareCap = false })
T.check(not PresentSync.probingDisplaySync(), "a finished probe clears warmup")
T.check(PresentSync.displaySyncConfirmed(), "gated verdict confirms display sync")
T.check(not PresentSync.needsSoftwareCap(), "so software cap stays off once sync is confirmed")

-- Broken sync after an honest ungated probe keeps the thermal net and no snap.
PresentProbe._testSetState({ gated = false, needsSoftwareCap = true })
T.check(PresentSync.needsSoftwareCap(), "ungated DISPLAY keeps FrameCap")
T.check(not PresentSync.displaySyncConfirmed(), "ungated is never confirmed")
T.eq(PresentSync.logicRefreshPeriod(), nil, "and never snaps logic to the panel")

VSync.apply("on")
PresentProbe._testSetState({ needsSoftwareCap = true, gated = false })
T.check(PresentSync.vsyncEnableBlocked(), "broken sync blocks enabling vsync")
T.check(PresentSync.vsyncStepAllowed("on", 1), "but one step to OFF is allowed")
T.check(PresentSync.vsyncStepAllowed("on", -1),
  "and stepping back is also OFF")

-- FixedStep snaps wall-clock dt, then applies speed (not the reverse).
FixedStep.refreshPeriod = 1 / 60
local steps = 0
FixedStep:init(function() steps = steps + 1 end)
FixedStep.maxAccum = FixedStep.catchupLimit(4)
FixedStep:update(1 / 60, 4)
T.eq(steps, 4, "4X on a snapped 60Hz frame runs four logic steps")
steps = 0
FixedStep.maxAccum = FixedStep.catchupLimit(2)
FixedStep:update(1 / 60, 2)
T.eq(steps, 2, "and 2X runs two")

T.eq(FixedStep.catchupLimit(1), FixedStep.STEP * 2,
  "1X catch-up floor is two steps")
T.eq(FixedStep.catchupLimit(4), 4 * FixedStep.STEP * 1.5,
  "4X catch-up matches one frame of target work")
T.eq(FixedStep.catchupLimit(200), 200 * FixedStep.STEP * 1.5,
  "200X catch-up scales with speed")
T.check(FixedStep.catchupLimit(200) > FixedStep.MAX_ACCUM,
  "200X catch-up is not pinned at MAX_ACCUM")
T.eq(FixedStep.catchupLimit(4, 1 / 30), 4 * (1 / 30) * 1.5,
  "a 30fps frame buys two frames of target work")
T.eq(FixedStep.catchupLimit(4, 1 / 240), 4 * FixedStep.STEP * 1.5,
  "a short frame keeps the one-step floor")
FixedStep.refreshPeriod = nil

love.window.getVSync, love.window.setVSync = nil, nil
VSync.reset()
PresentSync.reset()
PresentProbe.reset()
RefreshRate.reset()
FrameCap.apply(FrameCap.DEFAULT)

T.finish("present sync logic")

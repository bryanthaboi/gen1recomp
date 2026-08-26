-- Graphics performance tier (src/core/Performance.lua): the AUTO device
-- heuristic, tier normalization/labels, per-tier caps, the option-row
-- cycle, and applyOptions recording the live tier.  Pure logic over
-- stubbed love/jit globals, so it needs no ROM and runs in the T2 tier.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Performance = require("src.core.Performance")

-- detect() reads the live `love` and `jit` globals; swap them per scenario
-- and restore afterward so nothing leaks between checks (or into luajit).
local realLove, realJit = love, jit

local function device(os, arch, cores)
  love = {
    system = {
      getOS = function() return os end,
      getProcessorCount = function() return cores end,
    },
  }
  jit = arch and { arch = arch } or nil
end

local function restore()
  love, jit = realLove, realJit
end

-- ---------------------------------------------------------------- detect
device("Linux", "arm64", 4)
T.eq(Performance.detect(), "low", "ARM64 Linux handheld -> low")

device("Linux", "arm", 2)
T.eq(Performance.detect(), "low", "32-bit ARM Linux handheld -> low")

device("Android", "arm64", 8)
T.eq(Performance.detect(), "balanced", "Android phone -> balanced (not low)")

device("iOS", "arm64", 6)
T.eq(Performance.detect(), "balanced", "iOS -> balanced")

device("OS X", "x64", 8)
T.eq(Performance.detect(), "high", "8-core desktop -> high")

device("OS X", "arm64", 10)
T.eq(Performance.detect(), "high", "Apple Silicon Mac is not a handheld LOW")

device("Windows", "arm64", 8)
T.eq(Performance.detect(), "high", "Windows-on-ARM desktop -> high")

device("Windows", "x64", 2)
T.eq(Performance.detect(), "balanced", "dual-core desktop -> balanced")

device("Windows", "x86", 1)
T.eq(Performance.detect(), "balanced", "single-core desktop -> balanced")

-- No love, no jit (a plain-Lua tool/test): nothing looks weak -> high, so
-- tooling that runs applyOptions is never surprised by a clamp.
love, jit = nil, nil
T.eq(Performance.detect(), "high", "no love/jit -> high (no clamping)")
restore()

-- ---------------------------------------------------------------- resolve
T.eq(Performance.resolve("high"), "high", "resolve passes concrete high")
T.eq(Performance.resolve("balanced"), "balanced", "resolve passes balanced")
T.eq(Performance.resolve("low"), "low", "resolve passes low")

device("Linux", "arm64", 4)
T.eq(Performance.resolve("auto"), "low", "resolve auto -> detect (handheld)")
T.eq(Performance.resolve(nil), "low", "resolve nil -> detect")
T.eq(Performance.resolve("bogus"), "low", "resolve garbage -> detect")
restore()

-- --------------------------------------------------------------- normalize
T.eq(Performance.normalize("auto"), "auto", "normalize keeps auto")
T.eq(Performance.normalize("low"), "low", "normalize keeps low")
T.eq(Performance.normalize("xyz"), "auto", "normalize garbage -> auto")
T.eq(Performance.normalize(nil), "auto", "normalize nil -> auto")

-- ------------------------------------------------------------------- label
T.eq(Performance.label("low"), "LOW", "label low")
T.eq(Performance.label("balanced"), "BALANCED", "label balanced")
T.eq(Performance.label(nil), "AUTO", "label nil -> AUTO")

-- -------------------------------------------------------------------- caps
local hi, lo = Performance.CAPS.high, Performance.CAPS.low
T.check(hi.tilt and hi.survey and hi.shaderfx and not hi.fpsMax,
  "high caps: all on, no fps ceiling")
T.check((not lo.tilt) and (not lo.survey) and (not lo.shaderfx),
  "low caps: heavy extras off")
T.eq(lo.fpsMax, 60, "low caps: FPS ceiling of 60")
local bal = Performance.CAPS.balanced
T.check((not bal.tilt) and bal.survey and (not bal.shaderfx) and not bal.fpsMax,
  "balanced caps: no tilt, no shaderfx, survey kept, no fps ceiling")

device("Linux", "arm64", 4)
T.eq(Performance.caps("auto"), Performance.CAPS.low, "caps(auto) resolves through detect")
restore()

-- ------------------------------------------------------------- applyOptions
local caps = Performance.applyOptions({ performance = "low" })
T.eq(caps, Performance.CAPS.low, "applyOptions returns the resolved caps")
T.eq(Performance.tier, "low", "applyOptions records the live tier")

Performance.applyOptions({ performance = "high" })
T.eq(Performance.tier, "high", "applyOptions high tier")

device("Linux", "arm64", 4)
Performance.applyOptions(nil)
T.eq(Performance.tier, "low", "applyOptions(nil) resolves auto to the device tier")
restore()

-- ------------------------------------------------------------------- cycle
T.eq(Performance.cycle("auto", 1), "high", "cycle auto -> high")
T.eq(Performance.cycle("high", 1), "balanced", "cycle high -> balanced")
T.eq(Performance.cycle("balanced", 1), "low", "cycle balanced -> low")
T.eq(Performance.cycle("low", 1), "auto", "cycle low wraps to auto")
T.eq(Performance.cycle("auto", -1), "low", "cycle back auto -> low")
T.eq(Performance.cycle("high", -1), "auto", "cycle back high -> auto")

T.finish("performance_tiers")

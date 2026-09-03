package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FixedStep = require("src.core.FixedStep")
local LogicClock = require("src.core.LogicClock")

T.same(LogicClock.MODES, { "60", "gb" }, "two modes, in row order")
T.eq(LogicClock.normalize(nil), "60", "a save with no key is 60")
T.eq(LogicClock.normalize("junk"), "60", "and so is garbage")
T.eq(LogicClock.label("60"), "60HZ", "60 prints as 60HZ")
T.eq(LogicClock.label("gb"), "59.73HZ", "gb prints the cart's vblank rate")
T.eq(LogicClock.cycle("60", 1), "gb", "60 cycles to gb")
T.eq(LogicClock.cycle("gb", 1), "60", "gb wraps to 60")
T.eq(LogicClock.cycle(nil, -1), "gb", "a missing key normalizes before it steps")

T.check(math.abs(FixedStep.GB_HZ - 59.7275) < 1e-4, "GB_HZ is 4194304 / 70224")

T.eq(LogicClock.apply("gb"), "gb", "apply answers with what it stored")
T.check(math.abs(FixedStep.STEP - 1 / FixedStep.GB_HZ) < 1e-12, "and the fixed step is the cart period")

local steps = 0
FixedStep:init(function() steps = steps + 1 end)
FixedStep.maxAccum = FixedStep.MAX_ACCUM
for _ = 1, 6000 do FixedStep:update(1 / 600, 1) end
T.check(steps >= 597 and steps <= 598, ("ten seconds of wall clock buy %d steps at 59.73Hz"):format(steps))

T.eq(LogicClock.applyOptions({}), "60", "an options table with no key falls back to 60")
T.check(math.abs(FixedStep.STEP - 1 / 60) < 1e-12, "and the step is 1/60 again")
steps = 0
FixedStep:init(function() steps = steps + 1 end)
FixedStep.maxAccum = FixedStep.MAX_ACCUM
for _ = 1, 6000 do FixedStep:update(1 / 600, 1) end
T.check(steps >= 599 and steps <= 600, ("ten seconds buy %d steps at 60Hz"):format(steps))

LogicClock.applyOptions({ logicClock = "gb" })
T.eq(LogicClock.current, "gb", "applyOptions reads options.logicClock")
LogicClock.apply("60")

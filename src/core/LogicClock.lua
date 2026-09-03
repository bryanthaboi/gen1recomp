local FixedStep = require("src.core.FixedStep")

local LogicClock = {}

LogicClock.MODES = { "60", "gb" }
LogicClock.DEFAULT = "60"
LogicClock.HZ = { ["60"] = 60, gb = FixedStep.GB_HZ }
LogicClock.current = LogicClock.DEFAULT

function LogicClock.normalize(mode)
  if mode == "gb" or mode == "60" then return mode end
  return LogicClock.DEFAULT
end

function LogicClock.hz(mode)
  return LogicClock.HZ[LogicClock.normalize(mode)]
end

function LogicClock.label(mode)
  if LogicClock.normalize(mode) == "gb" then return "59.73HZ" end
  return "60HZ"
end

function LogicClock.cycle(mode, dir)
  local ring = LogicClock.MODES
  local cur = LogicClock.normalize(mode)
  local at = 1
  for i, m in ipairs(ring) do
    if m == cur then at = i break end
  end
  return ring[(at - 1 + (dir or 1)) % #ring + 1]
end

function LogicClock.apply(mode)
  LogicClock.current = LogicClock.normalize(mode)
  FixedStep.setHz(LogicClock.hz(LogicClock.current))
  return LogicClock.current
end

function LogicClock.applyOptions(opts)
  return LogicClock.apply(opts and opts.logicClock)
end

return LogicClock

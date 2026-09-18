-- Game3 battle capabilities (FRLG-shaped; no Gen4+ defaults).

local Capabilities = {
  gen3Crit = true,
  gen3PartialTrap = true,
  weatherChipDenom = 16,
  partialTrapChipDenom = 16,
  partialTrapMinTurns = 3,
  partialTrapMaxTurns = 6,
  screenDefaultTurns = 5,
  safeguardDefaultTurns = 5,
  weatherDefaultTurns = 5,
  critMultiplier = 2,
}

function Capabilities.get()
  return Capabilities
end

return Capabilities

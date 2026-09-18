-- Minimal stand-in for mods.Kanto-Reforged.core.host (standalone Game3).

local Host = {}

function Host.isGen1()
  return false
end

function Host.isGen2()
  return false
end

function Host.isGen3()
  return true
end

function Host.game()
  return nil
end

return Host

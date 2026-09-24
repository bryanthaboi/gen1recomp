local Guard = {}

Guard.active = false
Guard.tripped = nil

function Guard.arm()
  Guard.active = true
  Guard.tripped = nil
end

function Guard.disarm()
  Guard.active = false
end

function Guard.trip(where)
  Guard.tripped = Guard.tripped or tostring(where or "rng")
  error("link battle rng fallback: " .. tostring(where or "rng"), 2)
end

function Guard.fallback(where, lo, hi)
  if Guard.active then Guard.trip(where) end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    if lo == nil then return Rng.compat() end
    return Rng.compat(lo, hi)
  end
  if lo == nil then return math.random() end
  return math.random(lo, hi)
end

function Guard.source(where, fallback)
  if not Guard.active then return fallback end
  return function(...)
    if Guard.active then Guard.trip(where) end
    return fallback(...)
  end
end

return Guard

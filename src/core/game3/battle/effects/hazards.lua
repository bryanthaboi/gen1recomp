-- Hazards (FRLG Spikes only; Gen4+ not registered).

local H = require("src.core.game3.battle.effects._helpers")
local Strings = require("src.core.Strings")

local Hazards = {}

function Hazards.layers(side)
  if not side then return 0 end
  local n = tonumber(side.spikes) or 0
  local hz = side.hazards
  if hz then
    n = math.max(n, tonumber(hz.spikes) or 0)
    for _, h in ipairs(hz) do
      if h.id == "SPIKES" then n = math.max(n, tonumber(h.layers) or 1) end
    end
  end
  return n
end

function Hazards.set(side, n)
  if not side then return end
  side.hazards = side.hazards or {}
  local keep = {}
  for _, h in ipairs(side.hazards) do
    if h.id ~= "SPIKES" then keep[#keep + 1] = h end
  end
  for i = #side.hazards, 1, -1 do side.hazards[i] = nil end
  for i, h in ipairs(keep) do side.hazards[i] = h end
  if n > 0 then
    side.hazards[#side.hazards + 1] = { id = "SPIKES", layers = n }
    side.hazards.spikes = n
    side.spikes = n
  else
    side.hazards.spikes = nil
    side.spikes = 0
  end
end

function Hazards.clear(side)
  Hazards.set(side, 0)
end

-- pokefirered/src/battle_script_commands.c:8110
function Hazards.spikes(ctx)
  local side = H.foeSide(ctx)
  if not side then return H.sayFail(ctx) end
  local n = Hazards.layers(side)
  if n >= 3 then return H.sayFail(ctx) end
  Hazards.set(side, n + 1)
  H.attackAnim(ctx)
  ctx.adapter:say(Strings("SPIKES were scattered all around\nthe opponent's side!"))
end

return Hazards

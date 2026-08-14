-- Gen 1 type effectiveness from generated data (multipliers x10).
-- Like the original, each matchup row applies independently, so dual types
-- multiply (e.g. 20 * 5 -> neutral).

local Strings = require("src.core.Strings")
local TypeChart = {}
local index
local matchups
local types

function TypeChart.load(data)
  index = {}
  matchups = data.type_chart.matchups
  for _, m in ipairs(matchups) do
    index[m.attacker] = index[m.attacker] or {}
    index[m.attacker][m.defender] = m.multiplier
  end
  types = data.type_chart.types
end

function TypeChart.category(typeId)
  local record = types and types[typeId] or TypeChart.TYPES[typeId]
  return record and record.category or nil
end

function TypeChart.displayName(typeId)
  local record = types and types[typeId] or TypeChart.TYPES[typeId]
  return record and Strings(record.name) or typeId
end

function TypeChart.rows(moveType, defenderTypes)
  assert(matchups, "TypeChart.load not called")
  local out = {}
  for _, m in ipairs(matchups) do
    if m.attacker == moveType then
      for _, dt in ipairs(defenderTypes) do
        if m.defender == dt then out[#out + 1] = m.multiplier; break end
      end
    end
  end
  return out
end

function TypeChart.effectiveness(moveType, defenderTypes)
  assert(index, "TypeChart.load not called")
  local mult = 10
  local row = index[moveType]
  if not row then return mult end
  for _, dt in ipairs(defenderTypes) do
    local m = row[dt]
    if m ~= nil then mult = math.floor(mult * m / 10) end
  end
  return mult
end

TypeChart.TYPES = {
  NORMAL       = { name = "NORMAL",   category = "physical" },
  FIGHTING     = { name = "FIGHTING", category = "physical" },
  FLYING       = { name = "FLYING",   category = "physical" },
  POISON       = { name = "POISON",   category = "physical" },
  GROUND       = { name = "GROUND",   category = "physical" },
  ROCK         = { name = "ROCK",     category = "physical" },
  BUG          = { name = "BUG",      category = "physical" },
  GHOST        = { name = "GHOST",    category = "physical" },
  FIRE         = { name = "FIRE",     category = "special" },
  WATER        = { name = "WATER",    category = "special" },
  GRASS        = { name = "GRASS",    category = "special" },
  ELECTRIC     = { name = "ELECTRIC", category = "special" },
  PSYCHIC_TYPE = { name = "PSYCHIC",  category = "special" },
  ICE          = { name = "ICE",      category = "special" },
  DRAGON       = { name = "DRAGON",   category = "special" },
}

function TypeChart.registerInto(registry, data, owner)
  for id, record in pairs(TypeChart.TYPES) do registry:register(id, record, owner) end
  local chart = data and data.type_chart
  for _, row in ipairs(chart and chart.matchups or {}) do
    registry:register(row.attacker .. ">" .. row.defender, { multiplier = row.multiplier }, owner)
  end
end

return TypeChart

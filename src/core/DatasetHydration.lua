-- Canonical pure shaping shared by the active boot and inactive dataset views.
-- The caller supplies both the data table and selected version; no global
-- GameVersion, cache prefix, mount, or active Data table is changed.

local GameVersion = require("src.core.GameVersion")

local DatasetHydration = {}

function DatasetHydration.applyGen2(data, moduleLoader)
  local chart = data.type_chart or {}
  chart.matchups = chart.matchups or {}
  for _, row in ipairs(chart.foresightMatchups or {}) do
    chart.matchups[#chart.matchups + 1] = row
  end
  data.type_chart = chart
  data.gen2HeldItems =
    (moduleLoader or require)("src.core.gen2.ItemEffects").heldItemsFrom(data.items)
  return data
end

function DatasetHydration.apply(data, version, moduleLoader)
  if GameVersion.generation(version) == 2 then
    return DatasetHydration.applyGen2(data, moduleLoader)
  end
  require("src.core.Data").seedDefaults(data, version)
  return data
end

return DatasetHydration

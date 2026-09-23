local M = {}

function M.install(overrides)
  local MapSections = require("src.import.gba.map_sections_extract")
  if pcall(MapSections.ensureGenerated) then return false end
  local names = {}
  for secId, info in pairs(MapSections.SECTIONS) do
    names[secId] = (overrides and overrides[secId]) or info.id:gsub("^MAPSEC_", ""):gsub("_", " ")
  end
  MapSections.installNames(names)
  return true
end

return M

local FlagIds = require("src.core.gen2.FlagIds")

local Gen2Flags = {}

local LINEAGE = { gs = { "gold", "silver" }, crystal = { "crystal" } }

local function cacheConstants(engine)
  local SaveConvert = require("src.save_convert.SaveConvert")
  for _, version in ipairs(LINEAGE[engine]) do
    local constants = SaveConvert.gen2Constants(version)
    if constants then return constants end
  end
  return nil
end

local source = cacheConstants
local cache = {}

function Gen2Flags.setSource(fn)
  source = fn or cacheConstants
  cache = {}
end

function Gen2Flags.byName(engine)
  engine = (engine == "crystal") and "crystal" or "gs"
  if cache[engine] then return cache[engine] end
  local constants = source(engine)
  if not constants then
    error(("no %s cache: import the ROM before editing its event flags"):format(
      table.concat(LINEAGE[engine], " or ")), 2)
  end
  local ids = {}
  for name, id in pairs(FlagIds.events(constants)) do ids[name] = id end
  cache[engine] = ids
  return ids
end

function Gen2Flags.names(engine)
  local names = {}
  for name in pairs(Gen2Flags.byName(engine)) do names[#names + 1] = name end
  table.sort(names)
  return names
end

return Gen2Flags

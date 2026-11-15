local ORDER = require("src.save_convert.data.gen2_engine_flags")

local Gen2EngineFlags = {}

Gen2EngineFlags.ORDER = ORDER

local ids = {}
for family, list in pairs(ORDER) do
  local map = {}
  for id, name in pairs(list) do map[name] = id end
  ids[family] = map
end

function Gen2EngineFlags.family(gameVersion)
  return gameVersion == "crystal" and "crystal" or "gs"
end

function Gen2EngineFlags.id(gameVersion, name)
  local id = ids[Gen2EngineFlags.family(gameVersion)][name]
  if id == nil then
    error(("%s has no engine flag %s"):format(tostring(gameVersion), tostring(name)), 2)
  end
  return id
end

function Gen2EngineFlags.run(gameVersion, first, last)
  local from, to = Gen2EngineFlags.id(gameVersion, first), Gen2EngineFlags.id(gameVersion, last)
  local out = {}
  for id = from, to do out[id - from] = id end
  return out
end

return Gen2EngineFlags

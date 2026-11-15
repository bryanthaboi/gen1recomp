-- constants/event_flags.asm:1, constants/engine_flags.asm:2
local FlagIds = {}

local memo = { eventFlagOrder = setmetatable({}, { __mode = "k" }),
               engineFlagOrder = setmetatable({}, { __mode = "k" }) }

local function byName(constants, key)
  if type(constants) ~= "table" then error("no Gen 2 constants.lua", 3) end
  local hit = memo[key][constants]
  if hit then return hit end
  local order = constants[key]
  if type(order) ~= "table" then error("constants.lua has no " .. key, 3) end
  local map = {}
  for index, name in pairs(order) do
    if type(index) == "number" and type(name) == "string" then map[name] = index - 1 end
  end
  if next(map) == nil then error("constants.lua has an empty " .. key, 3) end
  memo[key][constants] = map
  return map
end

function FlagIds.events(constants)
  return byName(constants, "eventFlagOrder")
end

function FlagIds.engine(constants)
  return byName(constants, "engineFlagOrder")
end

return FlagIds

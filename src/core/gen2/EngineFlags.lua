-- constants/engine_flags.asm:2
local EngineFlags = {}

local ids = nil
local boundOrder = nil

function EngineFlags.bind(order)
  if type(order) ~= "table" then
    error("constants.lua has no engineFlagOrder", 2)
  end
  local map = {}
  for index, name in pairs(order) do
    if type(index) == "number" and type(name) == "string" then
      map[name] = index - 1
    end
  end
  if next(map) == nil then error("constants.lua has an empty engineFlagOrder", 2) end
  ids = map
  boundOrder = order
  return map
end

function EngineFlags.ensure(...)
  local order
  for i = 1, select("#", ...) do
    local data = select(i, ...)
    local constants = type(data) == "table" and data.gen2Constants
    order = type(constants) == "table" and constants.engineFlagOrder or nil
    if order ~= nil then break end
  end
  if order == nil then
    if ids then return end
    error("constants.lua has no engineFlagOrder", 2)
  end
  if order ~= boundOrder then EngineFlags.bind(order) end
end

function EngineFlags.order()
  return boundOrder
end

function EngineFlags.id(name)
  if not ids then error("engine flags are not bound", 2) end
  local id = ids[name]
  if id == nil then error("engineFlagOrder has no " .. tostring(name), 2) end
  return id
end

function EngineFlags.has(name)
  if not ids then error("engine flags are not bound", 2) end
  return ids[name] ~= nil
end

function EngineFlags.expose(module, names)
  local wanted = {}
  for _, name in ipairs(names) do wanted[name] = true end
  return setmetatable(module, {
    __index = function(_, key)
      if wanted[key] then return EngineFlags.id(key) end
      return nil
    end,
  })
end

return EngineFlags

-- src/event_object_movement.c:1719, src/event_object_movement.c:9236, src/event_object_movement.c:9248-9257

local VirtualObjects = {}

-- include/constants/global.h:110, event.inc
VirtualObjects.DIR_SOUTH = 1

local byId = {}
local order = {}
local logged = {}

local function log_once(key, msg)
  if logged[key] then return end
  logged[key] = true
  print("[game3/virtual_objects] " .. tostring(msg))
end

-- src/scrcmd.c:1171-1181
function VirtualObjects.spawn(vObjId, graphicsId, x, y, elevation, direction)
  local id = tonumber(vObjId)
  if id == nil then
    log_once("spawn:" .. tostring(vObjId), "createvobject with a non-numeric id")
    return nil
  end
  if byId[id] == nil then
    order[#order + 1] = id
  end
  local rec = {
    id = id,
    graphicsId = tonumber(graphicsId) or 0,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
    -- event.inc:1346
    elevation = tonumber(elevation) or 3,
    direction = tonumber(direction) or VirtualObjects.DIR_SOUTH,
  }
  byId[id] = rec
  return rec
end

function VirtualObjects.turn(vObjId, direction)
  local id = tonumber(vObjId)
  local rec = id and byId[id] or nil
  if not rec then
    log_once("turn:" .. tostring(vObjId),
      "turnvobject for an id that was never created (" .. tostring(vObjId) .. ")")
    return false
  end
  rec.direction = tonumber(direction) or rec.direction
  return true
end

function VirtualObjects.get(vObjId)
  local id = tonumber(vObjId)
  return id and byId[id] or nil
end

function VirtualObjects.list()
  local out = {}
  for i = 1, #order do
    local rec = byId[order[i]]
    if rec then out[#out + 1] = rec end
  end
  return out
end

function VirtualObjects.count()
  local n = 0
  for _ in pairs(byId) do n = n + 1 end
  return n
end

-- event_object_movement.c:9225
function VirtualObjects.clear()
  for k in pairs(byId) do byId[k] = nil end
  for i = #order, 1, -1 do order[i] = nil end
end

function VirtualObjects.reset()
  VirtualObjects.clear()
  logged = {}
end

return VirtualObjects

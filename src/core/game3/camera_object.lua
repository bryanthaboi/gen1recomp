-- pokefirered/src/field_specials.c:318

local CameraObject = {}

-- pokefirered/include/constants/event_objects.h:203
CameraObject.LOCALID = 127
-- pokefirered/include/constants/event_objects.h:24
local GFX_YOUNGSTER = 18
-- pokefirered/include/constants/event_object_movement.h:13
local MOVEMENT_TYPE_FACE_DOWN = 0x8
local ELEVATION = 3

local CELL = 16

CameraObject._eo = nil
CameraObject._mapId = nil
CameraObject._wrapped = false

local function Objects()
  return package.loaded["src.core.game3.objects"]
    or require("src.core.game3.objects")
end

local function Player()
  return package.loaded["src.core.game3.player"]
    or require("src.core.game3.player")
end

local function orderIndex(order, lid)
  for i = 1, #order do
    if order[i] == lid then return i end
  end
  return nil
end

local function live()
  local eo = CameraObject._eo
  if not eo then return nil end
  local O = Objects()
  local lid = CameraObject.LOCALID
  if O._byId[lid] ~= eo then
    if O._mapId ~= nil and O._mapId == CameraObject._mapId then
      O._byId[lid] = eo
      if not orderIndex(O._order, lid) then
        O._order[#O._order + 1] = lid
      end
      return eo
    end
    CameraObject._eo = nil
    CameraObject._mapId = nil
    return nil
  end
  return eo
end

function CameraObject.isActive()
  return live() ~= nil
end

function CameraObject.object()
  return live()
end

-- pokefirered/src/event_object_movement.c:2427
function CameraObject.offset()
  local eo = live()
  if not eo then return 0, 0 end
  local P = Player()
  local dx = (tonumber(eo.px) or 0) - (tonumber(P.px) or 0)
  local dy = (tonumber(eo.py) or 0) - (tonumber(P.py) or 0)
  return math.floor(dx + 0.5), math.floor(dy + 0.5)
end

-- pokefirered/src/field_camera.c:89
function CameraObject.installViewSeam()
  if CameraObject._wrapped then return true end
  local okV, FieldView = pcall(require, "src.core.game3.field_view")
  if not okV or type(FieldView) ~= "table" or type(FieldView.draw) ~= "function" then
    return false
  end
  local orig = FieldView.draw
  FieldView.draw = function(game, canvasW, canvasH, opts)
    local dx, dy = CameraObject.offset()
    if dx == 0 and dy == 0 then
      return orig(game, canvasW, canvasH, opts)
    end
    local bx = FieldView.cameraPanX or 0
    local by = FieldView.cameraPanY or 0
    FieldView.cameraPanX, FieldView.cameraPanY = bx + dx, by + dy
    local ok, err = pcall(orig, game, canvasW, canvasH, opts)
    FieldView.cameraPanX, FieldView.cameraPanY = bx, by
    if not ok then error(err, 0) end
  end
  FieldView._game3CameraObjectSeam = true
  CameraObject._wrapped = true
  return true
end

function CameraObject.spawn(game)
  local eo = live()
  if eo then return eo end
  local O = Objects()
  local P = Player()
  local lid = CameraObject.LOCALID
  local cx = tonumber(P.cellX) or 0
  local cy = tonumber(P.cellY) or 0
  local pool = O.spawnFromDefs({ {
    localId = lid,
    x = cx,
    y = cy,
    graphicsId = GFX_YOUNGSTER,
    movementType = MOVEMENT_TYPE_FACE_DOWN,
    elevation = ELEVATION,
  } }, nil)
  eo = pool and pool.byId and pool.byId[lid]
  if not eo then return nil end
  eo.visible = false
  eo.hidden = true
  eo.px = tonumber(P.px) or (cx * CELL)
  eo.py = tonumber(P.py) or (cy * CELL)
  eo.facing = P.facing or "down"
  O._byId[lid] = eo
  if not orderIndex(O._order, lid) then
    O._order[#O._order + 1] = lid
  end
  O._tracks[lid] = nil
  CameraObject._eo = eo
  CameraObject._mapId = O._mapId
  CameraObject.installViewSeam()
  return eo
end

-- pokefirered/src/field_specials.c:325
function CameraObject.remove(game)
  local O = Objects()
  local lid = CameraObject.LOCALID
  local eo = CameraObject._eo
  CameraObject._eo = nil
  CameraObject._mapId = nil
  local tr = O._tracks[lid]
  if tr and not tr.done then
    tr.done = true
    local cb = tr.onDone
    tr.onDone = nil
    if cb then cb() end
  end
  if O._byId[lid] == nil then return false end
  if eo ~= nil and O._byId[lid] ~= eo then return false end
  O._byId[lid] = nil
  local i = orderIndex(O._order, lid)
  if i then table.remove(O._order, i) end
  return true
end

function CameraObject.reset()
  local O = package.loaded["src.core.game3.objects"]
  local lid = CameraObject.LOCALID
  if O and O._byId and O._byId[lid] and O._byId[lid] == CameraObject._eo then
    O._byId[lid] = nil
    local i = orderIndex(O._order, lid)
    if i then table.remove(O._order, i) end
    if O._tracks then O._tracks[lid] = nil end
  end
  CameraObject._eo = nil
  CameraObject._mapId = nil
end

return CameraObject

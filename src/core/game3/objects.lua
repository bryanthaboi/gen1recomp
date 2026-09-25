-- Game3 EventObject instances (localId-keyed).
-- Owns idle AI + applymovement tracks; optional host NPC mirror for adapters.
-- Player localId 0xFF delegates to game3.player. Talk is Field.interact.

local Movement = require("src.core.game3.scripting.movement")
local Opcodes = require("src.core.game3.scripting.opcodes")
local GfxIds = require("src.core.game3.scripting.gfx_ids")
local ModRuntime = require("src.mods.Runtime")
local VirtualObjects = require("src.core.game3.virtual_objects")

local Objects = {}

Objects.PLAYER_LOCAL_ID = Opcodes.LOCALID_PLAYER or 0xFF

local CELL = 16
local WALK_FRAMES = 16
-- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
local RUN_FRAMES = 8
-- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
local RUN_SLOW_FRAMES = 11
-- include/constants/event_object_movement.h:81
local MOVEMENT_TYPE_INVISIBLE = 0x4C
Objects.MOVEMENT_TYPE_INVISIBLE = MOVEMENT_TYPE_INVISIBLE
local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

Objects._byId = {} -- [localId] = EventObject
Objects._order = {} -- stable draw/list order
Objects._tracks = {} -- [localId] = movement track
Objects._mapId = nil
Objects._defs = nil -- original mapDef.objects (for addobject)
Objects._bounds = nil
-- Permanent template overrides from setobjectxyperm / setobjectmovementtype.
-- Survives loadMap within a session (pret objectEventTemplates).
Objects._perm = {} -- [mapId] = { [localId] = { x=, y=, movementType= } }
Objects._templateMt = {}
Objects._logged = false

local function log(msg)
  print("[game3/objects] " .. tostring(msg))
end

-- pokefirered/src/overworld.c
local function layoutBounds(mapDef)
  local L = mapDef and mapDef.midLayout
  local w = L and L.width or 0
  local h = L and L.height or 0
  if w < 1 or h < 1 then return nil end
  return { w = w, h = h }
end

Objects.layoutBounds = layoutBounds

local function offMap(bounds, eo)
  if not bounds then return false end
  local x = eo.cellX or 0
  local y = eo.cellY or 0
  return x < 0 or y < 0 or x >= bounds.w or y >= bounds.h
end

Objects.offMap = offMap

local function Collision()
  return package.loaded["src.core.game3.collision"]
    or require("src.core.game3.collision")
end

local function Player()
  return package.loaded["src.core.game3.player"]
    or require("src.core.game3.player")
end

local function Space()
  return package.loaded["src.core.game3.scripting.space"]
end

function Objects.isPlayer(localId)
  local id = tonumber(localId)
  return id == Objects.PLAYER_LOCAL_ID or id == 0xFF or id == 0x800F
end

local function facingFromDef(def)
  local r = tostring(def.facing or def.range or "DOWN"):lower()
  if r == "up" or r == "down" or r == "left" or r == "right" then
    return r
  end
  if r == "any_dir" or r == "up_down" or r == "left_right" then
    return "down"
  end
  return "down"
end

local function dirsForRange(range)
  local r = tostring(range or "DOWN"):upper()
  if r == "ANY_DIR" then return { "up", "down", "left", "right" } end
  if r == "UP_DOWN" then return { "up", "down" } end
  if r == "LEFT_RIGHT" then return { "left", "right" } end
  if r == "UP" then return { "up" } end
  if r == "DOWN" then return { "down" } end
  if r == "LEFT" then return { "left" } end
  if r == "RIGHT" then return { "right" } end
  return { "down", "up", "left", "right" }
end

local function objectVisible(def)
  local SpaceMod = Space()
  if SpaceMod and SpaceMod.objectVisible then
    return SpaceMod.objectVisible(def)
  end
  local flag = def.flag
  if not flag or flag == 0 or flag == 0xFFFF or flag == 65535 then
    return true
  end
  return true
end

local function newEventObject(def, neighbor)
  -- Shallow-copy template so setobjectxy / removeobject cannot poison the
  -- shared events.lua / mapDef.objects tables for the rest of the session.
  local src = def or {}
  def = {}
  for k, v in pairs(src) do
    def[k] = v
  end
  local lid = tonumber(def.localId or def.index) or 0
  local x = tonumber(def.x) or 0
  local y = tonumber(def.y) or 0
  local rawMt = tonumber(def.movementType)
  local mt = rawMt or 0
  local spec
  if rawMt then
    spec = GfxIds.hostMovement(rawMt, def.rangeX, def.rangeY)
  else
    local r = def.radius or { x = 1, y = 1 }
    spec = {
      movement = def.movement or "STAY", range = def.range or "DOWN",
      rangeX = r.x, rangeY = r.y, radius = r,
    }
  end
  local facing = (def.facing and facingFromDef(def))
    or (rawMt and spec.face) or facingFromDef(def)
  local sprite = def.sprite
  local resolvedGfx = def.graphicsId or def.graphics
  do
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if okS and Space and Space.resolveObjectGraphicsId then
      local gid = Space.resolveObjectGraphicsId(def, neighbor)
      if gid then resolvedGfx = gid end
    end
  end
  if not sprite and resolvedGfx then
    sprite = GfxIds.spriteFor(resolvedGfx)
  end
  local Coll = Collision()
  local elev = (def.elevation and def.elevation ~= 0 and def.elevation)
    or (Coll and Coll.elevationAt and Coll.elevationAt(x, y)) or 0
  return {
    localId = lid,
    def = def,
    cellX = x,
    cellY = y,
    px = x * CELL,
    py = y * CELL,
    homeX = x,
    homeY = y,
    facing = facing,
    sprite = sprite or "SPRITE_YOUNGSTER",
    graphicsId = resolvedGfx,
    elevation = elev,
    currentElevation = tonumber(def.elevation) or 0,
    movementType = mt,
    movement = spec.movement,
    range = spec.range,
    radius = spec.radius or { x = spec.rangeX, y = spec.rangeY },
    rangeX = spec.rangeX,
    rangeY = spec.rangeY,
    spec = spec,
    seqIndex = 0,
    sight = tonumber(def.sight or def.trainerRange) or 0,
    trainerType = tonumber(def.trainerType) or 0,
    scriptKey = def.scriptKey,
    flag = def.flag,
    visible = objectVisible(def),
    hidden = not objectVisible(def),
    -- src/event_object_movement.c:1569
    invisible = mt == MOVEMENT_TYPE_INVISIBLE,
    frozen = false,
    passable = def.passable and true or false,
    moving = false,
    progress = 0,
    stepFrames = WALK_FRAMES,
    targetX = x,
    targetY = y,
    stepFlip = false,
    animClock = 0,
    scriptBusy = false,
  }
end

function Objects.clear()
  Objects._byId = {}
  Objects._order = {}
  Objects._tracks = {}
  Objects._mapId = nil
  Objects._defs = nil
  Objects._bounds = nil
  -- src/event_object_movement.c:9225
  VirtualObjects.clear()
end

-- pokefirered/src/overworld.c:405
function Objects.reset()
  Objects.clear()
  Objects._perm = {}
  Objects._templateMt = {}
  Objects._logged = false
  VirtualObjects.reset()
end

function Objects.hasMap()
  return Objects._mapId ~= nil
end

--- Re-resolve OBJ_EVENT_GFX_VAR_* after ON_TRANSITION sets VAR_OBJ_GFX_ID_*.
function Objects.refreshGraphics()
  local okS, Space = pcall(require, "src.core.game3.scripting.space")
  if not (okS and Space and Space.resolveObjectGraphicsId) then return 0 end
  local n = 0
  for _, eo in pairs(Objects._byId or {}) do
    if eo and eo.def then
      local gid = Space.resolveObjectGraphicsId(eo.def)
      if gid and gid ~= eo.graphicsId then
        eo.graphicsId = gid
        eo.sprite = GfxIds.spriteFor(gid) or eo.sprite
        n = n + 1
      elseif gid then
        eo.graphicsId = gid
      end
    end
  end
  local okFv, FieldView = pcall(require, "src.core.game3.field_view")
  if okFv and FieldView then FieldView._nativeDirty = true end
  return n
end

function Objects.hasActiveTracks()
  for _, tr in pairs(Objects._tracks) do
    if tr and not tr.done then return true end
  end
  return false
end

local function rememberPerm(mapId, localId, fields)
  mapId = mapId or Objects._mapId
  localId = tonumber(localId) or 0
  if not mapId or localId <= 0 then return end
  local bucket = Objects._perm[mapId]
  if not bucket then
    bucket = {}
    Objects._perm[mapId] = bucket
  end
  local row = bucket[localId]
  if not row then
    row = {}
    bucket[localId] = row
  end
  for k, v in pairs(fields) do
    row[k] = v
  end
end

Objects.rememberPerm = rememberPerm

-- src/event_object_movement.c:4806
local function setSpec(eo, mt)
  local spec = GfxIds.hostMovement(mt, eo.rangeX, eo.rangeY)
  spec.rangeX = tonumber(eo.rangeX) or 0
  spec.rangeY = tonumber(eo.rangeY) or 0
  spec.radius = { x = spec.rangeX, y = spec.rangeY }
  eo.movementType = tonumber(mt) or 0
  eo.spec = spec
  eo.movement = spec.movement
  eo.range = spec.range
  eo.radius = spec.radius
  eo.seqIndex = 0
  eo.idleTimer = nil
end

local function applyPerm(eo, mapId)
  local bucket = Objects._perm[mapId]
  local row = bucket and bucket[eo.localId]
  if not row then return end
  if row.x ~= nil then
    eo.cellX = row.x
    eo.homeX = row.x
    eo.px = row.x * CELL
    eo.targetX = row.x
    if eo.def then eo.def.x = row.x end
  end
  if row.y ~= nil then
    eo.cellY = row.y
    eo.homeY = row.y
    eo.py = row.y * CELL
    eo.targetY = row.y
    if eo.def then eo.def.y = row.y end
  end
  if row.movementType ~= nil then
    setSpec(eo, row.movementType)
    -- src/event_object_movement.c:1378
    eo.facing = eo.spec.face
    -- src/event_object_movement.c:1569
    eo.invisible = tonumber(row.movementType) == MOVEMENT_TYPE_INVISIBLE
    if eo.def then eo.def.movementType = row.movementType end
  end
  if row.facing ~= nil then
    eo.facing = row.facing
    if eo.def then eo.def.facing = row.facing end
  end
end

local function resolveContextualMapObjects(mapId)
  if mapId == "FR_OAKS_LAB" or mapId == "PalletTown_ProfessorOaksLab" then
    local Sp = Space()
    local store = Sp and Sp.store
    local Flags = package.loaded["src.core.game3.scripting.flags"]
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()

    local oakScene = 0
    if Flags and Flags.getVar and store then
      oakScene = Flags.getVar(store, nil, 0x4055)
    elseif session and session.vars then
      oakScene = tonumber(session.vars[0x4055]) or 0
    end

    local starter = 0
    if Flags and Flags.getVar and store then
      starter = Flags.getVar(store, nil, 0x4031)
    elseif session and session.vars then
      starter = tonumber(session.vars[0x4031]) or 0
    end

    if starter == 0 and session and session.party and session.party[1] then
      local sp = session.party[1].species
      if sp == 4 then starter = 2      -- Charmander -> Rival has Squirtle
      elseif sp == 7 then starter = 1  -- Squirtle -> Rival has Bulbasaur
      elseif sp == 1 then starter = 0  -- Bulbasaur -> Rival has Charmander
      end
    end

    if oakScene == 1 or oakScene == 2 then
      rememberPerm(mapId, 4, { x = 6, y = 3, movementType = 8, facing = "down" })
      rememberPerm(mapId, 8, { x = 5, y = 4, movementType = 7, facing = "up" })
    elseif oakScene == 3 then
      rememberPerm(mapId, 4, { x = 6, y = 3, movementType = 8, facing = "down" })
      local rx, ry = 10, 5
      if starter == 1 then
        rx, ry = 8, 5
      elseif starter == 2 then
        rx, ry = 9, 5
      end
      rememberPerm(mapId, 8, { x = rx, y = ry, movementType = 7, facing = "up" })
    elseif (oakScene >= 4 and oakScene <= 6) or oakScene >= 8 then
      rememberPerm(mapId, 4, { x = 6, y = 3, movementType = 8, facing = "down" })
    end
  end
  if mapId == "FR_PALLET_TOWN" or mapId == "PalletTown" then
    local Sp = Space()
    local store = Sp and Sp.store
    local Flags = package.loaded["src.core.game3.scripting.flags"]
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()

    local signLadyScene = 0
    if Flags and Flags.getVar and store then
      signLadyScene = Flags.getVar(store, nil, 0x4070)
    elseif session and session.vars then
      signLadyScene = tonumber(session.vars[0x4070]) or 0
    end

    local hasStarter = false
    if Flags and Flags.getFlag and store then
      hasStarter = Flags.getFlag(store, nil, 0x291) or Flags.getFlag(store, nil, 0x828)
    end
    if not hasStarter and session and session.flags then
      hasStarter = session.flags[0x291] == true or session.flags["0x291"] == true
        or session.flags[657] == true or session.flags["657"] == true
        or session.flags[0x828] == true or session.flags["0x828"] == true
        or session.flags[2088] == true or session.flags["2088"] == true
    end
    if not hasStarter and session and session.party and #session.party > 0 then
      hasStarter = true
    end

    if signLadyScene == 0 then
      if hasStarter then
        rememberPerm(mapId, 1, { x = 12, y = 2, movementType = 8, facing = "down" })
        if Flags and store then
          Flags.setVar(store, nil, 0x4002, 1) -- VAR_TEMP_2 = 1 (SIGN_LADY_READY)
          Flags.setFlag(store, nil, 0x291, true)
          Flags.setFlag(store, nil, 0x83E, false) -- FLAG_OPENED_START_MENU = false until scene completes
        end
        if session then
          if session.vars then session.vars[0x4002] = 1 end
          if session.flags then
            session.flags[0x291] = true
            session.flags[657] = true
            session.flags[0x83E] = nil
            session.flags[2110] = nil
          end
        end
      else
        rememberPerm(mapId, 1, { x = 5, y = 15, movementType = 7, facing = "up" })
      end
    end
  end
end

-- src/event_object_movement.c:1312
local function spawnFromTemplate(def, mapId)
  local eo = newEventObject(def)
  if eo.localId > 0 then
    applyPerm(eo, mapId)
    local tmt = Objects._templateMt[eo.localId]
    if tmt then
      Objects.setTrainerMovementType(eo, tmt)
      -- src/event_object_movement.c:1569
      eo.invisible = tmt == MOVEMENT_TYPE_INVISIBLE
      local face = ({ [7] = "up", [8] = "down", [9] = "left", [10] = "right" })[tmt]
      if face then eo.facing = face end
    end
  end
  return eo
end

-- src/event_object_movement.c:1651
local function respawnFromTemplate(lid)
  local tpl
  for _, def in ipairs(Objects._defs or {}) do
    if tonumber(def.localId or def.index) == lid then tpl = def end
  end
  if not tpl then return nil end
  local eo = spawnFromTemplate(tpl, Objects._mapId)
  eo.hidden, eo.visible = false, true
  if eo.def then eo.def.hidden = false end
  local present = Objects._byId[lid] ~= nil
  if not present then
    for _, id in ipairs(Objects._order) do
      if id == lid then present = true break end
    end
  end
  Objects._byId[lid] = eo
  Objects._tracks[lid] = nil
  if not present then Objects._order[#Objects._order + 1] = lid end
  if ModRuntime.wants("world.npc_spawned") then
    ModRuntime.emit("world.npc_spawned", { mapId = Objects._mapId, npcId = lid, runtime = eo })
  end
  return eo
end

--- Spawn EventObjects from mapDef.objects (extract / content).
function Objects.loadMap(game, mapId, mapDef)
  local sameMap = Objects._mapId == mapId
  -- Never wipe in-flight applymovement on a same-map rebind (host setMap echo).
  if not sameMap then
    Objects._tracks = {}
    Objects._templateMt = {}
    -- pokefirered/src/overworld.c:405
    Objects._perm = {}
  end
  Objects._byId = {}
  Objects._order = {}
  Objects._mapId = mapId
  -- Prefer ROM event bundle (source of truth). mapDef.objects is the same
  -- table reference after attachEventsToMaps and may have been mutated.
  local defs = nil
  local Sp = Space()
  local ev = Sp and Sp.bundle and Sp.bundle.events and Sp.bundle.events[mapId]
  if ev then
    defs = ev.objects or ev.objectEvents
  end
  if type(defs) ~= "table" then
    defs = mapDef and mapDef.objects
  end
  Objects._defs = defs or {}
  Objects._bounds = layoutBounds(mapDef)
  if mapId == "FR_PLAYERS_HOUSE_1F" then
    for _, def in ipairs(Objects._defs) do
      if tonumber(def.localId or def.index) == 1 then
        def.x, def.y = 8, 4
      end
    end
  end
  resolveContextualMapObjects(mapId)
  local announce = ModRuntime.wants("world.npc_spawned")
  for _, def in ipairs(Objects._defs) do
    local eo = spawnFromTemplate(def, mapId)
    if eo.localId > 0 then
      Objects._byId[eo.localId] = eo
      Objects._order[#Objects._order + 1] = eo.localId
      if announce then
        ModRuntime.emit("world.npc_spawned", { mapId = mapId, npcId = eo.localId, runtime = eo })
      end
    end
  end
  if not Objects._logged then
    log(string.format("spawned %d objects on %s", #Objects._order, tostring(mapId)))
    Objects._logged = true
  else
    log(string.format("reloaded %d objects on %s%s", #Objects._order, tostring(mapId),
      sameMap and " (kept tracks)" or ""))
  end
  return #Objects._order
end

function Objects.find(localId)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    return Player()
  end
  return Objects._byId[localId]
end

-- src/event_object_movement.c:2089-2116
local function on_named_map(mapGroup, mapNum)
  if mapGroup == nil or mapNum == nil then return true end
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if not (ok and type(MapCatalog) == "table" and MapCatalog.mapIdFor) then return true end
  local engineId = MapCatalog.mapIdFor(tonumber(mapGroup), tonumber(mapNum))
  if engineId == nil then return false end
  return engineId == Objects._mapId
end

-- src/event_object_movement.c:2089-2101, scrcmd.c:1130
function Objects.setSubpriority(localId, mapGroup, mapNum, subpriority)
  local eo = Objects._byId[tonumber(localId) or -1]
  if not eo then return false end
  if not on_named_map(mapGroup, mapNum) then return false end
  eo.fixedPriority = true
  eo.subpriority = tonumber(subpriority) or 0
  eo.fixedClass = nil
  return true
end

-- src/event_object_movement.c:2104-2116
function Objects.resetSubpriority(localId, mapGroup, mapNum)
  local eo = Objects._byId[tonumber(localId) or -1]
  if not eo then return false end
  if not on_named_map(mapGroup, mapNum) then return false end
  eo.fixedPriority = nil
  eo.subpriority = nil
  eo.fixedClass = nil
  return true
end

function Objects.listActive(_mod, _game, _mapId)
  local ids = {}
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden then
      ids[#ids + 1] = lid
    end
  end
  return ids
end

local VIRT_DIR_FACE = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }

local drawList = {}
local vrecs = {}

function Objects.forDraw()
  local list = drawList
  local n = 0
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    -- src/event_object_movement.c:8014
    if eo and eo.visible and not eo.hidden and not eo.invisible
        and not offMap(Objects._bounds, eo) then
      n = n + 1
      list[n] = eo
    end
  end
  -- src/event_object_movement.c:1719
  for i = 1, VirtualObjects.slots() do
    local vo = VirtualObjects.nth(i)
    if vo then
      local vrec = vrecs[vo.id]
      if not vrec then
        vrec = { virtualId = vo.id, visible = true, hidden = false }
        vrecs[vo.id] = vrec
      end
      local gid = tonumber(vo.graphicsId) or 0
      vrec.cellX = tonumber(vo.x) or 0
      vrec.cellY = tonumber(vo.y) or 0
      vrec.elevation = tonumber(vo.elevation) or 3
      vrec.facing = VIRT_DIR_FACE[tonumber(vo.direction)] or "down"
      vrec.sprite = GfxIds.spriteFor(gid)
      vrec.graphicsId = gid
      vrec.raiseY = tonumber(vo.y2) or 0
      if not offMap(Objects._bounds, vrec) then
        n = n + 1
        list[n] = vrec
      end
    end
  end
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

--- First visible EventObject standing on (tx, ty), or nil if moving onto it.
function Objects.at(tx, ty)
  tx, ty = tonumber(tx), tonumber(ty)
  if not tx or not ty then return nil end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden then
      -- src/event_object_movement.c:1281
      local cx = eo.moving and eo.targetX or eo.cellX
      local cy = eo.moving and eo.targetY or eo.cellY
      if cx == tx and cy == ty then
        return eo
      end
    end
  end
  return nil
end

-- pokefirered/src/event_object_movement.c:8432 AreElevationsCompatible
function Objects.elevationsCompatible(a, b)
  a, b = tonumber(a) or 0, tonumber(b) or 0
  return a == 0 or b == 0 or a == b
end

--- True if any non-passable EO occupies (tx,ty) or is stepping onto it.
function Objects.blocks(tx, ty, exceptLocalId, elevation)
  exceptLocalId = tonumber(exceptLocalId)
  for _, lid in ipairs(Objects._order) do
    if lid ~= exceptLocalId then
      local eo = Objects._byId[lid]
      if eo and eo.visible and not eo.hidden and not eo.passable
          and Objects.elevationsCompatible(elevation, eo.currentElevation) then
        if eo.cellX == tx and eo.cellY == ty then return true end
        if eo.moving and eo.targetX == tx and eo.targetY == ty then
          return true
        end
      end
    end
  end
  -- pokefirered/src/union_room_player_avatar.c:475
  for i = 1, VirtualObjects.slots() do
    local vo = VirtualObjects.nth(i)
    if vo and vo.solid == true and tonumber(vo.x) == tx and tonumber(vo.y) == ty then return true end
  end
  return false
end

-- pokefirered/src/event_object_movement.c:4899
function Objects.playerBlocks(tx, ty, elevation)
  local P = Player()
  if not P then return false end
  if not Objects.elevationsCompatible(elevation, P.currentElevation) then return false end
  if P.cellX == tx and P.cellY == ty then return true end
  if P.moving and P.targetX == tx and P.targetY == ty then return true end
  return false
end

local function walkPhaseOf(eo)
  if not eo.moving then return 0 end
  -- pokefirered/src/event_object_movement.c:7040 MovementAction_DisableAnimation_Step0
  if eo.inanimate then return 0 end
  local frames = eo.stepFrames or WALK_FRAMES
  local p = eo.animClock % frames
  local mid = math.floor(frames / 2)
  return (p >= math.floor(frames / 4) and p < mid + math.floor(frames / 4)) and 1 or 0
end

function Objects.walkPhase(eo)
  return walkPhaseOf(eo)
end

-- pokefirered/src/event_object_movement.c:8400
function Objects.updateElevation(eo)
  local Coll = Collision()
  if not (eo and Coll and Coll.nextElevation) then return end
  local mapDef = eo.mapDef or Coll._mapDef
  local cx, cy = eo.cellX, eo.cellY
  if eo.moving then cx, cy = eo.targetX, eo.targetY end
  eo.currentElevation = Coll.nextElevation(mapDef, eo.currentElevation or 0,
    cx, cy, eo.cellX, eo.cellY)
end

local function beginStep(eo, tx, ty)
  eo.moving = true
  eo.progress = 0
  eo.targetX = tx
  eo.targetY = ty
  Objects.updateElevation(eo)
  eo.stepFrames = WALK_FRAMES
  eo.animClock = 0
end

local function finishStep(eo, game, ctx)
  eo.cellX = eo.targetX
  eo.cellY = eo.targetY
  eo.px = eo.cellX * CELL
  eo.py = eo.cellY * CELL
  eo.moving = false
  eo.progress = 0
  eo.stepFlip = not eo.stepFlip
  if eo.def then
    eo.def.x, eo.def.y = eo.cellX, eo.cellY
  end
  if ctx then return end
  local Coll = Collision()
  local curElev = Coll and Coll.elevationAt and Coll.elevationAt(eo.cellX, eo.cellY)
  if curElev and curElev ~= 0 and curElev ~= 15 then
    eo.elevation = curElev
  end
  -- src/trainer_see.c:94
  if eo.sight and eo.sight > 0 and not eo.scriptBusy and not eo.frozen then
    local okTs, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
    if okTs and TrainerSight and TrainerSight.check then
      TrainerSight.check(game, eo)
    end
  end
end

-- src/event_object_movement.c:8866
local STEP_PIXELS = {
  [16] = { 1 },
  [8] = { 2 },
  [6] = { 2, 3, 3 },
  [4] = { 4 },
  [2] = { 8 },
  -- src/event_object_movement.c:9029
  [11] = { 1, 2 },
  -- src/event_object_movement.c:8984
  [24] = { 1, 1, 0 },
  -- src/event_object_movement.c:8959
  [32] = { 1, 0 },
}
local STEP_OFFSETS = {}
for frames, pat in pairs(STEP_PIXELS) do
  local cum, n = {}, 0
  for k = 1, frames do
    n = math.min(CELL, n + pat[(k - 1) % #pat + 1])
    cum[k] = n
  end
  STEP_OFFSETS[frames] = cum
end

local function stepOffset(frames, progress, cells)
  local cum = cells == 1 and STEP_OFFSETS[frames]
  if cum then return cum[math.min(progress, frames)] end
  return math.floor(cells * CELL * math.min(progress, frames) / frames)
end

local function tickMotion(eo, game, ctx)
  Objects.updateElevation(eo)
  if not eo.moving then return false end
  eo.progress = eo.progress + 1
  eo.animClock = eo.animClock + 1
  local frames = eo.stepFrames or WALK_FRAMES
  local dx = eo.targetX - eo.cellX
  local dy = eo.targetY - eo.cellY
  local off = stepOffset(frames, eo.progress, math.abs(dx) + math.abs(dy))
  eo.px = eo.cellX * CELL + (dx > 0 and off or dx < 0 and -off or 0)
  eo.py = eo.cellY * CELL + (dy > 0 and off or dy < 0 and -off or 0)
  if eo.progress >= frames then
    finishStep(eo, game, ctx)
    return true
  end
  return false
end

--- Scripted one-cell step (no collision — FRLG applymovement forces).
function Objects.scriptStep(eo, dir, run, slow)
  if not eo then return false end
  local P = Player()
  if eo == P then
    return P.scriptStep and P.scriptStep(dir, run, slow)
  end
  if eo.moving then return false end
  local d = DELTA[dir]
  if not d then return false end
  -- pokefirered/src/event_object_movement.c:6796 MovementAction_LockFacingDirection_Step0
  if not eo.facingLocked then eo.facing = dir end
  beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
  -- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
  if run then eo.stepFrames = slow and RUN_SLOW_FRAMES or RUN_FRAMES end
  eo.frozen = true
  eo.scriptBusy = true
  return true
end

function Objects.scriptJump(eo, dir, distance)
  if not eo then return false end
  local P = Player()
  if eo == P then
    return P.scriptJump and P.scriptJump(dir, distance)
  end
  if eo.moving then return false end
  distance = distance or 1
  local d = DELTA[dir]
  if not d then return false end
  eo.facing = dir
  beginStep(eo, eo.cellX + d[1] * distance, eo.cellY + d[2] * distance)
  eo.frozen = true
  eo.scriptBusy = true
  return true
end

-- pokefirered/src/event_object_movement.c:5351 InitNpcForWalkSlower
function Objects.pushStep(eo, dir, frames)
  local d = DELTA[dir]
  if not eo or not d or eo.moving then return false end
  eo.facing = dir
  beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
  eo.stepFrames = frames or WALK_FRAMES * 2
  return true
end

function Objects.scriptFace(eo, dir)
  if not eo then return end
  local P = Player()
  if eo == P then
    if P.scriptFace then P.scriptFace(dir) else P.facing = dir end
    return
  end
  -- pokefirered/src/event_object_movement.c:2501 SetObjectEventDirection
  if eo.facingLocked then return end
  eo.facing = dir
end

-- pokefirered/src/event_object_movement.c:5208 GetOppositeDirection
local OPPOSITE_DIR = { down = "up", up = "down", left = "right", right = "left" }

-- pokefirered/src/event_object_movement.c:4789 GetDirectionToFace
local function directionToFace(x1, y1, x2, y2)
  if x1 > x2 then return "left" end
  if x1 < x2 then return "right" end
  if y1 > y2 then return "up" end
  return "down"
end

local function advanceTrack(lid, tr, game)
  if tr.done then return end
  local eo = Objects.find(lid)
  if tr.sleep and tr.sleep > 0 then
    tr.sleep = tr.sleep - 1
    if tr.sleep > 0 then return end
  end
  -- Wait until current step finishes.
  if eo and eo.moving then return end
  if eo == Player() and Player().moving then return end

  local act = tr.actions[tr.i]
  if not act then
    tr.done = true
    if eo and eo ~= Player() then
      eo.scriptBusy = false
    end
    if tr.onDone then
      local cb = tr.onDone
      tr.onDone = nil
      cb()
    end
    return
  end
  tr.i = tr.i + 1
  if type(act) == "string" then
    local sdir = act:match("^walk_(.*)$") or act:match("^step_(.*)$")
    if sdir then
      act = { kind = "step", dir = sdir }
    else
      local tdir = act:match("^turn_(.*)$") or act:match("^face_(.*)$")
      if tdir then
        act = { kind = "turn", dir = tdir }
      end
    end
  end
  if type(act) == "table" then
    if act.kind == "step" then
      if eo == Player() then
        if Player().scriptStep then Player().scriptStep(act.dir, act.run, act.slow) end
      elseif eo then
        Objects.scriptStep(eo, act.dir, act.run, act.slow)
      end
    elseif act.kind == "jump" then
      if eo == Player() then
        if Player().scriptJump then
          Player().scriptJump(act.dir, act.distance or 1)
        elseif Player().scriptStep then
          for _ = 1, (act.distance or 1) do
            Player().scriptStep(act.dir)
          end
        end
      elseif eo then
        if Objects.scriptJump then
          Objects.scriptJump(eo, act.dir, act.distance or 1)
        else
          Objects.scriptStep(eo, act.dir)
        end
      end
    elseif act.kind == "turn" then
      Objects.scriptFace(eo, act.dir)
    elseif act.kind == "face_player" then
      -- pokefirered/src/event_object_movement.c:6772 MovementAction_FacePlayer_Step0
      if eo and eo ~= Player() then
        local dir = directionToFace(eo.cellX, eo.cellY, Player().cellX, Player().cellY)
        if act.away then dir = OPPOSITE_DIR[dir] end
        Objects.scriptFace(eo, dir)
      end
    elseif act.kind == "lock_facing" then
      -- pokefirered/src/event_object_movement.c:6796 MovementAction_LockFacingDirection_Step0
      if eo and eo ~= Player() then eo.facingLocked = act.locked and true or false end
    elseif act.kind == "animate" then
      -- pokefirered/src/event_object_movement.c:7040 MovementAction_DisableAnimation_Step0
      if eo and eo ~= Player() then eo.inanimate = act.inanimate and true or false end
    elseif act.kind == "remove_obstacle" then
      -- pokefirered/src/event_object_movement.c:7135 MovementAction_RockSmashBreak_Step0
      tr.sleep = act.frames or 32
    elseif act.kind == "face_original" then
      if eo and eo ~= Player() and eo.def then
        -- src/event_object_movement.c:7016
        local origFace = eo.def.movementType ~= nil and GfxIds.initialFacing(eo.movementType)
          or facingFromDef(eo.def)
        Objects.scriptFace(eo, origFace)
      end
    elseif act.kind == "bow" then
      if eo and eo ~= Player() then
        eo.bowFrames = act.frames or 48
        eo.facing = "down"
      end
      tr.sleep = act.frames or 48
    elseif act.kind == "emote" then
      if eo then
        local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
        if okFx and FieldEffects then
          if FieldEffects.startEmote then
            FieldEffects.startEmote(eo, act.emoteType or "exclamation")
          elseif FieldEffects.startExclamation then
            FieldEffects.startExclamation(eo)
          end
        end
      end
      tr.sleep = act.frames or 60
    elseif act.kind == "sleep" then
      tr.sleep = act.frames or 1
    elseif act.kind == "hide" then
      -- pokefirered/src/event_object_movement.c:7054
      if eo == Player() then
        Player().setVisible(false)
      elseif eo then
        eo.hidden = true
        eo.visible = false
      end
    elseif act.kind == "show" then
      -- pokefirered/src/event_object_movement.c:7061
      if eo == Player() then
        Player().setVisible(true)
      elseif eo then
        eo.hidden = false
        eo.visible = true
      end
    end
  end
end

function Objects.applyMovement(localId, stream, onDone)
  local lid = tonumber(localId) or localId
  local actions = Movement.actionsFromBytes(stream)
  local eo = Objects.find(lid)
  if eo and eo ~= Player() then
    eo.frozen = true
    eo.scriptBusy = true
  end
  Objects._tracks[lid] = {
    actions = actions,
    i = 1,
    sleep = 0,
    done = false,
    onDone = onDone,
  }
  advanceTrack(lid, Objects._tracks[lid], nil)
end

function Objects.startTrack(localId, actions, onDone)
  local lid = tonumber(localId) or localId
  local eo = Objects.find(lid)
  if eo and eo ~= Player() then
    eo.frozen = true
    eo.scriptBusy = true
  end
  if not actions or #actions == 0 then
    if eo and eo ~= Player() then
      eo.scriptBusy = false
    end
    if onDone then onDone() end
    return
  end
  Objects._tracks[lid] = {
    actions = actions,
    i = 1,
    sleep = 0,
    done = false,
    onDone = onDone,
  }
  advanceTrack(lid, Objects._tracks[lid], nil)
end

function Objects.pollMovement(localId)
  -- Tracks advance in Objects.update. Missing track ≠ done: returning true
  -- here after loadMap wiped tracks was skipping Bill's walk_up / MeetCelio.
  local lid = tonumber(localId) or localId
  if lid == 0 then
    local any = false
    for _, tr in pairs(Objects._tracks) do
      any = true
      if not tr.done then return false end
    end
    return any
  end
  local tr = Objects._tracks[lid]
  if not tr then return false end
  return tr.done == true
end

function Objects.clearMovements()
  Objects._tracks = {}
end

local function sine(i)
  local v = 256 * math.sin((i % 256) * math.pi / 128)
  return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
end

-- src/event_object_movement.c:7812
local function raiseHandTick(eo)
  local rh = eo.raiseHandState
  if not rh then
    rh = { mode = 0, angle = 0, hops = 0, timer = 0, swing = 0 }
    eo.raiseHandState = rh
    eo.raiseHand = true
  end
  local mt = tonumber(eo.movementType) or 0
  if mt == 0x4F then
    rh.swing = (rh.swing + 4) % 256
    eo.raiseX = math.floor(sine(rh.swing) / 128)
    return
  end
  if mt ~= 0x4E then return end
  if rh.mode == 0 then
    rh.angle = rh.angle + 10
    if rh.angle > 127 then
      rh.angle = 0
      rh.hops = rh.hops + 1
      rh.mode = rh.hops
      eo.raiseHand = false
    end
    eo.raiseY = -math.floor(3 * sine(rh.angle) / 128)
  elseif rh.mode == 1 then
    rh.timer = rh.timer + 1
    if rh.timer > 16 then
      rh.timer = 0
      eo.raiseHand = true
      rh.mode = 0
    end
  else
    rh.timer = rh.timer + 1
    if rh.timer > 80 then
      eo.raiseHandState = nil
    end
  end
end

local function checkSight(game, eo)
  local okTs, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
  if okTs and TrainerSight and TrainerSight.check then
    TrainerSight.check(game, eo)
  end
end

-- src/event_object_movement.c:4830
local function stepCollision(eo, game, ctx, dir)
  local d = DELTA[dir]
  local tx, ty = eo.cellX + d[1], eo.cellY + d[2]
  -- src/event_object_movement.c:4861
  local rx = tonumber(eo.rangeX or (eo.radius and eo.radius.x)) or 0
  local ry = tonumber(eo.rangeY or (eo.radius and eo.radius.y)) or 0
  if (rx ~= 0 and math.abs(tx - eo.homeX) > rx) or (ry ~= 0 and math.abs(ty - eo.homeY) > ry) then
    return "range"
  end
  local ok
  if ctx then
    local Coll = Collision()
    ok = ctx.canEnter(tx, ty, eo.cellX, eo.cellY, dir)
      and not ctx.blocks(tx, ty, eo.localId)
    if ok and eo.mapDef and Coll.directionallyImpassableOn(
        eo.mapDef, eo.cellX, eo.cellY, tx, ty, dir) then
      ok = false
    end
    -- pokefirered/src/event_object_movement.c:4839
    if ok and eo.mapDef and Coll.elevationMismatchOn(eo.mapDef, eo.currentElevation, tx, ty) then
      ok = false
    end
  else
    local Coll = Collision()
    -- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
    local onWater = Coll.isWater(eo.cellX, eo.cellY)
    ok = Coll.canEnter(game, tx, ty,
      { fromX = eo.cellX, fromY = eo.cellY, dir = dir, surfing = onWater,
        elevation = eo.currentElevation })
    if ok and Coll.isWater(tx, ty) ~= onWater then ok = false end
    -- pokefirered/src/event_object_movement.c:4841 DoesObjectCollideWithObjectAt
    if Objects.playerBlocks(tx, ty, eo.currentElevation) then ok = false end
    if Objects.blocks(tx, ty, eo.localId, eo.currentElevation) then ok = false end
  end
  if not ok then return "blocked" end
  return nil
end

-- src/event_object_movement.c:3884
local function walkOrInPlace(eo, dir, collision)
  eo.facing = dir
  if collision then
    beginStep(eo, eo.cellX, eo.cellY)
  else
    local d = DELTA[dir]
    beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
  end
end

-- src/event_object_movement.c:2770
local function playerCellFor(ctx)
  local P = Player()
  local px = P.moving and P.targetX or P.cellX
  local py = P.moving and P.targetY or P.cellY
  return px - (ctx and ctx.ox or 0), py - (ctx and ctx.oy or 0)
end

local function trainerCloseToRunningPlayer(eo, ctx)
  local P = Player()
  if not (P and P.running) or P.biking or P.surfing then return false end
  local tt = tonumber(eo.trainerType) or 0
  if tt ~= 1 and tt ~= 3 then return false end
  local r = tonumber(eo.sight) or 0
  local px, py = playerCellFor(ctx)
  return math.abs(px - eo.cellX) <= r and math.abs(py - eo.cellY) <= r
end

-- src/event_object_movement.c:2801
local function vectorDirection(dx, dy)
  if math.abs(dx) > math.abs(dy) then return dx < 0 and "left" or "right" end
  return dy < 0 and "up" or "down"
end

local function southNorth(dy) return dy < 0 and "up" or "down" end
local function westEast(dx) return dx < 0 and "left" or "right" end

-- src/data/object_events/movement_type_func_tables.h:185
local FOLLOW = {
  [0] = vectorDirection,
  [1] = function(_, dy) return southNorth(dy) end,
  [2] = function(dx) return westEast(dx) end,
  [3] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "down" then d = westEast(dx); if d == "right" then d = "up" end
    elseif d == "right" then d = southNorth(dy); if d == "down" then d = "up" end end
    return d
  end,
  [4] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "down" then d = westEast(dx); if d == "left" then d = "up" end
    elseif d == "left" then d = southNorth(dy); if d == "down" then d = "up" end end
    return d
  end,
  [5] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "up" then d = westEast(dx); if d == "right" then d = "down" end
    elseif d == "right" then d = southNorth(dy); if d == "up" then d = "down" end end
    return d
  end,
  [6] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "up" then d = westEast(dx); if d == "left" then d = "down" end
    elseif d == "left" then d = southNorth(dy); if d == "up" then d = "down" end end
    return d
  end,
  [7] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "right" then d = southNorth(dy) end
    return d
  end,
  [8] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "left" then d = southNorth(dy) end
    return d
  end,
  [9] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "down" then d = westEast(dx) end
    return d
  end,
  [10] = function(dx, dy)
    local d = vectorDirection(dx, dy)
    if d == "up" then d = westEast(dx) end
    return d
  end,
}

-- src/event_object_movement.c:2992
local function followDirection(eo, follow, ctx)
  local px, py = playerCellFor(ctx)
  local fn = FOLLOW[follow] or FOLLOW[0]
  return fn(px - eo.cellX, py - eo.cellY)
end

local function idleTick(eo, game, ctx)
  if eo.frozen or eo.scriptBusy or eo.moving or eo.hidden or not eo.visible then
    return
  end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return end
  local Hud = package.loaded["src.ui.game3.hud"]
  if Hud and Hud.isMenuOpen and Hud.isMenuOpen() then return end
  if eo.movement == "RAISE_HAND" then
    raiseHandTick(eo)
    return
  end

  local mv = tostring(eo.movement or "STAY"):upper()
  if mv == "STAY" then return end
  local spec = eo.spec
  if not spec or spec.movement ~= mv then
    spec = { movement = mv, dirs = dirsForRange(eo.range), delays = "MEDIUM", follow = 0 }
  end

  if mv == "BACK_FORTH" then
    -- src/event_object_movement.c:3849
    local dir = (eo.seqIndex or 0) ~= 0 and OPPOSITE_DIR[spec.face] or spec.face
    if (eo.seqIndex or 0) ~= 0 and eo.cellX == eo.homeX and eo.cellY == eo.homeY then
      eo.seqIndex = 0
      dir = OPPOSITE_DIR[dir]
    end
    local c = stepCollision(eo, game, ctx, dir)
    if c == "range" then
      eo.seqIndex = (eo.seqIndex or 0) + 1
      dir = OPPOSITE_DIR[dir]
      c = stepCollision(eo, game, ctx, dir)
    end
    walkOrInPlace(eo, dir, c)
    return
  end

  if mv == "SEQUENCE" then
    -- src/event_object_movement.c:3949
    local idx = eo.seqIndex or 0
    if idx == spec.skipFrom and ((spec.skipAxis == "x" and eo.cellX == eo.homeX)
        or (spec.skipAxis == "y" and eo.cellY == eo.homeY)) then
      idx = spec.skipFrom + 1
    end
    -- src/event_object_movement.c:3914
    if idx == 3 and eo.cellX == eo.homeX and eo.cellY == eo.homeY then idx = 0 end
    local dir = spec.route[idx + 1]
    local c = stepCollision(eo, game, ctx, dir)
    if c == "range" then
      idx = (idx + 1) % 4
      dir = spec.route[idx + 1]
      c = stepCollision(eo, game, ctx, dir)
    end
    eo.seqIndex = idx
    walkOrInPlace(eo, dir, c)
    return
  end

  local Rng = require("src.core.game3.rng")
  local function pick(t) return t[(Rng.Random() % #t) + 1] end

  if mv == "LOOK" or mv == "LOOK_AROUND" or mv == "ROTATE" then
    -- src/event_object_movement.c:3044
    local close = trainerCloseToRunningPlayer(eo, ctx)
    if eo.idleTimer == nil then
      eo.idleTimer = mv == "ROTATE" and 48 or pick(GfxIds.DELAYS[spec.delays or "MEDIUM"])
    end
    eo.idleTimer = eo.idleTimer - 1
    if eo.idleTimer > 0 and not close then return end
    local oldFacing = eo.facing
    -- src/event_object_movement.c:2992
    local dir = close and followDirection(eo, spec.follow or 0, ctx)
    if not dir then
      dir = mv == "ROTATE" and spec.next[eo.facing] or pick(spec.dirs)
    end
    eo.facing = dir
    eo.idleTimer = mv == "ROTATE" and 48 or pick(GfxIds.DELAYS[spec.delays or "MEDIUM"])
    if not ctx and eo.facing ~= oldFacing and eo.sight and eo.sight > 0 then
      checkSight(game, eo)
    end
    return
  end

  if mv == "WALK" then
    -- src/event_object_movement.c:2716
    if eo.idleTimer == nil then eo.idleTimer = pick(GfxIds.DELAYS.MEDIUM) end
    eo.idleTimer = eo.idleTimer - 1
    if eo.idleTimer > 0 then return end
    -- src/event_object_movement.c:2731
    local dir = pick(spec.dirs or dirsForRange(eo.range))
    eo.facing = dir
    eo.idleTimer = pick(GfxIds.DELAYS.MEDIUM)
    if stepCollision(eo, game, ctx, dir) then
      if not ctx and eo.sight and eo.sight > 0 then checkSight(game, eo) end
      return
    end
    local d = DELTA[dir]
    beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
    -- src/event_object_movement.c:8959
    if spec.slow then eo.stepFrames = WALK_FRAMES * 2 end
  end
end

function Objects.update(game)
  -- Advance script tracks then motion + idle.
  for lid, tr in pairs(Objects._tracks) do
    advanceTrack(lid, tr, game)
  end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo then
      if eo.bowFrames and eo.bowFrames > 0 then
        eo.bowFrames = eo.bowFrames - 1
        if eo.bowFrames <= 0 then eo.bowFrames = nil end
      end
      tickMotion(eo, game)
      idleTick(eo, game)
    end
  end
end

function Objects.spawnFromDefs(defs, mapDef, mapId)
  local pool = { byId = {}, order = {}, bounds = layoutBounds(mapDef), mapDef = mapDef }
  local Sp = mapId and Space()
  local nb = Sp and Sp.neighborObjectState and Sp.neighborObjectState(mapId)
  if mapId and not nb and not (Sp and Sp.mapId == mapId) then nb = { store = { flags = {}, vars = {} }, perm = {}, movementType = {} } end
  for _, def in ipairs(defs or {}) do
    local eo = newEventObject(def, nb)
    if eo.localId > 0 then
      eo.mapDef = mapDef
      if nb then
        local p = nb.perm[eo.localId]
        if p then
          eo.cellX, eo.cellY, eo.homeX, eo.homeY = p.x, p.y, p.x, p.y
          eo.targetX, eo.targetY = p.x, p.y
          eo.px, eo.py = p.x * CELL, p.y * CELL
          eo.def.x, eo.def.y = p.x, p.y
        end
        local mt = nb.movementType[eo.localId]
        if mt then
          Objects.setTrainerMovementType(eo, mt)
          -- pokefirered/src/event_object_movement.c:359
          eo.facing = GfxIds.initialFacing(mt)
        end
        if (tonumber(eo.graphicsId) or 0) >= 240 then eo.invisible = true end
      end
      pool.byId[eo.localId] = eo
      pool.order[#pool.order + 1] = eo.localId
    end
  end
  return pool
end

function Objects.tickPool(pool, game, ctx)
  if type(pool) ~= "table" then return end
  for _, lid in ipairs(pool.order or {}) do
    local eo = pool.byId[lid]
    if eo then
      if eo.bowFrames and eo.bowFrames > 0 then
        eo.bowFrames = eo.bowFrames - 1
        if eo.bowFrames <= 0 then eo.bowFrames = nil end
      end
      tickMotion(eo, game, ctx or pool)
      idleTick(eo, game, ctx)
    end
  end
end

function Objects.poolForDraw(pool)
  local list = {}
  if type(pool) ~= "table" then return list end
  for _, lid in ipairs(pool.order or {}) do
    local eo = pool.byId[lid]
    if eo and eo.visible and not eo.hidden and not eo.invisible
        and not offMap(pool.bounds, eo) then
      list[#list + 1] = eo
    end
  end
  return list
end

function Objects.snapshotPool()
  return {
    byId = Objects._byId, order = Objects._order,
    mapId = Objects._mapId, bounds = Objects._bounds,
  }
end

function Objects.adoptPool(pool)
  if type(pool) ~= "table" then return false end
  for _, lid in ipairs(pool.order or {}) do
    local live = Objects._byId[lid]
    local ghost = pool.byId[lid]
    local mv = live and ghost and live.movement == ghost.movement
      and tostring(live.movement or "STAY"):upper()
    if mv == "WALK" or mv == "BACK_FORTH" or mv == "SEQUENCE" then
      live.cellX, live.cellY = ghost.cellX, ghost.cellY
      live.px, live.py = ghost.px, ghost.py
      live.targetX, live.targetY = ghost.targetX, ghost.targetY
      live.moving, live.progress = ghost.moving, ghost.progress
      live.stepFrames, live.animClock = ghost.stepFrames, ghost.animClock
      live.facing = ghost.facing
      live.stepFlip = ghost.stepFlip
      live.idleTimer = ghost.idleTimer
      live.seqIndex = ghost.seqIndex
      if live.def then live.def.x, live.def.y = live.cellX, live.cellY end
    elseif mv == "LOOK" or mv == "ROTATE" then
      live.facing = ghost.facing
      live.idleTimer = ghost.idleTimer
    end
  end
  return true
end

function Objects.addObject(localId)
  localId = tonumber(localId) or 0
  local eo = Objects._byId[localId]
  if eo and not eo.hidden then return true end
  return respawnFromTemplate(localId) ~= nil
end

--- Re-evaluate hide flags after sidecar load / setflag mid-map.
function Objects.refreshVisibility()
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.def then
      local vis = objectVisible(eo.def)
      eo.visible = vis
      eo.hidden = not vis
    end
  end
end

-- src/event_object_movement.c:1841
local function inCameraView(eo)
  local P = Player()
  if not P then return false end
  local px, py = tonumber(P.cellX), tonumber(P.cellY)
  if not px or not py then return false end
  local function inside(x, y)
    x, y = tonumber(x), tonumber(y)
    return x ~= nil and y ~= nil
      and x >= px - 9 and x <= px + 10 and y >= py - 7 and y <= py + 9
  end
  return inside(eo.cellX, eo.cellY) or inside(eo.homeX, eo.homeY)
end

Objects.inCameraView = inCameraView

--- pret FlagClear/FlagSet on an object template hide flag.
-- src/scrcmd.c:558
function Objects.syncFlagVisibility(flagId, hidden, force)
  flagId = tonumber(flagId) or 0
  if flagId == 0 or flagId == 0xFFFF or flagId == 65535 then return end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo then
      local f = tonumber(eo.flag) or (eo.def and tonumber(eo.def.flag or eo.def.flagId)) or 0
      if f == flagId then
        if hidden then
          if force or not inCameraView(eo) then
            eo.hidden = true
            eo.visible = false
            if eo.def then eo.def.hidden = true end
          end
        elseif eo.hidden then
          -- src/event_object_movement.c:1792
          respawnFromTemplate(lid)
        end
      end
    end
  end
  -- Template exists in defs but was never spawned (or despawned from order).
  if not hidden then
    for _, def in ipairs(Objects._defs or {}) do
      local f = tonumber(def.flag or def.flagId) or 0
      local lid = tonumber(def.localId or def.index) or 0
      if f == flagId and lid > 0 and not Objects._byId[lid] then
        Objects.addObject(lid)
      end
    end
  end
end

function Objects.removeObject(localId)
  localId = tonumber(localId) or 0
  local eo = Objects._byId[localId]
  if not eo then return false end
  local flag = eo.def and (eo.def.flag or eo.def.flagId)
  if flag and flag ~= 0 and flag ~= 0xFFFF and flag ~= 65535 then
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.store then
      local Flags = require("src.core.game3.scripting.flags")
      Flags.setFlag(Space.store, nil, flag, true)
    end
  end
  eo.hidden = true
  eo.visible = false
  if eo.def then eo.def.hidden = true end
  Objects._tracks[localId] = nil
  return true
end

-- src/event_object_movement.c:2059
local function setObjectInvisibility(localId, state)
  local lid = tonumber(localId) or 0
  if lid >= Objects.PLAYER_LOCAL_ID then
    Player().setVisible(not state)
    return true
  end
  local eo = Objects._byId[lid]
  if not eo then return false end
  eo.invisible = state
  return true
end

function Objects.hideObject(localId)
  return setObjectInvisibility(localId, true)
end

function Objects.showObject(localId)
  return setObjectInvisibility(localId, false)
end

function Objects.turnObject(localId, dir)
  local dirs = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }
  local facing = dirs[tonumber(dir) or 0]
    or ({ down = "down", up = "up", left = "left", right = "right" })[tostring(dir or ""):lower()]
  local eo = Objects.find(localId)
  if eo and facing then
    Objects.scriptFace(eo, facing)
  end
end

function Objects.setObjectXY(localId, x, y)
  local lid = tonumber(localId) or 0
  local eo = Objects._byId[lid]
  x, y = tonumber(x) or 0, tonumber(y) or 0
  -- Key perm by script map (Space.mapId) when active — not the previous map's
  -- Objects._mapId if enter order ever regresses.
  local Sp = Space()
  local mapKey = (Sp and Sp.mapId) or Objects._mapId
  rememberPerm(mapKey, lid, { x = x, y = y })
  if not eo then return end
  eo.cellX, eo.cellY = x, y
  eo.homeX, eo.homeY = x, y
  eo.px, eo.py = eo.cellX * CELL, eo.cellY * CELL
  eo.targetX, eo.targetY = eo.cellX, eo.cellY
  eo.moving = false
  if eo.def then eo.def.x, eo.def.y = eo.cellX, eo.cellY end
end

function Objects.copyObjectXYToPerm(localId)
  local lid = tonumber(localId) or 0
  local eo = Objects._byId[lid]
  if not eo then return end
  local Sp = Space()
  local mapKey = (Sp and Sp.mapId) or Objects._mapId
  rememberPerm(mapKey, lid, { x = eo.cellX, y = eo.cellY })
  eo.homeX, eo.homeY = eo.cellX, eo.cellY
  if eo.def then eo.def.x, eo.def.y = eo.cellX, eo.cellY end
end

function Objects.setMovementType(localId, mt)
  local lid = tonumber(localId) or 0
  local eo = Objects._byId[lid]
  mt = tonumber(mt) or 0
  local Sp = Space()
  local mapKey = (Sp and Sp.mapId) or Objects._mapId
  rememberPerm(mapKey, lid, { movementType = mt })
  if not eo then return end
  Objects.setTrainerMovementType(eo, mt)
  local face = ({ [7] = "up", [8] = "down", [9] = "left", [10] = "right" })[mt]
  if face then eo.facing = face end
end

local function clearRaiseHand(eo)
  eo.raiseHandState = nil
  eo.raiseHand = nil
  eo.raiseX = nil
  eo.raiseY = nil
end

-- src/event_object_movement.c:4806
function Objects.setTrainerMovementType(localId, mt)
  local eo = type(localId) == "table" and localId or Objects._byId[tonumber(localId) or 0]
  if not eo then return end
  mt = tonumber(mt) or 0
  setSpec(eo, mt)
  clearRaiseHand(eo)
  -- src/event_object_movement.c:4543
  if mt == MOVEMENT_TYPE_INVISIBLE then eo.invisible = true end
  if eo.movement == "RAISE_HAND" then
    eo.facing = "down"
  end
end

-- src/event_object_movement.c:2640
function Objects.overrideTemplateMovementType(localId, mt)
  local lid = tonumber(localId) or 0
  if lid <= 0 then return end
  Objects._templateMt[lid] = tonumber(mt)
end

function Objects.templateMovementType(localId)
  local lid = tonumber(localId) or 0
  local o = Objects._templateMt[lid]
  if o then return o end
  for _, def in ipairs(Objects._defs or {}) do
    if tonumber(def.localId or def.index) == lid then
      return tonumber(def.movementType) or 0
    end
  end
  return nil
end

function Objects.facePlayer(localId, game)
  local eo = Objects._byId[tonumber(localId) or 0]
  local P = Player()
  if not eo or not P then return end
  local dx = P.cellX - eo.cellX
  local dy = P.cellY - eo.cellY
  if math.abs(dx) > math.abs(dy) then
    eo.facing = dx > 0 and "right" or "left"
  else
    eo.facing = dy > 0 and "down" or "up"
  end
end

function Objects.freeze(localId)
  local eo = Objects._byId[tonumber(localId) or 0]
  if eo then eo.frozen = true end
end

function Objects.unfreeze(localId)
  local eo = Objects._byId[tonumber(localId) or 0]
  if eo and not eo.scriptBusy then eo.frozen = false end
end

--- No-op. EventObjects are owned by game3; Field.interact + adapters read them
-- directly via Objects.find / forDraw. Kept for call-site compatibility.
function Objects.syncToHost(_game)
end

-- Back-compat thin wrappers used by older Objects.addObject(adapters, id) calls.
function Objects.addObjectVia(adapters, localId)
  if Objects.addObject(localId) then return true end
  if adapters and adapters.addObject then return adapters.addObject(localId) end
  return false
end

function Objects.removeObjectVia(adapters, localId)
  Objects.removeObject(localId)
  if adapters and adapters.removeObject then return adapters.removeObject(localId) end
  return true
end

return Objects

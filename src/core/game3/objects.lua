-- Game3 EventObject instances (localId-keyed).
-- Owns idle AI + applymovement tracks; optional host NPC mirror for adapters.
-- Player localId 0xFF delegates to game3.player. Talk is Field.interact.

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Movement = require("src.core.game3.scripting.movement")
local Opcodes = require("src.core.game3.scripting.opcodes")
local GfxIds = require("src.core.game3.scripting.gfx_ids")
local ModRuntime = require("src.mods.Runtime")
local VirtualObjects = require("src.core.game3.virtual_objects")
local Prepare = require("src.core.game3.object_prepare")

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
    or lazyReq("src.core.game3.collision")
end

local function Player()
  return package.loaded["src.core.game3.player"]
    or lazyReq("src.core.game3.player")
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

local EMPTY = {}

local function fieldBlock()
  local Profile = package.loaded["src.core.game3.profile"] or lazyReq("src.core.game3.profile")
  local ok, row = pcall(Profile.forSession)
  return ok and row and row.field or EMPTY
end

local function isRse()
  local Profile = package.loaded["src.core.game3.profile"] or lazyReq("src.core.game3.profile")
  local ok, row = pcall(Profile.forSession)
  return ok and row ~= nil and row.family == "rse"
end
Objects.isRse = isRse

local function canonMt(mt)
  mt = tonumber(mt)
  if mt == nil then return nil end
  local MovementTypes = lazyReq("src.core.game3.movement_types")
  local ok, v = pcall(MovementTypes.canon, lazyReq("src.core.GameVersion").get(), mt)
  return ok and v or mt
end

Objects.canonMovementType = canonMt

local inPlace
local function inPlaceTable()
  if inPlace then return inPlace end
  local MovementTypes = lazyReq("src.core.game3.movement_types")
  inPlace = {}
  local dirs = { DOWN = "down", UP = "up", LEFT = "left", RIGHT = "right" }
  -- pokeemerald/src/event_object_movement.c:4422
  local kinds = {
    { "firered", "MOVEMENT_TYPE_WALK_IN_PLACE_", 16, false },
    { "firered", "MOVEMENT_TYPE_WALK_IN_PLACE_FAST_", 8, false },
    { "firered", "MOVEMENT_TYPE_JOG_IN_PLACE_", 4, false },
    { "emerald", "MOVEMENT_TYPE_WALK_SLOWLY_IN_PLACE_", 32, true },
  }
  for _, k in ipairs(kinds) do
    for suffix, dir in pairs(dirs) do
      local id = MovementTypes.canonOf(k[1], k[2] .. suffix)
      if id then inPlace[id] = { dir = dir, frames = k[3], always = k[4] } end
    end
  end
  return inPlace
end

local function hostSpec(mt, rangeX, rangeY)
  local spec = GfxIds.hostMovement(mt, rangeX, rangeY)
  local ip = inPlaceTable()[tonumber(mt) or -1]
  if ip and (ip.always or fieldBlock().inPlaceMovementTypes) then
    spec.movement = "IN_PLACE"
    spec.face = ip.dir
    spec.range = ip.dir:upper()
    spec.frames = ip.frames
  end
  return spec
end

Objects.hostSpec = hostSpec

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

-- include/constants/event_objects.h:195
local OBJ_KIND_CLONE = 255

-- pokefirered/src/overworld.c:410
local function cloneTemplate(def)
  local t = def.cloneTarget
  if tonumber(def.kind) ~= OBJ_KIND_CLONE or type(t) ~= "table" then return nil end
  local mapId = t.mapId
  if not mapId then
    local ok, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
    if ok and type(MapCatalog) == "table" and MapCatalog.mapIdFor then
      mapId = MapCatalog.mapIdFor(tonumber(t.mapGroup), tonumber(t.mapNum))
    end
  end
  local Sp = Space()
  local ev = mapId and Sp and Sp.bundle and Sp.bundle.events and Sp.bundle.events[mapId]
  local defs = ev and (ev.objects or ev.objectEvents)
  local tpl = type(defs) == "table" and defs[tonumber(t.localId) or 0]
  if type(tpl) ~= "table" or tonumber(tpl.kind) == OBJ_KIND_CLONE then return nil end
  return tpl
end

Objects.cloneTemplate = cloneTemplate

local function templateCopy(src)
  src = src or {}
  local tpl = cloneTemplate(src)
  local def = {}
  for k, v in pairs(tpl or src) do def[k] = v end
  if tpl then
    def.localId, def.index, def.x, def.y = src.localId, src.index, src.x, src.y
    def.kind, def.cloneTarget = src.kind, src.cloneTarget
  end
  return def
end
local function sameTemplate(src, snapshot)
  if cloneTemplate(src) then return Prepare.matches(templateCopy(src), snapshot) end
  return Prepare.matches(src, snapshot)
end

local function newEventObject(src, neighbor, prepared)
  local def = templateCopy(src)
  local x, y = tonumber(def.x) or 0, tonumber(def.y) or 0
  local resolvedGfx = def.graphicsId or def.graphics
  local okS, Sp = pcall(lazyReq, "src.core.game3.scripting.space")
  if okS and Sp and Sp.resolveObjectGraphicsId then
    local gid = Sp.resolveObjectGraphicsId(def, neighbor)
    if gid then resolvedGfx = gid end
  end
  local Coll = Collision()
  local elev = (def.elevation and def.elevation ~= 0 and def.elevation)
    or (Coll and Coll.elevationAt and Coll.elevationAt(x, y)) or 0
  local MapCatalog = package.loaded["src.import.gba.map_catalog"]
    or (pcall(lazyReq, "src.import.gba.map_catalog") and package.loaded["src.import.gba.map_catalog"])
  local mg, mn
  if MapCatalog and MapCatalog.groupNumFor and (def.mapId or Objects._mapId) then
    mg, mn = MapCatalog.groupNumFor(def.mapId or Objects._mapId)
  end
  local visible = objectVisible(def)
  local eo = prepared
  if not eo then
    local rawMt = canonMt(def.movementType)
    eo = Prepare.instance(def, { rawMt = rawMt, spec = rawMt and hostSpec(rawMt, def.rangeX, def.rangeY),
      version = lazyReq("src.core.GameVersion").get(), mapId = Objects._mapId, rse = isRse(),
      graphicsId = resolvedGfx, elevation = elev, group = mg, num = mn, visible = visible })
  else
    -- Only authoritative live state is rebound here. Construction and movement
    -- specifications came from an immutable worker snapshot.
    eo.def = def
    if tonumber(def.movementType) == nil and def.radius then eo.spec.radius = def.radius end
    if eo.spec.radius then eo.radius = eo.spec.radius end
    eo.graphicsId = resolvedGfx
    eo.sprite = def.sprite or (resolvedGfx and GfxIds.spriteFor(resolvedGfx)) or "SPRITE_YOUNGSTER"
    eo.elevation, eo.visible, eo.hidden = elev, visible, not visible
    eo.originMapId = def.originMapId or def.mapId or Objects._mapId
    eo.originMapGroup = tonumber(def.originMapGroup or def.mapGroup) or mg
    eo.originMapNum = tonumber(def.originMapNum or def.mapNum) or mn
  end
  -- pokeemerald/src/event_object_movement.c:1301
  eo.spawnElevation = true
  return eo
end

local preparedMaps, preparationStream = {}, nil
local function definitions(mapId, mapDef)
  local Sp = Space()
  local ev = Sp and Sp.bundle and Sp.bundle.events and Sp.bundle.events[mapId]
  local defs = ev and (ev.objects or ev.objectEvents)
  return type(defs) == "table" and defs or (mapDef and mapDef.objects) or {}
end
local function preparationCurrent(row, defs)
  if row.defs ~= defs or row.version ~= lazyReq("src.core.GameVersion").get()
      or row.inPlace ~= fieldBlock().inPlaceMovementTypes or #row.snapshot.defs ~= #defs then return false end
  for i, def in ipairs(defs) do
    if not sameTemplate(def, row.snapshot.defs[i]) then return false end
  end
  return true
end
function Objects.prefetchMap(mapId, mapDef, priority)
  if not (love and love.thread and love.thread.newThread) then return end
  local Stream = lazyReq("src.core.game3.asset_stream")
  if Stream.workerFailed then return end
  local defs = definitions(mapId, mapDef)
  local old = preparedMaps[mapId]
  if old and old.error and preparationCurrent(old, defs) then return false end
  if old and preparationCurrent(old, defs)
      and (old.data or (preparationStream and preparationStream.pending[mapId])) then return true end
  if not preparationStream then
    preparationStream = Stream.newTask("objects", function(key, data, err)
      local row = preparedMaps[key]
      if row then row.data, row.error = data, err end
    end)
  end
  if old then
    local wanted = {}; for id in pairs(preparedMaps) do if id ~= mapId then wanted[id] = true end end
    preparationStream:retain(wanted)
  end
  local templates = {}
  for i, def in ipairs(defs) do templates[i] = templateCopy(def) end
  local frozen = Prepare.freeze(templates)
  if not frozen then preparedMaps[mapId] = nil; return end
  local version = lazyReq("src.core.GameVersion").get()
  local inPlaceEnabled = fieldBlock().inPlaceMovementTypes
  local snapshot = { defs = frozen, version = version, mapId = mapId, rse = isRse(), inPlace = inPlaceEnabled }
  preparedMaps[mapId] = { defs = defs, version = version, inPlace = inPlaceEnabled, snapshot = snapshot }
  preparationStream:submit(mapId, snapshot, priority)
  lazyReq("src.core.game3.asset_stream").poll()
  return preparationStream.pending[mapId] ~= nil or preparedMaps[mapId].data ~= nil
end
function Objects.preparationReady(mapId, mapDef)
  local Stream = package.loaded["src.core.game3.asset_stream"]
  if Stream then Stream.poll() end
  local row = preparedMaps[mapId]
  return row and row.data ~= nil and preparationCurrent(row, definitions(mapId, mapDef)) or false
end
function Objects.retainPrepared(wanted)
  if preparationStream then preparationStream:retain(wanted) end
  for id in pairs(preparedMaps) do if not wanted[id] then preparedMaps[id] = nil end end
end
function Objects._preparationPending(mapId)
  return preparationStream and preparationStream.pending[mapId] ~= nil
end
local function takePrepared(mapId, defs)
  local Stream = package.loaded["src.core.game3.asset_stream"]
  if Stream then Stream.poll() end
  local row = preparedMaps[mapId]
  if row and row.data and preparationCurrent(row, defs) then
    preparedMaps[mapId] = nil
    Objects._lastPreparationRoute = "worker"
    return row.data, row.snapshot.defs
  end
  Objects._lastPreparationRoute = "sync"
end
local function preparedRow(rows, snapshots, i, def)
  return rows and sameTemplate(def, snapshots[i]) and rows[i] or nil
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
  Objects.retainPrepared({})
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
  local okS, Space = pcall(lazyReq, "src.core.game3.scripting.space")
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
  local okFv, FieldView = pcall(lazyReq, "src.core.game3.field_view")
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
  mt = canonMt(mt) or 0
  local spec = hostSpec(mt, eo.rangeX, eo.rangeY)
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
  if isRse() then Objects.initRseKind(eo) end
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

local function spawnFromTemplate(def, mapId, prepared)
  local eo = newEventObject(def, nil, prepared)
  if mapId and (not eo.originMapGroup or not eo.originMapNum) then
    local okC, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
    if okC and MapCatalog and MapCatalog.groupNumFor then
      local g, n = MapCatalog.groupNumFor(mapId)
      if g and n then
        eo.originMapGroup = g
        eo.originMapNum = n
      end
    end
    eo.originMapId = mapId
  end
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
  Objects._foreign = nil
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
  local prepared, snapshots = takePrepared(mapId, Objects._defs)
  local announce = ModRuntime.wants("world.npc_spawned")
  for i, def in ipairs(Objects._defs) do
    local eo = spawnFromTemplate(def, mapId, preparedRow(prepared, snapshots, i, def))
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

local FOREIGN_BASE = 0xC0

local function shiftObject(eo, dx, dy)
  eo.cellX, eo.cellY = (eo.cellX or 0) + dx, (eo.cellY or 0) + dy
  eo.px, eo.py = (eo.px or 0) + dx * CELL, (eo.py or 0) + dy * CELL
  if eo.targetX then eo.targetX, eo.targetY = eo.targetX + dx, eo.targetY + dy end
  if eo.homeX then eo.homeX, eo.homeY = eo.homeX + dx, eo.homeY + dy end
end

-- pokeemerald/src/fieldmap.c:603 CameraMove, pokeemerald/src/event_object_movement.c:2217
function Objects.carryOut(dx, dy)
  local carry = { map = Objects._mapId, list = {}, player = nil }
  local playerTrack = Objects._tracks[Objects.PLAYER_LOCAL_ID]
  if playerTrack then carry.player = playerTrack end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    local tr = Objects._tracks[lid]
    if eo and eo.visible and not eo.hidden and ((tr and not tr.done) or eo.foreignMap) then
      shiftObject(eo, dx, dy)
      eo.foreignMap = eo.foreignMap or Objects._mapId
      eo.foreignLid = eo.foreignLid or lid
      eo.originLocalId = eo.originLocalId or lid
      eo.originMapId = eo.originMapId or eo.foreignMap
      if not eo.originMapGroup or not eo.originMapNum then
        local okC, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
        if okC and MapCatalog and MapCatalog.groupNumFor then
          local g, n = MapCatalog.groupNumFor(eo.originMapId)
          if g and n then
            eo.originMapGroup = g
            eo.originMapNum = n
          end
        end
      end
      carry.list[#carry.list + 1] = { eo = eo, track = tr }
    end
  end
  return carry
end

function Objects.carryIn(carry)
  if not carry then return end
  Objects._foreign = {}
  if carry.player then Objects._tracks[Objects.PLAYER_LOCAL_ID] = carry.player end
  for i, c in ipairs(carry.list) do
    local key = FOREIGN_BASE + i - 1
    if key >= Objects.PLAYER_LOCAL_ID then break end
    c.eo.localId = key
    Objects._byId[key] = c.eo
    Objects._order[#Objects._order + 1] = key
    if c.track then Objects._tracks[key] = c.track end
    Objects._foreign[c.eo.foreignMap .. ":" .. c.eo.foreignLid] = key
  end
end

function Objects.foreignKey(mapId, localId)
  local f = Objects._foreign
  return f and f[tostring(mapId) .. ":" .. tostring(tonumber(localId) or localId)] or nil
end

-- pokeemerald/src/load_save.c:180
function Objects.snapshot()
  if not Objects._mapId then return nil end
  local protos = {}
  for _, def in ipairs(Objects._defs or {}) do
    local lid = tonumber(def.localId or def.index) or 0
    if lid > 0 then
      local p = newEventObject(def)
      Objects.spawnElevation(p)
      protos[lid] = p
    end
  end
  local list = {}
  for _, lid in ipairs(Objects._order) do
    local eo, p = Objects._byId[lid], protos[lid]
    if eo and p and lid > 0 and lid < FOREIGN_BASE and not eo.foreignMap then
      local row = { l = lid }
      local diff = false
      local function put(k, v, base)
        if v ~= base then row[k], diff = v, true end
      end
      if eo.hidden then
        if not p.hidden then row.h, diff = 1, true end
      else
        local x, y = eo.cellX, eo.cellY
        if eo.moving and eo.targetX then x, y = eo.targetX, eo.targetY end
        put("x", tonumber(x), p.cellX)
        put("y", tonumber(y), p.cellY)
        put("hx", tonumber(eo.homeX), p.homeX)
        put("hy", tonumber(eo.homeY), p.homeY)
        put("f", eo.facing, p.facing)
        put("m", tonumber(eo.movementType), p.movementType)
        put("e", tonumber(eo.elevation), p.elevation)
        put("c", tonumber(eo.currentElevation), p.currentElevation)
        if (eo.invisible == true) ~= (p.invisible == true) then row.i, diff = eo.invisible and 1 or 0, true end
        if p.hidden then diff = true end
      end
      if diff then list[#list + 1] = row end
    end
  end
  return { mapId = Objects._mapId, list = list }
end

local function placeObject(eo, x, y, homeX, homeY)
  eo.cellX, eo.cellY = x, y
  eo.px, eo.py = x * CELL, y * CELL
  eo.targetX, eo.targetY = x, y
  eo.homeX, eo.homeY = homeX or x, homeY or y
  eo.moving, eo.progress = false, 0
  if eo.def then eo.def.x, eo.def.y = x, y end
end

-- pokeemerald/src/load_save.c:188
-- pokeemerald/src/event_object_movement.c:1715
function Objects.restoreSnapshot(snap)
  if type(snap) ~= "table" or type(snap.list) ~= "table" or snap.mapId ~= Objects._mapId then return false end
  for _, row in ipairs(snap.list) do
    local lid = type(row) == "table" and tonumber(row.l) or 0
    if lid > 0 and lid < FOREIGN_BASE then
      local eo = Objects._byId[lid]
      if row.h then
        if eo and not eo.hidden then
          eo.hidden, eo.visible = true, false
          if eo.def then eo.def.hidden = true end
          Objects._tracks[lid] = nil
        end
      else
        if not eo or eo.hidden then eo = respawnFromTemplate(lid) end
        if eo then
          local x, y, hx, hy = tonumber(row.x), tonumber(row.y), tonumber(row.hx), tonumber(row.hy)
          if x or y or hx or hy then
            placeObject(eo, x or eo.cellX, y or eo.cellY, hx or eo.homeX, hy or eo.homeY)
          end
          local mt = tonumber(row.m)
          if mt and mt ~= tonumber(eo.movementType) then Objects.setTrainerMovementType(eo, mt) end
          if type(row.f) == "string" then eo.facing = row.f end
          if tonumber(row.e) then eo.elevation = tonumber(row.e) end
          if tonumber(row.c) then eo.currentElevation = tonumber(row.c) end
          if row.i ~= nil then eo.invisible = tonumber(row.i) == 1 end
        end
      end
    end
  end
  return true
end

function Objects.find(localId)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    return Player()
  end
  return Objects._byId[localId]
end

-- src/event_object_movement.c:1234-1249 GetObjectEventIdByLocalIdAndMap / TryGetObjectEventIdByLocalIdAndMap
function Objects.findObjectByLocalIdAndMap(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    return Player()
  end
  local g = tonumber(mapGroup)
  local n = tonumber(mapNum)
  local okC, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
  local targetMapId = (okC and MapCatalog and g ~= nil and n ~= nil and MapCatalog.mapIdFor(g, n)) or nil

  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo then
      local idMatch = (eo.localId == localId) or (eo.originLocalId == localId) or (eo.foreignLid == localId)
      if idMatch then
        if g ~= nil and n ~= nil then
          if (eo.originMapGroup == g and eo.originMapNum == n)
              or (targetMapId and (eo.originMapId == targetMapId or eo.foreignMap == targetMapId)) then
            return eo
          elseif not eo.foreignMap and Objects._mapId == targetMapId and eo.localId == localId then
            return eo
          end
        else
          return eo
        end
      end
    end
  end
  return nil
end

-- src/event_object_movement.c:2089-2116
local function on_named_map(mapGroup, mapNum)
  if mapGroup == nil or mapNum == nil then return true end
  local ok, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
  if not (ok and type(MapCatalog) == "table" and MapCatalog.mapIdFor) then return true end
  local engineId = MapCatalog.mapIdFor(tonumber(mapGroup), tonumber(mapNum))
  if engineId == nil then return false end
  return engineId == Objects._mapId
end

-- src/event_object_movement.c:1967, scrcmd.c:1139
function Objects.setSubpriority(localId, mapGroup, mapNum, subpriority)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    local P = Player()
    if P then
      P.fixedPriority = true
      P.subpriority = tonumber(subpriority) or 0
      return true
    end
  end
  local eo = Objects.findObjectByLocalIdAndMap(localId, mapGroup, mapNum)
    or (on_named_map(mapGroup, mapNum) and Objects._byId[localId] or nil)
  if not eo then return false end
  eo.fixedPriority = true
  eo.subpriority = tonumber(subpriority) or 0
  eo.fixedClass = nil
  return true
end

-- src/event_object_movement.c:1982, scrcmd.c:1149
function Objects.resetSubpriority(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    local P = Player()
    if P then
      P.fixedPriority = nil
      P.subpriority = nil
      return true
    end
  end
  local eo = Objects.findObjectByLocalIdAndMap(localId, mapGroup, mapNum)
    or (on_named_map(mapGroup, mapNum) and Objects._byId[localId] or nil)
  if not eo then return false end
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
        and (eo.foreignMap ~= nil or eo.moving or eo.scriptBusy or (Objects._tracks and Objects._tracks[eo.localId] ~= nil) or not offMap(Objects._bounds, eo)) then
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
      local foreign = vo.foreign
      vrec.cellX = tonumber(vo.x) or 0
      vrec.cellY = tonumber(vo.y) or 0
      vrec.elevation = tonumber(vo.elevation) or 3
      vrec.facing = VIRT_DIR_FACE[tonumber(vo.direction)] or "down"
      vrec.foreign = foreign
      vrec.draw = foreign and Objects.drawForeign or nil
      vrec.sprite = not foreign and GfxIds.spriteFor(gid) or nil
      vrec.graphicsId = not foreign and gid or nil
      vrec.raiseY = tonumber(vo.y2) or 0
      vrec.px, vrec.py, vrec.moving = vo.px, vo.py, vo.moving == true
      vrec.targetX, vrec.targetY = vo.targetX, vo.targetY
      vrec.animClock, vrec.stepFrames, vrec.stepFlip = tonumber(vo.animClock) or 0, vo.stepFrames, vo.stepFlip
      if not offMap(Objects._bounds, vrec) then
        n = n + 1
        list[n] = vrec
      end
    end
  end
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

function Objects.drawForeign(a, camX, camY)
  local eo = a and a.eventObject
  local p = eo and eo.foreign
  if not p then return false end
  local Avatars = require("src.online.union.Avatars")
  return Avatars.draw(Avatars.resolve(p, p.host), math.floor(a.x - camX + CELL / 2), math.floor(a.y - camY + CELL),
    a.facing, a.walkPhase, a.stepFlip, 1)
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
    -- pokeruby/src/overworld.c:2709
    if vo and vo.solid == true and tonumber(vo.prevX) == tx and tonumber(vo.prevY) == ty then return true end
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

-- pokeemerald/src/event_object_movement.c:7737
function Objects.spawnElevation(eo)
  eo.spawnElevation = nil
  if eo.fixedPriority then return end
  local Coll = Collision()
  if not (Coll and Coll.nextElevation) then return end
  local cx, cy = eo.cellX, eo.cellY
  if eo.moving then cx, cy = eo.targetX, eo.targetY end
  local cur, prev = Coll.nextElevation(eo.mapDef or Coll._mapDef, eo.currentElevation or 0,
    cx, cy, eo.cellX, eo.cellY)
  eo.currentElevation = cur
  if prev then eo.elevation = prev end
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
    local okTs, TrainerSight = pcall(lazyReq, "src.core.game3.trainer_sight")
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
  local off = stepOffset(frames, eo.progress, math.max(math.abs(dx), math.abs(dy)))
  eo.px = eo.cellX * CELL + (dx > 0 and off or dx < 0 and -off or 0)
  eo.py = eo.cellY * CELL + (dy > 0 and off or dy < 0 and -off or 0)
  local arc = eo.jumpArc
  if arc then
    -- pokeemerald/src/event_object_movement.c:8462
    local i = math.floor((eo.progress - 1) / (2 ^ arc.shift))
    eo.raiseY = arc.table[i + 1] or 0
    if arc.thenFace and eo.progress == math.floor(arc.frames / 2) then eo.facing = arc.thenFace end
  end
  if eo.progress >= frames then
    if arc then
      eo.jumpArc = nil
      eo.raiseY = nil
    end
    finishStep(eo, game, ctx)
    return true
  end
  return false
end

--- Scripted one-cell step (no collision — FRLG applymovement forces).
function Objects.scriptStep(eo, dir, run, slow, fast, frames)
  if not eo then return false end
  local P = Player()
  if eo == P then
    return P.scriptStep and P.scriptStep(dir, run, slow, fast, frames)
  end
  if eo.moving then return false end
  local d = DELTA[dir]
  if not d then return false end
  -- pokefirered/src/event_object_movement.c:6796 MovementAction_LockFacingDirection_Step0
  if not eo.facingLocked then eo.facing = dir end
  beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
  -- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
  if run then eo.stepFrames = slow and RUN_SLOW_FRAMES or RUN_FRAMES end
  if fast then eo.stepFrames = RUN_FRAMES end
  if frames then eo.stepFrames = frames end
  eo.frozen = true
  eo.scriptBusy = true
  return true
end

function Objects.scriptJump(eo, dir, distance, opts)
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
  if isRse() then Objects.startJumpArc(eo, distance, opts) end
  eo.frozen = true
  eo.scriptBusy = true
  return true
end

-- pokeemerald/src/event_object_movement.c:8424
local JUMP_Y = {
  high = { -4, -6, -8, -10, -11, -12, -12, -12, -11, -10, -9, -8, -6, -4, 0, 0 },
  low = { 0, -2, -3, -4, -5, -6, -6, -6, -5, -5, -4, -3, -2, 0, 0, 0 },
  normal = { -2, -4, -6, -8, -9, -10, -10, -10, -9, -8, -6, -5, -3, -2, 0, 0 },
}
Objects.JUMP_Y = JUMP_Y

-- pokeemerald/src/event_object_movement.c:8454
function Objects.startJumpArc(eo, distance, opts)
  opts = opts or {}
  local frames = distance == 2 and 32 or 16
  local kind = opts.type or ((distance == 1) and "normal" or "high")
  eo.stepFrames = frames
  eo.jumpArc = {
    table = JUMP_Y[kind] or JUMP_Y.high, shift = distance == 2 and 1 or 0, frames = frames,
    thenFace = opts.thenFace, shadow = true,
  }
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
  if eo and eo.trackWait then
    if not eo.trackWait(eo) then return end
    eo.trackWait = nil
  end

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
        if Player().scriptStep then Player().scriptStep(act.dir, act.run, act.slow, act.fast, act.frames) end
      elseif eo then
        Objects.scriptStep(eo, act.dir, act.run, act.slow, act.fast, act.frames)
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
          Objects.scriptJump(eo, act.dir, act.distance or 1,
            { thenFace = act.thenFace, type = act.jumpType })
        else
          Objects.scriptStep(eo, act.dir)
        end
      end
    elseif act.kind == "step_diagonal" then
      Objects.scriptDiagonal(eo, act)
    elseif act.kind == "levitate" then
      Objects.setLevitate(eo, act.on, act.atTop)
    elseif act.kind == "figure8" then
      Objects.startFigure8(eo)
    elseif act.kind == "lock_anim" then
      -- pokeemerald/src/event_object_movement.c:8809
      if eo and eo ~= Player() then
        eo.inanimate = act.locked and true or false
        eo.facingLocked = act.locked and true or false
      end
    elseif act.kind == "reflection" then
      -- pokeemerald/src/event_object_movement.c:6617
      if eo then eo.hideReflection = act.hidden and true or false end
    elseif act.kind == "jump_landing_effect" then
      -- pokeemerald/src/event_object_movement.c:6444
      if eo == Player() then
        local okF, FxRse = pcall(lazyReq, "src.core.game3.field_effects_rse")
        if okF and FxRse then FxRse.setJumpLandingEffect(act.on) end
      elseif eo then
        eo.disableJumpLanding = not act.on
      end
    elseif act.kind == "reveal_trainer" then
      Objects.revealTrainer(eo)
    elseif act.kind == "turn" then
      Objects.scriptFace(eo, act.dir)
      if act.frames then tr.sleep = act.frames end
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
        local okFx, FieldEffects = pcall(lazyReq, "src.core.game3.field_effects")
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
        eo.invisible = true
      end
    elseif act.kind == "show" then
      -- pokefirered/src/event_object_movement.c:7061
      if eo == Player() then
        Player().setVisible(true)
      elseif eo then
        eo.invisible = false
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
  local okTs, TrainerSight = pcall(lazyReq, "src.core.game3.trainer_sight")
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

local idleRng
local function pick(t)
  idleRng = idleRng or lazyReq("src.core.game3.rng")
  return t[(idleRng.Random() % #t) + 1]
end

-- tostring(movement):upper(), memoised (idleTick runs per object per frame).
local UPPER_MOVEMENT = setmetatable({}, { __index = function(t, k)
  local v = tostring(k):upper()
  t[k] = v
  return v
end })

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

  local mv = UPPER_MOVEMENT[eo.movement or "STAY"]
  if mv == "STAY" then return end
  if mv == "IN_PLACE" then
    -- pokeemerald/src/event_object_movement.c:4422
    local frames = eo.spec and eo.spec.frames or WALK_FRAMES
    beginStep(eo, eo.cellX, eo.cellY)
    eo.stepFrames = frames
    return
  end
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

local trackIds, trackRefs, trackActors = {}, {}, {}

Objects.FADE_FRAMES = 10

function Objects.fadeAlpha(eo)
  local n = eo.fadeIn
  if not n then return nil end
  return (n + 1) / Objects.FADE_FRAMES
end

function Objects.beginFadeIn(seen)
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.foreignMap == nil and not Objects.isPlayer(lid)
        and eo.visible and not eo.hidden and not seen[lid]
        and Objects.inCameraView(eo) then
      if eo.berryTree then
        eo.fadeIn, eo.fadeHold = 0, true
      elseif not eo.invisible then
        eo.fadeIn = 0
      end
    end
  end
end

local function tickFade(eo)
  local n = eo.fadeIn
  if n then
    if eo.fadeHold then
      local bt = eo.berryTree
      if bt and not bt.init then return end
      eo.fadeHold = nil
      if not (bt and bt.visible) then
        eo.fadeIn = nil
        return
      end
    end
    n = n + 1
    eo.fadeIn = n < Objects.FADE_FRAMES and n or nil
  end
end
Objects.tickFade = tickFade

function Objects.update(game)
  local count = 0
  for lid, tr in pairs(Objects._tracks) do
    count = count + 1
    trackIds[count], trackRefs[count], trackActors[count] = lid, tr, Objects.find(lid)
  end
  -- pokeemerald/src/event_object_movement.c:2167
  for i = 1, count do
    local tr, eo = trackRefs[i], trackActors[i]
    local lid = (eo and eo.localId) or trackIds[i]
    trackIds[i], trackRefs[i], trackActors[i] = nil, nil, nil
    if Objects._tracks[lid] == tr and (not eo or Objects.find(lid) == eo) then
      advanceTrack(lid, tr, game)
    end
  end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo then
      if eo.spawnElevation then Objects.spawnElevation(eo) end
      if eo.bowFrames and eo.bowFrames > 0 then
        eo.bowFrames = eo.bowFrames - 1
        if eo.bowFrames <= 0 then eo.bowFrames = nil end
      end
      tickFade(eo)
      tickMotion(eo, game)
      idleTick(eo, game)
      if eo.rseKind or eo.levitate or eo.fig8 then Objects.tickRse(eo) end
    end
  end
end

-- pokeemerald/src/event_object_movement.c:5144
function Objects.scriptDiagonal(eo, act)
  if not eo or eo == Player() or eo.moving then return false end
  if not eo.facingLocked then eo.facing = act.dirs and act.dirs[1] or eo.facing end
  beginStep(eo, eo.cellX + (act.dx or 0), eo.cellY + (act.dy or 0))
  if act.slow then eo.stepFrames = WALK_FRAMES * 2 end
  eo.frozen = true
  eo.scriptBusy = true
  return true
end

-- pokeemerald/src/event_object_movement.c:8895
function Objects.setLevitate(eo, on, atTop)
  if not eo or eo == Player() then return end
  if on then
    eo.levitate = { t = 0, d = -1 }
    return
  end
  if atTop then
    -- pokeemerald/src/event_object_movement.c:7307
    eo.trackWait = function(o)
      if (o.raiseY or 0) == 0 then
        o.levitate = nil
        return true
      end
      return false
    end
    return
  end
  eo.levitate = nil
  eo.raiseY = nil
end

-- pokeemerald/src/event_object_movement.c:8347
local FIG8_X = {
  1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 1, 2, 2, 1, 2, 2, 1, 2, 1, 1,
  2, 1, 1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
}
local FIG8_Y = {
  0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1,
  0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, -1, 0, 0, -1, 0, 0, -1, 0, -1, -1, 0, -1, -1, 0, -1, -1, -1, -1, -1, -1, -1, -2,
}
Objects.FIG8_X, Objects.FIG8_Y = FIG8_X, FIG8_Y

function Objects.startFigure8(eo)
  if not eo or eo == Player() then return end
  eo.fig8 = { i = 0, part = 0, x2 = 0, y2 = 0 }
  eo.trackWait = function(o) return o.fig8 == nil end
end

-- pokeemerald/src/event_object_movement.c:8387
local function figure8Step(eo)
  local f = eo.fig8
  local n = #FIG8_X
  local j = (n - 1) - f.i
  if f.part == 0 then
    f.x2, f.y2 = f.x2 + FIG8_X[f.i + 1], f.y2 + FIG8_Y[f.i + 1]
  elseif f.part == 1 then
    f.x2, f.y2 = f.x2 - FIG8_X[j + 1], f.y2 + FIG8_Y[j + 1]
  elseif f.part == 2 then
    f.x2, f.y2 = f.x2 - FIG8_X[f.i + 1], f.y2 + FIG8_Y[f.i + 1]
  else
    f.x2, f.y2 = f.x2 + FIG8_X[j + 1], f.y2 + FIG8_Y[j + 1]
  end
  f.i = f.i + 1
  if f.i == n then
    f.i = 0
    f.part = f.part + 1
  end
  if f.part == 4 then
    eo.fig8 = nil
    eo.raiseX, eo.raiseY = nil, nil
    return
  end
  eo.raiseX, eo.raiseY = f.x2, f.y2
end

-- pokeemerald/src/event_object_movement.c:3075
local MT_BERRY_TREE = 0x0C
-- pokeemerald/include/constants/event_object_movement.h:61
local MT_TREE_DISGUISE = 0x39
local MT_MOUNTAIN_DISGUISE = 0x3A
local MT_BURIED = 0x3F
Objects.MT_BERRY_TREE, Objects.MT_BURIED = MT_BERRY_TREE, MT_BURIED
Objects.MT_TREE_DISGUISE, Objects.MT_MOUNTAIN_DISGUISE = MT_TREE_DISGUISE, MT_MOUNTAIN_DISGUISE

-- pokeemerald/src/event_object_movement.c:1153
local COPY_TYPES = {
  [0x35] = { init = "up" }, [0x36] = { init = "down" }, [0x37] = { init = "left" }, [0x38] = { init = "right" },
  [0x3B] = { init = "up", grass = true }, [0x3C] = { init = "down", grass = true },
  [0x3D] = { init = "left", grass = true }, [0x3E] = { init = "right", grass = true },
}
local DIR_IDX = { down = 1, up = 2, left = 3, right = 4 }
local IDX_DIR = { "down", "up", "left", "right" }
-- pokeemerald/src/event_object_movement.c:1124
local COPY_FOR = {
  { 2, 1, 4, 3 }, { 1, 2, 3, 4 }, { 3, 4, 2, 1 }, { 4, 3, 1, 2 },
}
local COPY_TO = {
  { 2, 1, 4, 3 }, { 1, 2, 3, 4 }, { 4, 3, 1, 2 }, { 3, 4, 2, 1 },
}

-- pokeemerald/src/event_object_movement.c:5012
function Objects.copyDirection(copyInit, playerInit, playerMove)
  local pi, pm, ci = DIR_IDX[playerInit], DIR_IDX[playerMove], DIR_IDX[copyInit]
  if not (pi and pm and ci) then return nil end
  return IDX_DIR[COPY_TO[ci][COPY_FOR[pi][pm]]]
end

Objects.initRseKind = Prepare.initRseKind

-- pokeemerald/src/event_object_movement.c:1890
local function setBerryTreeGraphics(eo, bt, tree)
  local stage = tree and tree.stage or 0
  eo.invisible = true
  bt.visible = false
  if stage == 0 then return end
  bt.visible = true
  local berryStage = stage - 1
  local FxRse = lazyReq("src.core.game3.field_effects_rse")
  local m = FxRse.berryManifest()
  local berry = tonumber(tree.berry) or 1
  local entry = m and m.trees and (m.trees[berry] or m.trees[1])
  local st = entry and entry.stages and entry.stages[berryStage + 1]
  if entry and st then
    bt.tree = entry
    local cmds = {}
    for _, a in ipairs(st.anim or {}) do cmds[#cmds + 1] = { "frame", a.frame, a.duration } end
    cmds[#cmds + 1] = { "jump", 0 }
    bt.anim = FxRse.anim(cmds)
    eo.graphicsId = st.gfxId or eo.graphicsId
  end
  bt.animNum = berryStage
  bt.gfxKey = tostring(tree.berry) .. ":" .. tostring(stage)
end

-- pokeemerald/src/event_object_movement.c:3093
local function berryTreeTick(eo)
  local bt = eo.berryTree
  local okB, BerryTrees = pcall(lazyReq, "src.core.game3.rse.berry_trees")
  if not (okB and BerryTrees and bt) then return end
  local tree = BerryTrees.peek(nil, bt.id)
  local stage = tree and tree.stage or 0
  local FxRse = lazyReq("src.core.game3.field_effects_rse")
  if not bt.init then
    -- pokeemerald/src/event_object_movement.c:3075
    bt.init, bt.func = true, "normal"
    setBerryTreeGraphics(eo, bt, tree)
    return
  end
  if bt.func == "sparkle" or bt.func == "sparkle_end" then
    -- pokeemerald/src/event_object_movement.c:3154
    bt.timer = bt.timer + 1
    bt.visible = math.floor(bt.timer / 2) % 2 == 0 and bt.animNum ~= nil
    if bt.timer > 64 then
      if bt.func == "sparkle" then
        setBerryTreeGraphics(eo, bt, tree)
        bt.func, bt.timer = "sparkle_end", 0
      else
        bt.func = "normal"
        bt.visible = stage ~= 0
      end
    end
    return
  end
  if stage == 0 then
    if not bt.justPicked and bt.animNum == 4 then
      FxRse.startBerryTreeSparkle(eo.cellX, eo.cellY)
    end
    bt.animNum = 0
    bt.visible = false
    return
  end
  bt.visible = true
  if bt.animNum ~= stage - 1 then
    -- pokeemerald/src/event_object_movement.c:3139
    bt.func, bt.timer = "sparkle", 0
    FxRse.startBerryTreeSparkle(eo.cellX, eo.cellY)
    return
  end
  if bt.gfxKey ~= tostring(tree.berry) .. ":" .. tostring(stage) then setBerryTreeGraphics(eo, bt, tree) end
end

local function isPokeGrass(x, y)
  local Coll = Collision()
  local MB = lazyReq("src.core.game3.mb")
  local b = Coll and Coll.behavior and Coll.behavior(x, y)
  return b ~= nil and (b == MB.id("TALL_GRASS") or b == MB.id("LONG_GRASS"))
end

-- pokeemerald/src/event_object_movement.c:4168
local function copyTick(eo)
  local c = eo.copy
  local P = Player()
  if not (c and P) then return end
  if not c.playerInit then c.playerInit = P.facing end
  local serial = P.stepSerial or 0
  if c.serial == nil then c.serial = serial end
  if c.serial == serial then return end
  -- pokeemerald/src/event_object_movement.c:4170
  if not P.moving then
    c.serial = serial
    return
  end
  if eo.moving or eo.frozen or eo.scriptBusy then return end
  c.serial = serial
  local okF, Faraway = pcall(lazyReq, "src.core.game3.faraway_island")
  local mew = okF and Faraway and Faraway.isMew(eo)
  local dir
  if mew then
    -- pokeemerald/src/event_object_movement.c:4206
    dir = Faraway.mewDirection(eo, P)
    if not dir then
      eo.facing = Objects.copyDirection(c.init, c.playerInit, P.moveDir or P.facing) or eo.facing
      return
    end
  else
    dir = Objects.copyDirection(c.init, c.playerInit, P.moveDir or P.facing)
  end
  if not dir then return end
  local d = DELTA[dir]
  eo.facing = dir
  if stepCollision(eo, nil, nil, dir) or (c.grass and not isPokeGrass(eo.cellX + d[1], eo.cellY + d[2])) then
    return
  end
  beginStep(eo, eo.cellX + d[1], eo.cellY + d[2])
  if P.running or P.biking then eo.stepFrames = RUN_FRAMES end
  -- pokeemerald/src/event_object_movement.c:8048
  if mew and Faraway.shouldShakeGrass() and isPokeGrass(eo.targetX, eo.targetY) then
    local MB = lazyReq("src.core.game3.mb")
    local Coll = Collision()
    local long = Coll.behavior(eo.targetX, eo.targetY) == MB.id("LONG_GRASS")
    local okFx, FxRse = pcall(lazyReq, "src.core.game3.field_effects_rse")
    if okFx and FxRse then
      FxRse.spawnAt(long and "long_grass" or "tall_grass", eo.targetX, eo.targetY, 8, 8, { layer = "front" })
    end
  end
end

function Objects.tickRse(eo)
  if eo.levitate then
    -- pokeemerald/src/event_object_movement.c:8908
    local l = eo.levitate
    if l.t % 4 == 0 then eo.raiseY = (eo.raiseY or 0) + l.d end
    if l.t % 16 == 0 then l.d = -l.d end
    l.t = l.t + 1
  end
  if eo.fig8 then figure8Step(eo) end
  if eo.rseKind == "berry_tree" then berryTreeTick(eo) end
  if eo.rseKind == "copy" then copyTick(eo) end
end

-- pokeemerald/src/event_object_movement.c:6503
function Objects.revealTrainer(eo)
  if not eo or eo == Player() then return end
  local mt = tonumber(eo.movementType) or 0
  if mt == MT_BURIED then
    local TrainerSight = lazyReq("src.core.game3.trainer_sight")
    local done = false
    TrainerSight.revealBuried(eo, function() done = true end)
    eo.trackWait = function() return done end
    return
  end
  local d = eo.disguise
  if not d then return end
  -- pokeemerald/src/field_effect_helpers.c:1380
  local FxRse = lazyReq("src.core.game3.field_effects_rse")
  d.a = FxRse.anim(FxRse.animCmds(d.sheet, 2))
  d.revealing = true
  eo.trackWait = function(o) return o.disguise == nil or o.disguise.done == true end
end

function Objects.spawnFromDefs(defs, mapDef, mapId)
  local pool = { byId = {}, order = {}, bounds = layoutBounds(mapDef), mapDef = mapDef }
  local Sp = mapId and Space()
  local nb = Sp and Sp.neighborObjectState and Sp.neighborObjectState(mapId)
  if mapId and not nb and not (Sp and Sp.mapId == mapId) then nb = { store = { flags = {}, vars = {} }, perm = {}, movementType = {} } end
  local prepared, snapshots = takePrepared(mapId, defs or {})
  for i, def in ipairs(defs or {}) do
    local eo = newEventObject(def, nb, preparedRow(prepared, snapshots, i, def))
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
      if eo.spawnElevation then Objects.spawnElevation(eo) end
      if eo.bowFrames and eo.bowFrames > 0 then
        eo.bowFrames = eo.bowFrames - 1
        if eo.bowFrames <= 0 then eo.bowFrames = nil end
      end
      tickFade(eo)
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
      local Flags = lazyReq("src.core.game3.scripting.flags")
      Flags.setFlag(Space.store, nil, flag, true)
    end
  end
  eo.hidden = true
  eo.visible = false
  if eo.def then eo.def.hidden = true end
  Objects._tracks[localId] = nil
  return true
end

-- pokeemerald/src/event_object_movement.c:1939 SetObjectInvisibility
function Objects.hideObjectAt(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    local P = Player()
    if P and P.setVisible then P.setVisible(false) end
    return true
  end
  local eo = Objects.findObjectByLocalIdAndMap(localId, mapGroup, mapNum)
    or (on_named_map(mapGroup, mapNum) and Objects._byId[localId] or nil)
  if not eo then return false end
  eo.invisible = true
  return true
end

function Objects.showObjectAt(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if Objects.isPlayer(localId) then
    local P = Player()
    if P and P.setVisible then P.setVisible(true) end
    return true
  end
  local eo = Objects.findObjectByLocalIdAndMap(localId, mapGroup, mapNum)
    or (on_named_map(mapGroup, mapNum) and Objects._byId[localId] or nil)
  if not eo then
    if on_named_map(mapGroup, mapNum) then
      return Objects.addObject(localId)
    end
    return false
  end
  eo.invisible = false
  eo.hidden = false
  eo.visible = true
  if eo.def then eo.def.hidden = false end
  return true
end

function Objects.hideObject(localId)
  return Objects.hideObjectAt(localId, nil, nil)
end

function Objects.showObject(localId)
  return Objects.showObjectAt(localId, nil, nil)
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
  mt = canonMt(mt) or 0
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
  mt = canonMt(mt) or 0
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
  Objects._templateMt[lid] = canonMt(mt)
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

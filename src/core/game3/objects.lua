-- Game3 EventObject instances (localId-keyed).
-- Owns idle AI + applymovement tracks; optional host NPC mirror for adapters.
-- Player localId 0xFF delegates to game3.player. Talk is Field.interact.

local Movement = require("src.core.game3.scripting.movement")
local Opcodes = require("src.core.game3.scripting.opcodes")
local GfxIds = require("src.core.game3.scripting.gfx_ids")
local ModRuntime = require("src.mods.Runtime")

local Objects = {}

Objects.PLAYER_LOCAL_ID = Opcodes.LOCALID_PLAYER or 0xFF

local CELL = 16
local WALK_FRAMES = 16
-- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
local RUN_FRAMES = 8
-- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
local RUN_SLOW_FRAMES = 11
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

local function newEventObject(def)
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
  local mt = tonumber(def.movementType) or 0
  local hostMv = GfxIds.hostMovement
    and GfxIds.hostMovement(mt, def.radius and def.radius.x, def.radius and def.radius.y)
    or nil
  local movement = def.movement
    or (hostMv and hostMv.movement)
    or "STAY"
  local range = def.range or (hostMv and hostMv.range) or "DOWN"
  local radius = def.radius or (hostMv and hostMv.radius)
  local sprite = def.sprite
  local resolvedGfx = def.graphicsId or def.graphics
  do
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if okS and Space and Space.resolveObjectGraphicsId then
      local gid = Space.resolveObjectGraphicsId(def)
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
    facing = facingFromDef(def),
    sprite = sprite or "SPRITE_YOUNGSTER",
    graphicsId = resolvedGfx,
    elevation = elev,
    movementType = mt,
    movement = movement,
    range = range,
    radius = radius or { x = 1, y = 1 },
    sight = tonumber(def.sight or def.trainerRange) or 0,
    trainerType = tonumber(def.trainerType) or 0,
    scriptKey = def.scriptKey,
    flag = def.flag,
    visible = objectVisible(def),
    hidden = not objectVisible(def),
    frozen = false,
    passable = def.passable and true or false,
    moving = false,
    progress = 0,
    stepFrames = WALK_FRAMES,
    targetX = x,
    targetY = y,
    stepFlip = false,
    animClock = 0,
    idleTimer = 30 + (lid * 17) % 60,
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
end

-- pokefirered/src/overworld.c:405
function Objects.reset()
  Objects.clear()
  Objects._perm = {}
  Objects._templateMt = {}
  Objects._logged = false
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
    eo.movementType = row.movementType
    local hostMv = GfxIds.hostMovement and GfxIds.hostMovement(row.movementType)
    if hostMv then
      eo.movement = hostMv.movement
      eo.range = hostMv.range
      if hostMv.radius then eo.radius = hostMv.radius end
    end
    local face = ({ [7] = "up", [8] = "down", [9] = "left", [10] = "right" })[row.movementType]
    if face then eo.facing = face end
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
    local eo = newEventObject(def)
    if eo.localId > 0 then
      applyPerm(eo, mapId)
      local tmt = Objects._templateMt[eo.localId]
      if tmt then
        Objects.setTrainerMovementType(eo, tmt)
        local face = ({ [7] = "up", [8] = "down", [9] = "left", [10] = "right" })[tmt]
        if face then eo.facing = face end
      end
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

function Objects.forDraw()
  local list = {}
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden
        and not offMap(Objects._bounds, eo) then
      list[#list + 1] = eo
    end
  end
  return list
end

--- First visible EventObject standing on (tx, ty), or nil if moving onto it.
function Objects.at(tx, ty)
  tx, ty = tonumber(tx), tonumber(ty)
  if not tx or not ty then return nil end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden then
      if eo.cellX == tx and eo.cellY == ty then
        if eo.moving then return nil end
        return eo
      end
    end
  end
  return nil
end

--- True if any non-passable EO occupies (tx,ty) or is stepping onto it.
function Objects.blocks(tx, ty, exceptLocalId)
  exceptLocalId = tonumber(exceptLocalId)
  for _, lid in ipairs(Objects._order) do
    if lid ~= exceptLocalId then
      local eo = Objects._byId[lid]
      if eo and eo.visible and not eo.hidden and not eo.passable then
        if eo.cellX == tx and eo.cellY == ty then return true end
        if eo.moving and eo.targetX == tx and eo.targetY == ty then
          return true
        end
      end
    end
  end
  return false
end

-- pokefirered/src/event_object_movement.c:4899
function Objects.playerBlocks(tx, ty)
  local P = Player()
  if not P then return false end
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

local function beginStep(eo, tx, ty)
  eo.moving = true
  eo.progress = 0
  eo.targetX = tx
  eo.targetY = ty
  eo.stepFrames = WALK_FRAMES
  eo.animClock = 0
end

local function finishStep(eo)
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
  local Coll = Collision()
  local curElev = Coll and Coll.elevationAt and Coll.elevationAt(eo.cellX, eo.cellY)
  if curElev and curElev ~= 0 and curElev ~= 15 then
    eo.elevation = curElev
  end
end

local function tickMotion(eo)
  if not eo.moving then return false end
  eo.progress = eo.progress + 1
  eo.animClock = eo.animClock + 1
  local frames = eo.stepFrames or WALK_FRAMES
  local dx = eo.targetX - eo.cellX
  local dy = eo.targetY - eo.cellY
  local t = math.min(1, eo.progress / frames)
  eo.px = eo.cellX * CELL + dx * CELL * t
  eo.py = eo.cellY * CELL + dy * CELL * t
  if eo.progress >= frames then
    finishStep(eo)
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
        local origFace = facingFromDef(eo.def)
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
      if eo and eo ~= Player() then
        eo.hidden = true
        eo.visible = false
      end
    elseif act.kind == "show" then
      if eo and eo ~= Player() then
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
  eo.idleTimer = (eo.idleTimer or 0) - 1
  if eo.idleTimer > 0 then return end

  local mv = tostring(eo.movement or "STAY"):upper()
  if mv == "STAY" then
    eo.idleTimer = 120
    return
  end

  local Rng = require("src.core.game3.rng")
  local dirs = dirsForRange(eo.range)
  if mv == "LOOK" or mv == "LOOK_AROUND" then
    local oldFacing = eo.facing
    local pickIdx = Rng.compat(1, #dirs)
    eo.facing = dirs[pickIdx] or dirs[1]
    eo.idleTimer = 48 + Rng.compat(0, 47)
    if not ctx and eo.facing ~= oldFacing and eo.sight and eo.sight > 0 then
      local okTs, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
      if okTs and TrainerSight and TrainerSight.check then
        TrainerSight.check(game, eo)
      end
    end
    return
  end

  if mv == "WALK" then
    local pickIdx = Rng.compat(1, #dirs)
    local dir = dirs[pickIdx] or dirs[1]
    local d = DELTA[dir]
    local tx, ty = eo.cellX + d[1], eo.cellY + d[2]
    local rx = (eo.radius and eo.radius.x) or 1
    local ry = (eo.radius and eo.radius.y) or 1
    if math.abs(tx - eo.homeX) > rx or math.abs(ty - eo.homeY) > ry then
      eo.idleTimer = 30 + Rng.compat(0, 29)
      return
    end
    local ok
    -- pokefirered/src/event_object_movement.c:4830 GetCollisionAtCoords
    if ctx then
      local Coll = Collision()
      ok = ctx.canEnter(tx, ty, eo.cellX, eo.cellY, dir)
        and not ctx.blocks(tx, ty, eo.localId)
      if ok and eo.mapDef and Coll.directionallyImpassableOn(
          eo.mapDef, eo.cellX, eo.cellY, tx, ty, dir) then
        ok = false
      end
    else
      local Coll = Collision()
      -- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
      local onWater = Coll.isWater(eo.cellX, eo.cellY)
      ok = Coll.canEnter(game, tx, ty,
        { fromX = eo.cellX, fromY = eo.cellY, dir = dir, surfing = onWater })
      if ok and Coll.isWater(tx, ty) ~= onWater then ok = false end
      if Objects.playerBlocks(tx, ty) then ok = false end
      if Objects.blocks(tx, ty, eo.localId) then ok = false end
    end
    if ok then
      eo.facing = dir
      beginStep(eo, tx, ty)
    else
      eo.facing = dir -- turn toward blocked anyway
    end
    eo.idleTimer = 40 + Rng.compat(0, 49)
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
      tickMotion(eo)
      idleTick(eo, game)
    end
  end
end

function Objects.spawnFromDefs(defs, mapDef)
  local pool = { byId = {}, order = {}, bounds = layoutBounds(mapDef), mapDef = mapDef }
  for _, def in ipairs(defs or {}) do
    local eo = newEventObject(def)
    if eo.localId > 0 then
      eo.mapDef = mapDef
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
      tickMotion(eo)
      idleTick(eo, game, ctx)
    end
  end
end

function Objects.poolForDraw(pool)
  local list = {}
  if type(pool) ~= "table" then return list end
  for _, lid in ipairs(pool.order or {}) do
    local eo = pool.byId[lid]
    if eo and eo.visible and not eo.hidden and not offMap(pool.bounds, eo) then
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
    local wanders = live and tostring(live.movement or "STAY"):upper() == "WALK"
    if live and ghost and wanders and not ghost.moving then
      live.cellX, live.cellY = ghost.cellX, ghost.cellY
      live.px, live.py = ghost.px, ghost.py
      live.facing = ghost.facing
      live.stepFlip = ghost.stepFlip
      live.idleTimer = ghost.idleTimer
      if live.def then live.def.x, live.def.y = live.cellX, live.cellY end
    end
  end
  return true
end

function Objects.addObject(localId)
  localId = tonumber(localId) or 0
  local eo = Objects._byId[localId]
  if eo then
    applyPerm(eo, Objects._mapId)
    eo.hidden = false
    eo.visible = true
    if eo.def then eo.def.hidden = false end
    return true
  end
  -- Respawn from template defs.
  for _, def in ipairs(Objects._defs or {}) do
    if tonumber(def.localId or def.index) == localId then
      eo = newEventObject(def)
      applyPerm(eo, Objects._mapId)
      eo.hidden = false
      eo.visible = true
      Objects._byId[localId] = eo
      Objects._order[#Objects._order + 1] = localId
      return true
    end
  end
  return false
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

--- pret FlagClear/FlagSet on an object template hide flag.
-- clearflag after removeobject must bring the NPC back at perm coords.
function Objects.syncFlagVisibility(flagId, hidden)
  flagId = tonumber(flagId) or 0
  if flagId == 0 or flagId == 0xFFFF or flagId == 65535 then return end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo then
      local f = tonumber(eo.flag) or (eo.def and tonumber(eo.def.flag or eo.def.flagId)) or 0
      if f == flagId then
        if hidden then
          eo.hidden = true
          eo.visible = false
          if eo.def then eo.def.hidden = true end
        else
          applyPerm(eo, Objects._mapId)
          eo.hidden = false
          eo.visible = true
          if eo.def then eo.def.hidden = false end
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

function Objects.hideObject(localId)
  return Objects.removeObject(localId)
end

function Objects.showObject(localId)
  return Objects.addObject(localId)
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
  eo.movementType = mt
  local hostMv = GfxIds.hostMovement and GfxIds.hostMovement(mt)
  if hostMv then
    eo.movement = hostMv.movement
    eo.range = hostMv.range
    if hostMv.radius then eo.radius = hostMv.radius end
  end
  clearRaiseHand(eo)
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

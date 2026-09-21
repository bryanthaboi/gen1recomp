local Data = require("src.core.game3.vs_seeker_data")
local Flags = require("src.core.game3.scripting.flags")
local Rng = require("src.core.game3.rng")
local Strings = require("src.core.Strings")

local VsSeeker = {}

-- pokefirered/include/constants/items.h:434
VsSeeker.ITEM_VS_SEEKER = 362
VsSeeker.MAX_CHARGE = 100
VsSeeker.FLAG_SYS_VS_SEEKER_CHARGING = 0x801
-- src/vs_seeker.c:973
VsSeeker.TIER_FLAGS = { 0x292, 0x896, 0x897, 0x82C, 0x844 }

VsSeeker.MOVEMENT_TYPE_FACE_UP = 0x07
VsSeeker.MOVEMENT_TYPE_FACE_DOWN = 0x08
VsSeeker.MOVEMENT_TYPE_FACE_LEFT = 0x09
VsSeeker.MOVEMENT_TYPE_FACE_RIGHT = 0x0A
VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_STOP = 0x4D
VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_JUMP = 0x4E
VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_SWIM = 0x4F

VsSeeker.NOT_CHARGED = 0
VsSeeker.NO_ONE_IN_RANGE = 1
VsSeeker.CAN_USE = 2

VsSeeker.RESPONSE_NO_RESPONSE = 0
VsSeeker.RESPONSE_UNFOUGHT_TRAINERS = 1
VsSeeker.RESPONSE_FOUND_REMATCHES = 2

local RESP_RAND, RESP_NO, RESP_YES = 0, 1, 2

local SE_PIN = 21
local SE_CONTEST_MONS_TURN = 94
VsSeeker.EFFECT_FRAMES = 89
VsSeeker.WAIT_FRAMES = 48

-- src/vs_seeker.c:565
VsSeeker.MOVEMENT_UNFOUGHT = { 0x62, 0xFE }
VsSeeker.MOVEMENT_NO_REMATCH = { 0x64, 0xFE }
VsSeeker.MOVEMENT_REMATCH = { 0x2D, 0x65, 0xFE }

-- English sources, translated where they are shown.
-- data/text/trainers.inc:1
VsSeeker.TEXT = {
  notCharged = Strings.source("The battery isn't charged enough.\fNo. of steps required to fully\ncharge the battery: %d"),
  noTrainers = Strings.source("There are no TRAINERS within range\nwho can battle…\fThe VS SEEKER was turned off."),
  notReady = Strings.source("The other TRAINERS don't appear\nto be ready for battle.\fLet's wait till later."),
}

-- src/item_use.c:712
VsSeeker.EXCLUDED_PRET_MAPS = { "ViridianForest", "MtEmber_Exterior", "ThreeIsland_BerryForest", "SixIsland_PatternBush" }

local RAISE_HAND = {
  [0x4D] = true,
  [0x4E] = true,
  [0x4F] = true,
}

-- src/vs_seeker.c:1132
local RAISE_HAND_AND_JUMP_GFX = {
  [17] = true, [18] = true, [19] = true, [20] = true, [22] = true, [23] = true,
  [24] = true, [25] = true, [26] = true, [28] = true, [29] = true, [30] = true,
  [37] = true, [39] = true, [40] = true, [41] = true, [42] = true, [45] = true,
  [46] = true, [54] = true, [56] = true, [62] = true,
}
local RAISE_HAND_AND_SWIM_GFX = { [36] = true, [43] = true, [44] = true }

local FACE_TYPE_BY_FACING = { up = 0x07, down = 0x08, left = 0x09, right = 0x0A }

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function runtimeSession()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function objectsMod()
  return package.loaded["src.core.game3.objects"] or require("src.core.game3.objects")
end

function VsSeeker.isRaiseHand(mt)
  return RAISE_HAND[tonumber(mt) or -1] == true
end

function VsSeeker.faceTypeFor(facing)
  return FACE_TYPE_BY_FACING[facing or "down"] or VsSeeker.MOVEMENT_TYPE_FACE_DOWN
end

function VsSeeker.state(session)
  session = session or runtimeSession()
  if not session then return { steps = 0, charging = 0, rematches = {} } end
  local s = session.vsSeeker
  if type(s) ~= "table" then
    s = {}
    session.vsSeeker = s
  end
  s.steps = tonumber(s.steps) or 0
  s.charging = tonumber(s.charging) or 0
  if type(s.rematches) ~= "table" then s.rematches = {} end
  return s
end

function VsSeeker.store(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then return Space.store end
  session = session or runtimeSession()
  if session then
    session.flags = session.flags or {}
    session.vars = session.vars or {}
    return { flags = session.flags, vars = session.vars }
  end
  return nil
end

local function getFlag(id, st)
  return Flags.getFlag(st or VsSeeker.store(), nil, id)
end

local function setFlag(id, on, st)
  st = st or VsSeeker.store()
  if st then Flags.setFlag(st, nil, id, on) end
end

local function fought(trainerId, st)
  return getFlag(Flags.trainerFlagId(trainerId), st)
end

function VsSeeker.getRematch(s, localId)
  local v = s.rematches[tonumber(localId) or -1] or s.rematches[tostring(localId)]
  return tonumber(v) or 0
end

local function setRematch(s, localId, v)
  localId = tonumber(localId) or 0
  s.rematches[tostring(localId)] = nil
  s.rematches[localId] = (v and v ~= 0) and v or nil
end

function VsSeeker.getBattery(session)
  return VsSeeker.state(session).steps
end

function VsSeeker.setBattery(session, charge)
  local s = VsSeeker.state(session)
  s.steps = math.min(VsSeeker.MAX_CHARGE, math.max(0, math.floor(tonumber(charge) or 0)))
end

-- src/vs_seeker.c:1209
function VsSeeker.clearAllRematchStates(session)
  VsSeeker.state(session).rematches = {}
end

-- src/vs_seeker.c:664
function VsSeeker.onStep(session, st)
  local s = VsSeeker.state(session)
  local Bag = require("src.core.game3.bag")
  if session and session.bag and Bag.has(session.bag, VsSeeker.ITEM_VS_SEEKER, 1) then
    if s.steps < VsSeeker.MAX_CHARGE then s.steps = s.steps + 1 end
  end
  st = st or VsSeeker.store(session)
  if getFlag(VsSeeker.FLAG_SYS_VS_SEEKER_CHARGING, st) then
    if s.charging < VsSeeker.MAX_CHARGE then s.charging = s.charging + 1 end
    if s.charging == VsSeeker.MAX_CHARGE then
      setFlag(VsSeeker.FLAG_SYS_VS_SEEKER_CHARGING, false, st)
      s.charging = 0
      s.rematches = {}
      return true
    end
  end
  return false
end

-- src/vs_seeker.c:1235
function VsSeeker.nextAvailable(trainerId, st)
  local ri = Data.byBase[tonumber(trainerId) or -1]
  if not ri then return 0, nil end
  local row = Data.REMATCHES[ri]
  for j = 1, Data.MAX_REMATCH_PARTIES - 1 do
    local id = row[j + 1]
    if id == nil or id == Data.TRAINER_NONE then return j - 1, ri end
    if id ~= Data.SKIP and not fought(id, st) then return j, ri end
  end
  return Data.MAX_REMATCH_PARTIES - 1, ri
end

-- src/vs_seeker.c:1002
local function stepDownTier(row, j)
  j = j - 1
  while j ~= 0 do
    if row[j + 1] ~= Data.SKIP then return j end
    j = j - 1
  end
  return 0
end

-- src/vs_seeker.c:1075
function VsSeeker.rematchTrainerId(trainerId, st)
  local j, ri = VsSeeker.nextAvailable(trainerId, st)
  if j == 0 then return 0 end
  local row = Data.REMATCHES[ri]
  local tier = VsSeeker.TIER_FLAGS[j]
  if tier and not getFlag(tier, st) then
    j = stepDownTier(row, j)
  end
  return row[j + 1] or 0
end

-- src/vs_seeker.c:1013
function VsSeeker.shouldTryRematchBattle(opponentA, lastTalked, st, session)
  local ri = Data.byBase[tonumber(opponentA) or -1]
  if not ri then return false end
  if VsSeeker.getRematch(VsSeeker.state(session), lastTalked) ~= 0 then return true end
  return fought(Data.REMATCHES[ri][1], st)
end

-- src/vs_seeker.c:1086
function VsSeeker.isTrainerReadyForRematch(opponentA, lastTalked, session)
  if not Data.byAny[tonumber(opponentA) or -1] then return false end
  return VsSeeker.getRematch(VsSeeker.state(session), lastTalked) ~= 0
end

-- src/vs_seeker.c:1047
function VsSeeker.clearRematchStateOfLastTalked(lastTalked, opponentA, st, session)
  setRematch(VsSeeker.state(session), lastTalked, 0)
  setFlag(Flags.trainerFlagId(opponentA), true, st)
end

-- src/vs_seeker.c:1113
function VsSeeker.randomFaceType()
  local r = Rng.Random() % 4
  if r == 0 then return VsSeeker.MOVEMENT_TYPE_FACE_UP end
  if r == 2 then return VsSeeker.MOVEMENT_TYPE_FACE_LEFT end
  if r == 3 then return VsSeeker.MOVEMENT_TYPE_FACE_RIGHT end
  return VsSeeker.MOVEMENT_TYPE_FACE_DOWN
end

function VsSeeker.runningBehavior(graphicsId)
  graphicsId = tonumber(graphicsId) or -1
  if RAISE_HAND_AND_JUMP_GFX[graphicsId] then return VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_JUMP end
  if RAISE_HAND_AND_SWIM_GFX[graphicsId] then return VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_SWIM end
  return VsSeeker.MOVEMENT_TYPE_RAISE_HAND_AND_STOP
end

local function templateTrainerId(def, eo)
  if def and def.trainerId then return tonumber(def.trainerId) end
  local okT, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
  if not okT then return nil end
  return TrainerSight.getTrainerId(eo or { def = def, scriptKey = def and def.scriptKey })
end

local function isSane(eo)
  return eo ~= nil and eo.visible ~= false and not eo.hidden
end

local function trainerTemplates(Objects)
  local out = {}
  for _, def in ipairs(Objects._defs or {}) do
    local tt = tonumber(def.trainerType) or 0
    local lid = tonumber(def.localId or def.index) or 0
    if (tt == 1 or tt == 3) and lid > 0 then
      out[#out + 1] = { def = def, localId = lid, eo = Objects._byId and Objects._byId[lid] }
    end
  end
  return out
end

-- src/vs_seeker.c:806
function VsSeeker.gather(Objects)
  Objects = Objects or objectsMod()
  local infos = {}
  for _, t in ipairs(trainerTemplates(Objects)) do
    local eo = t.eo
    infos[#infos + 1] = {
      localId = t.localId,
      trainerIdx = templateTrainerId(t.def, eo) or 0,
      x = eo and eo.cellX or 0,
      y = eo and eo.cellY or 0,
      graphicsId = tonumber(t.def.graphicsId or t.def.graphics) or 0,
      sane = isSane(eo),
    }
  end
  return infos
end

-- src/vs_seeker.c:1217
function VsSeeker.isVisible(info, px, py)
  if not info.sane then return false end
  return math.abs((info.x or 0) - px) <= 7 and math.abs((info.y or 0) - py) <= 5
end

-- src/vs_seeker.c:852
function VsSeeker.canUse(infos, px, py, s, st)
  if s.steps ~= VsSeeker.MAX_CHARGE then
    return VsSeeker.NOT_CHARGED, VsSeeker.MAX_CHARGE - s.steps
  end
  for _, info in ipairs(infos) do
    if VsSeeker.isVisible(info, px, py) then
      if not fought(info.trainerIdx, st) or VsSeeker.nextAvailable(info.trainerIdx, st) ~= 0 then
        return VsSeeker.CAN_USE
      end
    end
  end
  return VsSeeker.NO_ONE_IN_RANGE
end

-- src/vs_seeker.c:1285
local function curResponse(infos, idx, trainerIdx, responders, px, py)
  for i = 1, idx - 1 do
    local other = infos[i]
    if VsSeeker.isVisible(other, px, py) and other.trainerIdx == trainerIdx then
      for _, r in ipairs(responders) do
        if r.trainerIdx == other.trainerIdx then return RESP_YES end
      end
      return RESP_NO
    end
  end
  return RESP_RAND
end

-- src/vs_seeker.c:869
function VsSeeker.computeResponse(infos, px, py, s, st)
  local actions, responders = {}, {}
  local unfought, wants = false, false
  for i, info in ipairs(infos) do
    if VsSeeker.isVisible(info, px, py) then
      local tid = info.trainerIdx
      if not fought(tid, st) then
        actions[#actions + 1] = { localId = info.localId, movement = VsSeeker.MOVEMENT_UNFOUGHT }
        unfought = true
      else
        local j = VsSeeker.nextAvailable(tid, st)
        if j == 0 then
          actions[#actions + 1] = { localId = info.localId, movement = VsSeeker.MOVEMENT_NO_REMATCH }
        else
          local rval = Rng.Random() % 100
          local resp = curResponse(infos, i, tid, responders, px, py)
          if resp == RESP_YES then
            rval = 100
          elseif resp == RESP_NO then
            rval = 0
          end
          if rval < 30 then
            actions[#actions + 1] = { localId = info.localId, movement = VsSeeker.MOVEMENT_NO_REMATCH }
          else
            setRematch(s, info.localId, j)
            actions[#actions + 1] = { localId = info.localId, movement = VsSeeker.MOVEMENT_REMATCH, rematch = true }
            responders[#responders + 1] = { trainerIdx = tid, behavior = VsSeeker.runningBehavior(info.graphicsId) }
            wants = true
          end
        end
      end
    end
  end
  if wants then
    se(SE_PIN)
    setFlag(VsSeeker.FLAG_SYS_VS_SEEKER_CHARGING, true, st)
    s.charging = 0
    return VsSeeker.RESPONSE_FOUND_REMATCHES, actions, responders
  end
  if unfought then
    return VsSeeker.RESPONSE_UNFOUGHT_TRAINERS, actions, responders
  end
  return VsSeeker.RESPONSE_NO_RESPONSE, actions, responders
end

-- src/vs_seeker.c:1305
function VsSeeker.startAllRespondantIdleMovements(infos, responders, s, st, Objects)
  Objects = Objects or objectsMod()
  for _, r in ipairs(responders) do
    for _, info in ipairs(infos) do
      if info.trainerIdx == r.trainerIdx then
        if info.sane and Objects.setTrainerMovementType then
          Objects.setTrainerMovementType(info.localId, r.behavior)
        end
        if Objects.overrideTemplateMovementType then
          Objects.overrideTemplateMovementType(info.localId, r.behavior)
        end
        setRematch(s, info.localId, (VsSeeker.nextAvailable(info.trainerIdx, st)))
      end
    end
  end
end

-- src/vs_seeker.c:636
function VsSeeker.resetObjectMovementAfterChargeComplete(Objects)
  Objects = Objects or objectsMod()
  for _, t in ipairs(trainerTemplates(Objects)) do
    local mt = Objects.templateMovementType and Objects.templateMovementType(t.localId)
      or tonumber(t.def.movementType)
    if VsSeeker.isRaiseHand(mt) then
      local face = VsSeeker.randomFaceType()
      if isSane(t.eo) and Objects.setTrainerMovementType then
        Objects.setTrainerMovementType(t.localId, face)
      end
      if Objects.overrideTemplateMovementType then
        Objects.overrideTemplateMovementType(t.localId, face)
      end
    end
  end
end

-- src/vs_seeker.c:693
function VsSeeker.mapReset(session, st, Objects)
  local s = VsSeeker.state(session)
  setFlag(VsSeeker.FLAG_SYS_VS_SEEKER_CHARGING, false, st or VsSeeker.store(session))
  s.charging = 0
  s.rematches = {}
  Objects = Objects or package.loaded["src.core.game3.objects"]
  if not Objects then return end
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects._byId and Objects._byId[lid]
    if eo and VsSeeker.isRaiseHand(eo.movementType) then
      local face = VsSeeker.randomFaceType()
      if Objects.setTrainerMovementType then
        Objects.setTrainerMovementType(lid, face)
      end
    end
  end
end

-- src/vs_seeker.c:937
function VsSeeker.clearRematchStateByTrainerId(opponentA, selectedLocalId, st, session, Objects)
  local ri = Data.byAny[tonumber(opponentA) or -1]
  if not ri then return end
  Objects = Objects or package.loaded["src.core.game3.objects"]
  if not Objects then return end
  local s = VsSeeker.state(session)
  selectedLocalId = tonumber(selectedLocalId) or -1
  for _, t in ipairs(trainerTemplates(Objects)) do
    local tid = templateTrainerId(t.def, t.eo)
    if tid and Data.byAny[tid] == ri then
      Rng.Random()
      local eo = t.eo
      local faceType = VsSeeker.faceTypeFor(eo and eo.facing)
      if Objects.overrideTemplateMovementType then
        Objects.overrideTemplateMovementType(t.localId, faceType)
      end
      setRematch(s, t.localId, 0)
      if eo and Objects.setTrainerMovementType then
        Objects.setTrainerMovementType(t.localId,
          t.localId == selectedLocalId and faceType or VsSeeker.MOVEMENT_TYPE_FACE_DOWN)
      end
    end
  end
end

function VsSeeker.mapAllowed(mapId, mapType)
  mapType = tonumber(mapType) or 0
  if mapType ~= 1 and mapType ~= 2 and mapType ~= 3 then return false end
  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  for _, pret in ipairs(VsSeeker.EXCLUDED_PRET_MAPS) do
    if mapId == pret then return false end
    if okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine(pret) == mapId then return false end
  end
  return true
end

function VsSeeker.currentMapType(session)
  local mapId = session and session.map
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and (Map.current == nil or Map.current == mapId) and Map.currentDef() or nil
  if not (def and def.mapType) and mapId then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.map then
      local okM, d = pcall(Dataset.map, mapId)
      if okM and d then def = d end
    end
  end
  return def and tonumber(def.mapType) or 0
end

-- src/item_use.c:712
function VsSeeker.canUseHere(session)
  return VsSeeker.mapAllowed(session and session.map, VsSeeker.currentMapType(session))
end

-- src/strings.c:188
function VsSeeker.notTimeText(session)
  local name = tostring((session and (session.name or session.playerName)) or "RED")
  return Strings("OAK: %s!\nThis isn't the time to use that!", name)
end

local function fieldLock(on)
  local Field = package.loaded["src.core.game3.field"]
  if not Field then return end
  if on then Field.lock() else Field.unlock() end
end

local function showMessage(game, text, done)
  fieldLock(true)
  local Hud = package.loaded["src.ui.game3.hud"] or require("src.ui.game3.hud")
  Hud.openMessage(game, text, {
    done = function()
      fieldLock(false)
      if done then done() end
    end,
  })
end

local function playerCoords()
  local Player = package.loaded["src.core.game3.player"]
  if not Player then return 0, 0 end
  if Player.moving and Player.targetX then return Player.targetX, Player.targetY end
  return Player.cellX or 0, Player.cellY or 0
end

local function freezeAll(Objects)
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects._byId[lid]
    if eo then eo.frozen = true end
  end
end

local function unfreezeAll(Objects)
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects._byId[lid]
    if eo and not eo.scriptBusy then eo.frozen = false end
  end
end

local function queue(ev)
  local StepEvents = package.loaded["src.core.game3.step_events"] or require("src.core.game3.step_events")
  StepEvents.queueEvent(ev)
end

-- src/vs_seeker.c:745
function VsSeeker.use(session, game, onDone)
  session = session or runtimeSession()
  local st = VsSeeker.store(session)
  local s = VsSeeker.state(session)
  local Objects = objectsMod()
  local infos = VsSeeker.gather(Objects)
  local px, py = playerCoords()
  local code, need = VsSeeker.canUse(infos, px, py, s, st)
  if code == VsSeeker.NOT_CHARGED then
    showMessage(game, Strings(VsSeeker.TEXT.notCharged, need), onDone)
    return false, code
  elseif code == VsSeeker.NO_ONE_IN_RANGE then
    showMessage(game, Strings(VsSeeker.TEXT.noTrainers), onDone)
    return false, code
  end

  pcall(function()
    local Items = require("src.core.game3.items")
    require("src.core.game3.quest_log_recorder").event(session, "UsedTheItem",
      { Items.displayName(VsSeeker.ITEM_VS_SEEKER) })
  end)

  local seq = { t = 0, finished = false }
  local function finish()
    seq.finished = true
    unfreezeAll(Objects)
    fieldLock(false)
    if seq.evDone then seq.evDone() end
    if onDone then onDone(true, seq.response) end
  end

  queue({
    type = "vs_seeker",
    run = function(evDone)
      seq.evDone = evDone
      fieldLock(true)
      freezeAll(Objects)
      local Player = package.loaded["src.core.game3.player"]
      if Player and Player.startFieldMove then Player.startFieldMove(VsSeeker.EFFECT_FRAMES) end
    end,
    tick = function()
      if seq.finished or seq.waitingText then return end
      seq.t = seq.t + 1
      local t = seq.t
      if t == 31 or t == 42 then se(SE_CONTEST_MONS_TURN) end
      if t == VsSeeker.EFFECT_FRAMES then
        s.steps = 0
        local ppx, ppy = playerCoords()
        local response, actions, responders = VsSeeker.computeResponse(infos, ppx, ppy, s, st)
        seq.response, seq.responders = response, responders
        for _, a in ipairs(actions) do
          local eo = Objects._byId[a.localId]
          if eo then eo.frozen = false end
          Objects.applyMovement(a.localId, a.movement, function()
            if seq.finished and eo and not eo.scriptBusy then eo.frozen = false end
          end)
        end
        seq.waitUntil = t + VsSeeker.WAIT_FRAMES
      end
      if seq.waitUntil and t >= seq.waitUntil then
        if seq.response == VsSeeker.RESPONSE_NO_RESPONSE then
          seq.waitingText = true
          local Hud = package.loaded["src.ui.game3.hud"] or require("src.ui.game3.hud")
          Hud.openMessage(game, Strings(VsSeeker.TEXT.notReady), { done = finish })
        else
          if seq.response == VsSeeker.RESPONSE_FOUND_REMATCHES then
            VsSeeker.startAllRespondantIdleMovements(infos, seq.responders, s, st, Objects)
          end
          finish()
        end
      end
    end,
  })
  return true, code
end

-- data/event_scripts.s:1228
function VsSeeker.chargingDoneEvent()
  local Objects = objectsMod()
  local ev = { type = "vs_seeker_charged" }
  ev.run = function(done)
    ev.done = done
  end
  ev.tick = function()
    if not ev.done then return end
    local Player = package.loaded["src.core.game3.player"]
    if Player and Player.moving then return end
    for _, lid in ipairs(Objects._order or {}) do
      local eo = Objects._byId[lid]
      if eo and (eo.moving or (eo.raiseY or 0) ~= 0) then return end
    end
    if Objects.hasActiveTracks and Objects.hasActiveTracks() then return end
    freezeAll(Objects)
    VsSeeker.resetObjectMovementAfterChargeComplete(Objects)
    unfreezeAll(Objects)
    local cb = ev.done
    ev.done = nil
    cb()
  end
  return ev
end

return VsSeeker

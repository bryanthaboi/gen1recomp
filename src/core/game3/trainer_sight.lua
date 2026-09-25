-- Game3 Trainer Line of Sight Engine (FRLG authentic).
-- Handles directional raycast vision, elevation & ledge masking, exclamation bubble,
-- walk-up approach tracking, zero-distance skips, and battle script engagement.

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local ModRuntime = require("src.mods.Runtime")

local TrainerSight = {}

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

local OPPOSITE_FACING = {
  down = "up",
  up = "down",
  left = "right",
  right = "left",
}

-- pret MetatileBehavior ledge jump bytes (MB_JUMP_*)
local LEDGE_BEHAVIORS = {
  [0x38] = true, -- MB_JUMP_SOUTH
  [0x39] = true, -- MB_JUMP_NORTH
  [0x3A] = true, -- MB_JUMP_WEST
  [0x3B] = true, -- MB_JUMP_EAST
  [0xA0] = true, -- MB_JUMP_EAST_IGNORE_SLOPE
  [0xA1] = true, -- MB_JUMP_WEST_IGNORE_SLOPE
  [0xA2] = true, -- MB_JUMP_NORTH_IGNORE_SLOPE
  [0xA3] = true, -- MB_JUMP_SOUTH_IGNORE_SLOPE
}

local function Player()
  return package.loaded["src.core.game3.player"]
    or require("src.core.game3.player")
end

local function Objects()
  return package.loaded["src.core.game3.objects"]
    or require("src.core.game3.objects")
end

local function Collision()
  return package.loaded["src.core.game3.collision"]
    or require("src.core.game3.collision")
end

local function Field()
  return package.loaded["src.core.game3.field"]
    or require("src.core.game3.field")
end

local function Space()
  return package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
end

local function FieldEffects()
  return package.loaded["src.core.game3.field_effects"]
    or require("src.core.game3.field_effects")
end

--- Extract numeric trainer ID from EventObject def or script bytecode.
function TrainerSight.getTrainerId(eo)
  if not eo then return nil end
  if eo.trainerId then return eo.trainerId end
  if eo.def and eo.def.trainerId then
    eo.trainerId = tonumber(eo.def.trainerId)
    return eo.trainerId
  end
  local scriptKey = eo.scriptKey or (eo.def and eo.def.scriptKey)
  if not scriptKey then return nil end
  local Sp = Space()
  local scripts = Sp and Sp.bundle and Sp.bundle.scripts
  local list = scripts and scripts[scriptKey]
  if type(list) == "table" then
    for _, row in ipairs(list) do
      if row.op == "trainerbattle" or row.op == "dotrainerbattle" then
        local tid = tonumber(row.trainer or row[1])
        if tid then
          eo.trainerId = tid
          eo.trainerBattleType = tonumber(row.type) or 0
          return tid
        end
      end
    end
  end
  return nil
end

-- pokefirered/src/trainer_see.c:97
function TrainerSight.isTrainerType(eo)
  if not eo then return false end
  local tt = tonumber(eo.trainerType or (eo.def and eo.def.trainerType)) or 0
  return tt == 1 or tt == 3
end

--- Check if trainer has already been defeated.
function TrainerSight.isDefeated(eo, store, ctx)
  if not eo then return true end
  local tid = TrainerSight.getTrainerId(eo)
  if tid then
    local fid = Flags.trainerFlagId(tid)
    if Flags.getFlag(store, ctx, fid) then
      return true
    end
  end
  -- Check template defeat flag if present
  local flag = eo.flag or (eo.def and (eo.def.flag or eo.def.flagId))
  if flag and flag ~= 0 and flag ~= 0xFFFF and flag ~= 65535 then
    if Flags.getFlag(store, ctx, flag) then
      return true
    end
  end
  return false
end

function TrainerSight.battleType(eo)
  if not eo then return nil end
  if eo.trainerBattleType == nil then
    local Sp = Space()
    local scriptKey = eo.scriptKey or (eo.def and eo.def.scriptKey)
    local list = scriptKey and Sp and Sp.bundle and Sp.bundle.scripts and Sp.bundle.scripts[scriptKey]
    eo.trainerBattleType = false
    for _, row in ipairs(type(list) == "table" and list or {}) do
      if row.op == "trainerbattle" or row.op == "dotrainerbattle" then
        eo.trainerBattleType = tonumber(row.type) or 0
        break
      end
    end
  end
  return eo.trainerBattleType or nil
end

-- pokefirered/src/trainer_see.c:114
function TrainerSight.blockedByDoubles(eo)
  if TrainerSight.battleType(eo) ~= 4 then return false end
  local Party = require("src.core.game3.party")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  return Party.monsStateToDoubles(session and session.party) ~= Party.PLAYER_HAS_TWO_USABLE_MONS
end

--- Test if a metatile behavior byte represents a one-way ledge hop.
local function is_ledge_tile(game, cx, cy)
  local Coll = Collision()
  if Coll.isLedge and Coll.isLedge(cx, cy) then
    return true
  end
  local cellByte = Coll.cell and Coll.cell(cx, cy)
  if cellByte and LEDGE_BEHAVIORS[cellByte] then
    return true
  end
  return false
end

--- Directional line-of-sight raycast verifying elevation, obstacles, ledges, and intermediaries.
-- @return spotted (bool), dist (number)
function TrainerSight.checkLineOfSight(eo, P, game)
  if not eo or not P then return false, 0 end
  local facing = eo.facing or "down"
  local d = DELTA[facing]
  if not d then return false, 0 end

  -- src/trainer_see.c:151
  local ex = eo.moving and eo.targetX or eo.cellX
  local ey = eo.moving and eo.targetY or eo.cellY
  local px, py = P.cellX, P.cellY
  local dx, dy = d[1], d[2]
  local dist = 0

  if dx ~= 0 then
    if py ~= ey then return false, 0 end
    if (px - ex) * dx <= 0 then return false, 0 end
    dist = math.abs(px - ex)
  elseif dy ~= 0 then
    if px ~= ex then return false, 0 end
    if (py - ey) * dy <= 0 then return false, 0 end
    dist = math.abs(py - ey)
  end

  local sight = tonumber(eo.sight or (eo.def and (eo.def.sight or eo.def.trainerRange))) or 0
  if dist < 1 or dist > sight then
    return false, 0
  end

  local Coll = Collision()
  local Objs = Objects()
  local eoElev = tonumber(eo.currentElevation) or 0
  local mapDef = eo.mapDef or Coll._mapDef

  -- pokefirered/src/trainer_see.c:225
  if Objs.elevationsCompatible and not Objs.elevationsCompatible(eoElev, P.currentElevation) then
    return false, 0
  end
  if Coll.elevationMismatchOn and Coll.elevationMismatchOn(mapDef, eoElev, px, py) then
    return false, 0
  end

  -- Raycast intermediate tiles strictly between trainer and player
  for step = 1, dist - 1 do
    local cx = ex + dx * step
    local cy = ey + dy * step
    local fromX = ex + dx * (step - 1)
    local fromY = ey + dy * (step - 1)

    -- 1. Collision check: must be passable along raycast direction
    if Coll.canEnter and not Coll.canEnter(game, cx, cy, { fromX = fromX, fromY = fromY, dir = facing, elevation = eoElev }) then
      return false, 0
    end
    -- pokefirered/src/trainer_see.c:214
    if Coll.elevationMismatchOn and Coll.elevationMismatchOn(mapDef, eoElev, cx, cy) then
      return false, 0
    end

    -- 2. Ledge masking: line of sight cannot penetrate one-way ledge boundaries
    if is_ledge_tile(game, cx, cy) then
      return false, 0
    end

    -- 3. Intermediary NPCs block vision
    if Objs.blocks and Objs.blocks(cx, cy, eo.localId, eoElev) then
      return false, 0
    end
    local other = Objs.at and Objs.at(cx, cy)
    if other and (not Objs.elevationsCompatible or Objs.elevationsCompatible(eoElev, other.currentElevation)) then
      return false, 0
    end
  end

  -- Check player tile for ledge boundary
  if is_ledge_tile(game, px, py) then
    return false, 0
  end

  return true, dist
end

--- Engage trainer encounter: play '!' exclamation bubble, walk up (or skip if dist == 1), and launch script.
function TrainerSight.engage(game, eo, dist)
  local F = Field()
  local P = Player()
  local Objs = Objects()
  local Sp = Space()
  local Fx = FieldEffects()

  -- 1. Strictly lock overworld state immediately
  F.locked = true
  eo.frozen = true
  eo.scriptBusy = true

  -- 2. Turn trainer to face player directly
  local playerFacing = OPPOSITE_FACING[eo.facing] or "up"

  -- 3. Play encounter music immediately when trainer spots player (pret PlayTrainerEncounterMusic / EventScript_DoTrainerBattleFromApproach)
  local tid = TrainerSight.getTrainerId(eo)
  local okT, Trainers = pcall(require, "src.core.game3.scripting.trainers")
  -- pokefirered/src/trainer_see.c:105
  if ModRuntime.wants("world.trainer_engaged") then
    local info = okT and Trainers and tid and Trainers.info and Trainers.info(tid) or nil
    local Map = package.loaded["src.core.game3.map"]
    ModRuntime.emit("world.trainer_engaged", {
      npc = eo, trainerClass = info and info.class, partyIndex = tid, trainerId = tid,
      mapId = Map and Map.current, sight = { distance = dist, facing = eo.facing },
    })
  end
  local musicId = okT and Trainers and Trainers.getEncounterMusic and Trainers.getEncounterMusic(tid)
  if not musicId then
    musicId = 285 -- MUS_ENCOUNTER_BOY fallback
  end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSong then
    Audio.playSong(musicId)
  end

  -- 4. Play exclamation animation and sound effect SE_PIN (21)
  Fx.startExclamation(eo, function()
    local scriptKey = eo.scriptKey or (eo.def and eo.def.scriptKey)

    local function finishEngagement()
      P.facing = playerFacing
      -- pokefirered/src/trainer_see.c:349-351 SetTrainerMovementType, OverrideMovementTypeForObjectEvent, OverrideTemplateCoordsForObjectEvent
      local faceMt = ({ down = 0x08, up = 0x07, left = 0x09, right = 0x0A })[eo.facing] or 0x08
      if Objs.setTrainerMovementType then
        Objs.setTrainerMovementType(eo, faceMt)
      else
        eo.movementType = faceMt
        eo.movement = "STAY"
        eo.range = (eo.facing or "down"):upper()
      end
      if Objs.overrideTemplateMovementType then
        Objs.overrideTemplateMovementType(eo.localId, faceMt)
      end
      eo.homeX = eo.cellX
      eo.homeY = eo.cellY
      if eo.def then
        eo.def.movementType = faceMt
        eo.def.movement = "STAY"
        eo.def.x = eo.cellX
        eo.def.y = eo.cellY
        eo.def.range = (eo.facing or "down"):upper()
      end
      if Objs.rememberPerm and Objs._mapId then
        Objs.rememberPerm(Objs._mapId, eo.localId, {
          x = eo.cellX,
          y = eo.cellY,
          movementType = faceMt,
          facing = eo.facing,
        })
      end
      eo.frozen = false
      eo.scriptBusy = false
      F.locked = false
      if scriptKey then
        local dirs = { down = 1, up = 2, left = 3, right = 4 }
        local facingDir = dirs[P.facing] or 1
        if Sp and Sp.startScript then
          Sp.startScript(scriptKey, eo.localId, facingDir)
        elseif Sp and Sp.runScript then
          local Runtime = package.loaded["src.core.game3.runtime"]
          local mod = Runtime and Runtime._mod
          local g = game or (Runtime and Runtime._game)
          local world = g and (g.overworld or g.world)
          Sp.runScript(mod, scriptKey, g, world, eo.localId)
        end
      end
    end

    -- Walk-up Approach Tracking: walk dist - 1 steps toward player, or skip if adjacent (dist == 1)
    local walkSteps = dist - 1
    if walkSteps <= 0 then
      finishEngagement()
    else
      local actions = {}
      for _ = 1, walkSteps do
        actions[#actions + 1] = { kind = "step", dir = eo.facing }
      end
      Objs.startTrack(eo.localId, actions, function()
        finishEngagement()
      end)
    end
  end)
end

--- Main line of sight check.
-- @param game game instance
-- @param specificTrainer optional specific EventObject to check (e.g. from spinning NPC turn update)
-- @return boolean true if an encounter was triggered
function TrainerSight.check(game, specificTrainer)
  local F = Field()
  if F.locked then return false end

  local P = Player()
  if P.moving then return false end

  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return false end

  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return false end

  local Sp = Space()
  if Sp and Sp.vm and Sp.vm.isRunning and Sp.vm:isRunning() then return false end

  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() then return false end

  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then return false end

  local store = (Sp and Sp.store) or Flags.newStore()
  local ctx = (Sp and Sp.vm and Sp.vm.ctx) or Ctx.new()

  local Objs = Objects()

  if specificTrainer then
    local eo = specificTrainer
    -- src/trainer_see.c:94
    if Objs.find(eo.localId) ~= eo then return false end
    if eo.visible and not eo.hidden and not eo.scriptBusy and not eo.frozen then
      local sight = tonumber(eo.sight or (eo.def and (eo.def.sight or eo.def.trainerRange))) or 0
      if sight > 0 and TrainerSight.isTrainerType(eo)
        and not TrainerSight.isDefeated(eo, store, ctx) then
        local spotted, dist = TrainerSight.checkLineOfSight(eo, P, game)
        if spotted and not TrainerSight.blockedByDoubles(eo) then
          TrainerSight.engage(game, eo, dist)
          return true
        end
      end
    end
    return false
  end

  -- Simultaneous Spot Prioritization: iterate candidates in strict ascending localId order
  local order = Objs._order or {}
  for _, lid in ipairs(order) do
    local eo = Objs.find(lid)
    if eo and eo ~= P and eo.visible and not eo.hidden and not eo.scriptBusy and not eo.frozen then
      local sight = tonumber(eo.sight or (eo.def and (eo.def.sight or eo.def.trainerRange))) or 0
      if sight > 0 and TrainerSight.isTrainerType(eo)
        and not TrainerSight.isDefeated(eo, store, ctx) then
        local spotted, dist = TrainerSight.checkLineOfSight(eo, P, game)
        if spotted and not TrainerSight.blockedByDoubles(eo) then
          -- Immediately engage and break iterator to suppress any other simultaneous spots
          TrainerSight.engage(game, eo, dist)
          return true
        end
      end
    end
  end

  return false
end

return TrainerSight

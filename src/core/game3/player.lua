-- Game3 independent player avatar (walk / run with B / facing / ledge hop).
-- Owns cell + pixel motion; does not call World:step or Player:tryMove.
-- Collision via game3.collision (owned COLL_* grid from extract bake).

local Collision = require("src.core.game3.collision")
local ModRuntime = require("src.mods.Runtime")

local Player = {}

local CELL = 16
local WALK_FRAMES = 16
local RUN_FRAMES = 8
-- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
local RUN_SLOW_FRAMES = 11
local BIKE_FRAMES = 4
local TURN_FRAMES = 4
-- pokefirered/include/constants/metatile_behaviors.h:128
local MB_CYCLING_ROAD_PULL_DOWN = 0xD0
local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1
-- pokefirered/src/event_object_movement.c:8905 sSpeedFasterStepFuncs
local FASTER_FRAMES = 4
-- pret Jump2 / DoJumpSpriteMovement: JUMP_DISTANCE_FAR = 32 frames.
local JUMP_FRAMES = 32
-- pret sJumpY_High (event_object_movement.c). Jump2 indexes with sTimer >> 1.
local JUMP_Y_HIGH = {
  -4, -6, -8, -10, -11, -12, -12, -12,
  -11, -10, -9, -8, -6, -4, 0, 0,
}

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

-- pokefirered/src/data/object_events/object_event_anims.h:556
local SPIN_CYCLE = { "down", "right", "up", "left" }
local SPIN_PHASE = { down = 1, right = 4, up = 3, left = 2 }

Player.cellX = 0
Player.cellY = 0
Player.px = 0
Player.py = 0
Player.facing = "down"
Player.moving = false
Player.progress = 0
Player.stepFrames = WALK_FRAMES
Player.targetX = 0
Player.targetY = 0
Player.turnTimer = 0
Player.turnArmed = true
Player.stepFlip = false
Player.animClock = 0
Player.running = false
Player.jumping = false
Player.surfHopping = false
Player.dismounting = false
Player.fieldMoveAnim = 0
Player.spriteXOffset = 0
Player.spriteYOffset = 0
Player.biking = false
Player.surfing = false
-- pokefirered/src/field_player_avatar.c:1679
Player.fishing = false
Player.prevCellX = 0
Player.prevCellY = 0
-- pokefirered/src/field_player_avatar.c:325
Player.animDisabled = false
-- pokefirered/src/event_object_movement.c:7741
Player.spinning = false
Player.spinStart = "down"
-- pokefirered/src/field_fadetransition.c:860
Player.walkInPlace = false
Player.walkInPlaceFast = false
Player.visible = true
Player.elevation = 3
Player._logged = false

function Player.setVisible(vis)
  Player.visible = (vis ~= false)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local g = Runtime and (Runtime._game or (Runtime.getGame and Runtime.getGame()))
  local world = g and (g.overworld or g.world)
  if world and world.player then
    world.player.visible = Player.visible
    world.player.hidden = not Player.visible
  end
end

function Player.isVisible()
  return Player.visible ~= false
end

local function log(msg)

  print("[game3/player] " .. tostring(msg))
end

local function dirs_from_input(input)
  if not input then return nil end
  -- Prefer last-pressed feel: check wasPressed first, else held.
  local order = { "down", "up", "left", "right" }
  for _, d in ipairs(order) do
    if input.wasPressed and input:wasPressed(d) then return d end
  end
  for _, d in ipairs(order) do
    if input.isDown and input:isDown(d) then return d end
  end
  return nil
end

function Player.reset(x, y, facing)
  Player.cellX = tonumber(x) or 0
  Player.cellY = tonumber(y) or 0
  Player.px = Player.cellX * CELL
  Player.py = Player.cellY * CELL
  Player.facing = facing or "down"
  Player.elevation = 3
  Player.moving = false
  Player.progress = 0
  Player.stepFrames = WALK_FRAMES
  Player.targetX = Player.cellX
  Player.targetY = Player.cellY
  Player.turnTimer = 0
  Player.turnArmed = true
  Player.stepFlip = false
  Player.animClock = 0
  Player.running = false
  Player.jumping = false
  Player.spriteXOffset = 0
  Player.spriteYOffset = 0
  Player.biking = false
  Player.prevCellX = Player.cellX
  Player.prevCellY = Player.cellY
  Player.animDisabled = false
  Player.spinning = false
  Player.walkInPlace = false
  Player.walkInPlaceFast = false
  if not Player._logged then
    log(string.format("avatar ready @ %d,%d %s",
      Player.cellX, Player.cellY, Player.facing))
    Player._logged = true
  end
end

function Player.syncFromSession(session)
  if not session then return end
  Player.reset(session.x, session.y, session.facing)
  if session.elevation ~= nil then
    Player.elevation = tonumber(session.elevation) or 3
  end
end

function Player.syncFromHost(game)
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if not p then return end
  Player.reset(p.cellX or p.x, p.cellY or p.y, p.facing or "down")
  if p.elevation ~= nil then
    Player.elevation = tonumber(p.elevation) or 3
  end
end

--- Write avatar coords into save.position (ferry / host save). No host entity mirror.
function Player.syncSavePosition(game)
  local save = game and game.save
  if not (save and save.position) then return end
  save.position.x = Player.cellX
  save.position.y = Player.cellY
  save.position.facing = Player.facing
  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session and session.map then
    save.position.map = session.map
  end
end

--- Optional: mirror onto host player for heal-machine anim / leftover host reads.
-- Prefer syncSavePosition; full mirror is not required for talk/field.
function Player.syncToHost(game)
  Player.syncSavePosition(game)
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if not p then return end
  p.cellX = Player.cellX
  p.cellY = Player.cellY
  p.px = Player.px
  p.py = Player.py
  p.facing = Player.facing
  p.moving = Player.moving
  p.stepFlip = Player.stepFlip
  p.animClock = Player.animClock
  p.turnTimer = Player.turnTimer
  if p.stepFrames ~= nil then p.stepFrames = Player.stepFrames end
  if p.progress ~= nil then p.progress = Player.progress end
  if p.targetX ~= nil then p.targetX = Player.targetX end
  if p.targetY ~= nil then p.targetY = Player.targetY end
  p.jumping = Player.jumping
  p.spriteYOffset = Player.spriteYOffset or 0
end

local function walkInPlaceFrames()
  return Player.walkInPlaceFast and RUN_FRAMES or WALK_FRAMES
end

-- pokefirered/src/field_effect.c:1215 FallWarpEffect_4
local function warp_owns_sprite()
  local Warp = package.loaded["src.core.game3.warp"]
  return (Warp and Warp.isBusy and Warp.isBusy()) == true
end

function Player.walkPhase()
  -- pokefirered/src/field_player_avatar.c:325
  if Player.animDisabled then return 0 end
  if Player.turnTimer > 0 then return 1 end
  if not Player.moving then
    if not Player.walkInPlace then return 0 end
    local wf = walkInPlaceFrames()
    local wp = Player.animClock % wf
    local wmid = math.floor(wf / 2)
    return (wp >= math.floor(wf / 4) and wp < wmid + math.floor(wf / 4)) and 1 or 0
  end
  local frames = Player.stepFrames or WALK_FRAMES
  local p = Player.animClock % frames
  local mid = math.floor(frames / 2)
  return (p >= math.floor(frames / 4) and p < mid + math.floor(frames / 4)) and 1 or 0
end

function Player.drawFlip()
  return Player.stepFlip and true or false
end

local SURF_HOP_Y = {
  -2, -4, -6, -8, -9, -10, -10, -9, -8, -6, -4, -2, 0, 0, 0, 0,
}

--- pret DoJumpSpriteMovement y2 for JUMP_DISTANCE_FAR + JUMP_TYPE_HIGH.
function Player.jumpSpriteY()
  if not Player.jumping then return 0 end
  local progress = Player.progress or 0
  if progress < 1 then return 0 end
  if Player.surfHopping or Player.dismounting then
    local idx = math.min(progress, #SURF_HOP_Y)
    return SURF_HOP_Y[idx] or 0
  end
  -- After frame N's Step1, sTimer == N; y2 = sJumpY_High[sTimer >> 1].
  local idx = math.floor((progress - 1) / 2)
  if idx < 0 then return 0 end
  if idx >= #JUMP_Y_HIGH then return 0 end
  return JUMP_Y_HIGH[idx + 1]
end

local function beginStep(tx, ty, run, ledge)
  Player.prevCellX = Player.cellX
  Player.prevCellY = Player.cellY
  Player.moving = true
  Player.progress = 0
  Player.targetX = tx
  Player.targetY = ty
  Player.running = (not ledge) and run and true or false
  Player.jumping = ledge and true or false
  Player.spriteYOffset = 0
  if Player.surfHopping or Player.dismounting then
    Player.stepFrames = 16
    Player.jumping = true
  elseif ledge then
    Player.stepFrames = JUMP_FRAMES
  elseif Player.biking then
    Player.stepFrames = BIKE_FRAMES
    Player.running = true
  else
    Player.stepFrames = run and RUN_FRAMES or WALK_FRAMES
  end
  Player.animClock = 0

  -- pret GroundEffect_StepOnTallGrass when entering a grass cell.
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects then
    if Collision.isGrass and Collision.isGrass(tx, ty) then
      FieldEffects.tallGrassAt(tx, ty, false)
    else
      FieldEffects.leaveTallGrass()
    end
  end
end

function Player.tryMove(dir, game, run)
  if Player.moving then return nil end
  if not DELTA[dir] then return nil end

  if Player.facing ~= dir then
    Player.facing = dir
    if Player.turnArmed then
      Player.turnArmed = false
      Player.turnTimer = TURN_FRAMES
      return "turned"
    end
  end
  if Player.turnTimer > 0 then return nil end

  -- pokefirered/src/field_player_avatar.c:556
  local stair = Collision.isStairWarp
    and Collision.isStairWarp(game, Player.cellX, Player.cellY, dir)
  if stair then
    local Warp = require("src.core.game3.warp")
    if Warp.isBusy() then return "stair_busy" end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local mod = Runtime and Runtime._mod
    local g = game or (Runtime and Runtime._game)
    Warp.startStairWarp(mod, g, stair.destMap, stair.destX, stair.destY, stair.behavior)
    return "stair"
  end

  local d = DELTA[dir]
  local tx = Player.cellX + d[1]
  local ty = Player.cellY + d[2]

  -- pret CheckForPlayerAvatarCollision → ShouldJumpLedge(dest): hop over the
  -- impassable ledge tile when facing matches; otherwise canEnter bumps.
  local lx, ly = Collision.ledgeLanding(game, Player.cellX, Player.cellY, dir)
  if lx then
    beginStep(lx, ly, false, true)
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
    end)
    return "ledge"
  end

  if dir == "up" then
    local doorWarp = Collision.isDoorWarp and Collision.isDoorWarp(game, tx, ty)
    if doorWarp then
      local Warp = require("src.core.game3.warp")
      if not Warp.isBusy() then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        Warp.startDoorEntrance(mod, g, doorWarp.destMap, doorWarp.destX, doorWarp.destY, tx, ty)
        return "door"
      end
      return "door_busy"
    end
  end

  if dir == "down" then
    local exitWarp = Collision.isExitWarp and Collision.isExitWarp(game, Player.cellX, Player.cellY)
    if exitWarp then
      local Warp = require("src.core.game3.warp")
      if not Warp.isBusy() then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        Warp.startDoorExit(mod, g, exitWarp.destMap, exitWarp.destX, exitWarp.destY, Player.cellX, Player.cellY)
        return "exit_door"
      end
      return "door_busy"
    end
  end

  local escWarp = Collision.isEscalatorWarp and Collision.isEscalatorWarp(game, tx, ty, dir)
  if escWarp then
    local Warp = require("src.core.game3.warp")
    if not Warp.isBusy() then
      local Runtime = package.loaded["src.core.game3.runtime"]
      local mod = Runtime and Runtime._mod
      local g = game or (Runtime and Runtime._game)
      Warp.startEscalator(mod, g, escWarp.destMap, escWarp.destX, escWarp.destY, escWarp.escDir, dir, tx, ty)
      return "escalator"
    end
    return "escalator_busy"
  end

  -- pokefirered/src/field_control_avatar.c:825 TryArrowWarp
  if Collision.isArrowWarp
      and Collision.isArrowWarp(game, Player.cellX, Player.cellY, dir) then
    local Warp = require("src.core.game3.warp")
    if Warp.isBusy() then return "arrow_busy" end
    if Collision.tryWarpAt(game, Player.cellX, Player.cellY, dir, { arrow = true }) then
      return "arrow_warp"
    end
  end

  local ok, why = Collision.canEnter(game, tx, ty, {
    fromX = Player.cellX,
    fromY = Player.cellY,
    dir = dir,
    surfing = Player.surfing,
  })

  if not ok then
    if why == "entity" then
      local Space = package.loaded["src.core.game3.scripting.space"]
      local Flags = require("src.core.game3.scripting.flags")
      local FieldMoves = require("src.core.game3.field_moves")
      local isStrengthActive = Space and Space.store and Flags.getFlag(Space.store, nil, FieldMoves.SYS_FLAGS.USE_STRENGTH)
      if isStrengthActive then
        local Objects = require("src.core.game3.objects")
        local obj = Objects.at(tx, ty)
        if obj and (obj.def and (obj.def.graphicsId == FieldMoves.GFX_IDS.PUSHABLE_BOULDER or obj.def.gfx == FieldMoves.GFX_IDS.PUSHABLE_BOULDER)) then
          local canPush, destBx, destBy = FieldMoves.canPushBoulder(obj, dir, function(bx, by)
            return Collision.canEnter(game, bx, by, { fromX = tx, fromY = ty, dir = dir })
          end)
          if canPush then
            obj.cellX = destBx
            obj.cellY = destBy
            obj.px = destBx * CELL
            obj.py = destBy * CELL
            obj.targetX = destBx
            obj.targetY = destBy
            obj.moving = false
            obj.facing = dir
            if obj.def then obj.def.x = destBx; obj.def.y = destBy end
            if ModRuntime.wants("world.boulder_moved") then
              local Map = package.loaded["src.core.game3.map"]
              ModRuntime.emit("world.boulder_moved", {
                mapId = Map and Map.current, npcId = obj.localId, x = destBx, y = destBy,
              })
            end
            beginStep(tx, ty, false, false)
            -- pokefirered/src/field_player_avatar.c:1452
            local Field = require("src.core.game3.field")
            if Field.onBoulderMoved then Field.onBoulderMoved(game, obj, destBx, destBy) end
            return "step"
          end
        end
      end
    end
    if (why == "bounds" or why == "solid" or why == "tile") and Collision.tryWarpAt
        and Collision.tryWarpAt(game, Player.cellX, Player.cellY, dir) then
      return "warp"
    end
    -- Outdoor map connection (Pallet north → Route 1, etc.).
    if why == "bounds" and Collision.tryConnection
        and Collision.tryConnection(game, Player.cellX, Player.cellY, dir, run) then
      return "connection"
    end
    return "blocked", why
  end
  local isDismount = Player.surfing and (not (Collision.isWater and Collision.isWater(tx, ty)))
  if isDismount then
    Player.dismounting = true
  else
    Player.dismounting = false
  end

  beginStep(tx, ty, run, false)
  return "step"
end

-- pokefirered/src/metatile_behavior.c:668 MetatileBehavior_IsCyclingRoadPullDownTile
local function isCyclingRoadPullDown(beh)
  if Collision.isCyclingRoadPullDown then
    return Collision.isCyclingRoadPullDown(beh) == true
  end
  return beh ~= nil and beh >= MB_CYCLING_ROAD_PULL_DOWN
    and beh <= MB_CYCLING_ROAD_PULL_DOWN_GRASS
end

-- pokefirered/src/bike.c:215 GetBikeCollision
local function bikeCanMove(game, dir)
  local d = DELTA[dir]
  if not d then return false end
  return Collision.canEnter(game, Player.cellX + d[1], Player.cellY + d[2], {
    fromX = Player.cellX, fromY = Player.cellY, dir = dir, surfing = Player.surfing,
  }) == true
end

-- pokefirered/src/bike.c:199 BikeTransition_Downhill
local function bikeDownhill(game)
  local lx, ly = Collision.ledgeLanding(game, Player.cellX, Player.cellY, "down")
  if lx then
    Player.facing = "down"
    beginStep(lx, ly, false, true)
    return true
  end
  if not bikeCanMove(game, "down") then return false end
  Player.facing = "down"
  beginStep(Player.cellX, Player.cellY + 1, false, false)
  Player.stepFrames = FASTER_FRAMES
  return true
end

-- pokefirered/src/bike.c:209 BikeTransition_Uphill
local function bikeUphill(game, dir)
  local d = DELTA[dir]
  if not d then return false end
  if not bikeCanMove(game, dir) then return false end
  Player.facing = dir
  beginStep(Player.cellX + d[1], Player.cellY + d[2], false, false)
  Player.stepFrames = WALK_FRAMES
  return true
end

-- pokefirered/src/bike.c:53 BikeInputHandler_Normal
function Player.cyclingRoadPull(game, input, dir)
  if not Player.biking then return false end
  if Player.moving then return false end
  local beh = Collision.behavior and Collision.behavior(Player.cellX, Player.cellY)
  if not isCyclingRoadPullDown(beh) then return false end
  local braking = (input and input.isDown and input:isDown("b")) and true or false
  if not braking then
    -- pokefirered/src/bike.c:65
    if dir == nil or dir == "down" then return bikeDownhill(game) end
    return bikeUphill(game, dir)
  end
  -- pokefirered/src/bike.c:72
  if dir ~= nil then return bikeUphill(game, dir) end
  return false
end

--- Forced step along dir with onDone callback (e.g. exiting door).
function Player.forceStep(dir, onDone)
  if Player.moving then return false end
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  Player._onStepDone = onDone
  beginStep(Player.cellX + d[1], Player.cellY + d[2], false, false)
  return true
end

-- pokefirered/src/field_player_avatar.c:292
function Player.forcedStep(dir, frames, opts)
  if Player.moving then return false end
  local d = DELTA[dir]
  if not d then return false end
  opts = opts or {}
  if not opts.keepFacing then Player.facing = dir end
  Player._onStepDone = nil
  if opts.ledgeX then
    beginStep(opts.ledgeX, opts.ledgeY, false, true)
  else
    local tx, ty = Player.cellX + d[1], Player.cellY + d[2]
    Player.dismounting = Player.surfing
      and (not (Collision.isWater and Collision.isWater(tx, ty))) or false
    beginStep(tx, ty, false, false)
  end
  if frames and not opts.ledgeX and not Player.dismounting then
    Player.stepFrames = frames
  end
  if Player.spinning then Player.spinStart = dir end
  return true
end

--- Forced script step (applymovement localId 0xFF) — skips collision.
function Player.scriptStep(dir, run, slow)
  if Player.moving then return false end
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  beginStep(Player.cellX + d[1], Player.cellY + d[2], run and true or false, false)
  -- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
  if run and slow then Player.stepFrames = RUN_SLOW_FRAMES end
  return true
end

--- Forced script jump (applymovement localId 0xFF) — hops over ledges / gaps.
function Player.scriptJump(dir, distance)
  if Player.moving then return false end
  distance = distance or 1
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
  end)
  beginStep(Player.cellX + d[1] * distance, Player.cellY + d[2] * distance, false, true)
  return true
end

function Player.scriptFace(dir)
  if DELTA[dir] then Player.facing = dir end
end

--- Parabolic hop into water when initiating Surf.
function Player.startSurfing(game, onDone)
  Player.biking = false -- Bike override: clear bike state when using Surf
  Player.running = false
  Player.surfHopping = true
  Player.surfing = false
  Player.dismounting = false
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
  end)
  Player.forceStep(Player.facing, onDone)
end

function Player.startFieldMove(duration)
  Player.fieldMoveAnim = duration or 28
end

local function finishStep(game)
  -- pokefirered/src/event_object_movement.c:7741
  if Player.spinning then Player.facing = Player.spinStart or Player.facing end
  Player.cellX = Player.targetX
  Player.cellY = Player.targetY
  Player.px = Player.cellX * CELL
  Player.py = Player.cellY * CELL
  Player.moving = false
  Player.progress = 0
  Player.stepFlip = not Player.stepFlip
  Player.running = false
  Player.jumping = false
  Player.spriteYOffset = 0
  Player.syncSavePosition(game)

  -- Surf landing / dismount state transitions
  if Player.surfHopping then
    Player.surfHopping = false
    Player.surfing = true
  elseif Player.dismounting then
    Player.dismounting = false
    Player.surfing = false
  elseif Player.surfing then
    local onWater = Collision.isWater and Collision.isWater(Player.cellX, Player.cellY)
    if not onWater then
      Player.surfing = false
    end
  end

  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session then
    session.x, session.y, session.facing = Player.cellX, Player.cellY, Player.facing
  end

  if ModRuntime.wants("world.stepped") then
    local Map = package.loaded["src.core.game3.map"]
    ModRuntime.emit("world.stepped", {
      mapId = (session and session.map) or (Map and Map.current),
      x = Player.cellX, y = Player.cellY,
      tile = Collision.behavior and Collision.behavior(Player.cellX, Player.cellY),
      facing = Player.facing,
    })
  end

  local onDoneCb = Player._onStepDone
  Player._onStepDone = nil
  if onDoneCb then
    onDoneCb()
    return
  end

  local ForcedMovement = package.loaded["src.core.game3.forced_movement"]
    or require("src.core.game3.forced_movement")
  -- pokefirered/src/field_control_avatar.c:136
  local onForcedTile =
    ForcedMovement.isForcedMovementTile(Collision.behavior(Player.cellX, Player.cellY))

  local Field = package.loaded["src.core.game3.field"]
    or require("src.core.game3.field")

  if not onForcedTile then
    -- Evaluate Overworld Step Events (Happiness, VS Seeker, Poison, Egg/Daycare, Repel)
    local StepEvents = package.loaded["src.core.game3.step_events"]
      or require("src.core.game3.step_events")
    if StepEvents and StepEvents.onStepTaken then
      StepEvents.onStepTaken(session, game)
    end

    -- Land-on-warp via owned warp table (mapDef.warps).
    Collision.tryWarpAt(game, Player.cellX, Player.cellY, Player.facing)

    -- Coord events (Oak leave-block, triggers) after landing on the cell.
    if Field.tryCoordEvents then
      Field.tryCoordEvents(game, Player.cellX, Player.cellY)
    end
  end

  -- pokefirered/src/field_control_avatar.c:209
  if not Field.locked then
    local okTs, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
    if okTs and TrainerSight and TrainerSight.check then
      TrainerSight.check(game)
    end
  end

  -- pokefirered/src/field_tasks.c:66
  ForcedMovement.runStepCallback(game, Player.prevCellX, Player.prevCellY)

  -- pokefirered/src/field_player_avatar.c:136
  local Warp = package.loaded["src.core.game3.warp"]
  local warping = (Warp and Warp.isBusy and Warp.isBusy()) and true or false
  if not warping and ForcedMovement.onStepFinished(game) then return end

  -- pokefirered/src/wild_encounter.c:757
  local onGrass = Collision.isGrass and Collision.isGrass(Player.cellX, Player.cellY)
  local onWater = Player.surfing and (Collision.isWater and Collision.isWater(Player.cellX, Player.cellY))
  local okE, Encounters = pcall(require, "src.core.game3.encounters")
  if okE and Encounters and Encounters.onStep and not onForcedTile then
    local Battle = package.loaded["src.core.game3.battle"]
    local busy = (Battle and Battle.isActive and Battle.isActive()) or Field.locked
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
      busy = true
    end
    if not busy then
      local mapId = session and session.map
      if not mapId then
        local Map = package.loaded["src.core.game3.map"]
        mapId = Map and Map.current
      end
      local enc = Encounters.onStep(mapId, nil, { x = Player.cellX, y = Player.cellY })
      if enc then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local BattleBridge = require("src.core.game3.battle_bridge")
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        local okB, errB = BattleBridge.startWild(mod, g, enc, {})
        if not okB then
          print("[game3/encounters] startWild failed: " .. tostring(errB))
        end
      end
    end
  end
  if okE and Encounters and Encounters.noteGrass then
    Encounters.noteGrass(onGrass or onWater)
  end
  if onGrass then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.tallGrassAt then
      FieldEffects.tallGrassAt(Player.cellX, Player.cellY, true)
    end
  end
end

function Player.tick(game)
  if Player.fieldMoveAnim and Player.fieldMoveAnim > 0 then
    Player.fieldMoveAnim = Player.fieldMoveAnim - 1
  end
  if Player.turnTimer > 0 then
    Player.turnTimer = Player.turnTimer - 1
  end
  if not Player.moving then
    -- pokefirered/src/field_fadetransition.c:846
    if Player.walkInPlace then
      Player.animClock = Player.animClock + 1
      if Player.animClock % walkInPlaceFrames() == 0 then
        Player.stepFlip = not Player.stepFlip
      end
    end
    if Player.surfing and not Player.jumping then
      local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
      local clock = (okFx and FieldEffects and FieldEffects._surfClock) or 0
      Player.spriteYOffset = (math.floor(clock / 48) % 2 == 1) and -1 or 0
    elseif not Player.walkInPlace and not warp_owns_sprite() then
      Player.spriteYOffset = 0
    end
    return false
  end
  Player.progress = Player.progress + 1
  Player.animClock = Player.animClock + 1
  local frames = Player.stepFrames or WALK_FRAMES
  local dx = Player.targetX - Player.cellX
  local dy = Player.targetY - Player.cellY
  -- pret Step1: 1px/frame along the move. Ledge Jump2 is 32px over 32 frames.
  local span = math.max(math.abs(dx), math.abs(dy), 1)
  local adv = math.floor(Player.progress * CELL * span / frames)
  Player.px = Player.cellX * CELL + (dx / span) * adv
  Player.py = Player.cellY * CELL + (dy / span) * adv
  if Player.jumping then
    Player.spriteYOffset = Player.jumpSpriteY()
  else
    Player.spriteYOffset = 0
  end
  -- pokefirered/src/data/object_events/object_event_anims.h:556
  if Player.spinning then
    local base = SPIN_PHASE[Player.spinStart] or 1
    local idx = (base - 1 + math.floor((Player.progress - 1) / 2)) % #SPIN_CYCLE
    Player.facing = SPIN_CYCLE[idx + 1]
  end
  if Player.progress >= frames then
    finishStep(game)
    return true
  end
  return false
end

--- pret field_player_avatar: B-dash only with FLAG_SYS_B_DASH (Running Shoes).
function Player.canDash()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.getStore and Space.getStore()
  if not store then
    -- Field not scripted yet — deny dash (shoes not granted).
    return false
  end
  local Flags = require("src.core.game3.scripting.flags")
  return Flags.getFlag(store, nil, Flags.IDS.SYS_B_DASH) == true
end

--- Poll D-pad + B-run when field is free.
function Player.update(game, input)
  Player.tick(game)
  if Player.moving then return end
  if Player.fieldMoveAnim and Player.fieldMoveAnim > 0 then return end

  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return end
  local Fade = package.loaded["src.ui.game3.fade"]
  if Fade and Fade.lockInput then return end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return end
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return end
  local StepEvents = package.loaded["src.core.game3.step_events"]
  if StepEvents and StepEvents.busy and StepEvents.busy() then return end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return
  end

  -- Menu Dismissal Frame Trap & Idle Sight Check: check sight before D-pad input polling
  local okTs, TrainerSight = pcall(require, "src.core.game3.trainer_sight")
  if okTs and TrainerSight and TrainerSight.check then
    if TrainerSight.check(game) then
      return
    end
  end

  local dir = dirs_from_input(input)
  -- pokefirered/src/bike.c:43 MovePlayerOnBike
  if Player.cyclingRoadPull(game, input, dir) then return end
  if not dir then
    Player.turnArmed = true
    return
  end
  local wantRun = input and input.isDown and input:isDown("b")
  local run = Player.biking or (wantRun and Player.canDash())
  Player.tryMove(dir, game, run)
end

return Player

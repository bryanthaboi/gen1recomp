-- Game3 independent player avatar (walk / run with B / facing / ledge hop).
-- Owns cell + pixel motion; does not call World:step or Player:tryMove.
-- Collision via game3.collision (owned COLL_* grid from extract bake).

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Collision = require("src.core.game3.collision")
local ModRuntime = require("src.mods.Runtime")
local WarpArrow = require("src.core.game3.warp_arrow")

local Player = {}

local CELL = 16
local WALK_FRAMES = 16
local RUN_FRAMES = 8
-- pokefirered/src/event_object_movement.c:6163
local WALK_IN_PLACE_SLOW_FRAMES = 32
-- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
local RUN_SLOW_FRAMES = 11
local BIKE_FRAMES = 4
-- pokeemerald/src/event_object_movement.c:5780 MovementAction_WalkInPlaceFastDown_Step0
local TURN_FRAMES = 8
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
Player.stepSerial = 0
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
-- pokefirered/src/field_player_avatar.c:1296
Player.currentElevation = 0
Player._logged = false
-- pokeemerald/include/global.fieldmap.h:288
Player.bikeType = nil
Player.moveDir = "down"
Player.facingLocked = false
Player.action = nil
Player.jumpType = nil
Player.acroAnim = nil

-- pokeemerald/src/event_object_movement.c:8424
local JUMP_Y = {
  high = JUMP_Y_HIGH,
  low = { 0, -2, -3, -4, -5, -6, -6, -6, -5, -5, -4, -3, -2, 0, 0, 0 },
  normal = { -2, -4, -6, -8, -9, -10, -10, -10, -9, -8, -6, -5, -3, -2, 0, 0 },
}

local function rseBike()
  local Bike = package.loaded["src.core.game3.bike"] or lazyReq("src.core.game3.bike")
  return Bike.rse()
end

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

local EMPTY = {}

local function sessionFlags(session)
  local Profile = package.loaded["src.core.game3.profile"] or lazyReq("src.core.game3.profile")
  local Flags = package.loaded["src.core.game3.scripting.flags"] or lazyReq("src.core.game3.scripting.flags")
  local row = Profile.forSession(type(session) == "table" and session.version and session or nil)
  return Flags.forVersion(row.id)
end

local function fieldBlock()
  local Profile = package.loaded["src.core.game3.profile"] or lazyReq("src.core.game3.profile")
  local ok, row = pcall(Profile.forSession)
  return ok and row and row.field or EMPTY
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
  -- Callers pass the destination facing (Map.load, warp, fly, syncFromSession).
  -- An absent or invalid direction keeps the current facing.
  if facing ~= nil and DELTA[facing] then
    Player.facing = facing
  end
  Player.cellX = tonumber(x) or 0
  Player.cellY = tonumber(y) or 0
  Player._scriptedStep = nil
  -- pokeemerald/src/field_player_avatar.c:1402
  WarpArrow.hide()
  Player.px = Player.cellX * CELL
  Player.py = Player.cellY * CELL
  local Collision = package.loaded["src.core.game3.collision"]
  local curElev = Collision and Collision.elevationAt and Collision.elevationAt(Player.cellX, Player.cellY)
  if curElev and curElev ~= 0 and curElev ~= 15 then
    Player.elevation = curElev
  else
    Player.elevation = 3
  end
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
  -- Transient surf state: a reset lands the avatar on its feet, so a warp or
  -- whiteout out of the water must not leave surfing set -- Collision.canEnter
  -- reads Player.surfing and would treat water as walkable on land.
  Player.surfing = false
  Player.underwater = false
  Player.surfHopping = false
  Player.dismounting = false
  Player.prevCellX = Player.cellX
  Player.prevCellY = Player.cellY
  Player.animDisabled = false
  Player.spinning = false
  Player.walkInPlace = false
  Player.walkInPlaceFast = false
  Player.boulderPush = nil
  Player.currentElevation = 0
  Player.moveDir = Player.facing
  Player.facingLocked = false
  Player.fixedPriority = nil
  Player.subpriority = nil
  Player.action = nil
  Player.jumpType = nil
  Player.acroAnim = nil
  local BikeRse = package.loaded["src.core.game3.bike.rse"]
  if BikeRse then BikeRse.clearState(0, 0) end
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
  if session.biking ~= nil then
    Player.biking = (session.biking == true)
  end
  if session.bikeType ~= nil then
    Player.bikeType = session.bikeType
  end
  Player.restoreAvatar(session)
end

-- pokeemerald/src/field_player_avatar.c:1373
function Player.restoreAvatar(state)
  if not state then return end
  Player.underwater = state.underwater == true
  Player.surfing = not Player.underwater and state.surfing == true
  Player.biking = not Player.underwater and not Player.surfing and state.biking == true
  Player.bikeType = state.bikeType
  if state.elevation ~= nil then Player.elevation = tonumber(state.elevation) or 3 end
  Player.surfHopping, Player.dismounting = false, false
end

function Player.syncFromHost(game)
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if not p then return end
  Player.reset(p.cellX or p.x, p.cellY or p.y, p.facing or "down")
  if p.elevation ~= nil then
    Player.elevation = tonumber(p.elevation) or 3
  end
  local save = game and game.save
  if save and save.biking ~= nil then
    Player.biking = (save.biking == true)
  end
end

--- Write avatar coords into save.position (ferry / host save). No host entity mirror.
function Player.syncSavePosition(game)
  local save = game and game.save
  if save then
    if save.position then
      save.position.x = Player.cellX
      save.position.y = Player.cellY
      save.position.facing = Player.facing
      save.position.biking = Player.biking == true
    end
    save.biking = Player.biking == true
    save.surfing = Player.surfing == true
    save.underwater = Player.underwater == true
    save.elevation = Player.elevation
  end
  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session then
    session.biking = (Player.biking == true)
    session.surfing = Player.surfing == true
    session.underwater = Player.underwater == true
    session.bikeType = Player.bikeType
    session.elevation = Player.elevation
    if session.map and save and save.position then
      save.position.map = session.map
    end
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

local function surfBobY()
  if not (Player.surfing or Player.underwater) then return nil end
  local FieldEffects = package.loaded["src.core.game3.field_effects"]
  return FieldEffects and FieldEffects.surfPlayerY2 and FieldEffects.surfPlayerY2() or 0
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

-- src/event_object_movement.c:5333
function Player.runPose()
  if not (Player.moving and Player.running) or Player.biking or Player.jumping
      or Player.surfing or Player.animDisabled then
    return nil
  end
  -- src/data/object_events/object_event_anims.h:601
  return ((Player.animClock or 0) - 1) % 8 >= 5 and 1 or 0
end

function Player.drawFlip()
  return Player.stepFlip and true or false
end

--- pret DoJumpSpriteMovement y2 for JUMP_DISTANCE_FAR + JUMP_TYPE_HIGH.
function Player.jumpSpriteY()
  if not Player.jumping then return 0 end
  local progress = Player.progress or 0
  if progress < 1 then return 0 end
  if Player.jumpType then
    -- pokeemerald/src/event_object_movement.c:8462 DoJumpSpriteMovement
    local idx = (Player.stepFrames or 16) >= 32 and math.floor((progress - 1) / 2) or (progress - 1)
    local t = JUMP_Y[Player.jumpType] or JUMP_Y_HIGH
    return t[idx + 1] or 0
  end
  -- After frame N's Step1, sTimer == N; y2 = sJumpY_High[sTimer >> 1].
  local idx = math.floor((progress - 1) / 2)
  if idx < 0 then return 0 end
  if idx >= #JUMP_Y_HIGH then return 0 end
  return JUMP_Y_HIGH[idx + 1]
end

-- pokefirered/src/event_object_movement.c:8400
function Player.updateElevation(curX, curY, prevX, prevY)
  local cur, prev = Collision.nextElevation(Collision._mapDef, Player.currentElevation or 0,
    curX, curY, prevX or curX, prevY or curY)
  Player.currentElevation = cur
  if prev then Player.elevation = prev end
end

local function beginStep(tx, ty, run, ledge)
  local mdx, mdy = tx - Player.cellX, ty - Player.cellY
  if mdx ~= 0 or mdy ~= 0 then
    Player.moveDir = (mdx > 0 and "right") or (mdx < 0 and "left") or (mdy > 0 and "down") or "up"
  end
  Player.jumpType = nil
  Player.acroAnim = nil
  Player.updateElevation(tx, ty, Player.cellX, Player.cellY)
  Player.prevCellX = Player.cellX
  Player.prevCellY = Player.cellY
  Player.stepSerial = (Player.stepSerial or 0) + 1
  Player.moving = true
  Player.progress = 0
  Player.targetX = tx
  Player.targetY = ty
  Player.running = (not ledge) and run and true or false
  Player.jumping = ledge and true or false
  Player.spriteYOffset = (not ledge) and surfBobY() or 0
  if Player.surfHopping or Player.dismounting then
    -- pokeemerald/src/event_object_movement.c:8495 DoJumpSpecialSpriteMovement
    Player.stepFrames = JUMP_FRAMES
    Player.jumping = true
    Player.jumpType = "high"
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
  local okFx, FieldEffects = pcall(lazyReq, "src.core.game3.field_effects")
  if okFx and FieldEffects then
    if Collision.isGrass and Collision.isGrass(tx, ty) then
      FieldEffects.tallGrassAt(tx, ty, false)
    else
      FieldEffects.leaveTallGrass()
    end
  end
end

local function stairTrigger(game, dir)
  -- pokefirered/src/field_player_avatar.c:556
  local stair = Collision.isStairWarp
    and Collision.isStairWarp(game, Player.cellX, Player.cellY, dir)
  if stair then
    local Warp = lazyReq("src.core.game3.warp")
    if Warp.isBusy() then return "stair_busy" end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local mod = Runtime and Runtime._mod
    local g = game or (Runtime and Runtime._game)
    Warp.startStairWarp(mod, g, stair.destMap, stair.destX, stair.destY, stair.behavior)
    return "stair"
  end
  return nil
end

local function stepTriggers(game, dir, wasFacing, tx, ty)
  if dir == "up" then
    -- pokeemerald/src/field_control_avatar.c:837
    if lazyReq("src.core.game3.field_moves").isRse()
        and lazyReq("src.core.game3.rse.init").call("secretBase", "tryDoorWarp", nil, nil, game, tx, ty) then
      return "secret_base_door"
    end
    local doorWarp = Collision.isDoorWarp and Collision.isDoorWarp(game, tx, ty)
    if doorWarp then
      local Warp = lazyReq("src.core.game3.warp")
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

  if dir == "down" and wasFacing == "down" and Collision.arrowWarpDir(Collision.behavior(Player.cellX, Player.cellY)) == "down" then
    -- pokeruby/src/overworld.c:1984
    local Link = package.loaded["src.core.game3.link"] or package.loaded["src.core.game3.link.init"]
    local Space = package.loaded["src.core.game3.scripting.space"]
    local key = Space and Space.vm and (Space.scriptKey("TradeRoom_PromptToCancelLink")
      or Space.scriptKey("EventScript_ConfirmLeaveCableClubRoom")
      or Space.scriptKey("TradeCenter_ConfirmLeaveRoom"))
    if key and Link and Link.link and Link.link:isOpen() and Link.inLinkRoom(Space.vm.ctx) then
      local Audio = lazyReq("src.core.game3.audio")
      if Audio.playSe then Audio.playSe(lazyReq("src.core.game3.se_ids").SE_WIN_OPEN) end
      if Space.startScript(key) then return "link_room_exit" end
    end
  end

  if dir == "down" then
    local exitWarp = Collision.isExitWarp and Collision.isExitWarp(game, Player.cellX, Player.cellY)
    if exitWarp then
      local Warp = lazyReq("src.core.game3.warp")
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
    local Warp = lazyReq("src.core.game3.warp")
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
    local Warp = lazyReq("src.core.game3.warp")
    if Warp.isBusy() then return "arrow_busy" end
    if Collision.tryWarpAt(game, Player.cellX, Player.cellY, dir, { arrow = true }) then
      return "arrow_warp"
    end
  end

  -- pokefirered/src/field_control_avatar.c:262
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.tryWalkIntoSign then
    -- pokefirered/src/field_control_avatar.c:260
    if wasFacing ~= dir then
      if Field.tryWalkIntoSign(game, dir, true) then return "sign_turn" end
    elseif Field.tryWalkIntoSign(game, dir) then
      return "sign"
    end
  end
  return nil
end

function Player.fieldTriggers(game, dir)
  local d = DELTA[dir]
  if not d then return nil end
  return stairTrigger(game, dir)
    or stepTriggers(game, dir, Player.facing, Player.cellX + d[1], Player.cellY + d[2])
end

-- pokefirered/src/field_player_avatar.c:1005 PlayCollisionSoundIfNotFacingWarp
local function playCollisionSoundIfNotFacingWarp(dir)
  local beh = Collision.behavior(Player.cellX, Player.cellY)
  if Collision.arrowWarpDir(beh) == dir then return end
  if Collision.isStairWarpBehavior(beh) and Collision.stairWarpDir(beh) == dir then
    return
  end
  if dir == "up"
      and Collision.isWarpDoor(Collision.behavior(Player.cellX, Player.cellY - 1)) then
    return
  end
  local Audio = lazyReq("src.core.game3.audio")
  if Audio.playSe then Audio.playSe(lazyReq("src.core.game3.se_ids").SE_WALL_HIT) end
end

-- pokefirered/src/field_player_avatar.c:878 PlayerOnBikeCollide
-- pokefirered/src/field_player_avatar.c:884 PlayerNotOnBikeCollide
local function playerCollide(dir)
  playCollisionSoundIfNotFacingWarp(dir)
  Player.startAction({
    frames = Player.biking and WALK_FRAMES or WALK_IN_PLACE_SLOW_FRAMES,
    walk = "normal",
    interruptible = not Player.biking,
  })
end

function Player.cancelAction()
  if not Player.action then return end
  Player.action = nil
  Player.spriteYOffset = 0
  Player.walkInPlace = false
  Player.walkInPlaceFast = false
end

-- pokeemerald/src/field_player_avatar.c:353 TryInterruptObjectEventSpecialAnim
-- pokefirered/src/field_player_avatar.c:156 TryInterruptObjectEventSpecialAnim
local function tryInterruptAction(game, dir)
  local a = Player.action
  if not (a and a.interruptible and dir) then return false end
  if dir ~= Player.facing then
    Player.cancelAction()
    return true
  end
  -- pokeemerald/src/field_player_avatar.c:372
  local Profile = package.loaded["src.core.game3.profile"] or lazyReq("src.core.game3.profile")
  if Profile.forSession(nil).id ~= "emerald" then return false end
  local d = DELTA[dir]
  local ok = Collision.canEnter(game, Player.cellX + d[1], Player.cellY + d[2], {
    fromX = Player.cellX,
    fromY = Player.cellY,
    dir = dir,
    surfing = Player.surfing or Player.underwater,
    elevation = Player.currentElevation,
  })
  if ok then
    Player.cancelAction()
    return true
  end
  return false
end

function Player.tryMove(dir, game, run)
  if Player.moving or Player.boulderPush then return nil end
  if not DELTA[dir] then return nil end

  -- pokeemerald/src/field_player_avatar.c:353 TryInterruptObjectEventSpecialAnim
  if Player.turnTimer > 0 then return nil end
  local wasFacing = Player.facing
  if Player.facing ~= dir then
    Player.facing = dir
    -- pokeemerald/src/field_player_avatar.c:593
    if Player.turnArmed then
      Player.turnTimer = TURN_FRAMES
      return "turned"
    end
  end
  -- pokeemerald/src/field_player_avatar.c:595
  Player.turnArmed = false

  local trig = stairTrigger(game, dir)
  if trig then return trig end

  local d = DELTA[dir]
  local tx = Player.cellX + d[1]
  local ty = Player.cellY + d[2]

  -- pret CheckForPlayerAvatarCollision → ShouldJumpLedge(dest): hop over the
  -- impassable ledge tile when facing matches; otherwise canEnter bumps.
  local lx, ly = Collision.ledgeLanding(game, Player.cellX, Player.cellY, dir)
  if lx then
    beginStep(lx, ly, false, true)
    pcall(function()
      local Audio = lazyReq("src.core.game3.audio")
      local SE = lazyReq("src.core.game3.se_ids")
      if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
    end)
    return "ledge"
  end

  trig = stepTriggers(game, dir, wasFacing, tx, ty)
  if trig then return trig end

  local ok, why = Collision.canEnter(game, tx, ty, {
    fromX = Player.cellX,
    fromY = Player.cellY,
    dir = dir,
    surfing = Player.surfing or Player.underwater,
    elevation = Player.currentElevation,
  })

  if not ok then
    if why == "entity" then
      local Space = package.loaded["src.core.game3.scripting.space"]
      local Flags = lazyReq("src.core.game3.scripting.flags")
      local FieldMoves = lazyReq("src.core.game3.field_moves")
      local isStrengthActive = Space and Space.store and Flags.getFlag(Space.store, nil, FieldMoves.SYS_FLAGS.USE_STRENGTH)
      if isStrengthActive then
        local Objects = lazyReq("src.core.game3.objects")
        local obj = Objects.at(tx, ty)
        if obj and (obj.def and (obj.def.graphicsId == FieldMoves.GFX_IDS.PUSHABLE_BOULDER or obj.def.gfx == FieldMoves.GFX_IDS.PUSHABLE_BOULDER)) then
          -- pokefirered/src/field_player_avatar.c:638
          local canPush, destBx, destBy = FieldMoves.canPushBoulder(obj, dir, function(bx, by)
            local beh = Collision.behavior(bx, by)
            if Collision.isFallWarp(beh) then return true end
            return Collision.canEnter(game, bx, by,
              { fromX = tx, fromY = ty, dir = dir, elevation = obj.currentElevation }) == true
              and not Collision.isNonAnimDoor(beh)
          end)
          if canPush and not obj.moving then
            -- pokefirered/src/field_player_avatar.c:1417 DoBoulderInit
            Player.boulderPush = { obj = obj }
            -- pokefirered/src/field_player_avatar.c:1425 DoBoulderDust
            Player.facing = dir
            Player.walkInPlace = true
            Player.walkInPlaceFast = false
            Player.animClock = 0
            Objects.pushStep(obj, dir, WALK_FRAMES * 2)
            local FieldEffects = lazyReq("src.core.game3.field_effects")
            FieldEffects.startDust(tx, ty)
            lazyReq("src.core.game3.audio").playSe(lazyReq("src.core.game3.se_ids").SE_M_STRENGTH)
            if ModRuntime.wants("world.boulder_moved") then
              local Map = package.loaded["src.core.game3.map"]
              ModRuntime.emit("world.boulder_moved", {
                mapId = Map and Map.current, npcId = obj.localId, x = destBx, y = destBy,
              })
            end
            return "push"
          end
        end
      end
    end
    -- Outdoor map connection (Pallet north → Route 1, etc.).
    if why == "bounds" and Collision.tryConnection
        and Collision.tryConnection(game, Player.cellX, Player.cellY, dir, run) then
      return "connection"
    end
    -- pokefirered/src/field_player_avatar.c:504
    playerCollide(dir)
    return "blocked", why
  end
  local RG = package.loaded["src.core.game3.rotating_gate"]
  if RG and RG.active() and RG.checkCollision(dir, tx, ty) then
    -- pokeemerald/src/field_player_avatar.c:709
    return "blocked", "rotating_gate"
  end
  local BikeRse = rseBike()
  if BikeRse and BikeRse.acroCollision(Collision.behavior(tx, ty)) ~= 0 then
    -- pokeemerald/src/field_player_avatar.c:711
    return "blocked", "acro"
  end
  local isDismount = Player.surfing and not Player.underwater
    and Collision.isSurfDismount(tx, ty, Player.currentElevation)
  if isDismount then
    Player.dismounting = true
    lazyReq("src.core.game3.audio").stopSurfMusic()
  else
    Player.dismounting = false
  end

  beginStep(tx, ty, run, false)
  if not Player.jumping and not Player.biking then
    Player.stepFrames, Player.running = Player.ordinaryStepFrames(run)
  end
  return "step"
end

-- pokeemerald/src/field_player_avatar.c:651
function Player.ordinaryStepFrames(run)
  if Player.surfHopping or Player.dismounting then return WALK_FRAMES, false end
  if Player.surfing and not Player.underwater and not Player.biking and not Player.action then
    return RUN_FRAMES, false
  end
  return run and RUN_FRAMES or WALK_FRAMES, run == true
end

-- pokefirered/src/metatile_behavior.c:668 MetatileBehavior_IsCyclingRoadPullDownTile
local function isCyclingRoadPullDown(beh)
  if Collision.isCyclingRoadPullDown then
    return Collision.isCyclingRoadPullDown(beh) == true
  end
  return beh ~= nil and beh >= MB_CYCLING_ROAD_PULL_DOWN
    and beh <= MB_CYCLING_ROAD_PULL_DOWN_GRASS
end

function Player.isOnCyclingRoad(session, x, y, mapDef)
  local cx = x or Player.cellX
  local cy = y or Player.cellY
  local beh
  if mapDef then
    beh = Collision.behaviorOn and Collision.behaviorOn(mapDef, cx, cy)
  else
    beh = Collision.behavior and Collision.behavior(cx, cy)
  end
  if isCyclingRoadPullDown(beh) then return true end
  local Flags = package.loaded["src.core.game3.scripting.flags"]
    or package.loaded["src.core.game3.flags"]
    or lazyReq("src.core.game3.scripting.flags")
  local cf = Flags and Flags.forVersion and sessionFlags(session).IDS.FLAG_SYS_ON_CYCLING_ROAD
  if cf and Flags.getFlag then
    local cfKey = tostring(cf)
    local Live = package.loaded["src.core.game3.scripting.space"]
    if Live and Live.active == true and Live.store then
      return Flags.getFlag(Live.store, nil, cf) == true
    end
    if session and (session.store or session.flags) then
      local st = session.store or session
      if Flags.getFlag(st, nil, cf) == true or (session.flags and (session.flags[cf] == true or session.flags[cfKey] == true)) then
        return true
      end
    end
    local Space = package.loaded["src.core.game3.scripting.space"] or package.loaded["src.core.game3.space"]
    if Space and Space.store and Flags.getFlag(Space.store, nil, cf) == true then
      return true
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local s = Runtime and Runtime.getSession and Runtime.getSession()
    if s and (s.store or s.flags) then
      local st = s.store or s
      if Flags.getFlag(st, nil, cf) == true or (s.flags and (s.flags[cf] == true or s.flags[cfKey] == true)) then
        return true
      end
    end
  end
  return false
end

-- pokefirered/src/bike.c:215 GetBikeCollision
local function bikeCanMove(game, dir)
  local d = DELTA[dir]
  if not d then return false end
  local x, y = Player.cellX + d[1], Player.cellY + d[2]
  local RG = package.loaded["src.core.game3.rotating_gate"]
  -- pokeemerald/src/field_player_avatar.c:722
  if RG and RG.active() and RG.checkCollision(dir, x, y, true) then return false end
  return Collision.canEnter(game, x, y, {
    fromX = Player.cellX, fromY = Player.cellY, dir = dir, surfing = Player.surfing,
    elevation = Player.currentElevation,
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
  -- pokeemerald/src/field_screen_effect.c:699
  if Player.biking then
    Player.stepFrames = WALK_FRAMES
    Player.running = false
  end
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
    Player.dismounting = Player.surfing and not Player.underwater
      and Collision.isSurfDismount(tx, ty, Player.currentElevation) or false
    -- pokefirered/src/field_player_avatar.c:1609
    if Player.dismounting then lazyReq("src.core.game3.audio").stopSurfMusic() end
    beginStep(tx, ty, false, false)
  end
  if frames and not opts.ledgeX and not Player.dismounting then
    Player.stepFrames = frames
  end
  if Player.spinning then Player.spinStart = dir end
  return true
end

--- Forced script step (applymovement localId 0xFF): skips collision.
function Player.scriptStep(dir, run, slow, fast, frames)
  if Player.moving then return false end
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  local tx, ty = Player.cellX + d[1], Player.cellY + d[2]
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision._grid and Collision._grid[1] ~= nil and not Collision.inBounds(tx, ty) then
    local session = package.loaded["src.core.game3.runtime"]
    session = session and session.getSession and session.getSession()
    local mapBlock = session and lazyReq("src.core.game3.profile").forSession(session).map
    if mapBlock and mapBlock.scriptConnections then
      -- pokeemerald/src/fieldmap.c:603
      local lx, ly = Collision.scriptConnection(nil, Player.cellX, Player.cellY, Player.facing)
      if lx then tx, ty = lx, ly end
    end
  end
  beginStep(tx, ty, run and true or false, false)
  Player._scriptedStep = true
  -- pokeemerald/src/event_object_movement.c:5101
  if Player.biking and not (Player.surfHopping or Player.dismounting) then
    Player.stepFrames = run and RUN_FRAMES or WALK_FRAMES
    Player.running = run and true or false
  end
  -- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim
  if run and slow then Player.stepFrames = RUN_SLOW_FRAMES end
  if fast then Player.stepFrames = RUN_FRAMES end
  if frames then Player.stepFrames = frames end
  return true
end

--- Forced script jump (applymovement localId 0xFF): hops over ledges / gaps.
function Player.scriptJump(dir, distance)
  if Player.moving then return false end
  distance = distance or 1
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  pcall(function()
    local Audio = lazyReq("src.core.game3.audio")
    local SE = lazyReq("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
  end)
  beginStep(Player.cellX + d[1] * distance, Player.cellY + d[2] * distance, false, true)
  Player._scriptedStep = true
  return true
end

function Player.scriptFace(dir)
  if DELTA[dir] then Player.facing = dir end
end

-- pokeemerald/src/field_player_avatar.c:966 PlayerSetAnimId
function Player.bikeStep(tx, ty, dir, frames, opts)
  if Player.moving then return false end
  opts = opts or {}
  local face = Player.facing
  beginStep(tx, ty, false, opts.jump ~= nil)
  Player.facing = Player.facingLocked and face or dir
  Player.moveDir = dir
  Player.stepFrames = frames
  Player.running = false
  Player.jumping = opts.jump ~= nil
  Player.jumpType = opts.jump
  Player.acroAnim = opts.acroAnim
  return true
end

-- pokeemerald/src/event_object_movement.c:5704 InitMoveInPlace
function Player.startAction(opts)
  Player.action = {
    frames = opts.frames or 1,
    t = 0,
    jump = opts.jump,
    turnTo = opts.turnTo,
    walk = opts.walk,
    done = opts.done,
    interruptible = opts.interruptible,
  }
  Player.acroAnim = opts.acroAnim
  if opts.walk then
    Player.walkInPlace = true
    Player.walkInPlaceFast = opts.walk == "fast"
    Player.animClock = 0
  end
  return true
end

local function tickAction()
  local a = Player.action
  a.t = a.t + 1
  if a.jump then
    local t = JUMP_Y[a.jump] or JUMP_Y_HIGH
    Player.spriteYOffset = t[a.t] or 0
    -- pokeemerald/src/event_object_movement.c:5517
    if a.turnTo and a.t == 8 then Player.facing = a.turnTo end
  end
  if a.t >= a.frames then
    Player.action = nil
    Player.spriteYOffset = 0
    if a.walk then
      Player.walkInPlace = false
      Player.walkInPlaceFast = false
    end
    if a.done then a.done() end
  end
  return false
end

-- pokeemerald/src/data/object_events/object_event_anims.h:416
local ACRO_FRAMES = {
  back = { down = { 9, 10 }, up = { 13, 14 }, left = { 17, 18 }, right = { 17, 18 } },
  standBack = { down = { 9, 0 }, up = { 13, 1 }, left = { 17, 2 }, right = { 17, 2 } },
  pedal = { down = { 21, 10, 22, 10 }, up = { 23, 14, 24, 14 }, left = { 25, 18, 26, 18 }, right = { 25, 18, 26, 18 } },
}

-- pokeemerald/src/data/object_events/object_event_anims.h:392
local SURF_JUMP_FRAME = { down = 9, up = 10, left = 11, right = 11 }

function Player.surfJumpFrame()
  if not ((Player.surfHopping or Player.dismounting) and Player.jumping and Player.moving) then return nil end
  return SURF_JUMP_FRAME[Player.facing] or 9
end

function Player.acroFrame()
  local a = Player.acroAnim
  if not (a and Player.biking) then return nil end
  local seq = ACRO_FRAMES[a.kind] and ACRO_FRAMES[a.kind][Player.facing]
  if not seq then return nil end
  if a.paused then return seq[1] end
  local i = math.floor((a.clock or 0) / 4)
  if a.kind == "pedal" then i = i % #seq else i = math.min(i, #seq - 1) end
  return seq[i + 1]
end

--- Parabolic hop into water when initiating Surf.
function Player.startSurfing(game, onDone)
  Player.biking = false -- Bike override: clear bike state when using Surf
  Player.running = false
  Player.surfHopping = true
  Player.surfing = false
  Player.dismounting = false
  pcall(function()
    local Audio = lazyReq("src.core.game3.audio")
    local SE = lazyReq("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
  end)
  if not Player.forceStep(Player.facing, onDone) then
    Player.surfHopping = false
    return false
  end
  return true
end

function Player.startFieldMove(duration, kind)
  Player.fieldMoveAnim = duration or 28
  Player.fieldMoveTotal = Player.fieldMoveAnim
  Player.fieldMoveKind = kind
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
  Player.jumpType = nil
  Player.spriteYOffset = 0
  Player.updateElevation(Player.cellX, Player.cellY)

  -- Surf landing / dismount state transitions
  local wasSurfing = Player.surfing or Player.dismounting
  if Player.surfHopping then
    Player.surfHopping = false
    Player.surfing = true
  elseif Player.dismounting then
    Player.dismounting = false
    Player.surfing = false
  end

  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session then
    session.x, session.y, session.facing = Player.cellX, Player.cellY, Player.facing
  end

  if wasSurfing and not Player.surfing and not Player.surfHopping then
    if Player.isOnCyclingRoad(session, Player.cellX, Player.cellY) then
      Player.biking = true
      pcall(function()
        local Audio = lazyReq("src.core.game3.audio")
        Audio.bikeMusic(true, true)
      end)
    end
  end
  Player.syncSavePosition(game)

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
  local scripted = Player._scriptedStep
  Player._scriptedStep = nil
  if scripted then
    local mapBlock = session and lazyReq("src.core.game3.profile").forSession(session).map
    -- pokeemerald/src/field_control_avatar.c:159
    if mapBlock and mapBlock.scriptStepEvents == false then return end
  end

  local ForcedMovement = package.loaded["src.core.game3.forced_movement"]
    or lazyReq("src.core.game3.forced_movement")
  -- pokefirered/src/field_control_avatar.c:136
  local onForcedTile =
    ForcedMovement.isForcedMovementTile(Collision.behavior(Player.cellX, Player.cellY))

  local Field = package.loaded["src.core.game3.field"]
    or lazyReq("src.core.game3.field")

  local stepConsumed = false
  -- pokeemerald/src/field_control_avatar.c:147
  if not Field.locked then
    local okTs, TrainerSight = pcall(lazyReq, "src.core.game3.trainer_sight")
    if okTs and TrainerSight and TrainerSight.check then
      stepConsumed = TrainerSight.check(game) == true
    end
  end

  if not onForcedTile and not stepConsumed then
    -- pokeemerald/src/field_control_avatar.c:485
    if Field.tryCoordEvents then
      stepConsumed = Field.tryCoordEvents(game, Player.cellX, Player.cellY) == true
    end
    -- pokeemerald/src/field_control_avatar.c:487
    if not stepConsumed then
      stepConsumed = Collision.tryWarpAt(game, Player.cellX, Player.cellY, Player.facing) == true
    end
    -- pokeemerald/src/field_control_avatar.c:491
    local StepEvents = package.loaded["src.core.game3.step_events"]
      or lazyReq("src.core.game3.step_events")
    if not stepConsumed and StepEvents and StepEvents.onStepTaken then
      stepConsumed = StepEvents.onStepTaken(session, game) == true
    end
  end

  -- pokefirered/src/field_player_avatar.c:136
  local Warp = package.loaded["src.core.game3.warp"]
  local warping = (Warp and Warp.isBusy and Warp.isBusy()) and true or false
  if not warping and ForcedMovement.onStepFinished(game) then return end

  -- pokefirered/src/wild_encounter.c:757
  local onGrass = Collision.isGrass and Collision.isGrass(Player.cellX, Player.cellY)
  local onWater = Player.surfing and (Collision.isWater and Collision.isWater(Player.cellX, Player.cellY))
  local okE, Encounters = pcall(lazyReq, "src.core.game3.encounters")
  -- pokeemerald/src/field_control_avatar.c:160
  if okE and Encounters and Encounters.onStep and not onForcedTile and not stepConsumed then
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
        local BattleBridge = lazyReq("src.core.game3.battle_bridge")
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
    local okFx, FieldEffects = pcall(lazyReq, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.tallGrassAt then
      FieldEffects.tallGrassAt(Player.cellX, Player.cellY, true)
    end
  end
end

function Player.tick(game)
  if Player.acroAnim then Player.acroAnim.clock = (Player.acroAnim.clock or 0) + 1 end
  if Player.moving then
    Player.updateElevation(Player.targetX, Player.targetY, Player.cellX, Player.cellY)
  else
    Player.updateElevation(Player.cellX, Player.cellY)
  end
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
    if Player.action then return tickAction() end
    local bobY = (not Player.jumping) and surfBobY() or nil
    if bobY then
      Player.spriteYOffset = bobY
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
    Player.spriteYOffset = surfBobY() or 0
  end
  -- pokefirered/src/data/object_events/object_event_anims.h:556
  if Player.spinning then
    local base = SPIN_PHASE[Player.spinStart] or 1
    local idx = (base - 1 + math.floor((Player.progress - 1) / 2)) % #SPIN_CYCLE
    Player.facing = SPIN_CYCLE[idx + 1]
  end
  if Player.progress >= frames then
    finishStep(game)
    local bobY = (not Player.moving) and surfBobY() or nil
    if bobY then Player.spriteYOffset = bobY end
    return true
  end
  return false
end

--- pret field_player_avatar: B-dash only with FLAG_SYS_B_DASH (Running Shoes).
function Player.canDash()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.getStore and Space.getStore()
  if not store then
    -- Field not scripted yet: deny dash (shoes not granted).
    return false
  end
  local Flags = lazyReq("src.core.game3.scripting.flags")
  local rules = fieldBlock().running
  if not rules then
    return Flags.getFlag(store, nil, Flags.IDS.SYS_B_DASH) == true
  end
  if Flags.getFlag(store, nil, sessionFlags().IDS[rules.flag]) ~= true then return false end
  if Player.underwater then return false end
  return not Player.runningDisallowed(Player.cellX, Player.cellY)
end

-- pokeemerald/src/bike.c:1056
function Player.runningDisallowed(cx, cy)
  local rules = fieldBlock().running
  if not rules then return false end
  if rules.mapHeader then
    local def = Collision._mapDef
    if def and tonumber(def.allowRunning) == 0 then return true end
  end
  local beh = Collision.behavior and Collision.behavior(cx, cy)
  if beh == nil then return false end
  local MB = lazyReq("src.core.game3.mb")
  for _, name in ipairs(rules.behaviors or {}) do
    if beh == MB.id(name) then return true end
  end
  -- pokeemerald/src/bike.c:905
  for _, name in ipairs(rules.evenElevation or {}) do
    if beh == MB.id(name) and (tonumber(Player.currentElevation) or 0) % 2 == 0 then return true end
  end
  return false
end

--- Poll D-pad + B-run when field is free.
function Player.update(game, input)
  Player.tick(game)
  -- pokeemerald/src/field_player_avatar.c:336
  if not Player._scriptedStep then WarpArrow.update(Player) end
  if Player.biking and Player.bikeType == "acro" then
    local BikeRse = rseBike()
    -- pokeemerald/src/field_player_avatar.c:339
    if BikeRse then BikeRse.historyUpdate(input) end
  end
  if Player.moving then return end
  if Player.action and not tryInterruptAction(game, dirs_from_input(input)) then return end
  if Player.biking then
    local BikeRse = rseBike()
    -- pokeemerald/src/field_player_avatar.c:393 MovePlayerAvatarUsingKeypadInput
    if BikeRse then return BikeRse.update(game, input) end
  end
  local push = Player.boulderPush
  if push then
    if Player.walkInPlace and Player.animClock >= WALK_FRAMES then
      Player.walkInPlace = false
    end
    -- pokefirered/src/field_player_avatar.c:1445 DoBoulderFinish
    if Player.walkInPlace or push.obj.moving then return end
    Player.boulderPush = nil
    local Field = lazyReq("src.core.game3.field")
    Field.onBoulderMoved(game, push.obj, push.obj.cellX, push.obj.cellY)
    return
  end
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
  -- pokeemerald/src/field_control_avatar.c:150
  if Space and Space._pendingOnFrame then return end

  -- Menu Dismissal Frame Trap & Idle Sight Check: check sight before D-pad input polling
  local okTs, TrainerSight = pcall(lazyReq, "src.core.game3.trainer_sight")
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

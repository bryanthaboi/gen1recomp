-- pokefirered/src/field_player_avatar.c:226 sForcedMovementFuncs

local Collision = require("src.core.game3.collision")

local M = {}

-- pokefirered/include/constants/metatile_behaviors.h:17
local MB_WATERFALL = 0x13
local MB_ICE = 0x23
local MB_WALK_EAST = 0x40
local MB_WALK_WEST = 0x41
local MB_WALK_NORTH = 0x42
local MB_WALK_SOUTH = 0x43
local MB_SLIDE_EAST = 0x44
local MB_SLIDE_WEST = 0x45
local MB_SLIDE_NORTH = 0x46
local MB_SLIDE_SOUTH = 0x47
local MB_TRICK_HOUSE_PUZZLE_8_FLOOR = 0x48
local MB_EASTWARD_CURRENT = 0x50
local MB_WESTWARD_CURRENT = 0x51
local MB_NORTHWARD_CURRENT = 0x52
local MB_SOUTHWARD_CURRENT = 0x53
local MB_SPIN_RIGHT = 0x54
local MB_SPIN_LEFT = 0x55
local MB_SPIN_UP = 0x56
local MB_SPIN_DOWN = 0x57
local MB_STOP_SPINNING = 0x58

-- pokefirered/src/event_object_movement.c:8925 sStepTimes
local FRAMES_NORMAL = 16
local FRAMES_FAST_1 = 8
local FRAMES_FAST_2 = 6

-- pokefirered/src/field_player_avatar.c:379
local SE_M_RAZOR_WIND2 = 153

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

M.forced = false
M.lastSpinTile = nil
M._mapId = nil

local function player()
  return package.loaded["src.core.game3.player"] or require("src.core.game3.player")
end

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function behaviorPred(name, value)
  return function(beh)
    local fn = name and Collision[name]
    if fn then return fn(beh) == true end
    return beh == value
  end
end

local isSpinTile = function(beh)
  if Collision.isSpinTile then return Collision.isSpinTile(beh) == true end
  return beh ~= nil and beh >= MB_SPIN_RIGHT and beh <= MB_SPIN_DOWN
end

local isStopSpinning = behaviorPred("isStopSpinning", MB_STOP_SPINNING)

-- pokefirered/src/field_player_avatar.c:278 ForcedMovement_None
local function forcedMovementNone()
  local P = player()
  if M.forced then
    M.forced = false
    P.spinning = false
    P.animDisabled = false
  end
  return false
end

-- pokefirered/src/field_player_avatar.c:292 DoForcedMovement
local function doForcedMovement(game, dir, frames, opts)
  local P = player()
  local d = DELTA[dir]
  if not d then return forcedMovementNone() end
  if P.moving then return false end
  M.forced = true

  local lx, ly
  if Collision.ledgeLanding then
    lx, ly = Collision.ledgeLanding(game, P.cellX, P.cellY, dir)
  end
  if lx then
    -- pokefirered/src/field_player_avatar.c:307 PlayerJumpLedge
    forcedMovementNone()
    M.forced = true
    return P.forcedStep(dir, nil, { ledgeX = lx, ledgeY = ly })
  end

  local tx, ty = P.cellX + d[1], P.cellY + d[2]
  local ok = Collision.canEnter(game, tx, ty, {
    fromX = P.cellX, fromY = P.cellY, dir = dir, surfing = P.surfing,
  })
  if not ok then
    -- pokefirered/src/field_player_avatar.c:299
    return forcedMovementNone()
  end
  return P.forcedStep(dir, frames, opts)
end

-- pokefirered/src/field_player_avatar.c:330 ForcedMovement_Slip
local function slip(game)
  local P = player()
  P.animDisabled = true
  return doForcedMovement(game, P.facing, FRAMES_FAST_1)
end

-- pokefirered/src/field_player_avatar.c:335 ForcedMovement_WalkSouth
local function walk(dir)
  return function(game)
    return doForcedMovement(game, dir, FRAMES_NORMAL)
  end
end

-- pokefirered/src/field_player_avatar.c:384 ForcedMovement_PushedSouthByCurrent
local function current(dir)
  return function(game)
    return doForcedMovement(game, dir, FRAMES_FAST_2)
  end
end

-- pokefirered/src/field_player_avatar.c:355 ForcedMovement_SpinRight
local function spin(dir)
  return function(game)
    se(SE_M_RAZOR_WIND2)
    local P = player()
    P.spinning = true
    local moved = doForcedMovement(game, dir, FRAMES_FAST_1)
    if not moved then P.spinning = false end
    return moved
  end
end

-- pokefirered/src/field_player_avatar.c:404 ForcedMovement_Slide
local function slide(dir)
  return function(game)
    local P = player()
    P.animDisabled = true
    return doForcedMovement(game, dir, FRAMES_FAST_1, { keepFacing = true })
  end
end

-- pokefirered/src/field_effect.c:1605 FldEff_UseWaterfall
local function waterfallCurrent(game)
  local Field = package.loaded["src.core.game3.field"]
  if Field and (Field._waterfall or Field.locked) then return false end
  return current("down")(game)
end

-- pokefirered/src/metatile_behavior.c:620
local function never() return false end

-- pokefirered/src/field_player_avatar.c:433 ForcedMovement_MatJump
local function matJump() return false end

-- pokefirered/src/field_player_avatar.c:439 ForcedMovement_MatSpin
local function matSpin() return false end

-- pokefirered/src/field_player_avatar.c:226 sForcedMovementFuncs
M.TABLE = {
  { name = "Slip", check = behaviorPred(nil, MB_TRICK_HOUSE_PUZZLE_8_FLOOR), apply = slip },
  { name = "Slip", check = behaviorPred("isIce", MB_ICE), apply = slip },
  { name = "WalkSouth", check = behaviorPred("isWalkSouth", MB_WALK_SOUTH), apply = walk("down") },
  { name = "WalkNorth", check = behaviorPred("isWalkNorth", MB_WALK_NORTH), apply = walk("up") },
  { name = "WalkWest", check = behaviorPred("isWalkWest", MB_WALK_WEST), apply = walk("left") },
  { name = "WalkEast", check = behaviorPred("isWalkEast", MB_WALK_EAST), apply = walk("right") },
  { name = "PushedSouthByCurrent",
    check = behaviorPred("isSouthwardCurrent", MB_SOUTHWARD_CURRENT), apply = current("down") },
  { name = "PushedNorthByCurrent",
    check = behaviorPred("isNorthwardCurrent", MB_NORTHWARD_CURRENT), apply = current("up") },
  { name = "PushedWestByCurrent",
    check = behaviorPred("isWestwardCurrent", MB_WESTWARD_CURRENT), apply = current("left") },
  { name = "PushedEastByCurrent",
    check = behaviorPred("isEastwardCurrent", MB_EASTWARD_CURRENT), apply = current("right") },
  { name = "SpinRight", check = behaviorPred("isSpinRight", MB_SPIN_RIGHT), apply = spin("right") },
  { name = "SpinLeft", check = behaviorPred("isSpinLeft", MB_SPIN_LEFT), apply = spin("left") },
  { name = "SpinUp", check = behaviorPred("isSpinUp", MB_SPIN_UP), apply = spin("up") },
  { name = "SpinDown", check = behaviorPred("isSpinDown", MB_SPIN_DOWN), apply = spin("down") },
  { name = "SlideSouth", check = behaviorPred("isSlideSouth", MB_SLIDE_SOUTH), apply = slide("down") },
  { name = "SlideNorth", check = behaviorPred("isSlideNorth", MB_SLIDE_NORTH), apply = slide("up") },
  { name = "SlideWest", check = behaviorPred("isSlideWest", MB_SLIDE_WEST), apply = slide("left") },
  { name = "SlideEast", check = behaviorPred("isSlideEast", MB_SLIDE_EAST), apply = slide("right") },
  { name = "PushedSouthByCurrent",
    check = behaviorPred("isWaterfall", MB_WATERFALL), apply = waterfallCurrent },
  { name = "MatJump", check = never, apply = matJump },
  { name = "MatSpin", check = never, apply = matSpin },
}

-- pokefirered/src/metatile_behavior.c:266 MetatileBehavior_IsForcedMovementTile
function M.isForcedMovementTile(beh)
  if beh == nil then return false end
  return (beh >= MB_WALK_EAST and beh <= MB_TRICK_HOUSE_PUZZLE_8_FLOOR)
    or (beh >= MB_EASTWARD_CURRENT and beh <= MB_SOUTHWARD_CURRENT)
    or beh == MB_WATERFALL
    or beh == MB_ICE
    or (beh >= MB_SPIN_RIGHT and beh <= MB_SPIN_DOWN)
end

function M.lookup(beh)
  for i = 1, #M.TABLE do
    if M.TABLE[i].check(beh) then return i, M.TABLE[i] end
  end
  return nil
end

-- pokefirered/src/field_player_avatar.c:252 TryDoMetatileBehaviorForcedMovement
function M.tryDoMetatileBehaviorForcedMovement(game, beh)
  for i = 1, #M.TABLE do
    local row = M.TABLE[i]
    if row.check(beh) then
      M.lastSpinTile = beh
      return row.apply(game) and true or false, i
    end
  end
  return forcedMovementNone()
end

-- pokefirered/src/field_player_avatar.c:931 PlayerApplyTileForcedMovement
function M.applyTileForcedMovement(game, beh)
  local moved = false
  for i = 1, #M.TABLE do
    if M.TABLE[i].check(beh) then
      moved = M.TABLE[i].apply(game) and true or moved
    end
  end
  return moved
end

-- pokefirered/src/field_player_avatar.c:200 TryUpdatePlayerSpinDirection
function M.tryUpdatePlayerSpinDirection(game)
  if not (M.forced and isSpinTile(M.lastSpinTile)) then return false end
  local P = player()
  if P.moving then return true end
  local beh = Collision.behavior(P.cellX, P.cellY)
  if isStopSpinning(beh) then return false end
  if isSpinTile(beh) then M.lastSpinTile = beh end
  M.applyTileForcedMovement(game, M.lastSpinTile)
  return true
end

M.stepCallbacks = {}

-- pokefirered/src/field_tasks.c:38 sPerStepCallbacks
function M.registerStepCallback(name, fn)
  M.stepCallbacks[name] = fn
end

M._stepTask = nil
M._stepData = {}

-- pokefirered/src/field_tasks.c:66 Task_RunPerStepCallback
function M.runStepCallback(game)
  local okCtx, Ctx = pcall(require, "src.core.game3.scripting.ctx")
  if not (okCtx and Ctx and Ctx.stepCallback) then return false end
  local Map = package.loaded["src.core.game3.map"]
  local okName, name = pcall(Ctx.stepCallback, Map and Map.current)
  if not (okName and name) then return false end
  -- pokefirered/src/field_tasks.c:96
  if Ctx._stepCallback ~= M._stepTask then
    M._stepTask = Ctx._stepCallback
    M._stepData = {}
  end
  local fn = M.stepCallbacks[name]
  if not fn then return false end
  local ok, res = pcall(fn, game, M._stepData)
  return (ok and res) and true or false
end

local function playerDestCoords()
  local P = player()
  if P.moving and P.targetX then return P.targetX, P.targetY end
  return P.cellX, P.cellY
end

-- pokefirered/src/field_tasks.c:173 IcefallCaveIcePerStepCallback
M.registerStepCallback("ice", function(_game, data)
  local state = data.state or 0
  if state == 0 then
    data.prevX, data.prevY = playerDestCoords()
    data.state = 1
  elseif state == 1 then
    local x, y = playerDestCoords()
    if x == data.prevX and y == data.prevY then return false end
    data.prevX, data.prevY = x, y
    local beh = Collision.behavior(x, y)
    if Collision.isThinIce(beh) then
      local Events = require("src.core.game3.scripting.natives_events")
      -- pokefirered/src/field_tasks.c:139 MarkIcePuzzleCoordVisited
      for i, c in ipairs(Events.ICEFALL_CAVE_ICE_COORDS) do
        if c[1] == x and c[2] == y then
          local Flags = require("src.core.game3.scripting.flags")
          local Space = require("src.core.game3.scripting.space")
          Flags.setFlag(Space.store, Space.vm and Space.vm.ctx or nil, i, true)
          break
        end
      end
      data.delay, data.state, data.iceX, data.iceY = 4, 2, x, y
    elseif Collision.isCrackedIce(beh) then
      data.delay, data.state, data.iceX, data.iceY = 4, 3, x, y
    end
  elseif data.delay ~= 0 then
    data.delay = data.delay - 1
  else
    local Events = require("src.core.game3.scripting.natives_events")
    local Field = require("src.core.game3.field")
    local SE = require("src.core.game3.se_ids")
    if state == 2 then
      se(SE.SE_ICE_CRACK)
      Field.setMetatile(data.iceX, data.iceY, Events.METATILE_SEAFOAM_CRACKED_ICE, false)
    else
      se(SE.SE_ICE_BREAK)
      Field.setMetatile(data.iceX, data.iceY, Events.METATILE_SEAFOAM_ICE_HOLE, false)
      local Flags = require("src.core.game3.scripting.flags")
      local Space = require("src.core.game3.scripting.space")
      Flags.setVar(Space.store, Space.vm and Space.vm.ctx or nil, "VAR_TEMP_1", 1)
    end
    data.state = 1
  end
  return false
end)

function M.reset()
  M.forced = false
  M.lastSpinTile = nil
  local P = package.loaded["src.core.game3.player"]
  if P then
    P.spinning = false
    P.animDisabled = false
  end
end

-- pokefirered/src/field_player_avatar.c:1229 ClearPlayerAvatarInfo
function M.isForced()
  local mapId = Collision._mapId
  if mapId ~= M._mapId then
    M._mapId = mapId
    M.reset()
  end
  return M.forced
end

-- pokefirered/src/field_player_avatar.c:141 gPlayerAvatar.preventStep
function M.fieldControlsLocked()
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return true end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return true end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return true end
  return false
end

-- pokefirered/src/field_player_avatar.c:136 player_step
function M.onStepFinished(game)
  local P = player()
  if P.moving then return false end
  if M.fieldControlsLocked() then return false end
  M.isForced()
  if M.tryUpdatePlayerSpinDirection(game) then return true end
  local moved = M.tryDoMetatileBehaviorForcedMovement(game, Collision.behavior(P.cellX, P.cellY))
  return moved and true or false
end

return M

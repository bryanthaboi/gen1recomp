-- Gen 2 map object: walks / spins from SPRITEMOVEDATA_* + object_event
-- radius (not Gen 1's WALK/STAY + range strings).  Drawn via SpriteRenderer.

local Logger = require("src.core.Logger")
local Map = require("src.world.gen2.Map")
local Movement = require("src.script.gen2.Movement")
local Permissions = require("src.world.gen2.Permissions")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")

local NPC = {}
NPC.__index = NPC

local STEP_FRAMES = 16

-- OBJECT_ACTION_SPIN's own cadence: the spin frameset turns the sprite a
-- quarter every four frames, which is what makes a teleporting object read as
-- spinning rather than as facing one way while it rises.
local SPIN_FACINGS = { "down", "left", "up", "right" }
local SPIN_FRAMES_PER_FACING = 4

-- constants/map_object_constants.asm
local MOVE = {
  STILL = 1,
  WANDER = 2,
  SPINRANDOM_SLOW = 3,
  WALK_UP_DOWN = 4,
  WALK_LEFT_RIGHT = 5,
  STANDING_DOWN = 6,
  STANDING_UP = 7,
  STANDING_LEFT = 8,
  STANDING_RIGHT = 9,
  SPINRANDOM_FAST = 10,
  -- data/sprites/map_objects.asm:181-187
  POKEMON = 0x16,
  SPINCOUNTERCLOCKWISE = 0x1e,
  SPINCLOCKWISE = 0x1f,
  -- The three rows whose palette-flags byte is `STRENGTH_BOULDER | BIG_OBJECT`
  -- (data/sprites/map_objects.asm).  BIG_OBJECT is the bit IsNPCAtCoord tests
  -- before handing the coordinate to WillObjectIntersectBigObject -- so the
  -- object is TWO cells wide and two tall for collision and for an A press
  -- alike.  Gold puts exactly two of them on maps: the sleeping Snorlax
  -- outside Vermilion ($15) and PLAYERS_HOUSE_2F's big doll decoration ($21).
  BIGDOLLSYM = 0x15,
  BIGDOLLASYM = 0x20,
  BIGDOLL = 0x21,
  SWIM_WANDER = 0x24,
}

local BIG_OBJECT = {
  [MOVE.BIGDOLLSYM] = true,
  [MOVE.BIGDOLLASYM] = true,
  [MOVE.BIGDOLL] = true,
}

-- Every SPRITEMOVEDATA row whose flags1 byte carries FIXED_FACING
-- (data/sprites/map_objects.asm): STILL $01, BIGDOLLSYM $15, POKEMON $16,
-- SUDOWOODO $17, SMASHABLE_ROCK $18, STRENGTH_BOULDER $19, SHADOW $1b,
-- EMOTE $1c, BIGDOLLASYM $20, BIGDOLL $21, BOULDERDUST $22, GRASS $23.
-- CopySpriteMovementData rewrites OBJECT_FLAGS1 out of the row on every
-- spawn, so this is re-seeded in NPC.new rather than latched: a scripted
-- `fix_facing` correctly dies at the next rebuildPeople, exactly as a
-- respawned object loses it on the cart.
local FIXED_FACING_MOVE = {
  [0x01] = true, [0x15] = true, [0x16] = true, [0x17] = true,
  [0x18] = true, [0x19] = true, [0x1b] = true, [0x1c] = true,
  [0x20] = true, [0x21] = true, [0x22] = true, [0x23] = true,
}

-- SetFacingBigDoll (engine/overworld/map_object_action.asm): $15 always draws
-- through FacingBigDollSymmetric and $20 always through
-- FacingBigDollAsymmetric, but $21 reads wVariableSprites[SPRITE_BIG_DOLL] and
-- takes the symmetric table only for SPRITE_BIG_SNORLAX and SPRITE_BIG_LAPRAS.
-- SPRITE_BIG_ONIX is the doll a mirrored left half would draw wrong.
local BIG_DOLL_SYM_SPRITES = {
  SPRITE_BIG_SNORLAX = true,
  SPRITE_BIG_LAPRAS = true,
}

function NPC.bigFacing(movement, spriteId)
  if movement == MOVE.BIGDOLLSYM then return "sym" end
  if movement == MOVE.BIGDOLLASYM then return "asym" end
  if movement ~= MOVE.BIGDOLL then return nil end
  return BIG_DOLL_SYM_SPRITES[spriteId] and "sym" or "asym"
end

local FACING_FROM_MOVE = {
  [MOVE.STILL] = "down",
  [MOVE.WANDER] = "down",
  [MOVE.SPINRANDOM_SLOW] = "down",
  [MOVE.WALK_UP_DOWN] = "down",
  [MOVE.WALK_LEFT_RIGHT] = "left",
  [MOVE.STANDING_DOWN] = "down",
  [MOVE.STANDING_UP] = "up",
  [MOVE.STANDING_LEFT] = "left",
  [MOVE.STANDING_RIGHT] = "right",
  [MOVE.SPINRANDOM_FAST] = "down",
  [MOVE.SWIM_WANDER] = "down",
  -- The two spin rows are the only ones in the table that do NOT start facing
  -- down: `db LEFT ; facing` and `db RIGHT ; facing` (data/sprites/map_objects
  -- .asm:245-256).  They are the first quarter of their own cycle.
  [MOVE.SPINCOUNTERCLOCKWISE] = "left",
  [MOVE.SPINCLOCKWISE] = "right",
}

local DIRS_Y = { "up", "down" }
local DIRS_X = { "left", "right" }
local DIRS_ANY = { "up", "down", "left", "right" }

-- _MovementSpinTurnRight / _MovementSpinTurnLeft's two facing tables
-- (engine/overworld/map_objects.asm:826-843), read as "from this facing, next
-- this one".  The cart indexes them by OBJECT_DIRECTION >> 2, i.e. the OW_DOWN
-- / OW_UP / OW_LEFT / OW_RIGHT order; this is the same four rows by name.
--
-- Unlike the two RANDOM spins these are DETERMINISTIC quarter turns -- which is
-- the whole point of them, because a spinner whose facing is the puzzle (the
-- Team Rocket base's guard patterns) has to be predictable.
local SPIN_NEXT = {
  clockwise        = { down = "left", up = "right", left = "up", right = "down" },
  counterclockwise = { down = "right", up = "left", left = "down", right = "up" },
}

-- `ld a, $10 / ld [OBJECT_STEP_DURATION]` then STEP_TYPE_SLEEP
-- (_MovementSpinRepeat, map_objects.asm:809-823): a fixed sixteen frames on
-- each quarter, no Random anywhere in the loop.
local SPIN_TURN_FRAMES = 16

-- SetFacingBounce steps OBJECT_STEP_FRAME once a frame and reads bit 3, so a
-- mon object holds each icon frame for eight -- map_object_action.asm:184-201
local BOUNCE_PERIOD = 16
local BOUNCE_HALF = 8

local function rand(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

local function randf()
  if love and love.math and love.math.random then
    return love.math.random()
  end
  return math.random()
end

local function patternFor(movement)
  if movement == MOVE.WALK_UP_DOWN then
    return "walk", DIRS_Y
  elseif movement == MOVE.WALK_LEFT_RIGHT then
    return "walk", DIRS_X
  elseif movement == MOVE.WANDER or movement == MOVE.SWIM_WANDER then
    return "walk", DIRS_ANY
  elseif movement == MOVE.SPINRANDOM_SLOW then
    return "spin", DIRS_ANY, 60, 180
  elseif movement == MOVE.SPINRANDOM_FAST then
    return "spin", DIRS_ANY, 20, 60
  elseif movement == MOVE.SPINCLOCKWISE then
    return "turn", SPIN_NEXT.clockwise, SPIN_TURN_FRAMES, SPIN_TURN_FRAMES
  elseif movement == MOVE.SPINCOUNTERCLOCKWISE then
    return "turn", SPIN_NEXT.counterclockwise,
      SPIN_TURN_FRAMES, SPIN_TURN_FRAMES
  end
  return "stand", nil
end

-- Gen 1's two behaviour strings onto the cart's SPRITEMOVEDATA byte.  STAY is
-- STANDING_*, never STILL: STILL carries FIXED_FACING (above) and an object
-- that cannot turn is not a trailer.  WALK gets a radius default because Gen 2
-- refuses every step outside it and radius 0 would freeze the object.
local GEN1_STAY = {
  UP = MOVE.STANDING_UP, DOWN = MOVE.STANDING_DOWN,
  LEFT = MOVE.STANDING_LEFT, RIGHT = MOVE.STANDING_RIGHT,
}

-- The sheet a Gen 1 NPC.new falls back to when the SPRITE_* id it names is
-- not in Gold's table.  src/mods/Gen2Compat.lua points this at the live
-- player's; a mod overwrites npc.sprite the line after the call, so a missing
-- record must not decide whether the entity exists.
NPC.fallbackSpriteDef = nil

local warnedGen1Sprite = {}

-- src/world/NPC.lua:23's shape: (data, mapId, objDef).  Sniffed rather than
-- given its own name so `getmetatable(npc) == require("src.world.NPC")` holds
-- for a gen2compat mod -- the facade IS this table (src/mods/Gen2Compat.lua),
-- and a constructor that lived beside it would hand back objects carrying a
-- different metatable than the module the mod holds.
local function fromGen1(data, mapId, objDef)
  local movement, range = objDef.movement, objDef.range
  local mv, radius
  if type(movement) == "number" then
    mv, radius = movement, objDef.radius
  elseif movement == "WALK" then
    if range == "UP_DOWN" then mv = MOVE.WALK_UP_DOWN
    elseif range == "LEFT_RIGHT" then mv = MOVE.WALK_LEFT_RIGHT
    else mv = MOVE.WANDER end
    radius = objDef.radius or { x = 3, y = 3 }
  else
    mv = GEN1_STAY[range] or MOVE.STANDING_DOWN
  end
  local sprites = data and (rawget(data, "gen2Sprites") or data.sprites)
  local def = sprites and objDef.sprite and sprites[objDef.sprite]
  if not def then
    local key = tostring(objDef.sprite)
    if not warnedGen1Sprite[key] then
      warnedGen1Sprite[key] = true
      Logger.warn("src.world.NPC: no %s in Gold's sprite table; using the "
        .. "player sheet", key)
    end
    local fallback = NPC.fallbackSpriteDef
    def = type(fallback) == "function" and fallback() or fallback
  end
  if not def then
    error("src.world.NPC: no sprite record for " .. tostring(objDef.sprite), 0)
  end
  local npc = NPC.new(mapId, {
    index = objDef.index, name = objDef.name, sprite = objDef.sprite,
    movement = mv, radius = radius, x = objDef.x, y = objDef.y,
  }, def)
  -- the Gen 1 SPRITE_* id the caller passed in, which Gold's objDef does not
  -- keep once the sheet is resolved
  npc.spriteId = objDef.sprite
  return npc
end

function NPC.new(mapId, objDef, spriteDef)
  -- Gen 1 passes the DATA table first; Gold's first argument is always the
  -- map id string.
  if type(mapId) == "table" then return fromGen1(mapId, objDef, spriteDef) end
  local movement = objDef.movement or MOVE.STILL
  local kind, dirs, spinLo, spinHi = patternFor(movement)
  local radius = objDef.radius or {}
  local self = setmetatable({
    def = objDef,
    id = string.format("%s_obj_%d", mapId, objDef.index or 0),
    mapId = mapId,
    cellX = objDef.x,
    cellY = objDef.y,
    homeX = objDef.x,
    homeY = objDef.y,
    px = objDef.x * 16,
    py = objDef.y * 16,
    facing = FACING_FROM_MOVE[movement] or "down",
    moving = false,
    progress = 0,
    stepFlip = false,
    -- OBJECT_FLAGS2's IN_GRASS_F (engine/overworld/map_objects.asm:247), set
    -- from the spawn tile by the STEP_TYPE_RESET latch in NPC:update.
    inGrass = false,
    spawnLatched = false,
    frozen = false,
    kind = kind,
    roamDirs = dirs,
    radiusX = radius.x or 0,
    radiusY = radius.y or 0,
    spinLo = spinLo,
    spinHi = spinHi,
    bigObject = BIG_OBJECT[movement] == true,
    bigFacing = NPC.bigFacing(movement, spriteDef and spriteDef.id),
    fixedFacing = FIXED_FACING_MOVE[movement] or nil,
    bouncing = movement == MOVE.POKEMON or nil,
    bounceStep = 0,
    timer = rand(30, 120),
    sprite = SpriteRenderer.new(spriteDef, string.format("%s_obj_%d", mapId, objDef.index or 0)),
    -- The sheet is grayscale and carries no alpha; PAL_OW_* crossed with the
    -- time of day decides the real colors AND which pixels are transparent.
    -- World:applyPalettes pushes them into the SpriteRenderer and refreshes
    -- them when the clock rolls over, so a pooled NPC never keeps yesterday's.
    spriteDef = spriteDef,
  }, NPC)
  return self
end

-- `variablesprite` on a slot this object reads through: the sheet changes and
-- NOTHING else does.  Script_variablesprite writes one byte of wVariableSprites
-- (engine/overworld/scripting.asm:869) and the `special LoadUsedSpritesGFX`
-- beside it reloads the tiles -- the object STRUCT is never touched, so its
-- coordinates, its facing, its FROZEN_F and its identity as wLastTalked all
-- survive.  Two map scripts depend on that: LassAliceScript's
-- `applymovement ... Movement_NinjaSpin / faceplayer / variablesprite / special
-- LoadUsedSpritesGFX / faceplayer` (maps/FuchsiaGym.asm:61-66, and the same
-- shape for Linda, Cindy and Barry) and CopycatsHouse2F.asm:23-48.
--
-- So this repaints in place rather than the World retiring the NPC and letting
-- rebuildPeople make a new one: a new table would strand World.talkNpc,
-- .trainerNpc, .followState and any running moveState on an object that is no
-- longer on the map, and drop the ninja back to her map-def cell and default
-- facing halfway through unmasking.
function NPC:setSpriteDef(spriteDef)
  if not spriteDef or spriteDef == self.spriteDef then return false end
  self.spriteDef = spriteDef
  self.sprite = SpriteRenderer.new(spriteDef, self.id)
  -- bigFacing is derived from the SHEET (NPC.bigFacing keys off spriteDef.id),
  -- so it is the one cached field that has to be recomputed with it.
  self.bigFacing = NPC.bigFacing(self.def and self.def.movement, spriteDef.id)
  return true
end

function NPC:inRadius(tx, ty)
  return math.abs(tx - self.homeX) <= self.radiusX
     and math.abs(ty - self.homeY) <= self.radiusY
end

-- WillObjectIntersectBigObject (engine/overworld/npc_movement.asm): the object's
-- own coordinates are the TOP LEFT of the blob, and a cell belongs to it when
-- both `coord - object` land in 0..1 (`sub [hl] / jr c, .nope / cp 2 / jr nc`).
-- Every other object is the one cell it stands on, which is what the fall
-- through to a plain compare says.
function NPC:covers(cx, cy)
  if not self.bigObject then
    return self.cellX == cx and self.cellY == cy
  end
  local dx, dy = cx - self.cellX, cy - self.cellY
  return dx >= 0 and dx < 2 and dy >= 0 and dy < 2
end

function NPC:facePlayer(player)
  -- ApplyObjectFacing (engine/overworld/scripting.asm:856) refuses a
  -- fixed-facing object outright, and _DoesSpriteHaveFacings
  -- (engine/overworld/overworld.asm:343) returns carry for a STILL_SPRITE,
  -- whose sheet has only the one pose to turn to.
  if self.fixedFacing then return end
  if self.spriteDef and (self.spriteDef.frames or 0) <= 1 then return end
  local dx = player.cellX - self.cellX
  local dy = player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

function NPC:scriptFace(dir)
  if self.fixedFacing then return end
  if dir then self.facing = dir end
end

-- The direction the object MOVES in and the direction it is DRAWN facing are
-- two different bytes.  InitStep skips the OBJECT_DIRECTION write while
-- FIXED_FACING_F is set (engine/overworld/map_objects.asm:284-294) and
-- SetFacingStepAction bails to SetFacingCurrent while SLIDING_F is set
-- (engine/overworld/map_object_action.asm:48), so either flag walks the object
-- across the map without turning it.
function NPC:scriptStep(dir)
  if self.moving then return false end
  self.stepDir = dir or self.facing
  if not self.fixedFacing and not self.sliding then
    self.facing = self.stepDir
  end
  local d = Map.DELTA[self.stepDir]
  if not d then
    self.stepDir = nil
    return false
  end
  self.targetX, self.targetY = self.cellX + d[1], self.cellY + d[2]
  self.moving = true
  self.progress = 0
  self.frozen = true
  return true
end

-- StepFunction_TeleportFrom / _TeleportTo (engine/overworld/map_objects.asm).
-- `from` is sixteen frames of OBJECT_ACTION_SPIN on the spot and then sixteen
-- more spinning while OBJECT_JUMP_HEIGHT walks OBJECT_SPRITE_Y_OFFSET up a
-- sine, so the object lifts off its tile before `disappear` takes it away.
-- `to` is the same three beats in reverse: a still wait, a spinning descent
-- from the same curve, and one last spin once it has landed.
--
-- The step type owns the object until it is done, which is why this sets
-- `frozen`: World:beginMovement's own sleep counter is what waits it out.
function NPC:scriptTeleport(mode, frames)
  local beat = Movement.TELEPORT_BEAT_FRAMES
  self.teleport = {
    mode = mode == "to" and "to" or "from",
    frame = 0,
    frames = frames or ((mode == "to") and 3 * beat or 2 * beat),
  }
  self.frozen = true
  self.spriteYOffset = 0
  return true
end

-- One frame of that step type.  Returns false once the last beat is over, so
-- the caller can drop the state.
function NPC:updateTeleport()
  local st = self.teleport
  if not st then return false end
  local beat = Movement.TELEPORT_BEAT_FRAMES
  st.frame = st.frame + 1
  local spinning = true
  if st.mode == "from" then
    if st.frame <= beat then
      -- .DoSpin: the object is still on its tile for the first beat.
      self.spriteYOffset = 0
    else
      -- .DoSpinRise: OBJECT_JUMP_HEIGHT starts at $10 and is incremented once
      -- a frame, so the sine walks the sprite off the top of the tile.
      self.spriteYOffset = Movement.teleportYOffset(
        Movement.TELEPORT_RISE_HEIGHT + (st.frame - beat))
    end
  elseif st.frame <= beat then
    -- .DoWait holds OBJECT_ACTION_00, so nothing spins: the object simply
    -- waits at the far end of the descent curve.
    spinning = false
    self.spriteYOffset = Movement.teleportYOffset(
      Movement.TELEPORT_FALL_HEIGHT)
  elseif st.frame <= 2 * beat then
    -- .DoDescent, the rise's curve read backwards down to the tile.
    self.spriteYOffset = Movement.teleportYOffset(st.frame - beat)
  else
    -- .DoFinalSpin, back on the ground.
    self.spriteYOffset = 0
  end
  if spinning then
    self.facing = SPIN_FACINGS[
      (math.floor(st.frame / SPIN_FRAMES_PER_FACING) % #SPIN_FACINGS) + 1]
  end
  if st.frame >= st.frames then
    self.teleport = nil
    self.spriteYOffset = 0
    return false
  end
  return true
end

-- Movement_tree_shake (engine/overworld/movement.asm:334): OBJECT_ACTION is
-- set to OBJECT_ACTION_WEIRD_TREE and the object is parked on
-- STEP_TYPE_SLEEP for 24 frames.  Same lifetime as scriptTeleport above --
-- the step type owns the object, and World:beginMovement waits it out on the
-- sleep counter -- so it sets `frozen` the same way.
function NPC:scriptTreeShake(frames)
  self.treeShake = {
    frame = 0,
    frames = frames or Movement.TREE_SHAKE_FRAMES,
  }
  self.frozen = true
  return true
end

-- One frame of it.  Returns false on the last beat so the caller can drop the
-- state, matching NPC:updateTeleport.
function NPC:updateTreeShake()
  local st = self.treeShake
  if not st then return false end
  st.frame = st.frame + 1
  if st.frame >= st.frames then
    self.treeShake = nil
    return false
  end
  return true
end

function NPC:scriptRockSmash(frames)
  -- engine/overworld/map_objects.asm:1462
  self.rockSmash = {
    frame = 0,
    frames = frames or 10,
  }
  self.frozen = true
  return true
end

function NPC:updateRockSmash()
  local st = self.rockSmash
  if not st then return false end
  st.frame = st.frame + 1
  if st.frame >= st.frames then
    self.rockSmash = nil
    return false
  end
  return true
end

-- `passable` is the follower's escape (src/world/gen2/Follower.lua), the same
-- name and meaning src/world/Collision.lua:20 gives it under Gen 1.
local function occupied(entities, tx, ty, self)
  if not entities then return false end
  for _, e in ipairs(entities) do
    if e ~= self and not e.passable then
      if e.cellX == tx and e.cellY == ty then return true end
      if e.moving and e.targetX == tx and e.targetY == ty then return true end
    end
  end
  return false
end

-- the movement.collision chain's vanilla link and the verdict it wraps, both
-- hoisted so an empty chain allocates nothing (src/world/gen2/Player.lua and
-- src/world/Collision.lua are the same shape)
local function passthrough(allowed) return allowed end

local function wanderVerdict(self, map, entities, tx, ty)
  if not self:inRadius(tx, ty) then return false, "radius" end
  if not map:isWalkable(tx, ty) then return false, "tile" end
  -- don't walk out through doors
  if map:warpAt(tx, ty) then return false, "warp" end
  if occupied(entities, tx, ty, self) then return false, "entity" end
  return true
end

function NPC:walkPhase()
  -- SetFacingStepAction bails to SetFacingCurrent BEFORE it increments
  -- OBJECT_STEP_FRAME (engine/overworld/map_object_action.asm:48), so a
  -- sliding object holds its step frame as well as its facing: it glides.
  if self.sliding then return 0 end
  if not self.moving then return 0 end
  local frames = self.stepFrames or STEP_FRAMES
  local p = self.progress % frames
  return (p >= frames / 4 and p < frames * 3 / 4) and 1 or 0
end

-- OBJECT_ACTION_BOUNCE's two columns, SetFacingBounce and
-- SetFacingFreezeBounce -- engine/overworld/map_object_action.asm:184-201
function NPC:bounceFrame()
  if not self.bouncing then return nil end
  if self.frozen then return 0 end
  return ((self.bounceStep or 0) >= BOUNCE_HALF) and 1 or 0
end

-- Gen 1's seven-value entity pose (src/world/NPC.lua:124), on the class so a
-- mod poses the object it is FOLLOWING, not only one it built itself.
function NPC:pose()
  return self.sprite, self.px, self.py + (self.spriteYOffset or 0),
         self.facing, self:walkPhase(), self.stepFlip, false
end

-- SetTallGrassFlags' test (engine/overworld/map_objects.asm:247).
function NPC.grassAt(map, cx, cy)
  if not (map and map.cellCollision and cx and cy) then return false end
  local coll = map:cellCollision(cx, cy)
  return Permissions.isSuperTallGrass(coll) or Permissions.isGrass(coll)
end

function NPC:update(map, entities)
  -- STEP_TYPE_RESET's StepFunction_Reset reads the object's OWN tile into
  -- SetTallGrassFlags (engine/overworld/map_objects.asm:498-511, :196-208).
  if not self.spawnLatched and map then
    self.spawnLatched = true
    self.inGrass = NPC.grassAt(map, self.cellX, self.cellY)
  end
  if self.bouncing and not self.frozen then
    self.bounceStep = ((self.bounceStep or 0) + 1) % BOUNCE_PERIOD
  end
  -- The teleport step type owns the object outright (it replaces
  -- STEP_TYPE_FROM_MOVEMENT until its last beat), so it runs above the frozen
  -- gate the way the walk interpolation does.
  if self.teleport then
    self:updateTeleport()
    return
  end
  -- STEP_TYPE_SLEEP with OBJECT_ACTION_WEIRD_TREE owns the object the same
  -- way the teleport step type does, so it sits in the same position.
  if self.treeShake then
    self:updateTreeShake()
    return
  end
  if self.rockSmash then
    self:updateRockSmash()
    return
  end
  -- NPC_CHANGE_FACING (src/world/NPC.lua:71): one walk cycle in place, no
  -- translation.  Above the moving arm because it has no targetX to reach,
  -- and the arm below would assign cellX = nil a frame later.
  if self.marching then
    self.moving = true
    self.progress = self.progress + 1
    if self.progress >= (self.stepFrames or STEP_FRAMES) then
      self.progress = 0
      self.moving = false
      self.marching = false
      self.stepFlip = not self.stepFlip
    end
    return
  end
  if self.moving then
    -- NormalStep's begin-of-step grass work (engine/overworld/movement.asm:657-674);
    -- UpdateTallGrassFlags only RE-tests while IN_GRASS is set (map_objects.asm:226).
    if self.progress == 0 and map then
      local grass = NPC.grassAt(map, self.targetX, self.targetY)
      if self.inGrass then self.inGrass = grass end
      self.grassShake = grass or nil
    end
    self.progress = self.progress + 1
    -- Toward the TARGET, not one cell along stepDir: a follower's ledge hop is
    -- a two-cell move over one step (src/world/gen2/Player.lua:150 does the
    -- same), and `stepFrames` is what lets it keep pace with a bike.
    local frames = self.stepFrames or STEP_FRAMES
    local moved = math.floor(self.progress * 16 / frames)
    local dx = (self.targetX or self.cellX) - self.cellX
    local dy = (self.targetY or self.cellY) - self.cellY
    self.px = self.cellX * 16 + dx * moved
    self.py = self.cellY * 16 + dy * moved
    if self.progress >= frames then
      self.cellX, self.cellY = self.targetX, self.targetY
      self.targetX, self.targetY = nil, nil
      self.px, self.py = self.cellX * 16, self.cellY * 16
      self.moving = false
      self.stepDir = nil
      self.stepFlip = not self.stepFlip
      -- CopyCoordsTileToLastCoordsTile -> SetTallGrassFlags at the step's end
      -- (map_objects.asm:196-208, :247).
      if map then
        self.inGrass = NPC.grassAt(map, self.cellX, self.cellY)
      end
    end
    return
  end

  if self.frozen or self.kind == "stand" then return end

  self.timer = self.timer - 1
  if self.timer > 0 then return end

  if self.kind == "spin" then
    self.timer = rand(self.spinLo or 60, self.spinHi or 180)
    self.facing = self.roamDirs[rand(1, #self.roamDirs)]
    return
  end

  -- SPINCLOCKWISE / SPINCOUNTERCLOCKWISE: one quarter turn in a FIXED order
  -- every sixteen frames, never a re-roll (see SPIN_NEXT).  Route 32's
  -- Youngster Gordon, Route 35's Firebreather Walt, RadioTower4F's GruntM10 and
  -- the Route 40/41 swimmers all carry one of these two rows and used to fall
  -- through to "stand", so none of them turned at all.
  if self.kind == "turn" then
    self.timer = self.spinLo or SPIN_TURN_FRAMES
    self.facing = self.roamDirs[self.facing] or self.facing
    return
  end

  -- walk
  self.timer = rand(30, 180)
  local dir = self.roamDirs[rand(1, #self.roamDirs)]
  self.facing = dir
  if randf() < 0.5 then return end -- sometimes just turn, like Gen 1
  local d = Map.DELTA[dir]
  local tx, ty = self.cellX + d[1], self.cellY + d[2]
  local allowed, why = wanderVerdict(self, map, entities, tx, ty)
  -- movement.collision serves every mover, not just the player: Gen 1 runs the
  -- NPC wander through the same src/world/Collision.lua canMove the player
  -- uses, so a mod that widens or narrows movement sees both here too.  Guarded
  -- like the player's site; a mod-free boot pays one table lookup.  The two
  -- extra reasons ("radius", "warp") are Gen 2's own refusals -- an object_event
  -- may not leave its radius and never walks out through a door -- and are
  -- additions to Gen 1's bounds / tile / entity, never renames of them.
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = self, dir = dir,
                  fromX = self.cellX, fromY = self.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
  end
  if not allowed then return end
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.progress = 0
end

-- FacingBigDollSymmetric (data/sprites/facings.asm): sixteen OAM entries over a
-- 32x32 square, and the right half is the left half X-FLIPPED -- the sheet only
-- carries the eight tiles of one side.  Those eight are the sheet's first two
-- 16x16 frames stacked, so the doll is frame 0 over frame 1, mirrored across
-- the middle.  Drawn from the sprite's resolved (palette-baked) image so it
-- wears the same OBJ palette every other Gen 2 sprite does.
--
-- The 4px lift is the one SpriteRenderer:draw applies to every overworld
-- sprite; the object's own cell is the doll's top left, so the square lands on
-- the 2x2 blob NPC:covers describes.
function NPC:drawBig()
  local image = self.sprite.resolveImage and self.sprite:resolveImage()
  if not image then return end
  local G = love.graphics
  local x, y = math.floor(self.px), math.floor(self.py) - 4
  for half = 0, 1 do
    local quad = self.sprite.frames and self.sprite.frames[half]
    if quad then
      G.draw(image, quad, x, y + half * 16)
      G.draw(image, quad, x + 32, y + half * 16, 0, -1, 1)
    end
  end
end

-- FacingBigDollAsymmetric (data/sprites/facings.asm), transcribed as its own
-- `db y, x, attributes, tile index` rows: fourteen 8x8 tiles over the same
-- 32x32 square, with the lower left two cells left empty and two tiles reused
-- X-flipped.  A doll with no mirror line (SPRITE_BIG_ONIX) cannot be drawn by
-- doubling one half the way drawBig does.
local BIG_DOLL_ASYM = {
  {  0,  0, false, 0x00 },
  {  0,  8, false, 0x01 },
  {  8,  0, false, 0x04 },
  {  8,  8, false, 0x05 },
  { 16,  8, false, 0x07 },
  { 24,  8, false, 0x0a },
  {  0, 24, false, 0x03 },
  {  0, 16, false, 0x02 },
  {  8, 24, true,  0x02 },
  {  8, 16, false, 0x06 },
  { 16, 24, false, 0x09 },
  { 16, 16, false, 0x08 },
  { 24, 24, true,  0x04 },
  { 24, 16, false, 0x0b },
}

NPC.BIG_DOLL_ASYM = BIG_DOLL_ASYM

-- A tile index is four to a 16x16 sheet frame, row major, the way
-- FacingStepDown0's $00..$03 read off the standing-down frame -- so tile t
-- sits at ((t % 2) * 8, (t // 4) * 16 + ((t % 4) // 2) * 8) in the sheet.
function NPC.bigDollTileRect(tile)
  return (tile % 2) * 8,
    math.floor(tile / 4) * 16 + math.floor((tile % 4) / 2) * 8
end

function NPC:bigDollQuads(image)
  if self.bigDollQuadCache then return self.bigDollQuadCache end
  local iw, ih = image:getDimensions()
  local quads = {}
  for tile = 0, 11 do
    local sx, sy = NPC.bigDollTileRect(tile)
    quads[tile] = love.graphics.newQuad(sx, sy, 8, 8, iw, ih)
  end
  self.bigDollQuadCache = quads
  return quads
end

function NPC:drawBigAsym()
  local image = self.sprite.resolveImage and self.sprite:resolveImage()
  if not image then return end
  local G = love.graphics
  local x, y = math.floor(self.px), math.floor(self.py) - 4
  local quads = self:bigDollQuads(image)
  for _, row in ipairs(BIG_DOLL_ASYM) do
    local quad = quads[row[4]]
    if quad then
      if row[3] then
        G.draw(image, quad, x + row[2] + 8, y + row[1], 0, -1, 1)
      else
        G.draw(image, quad, x + row[2], y + row[1])
      end
    end
  end
end

function NPC:draw(ox, oy, scale)
  -- Gen 1 spells this draw(camX, camY) and SpriteRenderer subtracts them
  -- (src/world/NPC.lua:129).  Two arguments means that call, not a missing
  -- scale: G.scale(nil, nil) would either raise or draw unscaled at an
  -- offset, which is the silent wrong answer.
  if scale == nil then return self:draw(-(ox or 0), -(oy or 0), 1) end
  local G = love.graphics
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  -- OBJECT_SPRITE_Y_OFFSET is added to the OBJ's y when it is written to OAM,
  -- so it moves the sprite without moving the object off its tile.
  local yOffset = self.spriteYOffset or 0
  if self.bigObject then
    G.push()
    G.translate(0, yOffset)
    if self.bigFacing == "asym" then self:drawBigAsym() else self:drawBig() end
    G.pop()
  elseif self.treeShake then
    -- SetFacingWeirdTree cycles four quarters off FacingWeirdTree0-3
    -- (data/sprites/facings.asm:46-52, :185-190, :192-197): quarters 0 and 2
    -- are FacingStepDown0's tiles $00-$03, quarter 1 is $04-$07 (the "up"
    -- frame's tiles) and quarter 3 is that same frame mirrored.  So the tree
    -- rocks right, upright, left, upright rather than turning to face.
    local q = Movement.treeShakeIndex(self.treeShake.frame)
    local facing = (q == 1 or q == 3) and "up" or "down"
    self.sprite:draw(
      self.px, self.py + yOffset, 0, 0,
      facing, 0, false, false, q == 3)
  elseif self.rockSmash then
    -- engine/overworld/map_objects.asm:1462
    if (self.rockSmash.frame % 2) == 0 then
      G.pop()
      return
    end
    self.sprite:draw(
      self.px, self.py + yOffset, 0, 0,
      self.facing, self:walkPhase(), self.stepFlip)
  else
    self.sprite:draw(
      self.px, self.py + yOffset, 0, 0,
      self.facing, self:walkPhase(), self.stepFlip,
      false, false, self:bounceFrame())
  end
  G.pop()
end

NPC.MOVE = MOVE
NPC.patternFor = patternFor

return NPC

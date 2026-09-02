-- Minimal Gen 2 overworld player: tile-grid steps at 16 frames/cell.
-- Draws via shared SpriteRenderer (same 16x96 facing layout as Gen 1).

local Map = require("src.world.gen2.Map")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Player = {}
Player.__index = Player

local STEP_FRAMES = 16
local TURN_FRAMES = 4

-- The walking duration, exported so World can halve it for a bike step
-- (.DoStep's STEP_BIKE arm, engine/overworld/player_movement.asm).  The leg
-- cadence below deliberately does NOT scale with it: animClock keeps counting
-- at the walking rate, which is what stops a bike step flickering the legs.
Player.STEP_FRAMES = STEP_FRAMES

-- engine/overworld/map_objects.asm:1815
local JUMP_Y = {
  -4, -6, -8, -10, -11, -12, -12, -12,
  -11, -10, -9, -8, -6, -4, 0, 0,
}

-- FacingFish*'s loose rod OAM, offset from the sprite's top-left, and which
-- 8x8 of the sheet's rod row it draws (data/sprites/facings.asm:122-152).
local ROD_OAM = {
  down  = { dx =  0, dy = 16, tile = 0 },
  up    = { dx =  0, dy = -8, tile = 0 },
  left  = { dx = -8, dy =  5, tile = 1, flip = true },
  right = { dx = 16, dy =  5, tile = 1 },
}

-- The sheet row LoadFishingGFX lays over each standing frame's bottom tiles
-- (engine/events/fishing_gfx.asm:2-20).
local FISH_ROW = { down = 0, up = 1, left = 2, right = 2 }

function Player.new(cx, cy, facing, spriteDef)
  local self = setmetatable({
    cellX = cx, cellY = cy,
    px = cx * 16, py = cy * 16,
    facing = facing or "down",
    moving = false,
    progress = 0,
    turnTimer = 0,
    turnArmed = true,
    stepFlip = false,
    -- OBJECT_FLAGS2's IN_GRASS_F (engine/overworld/map_objects.asm:247).
    inGrass = false,
    animClock = 0,
    -- Frames this cell takes; World rewrites it per step from the STEP_* the
    -- player's state picks, and a step already under way keeps the one it
    -- started with.
    stepFrames = STEP_FRAMES,
    sprite = nil,
    spriteDef = spriteDef,
  }, Player)
  if spriteDef then
    self.sprite = SpriteRenderer.new(spriteDef, "player")
  end
  return self
end

function Player:setSprite(spriteDef)
  if not spriteDef then return end
  -- pokegold engine/overworld/overworld.asm:55-64
  local ok, sprite = pcall(SpriteRenderer.new, spriteDef, "player")
  if not (ok and sprite) then return end
  self.spriteDef = spriteDef
  self.sprite = sprite
end

-- the movement.collision chain sees the boolean; a wrapper that flips it
-- rewrites ctx.reason to say why (the engine's own reasons are bounds / tile /
-- entity, the same three src/world/Collision.lua names under Gen 1), so the
-- hook stays a single-value middleware.
local function passthrough(allowed) return allowed end

-- The verdict on one step, hoisted so the hooked and unhooked paths cannot
-- drift.  World:movePlayer has already vetoed the direction by handing us a
-- refusingMap when GetMovementPermissions says no, so a side-wall veto arrives
-- here as "tile" exactly like a wall does.
local function verdict(self, map, entities, tx, ty)
  if not map:inBounds(tx, ty) then return false, "bounds" end
  if not map:isWalkable(tx, ty) then return false, "tile" end
  if entities then
    for _, e in ipairs(entities) do
      -- `passable` is the follower's escape, src/world/Collision.lua:20's
      -- name and meaning: the player walks straight through it.
      if e ~= self and not e.passable then
        if e.cellX == tx and e.cellY == ty then return false, "entity" end
        if e.moving and e.targetX == tx and e.targetY == ty then
          return false, "entity"
        end
      end
    end
  end
  return true
end

function Player:tryMove(dir, map, entities)
  if self.moving then return nil end
  if self.facing ~= dir then
    self.facing = dir
    self.bumpFrames = nil
    if self.turnArmed then
      self.turnArmed = false
      self.turnTimer = TURN_FRAMES
      return "turned"
    end
  end
  if self.turnTimer > 0 then return nil end

  local d = Map.DELTA[dir]
  local tx, ty = self.cellX + d[1], self.cellY + d[2]
  local allowed, why = verdict(self, map, entities, tx, ty)
  -- Per-step hot path, guarded the way src/world/Collision.lua's canMove is:
  -- with an empty chain this costs one table lookup and no ctx allocation.
  if Runtime.wantsHook("movement.collision") then
    local ctx = { map = map, mover = self, dir = dir,
                  fromX = self.cellX, fromY = self.cellY,
                  toX = tx, toY = ty, reason = why }
    allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
    why = ctx.reason
  end
  if not allowed then
    -- World:movePlayer tells the two refusals apart: "edge" is what asks the
    -- connection table for the neighbouring map, "blocked" is a bump.
    -- (engine/overworld/player_movement.asm:93-106, :525-531).
    -- engine/overworld/movement.asm:315
    self.bumpFrames = 1
    return why == "bounds" and "edge" or "blocked"
  end
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.bumpFrames = nil
  self.progress = 0
  return "moved"
end

-- Cutscene step: ignores collision so Elm walk-up / after-pick paths play.
function Player:scriptFace(dir)
  if dir then self.facing = dir end
end

function Player:scriptStep(dir)
  if self.moving then return false end
  -- A scripted step names its own STEP_* on the cart (SurfStartStep is a slow
  -- step), so it never inherits the bike's shorter one.
  self.stepFrames = STEP_FRAMES
  self.facing = dir or self.facing
  local d = Map.DELTA[self.facing]
  if not d then return false end
  self.targetX, self.targetY = self.cellX + d[1], self.cellY + d[2]
  self.moving = true
  self.bumpFrames = nil
  self.progress = 0
  return true
end

-- CounterclockwiseSpinAction's .facings, seeded from the current direction by
-- Movement_step_dig -- map_object_action.asm:96-152, movement.asm:113-116
local SPIN_FACINGS = { "down", "right", "up", "left" }
local SPIN_START = { down = 0, right = 1, up = 2, left = 3 }

function Player:scriptSpin(frames)
  if not frames or frames <= 0 then return end
  self.spinFrames = frames
  self.spinTimer = (SPIN_START[self.facing] or 0) * 4
end

-- Gen 1's name for the cell being faced (src/world/Player.lua), so a mod that
-- wraps World:interact asks one question of either generation.
function Player:facingCell()
  local d = Map.DELTA[self.facing] or Map.DELTA.down
  return self.cellX + d[1], self.cellY + d[2]
end

function Player:walkPhase()
  -- pokegold engine/overworld/map_objects.asm StepFunction_Turn: forces the
  -- walking leg frame for the whole 4-frame turn-in-place.
  if self.turnTimer > 0 then return 1 end
  if not self.moving then
    -- map_object_action.asm:45-69
    if (self.bumpFrames or 0) <= 0 then return 0 end
    -- map_object_action.asm:98-119
    return (math.floor(self.animClock / STEP_FRAMES) % 2 == 1) and 1 or 0
  end
  local p = self.animClock % STEP_FRAMES
  return (p >= 4 and p < 12) and 1 or 0
end

-- map_object_action.asm:71-94
function Player:drawFlip()
  if self.moving or (self.bumpFrames or 0) <= 0 then return self.stepFlip end
  local mirrored = math.floor(self.animClock / (STEP_FRAMES * 2)) % 2 == 1
  return self.stepFlip ~= mirrored
end

function Player:update()
  if self.turnTimer > 0 then
    self.turnTimer = self.turnTimer - 1
  end
  if self.spinFrames then
    self.spinTimer = (self.spinTimer or 0) + 1
    self.spinFrames = self.spinFrames - 1
    if self.spinFrames <= 0 then self.spinFrames = nil end
  end
  if not self.moving then
    -- map_objects.asm:1517-1525
    if (self.bumpFrames or 0) > 0 then
      self.bumpFrames = self.bumpFrames - 1
      self.animClock = self.animClock + 1
    end
    -- Re-arm turn-in-place once a poll finds no held direction (caller
    -- clears this while a dir is held; we only set it from idle).
    return false
  end
  self.progress = self.progress + 1
  self.animClock = self.animClock + 1
  -- Interpolate toward the TARGET cell rather than one cell along the facing:
  -- a ledge hop (World:tryLedgeJump, the cart's STEP_LEDGE) is a two-cell move
  -- and the facing-delta math walked only half of it, leaving the sprite a
  -- cell behind where the grid said the player was.
  local frames = self.stepFrames or STEP_FRAMES
  local dx = (self.targetX or self.cellX) - self.cellX
  local dy = (self.targetY or self.cellY) - self.cellY
  -- engine/overworld/map_objects.asm:331 -- AddStepVector moves the object
  -- every frame, so the span is the whole move, not one cell scaled by dx.
  local span = math.max(math.abs(dx), math.abs(dy), 1)
  local adv = math.floor(self.progress * 16 * span / frames)
  self.px = self.cellX * 16 + (dx / span) * adv
  self.py = self.cellY * 16 + (dy / span) * adv
  if self.jumping then
    -- engine/overworld/map_objects.asm:1796 -- one table entry per cart frame,
    -- tweened across our doubled step (#1713)
    local t = (self.progress - 1) * (#JUMP_Y - 1)
      / math.max(frames - 1, 1) + 1
    local idx = math.floor(t)
    if idx < 1 then idx = 1 end
    if idx >= #JUMP_Y then
      self.spriteYOffset = JUMP_Y[#JUMP_Y]
    else
      self.spriteYOffset = math.floor(
        JUMP_Y[idx] + (JUMP_Y[idx + 1] - JUMP_Y[idx]) * (t - idx) + 0.5)
    end
  end
  if self.progress >= frames then
    self.cellX, self.cellY = self.targetX, self.targetY
    self.targetX, self.targetY = nil, nil
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving = false
    self.jumping = nil
    self.spriteYOffset = 0
    self.stepFlip = not self.stepFlip
    return true
  end
  return false
end

-- FacingFishDown/Up/Left/Right: the standing frame's bottom tile row swapped
-- for the fishing sheet, plus the loose rod tile -- facings.asm:122-152 (#1708)
function Player:drawFishing(yOffset)
  local sprite = self.sprite
  local py = self.py + yOffset
  local facing = self.facing
  sprite:draw(self.px, py, 0, 0, facing, 0, false, true)
  if not self.fishQuads then
    self.fishQuads = { pose = {}, rod = {} }
    for i = 0, 2 do
      self.fishQuads.pose[i] = love.graphics.newQuad(0, i * 8, 16, 8, 16, 32)
    end
    for i = 0, 1 do
      self.fishQuads.rod[i] = love.graphics.newQuad(i * 8, 24, 8, 8, 16, 32)
    end
  end
  local sx, sy = sprite:getScreenOrigin(self.px, py, 0, 0)
  sprite:drawTile(self.fishSheet, sx,
    sy + math.max(0, sprite.frameHeight - 8), facing == "right",
    self.fishQuads.pose[FISH_ROW[facing] or 0])
  local oam = ROD_OAM[facing] or ROD_OAM.down
  sprite:drawTile(self.fishSheet, sx + oam.dx, sy + oam.dy, oam.flip,
    self.fishQuads.rod[oam.tile])
end

function Player:draw(ox, oy, scale, oamRow)
  local G = love.graphics
  -- OBJECT_SPRITE_Y_OFFSET: added to the OBJ's y as it is written to OAM, so
  -- it moves the sprite without moving the player off the tile they are
  -- standing on.  StepFunction_GotBite's `xor 1` rod bob rides this one byte.
  local yOffset = self.spriteYOffset or 0
  if self.sprite then
    G.push()
    G.translate(ox, oy)
    G.scale(scale, scale)
    -- Chris is PAL_OW_RED; World:applyPalettes keeps the SpriteRenderer's
    -- OBJ palette current.
    if self.fishing and self.fishSheet then
      self:drawFishing(yOffset)
    else
      local facing, phase = self.facing, self:walkPhase()
      local flip = self:drawFlip()
      -- OBJECT_ACTION_SPIN (map_object_action.asm:96-152), for step_dig.
      if self.spinFrames then
        facing = SPIN_FACINGS[math.floor(self.spinTimer / 4) % 4 + 1]
        phase = 0
      end
      self.sprite:draw(
        self.px, self.py + yOffset, 0, 0, facing, phase, flip,
        nil, nil, nil, oamRow)
    end
    G.pop()
    return
  end
  -- Fallback rectangle if sprites.lua is missing from an old cache.
  local x = ox + self.px * scale
  local y = oy + (self.py + yOffset) * scale
  local s = 16 * scale
  G.setColor(0.95, 0.35, 0.25, 1)
  G.rectangle("fill", x + s * 0.15, y + s * 0.1, s * 0.7, s * 0.85, 2, 2)
  G.setColor(1, 0.9, 0.55, 1)
  local notch = s * 0.22
  if self.facing == "up" then
    G.rectangle("fill", x + s * 0.5 - notch / 2, y + s * 0.05, notch, notch)
  elseif self.facing == "down" then
    G.rectangle("fill", x + s * 0.5 - notch / 2, y + s * 0.7, notch, notch)
  elseif self.facing == "left" then
    G.rectangle("fill", x + s * 0.05, y + s * 0.4, notch, notch)
  else
    G.rectangle("fill", x + s * 0.75, y + s * 0.4, notch, notch)
  end
  G.setColor(1, 1, 1, 1)
end

return Player

-- Map object (NPC/item) built from a generated object_event entry.

local Collision = require("src.world.Collision")
local SpriteRenderer = require("src.render.SpriteRenderer")

local NPC = {}
NPC.__index = NPC

local STEP_FRAMES = 32

local FACING_FROM_RANGE = {
  DOWN = "down", UP = "up", LEFT = "left", RIGHT = "right",
}

-- .randomMovement -- pokered engine/overworld/movement.asm:190
local ROAM_DIRS = {
  ANY_DIR = { "up", "down", "left", "right" },
  NONE = { "up", "down", "left", "right" },
  UP_DOWN = { "up", "down" },
  LEFT_RIGHT = { "left", "right" },
}

function NPC.new(data, mapId, objDef)
  local self = setmetatable({}, NPC)
  self.def = objDef
  self.id = string.format("%s_obj_%d", mapId, objDef.index)
  local spriteDef = data.sprites[objDef.sprite]
  assert(spriteDef, "unknown sprite " .. tostring(objDef.sprite))
  self.sprite = SpriteRenderer.new(spriteDef, self.id)
  -- object_event coordinates are already walk-grid cells
  self.cellX, self.cellY = objDef.x, objDef.y
  self.px, self.py = self.cellX * 16, self.cellY * 16
  self.facing = FACING_FROM_RANGE[objDef.range] or "down"
  self.moving = false
  self.progress = 0
  self.animClock = 0
  self.stepFlip = false
  self.frozen = false -- scripts freeze NPCs while talking
  -- pokered engine/overworld/movement.asm:611
  local turnDirs = ROAM_DIRS[objDef.range or "NONE"]
  self.steps = objDef.movement == "WALK"
  self.wanders = (self.steps or objDef.movement == "STAY") and turnDirs ~= nil
  self.roamDirs = turnDirs or ROAM_DIRS.ANY_DIR
  self.timer = love.math.random(30, 120)
  return self
end

-- LoadMapHeader .loadSpriteData zeroes the sprite state data and re-seeds
-- MAPY/MAPX from the map header -- home/overworld.asm:2133
function NPC:resetToSpawn()
  local def = self.def
  self.cellX, self.cellY = def.x, def.y
  self.px, self.py = self.cellX * 16, self.cellY * 16
  self.facing = FACING_FROM_RANGE[def.range] or "down"
  self.targetX, self.targetY = nil, nil
  self.moving = false
  self.marching = false
  self.hopStep = nil
  self.progress = 0
  self.animClock = 0
  self.stepFlip = false
  self.timer = love.math.random(30, 120)
end

function NPC:facePlayer(player)
  local dx = player.cellX - self.cellX
  local dy = player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

function NPC:update(map, entities)
  -- engine/overworld/movement.asm:301, 32 frames per NPC cell; stepFrames is
  -- the follower's own step length (#410, #409).
  local stepLen = self.stepFrames or STEP_FRAMES
  local span = self.hopStep and 2 or 1
  if self.moving then
    self.progress = self.progress + 1
    self.animClock = (self.animClock or 0) + 1
    -- NPC_CHANGE_FACING (movement.asm ChangeFacingDirection): walk cycle in
    -- place, no translation.
    if self.marching then
      if self.progress >= stepLen then
        self.progress = 0
        self.moving = false
        self.marching = false
        self.stepFlip = not self.stepFlip
      end
      return
    end
    local d = Collision.DELTA[self.facing]
    -- 1px per 2 frames at the default length; a shortened step scales instead,
    -- so the cell still lands on a 16px boundary (Player:update does the
    -- same for the bicycle)
    local moved = math.floor(self.progress * 16 * span / stepLen)
    self.px = self.cellX * 16 + d[1] * moved
    self.py = self.cellY * 16 + d[2] * moved
    if self.progress >= stepLen then
      self.cellX, self.cellY = self.targetX, self.targetY
      self.targetX, self.targetY = nil, nil
      self.px, self.py = self.cellX * 16, self.cellY * 16
      self.moving = false
      self.hopStep = nil
      self.stepFlip = not self.stepFlip
    end
    return
  end
  if self.frozen or not self.wanders then return end
  self.timer = self.timer - 1
  if self.timer > 0 then return end
  self.timer = love.math.random(30, 180)
  local dir = self.roamDirs[love.math.random(#self.roamDirs)]
  self.facing = dir
  -- pokered engine/overworld/movement.asm:262
  if not self.steps then return end
  if love.math.random() < 0.5 then return end -- sometimes just turn
  -- never wander onto warps, so NPCs don't walk out of the map
  local tx, ty = Collision.target(self.cellX, self.cellY, dir)
  if map:warpAtCell(tx, ty) then return end
  if Collision.canMove(map, entities, self, dir) then
    self.targetX, self.targetY = tx, ty
    self.moving = true
    self.progress = 0
  end
end

-- UpdateNPCSprite branches to NotYetMoving while BIT_FONT_LOADED is set
-- -- engine/overworld/movement.asm:139
local function textBoxUp()
  local stack = require("src.core.Game").stack
  local top = stack and stack.top and stack:top()
  return top ~= nil and not top.isOverworld
end

function NPC:walkPhase()
  if not self.moving or textBoxUp() then return 0 end
  -- engine/overworld/movement.asm:301
  local p = (self.animClock or 0) % 16
  return (p >= 4 and p < 12) and 1 or 0
end

-- Same contract as Player:pose; an NPC never hops, so the trailing hop
-- flag is always false.
function NPC:pose()
  local flip = self.stepFlip
  if self.moving then
    flip = math.floor((self.animClock or 0) / 16) % 2 == 1
  end
  return self.sprite, self.px, self.py, self.facing,
         self:walkPhase(), flip, false
end

function NPC:draw(camX, camY)
  local sprite, px, py, facing, phase, flip = self:pose()
  sprite:draw(px, py, camX, camY, facing, phase, flip, nil, nil,
              self.frameOverride)
end

return NPC

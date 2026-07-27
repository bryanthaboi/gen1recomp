-- The player: tile-grid movement with pixel interpolation, faithful to the
-- original's feel: facing changes on a short tap, movement is tile-by-tile
-- at 1px per frame (16 frames per step), input locked while stepping.

local Collision = require("src.world.Collision")
local FieldDefaults = require("src.world.FieldDefaults")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Player = {}
Player.__index = Player

local STEP_FRAMES = 16
-- a turn in place holds for the ~2 frames the original spends on the
-- extra OverworldLoop pass (home/overworld.asm .handleDirectionButtonPress
-- returns to the loop without moving after a direction change)
local TURN_FRAMES = 2

function Player.new(data, cx, cy, facing)
  local self = setmetatable({}, Player)
  self.stepFrames = FieldDefaults.world(data, "stepFrames") or STEP_FRAMES
  self.bikeStepFrames = FieldDefaults.world(data, "bikeStepFrames")
  self.turnFrames = FieldDefaults.world(data, "turnFrames") or TURN_FRAMES
  -- field.playerSprites: which sprite ids the player wears on foot, on the
  -- water and on the bicycle (LoadPlayerSpriteGraphics /
  -- LoadSurfingPlayerSpriteGraphics, home/overworld.asm)
  local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
  local surfId = FieldDefaults.fieldValue(data, "playerSprites", "surf")
  local bikeId = FieldDefaults.fieldValue(data, "playerSprites", "bike")
  self.sprite = SpriteRenderer.new(data.sprites[walkId], "player")
  if surfId and data.sprites[surfId] then
    self.surfSprite = SpriteRenderer.new(data.sprites[surfId], "player")
  end
  if bikeId and data.sprites[bikeId] then
    self.bikeSprite = SpriteRenderer.new(data.sprites[bikeId], "player")
  end
  -- the ledge-hop shadow quarter-tile (gfx/overworld/shadow.png,
  -- LedgeHoppingShadow, engine/overworld/ledges.asm)
  local fx = data.field and data.field.overworldFx
  if fx and fx.shadow then
    local ok, img = pcall(love.graphics.newImage, fx.shadow.path)
    self.shadowImg = ok and img or nil
  end
  self.cellX, self.cellY = cx, cy
  self.px, self.py = cx * 16, cy * 16
  self.facing = facing or "down"
  self.moving = false
  self.progress = 0
  self.stepFlip = false
  self.turnTimer = 0
  self.inputLocked = false
  return self
end

function Player:position()
  return self.cellX, self.cellY
end

-- Attempt to start a step; returns "moved"|"turned"|"blocked"|nil.
function Player:tryMove(dir, map, entities)
  if self.moving or self.inputLocked then return nil end
  if self.facing ~= dir then
    self.facing = dir
    self.turnTimer = self.turnFrames or TURN_FRAMES
    self.bumpFrames = nil -- turning to a new facing ends any wall-bonk cycle
    return "turned"
  end
  if self.turnTimer > 0 then return nil end
  local ok, why = Collision.canMove(map, entities, self, dir)
  if not ok then
    -- Gen1: a blocked step still animates the player walking in place --
    -- the collision path spends the step's worth of frames running
    -- UpdateSprites before returning control, so the legs cycle without
    -- the cell changing (home/overworld.asm collision handling; issue
    -- #230).  Re-armed every frame the direction is held into the wall;
    -- Player:update ticks the walk clock while it counts down, so releasing
    -- returns to the standing pose within a step's length.
    self.bumpFrames = self.stepFrames or STEP_FRAMES
    return "blocked", why
  end
  local tx, ty = Collision.target(self.cellX, self.cellY, dir)
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.bumpFrames = nil -- a real step supersedes any in-place bonk
  self.progress = 0
  -- the bicycle doubles walking speed (8 frames per step); movement.speed
  -- lets a mod multiply or replace that (running shoes, dash, etc.)
  local Game = require("src.core.Game")
  local save = Game.save
  local frames = (save and save.onBike) and self.bikeStepFrames
                 or self.stepFrames or STEP_FRAMES
  if Runtime.wantsHook("movement.speed") then
    frames = Runtime.call("movement.speed", function(f) return f end, frames, {
      onBike = save and save.onBike or false,
      surfing = self.surfing and true or false,
      player = self,
      input = Game.input,
      save = save,
    })
  end
  self.stepFramesCur = math.max(1, math.floor(tonumber(frames) or STEP_FRAMES))
  return "moved"
end

-- Advance one fixed step; returns true when a step just completed.
function Player:update()
  -- land-frame walk pose lasts only through the draw after completion;
  -- the next update (idle or a chained step) clears it
  self.stepLanded = false
  -- Ledge-hop arc is cosmetic but must track the fixed 60Hz logic step,
  -- not love.draw's display refresh (issue #4: >59fps ended early).
  if self.hopFrames and self.hopFrames > 0 then
    self.hopFrames = self.hopFrames - 1
  end
  if self.turnTimer > 0 then
    self.turnTimer = self.turnTimer - 1
  end
  if self.spinFrames then
    self.spinFrames = self.spinFrames - 1
    if self.spinFrames <= 0 then
      self.spinFrames = nil
      self.spinDrop = nil
      self.spinRise = nil -- teleport-out departure lift (#196)
      self.spinning = false
    end
  end
  -- wall-bonk walk-in-place (issue #230): while pushing into a wall the
  -- collision path keeps the walk clock running without moving the cell,
  -- so the sprite animates against the wall.  Guarded on not-moving so a
  -- real step (which clears bumpFrames and advances animClock itself
  -- below) can never double-tick the leg cadence.
  if not self.moving and self.bumpFrames and self.bumpFrames > 0 then
    self.bumpFrames = self.bumpFrames - 1
    self.animClock = (self.animClock or 0) + 1
  end
  if not self.moving then return false end
  local stepLen = self.stepFramesCur or self.stepFrames or STEP_FRAMES
  self.progress = self.progress + 1
  -- the walk-cycle clock ticks once per real frame while moving, so the
  -- leg cadence stays constant when the bike halves stepFramesCur (only
  -- translation speed doubles, like UpdatePlayerSprite's frame counters)
  self.animClock = (self.animClock or 0) + 1
  local d = Collision.DELTA[self.facing]
  local px = math.floor(self.progress * 16 / stepLen)
  self.px = self.cellX * 16 + d[1] * px
  self.py = self.cellY * 16 + d[2] * px
  if self.progress >= stepLen then
    self.cellX, self.cellY = self.targetX, self.targetY
    self.targetX, self.targetY = nil, nil
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving = false
    self.stepFlip = not self.stepFlip
    -- keep animClock's pose on this frame (issue #82): bike steps land
    -- mid-cycle (animClock % 16 == 8), and walkPhase used to snap to
    -- stand whenever moving cleared — a stand flash every tile on the
    -- bike, and sometimes after dismount when the clock is desynced
    self.stepLanded = true
    return true
  end
  return false
end

function Player:facingCell()
  return Collision.target(self.cellX, self.cellY, self.facing)
end

function Player:walkPhase()
  -- moving, the land-frame after a completed step, or an active wall-bonk
  -- (issue #230) animate; a standing sprite otherwise
  if not self.moving and not self.stepLanded
     and not (self.bumpFrames and self.bumpFrames > 0) then
    return 0
  end
  -- walk frame during the middle of each 16-frame animation cycle
  local p = (self.animClock or self.progress) % 16
  return (p >= 4 and p < 12) and 1 or 0
end

local SPIN_ORDER = { "down", "left", "up", "right" }

-- What this frame renders to: the sheet, where it sits, which way it faces
-- and how far through a step it is.  Shared by the 2D draw below and by a
-- render pipeline's own geometry (src/render/Pipelines.lua), so the two can
-- never disagree about which sprite or facing is current.
--
-- The last return says the player is mid-ledge-hop, which is what the 2D
-- path draws the ground shadow from and a 3D path turns into vertical lift.
--
-- This ADVANCES the surf-bob and spinner timers, so exactly one of pose()
-- and draw() may run per frame -- and draw() is written in terms of pose()
-- to keep that true by construction.  (hopFrames counts down in
-- Player:update, on the fixed step, so it is safe to read here.)
function Player:pose()
  local py = self.py
  local hopping = false
  -- ledge hops arc (set for 2 cells by the ledge handler); surfing bobs
  if self.hopFrames and self.hopFrames > 0 then
    local total = self.hopTotal or 32
    -- update runs before draw, so remaining N means N steps already
    -- consumed this hop → t matches the old draw-side post-decrement phase
    local t = 1 - self.hopFrames / total
    py = py - math.floor(10 * math.sin(t * math.pi) + 0.5)
    hopping = true
  elseif self.surfing then
    self.bobTimer = ((self.bobTimer or 0) + 1) % 32
    py = py + (self.bobTimer < 16 and 0 or 1)
  end
  local facing = self.facing
  local phase = self:walkPhase()
  -- alternate walk cycles mirror the up/down frame; derived from the
  -- fixed-rate animation clock so the bike's shorter steps don't double
  -- the leg cadence
  local flip = math.floor((self.animClock or 0) / 16) % 2 == 1
  if self.spinning then
    -- spinner tiles whirl the sprite on its standing pose, one facing
    -- per frame (LoadSpinnerArrowTiles runs every OverworldLoop frame)
    self.spinTimer = (self.spinTimer or 0) + 1
    facing = SPIN_ORDER[self.spinTimer % 4 + 1]
    phase, flip = 0, false
    -- teleport arrivals spin the sprite down into place
    -- (EnterMapAnim PlayerSpinWhileMovingDown)
    if self.spinFrames and self.spinDrop then
      py = py - math.floor(self.spinFrames * 24 / (self.spinTotal or 64))
    elseif self.spinFrames and self.spinRise then
      -- Dig/Teleport/Escape-Rope departures spin the sprite UP out of the
      -- map before the fade (LeaveMapAnim PlayerSpinWhileMovingUp) -- the
      -- mirror of the arrival spin-down: the lift grows from 0 as spinFrames
      -- counts down to 0 (#196), opposite sign to spinDrop above.
      local total = self.spinTotal or 64
      py = py - math.floor((total - self.spinFrames) * 24 / total)
    end
  end
  local sprite = (self.surfing and self.surfSprite)
                 or (self.onBike and self.bikeSprite) or self.sprite
  return sprite, self.px, py, facing, phase, flip, hopping
end

function Player:draw(camX, camY)
  local sprite, px, py, facing, phase, flip, hopping = self:pose()
  -- the shadow stays on the ground under the jumper: one 8x8 tile
  -- mirrored into a 2x2 block (normal/XFLIP/YFLIP/both) whose top-left
  -- is 8px below the sprite's standing top-left (LoadHoppingShadowOAM +
  -- LedgeHoppingShadowOAMBlock, engine/overworld/ledges.asm)
  if hopping and self.shadowImg then
    local sx = math.floor(self.px - camX)
    local sy = math.floor(self.py - camY) - 4 + 8
    love.graphics.draw(self.shadowImg, sx, sy)
    love.graphics.draw(self.shadowImg, sx + 16, sy, 0, -1, 1)
    love.graphics.draw(self.shadowImg, sx, sy + 16, 0, 1, -1)
    love.graphics.draw(self.shadowImg, sx + 16, sy + 16, 0, -1, -1)
  end
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

return Player

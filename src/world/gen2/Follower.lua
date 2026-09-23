-- Gen 2 party follower: the entity and trail loop Gold's cart has no
-- counterpart for, shaped like src/world/PikachuFollower.lua because that is
-- the surface Gen 1 follower mods drive (docs/mod-api-gen2-compat.md).

local Logger = require("src.core.Logger")
local Map = require("src.world.gen2.Map")
local NPC = require("src.world.gen2.Npc")
local ModRuntime = require("src.mods.Runtime")

local Follower = {}

-- above every extracted object_event index, so the `<map>_obj_<n>` id
-- src/world/gen2/Npc.lua:165 seeds from can never collide with a map object
local INDEX = 250

-- Gold ships no such record: a mod patches the `sprites` registry (routed to
-- data.gen2Sprites, src/mods/Schemas.lua:475) before shouldSpawn says yes.
Follower.SPRITE = "SPRITE_PIKACHU"

local warnedSprite = false

-- Gold has no companion, so vanilla answers no.  A local VARIABLE, not a
-- function: setShouldSpawn writes the same cell debug.setupvalue reaches.
local shouldSpawn

shouldSpawn = function(_game, _world)
  return false
end

function Follower.setShouldSpawn(fn)
  local previous = shouldSpawn
  shouldSpawn = fn or previous
  return previous
end

local function spriteDefFor(world)
  local sprites = world.sprites or {}
  local def = sprites[Follower.SPRITE]
  if def then return def end
  -- Loud, then the player's sheet: a mod overwrites npc.sprite the line after
  -- NPC.new, so a missing record must not decide whether the entity exists.
  if not warnedSprite then
    warnedSprite = true
    Logger.warn("gen2 follower: no %s sprite record; using the player sheet",
      Follower.SPRITE)
  end
  return world.player and world.player.spriteDef
end

local function makeFollower(_game, world, x, y, facing)
  local def = spriteDefFor(world)
  if not def then return nil end
  local npc = NPC.new(world.map.id, {
    -- STANDING_DOWN, not STILL: STILL carries FIXED_FACING
    -- (src/world/gen2/Npc.lua:61) and a follower has to turn.
    index = INDEX, name = "FOLLOWER", sprite = Follower.SPRITE,
    movement = NPC.MOVE.STANDING_DOWN, x = x, y = y,
  }, def)
  npc.follower = true
  -- the Gen 1 name a mod tests when it hunts the stock companion
  -- (src/world/PikachuFollower.lua:141)
  npc.pikachuFollower = true
  npc.passable = true -- never blocks a step (src/world/gen2/Player.lua verdict)
  npc.facing = facing or "down"
  return npc
end

local function findFollower(world)
  for i, npc in ipairs(world.npcs or {}) do
    if npc.pikachuFollower then return npc, i end
  end
  return nil
end

local function remove(world)
  local npc, i = findFollower(world)
  if not npc then return end
  table.remove(world.npcs, i)
  for j, e in ipairs(world.entities or {}) do
    if e == npc then table.remove(world.entities, j) break end
  end
  world.follower = nil
end

-- behind the player's facing when walkable, else his own cell: it trails out
-- on the next step (src/world/PikachuFollower.lua:169)
local function spawnCell(world)
  local p = world.player
  local d = Map.DELTA[p.facing] or Map.DELTA.down
  local bx, by = p.cellX - d[1], p.cellY - d[2]
  if world.map:inBounds(bx, by) and world.map:isWalkableCell(bx, by) then
    return bx, by
  end
  return p.cellX, p.cellY
end

function Follower.current(world)
  return (findFollower(world))
end

function Follower.onMapEntered(game, world, opts, viaMapLoad)
  if not (world and world.map and world.player) then return end
  remove(world)
  if not ModRuntime.call("world.follower.spawn", shouldSpawn, game, world) then return end
  -- keepPikachu is Gen 1's spelling of the same opt (src/world/PikachuFollower
  -- .lua:191); a mod passing it must not get a fresh spawn at every seam.
  local keep = opts and (opts.keepFollower or opts.keepPikachu)
  if keep then
    table.insert(world.npcs, keep)
    table.insert(world.entities, keep)
    world.follower = keep
    return
  end
  local x, y = spawnCell(world)
  -- a fresh load parks it under the player and it walks out as the trail
  -- opens; a mid-map respawn keeps the behind-the-facing cell (#863)
  if viaMapLoad then x, y = world.player.cellX, world.player.cellY end
  local npc = makeFollower(game, world, x, y, world.player.facing)
  if not npc then return end
  table.insert(world.npcs, npc)
  table.insert(world.entities, npc)
  world.follower = npc
  world.followerTrail = { x = world.player.cellX, y = world.player.cellY }
  -- Gen 1's name for the same table, by reference: rebase mutates it in
  -- place, so a mod that resets ow.pikachuTrail still moves the live trail.
  world.pikachuTrail = world.followerTrail
end

-- One follow step per logic frame, called from World:step after
-- World:updatePeople -- src/world/OverworldController.lua:1039's position.
function Follower.update(game, world)
  if not (world and world.map and world.player) then return end
  local npc = findFollower(world)
  if not npc then
    if ModRuntime.call("world.follower.spawn", shouldSpawn, game, world) then Follower.onMapEntered(game, world) end
    return
  end
  if not ModRuntime.call("world.follower.spawn", shouldSpawn, game, world) then
    remove(world)
    return
  end
  world.follower = npc
  local p = world.player
  local trail = world.followerTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    world.followerTrail = trail
    world.pikachuTrail = trail
  end
  -- the commit, not the landing: targetX/Y is the live destination, which is
  -- what keeps the gap at one cell (src/world/PikachuFollower.lua:429, #410)
  local destX = p.targetX or p.cellX
  local destY = p.targetY or p.cellY
  if destX ~= trail.x or destY ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = destX, destY
  end
  if npc.moving then return end
  if not npc.goalX then return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    return
  end
  -- more than a screen behind (a warp, a scripted move): snap, do not walk
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > 6 then
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end
  local dir
  if npc.cellX < gx then dir = "right"
  elseif npc.cellX > gx then dir = "left"
  elseif npc.cellY < gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.stepDir = dir
  local d = Map.DELTA[dir]
  npc.targetX, npc.targetY = npc.cellX + d[1], npc.cellY + d[2]
  -- the player's own step length, halved while more than a cell behind:
  -- FastPikachuFollow (src/world/PikachuFollower.lua:509)
  local stepLen = p.stepFrames or 16
  if far > 1 then stepLen = math.max(1, math.floor(stepLen / 2)) end
  npc.stepFrames = stepLen
  npc.moving = true
  npc.progress = 0
  -- World:updatePeople already ran, so burn the first frame here or the
  -- follower loses a pixel a tile (src/world/PikachuFollower.lua:520)
  npc:update(world.map, world.entities)
end

-- The two Gen 1 members a follower mod replaces outright.  Gold has neither a
-- companion to talk to nor a walking starter, so both answer honestly nil.
function Follower.talk(_game, _world, _npc, _done)
  return false
end

function Follower.starterInParty(_save, _needHealthy)
  return nil
end

-- Drop the follower from the DRAW list while leaving it in the UPDATE list,
-- so it hides in place and keeps trailing (src/world/PikachuFollower.lua:952).
-- Re-adding faces it down, as the Gen 1 arm does.
function Follower.setVisible(world, visible)
  local npc = findFollower(world)
  if not npc then return end
  local entities = world.entities or {}
  for i, e in ipairs(entities) do
    if e == npc then
      if visible then return end
      table.remove(entities, i)
      return
    end
  end
  if not visible then return end
  npc.facing = "down"
  table.insert(entities, npc)
end

-- The follower when it is STANDING on that cell, which is the test an
-- interact hook wants: mid-step it is between two (src/world/PikachuFollower
-- .lua:965).
function Follower.at(world, cx, cy)
  local npc = findFollower(world)
  if not npc or npc.moving then return nil end
  if npc.cellX == cx and npc.cellY == cy then return npc end
  return nil
end

-- slide into a connected map's frame by the seam's delta, the way
-- src/world/PikachuFollower.lua:386 rebases the Gen 1 arm
function Follower.rebase(world, dx, dy)
  local npc = findFollower(world)
  if npc then
    npc.cellX, npc.cellY = npc.cellX + dx, npc.cellY + dy
    npc.px, npc.py = npc.px + dx * 16, npc.py + dy * 16
    if npc.targetX then npc.targetX = npc.targetX + dx end
    if npc.targetY then npc.targetY = npc.targetY + dy end
    if npc.goalX then npc.goalX = npc.goalX + dx end
    if npc.goalY then npc.goalY = npc.goalY + dy end
  end
  local trail = world.followerTrail
  if trail then trail.x, trail.y = trail.x + dx, trail.y + dy end
end

return Follower

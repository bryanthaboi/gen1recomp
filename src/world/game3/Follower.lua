-- Optional mod companion, independent of FireRed event-object IDs and scripts.
local Follower = {}
local ModRuntime = require("src.mods.Runtime")
local shouldSpawn = function() return false end
local npc, lastMap, trailX, trailY

function Follower.setShouldSpawn(fn)
  local previous = shouldSpawn
  shouldSpawn = fn or previous
  return previous
end

function Follower.reset()
  npc, lastMap, trailX, trailY = nil, nil, nil, nil
end

function Follower.current() return npc end
function Follower.talk() return false end
function Follower.starterInParty() return nil end
function Follower.setVisible(_, visible) if npc then npc.hidden = not visible end end
function Follower.at(_, x, y)
  if npc and not npc.moving and npc.cellX == x and npc.cellY == y then return npc end
end

function Follower.update(game)
  local Field = require("src.core.game3.field")
  local player = require("src.core.game3.player")
  local session = Field.getSession()
  local world = { player = player, map = { id = session and session.map } }
  if not Field.running or not session
      or not ModRuntime.call("world.follower.spawn", shouldSpawn, game, world) then
    Follower.reset()
    return
  end
  local teleported = trailX and (math.abs(player.cellX - trailX) + math.abs(player.cellY - trailY) > 6)
  if not npc or lastMap ~= session.map or teleported then
    npc = { cellX = player.cellX, cellY = player.cellY, px = player.px, py = player.py,
      facing = player.facing, passable = true, pikachuFollower = true, moving = false }
    lastMap, trailX, trailY = session.map, player.cellX, player.cellY
  end
  local tx = player.moving and player.targetX or player.cellX
  local ty = player.moving and player.targetY or player.cellY
  if tx ~= trailX or ty ~= trailY then
    npc.goalX, npc.goalY = trailX, trailY
    trailX, trailY = tx, ty
  end
  if not npc.moving and npc.goalX then
    local gx, gy = npc.goalX, npc.goalY
    local dx, dy = gx - npc.cellX, gy - npc.cellY
    local distance = math.abs(dx) + math.abs(dy)
    npc.goalX, npc.goalY = nil, nil
    if distance > 6 then
      npc.cellX, npc.cellY, npc.px, npc.py = gx, gy, gx * 16, gy * 16
    elseif distance > 0 then
      npc.facing = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left")
        or (dy > 0 and "down" or "up")
      npc.fromX, npc.fromY = npc.px, npc.py
      npc.targetX, npc.targetY, npc.progress = gx, gy, 0
      npc.stepFrames = math.max(1, math.floor((player.stepFrames or 16) / (distance > 1 and 2 or 1)))
      npc.moving = true
    end
  end
  if npc.moving then
    npc.progress = npc.progress + 1
    local t = math.min(1, npc.progress / npc.stepFrames)
    npc.px = npc.fromX + (npc.targetX * 16 - npc.fromX) * t
    npc.py = npc.fromY + (npc.targetY * 16 - npc.fromY) * t
    if t == 1 then
      npc.cellX, npc.cellY, npc.moving = npc.targetX, npc.targetY, false
    end
  end
  npc.elevation = player.elevation
end

function Follower.onMapEntered() Follower.reset() end

function Follower.actor()
  if not npc or not npc.sprite or npc.hidden then return nil end
  return { kind = "follower", i = -1, x = npc.px, y = npc.py,
    sortY = npc.py, elevation = npc.elevation, facing = npc.facing,
    walkPhase = npc.moving and 1 or 0, renderer = npc.sprite }
end

return Follower

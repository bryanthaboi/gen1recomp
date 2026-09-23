local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_npc_player_collision"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_npc_player_collision")
    love.event.quit(0)
  else
    print("FAIL game3_npc_player_collision failures=" .. failures)
    love.event.quit(1)
  end
end

local DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local DIR_ORDER = { "right", "left", "down", "up" }

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  local mapId = "FR_PALLET_TOWN"
  Map.load(nil, game, mapId, { x = 8, y = 10, facing = "down" })
  game.session.x, game.session.y, game.session.facing = 8, 10, "down"
  U.wait(60)

  local wanderer, plan
  for _, lid in ipairs(Objects.listActive()) do
    local eo = Objects.find(lid)
    if eo and tostring(eo.movement or ""):upper() == "WALK" then
      local rx = (eo.radius and eo.radius.x) or 1
      local ry = (eo.radius and eo.radius.y) or 1
      for _, dir in ipairs(DIR_ORDER) do
        local d = DELTA[dir]
        local tx, ty = eo.cellX + d[1], eo.cellY + d[2]
        local px, py = tx + d[1], ty + d[2]
        if math.abs(tx - eo.homeX) <= rx and math.abs(ty - eo.homeY) <= ry
          and Collision.canEnter(game, tx, ty, {}) and not Objects.at(tx, ty)
          and Collision.canEnter(game, px, py, {}) and not Objects.at(px, py)
        then
          wanderer = eo
          plan = { hx = eo.cellX, hy = eo.cellY, tx = tx, ty = ty, px = px, py = py,
            into = OPPOSITE[dir], back = dir }
          break
        end
      end
    end
    if wanderer then break end
  end

  if not result(wanderer ~= nil and plan ~= nil, "found a wandering NPC with a free contested cell") then
    return finish()
  end
  print(string.format("[driver] wanderer lid=%s at (%d,%d), contested cell (%d,%d), player start (%d,%d)",
    tostring(wanderer.localId), wanderer.cellX, wanderer.cellY, plan.tx, plan.ty, plan.px, plan.py))

  Map.load(nil, game, mapId, { x = plan.px, y = plan.py, facing = plan.into })
  game.session.x, game.session.y, game.session.facing = plan.px, plan.py, plan.into
  U.wait(60)
  wanderer = Objects.find(wanderer.localId)
  if not result(wanderer ~= nil, "wanderer survived the reload") then return finish() end
  local homeX, homeY = plan.hx, plan.hy
  wanderer.moving = false
  wanderer.progress = 0
  wanderer.cellX, wanderer.cellY = homeX, homeY
  wanderer.targetX, wanderer.targetY = homeX, homeY
  wanderer.px, wanderer.py = homeX * 16, homeY * 16

  local overlaps, contested, midSteps, declines = 0, 0, 0, 0
  local frozen, leashed = false, true

  local function pin()
    if leashed and wanderer.moving
      and (wanderer.targetX ~= plan.tx or wanderer.targetY ~= plan.ty) then
      wanderer.moving = false
      wanderer.progress = 0
      wanderer.targetX, wanderer.targetY = wanderer.cellX, wanderer.cellY
      wanderer.px, wanderer.py = wanderer.cellX * 16, wanderer.cellY * 16
    end
    if not wanderer.moving and (wanderer.cellX ~= homeX or wanderer.cellY ~= homeY)
      and not Objects.playerBlocks(homeX, homeY) then
      wanderer.cellX, wanderer.cellY = homeX, homeY
      wanderer.targetX, wanderer.targetY = homeX, homeY
      wanderer.px, wanderer.py = homeX * 16, homeY * 16
    end
    wanderer.idleTimer = frozen and 600 or 0
  end

  local function declined()
    return Player.moving and Player.targetX == plan.tx and Player.targetY == plan.ty
      and not wanderer.moving and wanderer.cellX == homeX and wanderer.cellY == homeY
      and wanderer.facing == plan.back
  end

  local function inspect()
    if wanderer.cellX == Player.cellX and wanderer.cellY == Player.cellY then
      overlaps = overlaps + 1
    end
    if Player.moving then
      midSteps = midSteps + 1
      if wanderer.moving and wanderer.targetX == Player.targetX
        and wanderer.targetY == Player.targetY then
        contested = contested + 1
      end
      if wanderer.moving and wanderer.targetX == Player.cellX
        and wanderer.targetY == Player.cellY then
        contested = contested + 1
      end
    end
  end

  local function walk(btn, frames)
    for _ = 1, frames do
      pin()
      table.insert(game.input.pressQueue, btn)
      game.input.state[btn] = true
      coroutine.yield()
      inspect()
      if declined() then declines = declines + 1 end
    end
    game.input.state[btn] = false
  end

  local function settle()
    for _ = 1, 40 do
      if not Player.moving then return end
      pin()
      coroutine.yield()
      inspect()
      if declined() then declines = declines + 1 end
    end
  end

  local function stepTo(gx, gy, onDecline)
    local dx, dy = gx - Player.cellX, gy - Player.cellY
    if dx == 0 and dy == 0 then return end
    local btn = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
    local started = false
    for _ = 1, 40 do
      pin()
      table.insert(game.input.pressQueue, btn)
      game.input.state[btn] = true
      coroutine.yield()
      inspect()
      if declined() then
        declines = declines + 1
        if onDecline and onDecline() then break end
      end
      if Player.moving then started = true elseif started then break end
    end
    game.input.state[btn] = false
    settle()
  end

  for _ = 1, 12 do
    stepTo(plan.tx, plan.ty)
    stepTo(plan.px, plan.py)
  end

  leashed = false
  for _ = 1, 6 do
    walk(plan.into, 26)
    walk(plan.back, 26)
  end
  settle()
  leashed = true
  if Player.cellX ~= plan.px or Player.cellY ~= plan.py then
    Map.load(nil, game, mapId, { x = plan.px, y = plan.py, facing = plan.into })
    game.session.x, game.session.y, game.session.facing = plan.px, plan.py, plan.into
    U.wait(60)
    wanderer = Objects.find(wanderer.localId)
    if not result(wanderer ~= nil, "wanderer survived the second reload") then return finish() end
  end

  result(midSteps > 0, "player actually stepped (mid-step frames=" .. midSteps .. ")")
  result(declines > 0, "NPC turned toward the player's destination and stayed put (declines=" .. declines .. ")")
  result(overlaps == 0, "NPC never shared the player's cell (overlaps=" .. overlaps .. ")")
  result(contested == 0,
    "NPC never claimed the player's in-flight cells (contested=" .. contested .. ")")

  local shot = false
  for _ = 1, 40 do
    stepTo(plan.tx, plan.ty, function()
      if shot then return false end
      frozen = true
      pin()
      shot = true
      U.shot(game, DIR .. "/2307_01_npc_declines_player_cell.png")
      return true
    end)
    if shot then break end
    stepTo(plan.px, plan.py)
  end
  result(shot, "captured the NPC declining the player's destination")
  U.wait(20)

  finish()
end

local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_npc_movement_types"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_npc_movement_types")
    love.event.quit(0)
  else
    print("FAIL game3_npc_movement_types failures=" .. failures)
    love.event.quit(1)
  end
end

local MEDIUM = { [32] = true, [64] = true, [96] = true, [128] = true }
local SHORT = { [32] = true, [48] = true, [64] = true, [80] = true }

local function keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return table.concat(out, ",")
end

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
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local TrainerSight = require("src.core.game3.trainer_sight")

  if not result(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local function go(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    U.wait(30)
    for _ = 1, 600 do
      if not Field.locked then break end
      U.wait(1)
    end
  end

  local function track(lids, frames, onFrame)
    local s = {}
    for _, lid in ipairs(lids) do
      local eo = Objects.find(lid)
      s[lid] = {
        eo = eo, cells = {}, facings = {}, moving = 0, frames = 0,
        minX = eo.cellX, maxX = eo.cellX, minY = eo.cellY, maxY = eo.cellY,
        delays = {}, badDelay = nil, prevTimer = eo.idleTimer, stepFrames = {},
        homeVisits = 0, wasHome = true,
      }
    end
    for f = 1, frames do
      U.wait(1)
      for _, lid in ipairs(lids) do
        local r = s[lid]
        local eo = r.eo
        r.frames = r.frames + 1
        if eo.moving then
          r.moving = r.moving + 1
          r.stepFrames[eo.stepFrames] = true
        end
        if eo.px % 1 ~= 0 or eo.py % 1 ~= 0 then r.fractional = true end
        r.cells[eo.cellX .. "," .. eo.cellY] = true
        r.minX, r.maxX = math.min(r.minX, eo.cellX), math.max(r.maxX, eo.cellX)
        r.minY, r.maxY = math.min(r.minY, eo.cellY), math.max(r.maxY, eo.cellY)
        r.facings[eo.facing] = true
        local t = eo.idleTimer
        if t and r.prevTimer and t > r.prevTimer then r.delays[#r.delays + 1] = t end
        if t and r.prevTimer == nil then r.delays[#r.delays + 1] = t end
        r.prevTimer = t
        local home = eo.cellX == eo.homeX and eo.cellY == eo.homeY
        if home and not r.wasHome then r.homeVisits = r.homeVisits + 1 end
        r.wasHome = home
      end
      if onFrame and onFrame(f) then break end
    end
    return s
  end

  local function delaysIn(r, set)
    if #r.delays == 0 then return false end
    for _, d in ipairs(r.delays) do
      if not set[d] then return false end
    end
    return true
  end

  local function delayList(r)
    local out = {}
    for i = 1, math.min(#r.delays, 8) do out[i] = tostring(r.delays[i]) end
    return table.concat(out, ",")
  end

  go("FR_ROUTE_17", 12, 70, "down")
  local bikers = { 1, 2, 4 }
  for _, lid in ipairs(bikers) do
    local eo = Objects.find(lid)
    if not result(eo and eo.movement == "BACK_FORTH" and eo.movementType == 0x1A,
        "route17 biker " .. lid .. " is WALK_DOWN_AND_UP") then return finish() end
  end
  local seq = Objects.find(3)
  if not result(seq and seq.movement == "SEQUENCE" and seq.movementType == 0x34,
      "route17 biker 3 is WALK_SEQUENCE_RIGHT_DOWN_LEFT_UP") then return finish() end
  local seqHomeX, seqHomeY = seq.homeX, seq.homeY
  local s17 = track({ 1, 2, 3, 4 }, 720)
  for _, lid in ipairs(bikers) do
    local r = s17[lid]
    local eo = r.eo
    print(string.format("[driver] biker %d home=(%d,%d) x=%d..%d y=%d..%d moving=%d/%d facings=%s homeVisits=%d",
      lid, eo.homeX, eo.homeY, r.minX, r.maxX, r.minY, r.maxY, r.moving, r.frames, keys(r.facings), r.homeVisits))
    result(r.minX == eo.homeX and r.maxX == eo.homeX, "biker " .. lid .. " never leaves its column")
    result(r.minY == eo.homeY and r.maxY == eo.homeY + eo.rangeY,
      "biker " .. lid .. " shuttles home..home+rangeY (" .. r.minY .. ".." .. r.maxY .. ")")
    result(r.homeVisits >= 2, "biker " .. lid .. " came back home repeatedly (" .. r.homeVisits .. ")")
    result(r.moving >= r.frames * 0.95, "biker " .. lid .. " walks nonstop (" .. r.moving .. "/" .. r.frames .. ")")
    result(keys(r.facings) == "down,up", "biker " .. lid .. " only faces down/up (" .. keys(r.facings) .. ")")
    result(not r.fractional, "biker " .. lid .. " moves in whole pixels")
  end
  do
    local r = s17[3]
    print(string.format("[driver] seq biker home=(%d,%d) x=%d..%d y=%d..%d moving=%d/%d facings=%s homeVisits=%d",
      seqHomeX, seqHomeY, r.minX, r.maxX, r.minY, r.maxY, r.moving, r.frames, keys(r.facings), r.homeVisits))
    result(r.minX == seqHomeX and r.maxX == seqHomeX + 4 and r.minY == seqHomeY and r.maxY == seqHomeY + 2,
      "walk sequence biker traces its right/down/left/up box")
    result(r.cells[(seqHomeX + 4) .. "," .. (seqHomeY + 2)] and r.cells[seqHomeX .. "," .. (seqHomeY + 2)]
      and r.cells[(seqHomeX + 4) .. "," .. seqHomeY] and true or false, "walk sequence biker reached all three far corners")
    result(r.homeVisits >= 2, "walk sequence biker loops back home (" .. r.homeVisits .. ")")
    result(r.moving >= r.frames * 0.95, "walk sequence biker walks nonstop (" .. r.moving .. "/" .. r.frames .. ")")
    result(keys(r.facings) == "down,left,right,up", "walk sequence biker faces all four legs")
  end
  Player.reset(8, 21, "left")
  U.wait(20)
  U.shot(game, DIR .. "/mov_route17_bikers_pacing.png")

  -- src/trainer_see.c:151
  do
    local eo = Objects.find(2)
    local engagedWhileMoving, engaged = false, false
    local realEngage = TrainerSight.engage
    TrainerSight.engage = function(_, who)
      engaged = true
      if who == eo and who.moving then engagedWhileMoving = true end
    end
    local bottom = eo.homeY + eo.rangeY
    Player.reset(eo.homeX, bottom + 1, "up")
    for _ = 1, 400 do
      U.wait(1)
      if engaged then break end
    end
    TrainerSight.engage = realEngage
    result(engaged and engagedWhileMoving,
      "walking biker spots the player from its destination mid-step")
  end

  go("FR_ROUTE_11", 40, 10, "down")
  do
    local eo = Objects.find(1)
    if not result(eo and eo.movement == "LOOK" and eo.movementType == 0x11,
        "route11 trainer 1 is FACE_DOWN_AND_LEFT") then return finish() end
    local r = track({ 1 }, 1500)[1]
    print("[driver] face_down_and_left facings=" .. keys(r.facings) .. " delays=" .. delayList(r))
    result(keys(r.facings) == "down,left", "FACE_DOWN_AND_LEFT only looks down and left")
    result(delaysIn(r, SHORT), "FACE_DOWN_AND_LEFT waits sMovementDelaysShort frames")
    result(r.moving == 0 and r.minX == r.maxX and r.minY == r.maxY, "FACE_DOWN_AND_LEFT never walks")
  end

  go("FR_ROUTE_8", 30, 10, "down")
  local looker = Objects.find(3)
  if not result(looker and looker.movement == "LOOK" and looker.movementType == 0x01,
      "route8 trainer 3 is LOOK_AROUND") then return finish() end
  do
    local r = track({ 3 }, 2400)[3]
    print("[driver] look_around facings=" .. keys(r.facings) .. " delays=" .. delayList(r))
    result(keys(r.facings) == "down,left,right,up", "LOOK_AROUND looks in all four directions")
    result(delaysIn(r, MEDIUM), "LOOK_AROUND waits sMovementDelaysMedium frames")
  end

  go("FR_FUCHSIA_CITY", 20, 30, "down")
  do
    local eo = Objects.find(2)
    if not result(eo and eo.movement == "WALK" and eo.movementType == 0x50,
        "fuchsia slowpoke is WANDER_AROUND_SLOWER") then return finish() end
    local r = track({ 2 }, 3000)[2]
    print(string.format("[driver] slowpoke home=(%d,%d) x=%d..%d y=%d..%d moving=%d stepFrames=%s delays=%s",
      eo.homeX, eo.homeY, r.minX, r.maxX, r.minY, r.maxY, r.moving, keys(r.stepFrames), delayList(r)))
    result(r.moving > 0 and keys(r.stepFrames) == "32", "slowpoke steps take 32 frames")
    result(not r.fractional, "slowpoke sprite moves in whole pixels")
    result(r.minX >= eo.homeX - eo.rangeX and r.maxX <= eo.homeX + eo.rangeX
      and r.minY >= eo.homeY - eo.rangeY and r.maxY <= eo.homeY + eo.rangeY, "slowpoke stays inside its range")
    result(delaysIn(r, MEDIUM), "slowpoke waits sMovementDelaysMedium frames")
  end

  -- src/event_object_movement.c:3044
  go("FR_ROUTE_8", 30, 10, "down")
  looker = Objects.find(3)
  local spot
  for _, off in ipairs({ { 2, 0, "left" }, { -2, 0, "right" }, { 0, -2, "down" } }) do
    local mx, my = looker.cellX + off[1] / 2, looker.cellY + off[2] / 2
    local px, py = looker.cellX + off[1], looker.cellY + off[2]
    if Collision.canEnter(game, mx, my, {}) and Collision.canEnter(game, px, py, {})
        and not Objects.at(mx, my) and not Objects.at(px, py) then
      spot = { x = px, y = py, face = off[3],
        want = off[1] > 0 and "right" or off[1] < 0 and "left" or "up" }
      break
    end
  end
  if not result(spot ~= nil, "found a side cell in the LOOK_AROUND trainer's reach") then return finish() end
  looker.facing = "down"
  Player.reset(spot.x, spot.y, spot.face)
  local spottedFacing
  for _ = 1, 4000 do
    U.wait(1)
    if Field.locked and looker.scriptBusy then
      spottedFacing = looker.facing
      break
    end
  end
  print("[driver] look_around spotted facing=" .. tostring(spottedFacing) .. " want=" .. spot.want)
  result(spottedFacing == spot.want, "LOOK_AROUND trainer turned and spotted the player from the side")
  U.wait(20)
  U.shot(game, DIR .. "/mov_lookaround_spots_from_side.png")

  return finish()
end

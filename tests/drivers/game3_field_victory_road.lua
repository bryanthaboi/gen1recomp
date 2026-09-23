local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_victory_road"

-- pokefirered/include/constants/vars.h:152
local VAR_MAP_SCENE_VICTORY_ROAD_1F = 0x4064
local VR1F = "FR_VICTORY_ROAD_1F"
-- pokefirered/data/maps/Route23/scripts.inc:8
local VR2F = "FR_VICTORY_ROAD_2F"
-- pokefirered/data/maps/VictoryRoad_1F/scripts.inc:11
local BARRIER_X, BARRIER_TOP, BARRIER_BOTTOM = 12, 14, 15
local SWITCH_X, SWITCH_Y = 20, 16
local BOULDER_ID = 5

local PATH = {
  "left", "left", "left", "left", "left", "up", "up", "right", "down", "left",
  "down", "right", "right", "right", "right", "right", "down", "right", "up", "up",
  "left", "up", "right", "right", "right", "right", "right", "right", "right", "down",
  "right", "up", "up", "down", "left", "left", "up", "up", "right", "right",
  "up", "right", "down",
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_victory_road")
    love.event.quit(0)
  else
    print("FAIL field_victory_road failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(60)
  end

  -- pokefirered/include/constants/vars.h:47 VAR_REPEL_STEP_COUNT
  local party = session.party
  if type(party) == "table" and type(party[1]) == "table" then
    party[1].level = 60
  end
  session.repelSteps = 250

  local function armStrength()
    Flags.setFlag(Space.store, ctx(), FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
    session.repelSteps = 250
  end

  local function barrierShut()
    local o = Field.metatileOverrideAt(VR1F, BARRIER_X, BARRIER_TOP)
    return o ~= nil and o.impassable == true
  end

  local function canPass()
    return Collision.canEnter(game, BARRIER_X, BARRIER_BOTTOM,
      { fromX = BARRIER_X - 1, fromY = BARRIER_BOTTOM, dir = "right" }) == true
  end

  local function walk(dir)
    local sx, sy = Player.cellX, Player.cellY
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then break end
      if Player.boulderPush then
        for _ = 1, 40 do
          if not Player.boulderPush then break end
          U.hold(game, dir, 1)
        end
      end
    end
    for _ = 1, 48 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(1)
    return Player.cellX ~= sx or Player.cellY ~= sy
  end

  local function runScript(limit)
    local n = 0
    while n < (limit or 600) do
      if not (Space.vm and Space.vm:isRunning()) then break end
      U.wait(6)
      n = n + 6
    end
  end

  goTo(VR1F, 11, 15, "right")
  armStrength()
  result(Space.mapId == VR1F, "stood on Victory Road 1F, map=" .. tostring(Space.mapId))
  result(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F) == 0,
    "VAR_MAP_SCENE_VICTORY_ROAD_1F starts at 0, got " ..
    tostring(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F)))
  result(barrierShut(), "ON_LOAD walled the rock barrier at (12,14)/(12,15)")
  result(not canPass(), "the barrier blocks the way north")
  U.shot(game, DIR .. "/field_victory_road_01_barrier_up.png")

  goTo(VR1F, 11, 19, "up")
  armStrength()
  local boulder = Objects.find(BOULDER_ID)
  result(boulder ~= nil and boulder.cellX == 7 and boulder.cellY == 18,
    "the strength boulder sits at (7,18)")

  local walked = 0
  for i, dir in ipairs(PATH) do
    if walk(dir) then
      walked = walked + 1
    else
      U.log(string.format("step %d (%s) went nowhere at (%s,%s)", i, dir,
        tostring(Player.cellX), tostring(Player.cellY)))
    end
    if Space.vm and Space.vm:isRunning() then runScript(600) end
  end
  U.log("walked " .. walked .. "/" .. #PATH .. " steps, player at (" ..
    tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")

  boulder = Objects.find(BOULDER_ID)
  result(boulder ~= nil and boulder.cellX == SWITCH_X and boulder.cellY == SWITCH_Y,
    "the boulder was pushed onto the floor switch, at (" ..
    tostring(boulder and boulder.cellX) .. "," .. tostring(boulder and boulder.cellY) .. ")")
  runScript(900)
  U.wait(60)
  result(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F) == 100,
    "the floor-switch script ran, var=" .. tostring(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F)))
  U.shot(game, DIR .. "/field_victory_road_02_switch_pressed.png")

  result(not barrierShut(), "the rock barrier is gone")
  result(canPass(), "the way north is walkable")

  goTo(VR2F, 1, 10, "down")
  U.wait(30)
  goTo(VR1F, 11, 15, "right")
  U.wait(30)
  result(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F) == 100,
    "the var survived the reload, var=" .. tostring(getVar(VAR_MAP_SCENE_VICTORY_ROAD_1F)))
  result(not barrierShut(), "ON_LOAD did not re-wall the barrier")
  result(canPass(), "the way north is still walkable after the reload")
  U.shot(game, DIR .. "/field_victory_road_03_barrier_open_after_reload.png")

  finish()
end

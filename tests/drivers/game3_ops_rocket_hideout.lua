local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ops_rocket_hideout"

local B4F = "FR_ROCKET_HIDEOUT_B4F"

-- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:1
local NUM_DOOR_GRUNTS_DEFEATED = 0x4001
-- pokefirered/include/constants/opponents.h:372
local TRAINER_TEAM_ROCKET_GRUNT_16 = 366
-- pokefirered/include/constants/opponents.h:373
local TRAINER_TEAM_ROCKET_GRUNT_17 = 367

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS ops_rocket_hideout")
    love.event.quit(0)
  else
    print("FAIL ops_rocket_hideout failures=" .. failures)
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
  local Field = require("src.core.game3.field")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function setTrainerFlag(tid)
    Flags.setFlag(Space.store, ctx(), Flags.trainerFlagId(tid), true)
  end

  local function goTo(x, y, facing)
    Map.load(nil, game, B4F, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function barrierAt(x, y)
    local o = Field.metatileOverrideAt(B4F, x, y)
    return o ~= nil and o.impassable == true
  end

  local function step(dir)
    local bx, by = Player.cellX, Player.cellY
    for _ = 1, 4 do
      U.hold(game, dir, 8)
      if Player.cellX ~= bx or Player.cellY ~= by then
        while Player.moving do U.wait(1) end
        return true
      end
    end
    return false
  end

  local function walk(dir, steps)
    local moved = 0
    for _ = 1, steps do
      if not step(dir) then break end
      moved = moved + 1
    end
    return moved
  end

  goTo(17, 16, "up")
  result(getVar(NUM_DOOR_GRUNTS_DEFEATED) == 0,
    "OnLoad counted 0 grunts, var=" .. tostring(getVar(NUM_DOOR_GRUNTS_DEFEATED)))
  result(barrierAt(17, 13) and barrierAt(18, 13) and barrierAt(17, 12) and barrierAt(18, 12),
    "the barrier metatiles at (17-18, 12-13) are impassable")
  U.shot(game, DIR .. "/ops_rocket_hideout_01_barrier_closed.png")
  walk("up", 8)
  print("[driver] blocked at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellY >= 14, "the player is stopped south of the barrier, y=" .. Player.cellY)

  -- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:15
  setTrainerFlag(TRAINER_TEAM_ROCKET_GRUNT_16)
  setTrainerFlag(TRAINER_TEAM_ROCKET_GRUNT_17)
  goTo(17, 16, "up")
  result(getVar(NUM_DOOR_GRUNTS_DEFEATED) == 2,
    "addvar counted both grunts, var=" .. tostring(getVar(NUM_DOOR_GRUNTS_DEFEATED)))
  result(not barrierAt(17, 13) and not barrierAt(18, 13),
    "no barrier override was written")
  U.wait(240)
  U.shot(game, DIR .. "/ops_rocket_hideout_02_barrier_open.png")

  walk("up", 12)
  print("[driver] walked to (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellY <= 11, "the player walked through the old barrier, y=" .. Player.cellY)

  -- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:18
  walk("up", 8)
  while Player.cellX < 19 do
    if not step("right") then break end
  end
  print("[driver] at (" .. Player.cellX .. "," .. Player.cellY .. ") before facing Giovanni")
  result(Player.cellX == 19 and Player.cellY == 5,
    "walked to the cell below Giovanni, (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.hold(game, "up", 10)
  U.wait(20)
  U.tap(game, "a")
  U.wait(60)
  local talking = (Space.vm and Space.vm:isRunning())
    or (Message.isOpen and Message.isOpen())
  result(talking, "Giovanni's script started")
  U.shot(game, DIR .. "/ops_rocket_hideout_03_giovanni.png")

  finish()
end

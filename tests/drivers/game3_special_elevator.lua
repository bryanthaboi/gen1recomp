local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_special_elevator"

local ELEVATOR = "FR_ROCKET_HIDEOUT_ELEVATOR"
local SIGN_XY = { 1, 2 }

-- pokefirered/include/constants/flags.h:702
local FLAG_CAN_USE_ROCKET_HIDEOUT_LIFT = 0x2A5
-- pokefirered/include/constants/items.h:428
local ITEM_LIFT_KEY = 356
local VAR_ELEVATOR_FLOOR = 0x403A -- pokefirered/include/constants/vars.h:108

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS special_elevator")
    love.event.quit(0)
  else
    print("FAIL special_elevator failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function var(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  -- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:61
  Flags.setFlag(Space.store, ctx(), FLAG_CAN_USE_ROCKET_HIDEOUT_LIFT, true)
  if session.bag then pcall(Bag.add, session.bag, ITEM_LIFT_KEY, 1) end

  local function dynamicMap()
    local Elevator = require("src.core.game3.scripting.natives_elevator")
    return Elevator.dynamicWarpMap()
  end

  goTo(ELEVATOR, SIGN_XY[1], SIGN_XY[2], "left")

  local function scriptRunning()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning() or false
  end

  local function talkToPanel()
    for _ = 1, 20 do
      if scriptRunning() or Choice.active then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return scriptRunning() or Choice.active
  end

  local function waitForChoice()
    for _ = 1, 400 do
      if Choice.active then return true end
      local Message = package.loaded["src.ui.game3.message"]
      if Message and Message.isOpen and Message.isOpen() and not Choice.active then
        U.tap(game, "a")
      end
      U.wait(4)
    end
    return Choice.active
  end

  local function waitIdle()
    for _ = 1, 900 do
      if not scriptRunning() and not Choice.active then return true end
      U.wait(4)
    end
    return false
  end

  result(talkToPanel(), "the lift panel answers with the Lift Key in the bag")
  result(waitForChoice(), "the floor menu opened")
  local firstLabel = Choice.options and Choice.options[1]
  result(firstLabel == "B1F", "the floor list is the Rocket Hideout list, first entry " ..
    tostring(firstLabel))
  -- pokefirered/src/field_specials.c:836
  result(var(VAR_ELEVATOR_FLOOR) == 4,
    "GetElevatorFloor set the cart default floor 4, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  result(Choice.cursor == 1,
    "InitElevatorFloorSelectMenuPos put the cursor on entry 1, got " .. tostring(Choice.cursor))
  U.shot(game, DIR .. "/special_elevator_01_floor_menu.png")

  U.tap(game, "down")
  U.wait(10)
  result(Choice.cursor == 2, "the cursor moved to B2F")
  U.tap(game, "a")
  U.wait(10)
  result(waitIdle(), "the elevator script finished")
  result(var(VAR_ELEVATOR_FLOOR) == 2,
    "VAR_ELEVATOR_FLOOR is B2F after the ride, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  result(dynamicMap() == "FR_ROCKET_HIDEOUT_B2F",
    "the engine recorded the dynamic warp to B2F, got " .. tostring(dynamicMap()))

  goTo(ELEVATOR, SIGN_XY[1], SIGN_XY[2], "left")
  result(talkToPanel(), "the panel answers again")
  result(waitForChoice(), "the floor menu reopened")
  result(var(VAR_ELEVATOR_FLOOR) == 2,
    "the second visit starts on B2F, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  result(Choice.cursor == 2,
    "the cursor opens on the current floor B2F, got " .. tostring(Choice.cursor))
  U.shot(game, DIR .. "/special_elevator_02_cursor_on_current_floor.png")
  U.tap(game, "b")
  U.wait(10)
  waitIdle()

  finish()
end

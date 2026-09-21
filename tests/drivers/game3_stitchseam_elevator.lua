local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchseam_elevator"

local SILPH = "FR_SILPH_CO_ELEVATOR"
local HIDEOUT = "FR_ROCKET_HIDEOUT_ELEVATOR"
local SIGN_XY = { 1, 2 }

local VAR_ELEVATOR_FLOOR = 0x403A -- pokefirered/include/constants/vars.h:108
-- pokefirered/include/constants/flags.h:702
local FLAG_CAN_USE_ROCKET_HIDEOUT_LIFT = 0x2A5
-- pokefirered/include/constants/items.h:428
local ITEM_LIFT_KEY = 356

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchseam_elevator")
    love.event.quit(0)
  else
    print("FAIL stitchseam_elevator failures=" .. failures)
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
  local Gfx = require("src.core.game3.gfx")
  local Choice = require("src.ui.game3.choice")
  local ElevatorWindow = require("src.ui.game3.elevator_window")
  local ListMenu = require("src.core.game3.scripting.natives_listmenu")
  local Menu = ListMenu.Menu

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  result(type(Gfx.drawUi) == "function", "the field HUD compositor is reachable")

  local paints = 0
  local realDraw = ElevatorWindow.draw
  ElevatorWindow.draw = function(...)
    paints = paints + 1
    return realDraw(...)
  end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function var(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function scriptRunning()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning() or false
  end
  local function menuUp()
    return Menu.isOpen() or Choice.active or false
  end

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

  local function talkToPanel()
    for _ = 1, 20 do
      if scriptRunning() or menuUp() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return scriptRunning() or menuUp()
  end

  local function waitForMenu()
    for _ = 1, 400 do
      if menuUp() then return true end
      local Message = package.loaded["src.ui.game3.message"]
      if Message and Message.isOpen and Message.isOpen() and not menuUp() then
        U.tap(game, "a")
      end
      U.wait(4)
    end
    return menuUp()
  end

  local function waitIdle()
    for _ = 1, 900 do
      if not scriptRunning() and not menuUp() then return true end
      U.wait(4)
    end
    return false
  end

  print("[driver] scene 1: the Rocket Hideout lift, multichoice plus the floor window")
  -- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:61
  Flags.setFlag(Space.store, ctx(), FLAG_CAN_USE_ROCKET_HIDEOUT_LIFT, true)
  if session.bag then pcall(Bag.add, session.bag, ITEM_LIFT_KEY, 1) end

  goTo(HIDEOUT, SIGN_XY[1], SIGN_XY[2], "left")
  if not result(talkToPanel(), "the Rocket Hideout panel answers") then return finish() end
  if not result(waitForMenu(), "the B-floor multichoice opened") then return finish() end
  -- pokefirered/data/maps/RocketHideout_Elevator/scripts.inc:9
  result(ElevatorWindow.isVisible(),
    "DrawElevatorCurrentFloorWindow left the floor window open under the multichoice")
  result(Choice.active, "the multichoice owns input at the same time")

  paints = 0
  U.wait(60)
  print("[driver] ElevatorWindow.draw calls over 60 visible frames: " .. paints)
  result(paints > 0, "the open floor window is painted every frame by Gfx.drawUi")
  result(Choice.active, "and the multichoice still owns input, the window never stole it")

  for _ = 1, 2 do
    U.tap(game, "down")
    U.wait(10)
  end
  result(Choice.cursor == 3, "the cursor is on B4F, got " .. tostring(Choice.cursor))
  U.tap(game, "a")
  U.wait(10)
  result(waitIdle(), "the Rocket Hideout ride finished")
  result(var(VAR_ELEVATOR_FLOOR) == 0,
    "VAR_ELEVATOR_FLOOR is B4F after the ride, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  -- pokefirered/data/maps/RocketHideout_Elevator/scripts.inc:73
  result(not ElevatorWindow.isVisible(),
    "CloseElevatorCurrentFloorWindow took the window off the field")
  paints = 0
  U.wait(30)
  result(paints == 0, "the compositor stopped painting it, " .. paints .. " calls")

  goTo(HIDEOUT, SIGN_XY[1], SIGN_XY[2], "left")
  if not result(talkToPanel(), "the panel answers a second time") then return finish() end
  if not result(waitForMenu(), "the multichoice reopened") then return finish() end
  -- pokefirered/src/field_specials.c:1106
  result(ElevatorWindow.label() == "B4F",
    "the window reads the floor the lift is on, got " .. tostring(ElevatorWindow.label()))
  U.shot(game, DIR .. "/stitchseam_elevator_01_hideout_b4f_window.png")
  U.tap(game, "b")
  U.wait(10)
  waitIdle()

  print("[driver] scene 2: the Silph Co lift, ListMenu plus the floor window")
  goTo(SILPH, SIGN_XY[1], SIGN_XY[2], "left")
  if not result(talkToPanel(), "the Silph lift panel answers") then return finish() end
  if not result(waitForMenu(), "special ListMenu opened the floor list") then return finish() end
  result(Menu.isOpen(), "the twelve-floor list is up")
  result(ElevatorWindow.isVisible(), "with the floor window beside it")
  -- pokefirered/src/field_specials.c:836
  result(var(VAR_ELEVATOR_FLOOR) == 0,
    "GetElevatorFloor still reads B4F from the dynamic warp, got " ..
    tostring(var(VAR_ELEVATOR_FLOOR)))
  result(ElevatorWindow.label() == "B4F",
    "the floor list and Now on: B4F are on screen together, got " ..
    tostring(ElevatorWindow.label()))
  paints = 0
  U.wait(30)
  result(paints > 0, "the compositor paints it over the Silph list too, " .. paints .. " calls")
  U.shot(game, DIR .. "/stitchseam_elevator_02_silph_list_and_window.png")

  for _ = 1, 14 do
    if Menu.selection() == 6 then break end
    U.tap(game, "down")
    U.wait(8)
  end
  result(Menu.selection() == 6, "the cursor is on 5F, index " .. tostring(Menu.selection()))
  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 900 do
    if not scriptRunning() then break end
    U.wait(4)
  end
  result(not scriptRunning(), "the Silph elevator script finished")
  result(var(VAR_ELEVATOR_FLOOR) == 8,
    "VAR_ELEVATOR_FLOOR is 5F after the ride, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  -- pokefirered/data/maps/SilphCo_Elevator/scripts.inc:132
  result(not ElevatorWindow.isVisible(), "and the floor window closed with the script")
  paints = 0
  U.wait(30)
  result(paints == 0, "nothing paints it afterwards, " .. paints .. " calls")

  print("[driver] scene 3: a soft reset with the floor window up")
  goTo(SILPH, SIGN_XY[1], SIGN_XY[2], "left")
  if not result(talkToPanel(), "the Silph panel answers a second time") then return finish() end
  if not result(waitForMenu(), "the floor list opened again") then return finish() end
  result(ElevatorWindow.isVisible(), "the floor window is up when the reset comes")

  for _ = 1, 40 do
    for _, b in ipairs({ "a", "b", "start", "select" }) do game.input.state[b] = true end
    coroutine.yield()
    if game.phase == "boot" then break end
  end
  for _, b in ipairs({ "a", "b", "start", "select" }) do game.input.state[b] = false end
  U.wait(30)
  if not result(game.phase == "boot", "A+B+START+SELECT returned to the title") then
    return finish()
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  paints = 0
  U.wait(60)
  U.shot(game, DIR .. "/stitchseam_elevator_03_after_soft_reset.png")
  result(not ElevatorWindow.isVisible(),
    "the floor window did not survive the soft reset")
  result(paints == 0,
    "and nothing paints it on the new session's field, " .. paints .. " calls in 60 frames")

  ElevatorWindow.draw = realDraw
  finish()
end

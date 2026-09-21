local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_special_silph_elevator"

local ELEVATOR = "FR_SILPH_CO_ELEVATOR"
local SIGN_XY = { 1, 2 }
local EXIT_XY = { 2, 5 }

local VAR_ELEVATOR_FLOOR = 0x403A -- pokefirered/include/constants/vars.h:108
local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS special_silph_elevator")
    love.event.quit(0)
  else
    print("FAIL special_silph_elevator failures=" .. failures)
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
  local ListMenu = require("src.core.game3.scripting.natives_listmenu")
  local Menu = ListMenu.Menu

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

  local Elevator = require("src.core.game3.scripting.natives_elevator")

  goTo(ELEVATOR, SIGN_XY[1], SIGN_XY[2], "left")

  local function scriptRunning()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning() or false
  end

  local function talkToPanel()
    for _ = 1, 20 do
      if scriptRunning() or Menu.isOpen() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return scriptRunning() or Menu.isOpen()
  end

  local function waitForList()
    for _ = 1, 400 do
      if Menu.isOpen() then return true end
      local Message = package.loaded["src.ui.game3.message"]
      if Message and Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return Menu.isOpen()
  end

  result(talkToPanel(), "the Silph lift panel answers")
  result(waitForList(), "special ListMenu opened the floor list")
  -- pokefirered/src/field_specials.c:836
  result(var(VAR_ELEVATOR_FLOOR) == 4,
    "GetElevatorFloor put the lift on 1F, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))
  -- pokefirered/src/field_specials.c:931
  result(Menu.scroll == 0 and Menu.row == 1,
    "InitElevatorFloorSelectMenuPos opened the list at the top, scroll " ..
    tostring(Menu.scroll) .. " row " .. tostring(Menu.row))
  result(Menu.selection() == 0, "11F is list index 0, got " .. tostring(Menu.selection()))
  U.shot(game, DIR .. "/special_silph_elevator_01_floor_list.png")

  for _ = 1, 6 do
    U.tap(game, "down")
    U.wait(8)
  end
  result(Menu.selection() == 6, "the cursor is on 5F, index " .. tostring(Menu.selection()))
  U.shot(game, DIR .. "/special_silph_elevator_02_cursor_on_5f.png")
  U.tap(game, "a")
  U.wait(10)
  result(var(VAR_RESULT) == 6, "VAR_RESULT is the 5F case, got " .. tostring(var(VAR_RESULT)))

  for _ = 1, 900 do
    if not scriptRunning() then break end
    U.wait(4)
  end
  result(not scriptRunning(), "the elevator script finished")
  result(var(VAR_ELEVATOR_FLOOR) == 8,
    "VAR_ELEVATOR_FLOOR is 5F after the ride, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))

  -- pokefirered/src/field_specials.c:1132
  local Field = require("src.core.game3.field")
  local overrides = Field.metatileOverrides and Field.metatileOverrides[session.map]
  local written = 0
  for _ in pairs(overrides or {}) do written = written + 1 end
  result(written == 9, "the elevator window view wrote its nine metatiles, got " .. tostring(written))

  local Collision = require("src.core.game3.collision")
  local exitWarp = Collision.warpAt(EXIT_XY[1], EXIT_XY[2])
  U.log("exit tile warp: destMap=" .. tostring(exitWarp and exitWarp.destMap) ..
    " mapGroup=" .. tostring(exitWarp and exitWarp.mapGroup) ..
    " mapNum=" .. tostring(exitWarp and exitWarp.mapNum))

  for _ = 1, 40 do
    if Menu.isOpen() or scriptRunning() then U.tap(game, "b") end
    U.wait(4)
  end
  for _ = 1, 6 do
    if Player.cellY >= EXIT_XY[2] - 1 then break end
    U.hold(game, "down", 20)
    U.wait(10)
  end
  for _ = 1, 6 do
    if Player.cellX == EXIT_XY[1] then break end
    U.hold(game, "right", 20)
    U.wait(10)
  end
  for _ = 1, 3 do
    U.hold(game, "down", 24)
    U.wait(10)
  end
  U.wait(180)

  result(Elevator.dynamicWarpMap() == "FR_SILPH_CO_5F",
    "the engine recorded the dynamic warp to SILPH CO 5F, got " ..
    tostring(Elevator.dynamicWarpMap()))
  result(session.map == "FR_SILPH_CO_5F",
    "walking out of the lift arrives on 5F, got " .. tostring(session.map))
  U.shot(game, DIR .. "/special_silph_elevator_03_arrived_on_5f.png")

  finish()
end

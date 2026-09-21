local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchscript_warp_gifts"

local ELEVATOR = "FR_SILPH_CO_ELEVATOR"
local PANEL_XY = { 1, 2 }
local ROUTE4_PC = "FR_ROUTE_4_POKEMON_CENTER_1F"
local SALESMAN_XY = { 1, 4 }

local VAR_ELEVATOR_FLOOR = 0x403A -- pokefirered/include/constants/vars.h:108
local SPECIES_MAGIKARP = 129

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchscript_warp_gifts")
    love.event.quit(0)
  else
    print("FAIL stitchscript_warp_gifts failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Elevator = require("src.core.game3.scripting.natives_elevator")
  local ListMenu = require("src.core.game3.scripting.natives_listmenu")
  local Menu = ListMenu.Menu

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function var(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function scriptRunning()
    return (Space.vm and Space.vm.isRunning and Space.vm:isRunning()) or false
  end
  local function message()
    return package.loaded["src.ui.game3.message"]
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

  local function talkUntil(pred)
    for _ = 1, 24 do
      if pred() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return pred()
  end

  goTo(ELEVATOR, PANEL_XY[1], PANEL_XY[2], "left")
  result(talkUntil(function() return scriptRunning() or Menu.isOpen() end),
    "the Silph lift panel answers")

  for _ = 1, 400 do
    if Menu.isOpen() then break end
    local M = message()
    if M and M.isOpen and M.isOpen() then U.tap(game, "a") end
    U.wait(4)
  end
  result(Menu.isOpen(), "the floor list opened")
  U.shot(game, DIR .. "/stitchscript_warp_gifts_01_floor_list.png")

  for _ = 1, 6 do
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
  result(not scriptRunning(), "the elevator script finished")

  -- pokefirered/src/overworld.c:605
  result(Elevator.dynamicWarpMap() == "FR_SILPH_CO_5F",
    "setdynamicwarp recorded SILPH CO 5F, got " .. tostring(Elevator.dynamicWarpMap()))
  local dw = session.dynamicWarp or {}
  result(dw.warpId == -1 and dw.x == 22 and dw.y == 3,
    "the stored warp is warpId " .. tostring(dw.warpId) ..
    " at " .. tostring(dw.x) .. "," .. tostring(dw.y))
  -- pokefirered/src/field_specials.c:836
  result(var(VAR_ELEVATOR_FLOOR) == 8,
    "GetElevatorFloor reads 5F back off it, got " .. tostring(var(VAR_ELEVATOR_FLOOR)))

  for _ = 1, 40 do
    if Menu.isOpen() or scriptRunning() then U.tap(game, "b") end
    U.wait(4)
  end

  for _ = 1, 6 do
    if #session.party >= 6 then break end
    Party.giveMonToPlayer(session, 19, 5)
  end
  session.money = 5000
  Storage.ensure(session)
  result(#session.party == 6, "the party is full, " .. tostring(#session.party) .. " mons")
  result(session.storage.boxes[1].mons[1] == nil, "box 1 slot 1 starts empty")

  goTo(ROUTE4_PC, SALESMAN_XY[1], SALESMAN_XY[2], "up")
  result(talkUntil(function()
    local M = message()
    return scriptRunning() or (M and M.isOpen and M.isOpen())
  end), "the Magikarp salesman answers")

  local asked = false
  for _ = 1, 400 do
    local M = message()
    if M and M.isOpen and M.isOpen() then
      if M.isWaiting and M.isWaiting() then
        asked = true
        break
      end
      U.tap(game, "a")
    end
    U.wait(4)
  end
  result(asked, "the 500 Poke sales pitch is on screen")
  U.shot(game, DIR .. "/stitchscript_warp_gifts_02_sales_pitch.png")

  local Choice = require("src.ui.game3.choice")
  local answeredBuy = false
  for _ = 1, 600 do
    local M = message()
    local page = (M and M.currentPage and M.currentPage()) or ""
    if page:find("transferred") and M.isWaiting and M.isWaiting() then break end
    if Choice.active then
      if answeredBuy then
        U.tap(game, "b")
      else
        answeredBuy = true
        U.tap(game, "a")
      end
    elseif M and M.isOpen and M.isOpen() then
      U.tap(game, "a")
    end
    U.wait(6)
  end

  local M = message()
  local page = (M and M.currentPage and M.currentPage()) or ""
  result(page:find("transferred") ~= nil and page:find("PC") ~= nil,
    "the PC arm text is on screen: " .. string.gsub(page, "\n", " "))
  U.wait(20)
  U.shot(game, DIR .. "/stitchscript_warp_gifts_03_sent_to_pc.png")

  -- pokefirered/src/script_pokemon_util.c:48
  local boxed = session.storage.boxes[1].mons[1]
  result(boxed ~= nil and (boxed.speciesId or boxed.species) == SPECIES_MAGIKARP,
    "the bought MAGIKARP went to the PC instead of being refused, box holds " ..
    tostring(boxed and (boxed.speciesId or boxed.species)))
  result(session.monBoxId == 0 and session.monBoxPos == 0,
    "monBoxId/monBoxPos point at box 1 slot 1, got " ..
    tostring(session.monBoxId) .. "/" .. tostring(session.monBoxPos))
  result(#session.party == 6, "the party is still six, " .. tostring(#session.party))

  finish()
end

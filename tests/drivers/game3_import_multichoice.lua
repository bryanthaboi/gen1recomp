local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_multichoice"

local BIKE_SHOP = "FR_CERULEAN_CITY_BIKE_SHOP"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import_multichoice")
    love.event.quit(0)
  else
    print("FAIL import_multichoice failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local Multichoice = require("src.core.game3.scripting.multichoice")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then
    return finish()
  end

  local okStub = pcall(require, "src.import.gba." .. "multichoice" .. "_data_stub")
  result(not okStub, "the checked-in list table is not in the build")

  local lists = 0
  for _ in pairs(Multichoice.LISTS) do lists = lists + 1 end
  result(lists >= 65, "the cache multichoice table is live, lists=" .. lists)

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  Map.load(nil, game, BIKE_SHOP, { x = 9, y = 4, facing = "up" })
  place(9, 4, "up")
  U.wait(90)
  result(Space.mapId == BIKE_SHOP, "standing in the Cerulean Bike Shop, map=" ..
    tostring(Space.mapId))

  -- data/maps/CeruleanCity_BikeShop/scripts.inc:12
  for _ = 1, 60 do
    if Choice.active then break end
    U.tap(game, "a")
    U.wait(12)
  end
  result(Choice.active == true, "the Bike Shop clerk opened a multichoice")

  local opts = Choice.options or {}
  print("[driver] options: " .. table.concat(opts, " | "))
  result(#opts == 2, "list 13 has two entries (" .. #opts .. ")")
  local synthetic = false
  for _, label in ipairs(opts) do
    if tostring(label):find("^OPTION ") then synthetic = true end
  end
  result(not synthetic, "no synthetic OPTION label is on screen")
  result(tostring(opts[1]):find("BICYCLE") ~= nil,
    "entry 0 is the ROM BICYCLE line (" .. tostring(opts[1]) .. ")")
  result(opts[2] == "NO THANKS", "entry 1 is NO THANKS (" .. tostring(opts[2]) .. ")")
  U.shot(game, DIR .. "/import_multichoice_02_bike_shop_menu.png")

  U.tap(game, "b")
  U.wait(30)
  result(Choice.active == false, "B closes the menu")
  for _ = 1, 40 do
    if not ((Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())) then
      break
    end
    U.tap(game, "a")
    U.wait(12)
  end
  U.wait(30)

  finish()
end

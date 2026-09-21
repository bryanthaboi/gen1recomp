local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_braille_wall"

local B5F = "FR_MT_EMBER_RUBY_PATH_B5F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import2_braille_wall")
    love.event.quit(0)
  else
    print("FAIL import2_braille_wall failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Message = require("src.ui.game3.message")
  local Braille = require("src.ui.game3.braille")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  Map.load(nil, game, B5F, { x = 10, y = 7, facing = "left" })
  place(10, 7, "left")
  U.wait(90)

  if not result(Space.mapId == B5F, "the Ruby chamber loaded, map=" .. tostring(Space.mapId)) then
    return finish()
  end

  print("[driver] (7,2) coll=" .. string.format("0x%02X", Collision.cell(7, 2) or -1)
    .. " (7,3) coll=" .. string.format("0x%02X", Collision.cell(7, 3) or -1))
  result(Collision.isWalkable(7, 3), "the floor in front of the braille wall is walkable")
  result(not Collision.isWalkable(7, 2), "the braille wall at (7,2) is not walkable")

  local function step(dir)
    local sx, sy = Player.cellX, Player.cellY
    for _ = 1, 4 do
      U.tap(game, dir)
      U.wait(24)
      if Player.cellX ~= sx or Player.cellY ~= sy then break end
    end
    print("[driver] step " .. dir .. " -> (" .. tostring(Player.cellX) .. "," ..
      tostring(Player.cellY) .. ")")
  end
  local function walkTo(route, tx, ty, label)
    for _, dir in ipairs(route) do step(dir) end
    return result(Player.cellX == tx and Player.cellY == ty, label ..
      ", at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  end
  walkTo({ "up", "up" }, 10, 5, "walked north off the B4F landing")
  walkTo({ "left", "left", "left" }, 7, 5, "walked west across the chamber")
  walkTo({ "up", "up" }, 7, 3, "walked north to the cell below the braille wall")
  print("[driver] after the walk: (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY)
    .. ") facing " .. tostring(Player.facing))
  if not result(Player.cellX == 7 and Player.cellY == 3,
    "the walk ended on (7,3), got (" .. tostring(Player.cellX) .. "," ..
    tostring(Player.cellY) .. ")") then
    U.shot(game, DIR .. "/import2_braille_wall_00_lost.png")
    return finish()
  end

  U.hold(game, "up", 90)
  U.wait(30)
  print("[driver] after holding UP: (" .. tostring(Player.cellX) .. "," ..
    tostring(Player.cellY) .. ") facing " .. tostring(Player.facing))
  result(Player.cellX == 7 and Player.cellY == 3,
    "holding UP did not walk onto the braille wall")
  result(Player.facing == "up", "the player is facing the braille wall")
  U.shot(game, DIR .. "/import2_braille_wall_01_facing_wall.png")

  -- data/maps/MtEmber_RubyPath_B5F/scripts.inc:4
  U.tap(game, "a")
  U.wait(60)
  local running = (Space.vm and Space.vm:isRunning()) or false
  local open = (Message.isOpen and Message.isOpen()) or Braille.isOpen()
  result(running or open, "pressing A opened the braille message")
  result(Braille.isOpen(), "the braille panel is the one on screen")
  U.shot(game, DIR .. "/import2_braille_wall_02_braille_open.png")

  for _ = 1, 40 do
    if not ((Space.vm and Space.vm:isRunning()) or Braille.isOpen()) then break end
    U.tap(game, "a")
    U.wait(20)
  end
  U.wait(30)
  result(Player.cellX == 7 and Player.cellY == 3,
    "the player is still in front of the wall after the message")

  finish()
end

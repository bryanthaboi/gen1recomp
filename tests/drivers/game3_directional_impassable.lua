local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_directional_impassable"

local VR = "FR_VICTORY_ROAD_1F"
local SILPH = "FR_SILPH_CO_1F"
local EM = "FR_MT_EMBER_SUMMIT_PATH_2F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS directional_impassable")
    love.event.quit(0)
  else
    print("FAIL directional_impassable failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function walk(dir, tries)
    for _ = 1, (tries or 3) do
      U.hold(game, dir, 24)
      U.wait(14)
    end
    return Player.cellX, Player.cellY
  end

  local function at(x, y)
    return Player.cellX == x and Player.cellY == y
  end

  print("[driver] 1. Victory Road 1F cliff band (row 5, x 7..19)")
  goTo(VR, 17, 7, "up")
  result(Collision.behavior(17, 5) == 0x32, "(17,5) is MB_IMPASSABLE_NORTH")
  result(Collision.behavior(17, 4) == 0x08, "(17,4) above the band is MB_CAVE")

  walk("up", 2)
  print(string.format("[driver] after walking up from (17,7): (%d,%d)", Player.cellX, Player.cellY))
  result(at(17, 5), "the player walked up onto the cliff band at (17,5)")
  U.shot(game, DIR .. "/directional_impassable_01_on_band.png")

  walk("up", 3)
  print(string.format("[driver] after pushing up again: (%d,%d)", Player.cellX, Player.cellY))
  result(at(17, 5), "pushing north off the band is refused, the player stays at (17,5)")
  U.shot(game, DIR .. "/directional_impassable_02_north_refused.png")

  walk("right", 2)
  print(string.format("[driver] after walking east: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY == 5 and Player.cellX > 17, "the band itself is walkable east")

  walk("down", 2)
  print(string.format("[driver] after walking down: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY >= 6, "stepping south off the band is allowed")
  U.shot(game, DIR .. "/directional_impassable_03_off_band.png")

  print("[driver] 2. the same edge refuses the drop from above")
  goTo(VR, 17, 3, "down")
  walk("down", 4)
  print(string.format("[driver] after walking down from (17,3): (%d,%d)", Player.cellX, Player.cellY))
  result(at(17, 4), "the player stops on the cave floor at (17,4), never onto the band")
  U.shot(game, DIR .. "/directional_impassable_04_drop_refused.png")

  print("[driver] 3. Silph Co 1F lobby rail: MB_IMPASSABLE_EAST beside MB_IMPASSABLE_WEST")
  goTo(SILPH, 0, 12, "right")
  result(Collision.behavior(1, 12) == 0x30, "(1,12) is MB_IMPASSABLE_EAST")
  result(Collision.behavior(2, 12) == 0x31, "(2,12) is MB_IMPASSABLE_WEST")
  walk("right", 3)
  print(string.format("[driver] Silph after walking east from (0,12): (%d,%d)", Player.cellX, Player.cellY))
  result(at(1, 12), "the player steps onto (1,12) and the rail stops him there")
  U.shot(game, DIR .. "/directional_impassable_05_silph_east_rail.png")

  goTo(SILPH, 3, 12, "left")
  walk("left", 3)
  print(string.format("[driver] Silph after walking west from (3,12): (%d,%d)", Player.cellX, Player.cellY))
  result(at(2, 12), "the player steps onto (2,12) and the rail stops him there")
  U.shot(game, DIR .. "/directional_impassable_06_silph_west_rail.png")

  goTo(SILPH, 1, 12, "down")
  walk("down", 2)
  print(string.format("[driver] Silph after walking south from (1,12): (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellX == 1 and Player.cellY > 12, "the rail's north and south edges stay open")

  print("[driver] 4. Mt Ember Summit Path 2F shelf is floor, not wall")
  goTo(EM, 25, 44, "down")
  result(Collision.behavior(25, 44) == 0x32, "(25,44) is MB_IMPASSABLE_NORTH")
  result(Collision.cell(25, 44) ~= 0x07, "(25,44) bakes as walkable rock, not a wall")
  walk("right", 2)
  print(string.format("[driver] Mt Ember after walking east: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY == 44 and Player.cellX > 25, "the shelf is walkable east")
  U.shot(game, DIR .. "/directional_impassable_07_mt_ember_shelf.png")
  walk("up", 2)
  print(string.format("[driver] Mt Ember after pushing north: (%d,%d)", Player.cellX, Player.cellY))
  result(Player.cellY == 44, "every north edge inside the shelf is sealed")

  finish()
end

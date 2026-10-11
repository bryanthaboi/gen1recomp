local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pc_escalator_rail_2848"

local failures = 0
local function result(ok, label, detail)
  print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS pc_escalator_rail_2848")
    love.event.quit(0)
  else
    print("FAIL pc_escalator_rail_2848 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local version = require("src.core.GameVersion").get()
  local rse = version == "emerald" or version == "ruby" or version == "sapphire"
  game:_handleBootAction({ action = "new_game", name = rse and "BRENDAN" or "RED", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")

  if not result(Runtime.getSession() ~= nil, "new_game_reached_field", version) then return finish() end

  local PC2 = rse and "EM_OLDALE_TOWN_POKEMON_CENTER_2F" or "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
  local PC1 = rse and "EM_OLDALE_TOWN_POKEMON_CENTER_1F" or "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"

  local function settle(limit)
    for _ = 1, (limit or 240) do
      local busy = (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
      if not busy then return true end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end

  local function at(x, y) return Player.cellX == x and Player.cellY == y end
  local function pos()
    return string.format("%s (%d,%d) elev=%s", tostring(Map.current), Player.cellX, Player.cellY,
      tostring(Player.currentElevation))
  end

  local function step(dir)
    local fx, fy = Player.cellX, Player.cellY
    for _ = 1, 3 do
      U.hold(game, dir, 4)
      for _ = 1, 60 do
        U.wait(1)
        if not Player.moving then break end
      end
      if Player.cellX ~= fx or Player.cellY ~= fy or Warp.isBusy() then break end
    end
    U.wait(8)
  end

  Map.load(nil, game, PC2, { x = 3, y = 6, facing = "left" })
  U.wait(60)
  settle(600)
  result(Map.current == PC2 and at(3, 6), "loaded_pc2f", pos())

  step("left")
  step("up")
  step("left")
  result(Map.current == PC2 and at(1, 5), "standing_above_escalator", pos())
  U.still(game, DIR .. "/2848_01_above_escalator.png")

  step("down")
  U.wait(30)
  result(Map.current == PC2 and at(1, 5) and not Warp.isEscalatorActive(),
    "down_from_rail_blocked", pos())
  U.still(game, DIR .. "/2848_02_down_from_rail_blocked.png")

  step("right")
  step("down")
  result(Map.current == PC2 and at(2, 6), "beside_escalator", pos())
  local rode = false
  for _ = 1, 3 do
    U.hold(game, "left", 4)
    for _ = 1, 30 do
      U.wait(1)
      if Warp.isEscalatorActive() then rode = true end
    end
    if rode then break end
  end
  if rode then U.still(game, DIR .. "/2848_03_riding_from_side.png") end
  for _ = 1, 600 do
    if Map.current == PC1 and not Warp.isBusy() then break end
    U.wait(1)
  end
  settle(300)
  result(rode and Map.current == PC1, "escalator_from_side_reaches_1f", pos())

  finish()
end

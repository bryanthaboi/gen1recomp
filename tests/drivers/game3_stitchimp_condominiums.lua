local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_condominiums"

local CELADON = "FR_CELADON_CITY"
local ONE_F = "FR_CELADON_CITY_CONDOMINIUMS_1F"
local TWO_F = "FR_CELADON_CITY_CONDOMINIUMS_2F"
local THREE_F = "FR_CELADON_CITY_CONDOMINIUMS_3F"
local HIDEOUT = "FR_ROCKET_HIDEOUT_B2F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_condominiums")
    love.event.quit(0)
  else
    print("FAIL stitchimp_condominiums failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function look(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    U.wait(30)
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    look(x, y, facing)
    U.wait(60)
  end

  local function trueSize()
    local def = game.data and game.data.maps and game.data.maps[Space.mapId]
    local L = def and def.midLayout
    if not L then return 0, 0 end
    return L.trueWidth or L.width, L.trueHeight or L.height
  end

  -- pokefirered/include/constants/metatile_behaviors.h:66-69
  local function countSpins()
    local w, h = trueSize()
    local n = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local b = Collision.behavior(x, y)
        if b and b >= 0x54 and b <= 0x57 then n = n + 1 end
      end
    end
    return n
  end

  local function settle()
    local frames = 0
    while Player.moving and frames < 600 do
      U.wait(1)
      frames = frames + 1
    end
    return frames
  end

  goTo(CELADON, 30, 12, "up")
  result(Space.mapId == CELADON, "stood outside the Condominiums, map=" .. tostring(Space.mapId))
  U.hold(game, "up", 6)
  settle()
  for _ = 1, 120 do
    if Space.mapId == ONE_F then break end
    U.wait(1)
  end
  result(Space.mapId == ONE_F,
    "walked in through the front door, map=" .. tostring(Space.mapId))
  if Space.mapId ~= ONE_F then goTo(ONE_F, 12, 18, "up") end

  local w, h = trueSize()
  result(w == 15 and h == 20, "1F is pret's 15x20, got " .. w .. "x" .. h)
  local spins1 = countSpins()
  result(spins1 == 0, "1F has no spin tiles, " .. spins1 .. " cells")

  look(9, 14, "left")
  U.hold(game, "left", 6)
  local frames = settle()
  result(Player.cellX == 8 and Player.cellY == 14,
    "one LEFT press in the ground-floor hallway walked one cell, ended at (" ..
    Player.cellX .. "," .. Player.cellY .. ") after " .. frames .. " frames")
  U.shot(game, DIR .. "/condominiums_01_hallway_1f.png")

  goTo(TWO_F, 4, 3, "down")
  result(Space.mapId == TWO_F, "reached 2F, map=" .. tostring(Space.mapId))
  local spins2 = countSpins()
  result(spins2 == 0, "2F has no spin tiles, " .. spins2 .. " cells")
  U.shot(game, DIR .. "/condominiums_02_meeting_room_2f.png")

  goTo(THREE_F, 4, 3, "down")
  result(Space.mapId == THREE_F, "reached 3F, map=" .. tostring(Space.mapId))
  local spins3 = countSpins()
  result(spins3 == 0, "3F has no spin tiles, " .. spins3 .. " cells")
  U.shot(game, DIR .. "/condominiums_03_development_room_3f.png")

  goTo(HIDEOUT, 23, 11, "down")
  result(Space.mapId == HIDEOUT, "reached Rocket Hideout B2F, map=" .. tostring(Space.mapId))
  local spinsHideout = countSpins()
  result(spinsHideout > 0,
    "the real spinner floor still spins, " .. spinsHideout .. " cells")
  look(23, 11, "down")
  U.wait(150)
  U.shot(game, DIR .. "/condominiums_04_hideout_b2f_control.png")

  finish()
end

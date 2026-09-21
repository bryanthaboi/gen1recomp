local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchmap_header"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchmap_header")
    love.event.quit(0)
  else
    print("FAIL stitchmap_header failures=" .. failures)
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
  local MapCatalog = require("src.import.gba.map_catalog")
  local FieldView = require("src.core.game3.field_view")
  local BattleBridge = require("src.core.game3.battle_bridge")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
    return Map.currentDef()
  end

  local function report(def, label)
    if not def then return end
    print(string.format(
      "[driver] %s cave=%s escape=%s run=%s bike=%s scene=%s music=%s border=%sx%s",
      label, tostring(def.cave), tostring(def.allowEscaping), tostring(def.allowRunning),
      tostring(def.bikingAllowed), tostring(def.battleType), tostring(def.music),
      tostring(def.borderWidth), tostring(def.borderHeight)))
  end

  local PALLET = MapCatalog.pretToEngine("PalletTown")
  local GYM = MapCatalog.pretToEngine("ViridianCity_Gym")
  local ROCK = MapCatalog.pretToEngine("RockTunnel_1F")
  local MOON = MapCatalog.pretToEngine("MtMoon_1F")

  local def = goTo(PALLET, 5, 6, "down")
  report(def, "PalletTown")
  if not result(def ~= nil, "Pallet Town has a live map def") then return finish() end
  result(def.cave == 0, "Pallet Town cave=0")
  result(def.allowEscaping == 0, "Pallet Town allowEscaping=0")
  result(def.allowRunning == 1, "Pallet Town allowRunning=1")
  result(def.bikingAllowed == 1, "Pallet Town bikingAllowed=1")
  result(def.battleType == 0, "Pallet Town battleType=MAP_BATTLE_SCENE_NORMAL")
  result(def.music == 300, "Pallet Town music=MUS_PALLET")
  result(def.borderWidth == 2 and def.borderHeight == 2, "Pallet Town border is 2x2")
  U.shot(game, DIR .. "/stitchmap_header_01_pallet.png")

  def = goTo(GYM, 4, 13, "up")
  report(def, "ViridianCity_Gym")
  if not result(def ~= nil, "Viridian Gym has a live map def") then return finish() end
  result(def.battleType == 1, "Viridian Gym battleType=MAP_BATTLE_SCENE_GYM")
  result(def.bikingAllowed == 0, "Viridian Gym bikingAllowed=0")
  result(def.allowEscaping == 0, "Viridian Gym allowEscaping=0")
  result(BattleBridge.mapBattleScene(GYM) == def.battleType,
    "the def matches the header.json battle scene reader")
  U.shot(game, DIR .. "/stitchmap_header_02_viridian_gym.png")

  def = goTo(ROCK, 5, 5, "down")
  report(def, "RockTunnel_1F")
  if not result(def ~= nil, "Rock Tunnel 1F has a live map def") then return finish() end
  result(def.cave == 1, "Rock Tunnel 1F cave=1")
  result(def.allowEscaping == 1, "Rock Tunnel 1F allowEscaping=1")
  result(FieldView.defaultFlashLevel(game, ROCK) == FieldView.MAX_FLASH_LEVEL,
    "Rock Tunnel 1F asks for the full flash level")
  U.shot(game, DIR .. "/stitchmap_header_03_rock_tunnel.png")

  -- pokefirered/src/item_use.c:614 CanUseEscapeRopeOnCurrMap
  def = goTo(MOON, 5, 5, "down")
  report(def, "MtMoon_1F")
  if not result(def ~= nil, "Mt Moon 1F has a live map def") then return finish() end
  result(def.cave == 0, "Mt Moon 1F cave=0")
  result(def.allowEscaping == 1, "Mt Moon 1F allowEscaping=1")
  result(def.mapType == 4, "Mt Moon 1F mapType=MAP_TYPE_UNDERGROUND")
  U.shot(game, DIR .. "/stitchmap_header_04_mt_moon.png")

  finish()
end

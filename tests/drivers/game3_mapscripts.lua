local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mapscripts"

local BEDROOM = "FR_PLAYERS_HOUSE_2F"
local LORELEI = "FR_POKEMON_LEAGUE_LORELEIS_ROOM"
local LOBBY = "FR_TRAINER_TOWER_LOBBY"

-- pokefirered/data/maps/PalletTown_PlayersHouse_2F/scripts.inc:14
local VAR_MAP_SCENE_PLAYERS_HOUSE_2F = 0x4056

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS mapscripts")
    love.event.quit(0)
  else
    print("FAIL mapscripts failures=" .. failures)
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
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function getVar(id)
    return Flags.getVar(Space.store, Space.vm and Space.vm.ctx, id)
  end
  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.map, game.session.x, game.session.y = mapId, x, y
      game.session.facing = facing or "down"
    end
    U.wait(60)
  end

  print("[driver] step 1: the bedroom the new game warps you into")
  result(Map.current == BEDROOM, "new game landed on " .. tostring(Map.current))
  result(Player.facing == "up",
    "ON_WARP_INTO_MAP turned the player north, facing=" .. tostring(Player.facing))
  result(getVar(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 1,
    "the bedroom scene var advanced to 1, got "
    .. tostring(getVar(VAR_MAP_SCENE_PLAYERS_HOUSE_2F)))
  U.shot(game, DIR .. "/mapscripts_01_bedroom_faces_north.png")

  print("[driver] step 2: walking back up the stairs does not turn you again")
  goTo("FR_PLAYERS_HOUSE_1F", 10, 3, "up")
  U.hold(game, "up", 12)
  U.wait(30)
  local climbed = false
  -- pokefirered/src/field_player_avatar.c:556
  for _ = 1, 20 do
    U.hold(game, "right", 8)
    U.wait(30)
    if Map.current == BEDROOM then climbed = true break end
  end
  U.wait(90)
  if result(climbed, "walking up the stairs warped into the bedroom the real way") then
    result(Player.facing ~= "up",
      "the stair warp in leaves the player facing where the stairs put them, facing="
      .. tostring(Player.facing))
    result(getVar(VAR_MAP_SCENE_PLAYERS_HOUSE_2F) == 1,
      "the scene var is still 1, so the turn-north row no longer matches, got "
      .. tostring(getVar(VAR_MAP_SCENE_PLAYERS_HOUSE_2F)))
  end

  print("[driver] step 3: Lorelei's room turns you north on entry")
  goTo(LORELEI, 6, 11, "down")
  result(Player.facing == "up",
    "Lorelei's ON_WARP_INTO_MAP faced the player north, facing="
    .. tostring(Player.facing))
  U.shot(game, DIR .. "/mapscripts_02_lorelei_faces_north.png")

  print("[driver] step 4: ON_RETURN_TO_FIELD re-adds the Trainer Tower staff")
  goTo(LOBBY, 9, 10, "up")
  -- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:41
  for _ = 1, 16 do
    U.tap(game, "a")
    U.wait(12)
    if not (Space.vm and Space.vm:isRunning()) then break end
  end
  U.wait(30)
  local before = 0
  for lid = 1, 5 do
    local eo = Objects.find(lid)
    if eo and eo.visible then before = before + 1 end
  end
  result(before == 5, "the lobby spawned all 5 staff, got " .. before)
  U.shot(game, DIR .. "/mapscripts_03_lobby_staffed.png")
  for lid = 1, 5 do Objects.removeObject(lid) end
  U.wait(30)
  local cleared = 0
  for lid = 1, 5 do
    local eo = Objects.find(lid)
    if not eo or eo.visible == false then cleared = cleared + 1 end
  end
  result(cleared == 5, "removeobject cleared the lobby, gone=" .. cleared)
  U.shot(game, DIR .. "/mapscripts_04_lobby_empty.png")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Party = require("src.core.game3.party")
  Party.giveMon(session, 150, 100)
  result(BattleBridge.start(nil, game, { species = 100, level = 34 },
    { wild = true, headless = true, fade = false }) == true,
    "a battle started in the lobby")
  for _ = 1, 120 do
    if not Battle.isActive() then break end
    BattleBridge.finishPending("win")
    U.wait(5)
  end
  U.wait(60)
  local after = 0
  for lid = 1, 5 do
    local eo = Objects.find(lid)
    if eo and eo.visible then after = after + 1 end
  end
  result(after == 5,
    "the battle return ran ON_RETURN_TO_FIELD and the staff are back, got " .. after)
  U.shot(game, DIR .. "/mapscripts_05_lobby_restaffed.png")

  U.wait(10)
  finish()
end

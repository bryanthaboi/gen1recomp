local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_union_room"

local UNION_ROOM = "FR_UNION_ROOM"
local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/data/specials.inc:5 SetCableClubWarp
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
-- pokefirered/include/constants/vars.h:328
local VAR_RESULT = 0x800D
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS link_union_room")
    love.event.quit(0)
  else
    print("FAIL link_union_room failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
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
  local Objects = require("src.core.game3.objects")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Screen = require("src.ui.game3.union_room")
  local Game3Link = require("src.link.Game3Link")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)

  -- pokefirered/data/scripts/cable_club.inc:776 CableClub_EventScript_EnterUnionRoom
  Map.load(nil, game, CENTER_2F, { x = 5, y = 2, facing = "up" })
  place(5, 2, "up")
  U.wait(60)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(5, 1, "up")
  U.wait(10)
  local Natives = require("src.core.game3.scripting.natives")
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, Space.vm and Space.vm.adapters)
  result(session.dynamicWarp ~= nil and session.dynamicWarp.map == CENTER_2F,
    "SetCableClubWarp recorded the way back to the cable club counter")
  setVar(VAR_CABLE_CLUB_STATE, 6)
  Map.load(nil, game, UNION_ROOM, { x = 7, y = 11, facing = "up" })
  place(7, 11, "up")
  U.wait(120)

  result(Space.mapId == UNION_ROOM, "the player is in the Union Room")
  result(Union.isActive(), "the Union Room ON_RESUME ran RunUnionRoom")
  print("[driver] union state after entry: " .. tostring(Union.state))
  U.shot(game, DIR .. "/union_room_01_empty.png")

  local host, peer = Game3Link.loopback({ game = game })
  host:update(0)
  peer:update(0)
  Link.attach(host)
  result(host:isReady(), "the loopback session handshook")

  peer:send({
    type = Union.MSG.HELLO,
    name = "BLUE",
    trainerId = 0x2222,
    gender = 0,
    activity = Union.ACTIVITY.SEARCH + Union.IN_UNION_ROOM,
  })
  local waited = 0
  while waited < 300 and Union.playerCount() == 0 do
    U.wait(10)
    waited = waited + 10
  end
  if not result(Union.playerCount() == 1, "the peer appeared in the Union Room player list") then
    U.shot(game, DIR .. "/union_room_99_no_peer.png")
    return finish()
  end
  local avatar = Objects.find(Union.LOCAL_IDS[1])
  result(avatar ~= nil and avatar.visible == true,
    "the slot 1 union room avatar is on the map")
  U.wait(30)
  U.shot(game, DIR .. "/union_room_02_player_spawned.png")

  -- pokefirered/src/union_room.c:3264 UR_STATE_INTERACT_WITH_ATTENDANT
  place(3, 3, "up")
  U.wait(15)
  waited = 0
  while waited < 200 and not Screen.isOpen() do
    U.tap(game, "a")
    U.wait(20)
    waited = waited + 20
  end
  if result(Screen.isOpen(), "the Union Room attendant opened the player list") then
    result(Screen.mode == "board", "the list is the trading board view")
    result(#Screen.players == 1, "it lists the one other player in the room")
    U.wait(20)
    U.shot(game, DIR .. "/union_room_03_player_list.png")
    U.tap(game, "b")
    U.wait(30)
  end

  -- pokefirered/data/maps/UnionRoom/scripts.inc:28 UnionRoom_EventScript_Player1
  waited = 0
  while waited < 240 and not Screen.isOpen() do
    local eo = Objects.find(Union.LOCAL_IDS[1])
    if eo and not eo.moving then
      place(tonumber(eo.cellX), tonumber(eo.cellY) + 1, "up")
      U.wait(10)
      U.tap(game, "a")
    end
    U.wait(20)
    waited = waited + 30
  end
  if not result(Screen.isOpen(), "talking to the player opened the activity chooser") then
    print("[driver] VAR_RESULT=" .. tostring(getVar(VAR_RESULT)) ..
      " state=" .. tostring(Union.state))
    U.shot(game, DIR .. "/union_room_98_no_chooser.png")
    return finish()
  end
  result(Screen.mode == "activity", "the chooser is the invite-to-activity list")
  result(#Screen.items == 4, "GREETINGS / BATTLE / CHAT / EXIT")
  U.wait(20)
  U.shot(game, DIR .. "/union_room_04_activity_chooser.png")

  U.tap(game, "a")
  U.wait(30)
  print("[driver] after greeting: activity=" .. tostring(Union.activity)
    .. " state=" .. tostring(Union.state))
  result(not Screen.isOpen(), "GREETINGS closed the chooser")
  result(Union.activity == Union.ACTIVITY.CARD, "and sent the trainer card activity")
  U.shot(game, DIR .. "/union_room_05_after_greeting.png")

  -- pokefirered/src/union_room.c:2937 UR_STATE_TRAINER_APPEARS_BUSY
  waited = 0
  while waited < 600 and Union.state ~= "main" do
    U.tap(game, "a")
    U.wait(20)
    waited = waited + 20
  end
  result(Union.state == "main", "an unanswered request frees the room again")

  -- pokefirered/src/field_fadetransition.c:578 DoUnionRoomWarp
  waited = 0
  while waited < 200 and Screen.isOpen() do
    U.tap(game, "b")
    U.wait(20)
    waited = waited + 20
  end
  U.wait(30)
  place(7, 10, "down")
  U.wait(30)
  local Message = require("src.ui.game3.message")
  waited = 0
  while waited < 200 and Message.isOpen() do
    U.tap(game, "a")
    U.wait(20)
    waited = waited + 20
  end
  U.wait(20)
  U.hold(game, "down", 30)
  waited = 0
  while waited < 600 and Space.mapId == UNION_ROOM do
    U.wait(15)
    waited = waited + 15
  end
  U.wait(90)
  print("[driver] after the pad: map=" .. tostring(Space.mapId) ..
    " union=" .. tostring(Union.state) .. " cable=" .. tostring(getVar(VAR_CABLE_CLUB_STATE)))
  result(Space.mapId == CENTER_2F, "the pad warped the player back to the cable club counter")
  result(not Union.isActive(), "leaving the Union Room ended the session")
  waited = 0
  while waited < 600 and getVar(VAR_CABLE_CLUB_STATE) ~= 0 do
    U.tap(game, "a")
    U.wait(20)
    waited = waited + 20
  end
  result(getVar(VAR_CABLE_CLUB_STATE) == 0,
    "CableClub_EventScript_ExitUnionRoom cleared VAR_CABLE_CLUB_STATE")
  U.shot(game, DIR .. "/union_room_06_back_at_counter.png")

  Link.reset()
  finish()
end

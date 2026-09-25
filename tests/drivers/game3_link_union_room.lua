local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_union_room"

local Plaza = require("src.core.game3.link.union_plaza_map")
local UNION_ROOM = Plaza.MAP_ID
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
  local slotKey = require("src.import.gba.map_catalog").slotKeyFor("FR_UNION_ROOM") or ""
  local group, num = slotKey:match("(%d+)%D+(%d+)")
  -- pokefirered/data/scripts/cable_club.inc:797
  Space.vm.adapters.warp(tonumber(group), tonumber(num), 0xFF, 7, 11, function() end, "warpspinenter")
  U.wait(120)

  result(Space.mapId == UNION_ROOM, "the player is in the Union Room")
  result(Union.isActive(), "the Union Room ON_RESUME ran RunUnionRoom")
  print("[driver] union state after entry: " .. tostring(Union.state))
  U.shot(game, DIR .. "/union_room_01_empty.png")

  result(Union.relay and Union.capacity() == Plaza.CAP, "offline, the Union Room is still the 40-player plaza")
  result(Union.playerCount() == 0, "with nobody in it")
  local waited = 0
  -- pokefirered/src/field_fadetransition.c:578 DoUnionRoomWarp
  waited = 0
  while waited < 200 and Screen.isOpen() do
    U.tap(game, "b")
    U.wait(20)
    waited = waited + 20
  end
  U.wait(30)
  place(12, 22, "down")
  U.wait(30)
  local Message = require("src.ui.game3.message")
  waited = 0
  while waited < 200 and Message.isOpen() do
    U.tap(game, "a")
    U.wait(20)
    waited = waited + 20
  end
  U.wait(20)
  for _ = 1, 20 do
    if Space.mapId ~= UNION_ROOM then break end
    U.hold(game, "down", 8)
  end
  print("[driver] exit walk: p=" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY)
    .. " msg=" .. tostring(Message.isOpen()) .. " union=" .. tostring(Union.state))
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

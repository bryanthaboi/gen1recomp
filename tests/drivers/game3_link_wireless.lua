local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_wireless"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/include/constants/metatile_behaviors.h:104 MB_CABLE_CLUB_WIRELESS_MONITOR
local MB_CABLE_CLUB_WIRELESS_MONITOR = 0x8D
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
    print("PASS link_wireless")
    love.event.quit(0)
  else
    print("FAIL link_wireless failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Link = require("src.core.game3.link")
  local LT = require("src.core.game3.link.trade")
  local LinkMenu = require("src.ui.game3.link_menu")
  local Game3Link = require("src.link.Game3Link")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

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
  Map.load(nil, game, CENTER_2F, { x = 7, y = 5, facing = "down" })
  U.wait(90)
  result(Space.mapId == CENTER_2F, "the player is on the Pokemon Center 2F")

  -- pokefirered/src/field_control_avatar.c:572 MetatileBehavior_IsPlayerFacingCableClubWirelessMonitor
  local mx, my
  for y = 0, 40 do
    for x = 0, 40 do
      if Collision.behavior(x, y) == MB_CABLE_CLUB_WIRELESS_MONITOR then
        mx, my = x, y
        break
      end
    end
    if mx then break end
  end
  print("[driver] monitor cell=" .. tostring(mx) .. "," .. tostring(my))
  if not result(mx ~= nil, "the 2F has a wireless communication monitor tile") then
    Link.reset()
    return finish()
  end

  place(mx, my + 1, "up")
  U.wait(30)
  U.shot(game, DIR .. "/link_wireless_01_at_the_monitor.png")

  -- pokefirered/data/scripts/cable_club.inc:1080 IsWirelessAdapterConnected is FALSE with no session
  U.tap(game, "a")
  U.wait(90)
  result(LinkMenu.isOpen() == false,
    "with no adapter session the monitor only prints the not-connected message")
  U.shot(game, DIR .. "/link_wireless_02_not_connected.png")
  for _ = 1, 8 do
    U.tap(game, "a")
    U.wait(20)
  end

  local host, peer = Game3Link.loopback({ game = game })
  host:update(0)
  peer:update(0)
  Link.attach(host)
  result(host:isReady(), "a wireless session is up")
  LT.startMenu({ screen = false })
  peer:update(0)
  peer:take(LT.MSG.PARTY)
  U.wait(30)

  place(mx, my + 1, "up")
  U.wait(20)
  U.tap(game, "a")
  local guard = 0
  while guard < 300 and not (Space.vm and Space.vm:isRunning()) do
    peer:update(0)
    U.wait(1)
    guard = guard + 1
  end
  for _ = 1, 300 do
    peer:update(0)
    U.wait(1)
    if LinkMenu.isOpen() then break end
    local Message = package.loaded["src.ui.game3.message"]
    if Message and Message.isOpen and Message.isOpen() then break end
  end
  -- pokefirered/src/link.c:243
  result(LinkMenu.isOpen() == false,
    "with a cable session the monitor still prints the not-connected message")
  for _ = 1, 8 do
    U.tap(game, "a")
    U.wait(20)
  end

  -- pokefirered/src/wireless_communication_status_screen.c:195 ShowWirelessCommunicationScreen
  LinkMenu.show({})
  for _ = 1, 120 do
    peer:update(0)
    U.wait(1)
    if LinkMenu.isOpen() and #LinkMenu.rows > 0 then break end
  end
  print("[driver] screen open=" .. tostring(LinkMenu.isOpen())
    .. " rows=" .. tostring(#LinkMenu.rows))
  if not result(LinkMenu.isOpen(), "ShowWirelessCommunicationScreen puts the status screen up") then
    Link.reset()
    return finish()
  end
  U.wait(30)
  U.shot(game, DIR .. "/link_wireless_03_status_screen.png")

  local rows = LinkMenu.rows
  result(#rows == 4, "it lists trading, battling, the UNION ROOM and the total")
  -- pokefirered/src/wireless_communication_status_screen.c:144 ACTIVITY_TRADE counts two people
  result(rows[1] and rows[1].count == 2, "the trade this machine is in counts two people")
  result(rows[4] and rows[4].count == 2, "and the total says the same")

  local firstPal = LinkMenu.palIdx
  U.wait(40)
  result(LinkMenu.palIdx ~= firstPal, "the wave palette is cycling")
  U.shot(game, DIR .. "/link_wireless_04_wave_cycled.png")

  U.tap(game, "a")
  U.wait(60)
  result(LinkMenu.isOpen() == false, "A closes the screen")
  local Stack = require("src.ui.game3.stack")
  result(Stack.top() == nil, "nothing is left over the field (top=" .. tostring(Stack.top() and Stack.top().id) .. ")")
  U.shot(game, DIR .. "/link_wireless_05_back_on_the_floor.png")

  Link.reset()
  finish()
end

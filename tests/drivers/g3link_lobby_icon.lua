local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link_lobby_icon"

local CORNER = "FR_TWO_ISLAND_JOYFUL_GAME_CORNER"
local CHARMANDER = 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  if failures == 0 then
    print("PASS g3link_lobby_icon")
    love.event.quit(0)
  else
    print("FAIL g3link_lobby_icon failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

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
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local WirelessIcon = require("src.ui.game3.wireless_icon")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.trainerId = 0x1234
  Party.giveMon(session, CHARMANDER, 12)

  local drawn = 0
  local draw = WirelessIcon.draw
  WirelessIcon.draw = function(...)
    local ok = draw(...)
    if ok then drawn = drawn + 1 end
    return ok
  end
  local function iconDrawn(frames)
    drawn = 0
    for _ = 1, 4000 do
      if drawn >= (frames or 3) then return true end
      U.wait(1)
      if drawn == 0 and _ > 600 then return false end
    end
    return drawn > 0
  end

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })
  local function waitFor(cond, seconds)
    local t0 = now()
    while not cond() do
      relay:pump()
      U.wait(1)
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end

  Map.load(nil, game, CORNER, { x = 6, y = 3, facing = "up" })
  U.wait(60)
  result(Link.liveProfile() ~= nil, "the live g3 profile computes")
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5), "the Client is online on the relay")
  print("[driver] state=" .. tostring(WirelessIcon.connectState()) .. " anim=" .. tostring(WirelessIcon.anim()))
  result(iconDrawn(), "Joyful Game Corner field draws the icon")

  Lobby.showPlayers({}, { mode = "leader", group = { min = 2, max = 5 }, activity = 9 })
  result(iconDrawn(), "leader lobby draws the icon")
  U.still(game, DIR .. "/g3link_lobby_icon_leader.png")
  Lobby.showPlayers({ { slot = 1, name = "BLUE", trainerId = 0x2222 } },
    { mode = "group", capacity = { activity = 9, min = 2, max = 5 } })
  result(iconDrawn(), "joiner lobby draws the icon")
  U.still(game, DIR .. "/g3link_lobby_icon_joiner.png")
  Lobby.reset()
  U.wait(4)
  finish()
end

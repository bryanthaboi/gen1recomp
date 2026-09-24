local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local TRADE_CENTER = "FR_TRADE_CENTER"
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F

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
    print("PASS g3link_direct_corner")
    love.event.quit(0)
  else
    print("FAIL g3link_direct_corner failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local RomText = require("src.core.game3.rom_text")
  local Link = require("src.core.game3.link")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  Party.giveMon(session, 25, 12)
  Party.giveMon(session, 1, 10)

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds, frames)
    local t0, n = now(), 0
    while not cond() do
      relay:pump()
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  local function pageHas(text)
    local page = Message.isOpen() and Message.currentPage() or ""
    return page:find(text, 1, true) ~= nil
  end
  local waitText = RomText.plain("CableClub_Text_PleaseWaitBCancel"):match("^[^\n]+")
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or (Message.isOpen() and not pageHas(waitText)) then
        U.tap(game, "a")
      end
      wait(6)
    end
    return cond()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")

  Map.load(nil, game, CENTER_2F, { x = 10, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(10, 4, "up")
  wait(12)
  U.tap(game, "a")
  local queued = drive(function() return relay.queue["a0000001"] ~= nil end, 25)
  print("[driver] queue=" .. tostring(relay.queue["a0000001"] and relay.queue["a0000001"].activity))
  if not result(queued, "TRADE CENTER > JOIN queues AUTO at the Direct Corner") then
    U.shot(game, DIR .. "/g3link_direct_failed.png")
    return finish()
  end
  local q = relay.queue["a0000001"]
  result(q.activity == "trade" and q.auto == true, "an AUTO trade queue")
  result(type(q.preview) == "table" and q.preview[1] == 25, "with the party preview")
  result(waitFor(function() return pageHas(waitText) end, 3, 60), "the cart's wait box is up")
  wait(20)
  U.shot(game, DIR .. "/g3link_direct_wait.png")

  U.tap(game, "b")
  result(waitFor(function() return relay.queue["a0000001"] == nil end, 3, 60), "B leaves the queue")
  local Direct = require("src.ui.game3.link_menu").Direct
  local back = drive(function() return Choice.active or (Direct.isOpen() and Direct.view == "modes") end, 8)
  print("[driver] after B: result=" .. tostring(getVar(0x800D)) .. " msg=" .. tostring(Message.isOpen()
    and Message.currentPage()) .. " running=" .. tostring(Space.vm and Space.vm:isRunning()))
  if not back then U.shot(game, DIR .. "/g3link_direct_after_b.png") end
  result(back, "and returns to the JOIN / LEAD menu")
  wait(10)
  U.shot(game, DIR .. "/g3link_direct_join_or_lead.png")
  U.tap(game, "a")
  result(waitFor(function() return relay.queue["a0000001"] ~= nil end, 5, 120), "JOIN queues again")

  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  relay:handle(blue, { type = "direct_queue", activity = "trade", ruleset = "g3_link", auto = true,
    profile = live, avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = "leafgreen" },
    preview = { 4 } })
  result(waitFor(function() return Link.link ~= nil end, 5, 120), "AUTO pairs and the link attaches")
  result(Link.link and Link.link.seat == 0, "the first in the queue sits at seat 0")
  result(Link.link and Link.link._transport.relay == true, "over the relay transport")
  local directed = RomText.plain("CableClub_Text_DirectYouToYourRoom")
  result(waitFor(function() return pageHas(directed) end, 5, 300), "the attendant directs the player to the room")
  waitFor(function() return not Message.isTyping() end, 3, 300)
  U.still(game, DIR .. "/g3link_direct_to_room.png")

  local hello = {}
  for k, v in pairs(Link.link.myHello) do hello[k] = v end
  hello.name = "BLUE"
  hello.game3 = { cacheVersion = Link.link.myHello.game3.cacheVersion,
    nativeVersion = Link.link.myHello.game3.nativeVersion, linkType = Link.link.linkType,
    trainerId = 0x2222, gender = 0, seat = 1 }
  relay:handle(blue, { type = "room_msg", seq = 1, msg = hello })

  local warped = waitFor(function() return Space.mapId == TRADE_CENTER end, 15, 600)
  print("[driver] map=" .. tostring(Space.mapId))
  if not result(warped, "the player walks through the door into the Trade Center") then
    U.shot(game, DIR .. "/g3link_direct_no_warp.png")
    return finish()
  end
  result(getVar(VAR_CABLE_CLUB_STATE) == Link.USING.TRADE_CENTER, "VAR_CABLE_CLUB_STATE = USING_TRADE_CENTER")
  result(session.dynamicWarp and session.dynamicWarp.map == CENTER_2F, "the return warp is the 2F")
  result(waitFor(function() return Link.link and Link.link:isReady() end, 5, 120), "the Game3 link handshake completed")
  wait(60)
  U.shot(game, DIR .. "/g3link_direct_trade_center.png")

  local room = Client.room()
  result(room ~= nil and room.origin == "direct" and room.stage == "battling", "a direct-origin relay room")
  Link.closeLink("done")
  wait(4)
  result(Client.room() == nil, "closing the link leaves the relay room")
  finish()
end

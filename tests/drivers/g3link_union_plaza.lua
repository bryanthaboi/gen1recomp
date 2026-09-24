local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local UNION_ROOM = "FR_UNION_ROOM"
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/metatile_behaviors.h:104
local MB_CABLE_CLUB_WIRELESS_MONITOR = 0x8D

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
    print("PASS g3link_union_plaza")
    love.event.quit(0)
  else
    print("FAIL g3link_union_plaza failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Chat = require("src.core.game3.link.chat")
  local LinkMenu = require("src.ui.game3.link_menu")
  local Status = require("src.core.game3.link.status")
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
  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Message.isOpen() or Choice.active
      or SaveMenu.isOpen()
  end
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
      wait(6)
    end
    return cond()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  local function peer(id, name, trainerId, gender, version)
    local s = relay:seat(id, name)
    relay:handle(s, { type = "lobby_hello", protocol = 3, name = name, profiles = { live },
      presence = { where = "launcher", status = "idle", version = version } })
    s.avatar = { name = name, trainerId = trainerId, gender = gender, version = version }
    return s
  end

  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5, 120), "the Client is online on the relay")
  result(Link.adapterConnected(), "the adapter reads connected")

  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  wait(60)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(6, 4, "up")
  wait(12)
  U.tap(game, "a")
  local entered = drive(function() return Space.mapId == UNION_ROOM and Union.state == "main" end, 25)
  print("[driver] map=" .. tostring(Space.mapId) .. " union=" .. tostring(Union.state))
  if not result(entered, "the attendant walks the player into the Union Room") then
    U.shot(game, DIR .. "/g3link_union_enter_failed.png")
    return finish()
  end
  result(Union.relay, "the Union Room runs over the relay")
  result(waitFor(function() return Client.plaza() ~= nil end, 5, 60), "the player is in the union plaza")
  me.presence.where = "union"

  local blue = peer("b0000002", "BLUE", 0x2222, 0, "leafgreen")
  local leaf = peer("c0000003", "LEAF", 0x3131, 1, "firered")
  relay:handle(blue, { type = "plaza_join", kind = "union", profile = live, avatar = blue.avatar })
  relay:handle(leaf, { type = "plaza_join", kind = "union", profile = live, avatar = leaf.avatar })
  result(waitFor(function() return Union.playerCount() == 2 end, 10, Union.REFRESH_FRAMES + 30),
    "both plaza members appear as union room avatars")
  wait(60)
  U.shot(game, DIR .. "/g3link_union_plaza_avatars.png")

  relay:handle(blue, { type = "invite", to = "a0000001", activity = "chat", detail = {}, profile = live })
  result(waitFor(function() return Union.state == "player_contacted_you" or Union.state == "handle_activity_request" end,
    5, 120), "BLUE's invite rings the player")
  waitFor(function()
    if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
      U.tap(game, "a")
    end
    return Choice.active
  end, 8, 600)
  wait(10)
  U.shot(game, DIR .. "/g3link_union_invite_prompt.png")
  U.tap(game, "a")
  local seated = waitFor(function() return Chat.isActive() end, 8, 400)
  if not result(seated, "accepting starts the chat in the private room") then return finish() end
  local room = Client.room()
  result(room ~= nil and room.intent == "chat" and room.stage == "battling", "a chat room born battling")
  relay:handle(blue, { type = "room_msg", seq = 1, msg = { type = "game3_union_hello", name = "BLUE",
    gender = 0, trainerId = 0x2222, activity = 0x45 } })
  relay:handle(blue, { type = "room_msg", seq = 2, msg = { type = Chat.MSG.LINE, name = "BLUE", text = "HELLO RED" } })
  result(waitFor(function() return #Chat.lines > 1 end, 5, 60), "BLUE's line arrives over the relay")
  wait(30)
  U.shot(game, DIR .. "/g3link_union_chat.png")
  Chat.stop("left")
  result(waitFor(function() return Union.state == "main" and Link.link == nil end, 5, 200),
    "leaving the chat ends it")
  result(Client.room() == nil, "and leaves the private room")

  Map.load(nil, game, CENTER_2F, { x = 7, y = 5, facing = "down" })
  wait(90)
  result(Union.state == "off", "leaving the Union Room stops it")
  result(Client.plaza() == nil, "and leaves the plaza")

  local mx, my
  for y = 0, 40 do
    for x = 0, 40 do
      if not mx and Collision.behavior(x, y) == MB_CABLE_CLUB_WIRELESS_MONITOR then mx, my = x, y end
    end
  end
  if not result(mx ~= nil, "the 2F has a wireless monitor") then return finish() end
  place(mx, my + 1, "up")
  wait(20)
  U.tap(game, "a")
  result(waitFor(function() return LinkMenu.isOpen() end, 5, 400), "the monitor opens over the relay")
  waitFor(function()
    relay:tick()
    return Client.plazaCounts() ~= nil
  end, 5, 60)
  for _ = 1, LinkMenu.ROWS_FRAMES + 5 do wait(1) end
  local rows = LinkMenu.rows
  print("[driver] rows trade=" .. tostring(rows[1] and rows[1].count) .. " battle=" .. tostring(rows[2] and rows[2].count)
    .. " union=" .. tostring(rows[3] and rows[3].count) .. " total=" .. tostring(rows[4] and rows[4].count))
  result(rows[Status.GROUPTYPE.UNION] and rows[Status.GROUPTYPE.UNION].count == 2,
    "UNION ROOM counts the two plaza members")
  result(rows[Status.GROUPTYPE.TOTAL] and rows[Status.GROUPTYPE.TOTAL].count == 2, "TOTAL = trade + battle + union")
  result(relay.wireless["a0000001"] == true, "the monitor subscribed to wireless counts")
  U.shot(game, DIR .. "/g3link_wireless_monitor_counts.png")
  U.tap(game, "a")
  result(waitFor(function() return not LinkMenu.isOpen() end, 5, 120), "A closes the monitor")
  wait(2)
  result(relay.wireless["a0000001"] == nil, "and unsubscribes")
  drive(function() return not busy() end, 8)
  finish()
end

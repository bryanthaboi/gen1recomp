local U = require("tests.drivers.util")

local SEAT = tonumber(os.getenv("G3TRADE_SEAT") or "0") or 0
local ROOMFILE = os.getenv("G3TRADE_ROOMFILE")
  or ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/g3trade_room.txt")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/gen3trade"
local TAG = "g3trade_seat" .. SEAT
local TRADE_CENTER = "FR_TRADE_CENTER"
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
local MACHOKE, MACHAMP, BULBASAUR, SQUIRTLE, PIKACHU = 67, 68, 1, 7, 25

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. TAG .. " " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function now()
  return love.timer.getTime()
end

return function(game)
  print("PASS " .. TAG .. " driver_started")
  local Link, Client

  local function finish()
    if Link then pcall(Link.closeLink, "driver_done") end
    if Client then pcall(Client.disconnect) end
    if failures == 0 then
      print("PASS " .. TAG .. " relay_trade")
      love.event.quit(0)
    else
      print("FAIL " .. TAG .. " relay_trade failures=" .. failures)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = SEAT == 0 and "RED" or "LEAF" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local LT = require("src.core.game3.link.trade")
  local TradeScene = require("src.core.game3.trade_scene")
  local Menu = require("src.ui.game3.link_trade_menu")
  local Game3Link = require("src.link.Game3Link")
  local RelayTransport = require("src.core.game3.link.relay_transport")
  local ArenaData = require("src.online.ArenaData")
  Link = require("src.core.game3.link")
  Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local g3 = Runtime._game or game

  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_SYS_POKEDEX_GET, true)
  session.name = SEAT == 0 and "RED" or "LEAF"
  session.trainerId = SEAT == 0 and 0x1234 or 0x2222
  session.party = {}
  if SEAT == 0 then
    Party.giveMon(session, MACHOKE, 30)
    Party.giveMon(session, BULBASAUR, 10)
  else
    Party.giveMon(session, SQUIRTLE, 11)
    Party.giveMon(session, PIKACHU, 14)
  end
  local expectFirst = SEAT == 0 and SQUIRTLE or MACHAMP

  local saves, savedLead = 0, nil
  local realSave = g3.saveGame
  g3.saveGame = function(self, ...)
    saves = saves + 1
    savedLead = session.party[1] and session.party[1].species
    if realSave then return realSave(self, ...) end
  end

  local function waitUntil(pred, seconds)
    local deadline = now() + (seconds or 10)
    while not pred() do
      if now() > deadline then return false end
      U.wait(1)
    end
    return true
  end

  local profile, why = ArenaData.liveProfile3(g3, "g3_link")
  if not result(profile ~= nil, "the running game has a live Gen 3 profile (" .. tostring(why) .. ")") then
    return finish()
  end
  local okC, errC = Client.connect({ name = session.name, profiles = { profile },
    presence = { where = "game", status = "busy" } })
  result(okC, "Client.connect to " .. tostring(os.getenv("POKEPORT_RELAY_ADDR")) .. " " .. tostring(errC))
  if not result(waitUntil(function() return Client.state() == "online" end, 10), "online on the relay") then
    return finish()
  end

  if SEAT == 0 then
    os.remove(ROOMFILE)
    Client.createRoom({ intent = "trade", profile = profile, seats = 2 })
    if not result(waitUntil(function() return Client.room() ~= nil end, 10), "seat 0 opened a trade room") then
      return finish()
    end
    local fh = io.open(ROOMFILE, "w")
    if fh then
      fh:write(tostring(Client.room().room))
      fh:close()
    end
  else
    local roomId
    waitUntil(function()
      local fh = io.open(ROOMFILE, "r")
      if fh then
        roomId = fh:read("*l")
        fh:close()
      end
      return roomId ~= nil and roomId ~= ""
    end, 15)
    if not result(roomId ~= nil, "seat 1 found the room id") then return finish() end
    Client.joinRoom(roomId, "player", profile)
  end

  local paired = waitUntil(function()
    local room = Client.room()
    return room and Client.seat() ~= nil and #(room.players or {}) == 2 and room.match ~= nil
  end, 15)
  if not result(paired, "both seats are in the room and the match started") then return finish() end
  result(Client.seat() == SEAT, "this process holds seat " .. SEAT)

  local transport = RelayTransport.new(Client.roomSession())
  local live = Game3Link.attach(transport, {
    seat = Client.seat(), seats = 2, game = g3, linkType = Game3Link.LINKTYPE.TRADE,
  })
  Link.attach(live)
  if not result(waitUntil(function() return live:isReady() end, 10), "the Game3Link handshake is full") then
    return finish()
  end

  -- pokefirered/data/maps/TradeCenter/map.json:1 TradeCenter_EventScript_Chair0 / Chair1
  Map.load(nil, g3, TRADE_CENTER, { x = SEAT == 0 and 4 or 7, y = 5, facing = SEAT == 0 and "right" or "left" })
  Player.cellX, Player.cellY = SEAT == 0 and 4 or 7, 5
  Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
  Player.targetX, Player.targetY = Player.cellX, Player.cellY
  U.wait(60)
  -- pokefirered/src/cable_club.c:958
  LT.startMenu()
  if not result(waitUntil(function() return Menu.isOpen() and Menu.cb == "main" and Menu.fade == 0 end, 15),
      "the trade menu is up with the other party on it") then
    return finish()
  end
  result(#LT.peerParty == 2, "the other seat's two mons arrived unpacked")
  U.wait(10)
  U.still(game, DIR .. "/" .. TAG .. "_trade_menu.png")

  U.tap(game, "a")
  U.wait(4)
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not result(waitUntil(function() return Menu.cb == "confirm_prompt" and Menu.confirming end, 20),
      "both offered their lead and IS THIS TRADE OKAY? came up") then
    return finish()
  end
  U.wait(4)
  U.still(game, DIR .. "/" .. TAG .. "_confirm.png")
  if SEAT == 1 then
    local realConfirm, holdUntil = LT.tryConfirm, nil
    LT.tryConfirm = function(...)
      holdUntil = holdUntil or (now() + 3)
      if now() < holdUntil then return false end
      LT.tryConfirm = realConfirm
      return realConfirm(...)
    end
  end
  U.tap(game, "a")

  result(waitUntil(function() return LT.state == "commit_wait" or LT._committed end, 10),
    "the confirm went to the relay")
  result(saves == 0, "nothing was written before trade_commit")
  print("INFO " .. TAG .. " digest=" .. tostring(LT._digest))
  if SEAT == 0 then
    U.wait(10)
    if result(LT.state == "commit_wait", "seat 0 waits on Communication standby for the other confirm") then
      U.still(game, DIR .. "/" .. TAG .. "_commit_wait.png")
    end
  end
  if not result(waitUntil(function() return TradeScene.isOpen() end, 15),
      "trade_commit arrived and the trade scene started") then
    return finish()
  end
  if result(waitUntil(function() return TradeScene.phase() == "bye_bye" end, 15),
      "the scene put the outgoing mon on screen") then
    U.wait(10)
    U.still(game, DIR .. "/" .. TAG .. "_scene.png")
  end

  local done = waitUntil(function()
    if not TradeScene.isOpen() and LT.completed >= 1 then return true end
    local Evo = package.loaded["src.ui.game3.evolution_scene"]
    local Message = package.loaded["src.ui.game3.message"]
    if (Evo and Evo.isOpen and Evo.isOpen()) or (Message and Message.isOpen and Message.isOpen()) then
      table.insert(game.input.pressQueue, "a")
    end
    return false
  end, 25)
  if not result(done, "the scene, evolution and save ran to the end") then return finish() end
  result(saves == 1, "the save was written exactly once (" .. saves .. ")")
  result(savedLead == expectFirst, "the save holds the received mon (" .. tostring(savedLead) .. ")")
  result(session.party[1] and session.party[1].species == expectFirst,
    "the party lead is now species " .. tostring(expectFirst))
  result(LT._saveFailed == false, "the post-trade save reported success")

  if result(waitUntil(function() return Menu.isOpen() and Menu.cb == "main" and Menu.fade == 0 end, 15),
      "the Trade Center returned to the trade menu with the new party") then
    U.wait(10)
    U.still(game, DIR .. "/" .. TAG .. "_after_save_party.png")
  end
  return finish()
end

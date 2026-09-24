local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/minigames"

local CORNER = "FR_TWO_ISLAND_JOYFUL_GAME_CORNER"
-- pokefirered/include/constants/flags.h:790
local FLAG_GOT_MOON_STONE_FROM_JOYFUL_GAME_CORNER = 0x2FB
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/vars.h:173
local VAR_MAP_SCENE_TWO_ISLAND_JOYFUL_GAME_CORNER = 0x4079
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
local CHARMANDER, DODRIO = 4, 85

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
    print("PASS g3mg_common_group")
    love.event.quit(0)
  else
    print("FAIL g3mg_common_group failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

local Stub = { MIN = 2, MAX = 5, END_FRAME = 420 }
Stub.__index = Stub

function Stub.loadArt() return {} end

function Stub.new(ctx)
  local sim = setmetatable({ ctx = ctx, f = 0, scores = { 0, 0, 0, 0, 0 },
    last = { 0, 0, 0, 0, 0 }, presses = 0, leader = ctx.leader }, Stub)
  return sim
end

function Stub:leaderStep(inputs, present)
  for s = 0, 4 do
    local i = inputs[s + 1]
    if present[s + 1] and type(i) == "number" and i > self.last[s + 1] then
      self.scores[s + 1] = self.scores[s + 1] + (i - self.last[s + 1])
      self.last[s + 1] = i
    end
  end
  self.f = self.f + 1
end

function Stub:snapshot()
  return { f = self.f, sc = { unpack(self.scores) }, la = { unpack(self.last) } }
end

function Stub:applySnapshot(s)
  self.f = s.f
  for i = 1, 5 do
    self.scores[i] = s.sc[i] or 0
    self.last[i] = s.la[i] or 0
  end
end

function Stub:localInput(input)
  if input and input:wasPressed("a") then self.presses = self.presses + 1 end
  return self.presses
end

function Stub:predict(i) self.predicted = i end

function Stub:becomeLeader(last)
  if last then self:applySnapshot(last) end
  self.leader = true
end

function Stub:update() end

function Stub:draw()
  local FrlgFont = require("src.ui.game3.frlg_font")
  local y = 16
  for _, p in ipairs(self.ctx.players) do
    local mine = p.seat == self.ctx.seat
    FrlgFont.draw(string.format("%s %d", p.name or "?", self.scores[p.seat + 1] or 0), 24, y,
      { colors = mine and FrlgFont.COLOR.GREEN or FrlgFont.COLOR.WHITE })
    y = y + 16
  end
  FrlgFont.draw(string.format("%d", self.f), 200, 136, { colors = FrlgFont.COLOR.WHITE })
end

function Stub:finished() return self.f >= Stub.END_FRAME end

function Stub:results()
  local results, powder = {}, {}
  for _, p in ipairs(self.ctx.players) do
    local sc = self.scores[p.seat + 1]
    results[#results + 1] = { seat = p.seat, score = sc, stats = { presses = sc } }
    powder[#powder + 1] = { seat = p.seat, amount = sc }
  end
  return { results = results, powder = powder }
end

function Stub.applyResults(session, result, mySeat)
  local Records = require("src.ui.game3.minigame_records")
  for _, r in ipairs(result.results) do
    if r.seat == mySeat then Records.updatePokemonJump(session, r.score, r.score, 0) end
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
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Wire = require("src.link.Wire")
  local MG = require("src.core.game3.minigames.common")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Countdown = require("src.ui.game3.minigames.common_countdown")

  package.loaded[MG.GAMES.jump] = Stub

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.trainerId = 0x1234
  Party.giveMon(session, CHARMANDER, 12)
  Party.giveMon(session, DODRIO, 30)

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local peers = {}
  local function peerSession(s)
    local rs = { paired = true, closed = false, left = false, seq = 0, target = s.room }
    function rs:send(msg)
      self.seq = self.seq + 1
      relay:handle(s, { type = "room_msg", seq = self.seq, msg = msg })
    end
    function rs:poll()
      local out = {}
      for _, m in ipairs(s.transport.inbox) do
        if m.type == "room_msg" and type(m.msg) == "table" then
          local inner = Wire.sanitize(m.msg)
          if inner then
            if m.relay then
              inner.relay = true
              if type(inner.seat) ~= "number" then inner.seat = -1 end
            else
              inner.seat = m.seat
            end
            out[#out + 1] = inner
          end
        end
      end
      s.transport.inbox = {}
      return out
    end
    function rs:players()
      local room = relay.rooms[s.room or ""]
      return room and room.players or {}
    end
    function rs:close()
      self.left = true
      self.closed = true
      relay:handle(s, { type = "room_leave" })
    end
    return rs
  end
  local function startPeer(s, pressEvery)
    local room = relay.rooms[s.room or ""]
    local seat = relay:seatOf(room, s.id)
    local players = {}
    for _, p in ipairs(room.players) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0x2000 + p.seat, gender = 0 }
    end
    local input = { n = 0 }
    function input:wasPressed(b) return b == "a" and self.n % pressEvery == 0 end
    local m = MG.Match.new({ game = "jump", session = peerSession(s), seat = seat, seats = #players,
      players = players, seed = room.seed, partySlot = 0 },
      { module = Stub, partyMon = { species = CHARMANDER }, leader = room.leader,
        countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end })
    peers[#peers + 1] = { s = s, m = m, input = input, acc = 0, last = now() }
    return m
  end
  local function stepPeers()
    for _, p in ipairs(peers) do
      if not p.gone and not p.m:finished() then
        local t = now()
        p.acc = p.acc + (t - p.last)
        p.last = t
        local n = 0
        while p.acc >= MG.DT and n < 8 do
          p.acc = p.acc - MG.DT
          n = n + 1
          p.input.n = p.input.n + 1
          p.m:step(p.input)
        end
      end
    end
  end
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      stepPeers()
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds)
    local t0 = now()
    while not cond() do
      relay:pump()
      stepPeers()
      U.wait(1)
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5), "the Client is online on the relay")
  wait(20)
  print("[driver] lobby screens")
  Lobby.showPlayers({}, { mode = "leader", group = { min = 2, max = 5 }, activity = 9 })
  wait(12)
  U.shot(game, DIR .. "/g3mg_common_lobby_leader_alone.png")
  result(Lobby.modeText():find("1 player") ~= nil, "leader alone: 1 player needed")
  local WirelessIcon = require("src.ui.game3.wireless_icon")
  result(WirelessIcon.anim() == "3bars" and (WirelessIcon.frame() or 1) > 1,
    "the lobby shows the animating wireless icon (frame " .. tostring(WirelessIcon.frame()) .. ")")
  Lobby.showPlayers({ { name = "BLUE", trainerId = 0x2222 }, { name = "LEAF", trainerId = 0x3333, pending = true } },
    { mode = "leader", group = { min = 2, max = 5 }, activity = 9 })
  wait(12)
  U.shot(game, DIR .. "/g3mg_common_lobby_leader_3p.png")
  result(Lobby.canStart(), "leader with members: START allowed (AwaitingLinkPressStart)")
  Lobby.showPlayers({ { slot = 1, name = "BLUE", trainerId = 0x2222 }, { slot = 2, name = "LEAF", trainerId = 0x3333, started = true } },
    { mode = "group", capacity = { activity = 9, min = 2, max = 5 } })
  wait(12)
  U.shot(game, DIR .. "/g3mg_common_lobby_joiner.png")
  Lobby.reset()
  wait(2)


  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  local leaf = relay:seat("c0000003", "LEAF")
  relay:handle(leaf, { type = "lobby_hello", protocol = 3, name = "LEAF", profiles = { live } })
  relay:handle(blue, { type = "group_open", activity = "minigame_jump", profile = live,
    avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = "leafgreen" } })

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  Flags.setFlag(Space.store, ctx(), FLAG_GOT_MOON_STONE_FROM_JOYFUL_GAME_CORNER, true)
  Map.load(nil, game, CORNER, { x = 6, y = 3, facing = "up" })
  wait(60)
  setVar(VAR_MAP_SCENE_TWO_ISLAND_JOYFUL_GAME_CORNER, 4)
  Player.cellX, Player.cellY = 6, 3
  Player.px, Player.py = 6 * 16, 3 * 16
  Player.targetX, Player.targetY = 6, 3
  Player.facing = "up"
  session.x, session.y, session.facing = 6, 3, "up"
  wait(10)
  U.tap(game, "a")

  local picked = false
  local joined = false
  local t0 = now()
  while now() - t0 < 40 do
    relay:pump()
    stepPeers()
    if PartyMenu.isOpen() and not picked then
      wait(10)
      U.shot(game, DIR .. "/g3mg_common_choose_mon.png")
      picked = true
      U.tap(game, "a")
    elseif Lobby.isOpen() and Lobby.mode == "group" and #Lobby.players > 0 and not joined then
      wait(30)
      U.shot(game, DIR .. "/g3mg_common_group_list.png")
      result(not Message.isOpen() and Lobby.message() == Lobby.chooseText() and Lobby.chooseText() ~= "",
        "the group list owns the textbox: " .. Lobby.chooseText())
      joined = true
      U.tap(game, "a")
    elseif Choice.active or SaveMenu.isOpen() or (Message.isOpen() and Message.isWaiting and Message.isWaiting()) then
      U.tap(game, "a")
    end
    local g = relay.groups[blue.id]
    if g and #g.pending > 0 then
      for _, p in ipairs(g.pending) do
        relay:handle(blue, { type = "group_accept", from = p.id, ok = true })
      end
      if #g.members == 2 then
        relay:handle(leaf, { type = "group_join", leader = blue.id, profile = live,
          avatar = { name = "LEAF", trainerId = 0x3333, gender = 1, version = "firered" } })
      end
    end
    if g and #g.members == 3 then
      relay:handle(blue, { type = "group_start" })
    end
    if MG.isActive() then break end
    U.wait(2)
  end
  result(picked, "ChooseMonForWirelessMinigame opened the party menu")
  result(MG.partySlot == 0, "Charmander (slot 0) entered")
  result(joined, "the group list showed BLUE's group")
  if not result(MG.isActive(), "MG.arm launched the minigame on the script's waitstate") then
    U.shot(game, DIR .. "/g3mg_common_no_launch.png")
    return finish()
  end
  local room = Client.room()
  result(room and room.intent == "minigame" and room.origin == "group", "a group-origin minigame room")
  startPeer(blue, 5)
  startPeer(leaf, 9)
  local mine = MG.match()
  result(mine and mine.seat == 1, "RED sits at seat 1")
  result(mine and mine.leader == 0, "BLUE leads")

  result(waitFor(function() return mine.phase ~= "ready" end, 10), "every seat readied and BLUE started")
  result(#(mine.startPlayers or {}) == 3, "three players in game3_mg_start")
  result(waitFor(function() return mine.countdown and mine.countdown:digitShown() == 3 end, 5), "3")
  wait(10)
  U.shot(game, DIR .. "/g3mg_common_countdown_3.png")
  result(waitFor(function() return mine.countdown and mine.countdown.starts ~= nil end, 8), "START")
  wait(12)
  U.shot(game, DIR .. "/g3mg_common_countdown_start.png")
  result(waitFor(function() return mine.phase == "play" end, 6), "play")
  for _ = 1, 40 do
    U.tap(game, "a")
    wait(5)
  end
  result(waitFor(function() return (mine.sim.scores[2] or 0) > 0 end, 5),
    "RED's presses reach the leader and come back in states")

  local roomId = Client.room() and Client.room().room
  peers[1].gone = true
  relay:handle(blue, { type = "room_leave" })
  relay:migrateLeader(roomId)
  result(waitFor(function() return mine:isLeader() end, 3), "BLUE dropped: leadership migrated to RED")
  result(peers[2].m.leader == 1, "LEAF follows RED")
  for _ = 1, 20 do
    U.tap(game, "a")
    wait(5)
  end
  U.shot(game, DIR .. "/g3mg_common_after_migration.png")
  result(waitFor(function() return mine.phase == "results" or mine.phase == "done" or not MG.isActive() end, 15),
    "RED finished the game as leader")
  local res = mine.result
  waitFor(function() return peers[2].m.result ~= nil or peers[2].m:finished() end, 5)
  print("[driver] LEAF phase=" .. tostring(peers[2].m.phase) .. " why=" .. tostring(peers[2].m.why))
  result(res ~= nil and peers[2].m.result ~= nil
    and require("src.link.Json").encode(res.results) == require("src.link.Json").encode(peers[2].m.result.results),
    "RED and LEAF agree on the results")
  local myScore = 0
  for _, r in ipairs(res and res.results or {}) do if r.seat == 1 then myScore = r.score end end
  result(myScore > 0, "RED scored " .. myScore)
  result((session.berryPowder or 0) == myScore, "Berry Powder = RED's share (" .. tostring(session.berryPowder) .. ")")
  result(session.pokemonJumpRecords and session.pokemonJumpRecords.bestJumpScore == myScore, "record written")

  result(waitFor(function() return not MG.isActive() end, 8), "the minigame exits")
  result(waitFor(function() return Space.mapId == CORNER and getVar(VAR_CABLE_CLUB_STATE) == 0 end, 10),
    "warped back and ExitMinigameRoom cleared VAR_CABLE_CLUB_STATE")
  local Fade = require("src.ui.game3.fade")
  waitFor(function() return not Fade.isActive() and (tonumber(Fade.t) or 0) == 0 and not Space.vm:isRunning() end, 10)
  print(string.format("[driver] after exit fade.t=%s active=%s map=%s pos=%s,%s visible=%s stack=%s",
    tostring(Fade.t), tostring(Fade.active), tostring(Space.mapId), tostring(Player.cellX), tostring(Player.cellY),
    tostring(Player.visible), tostring(require("src.ui.game3.stack").depth())))
  wait(30)
  U.shot(game, DIR .. "/g3mg_common_returned.png")
  result(Client.room() == nil, "RED left the relay room")
  finish()
end

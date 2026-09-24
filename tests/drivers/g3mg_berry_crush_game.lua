local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/09-23-26-03-gen3online/shots/minigames"
local MIGRATE = os.getenv("G3MG_CRUSH_MIGRATE") ~= "0"

-- pokefirered/include/constants/items.h:137
local CHERI, PERSIM, LUM, SITRUS = 133, 140, 141, 142

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
    print("PASS g3mg_berry_crush_game")
    love.event.quit(0)
  else
    print("FAIL g3mg_berry_crush_game failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Link = require("src.core.game3.link")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Wire = require("src.link.Wire")
  local MG = require("src.core.game3.minigames.common")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  local G = require("src.core.game3.minigames.berry_crush")
  local Sim = G.Sim
  local Pouch = require("src.ui.game3.minigames.berry_crush.pouch")
  local songs = {}
  local realPlaySong = G.hooks.playSong
  G.hooks.playSong = function(id)
    songs[#songs + 1] = id
    return realPlaySong(id)
  end
  local BerryPouch = require("src.ui.game3.berry_pouch")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.trainerId = 0x1234
  Bag.add(session.bag, CHERI, 2)
  Bag.add(session.bag, PERSIM, 1)
  Bag.add(session.bag, LUM, 3)
  Bag.add(session.bag, SITRUS, 1)
  session.berryPowder = 120
  local lumBefore = Bag.get(session.bag, LUM)

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

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

  local function peerModule(bagSession)
    local M = setmetatable({}, { __index = G })
    M.hooks = setmetatable({
      session = function() return bagSession end,
      playSe = function() end,
      playSong = function() end,
      pauseMusic = function() end,
      resumeMusic = function() end,
      save = function() end,
      tick = function() end,
      newCountdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
      pickBerry = function(sim, done)
        local list = Bag.listPocket(bagSession.bag, "BERRY_POUCH")
        done(list[1] and tonumber(list[1].id) or nil)
      end,
    }, { __index = G.hooks })
    M.new = function(ctx) return Sim.new(M, ctx) end
    return M
  end

  local function startPeer(s, item, pressEvery)
    local room = relay.rooms[s.room or ""]
    local seat = relay:seatOf(room, s.id)
    local players = {}
    for _, p in ipairs(room.players) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0x2000 + p.seat, gender = 0 }
    end
    local bagSession = { bag = Bag.new(), berryPowder = 0 }
    Bag.add(bagSession.bag, item, 2)
    local M = peerModule(bagSession)
    local input = { n = 0 }
    function input:wasPressed(b) return b == "a" and self.n % pressEvery == 0 end
    function input:isDown(b) return b == "a" and self.n % pressEvery < 2 end
    local art = assert(G.loadArt())
    local m = MG.Match.new({ game = "crush", session = peerSession(s), seat = seat, seats = #players,
      players = players, seed = room.seed },
      { module = M, art = art, leader = room.leader,
        countdown = function() return { step = function() return false end, draw = function() end } end,
        onResult = function(msg, match) MG.applyResults(bagSession, msg, match.seat, M) end })
    peers[#peers + 1] = { s = s, m = m, input = input, acc = 0, last = now(), bag = bagSession }
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

  local function pause(seconds)
    local t0 = now()
    waitFor(function() return now() - t0 >= seconds end, seconds + 1)
  end

  local function tapA()
    U.tap(game, "a")
    relay:pump()
    stepPeers()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5), "online on the relay")
  wait(20)

  print("[driver] lobby")
  Lobby.showPlayers({ { name = "BLUE", trainerId = 0x2222 }, { name = "LEAF", trainerId = 0x3333 } },
    { mode = "leader", group = { min = 2, max = 5 }, activity = 10 })
  wait(12)
  U.shot(game, DIR .. "/g3mg_berry_crush_lobby.png")
  result(Lobby.canStart(), "Berry Crush lobby: 3 players, START allowed")
  Lobby.reset()
  wait(2)

  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  local leaf = relay:seat("c0000003", "LEAF")
  relay:handle(leaf, { type = "lobby_hello", protocol = 3, name = "LEAF", profiles = { live } })
  relay:handle(blue, { type = "group_open", activity = "minigame_crush", profile = live,
    avatar = { name = "BLUE", trainerId = 0x2222, gender = 0, version = "leafgreen" } })
  wait(4)
  Client.joinGroup(blue.id, live, { name = "RED", trainerId = 0x1234, gender = 0, version = "firered" })
  local started = waitFor(function()
    local g = relay.groups[blue.id]
    if g then
      for _, p in ipairs(g.pending) do relay:handle(blue, { type = "group_accept", from = p.id, ok = true }) end
      if #g.members == 2 and not g.leafAsked then
        g.leafAsked = true
        relay:handle(leaf, { type = "group_join", leader = blue.id, profile = live,
          avatar = { name = "LEAF", trainerId = 0x3333, gender = 1, version = "firered" } })
      end
      if #g.members == 3 then relay:handle(blue, { type = "group_start" }) end
    end
    local room = Client.room()
    return room ~= nil and room.intent == "minigame"
  end, 10)
  if not result(started, "BLUE's Berry Crush group started a minigame room") then return finish() end

  local rs = Client.roomSession()
  local room = Client.room()
  local players = {}
  for _, p in ipairs(room.players or {}) do
    players[#players + 1] = { id = p.id, name = p.name, seat = tonumber(p.seat), trainerId = 0, gender = 0 }
  end
  table.sort(players, function(a, b) return a.seat < b.seat end)
  local exited
  MG.launch({ game = "crush", session = rs, seat = rs:seat(), seats = #players, players = players,
    seed = rs.seed and rs:seed() or room.seed, returnToMap = false,
    onExit = function(r) exited = r end })
  startPeer(blue, PERSIM, 5)
  startPeer(leaf, SITRUS, 7)
  local mine = MG.match()
  if not result(mine ~= nil, "MG launched Berry Crush") then return finish() end
  result(mine.seat == 1 and mine.leader == 0, "RED at seat 1, BLUE leads")
  local function sim() return mine.sim end
  local function stage() return sim() and sim().stage end

  result(waitFor(function() return stage() == "ask" and sim().printer and sim().printer.prompt end, 15),
    "Are you ready to BERRY-CRUSH?")
  pause(0.3)
  U.still(game, DIR .. "/g3mg_berry_crush_are_you_ready.png")
  result(stage() == "ask" and not Pouch.isOpen(), "the trailing \\p holds the message until A")
  tapA()
  result(waitFor(function() return Pouch.isOpen() end, 10), "the Berry Pouch opens")
  pause(0.4)
  U.still(game, DIR .. "/g3mg_berry_crush_pouch.png")
  U.tap(game, "down")
  pause(0.1)
  U.tap(game, "down")
  pause(0.1)
  result(BerryPouch.cursor == 3, "cursor on the third berry (LUM)")
  tapA()
  result(waitFor(function() return not Pouch.isOpen() end, 5), "berry chosen, pouch closes")
  result(Bag.get(session.bag, LUM) == lumBefore - 1, "one LUM BERRY left the bag")
  result(waitFor(function() return stage() == "waitmsg" and sim().printer and sim().printer:printed() end, 10),
    "Please wait while each member chooses a BERRY.")
  U.still(game, DIR .. "/g3mg_berry_crush_wait_others.png")
  result(waitFor(function()
    local s = sim()
    local b = s and s.berries and s.berries[2]
    return s.stage == "drop" and b and not b.destroyed and b.y + b.y2 > 40
  end, 15), "berries drop into the crusher")
  U.still(game, DIR .. "/g3mg_berry_crush_drop.png")
  result(waitFor(function() return stage() == "lid" and sim().depth > -60 end, 15), "the lid drops")
  U.still(game, DIR .. "/g3mg_berry_crush_lid.png")
  result(waitFor(function()
    local c = sim() and sim().countdown
    return c and c.digitShown and c:digitShown() == 2 and c.digit.state == 1 and c.digit.t > 10
  end, 15), "countdown 2")
  U.still(game, DIR .. "/g3mg_berry_crush_countdown.png")
  result(waitFor(function()
    local c = sim() and sim().countdown
    return c and c.starts ~= nil and c.starts[1].state >= 2
  end, 10), "countdown START")
  U.still(game, DIR .. "/g3mg_berry_crush_countdown_start.png")
  result(waitFor(function() return stage() == "play" end, 10), "play")

  local shotMid, migrated = false, false
  local t0 = now()
  while now() - t0 < 60 do
    tapA()
    pause(1 / 12)
    local s = sim()
    if not s then break end
    if not shotMid and s.A.tp > 25 then
      local sparkles = 0
      for _, sp in ipairs(s.sparkles) do if not sp.invisible then sparkles = sparkles + 1 end end
      if sparkles > 2 then
        U.still(game, DIR .. "/g3mg_berry_crush_midgame.png")
        shotMid = true
        result(s.presses > 0 and s.A.pl[2].np > 0, "RED's presses reach the leader")
      end
    end
    if MIGRATE and shotMid and not migrated and s.A.tp > 60 then
      migrated = true
      local roomId = Client.room() and Client.room().room
      peers[1].gone = true
      relay:handle(blue, { type = "room_leave" })
      relay:migrateLeader(roomId)
      result(waitFor(function() return mine:isLeader() end, 4), "BLUE dropped: RED leads")
      result(peers[2].m.leader == 1, "LEAF follows RED")
      result(waitFor(function() return mine.sim.A.gone[1] == true end, 3), "BLUE is gone on RED's crusher")
      result(waitFor(function() return peers[2].m.sim.A.gone[1] == true end, 3), "LEAF sees BLUE gone")
      pause(0.3)
      U.still(game, DIR .. "/g3mg_berry_crush_migrated.png")
    end
    if s.stage ~= "play" and s.stage ~= "waitplay" then break end
  end
  result(shotMid, "mid-game sparkles and impacts")
  local s = sim()
  result(s.stage == "finish" or s.stage == "tabwait" or s.stage == "results", "the crusher reached the bottom (" .. tostring(s.stage) .. ")")
  waitFor(function() return s.stage == "finish" and s.sub >= 2 end, 3)
  U.still(game, DIR .. "/g3mg_berry_crush_finish.png")

  local pages = { "presses", "random", "crushing" }
  for i, name in ipairs(pages) do
    local ok = waitFor(function() return s.stage == "results" and s.page == i - 1 and s.pageOpen and s.sub == 2 end, 15)
    result(ok, "results page " .. name)
    pause(0.6)
    U.still(game, DIR .. "/g3mg_berry_crush_results_" .. name .. ".png")
    tapA()
    waitFor(function() return not s.pageOpen or s.page ~= i - 1 end, 3)
  end
  result(waitFor(function() return s.stage == "powder" and s.printer and s.printer.prompt end, 10),
    "You ended up with ... units of silky-smooth BERRY POWDER.")
  U.still(game, DIR .. "/g3mg_berry_crush_powder.png")
  local heardLevelUp = false
  for _, id in ipairs(songs) do if id == 257 then heardLevelUp = true end end
  result(heardLevelUp, "{PLAY_BGM MUS_LEVEL_UP} in the powder text plays the jingle")
  tapA()
  result(waitFor(function() return s.stage == "powder" and s.printer and s.printer.prompt and s.printer:printed() end, 10),
    "Your total amount of BERRY POWDER waits for A")
  pause(0.3)
  U.still(game, DIR .. "/g3mg_berry_crush_powder_total.png")
  tapA()
  result(waitFor(function()
    return (s.stage == "standby" or s.stage == "savewait") and s.printer and s.printer:printed()
  end, 10), "Communication standby")
  U.still(game, DIR .. "/g3mg_berry_crush_standby.png")
  result(waitFor(function() return s.stage == "saving" and s.sf > 20 end, 20), "SAVING... DON'T TURN OFF THE POWER.")
  U.still(game, DIR .. "/g3mg_berry_crush_saving.png")
  result(waitFor(function() return s.stage == "yesno" and s.sf > 10 end, 10), "Want to play BERRY CRUSH again?")
  U.still(game, DIR .. "/g3mg_berry_crush_play_again.png")
  U.tap(game, "down")
  pause(0.1)
  result(s.yesNo == 1, "cursor on NO")
  tapA()
  result(waitFor(function() return s.stage == "stop" and s.sub == 2 end, 20),
    "A member dropped out. The game will be canceled.")
  U.still(game, DIR .. "/g3mg_berry_crush_stopped.png")
  result(peers[2].m.sim.answer == Sim.ANSWER.YES, "LEAF wanted another round")

  local res = s.res
  result(res and not res.timeUp and res.powder > 0, "powder " .. tostring(res and res.powder))
  result(session.berryPowder == 120 + res.powder, "Berry Powder given (" .. tostring(session.berryPowder) .. ")")
  result(session.berryCrushPressingSpeeds and session.berryCrushPressingSpeeds[2] == res.speed,
    "3-player pressing speed record")
  result(peers[2].bag.berryPowder == res.powder, "LEAF got the same powder")
  waitFor(function() return peers[2].m.result ~= nil end, 5)
  local leafRes = peers[2].m.result
  result(leafRes ~= nil and mine.result ~= nil and MG.same(leafRes.results, mine.result.results),
    "RED and LEAF agree on game3_mg_result")
  local leafSim = peers[2].m.sim
  result(leafSim.res and leafSim.res.total == res.total and leafSim.res.powder == res.powder,
    "RED and LEAF agree on the crushing results")
  result(waitFor(function() return exited ~= nil end, 10), "the minigame exits (" .. tostring(exited) .. ")")
  result(exited == "done", "exit result done")
  wait(20)
  finish()
end

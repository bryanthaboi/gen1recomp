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
-- pokefirered/include/constants/species.h:89
local DODRIO = 85
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
    print("PASS g3mg_dodrio_berry_picking_play")
    love.event.quit(0)
  else
    print("FAIL g3mg_dodrio_berry_picking_play failures=" .. failures)
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
  local PartyMenu = require("src.ui.game3.party_menu")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Screen = require("src.ui.game3.union_room")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Wire = require("src.link.Wire")
  local MG = require("src.core.game3.minigames.common")
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  local G = require("src.core.game3.minigames.dodrio_berry_picking")
  local R = G.Rules

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.trainerId = 0x1234
  Party.giveMon(session, DODRIO, 30)
  Party.giveMon(session, CHARMANDER, 12)

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

  local function wantDir(sim, frame, seat, until_)
    if not sim or sim.rs or sim.view.gray >= R.NUM_STATUS_SQUARES then return nil end
    if frame > until_ or (frame + seat * 7) % 53 < 5 then return nil end
    local dirs = { [0] = "left", "up", "right" }
    for pick = 0, 2 do
      local col = R.headColumn(sim.T, sim.n, sim.me, pick)
      local f = sim.view.fall[col]
      if (f == 6 or f == 7) and sim.view.ids[col] ~= R.BERRY_MISSED then return dirs[pick] end
    end
    return nil
  end

  local function startPeer(s, playFrames)
    local room = relay.rooms[s.room or ""]
    local seat = relay:seatOf(room, s.id)
    local players = {}
    for _, p in ipairs(room.players) do
      players[#players + 1] = { id = p.id, name = p.name, seat = p.seat, trainerId = 0x2000 + p.seat, gender = p.seat % 2 }
    end
    local input = { frame = 0, want = nil }
    function input:wasPressed(b) return self.want == b end
    function input:isDown() return false end
    local m = MG.Match.new({ game = "pick", session = peerSession(s), seat = seat, seats = #players,
      players = players, seed = room.seed, partySlot = 0 },
      { module = G, partyMon = { species = DODRIO, personality = 0x5555 + seat, otId = 0x2000 + seat },
        leader = room.leader, me = { name = s.name, trainerId = 0x2000 + seat, gender = seat % 2 },
        countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end })
    peers[#peers + 1] = { s = s, m = m, input = input, acc = 0, last = now(), play = playFrames, seat = seat }
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
          p.input.frame = p.input.frame + 1
          local sim = p.m.sim
          if sim and sim.flow == "results" then
            p.input.want = (p.input.frame % 45 == 0) and "a" or nil
          elseif sim and sim.flow == "ask" and sim.rs and sim.rs.show == "ask" then
            p.input.want = (p.input.frame % 20 == 0) and "a" or nil
          else
            p.input.want = wantDir(sim, sim and sim.frame or 0, p.seat, p.play)
          end
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
  local function stillFor(seconds)
    local t = now()
    while now() - t < seconds do
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

  print("[driver] lobby screen")
  Lobby.showPlayers({ { name = "BLUE", trainerId = 0x2222 }, { name = "LEAF", trainerId = 0x3333 } },
    { mode = "leader", group = { min = 3, max = 5 }, activity = 11 })
  wait(12)
  U.shot(game, DIR .. "/g3mg_dodrio_lobby_leader_3p.png")
  result(Lobby.canStart(), "three players: the leader may start DODRIO BERRY-PICKING")
  Lobby.reset()
  wait(2)

  local blue = relay:seat("b0000002", "BLUE")
  relay:handle(blue, { type = "lobby_hello", protocol = 3, name = "BLUE", profiles = { live } })
  local leaf = relay:seat("c0000003", "LEAF")
  relay:handle(leaf, { type = "lobby_hello", protocol = 3, name = "LEAF", profiles = { live } })
  relay:handle(blue, { type = "group_open", activity = "minigame_pick", profile = live,
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

  local gameChosen, picked, joined = false, false, false
  local t0 = now()
  while now() - t0 < 40 do
    relay:pump()
    stepPeers()
    if PartyMenu.isOpen() and not picked then
      wait(10)
      U.shot(game, DIR .. "/g3mg_dodrio_choose_mon.png")
      picked = true
      U.tap(game, "a")
    elseif not joined and ((Screen.isOpen() and Screen.mode == "group" and #Screen.players > 0)
        or (Lobby.isOpen() and Lobby.mode == "group" and #Lobby.players > 0)) then
      wait(6)
      U.shot(game, DIR .. "/g3mg_dodrio_group_list.png")
      joined = true
      U.tap(game, "a")
    elseif Choice.active and not gameChosen then
      wait(4)
      U.tap(game, "down")
      wait(4)
      gameChosen = true
      U.tap(game, "a")
    elseif not gameChosen and Message.isOpen() and Message.isWaiting and Message.isWaiting() then
      U.tap(game, "a")
      waitFor(function() return Choice.active end, 3)
    elseif gameChosen and (Choice.active or SaveMenu.isOpen()
        or (Message.isOpen() and Message.isWaiting and Message.isWaiting())) then
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
  result(gameChosen, "DODRIO BERRY-PICKING chosen at the attendant")
  result(picked, "ChooseMonForWirelessMinigame opened the party menu")
  result(MG.partySlot == 0, "Dodrio (slot 0) entered")
  result(joined, "the group list showed BLUE's group")
  if not result(MG.isActive(), "MG.arm launched Dodrio Berry Picking on the script's waitstate") then
    U.shot(game, DIR .. "/g3mg_dodrio_no_launch.png")
    return finish()
  end
  local room = Client.room()
  result(room and room.intent == "minigame" and room.origin == "group", "a group-origin minigame room")
  startPeer(blue, 2400)
  startPeer(leaf, 2700)
  local mine = MG.match()
  result(mine and mine.seat == 1, "RED sits at seat 1")
  result(mine and mine.leader == 0, "BLUE leads")
  result(mine and mine.G == G, "the real Dodrio module is running")

  result(waitFor(function() return mine.phase ~= "ready" end, 10), "every seat readied and BLUE started")
  result(#(mine.startPlayers or {}) == 3, "three players in game3_mg_start")
  local sim = mine.sim
  if not result(sim ~= nil, "Dodrio sim created") then return finish() end
  local shot = {}
  local okIntro = waitFor(function()
    local cd = sim.countdown or mine.countdown
    if not shot.names and sim.intro.names and sim.intro.namesState >= 20 then
      shot.names = U.still(game, DIR .. "/g3mg_dodrio_intro_names.png")
    end
    if not shot.three and cd and cd:digitShown() == 3 and cd.frames >= 10 then
      shot.three = U.still(game, DIR .. "/g3mg_dodrio_countdown_3.png")
    end
    if cd and cd.starts and not shot.startAt then shot.startAt = cd.frames end
    if not shot.start and shot.startAt and cd.frames >= shot.startAt + 12 then
      shot.start = U.still(game, DIR .. "/g3mg_dodrio_countdown_start.png")
    end
    return mine.phase == "play" and shot.names and sim.started
  end, 25)
  result(okIntro, "intro ran: tree borders, status bar, player names")
  result(shot.three, "countdown 3")
  result(shot.start, "countdown START")
  result(mine.phase == "play", "play")
  local myPicks = 0
  local shotMid, shotOver = false, false
  local playT0 = now()
  while now() - playT0 < 120 do
    relay:pump()
    stepPeers()
    if sim.flow ~= "game" then break end
    local dir = wantDir(sim, sim.frame, 1, math.huge)
    if dir and sim:ownPick() == R.PICK_NONE then
      U.tap(game, dir)
      myPicks = myPicks + 1
    else
      U.wait(1)
    end
    if not shotMid and now() - playT0 > 14 then
      shotMid = true
      U.still(game, DIR .. "/g3mg_dodrio_midgame.png")
    end
    if not shotOver and sim.view.gray >= R.NUM_STATUS_SQUARES then
      shotOver = true
      stillFor(0.4)
      U.still(game, DIR .. "/g3mg_dodrio_game_over.png")
    end
  end
  result(myPicks > 0, "RED reached for berries (" .. myPicks .. " taps, " .. sim.presses .. " presses)")
  local ack = sim.view.ack[sim.me] or 0
  result(ack > 0, "RED's presses reached the leader (ack " .. ack .. ")")
  result(shotOver, "ten berries missed: game over")

  local function pressUntilKey(key, cond, seconds)
    local t = now()
    while not cond() and now() - t < (seconds or 5) do
      U.tap(game, key)
      stillFor(0.1)
    end
    return cond()
  end
  local function pressUntil(cond, seconds) return pressUntilKey("a", cond, seconds) end
  result(waitFor(function() return sim.rs and sim.rs.show == "results" end, 15), "berry results window")
  stillFor(0.6)
  U.still(game, DIR .. "/g3mg_dodrio_results.png")
  result(pressUntil(function() return sim.rs.show == "rankings" end, 5), "rankings")
  stillFor(0.6)
  U.still(game, DIR .. "/g3mg_dodrio_rankings.png")
  local prize = sim:highest() >= R.PRIZE_SCORE
  result(pressUntil(function() return sim.rs.show == "prize" or sim.rs.show == "standby" end, 5),
    "past the rankings")
  if prize then
    result(sim.rs.show == "prize", "prize window (highest " .. sim:highest() .. ")")
    stillFor(0.6)
    U.still(game, DIR .. "/g3mg_dodrio_prize.png")
    pressUntil(function() return sim.rs.show == "standby" end, 5)
  end
  result(sim.rs.show == "standby", "communication standby")
  stillFor(0.2)
  U.still(game, DIR .. "/g3mg_dodrio_standby.png")
  result(waitFor(function() return sim.flow == "ask" and sim.rs.show == "ask" end, 20), "Want to play again?")
  stillFor(0.3)
  U.still(game, DIR .. "/g3mg_dodrio_play_again.png")
  result(pressUntilKey("b", function() return sim.flow == "standby2" end, 5), "RED answers NO")
  result(waitFor(function() return sim.flow == "dropped" and sim.rs.show == "dropped" end, 15),
    "Somebody dropped out. The link will be canceled.")
  stillFor(0.3)
  U.still(game, DIR .. "/g3mg_dodrio_dropped_out.png")

  local res = mine.result
  local peerRes = peers[2].m.result
  local Json = require("src.link.Json")
  local function canon(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  result(res ~= nil and peerRes ~= nil and canon(res.results) == canon(peerRes.results), "RED and LEAF agree on the results")
  print("[driver] results " .. Json.encode(res and res.results or {}))
  local myScore
  for _, r in ipairs(res and res.results or {}) do if r.seat == 1 then myScore = r.score end end
  result(session.dodrioBerryPickingRecords ~= nil and session.dodrioBerryPickingRecords.bestScore == myScore,
    "record written (" .. tostring(myScore) .. ")")

  result(waitFor(function() return not MG.isActive() end, 12), "the minigame exits")
  result(waitFor(function() return Space.mapId == CORNER and getVar(VAR_CABLE_CLUB_STATE) == 0 end, 10),
    "warped back and ExitMinigameRoom cleared VAR_CABLE_CLUB_STATE")
  wait(60)
  U.shot(game, DIR .. "/g3mg_dodrio_returned.png")
  result(Client.room() == nil, "RED left the relay room")
  finish()
end

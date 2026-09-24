-- Drives five src/online/Client instances through a v2 tournament against a
-- real ../pokeserver over TCP: tour_create with a party, joins, tour_start,
-- tour_bye, tour_match -> a child room -> a full Gen 1 LinkBattle over
-- roomSession(), reports, room_result, bracket advance, tour_over; an outside
-- spectator watching through match_start_spectate and side-tagged room_msg; a
-- mid-battle socket kill with resume and replay; a report("error") forfeit;
-- the server-side shot clock; and tour_closed on a kick.  Runs under love
-- because plain luajit on macOS has no luasocket.
--
--   POKEPORT_TOUCH=0 POKEPORT_DRIVER=tests/drivers/online_tour_smoke.lua love .
--
-- headless, with a wall-clock cap (script -q is useless on macOS):
--   perl -e 'alarm 900; exec @ARGV' \
--     python3 -c 'import pty,sys; pty.spawn(sys.argv[1:])' \
--     /Applications/love.app/Contents/MacOS/love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PORT = tonumber(os.getenv("POKEPORT_LINK_PORT") or "") or 17778
  local SERVER = os.getenv("POKESERVER_DIR") or "../pokeserver"
  local SHOT_MS = 6000
  local failures = 0

  local function check(cond, msg)
    if cond then
      U.log("ok  ", msg)
    else
      failures = failures + 1
      U.log("FAIL", msg)
    end
  end

  local function finish()
    U.log(failures == 0 and "online tournament smoke passed"
          or (failures .. " online tournament smoke check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local probe = io.open(SERVER .. "/server.js", "r")
  if not probe then
    U.log("FAIL", SERVER .. "/server.js is not checked out")
    love.event.quit(1)
    return
  end
  probe:close()

  local pidFile = "/tmp/pokeserver_tour_" .. PORT .. ".pid"
  os.execute(("(cd %q && PORT=%d HTTP_PORT=%d POKESERVER_TEST_SHOT_MS=%d " ..
              "node server.js >/tmp/pokeserver_tour.log 2>&1 & echo $! > %q)")
             :format(SERVER, PORT, PORT + 1, SHOT_MS, pidFile))

  local function stopServer()
    local handle = io.open(pidFile, "r")
    if handle then
      local pid = handle:read("*l")
      handle:close()
      if pid and pid ~= "" then os.execute("kill " .. pid .. " >/dev/null 2>&1") end
    end
    os.remove(pidFile)
  end

  local Net = require("src.link.Net")
  local function reachable()
    local sock = Net.new()
    if not sock:connectTCP("127.0.0.1:" .. PORT) then return false end
    for _ = 1, 30 do
      sock:update()
      if sock.closed then
        pcall(function() sock:close() end)
        return false
      end
      if not sock.connecting then
        pcall(function() sock:close() end)
        return true
      end
    end
    pcall(function() sock:close() end)
    return false
  end

  local up = false
  for _ = 1, 300 do
    up = reachable()
    if up then break end
    U.wait(2)
  end
  if not up then
    check(false, "the spawned pokeserver answered on 127.0.0.1:" .. PORT)
    stopServer()
    return finish()
  end
  U.log("pokeserver up on", PORT, "shot clock", SHOT_MS .. "ms")

  local Data = game.data
  local Input = require("src.core.Input")
  local LinkBattle = require("src.link.LinkBattle")
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local SaveData = require("src.core.SaveData")
  local Version = require("src.core.Version")

  local PROFILE = {
    engine = 1, version = "red", engineVersion = Version.engine,
    apiVersion = Version.modApi, fingerprint = "tour-smoke",
    rulesetId = "gen1_faithful", kind = "vanilla", rule = { partySize = 1 },
  }
  local RULE = { partySize = 1 }

  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = copy(item) end
    return out
  end

  local EVENTS = { "match_start", "match_end", "tour_match", "tour_spectate",
                   "tour_bye", "tour_over", "error" }

  local bots = {}

  local function newBot(name, species)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    local bot = { name = name, C = C, ev = {}, seen = {} }
    C.configure({
      relayAddress = "127.0.0.1:" .. PORT,
      connect = function(address)
        local net = Net.new()
        if not net:connectTCP(address or ("127.0.0.1:" .. PORT)) then
          return nil, net.error or "no relay"
        end
        net.mode = "onlineLobby"
        net.v2 = true
        bot.net = net
        return net
      end,
    })
    for _, event in ipairs(EVENTS) do
      local key = event
      C.on(key, function(payload)
        bot.ev[key] = payload
        bot.seen[key] = (bot.seen[key] or 0) + 1
      end)
    end
    C.on("tournament", function(t)
      if t and t.stage == "finished" and not bot.champFromState then
        bot.champFromState = t.champion
      end
    end)
    if species then
      local save = SaveData.newGame()
      save.player.name = name
      save.party = { Pokemon.new(Data, species, 50) }
      bot.save = save
      bot.party = Protocol.packParty(save.party)
    end
    bots[#bots + 1] = bot
    return bot
  end

  local function pump(n)
    for _ = 1, n or 1 do
      for _, bot in ipairs(bots) do bot.C.update(1 / 60) end
      coroutine.yield()
    end
  end

  local function waitFor(fn, frames, what)
    for _ = 1, frames or 600 do
      if fn() then return true end
      pump(1)
    end
    if what then check(false, "timed out waiting for " .. tostring(what)) end
    return false
  end

  local function connectAll(list)
    for _, bot in ipairs(list) do
      bot.C.connect({ name = bot.name, profiles = { PROFILE } })
    end
    local ok = waitFor(function()
      for _, bot in ipairs(list) do
        if bot.C.state() ~= "online" then return false end
      end
      return true
    end, 900, "every client to come online")
    return ok
  end

  local function headless(bot)
    local stack = { list = {} }
    function stack:push(state, ...)
      table.insert(self.list, state)
      if state.enter then state:enter(...) end
    end
    function stack:pop() return table.remove(self.list) end
    function stack:top() return self.list[#self.list] end
    function stack:update(dt)
      local top = self:top()
      if top and top.update then top:update(dt) end
    end
    return { data = Data, input = Input, stack = stack, save = bot.save }
  end

  -- ------------------------------------------------------- the main bracket

  local org = newBot("ORG")
  local watch = newBot("WATCH")
  local p1 = newBot("PONE", "CHARIZARD")
  local p2 = newBot("PTWO", "BLASTOISE")
  local p3 = newBot("PTHREE", "VENUSAUR")
  local players = { p1, p2, p3 }

  if not connectAll(bots) then
    stopServer()
    return finish()
  end
  check(org.C.you() ~= nil, "the real relay welcomes every v2 client")

  local made = org.C.createTournament({ profile = PROFILE, rule = RULE,
                                        playing = false, shotClock = 3,
                                        maxSpectators = 8 })
  waitFor(function() return made.done end, 600, "tour_create to answer")
  check(made.id ~= nil,
        "the real relay creates a tournament: " .. tostring(made.error))
  if not made.id then
    stopServer()
    return finish()
  end
  local tourId = made.id
  local created = org.C.tournament()
  check(created and created.stage == "registering" and
        created.creator == org.C.you().id and #created.players == 0 and
        #created.spectators == 1,
        "a playing:false creator is a spectator holding creator powers")
  check(created and created.shotClock == 3 and created.rule and
        created.rule.partySize == 1,
        "tour_state carries the shot clock and the rule")

  for _, bot in ipairs(players) do
    bot.join = bot.C.joinTournament({ tour = tourId, as = "player",
      party = bot.party, partyDigest = "d" .. bot.name })
  end
  watch.join = watch.C.joinTournament({ tour = tourId, as = "spectator" })
  waitFor(function()
    local t = org.C.tournament()
    return t and #t.players == 3 and #t.spectators == 2
  end, 900, "three players and two spectators to register")
  local roster = org.C.tournament()
  check(roster and #roster.players == 3,
        "three players register with their teams up front")
  check(roster and #roster.spectators == 2,
        "the creator and the outside spectator both watch")
  for _, bot in ipairs(players) do
    check(bot.join.error == nil,
          bot.name .. " joined: " .. tostring(bot.join.error))
  end

  local short = newBot("SHORT", "PIKACHU")
  connectAll({ short })
  local twoMons = copy(short.party)
  twoMons[2] = copy(short.party[1])
  local refused = short.C.joinTournament({ tour = tourId, as = "player",
    party = twoMons, partyDigest = "dx" })
  waitFor(function() return refused.done end, 600, "the bad party to be refused")
  check(refused.reason == "party_ineligible",
        "a party that breaks the rule is refused: " .. tostring(refused.reason))
  short.C.disconnect()

  org.C.startTournament()
  waitFor(function()
    local t = org.C.tournament()
    return t and t.stage == "running" and #t.bracket >= 1
  end, 900, "the tournament to start")
  local running = org.C.tournament()
  check(running and running.stage == "running",
        "the creator starts the tournament")
  check(running and running.bracket[1] and #running.bracket[1].matches == 2,
        "three players make a two-slot first round: " ..
        tostring(running and running.bracket[1] and #running.bracket[1].matches))

  waitFor(function()
    for _, bot in ipairs(players) do
      if bot.ev.tour_bye then return true end
    end
    return false
  end, 900, "a walkover player to be told tour_bye")
  local byeBots = 0
  for _, bot in ipairs(players) do
    if bot.ev.tour_bye then byeBots = byeBots + 1 end
  end
  check(byeBots == 1, "exactly one player gets tour_bye: " .. byeBots)

  local played = {}

  local function liveSeats()
    local seated = {}
    for _, bot in ipairs(players) do
      local tm = bot.ev.tour_match
      local start = bot.ev.match_start
      if tm and start and start.match == tm.match and not played[tm.match] then
        seated[#seated + 1] = bot
      end
    end
    return seated
  end

  local function playLiveMatch(label)
    waitFor(function() return #liveSeats() == 2 end, 1800,
            "two players to be seated in " .. label)
    local seats = liveSeats()
    if #seats ~= 2 then return nil end
    local a, b = seats[1], seats[2]
    local tourA, tourB = a.ev.tour_match, b.ev.tour_match
    local startA, startB = a.ev.match_start, b.ev.match_start
    local token = tourA.match
    played[token] = true
    check(tourA.match == tourB.match,
          label .. ": both players share the bracket token (" .. token .. ")")
    check(tourA.room == tourB.room and startA.room == tourA.room,
          label .. ": match_start is bound to the child room from tour_match")
    check(startA.match == token,
          label .. ": the child room reuses the bracket token as its match")
    check(startA.seed ~= nil and startA.seed == startB.seed,
          label .. ": both seats share one seed")
    check(startA.theirParty ~= nil and startB.theirParty ~= nil,
          label .. ": each seat is handed the other party without room_ready")

    local watchers = {}
    for _, bot in ipairs(bots) do
      if bot ~= a and bot ~= b and bot.C.state() == "online" then
        watchers[#watchers + 1] = bot
      end
    end
    waitFor(function()
      for _, bot in ipairs(watchers) do
        local spec, start = bot.ev.tour_spectate, bot.ev.match_start
        if not (spec and spec.match == token and start and start.match == token) then
          return false
        end
      end
      return true
    end, 900, label .. ": every other member to be told to spectate")
    for _, bot in ipairs(watchers) do
      local spec, start = bot.ev.tour_spectate, bot.ev.match_start
      check(spec ~= nil and spec.match == token and start ~= nil and
            start.match == token and start.role == "spectator",
            label .. ": " .. bot.name .. " watches through match_start_spectate")
      check(start ~= nil and start.room == tourA.room,
            label .. ": " .. bot.name .. " is put in the child room")
      bot.sides = {}
    end

    local host, hostStart = a, startA
    local guest, guestStart = b, startB
    if startA.role ~= "host" then
      host, hostStart, guest, guestStart = b, startB, a, startA
    end
    check(hostStart.role == "host" and guestStart.role == "guest",
          label .. ": the relay seats one host and one guest")

    local gameH, gameG = headless(host), headless(guest)
    local battleH = LinkBattle.newHost(gameH, host.C.roomSession(), {
      myParty = copy(host.party), theirParty = copy(hostStart.theirParty),
      theirName = hostStart.peerName, seed = hostStart.seed,
      ruleset = hostStart.ruleset, keepNetOpen = true,
    })
    local battleG = LinkBattle.newGuest(gameG, guest.C.roomSession(), {
      myParty = copy(guest.party), theirParty = copy(guestStart.theirParty),
      theirName = guestStart.peerName, seed = guestStart.seed,
      ruleset = guestStart.ruleset, keepNetOpen = true,
    })
    check(battleH ~= nil and battleG ~= nil,
          label .. ": LinkBattle builds over the tournament child room")
    if not (battleH and battleG) then return nil end

    local resH, resG
    battleH.onFinish = function(r) resH = r end
    battleG.onFinish = function(r) resG = r end
    gameH.stack:push(battleH)
    gameG.stack:push(battleG)

    for frame = 1, 24000 do
      if resH and resG then break end
      if frame % 600 == 0 then U.log(label, "battle frame", frame) end
      Input.pressed = { a = true }
      gameH.stack:update(1 / 60)
      gameG.stack:update(1 / 60)
      Input.pressed = {}
      for _, bot in ipairs(watchers) do
        local session = bot.C.roomSession()
        if session then
          for _, msg in ipairs(session:poll()) do
            if msg.type == "spectate" and msg.side then
              bot.sides[msg.side] = (bot.sides[msg.side] or 0) + 1
            end
          end
        end
      end
      pump(1)
    end
    check(resH ~= nil and resG ~= nil,
          label .. ": the battle finishes over the relay (" ..
          tostring(resH) .. " / " .. tostring(resG) .. ")")
    check(battleH.player.mon.hp == battleG.enemy.mon.hp and
          battleH.enemy.mon.hp == battleG.player.mon.hp,
          label .. ": both simulations agree on HP across the relay")
    for _, bot in ipairs(watchers) do
      check((bot.sides.host or 0) > 0 and (bot.sides.guest or 0) > 0,
            label .. ": " .. bot.name .. " saw both sides' room_msg tagged (" ..
            tostring(bot.sides.host) .. "/" .. tostring(bot.sides.guest) .. ")")
    end

    host.C.report(resH)
    guest.C.report(resG)
    local function ended(bot)
      return bot.ev.match_end and bot.ev.match_end.match == token
        and bot.ev.match_end or nil
    end
    waitFor(function() return ended(host) and ended(guest) end, 1200,
            label .. ": room_result on both seats")
    local endHost, endGuest = ended(host), ended(guest)
    check(endHost ~= nil,
          label .. ": room_result names the bracket token and reaches both seats")
    local winnerId = nil
    if endHost then
      winnerId = endHost.winnerId
      check(endHost.how == "agreed",
            label .. ": the relay agreed the two reports (" ..
            tostring(endHost.how) .. ")")
      check(endGuest ~= nil and endGuest.winnerId == winnerId,
            label .. ": both seats are told the same winner")
    end
    waitFor(function()
      local t = org.C.tournament()
      if not t then return false end
      for _, round in ipairs(t.bracket) do
        for _, m in ipairs(round.matches) do
          if m.match == token and m.state == "done" then return true end
        end
      end
      return false
    end, 900, label .. ": the bracket to record the result")
    local recorded = nil
    local t = org.C.tournament()
    for _, round in ipairs(t and t.bracket or {}) do
      for _, m in ipairs(round.matches) do
        if m.match == token then recorded = m end
      end
    end
    check(recorded ~= nil and recorded.state == "done" and
          recorded.winner == winnerId and recorded.how == "agreed",
          label .. ": the bracket records the winner and how")
    local loserId = nil
    if winnerId then
      loserId = winnerId == host.C.you().id and guest.C.you().id
        or host.C.you().id
    end
    local eliminated = false
    for _, entry in ipairs(t and t.players or {}) do
      if entry.id == loserId and entry.eliminated then eliminated = true end
    end
    check(eliminated, label .. ": the loser is marked eliminated in tour_state")
    return token
  end

  local firstToken = playLiveMatch("round 1")
  if not firstToken then
    stopServer()
    return finish()
  end
  local secondToken = playLiveMatch("round 2")
  check(secondToken ~= nil and secondToken ~= firstToken,
        "the bracket advances into a second match: " .. tostring(secondToken))

  waitFor(function() return org.ev.tour_over ~= nil end, 1200,
          "tour_over after the final")
  local over = org.ev.tour_over
  check(over ~= nil, "a three-player bracket ends in tour_over")
  if over then
    check(over.tour == tourId, "tour_over names the tournament")
    check(org.champFromState ~= nil and org.champFromState == over.championId,
          "tour_state.champion is the id tour_over calls championId (" ..
          tostring(org.champFromState) .. ")")
    local championName = nil
    for _, entry in ipairs(org.C.tournament().players) do
      if entry.id == over.championId then championName = entry.name end
    end
    check(championName ~= nil and championName == over.champion,
          "tour_over.champion is that id's name (" .. tostring(over.champion) ..
          ")")
    check(watch.ev.tour_over ~= nil and
          watch.ev.tour_over.championId == over.championId,
          "the outside spectator is told the same champion")
    check(org.C.tournament().stage == "finished",
          "the model stays finished until we leave")
  end

  for _, bot in ipairs(bots) do
    if bot.C.state() == "online" then bot.C.leaveTournament() end
  end
  pump(10)
  for _, bot in ipairs(bots) do bot.C.disconnect() end
  pump(5)
  bots = {}

  -- --------------------------------------------------- resume mid-battle

  local rOrg = newBot("RORG")
  local rA = newBot("RONE", "CHARIZARD")
  local rB = newBot("RTWO", "BLASTOISE")
  if not connectAll(bots) then
    stopServer()
    return finish()
  end
  local rMade = rOrg.C.createTournament({ profile = PROFILE, rule = RULE,
                                          playing = false, shotClock = 9,
                                          maxSpectators = 4 })
  waitFor(function() return rMade.done end, 600, "the resume tournament")
  rA.C.joinTournament({ tour = rMade.id, as = "player", party = rA.party,
    partyDigest = "dra" })
  rB.C.joinTournament({ tour = rMade.id, as = "player", party = rB.party,
    partyDigest = "drb" })
  waitFor(function()
    local t = rOrg.C.tournament()
    return t and #t.players == 2
  end, 900, "both resume-test players to register")
  rOrg.C.startTournament()
  waitFor(function() return rA.ev.match_start and rB.ev.match_start end, 1200,
          "the resume-test match to start")
  check(rA.ev.match_start ~= nil and rB.ev.match_start ~= nil,
        "resume: the bracket seats both players")
  if not (rA.ev.match_start and rB.ev.match_start) then
    stopServer()
    return finish()
  end

  local rHost = rA.ev.match_start.role == "host" and rA or rB
  local rGuest = rHost == rA and rB or rA
  local sessH, sessG = rHost.C.roomSession(), rGuest.C.roomSession()
  local function instrument(bot, session)
    bot.sent, bot.recv = 0, 0
    local rawSend, rawPoll = session.send, session.poll
    session.send = function(self, msg)
      bot.sent = bot.sent + 1
      return rawSend(self, msg)
    end
    session.poll = function(self)
      local out = rawPoll(self)
      bot.recv = bot.recv + #out
      return out
    end
  end
  instrument(rHost, sessH)
  instrument(rGuest, sessG)

  local rGameH, rGameG = headless(rHost), headless(rGuest)
  local rBattleH = LinkBattle.newHost(rGameH, sessH, {
    myParty = copy(rHost.party), theirParty = copy(rHost.ev.match_start.theirParty),
    theirName = rHost.ev.match_start.peerName, seed = rHost.ev.match_start.seed,
    ruleset = rHost.ev.match_start.ruleset, keepNetOpen = true,
  })
  local rBattleG = LinkBattle.newGuest(rGameG, sessG, {
    myParty = copy(rGuest.party), theirParty = copy(rGuest.ev.match_start.theirParty),
    theirName = rGuest.ev.match_start.peerName, seed = rGuest.ev.match_start.seed,
    ruleset = rGuest.ev.match_start.ruleset, keepNetOpen = true,
  })
  local rResH, rResG
  rBattleH.onFinish = function(r) rResH = r end
  rBattleG.onFinish = function(r) rResG = r end
  rGameH.stack:push(rBattleH)
  rGameG.stack:push(rBattleG)

  local sessionBefore = rGuest.C.sessionId()
  local killedAt, reconnected = nil, false
  for frame = 1, 24000 do
    if rResH and rResG then break end
    if frame == 240 and not killedAt then
      killedAt = frame
      pcall(function() rGuest.net.tcpSocket:close() end)
    end
    if killedAt and not reconnected and rGuest.C.state() == "online"
       and frame > killedAt + 30 then
      reconnected = true
    end
    Input.pressed = { a = true }
    rGameH.stack:update(1 / 60)
    rGameG.stack:update(1 / 60)
    Input.pressed = {}
    pump(1)
  end
  check(killedAt ~= nil, "resume: the guest's socket was killed mid-battle")
  check(reconnected, "resume: the guest reconnected on its own backoff")
  check(rGuest.C.sessionId() == sessionBefore,
        "resume: the guest walked back into the same relay session")
  check(rResH ~= nil and rResG ~= nil,
        "resume: the battle still finishes (" .. tostring(rResH) .. " / " ..
        tostring(rResG) .. ")")
  check(rBattleH.player.mon.hp == rBattleG.enemy.mon.hp and
        rBattleH.enemy.mon.hp == rBattleG.player.mon.hp,
        "resume: both simulations agree on HP, so the replay caused no desync")
  for _ = 1, 30 do
    if sessH then sessH:poll() end
    if sessG then sessG:poll() end
    pump(1)
  end
  check(rHost.recv == rGuest.sent,
        ("resume: the host got each guest message once (%d sent, %d delivered)")
          :format(rGuest.sent, rHost.recv))
  check(rGuest.recv == rHost.sent,
        ("resume: room_replay redelivered nothing twice (%d sent, %d delivered)")
          :format(rHost.sent, rGuest.recv))
  U.log("resume: duplicate room messages dropped by the client:",
        rGuest.C.duplicates())

  rHost.C.report(rResH)
  rGuest.C.report(rResG)
  waitFor(function() return rOrg.ev.tour_over ~= nil end, 1200,
          "resume: tour_over")
  check(rOrg.ev.tour_over ~= nil,
        "resume: the tournament finishes after the resumed match")
  for _, bot in ipairs(bots) do bot.C.disconnect() end
  pump(5)
  bots = {}

  -- ------------------------------------------------------------- forfeit

  local fOrg = newBot("FORG")
  local fA = newBot("FONE", "CHARIZARD")
  local fB = newBot("FTWO", "BLASTOISE")
  if not connectAll(bots) then
    stopServer()
    return finish()
  end
  local fMade = fOrg.C.createTournament({ profile = PROFILE, rule = RULE,
                                          playing = false, shotClock = 9,
                                          maxSpectators = 4 })
  waitFor(function() return fMade.done end, 600, "the forfeit tournament")
  fA.C.joinTournament({ tour = fMade.id, as = "player", party = fA.party,
    partyDigest = "dfa" })
  fB.C.joinTournament({ tour = fMade.id, as = "player", party = fB.party,
    partyDigest = "dfb" })
  waitFor(function()
    local t = fOrg.C.tournament()
    return t and #t.players == 2
  end, 900, "both forfeit-test players to register")
  fOrg.C.startTournament()
  waitFor(function() return fA.ev.match_start and fB.ev.match_start end, 1200,
          "the forfeit-test match to start")
  fA.C.report("error")
  waitFor(function() return fA.ev.match_end and fB.ev.match_end end, 1200,
          "room_result after the forfeit")
  check(fA.ev.match_end ~= nil and fA.ev.match_end.how == "forfeit",
        "report(\"error\") forfeits the match: " ..
        tostring(fA.ev.match_end and fA.ev.match_end.how))
  check(fA.ev.match_end and fA.ev.match_end.winnerId == fB.C.you().id,
        "the other seat wins the forfeited match")
  waitFor(function() return fOrg.ev.tour_over ~= nil end, 1200,
          "tour_over after the forfeit")
  check(fOrg.ev.tour_over ~= nil and
        fOrg.ev.tour_over.championId == fB.C.you().id,
        "the forfeit hands the bracket to the other player")
  for _, bot in ipairs(bots) do bot.C.disconnect() end
  pump(5)
  bots = {}

  -- ----------------------------------------------------------- shot clock

  local sOrg = newBot("SORG")
  local sA = newBot("SONE", "CHARIZARD")
  local sB = newBot("STWO", "BLASTOISE")
  if not connectAll(bots) then
    stopServer()
    return finish()
  end
  local sMade = sOrg.C.createTournament({ profile = PROFILE, rule = RULE,
                                          playing = false, shotClock = 3,
                                          maxSpectators = 4 })
  waitFor(function() return sMade.done end, 600, "the shot-clock tournament")
  sA.C.joinTournament({ tour = sMade.id, as = "player", party = sA.party,
    partyDigest = "dsa" })
  sB.C.joinTournament({ tour = sMade.id, as = "player", party = sB.party,
    partyDigest = "dsb" })
  waitFor(function()
    local t = sOrg.C.tournament()
    return t and #t.players == 2
  end, 900, "both shot-clock players to register")
  sOrg.C.startTournament()
  waitFor(function() return sA.ev.match_start and sB.ev.match_start end, 1200,
          "the shot-clock match to start")
  local sHost = sA.ev.match_start.role == "host" and sA or sB
  local sStalled = sHost == sA and sB or sA
  sHost.C.roomSession():send({ type = "action", kind = "move", slot = 1 })
  waitFor(function() return sHost.ev.match_end ~= nil end,
          math.floor(SHOT_MS / 1000 * 60) + 900,
          "the shot clock to fire on the stalled player")
  check(sHost.ev.match_end ~= nil and sHost.ev.match_end.how == "timeout",
        "an unanswered turn forfeits on the shot clock: " ..
        tostring(sHost.ev.match_end and sHost.ev.match_end.how))
  check(sHost.ev.match_end and sHost.ev.match_end.winnerId == sHost.C.you().id,
        "the player who acted wins the timed-out match")
  check(sStalled.ev.match_end ~= nil and
        sStalled.ev.match_end.winnerId == sHost.C.you().id,
        "the stalled player is told the same result")
  for _, bot in ipairs(bots) do bot.C.disconnect() end
  pump(5)
  bots = {}

  -- ----------------------------------------------------------- kick

  local kOrg = newBot("KORG")
  local kA = newBot("KONE", "CHARIZARD")
  if not connectAll(bots) then
    stopServer()
    return finish()
  end
  local kMade = kOrg.C.createTournament({ profile = PROFILE, rule = RULE,
                                          playing = false, shotClock = 6,
                                          maxSpectators = 4 })
  waitFor(function() return kMade.done end, 600, "the kick tournament")
  kA.C.joinTournament({ tour = kMade.id, as = "player", party = kA.party,
    partyDigest = "dka" })
  waitFor(function()
    local t = kOrg.C.tournament()
    return t and #t.players == 1
  end, 900, "the kick-test player to register")
  kOrg.C.kickFromTournament(kA.C.you().id)
  waitFor(function() return kA.ev.error ~= nil end, 900,
          "tour_closed on the kicked player")
  check(kA.ev.error ~= nil and kA.ev.error.scope == "tournament" and
        kA.ev.error.reason == "kicked",
        "a kicked player is told tour_closed: " ..
        tostring(kA.ev.error and kA.ev.error.reason))
  check(kA.C.tournament() == nil,
        "the kicked player's tournament model is cleared")
  waitFor(function()
    local t = kOrg.C.tournament()
    return t and #t.players == 0
  end, 900, "the kicked player to leave tour_state")
  check(kOrg.C.tournament() and #kOrg.C.tournament().players == 0,
        "the kicked player is out of tour_state")
  kOrg.C.closeTournament()
  waitFor(function() return kOrg.ev.error ~= nil end, 900,
          "tour_closed on the creator")
  check(kOrg.ev.error ~= nil and kOrg.ev.error.reason == "closed",
        "the creator can close the tournament: " ..
        tostring(kOrg.ev.error and kOrg.ev.error.reason))

  for _, bot in ipairs(bots) do bot.C.disconnect() end
  pump(5)
  stopServer()
  return finish()
end

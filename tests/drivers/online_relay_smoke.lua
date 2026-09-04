-- Drives two src/online/Client instances against a real ../pokeserver over
-- TCP: room create, join, ready, a full Gen 1 LinkBattle over roomSession(),
-- room_report from both sides, and the relay's room_result.  Runs under love
-- because plain luajit on macOS has no luasocket.
--
--   POKEPORT_IDENTITY=online_smoke POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/online_relay_smoke.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PORT = tonumber(os.getenv("POKEPORT_LINK_PORT") or "") or 17778
  local SERVER = os.getenv("POKESERVER_DIR") or "../pokeserver"
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
    U.log(failures == 0 and "online relay smoke passed"
          or (failures .. " online relay smoke check(s) failed"))
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

  local pidFile = "/tmp/pokeserver_smoke_" .. PORT .. ".pid"
  os.execute(("(cd %q && PORT=%d HTTP_PORT=%d node server.js " ..
              ">/tmp/pokeserver_smoke.log 2>&1 & echo $! > %q)")
             :format(SERVER, PORT, PORT + 1, pidFile))

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
    local probe = Net.new()
    if not probe:connectTCP("127.0.0.1:" .. PORT) then return false end
    for _ = 1, 30 do
      probe:update()
      if probe.closed then
        pcall(function() probe:close() end)
        return false
      end
      if not probe.connecting then
        pcall(function() probe:close() end)
        return true
      end
    end
    pcall(function() probe:close() end)
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
  U.log("pokeserver up on", PORT)

  local function freshClient()
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "127.0.0.1:" .. PORT })
    return C
  end

  local Host = freshClient()
  local Guest = freshClient()

  local function pump(n)
    for _ = 1, n or 1 do
      Host.update(1 / 60)
      Guest.update(1 / 60)
      coroutine.yield()
    end
  end

  local function waitFor(fn, frames, what)
    for _ = 1, frames or 600 do
      if fn() then return true end
      pump(1)
    end
    check(false, "timed out waiting for " .. tostring(what))
    return false
  end

  local Data = game.data
  local Version = require("src.core.Version")
  local PROFILE = {
    engine = 1, version = "red", engineVersion = Version.engine,
    apiVersion = Version.modApi, fingerprint = "relay-smoke",
    rulesetId = "gen1_faithful", kind = "vanilla", rule = { partySize = 1 },
  }

  local YELLOW = {}
  for k, v in pairs(PROFILE) do YELLOW[k] = v end
  YELLOW.version = "yellow"

  Host.connect({ name = "RED", profiles = { PROFILE } })
  Guest.connect({ name = "BLUE", profiles = { YELLOW } })
  if not waitFor(function()
        return Host.state() == "online" and Guest.state() == "online"
      end, 600, "both clients to come online") then
    U.log("host", Host.state(), tostring(Host.error()),
          "guest", Guest.state(), tostring(Guest.error()))
    stopServer()
    return finish()
  end
  check(Host.you() ~= nil and Guest.you() ~= nil,
        "the real relay welcomes both v2 clients")

  local room = Host.createRoom({ intent = "battle", profile = PROFILE,
                                 playing = true, maxSpectators = 4 })
  waitFor(function() return room.done end, 600, "room_create to answer")
  check(room.code ~= nil, "the real relay creates a room: " .. tostring(room.error))
  if not room.code then
    stopServer()
    return finish()
  end

  local joined = Guest.joinRoom(room.code, "player", YELLOW)
  waitFor(function() return joined.done end, 600, "room_join to answer")
  check(joined.error == nil,
        "a yellow guest joins a red room: " .. tostring(joined.error))
  waitFor(function()
    return Host.room() and #Host.room().players == 2
  end, 600, "the host to see two players")

  package.loaded["src.online.Client"] = nil
  local Watcher = require("src.online.Client")
  Watcher.reset()
  Watcher.configure({ relayAddress = "127.0.0.1:" .. PORT })
  Watcher.connect({ name = "GREEN", profiles = { PROFILE } })
  local function pump3(n)
    for _ = 1, n or 1 do
      Host.update(1 / 60)
      Guest.update(1 / 60)
      Watcher.update(1 / 60)
      coroutine.yield()
    end
  end
  for _ = 1, 600 do
    if Watcher.state() == "online" then break end
    pump3(1)
  end
  local badProfile = {}
  for k, v in pairs(PROFILE) do badProfile[k] = v end
  badProfile.fingerprint = "deadbeef"
  local refused = Watcher.joinRoom(room.code, "spectator", badProfile)
  for _ = 1, 600 do
    if refused.done then break end
    pump3(1)
  end
  check(refused.reason == "profile_mismatch",
        "a spectator whose profile differs is refused: " ..
        tostring(refused.reason))
  local watching = Watcher.joinRoom(room.code, "spectator", PROFILE)
  for _ = 1, 600 do
    if watching.done then break end
    pump3(1)
  end
  check(watching.error == nil, "a matching spectator is admitted: " ..
        tostring(watching.error))

  local function rejoin(profile)
    Watcher.leaveRoom()
    pump3(10)
    local pending = profile and Watcher.joinRoom(room.code, "spectator", profile)
      or Watcher.joinRoom(room.code, "spectator")
    for _ = 1, 600 do
      if pending.done then break end
      pump3(1)
    end
    return pending
  end

  Watcher.setProfiles({ badProfile })
  local stale = rejoin(nil)
  check(stale.reason == "profile_mismatch",
        "a join with no profile argument falls back to the stale snapshot " ..
        "and is refused: " .. tostring(stale.reason))
  local fresh = rejoin(PROFILE)
  check(fresh.error == nil,
        "the same session joins once the picked profile is passed: " ..
        tostring(fresh.error))
  Watcher.setProfiles({})
  local blind = rejoin(nil)
  check(blind.reason == "bad_profile",
        "a join with no profile at all is refused as bad_profile: " ..
        tostring(blind.reason))
  Watcher.disconnect()
  pump(5)

  local hostStart, guestStart, hostEnd, guestEnd
  Host.on("match_start", function(p) hostStart = p end)
  Guest.on("match_start", function(p) guestStart = p end)
  Host.on("match_end", function(p) hostEnd = p end)
  Guest.on("match_end", function(p) guestEnd = p end)

  local Input = require("src.core.Input")
  local LinkBattle = require("src.link.LinkBattle")
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local SaveData = require("src.core.SaveData")

  local function headless(name, species)
    local save = SaveData.newGame()
    save.player.name = name
    save.party = { Pokemon.new(Data, species, 50) }
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
    return { data = Data, input = Input, stack = stack, save = save }
  end

  local gameH = headless("RED", "CHARIZARD")
  local gameG = headless("BLUE", "BLASTOISE")
  local packedH = Protocol.packParty(gameH.save.party)
  local packedG = Protocol.packParty(gameG.save.party)

  Host.ready(packedH, "dh")
  Guest.ready(packedG, "dg")
  waitFor(function() return hostStart ~= nil and guestStart ~= nil end, 600,
          "match_start on both seats")
  check(hostStart ~= nil and guestStart ~= nil, "the relay starts the match")
  if not (hostStart and guestStart) then
    stopServer()
    return finish()
  end
  check(hostStart.role == "host" and guestStart.role == "guest",
        "the relay assigns host and guest by join order")
  check(type(hostStart.match) == "string" and hostStart.match == guestStart.match,
        "both seats share one match token: " .. tostring(hostStart.match))
  check(hostStart.seed == guestStart.seed and hostStart.seed ~= nil,
        "both seats share one seed: " .. tostring(hostStart.seed))
  check(hostStart.theirParty and hostStart.theirParty[1] and
        hostStart.theirParty[1].species == "BLASTOISE",
        "match_start carries the peer's party")

  local battleH = LinkBattle.newHost(gameH, Host.roomSession(), {
    myParty = packedH, theirParty = hostStart.theirParty,
    theirName = hostStart.peerName, seed = hostStart.seed,
    ruleset = hostStart.ruleset, keepNetOpen = true,
  })
  local battleG = LinkBattle.newGuest(gameG, Guest.roomSession(), {
    myParty = packedG, theirParty = guestStart.theirParty,
    theirName = guestStart.peerName, seed = guestStart.seed,
    ruleset = guestStart.ruleset, keepNetOpen = true,
  })
  check(battleH ~= nil and battleG ~= nil,
        "LinkBattle builds over a real relay room session")
  if not (battleH and battleG) then
    stopServer()
    return finish()
  end

  local resH, resG
  battleH.onFinish = function(r) resH = r end
  battleG.onFinish = function(r) resG = r end
  gameH.stack:push(battleH)
  gameG.stack:push(battleG)

  for _ = 1, 20000 do
    if resH and resG then break end
    Input.pressed = { a = true }
    gameH.stack:update(1 / 60)
    gameG.stack:update(1 / 60)
    pump(1)
  end
  check(resH ~= nil and resG ~= nil,
        ("the battle finishes over the real relay (%s / %s)")
          :format(tostring(resH), tostring(resG)))
  check(battleH.player.mon.hp == battleG.enemy.mon.hp and
        battleH.enemy.mon.hp == battleG.player.mon.hp,
        "both simulations agree on HP across the relay")

  check(Host.report(resH) ~= false, "the host reports its result")
  check(Guest.report(resG) ~= false, "the guest reports its result")
  waitFor(function() return hostEnd ~= nil and guestEnd ~= nil end, 900,
          "room_result on both seats")
  check(hostEnd ~= nil, "the relay answers room_report with room_result")
  if hostEnd then
    check(hostEnd.match == hostStart.match, "room_result names the match")
    check(hostEnd.how == "agreed" or hostEnd.how == "reported",
          "the relay resolved the reports: " .. tostring(hostEnd.how))
    check(hostEnd.winnerId ~= nil, "room_result names a winner id")
    check(hostEnd.youWon == (resH == "win"),
          "youWon matches what the host's own simulation said")
    check(guestEnd and guestEnd.winnerId == hostEnd.winnerId,
          "both seats are told the same winner")
  end
  waitFor(function()
    return Host.room() and Host.room().stage == "waiting"
  end, 600, "the room to return to waiting")
  check(Host.room() and Host.room().stage == "waiting",
        "the room is ready for a rematch")

  Host.leaveRoom()
  Guest.leaveRoom()
  pump(10)
  Host.disconnect()
  Guest.disconnect()
  pump(5)
  stopServer()
  return finish()
end

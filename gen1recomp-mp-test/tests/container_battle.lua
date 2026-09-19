-- Drives two real src/online/Client instances against the ALREADY RUNNING
-- relay container over its published TCP port, and plays a full Gen 1
-- LinkBattle through it.
--
-- tests/drivers/online_relay_smoke.lua proves the server is correct, but it
-- spawns its own server in-process and never crosses a container boundary.
-- This one spawns nothing: it connects to the container exactly as a player's
-- game does, so it covers the port mapping, the read-only container
-- filesystem, and the container's RELAY_TEST_NAMES=1 behaviour -- including
-- asserting that the seats really are named test_<digits>.
--
--   ./bin/container-test.sh
--
-- Exit code 0 means two players joined the running server and battled.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TARGET = os.getenv("POKEPORT_RELAY_ADDR") or "127.0.0.1:17778"
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
    U.log(failures == 0 and "container battle passed"
          or (failures .. " container battle check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local Net = require("src.link.Net")
  local function reachable()
    local probe = Net.new()
    if not probe:connectTCP(TARGET) then return false end
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
    U.log("FAIL no relay answered at " .. TARGET ..
          " -- is the container up?  Try ./bin/relay.sh up")
    return finish()
  end
  U.log("relay container reachable at", TARGET)

  local function freshClient()
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = TARGET })
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
    apiVersion = Version.modApi, fingerprint = "container-battle",
    rulesetId = "gen1_faithful", kind = "vanilla", rule = { partySize = 1 },
  }

  -- The clients ask to be called RED and BLUE.  The container runs with
  -- RELAY_TEST_NAMES=1, so it must ignore both and hand out test_<digits>.
  Host.connect({ name = "RED", profiles = { PROFILE } })
  Guest.connect({ name = "BLUE", profiles = { PROFILE } })
  if not waitFor(function()
        return Host.state() == "online" and Guest.state() == "online"
      end, 600, "both clients to come online") then
    U.log("host", Host.state(), tostring(Host.error()),
          "guest", Guest.state(), tostring(Guest.error()))
    return finish()
  end
  check(Host.you() ~= nil and Guest.you() ~= nil,
        "the container welcomes both v2 clients")

  local hostName = Host.you() and Host.you().name
  local guestName = Guest.you() and Guest.you().name
  U.log("seats:", tostring(hostName), tostring(guestName))
  -- Either separator is fine: `_` matches the POC's stated naming, `-` is what
  -- RELAY_TEST_NAME_SEP=- produces so the Gen 1 font can actually draw it.
  local function isTestName(n)
    return type(n) == "string" and n:match("^test[_%-]%d+$") ~= nil
  end
  check(isTestName(hostName),
        "the container names the first player test<sep><digits>: " ..
        tostring(hostName))
  check(isTestName(guestName),
        "the container names the second player test<sep><digits>: " ..
        tostring(guestName))
  check(hostName ~= guestName,
        "the two players get different names (" .. tostring(hostName) ..
        " / " .. tostring(guestName) .. ")")
  check(Host.you().verified == false,
        "the container marks the player unverified (no password)")

  local room = Host.createRoom({ intent = "battle", profile = PROFILE,
                                 playing = true, maxSpectators = 4 })
  waitFor(function() return room.done end, 600, "room_create to answer")
  check(room.code ~= nil, "the container creates a room: " ..
        tostring(room.error))
  if not room.code then return finish() end

  local joined = Guest.joinRoom(room.code, "player", PROFILE)
  waitFor(function() return joined.done end, 600, "room_join to answer")
  check(joined.error == nil, "the second player joins that room: " ..
        tostring(joined.error))
  waitFor(function()
    return Host.room() and #Host.room().players == 2
  end, 600, "the host to see two players")

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
  check(hostStart ~= nil and guestStart ~= nil,
        "the container starts the match")
  if not (hostStart and guestStart) then return finish() end
  check(hostStart.role == "host" and guestStart.role == "guest",
        "the container assigns host and guest by join order")
  check(type(hostStart.match) == "string" and
        hostStart.match == guestStart.match,
        "both seats share one match token: " .. tostring(hostStart.match))
  check(hostStart.seed == guestStart.seed and hostStart.seed ~= nil,
        "both seats share one seed: " .. tostring(hostStart.seed))

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
        "LinkBattle builds over the container's room session")
  if not (battleH and battleG) then return finish() end

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
        ("the battle finishes through the container (%s / %s)")
          :format(tostring(resH), tostring(resG)))
  if resH and resG then
    check(battleH.player.mon.hp == battleG.enemy.mon.hp and
          battleH.enemy.mon.hp == battleG.player.mon.hp,
          "both simulations agree on HP across the container")
  end

  check(Host.report(resH) ~= false, "the first player reports its result")
  check(Guest.report(resG) ~= false, "the second player reports its result")
  waitFor(function() return hostEnd ~= nil and guestEnd ~= nil end, 900,
          "room_result on both seats")
  check(hostEnd ~= nil, "the container answers room_report with room_result")
  if hostEnd then
    check(hostEnd.how == "agreed" or hostEnd.how == "reported",
          "the container resolved the reports: " .. tostring(hostEnd.how))
    check(hostEnd.youWon == (resH == "win"),
          "youWon matches what the first player's own simulation said")
    check(guestEnd and guestEnd.winnerId == hostEnd.winnerId,
          "both players are told the same winner")
  end
  waitFor(function()
    return Host.room() and Host.room().stage == "waiting"
  end, 600, "the room to return to waiting")
  check(Host.room() and Host.room().stage == "waiting",
        "the room is ready for a rematch")

  -- Leave the container as we found it.
  Host.leaveRoom()
  Guest.leaveRoom()
  pump(10)
  Host.disconnect()
  Guest.disconnect()
  pump(5)
  return finish()
end

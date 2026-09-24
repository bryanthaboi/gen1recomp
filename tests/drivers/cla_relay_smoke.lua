return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Net = require("src.link.Net")
  local addr = os.getenv("POKEPORT_RELAY_ADDR") or "127.0.0.1:7778"
  local failures = 0
  local function check(cond, label)
    U.log((cond and "ok   " or "FAIL ") .. label)
    if not cond then failures = failures + 1 end
  end

  local function newClient()
    local shared = package.loaded["src.online.Client"]
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    package.loaded["src.online.Client"] = shared
    C.reset()
    C.configure({ relayAddress = addr })
    return C
  end

  local clients = {}
  local function pumpAll()
    for _, C in ipairs(clients) do C.update(1 / 60) end
  end
  local function waitFor(pred, seconds)
    local deadline = love.timer.getTime() + (seconds or 4)
    while love.timer.getTime() < deadline do
      pumpAll()
      if pred() then return true end
      coroutine.yield()
    end
    return false
  end

  local function profile(rulesetId)
    return { engine = 3, version = "firered", engineVersion = "0.0.0-dev", apiVersion = 2,
             fingerprint = "clasmoke", rulesetId = rulesetId or "g3_single",
             kind = "vanilla", rule = { partySize = 3 } }
  end

  local old = Net.new()
  check(old:connectTCP(addr), "a v1 socket still dials the relay")
  old:send({ type = "host" })
  local up
  local deadline = love.timer.getTime() + 4
  while not up and love.timer.getTime() < deadline do
    old:update()
    for _, m in ipairs(old:poll()) do
      if m.type == "upgrade_required" then up = m end
    end
    coroutine.yield()
  end
  check(up ~= nil and up.protocol == 3, "a v1 host is answered with upgrade_required")
  old:close()

  local Stale = newClient()
  clients[#clients + 1] = Stale
  local Protocol2 = require("src.online.Protocol2")
  local savedProtocol = Protocol2.PROTOCOL
  Protocol2.PROTOCOL = 2
  Stale.connect({ name = "STALE", profiles = { profile() } })
  Protocol2.PROTOCOL = savedProtocol
  waitFor(function() return Stale.state() == "error" end)
  check(Stale.upgradeRequired() ~= nil, "a protocol 2 client surfaces upgrade_required")
  check(tostring(Stale.error()):find("update", 1, true) ~= nil,
        "with the relay's update text")

  local A = newClient()
  local B = newClient()
  clients[#clients + 1] = A
  clients[#clients + 1] = B
  A.connect({ name = "CLAHOST", profiles = { profile() },
              presence = { where = "launcher", status = "idle", version = "firered" } })
  B.connect({ name = "CLAJOIN", profiles = { profile() },
              presence = { where = "launcher", status = "idle", version = "leafgreen" } })
  check(waitFor(function() return A.state() == "online" and B.state() == "online" end),
        "two protocol 3 clients come online")

  local made = A.createRoom({ intent = "battle", profile = profile(), private = true,
                             pin = "2468", maxSpectators = 2 })
  waitFor(function() return made.done end)
  local roomId = made.id
  check(made.done and made.error == nil and roomId ~= nil,
        "a private engine 3 room is created: " .. tostring(made.error))
  check(A.room() and A.room().locked == true, "the room is locked")
  check(A.seat() == 0, "the host sits in seat 0")

  local listed = waitFor(function()
    for _, e in ipairs(B.lobby()) do
      if e.room == roomId then return e.locked == true and e.code == nil end
    end
    return false
  end)
  check(listed, "the joiner sees the room listed with a lock and no code")

  local noPin = B.joinRoom(roomId, "player", profile())
  waitFor(function() return noPin.done end)
  check(noPin.reason == "pin_required", "no PIN answers pin_required: " .. tostring(noPin.reason))
  local wrong = B.joinRoom(roomId, "player", profile(), "1357")
  waitFor(function() return wrong.done end)
  check(wrong.reason == "bad_pin" and wrong.triesLeft == 4,
        "a wrong PIN answers bad_pin with 4 tries left: " .. tostring(wrong.reason)
        .. " " .. tostring(wrong.triesLeft))

  local startA, startB
  A.on("match_start", function(p) startA = p end)
  B.on("match_start", function(p) startB = p end)
  local right = B.joinRoom(roomId, "player", profile(), "2468")
  waitFor(function() return right.done and startA and startB end)
  check(right.done and right.error == nil, "the right PIN seats the joiner")
  check(startA and startA.seat == 0 and startA.role == "host", "match_start seats the host at 0")
  check(startB and startB.seat == 1 and startB.role == "guest", "and the joiner at 1")
  check(startA and startB and startA.seed == startB.seed and startA.seed ~= nil,
        "both seats share the relay's seed")
  check(B.room() and B.room().stage == "battling", "the full engine 3 room is battling")

  local rsA, rsB = A.roomSession(), B.roomSession()
  rsA:send({ type = "game3_battle_action", turn = 1, kind = "move", slot = 1, move = 33 })
  local got
  waitFor(function()
    got = got or rsB:take("game3_battle_action")
    return got ~= nil
  end)
  check(got ~= nil and got.seat == 0 and got.move == 33,
        "an inner game3 message crosses the real relay tagged with seat 0")
  rsB:send({ type = "game3_made_up", x = 1 })
  rsB:send({ type = "game3_battle_switch", slot = 2 })
  local sw
  waitFor(function()
    sw = sw or rsA:take("game3_battle_switch")
    return sw ~= nil
  end)
  check(sw ~= nil and sw.seat == 1, "the guest's switch arrives tagged with seat 1")

  local token
  A.on("invite_token", function(m) token = m.token end)
  A.inviteToken(roomId)
  waitFor(function() return token ~= nil end)
  check(token ~= nil, "a seated player mints an invite token")

  A.leaveRoom()
  B.leaveRoom()
  waitFor(function() return A.room() == nil and B.room() == nil end, 1)
  A.disconnect()
  B.disconnect()
  Stale.disconnect()

  U.log("CLA_RELAY_SMOKE:", failures == 0 and "PASS" or ("FAIL " .. failures))
  love.event.quit(failures == 0 and 0 or 1)
end

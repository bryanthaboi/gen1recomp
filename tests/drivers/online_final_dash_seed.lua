return function()
  local U = dofile("tests/drivers/util.lua")
  local addr = os.getenv("POKEPORT_RELAY_ADDR") or "127.0.0.1:28100"
  local readyFile = os.getenv("POKEPORT_DASH_READY") or "/tmp/claude-501/lr-dash-ready"
  local releaseFile = os.getenv("POKEPORT_DASH_RELEASE") or "/tmp/claude-501/lr-dash-release"
  local hold = tonumber(os.getenv("POKEPORT_DASH_HOLD") or "") or 90
  local failures = 0
  local function check(cond, label)
    U.log((cond and "ok   " or "FAIL ") .. label)
    if not cond then failures = failures + 1 end
  end

  local clients = {}
  local function newClient()
    local shared = package.loaded["src.online.Client"]
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    package.loaded["src.online.Client"] = shared
    C.reset()
    C.configure({ relayAddress = addr })
    clients[#clients + 1] = C
    return C
  end
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
  local function settle(seconds)
    local deadline = love.timer.getTime() + seconds
    while love.timer.getTime() < deadline do
      pumpAll()
      coroutine.yield()
    end
  end

  local function profile(version, ruleset)
    return { engine = 3, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
             fingerprint = "dashseed", rulesetId = ruleset, kind = "vanilla",
             rule = { partySize = 3 } }
  end
  local function avatar(name, version, gender)
    return { name = name, trainerId = #name * 777, gender = gender or 0, version = version }
  end
  local function online(name, version, ruleset)
    local C = newClient()
    C.connect({ name = name, profiles = { profile(version, ruleset or "g3_single") },
      presence = { where = "launcher", status = "idle", version = version } })
    return C
  end

  local union, wireless = {}, {}
  local unionNames = { "MISTY", "ERIKA", "SABRINA", "BLAINE", "GIOVANNI", "LORELEI",
    "BRUNO", "AGATHA", "LANCE", "KOGA", "SURGE" }
  for i, n in ipairs(unionNames) do
    union[i] = online(n .. "#" .. (200 + i), i % 2 == 0 and "firered" or "leafgreen", "g3_link")
  end
  for i, n in ipairs({ "OAK", "DAISY", "BILL" }) do
    wireless[i] = online(n .. "#" .. (300 + i), "firered", "g3_link")
  end
  local hostA = online("LEAF#102", "leafgreen", "g3_single")
  local joinA = online("GOLD#103", "firered", "g3_single")
  local hostM = online("KRIS#105", "firered", "g3_multi")
  local joinM1 = online("LYRA#106", "leafgreen", "g3_multi")
  local joinM2 = online("ETHAN#107", "firered", "g3_multi")
  local hostD = online("WALLY#110", "leafgreen", "g3_double")
  local directQ = online("BROCK#111", "firered", "g3_single")
  local guesser = online("PIKA#199", "firered", "g3_single")
  check(waitFor(function()
    for _, C in ipairs(clients) do if C.state() ~= "online" then return false end end
    return true
  end, 10), "every seed client is online (" .. #clients .. ")")

  for i, C in ipairs(union) do
    C.joinPlaza("union", profile(i % 2 == 0 and "firered" or "leafgreen", "g3_link"),
      avatar(unionNames[i], i % 2 == 0 and "firered" or "leafgreen", i % 2))
  end
  for _, C in ipairs(wireless) do C.joinPlaza("wireless", profile("firered", "g3_link")) end
  check(waitFor(function()
    for _, C in ipairs(union) do if C.plaza() == nil then return false end end
    return true
  end, 6), "the Union Room holds " .. #union .. " trainers")

  local locked = hostA.createRoom({ intent = "battle", profile = profile("leafgreen", "g3_single"),
    playing = true, maxSpectators = 8, private = true, pin = "0427", seats = 2, auto = false })
  local multi = hostM.createRoom({ intent = "battle", profile = profile("firered", "g3_multi"),
    playing = true, maxSpectators = 8, private = false, seats = 4, auto = false })
  waitFor(function() return locked.done and multi.done end, 6)
  check(locked.id ~= nil and multi.id ~= nil, "a locked 2-seat room and a 4-seat room exist")
  for _, C in ipairs({ joinM1, joinM2 }) do
    local j = C.joinRoom(multi.id, "player", profile(C == joinM1 and "leafgreen" or "firered", "g3_multi"))
    waitFor(function() return j.done end, 4)
  end
  hostD.queueDirect({ activity = "battle_double", profile = profile("leafgreen", "g3_double"),
    auto = false, avatar = avatar("WALLY", "leafgreen") })
  directQ.queueDirect({ activity = "battle_single", profile = profile("firered", "g3_single"),
    auto = true, avatar = avatar("BROCK", "firered") })
  wireless[1].openGroup("minigame_crush", profile("firered", "g3_link"), avatar("OAK", "firered"))

  local tries = 0
  for i = 1, 6 do
    local wrong = guesser.joinRoom(locked.id, "player", profile("firered", "g3_single"),
      ("%04d"):format(1110 + i))
    waitFor(function() return wrong.done end, 4)
    tries = tries + 1
    U.log("pin try", i, tostring(wrong.reason), tostring(wrong.triesLeft))
  end
  local right = joinA.joinRoom(locked.id, "spectator", profile("firered", "g3_single"), "0427")
  waitFor(function() return right.done end, 4)
  check(tries == 6, "six wrong PINs were sent at the locked room")
  settle(1.5)

  local f = io.open(readyFile, "w")
  if f then f:write("ready\n") f:close() end
  U.log("DASH_SEED ready; holding up to", hold, "s")
  local from = love.timer.getTime()
  while love.timer.getTime() - from < hold do
    pumpAll()
    local r = io.open(releaseFile, "r")
    if r then r:close() break end
    coroutine.yield()
  end
  for _, C in ipairs(clients) do C.disconnect() end
  settle(0.3)
  os.remove(readyFile)
  U.log("ONLINE_FINAL_DASH_SEED:", failures == 0 and "PASS" or ("FAIL " .. failures))
  love.event.quit(failures == 0 and 0 or 1)
end

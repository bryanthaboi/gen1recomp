-- Drives the ONLINE tab's own screen stack against a real ../pokeserver:
-- connect, host from the Play screen, a second seat joins, both ready, the
-- arena spec is built and handed to playArena, and the panel is back on the
-- Room screen with the match result.
--
--   POKEPORT_RELAY_ADDR=127.0.0.1:17778 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/online_walkthrough.lua love .

return function()
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


  local probe = io.open(SERVER .. "/server.js", "r")
  if not probe then
    U.log("FAIL", SERVER .. "/server.js is not checked out")
    love.event.quit(1)
    return
  end
  probe:close()

  local pidFile = "/tmp/pokeserver_walk_" .. PORT .. ".pid"
  os.execute(("(cd %q && PORT=%d HTTP_PORT=%d node server.js " ..
              ">/tmp/pokeserver_walk.log 2>&1 & echo $! > %q)")
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

  local function finish()
    stopServer()
    U.log(failures == 0 and "online walkthrough passed"
          or (failures .. " online walkthrough check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local Host = require("src.online.Client")
  Host.reset()
  Host.configure({ relayAddress = "127.0.0.1:" .. PORT })
  package.loaded["src.online.Client"] = nil
  local Guest = require("src.online.Client")
  package.loaded["src.online.Client"] = Host
  Guest.reset()
  Guest.configure({ relayAddress = "127.0.0.1:" .. PORT })

  local Net = require("src.link.Net")
  local function reachable()
    local socketProbe = Net.new()
    if not socketProbe:connectTCP("127.0.0.1:" .. PORT) then return false end
    for _ = 1, 30 do
      socketProbe:update()
      if socketProbe.closed then
        pcall(function() socketProbe:close() end)
        return false
      end
      if not socketProbe.connecting then
        pcall(function() socketProbe:close() end)
        return true
      end
    end
    pcall(function() socketProbe:close() end)
    return false
  end

  local up = false
  local bootFrom = love.timer.getTime()
  while love.timer.getTime() - bootFrom < 20 do
    up = reachable()
    if up then break end
    U.wait(2)
  end
  if not up then
    check(false, "the spawned pokeserver answered on 127.0.0.1:" .. PORT)
    return finish()
  end
  U.log("pokeserver up on", PORT)

  local OnlinePanel = require("src.import.OnlinePanel")
  local SaveData = require("src.core.SaveData")
  local TeamPick = require("src.online.TeamPick")
  local GameVersion = require("src.core.GameVersion")

  local version
  for _, id in ipairs(GameVersion.ORDER) do
    if GameVersion.generation(id) == 1 then
      local ok, rows = pcall(SaveData.listSlots, id)
      if ok and type(rows) == "table" then
        for _, row in ipairs(rows) do
          if row.exists then version = version or id end
        end
      end
    end
    if version then break end
  end
  if not version then
    check(false, "a Gen 1 save is imported for the walkthrough")
    return finish()
  end

  local slots = SaveData.listSlots(version)
  local slotId
  for _, row in ipairs(slots) do
    if row.exists and not slotId then slotId = row.id end
  end

  local booted = nil
  local imp = {
    ready = { [version] = true },
    activeSlot = {}, slots = { [version] = slots }, carts = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
    playArena = function(_, bootVersion, cartId, spec)
      booted = { version = bootVersion, cartId = cartId, spec = spec }
      return true
    end,
  }
  local st = OnlinePanel.state(imp)
  st.version, st.slotId = version, slotId
  st.team = { { where = "party", index = 1 } }

  local function pump(n)
    for _ = 1, n or 1 do
      Guest.update(1 / 60)
      OnlinePanel.update(imp, 1 / 60)
      coroutine.yield()
    end
  end

  local function waitFor(fn, frames, what)
    for _ = 1, frames or 900 do
      if fn() then return true end
      pump(1)
    end
    check(false, "timed out waiting for " .. tostring(what))
    return false
  end

  local profileFrom = love.timer.getTime()
  while OnlinePanel.myProfile(imp) == nil and love.timer.getTime() - profileFrom < 10 do
    pump(1)
  end
  local profile, why = OnlinePanel.myProfile(imp)
  check(profile ~= nil, "the panel computes its own arena profile: " .. tostring(why))
  if not profile then return finish() end

  OnlinePanel.connect(imp)
  Guest.connect({ name = "BLUE#221", profiles = { profile } })
  waitFor(function()
    return Host.state() == "online" and Guest.state() == "online"
  end, 900, "both seats to come online")
  check(Host.state() == "online", "the panel's own client is online")

  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  check(OnlinePanel.screen(imp) == "play", "Home walks to the Play screen")

  check(OnlinePanel.startWizard(imp, "hostBattle"),
    "Host a battle opens the wizard")
  check(OnlinePanel.screen(imp) == "wizard", "on its own screen")
  local steps = OnlinePanel.wizardSteps(imp)
  check(table.concat(steps, ",") == "game,save,team,rules,visibility,summary",
    "one step per choice: " .. table.concat(steps, ","))
  OnlinePanel.wizardTo(imp, "rules")
  check(OnlinePanel.ruleFor(imp).partySize == 1,
    "the rule defaults to the number of POKeMON picked")
  OnlinePanel.wizardTo(imp, "summary")
  check(OnlinePanel.wizardNext(imp),
    "the summary confirm hosts the room: " .. tostring(st.status))
  waitFor(function() return Host.room() ~= nil end, 900, "the room to open")
  pump(2)
  local room = Host.room()
  check(room ~= nil and room.room ~= nil, "hosting opens a room")
  if not room then return finish() end
  check(OnlinePanel.screen(imp) == "room",
    "the panel routes itself onto the Room screen: "
    .. tostring(OnlinePanel.screen(imp)))

  OnlinePanel.go(imp, "play")
  check(OnlinePanel.screen(imp) == "play" and Host.room() ~= nil,
    "Play opens over the Room without leaving it")
  OnlinePanel.refresh(imp)
  local mine = OnlinePanel.cache(imp).mine
  check(mine ~= nil and mine.room == room.room,
    "Play shows the player's own lobby as a card, not a joinable row: "
    .. tostring(mine and mine.room) .. " vs " .. tostring(room.room))
  for _, entry in ipairs(OnlinePanel.cache(imp).rooms) do
    check(entry.room ~= room.room, "and never as a row you can join")
  end
  OnlinePanel.go(imp, "room")

  local joined = Guest.joinRoom(room.room, "player", profile)
  waitFor(function() return joined.done end, 900, "the guest's join to answer")
  check(joined.error == nil, "the second seat joins: " .. tostring(joined.error))
  waitFor(function()
    local live = Host.room()
    return live and #live.players == 2
  end, 900, "the room to hold two players")

  local pick = TeamPick.readSlot(version, slotId)
  local packed = TeamPick.pack(pick, { 1 }, pick.generation)
  local sent = OnlinePanel.sendReady(imp)
  check(sent, "READY packs the chosen team: " .. tostring(st.status))
  Guest.ready(packed, "guest")

  waitFor(function() return booted ~= nil end, 900, "the arena to boot")
  check(booted ~= nil, "match_start hands an arena spec to playArena")
  if booted then
    check(booted.spec.role == "host", "the panel boots as the host seat")
    check(booted.spec.session ~= nil, "over the room's own session")
    check(booted.spec.team ~= nil and #booted.spec.team == 1,
      "carrying the team the wizard picked")
    check(booted.spec.team[1] == 1, "as a party index ArenaBoot understands")
  end

  OnlinePanel.recordResult("win")
  st.routeKey = nil
  OnlinePanel.update(imp, 1 / 60)
  check(OnlinePanel.lastResult == "win", "the arena's result survives")
  check(OnlinePanel.screen(imp) == "room",
    "and the tab is back on the Room screen: "
    .. tostring(OnlinePanel.screen(imp)))

  Guest.disconnect()
  Host.disconnect()
  pump(5)
  return finish()
end

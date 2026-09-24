return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PORT = tonumber(os.getenv("POKEPORT_C1_RELAY_PORT") or "") or 18411
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

  local pidFile = "/tmp/pokeserver_c1_" .. PORT .. ".pid"
  local function stopServer()
    local handle = io.open(pidFile, "r")
    if handle then
      local pid = handle:read("*l")
      handle:close()
      if pid and pid:match("^%d+$") then
        os.execute("kill " .. pid .. " >/dev/null 2>&1")
      end
    end
    os.remove(pidFile)
  end

  local function finish()
    stopServer()
    U.log(failures == 0 and "online c1 pin relay passed"
          or (failures .. " online c1 pin relay check(s) failed"))
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

  os.execute(("(cd %q && PORT=%d HTTP_PORT=%d SYNC_ENABLED=0 CARTS_ENABLED=0 "
    .. "STATS_ENABLED=0 GIFTS_ENABLED=0 CART_MIRROR_ENABLED=0 node server.js "
    .. ">/tmp/pokeserver_c1_%d.log 2>&1 & echo $! > %q)")
    :format(SERVER, PORT, PORT + 1, PORT, pidFile))

  local Net = require("src.link.Net")
  local function reachable()
    local net = Net.new()
    if not net:connectTCP("127.0.0.1:" .. PORT) then return false end
    for _ = 1, 30 do
      net:update()
      if net.closed then
        pcall(function() net:close() end)
        return false
      end
      if not net.connecting then
        pcall(function() net:close() end)
        return true
      end
    end
    pcall(function() net:close() end)
    return false
  end

  local up = false
  local startedAt = love.timer.getTime()
  while love.timer.getTime() - startedAt < 20 do
    up = reachable()
    if up then break end
    U.wait(2)
  end
  check(up, "the spawned pokeserver answered on 127.0.0.1:" .. PORT)
  if not up then return finish() end

  local function freshClient()
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "127.0.0.1:" .. PORT })
    return C
  end

  local Host = freshClient()
  local Guest = freshClient()
  local OnlinePanel = require("src.import.OnlinePanel")
  OnlinePanel._hooked = nil
  OnlinePanel._events = {}

  local Version = require("src.core.Version")
  local PROFILE = {
    engine = 1, version = "red", engineVersion = Version.engine,
    apiVersion = Version.modApi, fingerprint = "c1-pin", rulesetId = "gen1_faithful",
    kind = "vanilla", rule = { partySize = 1 },
  }

  local imp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local st = OnlinePanel.state(imp)
  st.version, st.slotId, st.setupDone = "red", "slot1", true
  st.team = { { where = "party", index = 1 } }
  st.profiles["red|vanilla|-"] = { profile = PROFILE }
  local SAVE = { party = { { species = "PIKACHU", level = 20, moves = {} } } }
  st.slotRead = { key = "red|slot1|-",
    data = { generation = 1, party = SAVE.party, save = SAVE } }

  local function pump(n)
    for _ = 1, n or 1 do
      Host.update(1 / 60)
      Guest.update(1 / 60)
      OnlinePanel.update(imp, 1 / 60)
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

  Host.connect({ name = "HOST#001", profiles = { PROFILE } })
  Guest.connect({ name = "GUEST#002", profiles = { PROFILE } })
  if not waitFor(function()
        return Host.state() == "online" and Guest.state() == "online"
      end, 600, "both clients online") then
    U.log("host", Host.state(), tostring(Host.error()),
          "guest", Guest.state(), tostring(Guest.error()))
    return finish()
  end

  local made = Host.createRoom({ intent = "battle", profile = PROFILE,
    playing = true, maxSpectators = 4, private = true, pin = "0427",
    seats = 2, auto = false })
  waitFor(function() return made.done end, 600, "the private room")
  local hostRoom = Host.room()
  check(hostRoom ~= nil and hostRoom.locked == true, "the host's room is locked")
  local roomId = hostRoom and hostRoom.room
  check(type(roomId) == "string" and roomId:match("^r%x+$") ~= nil,
    "and has an opaque id, no code")

  local row
  waitFor(function()
    OnlinePanel.invalidate(imp, "lobby")
    OnlinePanel.refresh(imp)
    for _, r in ipairs(OnlinePanel.cache(imp).rooms) do
      if r.room == roomId then row = r end
    end
    return row ~= nil
  end, 600, "the locked room in the Play list")
  check(row and row.locked == true, "the Play list shows it with a lock")
  check(row and row.code == nil, "and no code")

  OnlinePanel.startJoin(imp, OnlinePanel.targetFor(row, "player"))
  check(OnlinePanel.pinModal(imp) ~= nil, "Join opens the PIN modal")
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "1111")
  check(OnlinePanel.pinSubmit(imp), "a wrong PIN is sent")
  waitFor(function() return OnlinePanel.pinModal(imp) ~= nil end, 600,
    "the wrong PIN answer")
  local mo = OnlinePanel.pinModal(imp)
  check(mo and mo.error and mo.error:find("didn't match", 1, true) ~= nil,
    "the relay's bad_pin reopens the modal: " .. tostring(mo and mo.error))
  check(Guest.room() == nil, "and the guest is not seated")

  for _ = 1, 4 do OnlinePanel.pinBack(imp) end
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "0427")
  check(OnlinePanel.pinSubmit(imp), "the right PIN is sent")
  waitFor(function() local r = Guest.room() return r and r.room == roomId end,
    600, "the guest to take the seat")
  check(Guest.room() and Guest.room().room == roomId,
    "the right PIN seats the guest")
  check(OnlinePanel.screen(imp) == "room", "on the Room screen")

  Guest.leaveRoom()
  pump(30)
  OnlinePanel.home(imp)

  local tokenMsg
  Host.on("invite_token", function(msg) tokenMsg = msg end)
  Host.inviteToken(roomId)
  waitFor(function() return tokenMsg ~= nil end, 600, "an invite token")
  local token = tokenMsg and tokenMsg.token
  check(type(token) == "string" and #token == 32, "the relay mints a token")
  if token then
    check(OnlinePanel.deepLink(imp, { invite = token }, "player"),
      "a Discord join hands the token to the panel")
    waitFor(function() local r = Guest.room() return r and r.room == roomId end,
      600, "the token join")
    check(Guest.room() and Guest.room().room == roomId,
      "the token seats the guest with no PIN")
    Guest.leaveRoom()
    pump(30)
  end
  OnlinePanel.home(imp)

  local guestId = Guest.you() and Guest.you().id
  if type(Host.invite) == "function" and guestId then
    Host.leaveRoom()
    pump(30)
    Host.invite(guestId, "battle_single", {}, PROFILE)
    waitFor(function() return OnlinePanel.toast(imp) ~= nil end, 600,
      "the invite toast")
    local toast = OnlinePanel.toast(imp)
    check(toast ~= nil, "an invite shows a toast")
    check(toast and OnlinePanel.inviteLine(toast):find("HOST#001", 1, true) ~= nil,
      "naming the sender")
    OnlinePanel.toastAction(imp, "accept")
    waitFor(function() return Guest.room() ~= nil end, 600, "the invite room")
    local r = Guest.room()
    check(r ~= nil and r.origin == "invite", "accepting lands in an invite room")
    check(r ~= nil and r.listed ~= true, "which is not listed")
    waitFor(function() return Host.room() ~= nil end, 600, "the inviter in the invite room")
    Guest.leaveRoom()
    Host.leaveRoom()
    local quietFrom = love.timer.getTime()
    while love.timer.getTime() - quietFrom < 1 do pump(1) end
  end

  local tourMade = Host.createTournament({ profile = PROFILE,
    rule = { partySize = 1 }, playing = false, shotClock = 6,
    maxSpectators = 8, public = false })
  waitFor(function() return tourMade.done end, 600, "the private tournament")
  local tour = Host.tournament()
  local code = tour and tour.code
  check(type(code) == "string" and #code == 6,
    "a private tournament keeps a six-character code: " .. tostring(code)
    .. " " .. tostring(tourMade.error or tourMade.reason))
  if code then
    st.tourCode = code:lower()
    OnlinePanel.joinTournament(imp, { code = st.tourCode }, "spectator")
    waitFor(function() return Guest.tournament() ~= nil end, 600,
      "joining by the private code")
    check(Guest.tournament() ~= nil, "the code lets a guest in")
  end

  Host.disconnect()
  Guest.disconnect()
  return finish()
end

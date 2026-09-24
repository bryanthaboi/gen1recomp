return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PORT = tonumber(os.getenv("POKEPORT_C2_RELAY_PORT") or "") or 18431
  local SERVER = os.getenv("POKESERVER_DIR") or "../pokeserver"
  local failures = 0

  local function check(cond, msg)
    if cond then
      U.log("ok  ", msg)
    else
      failures = failures + 1
      U.log("FAIL", msg)
    end
    return cond
  end

  local pidFile = "/tmp/pokeserver_c2_" .. PORT .. ".pid"
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
    U.log(failures == 0 and "online c2 relay passed"
          or (failures .. " online c2 relay check(s) failed"))
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
    .. ">/tmp/pokeserver_c2_%d.log 2>&1 & echo $! > %q)")
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
    local saved = package.loaded["src.online.Client"]
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    package.loaded["src.online.Client"] = saved
    C.reset()
    C.configure({ relayAddress = "127.0.0.1:" .. PORT })
    return C
  end

  local L = require("src.online.Client")
  L.reset()
  L.configure({ relayAddress = "127.0.0.1:" .. PORT })
  local OnlinePanel = require("src.import.OnlinePanel")
  OnlinePanel._hooked = nil
  OnlinePanel._events = {}
  OnlinePanel._pendingStart = nil

  local Version = require("src.core.Version")
  local Fingerprint = require("src.link.Fingerprint")
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  local fp = Fingerprint.compute({ generation = 3,
    gen3Inputs = Fingerprint.gen3Inputs(function(rel) return cache:read(rel) end) }, {}, 3)
  local function profile(version, ruleset, size)
    return { engine = 3, version = version, engineVersion = Version.engine,
      apiVersion = Version.modApi, fingerprint = fp, rulesetId = ruleset,
      kind = "vanilla", rule = { partySize = size or 3 } }
  end

  local SaveData = require("src.core.SaveData")
  local Trade = require("src.online.Trade")
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local Schema = require("src.core.game3.save_schema_firered")
  local RelayTransport = require("src.core.game3.link.relay_transport")

  local files = {}
  local savedFs = SaveData.portableFs
  SaveData.portableFs = function()
    return {
      getInfo = function(name) return files[name] and { type = "file" } or nil end,
      read = function(name) return files[name] end,
      write = function(name, body) files[name] = body return true end,
      remove = function(name) files[name] = nil return true end,
      createDirectory = function() return true end,
    }
  end
  local function makeSave(version, name, trainerId, mons)
    local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
    session.trainerId = trainerId
    session.dex.nationalUnlocked = true
    session.party = {}
    for _, row in ipairs(mons) do assert(Party.giveMon(session, row[1], row[2])) end
    return SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
  end
  local DATA = { generation = 3, Pokemon = Pokemon, pokemon = Pokemon }
  local function handle(version, slotId, save)
    local path = Trade.slotPath(version, slotId)
    files[path] = SaveData.encode(save)
    return { version = version, generation = 3, slotId = slotId, save = save,
             path = path, party = save.party, data = DATA }
  end
  local mySave = makeSave("firered", "RED", 11111,
    { { 6, 50 }, { 9, 50 }, { 3, 50 }, { 25, 40 } })
  local hL = handle("firered", "slot1", mySave)
  local savedOpen = Trade.openSlot
  Trade.openSlot = function() return hL end

  local imp = { ready = { firered = true, leafgreen = true }, activeSlot = {}, slots = {},
    pulse = 0, _pages = {}, _uiActions = {}, _actAt = {} }
  local played
  imp.playArena = function(_, version, cartId, spec)
    played = { version = version, cartId = cartId, spec = spec }
    return true
  end
  local st = OnlinePanel.state(imp)
  st.version, st.slotId, st.setupDone, st.kind = "firered", "slot1", true, "vanilla"
  st.profiles["firered|vanilla|-"] = { profile = profile("firered", "g3_single", 3) }
  st.slotRead = { key = "firered|slot1|-",
    data = { generation = 3, party = mySave.party, save = mySave } }

  local peers = {}
  local peer
  local function pump(n)
    for _ = 1, n or 1 do
      L.update(1 / 60)
      for _, C in ipairs(peers) do C.update(1 / 60) end
      OnlinePanel.update(imp, 1 / 60)
      if peer then peer:update(1 / 60) end
      coroutine.yield()
    end
  end
  local function waitFor(fn, frames, what)
    local limit = math.max(5, (frames or 600) / 60)
    local from = love.timer.getTime()
    while love.timer.getTime() - from < limit do
      if fn() then return true end
      pump(1)
    end
    if fn() then return true end
    check(false, "timed out waiting for " .. tostring(what))
    return false
  end

  local function team(n)
    local out = {}
    for i = 1, n do out[i] = { where = "party", index = i } end
    return out
  end

  L.connect({ name = "RED#001", profiles = { profile("firered", "g3_single", 3) },
    presence = { where = "launcher", status = "idle", version = "firered" } })
  for i, name in ipairs({ "LEAF#002", "GOLD#003", "KRIS#004", "MAY#005" }) do
    peers[i] = freshClient()
    peers[i].connect({ name = name, profiles = { profile("leafgreen", "g3_single", 3) } })
  end
  if not waitFor(function()
        if L.state() ~= "online" then return false end
        for _, C in ipairs(peers) do if C.state() ~= "online" then return false end end
        return true
      end, 900, "every client online") then
    U.log("launcher", L.state(), tostring(L.error()))
    return finish()
  end

  local lastRoom
  local function leaveAll()
    lastRoom = L.room() and L.room().room or lastRoom
    OnlinePanel.home(imp)
    L.leaveRoom()
    for _, C in ipairs(peers) do C.leaveRoom() end
    pump(30)
    local stale
    local quietFrom = love.timer.getTime()
    while love.timer.getTime() - quietFrom < 1 do
      stale = stale or (L.room() and L.room().room)
      pump(1)
    end
    check(stale == nil, "no stale room_state comes back after leaving: " .. tostring(stale))
    played = nil
    OnlinePanel._pendingStart = nil
  end
  local function newRoom()
    local r = L.room()
    return r ~= nil and r.room ~= lastRoom and r or nil
  end

  OnlinePanel.setRuleset(imp, "g3_double")
  st.team = team(3)
  check(OnlinePanel.hostBattle(imp), "the launcher hosts a FireRed double battle")
  waitFor(function() return L.room() ~= nil end, 600, "the double room")
  local room = L.room()
  check(room and room.engine == 3, "the relay made an engine 3 room")
  check(room and room.profile and room.profile.rulesetId == "g3_double", "a double battle")
  check(room and room.seats == 2, "with two seats")
  local row
  waitFor(function()
    OnlinePanel.invalidate(imp, "lobby")
    local found
    for _, e in ipairs(peers[1].lobby() or {}) do
      if room and e.room == room.room then found = e end
    end
    row = found
    return found ~= nil
  end, 600, "the room in another trainer's lobby")
  check(row and row.engine == 3, "the lobby row carries engine 3")
  check(row and row.profile and row.profile.version == "firered", "and FireRed")
  peers[1].joinRoom(room.room, "player", profile("leafgreen", "g3_double", 3))
  waitFor(function() return played ~= nil end, 600, "the double battle to start")
  check(peers[1].role() == "guest", "the LeafGreen trainer took seat 1")
  check(played and played.version == "firered", "the launcher boots FireRed")
  check(played and played.spec.mode == "double", "into a double battle arena")
  check(played and played.spec.seat == 0 and played.spec.seats == 2, "on seat 0 of 2")
  check(played and #played.spec.myParty == 3, "sending its three picks")
  check(played and type(played.spec.seed) == "number", "on the relay's seed")
  if played then
    local returned
    local savedReturn = game.returnToLauncher
    game.returnToLauncher = function(o) returned = o or {} end
    local Game3Link = require("src.link.Game3Link")
    local LB = require("src.core.game3.link.battle")
    local Protocol = require("src.link.Protocol")
    local linkType = LB.arenaLinkType(LB.MODE_OF.double)
    local rsG = peers[1].roomSession()
    local peerT = RelayTransport.new(rsG, { client = peers[1] })
    local peerLink = Game3Link.attach(peerT, { seat = 1, seats = 2, linkType = linkType,
      game = game, hello = Game3Link.hello(game, linkType,
        { name = "LEAF", trainerId = 22222, gender = 1 }) })
    local peerSave = makeSave("leafgreen", "LEAF", 22222,
      { { 94, 50 }, { 131, 50 }, { 59, 50 } })
    OnlinePanel.lastResult = nil
    game:enterArena(played.spec)
    check(game.phase == "arena", "the launcher's spec boots the Game3 arena")
    local setup
    waitFor(function()
      peerLink:update(1 / 60)
      setup = setup or peerLink:take(LB.MSG.SETUP)
      return setup ~= nil
    end, 900, "the arena's party at the other seat")
    check(peerLink:isReady(), "the arena's Game3Link hello matches over the real relay")
    check(setup ~= nil and #(setup.party or {}) == 3, "the arena sends the three picked POKeMON")
    peerLink:send({ type = LB.MSG.LINKUP, linkType = linkType, players = 2 })
    peerLink:send({ type = LB.MSG.SEAT, seat = 1 })
    peerLink:send({ type = LB.MSG.SETUP, mode = LB.MODE_OF.double, unionRoom = false,
      name = "LEAF", trainerId = 22222, gender = 1, seat = 1,
      party = Protocol.packParty3(peerSave.party) })
    waitFor(function()
      peerLink:update(1 / 60)
      return game.arena and game.arena.stage == "battle"
    end, 900, "the arena battle to begin")
    check(game.arena and game.arena.stage == "battle",
      "the arena reaches the battle against the other seat's party")
    peers[1].leaveRoom()
    waitFor(function() return returned ~= nil end, 1200,
      "the arena to hand back to the launcher")
    check(returned and returned.tab == "online", "the arena returns to the ONLINE tab")
    check(OnlinePanel.lastResult ~= nil, "the launcher hears the arena's result: "
      .. tostring(OnlinePanel.lastResult))
    game.returnToLauncher = savedReturn
  end
  leaveAll()

  OnlinePanel.setRuleset(imp, "g3_multi")
  st.team = team(3)
  check(OnlinePanel.hostBattle(imp), "the launcher hosts a multi battle")
  waitFor(function() return newRoom() ~= nil end, 600, "the multi room")
  room = newRoom()
  check(room and room.seats == 4, "the relay gave it four seats")
  for i = 1, 3 do
    peers[i].joinRoom(room.room, "player", profile("leafgreen", "g3_multi", 3))
    pump(20)
  end
  waitFor(function() return played ~= nil end, 600, "the multi battle to start")
  check(peers[3].role() == "seat3", "the fourth trainer sits on seat 3")
  check(played and played.spec.mode == "multi", "the launcher boots a multi battle")
  check(played and played.spec.seats == 4, "for four seats")
  check(played and #(played.spec.players or {}) == 4, "naming all four trainers")
  leaveAll()

  local hostC = peers[1]
  hostC.createRoom({ intent = "battle", profile = profile("leafgreen", "g3_multi", 3),
    playing = true, maxSpectators = 8, private = false, seats = 4, auto = false })
  waitFor(function() return hostC.room() ~= nil end, 600, "a LeafGreen multi room")
  room = hostC.room()
  OnlinePanel.setRuleset(imp, "g3_single")
  st.joinTarget = { room = room.room, engine = 3, rulesetId = "g3_multi", as = "spectator" }
  check(OnlinePanel.joinRoom(imp, room.room, "spectator"), "the launcher watches it")
  waitFor(function() return L.room() ~= nil end, 600, "the spectator seat")
  for i = 2, 4 do
    peers[i].joinRoom(room.room, "player", profile("leafgreen", "g3_multi", 3))
    pump(20)
  end
  waitFor(function() return played ~= nil end, 600, "the spectator arena")
  check(played and played.spec.role == "spectator", "the launcher watches as a spectator")
  check(played and played.spec.seats == 4 and played.spec.seat == nil,
    "of all four seats, with no seat of its own")
  leaveAll()

  local disk = files[hL.path]
  local savedLive = Trade.hostIsLive
  Trade.hostIsLive = nil
  check(OnlinePanel.hostTrade(imp), "the launcher hosts a FireRed trade")
  waitFor(function() return newRoom() ~= nil end, 600, "the trade room")
  room = newRoom()
  check(room and room.intent == "trade", "the relay made a trade room")
  check(room and room.profile.rulesetId == "g3_link", "on the link ruleset")
  local partner = peers[2]
  partner.joinRoom(room.room, "player", profile("leafgreen", "g3_link", 3))
  waitFor(function() return partner.room() ~= nil end, 600, "the partner seat")
  local hP = handle("leafgreen", "slot2", makeSave("leafgreen", "GOLD", 22222,
    { { 95, 25 }, { 1, 8 } }))
  local rsP = partner.roomSession()
  peer = Trade.remote(hP, rsP, { transport = RelayTransport.new(rsP, { client = partner }) })
  check(peer ~= nil, "the partner opens its side of the Trade Center")
  if peer then peer:start() end
  local tr = OnlinePanel.tradeState(imp)
  waitFor(function()
    return tr.remote and tr.remote:stage() == "picking" and peer and peer:stage() == "picking"
  end, 900, "both trade menus")
  check(OnlinePanel.screen(imp) == "trade", "the launcher is on the Trade screen")
  local _, theirs = OnlinePanel.remoteRows(tr.remote)
  check(#theirs == 2, "showing the partner's two POKeMON")
  check(OnlinePanel.remotePick(imp, 4), "the launcher offers its Pikachu")
  check(peer and peer:pick(1), "the partner offers its first")
  waitFor(function()
    return tr.remote and tr.remote:stage() == "confirming" and peer:stage() == "confirming"
  end, 600, "both confirm prompts")
  OnlinePanel.remoteConfirm(imp, true)
  peer:confirm(true)
  waitFor(function() return st.status == "Trade complete." or tr.remoteResult ~= nil end,
    900, "the relay's trade commit")
  check(st.status == "Trade complete.", "the relay commit finishes the launcher's trade: "
    .. tostring(st.status) .. " / " .. tostring(tr.remoteResult))
  check(files[hL.path] ~= disk, "and only then writes the launcher's save")
  check(peer and peer:stage() == "committed", "the partner committed too")
  peer = nil
  Trade.hostIsLive = savedLive
  leaveAll()

  local invitee = peers[3]
  local closedMsg, sentMsg
  L.on("invite_closed", function(m) closedMsg = m end)
  L.on("invite_sent", function(m) sentMsg = m end)
  local inviteIn
  invitee.on("invite_in", function(m) inviteIn = m end)
  local inviteeId = invitee.you() and invitee.you().id
  st.team = team(3)
  OnlinePanel.startInvite(imp, { id = inviteeId, name = "KRIS#004", engine = 3,
    version = "leafgreen" }, "battle_double")
  local answered = false
  local askedAt = love.timer.getTime()
  while love.timer.getTime() - askedAt < 4 do
    if sentMsg or closedMsg or inviteIn then answered = true break end
    pump(1)
  end
  if not answered then
    U.log("SKIP", "the relay never answered an invite (SRV-A A3 invites not in relay.js yet)")
  else
    waitFor(function() return inviteIn ~= nil end, 600, "the invite at the other trainer")
    check(inviteIn and inviteIn.activity == "battle_double", "a double battle invite")
    if inviteIn then
      local open = invitee.invites() or {}
      U.log("note", "invitee holds " .. #open .. " invites; id=" .. tostring(inviteIn.id)
        .. " expiresAt=" .. tostring(inviteIn.expiresAt) .. " serverTime="
        .. tostring(invitee.serverTime()))
      check(invitee.replyInvite(inviteIn.id, true) ~= false, "the other trainer accepts")
    end
    if not waitFor(function() return played ~= nil end, 600, "the invite battle") then
      local r = L.room()
      U.log("note", "status=" .. tostring(st.status), "room=" .. tostring(r and r.room),
        "stage=" .. tostring(r and r.stage), "closed=" .. tostring(closedMsg and closedMsg.why),
        "invitee=" .. tostring(invitee.room() and invitee.room().room))
    end
    check(played and played.spec.mode == "double", "the accepted invite boots a double")
    leaveAll()

    local sender = peers[4]
    local senderClosed
    sender.on("invite_closed", function(m) senderClosed = m end)
    local meId = L.you() and L.you().id
    sender.invite(meId, "chat", {}, profile("leafgreen", "g3_link", 3))
    waitFor(function() return senderClosed ~= nil end, 600, "the chat invite answer")
    check(senderClosed and senderClosed.why == "declined",
      "a chat invite to the launcher is declined at once: " .. tostring(senderClosed and senderClosed.why))
    check(OnlinePanel.toast(imp) == nil, "without a toast")
    sender.invite(meId, "battle_single", { ruleset = "g3_single" },
      profile("leafgreen", "g3_single", 3))
    waitFor(function() return OnlinePanel.toast(imp) ~= nil end, 600, "the launcher's invite toast")
    local toast = OnlinePanel.toast(imp)
    check(toast and OnlinePanel.inviteLine(toast):find("MAY#005", 1, true) ~= nil,
      "the toast names the trainer")
    OnlinePanel.toastAction(imp, "accept")
    waitFor(function() return played ~= nil end, 600, "the accepted invite battle")
    check(played and played.spec.seat == 1, "accepting puts the launcher on seat 1")
    check(played and played.spec.mode == "single", "for a single battle")
    leaveAll()
  end

  SaveData.portableFs = savedFs
  Trade.openSlot = savedOpen
  L.disconnect()
  for _, C in ipairs(peers) do C.disconnect() end
  return finish()
end

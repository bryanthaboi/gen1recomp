local ADDR = os.getenv("POKEPORT_RELAY_ADDR") or "127.0.0.1:28100"

local peers = {}
local hooks = {}
local log = function(...) print("[final]", ...) end

local function Main()
  return require("src.online.Client")
end

local function newPeer()
  local saved = package.loaded["src.online.Client"]
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  package.loaded["src.online.Client"] = saved
  C.reset()
  C.configure({ relayAddress = ADDR })
  peers[#peers + 1] = C
  return C
end

local function pumpAll(OnlinePanel, imp)
  pcall(Main().update, 1 / 60)
  for _, C in ipairs(peers) do pcall(C.update, 1 / 60) end
  for _, fn in ipairs(hooks) do pcall(fn) end
  OnlinePanel.update(imp, 1 / 60)
end

local function waitUntil(OnlinePanel, imp, fn, what, seconds)
  local deadline = love.timer.getTime() + (seconds or 8)
  while love.timer.getTime() < deadline do
    pumpAll(OnlinePanel, imp)
    if fn() then return true end
    love.timer.sleep(0.01)
  end
  log("TIMEOUT", what)
  return false
end

local function settle(OnlinePanel, imp, seconds)
  local deadline = love.timer.getTime() + (seconds or 0.3)
  while love.timer.getTime() < deadline do
    pumpAll(OnlinePanel, imp)
    love.timer.sleep(0.01)
  end
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
  return out
end

local function variant(base, version, ruleset, size)
  local p = copy(base)
  p.version = version or p.version
  p.rulesetId = ruleset or p.rulesetId
  p.rule = { partySize = size or 3 }
  return p
end

local function hookUpdate(OnlinePanel)
  if OnlinePanel._finalHooked then return end
  OnlinePanel._finalHooked = true
  local orig = OnlinePanel.update
  OnlinePanel.update = function(imp, dt)
    for _, C in ipairs(peers) do pcall(C.update, dt) end
    for _, fn in ipairs(hooks) do pcall(fn) end
    return orig(imp, dt)
  end
end

local function setup(OnlinePanel, imp, version, picks)
  local st = OnlinePanel.state(imp)
  st.version, st.kind, st.cartId = version, "vanilla", nil
  st.versionPicked = true
  st.slotId = nil
  for _, row in ipairs(OnlinePanel.slotsIn(imp, version, nil)) do
    if row.exists and not st.slotId then st.slotId = row.id end
  end
  st.setupDone = st.slotId ~= nil
  st.team = {}
  st.slotRead = nil
  local pick = OnlinePanel.readTeamSlot(imp)
  if pick then
    require("src.online.OnlineSprites").prime(version, pick.party)
    for index = 1, math.min(picks or 3, #pick.party) do
      OnlinePanel.toggleTeam(st.team, index)
    end
    st.focusMon = OnlinePanel.refKey(st.team[1])
  end
  OnlinePanel.invalidate(imp)
  return st
end

local function goOnline(OnlinePanel, imp, version, picks, ruleset)
  local st = setup(OnlinePanel, imp, version, picks)
  if ruleset then OnlinePanel.setRuleset(imp, ruleset) end
  waitUntil(OnlinePanel, imp, function() return OnlinePanel.myProfile(imp) ~= nil end,
    "the panel profile", 20)
  OnlinePanel.connect(imp)
  waitUntil(OnlinePanel, imp, function() return Main().state() == "online" end,
    "the panel online", 10)
  local base = OnlinePanel.myProfile(imp)
  log("panel", tostring(Main().state()), "profile", tostring(base and base.fingerprint),
    "slot", tostring(st.slotId), "team", #st.team)
  return st, base and copy(base) or nil
end

local function connectPeer(OnlinePanel, imp, name, profiles, where, version)
  local C = newPeer()
  C.connect({ name = name, profiles = profiles,
    presence = { where = where, status = "idle", version = version } })
  waitUntil(OnlinePanel, imp, function() return C.state() == "online" end,
    name .. " online", 8)
  return C
end

local function hostRoom(OnlinePanel, imp, C, opts)
  local made = C.createRoom(opts)
  waitUntil(OnlinePanel, imp, function() return made.done end, "room create", 8)
  log("room", tostring(made.id), tostring(made.error))
  return made.id
end

local function avatarOf(name, version, gender)
  return { name = name, trainerId = #name * 1111, gender = gender or 0, version = version }
end

local function joinUnion(OnlinePanel, imp, C, profile, name, version, gender)
  C.joinPlaza("union", profile, avatarOf(name, version, gender))
  waitUntil(OnlinePanel, imp, function() return C.plaza() ~= nil end, name .. " in the Union Room", 6)
end

local function directHost(OnlinePanel, imp, C, activity, profile, pin, name, version)
  C.queueDirect({ activity = activity, profile = profile, pin = pin, auto = false,
    avatar = avatarOf(name, version) })
  waitUntil(OnlinePanel, imp, function() return C.room() ~= nil end, name .. " hosting in Direct Corner", 6)
  log("direct", name, tostring(C.room() and C.room().room), tostring(C.error()))
end

local function seedLobby(OnlinePanel, imp, base)
  local fr, lg = "firered", "leafgreen"
  local P = {}
  P.leaf = connectPeer(OnlinePanel, imp, "LEAF#102",
    { variant(base, lg, "g3_single") }, "launcher", lg)
  hostRoom(OnlinePanel, imp, P.leaf, { intent = "battle", profile = variant(base, lg, "g3_single"),
    playing = true, maxSpectators = 8, private = true, pin = "0427", seats = 2, auto = false,
    note = "no legends" })
  P.gold = connectPeer(OnlinePanel, imp, "GOLD#103",
    { variant(base, fr, "g3_double") }, "launcher", fr)
  directHost(OnlinePanel, imp, P.gold, "battle_double", variant(base, fr, "g3_double"), nil,
    "GOLD", fr)
  P.wally = connectPeer(OnlinePanel, imp, "WALLY#110",
    { variant(base, lg, "g3_single") }, "launcher", lg)
  directHost(OnlinePanel, imp, P.wally, "battle_single", variant(base, lg, "g3_single"), "5555",
    "WALLY", lg)
  P.may = connectPeer(OnlinePanel, imp, "MAY#104",
    { variant(base, lg, "g3_link") }, "launcher", lg)
  hostRoom(OnlinePanel, imp, P.may, { intent = "trade", profile = variant(base, lg, "g3_link"),
    playing = true, maxSpectators = 0, private = true, pin = "1234", seats = 2, auto = false })
  P.kris = connectPeer(OnlinePanel, imp, "KRIS#105",
    { variant(base, fr, "g3_multi") }, "launcher", fr)
  P.krisRoom = hostRoom(OnlinePanel, imp, P.kris, { intent = "battle",
    profile = variant(base, fr, "g3_multi"), playing = true, maxSpectators = 8,
    private = false, seats = 4, auto = false })
  P.lyra = connectPeer(OnlinePanel, imp, "LYRA#106",
    { variant(base, lg, "g3_multi") }, "launcher", lg)
  if P.krisRoom then
    local j = P.lyra.joinRoom(P.krisRoom, "player", variant(base, lg, "g3_multi"))
    waitUntil(OnlinePanel, imp, function() return j.done end, "lyra joins kris", 6)
  end
  P.brock = connectPeer(OnlinePanel, imp, "BROCK#107",
    { variant(base, fr, "g3_single") }, "launcher", fr)
  P.brock.directList("battle_single", variant(base, fr, "g3_single"))
  P.misty = connectPeer(OnlinePanel, imp, "MISTY#108",
    { variant(base, lg, "g3_single") }, "launcher", lg)
  joinUnion(OnlinePanel, imp, P.misty, variant(base, lg, "g3_link"), "MISTY", lg, 1)
  P.erika = connectPeer(OnlinePanel, imp, "ERIKA#111",
    { variant(base, fr, "g3_single") }, "launcher", fr)
  joinUnion(OnlinePanel, imp, P.erika, variant(base, fr, "g3_link"), "ERIKA", fr, 1)
  P.blue = connectPeer(OnlinePanel, imp, "BLUE#109",
    { variant(base, lg, "g3_single") }, "launcher", lg)
  settle(OnlinePanel, imp, 0.5)
  return P
end

local function lobbyHas(OnlinePanel, imp, n)
  return function()
    OnlinePanel.invalidate(imp, "lobby")
    OnlinePanel.refresh(imp)
    local c = OnlinePanel.cache(imp)
    return #(c.rooms or {}) >= n
  end
end

local function rowFor(OnlinePanel, imp, name)
  OnlinePanel.invalidate(imp, "lobby")
  OnlinePanel.refresh(imp)
  for _, e in ipairs(Main().lobby() or {}) do
    if e.name == name then return e end
  end
  return nil
end

local function playerRowFor(OnlinePanel, imp, name)
  OnlinePanel.invalidate(imp, "lobby")
  OnlinePanel.refresh(imp)
  for _, r in ipairs(OnlinePanel.cache(imp).players or {}) do
    if r.name == name then return r end
  end
  return nil
end

local function playList(OnlinePanel, imp, base)
  local P = seedLobby(OnlinePanel, imp, base)
  waitUntil(OnlinePanel, imp, lobbyHas(OnlinePanel, imp, 3), "lobby rows", 8)
  for _, e in ipairs(Main().lobby() or {}) do
    log("entry", tostring(e.name), tostring(e.where), tostring(e.version), tostring(e.room),
      tostring(e.locked), tostring(e.status), "online=" .. tostring(e.online))
  end
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  return P
end

local function pinTarget(OnlinePanel, imp)
  local entry = rowFor(OnlinePanel, imp, "LEAF#102")
  log("pin row", tostring(entry and entry.room), tostring(entry and entry.locked))
  return entry and OnlinePanel.targetFor(entry, "player") or nil
end

local function submitPin(OnlinePanel, imp, pin)
  local mo = OnlinePanel.pinModal(imp)
  if mo then mo.pin = "" end
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, pin)
  OnlinePanel.pinSubmit(imp)
  waitUntil(OnlinePanel, imp, function()
    local m = OnlinePanel.pinModal(imp)
    return m ~= nil and m.error ~= nil
  end, "the PIN answer", 6)
  local m = OnlinePanel.pinModal(imp)
  log("pin answer", tostring(m and m.error))
end

local STATES = {}

function STATES.play(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
end

STATES["play-gen3"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  OnlinePanel.setFilter(imp, "gen3")
end

function STATES.trainers(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  st.list = "players"
  OnlinePanel.invalidate(imp)
end

STATES["trainers-where"] = function(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  local fr, lg = "firered", "leafgreen"
  local misty = connectPeer(OnlinePanel, imp, "MISTY#108", { variant(base, lg, "g3_single") }, "launcher", lg)
  joinUnion(OnlinePanel, imp, misty, variant(base, lg, "g3_link"), "MISTY", lg, 1)
  local erika = connectPeer(OnlinePanel, imp, "ERIKA#111", { variant(base, fr, "g3_single") }, "launcher", fr)
  joinUnion(OnlinePanel, imp, erika, variant(base, fr, "g3_link"), "ERIKA", fr, 1)
  local brock = connectPeer(OnlinePanel, imp, "BROCK#107", { variant(base, fr, "g3_single") }, "launcher", fr)
  brock.directList("battle_single", variant(base, fr, "g3_single"))
  local gold = connectPeer(OnlinePanel, imp, "GOLD#103", { variant(base, lg, "g3_double") }, "launcher", lg)
  directHost(OnlinePanel, imp, gold, "battle_double", variant(base, lg, "g3_double"), nil, "GOLD", lg)
  connectPeer(OnlinePanel, imp, "BLUE#109", { variant(base, lg, "g3_single") }, "launcher", lg)
  connectPeer(OnlinePanel, imp, "SILVER#112", { variant(base, fr, "g3_single") }, "launcher", fr)
  settle(OnlinePanel, imp, 0.5)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  st.list = "players"
  OnlinePanel.setFilter(imp, "gen3")
  OnlinePanel.invalidate(imp)
end

STATES["invite-picker"] = function(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  st.list = "players"
  local row = playerRowFor(OnlinePanel, imp, "MISTY#108")
  log("picker row", tostring(row and row.name), tostring(row and row.where))
  if row then OnlinePanel.invitePickerOpen(imp, row) end
end

STATES["invite-picker-direct"] = function(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  st.list = "players"
  local row = playerRowFor(OnlinePanel, imp, "BROCK#107")
  if row then OnlinePanel.invitePickerOpen(imp, row) end
end

STATES["invite-picker-launcher"] = function(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  st.list = "players"
  local row = playerRowFor(OnlinePanel, imp, "BLUE#109")
  if row then OnlinePanel.invitePickerOpen(imp, row) end
end

function STATES.toast(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  local P = playList(OnlinePanel, imp, base)
  local me = Main().you() and Main().you().id
  P.misty.invite(me, "battle_double", { ruleset = "g3_double" },
    variant(base, "leafgreen", "g3_double"))
  waitUntil(OnlinePanel, imp, function() return OnlinePanel.toast(imp) ~= nil end,
    "the invite toast", 6)
  settle(OnlinePanel, imp, 1.2)
  log("toast", tostring(OnlinePanel.toast(imp) and OnlinePanel.inviteLine(OnlinePanel.toast(imp))))
end

function STATES.pin(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  local target = pinTarget(OnlinePanel, imp)
  if target then OnlinePanel.startJoin(imp, target) end
  OnlinePanel.fieldType(imp, OnlinePanel.PIN_FIELD, "04")
end

STATES["pin-wrong"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  local target = pinTarget(OnlinePanel, imp)
  if target then OnlinePanel.startJoin(imp, target) end
  submitPin(OnlinePanel, imp, "1111")
end

STATES["pin-locked"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  playList(OnlinePanel, imp, base)
  local target = pinTarget(OnlinePanel, imp)
  if target then OnlinePanel.startJoin(imp, target) end
  for i = 1, 5 do submitPin(OnlinePanel, imp, ("%04d"):format(1110 + i)) end
end

STATES["host-private"] = function(OnlinePanel, imp)
  local st = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.startWizard(imp, "hostBattle")
  OnlinePanel.wizardTo(imp, "visibility")
  st.private = true
  OnlinePanel.fieldType(imp, OnlinePanel.HOST_PIN_FIELD or "online-host-pin", "0427")
  if st.pin ~= "0427" then st.pin = "0427" end
end

STATES["host-format"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, "firered", 3, "g3_double")
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.startWizard(imp, "hostBattle")
  OnlinePanel.wizardTo(imp, "format")
end

STATES["host-format-multi"] = function(OnlinePanel, imp)
  goOnline(OnlinePanel, imp, "firered", 3, "g3_multi")
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.startWizard(imp, "hostBattle")
  OnlinePanel.wizardTo(imp, "format")
end

function STATES.room(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  st.private, st.pin = true, "0427"
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.hostBattle(imp)
  waitUntil(OnlinePanel, imp, function() return Main().room() ~= nil end, "the panel room", 8)
  local room = Main().room()
  local guest = connectPeer(OnlinePanel, imp, "LEAF#102",
    { variant(base, "leafgreen", "g3_single") }, "union", "leafgreen")
  local spec = connectPeer(OnlinePanel, imp, "MISTY#108",
    { variant(base, "leafgreen", "g3_single") }, "launcher", "leafgreen")
  if room then
    local s = spec.joinRoom(room.room, "spectator", variant(base, "leafgreen", "g3_single"), "0427")
    waitUntil(OnlinePanel, imp, function() return s.done end, "the spectator", 6)
    log("spectator", tostring(s.error))
  end
  settle(OnlinePanel, imp, 0.3)
  OnlinePanel.go(imp, "room")
  log("room", tostring(room and room.room), tostring(room and room.locked), tostring(guest.state()))
end

STATES["room-multi"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_multi")
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.hostBattle(imp)
  waitUntil(OnlinePanel, imp, function() return Main().room() ~= nil end, "the multi room", 8)
  local room = Main().room()
  log("multi seats", tostring(room and room.seats))
  for _, who in ipairs({ { "LEAF#102", "leafgreen", "union" }, { "GOLD#103", "firered", "direct" } }) do
    local C = connectPeer(OnlinePanel, imp, who[1],
      { variant(base, who[2], "g3_multi") }, who[3], who[2])
    if room then
      local j = C.joinRoom(room.room, "player", variant(base, who[2], "g3_multi"))
      waitUntil(OnlinePanel, imp, function() return j.done end, who[1] .. " joins", 6)
    end
  end
  waitUntil(OnlinePanel, imp, function()
    local r = Main().room()
    return r and #(r.players or {}) >= 3
  end, "three seats taken", 6)
  OnlinePanel.go(imp, "room")
end

function STATES.watch(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  local host = connectPeer(OnlinePanel, imp, "STEVEN#111",
    { variant(base, "leafgreen", "g3_multi") }, "union", "leafgreen")
  local id = hostRoom(OnlinePanel, imp, host, { intent = "battle",
    profile = variant(base, "leafgreen", "g3_multi"), playing = true, maxSpectators = 8,
    private = false, seats = 4, auto = false })
  local seatNames = { { "WALLACE#112", "firered" }, { "GLACIA#113", "leafgreen" },
    { "DRAKE#114", "firered" } }
  for _, who in ipairs(seatNames) do
    local C = connectPeer(OnlinePanel, imp, who[1],
      { variant(base, who[2], "g3_multi") }, "direct", who[2])
    if id then
      local j = C.joinRoom(id, "player", variant(base, who[2], "g3_multi"))
      waitUntil(OnlinePanel, imp, function() return j.done end, who[1] .. " joins", 6)
    end
  end
  local blaine = connectPeer(OnlinePanel, imp, "BLAINE#115",
    { variant(base, "firered", "g3_double") }, "launcher", "firered")
  local id2 = hostRoom(OnlinePanel, imp, blaine, { intent = "battle",
    profile = variant(base, "firered", "g3_double"), playing = true, maxSpectators = 8,
    private = false, seats = 2, auto = false })
  local sabrina = connectPeer(OnlinePanel, imp, "SABRINA#116",
    { variant(base, "leafgreen", "g3_double") }, "union", "leafgreen")
  if id2 then
    local j = sabrina.joinRoom(id2, "player", variant(base, "leafgreen", "g3_double"))
    waitUntil(OnlinePanel, imp, function() return j.done end, "sabrina joins", 6)
  end
  waitUntil(OnlinePanel, imp, function()
    OnlinePanel.invalidate(imp, "lobby")
    OnlinePanel.refresh(imp)
    return #(OnlinePanel.cache(imp).watch or {}) >= 2
  end, "two watchable battles", 8)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "watch")
end

local function tradePair(OnlinePanel, imp, version, peerVersion, ruleset)
  local st, base = goOnline(OnlinePanel, imp, version, 1, nil)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "trade")
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "remote", true
  OnlinePanel.hostTrade(imp)
  waitUntil(OnlinePanel, imp, function() return Main().room() ~= nil end, "the trade room", 8)
  local room = Main().room()
  local peerProfile = variant(base, peerVersion, ruleset or (base and base.rulesetId), 3)
  if room and room.profile then
    peerProfile = copy(room.profile)
    peerProfile.version = peerVersion
  end
  local partner = connectPeer(OnlinePanel, imp, "LEAF#102", { peerProfile }, "launcher", peerVersion)
  local j = partner.joinRoom(room and room.room, "player", peerProfile)
  waitUntil(OnlinePanel, imp, function() return j.done end, "the partner joins", 6)
  log("partner join", tostring(j.error))
  local Trade = require("src.online.Trade")
  local handle, why = Trade.openSlot(peerVersion, "slot1", nil)
  log("partner handle", tostring(handle and #handle.party), tostring(why))
  local peer
  if handle and require("src.core.GameVersion").generation(peerVersion) ~= 3 then
    local Protocol = require("src.link.Protocol")
    partner.ready(Protocol.packParty({ handle.party[1] }), "final-peer")
    waitUntil(OnlinePanel, imp, function()
      local r = partner.room()
      return r and r.stage ~= "waiting" and r.stage ~= "ready"
    end, "the gen 1 trade to start", 8)
  end
  waitUntil(OnlinePanel, imp, function() return partner.roomSession() ~= nil end, "partner session", 6)
  if handle and partner.roomSession() then
    local err
    peer, err = Trade.remote(handle, partner.roomSession(), { peerName = "RED", strict = true })
    log("partner remote", tostring(peer ~= nil), tostring(err))
    if peer then
      hooks[#hooks + 1] = function() peer:update(1 / 60) end
      peer:start()
    end
  end
  waitUntil(OnlinePanel, imp, function()
    return tr.remote and tr.remote:stage() == "picking" and peer and peer:stage() == "picking"
  end, "both trade menus", 10)
  log("stages", tostring(tr.remote and tr.remote:stage()), tostring(peer and peer:stage()),
    tostring(tr.remoteError))
  return st, tr, peer
end

STATES["trade-picking"] = function(OnlinePanel, imp)
  tradePair(OnlinePanel, imp, "firered", "leafgreen")
end

STATES["trade-confirm"] = function(OnlinePanel, imp)
  local _, tr, peer = tradePair(OnlinePanel, imp, "firered", "leafgreen")
  OnlinePanel.remotePick(imp, 4)
  if peer then peer:pick(1) end
  waitUntil(OnlinePanel, imp, function()
    return tr.remote and tr.remote:stage() == "confirming" and peer and peer:stage() == "confirming"
  end, "both confirm prompts", 8)
end

STATES["trade-done"] = function(OnlinePanel, imp)
  local st, tr, peer = tradePair(OnlinePanel, imp, "firered", "leafgreen")
  OnlinePanel.remotePick(imp, 4)
  if peer then peer:pick(1) end
  waitUntil(OnlinePanel, imp, function()
    return tr.remote and tr.remote:stage() == "confirming" and peer and peer:stage() == "confirming"
  end, "both confirm prompts", 8)
  OnlinePanel.remoteConfirm(imp, true)
  if peer then peer:confirm(true) end
  waitUntil(OnlinePanel, imp, function()
    return st.status == "Trade complete." or tr.remoteResult ~= nil
  end, "the trade commit", 10)
  log("trade", tostring(st.status), tostring(tr.remoteResult), tostring(peer and peer:stage()))
end

STATES["tour-code"] = function(OnlinePanel, imp)
  local st, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  st.tourPublic = false
  st.tourPlaying = true
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.hostTournament(imp)
  waitUntil(OnlinePanel, imp, function() return Main().tournament() ~= nil end,
    "the private tournament", 8)
  local tour = Main().tournament()
  log("tour code", tostring(tour and tour.code))
  if tour and tour.code then
    for _, who in ipairs({ { "LEAF#102", "leafgreen" }, { "BROCK#107", "firered" } }) do
      local C = connectPeer(OnlinePanel, imp, who[1], { variant(base, who[2], "g3_single") },
        "launcher", who[2])
      local j = C.joinTournament({ code = tour.code, as = "spectator",
        profile = variant(base, who[2], "g3_single") })
      waitUntil(OnlinePanel, imp, function() return j.done end, who[1] .. " joins", 6)
    end
  end
  OnlinePanel.go(imp, "tournament")
end

STATES["tour-join"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "firered", 3, "g3_single")
  local org = connectPeer(OnlinePanel, imp, "LEAF#102",
    { variant(base, "leafgreen", "g3_single") }, "launcher", "leafgreen")
  local made = org.createTournament({ profile = variant(base, "leafgreen", "g3_single"),
    rule = { partySize = 3 }, playing = false, shotClock = 6, maxSpectators = 8,
    public = false })
  waitUntil(OnlinePanel, imp, function() return made.done end, "the peer tournament", 8)
  local code = org.tournament() and org.tournament().code
  log("peer tour code", tostring(code))
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "tournament")
  if code then
    imp._onlineFocus = OnlinePanel.TOUR_CODE_FIELD
    OnlinePanel.fieldType(imp, OnlinePanel.TOUR_CODE_FIELD, code:lower())
  end
end

function STATES.upgrade(OnlinePanel, imp)
  local st = setup(OnlinePanel, imp, "firered", 3)
  waitUntil(OnlinePanel, imp, function() return OnlinePanel.myProfile(imp) ~= nil end,
    "the panel profile", 20)
  local Protocol2 = require("src.online.Protocol2")
  local was = Protocol2.PROTOCOL
  Protocol2.PROTOCOL = 2
  OnlinePanel.connect(imp)
  Protocol2.PROTOCOL = was
  waitUntil(OnlinePanel, imp, function() return Main().upgradeRequired() ~= nil end,
    "upgrade_required", 8)
  log("upgrade", tostring(Main().state()), tostring(Main().error()), tostring(st.status))
  OnlinePanel.home(imp)
end

STATES["g1-play"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "red", 1, nil)
  if not base then return end
  local blue = connectPeer(OnlinePanel, imp, "BLUE#221", { copy(base) }, "launcher", "red")
  hostRoom(OnlinePanel, imp, blue, { intent = "battle", profile = copy(base), playing = true,
    maxSpectators = 4, private = false, seats = 2, auto = false, note = "first to three" })
  local green = connectPeer(OnlinePanel, imp, "GREEN#009", { copy(base) }, "launcher", "red")
  hostRoom(OnlinePanel, imp, green, { intent = "trade", profile = copy(base), playing = true,
    maxSpectators = 0, private = false, seats = 2, auto = false })
  waitUntil(OnlinePanel, imp, lobbyHas(OnlinePanel, imp, 2), "gen 1 rows", 8)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
end

STATES["g1-join"] = function(OnlinePanel, imp)
  local _, base = goOnline(OnlinePanel, imp, "red", 1, nil)
  if not base then return end
  local blue = connectPeer(OnlinePanel, imp, "BLUE#221", { copy(base) }, "launcher", "red")
  local id = hostRoom(OnlinePanel, imp, blue, { intent = "battle", profile = copy(base),
    playing = true, maxSpectators = 4, private = false, seats = 2, auto = false })
  waitUntil(OnlinePanel, imp, lobbyHas(OnlinePanel, imp, 1), "gen 1 row", 8)
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  local entry = rowFor(OnlinePanel, imp, "BLUE#221")
  if entry then
    OnlinePanel.startJoin(imp, OnlinePanel.targetFor(entry, "player"))
    local st = OnlinePanel.state(imp)
    if st.wizard then
      OnlinePanel.wizardTo(imp, "summary")
      OnlinePanel.wizardNext(imp)
    end
  end
  waitUntil(OnlinePanel, imp, function()
    local r = Main().room()
    return r and r.room == id and #(r.players or {}) == 2
  end, "the gen 1 room", 8)
  log("g1 room", tostring(Main().room() and Main().room().room), tostring(id))
  OnlinePanel.go(imp, "room")
end

STATES["g1-trade"] = function(OnlinePanel, imp)
  local _, tr, peer = tradePair(OnlinePanel, imp, "red", "red")
  OnlinePanel.remotePick(imp, 1)
  if peer then peer:pick(1) end
  waitUntil(OnlinePanel, imp, function()
    return tr.remote and tr.remote:stage() == "confirming" and peer and peer:stage() == "confirming"
  end, "both confirm prompts", 8)
end

return function(OnlinePanel, imp, want)
  require("src.ui.kit.Transition").reduceMotion = true
  hookUpdate(OnlinePanel)
  local run = STATES[want]
  if not run then
    log("unknown state", tostring(want))
    return
  end
  local ok, err = xpcall(function() run(OnlinePanel, imp) end, debug.traceback)
  if not ok then log("ERROR", tostring(err)) end
  settle(OnlinePanel, imp, 0.3)
  log("screen", tostring(OnlinePanel.screen(imp)), "status", tostring(OnlinePanel.state(imp).status))
end

local function Client()
  return require("src.online.Client")
end

local PROFILE = {
  engine = 3, version = "firered", engineVersion = "1.2.3", apiVersion = 4,
  fingerprint = "shot", rulesetId = "g3_single", kind = "vanilla",
  rule = { partySize = 3 },
}

local NAMES = { "RED", "BLUE", "GREEN", "LEAF", "ETHAN", "LYRA", "SILVER",
                "KRIS", "GOLD", "MAY", "BRENDAN", "WALLY" }
local WHERE = { "launcher", "union", "direct", "launcher", "game", "union" }
local VERSIONS = { "firered", "leafgreen", "red", "firered", "leafgreen" }

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function fakeLobby(count)
  local rows = {}
  for i = 1, count do
    local profile = copy(PROFILE)
    profile.version = VERSIONS[((i - 1) % #VERSIONS) + 1]
    if profile.version == "red" then
      profile.engine, profile.rulesetId = 1, "gen1_faithful"
    end
    local tour = i % 9 == 0
    local where = WHERE[((i - 1) % #WHERE) + 1]
    if profile.engine ~= 3 and (where == "union" or where == "direct") then
      where = "launcher"
    end
    rows[i] = {
      id = ("%08x"):format(0x1000 + i),
      name = NAMES[((i - 1) % #NAMES) + 1] .. "#" .. (100 + i),
      verified = i % 3 == 0,
      online = true,
      where = where,
      status = (i % 5 == 0) and "battling" or "idle",
      engine = profile.engine,
      version = profile.version,
      open = true,
      room = (not tour) and ("r%016x"):format(i) or nil,
      tour = tour and ("t%016x"):format(i) or nil,
      locked = (not tour) and (i % 3 == 1),
      intent = tour and "tournament" or "battle",
      note = (i % 4 == 0) and "first to three" or nil,
      spectators = i % 4,
      players = 1, seats = 2,
      profile = profile,
      stage = (i % 6 == 0) and "battling" or "waiting",
    }
  end
  return rows
end

local ROOM = {
  room = "r00000000000000aa", host = "me", stage = "waiting",
  intent = "battle", locked = true, listed = true, seats = 2,
  origin = "create", profile = PROFILE,
  players = {
    { id = "me", name = "RED#417", verified = true, ready = true, seat = 0 },
    { id = "00001003", name = "GREEN#103", ready = false, seat = 1 },
  },
  spectators = { { id = "00001004", name = "LEAF#104" } },
}

local TOUR = {
  tour = "t00000000000000aa", code = "TQ2RA3", creator = "me",
  stage = "registering", shotClock = 6, profile = PROFILE,
  rule = { partySize = 3 },
  players = {
    { id = "me", name = "RED#417", verified = true, online = true },
    { id = "00001002", name = "BLUE#102", online = true },
    { id = "00001005", name = "LEAF#105", online = true },
  },
  spectators = {}, bracket = {},
}

local function goOnline(OnlinePanel, imp, opts)
  opts = opts or {}
  local client = Client()
  local lobby = fakeLobby(opts.count or 14)
  local room, tour = opts.room, opts.tour
  client.state = function() return "online" end
  client.you = function() return { id = "me", name = "RED#417", verified = true } end
  client.serverTime = function() return 100000 end
  client.lobby = function() return lobby end
  client.openRooms = function()
    local out = {}
    for _, e in ipairs(lobby) do
      if e.stage == "waiting" then out[#out + 1] = e end
    end
    return out
  end
  client.watchable = function()
    local out = {}
    for _, e in ipairs(lobby) do
      if e.stage == "battling" or e.tour then out[#out + 1] = e end
    end
    return out
  end
  client.counts = function() return { players = #lobby + 1, openRooms = #lobby } end
  client.room = function() return room end
  client.tournament = function() return tour end
  client.setProfiles = function(list) return list end
  client.setPresence = function() return true end
  client.inviteToken = function() return true end
  client.invites = function() return {} end
  client.upgradeRequired = function() return opts.upgrade end
  client.joinRoom = function(id) return { id = id, done = false } end
  client.invite = function(to, activity)
    return { to = to, activity = activity, state = "sending" }
  end
  client.replyInvite = function() return true end
  local st = OnlinePanel.state(imp)
  st.version, st.kind, st.cartId = "firered", "vanilla", nil
  st.slotId, st.setupDone = "slot1", true
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 } }
  st.profiles["firered|vanilla|-"] = { profile = copy(PROFILE) }
  st.name = "RED#417"
  OnlinePanel.invalidate(imp)
  return st
end

return function(OnlinePanel, imp, want)
  if want == "play-locked" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
  elseif want == "trainers" then
    local st = goOnline(OnlinePanel, imp)
    st.list = "players"
    OnlinePanel.go(imp, "play")
  elseif want == "invite-picker" then
    local st = goOnline(OnlinePanel, imp)
    st.list = "players"
    OnlinePanel.go(imp, "play")
    OnlinePanel.invitePickerOpen(imp, { id = "00001002", name = "BLUE#102",
      engine = 3, version = "leafgreen", game = "LeafGreen",
      where = "Union Room", place = "union" })
  elseif want == "pin" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
    OnlinePanel.pinOpen(imp, { room = "r0000000000000001", locked = true,
      name = "RED#101", as = "player" })
    imp._pinModal.pin = "04"
  elseif want == "pin-wrong" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
    OnlinePanel.pinOpen(imp, { room = "r0000000000000001", locked = true,
      name = "RED#101", as = "player" },
      "That PIN didn't match. 3 tries left.")
    imp._pinModal.pin = "0427"
  elseif want == "pin-locked" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
    local target = { room = "r0000000000000001", locked = true,
      name = "RED#101", as = "player" }
    OnlinePanel.pinOpen(imp, target)
    OnlinePanel.pinFailed(imp, { reason = "pin_locked", retryAt = 100000 + 540000,
      pinTarget = target })
  elseif want == "toast" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
    OnlinePanel.inviteIn(imp, { id = "i00000000000000a1",
      activity = "battle_single",
      from = { id = "00001002", name = "BLUE#102", where = "union" },
      detail = { ruleset = "g3_single" }, expiresAt = 100000 + 14000 })
  elseif want == "toast-mods" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.inviteIn(imp, { id = "i00000000000000a2", activity = "trade",
      from = { id = "00001003", name = "GREEN#103", where = "launcher" },
      detail = {}, expiresAt = 100000 + 17000 })
  elseif want == "host-private" then
    local st = goOnline(OnlinePanel, imp)
    OnlinePanel.startWizard(imp, "hostBattle")
    st.private, st.pin = true, "0427"
    OnlinePanel.wizardTo(imp, "visibility")
  elseif want == "trade-private" then
    local st = goOnline(OnlinePanel, imp)
    st.tradeRole = "host"
    OnlinePanel.startWizard(imp, "tradeRemote")
    st.private, st.pin = true, "0427"
    OnlinePanel.wizardTo(imp, "visibility")
  elseif want == "room-players" then
    goOnline(OnlinePanel, imp, { room = ROOM })
    OnlinePanel.go(imp, "play")
    OnlinePanel.go(imp, "room")
  elseif want == "tour-code" then
    goOnline(OnlinePanel, imp, { tour = TOUR })
    OnlinePanel.go(imp, "play")
    OnlinePanel.go(imp, "tournament")
  elseif want == "tour-lobby" then
    local st = goOnline(OnlinePanel, imp)
    st.tourCode = "TQ2RA3"
    OnlinePanel.go(imp, "play")
    OnlinePanel.go(imp, "tournament")
  elseif want == "watch" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "watch")
  elseif want == "upgrade" then
    goOnline(OnlinePanel, imp, { upgrade = {
      text = "This build is too old for online play. Please update." } })
    Client().state = function() return "error" end
  end
end

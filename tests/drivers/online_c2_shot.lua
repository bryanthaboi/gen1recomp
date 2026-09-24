local function Client()
  return require("src.online.Client")
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local BASE = {
  engine = 3, version = "firered", engineVersion = "1.2.3", apiVersion = 4,
  fingerprint = "shot", rulesetId = "g3_single", kind = "vanilla",
  rule = { partySize = 3 },
}

local function profile(version, ruleset, size)
  local p = copy(BASE)
  p.version, p.rulesetId, p.rule = version, ruleset, { partySize = size or 3 }
  return p
end

local ROWS = {
  { "LEAF#102", "leafgreen", "union", "g3_double", 1, 2, "battle", false },
  { "GOLD#103", "firered", "direct", "g3_multi", 2, 4, "battle", false },
  { "MAY#104", "firered", "launcher", "g3_link", 1, 2, "trade", false },
  { "KRIS#105", "leafgreen", "direct", "g3_single", 1, 2, "battle", true },
  { "ETHAN#106", "firered", "launcher", "g3_single", 1, 2, "battle", false },
  { "LYRA#107", "leafgreen", "union", "g3_multi", 3, 4, "battle", false },
  { "WALLY#108", "firered", "launcher", "g3_double", 1, 2, "battle", true },
  { "BRENDAN#109", "leafgreen", "direct", "g3_link", 1, 2, "trade", false },
  { "SILVER#110", "firered", "union", "g3_single", 1, 2, "battle", false },
}

local function fakeLobby()
  local rows = {}
  for i, r in ipairs(ROWS) do
    rows[#rows + 1] = {
      id = ("%08x"):format(0x2000 + i), name = r[1], verified = i % 3 == 0,
      online = true, where = r[3], status = "idle", engine = 3, version = r[2],
      open = true, room = ("r%016x"):format(0x2000 + i), locked = r[8],
      intent = r[7], spectators = i % 3, maxSpectators = 8, players = r[5],
      seats = r[6], profile = profile(r[2], r[4], 3), stage = "waiting",
      note = (i == 1) and "doubles, no legends" or nil,
    }
  end
  rows[#rows + 1] = { id = "00002101", name = "STEVEN#111", online = true,
    where = "union", status = "battling", engine = 3, version = "leafgreen",
    room = "r0000000000002101", intent = "battle", spectators = 2, maxSpectators = 8,
    players = 4, seats = 4, profile = profile("leafgreen", "g3_multi", 3),
    stage = "battling" }
  rows[#rows + 1] = { id = "00002102", name = "BLAINE#112", online = true,
    where = "launcher", status = "battling", engine = 3, version = "firered",
    room = "r0000000000002102", intent = "battle", spectators = 1, maxSpectators = 8,
    players = 2, seats = 2, profile = profile("firered", "g3_double", 3),
    stage = "battling" }
  rows[#rows + 1] = { id = "00002103", name = "KOGA#113", online = true,
    where = "game", status = "busy", engine = 3, version = "firered" }
  rows[#rows + 1] = { id = "00002104", name = "MISTY#114", online = true,
    where = "union", status = "idle", engine = 3, version = "leafgreen" }
  rows[#rows + 1] = { id = "00002105", name = "BROCK#115", online = true,
    where = "direct", status = "idle", engine = 3, version = "firered" }
  return rows
end

local PARTY = {
  { species = 6, level = 52, nickname = "BLAZE", hp = 160, maxHp = 160 },
  { species = 9, level = 50, nickname = "SHELL", hp = 158, maxHp = 158 },
  { species = 3, level = 51, nickname = "IVY", hp = 162, maxHp = 162 },
  { species = 25, level = 40, nickname = "SPARKY", hp = 90, maxHp = 90 },
  { species = 65, level = 45, nickname = "SPOON", hp = 120, maxHp = 120 },
  { species = 143, level = 48, nickname = "SNORE", hp = 250, maxHp = 250 },
}

local THEIRS = {
  { species = 94, level = 49, nickname = "GENGAR" },
  { species = 131, level = 44, nickname = "NESSIE" },
  { species = 59, level = 47, nickname = "ARCANINE" },
}

local function goOnline(OnlinePanel, imp, opts)
  opts = opts or {}
  local client = Client()
  local lobby = fakeLobby()
  local room, tour = opts.room, opts.tour
  client.state = function() return "online" end
  client.you = function() return { id = "me", name = "RED#417", verified = true } end
  client.serverTime = function() return 100000 end
  client.lobby = function() return lobby end
  client.openRooms = function()
    local out = {}
    for _, e in ipairs(lobby) do
      if e.room and e.stage == "waiting" then out[#out + 1] = e end
    end
    return out
  end
  client.watchable = function()
    local out = {}
    for _, e in ipairs(lobby) do if e.stage == "battling" then out[#out + 1] = e end end
    return out
  end
  client.counts = function() return { players = #lobby + 1, openRooms = 9 } end
  client.room = function() return room end
  client.tournament = function() return tour end
  client.setProfiles = function(list) return list end
  client.setPresence = function() return true end
  client.inviteToken = function() return true end
  client.invites = function() return {} end
  client.upgradeRequired = function() return nil end
  client.joinRoom = function(id) return { id = id, done = false } end
  client.replyInvite = function() return true end
  client.roomSession = function() return nil end
  local st = OnlinePanel.state(imp)
  st.version, st.kind, st.cartId = "firered", "vanilla", nil
  st.slotId, st.setupDone = "slot1", true
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 } }
  st.profiles["firered|vanilla|-"] = { profile = copy(BASE) }
  st.slotRead = { key = "firered|slot1|-",
    data = { generation = 3, party = PARTY, save = { party = PARTY } } }
  st.name = "RED#417"
  st.ruleset = opts.ruleset
  OnlinePanel.invalidate(imp)
  return st
end

local MULTI_ROOM = {
  room = "r00000000000000bb", host = "me", stage = "waiting", intent = "battle",
  engine = 3, locked = false, listed = true, seats = 4, origin = "create",
  profile = profile("firered", "g3_multi", 3),
  players = {
    { id = "me", name = "RED#417", verified = true, seat = 0, online = true },
    { id = "00002102", name = "LEAF#102", seat = 1, online = true },
    { id = "00002103", name = "GOLD#103", seat = 2, online = true },
  },
  spectators = { { id = "00002104", name = "MISTY#114" } },
}

local TOUR = {
  tour = "t00000000000000bb", creator = "me", stage = "registering", shotClock = 6,
  profile = profile("firered", "g3_double", 3), rule = { partySize = 3 },
  players = {
    { id = "me", name = "RED#417", verified = true, online = true },
    { id = "00002102", name = "LEAF#102", online = true },
    { id = "00002105", name = "BROCK#115", online = true },
  },
  spectators = {}, bracket = {},
}

local function remoteStub(stage)
  local handle = { path = "shot", version = "firered", generation = 3, party = PARTY }
  local session = { theirParty = THEIRS, peerName = "LEAF#102", myPick = 1,
    theirPick = stage == "confirming" and 1 or nil }
  return {
    handle = handle, session = session,
    stage = function() return stage end,
    update = function() return stage end,
    canPick = function(_, index) return index ~= 5 end,
    pick = function() return true end,
    confirm = function() return true end,
    cancelPick = function() return true end,
    close = function() end,
  }
end

return function(OnlinePanel, imp, want)
  if want == "g3-play" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
  elseif want == "g3-trainers" then
    local st = goOnline(OnlinePanel, imp)
    st.list = "players"
    st.filter = "gen3"
    OnlinePanel.go(imp, "play")
  elseif want == "g3-format" then
    goOnline(OnlinePanel, imp, { ruleset = "g3_double" })
    OnlinePanel.startWizard(imp, "hostBattle")
    OnlinePanel.wizardTo(imp, "format")
  elseif want == "g3-format-multi" then
    goOnline(OnlinePanel, imp, { ruleset = "g3_multi" })
    OnlinePanel.startWizard(imp, "hostBattle")
    OnlinePanel.wizardTo(imp, "format")
  elseif want == "g3-room-multi" then
    goOnline(OnlinePanel, imp, { room = MULTI_ROOM, ruleset = "g3_multi" })
    OnlinePanel.go(imp, "play")
    OnlinePanel.go(imp, "room")
  elseif want == "g3-watch" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "watch")
  elseif want == "g3-trade-pick" or want == "g3-trade-confirm" then
    goOnline(OnlinePanel, imp)
    local tr = OnlinePanel.tradeState(imp)
    tr.mode, tr.chosen = "remote", true
    tr.remote = remoteStub(want == "g3-trade-confirm" and "confirming" or "picking")
    tr.peerName = "LEAF#102"
    local Sprites = require("src.online.OnlineSprites")
    Sprites.prime("firered", PARTY)
    Sprites.prime("firered", THEIRS)
    OnlinePanel.go(imp, "trade")
  elseif want == "g3-toast" then
    goOnline(OnlinePanel, imp)
    OnlinePanel.go(imp, "play")
    OnlinePanel.inviteIn(imp, { id = "i00000000000000c1", activity = "battle_double",
      from = { id = "00002104", name = "MISTY#114", where = "union",
               avatar = { name = "MISTY", trainerId = 4104, gender = 1,
                          version = "leafgreen" } },
      detail = { ruleset = "g3_double" }, expiresAt = 100000 + 15000 })
  elseif want == "g3-invite-picker" then
    local st = goOnline(OnlinePanel, imp)
    st.list = "players"
    OnlinePanel.go(imp, "play")
    OnlinePanel.invitePickerOpen(imp, { id = "00002105", name = "BROCK#115",
      engine = 3, version = "firered", game = "FireRed", where = "Direct Corner",
      place = "direct" })
  elseif want == "g3-tour" then
    goOnline(OnlinePanel, imp, { tour = TOUR, ruleset = "g3_double" })
    OnlinePanel.go(imp, "play")
    OnlinePanel.go(imp, "tournament")
  end
end

local Wire = {}

local MAX_INT = 2147483647
local MAX_STRING = 64
local MAX_DETAIL = 160
local MAX_NAME = 40
local MAX_LIST = 64
local MAX_PARTY = 32
local MAX_MOVES = 8
local MAX_MODS = 256
local MAX_RECORDS = 4096
local MAX_EXTRA_DEPTH = 8
local MAX_ROUNDS = 16
local MAX_MATCHES = 128

function Wire.num(v, default, min, max)
  local n = tonumber(v)
  if n == nil or n ~= n then return default end
  min = min or -MAX_INT
  max = max or MAX_INT
  if n < min then return min end
  if n > max then return max end
  return math.floor(n)
end

function Wire.str(v, default, maxLen)
  if type(v) ~= "string" then return default end
  maxLen = maxLen or MAX_STRING
  if #v > maxLen then return v:sub(1, maxLen) end
  return v
end

function Wire.bool(v, default)
  if type(v) == "boolean" then return v end
  return default
end

function Wire.list(v, maxN, fn)
  local out = {}
  if type(v) ~= "table" then return out end
  local n = math.min(#v, maxN or MAX_LIST)
  for i = 1, n do
    local entry = fn(v[i])
    if entry ~= nil then out[#out + 1] = entry end
  end
  return out
end

function Wire.records(v)
  local out = {}
  if type(v) ~= "table" then return out end
  local n = 0
  for k, val in pairs(v) do
    if type(k) == "string" then
      out[k] = Wire.str(val, nil, MAX_STRING) or tostring(Wire.num(val, 0))
      n = n + 1
      if n >= MAX_RECORDS then break end
    end
  end
  return out
end

function Wire.plain(v, depth)
  if type(v) ~= "table" then return nil end
  depth = depth or 0
  if depth > MAX_EXTRA_DEPTH then return nil end
  local out = {}
  for k, val in pairs(v) do
    local kt, vt = type(k), type(val)
    if kt == "string" or kt == "number" then
      if vt == "string" then out[k] = Wire.str(val, nil, MAX_STRING)
      elseif vt == "number" or vt == "boolean" then out[k] = val
      elseif vt == "table" then out[k] = Wire.plain(val, depth + 1) end
    end
  end
  return out
end

local STAT_KEYS = { "hp", "attack", "defense", "speed", "special" }

local function statMap(v)
  local out = {}
  if type(v) ~= "table" then return out end
  for _, k in ipairs(STAT_KEYS) do
    out[k] = Wire.num(v[k], nil, 0, 65535)
  end
  return out
end

local function move(v)
  if type(v) ~= "table" then return { id = nil } end
  return {
    id = Wire.str(v.id, nil, MAX_STRING),
    pp = Wire.num(v.pp, nil, 0, 255),
    ppUps = Wire.num(v.ppUps, nil, 0, 255),
    maxPp = Wire.num(v.maxPp, nil, 0, 255),
  }
end

local function mon(v)
  if type(v) ~= "table" then return {} end
  return {
    species = Wire.str(v.species, nil, MAX_STRING),
    level = Wire.num(v.level, nil, 0, 65535),
    exp = Wire.num(v.exp, nil, 0, MAX_INT),
    experience = Wire.num(v.experience, nil, 0, MAX_INT),
    hp = Wire.num(v.hp, nil, 0, 65535),
    status = Wire.str(v.status, nil, MAX_STRING),
    nickname = Wire.str(v.nickname, nil, MAX_NAME),
    dvs = statMap(v.dvs),
    statExp = statMap(v.statExp),
    moves = Wire.list(v.moves, MAX_MOVES, move),
    ot = Wire.str(v.ot, nil, MAX_NAME),
    otId = Wire.num(v.otId, nil, 0, MAX_INT),
    item = Wire.str(v.item, nil, MAX_STRING),
    happiness = Wire.num(v.happiness, nil, 0, 65535),
    pokerus = Wire.num(v.pokerus, nil, 0, 65535),
    caughtLevel = Wire.num(v.caughtLevel, nil, 0, 65535),
    -- ../pokecrystal/constants/pokemon_data_constants.asm:93-99
    caughtTime = Wire.num(v.caughtTime, nil, 0, 255),
    caughtLocation = Wire.num(v.caughtLocation, nil, 0, 255),
    caughtByGender = Wire.str(v.caughtByGender, nil, MAX_NAME),
    isEgg = Wire.bool(v.isEgg, nil),
    eggSteps = Wire.num(v.eggSteps, nil, 0, MAX_INT),
    extra = Wire.plain(v.extra),
  }
end

local function modEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    version = Wire.str(v.version, nil, MAX_NAME)
      or Wire.num(v.version, nil, 0, MAX_INT),
    affectsLink = Wire.bool(v.affectsLink, nil),
    language = Wire.bool(v.language, nil),
  }
end

local function name(v)
  return Wire.str(v, nil, MAX_NAME)
end

local sanitize
local arenaStart

local SCHEMAS = {}

SCHEMAS.hello = function(m)
  return {
    protocol = Wire.num(m.protocol, nil, 0, MAX_INT),
    name = name(m.name),
    mode = Wire.str(m.mode, nil, MAX_STRING),
    engineVersion = Wire.str(m.engineVersion, nil, MAX_STRING),
    apiVersion = Wire.str(m.apiVersion, nil, MAX_STRING),
    generation = Wire.num(m.generation, nil, 0, 255),
    fingerprint = Wire.str(m.fingerprint, nil, MAX_STRING),
    linkModified = Wire.bool(m.linkModified, nil),
    ruleset = Wire.str(m.ruleset, nil, MAX_STRING),
    mods = Wire.list(m.mods, MAX_MODS, modEntry),
  }
end

SCHEMAS.records = function(m)
  return {
    pokemon = Wire.records(m.pokemon),
    moves = Wire.records(m.moves),
    heldItems = m.heldItems ~= nil and Wire.records(m.heldItems) or nil,
  }
end

SCHEMAS.party = function(m)
  return {
    mons = Wire.list(m.mons, MAX_PARTY, mon),
    seed = Wire.num(m.seed, nil, 0, MAX_INT),
    forceLevel = Wire.num(m.forceLevel, nil, 0, 65535),
    ruleset = Wire.str(m.ruleset, nil, MAX_STRING),
  }
end

SCHEMAS.pick = function(m)
  return { index = Wire.num(m.index, nil, -MAX_INT, MAX_INT) }
end

SCHEMAS.confirm = function(m)
  return { ok = Wire.bool(m.ok, false) }
end

SCHEMAS.action = function(m)
  return {
    kind = Wire.str(m.kind, "", MAX_STRING),
    slot = Wire.num(m.slot, nil, 1, MAX_MOVES),
    index = Wire.num(m.index, nil, 1, MAX_PARTY),
    -- an ITEM action (RFC 0021) is the turn, and the peer cannot apply
    -- one it cannot name: the item id, and for the ETHERs the move slot.
    -- Dropped here, the action still arrives and still spends the turn,
    -- so the two sides diverge by a heal with nothing on screen to say
    -- so -- the quietest desync there is.
    item = Wire.str(m.item, nil, MAX_STRING),
    move = Wire.num(m.move, nil, 1, MAX_MOVES),
  }
end

SCHEMAS.hash = function(m)
  local parts
  if type(m.parts) == "table" then
    parts = {
      actives = Wire.str(m.parts.actives, nil, MAX_STRING),
      volatile = Wire.str(m.parts.volatile, nil, MAX_STRING),
      bench = Wire.str(m.parts.bench, nil, MAX_STRING),
    }
  end
  return {
    turn = Wire.num(m.turn, 0, 0, MAX_INT),
    value = Wire.str(m.value, nil, MAX_STRING),
    parts = parts,
  }
end

SCHEMAS.replace = function(m)
  return { index = Wire.num(m.index, 1, 1, MAX_PARTY) }
end

SCHEMAS.bye = function() return {} end
SCHEMAS.forfeit = function(m)
  return { match = Wire.str(m.match, nil, MAX_NAME) }
end

SCHEMAS.hosted = function(m)
  return { code = Wire.str(m.code, nil, MAX_NAME) }
end
SCHEMAS.paired = function() return {} end
SCHEMAS.ping = function(m)
  return { t = Wire.num(m.t, 0, 0) }
end
SCHEMAS.pong = SCHEMAS.ping
SCHEMAS.peer_gone = function() return {} end
SCHEMAS.join_error = function(m)
  return { reason = Wire.str(m.reason, "", MAX_STRING),
           field = Wire.str(m.field, nil, MAX_STRING),
           detail = Wire.str(m.detail, nil, MAX_DETAIL),
           code = Wire.str(m.code, nil, MAX_NAME) }
end

local function rule(m)
  return {
    requiredPartySize = Wire.num(m.requiredPartySize, nil, 0, 255),
    minLevel = Wire.num(m.minLevel, nil, 0, 65535),
    maxLevel = Wire.num(m.maxLevel, nil, 0, 65535),
    turnLimit = Wire.num(m.turnLimit, nil, 0, 65535),
    forceLevel = Wire.num(m.forceLevel, nil, 0, 65535),
  }
end

SCHEMAS.tournament_hosted = function(m)
  local out = rule(m)
  out.code = Wire.str(m.code, nil, MAX_NAME)
  out.participating = Wire.bool(m.participating, nil)
  return out
end

SCHEMAS.tournament_host_error = function(m)
  local out = rule(m)
  out.reason = Wire.str(m.reason, "", MAX_STRING)
  return out
end

SCHEMAS.tournament_join_error = SCHEMAS.tournament_host_error

SCHEMAS.tournament_roster = function(m)
  local out = rule(m)
  out.players = Wire.list(m.players, MAX_MATCHES, name)
  out.spectators = Wire.list(m.spectators, MAX_MATCHES, name)
  out.creator = name(m.creator)
  return out
end

local function match(v)
  if type(v) ~= "table" then return nil end
  return {
    a = name(v.a), b = name(v.b), winner = name(v.winner),
    bye = Wire.bool(v.bye, false),
    state = Wire.str(v.state, nil, MAX_STRING),
    match = Wire.str(v.match, nil, MAX_NAME),
    how = Wire.str(v.how, nil, MAX_STRING),
  }
end

local function round(v)
  if type(v) ~= "table" then return nil end
  return {
    round = Wire.num(v.round, 0, 0, MAX_ROUNDS),
    matches = Wire.list(v.matches, MAX_MATCHES, match),
  }
end

SCHEMAS.bracket_update = function(m)
  local t = type(m.tournament) == "table" and m.tournament or {}
  local out = rule(t)
  out.code = Wire.str(t.code, nil, MAX_NAME)
  out.status = Wire.str(t.status, nil, MAX_STRING)
  out.round = Wire.num(t.round, 0, 0, MAX_ROUNDS)
  out.champion = name(t.champion)
  out.rounds = Wire.list(t.rounds, MAX_ROUNDS, round)
  return { tournament = out }
end

SCHEMAS.match_start = function(m)
  local out = {
    opponent = name(m.opponent),
    round = Wire.num(m.round, 0, 0, MAX_ROUNDS),
    turnLimit = Wire.num(m.turnLimit, nil, 0, 65535),
    role = Wire.str(m.role, "", MAX_STRING),
    match = Wire.str(m.match, nil, MAX_NAME),
  }
  arenaStart(m, out)
  return out
end

SCHEMAS.match_start_spectate = function(m)
  local out = {
    round = Wire.num(m.round, 0, 0, MAX_ROUNDS),
    playerHost = name(m.playerHost),
    playerGuest = name(m.playerGuest),
    match = Wire.str(m.match, nil, MAX_NAME),
    role = Wire.str(m.role, nil, MAX_STRING),
  }
  arenaStart(m, out)
  return out
end

SCHEMAS.tournament_bye = function(m)
  return { round = Wire.num(m.round, 0, 0, MAX_ROUNDS),
           match = Wire.str(m.match, nil, MAX_NAME) }
end

SCHEMAS.tournament_over = function(m)
  return { champion = name(m.champion) }
end

local SPECTATABLE = {
  action = true, replace = true, bye = true, forfeit = true,
  hello = true, party = true, hash = true,
}

SCHEMAS.spectate = function(m)
  if type(m.msg) ~= "table" or not SPECTATABLE[m.msg.type] then return nil end
  local inner = sanitize(m.msg)
  if not inner then return nil end
  return { side = Wire.str(m.side, "", MAX_STRING), msg = inner }
end

local CodeEntry = require("src.link.CodeEntry")

local MAX_DISPLAY_NAME = 16
local MAX_TICKET = 128
local MAX_SESSION = 64
local MAX_PROFILES = 16
local MAX_LOBBY_ENTRIES = 200
local MAX_NOTE = 40
local MAX_SPECTATORS = 64
local MAX_REPLAY = 512
local MAX_ROOM_PLAYERS = 4
local MAX_ENTRY_PLAYERS = 64
local MAX_TEAM = 6
local MAX_DEADLINES = 8

local function displayName(v)
  return Wire.str(v, nil, MAX_DISPLAY_NAME)
end

local function codeStr(v)
  if type(v) ~= "string" then return nil end
  local s = v:upper()
  if #s ~= CodeEntry.LENGTH then return nil end
  for i = 1, #s do
    if not CodeEntry.CHARSET:find(s:sub(i, i), 1, true) then return nil end
  end
  return s
end

Wire.code = codeStr

local function cartRef(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    version = Wire.str(v.version, nil, MAX_NAME),
    hash = Wire.str(v.hash, nil, MAX_STRING),
  }
end

local function arenaRule(v)
  if type(v) ~= "table" then v = {} end
  return {
    partySize = Wire.num(v.partySize, nil, 1, MAX_TEAM),
    minLevel = Wire.num(v.minLevel, nil, 1, 100),
    maxLevel = Wire.num(v.maxLevel, nil, 1, 100),
    forceLevel = Wire.num(v.forceLevel, nil, 1, 100),
  }
end

local function profile(v)
  if type(v) ~= "table" then return nil end
  return {
    engine = Wire.num(v.engine, nil, 1, 2),
    version = Wire.str(v.version, nil, MAX_NAME),
    engineVersion = Wire.str(v.engineVersion, nil, MAX_STRING),
    apiVersion = Wire.num(v.apiVersion, nil, 0, MAX_INT),
    fingerprint = Wire.str(v.fingerprint, nil, MAX_STRING),
    rulesetId = Wire.str(v.rulesetId, nil, MAX_NAME),
    kind = Wire.str(v.kind, nil, MAX_NAME),
    cart = cartRef(v.cart),
    rule = arenaRule(v.rule),
  }
end

Wire.profile = profile

arenaStart = function(m, out)
  out.seed = Wire.num(m.seed, nil, 0, MAX_INT)
  out.ruleset = Wire.str(m.ruleset, nil, MAX_STRING)
  out.rule = m.rule ~= nil and arenaRule(m.rule) or nil
  out.code = codeStr(m.code) or out.code
  out.peerName = displayName(m.peerName)
  out.hostName = displayName(m.hostName)
  out.guestName = displayName(m.guestName)
  out.theirParty = m.theirParty ~= nil and Wire.list(m.theirParty, MAX_TEAM, mon) or nil
  out.hostParty = m.hostParty ~= nil and Wire.list(m.hostParty, MAX_TEAM, mon) or nil
  out.guestParty = m.guestParty ~= nil and Wire.list(m.guestParty, MAX_TEAM, mon) or nil
  return out
end

local function youEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    account = Wire.str(v.account, nil, MAX_NAME),
  }
end

local function lobbyEntry(v)
  if type(v) ~= "table" then return nil end
  local id = Wire.str(v.id, nil, MAX_NAME)
  if not id then return nil end
  return {
    id = id,
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    intent = Wire.str(v.intent, nil, MAX_NAME),
    profile = profile(v.profile),
    since = Wire.num(v.since, nil, 0),
    note = Wire.str(v.note, nil, MAX_STRING),
    code = codeStr(v.code),
    open = Wire.bool(v.open, nil),
    stage = Wire.str(v.stage, nil, MAX_NAME),
    players = Wire.num(v.players, nil, 0, MAX_ENTRY_PLAYERS),
    spectators = Wire.num(v.spectators, nil, 0, MAX_SPECTATORS),
    maxSpectators = Wire.num(v.maxSpectators, nil, 0, MAX_SPECTATORS),
  }
end

local function playerEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    role = Wire.str(v.role, nil, MAX_NAME),
    ready = Wire.bool(v.ready, false),
    online = Wire.bool(v.online, true),
    party = Wire.list(v.party, MAX_TEAM, mon),
    partyDigest = Wire.str(v.partyDigest, nil, MAX_STRING),
  }
end

local function spectatorEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
  }
end

local function deadlineEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    kind = Wire.str(v.kind, nil, MAX_NAME),
    at = Wire.num(v.at, nil, 0),
  }
end

local function innerMsg(v)
  if type(v) ~= "table" then return nil end
  return sanitize(v)
end

local function replayEntry(v)
  if type(v) ~= "table" then return nil end
  local inner = innerMsg(v.msg)
  if not inner then
    inner = innerMsg(v)
    if not inner then return nil end
    return { seq = Wire.num(v.seq, nil, 0, MAX_INT), msg = inner }
  end
  return {
    seq = Wire.num(v.seq, nil, 0, MAX_INT),
    clientSeq = Wire.num(v.clientSeq, nil, 0, MAX_INT),
    side = Wire.str(v.side, nil, MAX_NAME),
    msg = inner,
  }
end

SCHEMAS.lobby_hello = function(m)
  return {
    ticket = Wire.str(m.ticket, nil, MAX_TICKET),
    name = displayName(m.name),
    engineVersion = Wire.str(m.engineVersion, nil, MAX_STRING),
    platform = Wire.str(m.platform, nil, MAX_NAME),
    profiles = Wire.list(m.profiles, MAX_PROFILES, profile),
  }
end

SCHEMAS.lobby_welcome = function(m)
  return {
    session = Wire.str(m.session, nil, MAX_SESSION),
    you = youEntry(m.you),
    serverTime = Wire.num(m.serverTime, nil, 0),
    heartbeatMs = Wire.num(m.heartbeatMs, nil, 0, 600000),
    resumed = Wire.bool(m.resumed, false),
  }
end

SCHEMAS.resume = function(m)
  return {
    session = Wire.str(m.session, nil, MAX_SESSION),
    ack = Wire.num(m.ack, 0, 0, MAX_INT),
  }
end

SCHEMAS.advertise = function(m)
  return {
    intent = Wire.str(m.intent, nil, MAX_NAME),
    profile = profile(m.profile),
    note = Wire.str(m.note, nil, MAX_STRING),
  }
end

SCHEMAS.unadvertise = function() return {} end

SCHEMAS.room_create = function(m)
  return {
    intent = Wire.str(m.intent, nil, MAX_NAME),
    profile = profile(m.profile),
    playing = Wire.bool(m.playing, true),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_SPECTATORS),
    public = Wire.bool(m.public, true),
    note = Wire.str(m.note, nil, MAX_NOTE),
  }
end

SCHEMAS.room_join = function(m)
  return {
    code = codeStr(m.code),
    as = Wire.str(m.as, nil, MAX_NAME),
    profile = profile(m.profile),
  }
end

SCHEMAS.room_leave = function() return {} end

SCHEMAS.room_ready = function(m)
  return {
    party = Wire.list(m.party, MAX_TEAM, mon),
    partyDigest = Wire.str(m.partyDigest, nil, MAX_STRING),
  }
end

SCHEMAS.room_msg = function(m)
  local inner = innerMsg(m.msg)
  if not inner then return nil end
  return {
    seq = Wire.num(m.seq, 0, 0, MAX_INT),
    clientSeq = Wire.num(m.clientSeq, nil, 0, MAX_INT),
    side = Wire.str(m.side, nil, MAX_NAME),
    msg = inner,
  }
end

SCHEMAS.room_report = function(m)
  return {
    match = Wire.str(m.match, nil, MAX_NAME),
    result = Wire.str(m.result, nil, MAX_NAME),
  }
end

SCHEMAS.room_kick = function(m)
  return { id = Wire.str(m.id, nil, MAX_NAME) }
end

SCHEMAS.room_close = function() return {} end
SCHEMAS.lobby_query = function() return {} end

SCHEMAS.room_ack = function(m)
  return { seq = Wire.num(m.seq, 0, 0, MAX_INT) }
end

SCHEMAS.lobby_list = function(m)
  return {
    entries = Wire.list(m.entries, MAX_LOBBY_ENTRIES, lobbyEntry),
    online = Wire.num(m.online, nil, 0, MAX_INT),
  }
end

SCHEMAS.lobby_delta = function(m)
  local ids = function(v)
    return Wire.list(v, MAX_LOBBY_ENTRIES, function(x)
      return Wire.str(x, nil, MAX_NAME)
    end)
  end
  return {
    added = Wire.list(m.added, MAX_LOBBY_ENTRIES, lobbyEntry),
    changed = Wire.list(m.changed, MAX_LOBBY_ENTRIES, lobbyEntry),
    removed = ids(m.removed),
    add = Wire.list(m.add, MAX_LOBBY_ENTRIES, lobbyEntry),
    update = Wire.list(m.update, MAX_LOBBY_ENTRIES, lobbyEntry),
    remove = Wire.list(m.remove, MAX_LOBBY_ENTRIES, function(v)
      return Wire.str(v, nil, MAX_NAME)
    end),
    op = Wire.str(m.op, nil, MAX_NAME),
    entry = lobbyEntry(m.entry),
    id = Wire.str(m.id, nil, MAX_NAME),
  }
end

SCHEMAS.room_state = function(m)
  return {
    code = codeStr(m.code),
    players = Wire.list(m.players, MAX_ROOM_PLAYERS, playerEntry),
    spectators = Wire.list(m.spectators, MAX_SPECTATORS, spectatorEntry),
    stage = Wire.str(m.stage, nil, MAX_NAME),
    profile = profile(m.profile),
    host = Wire.str(m.host, nil, MAX_NAME),
    seed = Wire.num(m.seed, nil, 0, MAX_INT),
    intent = Wire.str(m.intent, nil, MAX_NAME),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_SPECTATORS),
    rule = m.rule ~= nil and arenaRule(m.rule) or nil,
    match = Wire.str(m.match, nil, MAX_NAME),
    deadlines = Wire.list(m.deadlines, MAX_DEADLINES, deadlineEntry),
  }
end

SCHEMAS.room_replay = function(m)
  return {
    from = Wire.num(m.from, 0, 0, MAX_INT),
    yourSeq = Wire.num(m.yourSeq, nil, 0, MAX_INT),
    msgs = Wire.list(m.msgs, MAX_REPLAY, replayEntry),
  }
end

SCHEMAS.room_deadline = function(m)
  return {
    kind = Wire.str(m.kind, nil, MAX_NAME),
    at = Wire.num(m.at, nil, 0),
  }
end

SCHEMAS.room_result = function(m)
  return {
    match = Wire.str(m.match, nil, MAX_NAME),
    code = codeStr(m.code),
    winner = displayName(m.winner),
    winnerId = Wire.str(m.winnerId, nil, MAX_NAME),
    how = Wire.str(m.how, nil, MAX_NAME),
  }
end

SCHEMAS.room_closed = function(m)
  return {
    reason = Wire.str(m.reason, nil, MAX_NAME),
    code = codeStr(m.code),
  }
end

local MAX_TOUR_PLAYERS = 64
local MAX_TOUR_SPECTATORS = 64
local MAX_TOUR_ROUNDS = 7
local MAX_TOUR_MATCHES = 32

local TOUR_STAGES = { registering = true, running = true, finished = true }
local TOUR_MATCH_STATES = { pending = true, live = true, done = true,
                            bye = true }

local function tourPlayerEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    online = Wire.bool(v.online, true),
    eliminated = Wire.bool(v.eliminated, false),
  }
end

local function tourMatchEntry(v)
  if type(v) ~= "table" then return nil end
  local state = Wire.str(v.state, nil, MAX_NAME)
  return {
    match = Wire.str(v.match, nil, MAX_NAME),
    a = Wire.str(v.a, nil, MAX_NAME),
    b = Wire.str(v.b, nil, MAX_NAME),
    winner = Wire.str(v.winner, nil, MAX_NAME),
    how = Wire.str(v.how, nil, MAX_NAME),
    state = TOUR_MATCH_STATES[state or ""] and state or nil,
  }
end

local function tourRoundEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    round = Wire.num(v.round, 0, 0, MAX_TOUR_ROUNDS),
    matches = Wire.list(v.matches, MAX_TOUR_MATCHES, tourMatchEntry),
  }
end

SCHEMAS.tour_create = function(m)
  return {
    profile = profile(m.profile),
    rule = m.rule ~= nil and arenaRule(m.rule) or nil,
    playing = Wire.bool(m.playing, true),
    shotClock = Wire.num(m.shotClock, nil, 0, 3600),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_TOUR_SPECTATORS),
    party = m.party ~= nil and Wire.list(m.party, MAX_TEAM, mon) or nil,
    partyDigest = Wire.str(m.partyDigest, nil, MAX_STRING),
    public = Wire.bool(m.public, true),
    note = Wire.str(m.note, nil, MAX_NOTE),
  }
end

SCHEMAS.tour_join = function(m)
  return {
    code = codeStr(m.code),
    as = Wire.str(m.as, nil, MAX_NAME),
    profile = profile(m.profile),
    party = Wire.list(m.party, MAX_TEAM, mon),
    partyDigest = Wire.str(m.partyDigest, nil, MAX_STRING),
  }
end

SCHEMAS.tour_leave = function() return {} end
SCHEMAS.tour_start = function() return {} end
SCHEMAS.tour_close = function() return {} end

SCHEMAS.tour_kick = function(m)
  return { id = Wire.str(m.id, nil, MAX_NAME) }
end

SCHEMAS.tour_state = function(m)
  local stage = Wire.str(m.stage, nil, MAX_NAME)
  return {
    code = codeStr(m.code),
    creator = Wire.str(m.creator, nil, MAX_NAME),
    stage = TOUR_STAGES[stage or ""] and stage or "registering",
    players = Wire.list(m.players, MAX_TOUR_PLAYERS, tourPlayerEntry),
    spectators = Wire.list(m.spectators, MAX_TOUR_SPECTATORS, spectatorEntry),
    profile = profile(m.profile),
    rule = m.rule ~= nil and arenaRule(m.rule) or nil,
    shotClock = Wire.num(m.shotClock, nil, 0, 3600),
    round = Wire.num(m.round, 0, 0, MAX_TOUR_ROUNDS),
    bracket = Wire.list(m.bracket, MAX_TOUR_ROUNDS, tourRoundEntry),
    live = Wire.str(m.live, nil, MAX_NAME),
    champion = Wire.str(m.champion, nil, MAX_NAME),
    championId = Wire.str(m.championId, nil, MAX_NAME),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_TOUR_SPECTATORS),
  }
end

SCHEMAS.tour_match = function(m)
  return {
    match = Wire.str(m.match, nil, MAX_NAME),
    round = Wire.num(m.round, 0, 0, MAX_TOUR_ROUNDS),
    code = codeStr(m.code),
  }
end

SCHEMAS.tour_match_spectate = SCHEMAS.tour_match

SCHEMAS.tour_bye = function(m)
  return {
    match = Wire.str(m.match, nil, MAX_NAME),
    round = Wire.num(m.round, 0, 0, MAX_TOUR_ROUNDS),
  }
end

SCHEMAS.tour_deadline = function(m)
  return {
    kind = Wire.str(m.kind, nil, MAX_NAME),
    at = Wire.num(m.at, nil, 0),
    match = Wire.str(m.match, nil, MAX_NAME),
  }
end

SCHEMAS.tour_closed = function(m)
  return {
    code = codeStr(m.code),
    reason = Wire.str(m.reason, nil, MAX_NAME),
  }
end

SCHEMAS.tour_over = function(m)
  return {
    code = codeStr(m.code),
    champion = displayName(m.champion),
    championId = Wire.str(m.championId, nil, MAX_NAME),
  }
end

Wire.SCHEMAS = SCHEMAS

local function passthrough(m)
  local out = Wire.plain(m) or {}
  out.type = nil
  return out
end

sanitize = function(msg)
  if type(msg) ~= "table" then return nil end
  local kind = msg.type
  if type(kind) ~= "string" or #kind > MAX_STRING then return nil end
  local schema = SCHEMAS[kind]
  local out
  if schema then
    out = schema(msg)
    if not out then return nil end
  else
    out = passthrough(msg)
  end
  out.type = kind
  return out
end

Wire.sanitize = sanitize

return Wire

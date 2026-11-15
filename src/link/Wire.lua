local Wire = {}

local MAX_INT = 2147483647
local MAX_TIME = 9007199254740991
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
  if #v > maxLen then
    local cut = maxLen
    while cut > 0 do
      local b = v:byte(cut + 1)
      if b < 0x80 or b >= 0xC0 then break end
      cut = cut - 1
    end
    return v:sub(1, cut)
  end
  return v
end

function Wire.chars(v, default, maxChars)
  if type(v) ~= "string" then return default end
  local maxBytes = maxChars * 4
  local count, cut = 0, #v
  for i = 1, #v do
    local b = v:byte(i)
    if b < 0x80 or b >= 0xC0 then
      count = count + 1
      if count > maxChars then
        cut = i - 1
        break
      end
    end
  end
  if cut > maxBytes then
    cut = maxBytes
    while cut > 0 do
      local b = v:byte(cut + 1)
      if b < 0x80 or b >= 0xC0 then break end
      cut = cut - 1
    end
  end
  if cut < #v then return v:sub(1, cut) end
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
    sleepTurns = v.status == "SLP" and Wire.num(v.sleepTurns, nil, 1, 7) or nil,
    nickname = Wire.str(v.nickname, nil, MAX_STRING),
    dvs = statMap(v.dvs),
    statExp = statMap(v.statExp),
    moves = Wire.list(v.moves, MAX_MOVES, move),
    ot = Wire.str(v.ot, nil, MAX_STRING),
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
  return { index = Wire.num(m.index, nil, -MAX_INT, MAX_INT),
           cancel = Wire.bool(m.cancel, nil) }
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

local MAX_SEAT = 4

local function seatNum(v)
  return Wire.num(v, nil, -1, MAX_SEAT)
end

SCHEMAS.bye = function(m)
  return { seat = seatNum(m.seat), relay = Wire.bool(m.relay, nil) }
end
SCHEMAS.forfeit = function(m)
  return { match = Wire.str(m.match, nil, MAX_NAME),
           reason = Wire.str(m.reason, nil, MAX_NAME),
           seat = seatNum(m.seat),
           relay = Wire.bool(m.relay, nil) }
end

SCHEMAS.ping = function(m)
  return { t = Wire.num(m.t, 0, 0, MAX_TIME) }
end
SCHEMAS.pong = SCHEMAS.ping
SCHEMAS.join_error = function(m)
  return { reason = Wire.str(m.reason, "", MAX_STRING),
           field = Wire.str(m.field, nil, MAX_STRING),
           detail = Wire.str(m.detail, nil, MAX_DETAIL),
           triesLeft = Wire.num(m.triesLeft, nil, 0, 255),
           retryAt = Wire.num(m.retryAt, nil, 0, MAX_TIME) }
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
local MAX_ROOM_PLAYERS = 5
local MAX_ENTRY_PLAYERS = 64
local MAX_TEAM = 6
local MAX_DEADLINES = 8
local MAX_U32 = 4294967295
local MAX_SEATS = 5
local MAX_PLAZA = 40
local MAX_DIRECT = 64
local MAX_GROUPS = 64
local MAX_AVATAR_NAME = 16
local MAX_AVATAR_CHARS = 10
local MAX_AVATAR_STYLE = 16
local MAX_CAPS_FP = 64
local MAX_CAPS_ENTRIES = 11
local MAX_MON_TEXT = 32
local MAX_CHAT_NAME = 7
local MAX_CHAT_TEXT = 15
local MAX_WIRE_DIGEST = 16

local function displayName(v)
  return Wire.chars(v, nil, MAX_DISPLAY_NAME)
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

local function patterned(pattern)
  return function(v)
    if type(v) ~= "string" then return nil end
    local s = v:lower()
    if not s:match(pattern) then return nil end
    return s
  end
end

Wire.roomId = patterned("^r" .. ("[0-9a-f]"):rep(16) .. "$")
Wire.tourId = patterned("^t" .. ("[0-9a-f]"):rep(16) .. "$")
Wire.inviteId = patterned("^i" .. ("[0-9a-f]"):rep(16) .. "$")
Wire.inviteToken = patterned("^" .. ("[0-9a-f]"):rep(32) .. "$")
Wire.playerId = patterned("^" .. ("[0-9a-f]"):rep(8) .. "$")
Wire.digest = patterned("^" .. ("[0-9a-f]"):rep(MAX_WIRE_DIGEST) .. "$")

function Wire.pin(v)
  if type(v) ~= "string" or not v:match("^[0-9][0-9][0-9][0-9]$") then
    return nil
  end
  return v
end

local STAT6 = { "hp", "atk", "def", "spe", "spa", "spd" }

local function stat6(v, max)
  local out = {}
  if type(v) ~= "table" then v = {} end
  for _, k in ipairs(STAT6) do out[k] = Wire.num(v[k], 0, 0, max) end
  return out
end

local function move3(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.num(v.id, 0, 0, 65535),
    pp = Wire.num(v.pp, 0, 0, 255),
    ppUps = Wire.num(v.ppUps, 0, 0, 3),
  }
end

local MON3_GENDERS = { M = true, F = true, U = true }

function Wire.mon3(v)
  if type(v) ~= "table" then return nil end
  local gender = v.gender
  if type(gender) ~= "string" or not MON3_GENDERS[gender] then gender = "U" end
  return {
    species = Wire.num(v.species, 0, 0, 65535),
    nickname = Wire.str(v.nickname, "", MAX_MON_TEXT),
    level = Wire.num(v.level, 0, 0, 255),
    exp = Wire.num(v.exp, 0, 0, MAX_INT),
    hp = Wire.num(v.hp, 0, 0, 65535),
    status = Wire.str(v.status, "", 8),
    personality = Wire.num(v.personality, 0, 0, MAX_U32),
    otId = Wire.num(v.otId, 0, 0, 65535),
    otSecretId = Wire.num(v.otSecretId, 0, 0, 65535),
    otName = Wire.str(v.otName, "", MAX_MON_TEXT),
    otGender = Wire.num(v.otGender, 0, 0, 1),
    nature = Wire.num(v.nature, 0, 0, 255),
    ability = Wire.num(v.ability, 0, 0, 255),
    abilityNum = Wire.num(v.abilityNum, nil, 0, 1),
    language = Wire.num(v.language, nil, 0, 255),
    contest = type(v.contest) == "table" and {
      cool = Wire.num(v.contest.cool, 0, 0, 255), beauty = Wire.num(v.contest.beauty, 0, 0, 255),
      cute = Wire.num(v.contest.cute, 0, 0, 255), smart = Wire.num(v.contest.smart, 0, 0, 255),
      tough = Wire.num(v.contest.tough, 0, 0, 255), sheen = Wire.num(v.contest.sheen, 0, 0, 255),
    } or nil,
    gender = gender,
    ivs = stat6(v.ivs, 255),
    evs = stat6(v.evs, 65535),
    moves = Wire.list(v.moves, 4, move3),
    item = Wire.num(v.item, 0, 0, 65535),
    friendship = Wire.num(v.friendship, 0, 0, 255),
    pokerus = Wire.num(v.pokerus, 0, 0, 255),
    metLocation = Wire.num(v.metLocation, 0, 0, 255),
    metLevel = Wire.num(v.metLevel, 0, 0, 255),
    metGame = Wire.num(v.metGame, 0, 0, 255),
    pokeball = Wire.num(v.pokeball, 0, 0, 255),
    ribbons = Wire.num(v.ribbons, 0, 0, MAX_U32),
    markings = Wire.num(v.markings, 0, 0, 255),
    isEgg = Wire.bool(v.isEgg, false),
    fatefulEncounter = Wire.bool(v.fatefulEncounter, false),
    modernFatefulEncounter = Wire.bool(v.modernFatefulEncounter, nil),
    eggCycles = Wire.num(v.eggCycles, 0, 0, 255),
  }
end

local function party3(v)
  return Wire.list(v, MAX_TEAM, Wire.mon3)
end

Wire.party3 = party3

local function avatarStyle(v)
  if type(v) ~= "string" or not v:match("^[a-z0-9:_%-]+$") or #v > MAX_AVATAR_STYLE then
    return nil
  end
  return v
end

Wire.avatarStyle = avatarStyle

function Wire.avatar(v)
  if type(v) ~= "table" then return nil end
  return {
    name = Wire.chars(v.name, "", MAX_AVATAR_CHARS),
    trainerId = Wire.num(v.trainerId, 0, 0, 65535),
    gender = Wire.num(v.gender, 0, 0, 1),
    version = Wire.str(v.version, nil, MAX_AVATAR_NAME),
    style = avatarStyle(v.style),
    gen = Wire.num(v.gen, nil, 1, 3),
    canLinkNationally = Wire.bool(v.canLinkNationally, nil),
  }
end

local function capsEntry(v)
  if type(v) ~= "table" then return nil end
  local version = Wire.str(v.version, nil, MAX_AVATAR_NAME)
  local fp = type(v.fp) == "string" and v.fp:lower() or nil
  if not version or not version:match("^[a-z]+$") or not fp
     or #fp > MAX_CAPS_FP or not fp:match("^[0-9a-f]+$") then
    return nil
  end
  return { version = version, fp = fp }
end

function Wire.caps(v)
  if type(v) ~= "table" then return nil end
  local gens, total = {}, 0
  local src = type(v.gens) == "table" and v.gens or {}
  for gen = 1, 3 do
    local list = src[tostring(gen)]
    if list == nil then list = src[gen] end
    if type(list) == "table" then
      local out = {}
      for i = 1, math.min(#list, MAX_CAPS_ENTRIES) do
        local entry = capsEntry(list[i])
        if entry and total < MAX_CAPS_ENTRIES then
          out[#out + 1] = entry
          total = total + 1
        end
      end
      gens[tostring(gen)] = out
    end
  end
  return {
    proto = Wire.num(v.proto, 1, 1, 1000),
    policy = Wire.num(v.policy, 0, 0, 1000000),
    gens = gens,
  }
end

local function recruiting(v)
  if type(v) ~= "table" then return nil end
  return {
    activity = Wire.str(v.activity, nil, MAX_NAME),
    joined = Wire.num(v.joined, 0, 0, MAX_SEATS),
    min = Wire.num(v.min, 0, 0, MAX_SEATS),
    max = Wire.num(v.max, 0, 0, MAX_SEATS),
  }
end

local function board(v)
  if type(v) ~= "table" then return nil end
  return {
    species = Wire.num(v.species, 0, 0, 65535),
    level = Wire.num(v.level, 0, 0, 255),
    wantType = Wire.num(v.wantType, 0, 0, 255),
    personality = Wire.num(v.personality, nil, 0, MAX_U32),
  }
end

local function memberGroup(v)
  if type(v) ~= "table" then return nil end
  return {
    leader = Wire.playerId(v.leader),
    members = Wire.list(v.members, MAX_SEATS, Wire.playerId),
    activity = Wire.str(v.activity, nil, MAX_NAME),
  }
end

function Wire.member(v)
  if type(v) ~= "table" then return nil end
  local id = Wire.playerId(v.id)
  if not id then return nil end
  return {
    id = id,
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    slot = Wire.num(v.slot, nil, 1, MAX_PLAZA),
    online = Wire.bool(v.online, true),
    status = Wire.str(v.status, nil, MAX_NAME),
    avatar = Wire.avatar(v.avatar),
    recruiting = recruiting(v.recruiting),
    board = board(v.board),
    group = memberGroup(v.group),
    caps = Wire.caps(v.caps),
  }
end

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
    engine = Wire.num(v.engine, nil, 1, 3),
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

local function partyOf(v, engine)
  if engine == 3 then return party3(v) end
  return Wire.list(v, MAX_TEAM, mon)
end

local function seatPlayer(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
  }
end

local function seatParties(v, engine)
  if type(v) ~= "table" then return nil end
  local out = {}
  for i = 1, MAX_SEATS do
    if type(v[i]) == "table" then out[i] = partyOf(v[i], engine) end
  end
  return out
end

arenaStart = function(m, out)
  local engine = Wire.num(m.engine, nil, 1, 3)
  out.room = Wire.roomId(m.room)
  out.engine = engine
  out.seat = Wire.num(m.seat, nil, 0, MAX_SEAT)
  out.seats = Wire.num(m.seats, nil, 2, MAX_SEATS)
  out.players = m.players ~= nil and Wire.list(m.players, MAX_SEATS, seatPlayer) or nil
  out.parties = seatParties(m.parties, engine)
  out.seed = Wire.num(m.seed, nil, 0, MAX_INT)
  out.ruleset = Wire.str(m.ruleset, nil, MAX_STRING)
  out.rule = m.rule ~= nil and arenaRule(m.rule) or nil
  out.peerName = displayName(m.peerName)
  out.hostName = displayName(m.hostName)
  out.guestName = displayName(m.guestName)
  out.theirParty = m.theirParty ~= nil and partyOf(m.theirParty, engine) or nil
  out.hostParty = m.hostParty ~= nil and partyOf(m.hostParty, engine) or nil
  out.guestParty = m.guestParty ~= nil and partyOf(m.guestParty, engine) or nil
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
    online = Wire.bool(v.online, true),
    where = Wire.str(v.where, nil, MAX_NAME),
    status = Wire.str(v.status, nil, MAX_NAME),
    engine = Wire.num(v.engine, nil, 0, 3),
    version = Wire.str(v.version, nil, MAX_NAME),
    intent = Wire.str(v.intent, nil, MAX_NAME),
    profile = profile(v.profile),
    since = Wire.num(v.since, nil, 0, MAX_TIME),
    note = Wire.str(v.note, nil, MAX_STRING),
    room = Wire.roomId(v.room),
    tour = Wire.tourId(v.tour),
    locked = Wire.bool(v.locked, false),
    auto = Wire.bool(v.auto, false),
    open = Wire.bool(v.open, nil),
    stage = Wire.str(v.stage, nil, MAX_NAME),
    players = Wire.num(v.players, nil, 0, MAX_ENTRY_PLAYERS),
    seats = Wire.num(v.seats, nil, 0, MAX_ENTRY_PLAYERS),
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
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
    party = Wire.list(v.party, MAX_TEAM, mon),
    partyDigest = Wire.str(v.partyDigest, nil, MAX_STRING),
    gen = Wire.num(v.gen, nil, 1, 3),
    avatar = Wire.avatar(v.avatar),
  }
end

local XG_MODES = { battle = true, trade = true }

local function xgMode(v)
  return XG_MODES[v] and v or nil
end

local function xgGens(v)
  if type(v) ~= "table" then return nil end
  local a, b = Wire.num(v[1], nil, 1, 3), Wire.num(v[2], nil, 1, 3)
  if not a or not b then return nil end
  return { a, b }
end

local function xgRules(v)
  if type(v) ~= "table" then return nil end
  return {
    mode = xgMode(v.mode),
    ruleset = Wire.str(v.ruleset, nil, MAX_NAME),
    gen = Wire.num(v.gen, nil, 1, 3),
    dexMax = Wire.num(v.dexMax, nil, 1, 65535),
    moveMax = Wire.num(v.moveMax, nil, 1, 65535),
    moveGen = Wire.num(v.moveGen, nil, 1, 3),
    policy = Wire.num(v.policy, nil, 0, 1000000),
    gens = xgGens(v.gens),
  }
end

Wire.xgRules = xgRules

local function xgPair(v, fn)
  local out = {}
  if type(v) ~= "table" then return out end
  for i = 1, 2 do
    if v[i] ~= nil then out[i] = fn(v[i]) end
  end
  return out
end

local function xgRoster(v)
  if type(v) ~= "table" then return nil end
  local size, digest = Wire.num(v.size, nil, 1, MAX_TEAM), Wire.digest(v.digest16)
  if not size or not digest then return nil end
  return { size = size, digest16 = digest }
end

local function xgOfferMeta(v)
  if type(v) ~= "table" then return nil end
  local offerRev, digest = Wire.num(v.offerRev, nil, 0, MAX_INT), Wire.digest(v.digest16)
  if not offerRev or not digest then return nil end
  return { offerRev = offerRev, digest16 = digest }
end

local function xgSnapshot(v)
  if type(v) ~= "table" then return nil end
  local mode = xgMode(v.mode)
  local rev = Wire.num(v.rev, nil, 0, MAX_INT)
  if not mode or not rev then return nil end
  return {
    mode = mode,
    rev = rev,
    gens = xgGens(v.gens),
    rules = xgRules(v.rules),
    blocked = Wire.str(v.blocked, nil, MAX_NAME),
    size = Wire.num(v.size, nil, 1, MAX_TEAM),
    caps = xgPair(v.caps, function(x) return x == true end),
    rosters = xgPair(v.rosters, xgRoster),
    sizeReq = xgPair(v.sizeReq, function(x) return Wire.num(x, nil, 1, MAX_TEAM) end),
    offers = xgPair(v.offers, xgOfferMeta),
    ready = xgPair(v.ready, function(x) return x == true end),
  }
end

Wire.xgSnapshot = xgSnapshot

local function spectatorEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    id = Wire.str(v.id, nil, MAX_NAME),
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    online = Wire.bool(v.online, true),
  }
end

local function deadlineEntry(v)
  if type(v) ~= "table" then return nil end
  return {
    kind = Wire.str(v.kind, nil, MAX_NAME),
    at = Wire.num(v.at, nil, 0, MAX_TIME),
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
    seat = seatNum(v.seat),
    side = Wire.str(v.side, nil, MAX_NAME),
    relay = Wire.bool(v.relay, nil),
    msg = inner,
  }
end

local function presenceFields(v)
  if type(v) ~= "table" then return nil end
  local out = {
    where = Wire.str(v.where, nil, MAX_NAME),
    status = Wire.str(v.status, nil, MAX_NAME),
    version = Wire.str(v.version, nil, MAX_NAME),
    engine = Wire.num(v.engine, nil, 1, 3),
  }
  if v.board == false then
    out.board = false
  else
    out.board = board(v.board)
  end
  return out
end

SCHEMAS.lobby_hello = function(m)
  return {
    protocol = Wire.num(m.protocol, nil, 0, MAX_INT),
    ticket = Wire.str(m.ticket, nil, MAX_TICKET),
    name = displayName(m.name),
    engineVersion = Wire.str(m.engineVersion, nil, MAX_STRING),
    platform = Wire.str(m.platform, nil, MAX_NAME),
    profiles = Wire.list(m.profiles, MAX_PROFILES, profile),
    presence = presenceFields(m.presence),
    xgen = Wire.num(m.xgen, nil, 0, 1),
  }
end

SCHEMAS.upgrade_required = function(m)
  return {
    protocol = Wire.num(m.protocol, nil, 0, MAX_INT),
    minBuild = Wire.str(m.minBuild, nil, MAX_STRING),
    text = Wire.str(m.text, nil, MAX_DETAIL),
  }
end

SCHEMAS.set_profiles = function(m)
  return { profiles = Wire.list(m.profiles, MAX_PROFILES, profile) }
end

SCHEMAS.presence = function(m)
  return presenceFields(m)
end

SCHEMAS.lobby_welcome = function(m)
  return {
    session = Wire.str(m.session, nil, MAX_SESSION),
    you = youEntry(m.you),
    serverTime = Wire.num(m.serverTime, nil, 0, MAX_TIME),
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
    private = Wire.bool(m.private, false),
    pin = Wire.pin(m.pin),
    seats = Wire.num(m.seats, nil, 2, MAX_SEATS),
    auto = Wire.bool(m.auto, false),
    note = Wire.str(m.note, nil, MAX_NOTE),
  }
end

SCHEMAS.room_join = function(m)
  return {
    room = Wire.roomId(m.room),
    invite = Wire.inviteToken(m.invite),
    as = Wire.str(m.as, nil, MAX_NAME),
    profile = profile(m.profile),
    pin = Wire.pin(m.pin),
  }
end

SCHEMAS.invite_token = function(m)
  return {
    room = Wire.roomId(m.room),
    token = Wire.inviteToken(m.token),
    expiresAt = Wire.num(m.expiresAt, nil, 0, MAX_TIME),
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
    seat = seatNum(m.seat),
    side = Wire.str(m.side, nil, MAX_NAME),
    relay = Wire.bool(m.relay, nil),
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

local ORIGINS = { create = true, invite = true, direct = true, group = true,
                  tour = true }

SCHEMAS.room_state = function(m)
  local origin = Wire.str(m.origin, nil, MAX_NAME)
  return {
    room = Wire.roomId(m.room),
    intent = Wire.str(m.intent, nil, MAX_NAME),
    engine = Wire.num(m.engine, nil, 1, 3),
    profile = profile(m.profile),
    rule = m.rule ~= nil and arenaRule(m.rule) or nil,
    seats = Wire.num(m.seats, nil, 2, MAX_SEATS),
    locked = Wire.bool(m.locked, false),
    listed = Wire.bool(m.listed, nil),
    auto = Wire.bool(m.auto, false),
    origin = ORIGINS[origin or ""] and origin or nil,
    players = Wire.list(m.players, MAX_ROOM_PLAYERS, playerEntry),
    spectators = Wire.list(m.spectators, MAX_SPECTATORS, spectatorEntry),
    stage = Wire.str(m.stage, nil, MAX_NAME),
    host = Wire.str(m.host, nil, MAX_NAME),
    seed = Wire.num(m.seed, nil, 0, MAX_INT),
    match = Wire.str(m.match, nil, MAX_NAME),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_SPECTATORS),
    leader = Wire.num(m.leader, nil, 0, MAX_SEAT),
    deadlines = Wire.list(m.deadlines, MAX_DEADLINES, deadlineEntry),
    mode = xgMode(m.mode),
    xg = xgSnapshot(m.xg),
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
    at = Wire.num(m.at, nil, 0, MAX_TIME),
  }
end

SCHEMAS.room_result = function(m)
  return {
    room = Wire.roomId(m.room),
    match = Wire.str(m.match, nil, MAX_NAME),
    winner = displayName(m.winner),
    winnerId = Wire.str(m.winnerId, nil, MAX_NAME),
    how = Wire.str(m.how, nil, MAX_NAME),
    winnerSide = Wire.num(m.winnerSide, nil, 0, 1),
    winners = Wire.list(m.winners, MAX_SEATS, function(v)
      return Wire.str(v, nil, MAX_NAME)
    end),
  }
end

SCHEMAS.room_closed = function(m)
  return {
    reason = Wire.str(m.reason, nil, MAX_NAME),
    room = Wire.roomId(m.room),
  }
end

local function idList(v, maxN)
  return Wire.list(v, maxN, Wire.playerId)
end

local function inviteDetail(v)
  if type(v) ~= "table" then return nil end
  return {
    ruleset = Wire.str(v.ruleset, nil, MAX_NAME),
    room = Wire.roomId(v.room),
    tour = Wire.tourId(v.tour),
    board = board(v.board),
    join = Wire.bool(v.join, nil),
  }
end

SCHEMAS.invite = function(m)
  return {
    to = Wire.playerId(m.to),
    activity = Wire.str(m.activity, nil, MAX_NAME),
    detail = inviteDetail(m.detail),
    profile = profile(m.profile),
  }
end

SCHEMAS.invite_reply = function(m)
  return { id = Wire.inviteId(m.id), accept = Wire.bool(m.accept, false) }
end

SCHEMAS.invite_sent = function(m)
  return {
    id = Wire.inviteId(m.id),
    to = Wire.playerId(m.to),
    activity = Wire.str(m.activity, nil, MAX_NAME),
    expiresAt = Wire.num(m.expiresAt, nil, 0, MAX_TIME),
  }
end

local function inviteFrom(v)
  if type(v) ~= "table" then return nil end
  local id = Wire.playerId(v.id)
  if not id then return nil end
  return {
    id = id,
    name = displayName(v.name),
    verified = Wire.bool(v.verified, false),
    where = Wire.str(v.where, nil, MAX_NAME),
    avatar = Wire.avatar(v.avatar),
  }
end

SCHEMAS.invite_in = function(m)
  return {
    id = Wire.inviteId(m.id),
    from = inviteFrom(m.from),
    activity = Wire.str(m.activity, nil, MAX_NAME),
    detail = inviteDetail(m.detail),
    expiresAt = Wire.num(m.expiresAt, nil, 0, MAX_TIME),
  }
end

SCHEMAS.invite_closed = function(m)
  return {
    id = Wire.inviteId(m.id),
    why = Wire.str(m.why, nil, MAX_NAME),
    room = Wire.roomId(m.room),
    detail = Wire.str(m.detail, nil, MAX_DETAIL),
    to = Wire.playerId(m.to),
    activity = Wire.str(m.activity, nil, MAX_NAME),
  }
end

SCHEMAS.plaza_join = function(m)
  return {
    kind = Wire.str(m.kind, nil, MAX_NAME),
    cap = Wire.num(m.cap, nil, 1, MAX_PLAZA),
    profile = profile(m.profile),
    avatar = Wire.avatar(m.avatar),
    xgen = Wire.num(m.xgen, nil, 0, 1),
    caps = Wire.caps(m.caps),
  }
end

SCHEMAS.set_caps = function(m)
  local caps = Wire.caps(m.caps)
  if not caps then return nil end
  return { caps = caps }
end

SCHEMAS.plaza_leave = function(m)
  return { kind = Wire.str(m.kind, nil, MAX_NAME) }
end

SCHEMAS.plaza_state = function(m)
  return {
    kind = Wire.str(m.kind, nil, MAX_NAME),
    instance = Wire.num(m.instance, nil, 0, MAX_INT),
    cap = Wire.num(m.cap, nil, 1, MAX_PLAZA),
    rev = Wire.num(m.rev, nil, 0, MAX_INT),
    you = Wire.num(m.you, nil, 1, MAX_PLAZA),
    members = type(m.members) == "table" and Wire.list(m.members, MAX_PLAZA, Wire.member)
      or nil,
  }
end

SCHEMAS.plaza_delta = function(m)
  return {
    kind = Wire.str(m.kind, nil, MAX_NAME),
    instance = Wire.num(m.instance, nil, 0, MAX_INT),
    rev = Wire.num(m.rev, nil, 0, MAX_INT),
    joined = Wire.list(m.joined, MAX_PLAZA, Wire.member),
    left = idList(m.left, MAX_PLAZA),
    changed = Wire.list(m.changed, MAX_PLAZA, Wire.member),
  }
end

SCHEMAS.plaza_counts = function(m)
  return {
    union = Wire.num(m.union, 0, 0, MAX_INT),
    trade = Wire.num(m.trade, 0, 0, MAX_INT),
    battle = Wire.num(m.battle, 0, 0, MAX_INT),
    chat = Wire.num(m.chat, 0, 0, MAX_INT),
    minigame = Wire.num(m.minigame, 0, 0, MAX_INT),
    link = Wire.num(m.link, 0, 0, MAX_INT),
    total = Wire.num(m.total, 0, 0, MAX_INT),
  }
end

local function groupPerson(v)
  if type(v) ~= "table" then return nil end
  local id = Wire.playerId(v.id)
  if not id then return nil end
  local out = {
    id = id,
    name = displayName(v.name),
    avatar = Wire.avatar(v.avatar),
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
  }
  if type(v.online) == "boolean" then out.online = v.online end
  return out
end

local function groupEntry(v)
  if type(v) ~= "table" then return nil end
  local leader = Wire.playerId(v.leader)
  if not leader then return nil end
  return {
    leader = leader,
    name = displayName(v.name),
    avatar = Wire.avatar(v.avatar),
    version = Wire.str(v.version, nil, MAX_NAME),
    joined = Wire.num(v.joined, 0, 0, MAX_SEATS),
    min = Wire.num(v.min, 0, 0, MAX_SEATS),
    max = Wire.num(v.max, 0, 0, MAX_SEATS),
  }
end

SCHEMAS.group_open = function(m)
  return {
    activity = Wire.str(m.activity, nil, MAX_NAME),
    profile = profile(m.profile),
    avatar = Wire.avatar(m.avatar),
  }
end

SCHEMAS.group_list = function(m)
  return {
    activity = Wire.str(m.activity, nil, MAX_NAME),
    profile = profile(m.profile),
    groups = m.groups ~= nil and Wire.list(m.groups, MAX_GROUPS, groupEntry) or nil,
  }
end

SCHEMAS.group_join = function(m)
  return {
    leader = Wire.playerId(m.leader),
    profile = profile(m.profile),
    avatar = Wire.avatar(m.avatar),
  }
end

SCHEMAS.group_accept = function(m)
  return { from = Wire.playerId(m.from), ok = Wire.bool(m.ok, false) }
end

SCHEMAS.group_leave = function() return {} end
SCHEMAS.group_start = function() return {} end

SCHEMAS.group_state = function(m)
  return {
    leader = Wire.playerId(m.leader),
    activity = Wire.str(m.activity, nil, MAX_NAME),
    min = Wire.num(m.min, 0, 0, MAX_SEATS),
    max = Wire.num(m.max, 0, 0, MAX_SEATS),
    members = type(m.members) == "table" and Wire.list(m.members, MAX_SEATS, groupPerson)
      or nil,
    pending = Wire.list(m.pending, MAX_GROUPS, groupPerson),
  }
end

SCHEMAS.group_request = function(m)
  return {
    from = Wire.playerId(m.from),
    name = displayName(m.name),
    avatar = Wire.avatar(m.avatar),
  }
end

SCHEMAS.group_closed = function(m)
  return {
    leader = Wire.playerId(m.leader),
    why = Wire.str(m.why, nil, MAX_NAME),
  }
end

local function speciesList(v)
  return Wire.list(v, MAX_TEAM, function(x) return Wire.num(x, nil, 0, 65535) end)
end

local function directEntry(v)
  if type(v) ~= "table" then return nil end
  local kind = v.kind
  if kind == "player" then
    local id = Wire.playerId(v.id)
    if not id then return nil end
    return {
      kind = "player",
      id = id,
      name = displayName(v.name),
      verified = Wire.bool(v.verified, false),
      avatar = Wire.avatar(v.avatar),
      version = Wire.str(v.version, nil, MAX_NAME),
      preview = speciesList(v.preview),
      since = Wire.num(v.since, nil, 0, MAX_TIME),
    }
  elseif kind == "room" then
    local room = Wire.roomId(v.room)
    if not room then return nil end
    return {
      kind = "room",
      room = room,
      host = Wire.playerId(v.host),
      name = displayName(v.name),
      avatar = Wire.avatar(v.avatar),
      version = Wire.str(v.version, nil, MAX_NAME),
      locked = Wire.bool(v.locked, false),
      auto = Wire.bool(v.auto, false),
      seats = Wire.num(v.seats, nil, 2, MAX_SEATS),
      players = Wire.num(v.players, nil, 0, MAX_SEATS),
      since = Wire.num(v.since, nil, 0, MAX_TIME),
    }
  end
  return nil
end

SCHEMAS.direct_queue = function(m)
  return {
    activity = Wire.str(m.activity, nil, MAX_NAME),
    ruleset = Wire.str(m.ruleset, nil, MAX_NAME),
    auto = Wire.bool(m.auto, false),
    pin = Wire.pin(m.pin),
    profile = profile(m.profile),
    avatar = Wire.avatar(m.avatar),
    preview = speciesList(m.preview),
    seats = Wire.num(m.seats, nil, 2, 4),
  }
end

SCHEMAS.direct_list = function(m)
  return {
    activity = Wire.str(m.activity, nil, MAX_NAME),
    profile = profile(m.profile),
    entries = m.entries ~= nil and Wire.list(m.entries, MAX_DIRECT, directEntry) or nil,
  }
end

SCHEMAS.direct_leave = function() return {} end

SCHEMAS.direct_state = function(m)
  return {
    activity = Wire.str(m.activity, nil, MAX_NAME),
    queued = Wire.bool(m.queued, false),
    hosting = Wire.roomId(m.hosting),
    why = Wire.str(m.why, nil, MAX_NAME),
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

local function profileEngine(p)
  return type(p) == "table" and p.engine or nil
end

SCHEMAS.tour_create = function(m)
  local prof = profile(m.profile)
  return {
    profile = prof,
    rule = m.rule ~= nil and arenaRule(m.rule) or nil,
    playing = Wire.bool(m.playing, true),
    shotClock = Wire.num(m.shotClock, nil, 0, 3600),
    maxSpectators = Wire.num(m.maxSpectators, nil, 0, MAX_TOUR_SPECTATORS),
    party = m.party ~= nil and partyOf(m.party, profileEngine(prof)) or nil,
    partyDigest = Wire.str(m.partyDigest, nil, MAX_STRING),
    public = Wire.bool(m.public, true),
    note = Wire.str(m.note, nil, MAX_NOTE),
  }
end

SCHEMAS.tour_join = function(m)
  local prof = profile(m.profile)
  return {
    tour = Wire.tourId(m.tour),
    code = codeStr(m.code),
    as = Wire.str(m.as, nil, MAX_NAME),
    profile = prof,
    party = partyOf(m.party, profileEngine(prof)),
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
    tour = Wire.tourId(m.tour),
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
    room = Wire.roomId(m.room),
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
    at = Wire.num(m.at, nil, 0, MAX_TIME),
    match = Wire.str(m.match, nil, MAX_NAME),
  }
end

SCHEMAS.tour_closed = function(m)
  return {
    tour = Wire.tourId(m.tour),
    reason = Wire.str(m.reason, nil, MAX_NAME),
  }
end

SCHEMAS.tour_over = function(m)
  return {
    tour = Wire.tourId(m.tour),
    champion = displayName(m.champion),
    championId = Wire.str(m.championId, nil, MAX_NAME),
  }
end

local function inner3(fn)
  return function(m)
    local out = fn(m)
    if not out then return nil end
    out.seat = seatNum(m.seat)
    out.relay = Wire.bool(m.relay, nil)
    return out
  end
end

local function g3extra(v)
  if type(v) ~= "table" then return nil end
  return {
    cacheVersion = Wire.num(v.cacheVersion, nil, 0, MAX_INT),
    nativeVersion = Wire.num(v.nativeVersion, nil, 0, MAX_INT)
      or Wire.str(v.nativeVersion, nil, MAX_NAME),
    linkType = Wire.num(v.linkType, nil, 0, 65535),
    trainerId = Wire.num(v.trainerId, 0, 0, MAX_U32),
    gender = Wire.num(v.gender, 0, 0, 1),
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
    version = Wire.str(v.version, nil, MAX_NAME),
    family = Wire.str(v.family, nil, MAX_NAME),
    gameVersion = Wire.num(v.gameVersion, nil, 0, 65535),
    language = Wire.num(v.language, nil, 0, 65535),
    progressFlags = Wire.num(v.progressFlags, nil, 0, 65535),
    rules = Wire.str(v.rules, nil, 128),
    core = Wire.digest(v.core),
    moves = Wire.digest(v.moves),
  }
end

local MAX_HOST_ROWS = 512
local MAX_HOST_ROW = 64

local function hostRules3(v)
  if type(v) ~= "table" then return nil end
  return {
    version = Wire.str(v.version, nil, MAX_NAME),
    rules = Wire.digest(v.rules),
    moves = Wire.digest(v.moves),
    rows = Wire.list(v.rows, MAX_HOST_ROWS, function(s) return Wire.str(s, nil, MAX_HOST_ROW) end),
  }
end

SCHEMAS.game3_hello = inner3(function(m)
  local out = SCHEMAS.hello(m)
  out.game3 = g3extra(m.game3)
  return out
end)

SCHEMAS.game3_bye = inner3(function(m)
  return { reason = Wire.str(m.reason, nil, MAX_NAME) }
end)

SCHEMAS.game3_link_card = inner3(function(m)
  return { card = Wire.plain(m.card, MAX_EXTRA_DEPTH - 3) }
end)

SCHEMAS.game3_exit_link_room = inner3(function() return {} end)

-- pokeruby/src/overworld.c:2282
SCHEMAS.game3_link_player = inner3(function(m)
  return {
    map = Wire.str(m.map, nil, MAX_NAME),
    x = Wire.num(m.x, nil, 0, 65535),
    y = Wire.num(m.y, nil, 0, 65535),
    tx = Wire.num(m.tx, nil, 0, 65535),
    ty = Wire.num(m.ty, nil, 0, 65535),
    facing = Wire.str(m.facing, nil, 8),
    frames = Wire.num(m.frames, nil, 1, 64),
    busy = Wire.bool(m.busy, nil),
  }
end)

SCHEMAS.game3_battle_linkup = inner3(function(m)
  return {
    linkType = Wire.num(m.linkType, nil, 0, 65535),
    players = Wire.num(m.players, nil, 0, MAX_SEATS),
    version = Wire.num(m.version, nil, 0, 65535),
    progressFlags = Wire.num(m.progressFlags, nil, 0, 65535),
  }
end)

SCHEMAS.game3_battle_seat = inner3(function() return {} end)

SCHEMAS.game3_battle_setup = inner3(function(m)
  return {
    mode = Wire.str(m.mode, nil, MAX_NAME),
    unionRoom = Wire.bool(m.unionRoom, false),
    name = Wire.str(m.name, nil, MAX_NAME),
    trainerId = Wire.num(m.trainerId, 0, 0, MAX_U32),
    gender = Wire.num(m.gender, 0, 0, 1),
    seed = Wire.num(m.seed, nil, 0, MAX_U32),
    party = party3(m.party),
    hostRules = hostRules3(m.hostRules),
  }
end)

local function action3(v)
  if type(v) ~= "table" then return nil end
  return {
    kind = Wire.str(v.kind, nil, MAX_NAME),
    slot = Wire.num(v.slot, nil, 0, 255),
    move = Wire.num(v.move, nil, 0, 65535) or Wire.str(v.move, nil, MAX_NAME),
    target = Wire.num(v.target, nil, 0, 255),
    itemId = Wire.num(v.itemId, nil, 0, 65535),
    partySlot = Wire.num(v.partySlot, nil, 0, 255),
  }
end

SCHEMAS.game3_battle_action = inner3(function(m)
  local out = action3(m)
  out.turn = Wire.num(m.turn, 0, 0, MAX_INT)
  out.forSeat = Wire.num(m.forSeat, nil, 0, MAX_SEAT)
  out.actions = m.actions ~= nil and Wire.list(m.actions, 2, action3) or nil
  return out
end)

SCHEMAS.game3_battle_switch = inner3(function(m)
  return { slot = Wire.num(m.slot, nil, 0, 255), forSeat = Wire.num(m.forSeat, nil, 0, MAX_SEAT) }
end)

local function blockData(v)
  if type(v) == "table" then return Wire.plain(v) end
  if type(v) == "number" then return Wire.num(v, nil, -MAX_INT, MAX_U32) end
  if type(v) == "boolean" then return v end
  return Wire.str(v, nil, MAX_STRING)
end

-- pokeemerald/src/contest_link.c:22 LinkContest_SendBlock
SCHEMAS.game3_contest_block = inner3(function(m)
  local key = Wire.str(m.key, nil, MAX_NAME)
  if not key then return nil end
  return { key = key, from = Wire.num(m.from, nil, 0, MAX_SEAT), data = blockData(m.data) }
end)

SCHEMAS.game3_contest_abort = inner3(function(m)
  return { from = Wire.num(m.from, nil, 0, MAX_SEAT) }
end)

-- pokeemerald/src/battle_tower.c:2588
SCHEMAS.game3_tower_challenge = inner3(function(m)
  return { from = Wire.num(m.from, nil, 0, MAX_SEAT), challengeNum = Wire.num(m.challengeNum, 0, 0, 65535) }
end)

-- pokeemerald/src/battle_tower.c:2625
SCHEMAS.game3_tower_trainers = inner3(function(m)
  return {
    from = Wire.num(m.from, nil, 0, MAX_SEAT),
    ids = Wire.list(m.ids, 14, function(v) return Wire.num(v, nil, 0, 65535) end),
  }
end)

-- pokeemerald/src/battle_main.c:1302
SCHEMAS.game3_tower_setup = inner3(function(m)
  return {
    from = Wire.num(m.from, nil, 0, MAX_SEAT),
    battleNum = Wire.num(m.battleNum, 0, 0, 255),
    name = Wire.str(m.name, nil, MAX_NAME),
    trainerId = Wire.num(m.trainerId, 0, 0, MAX_U32),
    gender = Wire.num(m.gender, 0, 0, 1),
    seed = Wire.num(m.seed, nil, 0, MAX_U32),
    party = party3(m.party),
    foes = m.foes ~= nil and Wire.list(m.foes, 2, function(f)
      if type(f) ~= "table" then return nil end
      return {
        name = Wire.str(f.name, nil, MAX_NAME),
        trainerId = Wire.num(f.trainerId, 0, 0, 65535),
        gender = Wire.num(f.gender, 0, 0, 1),
        party = party3(f.party),
      }
    end) or nil,
  }
end)

local function blender(extra)
  return inner3(function(m)
    local out = {
      senderSeat = Wire.num(m.senderSeat, nil, 0, MAX_SEAT),
      round = Wire.num(m.round, 0, 0, MAX_INT),
    }
    for k, kind in pairs(extra) do
      if kind == "num" then out[k] = Wire.num(m[k], nil, -MAX_INT, MAX_INT)
      elseif kind == "bool" then out[k] = Wire.bool(m[k], nil)
      else out[k] = Wire.str(m[k], nil, MAX_NAME) end
    end
    return out
  end)
end

-- pokeemerald/src/berry_blender.c:1047
SCHEMAS.game3_blender_abort = blender({ reason = "str" })
SCHEMAS.game3_blender_berry = blender({ itemId = "num" })
SCHEMAS.game3_blender_frame = blender({ frame = "num", score = "num" })
SCHEMAS.game3_blender_continue = blender({ choice = "num" })
SCHEMAS.game3_blender_continue_result = blender({ continue = "bool", reason = "num", reasonSeat = "num" })

-- pokeemerald/src/field_specials.c:3651
SCHEMAS.game3_tower_retire_choice = inner3(function(m)
  return { choice = Wire.num(m.choice, nil, 0, 1) }
end)
SCHEMAS.game3_tower_retire_result = inner3(function(m)
  return { result = Wire.num(m.result, nil, 0, 3) }
end)
SCHEMAS.game3_tower_retire_standby = inner3(function()
  return {}
end)

local MIX_DEPTH = 16
local MIX_STRING = 512

local function mixPlain(v, depth)
  if type(v) ~= "table" or depth > MIX_DEPTH then return nil end
  local out = {}
  for k, val in pairs(v) do
    local kt, vt = type(k), type(val)
    if kt == "string" and #k <= MAX_STRING then
      if vt == "string" then out[k] = Wire.str(val, nil, MIX_STRING)
      elseif vt == "number" then
        if val == val then out[k] = val end
      elseif vt == "boolean" then out[k] = val
      elseif vt == "table" then out[k] = mixPlain(val, depth + 1) end
    end
  end
  return out
end

-- pokeemerald/src/record_mixing.c:220
SCHEMAS.rse_record_mix = inner3(function(m)
  return { spot = Wire.num(m.spot, nil, 0, 3), packet = mixPlain(m.packet, 0) }
end)

SCHEMAS.game3_battle_outcome = inner3(function(m)
  return {
    outcome = Wire.num(m.outcome, nil, 0, 255),
    turn = Wire.num(m.turn, nil, 0, MAX_INT),
  }
end)

SCHEMAS.game3_battle_hash = inner3(function(m)
  local parts
  if type(m.parts) == "table" then
    parts = {
      actives = Wire.str(m.parts.actives, nil, MAX_STRING),
      volatile = Wire.str(m.parts.volatile, nil, MAX_STRING),
      bench = Wire.str(m.parts.bench, nil, MAX_STRING),
      field = Wire.str(m.parts.field, nil, MAX_STRING),
      rng = Wire.str(m.parts.rng, nil, MAX_STRING),
    }
  end
  return {
    turn = Wire.num(m.turn, 0, 0, MAX_INT),
    value = Wire.str(m.value, nil, MAX_STRING),
    parts = parts,
  }
end)

SCHEMAS.game3_trade_cmd = inner3(function(m)
  return {
    cmd = Wire.num(m.cmd, nil, 0, 65535),
    cursor = Wire.num(m.cursor, nil, 0, 255),
  }
end)

SCHEMAS.game3_trade_party = inner3(function(m)
  return {
    party = party3(m.party),
    name = Wire.str(m.name, nil, MAX_NAME),
    trainerId = Wire.num(m.trainerId, 0, 0, MAX_U32),
    gender = Wire.num(m.gender, 0, 0, 1),
    version = Wire.num(m.version, nil, 0, 255) or Wire.str(m.version, nil, MAX_NAME),
    progressFlags = Wire.num(m.progressFlags, nil, 0, MAX_INT),
    giftRibbons = m.giftRibbons ~= nil and Wire.list(m.giftRibbons, 11, function(v) return Wire.num(v, 0, 0, 255) end) or nil,
  }
end)

SCHEMAS.game3_trade_mon = inner3(function(m)
  return {
    mon = Wire.mon3(m.mon),
    mail = Wire.plain(m.mail, MAX_EXTRA_DEPTH - 3),
    name = Wire.str(m.name, nil, MAX_NAME),
    trainerId = Wire.num(m.trainerId, 0, 0, MAX_U32),
  }
end)

local function confirmDigest(m)
  return { digest = Wire.digest(m.digest) }
end

SCHEMAS.game3_trade_confirm = inner3(confirmDigest)
SCHEMAS.trade_confirm = inner3(confirmDigest)

SCHEMAS.trade_commit = inner3(function(m)
  return {
    n = Wire.num(m.n, 0, 0, MAX_INT),
    digests = Wire.list(m.digests, 2, Wire.digest),
  }
end)

SCHEMAS.trade_abort = inner3(function(m)
  return {
    n = Wire.num(m.n, 0, 0, MAX_INT),
    why = Wire.str(m.why, nil, MAX_NAME),
  }
end)

SCHEMAS.game3_union_hello = inner3(function(m)
  return {
    name = Wire.str(m.name, nil, MAX_NAME),
    gender = Wire.num(m.gender, 0, 0, 1),
    trainerId = Wire.num(m.trainerId, 0, 0, MAX_U32),
    activity = Wire.num(m.activity, nil, 0, 255),
  }
end)

SCHEMAS.game3_union_bye = inner3(function(m)
  return { reason = Wire.str(m.reason, nil, MAX_NAME) }
end)

SCHEMAS.game3_union_request = inner3(function(m)
  return {
    activity = Wire.num(m.activity, nil, 0, 255),
    name = Wire.str(m.name, nil, MAX_NAME),
  }
end)

SCHEMAS.game3_union_response = inner3(function(m)
  return { accept = Wire.bool(m.accept, false) }
end)

SCHEMAS.game3_chat_line = inner3(function(m)
  return {
    name = Wire.chars(m.name, nil, MAX_CHAT_NAME),
    text = Wire.chars(m.text, "", MAX_CHAT_TEXT),
  }
end)

SCHEMAS.game3_chat_bye = inner3(function() return {} end)

SCHEMAS.game3_mg_ready = inner3(function(m)
  return {
    species = Wire.num(m.species, nil, 0, 65535),
    partySlot = Wire.num(m.partySlot, nil, 0, 255),
    name = Wire.chars(m.name, nil, MAX_CHAT_NAME),
    trainerId = Wire.num(m.trainerId, nil, 0, 65535),
    gender = Wire.num(m.gender, nil, 0, 1),
  }
end)

local function mgPlayer(v)
  if type(v) ~= "table" then return nil end
  return {
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
    name = Wire.str(v.name, nil, MAX_NAME),
    trainerId = Wire.num(v.trainerId, 0, 0, MAX_U32),
    gender = Wire.num(v.gender, 0, 0, 1),
    species = Wire.num(v.species, nil, 0, 65535),
  }
end

SCHEMAS.game3_mg_start = inner3(function(m)
  return {
    game = Wire.str(m.game, nil, MAX_NAME),
    seed = Wire.num(m.seed, nil, 0, MAX_U32),
    epoch = Wire.num(m.epoch, nil, 0, MAX_INT),
    players = Wire.list(m.players, MAX_SEATS, mgPlayer),
  }
end)

SCHEMAS.game3_mg_state = inner3(function(m)
  return {
    f = Wire.num(m.f, 0, 0, MAX_INT),
    e = Wire.num(m.e, 0, 0, MAX_INT),
    s = Wire.plain(m.s, MAX_EXTRA_DEPTH - 3),
  }
end)

SCHEMAS.game3_mg_input = inner3(function(m)
  local i = m.i
  if type(i) == "table" then
    i = Wire.plain(i, MAX_EXTRA_DEPTH - 2)
  else
    i = Wire.num(i, nil)
  end
  return { f = Wire.num(m.f, 0, 0, MAX_INT), i = i }
end)

local function mgScore(v)
  if type(v) ~= "table" then return nil end
  return {
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
    score = Wire.num(v.score, 0, 0, MAX_INT),
    stats = Wire.plain(v.stats, MAX_EXTRA_DEPTH - 2),
  }
end

local function mgPowder(v)
  if type(v) ~= "table" then return nil end
  return {
    seat = Wire.num(v.seat, nil, 0, MAX_SEAT),
    amount = Wire.num(v.amount, 0, 0, MAX_INT),
  }
end

SCHEMAS.game3_mg_result = inner3(function(m)
  return {
    game = Wire.str(m.game, nil, MAX_NAME),
    results = Wire.list(m.results, MAX_SEATS, mgScore),
    powder = Wire.list(m.powder, MAX_SEATS, mgPowder),
  }
end)

SCHEMAS.game3_mg_bye = inner3(function(m)
  return { reason = Wire.str(m.reason, nil, MAX_NAME) }
end)

SCHEMAS.game3_mg_leader = inner3(function(m)
  return {
    prev = Wire.num(m.prev, nil, -1, MAX_SEAT),
    epoch = Wire.num(m.epoch, 0, 0, MAX_INT),
  }
end)

local XG_PAYLOAD_DEPTH = 8
local XG_PAYLOAD_STRING = 256
local XG_WHY = 40

local function xgPayload(v, depth)
  if type(v) ~= "table" or depth > XG_PAYLOAD_DEPTH then return nil end
  local out = {}
  for k, val in pairs(v) do
    local kt, vt = type(k), type(val)
    if (kt == "string" and #k <= MAX_STRING) or (kt == "number" and k == k) then
      if vt == "string" then out[k] = Wire.str(val, nil, XG_PAYLOAD_STRING)
      elseif vt == "number" then
        if val == val then out[k] = val end
      elseif vt == "boolean" then out[k] = val
      elseif vt == "table" then out[k] = xgPayload(val, depth + 1) end
    end
  end
  return out
end

local function xgInner(fn)
  return function(m)
    local out = fn(m)
    if not out then return nil end
    out.seat = seatNum(m.seat)
    out.relay = Wire.bool(m.relay, nil)
    return out
  end
end

local function xgRev(v)
  return Wire.num(v, nil, 0, MAX_INT)
end

SCHEMAS.xg_caps = xgInner(function(m)
  return { caps = Wire.caps(m.caps) }
end)

SCHEMAS.xg_rules = xgInner(function(m)
  local out = xgRules(m)
  out.rev = xgRev(m.rev)
  return out
end)

SCHEMAS.xg_blocked = xgInner(function(m)
  return { rev = xgRev(m.rev), why = Wire.str(m.why, nil, MAX_NAME) }
end)

SCHEMAS.xg_counter = xgInner(function(m)
  return { rev = xgRev(m.rev), gen = Wire.num(m.gen, nil, 1, 3) }
end)

SCHEMAS.xg_roster = xgInner(function(m)
  return { rev = xgRev(m.rev), size = Wire.num(m.size, nil, 1, MAX_TEAM),
           digest16 = Wire.digest(m.digest16) }
end)

SCHEMAS.xg_size = xgInner(function(m)
  return { rev = xgRev(m.rev), size = Wire.num(m.size, nil, 1, MAX_TEAM) }
end)

SCHEMAS.xg_size_req = SCHEMAS.xg_size

SCHEMAS.xg_offer = xgInner(function(m)
  return { rev = xgRev(m.rev), offerRev = Wire.num(m.offerRev, nil, 0, MAX_INT),
           payload = xgPayload(m.payload, 0), digest16 = Wire.digest(m.digest16) }
end)

SCHEMAS.xg_rev = xgInner(function(m)
  return { rev = xgRev(m.rev), cause = Wire.str(m.cause, nil, MAX_NAME) }
end)

SCHEMAS.xg_ready = xgInner(function(m)
  return { rev = xgRev(m.rev), digest16 = Wire.digest(m.digest16) }
end)

SCHEMAS.xg_go = xgInner(function(m)
  return {
    rev = xgRev(m.rev),
    seed = Wire.num(m.seed, nil, 0, MAX_INT),
    match = Wire.str(m.match, nil, MAX_NAME),
    mode = xgMode(m.mode),
    ruleset = Wire.str(m.ruleset, nil, MAX_NAME),
    size = Wire.num(m.size, nil, 1, MAX_TEAM),
    gen = Wire.num(m.gen, nil, 1, 3),
    dexMax = Wire.num(m.dexMax, nil, 1, 65535),
    moveMax = Wire.num(m.moveMax, nil, 1, 65535),
    moveGen = Wire.num(m.moveGen, nil, 1, 3),
  }
end)

SCHEMAS.xg_cancel = xgInner(function(m)
  return { why = Wire.str(m.why, nil, XG_WHY) }
end)

SCHEMAS.xg_closed = xgInner(function(m)
  return { why = Wire.str(m.why, nil, MAX_NAME), detail = Wire.str(m.detail, nil, XG_WHY) }
end)

SCHEMAS.xg_nack = xgInner(function(m)
  return {
    of = Wire.str(m.of, nil, MAX_NAME),
    why = Wire.str(m.why, nil, MAX_NAME),
    rev = xgRev(m.rev),
    current = xgRev(m.current),
  }
end)

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
  elseif kind:sub(1, 6) == "game3_" then
    return nil
  else
    out = passthrough(msg)
  end
  out.type = kind
  return out
end

Wire.sanitize = sanitize

return Wire

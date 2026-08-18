local Wire = {}

local MAX_INT = 2147483647
local MAX_STRING = 64
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
SCHEMAS.forfeit = function() return {} end

SCHEMAS.hosted = function(m)
  return { code = Wire.str(m.code, nil, MAX_NAME) }
end
SCHEMAS.paired = function() return {} end
SCHEMAS.peer_gone = function() return {} end
SCHEMAS.join_error = function(m)
  return { reason = Wire.str(m.reason, "", MAX_STRING) }
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
  return out
end

local function match(v)
  if type(v) ~= "table" then return nil end
  return {
    a = name(v.a), b = name(v.b), winner = name(v.winner),
    bye = Wire.bool(v.bye, false),
    state = Wire.str(v.state, nil, MAX_STRING),
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
  return {
    opponent = name(m.opponent),
    round = Wire.num(m.round, 0, 0, MAX_ROUNDS),
    turnLimit = Wire.num(m.turnLimit, nil, 0, 65535),
    role = Wire.str(m.role, "", MAX_STRING),
  }
end

SCHEMAS.match_start_spectate = function(m)
  return {
    round = Wire.num(m.round, 0, 0, MAX_ROUNDS),
    playerHost = name(m.playerHost),
    playerGuest = name(m.playerGuest),
  }
end

SCHEMAS.tournament_bye = function(m)
  return { round = Wire.num(m.round, 0, 0, MAX_ROUNDS) }
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

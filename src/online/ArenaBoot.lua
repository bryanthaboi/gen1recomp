local Protocol = require("src.link.Protocol")

local ArenaBoot = {}

local VERSIONS = {
  red = true, blue = true, yellow = true,
  gold = true, silver = true, crystal = true,
  firered = true, leafgreen = true,
}

local GEN3_VERSIONS = { firered = true, leafgreen = true }

local ROLES = { host = true, guest = true, seat2 = true, seat3 = true,
                spectator = true }

local TWO_SEAT_ROLES = { host = true, guest = true, spectator = true }

local ROLE_SEAT = { host = 0, guest = 1, seat2 = 2, seat3 = 3 }

local G3_MODES = { g3_single = "single", g3_double = "double", g3_multi = "multi" }

local KINDS = { vanilla = true, cart = true }

local function isCallable(v)
  if type(v) == "function" then return true end
  if type(v) ~= "table" then return false end
  local mt = getmetatable(v)
  return type(mt) == "table" and type(mt.__call) == "function"
end

local function hasMethod(obj, name)
  if type(obj) ~= "table" then return false end
  return isCallable(obj[name])
end

local function isPackedParty(v)
  if type(v) ~= "table" then return false end
  for _, mon in ipairs(v) do
    if type(mon) ~= "table" or type(mon.species) ~= "string" then return false end
  end
  return true
end

local function isPackedParty3(v)
  if type(v) ~= "table" then return false end
  for _, mon in ipairs(v) do
    if type(mon) ~= "table" or type(mon.species) ~= "number" then return false end
  end
  return true
end

local function isG3Ruleset(id)
  for _, known in ipairs(require("src.online.Protocol2").G3_RULESETS) do
    if known == id then return true end
  end
  return false
end

local function level(v)
  return type(v) == "number" and v >= 1 and v <= 100 and math.floor(v) == v
end

local function normaliseRule(rule)
  if rule == nil then rule = {} end
  if type(rule) ~= "table" then return nil, "rule must be a table" end
  local size = rule.partySize
  if size == nil then size = 6 end
  if type(size) ~= "number" or size < 1 or size > 6 or math.floor(size) ~= size then
    return nil, "rule.partySize must be 1..6"
  end
  if rule.minLevel ~= nil and not level(rule.minLevel) then
    return nil, "rule.minLevel must be 1..100"
  end
  if rule.maxLevel ~= nil and not level(rule.maxLevel) then
    return nil, "rule.maxLevel must be 1..100"
  end
  if rule.minLevel and rule.maxLevel and rule.minLevel > rule.maxLevel then
    return nil, "rule.minLevel is above rule.maxLevel"
  end
  if rule.forceLevel ~= nil and not level(rule.forceLevel) then
    return nil, "rule.forceLevel must be 1..100"
  end
  return {
    partySize = size,
    minLevel = rule.minLevel,
    maxLevel = rule.maxLevel,
    forceLevel = rule.forceLevel,
  }
end

function ArenaBoot.profile(fields)
  if type(fields) ~= "table" then return nil, "profile must be a table" end
  local engine = fields.engine
  if engine ~= 1 and engine ~= 2 and engine ~= 3 then
    return nil, "profile.engine must be 1, 2 or 3"
  end
  if type(fields.version) ~= "string" or not VERSIONS[fields.version]
      or (engine == 3) ~= (GEN3_VERSIONS[fields.version] == true) then
    return nil, "profile.version is not a known game"
  end
  local kind = fields.kind or "vanilla"
  if not KINDS[kind] then return nil, "profile.kind must be vanilla or cart" end
  if engine == 3 then
    if kind ~= "vanilla" then return nil, "a Gen 3 profile must be vanilla" end
    if not isG3Ruleset(fields.rulesetId) then
      return nil, "profile.rulesetId is not a Gen 3 ruleset"
    end
  end
  if kind == "cart" then
    local cart = fields.cart
    if type(cart) ~= "table" or type(cart.id) ~= "string" or cart.id == ""
        or type(cart.hash) ~= "string" or cart.hash == "" then
      return nil, "a cart profile needs cart.id and cart.hash"
    end
  end
  if fields.engineVersion ~= nil and type(fields.engineVersion) ~= "string" then
    return nil, "profile.engineVersion must be a string"
  end
  if fields.rulesetId ~= nil and type(fields.rulesetId) ~= "string" then
    return nil, "profile.rulesetId must be a string"
  end
  local rule, ruleErr = normaliseRule(fields.rule)
  if not rule then return nil, ruleErr end
  local cart = nil
  if kind == "cart" then
    cart = {
      id = fields.cart.id,
      version = fields.cart.version,
      hash = fields.cart.hash,
    }
  end
  return {
    engine = engine,
    version = fields.version,
    engineVersion = fields.engineVersion,
    apiVersion = fields.apiVersion,
    fingerprint = fields.fingerprint,
    rulesetId = fields.rulesetId,
    kind = kind,
    cart = cart,
    rule = rule,
  }
end

local function normaliseTeam(team, size)
  if team == nil then return nil end
  if type(team) ~= "table" then return nil, "team must be an array of party indices" end
  local seen, out = {}, {}
  for _, index in ipairs(team) do
    if type(index) ~= "number" or index < 1 or index > 6 or math.floor(index) ~= index then
      return nil, "team holds a party index outside 1..6"
    end
    if seen[index] then return nil, "team repeats a party index" end
    seen[index] = true
    out[#out + 1] = index
  end
  if #out == 0 then return nil, "team is empty" end
  if #out > size then return nil, "team is longer than the rule allows" end
  return out
end

local function normaliseTeam3(team, size)
  if team == nil then return nil end
  if type(team) ~= "table" then return nil, "team must be an array of picks" end
  local seen, out = {}, {}
  for _, ref in ipairs(team) do
    local key, pick
    if type(ref) == "number" then
      if ref < 1 or ref > 6 or math.floor(ref) ~= ref then
        return nil, "team holds a party index outside 1..6"
      end
      key, pick = "party|" .. ref, ref
    elseif type(ref) == "table" and ref.where == "box" then
      local box, index = tonumber(ref.box), tonumber(ref.index)
      if not (box and index and box >= 1 and box <= 14 and index >= 1 and index <= 30
          and box == math.floor(box) and index == math.floor(index)) then
        return nil, "team holds a box pick outside the PC"
      end
      key, pick = ("box|%d|%d"):format(box, index), { where = "box", box = box, index = index }
    else
      return nil, "team holds something that is not a pick"
    end
    if seen[key] then return nil, "team repeats a pick" end
    seen[key] = true
    out[#out + 1] = pick
  end
  if #out == 0 then return nil, "team is empty" end
  if #out > size then return nil, "team is longer than the rule allows" end
  return out
end

local function players3(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, row in ipairs(list) do
    if type(row) == "table" and tonumber(row.seat) then
      out[#out + 1] = { id = row.id, name = row.name, seat = tonumber(row.seat) }
    end
  end
  table.sort(out, function(a, b) return a.seat < b.seat end)
  return out
end

local function spec3(fields, profile)
  local role = fields.role
  if type(role) ~= "string" or not ROLES[role] then
    return nil, "role must be host, guest, seat2, seat3 or spectator"
  end
  local mode = G3_MODES[profile.rulesetId]
  if not mode then return nil, "that ruleset is not a battle" end
  local seats = fields.seats
  if seats ~= 2 and seats ~= 4 then return nil, "seats must be 2 or 4" end
  if (mode == "multi") ~= (seats == 4) then
    return nil, "a multi battle has 4 seats, every other battle 2"
  end
  local spectating = role == "spectator"
  local seat = fields.seat
  if spectating then
    if seat ~= nil then return nil, "a spectator has no seat" end
    if fields.slotId ~= nil and type(fields.slotId) ~= "string" then
      return nil, "slotId must be a string"
    end
  else
    if type(seat) ~= "number" or seat ~= ROLE_SEAT[role] or seat >= seats then
      return nil, "seat does not match the role"
    end
    if type(fields.slotId) ~= "string" or fields.slotId == "" then
      return nil, "slotId is required"
    end
  end
  local team, teamErr = normaliseTeam3(fields.team, profile.rule.partySize)
  if fields.team ~= nil and not team then return nil, teamErr end
  if type(fields.seed) ~= "number" then return nil, "seed must be a number" end
  local session = fields.session
  if not (hasMethod(session, "send") and hasMethod(session, "poll")
      and hasMethod(session, "close")) then
    return nil, "session must provide send, poll and close"
  end
  if fields.onDone ~= nil and not isCallable(fields.onDone) then
    return nil, "onDone must be a function"
  end
  if fields.myParty ~= nil and not isPackedParty3(fields.myParty) then
    return nil, "myParty must be a packed Gen 3 party"
  end
  local onDone = fields.onDone
  return {
    profile = profile,
    role = role,
    seat = seat,
    seats = seats,
    slotId = fields.slotId,
    team = team,
    seed = fields.seed,
    match = fields.match,
    room = fields.room,
    players = players3(fields.players),
    myParty = fields.myParty,
    session = session,
    mode = mode,
    onDone = function(result)
      if onDone then onDone(result) end
    end,
  }
end

function ArenaBoot.spec(fields)
  if type(fields) ~= "table" then return nil, "spec must be a table" end
  local profile, profileErr = ArenaBoot.profile(fields.profile)
  if not profile then return nil, profileErr end
  if profile.engine == 3 then return spec3(fields, profile) end

  local role = fields.role
  if type(role) ~= "string" or not TWO_SEAT_ROLES[role] then
    return nil, "role must be host, guest or spectator"
  end

  local spectating = role == "spectator"
  if not spectating then
    if type(fields.slotId) ~= "string" or fields.slotId == "" then
      return nil, "slotId is required"
    end
  elseif fields.slotId ~= nil and type(fields.slotId) ~= "string" then
    return nil, "slotId must be a string"
  end

  local team, teamErr = normaliseTeam(fields.team, profile.rule.partySize)
  if fields.team ~= nil and not team then return nil, teamErr end

  if type(fields.seed) ~= "number" then return nil, "seed must be a number" end

  local session = fields.session
  if not (hasMethod(session, "send") and hasMethod(session, "poll")
      and hasMethod(session, "close")) then
    return nil, "session must provide send, poll and close"
  end

  if fields.onDone ~= nil and not isCallable(fields.onDone) then
    return nil, "onDone must be a function"
  end

  if spectating then
    if not isPackedParty(fields.hostParty) or not isPackedParty(fields.guestParty) then
      return nil, "a spectator spec needs hostParty and guestParty"
    end
  else
    if not isPackedParty(fields.theirParty) then
      return nil, "theirParty must be a packed party"
    end
    if fields.myParty ~= nil and not isPackedParty(fields.myParty) then
      return nil, "myParty must be a packed party"
    end
  end

  local onDone = fields.onDone
  return {
    profile = profile,
    role = role,
    slotId = fields.slotId,
    team = team,
    seed = fields.seed,
    peerName = fields.peerName or "FOE",
    hostName = fields.hostName or "HOST",
    guestName = fields.guestName or "GUEST",
    myParty = fields.myParty,
    theirParty = fields.theirParty,
    hostParty = fields.hostParty,
    guestParty = fields.guestParty,
    session = session,
    onDone = function(result)
      if onDone then onDone(result) end
    end,
  }
end

function ArenaBoot.battleOpts(spec)
  if type(spec) ~= "table" or type(spec.profile) ~= "table" then
    return nil, "spec must carry a profile"
  end
  local rule = spec.profile.rule or {}
  if spec.role == "spectator" then
    return {
      hostParty = spec.hostParty,
      guestParty = spec.guestParty,
      hostName = spec.hostName,
      guestName = spec.guestName,
      seed = spec.seed,
      ruleset = spec.profile.rulesetId,
      verdict = "full",
      strict = true,
      forceLevel = rule.forceLevel,
      keepNetOpen = true,
    }
  end
  return {
    myParty = spec.myParty,
    theirParty = spec.theirParty,
    theirName = spec.peerName,
    role = spec.role,
    seed = spec.seed,
    ruleset = spec.profile.rulesetId,
    verdict = "full",
    strict = true,
    forceLevel = rule.forceLevel,
    keepNetOpen = true,
  }
end

local function packOwnParty3(game, spec)
  if isPackedParty3(spec.myParty) and #spec.myParty > 0 then return spec.myParty end
  local session = game and game.session
  local party = (type(session) == "table" and type(session.party) == "table"
    and session.party) or (game and game.save and game.save.party)
  if type(party) ~= "table" then return nil, "no party to send" end
  local size = (spec.profile.rule and spec.profile.rule.partySize) or 6
  local mons = {}
  local TeamPick = require("src.online.TeamPick")
  local source = { party = party, generation = 3,
    save = game and game.save or nil }
  local team = type(spec.team) == "table" and spec.team or {}
  for _, ref in ipairs(team) do
    local mon = TeamPick.monAt(source, ref)
    if not mon then return nil, "that team isn't in this save" end
    mons[#mons + 1] = Protocol.packMon3(mon)
  end
  if #team == 0 then
    local indices = {}
    for index = 1, math.min(#party, size) do indices[index] = index end
    mons = Protocol.packParty3(party, indices)
  end
  if #mons == 0 then return nil, "no party to send" end
  spec.myParty = mons
  return mons
end

function ArenaBoot.packOwnParty(game, spec)
  if type(spec) ~= "table" then return nil, "spec must be a table" end
  if spec.role == "spectator" then return nil end
  if spec.profile and spec.profile.engine == 3 then return packOwnParty3(game, spec) end
  if isPackedParty(spec.myParty) and #spec.myParty > 0 then return spec.myParty end
  local party = game and game.save and game.save.party
  if type(party) ~= "table" then return nil, "no party to send" end
  local size = (spec.profile and spec.profile.rule and spec.profile.rule.partySize) or 6
  local indices = {}
  for _, index in ipairs(spec.team or {}) do
    if party[index] then indices[#indices + 1] = index end
  end
  if #indices == 0 then
    for index = 1, math.min(#party, size) do indices[index] = index end
  end
  if #indices == 0 then return nil, "no party to send" end
  spec.myParty = (spec.profile and spec.profile.engine == 2)
    and Protocol.packParty2(party, indices)
    or Protocol.packParty(party, indices)
  return spec.myParty
end

return ArenaBoot

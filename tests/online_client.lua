--   luajit tests/online_client.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Protocol2 = require("src.online.Protocol2")
local Wire = require("src.link.Wire")

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end
local function eq(got, want, msg)
  check(got == want, ("%s (got %s, want %s)"):format(msg, tostring(got),
                                                     tostring(want)))
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = copy(val) end
  return out
end

local savedGetTime = love.timer.getTime
local CLOCK = 0
love.timer.getTime = function() return CLOCK end

-- ---------------------------------------------------------------- harness

local function newTransport()
  local t = { paired = true, closed = false, error = nil,
              inbox = {}, outbox = {} }
  function t:update() end
  function t:poll()
    local messages = self.inbox
    self.inbox = {}
    return messages
  end
  function t:send(msg) table.insert(self.outbox, copy(msg)) end
  function t:close() self.closed = true end
  return t
end

local function newClientModule()
  package.loaded["src.online.Client"] = nil
  local Client = require("src.online.Client")
  Client.reset()
  return Client
end

local PROFILE = {
  engine = 1, version = "red", engineVersion = "0.0.0-dev",
  apiVersion = "2", fingerprint = "abc123", rulesetId = "gen1_faithful",
  kind = "vanilla", rule = { partySize = 1 },
}

local function rid(n) return ("r%016x"):format(n) end
local function tid(n) return ("t%016x"):format(n) end

local ROOM1 = rid(0xabc234)
local TOUR1 = tid(0x234)

local Relay = {}
Relay.__index = Relay

local function newRelay()
  return setmetatable({ seats = {}, room = nil }, Relay)
end

function Relay:seat(id, name)
  local seat = { id = id, name = name, transport = newTransport(), ack = 0 }
  self.seats[id] = seat
  return seat
end

function Relay:to(seat, msg)
  if not seat then return end
  table.insert(seat.transport.inbox, copy(msg))
end

function Relay:welcome(seat, resumed)
  self:to(seat, { type = "lobby_welcome", session = "S-" .. seat.id,
                  you = { id = seat.id, name = seat.name, verified = true },
                  serverTime = 1000, heartbeatMs = 10000,
                  resumed = resumed == true })
end

function Relay:sideOf(id)
  local room = self.room
  if not room then return nil end
  if room.players[1] and room.players[1].id == id then return "host" end
  if room.players[2] and room.players[2].id == id then return "guest" end
  return nil
end

function Relay:roomStateMsg()
  local room = self.room
  local players = {}
  for i, p in ipairs(room.players) do
    table.insert(players, { id = p.id, name = p.name, verified = true,
                            ready = p.ready or false, online = true,
                            seat = i - 1 })
  end
  local spectators = {}
  for _, sp in ipairs(room.spectators) do
    table.insert(spectators, { id = sp.id, name = sp.name, verified = false })
  end
  return { type = "room_state", room = room.room, players = players,
           spectators = spectators, stage = room.stage,
           profile = room.profile, host = room.host, seed = room.seed,
           rule = room.profile and room.profile.rule or nil,
           intent = "battle", maxSpectators = 8, match = room.match,
           engine = 1, seats = 2, locked = false, listed = true,
           origin = room.origin or "create", deadlines = {} }
end

function Relay:broadcast(msg)
  local room = self.room
  for _, p in ipairs(room.players) do self:to(self.seats[p.id], msg) end
  for _, sp in ipairs(room.spectators) do self:to(self.seats[sp.id], msg) end
end

function Relay:roomState(stage)
  local room = self.room
  if not room then return end
  room.stage = stage or room.stage
  self:broadcast(self:roomStateMsg())
end

function Relay:startMatch(token)
  local room = self.room
  room.matchNo = (room.matchNo or 0) + 1
  room.match = token or (room.room .. "-m" .. room.matchNo)
  room.seed = 4242
  room.log = {}
  room.seq = 0
  room.reports = {}
  self:roomState("battling")
  local host, guest = room.players[1], room.players[2]
  local base = { seed = room.seed, ruleset = room.profile.rulesetId,
                 rule = room.profile.rule, hostName = host.name,
                 guestName = guest.name, hostParty = host.party,
                 guestParty = guest.party, match = room.match,
                 room = room.room, seats = 2, engine = 1,
                 players = { { id = host.id, name = host.name, seat = 0 },
                             { id = guest.id, name = guest.name, seat = 1 } } }
  local function start(seat, extra)
    local msg = {}
    for k, v in pairs(base) do msg[k] = v end
    for k, v in pairs(extra) do msg[k] = v end
    self:to(seat, msg)
  end
  start(self.seats[host.id], { type = "match_start", role = "host", seat = 0,
                               peerName = guest.name, theirParty = guest.party })
  start(self.seats[guest.id], { type = "match_start", role = "guest", seat = 1,
                                peerName = host.name, theirParty = host.party })
  for _, sp in ipairs(room.spectators) do
    start(self.seats[sp.id], { type = "match_start_spectate",
                               role = "spectator" })
  end
end

function Relay:resolve(how, winnerSide)
  local room = self.room
  local winner = winnerSide and room.players[winnerSide == "host" and 1 or 2]
  self:broadcast({ type = "room_result", match = room.match, room = room.room,
                   winner = winner and winner.name or nil,
                   winnerId = winner and winner.id or nil, how = how,
                   winnerSide = winnerSide and (winnerSide == "host" and 0 or 1) or nil,
                   winners = winner and { winner.id } or {} })
  for _, p in ipairs(room.players) do p.ready = false end
  room.seed = nil
  room.reports = {}
  self:roomState("waiting")
  local entry = self.tour and self.tour.liveEntry
  if entry and entry.match == room.match then
    entry.state = "done"
    entry.how = how
    entry.winner = winner and winner.id or entry.a
    local loser = entry.winner == entry.a and entry.b or entry.a
    for _, p in ipairs(self.tour.players) do
      if p.id == loser then p.eliminated = true end
    end
    self.tour.liveEntry = nil
    self.tour.live = nil
    self:tourState()
    self:tourAdvance()
  end
end

function Relay:fanout(fromId, clientSeq, inner)
  local room = self.room
  if not room then return end
  local side = self:sideOf(fromId)
  if not side then return end
  room.clientSeq = room.clientSeq or {}
  if clientSeq and room.clientSeq[fromId] and clientSeq <= room.clientSeq[fromId] then
    room.duplicates = (room.duplicates or 0) + 1
    return
  end
  if clientSeq then room.clientSeq[fromId] = clientSeq end
  room.seq = room.seq + 1
  local seat = side == "host" and 0 or 1
  local entry = { seq = room.seq, clientSeq = clientSeq, side = side,
                  seat = seat, msg = copy(inner) }
  table.insert(room.log, entry)
  for _, p in ipairs(room.players) do
    if p.id ~= fromId then
      self:to(self.seats[p.id], { type = "room_msg", seq = entry.seq,
                                  clientSeq = clientSeq, seat = seat,
                                  msg = copy(inner) })
    end
  end
  for _, sp in ipairs(room.spectators) do
    self:to(self.seats[sp.id], { type = "room_msg", seq = entry.seq,
                                 clientSeq = clientSeq, side = side,
                                 seat = seat, msg = copy(inner) })
  end
  if inner.type == "forfeit" then
    room.reports[side] = "lose"
    self:resolve("forfeit", side == "host" and "guest" or "host")
  end
end

function Relay:replay(seat, from)
  local room = self.room
  local side = self:sideOf(seat.id)
  local msgs = {}
  for _, e in ipairs(room.log or {}) do
    if e.seq > from and not (side and e.side == side) then
      table.insert(msgs, side
        and { seq = e.seq, clientSeq = e.clientSeq, seat = e.seat,
              msg = copy(e.msg) }
        or { seq = e.seq, clientSeq = e.clientSeq, side = e.side,
             seat = e.seat, msg = copy(e.msg) })
    end
  end
  self:to(seat, { type = "room_replay", from = from, msgs = msgs,
                  yourSeq = (room.clientSeq or {})[seat.id] or 0 })
end


-- ------------------------------------------------------------- tournaments

local CHILD_ROOMS = { rid(0xc1), rid(0xc2), rid(0xc3), rid(0xc4), rid(0xc5),
                      rid(0xc6), rid(0xc7), rid(0xc8) }

function Relay:tourSeats()
  local out = {}
  for _, p in ipairs(self.tour.players) do out[#out + 1] = self.seats[p.id] end
  for _, sp in ipairs(self.tour.spectators) do
    out[#out + 1] = self.seats[sp.id]
  end
  return out
end

function Relay:tourBroadcast(msg)
  for _, seat in ipairs(self:tourSeats()) do self:to(seat, msg) end
end

function Relay:tourNameOf(id)
  for _, p in ipairs(self.tour.players) do
    if p.id == id then return p.name end
  end
  return nil
end

function Relay:tourStateMsg()
  local t = self.tour
  local players, spectators, bracket = {}, {}, {}
  for _, p in ipairs(t.players) do
    players[#players + 1] = { id = p.id, name = p.name, verified = true,
                              online = true, eliminated = p.eliminated == true }
  end
  for _, sp in ipairs(t.spectators) do
    spectators[#spectators + 1] = { id = sp.id, name = sp.name,
                                    verified = false }
  end
  for _, round in ipairs(t.bracket) do
    local matches = {}
    for _, e in ipairs(round.matches) do
      matches[#matches + 1] = { match = e.match, a = e.a, b = e.b,
                                winner = e.winner, how = e.how,
                                state = e.state }
    end
    bracket[#bracket + 1] = { round = round.round, matches = matches }
  end
  return { type = "tour_state", tour = t.tour, code = t.code, creator = t.creator,
           stage = t.stage, players = players, spectators = spectators,
           profile = t.profile, rule = t.profile and t.profile.rule or nil,
           shotClock = t.shotClock, round = t.round, bracket = bracket,
           live = t.live, champion = t.champion,
           maxSpectators = 16 }
end

function Relay:tourState()
  if not self.tour then return end
  self:tourBroadcast(self:tourStateMsg())
end

function Relay:tourStartMatch(entry, roundNo)
  local t = self.tour
  entry.state = "live"
  t.live = entry.match
  t.liveEntry = entry
  t.childNo = (t.childNo or 0) + 1
  local child = CHILD_ROOMS[t.childNo]
  local function playerRec(id)
    for _, p in ipairs(t.players) do
      if p.id == id then
        return { id = p.id, name = p.name, party = p.party }
      end
    end
  end
  local a, b = playerRec(entry.a), playerRec(entry.b)
  local spectators = {}
  for _, p in ipairs(t.players) do
    if p.id ~= entry.a and p.id ~= entry.b then
      spectators[#spectators + 1] = { id = p.id, name = p.name }
    end
  end
  for _, sp in ipairs(t.spectators) do
    spectators[#spectators + 1] = { id = sp.id, name = sp.name }
  end
  self.room = { room = child, players = { a, b }, spectators = spectators,
                stage = "waiting", profile = t.profile, host = t.creator,
                seed = nil, log = {}, seq = 0, reports = {}, matchNo = 0,
                match = nil, origin = "tour" }
  self:to(self.seats[entry.a], { type = "tour_match", match = entry.match,
                                 round = roundNo, room = child })
  self:to(self.seats[entry.b], { type = "tour_match", match = entry.match,
                                 round = roundNo, room = child })
  for _, sp in ipairs(spectators) do
    self:to(self.seats[sp.id], { type = "tour_match_spectate",
                                 match = entry.match, round = roundNo,
                                 room = child })
  end
  self:tourState()
  self:to(self.seats[entry.a], { type = "tour_deadline", kind = "shot",
                                 at = 1000 + (t.shotClock or 6) * 1000,
                                 match = entry.match })
  self:startMatch(entry.match)
end

function Relay:tourAdvance()
  local t = self.tour
  if not t or t.stage ~= "running" then return end
  local round = t.bracket[#t.bracket]
  for _, e in ipairs(round.matches) do
    if e.state == "bye" and not e.winner then
      e.winner = e.a
      self:to(self.seats[e.a], { type = "tour_bye", match = e.match,
                                 round = round.round })
    end
  end
  for _, e in ipairs(round.matches) do
    if e.state == "pending" then
      self:tourStartMatch(e, round.round)
      return
    end
  end
  local winners = {}
  for _, e in ipairs(round.matches) do
    if e.winner then winners[#winners + 1] = e.winner end
  end
  if #winners <= 1 then
    t.stage = "finished"
    t.champion = winners[1]
    self:tourState()
    self:tourBroadcast({ type = "tour_over", tour = t.tour,
                         championId = winners[1],
                         champion = self:tourNameOf(winners[1]) })
    return
  end
  t.round = t.round + 1
  local matches = {}
  for i = 1, #winners, 2 do
    local a, b = winners[i], winners[i + 1]
    matches[#matches + 1] = {
      match = ("%s-r%d-m%d"):format(t.tour, t.round, math.ceil(i / 2)),
      a = a, b = b, state = b and "pending" or "bye" }
  end
  t.bracket[#t.bracket + 1] = { round = t.round, matches = matches }
  self:tourState()
  self:tourAdvance()
end

function Relay:tourHandle(seat, msg)
  local kind = msg.type
  local t = self.tour
  if kind == "tour_create" then
    self.tour = { tour = TOUR1, code = msg.public == false and "TRN234" or nil,
                  creator = seat.id, stage = "registering",
                  players = {}, spectators = {}, profile = msg.profile,
                  shotClock = msg.shotClock, round = 0, bracket = {},
                  live = nil, champion = nil, childNo = 0 }
    if msg.playing == false then
      table.insert(self.tour.spectators, { id = seat.id, name = seat.name })
    elseif not msg.party or #msg.party == 0 then
      self.tour = nil
      self:to(seat, { type = "join_error", reason = "party_ineligible" })
      return true
    else
      table.insert(self.tour.players, { id = seat.id, name = seat.name,
                                        party = msg.party,
                                        digest = msg.partyDigest })
    end
    self:tourState()
    return true
  end
  if kind ~= "tour_join" and kind ~= "tour_leave" and kind ~= "tour_start"
     and kind ~= "tour_kick" and kind ~= "tour_close" then
    return false
  end
  if not t then
    self:to(seat, { type = "join_error", reason = "tour_not_found" })
    return true
  end
  if kind == "tour_join" then
    local byId = msg.tour ~= nil and msg.tour == t.tour
    local byCode = msg.code ~= nil and t.code ~= nil and msg.code == t.code
    if byId and t.code ~= nil then
      self:to(seat, { type = "join_error", reason = "tour_private" })
      return true
    end
    if not byId and not byCode then
      self:to(seat, { type = "join_error", reason = "tour_not_found" })
      return true
    end
    if msg.as == "spectator" then
      table.insert(t.spectators, { id = seat.id, name = seat.name })
    else
      if t.stage ~= "registering" then
        self:to(seat, { type = "join_error", reason = "tour_started" })
        return true
      end
      if not msg.party or #msg.party == 0 then
        self:to(seat, { type = "join_error", reason = "party_ineligible" })
        return true
      end
      table.insert(t.players, { id = seat.id, name = seat.name,
                                party = msg.party, digest = msg.partyDigest })
    end
    self:tourState()
  elseif kind == "tour_start" then
    if seat.id ~= t.creator then
      self:to(seat, { type = "join_error", reason = "not_creator" })
      return true
    end
    if #t.players < 2 then return true end
    t.stage = "running"
    t.round = 1
    local matches = {}
    for i = 1, #t.players, 2 do
      local a, b = t.players[i], t.players[i + 1]
      matches[#matches + 1] = {
        match = ("%s-r1-m%d"):format(t.tour, math.ceil(i / 2)),
        a = a.id, b = b and b.id or nil,
        state = b and "pending" or "bye" }
    end
    t.bracket[1] = { round = 1, matches = matches }
    self:tourState()
    self:tourAdvance()
  elseif kind == "tour_kick" then
    if seat.id ~= t.creator then
      self:to(seat, { type = "join_error", reason = "not_creator" })
      return true
    end
    self.tourKicked = msg.id
    self:to(self.seats[msg.id], { type = "tour_closed", tour = t.tour,
                                  reason = "kicked" })
    for i = #t.players, 1, -1 do
      if t.players[i].id == msg.id then table.remove(t.players, i) end
    end
    self:tourState()
  elseif kind == "tour_close" then
    if seat.id ~= t.creator then
      self:to(seat, { type = "join_error", reason = "not_creator" })
      return true
    end
    self.tourClosedBy = seat.id
    self:tourBroadcast({ type = "tour_closed", tour = t.tour,
                         reason = "closed" })
    self.tour = nil
  elseif kind == "tour_leave" then
    self.tourLeft = seat.id
    for i = #t.players, 1, -1 do
      if t.players[i].id == seat.id then table.remove(t.players, i) end
    end
    for i = #t.spectators, 1, -1 do
      if t.spectators[i].id == seat.id then table.remove(t.spectators, i) end
    end
    self:tourState()
  end
  return true
end

function Relay:handle(seat, msg)
  local kind = msg.type
  local room = self.room
  if kind:sub(1, 5) == "tour_" then
    if self:tourHandle(seat, msg) then return end
  end
  if kind == "lobby_hello" then
    seat.name = msg.name or seat.name
    self:welcome(seat, false)
  elseif kind == "resume" then
    seat.resumedWith = msg.ack
    self:welcome(seat, true)
    if room then
      self:to(seat, self:roomStateMsg())
      self:replay(seat, math.max(0, msg.ack or 0))
    end
  elseif kind == "room_kick" then
    self.kicked = msg.id
  elseif kind == "room_close" then
    self.closedBy = seat.id
    if room then self:broadcast({ type = "room_closed", reason = "closed",
                                  room = room.room }) end
    self.room = nil
  elseif kind == "room_create" then
    self.room = { room = ROOM1, players = {}, spectators = {},
                  stage = "waiting", profile = msg.profile,
                  host = seat.id, seed = nil, log = {}, seq = 0,
                  reports = {}, matchNo = 0, match = nil }
    table.insert(self.room.players, { id = seat.id, name = seat.name })
    self:roomState("waiting")
  elseif kind == "room_join" then
    if not room or msg.room ~= room.room then
      self:to(seat, { type = "join_error", reason = "not_found" })
      return
    end
    if not msg.profile then
      self:to(seat, { type = "join_error", reason = "bad_profile" })
      return
    end
    if msg.as == "spectator" then
      table.insert(room.spectators, { id = seat.id, name = seat.name })
    else
      table.insert(room.players, { id = seat.id, name = seat.name })
    end
    self:roomState(nil)
    if msg.as == "spectator" and room.stage == "battling" then
      self:replay(seat, 0)
    end
  elseif kind == "room_ready" then
    local ready = 0
    for _, p in ipairs(room.players) do
      if p.id == seat.id then
        p.ready = true
        p.party = msg.party
        p.digest = msg.partyDigest
      end
      if p.ready then ready = ready + 1 end
    end
    if ready >= 2 then self:startMatch() else self:roomState("ready") end
  elseif kind == "room_msg" then
    self:fanout(seat.id, msg.seq, msg.msg)
  elseif kind == "room_ack" then
    seat.ack = math.max(seat.ack, msg.seq or 0)
  elseif kind == "room_report" or kind == "forfeit" then
    if not room or not room.match then return end
    if msg.match and msg.match ~= room.match then
      self.staleReports = (self.staleReports or 0) + 1
      return
    end
    local side = self:sideOf(seat.id)
    if not side then return end
    room.reports[side] = kind == "forfeit" and "lose" or msg.result
    local other = side == "host" and "guest" or "host"
    if kind == "forfeit" then
      self:resolve("forfeit", other)
    elseif room.reports[other] then
      local winner = room.reports.host == "win" and "host" or "guest"
      self:resolve("agreed", winner)
    end
  elseif kind == "room_leave" then
    if room then
      for i = #room.players, 1, -1 do
        if room.players[i].id == seat.id then table.remove(room.players, i) end
      end
      for i = #room.spectators, 1, -1 do
        if room.spectators[i].id == seat.id then
          table.remove(room.spectators, i)
        end
      end
    end
  end
end

function Relay:pump()
  local ids = {}
  for id in pairs(self.seats) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local seat = self.seats[id]
    local outbox = seat.transport.outbox
    seat.transport.outbox = {}
    for _, msg in ipairs(outbox) do
      if type(msg) == "table" and type(msg.type) == "string" then
        self:handle(seat, msg)
      end
    end
  end
end

local function connectTo(Client, seat, name)
  Client.configure({ relayAddress = "fake:1", connect = function()
    return seat.transport
  end })
  return Client.connect({ name = name, profiles = { PROFILE } })
end

-- ---------------------------------------------------------------- protocol

do
  local hello = Protocol2.lobbyHello({ name = "REDDISHLONGNAMEHERE",
                                       profiles = { PROFILE },
                                       engineVersion = "0.0.0-dev" })
  eq(hello.type, "lobby_hello", "lobbyHello builds its type")
  eq(#hello.name, 16, "a display name is bounded to 16 characters")
  eq(hello.profiles[1].rulesetId, "gen1_faithful", "the profile rides along")
  eq(hello.profiles[1].rule.partySize, 1, "the party rule rides along")
  eq(hello.protocol, 3, "lobby_hello announces protocol 3")

  local join = Protocol2.roomJoin(ROOM1:upper(), "spectator")
  eq(join.room, ROOM1, "a room id is lower-cased")
  eq(join.as, "spectator", "join carries the seat kind")
  eq(join.code, nil, "room_join never carries a code")
  eq(Protocol2.roomJoin("ABC234", "player").room, nil,
     "a code-shaped room reference is refused")
  eq(Protocol2.roomJoin("r123", "player").room, nil,
     "a short room id is refused")
  eq(Protocol2.roomJoin(ROOM1, "player", PROFILE, "0042").pin, "0042",
     "a four-digit PIN rides along")
  eq(Protocol2.roomJoin(ROOM1, "player", PROFILE, "42").pin, nil,
     "a short PIN is refused")
  eq(Protocol2.roomJoin(ROOM1, "player", PROFILE, 1234).pin, nil,
     "a numeric PIN is refused (it must be a string)")

  local wrapped = Protocol2.roomMsg(3, { type = "action", kind = "move",
                                         slot = 2 })
  eq(wrapped.seq, 3, "room_msg keeps its seq")
  eq(wrapped.msg.kind, "move", "room_msg sanitizes the inner message")
  eq(Protocol2.roomMsg(1, nil), nil, "room_msg without an inner message drops")

  local list = Wire.sanitize({ type = "lobby_list", entries = (function()
    local out = {}
    for i = 1, 400 do out[i] = { id = "p" .. i, name = "N", since = i } end
    return out
  end)() })
  eq(#list.entries, 200, "a lobby list is bounded to 200 entries")

  local replay = Wire.sanitize({ type = "room_replay", from = 0,
    msgs = (function()
      local out = {}
      for i = 1, 900 do out[i] = { seq = i, msg = { type = "bye" } } end
      return out
    end)() })
  eq(#replay.msgs, 512, "a replay is bounded to 512 messages")

  local state = Wire.sanitize({ type = "room_state", room = ROOM1,
    players = {}, spectators = (function()
      local out = {}
      for i = 1, 200 do out[i] = { id = "s" .. i, name = "S" } end
      return out
    end)() })
  eq(#state.spectators, 64, "spectators are bounded to 64")

  eq(select(2, Protocol2.validate({ type = "room_state", players = {} })),
     "room_state without a room id", "an id-less room_state fails validation")
  eq(select(2, Protocol2.validate({ type = "room_state", code = "ABC234",
                                    players = {} })),
     "room_state without a room id", "a room code is no room id")
  eq(select(2, Protocol2.validate({ type = "join_error" })),
     "join_error without a reason", "a reasonless join_error fails validation")
  eq(Protocol2.validate({ type = "action", kind = "move", slot = 1 }).kind,
     "move", "an unvalidated type still passes through sanitize")

  local created = Protocol2.roomCreate({ intent = "battle", profile = PROFILE,
                                        playing = true, maxSpectators = 4,
                                        private = true, pin = "0000",
                                        note = string.rep("z", 90) })
  eq(created.private, true, "roomCreate carries a private flag")
  eq(created.pin, "0000", "and the host's PIN")
  eq(created.public, nil, "the legacy public flag is gone")
  eq(created.seats, 2, "a room is two seats unless the caller says otherwise")
  eq(#created.note, 40, "a room note is bounded to 40 characters")
  eq(Protocol2.roomCreate({ profile = PROFILE }).private, false,
     "a room is open unless the caller says otherwise")
  eq(Protocol2.roomCreate({ profile = PROFILE, pin = "1234" }).pin, nil,
     "an open room never carries a PIN")
  eq(Protocol2.roomCreate({ profile = PROFILE }).note, nil,
     "a room without a note sends none")

  local shaped = Wire.sanitize({ type = "lobby_delta", added = {
    { id = "p9", name = "N", since = 1, code = "abc234", open = "yes",
      stage = "battling", players = 900, spectators = 200,
      maxSpectators = 200 } } }).added[1]
  eq(shaped.code, nil, "a lobby entry never carries a code")
  eq(shaped.open, nil, "a non-boolean open is dropped from a lobby entry")
  eq(shaped.stage, "battling", "a lobby entry carries the room stage")
  eq(shaped.players, 64, "the entry player count is bounded")
  eq(shaped.spectators, 64, "the entry spectator count is bounded")
  eq(shaped.maxSpectators, 64, "the entry spectator ceiling is bounded")
  local openEntry = Wire.sanitize({ type = "lobby_delta", added = {
    { id = "p8", name = "N", since = 1, code = "abc234", open = true,
      stage = "waiting", players = 1, spectators = 0,
      maxSpectators = 4 } } }).added[1]
  eq(openEntry.open, true, "an open flag survives the schema")
  eq(Wire.sanitize({ type = "lobby_list", entries = {}, online = 12 }).online,
     12, "lobby_list carries the relay's online count")

  local create = Protocol2.tourCreate({ profile = PROFILE, playing = false,
                                        shotClock = 7, maxSpectators = 999 })
  eq(create.type, "tour_create", "tourCreate builds its type")
  eq(create.playing, false, "a spectating creator says so")
  eq(create.shotClock, 6, "an off-list shot clock snaps to 3/6/9")
  eq(Protocol2.tourCreate({ shotClock = 9 }).shotClock, 9,
     "an allowed shot clock is kept")
  eq(create.maxSpectators, 64, "maxSpectators is bounded to 64")
  eq(create.public, true, "a tournament is public unless it says otherwise")
  eq(Protocol2.tourCreate({ public = false }).public, false,
     "tourCreate carries a private flag")
  eq(Protocol2.tourCreate({ note = ("z"):rep(80) }).note:len(), 40,
     "the tournament note is clipped to 40 characters")

  local tj = Protocol2.tourJoin("trn234", "player", PROFILE,
                                { { species = "PIKACHU", level = 5 } }, "dg")
  eq(tj.code, "TRN234", "tour_join upper-cases a private tournament code")
  eq(tj.tour, nil, "and sends no id with it")
  eq(tj.party[1].species, "PIKACHU", "tour_join carries the team")
  eq(tj.partyDigest, "dg", "tour_join carries the digest")
  local tjId = Protocol2.tourJoin({ tour = TOUR1, as = "spectator",
                                    profile = PROFILE })
  eq(tjId.tour, TOUR1, "the table form joins a public tournament by id")
  eq(tjId.code, nil, "without a code")
  eq(tjId.as, "spectator", "and keeps the seat kind")
  eq(Protocol2.tourKick("p9").id, "p9", "tour_kick names its target")
  eq(Protocol2.tourStart().type, "tour_start", "tour_start builds its type")
  eq(Protocol2.tourClose().type, "tour_close", "tour_close builds its type")
  eq(Protocol2.tourLeave().type, "tour_leave", "tour_leave builds its type")

  local function fill(n, fn)
    local out = {}
    for i = 1, n do out[i] = fn(i) end
    return out
  end
  local big = Wire.sanitize({
    type = "tour_state", tour = TOUR1, creator = "p1", stage = "running",
    players = fill(200, function(i)
      return { id = "p" .. i, name = "N" .. i, eliminated = false }
    end),
    spectators = fill(200, function(i) return { id = "s" .. i, name = "S" } end),
    bracket = fill(20, function(r)
      return { round = r, matches = fill(80, function(k)
        return { match = "m" .. r .. "-" .. k, a = "p1", b = "p2",
                 state = "pending" }
      end) }
    end),
  })
  eq(#big.players, 64, "a tournament is bounded to 64 players")
  eq(#big.spectators, 64, "and to 64 spectators")
  eq(#big.bracket, 7, "a bracket is bounded to 7 rounds")
  eq(#big.bracket[1].matches, 32, "a round is bounded to 32 matches")
  eq(big.players[1].eliminated, false, "an elimination mark rides along")
  eq(Wire.sanitize({ type = "tour_state", code = "TRN234", stage = "nonsense",
                     players = {} }).stage, "registering",
     "an unknown stage falls back to registering")
  eq(Wire.sanitize({ type = "tour_state", code = "TRN234", players = {},
                     bracket = { { round = 1, matches = {
                       { match = "m1", a = "p1", state = "sideways" } } } }
                   }).bracket[1].matches[1].state, nil,
     "an unknown match state is dropped")

  eq(select(2, Protocol2.validate({ type = "tour_match", round = 1 })),
     "tour_match without a match token",
     "a tokenless tour_match fails validation")
  eq(select(2, Protocol2.validate({ type = "tour_match", match = "m1" })),
     "tour_match without a child room id",
     "an id-less tour_match fails validation")
  eq(select(2, Protocol2.validate({ type = "tour_match", match = "m1",
                                    code = "CHA234" })),
     "tour_match without a child room id",
     "a child room code is no child room id")
  eq(select(2, Protocol2.validate({ type = "tour_deadline", kind = "shot" })),
     "tour_deadline without a time", "a timeless tour_deadline fails")
  eq(select(2, Protocol2.validate({ type = "tour_over" })),
     "tour_over without a tournament id", "an id-less tour_over fails")
  eq(Protocol2.validate({ type = "tour_match", match = "m1",
                          room = rid(0xc1):upper() }).room, rid(0xc1),
     "a child room id is lower-cased on the way in")
  eq(select(2, Protocol2.validate({ type = "tour_closed", tour = TOUR1 })),
     "tour_closed without a reason", "a reasonless tour_closed fails")
  eq(Protocol2.validate({ type = "tour_closed", tour = TOUR1,
                          reason = "idle" }).tour, TOUR1,
     "tour_closed carries its tournament id")
  eq(Protocol2.tourCreate({ profile = PROFILE, party = {
       { species = "PIKACHU", level = 5 } }, partyDigest = "dd" }).party[1]
     .species, "PIKACHU", "tour_create carries the creator's team")
end

-- ---------------------------------------------------------------- handshake

local relay = newRelay()
local seatA = relay:seat("a1", "RED")
local ClientA = newClientModule()

local states = {}
ClientA.on("state", function(s) table.insert(states, s) end)

eq(ClientA.state(), "offline", "a fresh client is offline")
check(connectTo(ClientA, seatA, "RED"), "connect opens the transport")
eq(ClientA.state(), "connecting", "connect moves to connecting")
eq(seatA.transport.outbox[1].type, "lobby_hello", "connect sends lobby_hello")
relay:pump()
ClientA.update(1 / 60)
eq(ClientA.state(), "online", "lobby_welcome moves to online")
eq(ClientA.you().name, "RED", "the welcome names us")
eq(ClientA.you().verified, true, "the welcome carries verification")
check(ClientA.serverTime() ~= nil and ClientA.serverTime() >= 1000,
      "the client estimates the relay's clock")
eq(ClientA.sessionId(), "S-a1", "the session id is held for resume")
eq(table.concat(states, ","), "connecting,online",
   "state transitions are offline -> connecting -> online")

-- ---------------------------------------------------------------- lobby

local lobbyEvents = 0
ClientA.on("lobby", function() lobbyEvents = lobbyEvents + 1 end)

relay:to(seatA, { type = "lobby_list", entries = {
  { id = "p3", name = "GREEN", since = 30, intent = "battle", profile = PROFILE },
  { id = "p1", name = "BLUE", since = 10, intent = "battle", profile = PROFILE },
  { id = "p2", name = "LEAF", since = 20, intent = "trade", profile = PROFILE },
} })
ClientA.update(0)
eq(#ClientA.lobby(), 3, "the lobby list lands")
eq(ClientA.lobby()[1].name, "BLUE", "entries order by since (first)")
eq(ClientA.lobby()[3].name, "GREEN", "entries order by since (last)")
eq(lobbyEvents, 1, "a lobby list emits one lobby event")

relay:to(seatA, { type = "lobby_delta",
                  added = { { id = "p0", name = "GOLD", since = 5,
                              room = ROOM1:upper(), locked = true } },
                  removed = { "p2" }, changed = {} })
ClientA.update(0)
eq(#ClientA.lobby(), 3, "a delta adds and removes")
eq(ClientA.lobby()[1].name, "GOLD", "a delta keeps the ordering stable")
eq(ClientA.lobby()[1].room, ROOM1,
   "a lobby entry carries the advertiser's room id")
eq(ClientA.lobby()[1].locked, true, "and whether it is PIN-locked")
local names = {}
for _, e in ipairs(ClientA.lobby()) do table.insert(names, e.name) end
eq(table.concat(names, ","), "GOLD,BLUE,GREEN", "the whole order is stable")

relay:to(seatA, { type = "lobby_delta", added = {}, removed = {},
                  changed = { { id = "p1", name = "BLUE", since = 10,
                                note = "wants a battle" } } })
ClientA.update(0)
eq(ClientA.lobby()[2].note, "wants a battle", "a changed entry updates in place")
eq(#ClientA.lobby(), 3, "a change does not duplicate an entry")

relay:to(seatA, { type = "lobby_delta", op = "update",
                  entry = { id = "p1", name = "BLUE", since = 10,
                            note = "still here" } })
ClientA.update(0)
eq(ClientA.lobby()[2].note, "still here",
   "the older single-entry delta shape still applies")

-- ------------------------------------------------------- open rooms, watch

relay:to(seatA, { type = "lobby_list", online = 9, entries = {
  { id = "a1", name = "RED", since = 5, intent = "battle", profile = PROFILE,
    room = rid(0xa), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 4 },
  { id = "p1", name = "BLUE", since = 10, intent = "battle", profile = PROFILE,
    room = rid(0xb), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 4 },
  { id = "p2", name = "LEAF", since = 20, intent = "battle", profile = PROFILE,
    room = rid(0xc), open = false, stage = "battling", players = 2,
    spectators = 1, maxSpectators = 4 },
  { id = "p3", name = "GREEN", since = 30, intent = "battle", profile = PROFILE,
    room = rid(0xd), open = false, stage = "battling", players = 2,
    spectators = 4, maxSpectators = 4 },
  { id = "p4", name = "GOLD", since = 40, intent = "battle", profile = PROFILE,
    note = "looking for a battle" },
  { id = "p5", name = "SILVER", since = 50, intent = "tournament",
    profile = PROFILE, tour = tid(0xe), open = false, stage = "registering",
    players = 3, spectators = 0, maxSpectators = 8 },
  { id = "p6", name = "CRYS", since = 60, intent = "battle", profile = PROFILE,
    room = rid(0xf), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 0, locked = true },
} })
ClientA.update(0)

local openRooms = ClientA.openRooms()
eq(#openRooms, 2, "openRooms keeps only the open entries with a room")
eq(openRooms[1].room, rid(0xb), "openRooms sorts by since")
eq(openRooms[2].room, rid(0xf), "...and the later room comes second")
eq(openRooms[2].locked, true, "a locked room is still listed, with its lock")
local sawSelf = false
for _, e in ipairs(openRooms) do
  if e.id == ClientA.you().id then sawSelf = true end
end
check(not sawSelf, "openRooms never lists your own room")
eq(openRooms[1].players, 1, "an open room entry carries its player count")
eq(openRooms[1].maxSpectators, 4, "...and its spectator ceiling")

local watchable = ClientA.watchable()
eq(#watchable, 2, "watchable keeps live rooms with a free spectator seat")
eq(watchable[1].room, rid(0xc), "a battling room with room to spectate is watchable")
eq(watchable[2].tour, tid(0xe), "a tournament is watchable too")
local sawFull = false
for _, e in ipairs(watchable) do
  if e.room == rid(0xd) then sawFull = true end
end
check(not sawFull, "a room with every spectator seat taken is not watchable")

local counts = ClientA.counts()
eq(counts.players, 9, "counts uses the relay's online count when it is sent")
eq(counts.openRooms, 2, "counts reports the open room total")

relay:to(seatA, { type = "lobby_list", entries = {
  { id = "p1", name = "BLUE", since = 10, intent = "battle", profile = PROFILE,
    room = rid(0xb), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 4 },
  { id = "p4", name = "GOLD", since = 40, intent = "battle", profile = PROFILE },
} })
ClientA.update(0)
local fallback = ClientA.counts()
eq(fallback.players, 2, "without an online count, counts falls back to entries")
eq(fallback.openRooms, 1, "and still counts the open rooms")
eq(#ClientA.watchable(), 0, "nothing is watchable in a quiet lobby")

relay:to(seatA, { type = "lobby_list", entries = {
  { id = "p1", name = "BLUE", since = 10, intent = "battle", profile = PROFILE,
    room = rid(0xb), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 4, online = false },
  { id = "p2", name = "LEAF", since = 20, intent = "battle", profile = PROFILE,
    room = rid(0xc), open = true, stage = "waiting", players = 2,
    spectators = 0, maxSpectators = 4, online = true },
  { id = "p3", name = "GREEN", since = 30, intent = "battle", profile = PROFILE,
    room = rid(0xc), open = false, stage = "waiting", online = false },
  { id = "p6", name = "CRYS", since = 60, intent = "battle", profile = PROFILE,
    room = rid(0xf), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 0, online = true },
} })
ClientA.update(0)
local liveRooms = ClientA.openRooms()
eq(#liveRooms, 1, "openRooms hides rooms with an offline host or seated player")
eq(liveRooms[1] and liveRooms[1].room, rid(0xf), "only the live room stays listed")
eq(ClientA.counts().openRooms, 1, "counts skips the offline rooms too")
relay:to(seatA, { type = "lobby_delta", changed = {
  { id = "p1", name = "BLUE", since = 10, intent = "battle", profile = PROFILE,
    room = rid(0xb), open = true, stage = "waiting", players = 1,
    spectators = 0, maxSpectators = 4, online = true },
} })
ClientA.update(0)
eq(#ClientA.openRooms(), 2, "a host that resumes lists its room again")

relay:to(seatA, { type = "lobby_list", entries = {
  { id = "a1", name = "RED", since = 5, intent = "tournament",
    profile = PROFILE, tour = tid(0x1), open = true, stage = "registering",
    players = 8, spectators = 0, maxSpectators = 8 },
  { id = "p7", name = "IVY", since = 6, intent = "tournament",
    profile = PROFILE, tour = tid(0x2), open = true, stage = "registering",
    players = 5, spectators = 0, maxSpectators = 8 },
} })
ClientA.update(0)
local watchMine = ClientA.watchable()
eq(#watchMine, 1, "watchable drops the caller's own entry")
eq(watchMine[1].tour, tid(0x2), "only another trainer's tournament is watchable")
eq(watchMine[1].players, 5,
   "a tournament entry keeps a player count above the room ceiling")

-- ---------------------------------------------------------------- advertise

ClientA.advertise("battle", PROFILE, "come at me")
relay:pump()
eq(seatA.transport.outbox[1], nil, "advertise leaves nothing queued after a pump")
ClientA.unadvertise()
local sawUnadvertise = false
for _, m in ipairs(seatA.transport.outbox) do
  if m.type == "unadvertise" then sawUnadvertise = true end
end
check(sawUnadvertise, "unadvertise is sent")
relay:pump()

-- ---------------------------------------------------------------- rooms

local roomEvents = 0
ClientA.on("room", function() roomEvents = roomEvents + 1 end)
local pending = ClientA.createRoom({ intent = "battle", profile = PROFILE,
                                     playing = true, maxSpectators = 8,
                                     private = false, note = "come and get it" })
local createSent
for _, m in ipairs(seatA.transport.outbox) do
  if m.type == "room_create" then createSent = m end
end
check(createSent ~= nil, "createRoom sends a room_create")
eq(createSent and createSent.private, false, "createRoom sends the private flag")
eq(createSent and createSent.note, "come and get it",
   "createRoom sends the note")
relay:pump()
ClientA.update(0)
check(pending.done, "createRoom's promise completes")
eq(pending.id, ROOM1, "createRoom yields a room id")
eq(pending.code, nil, "and no code")
eq(ClientA.room().room, ROOM1, "the room model holds the id")
eq(ClientA.room().seats, 2, "the room model holds its seat count")
eq(ClientA.room().engine, 1, "and its engine")
eq(ClientA.seat(), 0, "the creator sits in seat 0")
eq(ClientA.room().stage, "waiting", "a fresh room is waiting")
eq(#ClientA.room().players, 1, "the creator is the only player")
eq(roomEvents, 1, "room_state emits a room event")

local seatB = relay:seat("b1", "BLUE")
local ClientB = newClientModule()
connectTo(ClientB, seatB, "BLUE")
relay:pump()
ClientB.update(0)
eq(ClientB.state(), "online", "the second client comes online")
local joinPending = ClientB.joinRoom(ROOM1, "player")
local joinMsg
for _, m in ipairs(seatB.transport.outbox) do
  if m.type == "room_join" then joinMsg = m end
end
eq(joinMsg and joinMsg.profile and joinMsg.profile.fingerprint, "abc123",
   "room_join carries the joiner's profile")
eq(joinMsg and joinMsg.room, ROOM1, "room_join names the room by id")
relay:pump()
ClientA.update(0)
ClientB.update(0)
check(joinPending.done, "joinRoom's promise completes")
eq(joinPending.id, ROOM1, "the join promise names the room")
eq(ClientB.room().room, ROOM1, "the guest sees the room")
eq(ClientB.seat(), 1, "the joiner sits in seat 1")
eq(#ClientA.room().players, 2, "the host sees both players")

local seatC = relay:seat("c1", "GREEN")
local ClientC = newClientModule()
connectTo(ClientC, seatC, "GREEN")
relay:pump()
ClientC.update(0)
ClientC.joinRoom(ROOM1, "spectator")
local specJoin
for _, m in ipairs(seatC.transport.outbox) do
  if m.type == "room_join" then specJoin = m end
end
eq(specJoin and specJoin.as, "spectator", "a spectator join names its seat")
eq(specJoin and specJoin.profile and specJoin.profile.rulesetId, "gen1_faithful",
   "a spectator sends its profile too")
relay:pump()
ClientA.update(0); ClientB.update(0); ClientC.update(0)
eq(#ClientC.room().spectators, 1, "a spectator lands in the room")
eq(#ClientC.room().players, 2, "a spectator sees both players")

local sentBefore = #seatC.transport.outbox
local codeJoin = ClientC.joinRoom("ZZZZZZ", "player")
check(codeJoin.done and codeJoin.reason == "bad_room",
      "a code-shaped room reference fails locally as bad_room")
eq(#seatC.transport.outbox, sentBefore, "and nothing reaches the relay")
local badJoin = ClientC.joinRoom(rid(0xdead), "player")
relay:pump()
ClientC.update(0)
check(badJoin.done and badJoin.error ~= nil, "an unknown room answers join_error")
eq(badJoin.reason, "not_found", "the join error keeps its reason")

-- ---------------------------------------------------------------- match_start

local startA, startB, startC
ClientA.on("match_start", function(p) startA = p end)
ClientB.on("match_start", function(p) startB = p end)
ClientC.on("match_start", function(p) startC = p end)

local partyRed = { { species = "CHARIZARD", level = 50, hp = 10,
                     moves = { { id = "TACKLE", pp = 35 } } } }
local partyBlue = { { species = "BLASTOISE", level = 50, hp = 10,
                      moves = { { id = "TACKLE", pp = 35 } } } }
ClientA.ready(partyRed, "digestA")
ClientB.ready(partyBlue, "digestB")
relay:pump()
ClientA.update(0); ClientB.update(0); ClientC.update(0)

check(startA ~= nil and startB ~= nil, "both players get match_start")
eq(ClientA.room().stage, "battling", "a started room reads as battling")
eq(startA.match, ROOM1 .. "-m1", "match_start carries the match token")
eq(ClientA.match(), ROOM1 .. "-m1", "the client holds the match token")
eq(startA.room, ROOM1, "match_start names the room")
eq(startA.seat, 0, "match_start carries the host's seat")
eq(startB.seat, 1, "and the guest's seat")
eq(startA.seats, 2, "and the seat count")
eq(startC and startC.seat, nil, "a spectator has no seat")
eq(startA.players and #startA.players, 2, "match_start lists the seated players")
eq(ClientA.role(), "host", "the client knows its role")
eq(ClientC.role(), "spectator", "a spectator knows its role")
eq(startA.role, "host", "the creator is the host")
eq(startB.role, "guest", "the joiner is the guest")
eq(startC and startC.role, "spectator", "the spectator gets a spectator role")
eq(startA.seed, 4242, "match_start carries the room seed")
eq(startA.ruleset, "gen1_faithful", "match_start carries the ruleset")
eq(startA.rule.partySize, 1, "match_start carries the party rule")
eq(startA.peerName, "BLUE", "the host's peer is the guest")
eq(startB.peerName, "RED", "the guest's peer is the host")
eq(startA.hostName, "RED", "match_start names the host")
eq(startA.guestName, "BLUE", "match_start names the guest")
eq(startA.myParty, nil, "match_start leaves myParty for ArenaBoot")
eq(startA.theirParty[1].species, "BLASTOISE", "the host's theirParty is the guest's")
eq(startB.theirParty[1].species, "CHARIZARD", "the guest's theirParty is the host's")
eq(startC.hostParty[1].species, "CHARIZARD", "a spectator gets the host party")
eq(startC.guestParty[1].species, "BLASTOISE", "a spectator gets the guest party")
eq(startC.theirParty, nil, "a spectator has no theirParty")

-- ---------------------------------------------------------------- room session

local sessA = ClientA.roomSession()
local sessB = ClientB.roomSession()
check(sessA ~= nil and sessB ~= nil, "roomSession exists once a room does")
eq(sessA.paired, true, "a two-player room reads as paired")
eq(sessA.closed, false, "a live room session is not closed")

sessA:send({ type = "action", kind = "move", slot = 1 })
sessA:send({ type = "hash", turn = 1, value = "x" })
local sentSeqs = {}
for _, m in ipairs(seatA.transport.outbox) do
  if m.type == "room_msg" then table.insert(sentSeqs, m.seq) end
end
eq(table.concat(sentSeqs, ","), "1,2", "send wraps into room_msg with a rising seq")

relay:pump()
ClientB.update(0)
local got = sessB:poll()
eq(#got, 2, "poll unwraps both inner messages")
eq(got[1].type, "action", "poll keeps seq order (first)")
eq(got[2].type, "hash", "poll keeps seq order (second)")
eq(got[1].seat, nil, "an engine 1 seat gets the bare inner message, untagged")
eq(sessB:seat(), 1, "the room session knows its seat")
eq(sessB:seats(), 2, "and the seat count")
eq(sessB:role(), "guest", "and its role")
eq(sessB:engine(), 1, "and the engine")
eq(sessB:peerOnline(0), true, "the host seat reads as online")
eq(sessB.target, ROOM1, "the session targets the room id")
eq(sessB.code, nil, "and carries no code")
local ackSeq
for _, m in ipairs(seatB.transport.outbox) do
  if m.type == "room_ack" then ackSeq = m.seq end
end
eq(ackSeq, 2, "poll acks the highest delivered seq")

relay:pump()
sessA:send({ type = "replace", index = 2 })
sessA:send({ type = "bye" })
relay:pump()
ClientB.update(0)
local taken = sessB:take("bye")
check(taken ~= nil, "take pulls a message by type")
eq(sessB:pollOne().type, "replace", "the untaken message stays in order")
sessB:unread({ { type = "forfeit" } })
eq(sessB:take("forfeit") ~= nil, true, "unread puts a message back")

-- ---------------------------------------------------------------- reconnect

relay:pump()
sessA:send({ type = "hash", turn = 2, value = "y" })
sessA:send({ type = "hash", turn = 3, value = "z" })
relay:pump()
ClientB.update(0)
eq(#sessB:poll(), 2, "two more messages reach the guest before the drop")

sessA:send({ type = "hash", turn = 4, value = "w" })
relay:pump()

local oldTransport = seatB.transport
oldTransport.closed = true
ClientB.update(0)
eq(ClientB.state(), "reconnecting", "a dropped transport goes to reconnecting")

seatB.transport = newTransport()
ClientB.configure({ connect = function() return seatB.transport end })
CLOCK = CLOCK + 2
ClientB.update(0)
local resumeMsg
for _, m in ipairs(seatB.transport.outbox) do
  if m.type == "resume" then resumeMsg = m end
end
check(resumeMsg ~= nil, "the reconnect sends resume")
eq(resumeMsg.session, "S-b1", "resume carries the session id")
eq(resumeMsg.ack, 6, "resume carries the last acked seq")

relay:pump()
ClientB.update(0)
eq(ClientB.state(), "online", "the resumed client is online again")
local replayed = ClientB.roomSession():poll()
eq(#replayed, 1, "the replay delivers only the unacked message")
eq(replayed[1].value, "w", "the replayed message is the missing one")

-- ------------------------------------------------------------- spectating

local sessC = ClientC.roomSession()
check(sessC ~= nil, "a spectator holds a room session")
relay:pump()
ClientC.update(0)
sessC:poll()
sessA:send({ type = "action", kind = "move", slot = 3 })
relay:pump()
ClientC.update(0)
local watched = sessC:poll()
eq(#watched, 1, "a spectator's poll delivers the fanned-out message")
eq(watched[1].type, "spectate",
   "a side-tagged room_msg reaches a spectator as a spectate envelope")
eq(watched[1].side, "host", "the envelope keeps the side that sent it")
eq(watched[1].msg.kind, "move", "and carries the inner message")
sessA:send({ type = "hash", turn = 9, value = "s" })
relay:pump()
ClientC.update(0)
local takenSpec = sessC:take("spectate", function(m) return m.side == "host" end)
check(takenSpec ~= nil and takenSpec.msg.type == "hash",
      "take matches a spectate envelope by type and side")
ClientB.update(0)
local peerGot = sessB:poll()
check(#peerGot > 0 and peerGot[#peerGot].type == "hash",
      "the seated peer still gets bare inner messages")

-- ------------------------------------------------- resume replays its tail

relay:pump()
sessB:send({ type = "hash", turn = 5, value = "b5" })
relay:pump()
ClientA.update(0)
sessA:poll()
sessB:send({ type = "hash", turn = 6, value = "b6" })
seatB.transport.closed = true
ClientB.update(0)
eq(ClientB.state(), "reconnecting", "the second drop goes to reconnecting")
seatB.transport = newTransport()
ClientB.configure({ connect = function() return seatB.transport end })
CLOCK = CLOCK + 2
ClientB.update(0)
relay:pump()
local yourSeqSeen
for _, m in ipairs(seatB.transport.inbox) do
  if m.type == "room_replay" then yourSeqSeen = m.yourSeq end
end
ClientB.update(0)
eq(ClientB.state(), "online", "the second resume lands")
eq(yourSeqSeen, 1, "room_replay tells the resumed client its last logged seq")
local extraResume = false
for _, m in ipairs(seatB.transport.outbox) do
  if m.type == "resume" then extraResume = true end
end
check(not extraResume, "a landed resume clears the retry timer instead of re-resuming")
check(ClientB.roomSession() == sessB,
      "the room session object survives a resume, so a live battle keeps its net")
relay:pump()
ClientA.update(0)
local resent = sessA:poll()
eq(#resent, 1, "the resumed client replays only the message the relay missed")
eq(resent[1].value, "b6", "and it is the one that never arrived")
eq((relay.room.duplicates or 0), 0,
   "nothing the relay already had was sent a second time")
ClientB.sendRaw(Protocol2.roomMsg(2, { type = "hash", turn = 6, value = "b6" }))
relay:pump()
ClientA.update(0)
eq(#sessA:poll(), 0, "a re-sent clientSeq is dropped by the relay")
eq(relay.room.duplicates, 1, "and counted as a duplicate")

-- ---------------------------------------------------------------- results

local endA, endB, endC
ClientA.on("match_end", function(p) endA = p end)
ClientB.on("match_end", function(p) endB = p end)
ClientC.on("match_end", function(p) endC = p end)

ClientA.report("win")
local reportMsg
for _, m in ipairs(seatA.transport.outbox) do
  if m.type == "room_report" then reportMsg = m end
end
check(reportMsg ~= nil, "report sends room_report")
eq(reportMsg.match, ROOM1 .. "-m1", "room_report carries the live match token")
eq(reportMsg.result, "win", "room_report carries the result")

ClientB.report("lose")
relay:pump()
ClientA.update(0); ClientB.update(0); ClientC.update(0)

check(endA ~= nil and endB ~= nil, "both players get match_end")
eq(endA.how, "agreed", "match_end carries how the relay resolved it")
eq(endA.match, ROOM1 .. "-m1", "match_end carries the match token")
eq(endA.winnerId, "a1", "match_end carries the winner's seat id")
eq(endA.youWon, true, "the winner is told it won")
eq(endB.youWon, false, "the loser is told it did not")
eq(endC and endC.youWon, false, "a spectator never wins")
eq(ClientA.room().stage, "waiting", "the room returns to waiting after a result")

ClientA.ready(partyRed, "digestA")
ClientB.ready(partyBlue, "digestB")
relay:pump()
ClientA.update(0); ClientB.update(0)
eq(ClientA.match(), ROOM1 .. "-m2", "a rematch takes a fresh match token")

endA, endB = nil, nil
ClientB.forfeit()
local forfeitMsg
for _, m in ipairs(seatB.transport.outbox) do
  if m.type == "forfeit" then forfeitMsg = m end
end
check(forfeitMsg ~= nil, "forfeit sends a top-level forfeit")
eq(forfeitMsg.match, ROOM1 .. "-m2", "forfeit carries the live match token")
relay:pump()
ClientA.update(0); ClientB.update(0)
eq(endA and endA.how, "forfeit", "a forfeit resolves as a forfeit")
eq(endA and endA.youWon, true, "the forfeiter's opponent wins")

ClientA.ready(partyRed, "digestA")
ClientB.ready(partyBlue, "digestB")
relay:pump()
ClientA.update(0); ClientB.update(0)
local thirdMatch = ClientA.match()
eq(thirdMatch, ROOM1 .. "-m3", "a third match takes another token")
endA, endB = nil, nil
ClientA.report("error")
local errForfeit
for _, m in ipairs(seatA.transport.outbox) do
  if m.type == "forfeit" then errForfeit = m end
end
check(errForfeit ~= nil, "report with a non-result forfeits instead")
eq(errForfeit and errForfeit.match, thirdMatch,
   "the forfeit names the live match")
relay:pump()
ClientA.update(0); ClientB.update(0)
eq(endA and endA.how, "forfeit", "the relay resolves a reported non-result")
eq(endB and endB.youWon, true, "the other seat wins it")

local staleBefore = relay.staleReports or 0
ClientA.report("win")
relay:pump()
eq(relay.staleReports or 0, staleBefore,
   "a report after a result still names the match the relay knows")
ClientA.update(0)

ClientA.kick("b1")
relay:pump()
eq(relay.kicked, "b1", "kick sends room_kick with the target id")

relay:to(seatA, { type = "room_closed", reason = "closed", room = ROOM1 })
local closedErr
ClientA.on("error", function(e) closedErr = e end)
ClientA.update(0)
eq(ClientA.room(), nil, "room_closed clears the room model")
eq(ClientA.match(), nil, "room_closed clears the match token")
eq(ClientA.roomSession(), nil, "room_closed drops the room session")
eq(closedErr and closedErr.reason, "closed", "room_closed surfaces its reason")
eq(ClientA.closeRoom(), false, "closeRoom with no room is a no-op")

check(ClientC.closeRoom(), "closeRoom sends room_close while in a room")
relay:pump()
eq(relay.closedBy, "c1", "the relay saw room_close")
ClientC.update(0)
eq(ClientC.room(), nil, "the room_close broadcast clears the room")


-- ------------------------------------------------- host leaving closes it

do
  local rr = newRelay()
  local sh = rr:seat("h1", "HOST")
  local sg = rr:seat("g1", "GUEST")
  local CH, CG = newClientModule(), newClientModule()
  connectTo(CH, sh, "HOST")
  connectTo(CG, sg, "GUEST")
  rr:pump(); CH.update(0); CG.update(0)
  CH.createRoom({ intent = "battle", profile = PROFILE })
  rr:pump(); CH.update(0)
  CG.joinRoom(ROOM1, "player")
  rr:pump(); CH.update(0); CG.update(0)
  eq(#CH.room().players, 2, "host and guest share the room")
  local function types(seat)
    local out = {}
    for _, m in ipairs(seat.transport.outbox) do out[#out + 1] = m.type end
    return table.concat(out, ",")
  end
  sg.transport.outbox = {}
  check(CG.leaveRoom(), "the guest can leave")
  eq(types(sg), "room_leave", "a guest leaving only sends room_leave")
  rr:pump(); CH.update(0)
  sh.transport.outbox = {}
  check(CH.leaveRoom(), "the host can leave")
  eq(types(sh), "room_close,room_leave",
     "a host leaving closes the room before leaving it")
  rr:pump()
  eq(rr.closedBy, "h1", "so the relay tears the room down for everyone")
  eq(CH.room(), nil, "and the host's room model is gone")

  local lateErr
  CH.on("error", function(e) if e.scope == "room" then lateErr = e end end)
  local made = CH.createTournament({ profile = PROFILE, playing = true,
                                     shotClock = 6, maxSpectators = 8,
                                     party = { { species = "CHARIZARD",
                                                 level = 50, hp = 10 } },
                                     partyDigest = "dh" })
  CH.update(0)
  check(not made.done,
        "a late room_closed for the room just left does not fail the next request")
  eq(lateErr, nil, "and raises no room error")
  rr:pump(); CH.update(0)
  check(made.done and made.error == nil, "the tournament create still resolves")
  eq(CH.tournament() and CH.tournament().tour, TOUR1,
     "and the host holds the tournament")
end

do
  local rr = newRelay()
  local sh = rr:seat("h1", "HOST")
  local CH = newClientModule()
  connectTo(CH, sh, "HOST")
  rr:pump(); CH.update(0)
  local lateErr
  CH.on("error", function(e) if e.scope == "room" then lateErr = e end end)
  CH.createRoom({ intent = "battle", profile = PROFILE })
  rr:pump(); CH.update(0)
  eq(CH.room() and CH.room().room, ROOM1, "the host opens a room")
  rr:to(sh, { type = "room_closed", reason = "closed", room = rid(0x77) })
  CH.update(0)
  eq(CH.room() and CH.room().room, ROOM1,
     "a room_closed naming another room leaves the current room alone")
  eq(lateErr, nil, "and raises no room error either")
  rr:to(sh, { type = "room_closed", reason = "closed", room = ROOM1 })
  CH.update(0)
  eq(CH.room(), nil, "a room_closed for the current room still clears it")
  eq(lateErr and lateErr.room, ROOM1, "and surfaces the room error")

  lateErr = nil
  local joining = CH.joinRoom(rid(0x99), "player")
  rr:to(sh, { type = "room_closed", reason = "closed", room = rid(0x99) })
  CH.update(0)
  check(joining.done and joining.error ~= nil,
        "a room_closed for the room a join is waiting on fails that join")
end

-- ------------------------------------------------- reports across a drop

do
  local rr = newRelay()
  local sh = rr:seat("h1", "HOST")
  local sg = rr:seat("g1", "GUEST")
  local CH, CG = newClientModule(), newClientModule()
  connectTo(CH, sh, "HOST")
  connectTo(CG, sg, "GUEST")
  local function pump()
    rr:pump()
    CH.update(0)
    CG.update(0)
  end
  local function countOut(seat, kind)
    local n = 0
    for _, m in ipairs(seat.transport.outbox) do
      if m.type == kind then n = n + 1 end
    end
    return n
  end
  local function drop(client, seat)
    seat.transport.closed = true
    client.update(0)
  end
  local function relink(client, seat)
    seat.transport = newTransport()
    client.configure({ connect = function() return seat.transport end })
    CLOCK = CLOCK + 30
    client.update(0)
  end
  pump()

  local party = { { species = "PIKACHU", level = 50, hp = 10,
                    moves = { { id = "TACKLE", pp = 35 } } } }
  CH.createRoom({ profile = PROFILE })
  pump()
  CG.joinRoom(ROOM1, "player", PROFILE)
  pump()
  CH.ready(party, "dh")
  CG.ready(party, "dg")
  pump()
  local m1 = CH.match()
  eq(m1, ROOM1 .. "-m1", "the drop scenario opens on a live match")

  local endH
  CH.on("match_end", function(p) endH = p end)

  drop(CH, sh)
  eq(CH.state(), "reconnecting", "the reporting seat drops to reconnecting")
  eq(CH.report("win"), false, "a report sent while the socket is down waits")
  check(CH.pendingReport() ~= nil and CH.pendingReport().match == m1,
        "the report is queued against the match it belongs to")
  relink(CH, sh)
  rr:pump()
  CH.update(0)
  eq(CH.state(), "online", "the resume lands")
  eq(countOut(sh, "room_report"), 1,
     "the queued report goes out once the session is back")
  local queuedReport
  for _, m in ipairs(sh.transport.outbox) do
    if m.type == "room_report" then queuedReport = m end
  end
  eq(queuedReport and queuedReport.match, m1,
     "the delivered report still names its own match")
  eq(CH.pendingReport(), nil, "the queue empties once it is sent")
  CH.update(0)
  eq(countOut(sh, "room_report"), 1, "and it is never sent twice")
  pump()
  CG.report("lose")
  pump()
  eq(endH and endH.how, "agreed", "the relay resolves on the resumed report")

  CH.ready(party, "dh")
  CG.ready(party, "dg")
  pump()
  local m2 = CH.match()
  check(m2 ~= m1, "a rematch takes a fresh token")
  drop(CH, sh)
  CH.report("win")
  check(CH.pendingReport() ~= nil, "the second report queues too")
  relink(CH, sh)
  rr:pump()
  rr:to(sh, { type = "room_result", match = m2, winner = "GUEST",
              winnerId = "g1", how = "stall" })
  CH.update(0)
  eq(countOut(sh, "room_report"), 0,
     "a room_result that arrives first cancels the queued report")
  eq(CH.pendingReport(), nil, "and clears the queue")
  eq(endH and endH.match, m2, "the client still reports the match as ended")
  eq(endH and endH.room, ROOM1, "room_result carries the room id")
  endH = nil
  rr:to(sh, { type = "room_result", match = m2, room = rid(0x777),
              winnerId = "g1", how = "stall" })
  CH.update(0)
  eq(endH and endH.room, rid(0x777), "a room_result with a room id uses that id")

  CH.ready(party, "dh")
  CG.ready(party, "dg")
  pump()
  local m3 = CH.match()
  drop(CH, sh)
  CH.report("win")
  eq(CH.pendingReport().match, m3, "the report is queued for match A")
  rr:resolve("stall", "guest")
  rr:startMatch()
  local mB = rr.room.match
  check(mB ~= m3, "the relay moved on to match B while the seat was away")
  local staleBefore = rr.staleReports or 0
  relink(CH, sh)
  rr:pump()
  CH.update(0)
  rr:pump()
  eq(countOut(sh, "room_report"), 0,
     "a report queued for match A is dropped once the room is on match B")
  eq(rr.staleReports or 0, staleBefore,
     "and the relay never sees a stale report")
  eq(CH.pendingReport(), nil, "the queue is empty after the move")
  eq(CH.match(), mB, "the client follows the relay to match B")

  local sess = CG.roomSession()
  check(sess ~= nil, "the guest still holds a room session")
  local before = CG.unackedCount()
  for i = 1, 600 do sess:send({ type = "hash", turn = i, value = "v" }) end
  eq(CG.unackedCount(), 512, "unacked is capped at the relay's replay bound")
  eq(CG.unackedDropped(), before + 600 - 512,
     "the overflow is counted as dropped")
  rr:pump()
  CH.update(0)
  local hs = CH.roomSession()
  if hs then hs:poll() end
  local highest = 0
  for _, e in ipairs(rr.room.log) do
    if e.clientSeq and e.clientSeq > highest then highest = e.clientSeq end
  end
  rr:to(sg, { type = "room_replay", from = 0, msgs = {},
              yourSeq = highest - 40 })
  CG.update(0)
  eq(CG.unackedCount(), 40, "room_replay yourSeq trims what the relay acked")

  local lost
  CG.on("error", function(e) lost = e end)
  rr:to(sg, { type = "room_replay", from = 0, msgs = {}, yourSeq = 1 })
  CG.update(0)
  eq(lost and lost.reason, "resume_incomplete",
     "a resume past the replay bound gives up on the room")
  eq(CG.room(), nil, "and clears the room")
  eq(countOut(sg, "room_leave") >= 1, true, "and tells the relay it left")

  local CX = newClientModule()
  local sx = rr:seat("x1", "EXPIRED")
  connectTo(CX, sx, "EXPIRED")
  rr:pump()
  CX.update(0)
  eq(CX.state(), "online", "the expiring seat connects")
  drop(CX, sx)
  relink(CX, sx)
  eq(countOut(sx, "resume"), 1, "the reconnect asks to resume")
  rr:to(sx, { type = "join_error", reason = "resume_expired" })
  CX.update(0)
  eq(countOut(sx, "lobby_hello"), 1,
     "a refused resume falls back to a fresh hello")
  eq(CX.room(), nil, "and holds no room")
end

-- ---------------------------------------------------------- tournament run

do
  local tr = newRelay()
  local s1 = tr:seat("t1", "ONE")
  local s2 = tr:seat("t2", "TWO")
  local s3 = tr:seat("t3", "THREE")
  local s4 = tr:seat("t4", "WATCH")
  local C1, C2, C3, C4 = newClientModule(), newClientModule(),
                         newClientModule(), newClientModule()
  local seatsOf = { [C1] = s1, [C2] = s2, [C3] = s3, [C4] = s4 }
  connectTo(C1, s1, "ONE"); connectTo(C2, s2, "TWO")
  connectTo(C3, s3, "THREE"); connectTo(C4, s4, "WATCH")
  local function pump()
    tr:pump()
    C1.update(0); C2.update(0); C3.update(0); C4.update(0)
  end
  local function outbox(client, kind)
    local found
    for _, m in ipairs(seatsOf[client].transport.outbox) do
      if m.type == kind then found = m end
    end
    return found
  end
  pump()

  local tourEvents = 0
  C1.on("tournament", function() tourEvents = tourEvents + 1 end)
  local playNext, watchNext, byeSeen, overSeen = nil, nil, nil, nil
  C1.on("tour_match", function(p) playNext = p end)
  C3.on("tour_bye", function(p) byeSeen = p end)
  C4.on("tour_spectate", function(p) watchNext = p end)
  C1.on("tour_over", function(p) overSeen = p end)
  local startedC1, startedC4
  C1.on("match_start", function(p) startedC1 = p end)
  C4.on("match_start", function(p) startedC4 = p end)

  local party1 = { { species = "CHARIZARD", level = 50, hp = 10,
                     moves = { { id = "TACKLE", pp = 35 } } } }
  local teamless = C1.createTournament({ profile = PROFILE, playing = true,
                                         shotClock = 6 })
  pump()
  check(teamless.done and teamless.reason == "party_ineligible",
        "a playing creator without a team is refused")
  eq(C1.tournament(), nil, "and holds no tournament")

  local made = C1.createTournament({ profile = PROFILE, playing = true,
                                     shotClock = 6, maxSpectators = 16,
                                     party = party1, partyDigest = "d1",
                                     public = true, note = "open bracket" })
  local createMsg = outbox(C1, "tour_create")
  eq(createMsg and createMsg.public, true,
     "createTournament forwards the public flag")
  eq(createMsg and createMsg.note, "open bracket",
     "createTournament forwards the note")
  eq(createMsg and createMsg.shotClock, 6, "tour_create carries the shot clock")
  eq(createMsg and createMsg.playing, true, "tour_create says the creator plays")
  eq(createMsg and createMsg.party[1].species, "CHARIZARD",
     "a playing creator sends its team with tour_create")
  eq(createMsg and createMsg.partyDigest, "d1", "and its digest")
  pump()
  check(made.done and made.id == TOUR1, "createTournament yields a tournament id")
  eq(C1.tournament().tour, TOUR1, "the tournament model holds the id")
  eq(C1.tournament().code, nil, "a public tournament has no code")
  eq(C1.tournament().stage, "registering", "a fresh tournament is registering")
  eq(C1.tournament().creator, "t1", "the creator is named")
  eq(#C1.tournament().players, 1, "the playing creator is a player")
  eq(tourEvents, 1, "tour_state emits one tournament event")

  local party2 = { { species = "BLASTOISE", level = 50, hp = 10,
                     moves = { { id = "TACKLE", pp = 35 } } } }
  local party3 = { { species = "VENUSAUR", level = 50, hp = 10,
                     moves = { { id = "TACKLE", pp = 35 } } } }
  C2.joinTournament({ tour = TOUR1, as = "player", party = party2,
                      partyDigest = "d2" })
  local joinMsg2 = outbox(C2, "tour_join")
  eq(joinMsg2 and joinMsg2.tour, TOUR1, "tour_join carries the tournament id")
  eq(joinMsg2 and joinMsg2.code, nil, "and no code")
  eq(joinMsg2 and joinMsg2.as, "player", "tour_join names the seat kind")
  eq(joinMsg2 and joinMsg2.party[1].species, "BLASTOISE",
     "a player sends its team up front")
  eq(joinMsg2 and joinMsg2.partyDigest, "d2", "and its digest")
  C3.joinTournament(TOUR1, "player", party3, "d3")
  C4.joinTournament({ tour = TOUR1, as = "spectator" })
  pump()
  eq(#C1.tournament().players, 3, "three players are registered")
  eq(#C1.tournament().spectators, 1, "the outside spectator is registered")
  eq(C4.tournament().tour, TOUR1, "a spectator holds the same model")

  local refused = C2.joinTournament("ZZZZZZ", "player", party2, "d2")
  pump()
  check(refused.done and refused.reason == "tour_not_found",
        "a bad tournament code answers join_error")
  local malformed = C2.joinTournament("zz", "player", party2, "d2")
  check(malformed.done and malformed.reason == "bad_room",
        "a malformed tournament reference fails locally")
  eq(Protocol2.joinErrorText({ reason = "tour_started" }),
     "That tournament has already started.",
     "the new join_error reasons have human text")

  eq(C2.startTournament(), true, "a non-creator may still send tour_start")
  pump()
  eq(C1.tournament().stage, "registering",
     "but the relay refuses it: the bracket has not started")

  C1.startTournament()
  pump()
  local tour = C1.tournament()
  eq(tour.stage, "running", "tour_start moves the tournament to running")
  eq(#tour.bracket, 1, "the first round is drawn")
  eq(#tour.bracket[1].matches, 2, "three players make two first-round matches")
  eq(tour.bracket[1].matches[2].state, "bye", "the odd player gets a bye")
  check(byeSeen ~= nil and byeSeen.match == TOUR1 .. "-r1-m2",
        "the walkover player is told about its bye")

  local CHA, CHB = rid(0xc1), rid(0xc2)
  check(playNext ~= nil, "the paired player gets tour_match")
  eq(playNext.room, CHA, "tour_match names the child room")
  eq(playNext.match, TOUR1 .. "-r1-m1", "tour_match names the bracket match")
  check(watchNext ~= nil, "the outside spectator gets tour_match_spectate")
  eq(watchNext.room, CHA, "the spectator gets the same child room")

  eq(C1.room().room, CHA, "the client switches to the child room")
  eq(C1.roomSession().target, CHA, "roomSession binds to the child room")
  eq(C1.match(), TOUR1 .. "-r1-m1", "the match token is the bracket match")
  check(startedC1 ~= nil, "the child room fires match_start")
  eq(startedC1.match, TOUR1 .. "-r1-m1", "match_start carries the match")
  eq(startedC1.role, "host", "the first seat hosts the child room")
  eq(startedC1.room, CHA, "match_start names the child room")
  check(startedC4 ~= nil, "the spectator boots too")
  eq(startedC4.role, "spectator", "and does so as a spectator")
  eq(C4.roomSession().target, CHA,
     "the spectator's session binds to the child room")
  eq(C3.room() and C3.room().room, CHA,
     "the waiting player watches the live match")

  eq(C1.tournament().deadlines.shot, 7000,
     "tour_deadline lands in the tournament model by kind")
  eq(C1.room().deadlines.shot, 7000, "and in the child room's deadlines")

  local sess = C1.roomSession()
  sess:send({ type = "action", kind = "move", slot = 1 })
  tr:pump()
  C2.update(0)
  eq(#C2.roomSession():poll(), 1, "the child room carries the lockstep stream")

  playNext = nil
  C1.report("win")
  C2.report("lose")
  pump()
  eq(C1.tournament().tour, TOUR1, "the client stays in the tournament")
  local advanced = C1.tournament()
  eq(advanced.bracket[1].matches[1].state, "done", "the bracket advances")
  eq(advanced.bracket[1].matches[1].winner, "t1", "and records the winner")
  eq(advanced.bracket[1].matches[1].how, "agreed", "and how it was decided")
  eq(#advanced.bracket, 2, "the second round is drawn")
  eq(advanced.round, 2, "the tournament is on round 2")
  check(playNext ~= nil and playNext.room == CHB,
        "the next match uses a fresh child room")
  eq(C1.room().room, CHB, "the client follows to the next child room")
  eq(C1.roomSession().target, CHB, "and rebinds its session")

  local eliminated
  for _, p in ipairs(advanced.players) do
    if p.eliminated then eliminated = p.id end
  end
  eq(eliminated, "t2", "the loser is marked eliminated")

  C3.report("error")
  local tourForfeit = outbox(C3, "forfeit")
  check(tourForfeit ~= nil, "a non-result in a tournament match forfeits")
  eq(tourForfeit and tourForfeit.match, TOUR1 .. "-r2-m1",
     "the forfeit names the bracket match")
  pump()
  check(overSeen ~= nil, "tour_over reaches the finalists")
  eq(overSeen and overSeen.championId, "t1", "tour_over names the champion")
  eq(C1.tournament().stage, "finished",
     "the model stays finished until leaveTournament")
  eq(C1.room(), nil, "the child room is cleared after the final")

  check(C1.leaveTournament(), "leaveTournament reports success")
  eq(C1.tournament(), nil, "leaveTournament drops the model")
  tr:pump()
  eq(tr.tourLeft, "t1", "the relay saw tour_leave")
  eq(C1.leaveTournament(), false, "leaving twice is a no-op")

  eq(C4.tournament().stage, "finished",
     "the spectator's model is finished too")
  C4.leaveTournament()
  C1.disconnect(); C2.disconnect(); C3.disconnect(); C4.disconnect()
end


-- ------------------------------------------------------- tournament closes

do
  local tr = newRelay()
  local sa = tr:seat("u1", "HOST")
  local sb = tr:seat("u2", "GUEST")
  local CA, CB = newClientModule(), newClientModule()
  connectTo(CA, sa, "HOST"); connectTo(CB, sb, "GUEST")
  local function pump()
    tr:pump(); CA.update(0); CB.update(0)
  end
  pump()
  local party = { { species = "CHARIZARD", level = 50, hp = 10,
                    moves = { { id = "TACKLE", pp = 35 } } } }
  CA.createTournament({ profile = PROFILE, playing = true, shotClock = 3,
                        party = party, partyDigest = "d1", public = false })
  pump()
  eq(CA.tournament().code, "TRN234", "a private tournament shows its code")
  local byId = CB.joinTournament({ tour = TOUR1, as = "player", party = party,
                                   partyDigest = "d2" })
  pump()
  eq(byId.reason, "tour_private", "a private tournament refuses a bare id")
  CB.joinTournament("trn234", "player", party, "d2")
  pump()
  eq(#CA.tournament().players, 2, "two players are registered by code")

  local closedB
  CB.on("error", function(e) closedB = e end)
  eq(CB.kickFromTournament("u1"), true,
     "a non-creator may still send tour_kick")
  pump()
  eq(#CA.tournament().players, 2, "but the relay refuses it")

  CA.kickFromTournament("u2")
  pump()
  eq(tr.tourKicked, "u2", "tour_kick names its target")
  eq(CB.tournament(), nil, "a kicked player's tournament model is cleared")
  eq(closedB and closedB.scope, "tournament",
     "tour_closed surfaces as a tournament error")
  eq(closedB and closedB.reason, "kicked", "and keeps its reason")
  eq(Protocol2.tourClosedText({ reason = "kicked" }),
     "The creator removed you from the tournament.",
     "tour_closed has human text")
  eq(#CA.tournament().players, 1, "the creator sees the shrunken field")

  local closedA
  CA.on("error", function(e) closedA = e end)
  CA.closeTournament()
  pump()
  eq(tr.tourClosedBy, "u1", "the relay saw tour_close")
  eq(CA.tournament(), nil, "closing drops the creator's model too")
  eq(closedA and closedA.reason, "closed", "with the closed reason")
  eq(CA.closeTournament(), false, "closing twice is a no-op")
  eq(CA.startTournament(), false, "starting without a tournament is a no-op")
  eq(CA.kickFromTournament("u2"), false, "so is kicking")
  CA.disconnect(); CB.disconnect()
end

-- ---------------------------------------------------------------- robustness

local droppedBefore = ClientB.dropped()
relay:to(seatB, { type = "room_state", players = {} })
relay:to(seatB, { type = "join_error" })
relay:to(seatB, { notatype = true })
relay:to(seatB, "a bare string")
ClientB.update(0)
check(ClientB.dropped() >= droppedBefore + 3,
      "malformed server messages are dropped and counted")
eq(ClientB.state(), "online", "malformed messages do not throw or change state")

local errClient = newClientModule()
errClient.configure({ connect = function() return nil, "no relay" end })
local ok, err = errClient.connect({ name = "RED" })
eq(ok, false, "a failed connect reports failure")
eq(errClient.state(), "error", "a failed connect lands in error")
eq(errClient.error(), "no relay", "the failure reason is kept")
errClient.disconnect()
eq(errClient.state(), "offline", "disconnect returns to offline")
errClient.disconnect()
eq(errClient.state(), "offline", "disconnect is idempotent")
errClient.update(1 / 60)
eq(errClient.state(), "offline", "update on an offline client is a no-op")

local throwing = newClientModule()
local seatT = relay:seat("t1", "TRIP")
throwing.on("state", function() error("boom") end)
connectTo(throwing, seatT, "TRIP")
relay:pump()
throwing.update(0)
eq(throwing.state(), "online", "a throwing event handler does not stop the client")

ClientA.disconnect()
ClientB.disconnect()
ClientC.disconnect()
throwing.disconnect()

do
  local r2 = newRelay()
  local seat = r2:seat("z1", "ZED")
  local Stranded = newClientModule()
  connectTo(Stranded, seat, "ZED")
  r2:pump(); Stranded.update(0)
  Stranded.createRoom({ intent = "battle", profile = PROFILE })
  r2:pump(); Stranded.update(0)
  local sess = Stranded.roomSession()
  check(type(sess.update) == "function",
        "a room session exposes update for Game:step")
  check(pcall(function() sess:update(1 / 60) end),
        "room session update does not throw while connected")
  Stranded.disconnect()
  check(pcall(function() sess:update(1 / 60) end),
        "room session update does not throw with no connection")
  eq(sess.closed, true, "a room session closes when the client disconnects")
  check(pcall(function()
          sess:send({ type = "bye" })
          sess:poll()
          sess:take("bye")
          sess:close()
        end), "a stranded room session still answers send/poll/take/close")
end


-- ---------------------------------------------------------------- lockstep

local dataOk = pcall(function()
  local Data = require("src.core.Data")
  if not Data.pokemon then Data:load() end
  require("src.render.Font").load(Data)
end)

if not dataOk then
  print("skip lockstep smoke (data/generated is not built in this checkout)")
else
  local Data = require("src.core.Data")
  local Input = require("src.core.Input")
  local LinkBattle = require("src.link.LinkBattle")
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  Input:init()

  local function makeGame(name, species)
    local save = require("src.core.SaveData").newGame()
    save.player.name = name
    table.insert(save.party, Pokemon.new(Data, species, 50))
    local stack = { list = {} }
    function stack:push(s, ...)
      table.insert(self.list, s)
      if s.enter then s:enter(...) end
    end
    function stack:pop() return table.remove(self.list) end
    function stack:top() return self.list[#self.list] end
    function stack:update(dt)
      local t = self:top()
      if t and t.update then t:update(dt) end
    end
    return { data = Data, input = Input, stack = stack, save = save }
  end

  local lockRelay = newRelay()
  local hostSeat = lockRelay:seat("h", "RED")
  local guestSeat = lockRelay:seat("g", "BLUE")
  local Host = newClientModule()
  local Guest = newClientModule()
  local hostStart, guestStart
  Host.on("match_start", function(p) hostStart = p end)
  Guest.on("match_start", function(p) guestStart = p end)

  connectTo(Host, hostSeat, "RED")
  connectTo(Guest, guestSeat, "BLUE")
  lockRelay:pump(); Host.update(0); Guest.update(0)
  Host.createRoom({ intent = "battle", profile = PROFILE })
  lockRelay:pump(); Host.update(0)
  Guest.joinRoom(ROOM1, "player")
  lockRelay:pump(); Host.update(0); Guest.update(0)

  local gameH = makeGame("RED", "CHARIZARD")
  local gameG = makeGame("BLUE", "BLASTOISE")
  local packedH = Protocol.packParty(gameH.save.party)
  local packedG = Protocol.packParty(gameG.save.party)
  Host.ready(packedH, "dh")
  Guest.ready(packedG, "dg")
  lockRelay:pump(); Host.update(0); Guest.update(0)

  check(hostStart ~= nil and guestStart ~= nil,
        "both ends of the lockstep smoke get match_start")

  local sessHost = Host.roomSession()
  local sessGuest = Guest.roomSession()
  local battleH = LinkBattle.newHost(gameH, sessHost, {
    myParty = packedH, theirParty = hostStart.theirParty,
    theirName = hostStart.peerName, seed = hostStart.seed,
    ruleset = hostStart.ruleset, keepNetOpen = true,
  })
  local battleG = LinkBattle.newGuest(gameG, sessGuest, {
    myParty = packedG, theirParty = guestStart.theirParty,
    theirName = guestStart.peerName, seed = guestStart.seed,
    ruleset = guestStart.ruleset, keepNetOpen = true,
  })
  check(battleH ~= nil and battleG ~= nil,
        "LinkBattle builds over a room session unchanged")

  local resH, resG
  battleH.onFinish = function(r) resH = r end
  battleG.onFinish = function(r) resG = r end
  gameH.stack:push(battleH)
  gameG.stack:push(battleG)

  local guard = 0
  while (resH == nil or resG == nil) and guard < 60000 do
    guard = guard + 1
    lockRelay:pump()
    Input.pressed = { a = true }
    gameH.stack:update(1 / 60)
    gameG.stack:update(1 / 60)
  end
  check(resH ~= nil and resG ~= nil,
        ("the room-session lockstep battle completes (%s / %s)")
          :format(tostring(resH), tostring(resG)))
  check((resH == "win" and resG == "lose") or (resH == "lose" and resG == "win")
        or (resH == "draw" and resG == "draw"),
        "both room-session simulations agree on the outcome")
  eq(battleH.player.mon.hp, battleG.enemy.mon.hp,
     "host mon HP identical across the relay")
  eq(battleH.enemy.mon.hp, battleG.player.mon.hp,
     "guest mon HP identical across the relay")

  sessHost:close()
  eq(sessHost.closed, true, "closing a room session marks it closed")
  local sawLeave = false
  for _, m in ipairs(hostSeat.transport.outbox) do
    if m.type == "room_leave" then sawLeave = true end
  end
  check(sawLeave, "closing a room session sends room_leave")
  Host.disconnect()
  Guest.disconnect()
end

-- ---------------------------------------------------------------- real relay

love.timer.getTime = function() return os.clock() end

local hasSocket = pcall(require, "socket")
local nodeCheck = os.execute("command -v node >/dev/null 2>&1")
local hasNode = nodeCheck == true or nodeCheck == 0
local serverFile = io.open("../pokeserver/server.js", "r")
if serverFile then serverFile:close() end
local relaySource = io.open("../pokeserver/relay.js", "r")
local relayV3 = false
if relaySource then
  relayV3 = (relaySource:read("*a") or ""):find("upgrade_required", 1, true) ~= nil
  relaySource:close()
end

if not hasSocket then
  print("skip real relay v3 (luasocket not available under this interpreter)")
elseif not hasNode then
  print("skip real relay v3 (node not on PATH to spawn pokeserver)")
elseif not serverFile then
  print("skip real relay v3 (../pokeserver/server.js is not checked out)")
elseif not relayV3 then
  print("skip real relay v3 (../pokeserver predates protocol 3)")
else
  local PORT = 17780
  local pidFile = os.tmpname()
  os.execute(("(cd ../pokeserver && PORT=%d HTTP_PORT=%d node server.js >/tmp/pokeserver_v2_test.log 2>&1 & echo $! > %q)")
             :format(PORT, PORT + 1, pidFile))

  local function busyWait(seconds)
    local t0 = os.clock()
    while os.clock() - t0 < seconds do end
  end

  local function tcpConnectable(host, port)
    local socket = require("socket")
    local tcp = socket.tcp()
    tcp:settimeout(0.2)
    local ok = tcp:connect(host, port)
    tcp:close()
    return ok ~= nil
  end

  local ready = false
  for _ = 1, 50 do
    ready = tcpConnectable("127.0.0.1", PORT)
    if ready then break end
    busyWait(0.1)
  end

  if not ready then
    print("skip real relay v2 (couldn't reach the spawned pokeserver)")
  else
    local Live = newClientModule()
    Live.configure({ relayAddress = "127.0.0.1:" .. PORT })
    Live.connect({ name = "RED", profiles = { PROFILE } })
    local Peer = newClientModule()
    Peer.configure({ relayAddress = "127.0.0.1:" .. PORT })
    Peer.connect({ name = "BLUE", profiles = { PROFILE } })

    local function pump()
      Live.update(1 / 60)
      Peer.update(1 / 60)
    end
    local function waitFor(fn, seconds)
      local deadline = os.clock() + (seconds or 3)
      while os.clock() < deadline do
        pump()
        if fn() then return true end
      end
      return false
    end

    if not waitFor(function()
          return Live.state() == "online" and Peer.state() == "online"
        end, 3) then
      print("skip real relay v3 (the server did not answer lobby_hello in 3 s: "
            .. tostring(Live.state()) .. " " .. tostring(Live.error()) .. ")")
    else
      check(Live.you() ~= nil, "the real relay welcomes a v3 client")
      local room = Live.createRoom({ intent = "battle", profile = PROFILE })
      waitFor(function() return room.done end, 3)
      check(room.done and room.id ~= nil,
            "the real relay creates a v3 room: " .. tostring(room.error))
      if room.id then
        local joined = Peer.joinRoom(room.id, "player", PROFILE)
        waitFor(function() return joined.done end, 3)
        check(joined.done and joined.error == nil,
              "the real relay admits a matching profile: " .. tostring(joined.error))

        local badPeer = newClientModule()
        badPeer.configure({ relayAddress = "127.0.0.1:" .. PORT })
        badPeer.connect({ name = "GREEN", profiles = { PROFILE } })
        local badProfile = copy(PROFILE)
        badProfile.fingerprint = "deadbeef"
        local refused
        local badDeadline = os.clock() + 3
        while os.clock() < badDeadline do
          badPeer.update(1 / 60)
          if badPeer.state() == "online" and not refused then
            refused = badPeer.joinRoom(room.id, "spectator", badProfile)
          end
          if refused and refused.done then break end
        end
        check(refused and refused.reason == "profile_mismatch",
              "the real relay refuses a mismatched spectator profile: "
              .. tostring(refused and refused.reason))
        badPeer.disconnect()

        local startLive, startPeer, endLive
        Live.on("match_start", function(p) startLive = p end)
        Peer.on("match_start", function(p) startPeer = p end)
        Live.on("match_end", function(p) endLive = p end)
        local party = { { species = "CHARIZARD", level = 50, hp = 10,
                          moves = { { id = "TACKLE", pp = 35 } } } }
        Live.ready(party, "dl")
        Peer.ready(party, "dp")
        waitFor(function() return startLive and startPeer end, 3)
        check(startLive ~= nil and startPeer ~= nil,
              "the real relay starts the match on both seats")
        if startLive and startPeer then
          eq(startLive.role, "host", "the real relay makes the creator the host")
          eq(startPeer.role, "guest", "the real relay makes the joiner the guest")
          eq(startLive.match, startPeer.match,
             "both seats share the real relay's match token")
          check(startLive.seed ~= nil and startLive.seed == startPeer.seed,
                "both seats share the real relay's seed")
          Live.report("win")
          Peer.report("lose")
          waitFor(function() return endLive ~= nil end, 5)
          check(endLive ~= nil, "the real relay answers room_report")
          if endLive then
            eq(endLive.match, startLive.match, "room_result names the match")
            eq(endLive.how, "agreed", "the real relay agrees the two reports")
            eq(endLive.youWon, true, "the reported winner is told it won")
          end
        end
      end


      Live.leaveRoom()
      Peer.leaveRoom()
      local Third = newClientModule()
      Third.configure({ relayAddress = "127.0.0.1:" .. PORT })
      Third.connect({ name = "GOLD", profiles = { PROFILE } })
      local function pumpAll()
        Live.update(1 / 60); Peer.update(1 / 60); Third.update(1 / 60)
      end
      local function waitAll(fn, seconds)
        local deadline = os.clock() + (seconds or 3)
        while os.clock() < deadline do
          pumpAll()
          if fn() then return true end
        end
        return false
      end
      waitAll(function() return Third.state() == "online" end, 3)

      local hostParty = { { species = "CHARIZARD", level = 50, hp = 10,
                            moves = { { id = "TACKLE", pp = 35 } } } }
      local made = Live.createTournament({ profile = PROFILE, playing = true,
                                           shotClock = 3, maxSpectators = 8,
                                           party = hostParty,
                                           partyDigest = "dl" })
      waitAll(function() return made.done or Live.tournament() ~= nil end, 3)
      local mine = Live.tournament()
      if not mine then
        print("skip real relay tournaments (no tour_create support yet: "
              .. tostring(made.reason or made.error or "no reply") .. ")")
      else
        check(mine.tour ~= nil, "the real relay creates a tournament")
        eq(mine.code, nil, "a public tournament carries no code")
        local tourId = mine.tour
        local tourParty = { { species = "CHARIZARD", level = 50, hp = 10,
                              moves = { { id = "TACKLE", pp = 35 } } } }
        Peer.joinTournament({ tour = tourId, as = "player", party = tourParty,
                              partyDigest = "dp" })
        Third.joinTournament({ tour = tourId, as = "spectator" })
        waitAll(function()
          local t = Live.tournament()
          return t ~= nil and #t.players >= 2 and #t.spectators >= 1
        end, 3)
        local t = Live.tournament()
        check(t ~= nil and #t.players >= 2,
              "the real relay registers the second player")
        check(t ~= nil and #t.spectators >= 1,
              "the real relay registers the outside spectator")

        local liveStart, peerStart, specStart, overSeen
        Live.on("match_start", function(p) liveStart = p end)
        Peer.on("match_start", function(p) peerStart = p end)
        Third.on("match_start", function(p) specStart = p end)
        Live.on("tour_over", function(p) overSeen = p end)
        Live.startTournament()
        waitAll(function() return liveStart ~= nil and peerStart ~= nil end, 5)
        check(liveStart ~= nil and peerStart ~= nil,
              "the real relay starts the first bracket match")
        if liveStart and peerStart then
          eq(liveStart.match, peerStart.match,
             "both finalists share the bracket match token")
          check(Live.room() ~= nil and Live.room().room == liveStart.room,
                "the client follows the relay into the child room")
          check(specStart == nil or specStart.role == "spectator",
                "an outside spectator boots as a spectator")
          Live.report("win")
          Peer.report("lose")
          waitAll(function() return overSeen ~= nil end, 5)
          check(overSeen ~= nil, "a two-player bracket finishes")
          if overSeen then
            eq(Live.tournament().stage, "finished",
               "the model stays finished until we leave")
          end
        end
        Live.leaveTournament()
        Peer.leaveTournament()
        Third.leaveTournament()
      end
      Third.disconnect()
    end
    Peer.disconnect()
    Live.disconnect()
  end

  local pidHandle = io.open(pidFile, "r")
  if pidHandle then
    local pid = pidHandle:read("*l")
    pidHandle:close()
    if pid and pid ~= "" then os.execute("kill " .. pid .. " >/dev/null 2>&1") end
  end
  os.remove(pidFile)
end

love.timer.getTime = savedGetTime

if failures > 0 then
  print(("\n%d online client check(s) failed"):format(failures))
  os.exit(1)
end
print("\nonline client tests passed")
return failures

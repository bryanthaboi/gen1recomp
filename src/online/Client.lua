local Protocol2 = require("src.online.Protocol2")
local Session = require("src.link.Session")
local Version = require("src.core.Version")
local Wire = require("src.link.Wire")

local Client = {}

local BACKOFF = { 1, 2, 4, 8, 15 }
local MAX_ATTEMPTS = 12
local MATCH_STAGES = { battling = true }
local ROOM_STAGES = { waiting = true, ready = true, battling = true,
                      ended = true }
local UNACKED_MAX = 512

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local S
local clearRoom
local clearTournament
local resumeLost

local function blankState()
  return {
    relayAddress = nil,
    connectFn = nil,
    platform = nil,
    engineVersion = Version.engine,
    status = "offline",
    err = nil,
    opts = nil,
    net = nil,
    session = nil,
    sessionId = nil,
    you = nil,
    heartbeatMs = nil,
    serverTime = nil,
    serverTimeAt = nil,
    lobby = {},
    lobbyById = {},
    room = nil,
    leftRoom = nil,
    roomSession = nil,
    pending = nil,
    seq = 0,
    ack = 0,
    rxSeq = 0,
    unacked = {},
    unackedFloor = 0,
    unackedDropped = 0,
    pendingReport = nil,
    reportSent = nil,
    roomInbox = {},
    delivered = {},
    matchStarted = false,
    match = nil,
    role = nil,
    resuming = false,
    attempt = 0,
    retryAt = nil,
    handlers = {},
    dropped = 0,
    duplicates = 0,
    advertised = nil,
    online = nil,
    tournament = nil,
    tourMatch = nil,
    tourFinished = {},
    seat = nil,
    presence = nil,
    welcomed = false,
    upgrade = nil,
    invites = {},
    outgoing = {},
    plazaJoins = {},
    plaza = nil,
    plazaCounts = nil,
    groupOpen = nil,
    groupWatch = nil,
    groupLists = {},
    group = nil,
    directQueue = nil,
    directWatch = nil,
    directLists = {},
    direct = nil,
  }
end

S = blankState()

function Client.reset()
  if S.session then pcall(function() S.session:close() end) end
  S = blankState()
end

-- ---------------------------------------------------------------- events

function Client.on(event, fn)
  if type(event) ~= "string" or type(fn) ~= "function" then return end
  local list = S.handlers[event]
  if not list then
    list = {}
    S.handlers[event] = list
  end
  list[#list + 1] = fn
end

function Client.off(event, fn)
  local list = S.handlers[event]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == fn or fn == nil then table.remove(list, i) end
  end
end

local function emit(event, payload)
  local list = S.handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], payload)
    if not ok then
      S.err = tostring(err)
    end
  end
end

local function setState(status)
  if S.status == status then return end
  S.status = status
  emit("state", status)
end

-- ---------------------------------------------------------------- accessors

function Client.state() return S.status end
function Client.match() return S.match end
function Client.seat() return S.seat end
function Client.upgradeRequired() return S.upgrade end
function Client.invites() return S.invites end
function Client.outgoing() return S.outgoing end
function Client.plaza() return S.plaza end
function Client.plazaRev()
  local p = S.plaza
  if not p then return nil end
  return p.instance, p.rev
end
function Client.plazaCounts() return S.plazaCounts end
function Client.group() return S.group end
function Client.direct() return S.direct end
function Client.presence() return S.presence end

function Client.groups(activity)
  return S.groupLists[activity or ""] or {}
end

function Client.directEntries(activity)
  return S.directLists[activity or ""] or {}
end

function Client.serverTime()
  if not S.serverTime then return nil end
  return S.serverTime + (now() - (S.serverTimeAt or now())) * 1000
end

function Client.role() return S.role end
function Client.error() return S.err end
function Client.you() return S.you end
function Client.lobby() return S.lobby end
function Client.room() return S.room end
function Client.tournament() return S.tournament end
function Client.tourMatch() return S.tourMatch end
function Client.dropped() return S.dropped end
function Client.unackedDropped() return S.unackedDropped end
function Client.unackedCount() return #S.unacked end
function Client.pendingReport() return S.pendingReport end
function Client.duplicates() return S.duplicates end
function Client.sessionId() return S.sessionId end

-- ---------------------------------------------------------------- transport

local function openTransport()
  if S.connectFn then
    local transport, err = S.connectFn(S.relayAddress)
    if not transport then return nil, err or "no transport" end
    return transport
  end
  local Net = require("src.link.Net")
  local net = Net.new()
  local address = S.relayAddress or Net.defaultRelayAddress()
  if not net:connectTCP(address) then
    return nil, net.error or ("can't reach the relay at " .. tostring(address))
  end
  net.mode = "onlineLobby"
  return net
end

local function sendRaw(msg)
  if not msg or not S.session then return false end
  S.session:send(msg)
  return true
end

Client.sendRaw = sendRaw

-- ---------------------------------------------------------------- room session

local RoomSession = {}
RoomSession.__index = RoomSession

local function roomEngine(room)
  if not room then return nil end
  return room.engine or (room.profile and room.profile.engine) or nil
end

local function refreshRoomSession()
  local rs = S.roomSession
  if not rs then return end
  local room = S.room
  local players = room and room.players or {}
  rs.paired = room ~= nil and #players >= (room.seats or 2)
  rs.error = S.err
  if room then rs.target = room.room end
  if not room and not rs.left then rs.closed = true end
  if S.status == "error" or S.status == "offline" then rs.closed = true end
end

local function shaped(entry)
  if entry.shape then return entry.shape end
  local msg = entry.msg
  if entry.bare then return msg end
  if entry.relay then
    if type(msg.seat) ~= "number" then msg.seat = -1 end
    msg.relay = true
  elseif entry.g3 then
    msg.seat = entry.seat
    msg.relay = nil
  elseif entry.side then
    entry.shape = { type = "spectate", side = entry.side, msg = msg }
    return entry.shape
  end
  entry.shape = msg
  return msg
end

local function deliver(entries)
  local out = {}
  for i = 1, #entries do
    out[i] = shaped(entries[i])
    local seq = entries[i].seq
    if type(seq) == "number" and seq > S.ack then S.delivered[seq] = true end
  end
  local before = S.ack
  while S.delivered[S.ack + 1] do
    S.delivered[S.ack + 1] = nil
    S.ack = S.ack + 1
  end
  if S.ack > before then sendRaw(Protocol2.roomAck(S.ack)) end
  return out
end

function RoomSession:update()
  Client.update(0)
end

function RoomSession:send(msg)
  if type(msg) ~= "table" then return end
  if self.closed then return end
  S.seq = S.seq + 1
  local wrapped = Protocol2.roomMsg(S.seq, msg)
  if not wrapped then return end
  S.unacked[#S.unacked + 1] = wrapped
  while #S.unacked > UNACKED_MAX do
    local oldest = table.remove(S.unacked, 1)
    S.unackedDropped = S.unackedDropped + 1
    S.unackedFloor = (oldest.seq or 0) + 1
  end
  sendRaw(wrapped)
end

local function leftover(rs)
  if rs.leftover and rs ~= S.roomSession then return rs.leftover end
  return nil
end

function RoomSession:poll()
  local rest = leftover(self)
  if rest then
    self.leftover = {}
    local out = {}
    for i = 1, #rest do out[i] = shaped(rest[i]) end
    return out
  end
  local entries = S.roomInbox
  S.roomInbox = {}
  return deliver(entries)
end

function RoomSession:pollOne()
  local rest = leftover(self)
  if rest then
    if #rest == 0 then return nil end
    return shaped(table.remove(rest, 1))
  end
  if #S.roomInbox == 0 then return nil end
  local entry = table.remove(S.roomInbox, 1)
  return deliver({ entry })[1]
end

function RoomSession:take(messageType, predicate)
  local rest = leftover(self)
  local inbox = rest or S.roomInbox
  for index = 1, #inbox do
    local entry = inbox[index]
    local msg = shaped(entry)
    if msg.type == messageType
       and (predicate == nil or predicate(msg) == true) then
      table.remove(inbox, index)
      if rest then return msg end
      return deliver({ entry })[1]
    end
  end
  return nil
end

function RoomSession:unread(messages)
  if type(messages) ~= "table" then return end
  local inbox = leftover(self) or S.roomInbox
  for index = #messages, 1, -1 do
    local msg = messages[index]
    if type(msg) == "table" and type(msg.type) == "string" then
      table.insert(inbox, 1, { seq = nil, msg = msg, bare = true })
    end
  end
end

function RoomSession:hasPending()
  local rest = leftover(self)
  if rest then return #rest > 0 end
  return #S.roomInbox > 0
end

function RoomSession:seat() return S.seat end
function RoomSession:role() return S.role end
function RoomSession:match() return S.match end
function RoomSession:seats() return S.room and S.room.seats or nil end
function RoomSession:players() return S.room and S.room.players or {} end
function RoomSession:seed() return S.room and S.room.seed or nil end
function RoomSession:engine() return roomEngine(S.room) end

function RoomSession:peerOnline(seat)
  local room = S.room
  if not room then return false end
  for _, p in ipairs(room.players or {}) do
    if p.seat == seat then return p.online ~= false end
  end
  return false
end

local function sendLeave()
  if S.room then S.leftRoom = S.room.room end
  if S.room and S.role == "host" and S.room.intent == "battle" then
    sendRaw(Protocol2.roomClose())
  end
  sendRaw(Protocol2.roomLeave())
end

function RoomSession:close()
  if self.left then return end
  self.left = true
  self.closed = true
  sendLeave()
  clearRoom()
end

function Client.roomSession()
  if not S.room then return nil end
  if not S.roomSession or S.roomSession.left then
    S.roomSession = setmetatable({
      paired = false, closed = false, error = nil, left = false,
      code = nil, target = S.room.room,
    }, RoomSession)
  end
  refreshRoomSession()
  return S.roomSession
end

-- ---------------------------------------------------------------- lobby model

local function lobbyLess(a, b)
  local sa, sb = a.since or 0, b.since or 0
  if sa ~= sb then return sa < sb end
  return tostring(a.id) < tostring(b.id)
end

local function sortLobby()
  table.sort(S.lobby, lobbyLess)
end

local function putEntry(entry)
  if not entry or not entry.id then return end
  local existing = S.lobbyById[entry.id]
  if existing then
    for i = 1, #S.lobby do
      if S.lobby[i].id == entry.id then S.lobby[i] = entry end
    end
  else
    S.lobby[#S.lobby + 1] = entry
  end
  S.lobbyById[entry.id] = entry
end

local function dropEntry(id)
  if not id or not S.lobbyById[id] then return end
  S.lobbyById[id] = nil
  for i = #S.lobby, 1, -1 do
    if S.lobby[i].id == id then table.remove(S.lobby, i) end
  end
end

function Client.openRooms()
  local mine = S.you and S.you.id or nil
  local offline = {}
  for i = 1, #S.lobby do
    local entry = S.lobby[i]
    if entry.room and entry.online == false then offline[entry.room] = true end
  end
  local out = {}
  for i = 1, #S.lobby do
    local entry = S.lobby[i]
    if entry.room and entry.open == true and entry.id ~= mine
       and not offline[entry.room] then
      out[#out + 1] = entry
    end
  end
  table.sort(out, lobbyLess)
  return out
end

function Client.watchable()
  local mine = S.you and S.you.id or nil
  local out = {}
  for i = 1, #S.lobby do
    local entry = S.lobby[i]
    if entry.id ~= mine then
      local room = entry.room ~= nil and entry.stage == "battling"
        and (entry.spectators or 0) < (entry.maxSpectators or 0)
      if room or entry.tour ~= nil then out[#out + 1] = entry end
    end
  end
  table.sort(out, lobbyLess)
  return out
end

function Client.counts()
  local seen, players = {}, 0
  for i = 1, #S.lobby do
    local id = S.lobby[i].id
    if id and not seen[id] then
      seen[id] = true
      players = players + 1
    end
  end
  if type(S.online) == "number" then players = S.online end
  return { players = players, openRooms = #Client.openRooms() }
end

-- ---------------------------------------------------------------- room model

local function seatedPlayers(list)
  local out = {}
  for i, p in ipairs(list or {}) do
    if type(p.seat) ~= "number" then p.seat = i - 1 end
    out[#out + 1] = p
  end
  table.sort(out, function(a, b) return a.seat < b.seat end)
  return out
end

local function myRole(room)
  local me = S.you and S.you.id
  if me and room then
    for _, p in ipairs(room.players or {}) do
      if p.id == me then
        return Protocol2.seatRole(p.seat) or "spectator", p.seat
      end
    end
  end
  return "spectator", nil
end

local function applyRoomState(msg)
  local previous = S.room
  local deadlines = {}
  for _, d in ipairs(msg.deadlines or {}) do
    if d.kind then deadlines[d.kind] = d.at end
  end
  if previous and previous.room == msg.room then
    for kind, at in pairs(previous.deadlines or {}) do
      if deadlines[kind] == nil then deadlines[kind] = at end
    end
  end
  if not previous or previous.room ~= msg.room then
    S.seq, S.ack, S.rxSeq = 0, 0, 0
    S.unacked = {}
    S.unackedFloor = 0
    S.delivered = {}
    S.roomInbox = {}
    S.matchStarted = false
    S.pendingReport = nil
  end
  S.room = {
    room = msg.room,
    intent = msg.intent,
    engine = msg.engine or (msg.profile and msg.profile.engine) or nil,
    profile = msg.profile,
    rule = msg.rule or (msg.profile and msg.profile.rule) or nil,
    seats = msg.seats or 2,
    locked = msg.locked == true,
    listed = msg.listed,
    auto = msg.auto == true,
    origin = msg.origin,
    players = seatedPlayers(msg.players),
    spectators = msg.spectators or {},
    stage = ROOM_STAGES[msg.stage or ""] and msg.stage or "waiting",
    host = msg.host,
    seed = msg.seed,
    match = msg.match,
    maxSpectators = msg.maxSpectators,
    leader = msg.leader,
    deadlines = deadlines,
  }
  S.match = msg.match or S.match
  S.role, S.seat = myRole(S.room)
  if S.roomSession and S.roomSession.left then S.roomSession = nil end
  if S.pending and not S.pending.done and S.pending.kind ~= "tournament"
     and (S.pending.id == nil or S.pending.id == msg.room) then
    S.pending.id = msg.room
    S.pending.room = S.room
    S.pending.done = true
  end
  if not MATCH_STAGES[S.room.stage] then S.matchStarted = false end
  emit("room", S.room)
  refreshRoomSession()
end

clearRoom = function()
  S.room = nil
  S.match = nil
  S.role = nil
  S.seat = nil
  S.matchStarted = false
  S.seq, S.ack, S.rxSeq = 0, 0, 0
  S.unacked = {}
  S.unackedFloor = 0
  S.delivered = {}
  local inbox = S.roomInbox
  S.roomInbox = {}
  S.pendingReport = nil
  if S.roomSession then
    local keep = {}
    for i = 1, #inbox do
      local entry = inbox[i]
      local kind = entry.msg and entry.msg.type
      if entry.relay and (kind == "trade_commit" or kind == "trade_abort") then
        keep[#keep + 1] = entry
      end
    end
    S.roomSession.leftover = keep
    S.roomSession.closed = true
    S.roomSession.left = true
    S.roomSession = nil
  end
end

clearTournament = function()
  S.pendingReport = nil
  S.tournament = nil
  S.tourMatch = nil
  S.tourFinished = {}
end

resumeLost = function()
  local room = S.room and S.room.room or nil
  sendRaw(Protocol2.roomLeave())
  clearRoom()
  emit("room", nil)
  emit("error", { scope = "room", reason = "resume_incomplete", room = room,
                  text = Protocol2.roomClosedText({
                    reason = "resume_incomplete" }) })
end

local function enterChildRoom(roomId, msg)
  if not roomId then return end
  if S.room and S.room.room == roomId then
    S.room.match = msg and msg.match or S.room.match
    return
  end
  clearRoom()
  local tour = S.tournament
  local profile = tour and tour.profile or nil
  S.room = {
    room = roomId,
    intent = "tournament",
    engine = profile and profile.engine or nil,
    profile = profile,
    rule = tour and tour.rule or nil,
    seats = 2,
    locked = false,
    listed = false,
    auto = false,
    origin = "tour",
    players = {},
    spectators = {},
    stage = "waiting",
    host = nil,
    seed = nil,
    match = msg and msg.match or nil,
    maxSpectators = nil,
    leader = nil,
    deadlines = {},
  }
  S.match = S.room.match
  emit("room", S.room)
  refreshRoomSession()
end

local function applyTourState(msg)
  local previous = S.tournament
  local deadlines = {}
  if previous and previous.tour == msg.tour then
    for kind, at in pairs(previous.deadlines or {}) do deadlines[kind] = at end
  end
  if not previous or previous.tour ~= msg.tour then S.tourFinished = {} end
  S.tournament = {
    tour = msg.tour,
    code = msg.code,
    creator = msg.creator,
    stage = msg.stage or "registering",
    players = msg.players or {},
    spectators = msg.spectators or {},
    profile = msg.profile,
    rule = msg.rule or (msg.profile and msg.profile.rule) or nil,
    shotClock = msg.shotClock,
    round = msg.round,
    bracket = msg.bracket or {},
    live = msg.live,
    champion = msg.champion,
    championId = msg.championId,
    maxSpectators = msg.maxSpectators,
    deadlines = deadlines,
  }
  if S.pending and not S.pending.done and S.pending.kind == "tournament"
     and (S.pending.id == nil or S.pending.id == msg.tour) then
    S.pending.id = msg.tour
    S.pending.tournament = S.tournament
    S.pending.done = true
  end
  emit("tournament", S.tournament)
end

local function staleRoom(room)
  if room == nil or room ~= S.leftRoom then return false end
  if S.room and S.room.room == room then return false end
  local p = S.pending
  if p and not p.done and p.kind ~= "tournament" and p.id == room then return false end
  return true
end

local function matchStart(msg)
  local role = msg.role
  if not Protocol2.roleSeat(role) then role = "spectator" end
  S.role = role
  if role == "spectator" then
    S.seat = nil
  else
    S.seat = msg.seat or Protocol2.roleSeat(role)
  end
  S.match = msg.match or S.match
  local room = S.room
  if room then
    room.seed = msg.seed or room.seed
    room.match = S.match
    if msg.rule then room.rule = msg.rule end
    if msg.seats then room.seats = msg.seats end
    if msg.engine then room.engine = msg.engine end
  end
  if S.reportSent ~= S.match then S.reportSent = nil end
  if S.matchStarted then return end
  S.matchStarted = true
  emit("match_start", {
    room = msg.room or (room and room.room) or nil,
    match = S.match,
    role = role,
    seat = S.seat,
    seats = msg.seats or (room and room.seats) or 2,
    engine = msg.engine or roomEngine(room),
    seed = msg.seed,
    profile = room and room.profile or nil,
    ruleset = msg.ruleset,
    rule = msg.rule,
    players = msg.players,
    parties = msg.parties,
    peerName = msg.peerName,
    hostName = msg.hostName,
    guestName = msg.guestName,
    myParty = nil,
    theirParty = msg.theirParty,
    hostParty = msg.hostParty,
    guestParty = msg.guestParty,
  })
end

local function acceptRoomMsg(entry)
  local seq = entry.seq
  if type(seq) == "number" and seq > 0 then
    if seq <= S.rxSeq then
      S.duplicates = S.duplicates + 1
      return
    end
    S.rxSeq = seq
  end
  local rec = {
    seq = seq, side = entry.side, seat = entry.seat,
    relay = entry.relay == true or entry.seat == -1,
    g3 = roomEngine(S.room) == 3,
    msg = entry.msg,
  }
  S.roomInbox[#S.roomInbox + 1] = rec
  local kind = rec.msg.type
  if rec.relay and (kind == "trade_commit" or kind == "trade_abort") then
    emit(kind, shaped(rec))
  end
end

local function sortMembers(list)
  table.sort(list, function(a, b)
    local sa, sb = a.slot or 99, b.slot or 99
    if sa ~= sb then return sa < sb end
    return tostring(a.id) < tostring(b.id)
  end)
  return list
end

local function applyPlazaDelta(msg)
  local plaza = S.plaza
  if not plaza or plaza.kind ~= msg.kind then return false end
  if msg.instance ~= nil and plaza.instance ~= nil
     and msg.instance ~= plaza.instance then
    return false
  end
  if type(msg.rev) == "number" then plaza.rev = msg.rev end
  local gone = {}
  for _, id in ipairs(msg.left or {}) do gone[id] = true end
  local members = {}
  for _, m in ipairs(plaza.members) do
    if not gone[m.id] then members[#members + 1] = m end
  end
  local byId = {}
  for i, m in ipairs(members) do byId[m.id] = i end
  for _, list in ipairs({ msg.joined or {}, msg.changed or {} }) do
    for _, m in ipairs(list) do
      local at = byId[m.id]
      if at then
        members[at] = m
      else
        members[#members + 1] = m
        byId[m.id] = #members
      end
    end
  end
  plaza.members = sortMembers(members)
  return true
end

local function closeOutgoing(handle, msg)
  handle.why = msg.why
  handle.room = msg.room or handle.room
  handle.detail = msg.detail
  if msg.why == "accepted" or msg.why == "crossed" then
    handle.state = "accepted"
  else
    handle.state = "closed"
  end
  for i = #S.outgoing, 1, -1 do
    if S.outgoing[i] == handle then table.remove(S.outgoing, i) end
  end
end

local function findOutgoing(msg)
  for _, h in ipairs(S.outgoing) do
    if msg.id and h.id == msg.id then return h end
  end
  for _, h in ipairs(S.outgoing) do
    if h.state == "sending" and (msg.to == nil or h.to == msg.to)
       and (msg.activity == nil or h.activity == msg.activity) then
      return h
    end
  end
  return nil
end

local function dropInvite(id)
  for i = #S.invites, 1, -1 do
    if S.invites[i].id == id then
      table.remove(S.invites, i)
      return true
    end
  end
  return false
end

local function forgetPresenceState()
  S.plaza = nil
  S.plazaCounts = nil
  S.group = nil
  S.groupLists = {}
  S.direct = nil
  S.directLists = {}
  S.invites = {}
  local open = S.outgoing
  S.outgoing = {}
  for _, h in ipairs(open) do
    h.state = "closed"
    h.why = "sender_left"
  end
end

local function resendState()
  local profiles = S.opts and S.opts.profiles
  if type(profiles) == "table" and #profiles > 0 then
    sendRaw(Protocol2.setProfiles(profiles))
  end
  if S.presence then sendRaw(Protocol2.presence(S.presence)) end
  for _, kind in ipairs({ "union", "wireless" }) do
    local j = S.plazaJoins[kind]
    if j then sendRaw(Protocol2.plazaJoin(kind, j.profile, j.avatar, j.cap)) end
  end
  local board = S.presence and S.presence.board
  if S.plazaJoins.union and type(board) == "table" then
    sendRaw(Protocol2.presence({ board = board }))
  end
  if S.directQueue then sendRaw(Protocol2.directQueue(S.directQueue)) end
  if S.directWatch then
    sendRaw(Protocol2.directList(S.directWatch.activity, S.directWatch.profile))
  end
  local g = S.groupOpen
  if g then sendRaw(Protocol2.groupOpen(g.activity, g.profile, g.avatar)) end
  if S.groupWatch then
    sendRaw(Protocol2.groupList(S.groupWatch.activity, S.groupWatch.profile))
  end
end

-- ---------------------------------------------------------------- dispatch

local helloMessage

local function handle(msg)
  local kind = msg.type
  if kind == "lobby_welcome" then
    local resumed = msg.resumed == true
      and (S.resuming or (S.sessionId ~= nil and msg.session == S.sessionId))
    S.sessionId = msg.session
    S.you = { name = msg.you.name, verified = msg.you.verified,
              id = msg.you.id, session = msg.session }
    S.heartbeatMs = msg.heartbeatMs
    S.serverTime = msg.serverTime
    S.serverTimeAt = now()
    S.attempt = 0
    S.retryAt = nil
    S.err = nil
    S.resuming = false
    if not resumed then
      clearRoom()
      clearTournament()
      forgetPresenceState()
    end
    setState("online")
    if not resumed and S.welcomed then resendState() end
    S.welcomed = true
  elseif kind == "upgrade_required" then
    S.upgrade = msg
    S.err = Protocol2.upgradeText(msg)
    S.sessionId = nil
    S.resuming = false
    local session = S.session
    S.session = nil
    S.net = nil
    if session then pcall(function() session:close() end) end
    clearRoom()
    clearTournament()
    forgetPresenceState()
    setState("error")
    refreshRoomSession()
    emit("upgrade_required", msg)
  elseif kind == "lobby_list" then
    S.lobby, S.lobbyById = {}, {}
    S.online = type(msg.online) == "number" and msg.online or nil
    for _, entry in ipairs(msg.entries) do putEntry(entry) end
    sortLobby()
    emit("lobby", S.lobby)
  elseif kind == "lobby_delta" then
    for _, entry in ipairs(msg.added or {}) do putEntry(entry) end
    for _, entry in ipairs(msg.changed or {}) do putEntry(entry) end
    for _, id in ipairs(msg.removed or {}) do dropEntry(id) end
    for _, entry in ipairs(msg.add or {}) do putEntry(entry) end
    for _, entry in ipairs(msg.update or {}) do putEntry(entry) end
    for _, id in ipairs(msg.remove or {}) do dropEntry(id) end
    if msg.op == "add" or msg.op == "update" then putEntry(msg.entry)
    elseif msg.op == "remove" then dropEntry(msg.id or (msg.entry and msg.entry.id)) end
    sortLobby()
    emit("lobby", S.lobby)
  elseif kind == "room_state" then
    if staleRoom(msg.room) then return end
    if not (S.tournament and S.tourFinished[msg.room]) then
      S.leftRoom = nil
      applyRoomState(msg)
    end
  elseif kind == "match_start" or kind == "match_start_spectate" then
    if staleRoom(msg.room) then return end
    matchStart(msg)
  elseif kind == "room_replay" then
    if type(msg.yourSeq) == "number" then
      for i = #S.unacked, 1, -1 do
        if (S.unacked[i].seq or 0) <= msg.yourSeq then table.remove(S.unacked, i) end
      end
      if S.unackedFloor > 0 and msg.yourSeq + 1 < S.unackedFloor then
        resumeLost()
        return
      end
      for i = 1, #S.unacked do sendRaw(S.unacked[i]) end
    end
    for _, entry in ipairs(msg.msgs) do acceptRoomMsg(entry) end
    if S.rxSeq > S.ack then sendRaw(Protocol2.roomAck(S.ack)) end
    refreshRoomSession()
  elseif kind == "room_msg" then
    acceptRoomMsg(msg)
  elseif kind == "room_deadline" then
    if S.room then
      S.room.deadlines = S.room.deadlines or {}
      S.room.deadlines[msg.kind] = msg.at
      emit("room", S.room)
    end
  elseif kind == "room_result" then
    S.matchStarted = false
    if S.pendingReport
       and (msg.match == nil or msg.match == S.pendingReport.match) then
      S.pendingReport = nil
    end
    local me = S.you and S.you.id
    local youWon = me ~= nil and msg.winnerId ~= nil and msg.winnerId == me
    for _, id in ipairs(msg.winners or {}) do
      if me ~= nil and id == me then youWon = true end
    end
    local roomId = msg.room or (S.room and S.room.room) or nil
    emit("match_end", {
      match = msg.match,
      room = roomId,
      winner = msg.winner,
      winnerId = msg.winnerId,
      winnerSide = msg.winnerSide,
      winners = msg.winners or {},
      how = msg.how,
      youWon = youWon,
    })
    if S.tournament then
      if roomId then S.tourFinished[roomId] = true end
      S.tourMatch = nil
      clearRoom()
      emit("room", nil)
    end
  elseif kind == "room_closed" then
    local current = S.room and S.room.room or nil
    if msg.room ~= nil and msg.room ~= current then
      local p = S.pending
      local awaited = current == nil and p and not p.done
        and p.kind ~= "tournament" and p.id == msg.room
      if staleRoom(msg.room) or not awaited then return end
    end
    local roomId = msg.room or current
    clearRoom()
    if S.pending and not S.pending.done then
      S.pending.error = Protocol2.roomClosedText(msg)
      S.pending.reason = msg.reason
      S.pending.done = true
    end
    emit("room", nil)
    emit("error", { scope = "room", reason = msg.reason, room = roomId,
                    text = Protocol2.roomClosedText(msg) })
  elseif kind == "tour_state" then
    applyTourState(msg)
  elseif kind == "tour_match" or kind == "tour_match_spectate" then
    local payload = { match = msg.match, round = msg.round, room = msg.room,
                      role = kind == "tour_match" and "player" or "spectator" }
    S.tourMatch = payload
    S.tourFinished[msg.room] = nil
    enterChildRoom(msg.room, msg)
    emit(kind == "tour_match" and "tour_match" or "tour_spectate", payload)
  elseif kind == "tour_bye" then
    emit("tour_bye", { match = msg.match, round = msg.round })
  elseif kind == "tour_deadline" then
    if S.tournament then
      S.tournament.deadlines = S.tournament.deadlines or {}
      S.tournament.deadlines[msg.kind] = msg.at
      emit("tournament", S.tournament)
    end
    if S.room then
      S.room.deadlines = S.room.deadlines or {}
      S.room.deadlines[msg.kind] = msg.at
      emit("room", S.room)
    end
  elseif kind == "tour_closed" then
    local tour = msg.tour or (S.tournament and S.tournament.tour) or nil
    local text = Protocol2.tourClosedText(msg)
    clearRoom()
    clearTournament()
    if S.pending and not S.pending.done then
      S.pending.error = text
      S.pending.reason = msg.reason
      S.pending.done = true
    end
    emit("room", nil)
    emit("tournament", nil)
    emit("error", { scope = "tournament", reason = msg.reason, tour = tour,
                    text = text })
  elseif kind == "tour_over" then
    if S.tournament and S.tournament.tour == msg.tour then
      S.tournament.stage = "finished"
      S.tournament.champion = msg.championId or S.tournament.champion
      S.tournament.championName = msg.champion
      emit("tournament", S.tournament)
    end
    S.tourMatch = nil
    emit("tour_over", { tour = msg.tour, champion = msg.champion,
                        championId = msg.championId })
  elseif kind == "invite_token" then
    emit("invite_token", msg)
  elseif kind == "invite_sent" then
    local handle = findOutgoing({ to = msg.to, activity = msg.activity })
    if handle then
      handle.id = msg.id
      handle.state = "sent"
      handle.expiresAt = msg.expiresAt
    end
    emit("invite_sent", msg)
  elseif kind == "invite_in" then
    dropInvite(msg.id)
    S.invites[#S.invites + 1] = msg
    emit("invite_in", msg)
  elseif kind == "invite_closed" then
    if msg.id then dropInvite(msg.id) end
    local handle = findOutgoing(msg)
    if handle then closeOutgoing(handle, msg) end
    emit("invite_closed", msg)
  elseif kind == "plaza_state" then
    S.plaza = { kind = msg.kind, instance = msg.instance, you = msg.you,
                cap = msg.cap, rev = msg.rev, members = sortMembers(msg.members) }
    emit("plaza", S.plaza)
  elseif kind == "plaza_delta" then
    if applyPlazaDelta(msg) then emit("plaza", S.plaza) end
  elseif kind == "plaza_counts" then
    S.plazaCounts = msg
    emit("plaza_counts", msg)
  elseif kind == "group_state" then
    S.group = msg
    emit("group", msg)
  elseif kind == "group_request" then
    emit("group_request", msg)
  elseif kind == "group_list" then
    S.groupLists[msg.activity or ""] = msg.groups
    emit("group_list", msg)
  elseif kind == "group_closed" then
    local me = S.you and S.you.id
    if S.group and S.group.leader == msg.leader then S.group = nil end
    if me and msg.leader == me then S.groupOpen = nil end
    emit("group_closed", msg)
  elseif kind == "direct_state" then
    S.direct = msg
    if msg.queued ~= true and msg.hosting == nil then S.directQueue = nil end
    emit("direct", msg)
  elseif kind == "direct_list" then
    S.directLists[msg.activity or ""] = msg.entries
    emit("direct_list", msg)
  elseif kind == "join_error" then
    local text = Protocol2.joinErrorText(msg, Client.serverTime())
    if S.resuming then
      S.resuming = false
      S.sessionId = nil
      clearRoom()
      sendRaw(helloMessage())
      return
    end
    if S.pending and not S.pending.done then
      S.pending.error = text
      S.pending.reason = msg.reason
      S.pending.field = msg.field
      S.pending.triesLeft = msg.triesLeft
      S.pending.retryAt = msg.retryAt
      S.pending.done = true
    end
    emit("error", { scope = "join", reason = msg.reason, field = msg.field,
                    detail = msg.detail, triesLeft = msg.triesLeft,
                    retryAt = msg.retryAt, text = text })
  end
end

-- ---------------------------------------------------------------- connection

local function bind()
  local transport, err = openTransport()
  if not transport then return false, err end
  S.net = transport
  S.session = Session.new(transport, { role = "client", kind = "lobby" })
  return true
end

helloMessage = function()
  local opts = S.opts or {}
  return Protocol2.lobbyHello({
    ticket = opts.ticket,
    name = opts.name,
    engineVersion = S.engineVersion,
    platform = S.platform,
    profiles = opts.profiles,
    presence = S.presence,
  })
end

local function scheduleRetry()
  S.attempt = S.attempt + 1
  local wait = BACKOFF[math.min(S.attempt, #BACKOFF)]
  S.retryAt = now() + wait
end

local function onDisconnected(detail)
  S.session = nil
  S.net = nil
  if S.upgrade then
    setState("error")
  elseif S.sessionId and S.opts and S.attempt < MAX_ATTEMPTS then
    S.err = detail
    setState("reconnecting")
    scheduleRetry()
  else
    S.err = detail or S.err or "disconnected"
    setState("error")
  end
  refreshRoomSession()
end

local function tryReconnect()
  S.retryAt = nil
  local ok, err = bind()
  if not ok then
    if S.attempt >= MAX_ATTEMPTS then
      S.err = err
      setState("error")
      return
    end
    S.err = err
    scheduleRetry()
    return
  end
  S.resuming = true
  sendRaw(Protocol2.resume(S.sessionId, S.ack))
end

function Client.configure(opts)
  opts = opts or {}
  if opts.relayAddress ~= nil then S.relayAddress = opts.relayAddress end
  if opts.connect ~= nil then S.connectFn = opts.connect end
  if opts.platform ~= nil then S.platform = opts.platform end
  if opts.engineVersion ~= nil then S.engineVersion = opts.engineVersion end
  return S.relayAddress
end

function Client.setProfiles(list)
  S.opts = S.opts or {}
  S.opts.profiles = list or {}
  if S.status == "online" then sendRaw(Protocol2.setProfiles(S.opts.profiles)) end
  return S.opts.profiles
end

function Client.profiles()
  return (S.opts and S.opts.profiles) or {}
end

local PRESENCE_KEYS = { "where", "status", "version", "engine" }

local function mergePresence(fields)
  if type(fields) ~= "table" then return end
  S.presence = S.presence or {}
  for _, k in ipairs(PRESENCE_KEYS) do
    if fields[k] ~= nil then S.presence[k] = fields[k] end
  end
  if fields.board == false then
    S.presence.board = nil
  elseif type(fields.board) == "table" then
    S.presence.board = fields.board
  end
end

function Client.connect(opts)
  opts = opts or {}
  if S.session then Client.disconnect() end
  S.opts = { name = opts.name, ticket = opts.ticket,
             profiles = opts.profiles or {} }
  S.err = nil
  S.upgrade = nil
  S.sessionId = nil
  S.attempt = 0
  S.retryAt = nil
  S.welcomed = false
  mergePresence(opts.presence)
  setState("connecting")
  local ok, err = bind()
  if not ok then
    S.err = err
    setState("error")
    return false, err
  end
  sendRaw(helloMessage())
  return true
end

function Client.disconnect()
  if S.session then
    if S.room then sendLeave() end
    pcall(function() S.session:close() end)
  end
  S.session = nil
  S.net = nil
  S.sessionId = nil
  S.you = nil
  S.opts = nil
  S.lobby, S.lobbyById = {}, {}
  S.attempt = 0
  S.retryAt = nil
  S.resuming = false
  S.advertised = nil
  S.online = nil
  S.welcomed = false
  S.presence = nil
  S.plazaJoins = {}
  S.groupOpen, S.groupWatch = nil, nil
  S.directQueue, S.directWatch = nil, nil
  clearRoom()
  clearTournament()
  forgetPresenceState()
  setState("offline")
end

-- ---------------------------------------------------------------- pump

local function pump(dt)
  if S.status == "reconnecting" then
    if S.retryAt and now() >= S.retryAt then tryReconnect() end
  end
  local session = S.session
  if not session then return end
  session:update()
  local messages = session:poll()
  for i = 1, #messages do
    local msg, reason = Protocol2.validate(messages[i])
    if msg then
      handle(msg)
      if S.upgrade then return end
    else
      S.dropped = S.dropped + 1
      S.lastDrop = reason
    end
  end
  S.dropped = S.dropped + (session.dropped or 0)
  session.dropped = 0
  local t = Client.serverTime()
  if t then
    for i = #S.invites, 1, -1 do
      local at = S.invites[i].expiresAt
      if type(at) == "number" and at < t then table.remove(S.invites, i) end
    end
  end
  if session.closed then
    onDisconnected(session.error or "the relay closed the connection")
    return
  end
  local queued = S.pendingReport
  if queued and S.status == "online" then
    S.pendingReport = nil
    if S.match and queued.match == S.match then
      S.reportSent = queued.match
      sendRaw(queued.msg)
    end
  end
  refreshRoomSession()
end

function Client.update(dt)
  if S.status == "offline" then return end
  local ok, err = pcall(pump, dt or 0)
  if not ok then
    S.err = tostring(err)
    setState("error")
  end
end

-- ---------------------------------------------------------------- actions

function Client.advertise(intent, profile, note)
  S.advertised = { intent = intent, profile = profile, note = note }
  return sendRaw(Protocol2.advertise(intent, profile, note))
end

function Client.unadvertise()
  S.advertised = nil
  return sendRaw(Protocol2.unadvertise())
end

local function newPending(id, kind)
  S.pending = { id = id, room = nil, tournament = nil, error = nil,
                done = false, kind = kind or "room", at = now() }
  return S.pending
end

local function failPending(pending, reason)
  pending.reason = reason
  pending.error = Protocol2.joinErrorText({ reason = reason })
  pending.done = true
  emit("error", { scope = "join", reason = reason, text = pending.error })
  return pending
end

local function defaultProfile(engine)
  local profiles = S.opts and S.opts.profiles or {}
  if engine then
    for _, p in ipairs(profiles) do
      if p.engine == engine then return p end
    end
  end
  return profiles[1]
end

function Client.createRoom(opts)
  opts = opts or {}
  local pending = newPending(nil)
  local msg = {}
  for k, v in pairs(opts) do msg[k] = v end
  msg.profile = msg.profile or defaultProfile()
  sendRaw(Protocol2.roomCreate(msg))
  return pending
end

function Client.joinRoom(roomId, as, profile, pin)
  local id = Wire.roomId(roomId)
  local pending = newPending(id)
  if not id then return failPending(pending, "bad_room") end
  sendRaw(Protocol2.roomJoin(id, as, profile or defaultProfile(), pin))
  return pending
end

function Client.joinRoomByInvite(token, as, profile)
  local pending = newPending(nil)
  S.leftRoom = nil
  local invite = Wire.inviteToken(token)
  if not invite then return failPending(pending, "invite_expired") end
  sendRaw(Protocol2.roomJoin(nil, as, profile or defaultProfile(), nil, invite))
  return pending
end

function Client.inviteToken(roomId)
  local id = Wire.roomId(roomId or (S.room and S.room.room))
  if not id then return false end
  return sendRaw(Protocol2.inviteToken(id))
end

function Client.setPresence(fields)
  mergePresence(fields)
  if type(fields) ~= "table" then return false end
  return sendRaw(Protocol2.presence(fields))
end

function Client.setStatus(status)
  return Client.setPresence({ status = status })
end

function Client.invite(toId, activity, detail, profile)
  local handle = { to = Wire.playerId(toId), activity = activity, id = nil,
                   state = "sending", why = nil, room = nil }
  S.outgoing[#S.outgoing + 1] = handle
  local engine = Protocol2.ACTIVITY_RULESET[activity or ""] and 3 or nil
  local sent = handle.to ~= nil and sendRaw(Protocol2.invite(handle.to, activity,
    detail, profile or defaultProfile(engine)))
  if not sent then
    closeOutgoing(handle, { why = handle.to and "offline" or "self" })
  end
  return handle
end

function Client.replyInvite(id, accept)
  if not dropInvite(id) then return false end
  if accept == true then S.leftRoom = nil end
  return sendRaw(Protocol2.inviteReply(id, accept == true))
end

function Client.joinPlaza(kind, profile, avatar, cap)
  profile = profile or defaultProfile(3)
  if cap == nil and kind == "union" then cap = Protocol2.PLAZA_CAP end
  S.plazaJoins[kind] = { profile = profile, avatar = avatar, cap = cap }
  return sendRaw(Protocol2.plazaJoin(kind, profile, avatar, cap))
end

function Client.leavePlaza(kind)
  S.plazaJoins[kind] = nil
  if kind == "union" and S.plaza then
    S.plaza = nil
    emit("plaza", nil)
  elseif kind == "wireless" then
    S.plazaCounts = nil
  end
  return sendRaw(Protocol2.plazaLeave(kind))
end

function Client.openGroup(activity, profile, avatar)
  profile = profile or defaultProfile(3)
  S.groupOpen = { activity = activity, profile = profile, avatar = avatar }
  return sendRaw(Protocol2.groupOpen(activity, profile, avatar))
end

function Client.groupList(activity, profile)
  if activity == nil then
    S.groupWatch = nil
    return sendRaw(Protocol2.groupList(nil, nil))
  end
  profile = profile or defaultProfile(3)
  S.groupWatch = { activity = activity, profile = profile }
  return sendRaw(Protocol2.groupList(activity, profile))
end

function Client.joinGroup(leaderId, profile, avatar)
  return sendRaw(Protocol2.groupJoin(leaderId, profile or defaultProfile(3), avatar))
end

function Client.acceptGroup(fromId, ok)
  return sendRaw(Protocol2.groupAccept(fromId, ok == true))
end

function Client.startGroup()
  return sendRaw(Protocol2.groupStart())
end

function Client.leaveGroup()
  S.groupOpen = nil
  S.group = nil
  return sendRaw(Protocol2.groupLeave())
end

function Client.queueDirect(opts)
  opts = opts or {}
  local q = {}
  for k, v in pairs(opts) do q[k] = v end
  q.profile = q.profile or defaultProfile(3)
  S.directQueue = q
  return sendRaw(Protocol2.directQueue(q))
end

function Client.directList(activity, profile)
  if activity == nil then
    S.directWatch = nil
    return sendRaw(Protocol2.directList(nil, nil))
  end
  profile = profile or defaultProfile(3)
  S.directWatch = { activity = activity, profile = profile }
  return sendRaw(Protocol2.directList(activity, profile))
end

function Client.leaveDirect()
  S.directQueue = nil
  S.directWatch = nil
  return sendRaw(Protocol2.directLeave())
end

function Client.leaveRoom()
  local rs = S.roomSession
  if rs then
    rs:close()
    S.roomSession = nil
    return true
  end
  if not S.room then return false end
  sendLeave()
  clearRoom()
  return true
end

function Client.ready(packedParty, digest)
  return sendRaw(Protocol2.roomReady(packedParty, digest))
end

local function sendResult(msg)
  if not msg then return false end
  local match = S.match
  if S.session and S.status == "online" then
    if match then S.reportSent = match end
    return sendRaw(msg)
  end
  if match and S.reportSent ~= match then
    S.pendingReport = { match = match, msg = msg }
  end
  return false
end

function Client.report(result)
  if not Protocol2.RESULTS[result] then
    return sendResult(Protocol2.forfeit(S.match))
  end
  return sendResult(Protocol2.roomReport(S.match, result))
end

function Client.forfeit()
  return sendResult(Protocol2.forfeit(S.match))
end

function Client.kick(id)
  return sendRaw(Protocol2.roomKick(id))
end

function Client.closeRoom()
  if not S.room then return false end
  local ok = sendRaw(Protocol2.roomClose())
  return ok
end

function Client.createTournament(opts)
  opts = opts or {}
  local pending = newPending(nil, "tournament")
  sendRaw(Protocol2.tourCreate({
    profile = opts.profile or defaultProfile(),
    rule = opts.rule,
    playing = opts.playing,
    shotClock = opts.shotClock,
    maxSpectators = opts.maxSpectators,
    party = opts.party,
    partyDigest = opts.partyDigest,
    public = opts.public,
    note = opts.note,
  }))
  return pending
end

function Client.joinTournament(opts, as, packedParty, digest, profile)
  if type(opts) ~= "table" then
    local ref = opts
    opts = { as = as, party = packedParty, partyDigest = digest,
             profile = profile }
    if Wire.tourId(ref) then opts.tour = ref else opts.code = ref end
  end
  local tour = Wire.tourId(opts.tour)
  local code = Wire.code(opts.code)
  local pending = newPending(tour, "tournament")
  if not tour and not code then return failPending(pending, "bad_room") end
  sendRaw(Protocol2.tourJoin({
    tour = tour,
    code = not tour and code or nil,
    as = opts.as,
    profile = opts.profile or defaultProfile(),
    party = opts.party,
    partyDigest = opts.partyDigest,
  }))
  return pending
end

function Client.leaveTournament()
  if not S.tournament then return false end
  sendRaw(Protocol2.tourLeave())
  clearRoom()
  clearTournament()
  emit("room", nil)
  emit("tournament", nil)
  return true
end

function Client.startTournament()
  if not S.tournament then return false end
  return sendRaw(Protocol2.tourStart())
end

function Client.kickFromTournament(id)
  if not S.tournament then return false end
  return sendRaw(Protocol2.tourKick(id))
end

function Client.closeTournament()
  if not S.tournament then return false end
  return sendRaw(Protocol2.tourClose())
end

return Client

local Json = require("src.link.Json")

local FakeRelay = {}

local ROLES = { [0] = "host", [1] = "guest", [2] = "seat2", [3] = "seat3", [4] = "seat4" }

local function wire(msg)
  return Json.decode(Json.encode(msg))
end

local Room = {}
Room.__index = Room

local counter = 0

function FakeRelay.room(opts)
  opts = opts or {}
  counter = counter + 1
  local seats = tonumber(opts.seats) or 2
  local self = setmetatable({
    id = opts.id or string.format("r%016x", counter),
    seats = seats,
    intent = opts.intent or "battle",
    stage = opts.stage or "battling",
    seed = opts.seed or 12345,
    match = opts.match or (string.format("r%016x", counter) .. "-m1"),
    players = {},
    inbox = {},
    states = {},
    left = {},
    barrier = { n = 1, confirms = {} },
    log = {},
    seq = 0,
  }, Room)
  for seat = 0, seats - 1 do
    local name = opts.names and opts.names[seat + 1] or ("P" .. seat)
    self.players[#self.players + 1] = {
      id = string.format("%08x", 0x1000 + seat + counter * 16),
      name = name, seat = seat, online = true, ready = true,
    }
    self.inbox[seat] = {}
    self.states[seat] = "online"
  end
  return self
end

function Room:playerAt(seat)
  for _, p in ipairs(self.players) do
    if p.seat == seat then return p end
  end
  return nil
end

function Room:roomTable()
  local players = {}
  for i, p in ipairs(self.players) do
    players[i] = { id = p.id, name = p.name, seat = p.seat, online = p.online, ready = p.ready }
  end
  return {
    room = self.id, intent = self.intent, engine = 3, seats = self.seats,
    players = players, spectators = {}, stage = self.stage, seed = self.seed,
    match = self.match, origin = "invite", listed = false, locked = false,
  }
end

function Room:push(fromSeat, msg, relay)
  self.seq = self.seq + 1
  self.log[#self.log + 1] = { seq = self.seq, seat = fromSeat, msg = msg }
  for seat = 0, self.seats - 1 do
    if relay or seat ~= fromSeat then
      if not self.left[seat] then
        local copy = wire(msg)
        copy.seat = relay and -1 or fromSeat
        local box = self.inbox[seat]
        box[#box + 1] = copy
      end
    end
  end
end

function Room:relay(msg)
  self:push(-1, msg, true)
end

function Room:barrierConfirm(seat, digest)
  local b = self.barrier
  b.confirms[seat] = digest
  local d0, d1 = b.confirms[0], b.confirms[1]
  if d0 and d1 then
    local n = b.n
    self.barrier = { n = n + 1, confirms = {} }
    if d0 == d1 then
      self:relay({ type = "trade_commit", n = n, digests = { d0, d1 } })
    else
      self:relay({ type = "trade_abort", n = n, why = "digest" })
    end
  end
end

function Room:receive(seat, msg)
  if type(msg) ~= "table" or type(msg.type) ~= "string" then return end
  if msg.type == "trade_commit" or msg.type == "trade_abort" or msg.type == "game3_mg_leader" then
    return
  end
  local sent = wire(msg)
  if sent.type == "game3_trade_confirm" or sent.type == "trade_confirm" then
    self:push(seat, sent, false)
    self:barrierConfirm(seat, sent.digest)
    return
  end
  self:push(seat, sent, false)
end

function Room:drop(seat)
  for i = #self.players, 1, -1 do
    if self.players[i].seat == seat then table.remove(self.players, i) end
  end
  self.left[seat] = true
end

function Room:setOnline(seat, online)
  local p = self:playerAt(seat)
  if p then p.online = online and true or false end
end

function Room:setState(seat, state)
  self.states[seat] = state
end

function Room:client(seat)
  local room = self
  local C = {}
  C._seat = seat
  function C.state() return room.states[seat] end
  function C.error() return room.states[seat] == "error" and "relay error" or nil end
  function C.you()
    local p = room:playerAt(seat)
    return { id = p and p.id or string.format("%08x", 0xF000 + seat), name = p and p.name }
  end
  function C.room()
    if room.left[seat] then return nil end
    return room:roomTable()
  end
  function C.seat() return seat end
  function C.role() return ROLES[seat] end
  function C.match() return room.match end
  function C.roomSession() return room:session(seat) end
  return C
end

local Session = {}
Session.__index = Session

function Room:session(seat)
  self._sessions = self._sessions or {}
  local rs = self._sessions[seat]
  if rs and not rs.left then return rs end
  rs = setmetatable({
    paired = #self.players == self.seats, closed = false, error = nil, left = false,
    code = nil, target = self.id, _room = self, _seat = seat,
  }, Session)
  self._sessions[seat] = rs
  return rs
end

function Session:_refresh()
  local room = self._room
  self.paired = #room.players == room.seats
  if room.left[self._seat] then self.closed = true end
  local st = room.states[self._seat]
  if st == "error" or st == "offline" then self.closed = true end
end

function Session:update()
  self.updateCalls = (self.updateCalls or 0) + 1
end

function Session:send(msg)
  if self.closed or type(msg) ~= "table" then return end
  self.sent = (self.sent or 0) + 1
  self._room:receive(self._seat, msg)
end

function Session:poll()
  self:_refresh()
  local box = self._room.inbox[self._seat]
  self._room.inbox[self._seat] = {}
  return box
end

function Session:pollOne()
  local box = self._room.inbox[self._seat]
  return table.remove(box, 1)
end

function Session:take(messageType, predicate)
  local box = self._room.inbox[self._seat]
  for i, msg in ipairs(box) do
    if msg.type == messageType and (predicate == nil or predicate(msg) == true) then
      return table.remove(box, i)
    end
  end
  return nil
end

function Session:unread(messages)
  local box = self._room.inbox[self._seat]
  for i = #messages, 1, -1 do table.insert(box, 1, messages[i]) end
end

function Session:hasPending()
  return #self._room.inbox[self._seat] > 0
end

function Session:close()
  if self.left then return end
  self.left = true
  self.closed = true
  self.closeCalls = (self.closeCalls or 0) + 1
  self._room:drop(self._seat)
end

function Session:seat() return self._seat end
function Session:seats() return self._room.seats end
function Session:players() return self._room:roomTable().players end
function Session:role() return ROLES[self._seat] end
function Session:match() return self._room.match end
function Session:seed() return self._room.seed end
function Session:engine() return 3 end
function Session:peerOnline(seat)
  local p = self._room:playerAt(seat)
  return p ~= nil and p.online ~= false
end

function FakeRelay.transport(room, seat)
  local RelayTransport = require("src.core.game3.link.relay_transport")
  return RelayTransport.new(room:session(seat), { client = room:client(seat) })
end

function FakeRelay.links(opts)
  opts = opts or {}
  local Game3Link = require("src.link.Game3Link")
  local room = FakeRelay.room(opts)
  local links = {}
  for seat = 0, room.seats - 1 do
    links[seat + 1] = Game3Link.attach(FakeRelay.transport(room, seat), {
      game = opts.game, linkType = opts.linkType, timeout = opts.timeout,
      seat = seat, seats = room.seats,
    })
  end
  return room, links
end

function FakeRelay.pair(opts)
  local room, links = FakeRelay.links(opts)
  return links[1], links[2], room
end

function FakeRelay.client(opts)
  opts = opts or {}
  local C = {
    calls = {},
    handles = {},
    _state = opts.state or "offline",
    _error = nil,
    _profiles = {},
    _plaza = nil,
    _counts = nil,
    _invites = {},
    _groups = {},
    _group = nil,
    _direct = nil,
    _room = nil,
    _seat = nil,
    _you = { id = opts.id or "0000beef", name = opts.name or "RED" },
  }
  local function rec(name, ...)
    C.calls[#C.calls + 1] = { name = name, args = { ... } }
  end
  function C.count(name)
    local n = 0
    for _, c in ipairs(C.calls) do
      if c.name == name then n = n + 1 end
    end
    return n
  end
  function C.last(name)
    for i = #C.calls, 1, -1 do
      if C.calls[i].name == name then return C.calls[i].args end
    end
    return nil
  end
  function C.clear() C.calls = {} end
  function C.state() return C._state end
  function C.error() return C._error end
  function C.you() return C._you end
  function C.profiles() return C._profiles end
  function C.setProfiles(list)
    rec("setProfiles", list)
    C._profiles = list or {}
    return C._profiles
  end
  function C.setPresence(fields) rec("setPresence", fields) end
  function C.setStatus(status)
    rec("setStatus", status)
    C.status = status
  end
  function C.joinPlaza(kind, profile, avatar, cap) rec("joinPlaza", kind, profile, avatar, cap) end
  function C.leavePlaza(kind) rec("leavePlaza", kind) end
  function C.plaza() return C._plaza end
  function C.plazaCounts() return C._counts end
  function C.invite(to, activity, detail, profile)
    rec("invite", to, activity, detail, profile)
    local h = { to = to, activity = activity, state = "sending" }
    C.handles[#C.handles + 1] = h
    return h
  end
  function C.replyInvite(id, accept)
    rec("replyInvite", id, accept)
    for i = #C._invites, 1, -1 do
      if C._invites[i].id == id then table.remove(C._invites, i) end
    end
    return true
  end
  function C.invites() return C._invites end
  function C.queueDirect(o) rec("queueDirect", o) end
  function C.directList(activity, profile) rec("directList", activity, profile) end
  C._directEntries = {}
  C.pendings = {}
  function C.directEntries(activity) return C._directEntries[activity] or {} end
  function C.joinRoom(room, as, profile, pin)
    rec("joinRoom", room, as, profile, pin)
    local p = { id = room, done = false }
    C.pendings[#C.pendings + 1] = p
    return p
  end
  function C.leaveDirect() rec("leaveDirect") end
  function C.direct() return C._direct end
  function C.openGroup(activity, profile, avatar) rec("openGroup", activity, profile, avatar) end
  function C.groupList(activity, profile) rec("groupList", activity, profile) end
  function C.groups() return C._groups end
  function C.joinGroup(leader, profile, avatar) rec("joinGroup", leader, profile, avatar) end
  function C.acceptGroup(from, ok) rec("acceptGroup", from, ok) end
  function C.startGroup() rec("startGroup") end
  function C.leaveGroup() rec("leaveGroup") end
  function C.group() return C._group end
  function C.leaveRoom() rec("leaveRoom") end
  function C.bindRoom(room, seat)
    C._room = room
    C._seat = seat
  end
  function C.room()
    local room = C._room
    if not room or room.left[C._seat] then return nil end
    return room:roomTable()
  end
  function C.roomSession()
    if not C._room then return nil end
    return C._room:session(C._seat)
  end
  function C.seat() return C._seat end
  function C.role() return C._seat and ROLES[C._seat] or nil end
  function C.match() return C._room and C._room.match or nil end
  return C
end

function FakeRelay.avatars()
  local ok, src = pcall(function()
    return require("src.core.game3.dataset").cache():read("data/generated/gba/union_room/avatars.lua")
  end)
  if ok and type(src) == "string" then return assert(load(src, "@avatars.lua", "t", {}))() end
  return {
    gfx_ids = { male = { 41, 54, 39, 18, 19, 20, 25, 26 }, female = { 42, 58, 40, 22, 23, 24, 28, 29 } },
    leader_coords = { { 4, 6 }, { 13, 8 }, { 10, 6 }, { 1, 8 }, { 13, 4 }, { 7, 4 }, { 1, 4 }, { 7, 8 } },
    group_offsets = { { 0, 0 }, { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 1 } },
    member_facing = { 1, 3, 1, 4, 2 },
    opposite_facing = { 0, 2, 1, 4, 3 },
  }
end

return FakeRelay

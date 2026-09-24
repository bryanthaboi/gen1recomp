local RelayTransport = {}
RelayTransport.__index = RelayTransport

local SIDE_SEAT = { host = 0, guest = 1 }

local function defaultClient()
  local loaded = package.loaded["src.online.Client"]
  if loaded then return loaded end
  local ok, Client = pcall(require, "src.online.Client")
  return ok and Client or nil
end

local function roomIdOf(room)
  if type(room) ~= "table" then return nil end
  return room.room
end

local function call(obj, name, ...)
  local fn = obj and obj[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, obj, ...)
  if not ok then return nil end
  return a, b
end

local function copyPlayers(list)
  local out = {}
  for _, p in ipairs(type(list) == "table" and list or {}) do
    if type(p) == "table" then
      out[#out + 1] = { id = p.id, name = p.name, seat = tonumber(p.seat) }
    end
  end
  table.sort(out, function(a, b) return (a.seat or 99) < (b.seat or 99) end)
  return out
end

function RelayTransport.new(roomSession, opts)
  assert(type(roomSession) == "table", "RelayTransport.new requires a room session")
  opts = opts or {}
  local self = setmetatable({
    relay = true,
    paired = roomSession.paired == true,
    closed = false,
    error = nil,
    code = nil,
    target = roomSession.target,
    left = false,
    _rs = roomSession,
    _client = opts.client or defaultClient(),
    _closedByUs = false,
  }, RelayTransport)
  self._startPlayers = copyPlayers(self:players())
  self._mySeat = self:seat()
  self:update()
  return self
end

function RelayTransport:session()
  return self._rs
end

function RelayTransport:seat()
  local s = call(self._rs, "seat")
  if s ~= nil then return tonumber(s) end
  local C = self._client
  s = C and C.seat and C.seat()
  return tonumber(s)
end

function RelayTransport:seats()
  local n = call(self._rs, "seats")
  if n ~= nil then return tonumber(n) end
  local room = self:room()
  return tonumber(room and room.seats) or 2
end

function RelayTransport:players()
  local list = call(self._rs, "players")
  if type(list) == "table" then return list end
  local room = self:room()
  return room and room.players or {}
end

function RelayTransport:role()
  local r = call(self._rs, "role")
  if r ~= nil then return r end
  local C = self._client
  return C and C.role and C.role() or nil
end

function RelayTransport:match()
  local m = call(self._rs, "match")
  if m ~= nil then return m end
  local room = self:room()
  return room and room.match or nil
end

function RelayTransport:seed()
  local s = call(self._rs, "seed")
  if s ~= nil then return tonumber(s) end
  local room = self:room()
  return tonumber(room and room.seed)
end

function RelayTransport:peerOnline(seat)
  local v = call(self._rs, "peerOnline", seat)
  if v ~= nil then return v and true or false end
  for _, p in ipairs(self:players()) do
    if tonumber(p.seat) == tonumber(seat) then return p.online ~= false end
  end
  return false
end

function RelayTransport:room()
  local C = self._client
  return C and C.room and C.room() or nil
end

function RelayTransport:_seatGone()
  local present = {}
  for _, p in ipairs(self:players()) do
    if type(p) == "table" and p.id ~= nil then present[p.id] = true end
  end
  for _, p in ipairs(self._startPlayers) do
    if p.id ~= nil and p.seat ~= self._mySeat and not present[p.id] then return true end
  end
  return false
end

function RelayTransport:update()
  local rs = self._rs
  self.paired = rs.paired == true
  if self.closed then return end
  local C = self._client
  local state = C and C.state and C.state() or "offline"
  if state == "error" then
    self.error = (C.error and C.error()) or "error"
    self.closed = true
    return
  end
  if state == "offline" then
    self.closed = true
    return
  end
  local room = self:room()
  local id = roomIdOf(room)
  if id == nil or (self.target ~= nil and id ~= self.target) then
    self.closed = true
    return
  end
  if rs.closed == true or rs.left == true then
    self.closed = true
    return
  end
  if self:_seatGone() then self.closed = true end
end

local function tag(msg)
  if type(msg) ~= "table" then return msg end
  if msg.type == "spectate" and type(msg.msg) == "table" then
    local inner = msg.msg
    if inner.seat == nil then inner.seat = SIDE_SEAT[msg.side] or -1 end
    return inner
  end
  if msg.seat == nil then msg.seat = -1 end
  return msg
end

function RelayTransport:send(msg)
  if self.closed or type(msg) ~= "table" then return false end
  local out = {}
  for k, v in pairs(msg) do
    if k ~= "seat" then out[k] = v end
  end
  self._rs:send(out)
  return true
end

function RelayTransport:poll()
  local list = self._rs:poll() or {}
  local out = {}
  for i = 1, #list do out[#out + 1] = tag(list[i]) end
  return out
end

function RelayTransport:take(messageType, predicate)
  return tag(self._rs:take(messageType, predicate))
end

function RelayTransport:close()
  self._closedByUs = true
  self.closed = true
end

function RelayTransport:leave()
  self.closed = true
  if self.left then return false end
  self.left = true
  local rs = self._rs
  if rs.left then return false end
  pcall(rs.close, rs)
  return true
end

return RelayTransport

local Json = require("src.link.Json")
local Wire = require("src.link.Wire")

local Relay = {}
Relay.__index = Relay

local CONFIRMS = { trade_confirm = true, game3_trade_confirm = true }

function Relay.new(opts)
  opts = opts or {}
  return setmetatable({
    room = "r0123456789abcdef",
    seats = {},
    barrier = { n = 1, confirms = {} },
    commits = 0,
    aborts = 0,
    tamper = opts.tamper,
    rewrite = opts.rewrite,
    dropped = 0,
    log = {},
    ledger = {},
  }, Relay)
end

local function wire(msg)
  return Wire.sanitize(Json.decode(Json.encode(msg)))
end

function Relay:_push(seat, msg)
  local rs = self.seats[seat]
  if rs and not rs.left then rs.inbox[#rs.inbox + 1] = msg end
end

function Relay:_relayed(msg)
  msg.seat, msg.relay = -1, true
  self.log[#self.log + 1] = msg.type
  for seat = 0, 1 do self:_push(seat, wire(msg)) end
end

function Relay:_close(outcome)
  local b = self.barrier
  local digests = {}
  for seat = 0, 1 do
    if b.confirms[seat] ~= nil then digests[#digests + 1] = b.confirms[seat] end
  end
  self.ledger[#self.ledger + 1] = { room = self.room, n = b.n, outcome = outcome,
                                    digests = digests }
  self.barrier = { n = b.n + 1, confirms = {} }
end

function Relay:outcome(room, digest)
  for _, row in ipairs(self.ledger) do
    if row.room == room and row.outcome == "commit" then
      for _, d in ipairs(row.digests) do
        if d == digest then return "commit" end
      end
    end
  end
  if room == self.room then
    for _, d in pairs(self.barrier.confirms) do
      if d == digest then return "open" end
    end
  end
  return "abort"
end

function Relay:outcomeClient()
  local relay = self
  local client = { requests = {}, failNext = 0 }
  function client.send(_, method, path, _, opts)
    local params = opts and opts.params or {}
    client.requests[#client.requests + 1] = { method = method, path = path,
      room = params.room, digest = params.digest, noAuth = opts and opts.noAuth }
    return { room = params.room, digest = params.digest }
  end
  function client.poll(_, handle)
    if client.failNext > 0 then
      client.failNext = client.failNext - 1
      return { status = "error", err = "offline" }
    end
    return { status = "ok", code = 200,
             data = { outcome = relay:outcome(handle.room, handle.digest) } }
  end
  function client.release() end
  return client
end

function Relay:_barrier(from, digest)
  local b = self.barrier
  if b.confirms[from] ~= nil then
    self.dropped = self.dropped + 1
    return
  end
  if self.tamper then digest = self.tamper(from, digest) end
  b.confirms[from] = digest
  local d0, d1 = b.confirms[0], b.confirms[1]
  if d0 == nil or d1 == nil then return end
  if d0 == d1 then
    self.commits = self.commits + 1
    self:_relayed({ type = "trade_commit", n = b.n, digests = { d0, d1 } })
    self:_close("commit")
  else
    self.aborts = self.aborts + 1
    self:_relayed({ type = "trade_abort", n = b.n, why = "digest" })
    self:_close("abort")
  end
end

function Relay:timeout()
  local b = self.barrier
  if next(b.confirms) == nil then return false end
  self.aborts = self.aborts + 1
  self:_relayed({ type = "trade_abort", n = b.n, why = "timeout" })
  self:_close("abort")
  return true
end

function Relay:deliver(from, msg)
  local rs = self.seats[from]
  if not rs or rs.left then return end
  if CONFIRMS[msg.type] then
    return self:_barrier(from, msg.digest)
  end
  if self.rewrite then msg = self.rewrite(from, msg) or msg end
  local out = wire(msg)
  if not out then return end
  out.seat = from
  self:_push(1 - from, out)
end

function Relay:leave(seat)
  local rs = self.seats[seat]
  if not rs or rs.left then return end
  rs.left, rs.closed = true, true
  local other = self.seats[1 - seat]
  if other then other.paired = false end
  local b = self.barrier
  if next(b.confirms) ~= nil and b.confirms[seat] == nil then
    self.aborts = self.aborts + 1
    self:_relayed({ type = "trade_abort", n = b.n, why = "left" })
    self:_close("abort")
  end
end

function Relay:players()
  local out = {}
  for seat = 0, 1 do
    local rs = self.seats[seat]
    if rs and not rs.left then
      out[#out + 1] = { id = rs.id, name = rs.name, seat = seat, online = rs.online }
    end
  end
  return out
end

function Relay:join(seat, name)
  local relay = self
  local rs = { relay = self, n = seat, id = ("%08x"):format(seat + 1), name = name,
    inbox = {}, paired = true, closed = false, left = false, online = true,
    target = self.room, code = nil }
  function rs.seat() return rs.n end
  function rs.seats() return 2 end
  function rs.players() return relay:players() end
  function rs.role() return seat == 0 and "host" or "guest" end
  function rs.update() end
  function rs.send(_, msg)
    if rs.left or not rs.online then return false end
    relay:deliver(rs.n, msg)
    return true
  end
  function rs.poll()
    if not rs.online then return {} end
    local out = rs.inbox
    rs.inbox = {}
    return out
  end
  function rs.take(_, kind, pred)
    if not rs.online then return nil end
    for i, msg in ipairs(rs.inbox) do
      if msg.type == kind and (pred == nil or pred(msg)) then
        return table.remove(rs.inbox, i)
      end
    end
    return nil
  end
  function rs.close() relay:leave(rs.n) end
  rs.client = {
    state = function()
      if rs.left then return "offline" end
      return rs.online and "online" or "reconnecting"
    end,
    room = function()
      if rs.left then return nil end
      return { room = relay.room, players = relay:players(), seats = 2 }
    end,
    seat = function() return rs.n end,
    role = rs.role,
  }
  self.seats[seat] = rs
  return rs
end

function Relay:transport(rs)
  return require("src.core.game3.link.relay_transport").new(rs, { client = rs.client })
end

return Relay

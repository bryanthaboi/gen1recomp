-- Peer-to-peer link transport over lua-enet (bundled with LÖVE).
-- One player hosts (binds a UDP port); the other joins by address.
-- No external server: messages are JSON objects on ENet's
-- reliable-ordered channel 0.
--
-- Usage:
--   local net = Net.new()
--   net:host()                     -- or net:join("192.168.1.20:7777")
--   every frame: net:update(); msgs = net:poll()
--   net.address                    -- host: "ip:port" to tell the friend
--   net.paired                     -- true once both ends are connected
--   net:send({ type = "hello" })
--
-- Plain luajit (headless tests) has no enet; Net.available() reports
-- that, and Net.loopbackPair() returns two in-memory ends with the
-- same API so the protocol/battle logic stays testable offline.
--
-- A second backend, alongside the ENet one above, talks plain TCP to a
-- pokeserver relay instead of direct peer-to-peer: both sides dial out
-- to a public server (works through NAT with no hole-punching), the host
-- gets a 6-character room code instead of an IP, and the server forwards
-- messages between them. Same newline-delimited JSON on the wire, same
-- Net API (host/join/send/update/poll/.paired/.closed/.error) -- see
-- Net:hostOnline/Net:joinOnline below. LinkState/LinkBattle/Protocol don't
-- know or care which backend is in play.

local Json = require("src.link.Json")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local hasEnet, enet = pcall(require, "enet")
if not hasEnet then enet = nil end

local hasSocket, socket = pcall(require, "socket")
if not hasSocket then socket = nil end

local Net = {}
Net.__index = Net

Net.DEFAULT_PORT = 7777
Net.DEFAULT_RELAY_ADDRESS = "147.182.215.255:7778"

function Net.available()
  return enet ~= nil
end

function Net.defaultPort()
  return tonumber(os.getenv("POKEPORT_LINK_PORT") or "") or Net.DEFAULT_PORT
end

function Net.defaultRelayAddress()
  return os.getenv("POKEPORT_RELAY_ADDR") or Net.DEFAULT_RELAY_ADDRESS
end

-- monotonic-ish clock for the join timeout
local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.gettime then return socket.gettime() end
  return os.time()
end

-- best-effort LAN IP to show the host (no packet is sent: connecting a
-- UDP socket just picks the outbound interface)
function Net.lanIP()
  local ok, ip = pcall(function()
    local socket = require("socket")
    local udp = socket.udp()
    udp:setpeername("192.0.2.1", 9) -- TEST-NET-1, never routed
    local addr = udp:getsockname()
    udp:close()
    return addr
  end)
  if ok and ip and ip ~= "0.0.0.0" then return ip end
  return nil
end

function Net.new()
  return setmetatable({
    enetHost = nil, -- our enet host object (both ends have one)
    peer = nil,     -- the connected remote peer
    inbox = {},
    outbox = {},    -- messages queued before pairing completes (enet only)
    paired = false,
    address = nil,  -- host: "ip:port" the other player types in
    error = nil,
    closed = false,
    mode = nil,
    joinTimeout = 10,
    tcpSocket = nil, -- relay backend: the luasocket TCP connection
    rxBuf = "",      -- relay backend: bytes read but not yet a full line
    txBuf = "",      -- relay backend: bytes queued but not yet written
    code = nil,      -- relay backend, hosting: the room/tournament code
  }, Net)
end

-- two in-memory ends with the Net API, for tests / offline logic
function Net.loopbackPair()
  local function make()
    local n = Net.new()
    n.paired = true
    n.mode = "loopback"
    return n
  end
  local a, b = make(), make()
  a.peerEnd, b.peerEnd = b, a
  return a, b
end

function Net:host(port)
  if not enet then
    self.error = "link needs lua-enet (run the game with LOVE)"
    return false
  end
  port = tonumber(port) or Net.defaultPort()
  local ok, h, err = pcall(enet.host_create, ("*:%d"):format(port), 2, 1)
  if not ok or not h then
    self.error = ("can't open UDP port %d (%s)"):format(
      port, tostring(ok and err or h))
    return false
  end
  self.enetHost = h
  self.mode = "hosting"
  self.address = ("%s:%d"):format(Net.lanIP() or "?", port)
  return true
end

function Net:join(address)
  if not enet then
    self.error = "link needs lua-enet (run the game with LOVE)"
    return false
  end
  local host, port = address:match("^(.-):(%d+)$")
  host = host or address
  port = tonumber(port) or Net.defaultPort()
  local target = ("%s:%d"):format(host, port)
  local ok, h = pcall(enet.host_create) -- client: no bind address
  if not ok or not h then
    self.error = "can't create network socket"
    return false
  end
  local okc, peer = pcall(h.connect, h, target, 1)
  if not okc or not peer then
    pcall(function() h:destroy() end)
    self.error = ("bad address %s"):format(target)
    return false
  end
  self.enetHost = h
  self.peer = peer
  self.mode = "joining"
  self.target = target
  self.joinDeadline = now() + self.joinTimeout
  return true
end

-- opens a TCP connection to a pokeserver relay (blocking connect with a
-- short timeout -- this runs once, from a single explicit user action, not
-- from a per-frame poll, so blocking briefly is fine). Callers then send
-- whatever control message starts their session ({type="host"},
-- {type="join",...}, {type="host_tournament",...}, ...); every reply that
-- isn't one of the four generic ones below lands in the normal inbox for
-- the caller (LinkState, or Tournament.lua) to interpret.
function Net:connectTCP(addr)
  if not socket then
    self.error = "online play needs luasocket (bundled with LOVE)"
    return false
  end
  local host, port = addr:match("^(.-):(%d+)$")
  host = host or addr
  port = tonumber(port) or 7778
  local tcp = socket.tcp()
  tcp:settimeout(5)
  local ok, err = tcp:connect(host, port)
  if not ok then
    self.error = Strings("can't reach relay %s:%d\n(%s)", host, port, tostring(err))
    return false
  end
  tcp:settimeout(0)
  self.tcpSocket = tcp
  self.rxBuf = ""
  self.txBuf = ""
  return true
end

function Net:hostOnline(addr)
  if not self:connectTCP(addr or Net.defaultRelayAddress()) then return false end
  self.mode = "onlineHosting"
  self:send({ type = "host" })
  return true
end

function Net:joinOnline(addr, code)
  if not self:connectTCP(addr or Net.defaultRelayAddress()) then return false end
  self.mode = "onlineJoining"
  self.target = code
  self:send({ type = "join", code = code })
  return true
end

function Net:send(msg)
  if self.closed then return end
  if self.tcpSocket then
    self.txBuf = self.txBuf .. Json.encode(msg) .. "\n"
    return
  end
  if self.peerEnd then -- loopback: re-encode through json like the wire
    local decoded = Json.decode(Json.encode(msg))
    if decoded and not self.peerEnd.closed then
      table.insert(self.peerEnd.inbox, decoded)
    end
    return
  end
  if not self.paired or not self.peer then
    table.insert(self.outbox, msg) -- flushed when the connection opens
    return
  end
  local ok, err = pcall(function()
    return self.peer:send(Json.encode(msg), 0, "reliable")
  end)
  if not ok then
    self.error = "send failed: " .. tostring(err)
    self.closed = true
  end
end

-- one control message recognized on every relay connection, regardless of
-- what it's being used for (a 1v1 room or a tournament): "peer_gone" only
-- ever fires for a paired 1v1 room (tournaments signal disconnects through
-- bracket_update/tournament_over instead), so it's unambiguous here.
local function handleGenericRelayControl(self, msg)
  if msg.type == "hosted" then
    self.code = msg.code
    return true
  elseif msg.type == "paired" then
    self.paired = true
    return true
  elseif msg.type == "join_error" then
    self.error = Strings(({
      not_found = Strings.source("That code wasn't\nfound."),
      full = Strings.source("That game already\nhas two players."),
      expired = Strings.source("That code has\nexpired."),
    })[msg.reason] or "")
    if self.error == "" then
      self.error = Strings("Couldn't join:\n%s", tostring(msg.reason))
    end
    self.closed = true
    return true
  elseif msg.type == "peer_gone" then
    self.closed = true
    return true
  end
  return false
end

function Net:handleTCPLine(line)
  local msg = Json.decode(line)
  if not msg then
    Logger.warn("link: bad relay message %q", line:sub(1, 60))
    return
  end
  if not handleGenericRelayControl(self, msg) then
    table.insert(self.inbox, msg)
  end
end

-- pulls every complete "\n"-terminated line out of rxBuf (leaving a
-- trailing partial line, if any, for the next call to complete) and hands
-- each to handleTCPLine. Pure buffer manipulation, no socket -- factored
-- out of updateTCP so the framing logic is testable without a real
-- connection (see the relay-path tests in tests/run_link_tests.lua).
function Net:drainLines()
  while true do
    local nl = self.rxBuf:find("\n", 1, true)
    if not nl then break end
    local line = self.rxBuf:sub(1, nl - 1)
    self.rxBuf = self.rxBuf:sub(nl + 1)
    if #line > 0 then self:handleTCPLine(line) end
  end
end

-- non-blocking pump for the relay TCP backend: flush queued writes, drain
-- whatever's arrived into complete lines. Uses a byte-count receive
-- (rather than the "*l" pattern) because luasocket's "*l" doesn't let a
-- non-blocking caller recover the partial line across calls -- a
-- byte-count read hands back whatever's available via the third return
-- value on timeout, which we can buffer ourselves.
function Net:updateTCP()
  if self.closed then return end
  local sock = self.tcpSocket
  if #self.txBuf > 0 then
    local sent, err, lastByte = sock:send(self.txBuf)
    if sent then
      self.txBuf = ""
    elseif err == "timeout" then
      self.txBuf = self.txBuf:sub((lastByte or 0) + 1)
    else
      self.error = "send failed: " .. tostring(err)
      self.closed = true
      return
    end
  end
  while true do
    local data, err, partial = sock:receive(8192)
    local chunk = data or partial or ""
    if #chunk > 0 then self.rxBuf = self.rxBuf .. chunk end
    if err == "closed" then
      self.closed = true
      break
    elseif err and err ~= "timeout" then
      self.error = tostring(err)
      self.closed = true
      break
    end
    if not data then break end -- nothing more buffered this frame
  end
  self:drainLines()
end

-- pump enet events; decoded JSON messages are queued for poll()
function Net:update()
  if self.tcpSocket then
    self:updateTCP()
    return
  end
  if self.peerEnd then return end -- loopback needs no pumping
  if not self.enetHost or self.closed then return end
  while true do
    local ok, event = pcall(self.enetHost.service, self.enetHost, 0)
    if not ok then
      -- an unreachable join target surfaces as a service error
      -- (ICMP unreachable on the connected UDP socket)
      if self.mode == "joining" and not self.paired then
        self.error = Strings("no answer from\n%s", self.target or "the host")
      else
        self.error = tostring(event)
      end
      self.closed = true
      return
    end
    if not event then break end
    if event.type == "connect" then
      if self.mode == "hosting" and self.peer and self.peer ~= event.peer then
        pcall(function() event.peer:disconnect_now() end) -- room is taken
      else
        self.peer = event.peer
        self.paired = true
        local queued = self.outbox
        self.outbox = {}
        for _, msg in ipairs(queued) do self:send(msg) end
      end
    elseif event.type == "receive" then
      local msg = Json.decode(event.data)
      if msg then
        table.insert(self.inbox, msg)
      else
        Logger.warn("link: bad message %q", tostring(event.data):sub(1, 60))
      end
    elseif event.type == "disconnect" then
      if event.peer == self.peer then
        self.closed = true
        if not self.paired then
          self.error = self.error or
            Strings("no answer from\n%s", self.target or "the host")
        end
      end
    end
  end
  if self.mode == "joining" and not self.paired
     and self.joinDeadline and now() > self.joinDeadline then
    self.error = Strings("no answer from\n%s", self.target or "the host")
    self.closed = true
    pcall(function() self.peer:disconnect_now() end)
  end
end

function Net:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

function Net:close()
  if self.peerEnd then
    self.closed = true
    return
  end
  if self.tcpSocket then
    pcall(function() self.tcpSocket:close() end)
    self.tcpSocket = nil
    self.closed = true
    return
  end
  if self.enetHost then
    if self.peer and self.paired and not self.closed then
      -- graceful goodbye: disconnect_later delivers the queued
      -- reliables (e.g. the final confirm/bye) before disconnecting;
      -- disconnect_now would drop them on both ends.  Pump briefly
      -- until the handshake completes.
      pcall(function() self.peer:disconnect_later() end)
      local deadline = now() + 0.5
      while now() < deadline do
        local ok, event = pcall(self.enetHost.service, self.enetHost, 10)
        if not ok or (event and event.type == "disconnect") then break end
      end
    elseif self.peer then
      pcall(function() self.peer:disconnect_now() end)
    end
    pcall(function() self.enetHost:flush() end)
    pcall(function() self.enetHost:destroy() end)
    self.enetHost = nil
    self.peer = nil
  end
  self.closed = true
end

return Net

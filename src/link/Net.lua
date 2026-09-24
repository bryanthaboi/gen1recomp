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
-- pokeserver relay instead of direct peer-to-peer: the online Client
-- dials out to a public server (works through NAT with no hole-punching)
-- over Net:connectTCP. Same newline-delimited JSON on the wire, same
-- Net API (send/update/poll/.closed/.error).

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
Net.DEFAULT_RELAY_ADDRESS = "relay.gen1re.com:7778"

Net.MAX_LINE = 256 * 1024
Net.MAX_RX_PER_FRAME = 512 * 1024
Net.ENET_BANDWIDTH = 256 * 1024

Net.CONNECT_TIMEOUT = 5
Net.PING_INTERVAL = 10
Net.PING_MISSES = 3
Net.CLOSE_FLUSH_TIMEOUT = 0.25
Net.CLOSE_FLUSH_ATTEMPTS = 256

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
    connecting = false, -- relay backend: TCP connect still in flight
    selectable = true,
    lastSendAt = nil,
    pendingPings = 0,
    sawPong = false,
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
  local ok, h, err = pcall(enet.host_create, ("*:%d"):format(port), 2, 1,
                           Net.ENET_BANDWIDTH, Net.ENET_BANDWIDTH)
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

-- opens a TCP connection to a pokeserver relay. The connect is
-- non-blocking: connectTCP returns true once the socket is dialing and
-- updateTCP polls writability until the 5 s deadline. Callers send
-- whatever control message starts their session ({type="lobby_hello"},
-- {type="resume",...}) straight away; it waits in txBuf until the
-- connection lands. Every reply that isn't one of the generic ones below
-- reaches the normal inbox for the online client to interpret.
local function connectPending(err)
  err = tostring(err or "")
  return err == "timeout" or err:find("in progress", 1, true) ~= nil
end

function Net:beginTCP(tcp, host, port, pending)
  self.tcpSocket = tcp
  self.connectHost, self.connectPort = host, port
  self.rxBuf = ""
  self.txBuf = ""
  self.connecting = pending and true or false
  self.connectDeadline = now() + Net.CONNECT_TIMEOUT
  self.lastSendAt = now()
  if not pending then self:applyKeepalive() end
end

function Net:applyKeepalive()
  pcall(function() self.tcpSocket:setoption("keepalive", true) end)
end

function Net:connectTCP(addr)
  if not socket then
    self.error = "online play needs luasocket (bundled with LOVE)"
    return false
  end
  local host, port = addr:match("^(.-):(%d+)$")
  host = host or addr
  port = tonumber(port) or 7778
  local tcp = socket.tcp()
  tcp:settimeout(0)
  local ok, err = tcp:connect(host, port)
  if ok then
    self:beginTCP(tcp, host, port, false)
    return true
  end
  if connectPending(err) then
    self:beginTCP(tcp, host, port, true)
    return true
  end
  pcall(function() tcp:close() end)
  local blocking = socket.tcp()
  blocking:settimeout(Net.CONNECT_TIMEOUT)
  local bok, berr = blocking:connect(host, port)
  if not bok then
    pcall(function() blocking:close() end)
    self.error = Strings("can't reach relay %s:%d\n(%s)", host, port, tostring(berr))
    return false
  end
  blocking:settimeout(0)
  self:beginTCP(blocking, host, port, false)
  return true
end

function Net:pollConnectTCP()
  local sock = self.tcpSocket
  local okSel, _, writable = pcall(socket.select, nil, { sock }, 0)
  if okSel and writable and #writable > 0 then
    local ok, err = sock:connect(self.connectHost, self.connectPort)
    err = tostring(err or "")
    if ok or err:find("already connected", 1, true) then
      self.connecting = false
      self:applyKeepalive()
      return true
    end
    if not connectPending(err) then
      self.error = Strings("can't reach relay %s:%d\n(%s)",
                           self.connectHost, self.connectPort, err)
      self.closed = true
      return false
    end
  end
  if now() > (self.connectDeadline or 0) then
    self.error = Strings("can't reach relay %s:%d\n(%s)",
                         self.connectHost, self.connectPort, "timeout")
    self.closed = true
  end
  return false
end

function Net:send(msg)
  if self.closed then return end
  if self.tcpSocket then
    self.txBuf = self.txBuf .. Json.encode(msg) .. "\n"
    self.lastSendAt = now()
    return
  end
  if self.peerEnd then -- loopback: re-encode through json like the wire
    local decoded = Json.decode(Json.encode(msg))
    if decoded ~= nil and not self.peerEnd.closed then
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

local function handleGenericRelayControl(self, msg)
  if msg.type == "ping" then
    self:send({ type = "pong", t = msg.t })
    return true
  elseif msg.type == "pong" then
    self.sawPong = true
    self.pendingPings = 0
    return true
  end
  return false
end

function Net:handleTCPLine(line)
  local msg = Json.decode(line, Net.MAX_LINE)
  if msg == nil then
    Logger.warn("link: bad relay message %q", line:sub(1, 60))
    return
  end
  if type(msg) == "table" and handleGenericRelayControl(self, msg) then return end
  table.insert(self.inbox, msg)
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
  if #self.rxBuf > Net.MAX_LINE then
    self.rxBuf = ""
    self.error = Strings("The other side\nsent bad data.")
    self.closed = true
  end
end

-- non-blocking pump for the relay TCP backend: flush queued writes, drain
-- whatever's arrived into complete lines. Uses a byte-count receive
-- (rather than the "*l" pattern) because luasocket's "*l" doesn't let a
-- non-blocking caller recover the partial line across calls -- a
-- byte-count read hands back whatever's available via the third return
-- value on timeout, which we can buffer ourselves.
function Net:heartbeatTCP()
  local t = now()
  if not self.lastSendAt then self.lastSendAt = t end
  if t - self.lastSendAt < Net.PING_INTERVAL then return end
  self:send({ type = "ping", t = math.floor(t * 1000) })
  self.pendingPings = (self.pendingPings or 0) + 1
  if self.sawPong and self.pendingPings >= Net.PING_MISSES then
    self.error = Strings("The relay stopped\nanswering.")
    self.closed = true
  end
end

function Net:updateTCP()
  if self.closed then return end
  local sock = self.tcpSocket
  if self.connecting then
    if not self:pollConnectTCP() then return end
  end
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
  local budget = Net.MAX_RX_PER_FRAME
  while budget > 0 do
    local data, err, partial = sock:receive(8192)
    local chunk = data or partial or ""
    if #chunk > 0 then
      self.rxBuf = self.rxBuf .. chunk
      budget = budget - #chunk
    end
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
  if not self.closed then self:heartbeatTCP() end
end

function Net:flushTCP(seconds)
  local sock = self.tcpSocket
  if not sock or self.connecting then return end
  local deadline = now() + (seconds or Net.CLOSE_FLUSH_TIMEOUT)
  for _ = 1, Net.CLOSE_FLUSH_ATTEMPTS do
    if #self.txBuf == 0 then return end
    local sent, err, lastByte = sock:send(self.txBuf)
    if sent then
      self.txBuf = ""
      return
    elseif err == "timeout" then
      self.txBuf = self.txBuf:sub((lastByte or 0) + 1)
    else
      return
    end
    if #self.txBuf == 0 or now() >= deadline then return end
    if self.selectable and socket and socket.select then
      if not pcall(socket.select, nil, { sock }, 0.01) then
        self.selectable = false
      end
    end
  end
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
      local msg = Json.decode(event.data, Net.MAX_LINE)
      if msg ~= nil then
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
    pcall(function() self:flushTCP() end)
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

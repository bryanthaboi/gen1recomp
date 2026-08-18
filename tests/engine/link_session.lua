package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Net = require("src.link.Net")
local Json = require("src.link.Json")
local Session = require("src.link.Session")

local function sessionPair()
  local hostNet, guestNet = Net.loopbackPair()
  return Session.new(hostNet, { role = "host", kind = "link" }),
         Session.new(guestNet, { role = "guest", kind = "link" })
end

local function fakeTransport(options)
  options = options or {}
  local transport = {
    paired = options.paired ~= false,
    closed = false,
    error = nil,
    inbox = options.inbox or {},
    closeCount = 0,
  }
  function transport:update()
    if options.onUpdate then options.onUpdate(self) end
    if options.updateError then error(options.updateError) end
  end
  function transport:poll()
    if options.pollError then error(options.pollError) end
    local messages = self.inbox
    self.inbox = {}
    return messages
  end
  function transport:send(message)
    self.sent = message
    return true
  end
  function transport:close()
    self.closeCount = self.closeCount + 1
    self.closed = true
    if options.closeError then error(options.closeError) end
  end
  return transport
end

local function readFile(path)
  local handle = assert(io.open(path, "rb"))
  local body = handle:read("*a")
  handle:close()
  return body
end

do
  local host, guest = sessionPair()
  T.eq(host:getRole(), "host", "host role is assigned locally")
  T.eq(guest:getRole(), "guest", "guest role is assigned locally")
  T.eq(host:getKind(), "link", "session kind is retained")
  T.eq(host:getStatus(), "paired", "wrapped loopback starts paired")

  guest:send({
    type = "hello", name = "BLUE", role = "host", kind = "tournament",
  })
  host:update()
  local hello = host:take("hello")
  T.eq(hello.name, "BLUE", "send forwards the original payload")
  T.eq(hello.session, nil, "send adds no session envelope")
  T.eq(host:getRole(), "host", "peer payload cannot replace local role")
  T.eq(host:getKind(), "link", "peer payload cannot replace local kind")
end

do
  local host, guest = sessionPair()
  guest:send({ type = "before", sequence = 1 })
  guest:send({ type = "greeting", sequence = 2 })
  guest:send({ type = "after", sequence = 3 })
  guest:send({ type = "greeting", sequence = 4 })
  host:update()

  local hello = host:take("greeting")
  T.eq(hello.sequence, 2, "take removes the first matching packet")
  T.eq(host:pollOne().sequence, 1, "pollOne removes only the FIFO head")

  local rest = host:poll()
  T.eq(#rest, 2, "poll returns every remaining packet once")
  T.eq(rest[1].sequence, 3, "take preserves the earlier remainder order")
  T.eq(rest[2].sequence, 4, "take preserves repeated-type order")
  T.eq(#host:poll(), 0, "poll clears the private FIFO")
end

do
  local sent
  local transport = {
    paired = false,
    code = nil,
    address = "192.0.2.5:7777",
    target = "ROOM01",
    update = function(self)
      self.paired = true
      self.code = "ROOM02"
    end,
    poll = function() return {} end,
    send = function(_, message)
      sent = message
      return "queued", 7
    end,
    close = function(self) self.closed = true end,
  }
  local session = Session.new(transport, { role = "guest", kind = "tournament" })
  T.eq(session:getStatus(), "connecting", "unpaired transport starts connecting")
  T.eq(session.address, "192.0.2.5:7777", "address metadata is mirrored")
  T.eq(session.target, "ROOM01", "target metadata is mirrored")

  local outbound = { type = "ping" }
  local result, count = session:send(outbound)
  T.eq(result, "queued", "send preserves the transport's first return")
  T.eq(count, 7, "send preserves the transport's second return")
  T.eq(sent, outbound, "send forwards the original table unchanged")

  session:update()
  T.eq(session:getStatus(), "paired", "update observes transport pairing")
  T.eq(session.code, "ROOM02", "update refreshes relay metadata")
end

do
  local transport = fakeTransport({ onUpdate = function(self)
    self.inbox[#self.inbox + 1] = { type = "bye" }
    self.closed = true
  end })
  local session = Session.new(transport, { role = "host", kind = "link" })
  session:update()
  T.eq(session:getStatus(), "draining", "normal close drains its final packet")
  T.eq(session.closed, false, "compatibility closed waits for the FIFO")
  T.check(session:take("bye") ~= nil, "final close packet remains observable")
  T.eq(session:getStatus(), "closed", "normal drain reaches closed")
  T.eq(transport.closeCount, 1, "transport cleanup runs once")
end

do
  local transport = fakeTransport({
    onUpdate = function(self) self.closed = true end,
    closeError = "normal cleanup exploded",
  })
  local session = Session.new(transport, { role = "host", kind = "link" })
  T.check(pcall(session.update, session),
    "normal-close cleanup exception does not escape the game loop")
  local reason, detail = session:getFailure()
  T.eq(reason, "transport_error",
    "normal-close cleanup exception becomes a transport failure")
  T.check(detail:find("normal cleanup exploded", 1, true) ~= nil,
    "normal-close cleanup failure keeps its diagnostic detail")
  T.eq(session:getStatus(), "failed",
    "normal-close cleanup exception cannot report a clean close")
end

do
  local transport = fakeTransport({ onUpdate = function(self)
    self.inbox = { { type = "before", sequence = 1 } }
    self.error = "socket failed"
    self.closed = true
  end })
  local session = Session.new(transport, { role = "guest", kind = "link" })
  session:update()
  local reason, detail = session:getFailure()
  T.eq(reason, "transport_error", "transport failure has a stable reason")
  T.eq(detail, "socket failed", "transport failure retains original detail")
  T.eq(session:getStatus(), "draining", "transport failure drains valid prefix")
  T.eq(session.error, nil, "legacy error stays hidden during drain")
  T.eq(session.closed, false, "legacy closed stays false during failed drain")
  T.eq(session:pollOne().sequence, 1, "failed drain returns its valid prefix")
  T.eq(session:getStatus(), "failed", "failed drain reaches failed")
  T.eq(session.error, "socket failed", "legacy error appears at terminal failure")
  transport.error = "later error"
  session:update()
  local _, latchedDetail = session:getFailure()
  T.eq(latchedDetail, "socket failed", "first terminal failure stays latched")
end

do
  local transport = fakeTransport({ inbox = {
    { type = "before", sequence = 1 },
    false,
    { type = "after", sequence = 3 },
  } })
  local session = Session.new(transport, { role = "host", kind = "link" })
  session:update()
  T.eq(session:getFailure(), nil, "a malformed packet is not a terminal failure")
  T.eq(session:getStatus(), "paired", "the session stays usable after a bad packet")
  local messages = session:poll()
  T.eq(#messages, 2, "the malformed value is dropped, the rest is delivered")
  T.eq(messages[1].sequence, 1, "packets before the malformed one survive")
  T.eq(messages[2].sequence, 3, "packets after the malformed one survive")
  T.eq(session.dropped, 1, "the drop is counted")
end

do
  local transport = fakeTransport({ inbox = { { type = 7 } } })
  local session = Session.new(transport, { role = "host", kind = "link" })
  session:update()
  T.eq(session:getFailure(), nil,
    "a table without a string type is dropped, not a terminal failure")
  T.eq(#session:poll(), 0, "...and never reaches the mode")
end

do
  local transport = fakeTransport({
    inbox = { { type = "future_world_packet", value = 9 } },
  })
  local session = Session.new(transport, { role = "host", kind = "link" })
  session:update()
  T.eq(session:pollOne().value, 9, "unknown typed packet stays mode-owned")
end

do
  local transport = fakeTransport({
    inbox = { { type = "already_decoded", value = 4 } },
    updateError = "update exploded",
  })
  local session = Session.new(transport, { role = "host", kind = "link" })
  local ok = pcall(session.update, session)
  T.check(ok, "transport update exception does not escape the game loop")
  T.eq(session:getStatus(), "draining", "update exception still drains prior inbox")
  T.eq(session:pollOne().value, 4, "decoded packet survives update exception")
  T.eq(session:getStatus(), "failed", "update exception becomes terminal failure")
end

do
  local transport = fakeTransport({ pollError = "poll exploded" })
  local session = Session.new(transport, { role = "host", kind = "link" })
  T.check(pcall(session.update, session),
    "transport poll exception does not escape the game loop")
  local reason, detail = session:getFailure()
  T.eq(reason, "transport_error", "poll exception is a transport failure")
  T.check(detail:find("poll exploded", 1, true) ~= nil,
    "poll exception keeps its diagnostic detail")
end

do
  local transport = fakeTransport({ closeError = "close exploded" })
  local session = Session.new(transport, { role = "guest", kind = "link" })
  T.check(pcall(session.close, session),
    "transport close exception does not escape cleanup")
  T.eq(session:getFailure(), "transport_error",
    "close exception is a transport failure")
  session:close()
  T.eq(transport.closeCount, 1, "failed close is still attempted only once")
end

do
  local transport = fakeTransport()
  local session = Session.new(transport, { role = "guest", kind = "link" })
  session:close()
  session:close()
  session:update()
  T.eq(transport.closeCount, 1, "close and post-terminal update are idempotent")
  T.eq(session:getStatus(), "closed", "explicit close reaches closed")
end

do
  T.check(not pcall(Session.new, nil, { role = "host", kind = "link" }),
    "constructor rejects missing transport")
  local transport = fakeTransport()
  T.check(not pcall(Session.new, transport, { role = "leader", kind = "link" }),
    "constructor rejects unsupported role")
  T.check(not pcall(Session.new, transport, { role = "host", kind = "" }),
    "constructor rejects empty kind")
end

do
  local senderNet, receiverNet = Net.loopbackPair()
  local receiver = Session.new(receiverNet, { role = "guest", kind = "link" })
  senderNet:send(false)
  receiver:update()
  T.eq(receiver:getFailure(), nil,
    "a decoded scalar off the loopback is dropped, not fatal")
  T.eq(#receiver:poll(), 0, "...and never reaches the mode")
end

do
  local delivered = false
  local transport = Net.new()
  transport.enetHost = {
    service = function()
      if delivered then return nil end
      delivered = true
      return { type = "receive", data = "false" }
    end,
  }
  local session = Session.new(transport, { role = "guest", kind = "link" })
  session:update()
  T.eq(session:getFailure(), nil,
    "a decoded scalar off ENet is dropped, not fatal")
  T.eq(#session:poll(), 0, "...and never reaches the mode")
end

do
  local transport = Net.new()
  local session = Session.new(transport, { role = "host", kind = "tournament" })
  T.check(pcall(transport.handleTCPLine, transport, "42"),
    "TCP control handoff does not index a decoded scalar")
  session:update()
  T.eq(session:getFailure(), nil,
    "a decoded TCP scalar is dropped, not fatal")
  T.eq(#session:poll(), 0, "...and never reaches the mode")
end

do
  local transport = Net.new()
  transport:handleTCPLine(Json.encode({ type = "hosted", code = "ABCDEF" }))
  T.eq(transport.code, "ABCDEF", "valid relay controls stay transport-owned")
  transport:handleTCPLine(Json.encode({ type = "hello", name = "RED" }))
  T.eq(transport:poll()[1].name, "RED", "valid application packet stays intact")
end

do
  local source = readFile("src/link/LinkState.lua")
  T.check(source:find('require("src.link.Session")', 1, true) ~= nil,
    "LinkState depends on the session boundary")
  T.check(source:find('kind = "link"', 1, true) ~= nil,
    "LinkState assigns the link session kind locally")
  T.check(source:find("self.net.inbox", 1, true) == nil,
    "LinkState never mutates a transport inbox")
  T.check(source:find("self.net = Net.new()", 1, true) == nil,
    "LinkState stores only successful session wrappers")
  T.check(source:find(':take("hello")', 1, true) ~= nil,
    "LinkState retrieves hello without draining unrelated packets")
  T.check(source:find(':take("party")', 1, true) ~= nil,
    "LinkState leaves battle handoff packets in session order")
  T.check(source:find("getStatus()", 1, true) ~= nil,
    "LinkState uses the session lifecycle instead of raw terminal flags")
end

do
  local source = readFile("src/link/Tournament.lua")
  T.check(source:find('require("src.link.Session")', 1, true) ~= nil,
    "Tournament depends on the session boundary")
  T.check(source:find('kind = "tournament"', 1, true) ~= nil,
    "Tournament assigns its connection role and kind locally")
  T.check(source:find("self.net.inbox", 1, true) == nil,
    "Tournament never mutates a transport inbox")
  T.check(source:find("self.net = Net.new()", 1, true) == nil,
    "Tournament stores only a successful session wrapper")
  T.check(source:find(':take("hello")', 1, true) ~= nil,
    "Tournament retrieves match hello without draining its tail")
  T.check(source:find(":pollOne()", 1, true) ~= nil,
    "Tournament processes handoff prefixes one packet at a time")
  T.check(source:find("getStatus()", 1, true) ~= nil,
    "Tournament uses the session lifecycle instead of raw terminal flags")
end

T.finish("link_session")

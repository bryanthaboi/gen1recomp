local Handshake = require("src.link.Handshake")
local Session = require("src.link.Session")
local Versions = require("src.import.gba.versions")

local Game3Link = {}
Game3Link.__index = Game3Link

-- pokefirered/include/link.h:88
Game3Link.LINKTYPE = {
  TRADE = 0x1111,
  TRADE_CONNECTING = 0x1122,
  TRADE_SETUP = 0x1133,
  TRADE_DISCONNECTED = 0x1144,
  BATTLE = 0x2211,
  SINGLE_BATTLE = 0x2233,
  DOUBLE_BATTLE = 0x2244,
  MULTI_BATTLE = 0x2255,
  RECORD_MIX_BEFORE = 0x3311,
  RECORD_MIX_AFTER = 0x3322,
}

Game3Link.GENERATION = 3
Game3Link.HANDSHAKE_SECONDS = 10
Game3Link.BYE = "game3_bye"
Game3Link.HELLO = "game3_hello"
Game3Link.SEAT_ROLES = { [0] = "host", [1] = "guest", [2] = "seat2", [3] = "seat3", [4] = "seat4" }

-- pokefirered/src/link.c:343 InitLocalLinkPlayer
local function localPlayer(game)
  local rt = package.loaded["src.core.game3.runtime"]
  local s = rt and rt.getSession and rt.getSession()
  local name = s and (s.name or s.playerName)
  if type(name) ~= "string" or name == "" then
    name = game and game.save and game.save.player and game.save.player.name or nil
  end
  return name, tonumber(s and (s.trainerId or s.id)) or 0,
    (s and (s.gender == "female" or s.gender == 1)) and 1 or 0
end

local function handshakeView(game)
  if type(game) ~= "table" then return nil end
  return { data = game.data, save = game.save, mods = game.mods }
end

local function helloFor(game, linkType, player)
  local hello = Handshake.hello(handshakeView(game), nil)
  hello.generation = Game3Link.GENERATION
  hello.type = Game3Link.HELLO
  hello.ruleset = Handshake.DEFAULT_RULESET
  local name, trainerId, gender = localPlayer(game)
  if type(player) == "table" then
    if player.name ~= nil then name = player.name end
    if player.trainerId ~= nil then trainerId = tonumber(player.trainerId) or 0 end
    if player.gender ~= nil then gender = (player.gender == 1 or player.gender == "female") and 1 or 0 end
  end
  hello.name = name
  hello.game3 = {
    cacheVersion = Versions.CACHE_VERSION,
    nativeVersion = Versions.NATIVE_VERSION,
    linkType = tonumber(linkType),
    trainerId = trainerId,
    gender = gender,
  }
  return hello
end

Game3Link.hello = helloFor

local function transportSeat(transport)
  if type(transport) == "table" and type(transport.seat) == "function" then
    local ok, s = pcall(transport.seat, transport)
    if ok then return tonumber(s) end
  end
  return nil
end

local function transportSeats(transport)
  if type(transport) == "table" and type(transport.seats) == "function" then
    local ok, n = pcall(transport.seats, transport)
    if ok then return tonumber(n) end
  end
  return nil
end

function Game3Link.attach(transport, opts)
  opts = opts or {}
  local seat = tonumber(opts.seat) or transportSeat(transport)
  if seat == nil then seat = opts.role == "guest" and 1 or 0 end
  local seats = tonumber(opts.seats) or transportSeats(transport) or 2
  local role = seat == 0 and "host" or "guest"
  local self = setmetatable({
    role = role,
    seat = seat,
    nseats = seats,
    linkType = tonumber(opts.linkType) or Game3Link.LINKTYPE.BATTLE,
    game = opts.game,
    state = "handshake",
    elapsed = 0,
    closed = false,
    onReady = opts.onReady,
    onClosed = opts.onClosed,
    timeout = tonumber(opts.timeout) or Game3Link.HANDSHAKE_SECONDS,
    peerHellos = {},
    peerHello = nil,
    _transport = transport,
    _session = Session.new(transport, { role = role, kind = "game3" }),
  }, Game3Link)
  local hello = opts.hello
  if type(hello) == "table" then
    local copy = {}
    for k, v in pairs(hello) do copy[k] = v end
    copy.game3 = {}
    for k, v in pairs(type(hello.game3) == "table" and hello.game3 or {}) do copy.game3[k] = v end
    hello = copy
  else
    hello = helloFor(opts.game, self.linkType)
  end
  hello.type = Game3Link.HELLO
  hello.generation = Game3Link.GENERATION
  hello.game3 = hello.game3 or {}
  hello.game3.seat = seat
  if hello.game3.linkType == nil then hello.game3.linkType = self.linkType end
  self.myHello = hello
  self._session:send(self.myHello)
  return self
end

function Game3Link.loopback(opts)
  opts = opts or {}
  local Net = require("src.link.Net")
  local a, b = Net.loopbackPair()
  local host = Game3Link.attach(a, {
    seat = 0, seats = 2, game = opts.game, linkType = opts.linkType,
    timeout = opts.timeout, onReady = opts.onHostReady, onClosed = opts.onHostClosed,
  })
  local guest = Game3Link.attach(b, {
    seat = 1, seats = 2, game = opts.game, linkType = opts.linkType,
    timeout = opts.timeout, onReady = opts.onGuestReady, onClosed = opts.onGuestClosed,
  })
  return host, guest
end

function Game3Link:isOpen()
  return not self.closed
end

function Game3Link:isReady()
  return self.state == "ready" and not self.closed
end

function Game3Link:getStatus()
  return self.state
end

function Game3Link:getSeat()
  return self.seat
end

function Game3Link:seatCount()
  return self.nseats
end

function Game3Link:peerName()
  return self.peerHello and self.peerHello.name or nil
end

function Game3Link:peerLinkType()
  local g3 = self.peerHello and self.peerHello.game3
  return g3 and tonumber(g3.linkType) or nil
end

local function row(hello, seat, isLocal)
  local g3 = type(hello) == "table" and type(hello.game3) == "table" and hello.game3 or {}
  return {
    name = hello and hello.name,
    trainerId = tonumber(g3.trainerId) or 0,
    gender = tonumber(g3.gender) or 0,
    role = Game3Link.SEAT_ROLES[seat] or "guest",
    seat = seat,
    isLocal = isLocal,
  }
end

-- pokefirered/src/link.c:1069 GetLinkPlayerCount_2
function Game3Link:players()
  local list = { row(self.myHello, self.seat, true) }
  for seat, hello in pairs(self.peerHellos) do
    list[#list + 1] = row(hello, seat, false)
  end
  table.sort(list, function(a, b) return a.seat < b.seat end)
  return list
end

function Game3Link:send(message)
  if self.closed or type(message) ~= "table" then return false end
  self._session:send(message)
  return true
end

function Game3Link:take(messageType, predicate)
  return self._session:take(messageType, predicate)
end

function Game3Link:poll()
  return self._session:poll()
end

function Game3Link:peerGone()
  local t = self._transport
  if not t then return true end
  if t.closed == true or t.error then return true end
  if t.peerEnd and t.peerEnd.closed == true then return true end
  local status = self._session:getStatus()
  return status == "closed" or status == "failed"
end

function Game3Link:_finish(state, reason)
  if self.closed then return false end
  self.closed = true
  self.state = state
  self.reason = reason
  self._session:close()
  local cb = self.onClosed
  if cb then cb(reason, state) end
  return true
end

-- pokefirered/src/link.c:419 CloseLink
function Game3Link:close(reason)
  if self.closed then return false end
  pcall(function()
    self._session:send({ type = Game3Link.BYE, reason = tostring(reason or "bye") })
  end)
  return self:_finish("closed", reason or "close_link")
end

function Game3Link:leave()
  local t = self._transport
  if type(t) == "table" and type(t.leave) == "function" then
    pcall(t.leave, t)
    return true
  end
  return false
end

local function decideOne(myHello, peer)
  local g3 = peer and peer.game3
  if type(g3) ~= "table" then
    return "refused", "peer_is_not_firered"
  end
  local verdict, reason = Handshake.checkCompat(myHello, peer)
  if verdict ~= "full" then
    return "refused", reason or verdict
  end
  if tonumber(g3.cacheVersion) ~= Versions.CACHE_VERSION then
    return "refused", "cache_version_mismatch"
  end
  if tonumber(g3.nativeVersion) ~= Versions.NATIVE_VERSION then
    return "refused", "native_version_mismatch"
  end
  return "full", nil
end

function Game3Link:decide()
  if next(self.peerHellos) == nil then
    return decideOne(self.myHello, self.peerHello)
  end
  local seats = {}
  for seat in pairs(self.peerHellos) do seats[#seats + 1] = seat end
  table.sort(seats)
  for _, seat in ipairs(seats) do
    local verdict, reason = decideOne(self.myHello, self.peerHellos[seat])
    if verdict ~= "full" then return verdict, reason end
  end
  return "full", nil
end

function Game3Link:_helloSeat(hello)
  local s = tonumber(hello.seat)
  if s == nil or s < 0 then
    local g3 = type(hello.game3) == "table" and hello.game3 or {}
    s = tonumber(g3.seat)
  end
  if s == nil or s < 0 or s == self.seat then
    if self.nseats <= 2 then return 1 - (self.seat == 1 and 1 or 0) end
    return nil
  end
  return s
end

function Game3Link:_allHellos()
  local n = 0
  for _ in pairs(self.peerHellos) do n = n + 1 end
  return n >= self.nseats - 1
end

function Game3Link:_primaryHello()
  if self.seat ~= 0 and self.peerHellos[0] then return self.peerHellos[0] end
  local best
  for seat, hello in pairs(self.peerHellos) do
    if best == nil or seat < best then best = seat end
  end
  return best ~= nil and self.peerHellos[best] or nil
end

function Game3Link:update(dt)
  if self.closed then return self.state end
  self.elapsed = self.elapsed + (tonumber(dt) or 0)
  self._session:update()

  if self._session:take(Game3Link.BYE) then
    self:_finish("closed", "peer_left")
    return self.state
  end

  if self.state == "handshake" then
    local hello = self._session:take(Game3Link.HELLO) or self._session:take("hello")
    while hello do
      local seat = self:_helloSeat(hello)
      if seat ~= nil then self.peerHellos[seat] = hello end
      hello = self._session:take(Game3Link.HELLO)
    end
    self.peerHello = self:_primaryHello()
    if self.peerHello and self:_allHellos() then
      local verdict, reason = self:decide()
      self.verdict = verdict
      if verdict == "full" then
        self.state = "ready"
        local cb = self.onReady
        if cb then cb(self) end
      else
        self:close(reason or "refused")
        return self.state
      end
    end
  end

  if self:peerGone() then
    self:_finish("failed", self.peerHello and "peer_dropped" or "no_peer")
    return self.state
  end

  if self.state == "handshake" and self.timeout > 0 and self.elapsed >= self.timeout then
    self:_finish("failed", "handshake_timeout")
  end
  return self.state
end

return Game3Link

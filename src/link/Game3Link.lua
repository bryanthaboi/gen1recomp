local Handshake = require("src.link.Handshake")
local Net = require("src.link.Net")
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

local function helloFor(game, linkType)
  local hello = Handshake.hello(game, nil)
  hello.generation = Game3Link.GENERATION
  hello.type = Game3Link.HELLO
  local name, trainerId, gender = localPlayer(game)
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

function Game3Link.attach(transport, opts)
  opts = opts or {}
  local role = opts.role == "guest" and "guest" or "host"
  local self = setmetatable({
    role = role,
    linkType = tonumber(opts.linkType) or Game3Link.LINKTYPE.BATTLE,
    game = opts.game,
    state = "handshake",
    elapsed = 0,
    closed = false,
    onReady = opts.onReady,
    onClosed = opts.onClosed,
    timeout = tonumber(opts.timeout) or Game3Link.HANDSHAKE_SECONDS,
    _transport = transport,
    _session = Session.new(transport, { role = role, kind = "game3" }),
  }, Game3Link)
  self.myHello = helloFor(opts.game, self.linkType)
  self._session:send(self.myHello)
  return self
end

function Game3Link.loopback(opts)
  opts = opts or {}
  local a, b = Net.loopbackPair()
  local host = Game3Link.attach(a, {
    role = "host", game = opts.game, linkType = opts.linkType,
    timeout = opts.timeout, onReady = opts.onHostReady, onClosed = opts.onHostClosed,
  })
  local guest = Game3Link.attach(b, {
    role = "guest", game = opts.game, linkType = opts.linkType,
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

function Game3Link:peerName()
  return self.peerHello and self.peerHello.name or nil
end

function Game3Link:peerLinkType()
  local g3 = self.peerHello and self.peerHello.game3
  return g3 and tonumber(g3.linkType) or nil
end

-- pokefirered/src/link.c:1069 GetLinkPlayerCount_2
function Game3Link:players()
  local mine = self.myHello and self.myHello.game3 or nil
  local list = { {
    name = self.myHello and self.myHello.name,
    trainerId = mine and mine.trainerId or 0,
    gender = mine and mine.gender or 0,
    role = self.role,
    isLocal = true,
  } }
  if self.peerHello then
    local theirs = self.peerHello.game3 or {}
    list[2] = {
      name = self.peerHello.name,
      trainerId = tonumber(theirs.trainerId) or 0,
      gender = tonumber(theirs.gender) or 0,
      role = self.role == "host" and "guest" or "host",
      isLocal = false,
    }
  end
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

function Game3Link:decide()
  local peer = self.peerHello
  local g3 = peer and peer.game3
  if type(g3) ~= "table" then
    return "refused", "peer_is_not_firered"
  end
  local verdict, reason = Handshake.checkCompat(self.myHello, peer)
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

function Game3Link:update(dt)
  if self.closed then return self.state end
  self.elapsed = self.elapsed + (tonumber(dt) or 0)
  self._session:update()

  if self._session:take(Game3Link.BYE) then
    self:_finish("closed", "peer_left")
    return self.state
  end

  if not self.peerHello then
    local hello = self._session:take(Game3Link.HELLO) or self._session:take("hello")
    if hello then
      self.peerHello = hello
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

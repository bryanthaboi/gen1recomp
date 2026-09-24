package.path = "./?.lua;./?/init.lua;" .. package.path

local H = {}

local SHARED_PREFIX = { "src.import.", "tests." }
local SHARED = {
  ["src.link.Wire"] = true,
  ["src.link.Json"] = true,
  ["src.link.Protocol"] = true,
  ["src.core.Logger"] = true,
  ["src.core.Strings"] = true,
  ["src.core.game3.dataset"] = true,
  ["src.core.game3.pokemon"] = true,
  ["src.core.game3.rom_text"] = true,
  ["src.core.game3.items_data"] = true,
  ["src.core.game3.summary_data"] = true,
  ["src.core.game3.save_mon"] = true,
  ["src.core.game3.battle.moves"] = true,
}

local function swappable(name)
  if type(name) ~= "string" or name:sub(1, 4) ~= "src." then return false end
  if SHARED[name] then return false end
  for _, prefix in ipairs(SHARED_PREFIX) do
    if name:sub(1, #prefix) == prefix then return false end
  end
  return true
end

H.known = {}
H.current = nil

local function capture(w)
  for name, mod in pairs(package.loaded) do
    if swappable(name) then
      H.known[name] = true
      w.mods[name] = mod
    end
  end
end

local function clear()
  for name in pairs(package.loaded) do
    if swappable(name) then H.known[name] = true end
  end
  for name in pairs(H.known) do package.loaded[name] = nil end
end

function H.enter(w)
  if H.current == w then return end
  if H.current then capture(H.current) end
  for name in pairs(H.known) do package.loaded[name] = w.mods[name] end
  H.current = w
end

function H.run(w, fn, ...)
  H.enter(w)
  local out = { pcall(fn, ...) }
  capture(w)
  if not out[1] then error(out[2], 0) end
  return unpack(out, 2)
end

H.bundle = nil

function H.mountCache()
  local Cache = require("tests.game3_cache")
  if H.bundle ~= nil then return H.bundle end
  package.loaded["src.core.game3.scripting.space"] = nil
  local bundle = Cache.bundle()
  H.bundle = bundle or false
  return H.bundle
end

function H.newWorld(name, session)
  if H.current then capture(H.current) end
  clear()
  H.current = nil
  local w = { name = name, mods = {}, session = session, reports = {} }
  session.store = session.store or { flags = {}, vars = {} }
  local game = { data = { maps = {} }, session = session }
  w.game = game
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return w.session end,
    isActive = function() return true end,
    _game = game,
    _mod = nil,
  }
  package.loaded["src.core.game3.player"] = { cellX = 0, cellY = 0, facing = "up" }
  package.loaded["src.core.game3.map"] = { load = function() end, current = "FR_BATTLE_COLOSSEUM_2P" }
  package.loaded["src.core.game3.objects"] = {
    addObject = function() return true end,
    removeObject = function() return true end,
    refreshGraphics = function() return 0 end,
  }
  package.loaded["src.core.game3.scripting.space"] = {
    store = session.store,
    mapId = "FR_BATTLE_COLOSSEUM_2P",
    ensureBundle = function() return H.bundle or nil end,
    bundle = H.bundle or nil,
  }
  package.loaded["src.online.Client"] = {
    report = function(result) w.reports[#w.reports + 1] = result end,
    state = function() return "online" end,
  }
  w.Link = require("src.core.game3.link")
  w.LB = require("src.core.game3.link.battle")
  w.Battle = require("src.core.game3.battle")
  w.Ui = require("src.core.game3.battle.ui")
  w.Commands = require("src.core.game3.battle.commands")
  w.State = require("src.core.game3.battle.state")
  w.Game3Link = require("src.link.Game3Link")
  w.RelayTransport = require("src.core.game3.link.relay_transport")
  w.Guard = require("src.core.game3.battle.link_guard")
  capture(w)
  H.current = w
  return w
end

local Json = require("src.link.Json")

local function wireCopy(msg)
  return Json.decode(Json.encode(msg))
end

local Relay = {}
Relay.__index = Relay

function H.relay(opts)
  opts = opts or {}
  local self = setmetatable({
    room = "r" .. string.format("%016x", opts.roomSeed or 1),
    seats = opts.seats or 2,
    seed = opts.seed or 1,
    match = opts.match or "m1",
    players = {},
    ends = {},
    log = {},
    lag = opts.lag or {},
    tamper = opts.tamper,
  }, Relay)
  for seat = 0, self.seats - 1 do
    self.players[#self.players + 1] = { id = string.format("%08x", seat + 1), name = "P" .. seat, seat = seat, online = true }
  end
  return self
end

function Relay:client()
  local relay = self
  return {
    state = function() return "online" end,
    error = function() return nil end,
    room = function()
      return { room = relay.room, seats = relay.seats, players = relay.players, seed = relay.seed,
        match = relay.match }
    end,
    seat = function() return nil end,
    role = function() return nil end,
  }
end

local Session = {}
Session.__index = Session

function Relay:session(seat)
  local s = setmetatable({
    relay = self, mySeat = seat, inbox = {}, pending = {},
    paired = true, closed = false, left = false, target = self.room,
  }, Session)
  self.ends[#self.ends + 1] = s
  for _, row in ipairs(self.log) do
    if row.seat ~= seat then
      local msg = wireCopy(row.msg)
      msg.seat = row.seat
      s.inbox[#s.inbox + 1] = msg
    end
  end
  return s
end

function Relay:deliver(fromSeat, msg)
  self.log[#self.log + 1] = { seat = fromSeat, msg = wireCopy(msg) }
  for _, s in ipairs(self.ends) do
    if s.mySeat ~= fromSeat and not s.left then
      local copy = wireCopy(msg)
      copy.seat = fromSeat
      if self.tamper then copy = self.tamper(fromSeat, s.mySeat, copy) or copy end
      local delay = self.lag[s.mySeat == nil and "spectator" or s.mySeat] or 0
      s.pending[#s.pending + 1] = { at = delay, msg = copy }
    end
  end
end

function Relay:tick()
  for _, s in ipairs(self.ends) do
    local keep = {}
    for _, row in ipairs(s.pending) do
      row.at = row.at - 1
      if row.at < 0 and row.gone ~= nil then
        s.gone = s.gone or {}
        s.gone[row.gone] = true
      elseif row.at < 0 then
        s.inbox[#s.inbox + 1] = row.msg
      else
        keep[#keep + 1] = row
      end
    end
    s.pending = keep
  end
end

function Relay:drop(seat)
  for i = #self.players, 1, -1 do
    if self.players[i].seat == seat then table.remove(self.players, i) end
  end
end

function Relay:leave(seat)
  for _, s in ipairs(self.ends) do
    if s.mySeat ~= seat and not s.left then
      local delay = self.lag[s.mySeat == nil and "spectator" or s.mySeat] or 0
      s.pending[#s.pending + 1] = { at = delay, gone = seat }
    end
  end
end

function Session:update() end
function Session:seat() return self.mySeat end
function Session:seats() return self.relay.seats end
function Session:players()
  if not self.gone then return self.relay.players end
  local out = {}
  for _, p in ipairs(self.relay.players) do
    if not self.gone[p.seat] then out[#out + 1] = p end
  end
  return out
end
function Session:role()
  if self.mySeat == nil then return "spectator" end
  return ({ [0] = "host", [1] = "guest", [2] = "seat2", [3] = "seat3" })[self.mySeat]
end
function Session:match() return self.relay.match end
function Session:seed() return self.seedOverride or self.relay.seed end
function Session:peerOnline() return true end
function Session:send(msg)
  if self.closed or self.mySeat == nil or type(msg) ~= "table" then return end
  self.relay:deliver(self.mySeat, msg)
end
function Session:poll()
  local out = self.inbox
  self.inbox = {}
  return out
end
function Session:take(messageType, predicate)
  for i, msg in ipairs(self.inbox) do
    if msg.type == messageType and (predicate == nil or predicate(msg) == true) then
      table.remove(self.inbox, i)
      return msg
    end
  end
  return nil
end
function Session:close()
  if self.mySeat ~= nil and not self.left then self.relay:leave(self.mySeat) end
  self.left = true
  self.closed = true
end
function Session:hasPending() return #self.inbox > 0 end

H.Relay = Relay

function H.legal(mon)
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryData = require("src.core.game3.summary_data")
  mon.exp = mon.exp or SummaryData.expForLevel(Pokemon.growthRate(mon.species), mon.level)
  mon.otName = mon.otName or "RED"
  mon.otId = mon.otId or 0x1234
  mon.personality = mon.personality or 0
  if mon.hp == nil then
    Pokemon.applyStats(mon)
    mon.hp = mon.maxHp
  end
  return mon
end

function H.pack(list)
  local Protocol = require("src.link.Protocol")
  local out = {}
  for i, mon in ipairs(list) do out[i] = Protocol.packMon3(H.legal(mon)) end
  return out
end

function H.attachSeat(w, relay, seat, spec)
  return H.run(w, function()
    local rs = relay:session(seat)
    rs.seedOverride = spec.seedOverride
    local t = w.RelayTransport.new(rs, { client = relay:client() })
    local lk = w.Game3Link.attach(t, { seat = seat, seats = relay.seats, game = w.game,
      linkType = w.LB.arenaLinkType(w.LB.MODE_OF[spec.mode or "single"]) })
    w.Link.attach(lk)
    w.transport = t
    spec.session = rs
    spec.seat = seat
    spec.seats = relay.seats
    spec.seed = relay.seed
    spec.headless = true
    if spec.autoFight == nil then spec.autoFight = false end
    w.LB.startArena(spec, function(result) w.result = result end)
    return lk
  end)
end

function H.attachSpectator(w, relay, spec)
  return H.run(w, function()
    local rs = relay:session(nil)
    local t = w.RelayTransport.new(rs, { client = relay:client() })
    w.transport = t
    spec.session = rs
    spec.transport = t
    spec.seed = relay.seed
    spec.headless = true
    w.LB.startSpectator(spec, function(result) w.result = result end)
  end)
end

function H.step(w, policy)
  return H.run(w, function()
    w.Link.update(1 / 60)
    if w.LB._spec then w.LB.update(1 / 60) end
    local Battle = w.Battle
    if Battle.isActive() then
      if policy and Battle._phase == "command" and not Battle._st.spectate and w.Ui._pendingCommand == nil then
        policy(w, Battle._st)
      end
      Battle.update(0, nil)
    end
  end)
end

return H

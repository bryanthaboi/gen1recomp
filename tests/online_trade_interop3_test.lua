#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
if not Cache.root("meta.json") then
  print("[skip] online_trade_interop3: " .. tostring(Cache.reason))
  os.exit(0)
end
if not _G.love then _G.love = require("tests.love_stub") end
love.graphics = nil

local failed, total = 0, 0
local function check(cond, msg)
  total = total + 1
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local TRADE_CENTER = "FR_TRADE_CENTER"
local MAPS = {
  [TRADE_CENTER] = {
    warps = { { x = 5, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
}

local function isWorldModule(k)
  return k:match("^src%.") ~= nil
end

local current

local function stash()
  if not current then return end
  for k, v in pairs(package.loaded) do
    if isWorldModule(k) then current.mods[k] = v end
  end
end

local function clearWorld()
  for k in pairs(package.loaded) do
    if isWorldModule(k) then package.loaded[k] = nil end
  end
end

local function within(w, fn, ...)
  if current ~= w then
    stash()
    clearWorld()
    for k, v in pairs(w.mods) do package.loaded[k] = v end
    current = w
  end
  return fn(...)
end

local function newWorld()
  stash()
  clearWorld()
  local w = { mods = {} }
  current = w
  Cache.mount("meta.json")
  return w
end

local function gameWorld(name, trainerId, species)
  local w = newWorld()
  w.saves = 0
  local session = {
    store = { flags = {}, vars = {} }, map = TRADE_CENTER, x = 5, y = 8,
    name = name, gender = 0, trainerId = trainerId, party = {},
    bag = { pockets = { items = {} } }, dex = { seen = {}, owned = {}, caught = {} },
    gameStats = {},
  }
  local game = { data = { maps = MAPS, generation = 3 }, session = session }
  function game:saveGame() w.saves = w.saves + 1 end
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
    isActive = function() return true end,
    _game = game,
  }
  package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 8, facing = "up" }
  package.loaded["src.core.game3.quest_log_recorder"] = { event = function() end }
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    key = function(n, i) return n .. "[" .. i .. "]" end,
    at = function(n, i) return n .. "[" .. i .. "]" end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
  package.loaded["src.core.game3.map"] = { load = function() end, current = TRADE_CENTER }
  package.loaded["src.core.game3.objects"] = {
    addObject = function() return true end,
    removeObject = function() return true end,
    refreshGraphics = function() return 0 end,
  }
  package.loaded["src.core.game3.scripting.space"] = {
    store = session.store, mapId = TRADE_CENTER,
    vm = { ctx = { specialVars = {}, stringVars = {} }, adapters = { log = function() end } },
  }
  require("src.core.game3.pokemon").install(nil)
  local Party = require("src.core.game3.party")
  for _, sp in ipairs(species) do Party.giveMon(session, sp[1], sp[2]) end
  w.session, w.game = session, game
  w.Link = require("src.core.game3.link")
  w.LT = require("src.core.game3.link.trade")
  w.Game3Link = require("src.link.Game3Link")
  stash()
  return w
end

local function launcherWorld(name, trainerId, species)
  local w = newWorld()
  w.files = {}
  local SaveData = require("src.core.SaveData")
  SaveData.portableFs = function()
    return {
      getInfo = function(n) return w.files[n] and { type = "file" } or nil end,
      read = function(n) return w.files[n] end,
      write = function(n, body) w.files[n] = body return true end,
      remove = function(n) w.files[n] = nil return true end,
      createDirectory = function() return true end,
    }
  end
  require("src.core.GameVersion").set("leafgreen")
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")
  local s = Schema.newGame({ version = "leafgreen", name = name, rngSeed = trainerId })
  s.trainerId = trainerId
  s.party = {}
  for _, sp in ipairs(species) do Party.giveMon(s, sp[1], sp[2]) end
  local save = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  local Trade = require("src.online.Trade")
  local path = Trade.slotPath("leafgreen", "slot1")
  w.files[path] = SaveData.encode(save)
  w.path, w.disk = path, w.files[path]
  w.handle = { version = "leafgreen", generation = 3, slotId = "slot1", save = save,
    path = path, party = save.party,
    data = { generation = 3, Pokemon = Pokemon, pokemon = Pokemon } }
  w.Trade, w.SaveData = Trade, SaveData
  stash()
  return w
end

local function newRelay()
  local R = { seats = {}, confirms = {}, n = 1, commits = 0, aborts = 0 }
  local function deliver(from, msg)
    for s, t in pairs(R.seats) do
      if s ~= from and not t.closed then
        local m = {}
        for k, v in pairs(msg) do m[k] = v end
        m.seat = from
        t.inbox[#t.inbox + 1] = m
      end
    end
  end
  function R.receive(seat, msg)
    if msg.type == "game3_trade_confirm" then
      R.confirms[seat] = msg.digest
      local d0, d1 = R.confirms[0], R.confirms[1]
      if d0 and d1 then
        R.confirms = {}
        if d0 == d1 then
          R.commits = R.commits + 1
          deliver(-1, { type = "trade_commit", n = R.n, digests = { d0, d1 } })
          R.n = R.n + 1
        else
          R.aborts = R.aborts + 1
          deliver(-1, { type = "trade_abort", n = R.n, why = "digest" })
        end
      end
      return
    end
    deliver(seat, msg)
  end
  function R.transport(seat)
    local t = { relay = true, paired = true, closed = false, inbox = {} }
    function t:update() end
    function t:send(msg)
      if self.closed then return false end
      local copy = {}
      for k, v in pairs(msg) do copy[k] = v end
      copy.seat = nil
      R.receive(seat, copy)
      return true
    end
    function t:poll()
      local out = self.inbox
      self.inbox = {}
      return out
    end
    function t:take() return nil end
    function t:close() self.closed = true end
    function t:seat() return seat end
    function t:seats() return 2 end
    function t:peerOnline(s) local o = R.seats[s] return o ~= nil and not o.closed end
    R.seats[seat] = t
    return t
  end
  return R
end

local function scenario(label, gameSeat)
  print("[test] " .. label)
  local launcherSeat = 1 - gameSeat
  local relay = newRelay()
  local G = gameWorld("RED", 0x1234, { { 64, 30 }, { 25, 14 } })
  local L = launcherWorld("LEAF", 0x2222, { { 95, 25 }, { 1, 8 } })
  local tG, tL = relay.transport(gameSeat), relay.transport(launcherSeat)
  within(G, function()
    G.Link.reset()
    G.LT.reset()
    G.Link.attach(G.Game3Link.attach(tG, { seat = gameSeat, seats = 2, game = G.game,
      linkType = G.LT.LINKTYPE.TRADE }))
  end)
  local remote = within(L, function()
    local r = assert(L.Trade.remote(L.handle, tL, { transport = tL }))
    r:start()
    return r
  end)
  local function step(n)
    for _ = 1, n or 1 do
      within(G, function() G.Link.update(0) end)
      within(L, function() remote:update() end)
    end
  end
  step(3)
  check(within(G, function() return G.Link.link and G.Link.link:isReady() end),
    "the in-game link handshakes with the launcher as full")
  within(G, function()
    G.Link.link:send({ type = "game3_battle_seat", seat = gameSeat })
    G.LT.startMenu({ screen = false })
  end)
  step(3)
  eq(remote:stage(), "picking", "the launcher reaches the trade menu")
  eq(within(G, function() return #G.LT.peerParty end), 2, "the game sees the launcher's party")
  eq(within(G, function() return G.LT.peerParty[1].species end), 95, "packed as packMon3")
  eq(#remote.session.theirParty, 2, "the launcher sees the game's party")
  within(G, function() G.LT.offer(1) end)
  within(L, function() remote:pick(1) end)
  step(3)
  eq(remote:stage(), "confirming", "the launcher is asked to confirm")
  eq(within(G, function() return G.LT.state end), "confirm", "and so is the game")
  within(G, function() G.LT.confirm(true) end)
  within(L, function() remote:confirm(true) end)
  local done = false
  for _ = 1, 6000 do
    step(1)
    if within(G, function() return G.LT.completed end) == 1 and remote:stage() == "committed" then
      done = true
      break
    end
  end
  check(done, "the in-game scene finished and the launcher committed ("
    .. tostring(within(G, function() return G.LT.state .. "/" .. tostring(G.LT.lastResult)
      .. "/" .. tostring(G.LT.lastRefusal) end)) .. ", " .. tostring(remote:stage()) .. ")")
  eq(relay.commits, 1, "one trade_commit")
  eq(G.saves, 1, "the game saved once")
  eq(within(G, function() return G.session.party[1].species end), 95,
    "the game holds the launcher's Onix")
  eq(within(G, function() return G.session.party[1].otName end), "LEAF",
    "with the launcher player as its OT")
  local disk = within(L, function() return L.SaveData.decode(L.files[L.path]) end)
  eq(disk and disk.party[1].species, 65, "the launcher's file holds the Kadabra, now Alakazam")
  check(within(L, function() return L.files[L.path] end) ~= L.disk, "the launcher wrote its file")
end

scenario("1. in-game seat 0 trades with a launcher at seat 1", 0)
scenario("2. a launcher at seat 0 leads an in-game seat 1", 1)

print(("%d/%d checks passed"):format(total - failed, total))
os.exit(failed == 0 and 0 or 1)

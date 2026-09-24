#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
if not Cache.root("meta.json") then
  print("[skip] trade barrier: " .. tostring(Cache.reason))
  os.exit(0)
end

local failed = 0
local function check(cond, msg)
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

local function clearWorld()
  for k in pairs(package.loaded) do
    if isWorldModule(k) then package.loaded[k] = nil end
  end
end

local current
local relay

local function enter(w)
  if current == w then return end
  if current then
    for k, v in pairs(package.loaded) do
      if isWorldModule(k) then current.mods[k] = v end
    end
  end
  clearWorld()
  for k, v in pairs(w.mods) do package.loaded[k] = v end
  current = w
end

local function within(w, fn, ...)
  enter(w)
  return fn(...)
end

local function makeWorld(label, name, trainerId, species)
  if current then
    for k, v in pairs(package.loaded) do
      if isWorldModule(k) then current.mods[k] = v end
    end
  end
  clearWorld()
  local w = { label = label, mods = {}, saves = 0, savedParties = {} }
  current = w
  Cache.mount("meta.json")
  require("tests.fixture_data.game3_items").install()
  local session = {
    store = { flags = {}, vars = {} },
    map = TRADE_CENTER, x = 5, y = 8,
    name = name, gender = 0, trainerId = trainerId,
    party = {}, bag = { pockets = { items = {} } },
    dex = { seen = {}, owned = {}, caught = {} },
    gameStats = {},
  }
  local game = { data = { maps = MAPS }, session = session, phase = "field" }
  function game:saveGame()
    w.saves = w.saves + 1
    local snap = {}
    for i, m in ipairs(session.party) do snap[i] = m.species end
    w.savedParties[#w.savedParties + 1] = snap
  end
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
    isActive = function() return true end,
    _game = game,
    _mod = nil,
  }
  package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 8, facing = "up" }
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    key = function(n, i) return n .. "[" .. i .. "]" end,
    at = function(n, i) return n .. "[" .. i .. "]" end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
  w.quest = {}
  package.loaded["src.core.game3.quest_log_recorder"] = {
    event = function(_, key, args) w.quest[#w.quest + 1] = { key = key, args = args } end,
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
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  local Party = require("src.core.game3.party")
  for _, sp in ipairs(species) do Party.giveMon(session, sp[1], sp[2]) end
  w.session, w.game = session, game
  w.Link = require("src.core.game3.link")
  w.LT = require("src.core.game3.link.trade")
  w.Scene = require("src.core.game3.trade_scene")
  w.Game3Link = require("src.link.Game3Link")
  w.Protocol = require("src.link.Protocol")
  w.Task = require("src.core.game3.task")
  w.LT.journalIo = {
    read = function() return w.journalText end,
    write = function(text)
      if w.journalFails then return false end
      w.journalText = text
      return true
    end,
    remove = function() w.journalText = nil return true end,
  }
  w.queries = 0
  w.LT.outcomeClient = {
    send = function(_, method, path, _, opts)
      w.queries = w.queries + 1
      return { method = method, path = path, params = opts.params }
    end,
    poll = function(_, h)
      if relay.ledgerDown then return { status = "error", err = "offline" } end
      return { status = "ok", code = 200, data = { outcome = relay.outcome(h.params.room, h.params.digest) } }
    end,
    release = function() end,
  }
  for k, v in pairs(package.loaded) do
    if isWorldModule(k) then w.mods[k] = v end
  end
  return w
end

local function newRelay()
  local R = { log = {}, seq = 0, seats = {}, n = 1, confirms = {}, commits = 0, aborts = 0, ledger = {},
    dropped = 0 }

  local function deliver(t, entry)
    if t.closed or not t.online then return end
    local m = {}
    for k, v in pairs(entry.msg) do m[k] = v end
    m.seat = entry.seat
    t.inbox[#t.inbox + 1] = m
    t.lastSeq = entry.seq
  end

  local function append(seat, msg)
    R.seq = R.seq + 1
    local entry = { seq = R.seq, seat = seat, msg = msg }
    R.log[#R.log + 1] = entry
    for s, t in pairs(R.seats) do
      if s ~= seat then deliver(t, entry) end
    end
    return entry
  end

  local function settle()
    local d0, d1 = R.confirms[0], R.confirms[1]
    if not (d0 and d1) then return end
    local n = R.n
    R.n = n + 1
    R.confirms = {}
    if d0 == d1 then
      R.commits = R.commits + 1
      R.ledger[#R.ledger + 1] = { n = n, outcome = "commit", digests = { d0, d1 } }
      append(-1, { type = "trade_commit", n = n, digests = { d0, d1 } })
    else
      R.aborts = R.aborts + 1
      R.ledger[#R.ledger + 1] = { n = n, outcome = "abort", digests = { d0, d1 } }
      append(-1, { type = "trade_abort", n = n, why = "digest" })
    end
  end

  function R.abortOpen(why)
    if next(R.confirms) == nil then return false end
    local n = R.n
    R.n = n + 1
    local seen = {}
    for _, d in pairs(R.confirms) do seen[#seen + 1] = d end
    R.confirms = {}
    R.aborts = R.aborts + 1
    R.ledger[#R.ledger + 1] = { n = n, outcome = "abort", digests = seen }
    append(-1, { type = "trade_abort", n = n, why = why })
    return true
  end

  function R.outcome(room, digest)
    if room ~= "r0000000000000001" then return "abort" end
    for i = #R.ledger, 1, -1 do
      local e = R.ledger[i]
      for _, d in ipairs(e.digests) do
        if d == digest then return e.outcome end
      end
    end
    for _, d in pairs(R.confirms) do
      if d == digest then return "open" end
    end
    return "abort"
  end

  function R.receive(seat, msg)
    if R.tamper then
      local changed = R.tamper(seat, msg)
      if changed == false then return end
      msg = changed or msg
    end
    if msg.type == "game3_trade_confirm" and R.confirms[seat] ~= nil then
      R.dropped = R.dropped + 1
      return
    end
    append(seat, msg)
    if msg.type == "game3_trade_confirm" then
      R.confirms[seat] = msg.digest
      if R.afterConfirm then R.afterConfirm(seat) end
      settle()
    end
  end

  function R.transport(seat)
    local t = {
      relay = true, paired = true, closed = false, error = nil,
      online = true, inbox = {}, lastSeq = 0, target = "r0000000000000001",
    }
    function t:update() end
    function t:send(msg)
      if self.closed or not self.online then return false end
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
    function t:peerOnline(s) local o = R.seats[s] return o and o.online and not o.closed end
    R.seats[seat] = t
    return t
  end

  function R.drop(seat) R.seats[seat].online = false end

  function R.resume(seat, from)
    local t = R.seats[seat]
    t.online = true
    local since = from or t.lastSeq
    for _, entry in ipairs(R.log) do
      if entry.seq > since and entry.seat ~= seat then deliver(t, entry) end
    end
  end

  function R.leave(seat)
    R.seats[seat].closed = true
    if R.confirms[1 - seat] then R.abortOpen("left") end
    for s, t in pairs(R.seats) do
      if s ~= seat then t.closed = true end
    end
  end

  return R
end

local A, B

local function attach(w, seat)
  within(w, function()
    w.Link.reset()
    w.LT.reset()
    local t = relay.transport(seat)
    w.transport = t
    local link = w.Game3Link.attach(t, {
      role = seat == 0 and "host" or "guest", game = w.game,
      linkType = w.LT.LINKTYPE.TRADE,
    })
    w.Link.attach(link)
  end)
end

local function step(n)
  for _ = 1, n or 1 do
    within(A, function() A.Link.update(0) end)
    within(B, function() B.Link.update(0) end)
  end
end

local function ltState(w) return within(w, function() return w.LT.state end) end

local function speciesList(w)
  return within(w, function()
    local out = {}
    for i, m in ipairs(w.session.party) do out[i] = m.species end
    return table.concat(out, ",")
  end)
end

local function open(label)
  print("[test] " .. label)
  relay = newRelay()
  A = makeWorld("A", "RED", 0x1234, { { 1, 10 }, { 67, 30 } })
  B = makeWorld("B", "BLUE", 0x2222, { { 7, 11 }, { 25, 14 } })
  attach(A, 0)
  attach(B, 1)
  step(2)
  within(A, function() A.LT.startMenu({ screen = false }) end)
  within(B, function() B.LT.startMenu({ screen = false }) end)
  step(2)
end

local function offerAndConfirm(slotA, slotB)
  within(A, function() A.LT.offer(slotA) end)
  within(B, function() B.LT.offer(slotB) end)
  step(2)
  within(A, function() A.LT.confirm(true) end)
  within(B, function() B.LT.confirm(true) end)
end

local function pending(w)
  return within(w, function() return #w.LT.pendingTrades() end)
end

local function tick(w, n)
  within(w, function()
    for _ = 1, n or 1 do w.Task.update(1 / 60) end
  end)
end

local function runUntil(pred, limit)
  local n = 0
  while n < (limit or 6000) and not pred() do
    step(1)
    n = n + 1
  end
  return pred()
end

open("1. the happy path commits once and both saves hold the traded mons")
eq(ltState(A), "menu", "seat 0 is in the trade menu")
eq(within(A, function() return #A.LT.peerParty end), 2, "and sees the other party, unpacked")
eq(within(A, function() return A.LT.peerParty[1].species end), 7, "SQUIRTLE leads it")
check(within(A, function() return (A.LT.peerParty[1].maxHp or 0) > 0 end),
  "stats were recomputed on arrival, never read off the wire")
offerAndConfirm(2, 1)
check(runUntil(function() return ltState(A) == "commit_wait" or ltState(A) == "committed"
  or ltState(A) == "scene" end, 50), "seat 0 sent its confirm and waited for the relay")
eq(A.saves + B.saves, 0, "nothing was written before trade_commit")
check(runUntil(function()
  return within(A, function() return A.LT.completed end) == 1
    and within(B, function() return B.LT.completed end) == 1
end), "both sides played the scene to the end")
eq(relay.commits, 1, "the relay issued exactly one trade_commit")
eq(A.saves, 1, "seat 0 wrote its save once")
eq(B.saves, 1, "seat 1 wrote its save once")
eq(speciesList(A), "1,7", "seat 0 holds SQUIRTLE")
eq(speciesList(B), "68,25", "seat 1 holds the MACHOKE, which evolved into MACHAMP")
eq(B.savedParties[1] and B.savedParties[1][1], 68, "and the save happened after the evolution")
eq(A.quest[#A.quest] and A.quest[#A.quest].key, "TradedMon1ForPersonsMon2",
  "the quest log recorded the link trade")
check(runUntil(function() return ltState(A) == "menu" and ltState(B) == "menu"
  and within(A, function() return A.LT.peer ~= nil end) end, 50),
  "the Trade Center returns both players to the trade menu")
eq(within(A, function() return A.LT.peerParty[1].species end), 68,
  "with the other player's new party on it")
eq(pending(A) + pending(B), 0, "the post-trade saves cleared both pending-trade journals")

open("2. a trade_commit whose digests are not ours is ignored")
offerAndConfirm(1, 1)
runUntil(function() return ltState(A) == "commit_wait" end, 50)
local realDigest = within(A, function() return A.LT._digest end)
within(A, function()
  A.LT.onCommit({ n = 9, digests = { "0000000000000000", "0000000000000000" } })
end)
eq(ltState(A), "commit_wait", "a foreign commit does not start the scene")
check(realDigest and #realDigest == 16, "the digest is 16 hex")

open("3. the other seat leaves before confirming: nothing is written anywhere")
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_confirm" then
    relay.tamper = nil
    return false
  end
end
offerAndConfirm(1, 1)
runUntil(function() return ltState(A) == "commit_wait" and ltState(B) == "commit_wait" end, 50)
relay.leave(1)
step(3)
eq(ltState(A), "off", "seat 0's link closed with the other seat gone")
check(within(A, function() return A.LT.lastResult end) ~= nil, "and it knows why")
eq(ltState(B), "off", "seat 1 dropped out too")
eq(A.saves + B.saves, 0, "neither save was written")
eq(speciesList(A), "1,67", "seat 0's party is untouched")
eq(speciesList(B), "7,25", "seat 1's party is untouched")

open("4. a confirm that never reaches the relay times out on both seats")
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_confirm" then
    relay.tamper = nil
    return false
  end
end
offerAndConfirm(1, 1)
runUntil(function() return ltState(A) == "commit_wait" and ltState(B) == "commit_wait" end, 50)
relay.abortOpen("timeout")
step(3)
eq(ltState(A), "canceled", "seat 0 is back on the trade screen")
eq(ltState(B), "canceled", "and so is seat 1")
eq(within(B, function() return B.LT.lastResult end), "timeout", "as a timeout")
eq(A.saves + B.saves, 0, "nothing was written")
eq(pending(A), 0, "the relay's trade_abort cleared seat 0's journal")

open("5. drop after the commit, then resume: both saves written exactly once")
relay.afterConfirm = function()
  if relay.confirms[0] and relay.confirms[1] then
    relay.afterConfirm = nil
    relay.drop(1)
  end
end
offerAndConfirm(1, 1)
check(runUntil(function() return within(A, function() return A.LT.completed end) == 1 end),
  "seat 0 got the commit and finished the trade")
eq(A.saves, 1, "seat 0 wrote once")
eq(ltState(B), "commit_wait", "seat 1 never heard the commit and is still waiting")
eq(B.saves, 0, "and has written nothing yet")
eq(speciesList(B), "7,25", "its party is unchanged while it waits")
relay.resume(1)
check(runUntil(function() return within(B, function() return B.LT.completed end) == 1 end),
  "the resume replayed trade_commit and seat 1 finished the trade")
eq(B.saves, 1, "seat 1 wrote once")
eq(speciesList(B), "1,25", "seat 1 holds BULBASAUR")
eq(speciesList(A), "7,67", "seat 0 holds SQUIRTLE")
eq(pending(B), 0, "seat 1's journal was cleared by its post-commit save")
relay.resume(1, 0)
step(30)
eq(B.saves, 1, "a second replay of the whole log writes nothing more on seat 1")
eq(A.saves, 1, "and seat 0 is still at one write")
eq(within(B, function() return B.LT.completed end), 1, "no second trade happened")

open("6. the peer drops for good after the commit: the local write still finishes")
offerAndConfirm(1, 2)
runUntil(function() return ltState(A) == "committed" or ltState(A) == "scene" end, 50)
relay.leave(1)
check(runUntil(function() return within(A, function() return A.LT.completed end) == 1 end),
  "seat 0 plays the scene to the end without the other seat")
eq(A.saves, 1, "and writes its save once")
eq(speciesList(A), "25,67", "with PIKACHU in the party")

local function skewSeat0Digest()
  relay.tamper = function(seat, msg)
    if seat == 0 and msg.type == "game3_trade_confirm" then
      relay.tamper = nil
      local copy = {}
      for k, v in pairs(msg) do copy[k] = v end
      copy.digest = ("0"):rep(16)
      return copy
    end
  end
end

open("7. digest mismatch aborts both seats with nothing written")
skewSeat0Digest()
offerAndConfirm(1, 1)
step(5)
eq(relay.aborts, 1, "the relay saw two different digests")
eq(ltState(A), "canceled", "seat 0 is back on the trade screen")
eq(ltState(B), "canceled", "seat 1 too")
eq(within(A, function() return A.LT.lastResult end), "digest", "because of the digest")
eq(A.saves + B.saves, 0, "nothing was written")
eq(speciesList(A), "1,67", "seat 0's party is whole")
eq(speciesList(B), "7,25", "seat 1's party is whole")
within(A, function() A.LT.resumeMenu() end)
within(B, function() B.LT.resumeMenu() end)
offerAndConfirm(1, 1)
check(runUntil(function()
  return within(A, function() return A.LT.completed end) == 1
    and within(B, function() return B.LT.completed end) == 1
end), "a clean retry after the abort commits")
eq(A.saves .. "/" .. B.saves, "1/1", "each side wrote once")

open("8. a mon the strict unpack refuses cancels before any confirm")
relay.tamper = function(seat, msg)
  if seat == 0 and msg.type == "game3_trade_mon" then
    relay.tamper = nil
    local copy = {}
    for k, v in pairs(msg) do copy[k] = v end
    local mon = {}
    for k, v in pairs(msg.mon) do mon[k] = v end
    mon.species = 260
    copy.mon = mon
    return copy
  end
end
offerAndConfirm(1, 1)
step(5)
eq(ltState(B), "canceled", "seat 1 refused the illegal mon")
eq(within(B, function() return B.LT.lastResult end), "bad_mon", "as bad_mon")
eq(ltState(A), "canceled", "and seat 0 was told to cancel")
eq(relay.commits, 0, "no commit was issued")
eq(A.saves + B.saves, 0, "nothing was written")

open("9. the loopback harness self-commits without a relay")
do
  local W = makeWorld("L", "RED", 0x1234, { { 1, 10 }, { 4, 12 } })
  within(W, function()
    local LT, Link, P = W.LT, W.Link, W.Protocol
    Link.reset()
    LT.reset()
    LT.loopbackCommit = true
    local host, peer = W.Game3Link.loopback({ game = W.game })
    host:update(0)
    peer:update(0)
    Link.attach(host)
    LT.startMenu({ screen = false })
    local Party = require("src.core.game3.party")
    local other = { name = "BLUE", trainerId = 0x2222, party = {} }
    Party.giveMon(other, 7, 11)
    peer:send({ type = LT.MSG.PARTY, party = P.packParty3(other.party, { 1 }), name = "BLUE",
      trainerId = 0x2222, gender = 0, version = 4, progressFlags = 0 })
    LT.update(0)
    LT.offer(1)
    peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
    LT.update(0)
    LT.confirm(true)
    peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
    LT.update(0)
    peer:update(0)
    local mine = peer:take(LT.MSG.MON)
    local theirs = P.packMon3(other.party[1])
    peer:send({ type = LT.MSG.MON, mon = theirs, name = "BLUE", trainerId = 0x2222 })
    LT.update(0)
    eq(LT.state, "commit_wait", "loopback waits for the other confirm")
    peer:update(0)
    local myConfirm = peer:take(LT.MSG.CONFIRM)
    local wire = require("src.link.Wire").sanitize({ type = LT.MSG.MON, mon = theirs }).mon
    eq(myConfirm and myConfirm.digest, P.tradeDigest(mine.mon, wire),
      "the confirm carries tradeDigest(seat 0 mon, seat 1 mon)")
    peer:send({ type = LT.MSG.CONFIRM, digest = myConfirm and myConfirm.digest })
    local guard = 0
    while guard < 6000 and LT.completed == 0 do
      peer:update(0)
      local cmd = peer:take(LT.MSG.CMD)
      while cmd do
        if cmd.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
          peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
        end
        cmd = peer:take(LT.MSG.CMD)
      end
      LT.update(0)
      guard = guard + 1
    end
    eq(LT.completed, 1, "the loopback trade finished")
    eq(W.saves, 1, "and wrote once")
    eq(W.session.party[1].species, 7, "SQUIRTLE arrived")
    LT.loopbackCommit = false
    Link.reset()
  end)
end

local function dropSeat0AfterBothConfirms()
  relay.afterConfirm = function()
    if relay.confirms[0] and relay.confirms[1] then
      relay.afterConfirm = nil
      relay.seats[0].closed = true
    end
  end
end

open("10. a Union Room board trade that the relay aborts returns to the room")
do
  relay.tamper = function(seat, msg)
    if seat == 1 and msg.type == "game3_trade_confirm" then
      relay.tamper = nil
      return false
    end
  end
  local done = {}
  for _, w in ipairs({ A, B }) do
    within(w, function()
      w.LT.reset()
      local ok = w.LT.startUnionRoomTrade(function(received, why)
        done[w.label] = { received = received, why = why }
      end)
      check(ok, w.label .. " started a Union Room board trade")
    end)
  end
  runUntil(function() return ltState(A) == "commit_wait" and ltState(B) == "commit_wait" end, 50)
  eq(ltState(A), "commit_wait", "seat 0 confirmed and waits for the relay")
  relay.abortOpen("timeout")
  step(5)
  check(not within(A, function() return A.LT.isActive() end), "the board trade is no longer active on seat 0")
  check(not within(B, function() return B.LT.isActive() end), "nor on seat 1")
  check(done.A ~= nil and done.A.received == nil, "seat 0's Union Room callback fired with no mon")
  eq(done.A and done.A.why, "timeout", "and the timeout reason")
  check(done.B ~= nil, "seat 1's callback fired too")
  eq(A.saves + B.saves, 0, "nothing was written")
  eq(pending(A) + pending(B), 0, "and no journal is left behind")
end

open("11. stale barrier results from before the last commit are ignored")
offerAndConfirm(1, 1)
check(runUntil(function()
  return within(A, function() return A.LT.completed end) == 1
    and within(B, function() return B.LT.completed end) == 1
end), "a first trade commits")
runUntil(function() return ltState(A) == "menu" and ltState(B) == "menu" end, 50)
local lastN = within(A, function() return A.LT._lastCommitN end)
eq(lastN, 1, "seat 0 remembers barrier n 1")
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_confirm" then
    relay.tamper = nil
    return false
  end
end
offerAndConfirm(1, 1)
runUntil(function() return ltState(A) == "commit_wait" end, 50)
eq(ltState(A), "commit_wait", "seat 0 waits on the second barrier")
local t0 = A.transport
t0.inbox[#t0.inbox + 1] = { type = "trade_abort", n = lastN, why = "timeout", seat = -1, relay = true }
step(3)
eq(ltState(A), "commit_wait", "a replayed trade_abort with n <= the last commit is ignored")
local d2 = within(A, function() return A.LT._digest end)
check(not within(A, function() return A.LT.onCommit({ n = lastN, digests = { d2, d2 } }) end),
  "a replayed trade_commit with n <= the last commit is refused even when the digests match")
eq(ltState(A), "commit_wait", "and the barrier is still open")
relay.abortOpen("timeout")
step(3)
eq(ltState(A), "canceled", "the real abort (n 2) cancels")
eq(A.saves, 1, "only the first trade was written")

open("12. a seat whose link dies after its confirm reached the relay settles from the ledger")
dropSeat0AfterBothConfirms()
offerAndConfirm(2, 1)
check(runUntil(function() return within(B, function() return B.LT.completed end) == 1 end),
  "seat 1 got trade_commit and finished")
eq(speciesList(B), "68,25", "seat 1 holds the MACHOKE, evolved")
eq(ltState(A), "off", "seat 0 lost its link while waiting")
eq(A.saves, 0, "and wrote nothing then")
eq(speciesList(A), "1,67", "its party is untouched so far")
eq(pending(A), 1, "but it kept a pending-trade journal")
check(within(A, function() return A.LT._resolver ~= nil end), "and started the outcome resolver")
tick(A, 3)
check(A.queries >= 1, "the resolver asked for the barrier outcome")
eq(speciesList(A), "1,7", "the committed trade was applied: SQUIRTLE replaced the MACHOKE")
eq(A.saves, 1, "and saved once")
eq(pending(A), 0, "the journal is gone")
check(not (speciesList(A):find("67") and speciesList(B):find("68")), "the MACHOKE is not in both parties")
tick(A, 400)
check(within(A, function() return A.LT._resolver == nil end), "the resolver finished")
eq(A.saves, 1, "and nothing more is written")

open("13. the ledger is unreachable in session: the journal settles on the next Continue")
relay.ledgerDown = true
dropSeat0AfterBothConfirms()
offerAndConfirm(2, 1)
check(runUntil(function() return within(B, function() return B.LT.completed end) == 1 end),
  "seat 1 finished the committed trade")
tick(A, 600)
eq(pending(A), 1, "seat 0 keeps its journal while the ledger does not answer")
eq(speciesList(A), "1,67", "and does not guess")
eq(A.saves, 0, "or write")
local diskParty = within(A, function() return A.LT.copy(A.session.party) end)
local diskJournal = A.journalText
local A2 = makeWorld("A2", "RED", 0x1234, {})
within(A2, function()
  A2.session.party = diskParty
  A2.journalText = diskJournal
  A2.Link.reset()
  A2.LT.reset()
end)
relay.ledgerDown = false
within(A2, function() A2.LT.resumePending() end)
tick(A2, 3)
eq(speciesList(A2), "1,7", "after the restart the committed trade is applied")
eq(A2.saves, 1, "and saved once")
eq(pending(A2), 0, "and the journal is cleared")

open("14. a seat that drops before the relay commits drops its journal on abort")
relay.afterConfirm = function(seat)
  if seat == 0 then
    relay.afterConfirm = nil
    relay.seats[0].closed = true
  end
end
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_confirm" then
    relay.tamper = nil
    return false
  end
end
offerAndConfirm(2, 1)
runUntil(function() return ltState(A) == "off" and ltState(B) == "commit_wait" end, 50)
eq(pending(A), 1, "seat 0 went off with a journal")
tick(A, 3)
eq(pending(A), 1, "the barrier is still open, so it waits")
relay.abortOpen("timeout")
step(3)
tick(A, 400)
eq(pending(A), 0, "the ledger says abort and the journal is dropped")
eq(speciesList(A), "1,67", "the party is whole")
eq(A.saves, 0, "nothing was written")
eq(ltState(B), "canceled", "seat 1 got the abort")

open("15. a mon block left over from a canceled attempt is ignored")
skewSeat0Digest()
offerAndConfirm(1, 1)
step(5)
eq(relay.aborts, 1, "the first attempt aborted on the digest")
local stale = within(B, function()
  return { type = "game3_trade_mon", seat = 1,
    mon = B.Protocol.packMon3(B.session.party[2]), name = "BLUE", trainerId = 0x2222 }
end)
A.transport.inbox[#A.transport.inbox + 1] = stale
step(1)
within(A, function() A.LT.resumeMenu() end)
within(B, function() B.LT.resumeMenu() end)
local held
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_mon" then
    relay.tamper = nil
    held = msg
    return false
  end
end
offerAndConfirm(1, 1)
step(3)
eq(ltState(A), "exchange", "seat 0 skipped the stale block and still waits for this attempt's")
relay.receive(1, held)
check(runUntil(function()
  return within(A, function() return A.LT.completed end) == 1
    and within(B, function() return B.LT.completed end) == 1
end), "the retry commits once the real block lands")
eq(relay.aborts, 1, "with no spurious digest abort")
eq(speciesList(A), "7,67", "seat 0 received SQUIRTLE, not the stale PIKACHU")

open("16. a journal that cannot be written refuses the confirm")
A.journalFails = true
offerAndConfirm(1, 1)
step(5)
eq(within(A, function() return A.LT.lastResult end), "journal", "seat 0 canceled before confirming")
eq(relay.confirms[0], nil, "no confirm from seat 0 reached the relay")
eq(ltState(B), "canceled", "seat 1 was told to cancel")
eq(relay.commits, 0, "no commit")
eq(A.saves + B.saves, 0, "nothing was written")

open("17. a mon that is not the one shown is refused, and the next round survives the stale one")
local swapMon = within(B, function() return B.Protocol.packMon3(B.session.party[2]) end)
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_mon" then
    relay.tamper = nil
    local copy = {}
    for k, v in pairs(msg) do copy[k] = v end
    copy.mon = swapMon
    return copy
  end
end
offerAndConfirm(1, 1)
check(runUntil(function() return ltState(A) == "canceled" and ltState(B) == "canceled" end, 50),
  "both seats left the exchange")
-- pokefirered/src/trade.c:1951
eq(within(A, function() return A.LT.lastRefusal end), "not the POKéMON that was shown",
  "seat 0 refused the PIKACHU sent in place of the SQUIRTLE it was shown")
eq(within(A, function() return A.LT.lastResult end), "bad_mon", "as bad_mon")
eq(within(B, function() return B.LT.lastResult end), "trade_canceled",
  "seat 1 was pulled out of commit_wait")
check(relay.confirms[1] ~= nil and relay.confirms[0] == nil,
  "seat 1's confirm is left open on the relay")
eq(relay.commits, 0, "no commit")
eq(A.saves + B.saves, 0, "nothing was written")
within(A, function() A.LT.resumeMenu() end)
within(B, function() B.LT.resumeMenu() end)
offerAndConfirm(2, 1)
check(runUntil(function()
  return within(A, function() return A.LT.completed end) == 1
    and within(B, function() return B.LT.completed end) == 1
end), "the next round commits on both seats")
eq(relay.ledger[1] and relay.ledger[1].outcome, "abort", "the stale round settled as an abort")
eq(relay.aborts, 1, "only one")
eq(relay.ledger[2] and relay.ledger[2].n, 2, "the commit came on the next round")
eq(relay.commits, 1, "and the next round committed once")
eq(speciesList(A), "1,7", "seat 0 holds the SQUIRTLE it was shown")
eq(speciesList(B), "68,25", "seat 1 holds the MACHOKE, evolved")
eq(A.saves .. "/" .. B.saves, "1/1", "each side wrote once")

open("18. an abort past the stale round still cancels")
relay.tamper = function(seat, msg)
  if seat == 1 and msg.type == "game3_trade_confirm" then
    relay.tamper = nil
    return false
  end
end
offerAndConfirm(1, 1)
runUntil(function() return ltState(A) == "commit_wait" end, 50)
eq(ltState(A), "commit_wait", "seat 0 waits on the barrier")
within(A, function() A.LT._staleRound = 1 end)
A.transport.inbox[#A.transport.inbox + 1] = { type = "trade_abort", n = 2, why = "timeout", seat = -1, relay = true }
step(3)
eq(ltState(A), "canceled", "an abort newer than the stale round cancels")
eq(within(A, function() return A.LT._staleRound end), nil, "and clears the stale round")
eq(A.saves, 0, "nothing was written")

if failed == 0 then
  print("[pass] trade barrier")
  os.exit(0)
end
print("[FAIL] trade barrier: " .. failed .. " failed")
os.exit(1)

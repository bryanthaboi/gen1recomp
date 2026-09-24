#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local H = require("tests.link3_harness")
local Cache = require("tests.game3_cache")

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

if not Cache.root("meta.json") then
  print("[skip] the Gen 3 arena state runs a real link battle on ROM data: " .. tostring(Cache.reason))
  os.exit(0)
end
H.mountCache()

local function input()
  local i = { pressed = {} }
  function i:wasPressed(b) return self.pressed[b] == true end
  function i:isDown() return false end
  return i
end

local function arenaGame(w)
  local g = w.game
  g.input = input()
  g.returns = {}
  g.left = 0
  g.returnToLauncher = function(o) g.returns[#g.returns + 1] = o end
  g.leaveArena = function() g.left = g.left + 1 end
  return g
end

local function mon(species, moves)
  return H.legal({ species = species, level = 40, moves = moves,
    ivs = { hp = 15, atk = 15, def = 15, spe = 15, spa = 15, spd = 15 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, item = 0 })
end

local PROFILE = { engine = 3, version = "firered", kind = "vanilla", rulesetId = "g3_single", rule = { partySize = 6 } }

local function arenaSpec(relay, seat, party, done)
  return {
    profile = PROFILE, role = seat == nil and "spectator" or (seat == 0 and "host" or "guest"),
    seat = seat, seats = 2, seed = relay.seed, match = relay.match, room = relay.room,
    players = relay.players, myParty = party and H.pack(party) or nil,
    session = relay:session(seat), client = relay:client(), mode = "single",
    headless = true, autoFight = true, onDone = done,
  }
end

local function newArena(w, spec)
  return H.run(w, function()
    local ArenaState = require("src.ui.game3.arena_state")
    return ArenaState.new(arenaGame(w), spec)
  end)
end

local function step(w, arena)
  H.run(w, function() arena:update(1 / 60) end)
end

print("[test] 1. two arena states and a spectator play one match to the end over the relay")
do
  local relay = H.relay({ seed = 0xABCDE, seats = 2 })
  local w0 = H.newWorld("seat0", { name = "RED", trainerId = 1, gender = 0, party = {}, bag = {} })
  local w1 = H.newWorld("seat1", { name = "LEAF", trainerId = 2, gender = 1, party = {}, bag = {} })
  local ws = H.newWorld("spectator", { name = "WATCH", trainerId = 3, gender = 0, party = {}, bag = {} })
  local done = { [0] = {}, [1] = {}, s = {} }
  local s0 = arenaSpec(relay, 0, { mon(6, { 10 }), mon(25, { 84 }) }, function(r) table.insert(done[0], r) end)
  local s1 = arenaSpec(relay, 1, { mon(9, { 33 }), mon(1, { 33 }) }, function(r) table.insert(done[1], r) end)
  local a0 = newArena(w0, s0)
  local a1 = newArena(w1, s1)
  local ss = arenaSpec(relay, nil, nil, function(r) table.insert(done.s, r) end)
  local as = newArena(ws, ss)
  eq(a0.stage, "linking", "seat 0 starts linking")
  eq(as.spectator, true, "the third state is a spectator")
  for _ = 1, 20000 do
    step(w0, a0)
    step(w1, a1)
    step(ws, as)
    relay:tick()
    if a0.done and a1.done and as.done then break end
  end
  check(a0.done and a1.done and as.done, "all three arena states left")
  eq(#done[0], 1, "seat 0 onDone ran exactly once")
  eq(#done[1], 1, "seat 1 onDone ran exactly once")
  local mirror = { win = "lose", lose = "win", draw = "draw" }
  eq(mirror[done[0][1]], done[1][1], "their results mirror")
  eq(done.s[1], "ended", "the spectator ended with ended")
  eq(#w0.reports, 1, "seat 0 reported once")
  eq(w0.reports[1], done[0][1], "with its own result")
  eq(#w1.reports, 1, "seat 1 reported once")
  eq(#ws.reports, 0, "the spectator never reports")
  eq(#w0.game.returns, 1, "seat 0 returned to the launcher once")
  eq(w0.game.returns[1] and w0.game.returns[1].tab, "online", "on the online tab")
  eq(w0.game.left, 1, "and left the arena phase once")
  check(s0.session.left and s1.session.left and ss.session.left, "every room session was left")
  local byes = 0
  for _, row in ipairs(relay.log) do if row.msg.type == "game3_bye" then byes = byes + 1 end end
  check(byes >= 1, "the link closed with game3_bye before the room was left")
end

print("[test] 2. an arena with no seed from the relay shows the failure and leaves with error")
do
  local relay = H.relay({ seed = 5, seats = 2 })
  relay.seed = nil
  local w0 = H.newWorld("seat0", { name = "RED", trainerId = 1, gender = 0, party = {}, bag = {} })
  local results = {}
  local spec = arenaSpec(relay, 0, { mon(6, { 10 }) }, function(r) results[#results + 1] = r end)
  spec.seed = nil
  local a0 = newArena(w0, spec)
  eq(a0.stage, "failed", "the arena shows the failure")
  check(type(a0.message) == "string" and a0.message ~= "", "with a message")
  for _ = 1, 5 do step(w0, a0) end
  eq(#results, 0, "nothing is reported while the failure is on screen")
  w0.game.input.pressed.a = true
  step(w0, a0)
  step(w0, a0)
  eq(results[1], "error", "A dismisses it with error")
  eq(#results, 1, "exactly once")
  eq(#w0.game.returns, 1, "back to the launcher")
end

print("[test] 3. a peer that never arrives can be cancelled with B once the wait is long")
do
  local relay = H.relay({ seed = 9, seats = 2 })
  local w0 = H.newWorld("seat0", { name = "RED", trainerId = 1, gender = 0, party = {}, bag = {} })
  local results = {}
  local a0 = newArena(w0, arenaSpec(relay, 0, { mon(6, { 10 }) }, function(r) results[#results + 1] = r end))
  local ArenaStateCancel = H.run(w0, function() return require("src.ui.game3.arena_state").CANCEL_FRAMES end)
  for _ = 1, ArenaStateCancel do step(w0, a0) end
  eq(a0.stage, "linking", "still waiting for the other seat")
  w0.game.input.pressed.b = true
  step(w0, a0)
  step(w0, a0)
  eq(results[1], "ended", "B leaves with ended")
  check(a0.done, "and the state is gone")
end

local function peek(w)
  return H.run(w, function()
    local LB = require("src.core.game3.link.battle")
    return LB.endReason
  end)
end

print("[test] 4. a seat still on the last turn keeps its result when the winner leaves the room")
do
  local relay = H.relay({ seed = 0xABCDE, seats = 2, lag = { [1] = 2 } })
  local w0 = H.newWorld("seat0", { name = "RED", trainerId = 1, gender = 0, party = {}, bag = {} })
  local w1 = H.newWorld("seat1", { name = "LEAF", trainerId = 2, gender = 1, party = {}, bag = {} })
  local done = { [0] = {}, [1] = {} }
  local s0 = arenaSpec(relay, 0, { mon(6, { 10 }), mon(25, { 84 }) }, function(r) table.insert(done[0], r) end)
  local s1 = arenaSpec(relay, 1, { mon(9, { 33 }), mon(1, { 33 }) }, function(r) table.insert(done[1], r) end)
  s1.headless = false
  local a0 = newArena(w0, s0)
  local a1 = newArena(w1, s1)
  local lagged = false
  for _ = 1, 30000 do
    step(w0, a0)
    step(w1, a1)
    if a0.done and not a1.done then lagged = true end
    relay:tick()
    if a0.done and a1.done then break end
  end
  check(a0.done and a1.done, "both arena states left")
  check(lagged, "seat 0 left the room while seat 1 was still finishing")
  local mirror = { win = "lose", lose = "win", draw = "draw" }
  check(done[0][1] == "win" or done[0][1] == "lose", "seat 0 has a winner (" .. tostring(done[0][1]) .. ")")
  eq(done[1][1], mirror[done[0][1]], "seat 1 keeps the mirrored result")
  eq(w1.reports[1], mirror[w0.reports[1]], "and reports it")
  check(peek(w1) ~= "peer_dropped", "seat 1 is not ended as a dropped peer")
end

print("[test] 5. a rendered spectator behind the seats replays to the end after both seats leave")
do
  local relay = H.relay({ seed = 0xABCDE, seats = 2, lag = { spectator = 2 } })
  local w0 = H.newWorld("seat0", { name = "RED", trainerId = 1, gender = 0, party = {}, bag = {} })
  local w1 = H.newWorld("seat1", { name = "LEAF", trainerId = 2, gender = 1, party = {}, bag = {} })
  local ws = H.newWorld("spectator", { name = "WATCH", trainerId = 3, gender = 0, party = {}, bag = {} })
  local done = { [0] = {}, [1] = {}, s = {} }
  local a0 = newArena(w0, arenaSpec(relay, 0, { mon(6, { 10 }), mon(25, { 84 }) }, function(r) table.insert(done[0], r) end))
  local a1 = newArena(w1, arenaSpec(relay, 1, { mon(9, { 33 }), mon(1, { 33 }) }, function(r) table.insert(done[1], r) end))
  local ss = arenaSpec(relay, nil, nil, function(r) table.insert(done.s, r) end)
  ss.headless = false
  local as = newArena(ws, ss)
  local reason, lagged
  for _ = 1, 30000 do
    step(w0, a0)
    step(w1, a1)
    if not as.done then
      step(ws, as)
      reason = peek(ws) or reason
      if a0.done and a1.done then lagged = true end
    end
    relay:tick()
    if a0.done and a1.done and as.done then break end
  end
  check(a0.done and a1.done and as.done, "all three arena states left")
  check(lagged, "both seats left while the spectator was still replaying")
  eq(reason, nil, "the spectator is not cut off")
  eq(done.s[1], "ended", "the spectator ends with ended")
end

if failed == 0 then
  print("[pass] link3 arena state")
  os.exit(0)
end
print("[fail] link3 arena state: " .. failed)
os.exit(1)

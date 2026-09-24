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
  print("[skip] Gen 3 link lockstep runs the real battle engine on ROM data: " .. tostring(Cache.reason))
  os.exit(0)
end
H.mountCache()

local function mon(species, level, extra)
  local Pokemon = require("src.core.game3.pokemon")
  local moves = Pokemon.movesAtLevel(species, level)
  local m = {
    species = species, level = level, moves = moves, personality = extra and extra.personality or 0,
    ivs = { hp = 20, atk = 20, def = 20, spe = 20, spa = 20, spd = 20 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    item = extra and extra.item or 0,
  }
  return H.legal(m)
end

local function session(name, trainerId, gender)
  return { name = name, trainerId = trainerId, gender = gender, party = {}, bag = {} }
end

local function singlesPolicy(w, st)
  local b = st.player
  local mon0 = b and b.mon or {}
  local usable = {}
  for i = 1, 4 do
    if mon0.moves and mon0.moves[i] and (tonumber(mon0.pp and mon0.pp[i]) or 0) > 0 then usable[#usable + 1] = i end
  end
  local slot = usable[((st.turn or 0) % math.max(1, #usable)) + 1] or 1
  w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot)
end

local function doublesPolicy(w, st)
  local sel = w.Battle._dblSel
  if not (sel and sel.active) then return end
  local id = sel.active
  local b = w.State.battler(st, id)
  local mon0 = b and b.mon or {}
  local slot = 1
  for i = 1, 4 do
    if mon0.moves and mon0.moves[i] and (tonumber(mon0.pp and mon0.pp[i]) or 0) > 0 then
      slot = i
      if (st.turn + id) % 2 == 0 then break end
    end
  end
  local target = w.State.isPresent(st, 1) and 1 or 3
  w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot, id, target)
end

local function runMatch(opts)
  local relay = H.relay({ seed = opts.seed, seats = 2, lag = opts.lag or {}, roomSeed = opts.seed })
  local partyA = opts.partyA
  local partyB = opts.partyB
  local w0 = H.newWorld("seat0", session("RED", 0x1234, 0))
  local w1 = H.newWorld("seat1", session("LEAF", 0x5678, 1))
  local ws = H.newWorld("spectator", session("WATCHER", 0x9999, 0))
  H.attachSeat(w0, relay, 0, { mode = opts.mode, myParty = H.pack(partyA),
    profile = { rule = {} } })
  H.attachSeat(w1, relay, 1, { mode = opts.mode, myParty = H.pack(partyB),
    profile = { rule = {} } })
  if not opts.lateSpectator then H.attachSpectator(ws, relay, { mode = opts.mode, profile = { rule = {} } }) end
  local policy = opts.mode == "double" and doublesPolicy or singlesPolicy
  local frames, spectating = 0, not opts.lateSpectator
  while frames < 20000 do
    frames = frames + 1
    for _ = 1, opts.stepsA or 1 do H.step(w0, policy) end
    for _ = 1, opts.stepsB or 1 do H.step(w1, policy) end
    if not spectating then
      local st = H.run(w0, function() return w0.Battle.getState() end)
      if st and (st.turn or 0) >= 3 then
        H.attachSpectator(ws, relay, { mode = opts.mode, profile = { rule = {} } })
        spectating = true
      end
    end
    if spectating then H.step(ws, nil) end
    relay:tick()
    if w0.result and w1.result and (ws.result or not spectating) then break end
  end
  return w0, w1, ws, relay, frames
end

local function hashesOf(w)
  return H.run(w, function()
    local out = {}
    for turn, value in pairs(w.LB._myHashes or {}) do out[turn] = value end
    return out
  end)
end

local function sameHashes(a, b)
  local n = 0
  for turn, value in pairs(a) do
    if b[turn] ~= nil then
      n = n + 1
      if b[turn] ~= value then return false, n, turn end
    end
  end
  return true, n
end

local MIRROR = { win = "lose", lose = "win", draw = "draw" }

local function verify(label, w0, w1, ws, relay)
  eq(w0.result ~= nil and w1.result ~= nil, true, label .. ": both seats finished")
  eq(MIRROR[w0.result], w1.result, label .. ": the results mirror (" .. tostring(w0.result) .. "/" .. tostring(w1.result) .. ")")
  local r0 = H.run(w0, function() return w0.LB.endReason end)
  local r1 = H.run(w1, function() return w1.LB.endReason end)
  eq(r0, nil, label .. ": seat 0 saw no desync")
  eq(r1, nil, label .. ": seat 1 saw no desync")
  local h0, h1, hs = hashesOf(w0), hashesOf(w1), hashesOf(ws)
  local ok, n, turn = sameHashes(h0, h1)
  check(ok and n >= 2, label .. ": every turn's digest matched across seats (" .. tostring(n) .. " turns" .. (turn and (", split at " .. turn) or "") .. ")")
  local okS, nS = sameHashes(h0, hs)
  check(okS and nS >= 1, label .. ": the spectator's own simulation digested the same (" .. tostring(nS) .. " turns)")
  eq(ws.result, "ended", label .. ": the spectator watched to the end")
  eq(#w0.reports, 1, label .. ": seat 0 reported once")
  eq(#w1.reports, 1, label .. ": seat 1 reported once")
  eq(MIRROR[w0.reports[1]], w1.reports[1], label .. ": and the reports mirror")
  eq(#ws.reports, 0, label .. ": the spectator never reports")
  local spectatorSent = false
  for _, row in ipairs(relay.log) do if row.seat == nil then spectatorSent = true end end
  check(not spectatorSent, label .. ": the spectator never sent a message")
  local kinds = {}
  for _, row in ipairs(relay.log) do kinds[row.msg.type] = (kinds[row.msg.type] or 0) + 1 end
  check((kinds.game3_battle_hash or 0) >= 4, label .. ": hashes crossed the relay")
  check((kinds.game3_battle_outcome or 0) == 2, label .. ": each seat sent one game3_battle_outcome")
  local st0 = H.run(w0, function() return w0.Battle.getState() end)
  local stS = H.run(ws, function() return ws.Battle.getState() end)
  local hp0, hpS = {}, {}
  for i, m in ipairs(st0.playerParty) do hp0[i] = tonumber(m.hp) end
  for i, m in ipairs(stS.playerParty) do hpS[i] = tonumber(m.hp) end
  eq(table.concat(hp0, ","), table.concat(hpS, ","), label .. ": the spectator's view of seat 0's party ends the same")
end

print("[test] 1. a singles arena match over the relay, both seats and a spectator")
do
  local w0, w1, ws, relay = runMatch({
    seed = 0x13579, mode = "single",
    partyA = { mon(6, 50), mon(25, 50), mon(131, 50) },
    partyB = { mon(9, 50), mon(3, 50), mon(143, 50) },
  })
  verify("singles", w0, w1, ws, relay)
end

print("[test] 2. the same with lag and uneven frame rates on each side")
do
  local w0, w1, ws, relay = runMatch({
    seed = 0x2468A, mode = "single", lag = { [0] = 2, [1] = 0, spectator = 3 }, stepsA = 3, stepsB = 1,
    partyA = { mon(94, 50), mon(65, 50) },
    partyB = { mon(68, 50), mon(59, 50) },
  })
  verify("singles lag", w0, w1, ws, relay)
end

print("[test] 3. a doubles arena match with a spectator")
do
  local w0, w1, ws, relay = runMatch({
    seed = 0x5A5A5, mode = "double",
    partyA = { mon(6, 50), mon(9, 50), mon(3, 50) },
    partyB = { mon(130, 50), mon(143, 50), mon(65, 50) },
  })
  verify("doubles", w0, w1, ws, relay)
end

print("[test] 4. a spectator who joins at turn 3 replays the log and catches up")
do
  local w0, w1, ws, relay = runMatch({
    seed = 0x777, mode = "single", lateSpectator = true,
    partyA = { mon(149, 50), mon(26, 50) },
    partyB = { mon(248, 50), mon(59, 50) },
  })
  verify("late spectator", w0, w1, ws, relay)
end

if failed == 0 then
  print("[pass] link3 lockstep")
  os.exit(0)
end
print("[fail] link3 lockstep: " .. failed)
os.exit(1)

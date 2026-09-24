#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

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

local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local MG = require("src.core.game3.minigames.common")
local Records = require("src.ui.game3.minigame_records")
local Countdown = require("src.ui.game3.minigames.common_countdown")

local ROOM = "r0123456789abcdef"

local Hub = {}
Hub.__index = Hub

function Hub.new(n)
  local self = setmetatable({
    order = {}, inbox = {}, present = {}, online = {}, leader = 0, epoch = 1,
    log = {}, dropped = {}, names = {},
  }, Hub)
  for s = 0, n - 1 do
    self.order[#self.order + 1] = s
    self.inbox[s] = {}
    self.present[s] = true
    self.online[s] = true
    self.names[s] = ({ "RED", "BLUE", "LEAF", "GOLD", "KRIS" })[s + 1]
  end
  return self
end

function Hub:playersList()
  local out = {}
  for _, s in ipairs(self.order) do
    if self.present[s] then
      out[#out + 1] = { id = ("%08x"):format(0xa0 + s), name = self.names[s], seat = s,
                        online = self.online[s], ready = true }
    end
  end
  return out
end

local function wireCopy(msg)
  local decoded = Json.decode(Json.encode(msg))
  return Wire.sanitize(decoded)
end

function Hub:deliver(to, msg)
  if not self.present[to] then return end
  local q = self.inbox[to]
  q[#q + 1] = wireCopy(msg)
  q[#q].seat = msg.seat
  q[#q].relay = msg.relay
end

function Hub:route(from, msg)
  if not self.present[from] then return end
  local inner = wireCopy(msg)
  if not inner then
    self.dropped[#self.dropped + 1] = { from = from, type = msg.type, why = "schema" }
    return
  end
  if #Json.encode(msg) > ((msg.type == MG.MSG.RESULT) and 1024 or 512) then
    self.dropped[#self.dropped + 1] = { from = from, type = msg.type, why = "cap" }
    return
  end
  if inner.type == MG.MSG.STATE and from ~= self.leader then
    self.dropped[#self.dropped + 1] = { from = from, type = msg.type, why = "not_leader" }
    return
  end
  inner.seat = from
  self.log[#self.log + 1] = { from = from, type = inner.type }
  for _, s in ipairs(self.order) do
    if s ~= from then self:deliver(s, inner) end
  end
end

function Hub:migrate(prev)
  local nextSeat
  for _, s in ipairs(self.order) do
    if s > prev and self.present[s] and self.online[s] then nextSeat = s break end
  end
  if nextSeat == nil then
    for _, s in ipairs(self.order) do
      if s ~= prev and self.present[s] and self.online[s] then nextSeat = s break end
    end
  end
  self.leader = nextSeat
  self.epoch = self.epoch + 1
  local msg = { type = MG.MSG.LEADER, seat = nextSeat, prev = prev, epoch = self.epoch, relay = true }
  for _, s in ipairs(self.order) do self:deliver(s, msg) end
end

function Hub:drop(seat)
  self.present[seat] = false
  self.inbox[seat] = {}
  if seat == self.leader then self:migrate(seat) end
end

function Hub:session(seat)
  local hub = self
  local rs = { paired = true, closed = false, left = false, target = ROOM }
  function rs:send(msg) hub:route(seat, msg) end
  function rs:poll()
    local q = hub.inbox[seat]
    hub.inbox[seat] = {}
    return q
  end
  function rs:players() return hub:playersList() end
  function rs:close()
    self.left = true
    self.closed = true
    hub:drop(seat)
  end
  return rs
end

function Hub:client(seat)
  local hub = self
  return {
    state = function() return hub.present[seat] and "online" or "offline" end,
    room = function()
      if not hub.present[seat] then return nil end
      return { room = ROOM, leader = hub.leader, players = hub:playersList() }
    end,
  }
end

local TestGame = { id = "test", MIN = 2, MAX = 5, END_FRAME = 300 }
TestGame.__index = TestGame

function TestGame.loadArt() return {} end

function TestGame.new(ctx)
  local sim = setmetatable({
    ctx = ctx, f = 0, scores = {}, last = {}, presses = 0, predicted = nil,
    leader = ctx.leader, becameLeader = 0, applied = 0,
  }, TestGame)
  for i = 1, 5 do sim.scores[i] = 0 sim.last[i] = 0 end
  return sim
end

function TestGame:leaderStep(inputs, present)
  for s = 0, 4 do
    local i = inputs[s + 1]
    if present[s + 1] and type(i) == "number" and i > self.last[s + 1] then
      self.scores[s + 1] = self.scores[s + 1] + (i - self.last[s + 1])
      self.last[s + 1] = i
    end
  end
  self.f = self.f + 1
end

function TestGame:snapshot()
  return { f = self.f, sc = { unpack(self.scores) }, la = { unpack(self.last) } }
end

function TestGame:applySnapshot(s, f)
  self.f = s.f
  for i = 1, 5 do
    self.scores[i] = s.sc[i] or 0
    self.last[i] = s.la[i] or 0
  end
  self.applied = self.applied + 1
end

function TestGame:localInput(input)
  if input and input:wasPressed("a") then self.presses = self.presses + 1 end
  return self.presses
end

function TestGame:predict(i) self.predicted = i end

function TestGame:becomeLeader(last)
  if last then self:applySnapshot(last, last.f) end
  self.leader = true
  self.becameLeader = self.becameLeader + 1
end

function TestGame:update() end
function TestGame:draw() end
function TestGame:finished() return self.f >= TestGame.END_FRAME end

function TestGame:results()
  local results, powder = {}, {}
  for _, p in ipairs(self.ctx.players) do
    local sc = self.scores[p.seat + 1]
    results[#results + 1] = { seat = p.seat, score = sc, stats = { presses = sc } }
    powder[#powder + 1] = { seat = p.seat, amount = sc * 10 }
  end
  return { results = results, powder = powder }
end

function TestGame.applyResults(session, result, mySeat)
  for _, r in ipairs(result.results) do
    if r.seat == mySeat then Records.updatePokemonJump(session, r.score, r.score, 0) end
  end
end

local function inputFor(schedule)
  local input = { frame = 0 }
  function input:wasPressed(b) return b == "a" and schedule(self.frame) end
  function input:isDown() return false end
  return input
end

local function makeSeats(n, opts)
  opts = opts or {}
  local hub = Hub.new(n)
  local seats = {}
  local players = {}
  for s = 0, n - 1 do
    players[#players + 1] = { id = ("%08x"):format(0xa0 + s), name = hub.names[s], seat = s,
                              trainerId = 0x1000 + s, gender = s % 2 }
  end
  for s = 0, n - 1 do
    local session = { berryPowder = opts.powder or 0 }
    local spec = { game = "jump", session = hub:session(s), seat = s, seats = n, players = players,
                   seed = 424242, partySlot = 0 }
    local m = MG.Match.new(spec, {
      module = opts.module or TestGame,
      client = hub:client(s),
      partyMon = { species = 4, level = 10 },
      countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
      onResult = function(msg, match) MG.applyResults(session, msg, match.seat, opts.module or TestGame) end,
    })
    seats[s] = { match = m, session = session, input = inputFor(opts.schedule and opts.schedule(s)
      or function(f) return f % (7 + s) == 0 end) }
  end
  return hub, seats
end

local function stepAll(seats, n, hook)
  for _ = 1, n do
    for s = 0, #seats do
      local st = seats[s]
      if st and not st.gone then
        st.input.frame = st.input.frame + 1
        st.match:step(st.input)
      end
    end
    if hook and hook() then return end
  end
end

local function allDone(seats)
  for s = 0, #seats do
    local st = seats[s]
    if st and not st.gone and not st.match:finished() then return false end
  end
  return true
end

print("[test] 1. countdown timing matches minigame_countdown.c")
do
  local c = Countdown.new(120, 80, { playSe = function() end })
  local seen, order = {}, {}
  local frames = 0
  while c:step() do
    frames = frames + 1
    local d = c:digitShown()
    if d and not seen[d] then seen[d] = true order[#order + 1] = d end
  end
  eq(table.concat(order, ","), "3,2,1", "digits count down 3, 2, 1")
  eq(Countdown.totalFrames(), frames, "totalFrames is the run length")
  check(frames > 200 and frames < 300, "about four seconds at 60 Hz (" .. frames .. ")")
  local bounces = 0
  local c2 = Countdown.new(120, 80, { playSe = function(id) if id == 50 then bounces = bounces + 1 end end })
  while c2:step() do end
  eq(bounces, 9, "SE_BALL_BOUNCE_2 per digit plus three per START half")
end

print("[test] 2. three seats: start, net loop, results agreement")
do
  local hub, seats = makeSeats(3)
  stepAll(seats, 3)
  eq(seats[0].match.phase, "countdown", "leader started once every seat was ready")
  eq(seats[1].match.phase, "countdown", "member 1 got game3_mg_start")
  eq(seats[2].match.phase, "countdown", "member 2 got game3_mg_start")
  local startPlayers = seats[2].match.startPlayers
  eq(#startPlayers, 3, "start carries three players")
  eq(startPlayers[2].species, 4, "each player's species comes from its game3_mg_ready")
  eq(startPlayers[3].trainerId, 0x1002, "trainer ids ride game3_mg_start")
  eq(seats[1].match.seed, 424242, "the relay seed is the game seed")
  local stateSends, inputSends = 0, 0
  local maxInputBurst = 0
  local window = {}
  stepAll(seats, 2000, function()
    return allDone(seats)
  end)
  for _, e in ipairs(hub.log) do
    if e.type == MG.MSG.STATE then stateSends = stateSends + 1 end
    if e.type == MG.MSG.INPUT then inputSends = inputSends + 1 end
  end
  eq(seats[0].match.phase, "done", "leader done")
  eq(seats[1].match.phase, "done", "member 1 done")
  eq(seats[2].match.phase, "done", "member 2 done")
  eq(stateSends, math.floor(TestGame.END_FRAME / MG.STATE_EVERY), "one state every 3rd leader frame")
  check(inputSends > 0, "members sent inputs")
  local r0 = Json.encode(seats[0].match.result.results)
  eq(Json.encode(seats[1].match.result.results), r0, "member 1 results equal the leader's")
  eq(Json.encode(seats[2].match.result.results), r0, "member 2 results equal the leader's")
  local res = seats[0].match.result.results
  for s = 0, 2 do
    local sim = seats[s].match.sim
    local made = seats[s].match.lastLocal
    check(res[s + 1].score <= made and res[s + 1].score >= made - 1,
      "seat " .. s .. " score counts its presses up to the final frames (" .. res[s + 1].score .. "/" .. made .. ")")
    check(res[s + 1].score > 0, "seat " .. s .. " scored")
    eq(seats[s].session.berryPowder, res[s + 1].score * 10, "seat " .. s .. " got its own Berry Powder")
    eq(seats[s].session.pokemonJumpRecords.bestJumpScore, res[s + 1].score, "seat " .. s .. " record written")
    check(sim.applied > 0 or s == 0, "seat " .. s .. " rendered from leader states")
  end
  local byes = 0
  for _, e in ipairs(hub.log) do if e.type == MG.MSG.BYE then byes = byes + 1 end end
  eq(byes, 3, "every seat said game3_mg_bye")
  eq(#hub.dropped, 0, "nothing the relay would drop")
end

print("[test] 3. member inputs are coalesced to <= 20/s")
do
  local hub, seats = makeSeats(2, { schedule = function(s)
    if s == 1 then return function() return true end end
    return function() return false end
  end })
  stepAll(seats, 3 + Countdown.totalFrames() + 60)
  local sends = {}
  for _, e in ipairs(hub.log) do
    if e.type == MG.MSG.INPUT then sends[#sends + 1] = e end
  end
  check(#sends <= 21 and #sends >= 18, "60 frames of mashing sent about 20 inputs (" .. #sends .. ")")
  local m = seats[1].match
  eq(m.sim.predicted, m.lastLocal, "own input is predicted immediately")
end

print("[test] 4. leader inputs apply through the 2-frame buffer")
do
  local hub, seats = makeSeats(2, { schedule = function() return function() return false end end })
  stepAll(seats, 3 + Countdown.totalFrames() + 1)
  local leader = seats[0].match
  eq(leader.phase, "play", "leader in play")
  local f0 = leader.f
  leader:handle({ type = MG.MSG.INPUT, seat = 1, f = 10, i = 5 })
  leader:step(seats[0].input)
  eq(leader.sim.scores[2], 0, "not applied on the arrival frame")
  leader:step(seats[0].input)
  eq(leader.sim.scores[2], 0, "not applied one frame later")
  leader:step(seats[0].input)
  eq(leader.sim.scores[2], 5, "applied two frames after arrival")
  check(leader.f == f0 + 3, "three leader frames ran")
end

print("[test] 5. leader drop mid-game migrates leadership to the next seat")
do
  local hub, seats = makeSeats(3)
  local dropAt = 3 + Countdown.totalFrames() + 120
  local frame = 0
  local before
  stepAll(seats, dropAt, function()
    frame = frame + 1
  end)
  eq(seats[0].match.phase, "play", "game running")
  before = { seats[1].match.sim.scores[2], seats[2].match.sim.scores[3] }
  seats[0].gone = true
  hub:drop(0)
  eq(hub.leader, 1, "relay picked seat 1")
  stepAll(seats, 1)
  check(seats[1].match:isLeader(), "seat 1 is the leader now")
  eq(seats[2].match.leader, 1, "seat 2 follows seat 1")
  eq(seats[1].match.sim.becameLeader, 1, "sim:becomeLeader ran once on seat 1")
  eq(seats[1].match.epoch, seats[2].match.epoch, "both seats agree on the epoch")
  check(seats[1].match.epoch >= 2, "epoch advanced")
  local stale = { type = MG.MSG.STATE, seat = 0, f = 99999, e = 1, s = { f = 1, sc = { 999, 999, 999, 0, 0 }, la = {} } }
  seats[2].match:handle(stale)
  check(seats[2].match.sim.scores[1] ~= 999, "a state from the old epoch is ignored")
  stepAll(seats, 2000, function() return allDone(seats) end)
  eq(seats[1].match.phase, "done", "new leader finished")
  eq(seats[2].match.phase, "done", "member finished")
  local r1 = Json.encode(seats[1].match.result.results)
  eq(Json.encode(seats[2].match.result.results), r1, "survivors agree on the results")
  local res = seats[1].match.result.results
  eq(#res, 3, "results still name all three start seats")
  check(res[2].score >= before[1], "seat 1 kept its score across the migration")
  check(res[3].score >= before[2], "seat 2 kept its score across the migration")
  check(res[3].score >= seats[2].match.lastLocal - 1, "seat 2's presses after the migration counted")
  eq(seats[0].session.berryPowder, 0, "the dropped leader wrote no records")
  check(seats[2].session.berryPowder > 0, "survivor got Berry Powder")
  local notLeader = 0
  for _, d in ipairs(hub.dropped) do if d.why == "not_leader" then notLeader = notLeader + 1 end end
  eq(notLeader, 0, "no member ever sent a state")
end

print("[test] 6. dropping below MIN is a communication error with no records")
do
  local hub, seats = makeSeats(2)
  stepAll(seats, 3 + Countdown.totalFrames() + 30)
  seats[1].gone = true
  hub:drop(1)
  stepAll(seats, 2)
  eq(seats[0].match.phase, "error", "leader errors out")
  eq(seats[0].match.why, "dropped", "because too few seats remain")
  eq(seats[0].session.berryPowder, 0, "no Berry Powder")
  eq(seats[0].session.pokemonJumpRecords, nil, "no records")
end

print("[test] 7. leader drop during the ready handshake")
do
  local hub, seats = makeSeats(3)
  seats[0].gone = true
  hub:drop(0)
  stepAll(seats, 3)
  eq(seats[1].match.leader, 1, "seat 1 leads")
  eq(seats[1].match.phase, "countdown", "seat 1 started the game")
  eq(seats[2].match.phase, "countdown", "seat 2 got the start")
  eq(#seats[2].match.startPlayers, 2, "only the two present seats play")
end

print("[test] 8. a resumed old leader becomes a member")
do
  local hub, seats = makeSeats(3)
  stepAll(seats, 3 + Countdown.totalFrames() + 10)
  local m0 = seats[0].match
  m0.sim.becomeMember = function(self) self.member = true end
  m0:handle({ type = MG.MSG.LEADER, seat = 1, prev = 0, epoch = 2, relay = true })
  check(not m0:isLeader(), "seat 0 stepped down")
  check(m0.sim.member, "sim:becomeMember ran")
end

print("[test] 8b. game3_mg_ready names beat the spec's relay names")
do
  local hub, seats = makeSeats(2)
  local m = seats[0].match
  m.me = { name = "RED", trainerId = 0x1234, gender = 0 }
  local ready = m:readyPayload()
  eq(ready.name, "RED", "ready carries the cart name")
  eq(ready.trainerId, 0x1234, "and the trainer id")
  m.ready[1] = { species = 85, name = "LEAF", trainerId = 77, gender = 1 }
  local list = m:startPlayersList({ 1 })
  eq(list[1].name, "LEAF", "start uses the ready name")
  eq(list[1].trainerId, 77, "and its trainer id")
  eq(list[1].gender, 1, "and gender")
  m.ready[1] = { species = 85 }
  list = m:startPlayersList({ 1 })
  eq(list[1].name, "BLUE", "without one the spec name stands")
end

print("[test] 9. relay limits: snapshot and result fit the caps")
do
  local sim = TestGame.new({ players = {}, leader = true })
  local bytes = #Json.encode({ type = MG.MSG.STATE, f = 99999, e = 3, s = sim:snapshot() })
  check(bytes <= 512, "state packet " .. bytes .. " bytes <= 512")
end

print("[test] 10. records and Berry Powder")
do
  local s = { berryPowder = 99990 }
  eq(Records.giveBerryPowder(s, 5), true, "under the cap")
  eq(Records.giveBerryPowder(s, 50), false, "over the cap reports FALSE")
  eq(s.berryPowder, 99999, "Berry Powder caps at 99999")
  local t = {}
  eq(Records.updateBerryCrush(t, 3, 0x0280), true, "3-player speed recorded")
  eq(t.berryCrushPressingSpeeds[2], 0x0280, "slot 2 holds 3 players")
  eq(Records.updateBerryCrush(t, 3, 0x0100), false, "slower is not a record")
  eq(Records.updatePokemonJump(t, 100000, 12, 3), true, "jumps in a row is a record")
  eq(t.pokemonJumpRecords.bestJumpScore, 0, "a score over 99990 is not stored")
  eq(t.pokemonJumpRecords.jumpsInRow, 12, "jumps in a row stored")
  Records.incrementPokemonJumpMaxPlayerGames(t)
  eq(t.pokemonJumpRecords.gamesWithMaxPlayers, 1, "max player games counted")
  eq(Records.updateDodrio(t, 2000000, 20000, 7), true, "dodrio record")
  eq(t.dodrioBerryPickingRecords.bestScore, 999990, "score clamps to 999990")
  eq(t.dodrioBerryPickingRecords.berriesPicked, 9999, "berries clamp to 9999")
  eq(t.dodrioBerryPickingRecords.berriesPickedInRow, 7, "berries in a row")
  local session = { berryPowder = 0 }
  MG.applyResults(session, { results = {}, powder = { { seat = 1, amount = 30 }, { seat = 2, amount = 7 } } }, 2, nil)
  eq(session.berryPowder, 7, "applyResults gives only my seat's powder")
end

print("[test] 11. MG.arm launches on the waitstate and returns after exit")
do
  local ctx = {}
  local hub = Hub.new(2)
  package.loaded["src.online.Client"] = hub:client(0)
  local exits = {}
  local t = 0
  local realClock = MG.clock
  MG.clock = function() return t end
  local realJump = package.loaded[MG.GAMES.jump]
  package.loaded[MG.GAMES.jump] = { MIN = 2, MAX = 5, new = function() return {} end,
    loadArt = function() return nil, "pokemon_jump/manifest.lua is missing from the cache" end }
  local rs = hub:session(0)
  local spec = { game = "jump", session = rs, seat = 0, seats = 2,
                 players = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" } },
                 seed = 7, returnToMap = false, onExit = function(r) exits[#exits + 1] = r end }
  eq(MG.arm(ctx, spec), true, "arm returns true")
  check(type(ctx.stateWait) == "function", "arm waits on the script's waitstate")
  eq(MG.isActive(), false, "nothing runs before the waitstate")
  local poll = ctx.stateWait
  eq(poll(), false, "first poll launches")
  check(MG.isActive(), "minigame running")
  for _ = 1, 600 do
    t = t + 1 / 60
    MG.update(1 / 60)
    if not MG.isActive() then break end
  end
  eq(MG.isActive(), false, "missing game art ends the run")
  eq(exits[1], "error", "onExit(error)")
  check(rs.left and rs.closed, "a run with no Match still leaves the relay room")
  eq(poll(), true, "the waitstate releases after exit")
  MG.clock = realClock
  package.loaded[MG.GAMES.jump] = realJump
  package.loaded["src.online.Client"] = nil
end

print("[test] 12. ChooseMonForWirelessMinigame and IsPokemonJumpSpeciesInParty")
do
  local vars = {}
  local session = { party = { { species = 85, level = 30 }, { species = 4, level = 5 },
                              { species = 4, level = 5, isEgg = true } } }
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
  package.loaded["src.core.game3.scripting.flags"] = {
    getVar = function(_, _, id) return vars[id] or 0 end,
    setVar = function(_, _, id, v) vars[id] = v end,
  }
  local shown = {}
  local PM = { cursor = 1, mode = "choose" }
  function PM.show(party, _, opts) shown[#shown + 1] = opts PM.opts = opts PM.mode = "choose" end
  function PM.close() local cb = PM.opts.onClose if cb then cb() end end
  function PM.showYesNo(text, cb) PM.mode = "yesno" PM.yes = cb PM.prompt = text end
  package.loaded["src.ui.game3.party_menu"] = PM
  package.loaded["src.core.game3.rom_text"] = { box = function(k) return k end, plain = function(k) return k end }
  MG._jumpMons = { [4] = 1, [7] = 0 }
  package.loaded["src.core.game3.scripting.natives_wireless"] = nil
  local Std = require("src.core.game3.scripting.stdscripts")
  local Wireless = require("src.core.game3.scripting.natives_wireless")
  local ctx = {}
  vars[0x8005] = 0
  Wireless.HANDLERS[Std.SPECIAL.IsPokemonJumpSpeciesInParty](ctx)
  eq(vars[0x800D], 1, "Charmander can jump")
  session.party[2].species = 85
  Wireless.HANDLERS[Std.SPECIAL.IsPokemonJumpSpeciesInParty](ctx)
  eq(vars[0x800D], 0, "an egg and two Dodrio cannot")
  session.party[2].species = 4

  Wireless.HANDLERS[Std.SPECIAL.ChooseMonForWirelessMinigame](ctx)
  check(type(ctx.stateWait) == "function", "party menu waits on the waitstate")
  eq(PM.opts.mode, "choose", "cart party menu opened")
  check(PM.opts.validate(1) ~= nil, "Dodrio cannot enter Pokemon Jump")
  check(PM.opts.validate(3) ~= nil, "an egg cannot enter")
  eq(PM.opts.validate(2), nil, "Charmander can")
  eq(PM.opts.minigameEligible(2, session.party[2]), true, "ABLE marker for Charmander")
  PM.close()
  PM.opts.onSelect(2)
  eq(ctx.stateWait(), true, "waitstate released once the menu closed with a pick")
  eq(vars[0x8004], 1, "VAR_0x8004 = the 0-based slot")
  eq(MG.partySlot, 1, "MG remembers the slot for the group spec")

  vars[0x8005] = 1
  ctx = {}
  Wireless.HANDLERS[Std.SPECIAL.ChooseMonForWirelessMinigame](ctx)
  eq(PM.opts.validate(1), nil, "Dodrio can pick berries")
  check(PM.opts.validate(2) ~= nil, "Charmander cannot")
  PM.close()
  eq(ctx.stateWait(), false, "B does not release the waitstate")
  eq(PM.mode, "yesno", "B asks to cancel participation")
  eq(PM.prompt, "gText_CancelParticipation", "with the cart's text")
  PM.yes(false)
  eq(PM.mode, "choose", "NO goes back to the list")
  eq(ctx.stateWait(), false, "still waiting")
  PM.close()
  eq(ctx.stateWait(), false, "asked again")
  PM.yes(true)
  eq(ctx.stateWait(), true, "YES releases the waitstate")
  eq(vars[0x8004], 6, "YES cancels with PARTY_SIZE")
  eq(MG.partySlot, nil, "no slot remembered")

  package.loaded["src.core.game3.runtime"] = nil
  package.loaded["src.core.game3.scripting.flags"] = nil
  package.loaded["src.ui.game3.party_menu"] = nil
  package.loaded["src.core.game3.rom_text"] = nil
  package.loaded["src.core.game3.scripting.natives_wireless"] = nil
  MG._jumpMons = nil
end

print("[test] 13. ROM tables and cart text (needs the cache)")
do
  local Cache = require("tests.game3_cache")
  local bundle = Cache.bundle("pokemon_jump/tables.lua")
  if not bundle then
    print("[skip] cache-backed checks: " .. tostring(Cache.reason))
  else
    MG._jumpMons = nil
    check(MG.isJumpSpecies(4), "Charmander is in sPokeJumpMons")
    check(not MG.isJumpSpecies(85), "Dodrio is not")
    local n = 0
    for _ in pairs(MG.jumpMons()) do n = n + 1 end
    eq(n, 100, "100 jump species from the ROM")
    local Art = require("src.ui.game3.minigames.common_art")
    local art, err = Countdown.loadArt(Art.cache())
    check(art ~= nil, "countdown art loads from link/ (" .. tostring(err) .. ")")
    if art then
      eq(art.minigame_countdown_numbers.frames, 3, "three digits")
      eq(art.minigame_countdown_start.frame_w, 64, "START halves are 64 wide")
    end
    local Lobby = require("src.ui.game3.minigames.common_lobby")
    Lobby.showPlayers({}, { mode = "leader", capacity = { min = 1, max = 4 }, activity = 9 })
    eq(Lobby.group.min, 2, "leader capacity from members + 1")
    check(Lobby.modeText():find("1 player") ~= nil, "alone: 1 player needed (" .. Lobby.modeText() .. ")")
    check(Lobby.awaitingText():find("Awaiting") ~= nil, "awaiting communication")
    check(not Lobby.canStart(), "START needs another player")
    Lobby.showPlayers({ { name = "BLUE", trainerId = 1 } }, { mode = "leader", group = { min = 2, max = 5 }, activity = 9 })
    check(Lobby.modeText():find("2%-PLAYER") ~= nil, "two players: 2-PLAYER MODE (" .. Lobby.modeText() .. ")")
    check(Lobby.awaitingText():find("START") ~= nil, "press START when everyone's ready")
    check(Lobby.awaitingText():find(Lobby.activityName(), 1, true) ~= nil, "names the activity")
    check(Lobby.canStart(), "START allowed")
    local started = false
    Lobby._onConfirm = function() started = true end
    check(Lobby.confirm(), "confirm")
    check(started, "leader START fires onConfirm")
    Lobby.showPlayers({}, { mode = "leader", group = { min = 3, max = 5 }, activity = 11 })
    check(Lobby.modeText():find("2 players") ~= nil, "Dodrio alone: 2 players needed")
    local okMsg, Message = pcall(require, "src.ui.game3.message")
    if okMsg then
      Message.show("Please decide which of you will become the GROUP LEADER.", { stay = true })
      check(Message.isOpen(), "the script's leader prompt is up")
    end
    Lobby.showPlayers({ { slot = 1, name = "LEAF", started = true }, { slot = 2, name = "GOLD" } },
      { mode = "group", capacity = { activity = 10, min = 2, max = 5 } })
    check(Lobby.chooseText() ~= "", "joiner prompt from gTexts_UR_ChooseTrainer")
    if okMsg then check(not Message.isOpen(), "the group list reprints the textbox (union_room.c:1168)") end
    check(not Lobby.confirm(), "a started group plays SE_WALL_HIT")
    Lobby.move(1)
    local joined
    Lobby._onConfirm = function(slot) joined = slot end
    check(Lobby.confirm(), "join the open group")
    eq(joined, 2, "slot passed back")
    Lobby.reset()
  end
end

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] game3_minigame_common_test")

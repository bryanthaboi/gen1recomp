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
local R = require("src.core.game3.minigames.berry_crush.rules")
local Phys = require("src.core.game3.minigames.berry_crush.physics")

local ROOM = "r0123456789abcdef"

print("[test] 1. fixed-point helpers (berry_crush.c Q_24_8 / Q_N_S)")
do
  eq(R.trunc(-7, 2), -3, "C division truncates toward zero")
  eq(R.trunc(7, 0), 0, "division by zero reads 0 (agbcc __div0)")
  eq(R.s16(0x8000), -32768, "s16 wraps")
  eq(R.shr(-5, 1), -3, "arithmetic shift floors")
  eq(R.q24div(600 * 256, 60 * 256), 2560, "Q_24_8_div 600/60")
  eq(R.q24mul(1280, 25600), 128000, "Q_24_8_mul")
  eq(R.qnsDiv(7, R.qns(7, 127), 272), 7649, "berry drop var1")
  eq(R.berryIndex(133), 0, "CHERI is berry 0")
  eq(R.berryIndex(175), 42, "ENIGMA is berry 42")
  eq(R.berryIndex(176), nil, "176 is not a berry")
end

print("[test] 2. pressing speed, rankings, records (no tables)")
do
  eq(R.pressingSpeed(600, 100), 2560, "100 presses in 10 s = 10.00/s (Q24.8)")
  eq(R.pressingSpeed(900, 100), 1706, "100 presses in 15 s")
  eq(R.pressingSpeed(0, 100), 0, "zero time reads 0")
  local s0, r0, s1, r1 = R.rank({ 5, 7, 7 }, { 3, 1, 2 })
  eq(table.concat(s0, ","), "7,7,5", "presses sorted descending")
  eq(table.concat(r0, ","), "2,3,1", "bubble sort keeps the cart's tie order")
  eq(table.concat(s1, ","), "3,2,1", "random page sorted")
  eq(table.concat(r1, ","), "1,3,2", "random page player order")
  local st = R.newState(3)
  st.nb, st.nc, st.powder, st.timer = 3, 10, 90, 600
  st.pl[1].np, st.pl[1].mx, st.pl[1].ns = 10, 5, 4
  st.pl[2].np, st.pl[2].mx, st.pl[2].ns = 8, 8, 8
  st.pl[3].np = 0
  st.held = { 300, 700, 0 }
  local t = R.tabulate(st, R.RANDOM_NEATNESS)
  eq(t.silk, 65, "silkiness = 3 big / 10 checks -> 65")
  eq(t.powder, 175, "powder = 90 * 3 players * 65% (Q24.8)")
  eq(t.total, 18, "total presses")
  eq(t.random[1], 800, "neatness 5/10 = 50.00 (Q.4)")
  eq(t.random[2], 1600, "neatness 8/8 = 100.00")
  eq(t.random[3], 0, "no presses -> 0")
  local p = R.tabulate(st, R.RANDOM_POWER)
  eq(p.random[1], 800, "power: held 300 of 600 frames = 50%")
  eq(p.random[2], 1600, "power: held past the timer = 100%")
  local c = R.tabulate(st, R.RANDOM_COOPERATIVE)
  eq(c.random[1], 640, "cooperative 4/10 = 40%")
  local zero = R.newState(2)
  zero.nc = 0
  eq(R.tabulate(zero, 0).silk, 50, "no sparkle checks: division reads 0 -> 50")
  local Records = require("src.ui.game3.minigame_records")
  local session = {}
  check(Records.updateBerryCrush(session, 3, 2560), "first 3-player record")
  check(not Records.updateBerryCrush(session, 3, 2000), "a slower speed is not a record")
  eq(session.berryCrushPressingSpeeds[2], 2560, "3 players -> pressingSpeeds[1]")
end

print("[test] 3. link-state records round-trip")
do
  local q = {}
  R.encodeRecord({ t = 35999, d = 32, v = -2, fl = 0x7FFF, sa = 4, big = true, eg = true }, q)
  R.encodeRecord({ t = 1, d = 0, v = 3, fl = 6, sa = 0, big = false, eg = false }, q)
  local back = R.decodeRecords(Json.decode(Json.encode(q)))
  eq(#back, 2, "two records")
  eq(back[1].t, 35999, "timer")
  eq(back[1].v, -2, "negative vibration")
  check(back[1].big and back[1].eg and back[1].sa == 4, "big sparkle / end / sparkle amount")
  eq(R.recordFlags(back[2], 1), 6, "player 1 flags")
  eq(R.recordFlags({ fl = 6 + 48 }, 2), 6, "player 2 flags (3 bits each)")
end

print("[test] 4. sprite animation timing (sprite.c)")
do
  local sp = Phys.newImpact({ impactXOffset = 0, impactYOffset = -16 })
  Phys.startImpact(sp, 1, { impact_coords = { { 0, 0 }, { -1, 0 }, { 1, 1 } } })
  local frames = 0
  while not sp.invisible and frames < 100 do
    Phys.stepImpact(sp)
    frames = frames + 1
  end
  eq(frames, 14, "small impact: 3 frames x 4 then END, hidden on the next callback")
  local big = Phys.newImpact({ impactXOffset = 0, impactYOffset = -16 })
  Phys.startImpact(big, 5, { impact_coords = { { 0, 0 }, { -1, 0 }, { 1, 1 } } })
  eq(big.anim.num, 1, "sync flag -> big impact")
  eq(big.x2, 0, "impact offset from sImpactCoords[(5 % 4) - 1]")
  local n = Phys.dropFrames({ berryXOffset = -24, berryXDest = 16 })
  check(n > 20 and n < 60, "a berry falls from -16 to 112 in " .. n .. " frames")
  eq(Phys.dropFrames({ berryXOffset = 32, berryXDest = -8 }), n, "every seat's berry takes the same time")
end

local Cache = require("tests.game3_cache")
local bundle = Cache.bundle("berry_crush/tables.lua")
if not bundle then
  print("[skip] cache-backed checks: " .. tostring(Cache.reason))
  if failed > 0 then
    print(("[FAIL] %d check(s) failed"):format(failed))
    os.exit(1)
  end
  print("[PASS] game3_mg_berry_crush_test")
  os.exit(0)
end

local Art = require("src.ui.game3.minigames.common_art")
local G = require("src.core.game3.minigames.berry_crush")
local Sim = G.Sim
local Records = require("src.ui.game3.minigame_records")
local Bag = require("src.core.game3.bag")
local Countdown = require("src.ui.game3.minigames.common_countdown")

local art, artErr = G.loadArt(Art.cache())
check(art ~= nil, "berry_crush art + tables load from the cache (" .. tostring(artErr) .. ")")
if not art then
  print(("[FAIL] %d check(s) failed"):format(failed + 1))
  os.exit(1)
end
local T = art.tables

print("[test] 5. ROM tables match berry_crush.c")
do
  eq(table.concat(T.sync_press_bonus, ","), "0,1,2,3,5", "sSyncPressBonus")
  eq(table.concat(T.big_sparkle_thresholds, ","), "5,7,9,12", "sBigSparkleThresholds")
  eq(table.concat(T.sparkle_thresholds[1], ","), "2,4,6,7", "sSparkleThresholds 2 players")
  eq(table.concat(T.vibration[5], ","), "3,5,3,0", "sVibrationData 5 players")
  eq(table.concat(T.intro_outro_vibration[5], ","), "6,4,1,-2,-4,-2,0", "sIntroOutroVibrationData[4]")
  eq(#T.berry_data, 43, "43 berries")
  eq(T.berry_data[1].difficulty, 50, "CHERI difficulty")
  eq(T.player_coords[4].berryXOffset, 32, "sPlayerCoords[3]")
  eq(table.concat(T.player_id_to_pos_id[4], ","), "0,1,3,2,4", "sPlayerIdToPosId 5 players")
  eq(T.pressing_speed_table[8], 390625, "sPressingSpeedConversionTable")
  eq(T.digit_templates[1].x, 156, "timer minutes at x 156")
  check(art.namePal[1] ~= nil and art.namePal[4] ~= nil, "name colours from crusher.pal bank 8")
  check(art.bg and art.crusher_top and art.impact and art.sparkle and art.timer_digits, "sheets present")
  eq(art.impact.frames, 7, "impact frames")
  eq(art.sparkle.frames, 14, "sparkle frames")
end

print("[test] 6. leader frame: HandlePartnerInput / BuildLocalState / HandlePlayerInput")
do
  local st = R.newState(2)
  R.setBerries(st, T, { 0, 0 })
  eq(st.ta, 100, "two CHERIs: 100 presses target")
  eq(st.targetDepth, 800, "targetDepth = Q24.8(100 / 32)")
  eq(st.powder, 40, "berry powder base")
  local rec = R.leaderFrame(st, { true, true }, T)
  eq(st.tp, 3, "two synced presses + bonus 1")
  eq(st.pl[1].ns, 1, "synced press counted")
  eq(rec.fl, 6 + 6 * 8, "both players: hit flag 2 | sync 4")
  eq(rec.v, 3, "vibration from sVibrationData[1][1]")
  eq(st.nc, 0, "first big-sparkle check at timer 0")
  eq(rec.sa, 1, "3 presses in the window -> sparkle amount 1")
  check(not rec.eg, "not finished")
  local ended = false
  for _ = 1, 200 do
    st.timer = st.lastT
    rec = R.leaderFrame(st, { true, true }, T)
    if rec.eg then ended = true break end
  end
  check(ended, "reaching the target ends the game")
  eq(rec.d, 32, "crusher fully down")
  local amounts = {}
  local st2 = R.newState(5)
  R.setBerries(st2, T, { 42, 42, 42, 42, 42 })
  for f = 1, 900 do
    st2.timer = st2.lastT < 0 and 0 or st2.lastT
    local pressed = {}
    for p = 1, 5 do pressed[p] = (f + p) % (1 + (f % 4)) == 0 end
    local r = R.leaderFrame(st2, pressed, T)
    amounts[r.sa] = true
    if r.eg then break end
  end
  check(not amounts[2] and not amounts[3], "sparkle amount 2/3 unreachable (cart bug kept)")
end

local NOCD = function() return { step = function() return false end, draw = function() end } end

local function moduleFor(session, opts)
  opts = opts or {}
  local M = setmetatable({}, { __index = G })
  M.hooks = setmetatable({
    session = function() return session end,
    playSe = function(id) if opts.se then opts.se[#opts.se + 1] = id end end,
    playSong = function() end,
    pauseMusic = function() end,
    resumeMusic = function() end,
    textSpeed = function() return 2 end,
    tick = function() end,
    newCountdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
    pickBerry = function(sim, done)
      local list = Bag.listPocket(session.bag, "BERRY_POUCH")
      done(list[opts.pick or 1] and tonumber(list[opts.pick or 1].id) or nil)
    end,
    givePowder = function(s, amount)
      if opts.powder then opts.powder[#opts.powder + 1] = amount end
      return G.hooks.givePowder(s, amount)
    end,
    save = function() if opts.saves then opts.saves[1] = (opts.saves[1] or 0) + 1 end end,
  }, { __index = G.hooks })
  M.new = function(ctx) return Sim.new(M, ctx) end
  return M
end

local Hub = {}
Hub.__index = Hub

function Hub.new(n)
  local self = setmetatable({ order = {}, inbox = {}, present = {}, leader = 0, epoch = 1,
    dropped = {}, names = {}, maxState = 0 }, Hub)
  for s = 0, n - 1 do
    self.order[#self.order + 1] = s
    self.inbox[s] = {}
    self.present[s] = true
    self.names[s] = ({ "RED", "BLUE", "LEAF", "GOLD", "KRIS" })[s + 1]
  end
  return self
end

function Hub:playersList()
  local out = {}
  for _, s in ipairs(self.order) do
    if self.present[s] then
      out[#out + 1] = { id = ("%08x"):format(0xa0 + s), name = self.names[s], seat = s, online = true }
    end
  end
  return out
end

local function wireCopy(msg)
  return Wire.sanitize(Json.decode(Json.encode(msg)))
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
  local bytes = #Json.encode(msg)
  if msg.type == MG.MSG.STATE and bytes > self.maxState then self.maxState = bytes end
  if bytes > ((msg.type == MG.MSG.RESULT) and 1024 or 512) then
    self.dropped[#self.dropped + 1] = msg.type .. " cap " .. bytes
    return
  end
  local inner = wireCopy(msg)
  if not inner then
    self.dropped[#self.dropped + 1] = msg.type .. " schema"
    return
  end
  if inner.type == MG.MSG.STATE and from ~= self.leader then return end
  inner.seat = from
  for _, s in ipairs(self.order) do
    if s ~= from then self:deliver(s, inner) end
  end
end

function Hub:drop(seat)
  self.present[seat] = false
  self.inbox[seat] = {}
  if seat == self.leader then
    local nextSeat
    for _, s in ipairs(self.order) do
      if self.present[s] then nextSeat = s break end
    end
    self.leader = nextSeat
    self.epoch = self.epoch + 1
    local msg = { type = MG.MSG.LEADER, seat = nextSeat, prev = seat, epoch = self.epoch, relay = true }
    for _, s in ipairs(self.order) do self:deliver(s, msg) end
  end
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

local function makeInput(every, st)
  local input = { frame = 0 }
  function input:wasPressed(b)
    local sim = st.match and st.match.sim
    if sim and sim.stage == "yesno" and st.wantNo then
      if b == "down" then return sim.yesNo == 0 end
      return b == "a" and sim.yesNo == 1 and self.frame % every == 0
    end
    return b == "a" and self.frame % every == 0
  end
  function input:isDown(b) return b == "a" and self.frame % every < 2 end
  return input
end

local function makeGame(n, berriesBySeat, counts)
  local hub = Hub.new(n)
  local players = {}
  for s = 0, n - 1 do
    players[#players + 1] = { id = ("%08x"):format(0xa0 + s), name = hub.names[s], seat = s,
      trainerId = 0x1000 + s, gender = s % 2 }
  end
  local seats = {}
  for s = 0, n - 1 do
    local session = { berryPowder = 10, bag = Bag.new(), name = hub.names[s] }
    local count = counts and counts[s + 1] or 3
    Bag.add(session.bag, berriesBySeat[s + 1], count)
    local st = { session = session, se = {}, powder = {}, saves = {}, item = berriesBySeat[s + 1], count = count }
    local M = moduleFor(session, { se = st.se, powder = st.powder, saves = st.saves })
    local spec = { game = "crush", session = hub:session(s), seat = s, seats = n, players = players, seed = 777 }
    st.match = MG.Match.new(spec, {
      module = M, client = hub:client(s), art = art, countdown = NOCD,
      onResult = function(msg, match) MG.applyResults(session, msg, match.seat, M) end,
    })
    st.input = makeInput(4 + s, st)
    seats[s] = st
  end
  return hub, seats
end

local function step(seats, frames, hook)
  for _ = 1, frames do
    for s = 0, 4 do
      local st = seats[s]
      if st and not st.gone and not st.match:finished() then
        st.input.frame = st.input.frame + 1
        st.match:step(st.input)
      end
    end
    if hook and hook() then return true end
  end
  return false
end

local function allFinished(seats)
  for s = 0, 4 do
    local st = seats[s]
    if st and not st.gone and not st.match:finished() then return false end
  end
  return true
end

local function sum(list)
  local n = 0
  for _, v in ipairs(list) do n = n + v end
  return n
end

print("[test] 7. 3-seat game over the fake relay: two rounds, play again, no berries left")
do
  local hub, seats = makeGame(3, { 133, 140, 150 }, { 3, 3, 2 })
  local sawStages = {}
  local predictedImpact = false
  local firstTarget, firstBerries
  step(seats, 20000, function()
    for s = 0, 2 do
      local sim = seats[s].match.sim
      if sim then
        sawStages[sim.stage] = true
        if s == 1 and sim.stage == "play" and sim.predicted > 0 and not sim.impacts[sim.me].invisible then
          predictedImpact = true
        end
        if s == 0 and not firstTarget and sim.A.ph == Sim.PH.PLAY then
          firstTarget = sim.A.ta
        end
        if s == 1 and not firstBerries and sim.A.ph == Sim.PH.PLAY then
          firstBerries = table.concat(sim.A.berries, ",")
        end
      end
    end
    return allFinished(seats)
  end)
  check(allFinished(seats), "every seat finished (" .. tostring(seats[0].match.phase) .. "/"
    .. tostring(seats[1].match.phase) .. "/" .. tostring(seats[2].match.phase) .. ")")
  for _, name in ipairs({ "ask", "pouch", "waitmsg", "drop", "lid", "countdown", "play", "finish", "results",
      "powder", "standby", "saving", "yesno", "again", "stop" }) do
    check(sawStages[name], "stage " .. name)
  end
  eq(#hub.dropped, 0, "no message dropped by the byte caps (" .. table.concat(hub.dropped, ";") .. ")")
  check(hub.maxState <= 512, "largest game3_mg_state " .. hub.maxState .. " bytes")
  check(predictedImpact, "a member's own impact shows before the leader confirms (prediction)")
  eq(firstTarget, T.berry_data[1].difficulty + T.berry_data[8].difficulty + T.berry_data[18].difficulty,
    "target presses from the three berries")
  eq(firstBerries, "0,7,17", "every seat knows every berry")
  local r0 = seats[0].match.result
  check(r0 ~= nil, "leader produced game3_mg_result")
  for s = 1, 2 do
    local rs = seats[s].match.result
    check(rs ~= nil and MG.same(rs.results, r0.results), "seat " .. s .. " agrees")
  end
  eq(#(r0 and r0.powder or {}), 0, "powder was given in-game, not by the MG result")
  for s = 0, 2 do
    local st = seats[s]
    local sim = st.match.sim
    eq(sim.round, 1, "seat " .. s .. " played two rounds")
    eq(Bag.get(st.session.bag, st.item), st.count - 2, "seat " .. s .. " used one berry per round")
    eq(#st.powder, 2, "seat " .. s .. " got powder twice")
    check(st.powder[1] > 0 and st.powder[2] > 0, "powder " .. table.concat(st.powder, "+"))
    eq(st.session.berryPowder, 10 + sum(st.powder), "seat " .. s .. " Berry Powder total")
    check((st.session.berryCrushPressingSpeeds and st.session.berryCrushPressingSpeeds[2] or 0) > 0,
      "seat " .. s .. " 3-player pressing speed record")
    eq(st.session.gameStats and st.session.gameStats[Sim.GAME_STAT_BERRY_CRUSH_POINTS], 2, "GAME_STAT_BERRY_CRUSH_POINTS")
    eq(st.saves[1], 2, "seat " .. s .. " saved after each round")
    check(sim.over, "seat " .. s .. " closed the game")
  end
  eq(seats[0].powder[1], seats[1].powder[1], "everyone gets the same powder")
  eq(seats[2].match.sim.answer, Sim.ANSWER.NO_BERRIES, "LEAF ran out of berries")
  eq(seats[0].match.sim.answer, Sim.ANSWER.YES, "RED wanted another round")
  local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
  end
  check(has(seats[1].se, Sim.SE.BALL_THROW) and has(seats[1].se, Sim.SE.FALL) and has(seats[1].se, Sim.SE.M_STRENGTH),
    "drop / lid sounds")
  check(has(seats[1].se, Sim.SE.MUD_BALL) or has(seats[1].se, Sim.SE.BREAKABLE_DOOR), "crush sounds")
  local sim1 = seats[1].match.sim
  local lines, win = require("src.ui.game3.minigames.berry_crush.view").buildPage(sim1, 2)
  check(#lines > 6 and win.width == 24, "crushing results page builds (" .. #lines .. " lines)")
  local found = false
  for _, l in ipairs(lines) do if l.text:find("BERRY", 1, true) then found = true end end
  check(found, "berry names on the crushing page")
end

print("[test] 8. leader drops mid-game: seat 1 takes over and the game still finishes")
do
  local hub, seats = makeGame(3, { 133, 133, 133 })
  for s = 0, 2 do seats[s].wantNo = true end
  local dropped = false
  step(seats, 12000, function()
    local sim0 = seats[0].match.sim
    if not dropped and sim0 and sim0.A.ph == Sim.PH.PLAY and sim0.A.tp >= 30 then
      dropped = true
      seats[0].gone = true
      hub:drop(0)
    end
    return dropped and seats[1].match:finished() and seats[2].match:finished()
  end)
  check(dropped, "seat 0 dropped during play")
  check(seats[1].match:isLeader(), "seat 1 became leader")
  eq(seats[2].match.leader, 1, "seat 2 follows seat 1")
  check(seats[1].match.sim.A.gone[1], "the old leader is marked gone")
  eq(seats[1].match.phase, "done", "seat 1 finished as leader")
  eq(seats[2].match.phase, "done", "seat 2 finished")
  local a, b = seats[1].match.result, seats[2].match.result
  check(a ~= nil and b ~= nil and MG.same(a.results, b.results), "seats 1 and 2 agree")
  local tp = seats[1].match.sim.res and seats[1].match.sim.res.total or 0
  check(tp >= 30, "presses before the drop were kept (" .. tp .. ")")
  eq(#seats[1].powder, 1, "one round of powder for seat 1")
  eq(seats[1].powder[1], seats[2].powder[1], "seats 1 and 2 got the same powder")
  eq(seats[2].match.sim.answer, Sim.ANSWER.NO, "declined another round")
end

print("[test] 9. time up at 10 minutes: no powder, no record")
do
  local ctx = { seat = 0, leader = true, players = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" } },
    art = art, rng = MG.rng(1) }
  local session = { bag = Bag.new() }
  local powder = {}
  local M = moduleFor(session, { powder = powder })
  local sim = Sim.new(M, ctx)
  local inputs = { { r = 0, b = 0, a = 3, n = 0, h = 0 }, { r = 0, b = 0, a = 3, n = 0, h = 0 } }
  local present = { true, true }
  sim.A.ph = Sim.PH.COUNTDOWN
  R.setBerries(sim.A, T, { 0, 0 })
  local frames = 0
  while sim.A.ph ~= Sim.PH.TIMEUP and frames < R.MAX_TIME + 10 do
    sim:leaderStep(inputs, present)
    frames = frames + 1
  end
  eq(sim.A.ph, Sim.PH.TIMEUP, "leader times out")
  eq(sim.A.timer, R.MAX_TIME, "timer clamped to MAX_TIME")
  inputs[1].a, inputs[2].a = 4, 4
  sim:leaderStep(inputs, present)
  eq(sim.A.ph, Sim.PH.RESULTS, "results phase")
  check(sim.A.res and sim.A.res.timeUp, "results say time up")
  sim:takeResults(sim.A.res)
  eq(#powder, 0, "no powder")
  eq(session.berryCrushPressingSpeeds, nil, "records untouched")
  check(not G.applyResults(session, sim:results(), 0), "the MG result writes nothing")
end

print("[test] 10. snapshot stays under the relay cap with 5 players")
do
  local players = {}
  for s = 0, 4 do players[#players + 1] = { seat = s, name = "PLAYER" .. s } end
  local sim = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 0, leader = true, players = players, art = art })
  R.setBerries(sim.A, T, { 42, 42, 42, 42, 42 })
  sim.A.ph = Sim.PH.PLAY
  local A = sim.A
  A.lt, A.timer, A.tp, A.nc, A.nb, A.lastT = 35999, 35998, 32000, 1199, 1199, 35999
  for p = 1, 5 do
    local pl = A.pl[p]
    pl.np, pl.ns, pl.st, pl.mx, pl.td, pl.it, pl.fl, pl.sn = 9999, 9999, 9999, 9999, 35999, 35999, 2, 9999
    A.held[p] = 35999
  end
  for t = 1, 3 do
    sim.outq[#sim.outq + 1] = { t = 35990 + t, d = 32, v = -4, fl = 0x7FFF, sa = 4, big = true, eg = false }
  end
  local msg = { type = MG.MSG.STATE, f = 99999, e = 12, s = sim:snapshot() }
  local bytes = #Json.encode(msg)
  check(bytes <= 512, "worst-case game3_mg_state is " .. bytes .. " bytes")
  local saved = sim.A.ph
  sim.A.ph = Sim.PH.RESULTS
  sim.A.res = { time = 35999, silk = 100, powder = 99999, page = 2, total = 49995,
    presses = { 9999, 9999, 9999, 9999, 9999 }, random = { 1600, 1600, 1600, 1600, 1600 } }
  local rbytes = #Json.encode({ type = MG.MSG.STATE, f = 99999, e = 12, s = sim:snapshot() })
  check(rbytes <= 512, "results-phase game3_mg_state is " .. rbytes .. " bytes")
  sim.A.ph, sim.A.res = saved, nil
  local back = Wire.sanitize(Json.decode(Json.encode(msg)))
  local other = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 1, leader = false, players = players, art = art })
  other:applySnapshot(back.s)
  eq(other.A.pl[5].np, 9999, "member restores player counters")
  eq(other.A.lt, 35999, "member restores leader timer")
  eq(#other.vq, 3, "records queued for playback")
  other:becomeLeader(back.s)
  check(other.leader and #other.vq == 3, "becomeLeader does not queue records twice")
end

print("[test] 11. results pages and cart text")
do
  local players = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" } }
  local sim = Sim.new(moduleFor({ bag = Bag.new(), berryPowder = 500 }),
    { seat = 1, leader = false, players = players, art = art })
  R.setBerries(sim.A, T, { 0, 8 })
  sim:takeResults({ time = 1234, silk = 70, powder = 88, page = 1, total = 75,
    presses = { 40, 35 }, random = { 800, 900 } })
  eq(sim.res.rank0[1], 1, "RED first on presses")
  eq(sim.res.rank1[1], 2, "BLUE first on the cooperative page")
  local lines = require("src.ui.game3.minigames.berry_crush.view").buildPage(sim, 1)
  local text = {}
  for _, l in ipairs(lines) do text[#text + 1] = l.text end
  local joined = table.concat(text, "|")
  check(joined:find("Cooperative Rankings", 1, true) ~= nil, "random page header (" .. joined .. ")")
  check(joined:find("56.25", 1, true) ~= nil, "Q.4 percentage 900/16 = 56.25")
  local crush = require("src.ui.game3.minigames.berry_crush.view").buildPage(sim, 2)
  local all = {}
  for _, l in ipairs(crush) do all[#all + 1] = l.text end
  joined = table.concat(all, "|")
  check(joined:find("CHERI BERRY", 1, true) ~= nil and joined:find("LUM BERRY", 1, true) ~= nil,
    "berry names (" .. joined .. ")")
  check(joined:find("Silkiness", 1, true) ~= nil and joined:find(" 70%", 1, true) ~= nil, "silkiness")
  check(joined:find("20.53", 1, true) ~= nil, "time 1234 frames = 0 min 20.53 sec")
  local Printer = require("src.ui.game3.minigames.berry_crush.printer")
  local music = {}
  local p
  p = Printer.new(G.hooks.text(Sim.MSG.POWDER, { "88", "588" }), 1,
    { music = function(cmd, arg) music[#music + 1] = cmd .. ":" .. arg .. "@" .. (p and p.revealed or 0) end })
  eq(table.concat(music, ","), "23:0@0,11:257@0", "PAUSE_MUSIC then PLAY_BGM MUS_LEVEL_UP before the first glyph")
  local guard = 0
  while not p.prompt and guard < 500 do p:tick(nil) guard = guard + 1 end
  check(p.prompt, "the powder message stops for A at its paragraph break")
  eq(music[3], "24:0@" .. p.total, "RESUME_MUSIC after the last glyph of page 1")
  local A = { wasPressed = function(_, b) return b == "a" end }
  p:tick(A)
  while not p.prompt and guard < 1000 do p:tick(nil) guard = guard + 1 end
  check(p.prompt and p:printed() and not p:done(), "the trailing \\p holds the second page for A")
  check(p:text():find("588", 1, true) ~= nil, "total Berry Powder in the text")
  for _ = 1, 30 do p:tick(nil) end
  check(not p:done(), "no auto-close without A")
  p:tick(A)
  p:tick(nil)
  p:tick(nil)
  check(p:done() and p:text() == "", "A clears the window and ends the message")
  for _, key in ipairs({ Sim.MSG.PICK_BERRY, Sim.MSG.TIMES_UP }) do
    local q = Printer.new(G.hooks.text(key), 0)
    for _ = 1, 400 do if q.prompt and q.page == #q.pages then break end q:tick(q.prompt and A or nil) end
    check(q.prompt and q.page == #q.pages and not q:done(), key .. " waits for A after its last page")
  end
  local w = Printer.new(G.hooks.text(Sim.MSG.COMM_STANDBY), 0)
  for _ = 1, 100 do w:tick(nil) end
  check(w:done(), "a message without a trailing \\p closes on its own")
end

print("[test] 12. a member missing at the play-again barrier stops the game (berry_crush.c:2286)")
do
  local players = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" }, { seat = 2, name = "LEAF" } }
  local function yes(round) return { r = round, b = 0, a = Sim.ACK.ANSWER, n = 0, h = 0, y = Sim.ANSWER.YES } end
  local sim = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 0, leader = true, players = players, art = art })
  sim.A.ph = Sim.PH.SAVE
  sim:leaderStep({ yes(0), yes(0), nil }, { true, true, nil })
  eq(sim.A.ph, Sim.PH.STOP, "LEAF left before answering: STOP, not a new round")
  eq(sim.A.round, 0, "no new round")
  local full = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 0, leader = true, players = players, art = art })
  full.A.ph = Sim.PH.SAVE
  full:leaderStep({ yes(0), yes(0), yes(0) }, { true, true, true })
  eq(full.A.round, 1, "everyone present and YES starts round 2")
  local mig = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 1, leader = false, players = players, art = art })
  mig.A.ph = Sim.PH.SAVE
  mig.A.ld = 1
  mig:becomeLeader(nil)
  mig.A.ph = Sim.PH.SAVE
  mig:leaderStep({ nil, yes(0), yes(0) }, { nil, true, true })
  eq(mig.A.ph, Sim.PH.STOP, "the old leader is gone after migration: STOP")
  local results = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 0, leader = true, players = players, art = art })
  results.A.ph = Sim.PH.RESULTS
  local st = { r = 0, b = 0, a = Sim.ACK.STANDBY, n = 0, h = 0, y = 0 }
  results:leaderStep({ st, st, nil }, { true, true, nil })
  eq(results.A.ph, Sim.PH.SAVE, "earlier barriers still release without the missing seat")
end

print("[test] 13. a member who leaves mid-game is marked gone for every seat")
do
  local players = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" }, { seat = 2, name = "LEAF" } }
  local lead = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 0, leader = true, players = players, art = art })
  local member = Sim.new(moduleFor({ bag = Bag.new() }), { seat = 2, leader = false, players = players, art = art })
  lead.A.ph = Sim.PH.PLAY
  lead:leaderStep({ nil, nil, nil }, { true, true, true })
  check(not lead.A.gone[2], "everyone present: nobody gone")
  lead:leaderStep({ nil, nil, nil }, { true, nil, true })
  check(lead.A.gone[2] == true, "BLUE left the room: gone on the leader")
  check(not lead.A.gone[1] and not lead.A.gone[3], "the others stay")
  local wired = wireCopy({ type = MG.MSG.STATE, f = 1, e = 1, s = lead:snapshot() })
  member:applySnapshot(wired and wired.s)
  check(member.A.gone[2] == true, "the snapshot carries BLUE's drop to LEAF")
  lead:leaderStep({ nil, nil, nil }, { true, true, true })
  check(lead.A.gone[2] == true, "a dropped seat does not come back")
end

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] game3_mg_berry_crush_test")

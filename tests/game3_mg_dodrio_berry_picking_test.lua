#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
local root = Cache.mountOrSkip("dodrio berry picking (ROM tables, art, text)", "dodrio_berry_picking/tables.lua")

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
local G = require("src.core.game3.minigames.dodrio_berry_picking")
local R = G.Rules
local Sim = G.Sim
local Art = require("src.ui.game3.minigames.common_art")
local Countdown = require("src.ui.game3.minigames.common_countdown")
local FakeRelay = require("tests.support.fake_relay")

local T = assert(Art.tables("dodrio_berry_picking"))

local sounds = {}
local function resetSounds() sounds = {} end
G.audio = {
  playSe = function(id) sounds[#sounds + 1] = "se" .. id end,
  stopSe = function() end,
  isSePlaying = function() return false end,
  playSong = function(id) sounds[#sounds + 1] = "song" .. id end,
  playFanfare = function(id) sounds[#sounds + 1] = "fanfare" .. id end,
  fadeOutAndPlay = function(id) sounds[#sounds + 1] = "fade" .. id end,
}

local function canon(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function count(list, v)
  local n = 0
  for _, x in ipairs(list) do if x == v then n = n + 1 end end
  return n
end

local function stepN(st, n, presses)
  for _ = 1, n do R.step(st, presses or {}) end
end

print("[test] 1. ROM tables and cart geometry")
do
  eq(select(1, R.activeColumns(3)), 2, "3 players: first active column 2")
  eq(select(2, R.activeColumns(5)), 11, "5 players: all 11 columns (10 + wrap)")
  eq(R.dodrioX(0, 3), 120, "own Dodrio centred with 3 players")
  eq(R.dodrioX(3, 5), 24, "5 players: position 3 at x 24")
  eq(R.headColumn(T, 3, 1, 0), 6, "sDodrioHeadToColumnMap[2][1] left head")
  eq(R.activeColumn(T, 3, 2, 8), 6, "sActiveColumnMap[2][2][8] wraps to column 6")
  eq(T.tree_border_x[5], 15, "sTreeBorderXPos 5 players")
  eq(#T.prize_berry_ids, 3, "three prize sets")
end

print("[test] 2. first wave, prize and falling")
do
  local st = R.new(T, 3, MG.rng(7))
  eq(st.fall[2], 1, "even column starts at 1")
  eq(st.fall[3], 0, "odd column starts hidden")
  eq(st.ids[4], R.BERRY_BLUE, "first wave is blue")
  local r = MG.rng(7)
  eq(st.prize, T.prize_berry_ids[1][r:next() % 10 + 1], "prize from the first Random() and the 3-player set")
  local st5 = R.new(T, 5, MG.rng(7))
  eq(st5.prize, T.prize_berry_ids[3][MG.rng(7):next() % 10 + 1], "5 players use the third set")
  stepN(st, T.berry_fall_delays[1][1] - 1)
  eq(st.fall[2], 1, "blue waits sBerryFallDelays[0][BLUE] frames")
  R.step(st, {})
  eq(st.fall[2], 2, "then drops one step")
  eq(st.fall[3], 1, "odd column entered on the same frame")
  check(st.falling, "berries falling")
end

local function fresh(n, seed)
  local st = R.new(T, n, MG.rng(seed or 99))
  for c = 0, 10 do
    st.fall[c] = 0
    st.state[c] = R.BS_SQUISHED
    st.newTimer[c] = 0
  end
  st.gray = 0
  return st
end

print("[test] 3. picking, eating, difficulty")
do
  local st = fresh(3)
  local col = R.headColumn(T, 3, 0, 1)
  eq(col, 5, "player 0 middle head over column 5")
  st.state[col] = R.BS_NONE
  st.fall[col] = 6
  st.ids[col] = R.BERRY_GREEN
  st.echo[col] = R.BERRY_GREEN
  R.step(st, { [0] = { n = 1, d = R.PICK_MIDDLE } })
  eq(st.inputState[0], R.IN_PICKED, "press in range picks")
  eq(st.state[col], R.BS_PICKED, "berry picked")
  local frames = 0
  while st.state[col] == R.BS_PICKED and frames < 20 do
    R.step(st, { [0] = { n = 1, d = R.PICK_MIDDLE } })
    frames = frames + 1
  end
  eq(st.state[col], R.BS_EATEN, "eaten after the eat timer")
  eq(st.res[0][R.BERRY_GREEN], 1, "green counted for player 0")
  eq(st.eaten[0], 1, "berriesEaten")
  eq(st.ate[0], 1, "ateBerry set")
  eq(st.ids[col], R.BERRY_MISSED, "id cleared to BERRY_MISSED")
  eq(st.fall[col], R.EAT_FALL_DIST, "eaten berry parks at EAT_FALL_DIST")
  stepN(st, 25, { [0] = { n = 1, d = R.PICK_MIDDLE } })
  eq(st.state[col], R.BS_NONE, "new berry after 20 frames")
  eq(st.fall[col], 1, "new berry at the top")
  eq(st.ate[0], 0, "ateBerry cleared")
  eq(st.inputState[0], R.IN_NONE, "input released after 6 frames")

  local d = fresh(3)
  d.eaten[0] = 4
  d.difficulty[0] = 0
  local c2 = R.headColumn(T, 3, 0, 0)
  d.state[c2] = R.BS_NONE
  d.fall[c2] = 7
  d.ids[c2] = R.BERRY_BLUE
  d.echo[c2] = R.BERRY_BLUE
  for i = 1, 10 do R.step(d, { [0] = { n = 1, d = R.PICK_LEFT } }) if d.state[c2] == R.BS_EATEN then break end end
  eq(d.difficulty[0], 1, "5 berries eaten -> difficulty 1")
  d.difficulty[0] = 21
  d.eaten[0] = 49
  d.state[c2] = R.BS_NONE
  d.fall[c2] = 7
  d.ids[c2], d.echo[c2] = 0, 0
  d.inputState[0] = R.IN_NONE
  for i = 1, 10 do R.step(d, { [0] = { n = 2, d = R.PICK_LEFT } }) if d.state[c2] == R.BS_EATEN then break end end
  eq(d.difficulty[0], 22, "u8 threshold wraps at difficulty 21 (5 + 300 -> 49)")
end

print("[test] 4. misses")
do
  local st = fresh(3)
  local col = R.headColumn(T, 3, 1, 1)
  st.state[col] = R.BS_NONE
  st.fall[col] = 3
  R.step(st, { [1] = { n = 1, d = R.PICK_MIDDLE } })
  eq(st.inputState[1], R.IN_BAD_MISS, "out of range press is a bad miss")
  eq(st.missed[1], 1, "missedBerry set")
  stepN(st, 38, { [1] = { n = 2, d = R.PICK_MIDDLE } })
  eq(st.inputState[1], R.IN_BAD_MISS, "still locked inside 40 frames")
  eq(st.ack[1], 2, "the press during the lockout is consumed")
  stepN(st, 1, { [1] = { n = 2, d = R.PICK_MIDDLE } })
  eq(st.inputState[1], R.IN_NONE, "released after 40 frames")

  local sq = fresh(3)
  sq.state[4] = R.BS_NONE
  sq.fall[4] = R.MAX_FALL_DIST
  R.step(sq, {})
  eq(sq.state[4], R.BS_SQUISHED, "berry squished at MAX_FALL_DIST")
  eq(sq.gray, 1, "one gray square")
  eq(sq.res[2][R.BERRY_MISSED], 1, "column 4 miss charged to player 2")
  eq(sq.res[0][R.BERRY_MISSED], 1, "and player 0")
  eq(sq.res[1][R.BERRY_MISSED], 0, "not player 1")
  eq(sq.maxInRow, 0, "berries in a row only counts with 5 players")

  local five = fresh(5)
  five.inRow = 12
  five.state[0] = R.BS_NONE
  five.fall[0] = R.MAX_FALL_DIST
  R.step(five, {})
  eq(five.maxInRow, 12, "5 players: a miss banks the streak")
  eq(five.inRow, 0, "and resets it")

  local two = fresh(3, 5)
  local c = 4
  eq(R.headColumn(T, 3, 0, 0), c, "player 0 left head on 4")
  eq(R.headColumn(T, 3, 2, 2), c, "player 2 right head on 4")
  two.state[c] = R.BS_NONE
  two.fall[c] = 6
  two.ids[c], two.echo[c] = 0, 0
  R.step(two, { [0] = { n = 1, d = R.PICK_LEFT }, [2] = { n = 1, d = R.PICK_RIGHT } })
  eq(two.att0[c], 0, "first picker recorded")
  eq(two.att1[c], R.PLAYER_NONE, "the berry is already PICKED for the second one")
  eq(two.missed[2], 1, "so player 2 missed it")
  for i = 1, 10 do
    R.step(two, { [0] = { n = 1, d = R.PICK_LEFT }, [2] = { n = 1, d = R.PICK_RIGHT } })
    if two.state[c] == R.BS_EATEN then break end
  end
  eq(two.state[c], R.BS_EATEN, "shared berry eaten")
  eq(two.ate[0], 1, "player 0 ate it")
  eq(two.ate[2], 0, "player 2 did not")
end

print("[test] 5. berry types by difficulty")
do
  local st = fresh(3)
  eq(R.berryIdByDifficulty(st, 0, 4), R.BERRY_BLUE, "d0 blue")
  eq(R.berryIdByDifficulty(st, 1, 4), R.BERRY_GREEN, "d1 green")
  eq(R.berryIdByDifficulty(st, 2, 4), R.BERRY_GOLD, "d2 gold")
  st.prev[4] = R.BERRY_BLUE
  eq(R.berryIdByDifficulty(st, 3, 4), R.BERRY_GREEN, "d3 alternates blue/green")
  eq(R.berryIdByDifficulty(st, 4, 4), R.BERRY_GOLD, "d4 alternates blue/gold")
  st.prev[4] = R.BERRY_GOLD
  eq(R.berryIdByDifficulty(st, 5, 4), R.BERRY_GREEN, "d5 alternates gold/green")
  st.prev[4] = R.BERRY_GREEN
  eq(R.berryIdByDifficulty(st, 6, 4), R.BERRY_GOLD, "d6 cycles blue/green/gold")
  eq(R.berryIdByDifficulty(st, 7, 4), R.BERRY_BLUE, "d7 wraps to blue")
  st.difficulty[1] = 2
  eq(R.newBerryId(st, 0, 5), R.BERRY_BLUE, "unshared column 5 uses player 0 only")
  eq(R.newBerryId(st, 0, 6), R.BERRY_GOLD, "shared column 6 takes the hardest neighbour")
end

print("[test] 6. scores and rankings")
do
  local res = R.newResults()
  res[0][0], res[0][1], res[0][2], res[0][3] = 10, 5, 2, 1
  eq(R.score(T, res[0]), 100 + 150 + 100 - 50, "10/30/50 points, -50 per miss")
  res[1][3] = 5
  eq(R.score(T, res[1]), 0, "score never goes negative")
  res[2][0] = 30
  eq(R.highestScore(T, res, 3), 300, "highest")
  local sr = R.scoreResults(T, res, 3)
  eq(sr[0].ranking, 0, "tie at the top: first")
  eq(sr[2].ranking, 0, "tie at the top: first too")
  eq(sr[1].ranking, 2, "then third")
  local rows = R.rankedOrder(T, res, 3)
  eq(rows[1].player, 0, "ranked list keeps player order inside a tie")
  eq(rows[3].player, 1, "zero score last")
  eq(rows[3].ranking, 2, "zero score shown at the last rank")
  local none = R.rankedOrder(T, R.newResults(), 3)
  eq(none[1].ranking, 2, "nobody scored: everybody last")
  eq(R.berriesPicked({ [0] = 9000, 900, 200, 0 }), 9999, "berries picked capped at 9999")
end

print("[test] 7. snapshot encoding and leader handover")
do
  local st = R.new(T, 5, MG.rng(31337))
  local presses = {}
  local rng = MG.rng(5)
  for f = 1, 900 do
    for p = 0, 4 do
      if rng:next() % 11 == 0 then presses[p] = { n = f % 256, d = rng:next() % 3 + 1 } end
    end
    R.step(st, presses)
  end
  for p = 0, 4 do
    st.res[p][0], st.res[p][1], st.res[p][2], st.res[p][3] = 19999, 19999, 19999, 65535
    st.eaten[p] = 65535
  end
  local s = R.encode(st)
  s.go, s.rd, s.m, s.e = 1, 99, 1048575, 1
  local msg = { type = "game3_mg_state", f = 2147483, e = 99, s = s }
  local bytes = #Json.encode(msg)
  check(bytes <= 512, "5-player state at maximum counts fits the 512 byte cap (" .. bytes .. ")")
  local wired = Wire.sanitize(Json.decode(Json.encode(msg)))
  check(wired and type(wired.s) == "table", "state survives Wire.sanitize")
  local copyRng = MG.rng(0)
  local back = R.decode(T, 5, wired.s, copyRng)
  eq(canon(R.encode(back)), canon(R.encode(st)), "decode(encode(state)) round trips")
  eq(copyRng.state, st.rng.state, "RNG state rides the snapshot")

  local a = R.new(T, 4, MG.rng(4242))
  local script = {}
  local ir = MG.rng(77)
  local cur = {}
  for f = 1, 2600 do
    for p = 0, 3 do
      if (f + p * 3) % 9 == 0 then cur[p] = { n = (f + p) % 256, d = ir:next() % 3 + 1 } end
    end
    local frame = {}
    for p = 0, 3 do frame[p] = cur[p] end
    script[f] = frame
  end
  for f = 1, 600 do R.step(a, script[f]) end
  local handover = Json.decode(Json.encode(R.encode(a)))
  local b = R.decode(T, 4, handover, MG.rng(0))
  local same = true
  local eatenAfter = 0
  for f = 601, 2600 do
    R.step(a, script[f])
    R.step(b, script[f])
    if Json.encode(R.encode(a)) ~= Json.encode(R.encode(b)) then same = false break end
  end
  for p = 0, 3 do eatenAfter = eatenAfter + a.eaten[p] end
  check(eatenAfter > 0, "the handover run had picks in it (" .. eatenAfter .. ")")
  check(same, "a new leader continues bit-for-bit from the last state")
end

print("[test] 8. game over")
do
  local st = R.new(T, 5, MG.rng(3))
  st.inRow, st.maxInRow = 4, 7
  local f = 0
  while not R.ended(st) and f < 5000 do R.step(st, {}) f = f + 1 end
  check(R.ended(st), "no picks: the game ends (" .. f .. " frames)")
  eq(st.gray, R.NUM_STATUS_SQUARES, "ten gray squares")
  check(not st.falling, "nothing left falling")
  eq(st.res[3][R.BERRY_IN_ROW], 7, "max berries in a row copied to every player")
end

local function players(n)
  local out = {}
  local names = { "RED", "BLUE", "LEAF", "GOLD", "KRIS" }
  for s = 0, n - 1 do
    out[#out + 1] = { seat = s, name = names[s + 1], trainerId = 0x100 + s, gender = s % 2, species = 85 }
  end
  return out
end

local function newSim(n, seat, leader, seed)
  return G.new({ game = "pick", seat = seat, seats = n, players = players(n), leader = leader,
    seed = seed or 11, rng = MG.rng(seed or 11), partyMon = { species = 85, personality = 1, otId = 2 } })
end

local function press(dir)
  return { wasPressed = function(_, b) return b == dir end, isDown = function() return false end }
end
local IDLE = { wasPressed = function() return false end, isDown = function() return false end }

print("[test] 9. sim: intro, own countdown, input gating, prediction")
do
  resetSounds()
  local sim = newSim(3, 1, false)
  eq(sim.me, 1, "seat 1 is player 1")
  local function frame(input)
    sim:localInput(input or IDLE)
    sim:update()
  end
  check(not sim:introDone(), "intro running")
  local slide = 0
  while sim.intro.stage == "slide" do frame() slide = slide + 1 end
  eq(slide, 4 * (T.tree_border_x[3] + 1), "tree borders slide for 4 * (XPos + 1) frames")
  eq(sim.intro.hofs, (T.tree_border_x[3] - 1) * 8, "borders stop at (XPos - 1) * 8")
  local f = 0
  while not sim:introDone() and f < 1000 do frame() f = f + 1 end
  check(sim:introDone(), "intro finishes (" .. f .. " more frames)")
  eq(count(sounds, "se" .. Sim.SE_CLICK), 10, "SE_CLICK per status square")
  eq(count(sounds, "se" .. Sim.SE_M_CHARM), 6, "intro head stretches: SE_M_CHARM x6")
  eq(sim.status.y[9], 8, "status bar settled at y 8")
  check(count(sounds, "song" .. Sim.MUS_BERRY_PICK) == 1, "MUS_BERRY_PICK")
  check(not sim.hostCountdown, "Match skipped its countdown (G.OWN_COUNTDOWN): the sim plays it")
  check(sim.countdown ~= nil, "StartMinigameCountdown after the names")
  eq(sim:localInput(press("up")).n, 0, "no picking during the countdown")
  local cd = 0
  while not sim.started and cd < 400 do frame() cd = cd + 1 end
  check(sim.started, "countdown over, game on (" .. cd .. " frames)")
  eq(count(sounds, "se50"), 9, "SE_BALL_BOUNCE_2 x9 from the countdown")
  check(G.OWN_COUNTDOWN, "the module owns its countdown")

  local host = newSim(3, 2, false)
  host:update()
  check(host.hostCountdown, "an update before any step means the Match is counting down")
  for _ = 1, 600 do host:update() end
  check(host.countdown == nil, "then the sim does not play a second countdown")
  check(host:localInput(press("left")) ~= nil, "input opens when the Match starts play")

  local i0 = sim:localInput(IDLE)
  eq(i0.n, 0, "no press counted before the first press")
  eq(i0.sh, 1, "input carries the mon's shininess (tid 2 ^ pid 1 < 8: shiny)")
  local i = sim:localInput(press("up"))
  eq(i and i.d, R.PICK_MIDDLE, "UP reaches up (middle head)")
  sim:predict(i)
  eq(sim:dodrioPose(1), R.PICK_MIDDLE, "own Dodrio predicted at once")
  local again = sim:localInput(press("left"))
  eq(again.n, 1, "a press while the head is out is ignored")
  for _ = 1, 6 do sim:update() end
  eq(sim:dodrioPose(1), R.PICK_NONE, "prediction ends after 6 frames")
  local r = sim:localInput(press("right"))
  eq(r.n, 2, "next press counted")
  eq(r.d, R.PICK_RIGHT, "RIGHT")
end

print("[test] 10. sim: sounds and missed shake")
do
  resetSounds()
  local sim = newSim(3, 0, true)
  sim.intro.done = true
  sim.intro.stage = "done"
  sim.started = true
  local st = sim.st
  local col = R.headColumn(T, 3, 0, 1)
  for c = 0, 10 do st.fall[c], st.state[c], st.fallTimer[c] = 2, R.BS_NONE, 0 end
  st.state[col], st.fall[col] = R.BS_NONE, 6
  sim:leaderStep({ [1] = { n = 1, d = R.PICK_MIDDLE } })
  for _ = 1, 8 do
    sim:leaderStep({ [1] = { n = 1, d = R.PICK_MIDDLE } })
    sim:update()
  end
  eq(count(sounds, "se" .. Sim.SE_SUCCESS), 1, "SE_SUCCESS once for an eaten berry")
  resetSounds()
  st.state[col], st.fall[col], st.ids[col] = R.BS_NONE, 2, 0
  for _ = 1, 3 do sim:leaderStep({ [1] = { n = 2, d = R.PICK_MIDDLE } }) sim:update() end
  eq(count(sounds, "se" .. Sim.SE_BOO), 1, "SE_BOO for a bad miss")
  eq(sim.own.state, 1, "own Dodrio shakes")
  local moved = false
  for _ = 1, 25 do sim:update() if sim.own.dx ~= 0 then moved = true end end
  check(moved, "shake moves the sprite")
  eq(sim.own.state, 0, "shake ends")
  eq(sim.own.dx, 0, "back at its position")
  resetSounds()
  st.state[col], st.fall[col], st.ids[col] = R.BS_NONE, R.MAX_FALL_DIST, R.BERRY_GOLD
  st.gray = 9
  for _ = 1, 3 do sim:leaderStep({}) sim:update() end
  eq(count(sounds, "se" .. (Sim.SE_BALLOON_RED + R.BERRY_GOLD)), 1, "squish sound by berry colour")
  eq(count(sounds, "song0"), 1, "map music stops at the tenth miss")
  eq(count(sounds, "fanfare" .. Sim.MUS_TOO_BAD), 1, "FANFARE_TOO_BAD")
  eq(sim:dodrioPose(0), R.PICK_DISABLED, "every Dodrio down")
end

local function recorderHooks(bag)
  local log = { records = {}, saves = 0, added = {} }
  local Bag = require("src.core.game3.bag")
  log.hooks = {
    updateRecords = function(score, picked, inRow) log.records[#log.records + 1] = { score, picked, inRow } end,
    canAdd = function(item, qty) return Bag.canAdd(bag, item, qty) end,
    addItem = function(item, qty) log.added[#log.added + 1] = item return (Bag.add(bag, item, qty)) end,
    save = function() log.saves = log.saves + 1 end,
  }
  return log
end

local function endRound(sim, res)
  local st = sim.st
  for c = 0, 10 do st.fall[c], st.state[c] = R.MAX_FALL_DIST, R.BS_SQUISHED end
  for p = 0, 2 do
    local r = res[p + 1] or { 0, 0, 0, 0 }
    st.res[p][0], st.res[p][1], st.res[p][2], st.res[p][3] = r[1], r[2], r[3], r[4]
  end
  st.gray = R.NUM_STATUS_SQUARES
  st.phase = R.PHASE_WAIT
end

print("[test] 11. results, records, prize, save, play again, end of link")
do
  local Bag = require("src.core.game3.bag")
  local bag = Bag.new()
  local log = recorderHooks(bag)
  resetSounds()
  local sim = G.new({ game = "pick", seat = 0, seats = 3, players = players(3), leader = true, seed = 5,
    rng = MG.rng(5), partyMon = { species = 85 }, hooks = log.hooks })
  sim.intro.done, sim.intro.stage, sim.started = true, "done", true
  local others = { [2] = { n = 0 }, [3] = { n = 0 } }
  local function step(btn)
    local own = sim:localInput(btn and press(btn) or IDLE)
    sim:leaderStep({ [1] = own, [2] = others[2], [3] = others[3] }, { true, true, true })
    sim:update()
  end
  local function run(n, btn) for _ = 1, n do step(btn) end end
  local function until_(cond, limit, btn)
    for _ = 1, limit or 600 do
      if cond() then return true end
      step(btn)
    end
    return cond()
  end
  endRound(sim, { { 10, 20, 50, 2 }, { 5, 0, 0, 9 }, { 1, 1, 1, 0 } })
  run(1)
  eq(sim.view.ph, R.PHASE_END, "round over once nothing falls")
  check(until_(function() return sim.flow ~= "game" end, 5), "results start")
  check(until_(function() return sim.rs.show == "results" end, 400), "berry results window")
  check(sim.rs.icons, "berry icons over the window")
  eq(#log.records, 1, "TryUpdateRecords once")
  eq(log.records[1][1], 100 + 600 + 2500 - 100, "record score")
  eq(log.records[1][2], 80, "record berries picked")
  check(count(sounds, "fade" .. Sim.MUS_VICTORY_WILD) == 1, "MUS_VICTORY_WILD after the fanfare")
  run(1, "a")
  check(sim.rs.show == "results", "A needs 30 frames first")
  run(40)
  run(1, "a")
  run(5)
  eq(sim.rs.show, "rankings", "rankings after A")
  eq(sim.rs.rows[1].player, 0, "RED ranked first")
  run(40)
  run(1, "a")
  run(3)
  eq(sim.rs.show, "prize", "prize window when someone reached 3000")
  check(count(sounds, "song" .. Sim.MUS_LEVEL_UP) == 1, "MUS_LEVEL_UP for the prize")
  eq(sim.rs.prizeState, R.PRIZE_RECEIVED, "top scorer gets the prize")
  eq(Bag.get(bag, R.prizeItem(sim.rs.prize)), 1, "prize berry in the bag")
  run(40)
  run(1, "a")
  run(5)
  eq(sim.flow, "standby1", "communication standby")
  eq(sim:localInput(IDLE).r, 1, "results viewed: r = round")
  run(200)
  eq(sim.flow, "standby1", "waits for every player")
  others[2].r, others[3].r = 1, 1
  check(until_(function() return sim.flow == "save" end, 200), "then saves (someone reached 3000)")
  check(until_(function() return sim.flow == "ask" end, 200), "then asks")
  eq(log.saves, 1, "Task_LinkFullSave once")
  check(until_(function() return sim.rs.show == "ask" end, 10), "Want to play again?")
  check(sim.blank, "berries cleared for the prompt")
  eq(sim:displayView().gray, 0, "status bar all yellow again")
  run(1, "down")
  eq(sim.rs.cursor, Sim.PLAY_AGAIN_NO, "cursor to NO")
  run(1, "up")
  eq(sim.rs.cursor, Sim.PLAY_AGAIN_YES, "back to YES")
  run(1, "a")
  eq(sim.flow, "standby2", "answered")
  eq(sim:localInput(IDLE).v, 1 * 4 + Sim.PLAY_AGAIN_YES, "vote rides the input")
  resetSounds()
  run(1, "up")
  eq(count(sounds, "se" .. Sim.SE_M_CHARM), 1, "heads move while waiting (SE_M_CHARM)")
  eq(sim:dodrioPose(0), R.PICK_MIDDLE, "own Dodrio reaches up")
  others[2].v, others[3].v = 5, 5
  run(3)
  eq(sim.L.rd, 2, "everyone said YES: round 2")
  check(until_(function() return sim.round == 2 end, 300), "fade out, reset, fade in")
  eq(sim.flow, "game", "new game")
  eq(sim.intro.stage, "slide", "tree borders slide again")
  check(not sim.started, "rules wait for the new countdown")
  check(until_(function() return sim.started end, 900), "second game starts after its countdown")
  endRound(sim, { { 1, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } })
  check(until_(function() return sim.flow == "results" end, 400), "round 2 results")
  local ok = until_(function() return sim.flow == "standby1" end, 400, "a")
  check(ok, "results screens (no prize window below 3000)")
  others[2].r, others[3].r = 2, 2
  check(until_(function() return sim.flow == "ask" end, 300), "no save below 3000")
  eq(log.saves, 1, "still one save")
  run(5)
  run(1, "b")
  eq(sim:localInput(IDLE).v, 2 * 4 + Sim.PLAY_AGAIN_NO, "B answers NO")
  others[2].v = 2 * 4 + Sim.PLAY_AGAIN_YES
  others[3].v = 2 * 4 + Sim.PLAY_AGAIN_YES
  run(3)
  check(sim.L.ended, "someone said NO: the link ends")
  sim:snapshot()
  check(sim:finished(), "leader finishes after the last state")
  sim:showResults({})
  check(until_(function() return sim.flow == "dropped" end, 200), "Somebody dropped out")
  check(until_(function() return sim:resultsDone() end, 200), "then MG leaves")

  local bundle = Cache.bundle("dodrio_berry_picking/tables.lua")
  if bundle then
    local RomText = require("src.core.game3.rom_text")
    for _, key in ipairs({ "gText_BerryPickingResults", "gText_10P30P50P50P", "gText_AnnouncingRankings",
      "gText_AnnouncingPrizes", "gText_FirstPlacePrize", "gText_CantHoldAnyMore", "gText_FilledStorageSpace",
      "gText_SpacePoints", "gText_1Colon", "gText_5Colon", "gText_CommunicationStandby3", "gText_SomeoneDroppedOut" }) do
      check(RomText.has(key), key .. " is ROM text")
    end
    local t = RomText.plain("gText_FirstPlacePrize", { dynamic = { [0] = "RAZZ BERRY" } })
    check(t:find("RAZZ BERRY", 1, true) ~= nil, "prize text takes the item name (" .. t:gsub("\n", " ") .. ")")
  else
    print("[skip] ROM text bundle: " .. tostring(Cache.reason))
  end
end

local function roomSession(relay, s, roomId)
  local rs = { paired = true, closed = false, left = false, seq = 0, target = roomId, lastSeq = 0 }
  function rs:send(msg)
    self.seq = self.seq + 1
    relay:handle(s, { type = "room_msg", seq = self.seq, msg = msg })
  end
  local function inner(m, out)
    if type(m.msg) ~= "table" then return end
    local inn = Wire.sanitize(Json.decode(Json.encode(m.msg)))
    if not inn then return end
    if m.relay then
      inn.relay = true
      if type(inn.seat) ~= "number" then inn.seat = -1 end
    else
      inn.seat = m.seat
    end
    if (m.seq or 0) > rs.lastSeq then rs.lastSeq = m.seq end
    out[#out + 1] = inn
  end
  function rs:poll()
    local out = {}
    for _, m in ipairs(s.transport.inbox) do
      if m.type == "room_msg" then
        inner(m, out)
      elseif m.type == "room_replay" then
        for _, e in ipairs(m.msgs or {}) do inner(e, out) end
      end
    end
    s.transport.inbox = {}
    return out
  end
  function rs:players()
    local room = relay.rooms[roomId]
    return room and room.players or {}
  end
  function rs:close()
    self.left = true
    self.closed = true
    relay:handle(s, { type = "room_leave" })
  end
  return rs
end

local function bot(seat, votes)
  local input = { want = nil, votes = votes or {}, roundAt = {} }
  function input:wasPressed(b) return self.want == b end
  function input:isDown() return false end
  function input:plan(sim, frame)
    self.want = nil
    if not sim then return end
    if sim.flow == "results" then
      if frame % 40 == 0 then self.want = "a" end
      return
    end
    if sim.flow == "ask" and sim.rs and sim.rs.show == "ask" then
      self.want = (self.votes[sim.round] == "no") and "b" or "a"
      return
    end
    if sim.flow ~= "game" or sim.view.gray >= R.NUM_STATUS_SQUARES then return end
    self.roundAt[sim.round] = self.roundAt[sim.round] or frame
    local limit = (sim.round == 1) and (1500 + seat * 200) or 200
    if frame - self.roundAt[sim.round] > limit or (frame + seat * 7) % 97 < 6 then return end
    local dirs = { [0] = "left", "up", "right" }
    for pick = 0, 2 do
      local col = R.headColumn(T, sim.n, sim.me, pick)
      local f = sim.view.fall[col]
      if (f == 6 or f == 7) and sim.view.ids[col] ~= R.BERRY_MISSED then
        self.want = dirs[pick]
        return
      end
    end
  end
  return input
end

local hookLogs = {}
G.hooksFor = function(ctx)
  local seat = tonumber(ctx.seat) or 0
  local entry = hookLogs[seat]
  if not entry then
    entry = recorderHooks(require("src.core.game3.bag").new())
    hookLogs[seat] = entry
  end
  return entry.hooks
end

local function makeGame(n, ownCountdown, votes)
  hookLogs = {}
  local relay = FakeRelay.new()
  local room = relay:newRoom({ intent = "minigame", seats = n, engine = 3 })
  local seats = {}
  local list = players(n)
  local sizes = { state = 0, result = 0, bad = 0 }
  for s = 0, n - 1 do
    local sess = relay:seat(("%08x"):format(0xd0 + s), list[s + 1].name)
    relay:seatPlayer(room, sess)
    local rs = roomSession(relay, sess, room.room)
    local send = rs.send
    function rs:send(msg)
      local bytes = #Json.encode(msg)
      if msg.type == "game3_mg_state" then sizes.state = math.max(sizes.state, bytes) end
      if msg.type == "game3_mg_result" then sizes.result = math.max(sizes.result, bytes) end
      if bytes > ((msg.type == "game3_mg_result") and 1024 or 512) then sizes.bad = sizes.bad + 1 end
      return send(self, msg)
    end
    local client = {
      state = function() return sess.online and "online" or "offline" end,
      room = function() return { room = room.room, leader = room.leader } end,
    }
    local session = { bag = require("src.core.game3.bag").new() }
    local spec = { game = "pick", session = rs, seat = s, seats = n, players = list, seed = 424242, partySlot = 0,
                   returnToMap = false }
    local m = MG.Match.new(spec, {
      module = G, client = client, leader = 0,
      partyMon = { species = 85, personality = 0x1234 + s, otId = 0x100 + s },
      me = { name = list[s + 1].name, trainerId = 0x100 + s, gender = s % 2 },
      countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
      onResult = function(msg, match) MG.applyResults(session, msg, match.seat, G) end,
    })
    if ownCountdown then
      local onStart = m.onStart
      m.onStart = function(self, msg)
        onStart(self, msg)
        if self.G.OWN_COUNTDOWN and self.sim then
          self.countdown = nil
          self.phase = "play"
          self.sinceState = 0
        end
      end
    end
    seats[s] = { sess = sess, rs = rs, match = m, session = session, input = bot(s, votes and votes[s]), frame = 0 }
  end
  return relay, room, seats, sizes
end

local function stepSeats(seats, n)
  for s = 0, n - 1 do
    local st = seats[s]
    if not st.frozen and not st.gone and not st.match:finished() then
      st.frame = st.frame + 1
      st.input:plan(st.match.sim, st.frame)
      st.match:step(st.input)
    end
  end
end

local function runUntil(seats, n, cond, limit)
  for _ = 1, limit do
    stepSeats(seats, n)
    if cond() then return true end
  end
  return false
end

local function allDone(seats, n)
  for s = 0, n - 1 do
    local st = seats[s]
    if not st.gone and not st.match:finished() then return false end
  end
  return true
end

print("[test] 11b. game3_mg_result -> records")
do
  local rows = {
    { seat = 0, score = 3100, stats = { b = 10, g = 20, o = 50, m = 2, r = 7, p = 16 } },
    { seat = 1, score = 0, stats = { b = 5, g = 0, o = 0, m = 9, r = 7, p = 16 } },
  }
  local res = Wire.sanitize({ type = "game3_mg_result", game = "pick", results = rows, powder = {} })
  local session = {}
  check(G.applyResults(session, res, 0), "applyResults")
  local rec = session.dodrioBerryPickingRecords
  eq(rec.bestScore, 3100, "best score")
  eq(rec.berriesPicked, 80, "berries picked")
  eq(rec.berriesPickedInRow, 7, "berries in a row")
  G.applyResults(session, res, 0)
  eq(rec.bestScore, 3100, "idempotent")
  local lower = { dodrioBerryPickingRecords = { bestScore = 5000, berriesPicked = 90, berriesPickedInRow = 9 } }
  G.applyResults(lower, res, 0)
  eq(lower.dodrioBerryPickingRecords.bestScore, 5000, "records only go up")
end

print("[test] 11c. prize bag rules (TryGivePrize)")
do
  local Bag = require("src.core.game3.bag")
  local function prizeFor(bag, seat, scores)
    local sim = G.new({ game = "pick", seat = seat, seats = 3, players = players(3), leader = seat == 0, seed = 1,
      rng = MG.rng(1), partyMon = { species = 85 }, hooks = recorderHooks(bag).hooks })
    local res = R.newResults()
    for p = 0, 2 do for k = 0, 3 do res[p][k] = scores[p + 1][k + 1] end end
    sim.rs = { res = res, prize = 16 }
    return sim:tryGivePrize()
  end
  local top = { { 10, 20, 50, 2 }, { 5, 0, 0, 9 }, { 1, 1, 1, 0 } }
  local bag = Bag.new()
  eq(prizeFor(bag, 0, top), R.PRIZE_RECEIVED, "top scorer gets it")
  eq(prizeFor(Bag.new(), 1, top), R.NO_PRIZE, "second place gets nothing")
  local full = Bag.new()
  Bag.add(full, R.prizeItem(16), 998)
  eq(prizeFor(full, 0, top), R.PRIZE_FILLED_BAG, "the 999th berry fills the storage space")
  eq(prizeFor(full, 0, top), R.PRIZE_NO_ROOM, "then no room")
end

print("[test] 12. three seats over the fake relay: leader drops and comes back, play again, then NO")
do
  local relay, room, seats, sizes = makeGame(3, false, { [2] = { [2] = "no" } })
  check(runUntil(seats, 3, function() return seats[0].match.phase == "play" and seats[2].match.phase == "play" end, 400),
    "ready -> start -> countdown -> play on every seat")
  eq(#seats[1].match.startPlayers, 3, "three players in game3_mg_start")
  runUntil(seats, 3, function() return false end, 900)
  local picked = 0
  for p = 0, 2 do picked = picked + R.berriesPicked(seats[0].match.sim.st.res[p]) end
  check(picked > 0, "bots picked berries through the relay (" .. picked .. ")")
  check(seats[1].match.sim.view.live, "member view comes from leader states")

  seats[0].frozen = true
  relay:drop(seats[0].sess)
  runUntil(seats, 3, function() return false end, 150)
  relay:migrateLeader(room.room)
  check(runUntil(seats, 3, function() return seats[1].match:isLeader() end, 30), "relay migrated leadership to seat 1")
  eq(seats[2].match.leader, 1, "seat 2 follows seat 1")
  check(seats[1].match.sim.leader, "seat 1's sim took over from the last state")
  runUntil(seats, 3, function() return false end, 120)
  relay:reconnect(seats[0].sess)
  seats[0].sess.online = true
  relay:replay(seats[0].sess, seats[0].rs.lastSeq)
  seats[0].frozen = false
  check(runUntil(seats, 3, function() return seats[0].match.leader == 1 end, 30), "the old leader resumes as a member")
  check(not seats[0].match.sim.leader, "its sim stepped down")
  check(runUntil(seats, 3, function()
    return seats[0].match.sim.round == 2 and seats[1].match.sim.round == 2 and seats[2].match.sim.round == 2
  end, 60 * 60 * 6), "first game over, everyone said YES: second game on every seat")
  local pickedGame1 = 0
  for s = 0, 2 do
    eq(#hookLogs[s].records, 1, "seat " .. s .. " TryUpdateRecords after game 1")
    pickedGame1 = pickedGame1 + ((hookLogs[s].records[1] or {})[2] or 0)
  end
  check(pickedGame1 > 0, "game 1 berries picked, per the records (" .. pickedGame1 .. ")")
  local ok = runUntil(seats, 3, function()
    return seats[0].match.phase == "results" and seats[1].match.phase == "results" and seats[2].match.phase == "results"
  end, 60 * 60 * 6)
  check(ok, "seat 2 said NO after game 2: the link ends")
  local r1 = canon(seats[1].match.result and seats[1].match.result.results)
  eq(canon(seats[0].match.result and seats[0].match.result.results), r1, "seat 0 agrees on the results")
  eq(canon(seats[2].match.result and seats[2].match.result.results), r1, "seat 2 agrees on the results")
  print("[info] results " .. r1)
  check(runUntil(seats, 3, function() return allDone(seats, 3) end, 3000), "every seat showed 'Somebody dropped out'")
  for s = 0, 2 do
    eq(seats[s].match.sim.flow, "done", "seat " .. s .. " flow done")
    eq(#hookLogs[s].records, 2, "seat " .. s .. " records after both games")
    local rec = seats[s].session.dodrioBerryPickingRecords
    local mine
    for _, r in ipairs(seats[1].match.result.results) do if r.seat == s then mine = r end end
    check(rec ~= nil and mine ~= nil and rec.bestScore >= mine.score, "seat " .. s .. " MG result applied (records)")
    eq(seats[s].session.berryPowder, nil, "no Berry Powder from Dodrio Berry Picking")
  end
  check(sizes.state > 0 and sizes.bad == 0, "every message under the relay caps (state max " .. sizes.state
    .. ", result " .. sizes.result .. ")")
end

print("[test] 13. four seats, the leader leaves, three play on")
do
  local relay, room, seats = makeGame(4)
  runUntil(seats, 4, function() return seats[3].match.phase == "play" end, 400)
  runUntil(seats, 4, function() return false end, 400)
  seats[0].gone = true
  seats[0].rs:close()
  relay:migrateLeader(room.room)
  check(runUntil(seats, 4, function() return seats[1].match:isLeader() end, 30), "seat 1 leads")
  local ok = runUntil(seats, 4, function()
    return seats[1].match.phase == "results" and seats[2].match.phase == "results" and seats[3].match.phase == "results"
  end, 60 * 60 * 6)
  check(ok, "three remaining seats finish the 4-player game")
  local res = seats[1].match.result
  eq(#(res and res.results or {}), 4, "results still list all four players")
end

print("[test] 14. three seats, one leaves: below the minimum")
do
  local relay, room, seats = makeGame(3)
  runUntil(seats, 3, function() return seats[2].match.phase == "play" end, 400)
  seats[2].gone = true
  seats[2].rs:close()
  runUntil(seats, 3, function() return seats[0].match.phase == "error" end, 30)
  eq(seats[0].match.phase, "error", "leader errors with two players left")
  eq(seats[1].match.phase, "error", "member errors too")
  eq(seats[0].session.dodrioBerryPickingRecords, nil, "no records written")
end

print("[test] 15. G.OWN_COUNTDOWN: intro and countdown per seat, leader drops during the intro")
do
  local relay, room, seats = makeGame(3, true, { [1] = { [1] = "no" } })
  check(runUntil(seats, 3, function() return seats[2].match.phase == "play" end, 60), "Match skips its countdown")
  runUntil(seats, 3, function() return false end, 150)
  check(not seats[0].match.sim.started, "leader still in its intro")
  check(not seats[2].match.sim.view.live, "members see no berries before the game starts")
  seats[0].frozen = true
  relay:drop(seats[0].sess)
  relay:migrateLeader(room.room)
  check(runUntil(seats, 3, function() return seats[1].match:isLeader() end, 30), "seat 1 leads from inside the intro")
  check(runUntil(seats, 3, function() return seats[1].match.sim.started end, 900), "the new leader starts after its own countdown")
  check(runUntil(seats, 3, function() return seats[2].match.sim.view.live end, 30), "member 2 sees the berries")
  relay:reconnect(seats[0].sess)
  seats[0].sess.online = true
  relay:replay(seats[0].sess, seats[0].rs.lastSeq)
  seats[0].frozen = false
  check(runUntil(seats, 3, function() return seats[0].match.leader == 1 end, 30), "old leader back as a member")
  check(runUntil(seats, 3, function() return seats[0].match.sim.view.live end, 900),
    "after its own countdown it renders seat 1's game")
  local ok = runUntil(seats, 3, function()
    return seats[0].match.phase == "results" and seats[1].match.phase == "results" and seats[2].match.phase == "results"
  end, 60 * 60 * 6)
  check(ok, "the game ends on every seat")
  eq(canon(seats[0].match.result and seats[0].match.result.results),
    canon(seats[2].match.result and seats[2].match.result.results), "results agree")
end

G.audio = nil

if failed > 0 then
  print(("[FAIL] %d check(s) failed"):format(failed))
  os.exit(1)
end
print("[PASS] game3_mg_dodrio_berry_picking_test")

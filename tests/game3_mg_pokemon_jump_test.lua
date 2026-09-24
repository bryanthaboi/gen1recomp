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

local function finish()
  if failed > 0 then
    print(string.format("[FAIL] game3_mg_pokemon_jump_test: %d failure(s)", failed))
    os.exit(1)
  end
  print("[PASS] game3_mg_pokemon_jump_test")
  os.exit(0)
end

local Game = require("src.core.game3.minigames.pokemon_jump.game")
local Gfx = require("src.core.game3.minigames.pokemon_jump.gfx")

print("[test] 1. cart arithmetic (ROM-free)")
do
  eq(Game.isoRandomize1(0), 24691, "ISO_RANDOMIZE1(0)")
  eq(Game.isoRandomize1(24691), 3917380458, "ISO_RANDOMIZE1 is exact u32 math")
  eq(Game.isoRandomize1(0xFFFFFFFF), 3191476742, "ISO_RANDOMIZE1 wraps at 2^32")
  local item, qty = Game.unpackPrizeData(2 * 0x1000 + 141)
  eq(item, 141, "prize data item in the low 12 bits")
  eq(qty, 2, "prize quantity in the top 4 bits")
  eq(Game.prizeItemName(141, 2, "LUM BERRY"), "LUM BERRIES", "two berries use sPluralTxt")
  eq(Game.prizeItemName(141, 1, "LUM BERRY"), "LUM BERRY", "one berry stays singular")
  eq(Game.prizeItemName(175, 3, "ENIGMA BERRY"), "ENIGMA BERRY", "LAST_BERRY_INDEX is excluded")
end

local Cache = require("tests.game3_cache")
local root = Cache.mount("pokemon_jump/tables.lua")
if not root then
  print("[skip] cache-backed checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local MG = require("src.core.game3.minigames.common")
local Countdown = require("src.ui.game3.minigames.common_countdown")
local Records = require("src.ui.game3.minigame_records")
local G = require(MG.GAMES.jump)
local Art = require("src.ui.game3.minigames.common_art")

local art, artErr = G.loadArt(Art.cache())
check(art ~= nil, "Pokemon Jump art loads from the cache (" .. tostring(artErr) .. ")")
if not art then finish() end
local tables = art.tables

local F = Game.FUNC
local VINE = Game.VINE
local MON = Game.MONSTATE

print("[test] 2. ROM tables drive the rules")
do
  eq(#tables.jump_mons, 100, "sPokeJumpMons has 100 species")
  eq(#tables.vine_base_speeds, 8, "sVineBaseSpeeds")
  eq(tables.score_bonuses[3], 50, "two players in sync score 50")
  eq(tables.score_bonuses[6], 500, "five players in sync score 500")
  eq(tables.prize_quantity[1].score, 5000, "prizes start at 5000 points")
  eq(#tables.prize_items, 8, "eight prize berries")
  eq(G.MIN, 2, "two players minimum")
  eq(G.MAX, 5, "five players maximum")
  eq(G.DROPPED_TEXT, "gText_SomeoneDroppedOut2", "drop text is the cart's")
  check(art.interface[2] ~= nil and art.interface[4] ~= nil, "interface palette (name colors) from bg.pal")
  eq(art.digits.frames, 11, "minigame digits sheet")
  eq(art.vine2.frame_h, 32, "vine2 is the tall vine")
end

local function newHooks(log)
  log = log or {}
  local h = { log = log, bag = {}, full = false, limit = nil }
  h.hooks = {
    playSe = function(id) log[#log + 1] = { "se", id } end,
    playFanfare = function(id) log[#log + 1] = { "fanfare", id } end,
    fanfareDone = function() return true end,
    playMusic = function(id) log[#log + 1] = { "music", id } end,
    canAdd = function(item, qty)
      if h.full then return false end
      if h.limit then return ((h.bag[item] or 0) + qty) <= h.limit end
      return true
    end,
    addItem = function(item, qty)
      if not h.hooks.canAdd(item, qty) then return false end
      h.bag[item] = (h.bag[item] or 0) + qty
      log[#log + 1] = { "item", item, qty }
      return true
    end,
    updateRecords = function(score, row, exc)
      log[#log + 1] = { "records", score, row, exc }
      h.records = { score, row, exc }
      return true
    end,
    incrementMaxPlayerGames = function() log[#log + 1] = { "maxgames" } end,
    save = function() log[#log + 1] = { "save" } end,
  }
  return h
end

local function countLog(log, kind, a)
  local n = 0
  for _, e in ipairs(log) do
    if e[1] == kind and (a == nil or e[2] == a) then n = n + 1 end
  end
  return n
end

local function standalone(opts)
  opts = opts or {}
  local h = newHooks()
  local players = {}
  for s = 0, (opts.n or 2) - 1 do
    players[#players + 1] = { seat = s, name = ({ "RED", "BLUE", "LEAF", "GOLD", "KRIS" })[s + 1], species = 4 }
  end
  local sim = G.new({
    game = "jump", seat = opts.seat or 0, seats = #players, players = players, leader = (opts.seat or 0) == 0,
    seed = 1234, rng = MG.rng(1234), partyMon = { species = 4, personality = 0x12345678, otId = 1 },
    art = art, hooks = h.hooks,
    countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
  })
  return sim, h
end

print("[test] 3. vine speeds and swing timing (sVineBaseSpeeds, sVineSpeedDelays, PokeJumpRandom)")
do
  local sim = standalone()
  local g = sim.game
  g.rngSeed = 0x1234
  g:resetVineState()
  eq(g.vineSpeed, 26, "first swing runs at sVineBaseSpeeds[0]")
  eq(g.vineState, VINE.UPSWING_LOW, "ResetVineState leaves the vine on the upswing")
  check(g.vineSpeedDelay >= 2 and g.vineSpeedDelay <= 4, "speed delay is sVineSpeedDelays[r % 4] + 2 (" .. g.vineSpeedDelay .. ")")
  g:enableVineUpdates()
  local swings, frames, speeds = 0, 0, {}
  local lastSpeed = g.vineSpeed
  local seen = {}
  while swings < 40 and frames < 20000 do
    g:updateVineState()
    frames = frames + 1
    seen[g.vineState] = true
    if g.ignoreJumpInput ~= 0 then
      g.ignoreJumpInput = 0
      swings = swings + 1
      speeds[#speeds + 1] = g.vineSpeed
    end
    lastSpeed = g.vineSpeed
  end
  eq(swings, 40, "forty swings")
  local all = true
  for s = 0, 9 do all = all and seen[s] == true end
  check(all, "the vine passes through all ten states")
  local stageUp = false
  for _, sp in ipairs(speeds) do
    if sp >= 26 + 7 then stageUp = true end
  end
  check(stageUp, "speed stage rises after the base table is walked (+7 per stage)")
  local okRange = true
  for _, sp in ipairs(speeds) do
    if sp < 21 or sp > 82 then okRange = false end
  end
  check(okRange, "speeds stay inside the cart's range")
  local g2 = standalone().game
  g2.rngSeed = 0x1234
  g2:resetVineState()
  g2:enableVineUpdates()
  local speeds2 = {}
  local n = 0
  while #speeds2 < 40 and n < 20000 do
    g2:updateVineState()
    n = n + 1
    if g2.ignoreJumpInput ~= 0 then
      g2.ignoreJumpInput = 0
      speeds2[#speeds2 + 1] = g2.vineSpeed
    end
  end
  eq(table.concat(speeds2, ","), table.concat(speeds, ","), "same seed, same vine (members share the leader's seed)")
end

print("[test] 4. jump arc, hit shake, intro bounce")
do
  local sim = standalone()
  local g = sim.game
  local gfx = g.gfx
  local row = tables.jump_offsets[1]
  g.vineTimer = 100
  g.player.monJumpType = 0
  g.player.jumpTimeStart = 100
  g.player.monState = MON.JUMP
  g.player.prevMonState = MON.NORMAL
  local ys, peak = {}, 0
  for _ = 1, 60 do
    g:handleMonState()
    ys[#ys + 1] = gfx.monSprites[0].y2
    if g.player.jumpOffset == -30 then peak = peak + 1 end
    g.vineTimer = g.vineTimer + 1
    if g.player.monState == MON.NORMAL then break end
  end
  eq(ys[1], 0, "four frames on the ground before the jump leaves")
  eq(ys[5], row[1], "then sJumpOffsets[NORMAL][0]")
  eq(peak, 3, "three frames at JUMP_PEAK for a normal jumper")
  eq(g.player.monState, MON.NORMAL, "the mon lands and goes back to MONSTATE_NORMAL")
  gfx:startMonHitShake(1)
  local frames = 0
  while gfx:isMonHitShakeActive(1) do
    gfx:animateSprites()
    frames = frames + 1
  end
  eq(frames, 26, "SpriteCB_MonHitShake runs 13 shakes two frames apart")
  eq(gfx.monSprites[1].y2, 0, "shake ends level")
  gfx:startMonIntroBounce(0)
  local bounce, minY = 0, 0
  while gfx:isMonIntroBounceActive() do
    gfx:animateSprites()
    bounce = bounce + 1
    minY = math.min(minY, gfx.monSprites[0].y2)
  end
  eq(bounce, 64, "two 32-frame hops")
  eq(minY, -32, "hop height is gSineTable >> 3")
  gfx:doSameJumpTimeBonus(1 + 2)
  eq(gfx.bonus.id, 0, "two players in sync show the first bonus plate")
  eq(gfx:bonusScrollY(), -40, "plate starts 40 px down")
  local visible = 0
  for _ = 1, 40 do
    gfx:update()
    if not gfx.starSprites[0].invisible then visible = visible + 1 end
  end
  eq(visible, 37, "stars spin through sAnim_Star_Spinning then hide")
  check(not gfx.bonus.visible, "bonus plate hides after 32 frames")
end

local ROOM = "r0123456789abcdef"

local Hub = {}
Hub.__index = Hub

function Hub.new(n)
  local self = setmetatable({ order = {}, inbox = {}, present = {}, leader = 0, epoch = 1,
    log = {}, dropped = {}, names = {}, maxState = 0, maxInput = 0, maxResult = 0 }, Hub)
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
      out[#out + 1] = { id = ("%08x"):format(0xa0 + s), name = self.names[s], seat = s, online = true, ready = true }
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
  local c = wireCopy(msg)
  c.seat = msg.seat
  c.relay = msg.relay
  q[#q + 1] = c
end

function Hub:route(from, msg)
  if not self.present[from] then return end
  local bytes = #Json.encode(msg)
  local cap = (msg.type == MG.MSG.RESULT) and 1024 or 512
  if msg.type == MG.MSG.STATE then self.maxState = math.max(self.maxState, bytes) end
  if msg.type == MG.MSG.INPUT then self.maxInput = math.max(self.maxInput, bytes) end
  if msg.type == MG.MSG.RESULT then self.maxResult = math.max(self.maxResult, bytes) end
  if bytes > cap then
    self.dropped[#self.dropped + 1] = { from = from, type = msg.type, why = "cap" }
    return
  end
  local inner = wireCopy(msg)
  if not inner then
    self.dropped[#self.dropped + 1] = { from = from, type = msg.type, why = "schema" }
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
    if s > prev and self.present[s] then nextSeat = s break end
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

local SPECIES = { 4, 25, 1, 7, 133 }

local function makeSeats(n, opts)
  opts = opts or {}
  local hub = Hub.new(n)
  local seats = {}
  local players = {}
  for s = 0, n - 1 do
    players[#players + 1] = { id = ("%08x"):format(0xa0 + s), name = hub.names[s], seat = s,
      trainerId = 0x1000 + s, gender = s % 2 }
  end
  G.hooksFor = function(ctx) return seats[ctx.seat].h.hooks end
  for s = 0, n - 1 do
    local st = { seat = s, h = newHooks(), session = {}, jump = true, answer = "yes", pressAt = 4 }
    seats[s] = st
    local spec = { game = "jump", session = hub:session(s), seat = s, seats = n, players = players,
      seed = 97531, partySlot = 0 }
    local input = { want = nil }
    function input:wasPressed(b) return self.want == b end
    function input:isDown() return false end
    st.input = input
    st.match = MG.Match.new(spec, {
      module = G,
      client = hub:client(s),
      art = art,
      partyMon = { species = SPECIES[s + 1], personality = 0x1000 * (s + 1), otId = 0x2000 + s },
      me = { name = hub.names[s], trainerId = 0x1000 + s, gender = s % 2 },
      countdown = function() return Countdown.new(120, 80, { playSe = function() end }) end,
      onResult = function(msg, match) MG.applyResults(st.session, msg, match.seat, G) end,
    })
  end
  return hub, seats
end

local function plan(st)
  local input = st.input
  input.want = nil
  local sim = st.match.sim
  if not sim then return end
  local g = sim.game
  local gfx = g.gfx
  if gfx.yesno then
    if st.answer == "yes" then
      if gfx.yesno.cursor == 0 then input.want = "a" else input.want = "up" end
    elseif st.answer == "no" then
      if gfx.yesno.cursor == 1 then input.want = "a" else input.want = "down" end
    elseif st.answer == "b" then
      input.want = "b"
    end
    return
  end
  if gfx.msgWindow and gfx.msgWindow.itemId and gfx.msgWindow.shown and st.dismiss then
    input.want = "a"
    return
  end
  if st.jump and g.comm.funcId == F.GAME_ROUND and g.vineState == st.pressAt
      and g.player.monState == MON.NORMAL then
    input.want = "a"
  end
end

local function stepAll(seats, n, hook)
  for _ = 1, n do
    for s = 0, #seats do
      local st = seats[s]
      if st and not st.gone and not st.match:finished() then
        plan(st)
        st.match:step(st.input)
      end
    end
    if hook and hook() then return true end
  end
  return false
end

print("[test] 5. three seats over the fake relay: intro, rounds, sync bonus, leader drop -> seat 1 leads")
do
  local hub, seats = makeSeats(3)
  local sawCountdown, sawNames, sawHighlight = false, false, false
  stepAll(seats, 2000, function()
    local sim = seats[1].match.sim
    if sim then
      local gfx = sim.game.gfx
      if gfx.countdown and gfx.countdown:running() or seats[1].match.phase == "countdown" then sawCountdown = true end
      if gfx.names.visible then
        sawNames = true
        if gfx.names.highlight then sawHighlight = true end
      end
    end
    return seats[0].match.sim and seats[0].match.sim.game.comm.funcId == F.GAME_ROUND
  end)
  local m0, m1, m2 = seats[0].match, seats[1].match, seats[2].match
  eq(m0.phase, "play", "leader playing")
  check(sawNames and sawHighlight, "intro prints every name with our own highlighted")
  check(sawCountdown, "one minigame countdown before the first swing")
  eq(m0.sim.game.comm.funcId, F.GAME_ROUND, "leader reached FUNC_GAME_ROUND")
  eq(countLog(seats[1].h.log, "music", Game.MUS_POKE_JUMP), 1, "MUS_POKE_JUMP starts")
  local bonus, maxRow = false, 0
  stepAll(seats, 20000, function()
    local g = m0.sim.game
    if g.comm.jumpScore > g.comm.jumpsInRow * 10 then bonus = true end
    maxRow = math.max(maxRow, g.comm.jumpsInRow)
    return g.comm.jumpsInRow >= 6
  end)
  local g0 = m0.sim.game
  check(g0.comm.jumpsInRow >= 6, "six clean jumps in a row (" .. g0.comm.jumpsInRow .. ")")
  check(bonus, "players jumping together earned a same-time bonus (score " .. g0.comm.jumpScore .. ")")
  stepAll(seats, 10, function() return m2.sim.game.comm.jumpScore == g0.comm.jumpScore end)
  eq(m2.sim.game.comm.jumpScore, g0.comm.jumpScore, "member score follows the leader")
  check(countLog(seats[2].h.log, "se", Game.SE_LEDGE) > 0, "SE_LEDGE on jumps")
  local se = tables.sound_effects
  check(countLog(seats[2].h.log, "se", se[1]) + countLog(seats[2].h.log, "se", se[2]) > 0,
    "member heard the bonus SE from sSoundEffects")
  local mi = m2.sim.game.monInfo[1]
  eq(mi.personality, 0x2000, "member 1's personality reached member 2 through the leader")
  local scoreBefore = g0.comm.jumpScore
  local rowBefore = g0.comm.jumpsInRow
  seats[0].gone = true
  hub:drop(0)
  stepAll(seats, 5, function() return false end)
  check(m1:isLeader(), "seat 0 dropped: seat 1 leads")
  eq(m2.leader, 1, "seat 2 follows seat 1")
  check(m1.sim.game:isLeader(), "the new leader's sim runs the leader funcs")
  check(m1.sim.game.gone[0] and m2.sim.game.gone[0], "the dropped seat's mon is out of the game")
  stepAll(seats, 20000, function()
    return m1.sim.game.comm.jumpsInRow >= rowBefore + 3
  end)
  local g1 = m1.sim.game
  check(g1.comm.jumpsInRow >= rowBefore + 3, "the swing goes on under the new leader (" .. g1.comm.jumpsInRow .. ")")
  check(g1.comm.jumpScore > scoreBefore, "score carried over and keeps growing")
  stepAll(seats, 10, function() return m2.sim.game.comm.jumpScore == g1.comm.jumpScore end)
  eq(m2.sim.game.comm.jumpScore, g1.comm.jumpScore, "seat 2 follows the new leader's score")

  print("[test] 6. a missed jump ends the round for everyone; records; NO drops the link")
  seats[2].jump = false
  seats[1].answer = "yes"
  seats[2].answer = "no"
  local sawPrompt1, sawPrompt2, sawShake = false, false, false
  stepAll(seats, 20000, function()
    local sim1, sim2 = m1.sim, m2.sim
    if sim1 and sim1.game.gfx.yesno then sawPrompt1 = true end
    if sim2 and sim2.game.gfx.yesno then sawPrompt2 = true end
    if sim1 and sim1.game.gfx:isMonHitShakeActive(2) then sawShake = true end
    return m1:finished() and m2:finished()
  end)
  check(sawShake, "the leader shook the hit mon (SpriteCB_MonHitShake)")
  check(countLog(seats[1].h.log, "se", Game.SE_POKE_JUMP_FAILURE) > 0, "SE_POKE_JUMP_FAILURE")
  check(sawPrompt1 and sawPrompt2, "both seats got \"Want to play again?\" with YES/NO")
  eq(m1.phase, "done", "new leader done")
  eq(m2.phase, "done", "member done")
  check(m1.result ~= nil and m2.result ~= nil, "both seats got game3_mg_result")
  eq(Json.encode(m1.result.results), Json.encode(m2.result.results), "results agree")
  local final = g1.best
  check(final.score > 0 and final.jumpsInRow > 0, "best score/jumps in the result")
  eq(seats[1].session.pokemonJumpRecords.bestJumpScore, final.score, "seat 1 record written from the result")
  eq(seats[2].session.pokemonJumpRecords.jumpsInRow, final.jumpsInRow, "seat 2 jumps-in-a-row record")
  eq(countLog(seats[1].h.log, "records"), 1, "TryUpdateRecords once per game (AskPlayAgain)")
  eq(countLog(seats[2].h.log, "records"), 1, "member too")
  check(m2.sim.game.exited and m1.sim.game.exited, "both ran ClosePokeJumpLink to the fade")
  eq(#hub.dropped, 0, "nothing the relay would drop")
  check(hub.maxState <= 512 and hub.maxInput <= 512 and hub.maxResult <= 1024,
    string.format("byte caps (state %d, input %d, result %d)", hub.maxState, hub.maxInput, hub.maxResult))
  eq(countLog(seats[1].h.log, "maxgames"), 0, "three players: no five-player game counted")
end

print("[test] 7. prize, bag limits, save, play again")
do
  local hub, seats = makeSeats(2)
  seats[0].dismiss, seats[1].dismiss = true, true
  local m0, m1 = seats[0].match, seats[1].match
  stepAll(seats, 20000, function()
    return m0.sim and m0.sim.game.comm.jumpsInRow >= 2
  end)
  local g0 = m0.sim.game
  g0.comm.jumpScore = 7990
  stepAll(seats, 20000, function() return g0.comm.jumpScore >= 8000 end)
  seats[1].h.limit = 1
  seats[0].jump, seats[1].jump = false, false
  local prizeMsg0, prizeMsg1, saving = nil, nil, false
  stepAll(seats, 20000, function()
    local w0 = m0.sim.game.gfx.msgWindow
    local w1 = m1.sim.game.gfx.msgWindow
    if w0 and w0.shown and w0.key == "gText_AwesomeWonF701F700" then prizeMsg0 = w0 end
    if w1 and w1.shown and w1.key == "gText_AwesomeWonF701F700" then prizeMsg1 = w1 end
    if w0 and w0.key == "gText_SavingDontTurnOffPower" and w0.shown then saving = true end
    return m0.sim.game.comm.funcId == F.ASK_PLAY_AGAIN
  end)
  check(prizeMsg0 ~= nil and prizeMsg1 ~= nil, "both seats print the prize message")
  eq(prizeMsg0 and prizeMsg0.quantity, 2, "8000 points: two berries")
  eq(prizeMsg1 and prizeMsg1.itemId, prizeMsg0 and prizeMsg0.itemId, "same berry for every seat (leader's comm.data)")
  local item = prizeMsg0 and prizeMsg0.itemId
  local isPrize = false
  for _, id in ipairs(tables.prize_items) do if id == item then isPrize = true end end
  check(isPrize, "prize is one of sPrizeItems (" .. tostring(item) .. ")")
  eq(seats[0].h.bag[item], 2, "seat 0 bag got both berries")
  eq(seats[1].h.bag[item], 1, "seat 1 bag limited by CheckBagHasSpace")
  eq(countLog(seats[0].h.log, "fanfare", 257), 1, "MUS_LEVEL_UP fanfare")
  check(saving, "SAVING... DON'T TURN OFF THE POWER.")
  eq(countLog(seats[0].h.log, "save"), 1, "Task_LinkFullSave on the leader")
  eq(countLog(seats[1].h.log, "save"), 1, "and on the member")
  eq(countLog(seats[0].h.log, "records"), 1, "records written in SavePokeJump")
  seats[0].answer, seats[1].answer = "yes", "yes"
  local introAgain = false
  stepAll(seats, 20000, function()
    local g = m1.sim.game
    if g.comm.funcId == F.GAME_INTRO then introAgain = true end
    return m0.sim.game.gamesStarted >= 2 and m1.sim.game.gamesStarted >= 2
  end)
  check(introAgain, "YES + YES resets the game")
  eq(m0.sim.game.comm.jumpScore, 0, "score back to 0")
  check(m1.sim.game.gfx.countdown ~= nil, "the replay plays its own minigame countdown")
  seats[0].answer, seats[1].answer = "b", "yes"
  stepAll(seats, 20000, function() return m0:finished() and m1:finished() end)
  eq(m0.phase, "done", "B at the prompt ends the link (leader)")
  eq(m1.phase, "done", "member follows")
  eq(countLog(seats[0].h.log, "records"), 3, "records once more for the second game")
  eq(#hub.dropped, 0, "nothing dropped")
end

print("[test] 8. five players count toward gamesWithMaxPlayers; bag full message")
do
  local hub, seats = makeSeats(5)
  stepAll(seats, 3)
  for s = 0, 4 do
    eq(countLog(seats[s].h.log, "maxgames"), 1, "seat " .. s .. " IncrementGamesWithMaxPlayers")
  end
  local sim, h = standalone()
  local g = sim.game
  h.full = true
  g.comm.data = 1 * 0x1000 + 138
  g.helperState = 0
  g.joy = {}
  local texts = {}
  for _ = 1, 400 do
    g.joy = { a = (g.helperState == 5) }
    local r = g:tryGivePrize()
    g.gfx:update()
    local w = g.gfx.msgWindow
    if w and w.shown then texts[w.key] = true end
    if not r then break end
  end
  check(texts.gText_AwesomeWonF701F700, "prize message first")
  check(texts.gText_CantHoldMore, "full bag: You can't hold any more!")
  eq(h.bag[138], nil, "nothing added")
end

print("[test] 9. snapshot carries what a new leader needs")
do
  local sim = standalone({ n = 3 })
  local g = sim.game
  g.excellentsInRow, g.excellentsInRowRecord = 3, 4
  g.numPlayersAtPeak, g.initScoreUpdate, g.giveBonus = 2, true, true
  g.atJumpPeak3[0], g.atJumpPeak3[2] = true, true
  g.best.score = 1230
  local s = Wire.sanitize(Json.decode(Json.encode({ type = MG.MSG.STATE, f = 3, e = 1, s = sim:snapshot() }))).s
  local member = standalone({ n = 3, seat = 1 })
  member.game.comm.funcId = F.GAME_ROUND
  member.game.funcActive = true
  member:becomeLeader(s)
  local mg = member.game
  check(mg:isLeader(), "becomeLeader switches the funcs")
  eq(mg.excellentsInRowRecord, 4, "excellents record carried")
  eq(mg.numPlayersAtPeak, 2, "peak count carried")
  check(mg.giveBonus and mg.atJumpPeak3[0] and mg.atJumpPeak3[2] and not mg.atJumpPeak3[1], "pending bonus carried")
  eq(mg.best.score, 1230, "session best carried")
  check(mg.gone[0], "old leader is out")
  local big = standalone({ n = 5 }).game
  for i = 0, 4 do
    big.monInfo[i].personality, big.monInfo[i].species, big.monInfo[i].shiny = 0xFFFFFFFF, 412, true
    local p = big.players[i]
    p.monState, p.jumpState, p.jumpTimeStart, p.funcFinished = 2, 2, 65535, true
    big.memberFuncIds[i], big.playAgainStates[i] = 9, 2
    big.atJumpPeak2[i], big.atJumpPeak3[i] = true, true
  end
  big.comm.funcId, big.comm.data, big.comm.jumpsInRow, big.comm.jumpScore, big.comm.receivedBonusFlags = 9, 65535, 9999, 99990, 31
  big.excellentsInRow, big.excellentsInRowRecord, big.numPlayersAtPeak = 9999, 9999, 5
  big.best = { score = 99990, jumpsInRow = 9999, excellentsInRow = 9999 }
  local bytes = #Json.encode({ type = MG.MSG.STATE, f = 2147483647, e = 2147483647, s = big:leaderPacketOut(true) })
  check(bytes <= 512, "worst-case five-seat state with mon info fits the 512-byte cap (" .. bytes .. ")")
  local ibytes = #Json.encode({ type = MG.MSG.INPUT, f = 2147483647, i = big:memberPacketOut() })
  check(ibytes <= 512, "member input fits (" .. ibytes .. ")")
end

finish()

local R = require("src.core.game3.minigames.berry_crush.rules")
local Phys = require("src.core.game3.minigames.berry_crush.physics")

local Sim = {}
Sim.__index = Sim

Sim.PH = { PICK = 1, DROP = 2, COUNTDOWN = 3, PLAY = 4, FINISH = 5, TIMEUP = 6, RESULTS = 7, SAVE = 8, STOP = 9 }
Sim.ACK = { PICKED = 1, LID = 2, COUNTDOWN = 3, EFFECTS = 4, STANDBY = 5, ANSWER = 6 }
Sim.ANSWER = { YES = 1, NO = 2, NO_BERRIES = 4 }
-- pokefirered/src/save.c:882
Sim.SAVE_FRAMES = 93
-- pokefirered/src/berry_crush.c:2378
Sim.STOP_FRAMES = 120

-- pokefirered/include/constants/songs.h:9
Sim.SE = {
  SELECT = 5, FAILURE = 26, FALL = 37, BALL_THROW = 54,
  BREAKABLE_DOOR = 70, MUD_BALL = 71, M_STRENGTH = 207,
}
-- pokefirered/include/constants/songs.h:281
Sim.MUS_GAME_CORNER = 273
-- pokefirered/include/constants/songs.h:311
Sim.MUS_POKE_CENTER = 303
-- pokefirered/include/constants/game_stat.h:55
Sim.GAME_STAT_BERRY_CRUSH_POINTS = 51

-- pokefirered/src/berry_crush.c:448
Sim.MSG = {
  PICK_BERRY = "gText_BerryCrush_AreYouReady",
  WAIT_PICK = "gText_BerryCrush_WaitForOthersToChooseBerry",
  POWDER = "gText_BerryCrush_GainedXUnitsOfPowder",
  TIMES_UP = "gText_BerryCrush_TimeUp",
  COMM_STANDBY = "gText_BerryCrush_CommunicationStandby",
  PLAY_AGAIN = "gText_BerryCrush_WantToPlayAgain",
  NO_BERRIES = "gText_BerryCrush_NoBerries",
  DROPPED = "gText_BerryCrush_MemberDroppedOut",
  SAVING = "gText_SavingDontTurnOffThePower2",
}

local PH = Sim.PH
local floor = math.floor

function Sim.new(G, ctx)
  local art = assert(type(ctx.art) == "table" and ctx.art, "berry_crush art is not loaded")
  local T = assert(art.tables, "berry_crush/tables.lua is not loaded")
  local players = type(ctx.players) == "table" and ctx.players or {}
  local n = #players
  assert(n >= 2 and n <= R.MAX_PLAYERS, "berry crush needs 2 to 5 players")
  local self = setmetatable({
    G = G, ctx = ctx, art = art, T = T, players = players, n = n,
    seat = tonumber(ctx.seat) or 0, leader = ctx.leader and true or false,
    rng = ctx.rng, hooks = setmetatable({}, { __index = G.hooks }),
    A = R.newState(n),
    berry = -1, ack = 0, presses = 0, held = 0, predN = 0, predicted = 0,
    stage = "show", sf = 0, sub = 0, first = true,
    displayOn = false, fadeY = 16, fadeTo = 16, blend = nil,
    depth = R.CRUSHER_START_Y, vib = 0, vtimer = 0, timerVal = 0, timerShown = false,
    vq = {}, lastQT = -1, outq = {}, playedSound = false,
    impacts = {}, sparkles = {}, berries = nil, dropIdx = 0, gap = 0,
    printer = nil, countdown = nil, res = nil, page = 0, pageOpen = false, pageLines = nil,
    over = false, frame = 0, inp = nil, lv = nil, cnt = 0,
    round = 0, answer = 0, yesNo = nil, stop = false,
    scratchPending = {}, scratchPressed = {},
  }, Sim)
  self.me = 1
  for p, pl in ipairs(players) do
    if tonumber(pl.seat) == self.seat then self.me = p end
  end
  if self.leader then self.A.ld = self.me end
  self.coords = {}
  -- pokefirered/src/berry_crush.c:3224
  local pos = T.player_id_to_pos_id[n - 1]
  for p = 1, n do
    self.coords[p] = T.player_coords[pos[p] + 1]
    self.impacts[p] = Phys.newImpact(self.coords[p])
  end
  for i = 0, 10 do self.sparkles[i + 1] = Phys.newSparkle(i, T) end
  return self
end

function Sim:session()
  return self.hooks.session and self.hooks.session() or nil
end

function Sim:se(id)
  if self.hooks.playSe then self.hooks.playSe(id) end
end

function Sim:song(id)
  if self.hooks.playSong then self.hooks.playSong(id) end
end

function Sim:go(stage)
  self.stage = stage
  self.sf = 0
  self.sub = 0
end

function Sim:print(key, vars, clear)
  local Printer = require("src.ui.game3.minigames.berry_crush.printer")
  local text = self.hooks.text(key, vars)
  local speed = Printer.speedFor(self.hooks.textSpeed and self.hooks.textSpeed() or 1)
  local me = self
  self.printer = Printer.new(text, speed, { clear = clear, playSe = function(id) me:se(id) end,
    music = function(cmd, arg) me:music(cmd, arg) end })
end

-- pokefirered/src/text.c:721
function Sim:music(cmd, arg)
  local h = self.hooks
  if cmd == 0x17 then
    if h.pauseMusic then h.pauseMusic() end
  elseif cmd == 0x18 then
    if h.resumeMusic then h.resumeMusic() end
  elseif cmd == 0x0B then
    self:song(arg)
  end
end

function Sim:seatOf(p)
  local pl = self.players[p]
  return pl and tonumber(pl.seat) or (p - 1)
end

function Sim:indexOfSeat(seat)
  seat = tonumber(seat)
  for p = 1, self.n do
    if self:seatOf(p) == seat then return p end
  end
  return nil
end

-- pokefirered/src/berry_crush.c:1711
function Sim:localInput(input)
  self.inp = input
  if self.stage == "play" and input then
    if input.wasPressed and input:wasPressed("a") then self.presses = self.presses + 1 end
    if input.isDown and input:isDown("a") and self.held < self.vtimer then
      self.held = self.held + 1
    end
  end
  return { r = self.round, b = self.berry, a = self.ack, n = self.presses, h = self.held, y = self.answer }
end

function Sim:handleInput(input)
  self.inp = input
end

function Sim:predict(i)
  if type(i) ~= "table" then return end
  local n = tonumber(i.n) or 0
  while self.predN < n do
    self.predN = self.predN + 1
    if self.stage == "play" then
      self.predicted = self.predicted + 1
      Phys.startImpact(self.impacts[self.me], (self.predN - 1) % 3 + 1, self.T)
      self:se(Sim.SE.MUD_BALL)
    end
  end
end

local function inputOf(inputs, seat)
  local i = inputs and inputs[seat + 1]
  if type(i) ~= "table" then return nil end
  return i
end

function Sim:inGame(p, present)
  if self.A.gone[p] then return false end
  return present == nil or present[self:seatOf(p) + 1] == true
end

function Sim:roundInput(inputs, p)
  local i = inputOf(inputs, self:seatOf(p))
  if i and floor(tonumber(i.r) or -1) == self.A.round then return i end
  return nil
end

function Sim:gate(inputs, present, minAck, needBerry)
  for p = 1, self.n do
    if self:inGame(p, present) then
      local i = self:roundInput(inputs, p)
      if not i or (tonumber(i.a) or 0) < minAck then return false end
      if needBerry and (tonumber(i.b) or -1) < 0 then return false end
    end
  end
  return true
end

-- pokefirered/src/berry_crush.c:2286
function Sim:allAgain(inputs, present)
  for p = 1, self.n do
    if not self:inGame(p, present) then return false end
    local i = self:roundInput(inputs, p)
    if not i or floor(tonumber(i.y) or 0) ~= Sim.ANSWER.YES then return false end
  end
  return true
end

function Sim:leaderStep(inputs, present)
  local A = self.A
  local pending = self.scratchPending
  for p = 1, self.n do
    if present and p ~= self.me and present[self:seatOf(p) + 1] ~= true then A.gone[p] = true end
    local i = self:roundInput(inputs, p)
    if i then
      A.held[p] = math.max(0, floor(tonumber(i.h) or 0))
      pending[p] = floor(tonumber(i.b) or -1)
    else
      pending[p] = A.berries[p]
    end
  end
  if A.ph == PH.PICK then
    -- pokefirered/src/berry_crush.c:1393
    if self:gate(inputs, present, Sim.ACK.PICKED, true) then
      R.setBerries(A, self.T, pending)
      A.ph = PH.DROP
    end
  elseif A.ph == PH.DROP then
    if self:gate(inputs, present, Sim.ACK.LID) then A.ph = PH.COUNTDOWN end
  elseif A.ph == PH.COUNTDOWN then
    if self:gate(inputs, present, Sim.ACK.COUNTDOWN) then
      for p = 1, self.n do
        local i = self:roundInput(inputs, p)
        if i then A.pl[p].sn = math.max(A.pl[p].sn, floor(tonumber(i.n) or 0)) end
      end
      A.ph = PH.PLAY
    end
  elseif A.ph == PH.PLAY then
    self:leaderPlay(inputs, present)
  elseif A.ph == PH.FINISH or A.ph == PH.TIMEUP then
    if self:gate(inputs, present, Sim.ACK.EFFECTS) then
      if A.ended == PH.TIMEUP then
        A.res = { time = A.timer, timeUp = true, presses = {}, random = {} }
      else
        local page = self.rng and (self.rng:next() % R.NUM_RANDOM_PAGES) or 0
        A.res = R.tabulate(A, page)
      end
      A.ph = PH.RESULTS
    end
  elseif A.ph == PH.RESULTS then
    if self:gate(inputs, present, Sim.ACK.STANDBY) then A.ph = PH.SAVE end
  elseif A.ph == PH.SAVE then
    if self:gate(inputs, present, Sim.ACK.ANSWER) then
      if self:allAgain(inputs, present) then
        self.A = R.nextRound(A)
      else
        A.ph = PH.STOP
      end
    end
  end
end

-- pokefirered/src/berry_crush.c:1825
function Sim:leaderPlay(inputs, present)
  local A = self.A
  if A.lastT >= 0 then
    A.timer = A.lastT
    if A.lastEg then
      if A.timer >= R.MAX_TIME then
        A.timer = R.MAX_TIME
        A.ph = PH.TIMEUP
      else
        A.ph = PH.FINISH
      end
      A.ended = A.ph
      return
    end
  end
  local pressed = self.scratchPressed
  for p = 1, self.n do
    local i = self:roundInput(inputs, p)
    local pl = A.pl[p]
    pressed[p] = nil
    if i and self:inGame(p, present) and (tonumber(i.n) or 0) > pl.sn then
      pl.sn = pl.sn + 1
      pressed[p] = true
    end
  end
  local rec = R.leaderFrame(A, pressed, self.T)
  self.outq[#self.outq + 1] = rec
  self.vq[#self.vq + 1] = rec
  self.lastQT = rec.t
end

function Sim:snapshot()
  local A = self.A
  local q = {}
  for _, rec in ipairs(self.outq) do R.encodeRecord(rec, q) end
  self.outq = {}
  local b, m = {}, {}
  for p = 1, self.n do
    b[p] = A.berries[p]
    local pl = A.pl[p]
    m[#m + 1] = pl.np
    m[#m + 1] = pl.ns
    m[#m + 1] = pl.st
    m[#m + 1] = pl.mx
    m[#m + 1] = pl.td
    m[#m + 1] = pl.it
    m[#m + 1] = pl.fl
    m[#m + 1] = pl.sn
    m[#m + 1] = A.held[p]
  end
  local l = {
    A.lt, A.timer, A.tp, A.sc, A.bc, A.nb, A.nc, A.sa, A.bs and 1 or 0, A.nd,
    A.gc, A.gi, A.gn, A.gv and 1 or 0, A.lastT, A.lastEg and 1 or 0, A.ended or 0,
  }
  local g = 0
  for p = 1, self.n do
    if A.gone[p] then g = g + 2 ^ (p - 1) end
  end
  local s = { p = A.ph, rd = A.round, ld = self.me, g = g, b = b, q = q, l = l, m = m }
  if A.res and A.ph >= PH.RESULTS then s.r = R.encodeResults(A.res, self.n) end
  return s
end

local function int(v, d)
  local n = tonumber(v)
  if n == nil then return d end
  return floor(n)
end

function Sim:applySnapshot(s)
  if type(s) ~= "table" then return end
  local rd = int(s.rd, self.A.round)
  if rd > self.A.round then
    local A0 = self.A
    while A0.round < rd do A0 = R.nextRound(A0) end
    self.A = A0
  elseif rd < self.A.round then
    return
  end
  local A = self.A
  A.ph = int(s.p, A.ph)
  A.ld = int(s.ld, A.ld)
  local g = int(s.g, 0)
  for p = 1, self.n do
    if floor(g / 2 ^ (p - 1)) % 2 == 1 then A.gone[p] = true end
  end
  if type(s.r) == "table" and A.ph >= PH.RESULTS then A.res = R.decodeResults(s.r, self.n) end
  if type(s.b) == "table" and A.ph >= PH.DROP then
    local bs = {}
    for p = 1, self.n do bs[p] = int(s.b[p], -1) end
    R.setBerries(A, self.T, bs)
  end
  local l = s.l
  if type(l) == "table" then
    A.lt, A.timer, A.tp, A.sc, A.bc = int(l[1], A.lt), int(l[2], A.timer), int(l[3], A.tp), int(l[4], A.sc), int(l[5], A.bc)
    A.nb, A.nc, A.sa, A.bs, A.nd = int(l[6], A.nb), int(l[7], A.nc), int(l[8], A.sa), int(l[9], 0) == 1, int(l[10], A.nd)
    A.gc, A.gi, A.gn, A.gv = int(l[11], A.gc), int(l[12], A.gi), int(l[13], A.gn), int(l[14], 0) == 1
    A.lastT, A.lastEg = int(l[15], A.lastT), int(l[16], 0) == 1
    local ended = int(l[17], 0)
    A.ended = ended ~= 0 and ended or nil
  end
  local m = s.m
  if type(m) == "table" then
    for p = 1, self.n do
      local o = (p - 1) * 9
      local pl = A.pl[p]
      pl.np, pl.ns, pl.st, pl.mx = int(m[o + 1], pl.np), int(m[o + 2], pl.ns), int(m[o + 3], pl.st), int(m[o + 4], pl.mx)
      pl.td, pl.it, pl.fl, pl.sn = int(m[o + 5], pl.td), int(m[o + 6], pl.it), int(m[o + 7], pl.fl), int(m[o + 8], pl.sn)
      A.held[p] = int(m[o + 9], A.held[p])
    end
  end
  for _, rec in ipairs(R.decodeRecords(s.q)) do
    if rec.t > self.lastQT then
      self.vq[#self.vq + 1] = rec
      self.lastQT = rec.t
    end
  end
end

function Sim:becomeLeader(last)
  if type(last) == "table" then self:applySnapshot(last) end
  local old = self.A.ld
  if old and old ~= self.me then self.A.gone[old] = true end
  self.A.ld = self.me
  self.leader = true
  self.outq = {}
end

function Sim:becomeMember()
  self.leader = false
  self.outq = {}
end

function Sim:finished()
  return self.A.ph == PH.STOP
end

function Sim:results()
  local A = self.A
  local out = {}
  for p = 1, self.n do
    local np = A.pl[p].np
    out[p] = { seat = self:seatOf(p), score = np, stats = { p = np, rd = A.round } }
  end
  return { results = out, powder = {} }
end

function Sim.parseResult(msg)
  local out = { entries = {}, n = 0 }
  for _, r in ipairs(type(msg) == "table" and type(msg.results) == "table" and msg.results or {}) do
    local s = type(r.stats) == "table" and r.stats or {}
    out.entries[#out.entries + 1] = { seat = int(r.seat, -1), p = int(s.p, int(r.score, 0)), round = int(s.rd, 0) }
  end
  out.n = #out.entries
  return out
end

function Sim:showResults()
  self.stop = true
end

-- pokefirered/src/berry_crush.c:2146
function Sim:takeResults(res)
  local copy = {}
  for k, v in pairs(res) do copy[k] = v end
  copy.presses, copy.random = {}, {}
  for p = 1, self.n do
    copy.presses[p] = (res.presses and res.presses[p]) or 0
    copy.random[p] = (res.random and res.random[p]) or 0
  end
  copy.speed = R.pressingSpeed(copy.time, copy.total)
  copy.s0, copy.rank0, copy.s1, copy.rank1 = R.rank(copy.presses, copy.random)
  self.res = copy
  if copy.timeUp then return end
  -- pokefirered/src/berry_crush.c:1049
  local session = self:session()
  copy.newRecord = self.hooks.updateRecord and self.hooks.updateRecord(session, self.n, copy.speed) and true or false
  if self.hooks.givePowder then self.hooks.givePowder(session, copy.powder) end
end

function Sim:resultsDone()
  return self.over
end

function Sim:effectsFinished()
  for p = 1, self.n do
    if not self.impacts[p].invisible then return false end
  end
  for _, sp in ipairs(self.sparkles) do
    if not sp.invisible then return false end
  end
  if self.vib ~= 0 then self.vib = 0 end
  return true
end

-- pokefirered/src/berry_crush.c:2779
function Sim:applyRecord(rec)
  self.vtimer = rec.t
  self.depth = rec.d
  self.vib = rec.v
  local num, onlyPredicted = 0, true
  for p = 1, self.n do
    local fl = R.recordFlags(rec, p)
    if fl ~= 0 then
      num = num + 1
      if p == self.me and self.predicted > 0 then
        self.predicted = self.predicted - 1
      else
        onlyPredicted = false
        Phys.startImpact(self.impacts[p], fl, self.T)
      end
    end
  end
  if num == 0 then
    self.playedSound = false
    return
  end
  Phys.spawnSparkles(self.sparkles, rec, R.u8(rec.t % 3), self.T)
  if self.playedSound then
    self.playedSound = false
  else
    if not (num == 1 and onlyPredicted) then
      self:se(num == 1 and Sim.SE.MUD_BALL or Sim.SE.BREAKABLE_DOOR)
    end
    self.playedSound = true
  end
end

function Sim:vibStep()
  local lv = self.lv
  local rows = self.T.intro_outro_vibration
  self.vib = rows[lv.idx + 1][lv.counter + 1]
  lv.counter = lv.counter + 1
  if lv.counter < lv.num then return false end
  if lv.idx == 0 then return true end
  lv.idx = lv.idx - 1
  lv.num = rows[lv.idx + 1][1]
  lv.counter = 0
  return false
end

function Sim:startOutroVibration()
  self.lv = { idx = 4, counter = 0, num = self.T.intro_outro_vibration[5][1] }
end

local stages = {}

-- pokefirered/src/berry_crush.c:2490
function stages.show(self)
  if self.sf == 1 then
    self.displayOn = false
    self.depth = R.CRUSHER_START_Y
    self.vib = 0
  end
  if self.sf >= 10 then
    self.displayOn = true
    self.timerShown = not self.first
    self.fadeY, self.fadeTo = 16, 0
    self:go(self.first and "fadein" or "fadein2")
  end
end

function stages.fadein(self)
  if self.sf > 1 and self.fadeY == self.fadeTo then self:go("ready") end
end

-- pokefirered/src/berry_crush.c:1316
function stages.ready(self)
  if self.sf < 2 then return end
  self:song(Sim.MUS_GAME_CORNER)
  self:askPick()
end

-- pokefirered/src/berry_crush.c:2424
function Sim:askPick()
  if self.hooks.incrementGameStat then
    self.hooks.incrementGameStat(self:session(), Sim.GAME_STAT_BERRY_CRUSH_POINTS)
  end
  self:print(Sim.MSG.PICK_BERRY, nil, true)
  self:go("ask")
end

-- pokefirered/src/berry_crush.c:1337
function stages.ask(self)
  if self.printer and self.printer:done() then
    self.printer = nil
    self:go("hide")
  end
end

-- pokefirered/src/berry_crush.c:2588
function stages.hide(self)
  if self.sf == 2 then self.fadeTo = 16 end
  if self.sub == 0 and self.sf > 2 and self.fadeY == 16 then
    self.sub = 1
    self.gap = 0
  elseif self.sub == 1 then
    self.gap = self.gap + 1
    if self.gap >= 5 then
      self.displayOn = false
      self:go("pouch")
    end
  end
end

-- pokefirered/src/berry_crush.c:1359
function stages.pouch(self)
  if self.sf ~= 1 then return end
  self.first = false
  local me = self
  self.hooks.pickBerry(self, function(itemId) me:onBerryPicked(itemId) end)
end

-- pokefirered/src/berry_crush.c:1017
function Sim:onBerryPicked(itemId)
  if self.stage ~= "pouch" then return end
  local idx = R.berryIndex(itemId)
  if idx then
    if self.hooks.removeItem then self.hooks.removeItem(self:session(), itemId) end
  else
    idx = 0
  end
  self.berry = idx
  self:go("show")
end

function stages.fadein2(self)
  if self.sf > 1 and self.fadeY == self.fadeTo then
    self:print(Sim.MSG.WAIT_PICK, nil, false)
    self:go("waitmsg")
  end
end

-- pokefirered/src/berry_crush.c:1366
function stages.waitmsg(self)
  if self.printer and self.printer:done() then
    self.ack = math.max(self.ack, Sim.ACK.PICKED)
    self:go("waitdrop")
  end
end

function stages.waitdrop(self)
  if self.A.ph < PH.DROP then return end
  self.printer = nil
  self.berries = {}
  for p = 1, self.n do
    local b = self.A.berries[p]
    if b and b >= 0 then self.berries[p] = Phys.newBerry(self.coords[p], b) end
  end
  self:go("drop")
end

function Sim:nextDrop()
  repeat
    self.dropIdx = self.dropIdx + 1
  until self.dropIdx > self.n or self.berries[self.dropIdx]
  if self.dropIdx > self.n then return false end
  Phys.dropBerry(self.berries[self.dropIdx])
  self:se(Sim.SE.BALL_THROW)
  self.sub = 1
  return true
end

-- pokefirered/src/berry_crush.c:1418
function stages.drop(self)
  if self.sub == 0 then
    if self.sf >= 2 then
      self.dropIdx = 0
      if not self:nextDrop() then
        self.sub = 3
        self.gap = 0
      end
    end
  elseif self.sub == 1 then
    local b = self.berries[self.dropIdx]
    if not b or b.destroyed then
      self.sub = 2
      self.gap = 0
    end
  elseif self.sub == 2 then
    self.gap = self.gap + 1
    if self.gap >= 2 and not self:nextDrop() then
      self.sub = 3
      self.gap = 0
    end
  elseif self.sub == 3 then
    self.gap = self.gap + 1
    if self.gap >= 2 then
      self.berries = nil
      self:se(Sim.SE.FALL)
      self:go("lid")
    end
  end
end

-- pokefirered/src/berry_crush.c:1473
function stages.lid(self)
  self.depth = self.depth + 4
  if self.depth < 0 then return end
  self.depth = 0
  self:startOutroVibration()
  self:se(Sim.SE.M_STRENGTH)
  self:go("lidvib")
end

function stages.lidvib(self)
  if self:vibStep() then self:go("lidend") end
end

function stages.lidend(self)
  self.vib = 0
  self.ack = math.max(self.ack, Sim.ACK.LID)
  self:go("waitcd")
end

-- pokefirered/src/berry_crush.c:1520
function stages.waitcd(self)
  if self.A.ph < PH.COUNTDOWN then return end
  self.countdown = self.hooks.newCountdown(self)
  self:go("countdown")
end

function stages.countdown(self)
  if self.countdown and self.countdown:step() then return end
  self.countdown = nil
  self.ack = math.max(self.ack, Sim.ACK.COUNTDOWN)
  self:go("waitplay")
end

function stages.waitplay(self)
  if self.A.ph < PH.PLAY then return end
  self.playedSound = false
  self:go("play")
end

-- pokefirered/src/berry_crush.c:1794
function stages.play(self)
  local backlog = #self.vq
  local take = backlog > 6 and (backlog - 3) or 1
  local any = false
  for _ = 1, take do
    local rec = table.remove(self.vq, 1)
    if not rec then break end
    any = true
    self:applyRecord(rec)
    if rec.eg then
      self.timerVal = self.vtimer
      if self.vtimer >= R.MAX_TIME then
        self.vtimer = R.MAX_TIME
        self:go("timeup")
      else
        self:go("finish")
      end
      return
    end
  end
  if not any then self.playedSound = false end
  self.timerVal = self.vtimer
end

-- pokefirered/src/berry_crush.c:1889
function stages.finish(self)
  if self.sub == 0 then
    self:se(Sim.SE.M_STRENGTH)
    self.blend = { 1, 1, 0 }
    self.cnt = 2
    self.sub = 1
  elseif self.sub == 1 then
    self.cnt = self.cnt - 1
    if self.cnt ~= -1 then return end
    self.blend = nil
    self:startOutroVibration()
    self.sub = 2
  elseif self.sub == 2 then
    if self:vibStep() then self.sub = 3 end
  elseif self.sub == 3 then
    self.vib = 0
    self.sub = 4
  elseif self.sub == 4 then
    if not self:effectsFinished() then return end
    self.ack = math.max(self.ack, Sim.ACK.EFFECTS)
    self:go("tabwait")
  end
end

-- pokefirered/src/berry_crush.c:1946
function stages.timeup(self)
  if self.sub == 0 then
    self:se(Sim.SE.FAILURE)
    self.blend = { 1, 0, 0 }
    self.cnt = 4
    self.sub = 1
  elseif self.sub == 1 then
    self.cnt = self.cnt - 1
    if self.cnt ~= -1 then return end
    self.blend = nil
    self.sub = 2
  elseif self.sub == 2 then
    if not self:effectsFinished() then return end
    self.vib = 0
    self.ack = math.max(self.ack, Sim.ACK.EFFECTS)
    self:go("tabwait")
  end
end

-- pokefirered/src/berry_crush.c:1986
function stages.tabwait(self)
  local A = self.A
  if A.ph < PH.RESULTS or not A.res then return end
  self:takeResults(A.res)
  if self.res.timeUp then
    self:print(Sim.MSG.TIMES_UP, nil, true)
    self:go("timeupmsg")
  else
    self.page = 0
    self:go("results")
  end
end

function Sim:openPage()
  local View = require("src.ui.game3.minigames.berry_crush.view")
  self.pageLines, self.pageWin = View.buildPage(self, self.page)
  self.pageOpen = true
end

-- pokefirered/src/berry_crush.c:2162
function stages.results(self, inp)
  if self.sub == 0 then
    if self.sf == 1 then self.timerShown = false end
    local build = self.page == 2 and 6 or 5
    if self.sf >= build then
      self:openPage()
      self.sub = 1
    end
  elseif self.sub == 1 then
    self.cnt = 30
    self.sub = 2
  elseif self.sub == 2 then
    if self.cnt ~= 0 then
      self.cnt = self.cnt - 1
      return
    end
    if not (inp and inp.wasPressed and inp:wasPressed("a")) then return end
    self:se(Sim.SE.SELECT)
    self.pageOpen = false
    self.pageLines = nil
    self.sub = 3
  elseif self.sub == 3 then
    if self.page < 2 then
      self.page = self.page + 1
      self.sf = 0
      self.sub = 0
      return
    end
    local s = self:session()
    local total = type(s) == "table" and tonumber(s.berryPowder) or 0
    self:print(Sim.MSG.POWDER, { tostring(self.res.powder), tostring(total) }, true)
    self:go("powder")
  end
end

function stages.powder(self)
  if self.printer and self.printer:done() then
    self.printer = nil
    self:print(Sim.MSG.COMM_STANDBY, nil, false)
    self:go("standby")
  end
end

-- pokefirered/src/berry_crush.c:2206
function stages.timeupmsg(self)
  if self.printer and self.printer:done() then
    self.printer = nil
    self.timerShown = false
    self:print(Sim.MSG.COMM_STANDBY, nil, false)
    self:go("standby")
  end
end

function stages.standby(self)
  if self.printer and self.printer:done() then
    self.ack = math.max(self.ack, Sim.ACK.STANDBY)
    self:go("savewait")
  end
end

-- pokefirered/src/berry_crush.c:2218
function stages.savewait(self)
  if self.A.ph < PH.SAVE then return end
  self:print(Sim.MSG.SAVING, nil, false)
  self.printer.speed = 0
  while not self.printer:printed() do self.printer:tick(nil) end
  if self.hooks.save then self.hooks.save() end
  self:go("saving")
end

function stages.saving(self)
  if self.sf < Sim.SAVE_FRAMES then return end
  self:print(Sim.MSG.PLAY_AGAIN, nil, false)
  self:go("askagain")
end

-- pokefirered/src/berry_crush.c:2243
function stages.askagain(self)
  if self.printer and self.printer:done() then
    self.yesNo = 0
    self:go("yesno")
  end
end

function stages.yesno(self, inp)
  if not (inp and inp.wasPressed) or self.sf < 2 then return end
  local answer
  if inp:wasPressed("up") and self.yesNo ~= 0 then
    self.yesNo = 0
    self:se(Sim.SE.SELECT)
  elseif inp:wasPressed("down") and self.yesNo ~= 1 then
    self.yesNo = 1
    self:se(Sim.SE.SELECT)
  elseif inp:wasPressed("a") then
    self:se(Sim.SE.SELECT)
    if self.yesNo == 0 then
      local has = self.hooks.hasBerry and self.hooks.hasBerry(self:session())
      answer = has and Sim.ANSWER.YES or Sim.ANSWER.NO_BERRIES
    else
      answer = Sim.ANSWER.NO
    end
  elseif inp:wasPressed("b") then
    self:se(Sim.SE.SELECT)
    answer = Sim.ANSWER.NO
  end
  if not answer then return end
  self.yesNo = nil
  self.answerGiven = answer
  self.printer = nil
  self:print(Sim.MSG.COMM_STANDBY, nil, false)
  self:go("answerwait")
end

-- pokefirered/src/berry_crush.c:2286
function stages.answerwait(self)
  if self.printer and self.printer:printed() and self.answer == 0 then
    self.answer = self.answerGiven
    self.ack = math.max(self.ack, Sim.ACK.ANSWER)
  end
  if self.answer == 0 then return end
  if self.A.round > self.round then
    self:go("again")
  elseif self.A.ph == PH.STOP or self.stop then
    self:go("stop")
  end
end

-- pokefirered/src/berry_crush.c:2333
function stages.again(self)
  if self.sub == 0 then
    self.fadeTo = 16
    self.fadeDelay = 1
    self.sub = 1
  elseif self.sub == 1 then
    if self.fadeY ~= 16 then return end
    self.printer = nil
    self:resetRound()
    self.fadeDelay = 0
    self.fadeTo = 0
    self.sub = 2
  elseif self.sub == 2 then
    if self.fadeY ~= 0 then return end
    self:askPick()
  end
end

function Sim:resetRound()
  self.round = self.A.round
  self.berry, self.ack, self.held, self.answer, self.answerGiven = -1, 0, 0, 0, nil
  self.res, self.vq, self.lastQT, self.predicted, self.predN = nil, {}, -1, 0, self.presses
  self.timerVal, self.vtimer, self.berries, self.playedSound = 0, 0, nil, false
  self.depth, self.vib, self.pageOpen, self.pageLines = R.CRUSHER_START_Y, 0, false, nil
end

-- pokefirered/src/berry_crush.c:2363
function stages.stop(self)
  if self.sub == 0 then
    local key = self.answer == Sim.ANSWER.NO_BERRIES and Sim.MSG.NO_BERRIES or Sim.MSG.DROPPED
    self:print(key, nil, false)
    self.sub = 1
  elseif self.sub == 1 then
    if not self.printer:printed() then return end
    self.cnt = Sim.STOP_FRAMES
    self.sub = 2
  elseif self.sub == 2 then
    if self.cnt > 0 then
      self.cnt = self.cnt - 1
      return
    end
    if not self.over then
      self.over = true
      self:song(Sim.MUS_POKE_CENTER)
    end
  end
end

Sim.STAGES = stages

function Sim:stepFade()
  if (self.fadeDelay or 0) > 0 then
    self.fadeCount = (self.fadeCount or 0) + 1
    if self.fadeCount <= self.fadeDelay then return end
    self.fadeCount = 0
  end
  if self.fadeY < self.fadeTo then
    self.fadeY = math.min(self.fadeTo, self.fadeY + 2)
  elseif self.fadeY > self.fadeTo then
    self.fadeY = math.max(self.fadeTo, self.fadeY - 2)
  end
end

function Sim:stepSprites()
  for _, sp in ipairs(self.sparkles) do Phys.stepSparkle(sp) end
  for p = 1, self.n do Phys.stepImpact(self.impacts[p]) end
  if self.berries then
    for p = 1, self.n do
      local b = self.berries[p]
      if b then Phys.stepBerry(b) end
    end
  end
end

function Sim:update(dt)
  self.frame = self.frame + 1
  self.sf = self.sf + 1
  local inp = self.inp
  self.inp = nil
  local fn = stages[self.stage]
  if fn then fn(self, inp) end
  if self.printer then self.printer:tick(inp) end
  self:stepFade()
  self:stepSprites()
  if self.hooks.tick then self.hooks.tick(dt or (1 / 60)) end
end

function Sim:draw()
  require("src.ui.game3.minigames.berry_crush.view").draw(self)
end

return Sim

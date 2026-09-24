local R = require("src.core.game3.minigames.dodrio_berry_picking.rules")

local Sim = {}
Sim.__index = Sim

Sim.DIR = "dodrio_berry_picking"
-- pokefirered/include/constants/songs.h:9
Sim.SE_SELECT = 5
Sim.SE_BOO = 22
Sim.SE_SUCCESS = 25
Sim.SE_CLICK = 30
Sim.SE_BALLOON_RED = 67
Sim.SE_M_CHARM = 205
Sim.MUS_LEVEL_UP = 257
Sim.MUS_TOO_BAD = 271
Sim.MUS_VICTORY_WILD = 311
Sim.MUS_BERRY_PICK = 330
-- pokefirered/src/sound.c:61
Sim.TOO_BAD_FRAMES = 160
-- pokefirered/src/dodrio_berry_picking.c:3663
Sim.INTRO_FRAMES_PER_STATE = 13
-- pokefirered/src/dodrio_berry_picking.c:3586
Sim.DODRIO_Y = 136
-- pokefirered/src/dodrio_berry_picking.c:932
Sim.COUNTDOWN_X = 120
Sim.COUNTDOWN_Y = 80
Sim.PREDICT_FRAMES = 6
Sim.PREDICT_TIMEOUT = 20
-- pokefirered/src/save.c:882
Sim.SAVE_FRAMES = 93
-- pokefirered/src/dodrio_berry_picking.c:75
Sim.PLAY_AGAIN_NONE, Sim.PLAY_AGAIN_YES, Sim.PLAY_AGAIN_NO = 0, 1, 2
-- pokefirered/src/dodrio_berry_picking.c:1209
Sim.WAIT_FRAMES = 120

local band, bor = bit.band, bit.bor

local function common()
  return package.loaded["src.core.game3.minigames.common"] or require("src.core.game3.minigames.common")
end

function Sim.tables(ctx)
  local art = ctx and ctx.art
  if type(art) == "table" and type(art.tables) == "table" then return art.tables end
  local Art = require("src.ui.game3.minigames.common_art")
  local T, err = Art.tables(Sim.DIR)
  if not T then error(err, 0) end
  return T
end

local function isShiny(mon)
  if type(mon) ~= "table" then return false end
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not ok then return mon.isShiny == true end
  return Pokemon.isShiny(mon) and true or false
end

function Sim.new(ctx, G)
  local T = R.checkTables(Sim.tables(ctx))
  local players = {}
  for _, p in ipairs(type(ctx.players) == "table" and ctx.players or {}) do players[#players + 1] = p end
  table.sort(players, function(a, b) return (tonumber(a.seat) or 99) < (tonumber(b.seat) or 99) end)
  local n = #players
  assert(n >= (G and G.MIN or 3) and n <= R.MAX_PLAYERS, "dodrio berry picking needs 3 to 5 players")
  local hooks = ctx.hooks or (G and G.hooksFor and G.hooksFor(ctx)) or {}
  local self = setmetatable({
    ctx = ctx, G = G, T = T, n = n, players = players,
    seatOf = {}, playerOfSeat = {}, names = {}, shiny = {},
    me = 0, leader = ctx.leader and true or false,
    hooks = hooks, hooksOwned = ctx.hooks ~= nil or (G ~= nil and G.hooksFor ~= G.defaultHooksFor),
    frame = 0, presses = 0, lastDir = R.PICK_NONE, pred = nil,
    playing = false, endReady = false, finalSent = false,
    started = false, stepped = false, hostCountdown = false, countdown = nil,
    round = 1, flow = "game", resultsAck = 0, vote = 0, endSeen = false,
    btn = {}, blank = false, lastSt = nil, waitPose = nil, waitDelay = 0,
    L = { rd = 1, ended = false, rmask = 0, ymask = 0, nmask = 0, shmask = 0 },
    vs = { rd = 1, e = 0, rmask = 0, ymask = 0, nmask = 0, shmask = 0 },
  }, Sim)
  for p = 0, n - 1 do
    local pl = players[p + 1]
    local seat = tonumber(pl.seat) or p
    self.seatOf[p] = seat
    self.playerOfSeat[seat] = p
    self.names[p] = type(pl.name) == "string" and pl.name or ""
    self.shiny[p] = pl.shiny == true
    if seat == tonumber(ctx.seat) then self.me = p end
  end
  if ctx.partyMon then self.shiny[self.me] = isShiny(ctx.partyMon) end
  self.myShiny = self.shiny[self.me] and true or false
  self.start, self.stop = R.activeColumns(n)
  self.rng = ctx.rng or common().rng(ctx.seed)
  self.st = R.new(T, n, self.rng)
  self.blankView = R.emptyView(n)
  self:initPresentation()
  self:initRound()
  return self
end

function Sim:initPresentation()
  local T = self.T
  local cs = T.cloud_start
  self.clouds = {
    x = { cs[1][1], cs[2][1] }, y = { cs[1][2], cs[2][2] }, c = { 0, 0 },
    delays = T.cloud_move_delays, frozen = false, visible = true,
  }
  self.snd = { playingPick = false, squish = {}, endState = 0, fanfare = 0, music = false }
end

-- pokefirered/src/dodrio_berry_picking.c:1368
function Sim:initRound()
  self.intro = { stage = "slide", timer = 0, hofs = 0, names = false, namesState = 0, doneWait = 0, done = false }
  local bar = self.status and self.status.bar or R.newStatusBar()
  self.status = { y = {}, entered = {}, visible = true, live = false, bar = bar }
  for i = 0, R.NUM_STATUS_SQUARES - 1 do
    self.status.y[i] = -8 - i * 8
    self.status.entered[i] = false
  end
  self.own = { state = 0, timer = 0, pose = nil, dx = 0 }
  self.snd.playingPick = false
  self.snd.squish = {}
  self.snd.endState = 0
  self.flow = "game"
  self.rs = nil
  self.started = false
  self.countdown = nil
  self.playing = false
  self.pred = nil
  self.blank = false
  self.lastSt = nil
  self.waitPose = nil
  self.waitDelay = 0
  self.fadeY = 0
  self.view = R.emptyView(self.n)
end

function Sim:hook(name, ...)
  local h = self.hooks[name]
  if type(h) ~= "function" then return nil end
  if not (self.hooksOwned or self:displayed()) then return nil end
  local ok, v = pcall(h, ...)
  if ok then return v end
  print("[minigame] dodrio " .. name .. ": " .. tostring(v))
  return nil
end

function Sim:isShiny(p)
  if p == self.me then return self.myShiny end
  if self.shiny[p] then return true end
  return band(self.vs.shmask or 0, 2 ^ p) ~= 0
end

function Sim:displayView()
  if self.blank then return self.blankView end
  return self.view
end

function Sim:displayed()
  local MG = common()
  local run = MG and MG._run
  return run ~= nil and run.match ~= nil and run.match.sim == self
end

function Sim:audio()
  if self.G and self.G.audio then return self.G.audio end
  if not self:displayed() then return nil end
  local ok, A = pcall(require, "src.core.game3.audio")
  return ok and A or nil
end

function Sim:call(fn, ...)
  local A = self:audio()
  if not (A and A[fn]) then return nil end
  local ok, v = pcall(A[fn], ...)
  if ok then return v end
  return nil
end

function Sim:se(id) self:call("playSe", id) end

function Sim:stopMusic() self:call("playSong", 0) end

function Sim:column(pos)
  return R.activeColumn(self.T, self.n, self.me, pos)
end

function Sim:ownPick()
  local pr = self.pred
  if pr and pr.t < Sim.PREDICT_FRAMES then return pr.d end
  return self.view.pick[self.me] or R.PICK_NONE
end

Sim.BUTTONS = { "a", "b", "up", "down", "left", "right" }

function Sim:readButtons(input)
  if not (input and input.wasPressed) then return end
  for _, b in ipairs(Sim.BUTTONS) do
    if input:wasPressed(b) then self.btn[b] = true end
  end
end

function Sim:openingRound()
  return self.hostCountdown and self.round == 1
end

-- pokefirered/src/dodrio_berry_picking.c:1016
function Sim:localInput(input)
  self.stepped = true
  self:readButtons(input)
  if self:openingRound() then self.started = true end
  if input and input.wasPressed and self.flow == "game" and self.started and self.view.ph == R.PHASE_PLAY
      and self.view.gray < R.NUM_STATUS_SQUARES and self:ownPick() == R.PICK_NONE then
    local d
    if input:wasPressed("up") then d = R.PICK_MIDDLE
    elseif input:wasPressed("right") then d = R.PICK_RIGHT
    elseif input:wasPressed("left") then d = R.PICK_LEFT end
    if d then
      self.presses = (self.presses + 1) % 256
      self.lastDir = d
    end
  end
  return { n = self.presses, d = self.lastDir, sh = self.myShiny and 1 or 0, r = self.resultsAck, v = self.vote }
end

function Sim:predict(i)
  if type(i) ~= "table" or tonumber(i.n) == self.lastPredicted then return end
  self.lastPredicted = tonumber(i.n)
  if (tonumber(i.n) or 0) == 0 then return end
  self.pred = { n = (tonumber(i.n) or 0) % 256, d = tonumber(i.d) or R.PICK_NONE, t = 0 }
end

-- pokefirered/src/dodrio_berry_picking.c:1197
function Sim:aggregate(inputsBySeat, presentBySeat)
  local L = self.L
  local rmask, ymask, nmask, shmask = 0, 0, 0, 0
  for p = 0, self.n - 1 do
    local seat = self.seatOf[p]
    local inp = inputsBySeat and inputsBySeat[seat + 1]
    if type(inp) ~= "table" then inp = nil end
    local here = presentBySeat == nil or presentBySeat[seat + 1] == true
    local b = 2 ^ p
    if p == self.me then
      if self.myShiny then shmask = shmask + b end
    elseif inp and tonumber(inp.sh) == 1 then
      shmask = shmask + b
    end
    if not here then
      rmask = rmask + b
      nmask = nmask + b
    else
      if inp and (tonumber(inp.r) or 0) >= L.rd then rmask = rmask + b end
      local v = inp and tonumber(inp.v) or 0
      if math.floor(v / 4) == L.rd then
        if v % 4 == Sim.PLAY_AGAIN_YES then ymask = ymask + b elseif v % 4 == Sim.PLAY_AGAIN_NO then nmask = nmask + b end
      end
    end
  end
  L.rmask, L.ymask, L.nmask, L.shmask = rmask, ymask, nmask, shmask
  local all = 2 ^ self.n - 1
  if not L.ended and R.ended(self.st) and rmask == all and bor(ymask, nmask) == all then
    if nmask ~= 0 then
      L.ended = true
    else
      L.rd = L.rd + 1
      self.st = R.new(self.T, self.n, self.rng)
    end
  end
  self.vs = { rd = L.rd, e = L.ended and 1 or 0, rmask = rmask, ymask = ymask, nmask = nmask, shmask = shmask }
end

function Sim:leaderStep(inputsBySeat, presentBySeat)
  self.stepped = true
  if self:openingRound() then self.started = true end
  self:aggregate(inputsBySeat, presentBySeat)
  self.endReady = self.L.ended
  if not self.started or self.round ~= self.L.rd or self.flow ~= "game" then return end
  local presses = {}
  for p = 0, self.n - 1 do presses[p] = inputsBySeat and inputsBySeat[self.seatOf[p] + 1] end
  R.step(self.st, presses)
  self.view = R.view(self.st, self.view)
  self.lastSt = self.st
  self.playing = true
end

function Sim:snapshot()
  local L = self.L
  local s = R.encode(self.st)
  s.go = (self.started and self.round == L.rd) and 1 or 0
  s.rd = L.rd
  s.m = L.rmask + L.ymask * 32 + L.nmask * 1024 + L.shmask * 32768
  s.e = L.ended and 1 or 0
  if L.ended then self.finalSent = true end
  return s
end

local function sessionOf(s)
  local m = tonumber(s.m) or 0
  return {
    rd = tonumber(s.rd) or 1, e = tonumber(s.e) or 0,
    rmask = m % 32, ymask = math.floor(m / 32) % 32, nmask = math.floor(m / 1024) % 32,
    shmask = math.floor(m / 32768) % 32,
  }
end

-- pokefirered/src/dodrio_berry_picking.c:1658
function Sim:applySnapshot(s)
  if self.leader or type(s) ~= "table" then return end
  self.vs = sessionOf(s)
  if tonumber(s.go) ~= 1 or self.vs.rd ~= self.round or not self.started then return end
  if self.flow ~= "game" and self.lastSt then return end
  local st = R.decode(self.T, self.n, s, nil)
  if not st then return end
  self.view = R.view(st, self.view)
  self.lastSt = st
  self.playing = true
end

function Sim:becomeLeader(last)
  if type(last) == "table" then
    local st = R.decode(self.T, self.n, last, self.rng)
    if st then
      local vs = sessionOf(last)
      self.st = st
      self.L = { rd = vs.rd, ended = vs.e == 1, rmask = vs.rmask, ymask = vs.ymask, nmask = vs.nmask,
        shmask = vs.shmask }
      self.vs = vs
      if tonumber(last.go) == 1 and vs.rd == self.round and self.flow == "game" then
        self.started = true
        self.view = R.view(st, self.view)
        self.lastSt = st
      end
    end
  else
    self.L.rd = self.round
  end
  self.leader = true
  self.pred = nil
  self.endReady = self.L.ended
end

function Sim:becomeMember()
  self.leader = false
  self.finalSent = false
end

function Sim:finished()
  return self.leader and self.L.ended and self.finalSent
end

function Sim:results()
  local st = self.st
  local out = {}
  for p = 0, self.n - 1 do
    local r = st.res[p]
    out[#out + 1] = {
      seat = self.seatOf[p],
      score = math.min(R.score(self.T, r), R.MAX_SCORE),
      stats = { b = r[0], g = r[1], o = r[2], m = r[3], r = st.maxInRow, p = st.prize },
    }
  end
  return { results = out, powder = {} }
end

function Sim:introDone()
  return self.intro.done
end

-- pokefirered/src/dodrio_berry_picking.c:1848
function Sim:stepSlide()
  local it = self.intro
  local x = math.floor(it.timer / 4)
  it.timer = it.timer + 1
  if x ~= 0 and it.timer % 4 == 0 then
    if x < self.T.tree_border_x[self.n] then
      it.hofs = x * 8
    else
      it.stage = "status_init"
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:3786
function Sim:stepStatusIntro()
  local s = self.status
  local active = false
  for i = 0, R.NUM_STATUS_SQUARES - 1 do
    local dy = 2
    if not (s.entered[i] and s.y[i] == 8) then
      active = true
      if s.y[i] == 8 then
        s.entered[i] = true
        dy = -16
        self:se(Sim.SE_CLICK)
      end
      s.y[i] = s.y[i] + dy
    end
  end
  return not active
end

-- pokefirered/src/dodrio_berry_picking.c:1425
function Sim:stepIntro()
  local it = self.intro
  if it.stage == "slide" then
    self:stepSlide()
  elseif it.stage == "status_init" then
    for i = 0, R.NUM_STATUS_SQUARES - 1 do
      self.status.y[i] = -8 - i * 8
      self.status.entered[i] = false
    end
    it.stage = "status"
  elseif it.stage == "status" then
    if self:stepStatusIntro() then it.stage = "task" end
  elseif it.stage == "task" then
    self.status.live = true
    it.stage = "names"
    it.namesState = 0
    self.own.state = 2
    self.own.timer = 0
  elseif it.stage == "names" then
    it.namesState = it.namesState + 1
    it.names = it.namesState >= 1 and it.namesState <= 180
    if it.namesState > 180 then
      it.names = false
      it.stage = "countdown_wait"
      it.doneWait = 0
    end
  elseif it.stage == "countdown_wait" then
    it.doneWait = it.doneWait + 1
    if it.doneWait >= 3 then
      it.stage = "countdown"
      it.done = true
      if not self:openingRound() then self:startCountdown() end
    end
  elseif it.stage == "countdown" then
    local cd = self.countdown
    if cd and not cd:step() then
      self.countdown = nil
      it.stage = "done"
      self.started = true
    elseif not cd then
      it.stage = "done"
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:932
function Sim:startCountdown()
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  local sim = self
  self.countdown = Countdown.new(Sim.COUNTDOWN_X, Sim.COUNTDOWN_Y, { playSe = function(id) sim:se(id) end })
end

-- pokefirered/src/dodrio_berry_picking.c:4004
function Sim:stepClouds()
  local c = self.clouds
  if c.frozen then return end
  for s = 1, 2 do
    for i = 1, 2 do
      c.c[i] = c.c[i] + 1
      if c.c[i] > c.delays[i] then
        c.x[s] = c.x[s] - 1
        c.c[i] = 0
      end
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:3632
function Sim:stepOwnDodrio()
  local o = self.own
  if o.state == 1 then
    o.timer = o.timer + 1
    local phase = math.floor(o.timer / 2) % 4
    if o.timer >= 3 then
      o.dx = o.dx + ((phase == 1 or phase == 2) and -1 or 1)
      o.timer = o.timer + 1
      if o.timer >= 40 then
        o.state = 0
        o.dx = 0
      end
    end
  elseif o.state == 2 then
    o.timer = o.timer + 1
    local pose = math.floor(o.timer / Sim.INTRO_FRAMES_PER_STATE) % R.PICK_DISABLED
    if o.timer % Sim.INTRO_FRAMES_PER_STATE == 0 and pose ~= R.PICK_NONE then self:se(Sim.SE_M_CHARM) end
    if o.timer >= Sim.INTRO_FRAMES_PER_STATE * R.PICK_DISABLED * 2 then
      o.state = 0
      pose = R.PICK_NONE
    end
    o.pose = pose
    if o.state == 0 then o.pose = nil end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:3611
function Sim:startMissedAnim()
  local o = self.own
  o.state = 1
  o.timer = 0
  o.dx = 0
end

-- pokefirered/src/dodrio_berry_picking.c:1748
function Sim:stepSound()
  local v, me, snd = self.view, self.me, self.snd
  local pick = v.pick[me] or 0
  if pick == R.PICK_NONE then
    if v.ate[me] ~= 1 and v.missed[me] ~= 1 then snd.playingPick = false end
  elseif v.ate[me] == 1 then
    if not snd.playingPick then
      self:call("stopSe", Sim.SE_SUCCESS)
      self:se(Sim.SE_SUCCESS)
      snd.playingPick = true
    end
  elseif v.missed[me] == 1 then
    if not snd.playingPick and not self:call("isSePlaying") then
      self:se(Sim.SE_BOO)
      self:startMissedAnim()
      snd.playingPick = true
    end
  end
  for i = self.start, self.stop - 1 do
    if (v.fall[i] or 0) >= R.MAX_FALL_DIST then
      if not snd.squish[i] then
        self:se(Sim.SE_BALLOON_RED + (v.ids[i] or 0))
        snd.squish[i] = true
      end
    else
      snd.squish[i] = false
    end
  end
  self:stepEndSound()
end

function Sim:stepEndSound()
  local snd = self.snd
  if snd.endState == 0 and self.view.gray >= R.NUM_STATUS_SQUARES then
    self:stopMusic()
    snd.endState = 1
  elseif snd.endState == 1 then
    self:call("playFanfare", Sim.MUS_TOO_BAD)
    snd.fanfare = Sim.TOO_BAD_FRAMES
    snd.endState = 2
  end
end

function Sim:stepPrediction()
  local pr = self.pred
  if not pr then return end
  pr.t = pr.t + 1
  if (self.view.ack[self.me] == pr.n and pr.t >= 1) or pr.t > Sim.PREDICT_TIMEOUT then self.pred = nil end
end

function Sim:dodrioPose(p)
  local v = self:displayView()
  if v.gray >= R.NUM_STATUS_SQUARES then return R.PICK_DISABLED end
  if p == self.me then
    if self.own.state == 2 and self.own.pose then return self.own.pose end
    if self.blank then return self.waitPose or R.PICK_NONE end
    local pr = self.pred
    if pr and pr.t < Sim.PREDICT_FRAMES then return pr.d end
  end
  return v.pick[p] or R.PICK_NONE
end

function Sim:startMusic()
  self:stopMusic()
  self:call("playSong", Sim.MUS_BERRY_PICK)
end

function Sim:update()
  self.frame = self.frame + 1
  if not self.stepped and not self.hostCountdown then self.hostCountdown = true end
  if not self.snd.music and self:audio() then
    self.snd.music = true
    self:startMusic()
  end
  local btn = self.btn
  self.btn = {}
  self:stepClouds()
  self:stepOwnDodrio()
  if self.snd.fanfare > 0 then self.snd.fanfare = self.snd.fanfare - 1 end
  if self.flow == "game" then
    self:stepIntro()
    if self.playing then self:stepSound() end
    self:stepPrediction()
    if self.started and self.playing and self.view.ph == R.PHASE_END and self.lastSt then self:enterResults() end
  else
    self:stepFlow(btn)
  end
  if self.status.live then R.updateStatusBar(self.status.bar, self:displayView().gray) end
  if self:displayed() then
    local okW, WirelessIcon = pcall(require, "src.ui.game3.wireless_icon")
    if okW and WirelessIcon.update then WirelessIcon.update(1 / 60) end
  end
end

local function copyResults(res)
  local out = R.newResults()
  for p = 0, R.MAX_PLAYERS - 1 do
    for k = 0, 5 do out[p][k] = res[p][k] or 0 end
  end
  return out
end

-- pokefirered/src/dodrio_berry_picking.c:1079
function Sim:enterResults()
  local st = self.lastSt
  self.flow = "init_results"
  self.rs = {
    res = copyResults(st.res), prize = st.prize, inRow = st.maxInRow,
    frames = 0, gstate = 0, timer = 0, wait = 0,
    show = nil, icons = false, rows = nil, sr = nil, prizeState = nil, cursor = Sim.PLAY_AGAIN_NONE,
  }
  if self.snd.endState < 2 then
    if self.snd.endState == 0 then self:stopMusic() end
    self.snd.endState = 1
    self:stepEndSound()
  end
end

function Sim:showResults()
  self.endSeen = true
end

function Sim:handleInput(input)
  self:readButtons(input)
end

function Sim:resultsDone()
  return self.flow == "done"
end

function Sim:highest()
  return R.highestScore(self.T, self.rs.res, self.n)
end

function Sim:allReady()
  if self.endSeen then return true end
  return self.vs.rd == self.round and self.vs.rmask == 2 ^ self.n - 1
end

function Sim:decided()
  if self.endSeen or self.vs.e == 1 then return "end" end
  if self.vs.rd > self.round then return "again" end
  return nil
end

-- pokefirered/src/dodrio_berry_picking.c:2633
function Sim:tryUpdateRecords()
  local rs = self.rs
  local mine = rs.res[self.me]
  self:hook("updateRecords", math.min(R.score(self.T, mine), R.MAX_SCORE), R.berriesPicked(mine), rs.inRow)
end

-- pokefirered/src/dodrio_berry_picking.c:2874
function Sim:tryGivePrize()
  local rs = self.rs
  local item = R.prizeItem(rs.prize)
  if R.score(self.T, rs.res[self.me]) ~= self:highest() then return R.NO_PRIZE end
  if not self:hook("canAdd", item, 1) then return R.PRIZE_NO_ROOM end
  self:hook("addItem", item, 1)
  if not self:hook("canAdd", item, 1) then return R.PRIZE_FILLED_BAG end
  return R.PRIZE_RECEIVED
end

-- pokefirered/src/dodrio_berry_picking.c:2661
function Sim:waitPlayAgainInput(btn)
  if self.waitDelay == 0 then
    local d
    if btn.up then d = R.PICK_MIDDLE elseif btn.left then d = R.PICK_LEFT elseif btn.right then d = R.PICK_RIGHT end
    if d then
      self.waitPose = d
      self.waitDelay = 6
      self:se(Sim.SE_M_CHARM)
    else
      self.waitPose = R.PICK_NONE
    end
  else
    self.waitDelay = self.waitDelay - 1
  end
end

-- pokefirered/src/dodrio_berry_picking.c:1163
function Sim:stepFlow(btn)
  local rs = self.rs
  local f = self.flow
  if self.endSeen and (f == "standby1" or f == "ask0" or f == "save" or f == "ask") then
    rs.show = nil
    self.blank = true
    self.flow = "dropped"
    rs.frames = 0
    return
  end
  if f == "init_results" then
    rs.frames = rs.frames + 1
    if rs.frames >= 3 then
      if self.snd.fanfare > 0 then
        self.snd.fanfare = self.snd.fanfare - 1
      else
        self:call("fadeOutAndPlay", Sim.MUS_VICTORY_WILD, 4)
        self.flow = "doresults"
      end
    end
  elseif f == "doresults" then
    self:tryUpdateRecords()
    self.status.visible = false
    local c = self.clouds
    local cs = self.T.cloud_start
    c.frozen = true
    c.x = { cs[1][1], cs[2][1] }
    c.y = { cs[1][2], cs[2][2] }
    c.visible = false
    self.flow = "results"
    rs.gstate = 0
  elseif f == "results" then
    self:stepShowResults(btn.a)
  elseif f == "standby1" then
    rs.frames = rs.frames + 1
    rs.show = rs.frames >= 3 and "standby" or nil
    if self:allReady() then
      rs.wait = rs.wait + 1
      if rs.wait >= Sim.WAIT_FRAMES then
        rs.show = nil
        self.flow = "ask0"
      end
    end
  elseif f == "ask0" then
    rs.frames = 0
    if self:highest() >= R.PRIZE_SCORE then self.flow = "save" else self.flow = "ask" end
  elseif f == "save" then
    rs.frames = rs.frames + 1
    rs.show = "saving"
    if rs.frames == 3 then self:hook("save") end
    if rs.frames >= 3 + Sim.SAVE_FRAMES then
      rs.show = nil
      rs.frames = 0
      self.flow = "ask"
    end
  elseif f == "ask" then
    self:stepAsk(btn)
  elseif f == "standby2" then
    rs.frames = rs.frames + 1
    rs.show = rs.frames >= 3 and "standby" or nil
    local d = self:decided()
    if d then
      rs.wait = rs.wait + 1
      if rs.wait >= Sim.WAIT_FRAMES then
        rs.show = nil
        self.waitPose = nil
        rs.frames = 0
        self.flow = (d == "again") and "reset" or "dropped"
      end
    else
      self:waitPlayAgainInput(btn)
    end
  elseif f == "dropped" then
    rs.frames = rs.frames + 1
    rs.show = rs.frames >= 3 and "dropped" or nil
    if rs.frames >= 3 + Sim.WAIT_FRAMES then
      rs.show = nil
      self.flow = "done"
    end
  elseif f == "reset" then
    self:stepReset()
  end
end

-- pokefirered/src/dodrio_berry_picking.c:4660
function Sim:stepAsk(btn)
  local rs = self.rs
  rs.frames = rs.frames + 1
  if rs.frames == 1 then
    rs.cursor = Sim.PLAY_AGAIN_NONE
    self.blank = true
    self.status.visible = true
    self.snd.endState = 0
  end
  if rs.frames < 3 then return end
  rs.show = "ask"
  if btn.a then
    self:se(Sim.SE_SELECT)
    if rs.cursor == Sim.PLAY_AGAIN_NONE then rs.cursor = Sim.PLAY_AGAIN_YES end
  elseif btn.up or btn.down then
    self:se(Sim.SE_SELECT)
    rs.cursor = (rs.cursor == Sim.PLAY_AGAIN_NO) and Sim.PLAY_AGAIN_YES or Sim.PLAY_AGAIN_NO
    return
  elseif btn.b then
    self:se(Sim.SE_SELECT)
    rs.cursor = Sim.PLAY_AGAIN_NO
  else
    return
  end
  self.vote = self.round * 4 + rs.cursor
  rs.show = nil
  rs.frames = 0
  rs.wait = 0
  self.flow = "standby2"
end

-- pokefirered/src/dodrio_berry_picking.c:1368
function Sim:stepReset()
  local rs = self.rs
  rs.frames = rs.frames + 1
  if rs.frames == 1 then
    self.fadeY = 0
    rs.fading = "out"
  end
  if rs.fading == "out" then
    self.fadeY = math.min(16, self.fadeY + 2)
    if self.fadeY >= 16 then rs.fading = "reset" end
  elseif rs.fading == "reset" then
    self.intro.hofs = 0
    self:stopMusic()
    self:call("playSong", Sim.MUS_BERRY_PICK)
    self.clouds.frozen = false
    rs.fading = "in"
  elseif rs.fading == "in" then
    self.fadeY = math.max(0, self.fadeY - 2)
    if self.fadeY <= 0 then
      self.round = self.round + 1
      self:initRound()
      self.clouds.visible = true
    end
  end
end

function Sim:stepShowResults(a)
  local rs = self.rs
  local g = rs.gstate
  if g == 0 then
    rs.sr = R.scoreResults(self.T, rs.res, self.n)
    rs.timer = 0
    rs.gstate = 1
  elseif g == 1 or g == 2 then
    rs.gstate = g + 1
  elseif g == 3 then
    rs.show = "results"
    rs.icons = true
    rs.gstate = 4
  elseif g == 4 then
    rs.timer = rs.timer + 1
    if rs.timer >= 30 and a then
      rs.timer = 0
      self:se(Sim.SE_SELECT)
      rs.icons = false
      rs.gstate = 5
    end
  elseif g == 5 or g == 6 then
    if g == 6 then rs.rows = R.rankedOrder(self.T, rs.res, self.n) end
    rs.gstate = g + 1
  elseif g == 7 then
    rs.show = "rankings"
    rs.gstate = 8
  elseif g == 8 then
    rs.timer = rs.timer + 1
    if rs.timer >= 30 and a then
      rs.timer = 0
      self:se(Sim.SE_SELECT)
      if self:highest() < R.PRIZE_SCORE then
        rs.gstate = 127
      else
        self:stopMusic()
        rs.gstate = 9
      end
    end
  elseif g == 9 then
    self:call("playSong", Sim.MUS_LEVEL_UP)
    rs.prizeState = self:tryGivePrize()
    rs.gstate = 10
  elseif g == 10 then
    rs.show = "prize"
    self:call("fadeOutAndPlay", Sim.MUS_VICTORY_WILD, 20)
    rs.gstate = 11
  elseif g == 11 then
    rs.timer = rs.timer + 1
    if rs.timer >= 30 and a then
      rs.timer = 0
      self:se(Sim.SE_SELECT)
      rs.gstate = 12
    end
  else
    rs.show = nil
    rs.frames = 0
    rs.wait = 0
    self.resultsAck = self.round
    self.flow = "standby1"
  end
end

function Sim:draw()
  local ok, Draw = pcall(require, "src.ui.game3.minigames.dodrio_berry_picking.draw")
  if not ok then error(Draw, 0) end
  Draw.draw(self, self.ctx.art)
end

return Sim

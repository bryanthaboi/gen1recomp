local Wire = require("src.link.Wire")

local MG = {}

MG.GAMES = {
  jump = "src.core.game3.minigames.pokemon_jump",
  crush = "src.core.game3.minigames.berry_crush",
  pick = "src.core.game3.minigames.dodrio_berry_picking",
}
MG.GROUP_GAME = { [4] = "jump", [5] = "crush", [6] = "pick" }
MG.ACTIVITY = { jump = "minigame_jump", crush = "minigame_crush", pick = "minigame_pick" }
-- pokefirered/src/union_room.c:1956
MG.RETURN = {
  jump = { using = 8, x = 5, y = 1 },
  crush = { using = 7, x = 9, y = 1 },
  pick = { using = 8, x = 5, y = 1 },
}
-- pokefirered/data/scripts/cable_club.inc:1175
MG.PARTY_KIND = { jump = 0, pick = 1 }
MG.CAPACITY = { jump = { 2, 5 }, crush = { 2, 5 }, pick = { 3, 5 } }

MG.MSG = {
  READY = "game3_mg_ready",
  START = "game3_mg_start",
  STATE = "game3_mg_state",
  INPUT = "game3_mg_input",
  RESULT = "game3_mg_result",
  BYE = "game3_mg_bye",
  LEADER = "game3_mg_leader",
}

MG.DT = 1 / 60
MG.STATE_EVERY = 3
MG.INPUT_GAP = 3
MG.INPUT_DELAY = 2
MG.READY_TIMEOUT = 60 * 60
MG.STALL_TIMEOUT = 60 * 10
MG.MAX_CATCHUP = 4
MG.MESSAGE_FRAMES = 180
MG.FADE_GUARD = 90
-- pokefirered/src/pokemon_jump.c:4440
MG.COUNTDOWN_X = 120
MG.COUNTDOWN_Y = 80
-- pokefirered/src/dodrio_berry_picking.c:4839
MG.DROPPED_TEXT = "gText_SomeoneDroppedOut"
-- pokefirered/src/mystery_gift_menu.c:937
MG.ERROR_TEXT = "gText_CommunicationError"
-- pokefirered/src/pokemon_jump.c:3268
MG.STANDBY_TEXT = "gText_CommunicationStandby4"
MG.LAYER = "minigame"

-- pokefirered/include/constants/species.h:89
MG.SPECIES_DODRIO = 85
-- pokefirered/include/constants/species.h:421
MG.SPECIES_EGG = 412
MG.PARTY_SIZE = 6

MG.partySlot = nil
MG._run = nil
MG._jumpMons = nil

local function num(v, d)
  local n = tonumber(v)
  if n == nil then return d end
  return math.floor(n)
end

local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

MG.same = same

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = copy(val) end
  return out
end

function MG.clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

-- pokefirered/src/random.c:9
function MG.rng(seed)
  local r = { state = (tonumber(seed) or 0) % 0x100000000 }
  function r:next()
    self.state = (1103515245 * self.state + 24691) % 0x100000000
    return math.floor(self.state / 0x10000)
  end
  return r
end

function MG.module(id)
  local path = MG.GAMES[id]
  if not path then error("unknown minigame " .. tostring(id)) end
  local G = require(path)
  if type(G) ~= "table" or type(G.new) ~= "function" then
    error(path .. " is not a minigame module")
  end
  return G
end

function MG.speciesOf(mon)
  return tonumber(type(mon) == "table" and (mon.species or mon.speciesId)) or 0
end

-- pokefirered/src/pokemon.c:3245
function MG.speciesOrEgg(mon)
  if type(mon) ~= "table" then return 0 end
  if mon.isEgg or mon.egg then return MG.SPECIES_EGG end
  return MG.speciesOf(mon)
end

-- pokefirered/src/pokemon_jump.c:766
function MG.jumpMons(cache)
  if MG._jumpMons then return MG._jumpMons end
  local Art = require("src.ui.game3.minigames.common_art")
  local tables, err = Art.tables("pokemon_jump", cache)
  if not tables then error(err) end
  local list = assert(tables.jump_mons, "pokemon_jump/tables.lua has no jump_mons")
  local bySpecies = {}
  for _, row in ipairs(list) do
    local sp = tonumber(row.species)
    if sp then bySpecies[sp] = tonumber(row.jumpType) or 0 end
  end
  MG._jumpMons = bySpecies
  return bySpecies
end

-- pokefirered/src/pokemon_jump.c:2682
function MG.isJumpSpecies(species)
  return MG.jumpMons()[tonumber(species) or -1] ~= nil
end

-- pokefirered/src/party_menu.c:1794
function MG.eligible(mon, kind)
  if type(mon) ~= "table" or MG.speciesOf(mon) == 0 then return false end
  if mon.isEgg or mon.egg then return false end
  if kind == 1 then return MG.speciesOf(mon) == MG.SPECIES_DODRIO end
  return MG.isJumpSpecies(MG.speciesOf(mon))
end

local function runtime()
  return package.loaded["src.core.game3.runtime"]
end

function MG.gameSession()
  local rt = runtime()
  local s = rt and rt.getSession and rt.getSession()
  if s then return s end
  local game = rt and rt._game
  return game and game.session or nil
end

function MG.roomLeader(client)
  local room = client and client.room and client.room()
  return type(room) == "table" and tonumber(room.leader) or nil
end

local Channel = {}
Channel.__index = Channel
MG.Channel = Channel

function Channel.new(rs, client)
  return setmetatable({ rs = rs, client = client }, Channel)
end

function Channel:send(msg)
  local rs = self.rs
  if type(rs) ~= "table" or rs.closed or rs.left then return false end
  local out = {}
  for k, v in pairs(msg) do
    if k ~= "seat" and k ~= "relay" then out[k] = v end
  end
  rs:send(out)
  return true
end

function Channel:poll()
  local rs = self.rs
  if type(rs) ~= "table" or not rs.poll then return {} end
  return rs:poll() or {}
end

function Channel:players()
  local rs = self.rs
  if type(rs) == "table" and rs.players then
    local ok, list = pcall(rs.players, rs)
    if ok and type(list) == "table" then return list end
  end
  return {}
end

function Channel:alive()
  local rs = self.rs
  if type(rs) ~= "table" then return false, "closed" end
  if rs.closed or rs.left then return false, "closed" end
  local C = self.client
  if C then
    local st = C.state and C.state()
    if st == "error" or st == "offline" then return false, st end
    local room = C.room and C.room()
    if type(room) ~= "table" then return false, "room" end
    local id = room.room
    if rs.target ~= nil and id ~= nil and id ~= rs.target then return false, "room" end
  end
  return true
end

function Channel:leave()
  local rs = self.rs
  if type(rs) ~= "table" or rs.left then return false end
  pcall(rs.close, rs)
  return true
end

local Match = {}
Match.__index = Match
MG.Match = Match

function Match.new(spec, opts)
  opts = opts or {}
  local G = opts.module or MG.module(spec.game)
  local self = setmetatable({
    spec = spec,
    G = G,
    game = spec.game,
    seat = num(spec.seat, 0),
    channel = Channel.new(spec.session, opts.client),
    phase = "ready",
    why = nil,
    epoch = 1,
    leader = num(opts.leader, nil) or MG.roomLeader(opts.client) or 0,
    seed = num(spec.seed, 0),
    frame = 0,
    f = 0,
    ready = {},
    readySent = false,
    startSent = false,
    readyWait = 0,
    sinceState = 0,
    lastStateF = -1,
    lastSnapshot = nil,
    latest = {},
    queue = {},
    current = {},
    lastLocal = nil,
    pending = nil,
    pendingSet = false,
    lastSendFrame = -1000000,
    left = {},
    startPlayers = nil,
    sim = nil,
    result = nil,
    byeSent = false,
    art = opts.art,
    partyMon = opts.partyMon,
    me = opts.me,
    playSe = opts.playSe,
    onResultCb = opts.onResult,
    countdownFactory = opts.countdown,
    sent = 0,
    scratchRoom = {},
    scratchSeats = {},
    scratchInputs = {},
    scratchPresent = {},
  }, Match)
  return self
end

function Match:isLeader()
  return self.leader == self.seat
end

function Match:send(msg)
  if self.channel:send(msg) then
    self.sent = self.sent + 1
    return true
  end
  return false
end

local function clear(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

function Match:presentSeats()
  local inRoom = clear(self.scratchRoom)
  for _, p in ipairs(self.channel:players()) do
    local s = tonumber(type(p) == "table" and p.seat)
    if s then inRoom[s] = true end
  end
  inRoom[self.seat] = true
  local out = clear(self.scratchSeats)
  if self.startPlayers then
    for _, p in ipairs(self.startPlayers) do
      local s = tonumber(p.seat)
      if s and inRoom[s] and not self.left[s] then out[#out + 1] = s end
    end
  else
    for s in pairs(inRoom) do
      if not self.left[s] then out[#out + 1] = s end
    end
  end
  table.sort(out)
  return out
end

function Match:fail(why)
  if self.phase == "results" or self.phase == "done" or self.phase == "error" then return end
  self.phase = "error"
  self.why = why or "error"
  if not self.byeSent then
    self.byeSent = true
    self:send({ type = MG.MSG.BYE, reason = tostring(self.why) })
  end
end

function Match:finishDone()
  if self.phase == "done" then return end
  self.phase = "done"
  if not self.byeSent then
    self.byeSent = true
    self:send({ type = MG.MSG.BYE, reason = "done" })
  end
end

local function specPlayer(spec, seat)
  for _, p in ipairs(type(spec.players) == "table" and spec.players or {}) do
    if tonumber(p.seat) == seat then return p end
  end
  return nil
end

function Match:roomPlayer(seat)
  for _, p in ipairs(self.channel:players()) do
    if tonumber(p.seat) == seat then return p end
  end
  return nil
end

function Match:readyPayload()
  local msg = { type = MG.MSG.READY, species = MG.speciesOf(self.partyMon) }
  local slot = tonumber(self.spec.partySlot)
  if slot and MG.PARTY_KIND[self.game] then msg.partySlot = slot end
  local me = self.me
  if type(me) == "table" then
    if type(me.name) == "string" and me.name ~= "" then msg.name = me.name end
    msg.trainerId = num(me.trainerId, nil)
    msg.gender = num(me.gender, nil)
  end
  return msg
end

function Match:startPlayersList(seats)
  local out = {}
  for _, s in ipairs(seats) do
    local sp = specPlayer(self.spec, s) or {}
    local rp = self:roomPlayer(s) or {}
    local r = self.ready[s] or {}
    out[#out + 1] = {
      seat = s,
      name = r.name or sp.name or rp.name or "",
      trainerId = num(r.trainerId, nil) or num(sp.trainerId, 0),
      gender = num(r.gender, nil) or num(sp.gender, 0),
      species = num(r.species, 0),
    }
  end
  return out
end

function Match:newCountdown()
  if self.countdownFactory then return self.countdownFactory() end
  local Countdown = require("src.ui.game3.minigames.common_countdown")
  return Countdown.new(MG.COUNTDOWN_X, MG.COUNTDOWN_Y, { playSe = self.playSe })
end

function Match:onStart(msg)
  local players = {}
  for _, p in ipairs(type(msg.players) == "table" and msg.players or {}) do
    players[#players + 1] = copy(p)
  end
  table.sort(players, function(a, b) return (tonumber(a.seat) or 99) < (tonumber(b.seat) or 99) end)
  self.startPlayers = players
  self.seed = num(msg.seed, self.seed)
  self.epoch = math.max(self.epoch, num(msg.epoch, 1))
  local ok, sim = pcall(self.G.new, {
    game = self.game,
    seat = self.seat,
    seats = #players,
    players = players,
    leader = self:isLeader(),
    seed = self.seed,
    rng = MG.rng(self.seed),
    partyMon = self.partyMon,
    art = self.art,
  })
  if not ok or type(sim) ~= "table" then
    self.simError = sim
    return self:fail("sim")
  end
  self.sim = sim
  if self.G.OWN_COUNTDOWN then
    self.countdown = nil
    self.phase = "play"
    self.sinceState = 0
    return
  end
  self.countdown = self:newCountdown()
  self.phase = "countdown"
end

function Match:onState(msg, from)
  if self:isLeader() then return end
  local e, f = num(msg.e, 0), num(msg.f, 0)
  if e < self.epoch then return end
  if e > self.epoch then
    self.epoch = e
    self.lastStateF = -1
    if from and from >= 0 then self.leader = from end
  elseif f <= self.lastStateF then
    return
  end
  self.lastStateF = f
  self.lastSnapshot = msg.s
  self.sinceState = 0
  if self.sim and (self.phase == "countdown" or self.phase == "play") then
    self.sim:applySnapshot(msg.s, f)
  end
end

function Match:onInput(from, msg)
  if from == self.seat then return end
  self.latest[from] = msg.i
  if self:isLeader() then
    local q = self.queue[from] or {}
    self.queue[from] = q
    q[#q + 1] = { at = self.f + MG.INPUT_DELAY, i = msg.i }
  end
end

function Match:becomeLeader()
  self.leader = self.seat
  if not self.sim then return end
  if self.phase ~= "countdown" and self.phase ~= "play" then return end
  self.sim:becomeLeader(self.lastSnapshot)
  if self.lastStateF >= 0 then self.f = self.lastStateF end
  self.queue = {}
  self.current = {}
  for s, i in pairs(self.latest) do self.current[s] = i end
  if self.lastLocal ~= nil then self.current[self.seat] = self.lastLocal end
end

function Match:onLeader(msg)
  local newSeat = tonumber(msg.seat)
  self.epoch = math.max(self.epoch + 1, num(msg.epoch, 0))
  if newSeat == nil or newSeat < 0 then return self:fail("leader") end
  local was = self:isLeader()
  local prev = tonumber(msg.prev)
  if prev and prev ~= newSeat and prev ~= self.seat and not self:roomPlayer(prev) then
    self.left[prev] = true
  end
  self.leader = newSeat
  if newSeat == self.seat and not was then
    self:becomeLeader()
  elseif was and newSeat ~= self.seat and self.sim and self.sim.becomeMember then
    self.sim:becomeMember()
  end
  if not self:isLeader() then
    self.lastStateF = -1
    self.sinceState = 0
  end
end

function Match:onResult(msg)
  self.result = msg
  self.phase = "results"
  if self.onResultCb then self.onResultCb(msg, self) end
  if self.sim and self.sim.showResults then self.sim:showResults(msg) end
end

function Match:handle(msg)
  if type(msg) ~= "table" then return end
  local t = msg.type
  local from = tonumber(msg.seat)
  local M = MG.MSG
  if t == M.READY then
    if from and from >= 0 then
      self.ready[from] = {
        species = num(msg.species, 0), partySlot = tonumber(msg.partySlot),
        name = type(msg.name) == "string" and msg.name ~= "" and msg.name or nil,
        trainerId = tonumber(msg.trainerId), gender = tonumber(msg.gender),
      }
    end
  elseif t == M.START then
    if self.phase == "ready" and from == self.leader then self:onStart(msg) end
  elseif t == M.STATE then
    self:onState(msg, from)
  elseif t == M.INPUT then
    if from and from >= 0 then self:onInput(from, msg) end
  elseif t == M.RESULT then
    if (self.phase == "countdown" or self.phase == "play") and from == self.leader then
      self:onResult(msg)
    end
  elseif t == M.BYE then
    if from and from >= 0 and from ~= self.seat then self.left[from] = true end
  elseif t == M.LEADER then
    self:onLeader(msg)
  end
end

function Match:pump()
  local list = self.channel:poll()
  for i = 1, #list do self:handle(list[i]) end
end

function Match:checkAlive()
  if self.phase == "results" or self.phase == "done" or self.phase == "error" then return end
  local ok, why = self.channel:alive()
  if not ok then return self:fail(why) end
  if #self:presentSeats() < (tonumber(self.G.MIN) or 2) then return self:fail("dropped") end
end

function Match:stepReady()
  if not self.readySent then
    self.readySent = true
    local msg = self:readyPayload()
    self.ready[self.seat] = { species = msg.species, partySlot = msg.partySlot, name = msg.name,
      trainerId = msg.trainerId, gender = msg.gender }
    self:send(msg)
  end
  self.readyWait = self.readyWait + 1
  if self.readyWait > MG.READY_TIMEOUT then return self:fail("timeout") end
  if not self:isLeader() or self.startSent then return end
  local seats = self:presentSeats()
  for _, s in ipairs(seats) do
    if not self.ready[s] then return end
  end
  self.startSent = true
  local msg = {
    type = MG.MSG.START,
    game = self.game,
    seed = self.seed,
    epoch = self.epoch,
    players = self:startPlayersList(seats),
  }
  self:send(msg)
  self:onStart(Wire.sanitize(msg) or msg)
end

function Match:takeLocal(input)
  if not (self.sim and self.sim.localInput) then return nil end
  local i = self.sim:localInput(input)
  if i == nil or same(i, self.lastLocal) then return nil end
  self.lastLocal = copy(i)
  return i
end

function Match:stepLeader(input)
  local i = self:takeLocal(input)
  if i ~= nil then
    self.latest[self.seat] = i
    local q = self.queue[self.seat] or {}
    self.queue[self.seat] = q
    q[#q + 1] = { at = self.f + MG.INPUT_DELAY, i = i }
  end
  for seat, q in pairs(self.queue) do
    while q[1] and q[1].at <= self.f do
      self.current[seat] = q[1].i
      table.remove(q, 1)
    end
  end
  local inputs, present = clear(self.scratchInputs), clear(self.scratchPresent)
  for _, s in ipairs(self:presentSeats()) do
    present[s + 1] = true
    inputs[s + 1] = self.current[s]
  end
  self.sim:leaderStep(inputs, present)
  self.f = self.f + 1
  if self.f % MG.STATE_EVERY == 0 then
    self:send({ type = MG.MSG.STATE, f = self.f, e = self.epoch, s = self.sim:snapshot() })
  end
  self.sim:update(MG.DT)
  if self.sim:finished() then
    local res = self.sim:results() or {}
    local msg = {
      type = MG.MSG.RESULT,
      game = self.game,
      results = res.results or {},
      powder = res.powder or {},
    }
    local clean = Wire.sanitize(msg) or msg
    self:send(clean)
    self:onResult(clean)
  end
end

function Match:stepMember(input)
  local i = self:takeLocal(input)
  if i ~= nil then
    if self.sim.predict then self.sim:predict(i) end
    self.pending = i
    self.pendingSet = true
  end
  if self.pendingSet and self.frame - self.lastSendFrame >= MG.INPUT_GAP then
    self:send({ type = MG.MSG.INPUT, f = self.frame, i = self.pending })
    self.lastSendFrame = self.frame
    self.pendingSet = false
  end
  self.sim:update(MG.DT)
  self.sinceState = self.sinceState + 1
  if self.sinceState > MG.STALL_TIMEOUT then self:fail("stall") end
end

function Match:step(input)
  self.frame = self.frame + 1
  self:pump()
  self:checkAlive()
  local phase = self.phase
  if phase == "ready" then
    self:stepReady()
  elseif phase == "countdown" then
    if self.sim.update then self.sim:update(MG.DT) end
    if not self.countdown:step() then
      self.phase = "play"
      self.sinceState = 0
    end
  elseif phase == "play" then
    if self:isLeader() then self:stepLeader(input) else self:stepMember(input) end
  elseif phase == "results" then
    local sim = self.sim
    if sim and sim.handleInput and input then sim:handleInput(input) end
    if sim and sim.update then sim:update(MG.DT) end
    if not (sim and sim.resultsDone) or sim:resultsDone() then self:finishDone() end
  end
  return self.phase
end

function Match:finished()
  return self.phase == "done" or self.phase == "error"
end

function MG.applyResults(session, result, mySeat, G)
  if type(session) ~= "table" or type(result) ~= "table" then return false end
  if G and G.applyResults then G.applyResults(session, result, mySeat) end
  local Records = require("src.ui.game3.minigame_records")
  for _, p in ipairs(type(result.powder) == "table" and result.powder or {}) do
    if tonumber(p.seat) == tonumber(mySeat) and (tonumber(p.amount) or 0) > 0 then
      Records.giveBerryPowder(session, p.amount)
    end
  end
  return true
end

local Latch = {}
Latch.__index = Latch
MG.Latch = Latch
Latch.BUTTONS = { "a", "b", "start", "select", "up", "down", "left", "right", "l", "r" }

function Latch.new()
  return setmetatable({ pressed = {}, src = nil }, Latch)
end

function Latch:feed(input)
  if not input then return end
  self.src = input
  if not input.wasPressed then return end
  for _, b in ipairs(Latch.BUTTONS) do
    if input:wasPressed(b) then self.pressed[b] = true end
  end
end

function Latch:wasPressed(b)
  return self.pressed[b] == true
end

function Latch:isDown(b)
  local src = self.src
  if src and src.isDown then return src:isDown(b) and true or false end
  return false
end

function Latch:clear()
  self.pressed = {}
end

local function Stack()
  return require("src.ui.game3.stack")
end

local function Fade()
  local ok, F = pcall(require, "src.ui.game3.fade")
  return ok and F or nil
end

local function coverWith(mode, done)
  local F = Fade()
  if not (F and F.begin and F.MODE) then done() return end
  F.begin(F.MODE[mode], 1, done)
end

local function clientModule()
  return package.loaded["src.online.Client"]
end

function MG.isActive()
  return MG._run ~= nil
end

function MG.isLeader()
  local run = MG._run
  return run ~= nil and run.match ~= nil and run.match:isLeader()
end

function MG.leaderSeat()
  local run = MG._run
  return run and run.match and run.match.leader or nil
end

function MG.match()
  local run = MG._run
  return run and run.match or nil
end

function MG.arm(ctx, spec)
  local done, launched = false, false
  local armed = {}
  for k, v in pairs(spec or {}) do armed[k] = v end
  local userExit = armed.onExit
  armed.onExit = function(result)
    done = true
    if userExit then pcall(userExit, result) end
  end
  require("src.core.game3.scripting.natives").awaitState(ctx, function()
    if not launched then
      launched = true
      MG.launch(armed)
    end
    return done
  end)
  return true
end

local function partyMonFor(spec, session)
  if not MG.PARTY_KIND[spec.game] then return nil end
  local slot = tonumber(spec.partySlot)
  local party = type(session) == "table" and session.party or nil
  if not (slot and party) then return nil end
  return party[slot + 1]
end

function MG.launch(spec)
  if MG._run then MG.abort("replaced") end
  local session = MG.gameSession()
  local run = {
    spec = spec,
    stage = "enter",
    frames = 0,
    stageFrames = 0,
    latch = Latch.new(),
    last = nil,
    acc = 0,
    result = nil,
    text = nil,
  }
  MG._run = run
  local okG, G = pcall(MG.module, spec.game)
  local art
  if okG then
    local okA, a, err = pcall(G.loadArt, require("src.ui.game3.minigames.common_art").cache())
    if okA and a then art = a else run.artError = okA and err or a end
  else
    run.artError = G
  end
  local okC, cdErr = pcall(function()
    local Countdown = require("src.ui.game3.minigames.common_countdown")
    assert(Countdown.loadArt())
  end)
  if not okC then run.artError = run.artError or cdErr end
  if okG and art and okC then
    run.G = G
    run.match = Match.new(spec, {
      module = G,
      client = clientModule(),
      art = art,
      partyMon = partyMonFor(spec, session),
      me = type(session) == "table" and {
        name = session.name, trainerId = (tonumber(session.trainerId) or 0) % 0x10000,
        gender = session.gender,
      } or nil,
      onResult = function(msg, m)
        MG.applyResults(session, msg, m.seat, G)
      end,
    })
  end
  Stack().push(MG.LAYER, MG, { hideBelow = true })
  coverWith("TO_BLACK", function() run.covered = true end)
  return run
end

local function leaveRoom(run)
  if run.match then return run.match.channel:leave() end
  return Channel.new(run.spec and run.spec.session):leave()
end

local function stepRun(run)
  run.frames = run.frames + 1
  run.stageFrames = run.stageFrames + 1
  local m = run.match
  if m and not m:finished() and run.stage ~= "leave" then
    m:step(run.latch)
  end
  run.latch:clear()
  if run.stage == "enter" then
    if run.covered or run.stageFrames > MG.FADE_GUARD then
      run.stage = "active"
      run.stageFrames = 0
      coverWith("FROM_BLACK", function() end)
    end
    return
  end
  if run.stage == "active" then
    if not m then
      leaveRoom(run)
      run.result = "error"
      run.text = MG.ERROR_TEXT
      run.stage = "message"
      run.stageFrames = 0
      if run.artError then print("[minigame] " .. tostring(run.artError):match("^[^\n]*")) end
    elseif m.phase == "done" then
      run.result = "done"
      MG.leave(run)
    elseif m.phase == "error" then
      run.result = "error"
      run.text = (run.G and run.G.DROPPED_TEXT) or MG.DROPPED_TEXT
      if m.why == "sim" and m.simError then print("[minigame] " .. tostring(m.simError)) end
      run.stage = "message"
      run.stageFrames = 0
    end
    return
  end
  if run.stage == "message" then
    if run.stageFrames > MG.MESSAGE_FRAMES then MG.leave(run) end
    return
  end
  if run.stage == "leave" then
    if (run.covered or run.stageFrames > MG.FADE_GUARD) and not run.warping then
      run.warping = true
      MG.finishRun(run)
    end
  end
end

function MG.leave(run)
  run.stage = "leave"
  run.stageFrames = 0
  run.covered = false
  coverWith("TO_BLACK", function() run.covered = true end)
end

-- pokefirered/src/union_room.c:1824
function MG.returnToMap(game, onDone)
  local ret = MG.RETURN[game] or MG.RETURN.jump
  local okL, Link = pcall(require, "src.core.game3.link")
  if not okL then onDone() return false end
  local ctx = Link.vmCtx()
  Link.setVar(ctx, Link.VAR_CABLE_CLUB_STATE, ret.using)
  local s = Link.session()
  local map = Link.currentMap()
  if s and map then s.dynamicWarp = { map = map, warpId = -1, x = ret.x, y = ret.y } end
  local okW, Warp = pcall(require, "src.core.game3.warp")
  local rt = runtime()
  if map and okW and Warp.scripted and rt and rt.isActive and rt.isActive() then
    Warp.scripted(rt._mod, Link.game(), "warpsilent", map, ret.x, ret.y, nil, onDone)
    return true
  end
  onDone()
  return false
end

function MG.finishRun(run)
  leaveRoom(run)
  local spec = run.spec
  Stack().pop(MG.LAYER)
  local function exit()
    if MG._run == run then MG._run = nil end
    if spec.onExit then spec.onExit(run.result or "error") end
  end
  if spec.returnToMap == false then
    exit()
    return
  end
  MG.returnToMap(spec.game, exit)
end

function MG.abort(why)
  local run = MG._run
  if not run then return false end
  if run.match then run.match:fail(why or "abort") end
  leaveRoom(run)
  Stack().pop(MG.LAYER)
  MG._run = nil
  return true
end

function MG.update(dt)
  local run = MG._run
  if not run then return end
  local now = MG.clock()
  if not run.last then
    run.last = now
    stepRun(run)
    return
  end
  run.acc = run.acc + math.max(0, now - run.last)
  run.last = now
  local n = 0
  while run.acc >= MG.DT and n < MG.MAX_CATCHUP and MG._run == run do
    run.acc = run.acc - MG.DT
    n = n + 1
    stepRun(run)
  end
  if run.acc > 0.25 then run.acc = 0 end
end

function MG.handleInput(input)
  local run = MG._run
  if not run then return end
  run.latch:feed(input)
  if run.stage == "message" and run.stageFrames > 30
      and input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("b")) then
    MG.leave(run)
  end
end

local function drawText(key)
  local okR, RomText = pcall(require, "src.core.game3.rom_text")
  if not okR then return end
  local Window = require("src.ui.game3.window")
  local Chrome = require("src.ui.game3.chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")
  Window.dialogueFrame()
  local ok, text = pcall(RomText.plain, key)
  FrlgFont.draw(ok and text or "", Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1,
    { maxWidth = Chrome.DLG_W * 8, colors = FrlgFont.COLOR.NORMAL })
end

function MG.draw()
  local run = MG._run
  if not run or not (love and love.graphics) then return end
  if run.stage == "enter" then return end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  local m = run.match
  if m and m.sim and m.phase ~= "ready" then
    local ok, err = pcall(m.sim.draw, m.sim)
    if not ok and not run.drawErr then
      run.drawErr = true
      print("[minigame] draw " .. tostring(err))
    end
  end
  if m and m.phase == "countdown" and m.countdown and m.countdown.draw then
    pcall(m.countdown.draw, m.countdown)
  end
  if run.stage == "message" then
    drawText(run.text or MG.ERROR_TEXT)
  elseif m and m.phase == "ready" then
    drawText(MG.STANDBY_TEXT)
  end
end

function MG.reset()
  MG._run = nil
  MG.partySlot = nil
  MG._jumpMons = nil
end

return MG

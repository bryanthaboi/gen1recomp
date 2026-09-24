local bit = require("bit")
local Game = require("src.core.game3.minigames.pokemon_jump.game")

local G = {}

G.id = "jump"
G.MIN = 2
G.MAX = 5
-- pokefirered/src/pokemon_jump.c:3242
G.DROPPED_TEXT = "gText_SomeoneDroppedOut2"
G.OWN_COUNTDOWN = true
G.MON_INFO_FRAMES = 180
G.Game = Game

local function MG()
  return require("src.core.game3.minigames.common")
end

function G.loadArt(cache)
  return require("src.ui.game3.minigames.pokemon_jump.art").load(cache)
end

local function records()
  return require("src.ui.game3.minigame_records")
end

local function audio()
  local ok, A = pcall(require, "src.core.game3.audio")
  if ok and type(A) == "table" then return A end
  return nil
end

function G.defaultHooks()
  local function session() return MG().gameSession() end
  return {
    playSe = function(id)
      local A = audio()
      if A and A.playSe then pcall(A.playSe, id) end
    end,
    playFanfare = function(id)
      local A = audio()
      if A and A.playFanfare then pcall(A.playFanfare, id) end
    end,
    fanfareDone = function()
      local A = audio()
      if not (A and A.isFanfareFinished) then return true end
      local ok, done = pcall(A.isFanfareFinished)
      return not ok or done
    end,
    playMusic = function(id)
      local A = audio()
      if A and A.fadeOutAndPlay then pcall(A.fadeOutAndPlay, id, 4) end
    end,
    canAdd = function(item, qty)
      local s = session()
      if type(s) ~= "table" or s.bag == nil then return false end
      return require("src.core.game3.bag").canAdd(s.bag, item, qty)
    end,
    addItem = function(item, qty)
      local s = session()
      if type(s) ~= "table" or s.bag == nil then return false end
      return (require("src.core.game3.bag").add(s.bag, item, qty))
    end,
    updateRecords = function(score, row, excellents)
      return records().updatePokemonJump(session(), score, row, excellents)
    end,
    incrementMaxPlayerGames = function()
      records().incrementPokemonJumpMaxPlayerGames(session())
    end,
    save = function()
      local rt = package.loaded["src.core.game3.runtime"]
      local game = type(rt) == "table" and rt._game or nil
      if game and type(game.saveGame) == "function" then
        local ok, written = pcall(game.saveGame, game)
        if not ok or written == false then print("[minigame] pokemon jump save failed: " .. tostring(written)) end
      end
    end,
  }
end

G.hooksFor = function() return G.defaultHooks() end

-- pokefirered/src/pokemon.c:6062
local function isShiny(mon)
  if type(mon) ~= "table" then return false end
  if mon.isShiny ~= nil then return mon.isShiny and true or false end
  local p = (tonumber(mon.personality) or 0) % 0x100000000
  local tid = (tonumber(mon.otId or mon.trainerId) or 0) % 0x10000
  local sid = (tonumber(mon.otSecretId) or 0) % 0x10000
  local v = bit.bxor(bit.bxor(tid, sid), bit.bxor(math.floor(p / 0x10000), p % 0x10000))
  return v < 8
end

local function frontYOffset(species)
  local ok, PicCoords = pcall(require, "src.core.game3.battle.pic_coords")
  if not ok or type(PicCoords) ~= "table" or type(PicCoords.front) ~= "table" then return 0 end
  return tonumber(PicCoords.front[tonumber(species) or 0]) or 0
end

local function readJoy(input, into)
  into = into or {}
  if input and input.wasPressed then
    for _, b in ipairs({ "a", "b", "up", "down" }) do
      if input:wasPressed(b) then into[b] = true end
    end
  end
  return into
end

local Sim = {}
Sim.__index = Sim
G.Sim = Sim

function G.new(ctx)
  return Sim.new(ctx)
end

function Sim.new(ctx)
  local art = ctx.art
  local tables = type(art) == "table" and art.tables or ctx.tables
  assert(type(tables) == "table", "pokemon_jump art has no tables")
  local players = {}
  for _, p in ipairs(ctx.players or {}) do players[#players + 1] = p end
  local me
  for i, p in ipairs(players) do
    if tonumber(p.seat) == tonumber(ctx.seat) then me = i - 1 end
  end
  assert(me ~= nil, "my seat is not in the start players")
  local mon = ctx.partyMon
  local monInfo = {}
  for i, p in ipairs(players) do
    local info = { species = tonumber(p.species) or 0, name = p.name or "" }
    if i - 1 == me and type(mon) == "table" then
      info.species = tonumber(mon.species or mon.speciesId) or info.species
      info.personality = tonumber(mon.personality) or 0
      info.shiny = isShiny(mon)
    end
    monInfo[i] = info
  end
  local rng = ctx.rng or MG().rng(ctx.seed)
  local hooks = ctx.hooks or G.hooksFor(ctx)
  local self = setmetatable({
    ctx = ctx,
    art = art,
    players = players,
    me = me,
    hooks = hooks,
    joy = {},
    stepped = false,
    inResults = false,
    miFrames = G.MON_INFO_FRAMES,
    frames = 0,
  }, Sim)
  self.game = Game.new({
    tables = tables,
    hooks = hooks,
    random = function() return rng:next() end,
    numPlayers = #players,
    multiplayerId = me,
    leaderIdx = ctx.leader and me or 0,
    monInfo = monInfo,
    yOffset = ctx.yOffset or frontYOffset,
    countdown = ctx.countdown,
  })
  if hooks.playMusic then hooks.playMusic(Game.MUS_POKE_JUMP) end
  return self
end

function Sim:isLeader()
  return self.game:isLeader()
end

function Sim:leaderStep(inputsBySeat, presentBySeat)
  self.stepped = true
  local g = self.game
  inputsBySeat = inputsBySeat or {}
  presentBySeat = presentBySeat or {}
  for i, p in ipairs(self.players) do
    local idx = i - 1
    if idx ~= g.multiplayerId then
      local seat = tonumber(p.seat) or 0
      if not presentBySeat[seat + 1] then
        g:markGone(idx)
      else
        g:receiveMemberPacket(idx, inputsBySeat[seat + 1])
      end
    end
  end
  if self.miFrames > 0 then self.miFrames = self.miFrames - 1 end
  g.joy = self.joy
  g:frame()
  self.joy = {}
end

function Sim:snapshot()
  return self.game:leaderPacketOut(self.miFrames > 0)
end

function Sim:applySnapshot(s)
  self.game:receiveLeaderPacket(s)
end

function Sim:localInput(input)
  self.stepped = true
  local g = self.game
  if g:isLeader() then
    readJoy(input, self.joy)
    return nil
  end
  g.joy = readJoy(input)
  g:frame()
  return g:memberPacketOut()
end

function Sim:predict() end

function Sim:becomeLeader(lastSnapshot)
  self.game:becomeLeader(lastSnapshot)
  self.miFrames = G.MON_INFO_FRAMES
end

function Sim:becomeMember()
  self.game:becomeMember()
end

function Sim:update()
  self.frames = self.frames + 1
  local g = self.game
  if not self.stepped and not self.hostCountdown then
    self.hostCountdown = true
    g.skipCountdown = true
  end
  if self.inResults then
    g.joy = self.joy
    g:frame()
    self.joy = {}
  end
  g.gfx:update()
  if love and love.graphics then
    local okW, WirelessIcon = pcall(require, "src.ui.game3.wireless_icon")
    if okW and WirelessIcon.update then WirelessIcon.update(1 / 60) end
  end
end

function Sim:draw()
  require("src.ui.game3.minigames.pokemon_jump.render").draw(self)
end

function Sim:finished()
  local g = self.game
  return g:isLeader() and g.comm.funcId == Game.FUNC.EXIT
end

function Sim:results()
  local b = self.game.best
  local out = {}
  for _, p in ipairs(self.players) do
    out[#out + 1] = { seat = tonumber(p.seat), score = b.score,
      stats = { jumpsInRow = b.jumpsInRow, excellentsInRow = b.excellentsInRow } }
  end
  return { results = out, powder = {} }
end

function Sim:showResults()
  self.inResults = true
  local g = self.game
  if g.comm.funcId ~= Game.FUNC.EXIT then g:setFuncMember(Game.FUNC.EXIT) end
end

function Sim:handleInput(input)
  readJoy(input, self.joy)
end

function Sim:resultsDone()
  return self.game.exited
end

function G.applyResults(session, result, mySeat)
  if type(session) ~= "table" or type(result) ~= "table" then return false end
  for _, r in ipairs(type(result.results) == "table" and result.results or {}) do
    if tonumber(r.seat) == tonumber(mySeat) then
      local st = type(r.stats) == "table" and r.stats or {}
      records().updatePokemonJump(session, tonumber(r.score) or 0,
        tonumber(st.jumpsInRow) or 0, tonumber(st.excellentsInRow) or 0)
      return true
    end
  end
  return false
end

return G

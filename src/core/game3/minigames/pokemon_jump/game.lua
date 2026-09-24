local bit = require("bit")
local Gfx = require("src.core.game3.minigames.pokemon_jump.gfx")

local Game = {}
Game.__index = Game

local MAX_RFU_PLAYERS = 5
-- pokefirered/src/pokemon_jump.c:25
local MAX_JUMP_SCORE = 99990
local MAX_JUMPS = 9999
local JUMP_PEAK = -30
local INT_MAX = 2147483647

-- pokefirered/src/pokemon_jump.c:57
local FUNC_GAME_INTRO = 0
local FUNC_WAIT_ROUND = 1
local FUNC_GAME_ROUND = 2
local FUNC_GAME_OVER = 3
local FUNC_ASK_PLAY_AGAIN = 4
local FUNC_RESET_GAME = 5
local FUNC_EXIT = 6
local FUNC_GIVE_PRIZE = 7
local FUNC_SAVE = 8
local FUNC_NONE = 9

Game.FUNC = {
  GAME_INTRO = FUNC_GAME_INTRO, WAIT_ROUND = FUNC_WAIT_ROUND, GAME_ROUND = FUNC_GAME_ROUND,
  GAME_OVER = FUNC_GAME_OVER, ASK_PLAY_AGAIN = FUNC_ASK_PLAY_AGAIN, RESET_GAME = FUNC_RESET_GAME,
  EXIT = FUNC_EXIT, GIVE_PRIZE = FUNC_GIVE_PRIZE, SAVE = FUNC_SAVE, NONE = FUNC_NONE,
}

-- pokefirered/src/pokemon_jump.c:83
local VINE_HIGHEST = 0
local VINE_LOWEST = 5
local VINE_UPSWING_LOWER = 6
local VINE_UPSWING_LOW = 7
local VINE_UPSWING_HIGH = 8
local NUM_VINESTATES = 10

Game.VINE = { HIGHEST = VINE_HIGHEST, LOWEST = VINE_LOWEST, UPSWING_LOWER = VINE_UPSWING_LOWER,
  UPSWING_LOW = VINE_UPSWING_LOW, UPSWING_HIGH = VINE_UPSWING_HIGH }

-- pokefirered/src/pokemon_jump.c:104
local MONSTATE_NORMAL = 0
local MONSTATE_JUMP = 1
local MONSTATE_HIT = 2
local JUMPSTATE_NONE = 0
local JUMPSTATE_SUCCESS = 1
local JUMPSTATE_FAILURE = 2

Game.MONSTATE = { NORMAL = MONSTATE_NORMAL, JUMP = MONSTATE_JUMP, HIT = MONSTATE_HIT }
Game.JUMPSTATE = { NONE = JUMPSTATE_NONE, SUCCESS = JUMPSTATE_SUCCESS, FAILURE = JUMPSTATE_FAILURE }

-- pokefirered/src/pokemon_jump.c:116
local PLAY_AGAIN_NO = 1
local PLAY_AGAIN_YES = 2
Game.PLAY_AGAIN = { NO = PLAY_AGAIN_NO, YES = PLAY_AGAIN_YES }

-- pokefirered/include/constants/items.h:181
local FIRST_BERRY_INDEX = 133
local LAST_BERRY_INDEX = 175

-- pokefirered/include/constants/songs.h:14
Game.SE_LEDGE = 10
-- pokefirered/include/constants/songs.h:261
Game.SE_POKE_JUMP_FAILURE = 255
-- pokefirered/include/constants/songs.h:334
Game.MUS_POKE_JUMP = 326

-- pokefirered/src/save.c:882
Game.SAVE_FRAMES = 93

local function u16(v) return v % 0x10000 end

local function vineStateTimer(state) return state * 256 + 0xFF end

local function mulU32(a, b)
  local bl, bh = b % 0x10000, math.floor(b / 0x10000)
  local lo = a * bl
  local hi = (a * bh) % 0x10000
  return (lo + hi * 0x10000) % 0x100000000
end

-- pokefirered/include/random.h:19
function Game.isoRandomize1(v)
  return (mulU32(1103515245, v % 0x100000000) + 24691) % 0x100000000
end

local function newPlayer()
  return { jumpOffset = 0, jumpOffsetIdx = INT_MAX, monJumpType = 0, jumpTimeStart = 0,
    monState = MONSTATE_NORMAL, prevMonState = MONSTATE_NORMAL, jumpState = JUMPSTATE_NONE,
    funcFinished = false, name = "" }
end

function Game.new(o)
  local self = setmetatable({}, Game)
  self.tables = o.tables
  self.hooks = o.hooks or {}
  self.random = o.random or function() return 0 end
  self.numPlayers = o.numPlayers
  self.multiplayerId = o.multiplayerId
  self.leaderIdx = o.leaderIdx or 0
  self.gone = {}
  self.players = {}
  self.monInfo = {}
  self.atJumpPeak, self.atJumpPeak2, self.atJumpPeak3 = {}, {}, {}
  self.memberFuncIds, self.playAgainStates, self.jumpTimeStarts = {}, {}, {}
  for i = 0, MAX_RFU_PLAYERS - 1 do
    self.players[i] = newPlayer()
    self.monInfo[i] = { species = 0, personality = 0, otId = 0, shiny = false }
    self.atJumpPeak[i], self.atJumpPeak2[i], self.atJumpPeak3[i] = false, false, false
    self.memberFuncIds[i] = FUNC_NONE
    self.playAgainStates[i] = 0
    self.jumpTimeStarts[i] = 0
  end
  for i, info in ipairs(o.monInfo or {}) do
    local m = self.monInfo[i - 1]
    m.species = tonumber(info.species) or 0
    m.personality = tonumber(info.personality) or 0
    m.otId = tonumber(info.otId) or 0
    m.shiny = info.shiny and true or false
    self.players[i - 1].name = tostring(info.name or "")
  end
  self.comm = { funcId = FUNC_NONE, receivedBonusFlags = 0, data = 0, jumpsInRow = 0, jumpScore = 0 }
  self.player = self.players[self.multiplayerId]
  self.mainState, self.helperState = 0, 0
  self.excellentsInRow, self.excellentsInRowRecord = 0, 0
  self.gameOver = false
  self.vineState, self.prevVineState = VINE_UPSWING_LOWER, VINE_UPSWING_LOWER
  self.vineSpeed, self.vineSpeedAccel, self.rngSeed, self.nextVineSpeed = 0, 0, 0, 0
  self.vineStateTimer, self.ignoreJumpInput = 0, 0
  self.timer, self.prizeItemId, self.prizeItemQuantity = 0, 0, 0
  self.playAgainComm, self.playAgainState = 0, 0
  self.allowVineUpdates, self.funcActive, self.allPlayersReady = false, false, false
  self.vineTimer, self.nextFuncId, self.showBonus = 0, FUNC_NONE, false
  self.vineSpeedDelay, self.vineBaseSpeedIdx, self.vineSpeedStage = 0, 0, 0
  self.numPlayersAtPeak = 0
  self.initScoreUpdate, self.updateScore, self.giveBonus = false, false, false
  self.skipJumpUpdate, self.atMaxSpeedStage = false, false
  self.startDelayTimer, self.started = 0, false
  self.saveTimer = 0
  self.exited = false
  self.skipCountdown = false
  self.gamesStarted = 0
  self.best = { score = 0, jumpsInRow = 0, excellentsInRow = 0 }
  self.joy = {}
  self.memberPackets = {}
  self.leaderPacket = nil
  local yOffsets = {}
  for i = 0, self.numPlayers - 1 do
    yOffsets[i] = o.yOffset and o.yOffset(self.monInfo[i].species) or 0
  end
  self.gfx = Gfx.new({
    numPlayers = self.numPlayers, multiplayerId = self.multiplayerId, tables = self.tables,
    hooks = self.hooks, yOffsets = yOffsets, countdown = o.countdown,
  })
  self:initGame()
  return self
end

function Game:isLeader()
  return self.leaderIdx == self.multiplayerId
end

function Game:active(i)
  return not self.gone[i]
end

function Game:playSe(id)
  if self.hooks.playSe then self.hooks.playSe(id) end
end

-- pokefirered/src/pokemon_jump.c:903
function Game:initGame()
  self.comm.funcId = FUNC_RESET_GAME
  self.comm.data = 0
  self:initPlayerAndJumpTypes()
  self:resetForNewGame()
  if self.numPlayers == MAX_RFU_PLAYERS and self.hooks.incrementMaxPlayerGames then
    self.hooks.incrementMaxPlayerGames()
  end
end

-- pokefirered/src/pokemon_jump.c:914
function Game:resetForNewGame()
  self.vineState = VINE_UPSWING_LOWER
  self.prevVineState = VINE_UPSWING_LOWER
  self.vineTimer = 0
  self.vineSpeed = 0
  self.updateScore = false
  self.mainState = 0
  self.helperState = 0
  self.excellentsInRow = 0
  self.excellentsInRowRecord = 0
  self.initScoreUpdate = false
  self.numPlayersAtPeak = 0
  self.allowVineUpdates = false
  self.allPlayersReady = false
  self.funcActive = true
  self.comm.jumpScore = 0
  self.comm.receivedBonusFlags = 0
  self.comm.jumpsInRow = 0
  self.showBonus = false
  self.skipJumpUpdate = false
  self.giveBonus = false
  self:resetPlayersForNewGame()
  self:resetPlayersJumpStates()
  for i = 0, MAX_RFU_PLAYERS - 1 do
    self.atJumpPeak[i] = false
    self.jumpTimeStarts[i] = 0
  end
end

-- pokefirered/src/pokemon_jump.c:954
function Game:initPlayerAndJumpTypes()
  local types = {}
  for _, row in ipairs(self.tables.jump_mons) do
    types[tonumber(row.species)] = tonumber(row.jumpType) or 0
  end
  for i = 0, MAX_RFU_PLAYERS - 1 do
    self.players[i].monJumpType = types[self.monInfo[i].species] or 0
  end
  self.player = self.players[self.multiplayerId]
end

-- pokefirered/src/pokemon_jump.c:967
function Game:resetPlayersForNewGame()
  for i = 0, MAX_RFU_PLAYERS - 1 do
    local p = self.players[i]
    p.jumpTimeStart = 0
    p.monState = MONSTATE_NORMAL
    p.prevMonState = MONSTATE_NORMAL
    p.jumpOffset = 0
    p.jumpOffsetIdx = INT_MAX
    p.jumpState = JUMPSTATE_NONE
    self.memberFuncIds[i] = FUNC_NONE
  end
end

function Game:markGone(i)
  if i == nil or i == self.multiplayerId or self.gone[i] then return end
  self.gone[i] = true
  local p = self.players[i]
  p.monState = MONSTATE_NORMAL
  p.prevMonState = MONSTATE_NORMAL
  p.jumpState = JUMPSTATE_NONE
  p.jumpOffset = 0
  p.jumpOffsetIdx = INT_MAX
  local s = self.gfx.monSprites[i]
  if s then s.gone = true end
end

-- pokefirered/src/pokemon_jump.c:1023
function Game:frame()
  if not self.started then
    self.startDelayTimer = self.startDelayTimer + 1
    if self.startDelayTimer >= 20 then
      self.started = true
      self:initVineState()
    end
    return
  end
  if self:isLeader() then self:leaderTask() else self:memberTask() end
end

-- pokefirered/src/pokemon_jump.c:1101
function Game:setFuncLeader(funcId)
  self.comm.funcId = funcId
  self.mainState = 0
  self.helperState = 0
  self.funcActive = true
  self.allPlayersReady = false
  for i = 0, self.numPlayers - 1 do
    if i ~= self.multiplayerId then self.players[i].funcFinished = false end
  end
end

-- pokefirered/src/pokemon_jump.c:1114
function Game:recvLinkDataLeader()
  local numReady = 0
  for i = 0, self.numPlayers - 1 do
    if i ~= self.multiplayerId then
      local p = self.players[i]
      local pkt = self.memberPackets[i]
      if self:active(i) and type(pkt) == "table" then
        local monState = p.monState
        p.monState = tonumber(pkt.ms) or MONSTATE_NORMAL
        p.jumpState = tonumber(pkt.js) or JUMPSTATE_NONE
        p.funcFinished = pkt.ff == 1
        p.jumpTimeStart = u16(tonumber(pkt.jt) or 0)
        self.playAgainStates[i] = tonumber(pkt.pa) or 0
        self.memberFuncIds[i] = tonumber(pkt.fn) or FUNC_NONE
        p.prevMonState = monState
      end
      if not self:active(i) or (p.funcFinished and self.memberFuncIds[i] == self.comm.funcId) then
        numReady = numReady + 1
      end
    end
  end
  if numReady == self.numPlayers - 1 then self.allPlayersReady = true end
end

local LEADER_FUNCS, MEMBER_FUNCS

-- pokefirered/src/pokemon_jump.c:1153
function Game:leaderTask()
  self:recvLinkDataLeader()
  self:tryUpdateScore()
  if not self.funcActive and self.allPlayersReady then
    self:setFuncLeader(self.nextFuncId)
  end
  if self.funcActive then
    local fn = LEADER_FUNCS[self.comm.funcId]
    if not fn or not fn(self) then
      self.funcActive = false
      self.players[self.multiplayerId].funcFinished = true
    end
  end
  self:updateGame()
end

-- pokefirered/src/pokemon_jump.c:1188
function Game:setFuncMember(funcId)
  self.comm.funcId = funcId
  self.mainState = 0
  self.helperState = 0
  self.funcActive = true
  self.players[self.multiplayerId].funcFinished = false
end

local function packetPlayer(pkt, i)
  local list = type(pkt) == "table" and pkt.p
  local row = type(list) == "table" and list[i + 1]
  if type(row) ~= "table" then return nil end
  return row
end

-- pokefirered/src/pokemon_jump.c:1197
function Game:recvLinkDataMember()
  local pkt = self.leaderPacket
  if type(pkt) ~= "table" then return end
  local L = self.leaderIdx
  local me = self.multiplayerId
  local lp = self.players[L]
  local row = packetPlayer(pkt, L)
  if lp and row and L ~= me then
    local monState = lp.monState
    lp.monState = tonumber(row[1]) or MONSTATE_NORMAL
    lp.jumpState = tonumber(row[2]) or JUMPSTATE_NONE
    lp.jumpTimeStart = u16(tonumber(row[3]) or 0)
    local funcId = tonumber(pkt.fn) or FUNC_NONE
    if self.players[me].funcFinished and funcId ~= self.comm.funcId then
      self:setFuncMember(funcId)
    end
    local score = tonumber(pkt.sc) or 0
    if self.comm.jumpScore ~= score then
      self.comm.jumpScore = score
      self.updateScore = true
      self.comm.receivedBonusFlags = tonumber(pkt.b) or 0
      self.showBonus = self.comm.receivedBonusFlags ~= 0
    end
    self.comm.data = u16(tonumber(pkt.d) or 0)
    self.comm.jumpsInRow = tonumber(pkt.r) or 0
    lp.prevMonState = monState
  end
  for i = 0, self.numPlayers - 1 do
    if i ~= me and i ~= L and self:active(i) then
      local r = packetPlayer(pkt, i)
      if r then
        local p = self.players[i]
        local monState = p.monState
        p.monState = tonumber(r[1]) or MONSTATE_NORMAL
        p.jumpState = tonumber(r[2]) or JUMPSTATE_NONE
        p.jumpTimeStart = u16(tonumber(r[3]) or 0)
        p.funcFinished = r[4] == 1
        p.prevMonState = monState
      end
    end
  end
end

-- pokefirered/src/pokemon_jump.c:1252
function Game:memberTask()
  self:recvLinkDataMember()
  if self.funcActive then
    local fn = MEMBER_FUNCS[self.comm.funcId]
    if not fn or not fn(self) then
      self.funcActive = false
      self.players[self.multiplayerId].funcFinished = true
    end
  end
  self:updateGame()
end

-- pokefirered/src/pokemon_jump.c:1281
local function gameIntroLeader(self)
  if self.mainState == 0 then self.mainState = 1 end
  if self.mainState == 1 then
    if not self:doGameIntro() then
      self.comm.data = self.vineTimer
      self.nextFuncId = FUNC_WAIT_ROUND
      return false
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1302
local function gameIntroMember(self)
  if self.mainState == 0 then
    self.rngSeed = self.comm.data
    self.mainState = 1
  end
  if self.mainState == 1 then return self:doGameIntro() end
  return true
end

-- pokefirered/src/pokemon_jump.c:1318
local function waitRoundLeader(self)
  if self.mainState == 0 then
    self:resetPlayersJumpStates()
    self.mainState = 1
  elseif self.mainState == 1 then
    if self.allPlayersReady then
      self.nextFuncId = FUNC_GAME_ROUND
      return false
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1339
local function waitRoundMember(self)
  if self.mainState == 0 then
    self:resetPlayersJumpStates()
    self.vineTimer = self.comm.data
    self.mainState = 1
  end
  if self.mainState == 1 then return false end
  return true
end

-- pokefirered/src/pokemon_jump.c:1358
local function gameRoundLeader(self)
  if not self:handleSwingRound() then
    self.comm.data = self.vineTimer
    self.nextFuncId = FUNC_WAIT_ROUND
  elseif self:updateVineHitStates() then
    return true
  else
    self:resetVineAfterHit()
    self.nextFuncId = FUNC_GAME_OVER
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:1379
local function gameRoundMember(self)
  if not self:handleSwingRound() then
    return false
  elseif self:updateVineHitStates() then
    return true
  end
  self:resetVineAfterHit()
  return false
end

-- pokefirered/src/pokemon_jump.c:1391
local function gameOverLeader(self)
  local s = self.mainState
  if s == 0 then
    self:updateVineHitStates()
    if self:allPlayersJumpedOrHit() then self.mainState = 1 end
  elseif s == 1 then
    if not self:doVineHitEffect() then
      if self:hasEnoughScoreForPrize() then
        self.comm.data = self:getPrizeData()
        self.nextFuncId = FUNC_GIVE_PRIZE
      elseif self.comm.jumpsInRow >= 200 then
        self.comm.data = self.excellentsInRowRecord
        self.nextFuncId = FUNC_SAVE
      else
        self.comm.data = self.excellentsInRowRecord
        self.nextFuncId = FUNC_ASK_PLAY_AGAIN
      end
      self.mainState = 2
      return false
    end
  elseif s == 2 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1430
local function gameOverMember(self)
  local s = self.mainState
  if s == 0 then
    if not self:updateVineHitStates() then self:resetVineAfterHit() end
    if self:allPlayersJumpedOrHit() then self.mainState = 1 end
  elseif s == 1 then
    if not self:doVineHitEffect() then
      self.mainState = 2
      return false
    end
  elseif s == 2 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1454
local function askPlayAgainLeader(self)
  if self.mainState == 0 then self.mainState = 1 end
  local s = self.mainState
  if s == 1 then
    if not self:doPlayAgainPrompt() then
      self:tryUpdateRecords(self.comm.jumpScore, self.comm.jumpsInRow, self.comm.data)
      self.mainState = 2
    end
  elseif s == 2 then
    if self.allPlayersReady then
      if self:shouldPlayAgain() then
        self.nextFuncId = FUNC_RESET_GAME
      else
        self.nextFuncId = FUNC_EXIT
      end
      self.mainState = 3
      return false
    end
  elseif s == 3 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1488
local function askPlayAgainMember(self)
  if self.mainState == 0 then self.mainState = 1 end
  if self.mainState == 1 then
    if not self:doPlayAgainPrompt() then
      self:tryUpdateRecords(self.comm.jumpScore, self.comm.jumpsInRow, self.comm.data)
      self.playAgainComm = self.playAgainState
      return false
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1509
local function resetGameLeader(self)
  if self.mainState == 0 then
    if not self:closeMessageAndResetScore() then self.mainState = 1 end
  elseif self.mainState == 1 then
    if self.allPlayersReady then
      self:resetForNewGame()
      self.rngSeed = u16(self.random())
      self.comm.data = self.rngSeed
      self.nextFuncId = FUNC_GAME_INTRO
      return false
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1532
local function resetGameMember(self)
  if self.mainState == 0 then
    if not self:closeMessageAndResetScore() then
      self:resetForNewGame()
      self.mainState = 1
      return false
    end
  elseif self.mainState == 1 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1551
local function exitGame(self)
  local s = self.mainState
  if s == 0 then
    self.mainState = 1
  elseif s == 1 then
    self.mainState = 2
  elseif s == 2 then
    if not self:closePokeJumpLink() then self.exited = true end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1574
local function givePrizeLeader(self)
  if self.mainState == 0 then
    self.mainState = 1
  elseif self.mainState == 1 then
    if not self:tryGivePrize() then
      self.comm.data = self.excellentsInRowRecord
      self.nextFuncId = FUNC_SAVE
      return false
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1595
local function givePrizeMember(self)
  return self:tryGivePrize()
end

-- pokefirered/src/pokemon_jump.c:1604
local function savePokeJump(self)
  local s = self.mainState
  local gfx = self.gfx
  if s == 0 then
    self:tryUpdateRecords(self.comm.jumpScore, self.comm.jumpsInRow, self.comm.data)
    gfx:setFunc(Gfx.FUNC.MSG_SAVING)
    self.mainState = 1
  elseif s == 1 then
    if not gfx:busy() then self.mainState = 2 end
  elseif s == 2 then
    if self.hooks.save then self.hooks.save() end
    self.saveTimer = 0
    self.mainState = 3
  elseif s == 3 then
    self.saveTimer = self.saveTimer + 1
    if self.saveTimer >= Game.SAVE_FRAMES then
      gfx:clearMessageWindow()
      self.mainState = 4
    end
  elseif s == 4 then
    if not gfx:removeMessageWindow() then
      self.nextFuncId = FUNC_ASK_PLAY_AGAIN
      return false
    end
  end
  return true
end

LEADER_FUNCS = {
  [FUNC_GAME_INTRO] = gameIntroLeader,
  [FUNC_WAIT_ROUND] = waitRoundLeader,
  [FUNC_GAME_ROUND] = gameRoundLeader,
  [FUNC_GAME_OVER] = gameOverLeader,
  [FUNC_ASK_PLAY_AGAIN] = askPlayAgainLeader,
  [FUNC_RESET_GAME] = resetGameLeader,
  [FUNC_EXIT] = exitGame,
  [FUNC_GIVE_PRIZE] = givePrizeLeader,
  [FUNC_SAVE] = savePokeJump,
}

MEMBER_FUNCS = {
  [FUNC_GAME_INTRO] = gameIntroMember,
  [FUNC_WAIT_ROUND] = waitRoundMember,
  [FUNC_GAME_ROUND] = gameRoundMember,
  [FUNC_GAME_OVER] = gameOverMember,
  [FUNC_ASK_PLAY_AGAIN] = askPlayAgainMember,
  [FUNC_RESET_GAME] = resetGameMember,
  [FUNC_EXIT] = exitGame,
  [FUNC_GIVE_PRIZE] = givePrizeMember,
  [FUNC_SAVE] = savePokeJump,
}

-- pokefirered/src/pokemon_jump.c:1646
function Game:doGameIntro()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    gfx:setFunc(Gfx.FUNC.SHOW_NAMES_HIGHLIGHT)
    gfx:resetMonSpriteSubpriorities()
    self.helperState = 1
  elseif h == 1 then
    if not gfx:busy() then
      gfx:startMonIntroBounce(self.multiplayerId)
      self.timer = 0
      self.helperState = 2
    end
  elseif h == 2 then
    self.timer = self.timer + 1
    if self.timer > 120 then
      gfx:setFunc(Gfx.FUNC.ERASE_NAMES)
      self.helperState = 3
    end
  elseif h == 3 then
    if not gfx:busy() and not gfx:isMonIntroBounceActive() then self.helperState = 4 end
  elseif h == 4 then
    if self.skipCountdown then
      self.skipCountdown = false
      gfx:resetMonSpriteSubpriorities()
    else
      gfx:setFunc(Gfx.FUNC.COUNTDOWN)
    end
    self.helperState = 5
  elseif h == 5 then
    if not gfx:busy() then
      self:disableVineUpdates()
      gfx:setUpResetVineGfx()
      self.helperState = 6
    end
  elseif h == 6 then
    if not gfx:resetVineGfx() then
      self:enableVineUpdates()
      self:resetVineState()
      self.helperState = 7
      self.gamesStarted = self.gamesStarted + 1
      return false
    end
  elseif h == 7 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1705
function Game:handleSwingRound()
  self:updateVineState()
  if self.ignoreJumpInput ~= 0 then
    self.ignoreJumpInput = 0
    return false
  end
  local h = self.helperState
  if h == 0 then
    if self:isPlayersMonState(MONSTATE_NORMAL) then
      self.helperState = 1
      h = 1
    end
  end
  if h == 1 then
    if self.joy.a then
      self:setMonStateJump()
      self.helperState = 2
    end
  elseif h == 2 then
    if self:isPlayersMonState(MONSTATE_JUMP) then self.helperState = 3 end
  elseif h == 3 then
    if self:isPlayersMonState(MONSTATE_NORMAL) then self.helperState = 0 end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1743
function Game:doVineHitEffect()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    for i = 0, self.numPlayers - 1 do
      if gfx:isMonHitShakeActive(i) then return true end
    end
    self.helperState = 1
  elseif h == 1 then
    for i = 0, self.numPlayers - 1 do
      if self.players[i].monState == MONSTATE_HIT then gfx:startMonHitFlash(i) end
    end
    gfx:setFunc(Gfx.FUNC.SHOW_NAMES)
    self.timer = 0
    self.helperState = 2
  elseif h == 2 then
    self.timer = self.timer + 1
    if self.timer > 100 then
      gfx:setFunc(Gfx.FUNC.ERASE_NAMES)
      self.timer = 0
      self.helperState = 3
    end
  elseif h == 3 then
    if not gfx:busy() then
      gfx:stopMonHitFlash()
      self.comm.receivedBonusFlags = 0
      self:resetPlayersMonState()
      self.helperState = 4
      return false
    end
  elseif h == 4 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1794
function Game:tryGivePrize()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    self.prizeItemId, self.prizeItemQuantity = Game.unpackPrizeData(self.comm.data)
    gfx:printPrizeMessage(self.prizeItemId, self.prizeItemQuantity)
    self.helperState = 1
  elseif h == 1 or h == 4 then
    if not gfx:doPrizeMessageAndFanfare() then
      self.timer = 0
      self.helperState = h + 1
    end
  elseif h == 2 or h == 5 then
    self.timer = self.timer + 1
    if self.joy.a or self.joy.b or self.timer > 180 then
      gfx:clearMessageWindow()
      self.helperState = h + 1
    end
  elseif h == 3 then
    if not gfx:removeMessageWindow() then
      self.prizeItemQuantity = self:getQuantityLimitedByBag(self.prizeItemId, self.prizeItemQuantity)
      local added = self.prizeItemQuantity > 0 and self.hooks.addItem
        and self.hooks.addItem(self.prizeItemId, self.prizeItemQuantity)
      if added then
        if not self:checkBagHasSpace(self.prizeItemId, 1) then
          gfx:printPrizeFilledBagMessage(self.prizeItemId)
          self.helperState = 4
        else
          self.helperState = 6
        end
      else
        gfx:printNoRoomForPrizeMessage(self.prizeItemId)
        self.helperState = 4
      end
    end
  elseif h == 6 then
    if not gfx:removeMessageWindow() then return false end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1856
function Game:doPlayAgainPrompt()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    gfx:setFunc(Gfx.FUNC.MSG_PLAY_AGAIN)
    self.helperState = 1
  elseif h == 1 then
    if not gfx:busy() then self.helperState = 2 end
  elseif h == 2 then
    local input = gfx:processYesNoInput(self.joy)
    if input == Gfx.MENU_B_PRESSED or input == 1 then
      self.playAgainState = PLAY_AGAIN_NO
      gfx:setFunc(Gfx.FUNC.ERASE_MSG)
      self.helperState = 3
    elseif input == 0 then
      self.playAgainState = PLAY_AGAIN_YES
      gfx:setFunc(Gfx.FUNC.ERASE_MSG)
      self.helperState = 3
    end
  elseif h == 3 then
    if not gfx:busy() then self.helperState = 4 end
  elseif h == 4 then
    gfx:setFunc(Gfx.FUNC.MSG_COMM_STANDBY)
    self.helperState = 5
  elseif h == 5 then
    if not gfx:busy() then
      self.helperState = 6
      return false
    end
  elseif h == 6 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1909
function Game:closePokeJumpLink()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    gfx:clearMessageWindow()
    self.helperState = 1
  elseif h == 1 then
    if not gfx:removeMessageWindow() then
      gfx:setFunc(Gfx.FUNC.MSG_PLAYER_DROPPED)
      self.helperState = 2
    end
  elseif h == 2 then
    if not gfx:busy() then
      self.timer = 0
      self.helperState = 3
    end
  elseif h == 3 then
    self.timer = self.timer + 1
    if self.timer > 120 then
      gfx:beginFadeOut()
      self.helperState = 4
    end
  elseif h == 4 then
    if not gfx:fadeActive() then
      self.helperState = 5
    end
  elseif h == 5 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:1954
function Game:closeMessageAndResetScore()
  local gfx = self.gfx
  local h = self.helperState
  if h == 0 then
    gfx:clearMessageWindow()
    gfx:printScore(0)
    self.helperState = 1
  elseif h == 1 then
    if not gfx:removeMessageWindow() then
      self.helperState = 2
      return false
    end
  elseif h == 2 then
    return false
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:2028
function Game:initVineState()
  self.vineTimer = 0
  self.vineState = VINE_UPSWING_LOWER
  self.vineStateTimer = 0
  self.vineSpeed = 0
  self.ignoreJumpInput = 0
  self.gameOver = false
end

-- pokefirered/src/pokemon_jump.c:2038
function Game:resetVineState()
  self.vineTimer = 0
  self.vineStateTimer = vineStateTimer(VINE_UPSWING_LOWER)
  self.vineState = VINE_UPSWING_LOW
  self.ignoreJumpInput = 0
  self.gameOver = false
  self.vineSpeedStage = 0
  self.vineBaseSpeedIdx = 0
  self.vineSpeedAccel = 0
  self.vineSpeedDelay = 0
  self.atMaxSpeedStage = false
  self:updateVineSpeed()
end

-- pokefirered/src/pokemon_jump.c:2053
function Game:updateVineState()
  if not self.allowVineUpdates then return end
  self.vineTimer = u16(self.vineTimer + 1)
  self.vineStateTimer = self.vineStateTimer + self:getVineSpeed()
  if self.vineStateTimer >= vineStateTimer(NUM_VINESTATES - 1) then
    self.vineStateTimer = self.vineStateTimer - vineStateTimer(NUM_VINESTATES - 1)
  end
  self.prevVineState = self.vineState
  self.vineState = math.floor(self.vineStateTimer / 256)
  if self.vineState > VINE_UPSWING_LOWER and self.prevVineState < VINE_UPSWING_LOW then
    self.ignoreJumpInput = self.ignoreJumpInput + 1
    self:updateVineSpeed()
  end
end

-- pokefirered/src/pokemon_jump.c:2074
function Game:getVineSpeed()
  if self.gameOver then return 0 end
  local speed = self.vineSpeed
  if self.vineStateTimer <= vineStateTimer(VINE_LOWEST) then
    self.vineSpeedAccel = self.vineSpeedAccel + 80
    speed = speed + math.floor(self.vineSpeedAccel / 256)
  end
  return speed
end

-- pokefirered/src/pokemon_jump.c:2096
function Game:updateVineSpeed()
  local base = self.tables.vine_base_speeds
  local delays = self.tables.vine_speed_delays
  local nBase = #base
  self.vineSpeedAccel = 0
  if self.vineSpeedDelay ~= 0 then
    self.vineSpeedDelay = self.vineSpeedDelay - 1
    if self.atMaxSpeedStage then
      if self:pokeJumpRandom() % 4 ~= 0 then
        self.vineSpeed = self.nextVineSpeed
      elseif self.nextVineSpeed > 54 then
        self.vineSpeed = 30
      else
        self.vineSpeed = 82
      end
    end
    return
  end
  if bit.band(self.vineBaseSpeedIdx, nBase) == 0 then
    self.nextVineSpeed = base[self.vineBaseSpeedIdx + 1] + self.vineSpeedStage * 7
    self.vineSpeedDelay = delays[(self:pokeJumpRandom() % #delays) + 1] + 2
    self.vineBaseSpeedIdx = self.vineBaseSpeedIdx + 1
  else
    if self.vineBaseSpeedIdx == nBase then
      if self.vineSpeedStage < 3 then
        self.vineSpeedStage = self.vineSpeedStage + 1
      else
        self.atMaxSpeedStage = true
      end
    end
    self.nextVineSpeed = base[15 - self.vineBaseSpeedIdx + 1] + self.vineSpeedStage * 7
    self.vineBaseSpeedIdx = self.vineBaseSpeedIdx + 1
    if self.vineBaseSpeedIdx > 15 then
      if self:pokeJumpRandom() % 4 == 0 then
        self.nextVineSpeed = self.nextVineSpeed - 5
      end
      self.vineBaseSpeedIdx = 0
    end
  end
  self.vineSpeed = self.nextVineSpeed
end

-- pokefirered/src/pokemon_jump.c:2152
function Game:pokeJumpRandom()
  self.rngSeed = Game.isoRandomize1(self.rngSeed)
  return math.floor(self.rngSeed / 0x10000)
end

-- pokefirered/src/pokemon_jump.c:2158
function Game:resetVineAfterHit()
  self.gameOver = true
  self.vineState = VINE_UPSWING_LOWER
  self.vineStateTimer = vineStateTimer(VINE_LOWEST)
  self:enableVineUpdates()
end

-- pokefirered/src/pokemon_jump.c:2171
function Game:resetPlayersJumpStates()
  for i = 0, MAX_RFU_PLAYERS - 1 do
    self.players[i].jumpState = JUMPSTATE_NONE
  end
end

-- pokefirered/src/pokemon_jump.c:2178
function Game:resetPlayersMonState()
  self.player.monState = MONSTATE_NORMAL
  self.player.prevMonState = MONSTATE_NORMAL
end

function Game:isPlayersMonState(monState)
  return self.players[self.multiplayerId].monState == monState
end

-- pokefirered/src/pokemon_jump.c:2192
function Game:setMonStateJump()
  self.player.jumpTimeStart = self.vineTimer
  self.player.prevMonState = self.player.monState
  self.player.monState = MONSTATE_JUMP
end

-- pokefirered/src/pokemon_jump.c:2199
function Game:setMonStateHit()
  self.player.prevMonState = self.player.monState
  self.player.monState = MONSTATE_HIT
  self.player.jumpTimeStart = self.vineTimer
  self.player.jumpState = JUMPSTATE_FAILURE
end

function Game:setMonStateNormal()
  self.player.prevMonState = self.player.monState
  self.player.monState = MONSTATE_NORMAL
end

-- pokefirered/src/pokemon_jump.c:2215
function Game:updateGame()
  local gfx = self.gfx
  if self.updateScore then
    gfx:printScore(self.comm.jumpScore)
    self.updateScore = false
    if self.showBonus then
      local numPlayers = gfx:doSameJumpTimeBonus(self.comm.receivedBonusFlags)
      local se = self.tables.sound_effects[numPlayers - 1]
      if se then self:playSe(se) end
      self.showBonus = false
    end
  end
  gfx:printJumpsInRow(self.comm.jumpsInRow)
  self:handleMonState()
  if self.allowVineUpdates then gfx:updateVineSwing(self.vineState) end
end

function Game:disableVineUpdates()
  self.allowVineUpdates = false
end

function Game:enableVineUpdates()
  self.allowVineUpdates = true
end

-- pokefirered/src/pokemon_jump.c:2253
function Game:handleMonState()
  local gfx = self.gfx
  local seJump, seFail = false, false
  for i = 0, self.numPlayers - 1 do
    local p = self.players[i]
    if p.monState == MONSTATE_NORMAL then
      gfx:setMonSpriteY(i, 0)
    elseif p.monState == MONSTATE_JUMP then
      if p.prevMonState ~= MONSTATE_JUMP or p.jumpTimeStart ~= self.jumpTimeStarts[i] then
        if i == self.multiplayerId then p.prevMonState = MONSTATE_JUMP end
        seJump = true
        p.jumpOffsetIdx = INT_MAX
        self.jumpTimeStarts[i] = p.jumpTimeStart
      end
      self:updateJump(i)
    elseif p.monState == MONSTATE_HIT then
      if p.prevMonState ~= MONSTATE_HIT then
        if i == self.multiplayerId then p.prevMonState = MONSTATE_HIT end
        seFail = true
        gfx:startMonHitShake(i)
      end
    end
  end
  if seFail then
    self:playSe(Game.SE_POKE_JUMP_FAILURE)
  elseif seJump then
    self:playSe(Game.SE_LEDGE)
  end
end

-- pokefirered/src/pokemon_jump.c:2321
function Game:updateJump(id)
  if self.skipJumpUpdate then return end
  local p = self.players[id]
  local idx
  if p.jumpOffsetIdx ~= INT_MAX then
    p.jumpOffsetIdx = p.jumpOffsetIdx + 1
    idx = p.jumpOffsetIdx
  else
    idx = self.vineTimer - p.jumpTimeStart
    if idx >= 65000 then
      idx = idx - 65000
      idx = idx + self.vineTimer
    end
    p.jumpOffsetIdx = idx
  end
  if idx < 4 then return end
  idx = idx - 4
  local offset = 0
  local row = self.tables.jump_offsets[p.monJumpType + 1]
  if idx < #row then offset = tonumber(row[idx + 1]) or 0 end
  self.gfx:setMonSpriteY(id, offset)
  if offset == 0 and id == self.multiplayerId then self:setMonStateNormal() end
  p.jumpOffset = offset
end

-- pokefirered/src/pokemon_jump.c:2364
function Game:tryUpdateScore()
  if self.vineState == VINE_UPSWING_HIGH and self.prevVineState == VINE_UPSWING_LOW then
    if not self.initScoreUpdate then
      self.numPlayersAtPeak = 0
      self.initScoreUpdate = true
      self.comm.receivedBonusFlags = 0
    else
      if self.numPlayersAtPeak == MAX_RFU_PLAYERS then
        self.excellentsInRow = self.excellentsInRow + 1
        self:tryUpdateExcellentsRecord(self.excellentsInRow)
      else
        self.excellentsInRow = 0
      end
      if self.numPlayersAtPeak > 1 then
        self.giveBonus = true
        for i = 0, MAX_RFU_PLAYERS - 1 do self.atJumpPeak3[i] = self.atJumpPeak2[i] end
      end
      self.numPlayersAtPeak = 0
      self.initScoreUpdate = true
      self.comm.receivedBonusFlags = 0
      if self.comm.jumpsInRow < MAX_JUMPS then
        self.comm.jumpsInRow = self.comm.jumpsInRow + 1
      end
      self:addJumpScore(10)
    end
  end
  if self.giveBonus and (self:didAllPlayersClearVine() or self.vineState == VINE_HIGHEST) then
    local numPlayers = self:getNumPlayersForBonus(self.atJumpPeak3)
    self:addJumpScore(self:getScoreBonus(numPlayers))
    self.giveBonus = false
  end
  if self.initScoreUpdate then
    local numAtPeak = self:getPlayersAtJumpPeak()
    if numAtPeak > self.numPlayersAtPeak then
      self.numPlayersAtPeak = numAtPeak
      for i = 0, MAX_RFU_PLAYERS - 1 do self.atJumpPeak2[i] = self.atJumpPeak[i] end
    end
  end
end

-- pokefirered/src/pokemon_jump.c:2430
function Game:updateVineHitStates()
  local me = self.player
  if self.vineState == VINE_UPSWING_LOWER and me.jumpOffset == 0 then
    if me.prevMonState == MONSTATE_JUMP and self.gameOver then
      me.jumpState = JUMPSTATE_SUCCESS
    else
      self:setMonStateHit()
    end
  end
  if self.vineState == VINE_UPSWING_LOW and self.prevVineState == VINE_UPSWING_LOWER
      and me.monState ~= MONSTATE_HIT then
    me.jumpState = JUMPSTATE_SUCCESS
  end
  for i = 0, self.numPlayers - 1 do
    if self:active(i) and self.players[i].monState == MONSTATE_HIT then return false end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:2469
function Game:allPlayersJumpedOrHit()
  local n = 0
  for i = 0, self.numPlayers - 1 do
    if not self:active(i) or self.players[i].jumpState ~= JUMPSTATE_NONE then n = n + 1 end
  end
  return n == self.numPlayers
end

-- pokefirered/src/pokemon_jump.c:2483
function Game:didAllPlayersClearVine()
  for i = 0, self.numPlayers - 1 do
    if self:active(i) and self.players[i].jumpState ~= JUMPSTATE_SUCCESS then return false end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:2495
function Game:shouldPlayAgain()
  if self.playAgainState == PLAY_AGAIN_NO then return false end
  for i = 0, self.numPlayers - 1 do
    if i ~= self.multiplayerId then
      if not self:active(i) or self.playAgainStates[i] == PLAY_AGAIN_NO then return false end
    end
  end
  return true
end

-- pokefirered/src/pokemon_jump.c:2511
function Game:addJumpScore(score)
  self.comm.jumpScore = self.comm.jumpScore + score
  self.updateScore = true
  if self.comm.jumpScore >= MAX_JUMP_SCORE then self.comm.jumpScore = MAX_JUMP_SCORE end
end

-- pokefirered/src/pokemon_jump.c:2519
function Game:getPlayersAtJumpPeak()
  local n = 0
  for i = 0, self.numPlayers - 1 do
    if self:active(i) and self.players[i].jumpOffset == JUMP_PEAK then
      self.atJumpPeak[i] = true
      n = n + 1
    else
      self.atJumpPeak[i] = false
    end
  end
  return n
end

-- pokefirered/src/pokemon_jump.c:2546
function Game:getNumPlayersForBonus(peaks)
  local flags, count = 0, 0
  for i = 0, MAX_RFU_PLAYERS - 1 do
    if peaks[i] then
      flags = flags + 2 ^ i
      count = count + 1
    end
  end
  self.comm.receivedBonusFlags = flags
  if flags ~= 0 then self.showBonus = true end
  return count
end

-- pokefirered/src/pokemon_jump.c:2577
function Game:getScoreBonus(numPlayers)
  return tonumber(self.tables.score_bonuses[numPlayers + 1]) or 0
end

function Game:tryUpdateExcellentsRecord(excellentsInRow)
  if excellentsInRow > self.excellentsInRowRecord then
    self.excellentsInRowRecord = excellentsInRow
  end
end

-- pokefirered/src/pokemon_jump.c:2611
function Game:hasEnoughScoreForPrize()
  return self.comm.jumpScore >= tonumber(self.tables.prize_quantity[1].score)
end

-- pokefirered/src/pokemon_jump.c:2619
function Game:getPrizeData()
  local itemId = self:getPrizeItemId()
  local quantity = self:getPrizeQuantity()
  return (quantity * 0x1000 + itemId % 0x1000) % 0x10000
end

-- pokefirered/src/pokemon_jump.c:2626
function Game.unpackPrizeData(data)
  data = tonumber(data) or 0
  return data % 0x1000, math.floor(data / 0x1000)
end

-- pokefirered/src/pokemon_jump.c:2632
function Game:getPrizeItemId()
  local items = self.tables.prize_items
  return tonumber(items[(u16(self.random()) % #items) + 1])
end

-- pokefirered/src/pokemon_jump.c:2638
function Game:getPrizeQuantity()
  local quantity = 0
  for _, row in ipairs(self.tables.prize_quantity) do
    if self.comm.jumpScore >= tonumber(row.score) then
      quantity = tonumber(row.quantity)
    else
      break
    end
  end
  return quantity
end

function Game:checkBagHasSpace(item, quantity)
  if not self.hooks.canAdd then return false end
  return self.hooks.canAdd(item, quantity) and true or false
end

-- pokefirered/src/pokemon_jump.c:2654
function Game:getQuantityLimitedByBag(item, quantity)
  while quantity > 0 and not self:checkBagHasSpace(item, quantity) do
    quantity = quantity - 1
  end
  return quantity
end

-- pokefirered/src/pokemon_jump.c:4465
function Game:tryUpdateRecords(jumpScore, jumpsInRow, excellentsInRow)
  local b = self.best
  if jumpScore > b.score and jumpScore <= MAX_JUMP_SCORE then b.score = jumpScore end
  if jumpsInRow > b.jumpsInRow and jumpsInRow <= MAX_JUMPS then b.jumpsInRow = jumpsInRow end
  if excellentsInRow > b.excellentsInRow and excellentsInRow <= MAX_JUMPS then
    b.excellentsInRow = excellentsInRow
  end
  if self.hooks.updateRecords then
    return self.hooks.updateRecords(jumpScore, jumpsInRow, excellentsInRow)
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:3337
function Game.prizeItemName(itemId, quantity, name)
  name = tostring(name or "")
  if itemId >= FIRST_BERRY_INDEX and itemId < LAST_BERRY_INDEX and quantity > 1 and #name > 0 then
    name = name:sub(1, #name - 1) .. "IES"
  end
  return name
end

local function mask(list, n)
  local m = 0
  for i = 0, n - 1 do
    if list[i] then m = m + 2 ^ i end
  end
  return m
end

local function unmask(m, n, out)
  m = tonumber(m) or 0
  for i = 0, n - 1 do
    out[i] = math.floor(m / 2 ^ i) % 2 == 1
  end
end

-- pokefirered/src/pokemon_jump.c:2774
function Game:leaderPacketOut(withMonInfo)
  local p = {}
  for i = 0, self.numPlayers - 1 do
    local pl = self.players[i]
    local fid = (i == self.multiplayerId) and self.comm.funcId or self.memberFuncIds[i]
    p[i + 1] = { pl.monState, pl.jumpState, pl.jumpTimeStart, pl.funcFinished and 1 or 0, fid,
      (i == self.multiplayerId) and self.playAgainComm or self.playAgainStates[i] }
  end
  local s = {
    fn = self.comm.funcId, d = self.comm.data, r = self.comm.jumpsInRow, sc = self.comm.jumpScore,
    b = self.comm.receivedBonusFlags, p = p, L = self.multiplayerId,
    g = mask(self.gone, self.numPlayers),
    x = self.excellentsInRow, xr = self.excellentsInRowRecord, np = self.numPlayersAtPeak,
    is = self.initScoreUpdate and 1 or 0, gb = self.giveBonus and 1 or 0,
    k2 = mask(self.atJumpPeak2, MAX_RFU_PLAYERS), k3 = mask(self.atJumpPeak3, MAX_RFU_PLAYERS),
    bs = self.best.score, br = self.best.jumpsInRow, bx = self.best.excellentsInRow,
  }
  if withMonInfo then
    local mi = {}
    for i = 0, self.numPlayers - 1 do
      local m = self.monInfo[i]
      mi[i + 1] = { m.species, m.personality, m.shiny and 1 or 0 }
    end
    s.mi = mi
  end
  return s
end

-- pokefirered/src/pokemon_jump.c:2823
function Game:memberPacketOut()
  local me = self.player
  local info = self.monInfo[self.multiplayerId]
  return {
    ms = me.monState, js = me.jumpState, ff = me.funcFinished and 1 or 0, jt = me.jumpTimeStart,
    fn = self.comm.funcId, pa = self.playAgainComm,
    sp = info.species, pv = info.personality, sh = info.shiny and 1 or 0,
  }
end

function Game:applyMonInfo(i, sp, pv, sh)
  if i == self.multiplayerId then return end
  local m = self.monInfo[i]
  if not m then return end
  if tonumber(pv) then m.personality = tonumber(pv) end
  if sh ~= nil then m.shiny = sh == 1 or sh == true end
  if tonumber(sp) and tonumber(sp) > 0 then m.species = tonumber(sp) end
  m.known = true
end

function Game:receiveLeaderPacket(s)
  if type(s) ~= "table" then return end
  self.leaderPacket = s
  local L = tonumber(s.L)
  if L and L >= 0 and L < self.numPlayers then self.leaderIdx = L end
  local g = tonumber(s.g)
  if g then
    for i = 0, self.numPlayers - 1 do
      if math.floor(g / 2 ^ i) % 2 == 1 then self:markGone(i) end
    end
  end
  if type(s.mi) == "table" then
    for i = 0, self.numPlayers - 1 do
      local row = s.mi[i + 1]
      if type(row) == "table" then self:applyMonInfo(i, row[1], row[2], row[3]) end
    end
  end
end

function Game:receiveMemberPacket(i, pkt)
  if type(pkt) ~= "table" or i == self.multiplayerId then return end
  self.memberPackets[i] = pkt
  self:applyMonInfo(i, pkt.sp, pkt.pv, pkt.sh)
end

-- pokefirered/src/pokemon_jump.c:1153
function Game:becomeLeader(pkt)
  local me = self.multiplayerId
  if type(pkt) == "table" then
    self:receiveLeaderPacket(pkt)
    self:recvLinkDataMember()
    self.excellentsInRow = tonumber(pkt.x) or self.excellentsInRow
    self.excellentsInRowRecord = tonumber(pkt.xr) or self.excellentsInRowRecord
    self.numPlayersAtPeak = tonumber(pkt.np) or self.numPlayersAtPeak
    self.initScoreUpdate = pkt.is == 1
    self.giveBonus = pkt.gb == 1
    unmask(pkt.k2, MAX_RFU_PLAYERS, self.atJumpPeak2)
    unmask(pkt.k3, MAX_RFU_PLAYERS, self.atJumpPeak3)
    self.best.score = math.max(self.best.score, tonumber(pkt.bs) or 0)
    self.best.jumpsInRow = math.max(self.best.jumpsInRow, tonumber(pkt.br) or 0)
    self.best.excellentsInRow = math.max(self.best.excellentsInRow, tonumber(pkt.bx) or 0)
    for i = 0, self.numPlayers - 1 do
      local row = packetPlayer(pkt, i)
      if i ~= me and row then
        self.memberFuncIds[i] = tonumber(row[5]) or FUNC_NONE
        self.playAgainStates[i] = tonumber(row[6]) or 0
        self.memberPackets[i] = self.memberPackets[i] or {
          ms = row[1], js = row[2], jt = row[3], ff = row[4], fn = row[5], pa = row[6] }
      end
    end
  end
  local old = self.leaderIdx
  self.leaderIdx = me
  if old ~= me then self:markGone(old) end
  local F = self.comm.funcId
  if self.funcActive then
    if F == FUNC_GIVE_PRIZE then self.mainState = 1 end
  elseif F == FUNC_GAME_ROUND then
    local hit = false
    for i = 0, self.numPlayers - 1 do
      if self:active(i) and self.players[i].monState == MONSTATE_HIT then hit = true end
    end
    if hit then
      self.nextFuncId = FUNC_GAME_OVER
    else
      self.comm.data = self.vineTimer
      self.nextFuncId = FUNC_WAIT_ROUND
    end
    self.allPlayersReady = false
  elseif F == FUNC_SAVE then
    self.funcActive = true
  elseif F ~= FUNC_EXIT and F ~= FUNC_NONE then
    self.funcActive = true
    self.mainState = 1
  end
end

function Game:becomeMember()
  self.leaderIdx = -1
end

return Game

local Gfx = {}
Gfx.__index = Gfx

-- pokefirered/src/pokemon_jump.c:70
Gfx.FUNC = {
  LOAD = 0,
  SHOW_NAMES = 1,
  SHOW_NAMES_HIGHLIGHT = 2,
  ERASE_NAMES = 3,
  MSG_PLAY_AGAIN = 4,
  MSG_SAVING = 5,
  ERASE_MSG = 6,
  MSG_PLAYER_DROPPED = 7,
  MSG_COMM_STANDBY = 8,
  COUNTDOWN = 9,
}

-- pokefirered/include/constants/songs.h:9
Gfx.SE_SELECT = 5
-- pokefirered/include/constants/songs.h:32
Gfx.SE_BIKE_HOP = 28
-- pokefirered/include/constants/songs.h:264
Gfx.MUS_LEVEL_UP = 257
Gfx.MUS_DUMMY = 0

Gfx.MENU_NOTHING_CHOSEN = -2
Gfx.MENU_B_PRESSED = -1

local VINE_HIGHEST = 0
local VINE_LOWEST = 5
local VINE_UPSWING_LOWER = 6
local VINE_UPSWING_LOW = 7
local NUM_VINESTATES = 10

-- pokefirered/src/pokemon_jump.c:4085
local STAR_SPIN = { 0, 1, 2, 3, 0, 1, 2, 3, 0 }
local STAR_FRAME_DURATION = 4

local SINE = {}
for i = 0, 255 do
  SINE[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5)
end
Gfx.SINE = SINE

local function zeroData()
  return { [0] = 0, 0, 0, 0, 0, 0, 0, 0 }
end

function Gfx.new(o)
  local self = setmetatable({
    numPlayers = o.numPlayers,
    multiplayerId = o.multiplayerId,
    tables = o.tables,
    hooks = o.hooks or {},
    countdownFactory = o.countdown,
    funcFinished = false,
    mainState = 0,
    func = nil,
    resetVineState = 0,
    resetVineTimer = 0,
    vineState = VINE_UPSWING_LOWER,
    msgWindowState = 0,
    msgWindow = nil,
    fanfare = Gfx.MUS_DUMMY,
    bonusTimer = 0,
    bonusTasks = 0,
    bonus = { visible = false, x = 0, y8 = 0 },
    names = { added = false, visible = false, highlight = false },
    yesno = nil,
    points = 0,
    times = 0,
    venusaurY = 0,
    vine = { anim = 0, priority = 2, pal2 = false, state = VINE_HIGHEST },
    monSprites = {},
    starSprites = {},
    monSpriteSubpriorities = {},
    countdown = nil,
    fade = nil,
    frames = 0,
  }, Gfx)
  self:load(o.yOffsets or {})
  return self
end

function Gfx:playSe(id)
  if self.hooks.playSe then self.hooks.playSe(id) end
end

-- pokefirered/src/pokemon_jump.c:3030
function Gfx:load(yOffsets)
  self:printScore(0)
  self:createJumpMonSprites(yOffsets)
  self:updateVineAnim(VINE_UPSWING_LOWER)
  self.bonus.visible = false
  self.funcFinished = true
end

-- pokefirered/src/pokemon_jump.c:3582
function Gfx:createJumpMonSprites(yOffsets)
  local xs = self.tables.mon_x_coords[self.numPlayers]
  for i = 0, self.numPlayers - 1 do
    local x = xs[i + 1]
    local y = (tonumber(yOffsets[i]) or 0) + 112
    local sub = (i == self.multiplayerId) and 3 or (i + 4)
    self.monSprites[i] = { x = x, y = y, y2 = 0, invisible = false, cb = nil,
      data = zeroData(), subpriority = sub, gone = false }
    self.monSpriteSubpriorities[i] = sub
    self.starSprites[i] = { x = x, y = 112, invisible = true, cb = nil, t = 0,
      animEnded = true, frame = 0, spinning = false }
  end
end

function Gfx:busy()
  return self.funcFinished ~= true
end

function Gfx:setFunc(id)
  self.func = id
  self.mainState = 0
  self.funcFinished = false
end

-- pokefirered/src/pokemon_jump.c:3019
function Gfx:runFunc()
  if self.funcFinished then return end
  local F = Gfx.FUNC
  local id = self.func
  if id == F.SHOW_NAMES then self:funcShowNames(false)
  elseif id == F.SHOW_NAMES_HIGHLIGHT then self:funcShowNames(true)
  elseif id == F.ERASE_NAMES then self:funcEraseNames()
  elseif id == F.MSG_PLAY_AGAIN then self:funcMsgPlayAgain()
  elseif id == F.MSG_SAVING then self:funcMessage("gText_SavingDontTurnOffPower", 2, 7, 26, 4)
  elseif id == F.ERASE_MSG then self:funcEraseMessage()
  elseif id == F.MSG_PLAYER_DROPPED then self:funcMessage("gText_SomeoneDroppedOut2", 2, 8, 22, 4)
  elseif id == F.MSG_COMM_STANDBY then self:funcMessage("gText_CommunicationStandby4", 7, 10, 16, 2)
  elseif id == F.COUNTDOWN then self:funcCountdown()
  else self.funcFinished = true end
end

-- pokefirered/src/pokemon_jump.c:3082
function Gfx:funcShowNames(highlight)
  local s = self.mainState
  if s == 0 then
    self.names = { added = true, visible = false, highlight = false }
    self.mainState = 1
  elseif s == 1 then
    self.names.highlight = highlight
    self.names.printed = true
    self.mainState = 2
  elseif s == 2 then
    self.names.visible = true
    self.mainState = 3
  elseif s == 3 then
    self.funcFinished = true
  end
end

-- pokefirered/src/pokemon_jump.c:3140
function Gfx:funcEraseNames()
  if self.mainState == 0 then
    self.names.visible = false
    self.mainState = 1
  elseif self.mainState == 1 then
    self.names = { added = false, visible = false, highlight = false }
    self.funcFinished = true
  end
end

function Gfx:addMessageWindow(key, left, top, width, height, extra)
  local w = { key = key, left = left, top = top, width = width, height = height, shown = false }
  for k, v in pairs(extra or {}) do w[k] = v end
  self.msgWindow = w
  return w
end

-- pokefirered/src/pokemon_jump.c:3166
function Gfx:funcMsgPlayAgain()
  local s = self.mainState
  if s == 0 then
    self:addMessageWindow("gText_WantToPlayAgain2", 1, 8, 20, 2)
    self.mainState = 1
  elseif s == 1 then
    self.msgWindow.shown = true
    self:createYesNoMenu(23, 7, 0)
    self.mainState = 2
  elseif s == 2 then
    self.funcFinished = true
  end
end

-- pokefirered/src/pokemon_jump.c:3193
function Gfx:funcMessage(key, left, top, width, height)
  local s = self.mainState
  if s == 0 then
    self:addMessageWindow(key, left, top, width, height)
    self.mainState = 1
  elseif s == 1 then
    self.msgWindow.shown = true
    self.mainState = 2
  elseif s == 2 then
    self.funcFinished = true
  end
end

-- pokefirered/src/pokemon_jump.c:3219
function Gfx:funcEraseMessage()
  if self.mainState == 0 then
    self:clearMessageWindow()
    self:destroyYesNoMenu()
    self.mainState = 1
  elseif self.mainState == 1 then
    if not self:removeMessageWindow() then self.funcFinished = true end
  end
end

-- pokefirered/src/pokemon_jump.c:3288
function Gfx:funcCountdown()
  if self.mainState == 0 then
    self:startCountdown()
    self.mainState = 1
  elseif self.mainState == 1 then
    if not self:isCountdownRunning() then self.funcFinished = true end
  end
end

-- pokefirered/src/pokemon_jump.c:4438
function Gfx:startCountdown()
  if self.countdownFactory then
    self.countdown = self.countdownFactory()
  else
    local Countdown = require("src.ui.game3.minigames.common_countdown")
    local hooks = self.hooks
    self.countdown = Countdown.new(120, 80, { playSe = function(id) if hooks.playSe then hooks.playSe(id) end end })
  end
  self:resetMonSpriteSubpriorities()
end

function Gfx:isCountdownRunning()
  local c = self.countdown
  return c ~= nil and c:running()
end

-- pokefirered/src/pokemon_jump.c:3303
function Gfx:setUpResetVineGfx()
  self.resetVineState = 0
  self.resetVineTimer = 0
  self.vineState = VINE_UPSWING_LOWER
  self:updateVineSwing(self.vineState)
end

-- pokefirered/src/pokemon_jump.c:3311
function Gfx:resetVineGfx()
  if self.resetVineState == 0 then
    self.resetVineTimer = self.resetVineTimer + 1
    if self.resetVineTimer > 10 then
      self.resetVineTimer = 0
      self.vineState = self.vineState + 1
      if self.vineState >= NUM_VINESTATES then
        self.vineState = VINE_HIGHEST
        self.resetVineState = self.resetVineState + 1
      end
    end
    self:updateVineSwing(self.vineState)
    if self.vineState ~= VINE_UPSWING_LOW then return true end
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:3339
function Gfx:printPrizeMessage(itemId, quantity)
  self:addMessageWindow("gText_AwesomeWonF701F700", 4, 8, 22, 4, { itemId = itemId, quantity = quantity })
  self.fanfare = Gfx.MUS_LEVEL_UP
  self.msgWindowState = 0
end

-- pokefirered/src/pokemon_jump.c:3367
function Gfx:printPrizeFilledBagMessage(itemId)
  self:addMessageWindow("gText_FilledStorageSpace2", 4, 8, 22, 4, { itemId = itemId })
  self.fanfare = Gfx.MUS_DUMMY
  self.msgWindowState = 0
end

-- pokefirered/src/pokemon_jump.c:3380
function Gfx:printNoRoomForPrizeMessage(itemId)
  self:addMessageWindow("gText_CantHoldMore", 4, 9, 22, 2, { itemId = itemId })
  self.fanfare = Gfx.MUS_DUMMY
  self.msgWindowState = 0
end

-- pokefirered/src/pokemon_jump.c:3393
function Gfx:doPrizeMessageAndFanfare()
  local s = self.msgWindowState
  if s == 0 then
    if self.msgWindow then self.msgWindow.shown = true end
    self.msgWindowState = 1
    return true
  end
  if s == 1 then
    if self.fanfare == Gfx.MUS_DUMMY then
      self.msgWindowState = self.msgWindowState + 2
      return false
    end
    if self.hooks.playFanfare then self.hooks.playFanfare(self.fanfare) end
    self.msgWindowState = 2
    s = 2
  end
  if s == 2 then
    if self.hooks.fanfareDone and not self.hooks.fanfareDone() then return true end
    self.msgWindowState = 3
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:3427
function Gfx:clearMessageWindow()
  if self.msgWindow then
    self.msgWindow.shown = false
    self.msgWindowState = 0
  end
end

-- pokefirered/src/pokemon_jump.c:3437
function Gfx:removeMessageWindow()
  if not self.msgWindow then return false end
  if self.msgWindowState == 0 then
    self.msgWindow = nil
    self.msgWindowState = 1
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:3483
function Gfx:createYesNoMenu(left, top, cursor)
  self.yesno = { left = left, top = top, width = 6, height = 4, cursor = cursor or 0 }
end

-- pokefirered/src/menu.c:568
function Gfx:destroyYesNoMenu()
  self.yesno = nil
end

-- pokefirered/src/menu.c:560
function Gfx:processYesNoInput(joy)
  local menu = self.yesno
  if not menu then return Gfx.MENU_NOTHING_CHOSEN end
  joy = joy or {}
  local result = Gfx.MENU_NOTHING_CHOSEN
  if joy.a then
    self:playSe(Gfx.SE_SELECT)
    result = menu.cursor
  elseif joy.b then
    result = Gfx.MENU_B_PRESSED
  elseif joy.up then
    if menu.cursor > 0 then
      menu.cursor = menu.cursor - 1
      self:playSe(Gfx.SE_SELECT)
    end
  elseif joy.down then
    if menu.cursor < 1 then
      menu.cursor = menu.cursor + 1
      self:playSe(Gfx.SE_SELECT)
    end
  end
  if result ~= Gfx.MENU_NOTHING_CHOSEN then self:destroyYesNoMenu() end
  return result
end

-- pokefirered/src/pokemon_jump.c:3653
function Gfx:printScore(num)
  self.points = tonumber(num) or 0
end

-- pokefirered/src/pokemon_jump.c:3658
function Gfx:printJumpsInRow(num)
  self.times = tonumber(num) or 0
end

-- pokefirered/src/pokemon_jump.c:4399
function Gfx:updateVineAnim(vineState)
  local v = self.vine
  v.state = vineState
  if vineState > VINE_LOWEST then
    v.anim = NUM_VINESTATES - vineState
    v.priority = 3
    v.pal2 = true
  else
    v.anim = vineState
    v.priority = 2
    v.pal2 = false
  end
end

-- pokefirered/src/pokemon_jump.c:3603
function Gfx:updateVineSwing(vineState)
  self:updateVineAnim(vineState)
  self.venusaurY = (tonumber(self.tables.venusaur_states[vineState + 1]) or 0) * 5 * 8192 / 256
end

-- pokefirered/src/pokemon_jump.c:3598
function Gfx:setMonSpriteY(id, y)
  local s = self.monSprites[id]
  if s then s.y2 = y end
end

-- pokefirered/src/pokemon_jump.c:3767
function Gfx:showBonus(bonusId)
  self.bonusTimer = 0
  self.bonus.x = math.floor(bonusId / 2) * 256
  self.bonus.y8 = ((bonusId % 2) * 256 - 40) * 256
  self.bonus.visible = true
  self.bonus.id = bonusId
  self.bonusTasks = self.bonusTasks + 1
end

-- pokefirered/src/pokemon_jump.c:3776
function Gfx:updateBonus()
  if self.bonusTimer >= 32 then return false end
  self.bonus.y8 = self.bonus.y8 + 128
  self.bonusTimer = self.bonusTimer + 1
  if self.bonusTimer >= 32 then self.bonus.visible = false end
  return true
end

function Gfx:bonusScrollY()
  return math.floor(self.bonus.y8 / 256)
end

-- pokefirered/src/pokemon_jump.c:4190
function Gfx:doStarAnim(id)
  local star = self.starSprites[id]
  if not star then return end
  star.invisible = false
  star.y = 96
  star.cb = "star"
  star.state = 0
  star.t = 0
  star.frame = 0
  star.animEnded = false
  star.spinning = true
end

-- pokefirered/src/pokemon_jump.c:3609
function Gfx:doSameJumpTimeBonus(flags)
  local numPlayers = 0
  for i = 0, 4 do
    if flags % 2 == 1 then
      self:doStarAnim(i)
      numPlayers = numPlayers + 1
    end
    flags = math.floor(flags / 2)
  end
  self:showBonus(numPlayers - 2)
  return numPlayers
end

-- pokefirered/src/pokemon_jump.c:4234
function Gfx:startMonHitShake(id)
  local s = self.monSprites[id]
  if not s then return end
  s.cb = "shake"
  s.y2 = 0
  s.data = zeroData()
end

function Gfx:isMonHitShakeActive(id)
  local s = self.monSprites[id]
  return s ~= nil and s.cb == "shake"
end

-- pokefirered/src/pokemon_jump.c:4271
function Gfx:startMonHitFlash(id)
  local s = self.monSprites[id]
  if not s then return end
  s.data = zeroData()
  s.cb = "flash"
end

-- pokefirered/src/pokemon_jump.c:4277
function Gfx:stopMonHitFlash()
  for i = 0, self.numPlayers - 1 do
    local s = self.monSprites[i]
    if s.cb == "flash" then
      s.invisible = false
      s.cb = nil
      s.subpriority = 10
    end
  end
end

-- pokefirered/src/pokemon_jump.c:4305
function Gfx:resetMonSpriteSubpriorities()
  for i = 0, self.numPlayers - 1 do
    self.monSprites[i].subpriority = self.monSpriteSubpriorities[i]
  end
end

-- pokefirered/src/pokemon_jump.c:4313
function Gfx:startMonIntroBounce(id)
  local s = self.monSprites[id]
  if not s then return end
  s.data = zeroData()
  s.cb = "bounce"
end

function Gfx:isMonIntroBounceActive()
  for i = 0, self.numPlayers - 1 do
    if self.monSprites[i].cb == "bounce" then return true end
  end
  return false
end

-- pokefirered/src/pokemon_jump.c:4249
local function cbShake(s)
  local d = s.data
  d[1] = d[1] + 1
  if d[1] > 1 then
    d[2] = d[2] + 1
    if d[2] % 2 == 1 then s.y2 = 2 else s.y2 = -2 end
    d[1] = 0
  end
  if d[2] > 12 then
    s.y2 = 0
    s.cb = nil
  end
end

-- pokefirered/src/pokemon_jump.c:4294
local function cbFlash(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > 3 then
    d[0] = 0
    s.invisible = not s.invisible
  end
end

-- pokefirered/src/pokemon_jump.c:4336
function Gfx:cbBounce(s)
  local d = s.data
  if d[0] == 0 then
    self:playSe(Gfx.SE_BIKE_HOP)
    d[1] = 0
    d[0] = 1
  end
  if d[0] == 1 then
    d[1] = d[1] + 4
    if d[1] > 127 then d[1] = 0 end
    s.y2 = -math.floor(SINE[d[1]] / 8)
    if d[1] == 0 then
      d[2] = d[2] + 1
      if d[2] < 2 then
        d[0] = 0
      else
        s.cb = nil
      end
    end
  end
end

-- pokefirered/src/pokemon_jump.c:4200
local function cbStar(star)
  if star.animEnded then
    star.invisible = true
    star.cb = nil
  end
end

-- pokefirered/src/sprite.c:905
local function animStar(star)
  if not star.spinning then return end
  star.t = star.t + 1
  local idx = math.floor((star.t - 1) / STAR_FRAME_DURATION) + 1
  if idx > #STAR_SPIN then
    star.animEnded = true
    star.spinning = false
    return
  end
  star.frame = STAR_SPIN[idx]
end

-- pokefirered/src/sprite.c:304
function Gfx:animateSprites()
  for i = 0, self.numPlayers - 1 do
    local s = self.monSprites[i]
    if s.cb == "shake" then cbShake(s)
    elseif s.cb == "flash" then cbFlash(s)
    elseif s.cb == "bounce" then self:cbBounce(s) end
    local star = self.starSprites[i]
    if star.cb == "star" then cbStar(star) end
    animStar(star)
  end
end

-- pokefirered/src/palette.c:151
function Gfx:beginFadeOut()
  self.fade = { y = 0, active = true, deltaY = 3 }
end

function Gfx:fadeActive()
  return self.fade ~= nil and self.fade.active
end

function Gfx:updateFade()
  local f = self.fade
  if not f or not f.active then return end
  if f.y >= 16 then
    f.active = false
    return
  end
  f.y = math.min(16, f.y + f.deltaY)
end

function Gfx:fadeLevel()
  return self.fade and self.fade.y or 0
end

function Gfx:update()
  self.frames = self.frames + 1
  self:runFunc()
  local n = self.bonusTasks
  for _ = 1, n do
    if not self:updateBonus() then self.bonusTasks = self.bonusTasks - 1 end
  end
  if self.countdown and self.countdown:running() then self.countdown:step() end
  self:animateSprites()
  self:updateFade()
end

return Gfx

local Art = require("src.ui.game3.minigames.common_art")

local Countdown = {}
Countdown.__index = Countdown

Countdown.DIR = "link"
Countdown.NUMBERS = "minigame_countdown_numbers"
Countdown.START = "minigame_countdown_start"
-- pokefirered/include/constants/songs.h:54
Countdown.SE_BALL_BOUNCE_2 = 50
-- pokefirered/src/minigame_countdown.c:83
Countdown.ANCHOR_Y = 26

local END = false

-- pokefirered/src/minigame_countdown.c:274
local AFFINE = {
  [0] = { { 0x100, 0x100, 0 }, END },
  [1] = { { 0x100, 0x100, 0 }, { 0x10, -0x10, 8 }, END },
  [2] = { { -0x12, 0x12, 8 }, END },
  [3] = { { 0x6, -0x6, 8 }, { -0x4, 0x4, 8 }, { 0x100, 0x100, 0 }, END },
}

local SINE = {}
for i = 0, 255 do
  SINE[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5)
end

local function shr(v, n)
  return math.floor(v / (2 ^ n))
end

local function newAffine()
  return { xs = 0x100, ys = 0x100, anim = 0, idx = 1, delay = 0, beginning = false, ended = true }
end

local function applyCmd(a, cmd)
  if cmd[3] > 0 then
    a.xs, a.ys = a.xs + cmd[1], a.ys + cmd[2]
    a.delay = cmd[3] - 1
  else
    a.xs, a.ys = cmd[1], cmd[2]
    a.delay = 0
  end
end

-- pokefirered/src/sprite.c:1063
local function stepAffine(a)
  local cmds = AFFINE[a.anim]
  if a.beginning then
    a.beginning = false
    a.ended = false
    a.idx = 1
    local cmd = cmds[1]
    if cmd == END then a.ended = true return end
    applyCmd(a, cmd)
    return
  end
  if a.delay > 0 then
    a.delay = a.delay - 1
    local cmd = cmds[a.idx]
    if cmd then a.xs, a.ys = a.xs + cmd[1], a.ys + cmd[2] end
    return
  end
  local nextCmd = cmds[a.idx + 1]
  if nextCmd == END or nextCmd == nil then
    a.ended = true
    return
  end
  a.idx = a.idx + 1
  applyCmd(a, nextCmd)
end

local function startAffine(a, n)
  a.anim = n
  a.beginning = true
  a.ended = false
end

-- pokefirered/src/minigame_countdown.c:27
function Countdown.new(x, y, opts)
  opts = opts or {}
  local self = setmetatable({
    x = tonumber(x) or 120,
    y = tonumber(y) or 80,
    playSe = opts.playSe,
    state = 0,
    digit = { state = 0, t = 0, n = 0, frame = 0, dy = 0, alive = true, aff = newAffine() },
    starts = nil,
    frames = 0,
  }, Countdown)
  return self
end

function Countdown:se()
  if self.playSe then
    self.playSe(Countdown.SE_BALL_BOUNCE_2)
    return
  end
  pcall(function() require("src.core.game3.audio").playSe(Countdown.SE_BALL_BOUNCE_2) end)
end

-- pokefirered/src/minigame_countdown.c:76
function Countdown:stepDigit()
  local d = self.digit
  if d.state == 0 then
    d.state = 1
  end
  if d.state == 1 then
    if d.t == 0 then self:se() end
    d.t = d.t + 1
    if d.t >= 20 then
      d.t = 0
      startAffine(d.aff, 1)
      d.state = 2
    end
  elseif d.state == 2 then
    if d.aff.ended then d.state = 3 end
  elseif d.state == 3 then
    d.t = d.t + 1
    if d.t >= 4 then
      d.t = 0
      d.state = 4
      startAffine(d.aff, 2)
    end
  elseif d.state == 4 then
    d.dy = d.dy - 4
    d.t = d.t + 1
    if d.t >= 8 then
      if d.n < 2 then
        d.frame = d.n + 1
        d.t = 0
        d.state = 5
      else
        d.state = 7
        return false
      end
    end
  elseif d.state == 5 then
    d.dy = d.dy + 4
    d.t = d.t + 1
    if d.t >= 8 then
      d.t = 0
      startAffine(d.aff, 3)
      d.state = 6
    end
  elseif d.state == 6 then
    if d.aff.ended then
      d.n = d.n + 1
      d.state = 1
    end
  elseif d.state == 7 then
    return false
  end
  return true
end

local function newStart()
  return { state = 0, y2 = -40, d1 = 0, d4 = 0, d5 = 0, done = false }
end

-- pokefirered/src/minigame_countdown.c:162
function Countdown:stepStart(s)
  if s.done then return end
  if s.state == 0 then
    s.d4 = 64
    s.d5 = s.y2 * 16
    s.state = 1
  end
  if s.state == 1 then
    s.d5 = s.d5 + s.d4
    s.d4 = s.d4 + 1
    s.y2 = shr(s.d5, 4)
    if s.y2 >= 0 then
      self:se()
      s.y2 = 0
      s.state = 2
    end
  elseif s.state == 2 then
    s.d1 = s.d1 + 12
    if s.d1 >= 128 then
      self:se()
      s.d1 = 0
      s.state = 3
    end
    s.y2 = -shr(SINE[s.d1], 4)
  elseif s.state == 3 then
    s.d1 = s.d1 + 16
    if s.d1 >= 128 then
      self:se()
      s.d1 = 0
      s.state = 4
    end
    s.y2 = -shr(SINE[s.d1], 5)
  elseif s.state == 4 then
    s.d1 = s.d1 + 1
    if s.d1 > 40 then s.done = true end
  end
end

-- pokefirered/src/minigame_countdown.c:42
function Countdown:step()
  if self.state == 3 then return false end
  self.frames = self.frames + 1
  if self.state == 0 then
    self.state = 1
  end
  if self.state == 1 then
    if not self:stepDigit() then
      self.digit.alive = false
      self.starts = { newStart(), newStart() }
      self.state = 2
    end
  elseif self.state == 2 then
    if self.starts[1].done then
      self.starts = nil
      self.state = 3
      return false
    end
  end
  if self.digit.alive then stepAffine(self.digit.aff) end
  if self.starts then
    self:stepStart(self.starts[1])
    self:stepStart(self.starts[2])
  end
  return true
end

function Countdown:running()
  return self.state ~= 3
end

function Countdown:digitShown()
  if not self.digit.alive then return nil end
  return 3 - self.digit.frame
end

-- pokefirered/src/sprite.c:1203
local function anchorCoord(scale256, modifier)
  local dim = 32
  local baseDim = dim * 256
  local xformed = dim * scale256
  local sub = xformed - baseDim
  local shift
  if sub < 0 then shift = shr(-sub, 9) else shift = -shr(sub, 9) end
  return modifier - (math.floor(modifier * xformed / baseDim) + shift)
end

function Countdown:digitPose()
  local d = self.digit
  local sx, sy = d.aff.xs / 256, d.aff.ys / 256
  local y2 = anchorCoord(d.aff.ys, Countdown.ANCHOR_Y)
  return self.x, self.y + d.dy + y2, sx, sy
end

Countdown._art = nil

function Countdown.loadArt(cache)
  if Countdown._art then return Countdown._art end
  local art, err = Art.load(Countdown.DIR, { Countdown.NUMBERS, Countdown.START }, cache)
  if not art then return nil, err end
  Countdown._art = art
  return art
end

function Countdown:draw(art)
  art = art or Countdown._art or assert(Countdown.loadArt())
  if self.digit.alive and self.state ~= 3 then
    local x, y, sx, sy = self:digitPose()
    Art.drawFrame(art[Countdown.NUMBERS], self.digit.frame, x, y, sx, sy, 16, 16)
  end
  if self.starts then
    local sheet = art[Countdown.START]
    Art.drawFrame(sheet, 0, self.x - 32, self.y + self.starts[1].y2, 1, 1, 32, 16)
    Art.drawFrame(sheet, 1, self.x + 32, self.y + self.starts[2].y2, 1, 1, 32, 16)
  end
end

function Countdown.totalFrames()
  local c = Countdown.new(120, 80, { playSe = function() end })
  local n = 0
  while c:step() do n = n + 1 end
  return n
end

return Countdown

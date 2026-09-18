local Fx = require("src.core.game3.gba_fx")

local Pal = {}
Pal.__index = Pal

Pal.WHITE = { 31, 31, 31 }
Pal.BLACK = { 0, 0, 0 }

local function bit(mask, i)
  return math.floor(mask / 2 ^ i) % 2 == 1
end

function Pal.new()
  local self = setmetatable({ slots = {}, fade = nil, gradual = {} }, Pal)
  self:reset()
  return self
end

function Pal:reset()
  for i = 0, 31 do
    self.slots[i] = { y = 0, color = Pal.BLACK, gray = false, base = nil }
  end
  self.fade = nil
  self.gradual = {}
end

function Pal.mask(bg, obj)
  local m = 0
  for _, i in ipairs(bg or {}) do m = m + 2 ^ i end
  for _, i in ipairs(obj or {}) do m = m + 2 ^ (16 + i) end
  return m
end

Pal.ALL = 2 ^ 32 - 1
Pal.BG = 2 ^ 16 - 1
Pal.OBJ = Pal.ALL - Pal.BG

local function blendRange(self, mask, lo, hi, y, color)
  for i = lo, hi do
    if bit(mask, i) then
      local s = self.slots[i]
      s.y = y
      s.color = color
    end
  end
end

-- pokefirered/src/palette.c:778
function Pal:blend(mask, y, color)
  blendRange(self, mask, 0, 31, y, color)
end

function Pal:setGray(slot, on)
  self.slots[slot].gray = on and true or false
end

function Pal:setBase(slot, color)
  self.slots[slot].base = color
end

function Pal:restore(slot)
  local s = self.slots[slot]
  s.y, s.gray, s.base = 0, false, nil
end

-- pokefirered/src/palette.c:157
function Pal:beginFade(mask, delay, startY, targetY, color)
  if self.fade and self.fade.active then return false end
  local deltaY = 2
  if delay < 0 then
    deltaY = deltaY - delay
    delay = 0
  end
  self.fade = {
    active = true, mask = mask, delay = delay, counter = delay,
    y = startY, target = targetY, color = color, deltaY = deltaY,
    yDec = startY >= targetY, toggle = 0, finishing = false, finishCount = 0,
  }
  self:updateFade()
  return true
end

function Pal:fadeActive()
  return self.fade ~= nil and self.fade.active
end

-- pokefirered/src/palette.c:414
function Pal:updateFade()
  local f = self.fade
  if not (f and f.active) then return false end
  if f.finishing then
    if f.finishCount == 4 then
      f.active = false
      f.finishing = false
      f.finishCount = 0
    else
      f.finishCount = f.finishCount + 1
    end
    return f.active
  end
  if f.toggle == 0 then
    if f.counter < f.delay then
      f.counter = f.counter + 1
      return true
    end
    f.counter = 0
  end
  if f.toggle == 0 then
    blendRange(self, f.mask, 0, 15, f.y, f.color)
  else
    blendRange(self, f.mask, 16, 31, f.y, f.color)
  end
  f.toggle = 1 - f.toggle
  if f.toggle == 0 then
    if f.y == f.target then
      f.mask = 0
      f.finishing = true
    elseif not f.yDec then
      f.y = math.min(f.target, f.y + f.deltaY)
    else
      f.y = math.max(f.target, f.y - f.deltaY)
    end
  end
  return true
end

function Pal:resetFade()
  self.fade = nil
end

-- pokefirered/src/palette.c:912
function Pal:blendGradually(mask, delay, coeff, target, color)
  local t = { mask = mask, coeff = coeff, target = target, color = color, timer = 0 }
  if delay >= 0 then
    t.delay, t.delta = delay, 1
  else
    t.delay, t.delta = 0, -delay + 1
  end
  if target < coeff then t.delta = -t.delta end
  self.gradual[#self.gradual + 1] = t
  self:_stepGradual(t)
  return t
end

-- pokefirered/src/palette.c:935
function Pal:_stepGradual(t)
  if t.done then return end
  t.timer = t.timer + 1
  if t.timer > t.delay then
    t.timer = 0
    self:blend(t.mask, t.coeff, t.color)
    if t.coeff == t.target then
      t.done = true
      return
    end
    t.coeff = t.coeff + t.delta
    if (t.delta >= 0 and t.coeff >= t.target) or (t.delta < 0 and t.coeff <= t.target) then
      t.coeff = t.target
    end
  end
end

function Pal:runGradual()
  local keep = {}
  for _, t in ipairs(self.gradual) do
    self:_stepGradual(t)
    if not t.done then keep[#keep + 1] = t end
  end
  self.gradual = keep
end

function Pal:gradualActive()
  for _, t in ipairs(self.gradual) do
    if not t.done then return true end
  end
  return false
end

function Pal:clearGradual()
  self.gradual = {}
end

function Pal:fx(slot, extra)
  local s = self.slots[slot]
  local y, color = s.y, s.color
  local fx = { y = y, color = color, gray = s.gray }
  if s.base then
    fx.base = s.base
    fx.y = 16
    fx.color = { s.base[1] + math.floor((color[1] - s.base[1]) * y / 16),
      s.base[2] + math.floor((color[2] - s.base[2]) * y / 16),
      s.base[3] + math.floor((color[3] - s.base[3]) * y / 16) }
  end
  if extra then
    for k, v in pairs(extra) do fx[k] = v end
  end
  if not Fx.active(fx) then return nil end
  return fx
end

function Pal.bgSlot(i) return i end
function Pal.objSlot(i) return 16 + i end

return Pal

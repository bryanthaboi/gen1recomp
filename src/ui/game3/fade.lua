-- FRLG-style screen fade overlay for game3 (boot, field adapters, Oak).
-- Modes match pret include/constants/field_weather.h (fadescreen operand):
--   FADE_FROM_BLACK=0, FADE_TO_BLACK=1, FADE_FROM_WHITE=2, FADE_TO_WHITE=3

local Display = require("src.core.game3.display")

local Fade = {}

Fade.active = false
Fade.mode = 0
Fade.speed = 1 -- palette steps per frame (pret speed)
Fade.t = 0 -- 0..16 blend strength toward target
Fade.doneCb = nil
Fade._dir = 1 -- +1 toward cover, -1 toward clear

local MODE = {
  FROM_BLACK = 0, -- pret FADE_FROM_BLACK
  TO_BLACK = 1,   -- pret FADE_TO_BLACK
  FROM_WHITE = 2, -- pret FADE_FROM_WHITE
  TO_WHITE = 3,   -- pret FADE_TO_WHITE
}
Fade.MODE = MODE

local function targetColor(mode)
  if mode == MODE.TO_WHITE or mode == MODE.FROM_WHITE then
    return 1, 1, 1
  end
  return 0, 0, 0
end

--- Start a fade. done() called when complete.
-- speed: frames per step of 16 (default 1 → ~16 frames).
function Fade.begin(mode, speed, done)
  mode = tonumber(mode) or 0
  speed = math.max(1, tonumber(speed) or 1)
  Fade.active = true
  Fade.mode = mode
  Fade.speed = speed
  Fade.doneCb = done
  Fade._accum = 0
  if mode == MODE.FROM_BLACK or mode == MODE.FROM_WHITE then
    Fade.t = 16
    Fade._dir = -1
  else
    Fade.t = 0
    Fade._dir = 1
  end
end

function Fade.isActive()
  return Fade.active
end

function Fade.tick(dt)
  if not Fade.active then return false end
  -- Frame-based: one step every `speed` frames at 60Hz.
  local frames = (dt or 1 / 60) * 60
  Fade._accum = (Fade._accum or 0) + frames
  while Fade._accum >= Fade.speed do
    Fade._accum = Fade._accum - Fade.speed
    Fade.t = Fade.t + Fade._dir
    if Fade._dir > 0 and Fade.t >= 16 then
      Fade.t = 16
      Fade:_finish()
      return true
    elseif Fade._dir < 0 and Fade.t <= 0 then
      Fade.t = 0
      Fade:_finish()
      return true
    end
  end
  return false
end

function Fade:_finish()
  Fade.active = false
  Fade.lockInput = nil
  local cb = Fade.doneCb
  Fade.doneCb = nil
  if (Fade.t or 0) <= 0 then
    local okR, Renderer = pcall(require, "src.render.Renderer")
    if okR and Renderer then
      Renderer.screenVeil = nil
    end
  end
  if cb then cb() end
end

function Fade.draw()
  if not Fade.active and (Fade.t or 0) <= 0 then return end
  local a = (Fade.t or 0) / 16
  if a <= 0 then return end
  local r, g, b = targetColor(Fade.mode)

  local okR, Renderer = pcall(require, "src.render.Renderer")
  if okR and Renderer and Renderer.canvas then
    Renderer.screenVeil = { r, g, b, a }
    return
  end

  love.graphics.setColor(r, g, b, a)
  local w, h = Display.W, Display.H
  local curCanvas = love.graphics.getCanvas()
  if curCanvas then
    local okW, cw, ch = pcall(function() return curCanvas:getWidth(), curCanvas:getHeight() end)
    if okW and cw and ch then w, h = cw, ch end
  elseif love and love.graphics and love.graphics.getDimensions then
    local gw, gh = love.graphics.getDimensions()
    if gw and gh and gw > 0 and gh > 0 then w, h = gw, gh end
  end
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Instant clear (no anim).
function Fade.clear()
  Fade.lockInput = nil
  Fade.active = false
  Fade.t = 0
  Fade.doneCb = nil
  local okR, Renderer = pcall(require, "src.render.Renderer")
  if okR and Renderer then
    Renderer.screenVeil = nil
  end
end

return Fade

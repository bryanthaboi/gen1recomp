-- pret-faithful GBA background layers for game3 (4 hardware BGs).
-- Each BG has its own priority 0..3 (lower = closer to camera).
-- Display.composeHardware interleaves Bg.flushPriority with Oam.flushPriority.

local Bg = {}

Bg.COUNT = 4 -- BG0..BG3
Bg.COORD_SET = 0
Bg.COORD_ADD = 1
Bg.COORD_SUB = 2

local function new_layer(id)
  return {
    id = id,
    visible = false,
    priority = 0,
    image = nil,
    quad = nil,
    -- Pixel scroll (pret ChangeBgX/Y are Q8.8; callers convert or use setScrollPx)
    scrollX = 0,
    scrollY = 0,
    -- Optional wrap period for H/V tiling (nil = no wrap)
    wrapW = nil,
    wrapH = nil,
    -- Extra draw offset (close-up nudges, letterbox)
    offsetX = 0,
    offsetY = 0,
    alpha = 1,
    fx = nil,
    blend = nil,
    clip = nil,
  }
end

Bg._layers = nil

local function ensure()
  if Bg._layers then return end
  Bg._layers = {}
  for i = 0, Bg.COUNT - 1 do
    Bg._layers[i] = new_layer(i)
  end
end

function Bg.reset()
  ensure()
  for i = 0, Bg.COUNT - 1 do
    local L = Bg._layers[i]
    L.visible = false
    L.priority = 0
    L.image = nil
    L.quad = nil
    L.scrollX = 0
    L.scrollY = 0
    L.wrapW = nil
    L.wrapH = nil
    L.offsetX = 0
    L.offsetY = 0
    L.alpha = 1
    L.fx = nil
    L.blend = nil
    L.clip = nil
  end
end

function Bg.get(bg)
  ensure()
  bg = tonumber(bg)
  if bg == nil or bg < 0 or bg >= Bg.COUNT then return nil end
  return Bg._layers[bg]
end

--- InitBgsFromTemplates-style: { {bg=, priority=, ...}, ... }
function Bg.initFromTemplates(templates)
  Bg.reset()
  if not templates then return end
  for _, t in ipairs(templates) do
    local L = Bg.get(t.bg)
    if L then
      L.priority = tonumber(t.priority) or 0
      if t.visible then L.visible = true end
    end
  end
end

function Bg.setImage(bg, image, quad)
  local L = Bg.get(bg)
  if not L then return end
  L.image = image
  L.quad = quad
end

function Bg.setQuad(bg, quad)
  local L = Bg.get(bg)
  if not L then return end
  L.quad = quad
end

function Bg.setPriority(bg, priority)
  local L = Bg.get(bg)
  if not L then return end
  L.priority = math.max(0, math.min(3, tonumber(priority) or 0))
end

function Bg.show(bg)
  local L = Bg.get(bg)
  if L then L.visible = true end
end

function Bg.hide(bg)
  local L = Bg.get(bg)
  if L then L.visible = false end
end

function Bg.setAlpha(bg, a)
  local L = Bg.get(bg)
  if L then L.alpha = tonumber(a) or 1 end
end

function Bg.setOffset(bg, ox, oy)
  local L = Bg.get(bg)
  if not L then return end
  if ox ~= nil then L.offsetX = ox end
  if oy ~= nil then L.offsetY = oy end
end

function Bg.setWrap(bg, wrapW, wrapH)
  local L = Bg.get(bg)
  if not L then return end
  L.wrapW = wrapW
  L.wrapH = wrapH
end

--- Direct pixel scroll.
function Bg.setScrollPx(bg, x, y)
  local L = Bg.get(bg)
  if not L then return end
  if x ~= nil then L.scrollX = x end
  if y ~= nil then L.scrollY = y end
end

--- pret ChangeBgX: value is Q8.8 (256ths of a pixel) when using ADD/SUB/SET modes.
function Bg.changeBgX(bg, value, mode)
  local L = Bg.get(bg)
  if not L then return end
  local px = (tonumber(value) or 0) / 256
  mode = mode or Bg.COORD_SET
  if mode == Bg.COORD_ADD then
    L.scrollX = L.scrollX + px
  elseif mode == Bg.COORD_SUB then
    L.scrollX = L.scrollX - px
  else
    L.scrollX = px
  end
end

function Bg.changeBgY(bg, value, mode)
  local L = Bg.get(bg)
  if not L then return end
  local px = (tonumber(value) or 0) / 256
  mode = mode or Bg.COORD_SET
  if mode == Bg.COORD_ADD then
    L.scrollY = L.scrollY + px
  elseif mode == Bg.COORD_SUB then
    L.scrollY = L.scrollY - px
  else
    L.scrollY = px
  end
end

function Bg.hasVisible()
  ensure()
  for i = 0, Bg.COUNT - 1 do
    local L = Bg._layers[i]
    if L.visible and L.image then return true end
  end
  return false
end

local function modPositive(a, n)
  return ((a % n) + n) % n
end

local Fx = require("src.core.game3.gba_fx")

function Bg.setFx(bg, fx)
  local L = Bg.get(bg)
  if L then L.fx = fx end
end

function Bg.setBlend(bg, blend)
  local L = Bg.get(bg)
  if L then L.blend = blend end
end

function Bg.setClip(bg, clip)
  local L = Bg.get(bg)
  if L then L.clip = clip end
end

local function blitRaw(L)
  local img = L.image
  local a = L.alpha or 1
  love.graphics.setColor(1, 1, 1, a)

  local scrollX = math.floor(L.scrollX or 0)
  local scrollY = math.floor(L.scrollY or 0)
  local ox = (L.offsetX or 0) - scrollX
  local oy = (L.offsetY or 0) - scrollY
  local wrapW = L.wrapW
  local wrapH = L.wrapH

  -- GBA sampling: screen (0,0) shows image (scrollX, scrollY), with optional wrap.
  local function drawAt(x, y)
    if L.quad then
      love.graphics.draw(img, L.quad, x, y)
    else
      love.graphics.draw(img, x, y)
    end
  end

  if wrapW and wrapW > 0 and wrapH and wrapH > 0 then
    local startX = modPositive(ox, wrapW)
    if startX > 0 then startX = startX - wrapW end
    local startY = modPositive(oy, wrapH)
    if startY > 0 then startY = startY - wrapH end
    local y = startY
    while y < 160 + wrapH do
      local x = startX
      while x < 240 + wrapW do
        drawAt(x, y)
        x = x + wrapW
      end
      y = y + wrapH
    end
  elseif wrapW and wrapW > 0 then
    local start = modPositive(ox, wrapW)
    if start > 0 then start = start - wrapW end
    local x = start
    while x < 240 + wrapW do
      drawAt(x, oy)
      x = x + wrapW
    end
  elseif wrapH and wrapH > 0 then
    local start = modPositive(oy, wrapH)
    if start > 0 then start = start - wrapH end
    local y = start
    while y < 160 + wrapH do
      drawAt(ox, y)
      y = y + wrapH
    end
  else
    drawAt(ox, oy)
  end
end

local function blitLayer(L)
  if not L.image then return end
  if L.clip and (L.clip.w <= 0 or L.clip.h <= 0) then return end
  Fx.withClip(L.clip, function()
    Fx.draw(function() blitRaw(L) end, L.fx, L.blend)
  end)
end

--- Draw all visible BGs with the given hardware priority (back-to-front caller loops 3→0).
--- Same-priority BGs: lower BG index drawn later (in front), matching GBA.
function Bg.flushPriority(priority)
  if not love or not love.graphics then return end
  ensure()
  priority = tonumber(priority) or 0
  -- Collect then draw low index last (front)
  local list = {}
  for i = 0, Bg.COUNT - 1 do
    local L = Bg._layers[i]
    if L.visible and L.image and L.priority == priority then
      list[#list + 1] = L
    end
  end
  table.sort(list, function(a, b) return a.id > b.id end) -- high id first (behind)
  for _, L in ipairs(list) do
    blitLayer(L)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Flush all priorities back→front (BGs only). Prefer Display.composeHardware.
function Bg.flushAll()
  for pri = 3, 0, -1 do
    Bg.flushPriority(pri)
  end
end

return Bg

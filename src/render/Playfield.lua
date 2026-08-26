local GameViewport = require("src.render.GameViewport")
local TouchSkin = require("src.core.TouchSkin")

local Playfield = {}

Playfield.entered = false
Playfield.box = nil

local function clampRect(x, y, w, h, sw, sh)
  if type(w) ~= "number" or type(h) ~= "number" then return nil end
  if w ~= w or h ~= h then return nil end
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w, h = math.floor(w), math.floor(h)
  if x < 0 then w, x = w + x, 0 end
  if y < 0 then h, y = h + y, 0 end
  if x + w > sw then w = sw - x end
  if y + h > sh then h = sh - y end
  if w < 1 or h < 1 then return nil end
  return x, y, w, h
end

function Playfield.cutout(sw, sh)
  if Playfield.entered then return nil end
  if type(sw) ~= "number" or type(sh) ~= "number" then return nil end
  if sw < 1 or sh < 1 then return nil end
  if type(TouchSkin.viewport) ~= "function" then return nil end
  local ok, x, y, w, h, fill, expand = pcall(TouchSkin.viewport, sw, sh)
  if not ok then return nil end
  local cx, cy, cw, ch = clampRect(x, y, w, h, sw, sh)
  if not cx then return nil end
  return cx, cy, cw, ch, fill == true, expand == true
end

function Playfield.rect(sw, sh)
  local x, y, w, h = Playfield.cutout(sw, sh)
  if not x then return 0, 0, sw or 0, sh or 0, false end
  return x, y, w, h, true
end

function Playfield.enter(x, y, w, h)
  Playfield.entered = true
  Playfield.box = { x = x, y = y, w = w, h = h }
end

function Playfield.leave()
  Playfield.entered = false
  Playfield.box = nil
end

function Playfield.dimensions()
  if Playfield.entered and Playfield.box then
    return Playfield.box.w, Playfield.box.h
  end
  return GameViewport.dimensions()
end

function Playfield.push(sw, sh)
  local x, y, w, h, active = Playfield.rect(sw, sh)
  local G = love.graphics
  G.push("all")
  if active then G.setScissor(x, y, w, h) end
  G.translate(x, y)
  Playfield.enter(x, y, w, h)
  return w, h, x, y, active
end

function Playfield.pop()
  Playfield.leave()
  love.graphics.setScissor()
  love.graphics.pop()
end

return Playfield

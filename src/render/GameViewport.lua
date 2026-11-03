-- Optional game viewport inside the OS window. A layout mod may reserve any
-- window-space rectangle through render.viewport; the game then renders as if
-- that rectangle were its whole display. With no subscriber this module is a
-- pass-through and allocates no canvas.

local Runtime = require("src.mods.Runtime")

-- Lazy: DuoPosture -> SafeArea -> this module.
local DuoPosture

local Viewport = {
  rect = nil,
  full = nil,
  canvas = nil,
  generation = nil,
  frameActive = false,
}

local function finite(value)
  return type(value) == "number" and value == value
    and value > -math.huge and value < math.huge
end

local function realMetrics()
  local G = love.graphics
  local w, h = G.getDimensions()
  local pw, ph = w, h
  if G.getPixelDimensions then pw, ph = G.getPixelDimensions() end
  local dpiX = w > 0 and pw / w or 1
  local dpiY = h > 0 and ph / h or 1
  if dpiX < 1e-6 then dpiX = 1 end
  if dpiY < 1e-6 then dpiY = 1 end
  return math.max(1, w), math.max(1, h),
    math.max(1, pw), math.max(1, ph), dpiX, dpiY
end

local function clampRect(value, w, h)
  if type(value) ~= "table" then
    return { x = 0, y = 0, width = w, height = h }
  end
  local x = finite(value.x) and math.floor(value.x) or 0
  local y = finite(value.y) and math.floor(value.y) or 0
  local rw = finite(value.width) and math.floor(value.width) or w
  local rh = finite(value.height) and math.floor(value.height) or h
  x = math.max(0, math.min(x, w - 1))
  y = math.max(0, math.min(y, h - 1))
  rw = math.max(1, math.min(rw, w - x))
  rh = math.max(1, math.min(rh, h - y))
  return { x = x, y = y, width = rw, height = rh }
end

local function sameSize(canvas, w, h)
  return canvas and canvas:getWidth() == w and canvas:getHeight() == h
end

function Viewport.begin(generation)
  local w, h, pw, ph, dpiX, dpiY = realMetrics()
  local context = {
    width = w, height = h, pixelWidth = pw, pixelHeight = ph,
    dpiX = dpiX, dpiY = dpiY, generation = generation,
  }
  -- Foldables (src/core/DuoPosture.lua) put the game in its own half; that
  -- rect is the default a layout mod's render.viewport wraps, so a mod can
  -- still take over.  Nil (and nearly free) without a hinge.
  DuoPosture = DuoPosture or require("src.core.DuoPosture")
  local duo = DuoPosture.current(generation)
  local duoRect = duo and duo.game and {
    x = duo.game.x, y = duo.game.y,
    width = duo.game.w, height = duo.game.h,
  } or nil
  local requested = duoRect
  if Runtime.wantsHook("render.viewport") then
    requested = Runtime.call("render.viewport", function(ctx)
      return duoRect or { x = 0, y = 0, width = ctx.width, height = ctx.height }
    end, context)
  end
  local rect = clampRect(requested, w, h)
  Viewport.full = context
  Viewport.rect = rect
  Viewport.generation = generation
  local active = type(requested) == "table" and requested.capture == true
    or rect.x ~= 0 or rect.y ~= 0
    or rect.width ~= w or rect.height ~= h
  Viewport.frameActive = active
  if active then
    if not sameSize(Viewport.canvas, rect.width, rect.height) then
      if Viewport.canvas and Viewport.canvas.release then
        Viewport.canvas:release()
      end
      Viewport.canvas = love.graphics.newCanvas(rect.width, rect.height)
      Viewport.canvas:setFilter("nearest", "nearest")
    end
  else
    if Viewport.canvas and Viewport.canvas.release then
      Viewport.canvas:release()
    end
    Viewport.canvas = nil
  end
  return rect
end

function Viewport.active()
  return Viewport.frameActive == true and Viewport.canvas ~= nil
end

function Viewport.dimensions()
  if Viewport.active() then
    return Viewport.rect.width, Viewport.rect.height
  end
  return love.graphics.getDimensions()
end

function Viewport.pixelDimensions()
  if Viewport.active() then
    if Viewport.canvas.getPixelDimensions then
      local w, h = Viewport.canvas:getPixelDimensions()
      return math.max(1, w), math.max(1, h)
    end
    return math.max(1, math.floor(Viewport.rect.width * Viewport.full.dpiX)),
      math.max(1, math.floor(Viewport.rect.height * Viewport.full.dpiY))
  end
  if love.graphics.getPixelDimensions then
    return love.graphics.getPixelDimensions()
  end
  return love.graphics.getDimensions()
end

function Viewport.fullDimensions()
  if Viewport.full then return Viewport.full.width, Viewport.full.height end
  return love.graphics.getDimensions()
end

function Viewport.target()
  return Viewport.canvas
end

function Viewport.setTarget()
  love.graphics.setCanvas(Viewport.canvas)
end

function Viewport.toLocal(x, y)
  local rect = Viewport.rect
  if not rect then return x, y, true end
  local lx, ly = x - rect.x, y - rect.y
  return lx, ly,
    lx >= 0 and ly >= 0 and lx < rect.width and ly < rect.height
end

function Viewport.localSafeRect(x, y, w, h)
  local rect = Viewport.rect
  if not Viewport.active() or not rect then return x, y, w, h end
  local x1, y1 = math.max(x, rect.x), math.max(y, rect.y)
  local x2 = math.min(x + w, rect.x + rect.width)
  local y2 = math.min(y + h, rect.y + rect.height)
  if x2 <= x1 or y2 <= y1 then
    return 0, 0, rect.width, rect.height
  end
  return x1 - rect.x, y1 - rect.y, x2 - x1, y2 - y1
end

function Viewport.finish(game)
  if not Viewport.active() then return end
  local G = love.graphics
  local rect, full = Viewport.rect, Viewport.full
  G.setCanvas()
  G.push("all")
  G.origin()
  G.setScissor()
  G.setShader()
  G.setBlendMode("alpha")
  G.clear(0, 0, 0, 1)
  local context = {
    canvas = Viewport.canvas,
    x = rect.x, y = rect.y, width = rect.width, height = rect.height,
    windowWidth = full.width, windowHeight = full.height,
    dpiX = full.dpiX, dpiY = full.dpiY,
    generation = Viewport.generation,
  }
  Runtime.call("render.window", function(_, ctx)
    G.setColor(1, 1, 1, 1)
    G.draw(ctx.canvas, ctx.x, ctx.y)
  end, game, context)
  G.pop()
end

function Viewport.reset()
  Viewport.frameActive = false
  Viewport.rect = nil
  Viewport.full = nil
  Viewport.generation = nil
  if Viewport.canvas and Viewport.canvas.release then
    Viewport.canvas:release()
  end
  Viewport.canvas = nil
end

return Viewport

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end, warn = function() end, error = function() end,
}

love.filesystem.write = function() return true end
love.graphics.getRendererInfo = function() return "OpenGL", "4.1 stub", "stub", "stub" end
love.graphics.getSupported = function() return { glsl3 = true } end
love.graphics.flushBatch = function() end
love.graphics.validateShader = function() return true end
love.timer = love.timer or {}
love.timer.getDelta = love.timer.getDelta or function() return 1 / 60 end

local sends = {}
love.graphics.newShader = function(frag, vert)
  local sh = { frag = frag, vert = vert }
  function sh.send(self, name, value) sends[#sends + 1] = { shader = self, name = name, value = value } end
  return sh
end

local quads, draws, scissors = {}, {}, {}
love.graphics.newQuad = function(x, y, w, h, sw, sh)
  local q = { x = x, y = y, w = w, h = h, sw = sw, sh = sh }
  quads[#quads + 1] = q
  return q
end
love.graphics.draw = function(img, a, b, c, d, e, f)
  if type(a) == "table" then
    draws[#draws + 1] = { img = img, quad = a, x = b, y = c, sx = e, sy = f }
  else
    draws[#draws + 1] = { img = img, x = a, y = b, sx = d, sy = e }
  end
end
love.graphics.setScissor = function(x, y, w, h)
  scissors[#scissors + 1] = x and { x, y, w, h } or false
end

local ShaderFX = require("src.render.ShaderFX")

local function entry(name)
  return { name = name .. ".slangp", fullPath = "tests/data/shaderfx/gl/" .. name .. ".slangp", converted = true }
end

local function windowCanvas(w, h)
  return setmetatable({ w = w, h = h }, { __index = {
    getWidth = function(self) return self.w end,
    getHeight = function(self) return self.h end,
    getPixelWidth = function(self) return self.w end,
    getPixelHeight = function(self) return self.h end,
  } })
end

local ok = ShaderFX.activate("main", entry("lcd3x"))
eq(ok, true, "lcd3x activates under the stub")

local realRunChain = ShaderFX.runChain
local captured
ShaderFX.runChain = function(state, img, luts, viewport, original, layer)
  local out = realRunChain(state, img, luts, viewport, original, layer)
  captured = { viewport = viewport, original = original, out = out, img = img }
  return out
end

local function render(W, H, s, originX, originY, dpi, opts)
  quads, draws, scissors, sends, captured = {}, {}, {}, {}, nil
  dpi = dpi or 1
  opts = opts or {}
  opts.originX, opts.originY = originX, originY
  local canvas = windowCanvas(W, H)
  ShaderFX.render(canvas, { x = 0, y = 0, w = W, h = H, scale = s },
    { w = W / s, h = H / s }, dpi, dpi, opts)
  return canvas
end

local function findDraw(img)
  for _, d in ipairs(draws) do
    if d.img == img then return d end
  end
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

local cases = {
  { label = "FIT", W = 1024, H = 768, s = 5, ox = 112, oy = 24 },
  { label = "OUT1", W = 1024, H = 768, s = 4, ox = 2, oy = 1 },
  { label = "OUT2", W = 1024, H = 768, s = 3, ox = 0, oy = 0 },
  { label = "OUT2 camera phase", W = 1024, H = 768, s = 3, ox = -7, oy = 5 },
  { label = "FIT 1280x720", W = 1280, H = 720, s = 5, ox = 240, oy = 0 },
}

for _, c in ipairs(cases) do
  local canvas = render(c.W, c.H, c.s, c.ox, c.oy)
  check(captured ~= nil, c.label .. ": the chain ran")
  if captured then
    local vp, orig = captured.viewport, captured.original
    eq(vp.w, orig.w * c.s, c.label .. ": viewport width is exactly scale x source width")
    eq(vp.h, orig.h * c.s, c.label .. ": viewport height is exactly scale x source height")

    local q = quads[1]
    check(q ~= nil, c.label .. ": the crop uses a quad")
    local x0, y0 = math.floor(q.x), math.floor(q.y)
    eq((c.ox - x0) % c.s, 0, c.label .. ": crop starts on a GB pixel column edge")
    eq((c.oy - y0) % c.s, 0, c.label .. ": crop starts on a GB pixel row edge")
    check(x0 <= 0 and x0 > -c.s and y0 <= 0 and y0 > -c.s,
      c.label .. ": crop starts within one GB pixel above/left of the window")
    eq(q.w, orig.w * c.s, c.label .. ": crop quad spans whole GB pixel columns")
    eq(q.h, orig.h * c.s, c.label .. ": crop quad spans whole GB pixel rows")
    check(x0 + q.w >= c.W and y0 + q.h >= c.H, c.label .. ": crop covers the whole window")
    check(q.x - x0 > 0 and q.x - x0 < 0.5 and q.y - y0 > 0 and q.y - y0 < 0.5,
      c.label .. ": crop samples inside a physical pixel, never on its edge")

    local cropDraw = findDraw(canvas)
    check(cropDraw and near(cropDraw.sx, 1 / c.s), c.label .. ": crop draws at exactly 1/scale")

    local passDraw = findDraw(captured.img)
    check(passDraw and near(passDraw.sx, c.s) and near(passDraw.sy, c.s),
      c.label .. ": the viewport pass stretches the source by the integer scale")
    check(passDraw and passDraw.x >= 1 / 16 and passDraw.x < 0.5 and passDraw.y >= 1 / 16 and passDraw.y < 0.5,
      c.label .. ": the integer viewport pass bias is at least a rasterizer subpixel and under half a pixel")
    if passDraw then
      for j = 0, c.s * 4 do
        eq(math.floor((j + 0.5 - passDraw.y) / c.s), math.floor((j + 0.5) / c.s),
          c.label .. ": the bias never changes which texel output row " .. j .. " samples")
      end
    end

    local final = findDraw(captured.out)
    check(final ~= nil, c.label .. ": chain output reaches the screen")
    if final then
      eq(final.x, x0, c.label .. ": chain output lands where the crop was taken (x)")
      eq(final.y, y0, c.label .. ": chain output lands where the crop was taken (y)")
      local cw, ch = captured.out:getWidth(), captured.out:getHeight()
      check(near(final.sx * cw, orig.w * c.s) and near(final.sy * ch, orig.h * c.s),
        c.label .. ": chain output is exactly scale physical px per GB pixel")
    end
    local sc = scissors[#scissors - 1]
    check(type(sc) == "table" and sc[1] == 0 and sc[2] == 0 and sc[3] == c.W and sc[4] == c.H,
      c.label .. ": the overhanging output is clipped to the window")
  end
end

do
  local canvas = render(1024, 768, 3, 1, 2, 1, { layer = "ui", mask = true })
  local maskRect
  for _, s in ipairs(sends) do
    if s.name == "maskRect" then maskRect = s.value end
  end
  check(maskRect ~= nil, "masked UI layer sends the mask rect")
  if maskRect and captured then
    local x0, y0 = -2, -1
    check(near(maskRect[1], x0 / 1024) and near(maskRect[2], y0 / 768),
      "mask rect starts at the crop origin")
    check(near(maskRect[3], captured.original.w * 3 / 1024) and near(maskRect[4], captured.original.h * 3 / 768),
      "mask rect spans the drawn chain output")
  end
  check(canvas ~= nil, "masked render ran")
end

do
  render(2048, 1536, 6, 224, 48, 2)
  local q = quads[1]
  local final = captured and findDraw(captured.out)
  check(q and final, "HiDPI render ran")
  if q and final then
    local x0 = math.floor(q.x)
    eq((224 - x0) % 6, 0, "HiDPI: crop aligned to the physical UI origin")
    eq(final.x, x0 / 2, "HiDPI: chain output placed in logical units")
    eq(captured.viewport.w, captured.original.w * 6, "HiDPI: viewport is exactly scale x source")
  end
end

do
  render(1024, 768, 4.8, 12, 0)
  local q = quads[1]
  check(q and q.x == 0 and q.y == 0 and q.w == 1024 and q.h == 768,
    "fractional scale keeps the whole-window crop")
  eq(captured.viewport.w, 1024, "fractional scale keeps the window viewport width")
  eq(captured.viewport.h, 768, "fractional scale keeps the window viewport height")
  eq(captured.original.w, math.floor(1024 / 4.8 + 0.5), "fractional scale keeps the rounded source width")
  local passDraw = findDraw(captured.img)
  check(passDraw and passDraw.x == 0 and passDraw.y == 0,
    "a non-integer viewport stretch draws unbiased")
  local final = findDraw(captured.out)
  check(final and final.x == 0 and final.y == 0
    and near(final.sx * captured.out:getWidth(), 1024),
    "fractional scale draws the chain output over the window as before")
  for _, sc in ipairs(scissors) do
    check(sc == false, "fractional scale adds no scissor")
  end
end

ShaderFX.runChain = realRunChain
ShaderFX.deactivate("main")

do
  draws = {}
  local canvas = windowCanvas(1024, 768)
  ShaderFX.render(canvas, { x = 0, y = 0, w = 1024, h = 768, scale = 3 },
    { w = 1024 / 3, h = 256 }, 1, 1, { originX = 1, originY = 1 })
  eq(#draws, 1, "shader off: one draw")
  check(draws[1] and draws[1].img == canvas and draws[1].x == 0 and draws[1].y == 0 and draws[1].sx == nil,
    "shader off: the canvas is drawn untouched at the origin")
end

do
  local Game2 = require("src.core.Game2")
  local Chrome = require("src.ui.gen2.Chrome")
  local function game(zoom, fit, cam)
    return setmetatable({
      world = {
        map = {}, camera = cam or { x = 9, y = 27 },
        zoomScale = function() return zoom end,
        fitScale = function() return fit end,
      },
    }, { __index = Game2 })
  end
  eq(Chrome.fitScale(1024, 768), 5, "1024x768 fits at 5")
  local ox, oy = Chrome.fitOrigin(1024, 768, 5)
  eq(ox, 112, "1024x768 fit origin x")
  eq(oy, 24, "1024x768 fit origin y")
  local wx, wy = game(5, 5):fxWorldOrigin(1024, 768, 5)
  eq(wx, -45, "world grid origin follows the camera x")
  eq(wy, -135, "world grid origin follows the camera y")
  eq(game(5, 5):fxSplitsUi(1024, 768), true,
    "Gen 2 at FIT splits the UI layer when the menu grid phase differs from the world camera grid")
  eq(game(5, 5, { x = 0, y = 0 }):fxSplitsUi(1024, 768), true,
    "1024x768 never aligns at FIT: the fit origin is off the camera grid by 2,4 for every integer camera")
  eq(game(5, 5, { x = 4, y = 11 }):fxSplitsUi(1280, 720), false,
    "1280x720 (origin 240,0) shares phase with the camera grid, no split at FIT")
  eq(game(3, 5):fxSplitsUi(1280, 720), true, "a zoomed world always splits the UI layer")
  eq(setmetatable({ world = { map = nil } }, { __index = Game2 }):fxSplitsUi(1024, 768), false,
    "no map, no split")
  eq(setmetatable({}, { __index = Game2 }):fxSplitsUi(1024, 768), false, "no world, no split")
end

T.finish("shaderfx_grid_alignment_2235")

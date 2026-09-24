-- PIXEL FILTER: built-in upscalers for the final frame (OFF, XBRZ, ...).
--
-- Runs where SHADER FX runs (Renderer:endFrame for Gen 1 / Gen 3, Game2's
-- present for Gen 2) and with the same render() signature, so both call sites
-- dispatch to one or the other.  A SHADER FX preset wins when both are set:
-- a slang chain expects the raw 1x grid as its Source, and handing it an
-- already-smoothed image would just smear its mask/scanline math.
--
-- The composite is window-sized and nearest-upscaled, so the first step
-- reads it back down to one texel per GB pixel -- the same crop ShaderFX
-- does, but grid-exact for fractional scales too (BATTLE SIZE "fill"),
-- since these filters need the true source pixels rather than a resample of
-- them.  The filter then scales that grid straight to the output size
-- ("freescale"), so any window size works without a 2x/3x/4x ladder.
--
-- ------- adding a filter
--
-- A filter is a module under src/render/pixel_filters/ listed in FILTERS
-- below, returning
--
--   { id = "name", label = "NAME", passes = { ... },
--     tiers = { high = true } }   -- optional: PERFORMANCE tiers it runs on
--
-- `passes` runs in order.  Every pass's main texture (`tex` in effect()) is
-- the source grid, one texel per GB pixel, premultiplied RGBA.
--   { scope = "source", name = "info", source = GLSL }
--     runs once per source pixel into an rgba8 canvas the size of the grid,
--     written raw (no blending), which every later pass reads as
--     `extern Image info;`.  Any number of these, or none.
--   { scope = "output", source = GLSL }
--     last, exactly one: runs once per output pixel, drawn over the frame
--     with premultiplied alpha.
-- Uniforms, sent to any pass that declares them:
--   extern vec2 srcSize;    -- the grid in source pixels
--   extern float outScale;  -- output pixels per source pixel

local Logger = require("src.core.Logger")
local PixelCanvas = require("src.render.PixelCanvas")

local PixelFilter = {}

local FILTERS = {
  require("src.render.pixel_filters.xbrz"),
}

local byId = {}
PixelFilter.MODES = { "off" }
local LABELS = { off = "OFF" }
for _, def in ipairs(FILTERS) do
  byId[def.id] = def
  PixelFilter.MODES[#PixelFilter.MODES + 1] = def.id
  LABELS[def.id] = def.label
end

-- Set from applyOptions on every generation, like Letterbox.mode, so a draw
-- call needs no options table in hand.
PixelFilter.mode = "off"

function PixelFilter.normalize(mode)
  if mode ~= nil and (mode == "off" or byId[mode]) then return mode end
  return "off"
end

function PixelFilter.label(mode)
  return LABELS[PixelFilter.normalize(mode)]
end

function PixelFilter.cycle(mode, dir)
  local at = 1
  for i, id in ipairs(PixelFilter.MODES) do
    if id == PixelFilter.normalize(mode) then at = i break end
  end
  local n = #PixelFilter.MODES
  return PixelFilter.MODES[(at - 1 + (dir or 1)) % n + 1]
end

function PixelFilter.setMode(mode)
  PixelFilter.mode = PixelFilter.normalize(mode)
  return PixelFilter.mode
end

function PixelFilter.applyOptions(options)
  return PixelFilter.setMode(options and options.pixelFilter)
end

-- ------- shaders

-- Per filter id: nil = not built yet, false = the driver refused a pass
-- (logged once, and the filter then reports inactive so the frame falls back
-- to the plain blit), else one Shader per pass, in pass order.
local built = {}

local function getShaders(def)
  local shaders = built[def.id]
  if shaders == nil then
    shaders = false
    if love and love.graphics and love.graphics.newShader then
      shaders = {}
      for i, pass in ipairs(def.passes) do
        local ok, result = pcall(love.graphics.newShader, pass.source)
        if not (ok and result) then
          Logger.error("PIXEL FILTER: %s shader failed to compile: %s",
            def.id, tostring(result))
          shaders = false
          break
        end
        shaders[i] = result
      end
    end
    built[def.id] = shaders
  end
  return shaders or nil
end

local Performance = nil

-- Whether the final present should run through the chosen filter this
-- frame.  The PERFORMANCE tier's `pixelFilter` cap turns it off on the low
-- tier without rewriting the player's choice, the way TILT and SHADER FX
-- clamp; a filter's own `tiers` can narrow that further.
function PixelFilter.active()
  local def = byId[PixelFilter.mode]
  if not def then return false end
  Performance = Performance or require("src.core.Performance")
  local caps = Performance.CAPS[Performance.tier]
  if caps and caps.pixelFilter == false then return false end
  if def.tiers and not def.tiers[Performance.tier] then return false end
  return getShaders(def) ~= nil
end

-- ------- present

-- Per layer ("main", "ui"): the crop canvas, one canvas per source pass and
-- the crop quad, reallocated only on a real size change or filter switch, so
-- a steady frame allocates nothing.
local layerCache = {}
-- reused for every srcSize send
local sizeBuf = { 0, 0 }

-- The run of whole source pixels covering [lo, lo + len) on an axis whose
-- pixel 0 starts at `origin`, `s` physical pixels apiece.  Returns the first
-- pixel's physical start and the pixel count.
local function gridSpan(lo, len, origin, s)
  local first = math.floor((lo - origin) / s + 1e-6)
  local last = math.ceil((lo + len - origin) / s - 1e-6)
  return origin + first * s, math.max(1, last - first)
end
PixelFilter._gridSpan = gridSpan

local function layerSlot(layer, def, cols, rows)
  local slot = layerCache[layer]
  if not slot or slot.cols ~= cols or slot.rows ~= rows or slot.def ~= def then
    slot = {
      def = def, cols = cols, rows = rows, targets = {},
      src = PixelCanvas.new(cols, rows, "nearest"),
      quad = love.graphics.newQuad(0, 0, 1, 1, 1, 1),
    }
    for i, pass in ipairs(def.passes) do
      if pass.scope == "source" then
        -- explicit rgba8: packed data must round-trip exactly, which an sRGB
        -- canvas (LOVE's default under gamma-correct rendering) would not
        local target = love.graphics.newCanvas(cols, rows, { dpiscale = 1, format = "rgba8" })
        target:setFilter("nearest", "nearest")
        slot.targets[i] = target
      end
    end
    layerCache[layer] = slot
  end
  return slot
end

-- Send the uniforms `shader` declares: the sizes, and every earlier source
-- pass's canvas by its name.
local function sendInputs(shader, def, slot, upto, s)
  if shader:hasUniform("srcSize") then shader:send("srcSize", sizeBuf) end
  if s and shader:hasUniform("outScale") then shader:send("outScale", s) end
  for i = 1, upto - 1 do
    local name = def.passes[i].name
    if slot.targets[i] and name and shader:hasUniform(name) then
      shader:send(name, slot.targets[i])
    end
  end
end

-- Read `canvas` back down to one texel per source pixel -- each output texel
-- samples the physical pixel at the centre of its block, which lands inside
-- the block for any scale >= 1, integer or not -- then run the filter's
-- source passes over that grid.
local function prepare(canvas, layer, def, shaders, gx, gy, cols, rows, s)
  local slot = layerSlot(layer, def, cols, rows)
  local minF, magF = canvas:getFilter()
  canvas:setFilter("nearest", "nearest")
  slot.quad:setViewport(gx, gy, cols * s, rows * s,
    canvas:getPixelWidth(), canvas:getPixelHeight())
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas(slot.src)
  love.graphics.setShader()
  love.graphics.draw(canvas, slot.quad, 0, 0, 0, 1 / s, 1 / s)
  -- "replace" alone still multiplies RGB by alpha on write, which would
  -- scramble data a pass packs into all four channels
  love.graphics.setBlendMode("replace", "premultiplied")
  sizeBuf[1], sizeBuf[2] = cols, rows
  for i, pass in ipairs(def.passes) do
    if pass.scope == "source" then
      love.graphics.setCanvas(slot.targets[i])
      love.graphics.setShader(shaders[i])
      sendInputs(shaders[i], def, slot, i)
      love.graphics.draw(slot.src, 0, 0)
    end
  end
  love.graphics.pop()
  canvas:setFilter(minF, magF)
  return slot
end

-- Same contract as ShaderFX.render: `canvas` is the finished window-size
-- composite, `rect` the area to shade in PHYSICAL pixels with `rect.scale`
-- physical pixels per source pixel, and opts.originX/originY the physical
-- position of a source pixel's top-left corner, which pins the grid.
-- `opts.mask` composites a transparent layer (the UI a zoomed world split
-- off) over what is already on screen instead of replacing it.
function PixelFilter.render(canvas, rect, source, dpiX, dpiY, opts)
  local def = byId[PixelFilter.mode]
  local shaders = def and getShaders(def)
  local masked = opts and opts.mask
  local s = tonumber(rect.scale)
  dpiX, dpiY = tonumber(dpiX) or 1, tonumber(dpiY) or 1
  if not shaders or not s or s < 1 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
    return
  end
  local originX = tonumber(opts and opts.originX) or rect.x
  local originY = tonumber(opts and opts.originY) or rect.y
  local gx, cols = gridSpan(rect.x, rect.w, originX, s)
  local gy, rows = gridSpan(rect.y, rect.h, originY, s)

  local clipX = love.graphics.getScissor()
  love.graphics.flushBatch()
  local ok, slot = pcall(prepare, canvas, (opts and opts.layer) or "main",
    def, shaders, gx, gy, cols, rows, s)

  love.graphics.setColor(1, 1, 1, 1)
  if not masked then
    -- what the grid does not cover (a cutout's surround) still shows
    love.graphics.setBlendMode("replace")
    love.graphics.draw(canvas, 0, 0)
  end
  if not ok then
    Logger.error("PIXEL FILTER: crop failed: %s", tostring(slot))
    if masked then
      love.graphics.setBlendMode("alpha")
      love.graphics.draw(canvas, 0, 0)
    end
    love.graphics.setBlendMode("alpha")
    return
  end

  -- the grid overhangs the rect by up to a source pixel on each side
  if not clipX then
    love.graphics.setScissor(math.floor(rect.x / dpiX), math.floor(rect.y / dpiY),
      math.ceil(rect.w / dpiX), math.ceil(rect.h / dpiY))
  end
  local last = #def.passes
  local shader = shaders[last]
  love.graphics.setShader(shader)
  sendInputs(shader, def, slot, last, s)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.draw(slot.src, gx / dpiX, gy / dpiY, 0, s / dpiX, s / dpiY)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  if not clipX then love.graphics.setScissor() end
end

return PixelFilter

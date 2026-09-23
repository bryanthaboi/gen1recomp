local Extract = require("src.import.gba.extract_island1")

local HofGfx = {}

local W, H = 240, 160
local images = {}

local function image(name, w, h)
  if images[name] then return images[name] end
  if not (love and love.image and love.graphics and love.graphics.newImage) then return nil end
  local rel = (Extract.CACHE_ROOT or "data/generated/gba") .. "/hall_of_fame/" .. name .. ".rgba"
  local bytes = require("src.core.game3.dataset").cache():read(rel)
  assert(bytes and #bytes == w * h * 4, "hall of fame art missing from the cache: " .. rel)
  local img = love.graphics.newImage(love.image.newImageData(w, h, "rgba8", bytes))
  img:setFilter("nearest", "nearest")
  local entry = { image = img, w = w, h = h }
  images[name] = entry
  return entry
end

-- pokefirered/src/hall_of_fame.c:1181
function HofGfx.drawStripes()
  local stripes = image("stripes", W, H)
  if not stripes then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(stripes.image, 0, 0)
end

-- pokefirered/src/hall_of_fame.c:333, :611
function HofGfx.drawBands(eva, evb)
  local entry = image("bands", W, H)
  if not entry then return end
  local bands = entry.image
  local mode, alphaMode = love.graphics.getBlendMode()
  love.graphics.setColor(0, 0, 0, 1 - math.min(16, evb) / 16)
  love.graphics.draw(bands, 0, 0)
  if eva > 0 then
    local k = math.min(16, eva) / 16
    love.graphics.setBlendMode("add")
    love.graphics.setColor(k, k, k, 1)
    love.graphics.draw(bands, 0, 0)
  end
  love.graphics.setBlendMode(mode, alphaMode)
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/hall_of_fame.c:142, :169
function HofGfx.confetti()
  local entry = image("confetti", 8, 8 * 17)
  if entry and not entry.quads then
    entry.quads = {}
    for f = 0, 16 do
      entry.quads[f] = love.graphics.newQuad(0, f * 8, 8, 8, entry.w, entry.h)
    end
  end
  return entry
end

function HofGfx.reset()
  images = {}
end

return HofGfx

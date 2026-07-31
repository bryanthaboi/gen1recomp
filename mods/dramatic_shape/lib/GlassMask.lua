-- Voxel world mode: the glass in the windows, found rather than listed.
--
-- Buildings and doors in the overworld art carry small panes -- six texels
-- wide, framed in black, with a diagonal shine drawn in. This module finds
-- them by SHAPE in the tileset image itself: a border row of six black
-- texels, four or five rows of black-flanked non-black glass under it, and
-- a closing border row. No tile ids are hardcoded, so a total conversion
-- that draws its own windows in the same idiom gets glass for free, and art
-- with no windows gets an empty mask and costs nothing.
--
-- The scan slides at PIXEL granularity because the art does: the building
-- window sits a row down inside its tile, and the door's pane straddles a
-- 2x2 tile block entirely -- a per-tile matcher finds neither.
--
-- What the scan yields is a MASK TEXTURE the same size as the tileset
-- atlas: opaque white on glass texels, transparent everywhere else. Terrain
-- meshes sample the atlas by normalized coordinates (ChunkMesher.uvRect),
-- so the scene shader can sample this mask with the SAME coordinates and
-- know, per fragment, whether it is drawing glass -- on any wall, at any
-- angle, in free-roam or a staged battle, with no geometry work anywhere.
-- The recoloured atlases (display modes, RED++) keep the tileset's layout,
-- so the alignment holds under every palette.
--
-- What the shader does with the answer (Voxel3D): by day a thin glint
-- sweeps across the panes -- a pseudo reflection, view-anchored, preserving
-- the art under it -- and after dark the panes are LIT: the texel's own
-- shine pattern, warmed and brightened, exempt from the sun, the shadow
-- map and the hour's tint, as a window with a lamp behind it is.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")

local GlassMask = {}

-- pane geometry the scan accepts: six glass texels across, and this many
-- rows of them between the two border rows
GlassMask.GLASS_W = 6
GlassMask.ROWS = { 4, 5 }        -- door pane, building pane

-- Whether a channel triple is the border black. The raw tileset art is the
-- four DMG greys, so black is genuinely zero; the threshold forgives a
-- rescaled asset without accepting the dark grey rung (85/255 = 0.33).
local function isBlack(r, g, b)
  return r < 0.12 and g < 0.12 and b < 0.12
end

GlassMask._isBlack = isBlack     -- named for the suite

-- Find every pane in an image, through a pure reader so the geometry is
-- testable headless: `getPixel(x, y)` returns r, g, b in 0..1 for 0-based
-- coordinates. Returns { {x=, y=, w=, h=}, ... } rects of GLASS texels
-- (the border is the detector's evidence, not part of the answer).
function GlassMask.scan(getPixel, w, h)
  local function black(x, y)
    return isBlack(getPixel(x, y))
  end
  local function borderRow(x, y)
    for c = 1, 6 do
      if not black(x + c, y) then return false end
    end
    return true
  end
  local function glassRow(x, y)
    if not (black(x, y) and black(x + 7, y)) then return false end
    for c = 1, 6 do
      if black(x + c, y) then return false end
    end
    return true
  end
  local want = {}
  for _, n in ipairs(GlassMask.ROWS) do want[n] = true end

  local rects = {}
  for y = 0, h - 1 do
    for x = 0, w - 8 do
      if borderRow(x, y) then
        local n = 0
        while y + 1 + n < h and glassRow(x, y + 1 + n) do
          n = n + 1
        end
        if want[n] and y + 1 + n < h and borderRow(x, y + 1 + n) then
          rects[#rects + 1] = { x = x + 1, y = y + 1,
                                w = GlassMask.GLASS_W, h = n }
        end
      end
    end
  end
  return rects
end

-- ------- the runtime cache, one entry per tileset image

local cache = {}       -- image path -> { rects, texture (or false) }

local function entry(tileset)
  local path = tileset and tileset.image
  if not path then return nil end
  local hit = cache[path]
  if hit then return hit end
  local ok, data = pcall(Assets.imageData, path)
  if not (ok and data) then
    -- unreadable art is a verdict for the session, not a retry loop
    cache[path] = { rects = {}, texture = false }
    return cache[path]
  end
  local w, h = data:getDimensions()
  local rects = GlassMask.scan(function(x, y)
    return data:getPixel(x, y)
  end, w, h)
  local texture = false
  if #rects > 0 and love.image and love.image.newImageData
     and love.graphics and love.graphics.newImage then
    local built = pcall(function()
      local mask = love.image.newImageData(w, h)
      for _, r in ipairs(rects) do
        for yy = r.y, r.y + r.h - 1 do
          for xx = r.x, r.x + r.w - 1 do
            mask:setPixel(xx, yy, 1, 1, 1, 1)
          end
        end
      end
      texture = love.graphics.newImage(mask)
      texture:setFilter("nearest", "nearest")
    end)
    if not built then texture = false end
  end
  cache[path] = { rects = rects, texture = texture }
  return cache[path]
end

-- The panes found in a tileset's art, as glass rects in atlas pixels.
function GlassMask.rects(tileset)
  local e = entry(tileset)
  return e and e.rects or {}
end

-- The mask texture for a tileset, or nil when it has no panes (or the art
-- is unreadable, or there is no GPU) -- callers bind the blank instead.
function GlassMask.texture(tileset)
  local e = entry(tileset)
  return (e and e.texture) or nil
end

-- A 1x1 transparent stand-in, for the frames (and drivers) with no mask:
-- the scene shader always declares the sampler, and an unbound sampler is
-- a driver-dependent crash rather than a fallback.
local blank = nil

function GlassMask.blank()
  if blank == nil then
    local ok, img = pcall(function()
      local data = love.image.newImageData(1, 1)
      data:setPixel(0, 0, 0, 0, 0, 0)
      return love.graphics.newImage(data)
    end)
    blank = (ok and img) or false
  end
  return blank or nil
end

-- Drop the GPU objects (window resize, hot reload). The rects survive --
-- they are a fact about the art -- but textures are rebuilt on demand.
function GlassMask.invalidate()
  for _, e in pairs(cache) do
    if e.texture and e.texture.release then pcall(e.texture.release, e.texture) end
    e.texture = false
  end
  cache = {}
  blank = nil
end

return GlassMask

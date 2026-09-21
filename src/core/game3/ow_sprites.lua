-- Runtime FRLG overworld sprites (extracted 4bpp → RGBA sheets).

local Extract = require("src.import.gba.extract_island1")
local OwExtract = require("src.import.gba.ow_extract")
local Versions = require("src.import.gba.versions")

local OwSprites = {}

OwSprites._cache = nil
OwSprites._manifest = nil
OwSprites._loaded = {} -- [graphicsId] = { image, quads, w, h, frameCount, inanimate }
OwSprites._logged = false

-- pret ANIM_STD: stand S/N/W; walk uses frames 3-8; east = west + hflip
local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK_A = { down = 3, up = 5, left = 7, right = 7 }
local WALK_B = { down = 4, up = 6, left = 8, right = 8 }

local function owRoot()
  -- Must follow Dataset.mountExtractRoots() — do not bake CACHE_ROOT at require.
  return (Extract.CACHE_ROOT or "data/generated/gba") .. "/ow"
end

function OwSprites.install(cache)
  OwSprites._cache = cache
  OwSprites._loaded = {}
  OwSprites._manifest = nil
  OwSprites._logged = false
  if not cache then return end
  local src = cache:read(owRoot() .. "/manifest.lua")
  if src then
    local chunk = load(src, "@ow/manifest.lua", "t", {})
    if chunk then OwSprites._manifest = chunk() end
  end
end

function OwSprites.invalidate()
  OwSprites._loaded = {}
  OwSprites._manifest = nil
  OwSprites._logged = false
end

function OwSprites.ready()
  if not Versions.OW_RENDER then return false end
  if OwSprites._manifest then return true end
  local cache = OwSprites._cache
  return OwExtract.ready(cache, Extract.CACHE_ROOT or "data/generated/gba")
end

local function load_one(gid)
  local cache = OwSprites._cache
  if not cache then return nil end
  local root = owRoot()
  local metaBlob = cache:read(root .. "/" .. gid .. ".meta")
  local rgba = cache:read(root .. "/" .. gid .. ".rgba")
  if not metaBlob or not rgba then return nil end
  local meta = OwExtract.decodeMeta(metaBlob)
  if not meta then return nil end
  local w, h, n = meta.width, meta.height, meta.frameCount
  local aw, ah = w, h * n
  if #rgba ~= aw * ah * 4 then
    if #rgba < aw * h * 4 then return nil end
  end
  if not (love and love.image and love.graphics) then return nil end

  local ok, imageData = pcall(love.image.newImageData, aw, ah, "rgba8", rgba)
  if not ok or not imageData then
    imageData = love.image.newImageData(aw, ah)
    local i = 1
    for y = 0, ah - 1 do
      for x = 0, aw - 1 do
        local r = (rgba:byte(i) or 0) / 255
        local g = (rgba:byte(i + 1) or 0) / 255
        local b = (rgba:byte(i + 2) or 0) / 255
        local a = (rgba:byte(i + 3) or 0) / 255
        imageData:setPixel(x, y, r, g, b, a)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  local quads = {}
  for fi = 0, n - 1 do
    quads[fi] = love.graphics.newQuad(0, fi * h, w, h, aw, ah)
  end
  return {
    image = image,
    -- Kept so setObjectPalette can recolour the sheet: LOVE 11 has no
    -- Image:newImageData, so the decoded pixels are the only CPU-side source.
    imageData = imageData,
    quads = quads,
    width = w,
    height = h,
    frameCount = n,
    inanimate = meta.inanimate,
  }
end

function OwSprites.get(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return nil end
  local cached = OwSprites._loaded[graphicsId]
  if cached then return cached end
  if not OwSprites._manifest then
    OwSprites.install(OwSprites._cache)
  end
  local spr = load_one(graphicsId)
  if spr then
    OwSprites._loaded[graphicsId] = spr
    if not OwSprites._logged then
      local n = OwSprites._manifest and OwSprites._manifest.count
      print(string.format("[game3/ow] FRLG sprites ready (%s sheets)",
        tostring(n or "?")))
      OwSprites._logged = true
    end
  end
  return spr
end

local FIELD_MOVE_POSE = { down = 3, up = 7, left = 4, right = 4 }

-- ------------------------------------------------ runtime palette substitution
-- pret recolours field objects by loading a new palette into their OBJ palette
-- slot (LoadPalette + ApplyGlobalFieldPaletteTint). The engine bakes palettes to
-- RGBA at extract time, so an alternate palette is reproduced by substituting the
-- sprite's opaque colours. Used by the Birth Island Deoxys rock.

OwSprites._overrides = {} -- [graphicsId] = { key = string, spr = sprite }

local function to8(v)
  v = math.floor((tonumber(v) or 0) * 255 + 0.5)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

-- How far (per channel) a baked sprite colour may sit from the palette entry it
-- is meant to match before the swap gives up.  The rock ramp's entries are
-- always tens of units apart, so this can never select the wrong colour.
local NEAREST_TOL = 4

--- Build a copy of `spr` with the colours in `from` replaced by `to`.
--- Returns nil when image data is unavailable (e.g. headless tests) or when not
--- a single pixel matched (a silent no-op swap is always a bug).
local function recolour_sprite(spr, from, to)
  if not (love and love.image and love.image.newImageData
    and love.graphics and love.graphics.newImage) then
    return nil
  end
  if not (spr and spr.image) then return nil end
  -- LOVE 11 exposes no Image:newImageData, so recolour from the ImageData the
  -- sheet was decoded from.  Clone it: mapPixel mutates in place and the cached
  -- sprite has to keep its own colours for the next swap.
  local data
  if spr.imageData then
    local okClone, copy = pcall(function() return spr.imageData:clone() end)
    if okClone then data = copy end
  end
  if not data then
    local okData, d = pcall(function() return spr.image:newImageData() end)
    if okData then data = d end
  end
  if not data then return nil end

  -- Colour-keyed LUT so the per-pixel work stays a single table lookup.
  local lut, sources = {}, {}
  for i = 1, #from do
    local a, b = from[i], to[i]
    if a and b then
      lut[(a[1] * 65536) + (a[2] * 256) + a[3]] = b
      sources[#sources + 1] = { a[1], a[2], a[3], b }
    end
  end
  if not next(lut) then return nil end

  -- Sprites are baked from 5-bit GBA channels, so a stored colour can sit a
  -- unit or two away from the palette it was authored with.  Fall back to the
  -- nearest source within NEAREST_TOL: the palette entries we swap between are
  -- tens of units apart, so this cannot pick the wrong one.
  local replaced = 0
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, g, b, a)
      if a <= 0 then return r, g, b, a end
      local r8, g8, b8 = to8(r), to8(g), to8(b)
      local c = lut[(r8 * 65536) + (g8 * 256) + b8]
      if not c then
        local best, bestD
        for _, e in ipairs(sources) do
          local d = (e[1] - r8) ^ 2 + (e[2] - g8) ^ 2 + (e[3] - b8) ^ 2
          if d <= NEAREST_TOL * NEAREST_TOL * 3 and (bestD == nil or d < bestD) then
            best, bestD = e[4], d
          end
        end
        c = best
      end
      if not c then return r, g, b, a end
      replaced = replaced + 1
      return c[1] / 255, c[2] / 255, c[3] / 255, a
    end)
  end)
  if not okMap then return nil end
  if replaced == 0 then
    print(string.format(
      "[game3/ow] palette swap matched no pixels against %d source colour(s)",
      #sources))
    return nil
  end

  local okImg, img = pcall(love.graphics.newImage, data)
  if not (okImg and img) then return nil end
  if img.setFilter then img:setFilter("nearest", "nearest") end

  local copy = {}
  for k, v in pairs(spr) do copy[k] = v end
  copy.image = img
  copy.imageData = data
  return copy
end

--- Apply an alternate palette to every draw of `graphicsId`.
--- `colours` are the new {r,g,b} values; `sourceColours` the ones they replace
--- (defaults to the first rock palette, which is byte-identical to the
--- meteorite's own palette).
function OwSprites.setObjectPalette(graphicsId, key, colours, sourceColours)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil or type(key) ~= "string" then return false end
  local current = OwSprites._overrides[graphicsId]
  if current and current.key == key then return true end
  if type(colours) ~= "table" or #colours == 0 then return false end

  local base = OwSprites.get(graphicsId)
  if not base then return false end
  local from = sourceColours
  if type(from) ~= "table" or #from ~= #colours then
    local okD, Deoxys = pcall(require, "src.core.game3.deoxys")
    from = (okD and Deoxys and Deoxys.ROCK_PALS and Deoxys.ROCK_PALS[1]) or nil
  end
  local spr = recolour_sprite(base, from, colours)
  if not spr then return false end
  OwSprites._overrides[graphicsId] = { key = key, spr = spr }
  return true
end

function OwSprites.clearObjectPalette(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return false end
  if OwSprites._overrides[graphicsId] == nil then return false end
  OwSprites._overrides[graphicsId] = nil
  return true
end

function OwSprites.objectPaletteKey(graphicsId)
  local o = OwSprites._overrides[tonumber(graphicsId) or -1]
  return o and o.key or nil
end


--- Resolve frame index + hflip for facing / walk.
-- opts: { bow = bool, fieldMove = bool, frame = number }
function OwSprites.pose(spr, facing, walkPhase, stepFlip, opts)
  facing = facing or "down"
  if not spr then return 0, false end

  local flip = (facing == "right")
  if opts and opts.frame ~= nil then
    local f = tonumber(opts.frame) or 0
    if f < 0 then f = 0 end
    if f >= spr.frameCount then f = spr.frameCount - 1 end
    return f, flip
  end

  if spr.frameCount <= 1 or spr.inanimate then
    return 0, false
  end

  if opts and opts.bow and spr.frameCount > 9 then
    return 9, false
  end

  if opts and opts.fieldMove and spr.frameCount >= 9 then
    local f = FIELD_MOVE_POSE[facing] or 3
    if f >= spr.frameCount then f = 0 end
    return f, flip
  end

  if spr.frameCount == 3 then
    -- Surfing mount pose (0 = down, 1 = up, 2 = left, 2 + hflip = right)
    local f = STAND[facing] or 0
    if f >= spr.frameCount then f = 0 end
    return f, flip
  end

  local walking = walkPhase == 1 or walkPhase == true
  local frame
  if walking and spr.frameCount >= 9 then
    frame = (stepFlip and WALK_A[facing] or WALK_B[facing]) or STAND[facing] or 0
  else
    frame = STAND[facing] or 0
  end
  if frame >= spr.frameCount then frame = math.min(STAND[facing] or 0, spr.frameCount - 1) end
  return frame, flip
end

--- The sprite actually drawn for `graphicsId`: the palette override when one is
--- active, otherwise the base sprite.
function OwSprites.getDraw(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return nil end
  local ov = OwSprites._overrides and OwSprites._overrides[graphicsId]
  if ov and ov.spr then return ov.spr end
  return OwSprites.get(graphicsId)
end

--- Draw at world pixel position (cell top-left). Feet at bottom of sprite.
-- opts.bow: use nurse bow frame (ANIM_NURSE_BOW).
-- opts.fieldMove: use directional arm-raise field move frame.
-- opts.frame: explicit frame index override.
function OwSprites.draw(graphicsId, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
  local spr = OwSprites.getDraw(graphicsId)
  if not spr then return false end
  local frame, flip = OwSprites.pose(spr, facing, walkPhase, stepFlip, opts)
  local q = spr.quads[frame]
  if not q then return false end
  local sx = px - camX + (16 - spr.width) / 2
  local sy = py - camY + 16 - spr.height
  love.graphics.setColor(1, 1, 1, 1)
  if flip then
    love.graphics.draw(spr.image, q, sx + spr.width, sy, 0, -1, 1)
  else
    love.graphics.draw(spr.image, q, sx, sy)
  end
  return true
end

function OwSprites.playerGraphicsId(game)
  local P = package.loaded["src.core.game3.player"]
  local save = game and game.save
  local session = game and game.session
  local gender = (session and session.gender)
    or (save and (save.gender or (save.player and save.player.gender)))
  local isFemale = (gender == "female" or gender == "F" or gender == 1)

  if P then
    if P.fieldMoveAnim and P.fieldMoveAnim > 0 then
      return isFemale and (Versions.OW_PLAYER_FEMALE_FIELD_MOVE or 10)
                       or (Versions.OW_PLAYER_MALE_FIELD_MOVE or 3)
    end
    -- If jumping / hop onto/off water, maintain normal or surfing sprite during arc
    if P.surfing and not P.dismounting then
      return isFemale and (Versions.OW_PLAYER_FEMALE_SURF or 9)
                       or (Versions.OW_PLAYER_MALE_SURF or 2)
    end
    if P.biking then
      return isFemale and (Versions.OW_PLAYER_FEMALE_BIKE or 8)
                       or (Versions.OW_PLAYER_MALE_BIKE or 1)
    end
    if P.fishing then
      return isFemale and (Versions.OW_PLAYER_FEMALE_FISH or 11)
                       or (Versions.OW_PLAYER_MALE_FISH or 4)
    end
  end

  if isFemale then
    return Versions.OW_PLAYER_FEMALE or 7
  end
  return Versions.OW_PLAYER_MALE or 0
end

return OwSprites

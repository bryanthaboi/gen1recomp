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

--- Draw at world pixel position (cell top-left). Feet at bottom of sprite.
-- opts.bow: use nurse bow frame (ANIM_NURSE_BOW).
-- opts.fieldMove: use directional arm-raise field move frame.
-- opts.frame: explicit frame index override.
function OwSprites.draw(graphicsId, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
  local spr = OwSprites.get(graphicsId)
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

-- Runtime FRLG overworld sprites (extracted 4bpp → RGBA sheets).

local Extract = require("src.import.gba.extract_island1")
local OwExtract = require("src.import.gba.ow_extract")
local Versions = require("src.import.gba.versions")

local Stream = require("src.core.game3.asset_stream")
local OwSprites = {}
local makeStream
local function resetStream()
  if OwSprites._stream then OwSprites._stream:cancel() end
  OwSprites._stream = OwSprites._cache and makeStream() or nil
end

OwSprites._cache = nil
OwSprites._manifest = nil
OwSprites._loaded = {} -- [graphicsId] = { image, quads, w, h, frameCount, inanimate }
OwSprites._reflectionLoaded = {}
OwSprites._logged = false

-- pret ANIM_STD: stand S/N/W; walk uses frames 3-8; east = west + hflip
local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK_A = { down = 3, up = 5, left = 7, right = 7 }
local WALK_B = { down = 4, up = 6, left = 8, right = 8 }
-- src/data/object_events/object_event_anims.h:601
local RUN_BASE = { down = 9, up = 12, left = 15, right = 15 }
local RUN_A = { down = 10, up = 13, left = 16, right = 16 }
local RUN_B = { down = 11, up = 14, left = 17, right = 17 }

local EMPTY = {}

local function fieldBlock()
  local Profile = package.loaded["src.core.game3.profile"] or require("src.core.game3.profile")
  local ok, row = pcall(Profile.forSession)
  return ok and row and row.field or EMPTY
end

local function owRoot()
  -- Must follow Dataset.mountExtractRoots(): do not bake CACHE_ROOT at require.
  return (Extract.CACHE_ROOT or "data/generated/gba") .. "/ow"
end

local function loadManifest()
  OwSprites._manifestAttempted = true
  local src = OwSprites._cache and OwSprites._cache:read(owRoot() .. "/manifest.lua")
  local chunk = src and load(src, "@ow/manifest.lua", "t", {})
  OwSprites._manifest = chunk and chunk() or nil
end

local function resetPalettes(changed)
  if changed then OwSprites._overrides = {} end
  for _, o in pairs(OwSprites._overrides or {}) do o.spr = nil end
end

function OwSprites.install(cache)
  resetPalettes(OwSprites._cache ~= cache or OwSprites._root ~= owRoot())
  OwSprites._root = owRoot()
  OwSprites._cache = cache
  OwSprites._loaded = {}
  resetStream()
  OwSprites._reflectionLoaded = {}
  OwSprites._manifest = nil
  OwSprites._logged = false
  loadManifest()
end

function OwSprites.invalidate()
  resetPalettes(false)
  OwSprites._manifestAttempted = false
  OwSprites._loaded = {}
  resetStream()
  OwSprites._reflectionLoaded = {}
  OwSprites._manifest = nil
  OwSprites._logged = false
end

function OwSprites.ready()
  if not Versions.OW_RENDER then return false end
  if OwSprites._manifest then return true end
  local cache = OwSprites._cache
  return OwExtract.ready(cache, Extract.CACHE_ROOT or "data/generated/gba")
end

local function uploadSprite(meta)
  local image = love.graphics.newImage(meta.imageData)
  image:setFilter("nearest", "nearest")
  coroutine.yield("texture")
  local w, h, n = meta.width, meta.height, meta.frameCount
  local quads = {}
  for fi = 0, n - 1 do
    quads[fi] = love.graphics.newQuad(0, fi * h, w, h, w, h * n)
    if fi % 32 == 31 then coroutine.yield("quads") end
  end
  meta.image, meta.quads = image, quads
  meta.bytes = nil
  return meta
end
makeStream = function()
  return Stream.new("sprite", OwSprites._cache, owRoot(), uploadSprite, function(gid, spr)
    OwSprites._loaded[gid] = spr
    if not OwSprites._logged then
      print(string.format("[game3/ow] sprites ready (%s sheets)", tostring(OwSprites._manifest and OwSprites._manifest.count or "?")))
      OwSprites._logged = true
    end
  end)
end

function OwSprites.prefetch(gid, priority)
  gid = tonumber(gid)
  if gid and not OwSprites._loaded[gid] and OwSprites._stream then OwSprites._stream:prefetch(gid, priority) end
end

function OwSprites.get(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return nil end
  local cached = OwSprites._loaded[graphicsId]
  if cached then return cached end
  if not OwSprites._manifestAttempted then loadManifest() end
  return OwSprites._stream and OwSprites._stream:get(graphicsId) or nil
end

-- src/data/object_events/object_event_anims.h:633
local FIELD_MOVE_SEQ = { 0, 4, 1, 4, 2, 4, 3, 4, 4, 8 }
-- src/data/object_events/object_event_anims.h:642
local VS_SEEKER_SEQ = { 0, 4, 1, 4, 5, 4, 6, 4 }
for _ = 1, 7 do
  VS_SEEKER_SEQ[#VS_SEEKER_SEQ + 1] = 7; VS_SEEKER_SEQ[#VS_SEEKER_SEQ + 1] = 4
  VS_SEEKER_SEQ[#VS_SEEKER_SEQ + 1] = 8; VS_SEEKER_SEQ[#VS_SEEKER_SEQ + 1] = 4
end
for _, v in ipairs({ 6, 4, 1, 4, 0, 4 }) do VS_SEEKER_SEQ[#VS_SEEKER_SEQ + 1] = v end
-- src/data/object_events/object_event_anims.h:657
local VS_SEEKER_BIKE_SEQ = { 0, 4, 1, 4, 2, 4, 3, 4 }
for _ = 1, 7 do
  VS_SEEKER_BIKE_SEQ[#VS_SEEKER_BIKE_SEQ + 1] = 4; VS_SEEKER_BIKE_SEQ[#VS_SEEKER_BIKE_SEQ + 1] = 4
  VS_SEEKER_BIKE_SEQ[#VS_SEEKER_BIKE_SEQ + 1] = 5; VS_SEEKER_BIKE_SEQ[#VS_SEEKER_BIKE_SEQ + 1] = 4
end
for _, v in ipairs({ 3, 4, 2, 4, 1, 4, 0, 4 }) do VS_SEEKER_BIKE_SEQ[#VS_SEEKER_BIKE_SEQ + 1] = v end

-- src/data/object_events/object_event_anims.h:877
local FISH_BASE = { down = 8, up = 4, left = 0, right = 0 }
local FISH_TAKE_OUT = { 0, 4, 1, 4, 2, 4, 3, 4 }
-- src/data/object_events/object_event_anims.h:909
local FISH_PUT_AWAY_SN = { 3, 4, 2, 6, 1, 6, 0, 6 }
local FISH_PUT_AWAY_WE = { 3, 4, 2, 4, 1, 4, 0, 4 }
-- src/data/object_events/object_event_anims.h:941
local FISH_HOOKED = { 2, 6, 3, 6, 2, 6, 3, 6, 3, 30 }

local function seqFrame(seq, t, loop)
  t = math.max(0, math.floor(tonumber(t) or 0))
  local total = 0
  for i = 2, #seq, 2 do total = total + seq[i] end
  if loop and total > 0 then t = t % total end
  local acc = 0
  for i = 1, #seq, 2 do
    acc = acc + seq[i + 1]
    if t < acc then return seq[i], false end
  end
  return seq[#seq - 1], true
end

function OwSprites.fieldMoveFrame(elapsed, kind)
  local seq = FIELD_MOVE_SEQ
  if kind == "vs_seeker" then seq = VS_SEEKER_SEQ
  elseif kind == "vs_seeker_bike" then seq = VS_SEEKER_BIKE_SEQ end
  return (seqFrame(seq, elapsed))
end

function OwSprites.fishingFrame(facing, anim, t)
  if anim == "hooked" then
    return seqFrame(FISH_HOOKED, t, true)
  elseif anim == "putaway" then
    local seq = (facing == "left" or facing == "right") and FISH_PUT_AWAY_WE or FISH_PUT_AWAY_SN
    return seqFrame(seq, t)
  end
  return seqFrame(FISH_TAKE_OUT, t)
end

function OwSprites.fishingAbsFrame(facing, frameInGroup)
  return (FISH_BASE[facing] or 8) + (tonumber(frameInGroup) or 3)
end

-- src/field_player_avatar.c:1954 AlignFishingAnimationFrames
function OwSprites.fishingOffset(absFrame, facing)
  local x2, y2 = 0, 0
  if absFrame == 1 or absFrame == 2 or absFrame == 3 then
    x2 = (facing == "left") and -8 or 8
  end
  if absFrame == 5 then y2 = -8 end
  if absFrame == 10 or absFrame == 11 then y2 = 8 end
  return x2, y2
end

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
  if current and current.key == key and current.spr then return true end
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
  OwSprites._overrides[graphicsId] = { key = key, spr = spr, colours = colours, sourceColours = from }
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
  if opts and opts.fishing and spr.frameCount >= 12 then
    local g = math.max(0, math.min(3, tonumber(opts.fishFrame) or 3))
    return OwSprites.fishingAbsFrame(facing, g), flip
  end

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

  if opts and opts.fieldMove and spr.frameCount >= 5 then
    local f = tonumber(opts.fieldMoveFrame) or 4
    if f >= spr.frameCount then f = 0 end
    return f, false
  end

  if opts and opts.running ~= nil and spr.frameCount >= 18 then
    local runFrames = fieldBlock().runFrames
    if runFrames then
      local phase = runFrames[opts.running == 1 and 2 or 1]
      local set = phase and (stepFlip and phase.a or phase.b)
      local f = set and set[facing]
      if f then return f, flip end
    end
    if opts.running == 1 then
      return (stepFlip and RUN_A[facing] or RUN_B[facing]) or RUN_BASE[facing] or 9, flip
    end
    return RUN_BASE[facing] or 9, flip
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
  if ov and not ov.spr then
    OwSprites.setObjectPalette(graphicsId, ov.key, ov.colours, ov.sourceColours)
    ov = OwSprites._overrides[graphicsId]
  end
  if ov and ov.spr then return ov.spr end
  return OwSprites.get(graphicsId)
end

function OwSprites.peekDraw(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return nil end
  local ov = OwSprites._overrides and OwSprites._overrides[graphicsId]
  if ov or OwSprites._loaded[graphicsId] or not OwSprites._stream then return OwSprites.getDraw(graphicsId) end
  OwSprites.prefetch(graphicsId, 0)
  return nil
end

local function paletteRgb(colors)
  if type(colors) ~= "table" then return nil end
  local out = {}
  for i = 1, 15 do
    local c = colors[i]
    if c == nil then return nil end
    c = tonumber(c) or 0
    local r = c % 32
    local g = math.floor(c / 32) % 32
    local b = math.floor(c / 1024) % 32
    out[#out + 1] = {
      math.floor(r * 255 / 31 + 0.5),
      math.floor(g * 255 / 31 + 0.5),
      math.floor(b * 255 / 31 + 0.5),
    }
  end
  return out
end

function OwSprites.getReflectionDraw(graphicsId)
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return nil end
  local cached = OwSprites._reflectionLoaded[graphicsId]
  if cached ~= nil then return cached or nil end
  local base = OwSprites.get(graphicsId)
  if not base or not base.reflectionPaletteMappedTag then
    OwSprites._reflectionLoaded[graphicsId] = false
    return nil
  end
  local from = paletteRgb(base.palette)
  local to = paletteRgb(base.mappedReflectionPalette)
  if not (from and to) then
    OwSprites._reflectionLoaded[graphicsId] = false
    return nil
  end
  local reflected = recolour_sprite(base, from, to)
  OwSprites._reflectionLoaded[graphicsId] = reflected or false
  return reflected
end

--- Draw at world pixel position (cell top-left). Feet at bottom of sprite.
-- opts.bow: use nurse bow frame (ANIM_NURSE_BOW).
-- opts.fieldMove: use the arm-raise field move frame (opts.fieldMoveFrame).
-- opts.frame: explicit frame index override.
function OwSprites.draw(graphicsId, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
  local spr = OwSprites.getDraw(graphicsId)
  if not spr then return false end
  local frame, flip = OwSprites.pose(spr, facing, walkPhase, stepFlip, opts)
  local q = spr.quads[frame]
  if not q then return false end
  local offX = spr.drawOffX or 0
  -- src/sprite.c:1669
  if flip then offX = -offX end
  local sx = px - camX + (16 - spr.width) / 2 + offX
  local sy = py - camY + 16 - spr.height + (spr.drawOffY or 0)
  love.graphics.setColor(1, 1, 1, opts and opts.alpha or 1)
  if flip then
    love.graphics.draw(spr.image, q, sx + spr.width, sy, 0, -1, 1)
  else
    love.graphics.draw(spr.image, q, sx, sy)
  end
  if opts and opts.alpha then love.graphics.setColor(1, 1, 1, 1) end
  return true
end

function OwSprites.avatars()
  if not OwSprites._manifestAttempted and OwSprites._cache then loadManifest() end
  local m = OwSprites._manifest
  return m and m.avatars or nil
end

-- pokeemerald/src/field_player_avatar.c:1256
function OwSprites.avatarState(P)
  if not P then return "NORMAL" end
  if P.fieldMoveAnim and P.fieldMoveAnim > 0 then return "FIELD_MOVE" end
  if P.underwater then return "UNDERWATER" end
  -- pokeemerald/src/field_player_avatar.c:1428
  if P.fishing then return "FISHING" end
  if (P.surfing and not P.dismounting) or P.flyRide or (P.surfJumpFrame and P.surfJumpFrame()) then return "SURFING" end
  if P.biking then return P.bikeType == "acro" and "ACRO_BIKE" or "MACH_BIKE" end
  if P.watering then return "WATERING" end
  return "NORMAL"
end

-- pokeemerald/src/field_player_avatar.c:1241
function OwSprites.avatarGraphicsId(state, isFemale, avatars, who)
  avatars = avatars or OwSprites.avatars()
  local rows = avatars and avatars[who or "player"]
  if type(rows) ~= "table" then return nil end
  local key = isFemale and "female" or "male"
  local normal
  for _, row in ipairs(rows) do
    if row.state == state then return row[key] end
    if row.state == "NORMAL" then normal = row[key] end
  end
  return normal
end

function OwSprites.playerGraphicsId(game, player)
  local P = player or package.loaded["src.core.game3.player"]
  local save = game and game.save
  local session = game and game.session
  local gender = (session and session.gender)
    or (save and (save.gender or (save.player and save.player.gender)))
  local isFemale = (gender == "female" or gender == "F" or gender == 1)

  local avatars = OwSprites.avatars()
  if avatars then
    return OwSprites.avatarGraphicsId(OwSprites.avatarState(P), isFemale, avatars)
  end

  if P then
    if P.fieldMoveAnim and P.fieldMoveAnim > 0 then
      if P.fieldMoveKind == "vs_seeker_bike" then
        -- src/field_player_avatar.c:1331
        return isFemale and (Versions.OW_PLAYER_FEMALE_VS_SEEKER_BIKE or 13)
                         or (Versions.OW_PLAYER_MALE_VS_SEEKER_BIKE or 6)
      end
      return isFemale and (Versions.OW_PLAYER_FEMALE_FIELD_MOVE or 10)
                       or (Versions.OW_PLAYER_MALE_FIELD_MOVE or 3)
    end
    -- pokefirered/src/field_player_avatar.c:1716
    if P.fishing then
      return isFemale and (Versions.OW_PLAYER_FEMALE_FISH or 11)
                       or (Versions.OW_PLAYER_MALE_FISH or 4)
    end
    -- pokefirered/src/field_effect.c:3294
    if (P.surfing and not P.dismounting) or P.flyRide or (P.surfJumpFrame and P.surfJumpFrame()) then
      return isFemale and (Versions.OW_PLAYER_FEMALE_SURF or 9)
                       or (Versions.OW_PLAYER_MALE_SURF or 2)
    end
    if P.biking then
      return isFemale and (Versions.OW_PLAYER_FEMALE_BIKE or 8)
                       or (Versions.OW_PLAYER_MALE_BIKE or 1)
    end
  end

  if isFemale then
    return Versions.OW_PLAYER_FEMALE or 7
  end
  return Versions.OW_PLAYER_MALE or 0
end

return OwSprites

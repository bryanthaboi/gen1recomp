-- Per-pair native FRLG mid atlas (indexed → RGBA) for game3 FieldView.
-- Layered packs: mids.idx = under sprites (BG3/BG1), mids_over.idx = over (BG2).

local Extract = require("src.import.gba.extract_island1")
local NativePack = require("src.import.gba.native_pack")
local Palette = require("src.core.game3.palette")
local Versions = require("src.import.gba.versions")

local NativeTileset = {}

NativeTileset._pairs = {} -- [pair] = { image, overImage?, quads, overQuads, ... }
NativeTileset._cache = nil
NativeTileset._logged = {}

local NATIVE = Extract.NATIVE_ROOT or (Extract.CACHE_ROOT .. "/native")

local function log(msg)
  print("[game3/native] " .. tostring(msg))
end

function NativeTileset.install(cache, _bundle)
  NativeTileset._cache = cache
  NativeTileset._pairs = {}
  NativeTileset._logged = {}
  local okA, TilesetAnim = pcall(require, "src.core.game3.tileset_anim")
  if okA and TilesetAnim and TilesetAnim.install then
    TilesetAnim.install(cache)
  end
end

function NativeTileset.invalidate()
  NativeTileset._pairs = {}
  NativeTileset._logged = {}
  local okA, TilesetAnim = pcall(require, "src.core.game3.tileset_anim")
  if okA and TilesetAnim and TilesetAnim.invalidate then
    TilesetAnim.invalidate()
  end
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.image.newImageData) then
    return nil, nil, "love.image unavailable"
  end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then
    ok, imageData = pcall(function()
      local id = love.image.newImageData(w, h)
      if id.setString then
        id:setString(rgba)
      end
      return id
    end)
  end
  if not ok or not imageData then
    imageData = love.image.newImageData(w, h)
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r = rgba:byte(i) or 0
        local g = rgba:byte(i + 1) or 0
        local b = rgba:byte(i + 2) or 0
        local a = rgba:byte(i + 3) or 255
        imageData:setPixel(x, y, r / 255, g / 255, b / 255, a / 255)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image, imageData
end

local function bake_or_load(cache, pair, idxTbl, rgb, hash, tag, transparentZero)
  local w = (idxTbl.atlasCols or 16) * 16
  local h = (idxTbl.atlasRows or 1) * 16
  local rgbaRel = NATIVE .. "/" .. pair .. "/atlas_" .. tag .. "_" .. hash .. ".rgba"
  local rgba = cache:read(rgbaRel)
  if not rgba or #rgba ~= w * h * 4 then
    rgba, w, h = NativePack.bakeRgba(idxTbl, rgb, { transparentZero = transparentZero })
    pcall(function() cache:write(rgbaRel, rgba) end)
  end
  return rgba_to_image(rgba, w, h)
end

local function load_pair(cache, pair)
  local idxBlob = cache:read(NATIVE .. "/" .. pair .. "/mids.idx")
  local palBlob = cache:read(NATIVE .. "/" .. pair .. "/palettes.bin")
  if not idxBlob or not palBlob then
    return nil, "missing native blobs for " .. tostring(pair)
  end
  local idxTbl, ierr = NativePack.decodeIdx(idxBlob)
  if not idxTbl then return nil, ierr end
  local rgb, bgr = Palette.load(palBlob)
  if not rgb then return nil, bgr end

  local hash = Palette.hash(bgr, idxBlob)
  local layered = cache:exists(NATIVE .. "/" .. pair .. "/mids_over.idx")
  local tag = layered and "u" or "flat"
  local image, imageData, err = bake_or_load(cache, pair, idxTbl, rgb, hash, tag, false)
  if not image then return nil, err or "bake under failed" end

  local midToSlot = {}
  for i, mid in ipairs(idxTbl.midIds or {}) do
    midToSlot[mid] = i - 1
  end

  local cols = idxTbl.atlasCols or 16
  if (idxTbl.atlasRows or 0) * 16 > 2048 then
    log("WARNING atlas rows large for " .. pair)
  end

  local ts = {
    pair = pair,
    image = image,
    imageData = imageData,
    midToSlot = midToSlot,
    cols = cols,
    rows = idxTbl.atlasRows or 1,
    midCount = idxTbl.midCount or 0,
    quads = {},
    layered = false,
    overImage = nil,
    overImageData = nil,
    overQuads = {},
  }

  if layered then
    local overBlob = cache:read(NATIVE .. "/" .. pair .. "/mids_over.idx")
    local overTbl = overBlob and NativePack.decodeIdx(overBlob)
    if overTbl then
      local overHash = Palette.hash(bgr, overBlob)
      local oImg, oData = bake_or_load(cache, pair, overTbl, rgb, overHash, "o", true)
      if oImg then
        ts.layered = true
        ts.overImage = oImg
        ts.overImageData = oData
      end
    end
  end

  return ts
end

function NativeTileset.ready(pair)
  if not Versions.NATIVE_RENDER then return false end
  if not pair then return false end
  if NativeTileset._pairs[pair] then return true end
  local cache = NativeTileset._cache
  if not cache then return false end
  return cache:exists(NATIVE .. "/" .. pair .. "/mids.idx")
    and cache:exists(NATIVE .. "/" .. pair .. "/palettes.bin")
end

local function bind_anim(pair)
  local okA, TilesetAnim = pcall(require, "src.core.game3.tileset_anim")
  if okA and TilesetAnim and TilesetAnim.bindPair then
    TilesetAnim.bindPair(pair)
  end
end

function NativeTileset.get(pair)
  if not pair then return nil end
  local cached = NativeTileset._pairs[pair]
  if cached then
    bind_anim(pair)
    return cached
  end
  local cache = NativeTileset._cache
  if not cache then return nil end
  local ts, err = load_pair(cache, pair)
  if not ts then
    if not NativeTileset._logged[pair] then
      log("load failed " .. tostring(pair) .. ": " .. tostring(err))
      NativeTileset._logged[pair] = true
    end
    return nil
  end
  NativeTileset._pairs[pair] = ts
  if not NativeTileset._logged[pair] then
    log(string.format("atlas ready pair=%s mids=%d %dx%d layered=%s",
      pair, ts.midCount, ts.cols * 16, ts.rows * 16, tostring(ts.layered)))
    NativeTileset._logged[pair] = true
  end
  bind_anim(pair)
  return ts
end

function NativeTileset.slotFor(pairOrTs, mid)
  local ts = type(pairOrTs) == "table" and pairOrTs or NativeTileset.get(pairOrTs)
  if not ts then return 0 end
  return ts.midToSlot[mid] or ts.midToSlot[0] or 0
end

function NativeTileset.hasMid(pairOrTs, mid)
  local ts = type(pairOrTs) == "table" and pairOrTs or NativeTileset.get(pairOrTs)
  return not not (ts and ts.midToSlot and ts.midToSlot[mid] ~= nil)
end

function NativeTileset.quad(pairOrTs, slot)
  local ts = type(pairOrTs) == "table" and pairOrTs or NativeTileset.get(pairOrTs)
  if not ts or not ts.image then return nil end
  slot = tonumber(slot) or 0
  local q = ts.quads[slot]
  if q then return q end
  local cols = ts.cols
  local sx = (slot % cols) * 16
  local sy = math.floor(slot / cols) * 16
  q = love.graphics.newQuad(sx, sy, 16, 16, ts.image:getDimensions())
  ts.quads[slot] = q
  return q
end

function NativeTileset.overQuad(pairOrTs, slot)
  local ts = type(pairOrTs) == "table" and pairOrTs or NativeTileset.get(pairOrTs)
  if not ts or not ts.overImage then return nil end
  slot = tonumber(slot) or 0
  local q = ts.overQuads[slot]
  if q then return q end
  local cols = ts.cols
  local sx = (slot % cols) * 16
  local sy = math.floor(slot / cols) * 16
  q = love.graphics.newQuad(sx, sy, 16, 16, ts.overImage:getDimensions())
  ts.overQuads[slot] = q
  return q
end

return NativeTileset

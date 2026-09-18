-- Pret General tileset animations (water / sand edge / flower) for native FieldView.

local Extract = require("src.import.gba.extract_island1")
local Versions = require("src.import.gba.versions")

local TilesetAnim = {}

TilesetAnim._cache = nil
TilesetAnim._pair = nil
TilesetAnim._manifest = nil
TilesetAnim._banks = {} -- kind → { mids, frames, rgba, midIndex }
TilesetAnim.counter = 0
TilesetAnim.counterMax = 640
TilesetAnim._waterFrame = -1
TilesetAnim._sandFrame = -1
TilesetAnim._flowerFrame = -1
TilesetAnim._enabled = true

local MID_RGBA = 16 * 16 * 4 -- 1024

local function log(msg)
  print("[game3/anim] " .. tostring(msg))
end

function TilesetAnim.install(cache)
  TilesetAnim._cache = cache
  TilesetAnim._pair = nil
  TilesetAnim._manifest = nil
  TilesetAnim._banks = {}
  TilesetAnim.counter = 0
  TilesetAnim._waterFrame = -1
  TilesetAnim._sandFrame = -1
  TilesetAnim._flowerFrame = -1
end

function TilesetAnim.invalidate()
  TilesetAnim._pair = nil
  TilesetAnim._manifest = nil
  TilesetAnim._banks = {}
  TilesetAnim._waterFrame = -1
  TilesetAnim._sandFrame = -1
  TilesetAnim._flowerFrame = -1
end

local function load_bank(cache, pair, kind, info)
  if not info or not info.mids or #info.mids < 1 then return nil end
  local rgba = cache:read(
    (Extract.CACHE_ROOT or "data/generated/gba") .. "/native/" .. pair .. "/anim_" .. kind .. ".rgba")
  if not rgba then return nil end
  local nMids = #info.mids
  local nFrames = info.frames or 0
  local need = nMids * nFrames * MID_RGBA
  if #rgba < need then
    log("short anim bank " .. kind .. " for " .. pair)
    return nil
  end
  local midIndex = {}
  for i, mid in ipairs(info.mids) do
    midIndex[mid] = i - 1 -- 0-based
  end
  return {
    mids = info.mids,
    frames = nFrames,
    rgba = rgba,
    midIndex = midIndex,
  }
end

--- Bind anim banks for the active tileset pair (call on map enter).
function TilesetAnim.bindPair(pair)
  if not Versions.NATIVE_RENDER or Versions.TILESET_ANIM == false then
    TilesetAnim._pair = nil
    return false
  end
  if TilesetAnim._pair == pair and TilesetAnim._manifest then
    return true
  end
  local cache = TilesetAnim._cache
  if not cache or not pair then
    TilesetAnim._pair = nil
    return false
  end
  local src = cache:read(
    (Extract.CACHE_ROOT or "data/generated/gba") .. "/native/" .. pair .. "/anim_manifest.lua")
  if not src then
    TilesetAnim._pair = nil
    TilesetAnim._manifest = nil
    TilesetAnim._banks = {}
    return false
  end
  local chunk = load(src, "@anim_manifest.lua", "t", {})
  local man = chunk and chunk()
  if not man then return false end
  TilesetAnim._pair = pair
  TilesetAnim._manifest = man
  TilesetAnim._banks = {
    water = load_bank(cache, pair, "water", man.water),
    sand = load_bank(cache, pair, "sand", man.sand),
    flower = load_bank(cache, pair, "flower", man.flower),
  }
  TilesetAnim.counter = 0
  TilesetAnim._waterFrame = -1
  TilesetAnim._sandFrame = -1
  TilesetAnim._flowerFrame = -1
  -- Apply frame 0 immediately so first draw matches bank.
  TilesetAnim._applyKind("water", 0)
  TilesetAnim._applyKind("sand", 0)
  TilesetAnim._applyKind("flower", 0)
  TilesetAnim._waterFrame = 0
  TilesetAnim._sandFrame = 0
  TilesetAnim._flowerFrame = 0
  log(string.format("bound pair=%s water=%s sand=%s flower=%s",
    pair,
    TilesetAnim._banks.water and #TilesetAnim._banks.water.mids or 0,
    TilesetAnim._banks.sand and #TilesetAnim._banks.sand.mids or 0,
    TilesetAnim._banks.flower and #TilesetAnim._banks.flower.mids or 0))
  return true
end

function TilesetAnim._applyKind(kind, frame)
  local bank = TilesetAnim._banks[kind]
  if not bank or bank.frames < 1 then return end
  frame = frame % bank.frames
  local NativeTileset = package.loaded["src.core.game3.tileset_native"]
    or require("src.core.game3.tileset_native")
  local ts = NativeTileset.get(TilesetAnim._pair)
  if not ts or not ts.imageData then return end

  local nMids = #bank.mids
  local cols = ts.cols or 16
  for mi, mid in ipairs(bank.mids) do
    local slot = ts.midToSlot[mid]
    if slot then
      local srcOff = (frame * nMids + (mi - 1)) * MID_RGBA
      local ax = (slot % cols) * 16
      local ay = math.floor(slot / cols) * 16
      local frameRgba = bank.rgba:sub(srcOff + 1, srcOff + MID_RGBA)
      local pasted = false
      if love and love.image and love.image.newImageData then
        local ok, piece = pcall(love.image.newImageData, 16, 16, "rgba8", frameRgba)
        if ok and piece and ts.imageData.paste then
          ts.imageData:paste(piece, ax, ay)
          pasted = true
        end
      end
      if not pasted then
        local i = 1
        for y = 0, 15 do
          for x = 0, 15 do
            local r = (frameRgba:byte(i) or 0) / 255
            local g = (frameRgba:byte(i + 1) or 0) / 255
            local b = (frameRgba:byte(i + 2) or 0) / 255
            local a = (frameRgba:byte(i + 3) or 255) / 255
            ts.imageData:setPixel(ax + x, ay + y, r, g, b, a)
            i = i + 4
          end
        end
      end
    end
  end
  if ts.image and ts.image.replacePixels then
    ts.image:replacePixels(ts.imageData)
  elseif ts.image and love and love.graphics then
    ts.image = love.graphics.newImage(ts.imageData)
    if ts.image.setFilter then ts.image:setFilter("nearest", "nearest") end
    ts.quads = {}
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then
      FieldView._nativeBatch = nil
      FieldView._nativeBatches = nil
      FieldView._nativeDirty = true
    end
  end
end

--- Pret TilesetAnim_General schedule (UpdateTilesetAnimations increments first).
function TilesetAnim.step()
  if not TilesetAnim._enabled or not TilesetAnim._pair then return end
  TilesetAnim.counter = TilesetAnim.counter + 1
  if TilesetAnim.counter >= TilesetAnim.counterMax then
    TilesetAnim.counter = 0
  end
  local timer = TilesetAnim.counter

  if timer % 8 == 0 then
    local frame = math.floor(timer / 8) % 8
    if frame ~= TilesetAnim._sandFrame then
      TilesetAnim._sandFrame = frame
      TilesetAnim._applyKind("sand", frame)
    end
  end
  if timer % 16 == 1 then
    local frame = math.floor(timer / 16) % 8
    if frame ~= TilesetAnim._waterFrame then
      TilesetAnim._waterFrame = frame
      TilesetAnim._applyKind("water", frame)
    end
  end
  if timer % 16 == 2 then
    local frame = math.floor(timer / 16) % 5
    if frame ~= TilesetAnim._flowerFrame then
      TilesetAnim._flowerFrame = frame
      TilesetAnim._applyKind("flower", frame)
    end
  end
end

return TilesetAnim

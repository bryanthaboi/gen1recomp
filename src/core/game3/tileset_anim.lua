-- Pret General tileset animations (water / sand edge / flower) for native FieldView.

local Extract = require("src.import.gba.extract_island1")
local Versions = require("src.import.gba.versions")

local TilesetAnim = {}

TilesetAnim._cache = nil
TilesetAnim._pairs = {}
TilesetAnim._visible = {}
TilesetAnim.counter = 0
TilesetAnim.counterMax = 640
TilesetAnim._waterFrame = 0
TilesetAnim._sandFrame = 0
TilesetAnim._flowerFrame = 0
TilesetAnim._enabled = true

local MID_RGBA = 16 * 16 * 4 -- 1024

local function log(msg)
  print("[game3/anim] " .. tostring(msg))
end

function TilesetAnim.install(cache)
  TilesetAnim._cache = cache
  TilesetAnim.invalidate()
end

function TilesetAnim.invalidate()
  TilesetAnim._pairs = {}
  TilesetAnim._visible = {}
  TilesetAnim.counter = 0
  TilesetAnim._waterFrame = 0
  TilesetAnim._sandFrame = 0
  TilesetAnim._flowerFrame = 0
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

-- pokefirered/src/tileset_anims.c:223
function TilesetAnim.bindPair(pair, atlas)
  if not Versions.NATIVE_RENDER or Versions.TILESET_ANIM == false then
    return false
  end
  local cache = TilesetAnim._cache
  if not cache or not pair or not atlas then return false end
  local entry = TilesetAnim._pairs[pair]
  if entry == false then return false end
  if not entry then
    local src = cache:read(
      (Extract.CACHE_ROOT or "data/generated/gba") .. "/native/" .. pair .. "/anim_manifest.lua")
    local chunk = src and load(src, "@anim_manifest.lua", "t", {})
    local man = chunk and chunk()
    if not man then
      TilesetAnim._pairs[pair] = false
      return false
    end
    entry = { atlas = atlas, frames = {}, banks = {
      water = load_bank(cache, pair, "water", man.water),
      sand = load_bank(cache, pair, "sand", man.sand),
      flower = load_bank(cache, pair, "flower", man.flower),
    } }
    TilesetAnim._pairs[pair] = entry
  end
  TilesetAnim._visible[pair] = true
  for _, kind in ipairs({ "water", "sand", "flower" }) do
    TilesetAnim._applyKind(entry, kind, TilesetAnim["_" .. kind .. "Frame"])
  end
  return true
end

function TilesetAnim.setVisiblePairs(visible)
  TilesetAnim._visible = {}
  for pair in pairs(visible) do TilesetAnim._visible[pair] = true end
end

function TilesetAnim._applyKind(entry, kind, frame)
  local bank = entry.banks[kind]
  if not bank or bank.frames < 1 then return end
  frame = frame % bank.frames
  if entry.frames[kind] == frame then return end
  local ts = entry.atlas
  if not ts or not ts.imageData then return end
  entry.frames[kind] = frame

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
  if not TilesetAnim._enabled or not Versions.NATIVE_RENDER
      or Versions.TILESET_ANIM == false then return end
  TilesetAnim.counter = TilesetAnim.counter + 1
  if TilesetAnim.counter >= TilesetAnim.counterMax then
    TilesetAnim.counter = 0
  end
  local timer = TilesetAnim.counter

  if timer % 8 == 0 then
    local frame = math.floor(timer / 8) % 8
    if frame ~= TilesetAnim._sandFrame then
      TilesetAnim._sandFrame = frame
    end
  end
  if timer % 16 == 1 then
    local frame = math.floor(timer / 16) % 8
    if frame ~= TilesetAnim._waterFrame then
      TilesetAnim._waterFrame = frame
    end
  end
  if timer % 16 == 2 then
    local frame = math.floor(timer / 16) % 5
    if frame ~= TilesetAnim._flowerFrame then
      TilesetAnim._flowerFrame = frame
    end
  end
  for pair in pairs(TilesetAnim._visible) do
    local entry = TilesetAnim._pairs[pair]
    if entry then
      TilesetAnim._applyKind(entry, "sand", TilesetAnim._sandFrame)
      TilesetAnim._applyKind(entry, "water", TilesetAnim._waterFrame)
      TilesetAnim._applyKind(entry, "flower", TilesetAnim._flowerFrame)
    end
  end
end

return TilesetAnim

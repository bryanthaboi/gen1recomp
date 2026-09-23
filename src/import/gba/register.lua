-- Load Island 1 extract from mod.cache and register per-pair Sevii tilesets.

local Extract = require("src.import.gba.extract_island1")
local Versions = require("src.import.gba.versions")

local Register = {}

local CACHE = Extract.CACHE_ROOT

local TILESET_IDS = {
  "SEVII_OUTDOOR",
  "SEVII_NETWORK",
  "SEVII_HOUSE",
  "SEVII_HARBOR",
}

local function load_lua(cache, rel)
  local src = cache:read(rel)
  if not src then return nil, "missing " .. rel end
  local chunk, err = load(src, "@" .. rel, "t", {})
  if not chunk then return nil, err end
  return chunk()
end

local function decode_tileset_image(raw, width, height)
  local ImageWriter = require("src.import.ImageWriter")
  local bytes = {}
  for i = 1, #raw do bytes[i] = raw:byte(i) end
  return ImageWriter.decode2bpp(bytes, width, height, false)
end

function Register.loadBundle(cache)
  if not Extract.cacheReady(cache) then
    return nil, "sevii extract cache missing — run extract first"
  end
  local metaSrc = cache:read(CACHE .. "/meta.json")
  local meta = {}
  if metaSrc then
    meta.imageWidth = tonumber(metaSrc:match('"imageWidth"%s*:%s*(%d+)')) or 128
    meta.imageHeight = tonumber(metaSrc:match('"imageHeight"%s*:%s*(%d+)')) or 8
    meta.tilesPerRow = tonumber(metaSrc:match('"tilesPerRow"%s*:%s*(%d+)')) or 16
    meta.tileCount = tonumber(metaSrc:match('"tile_count"%s*:%s*(%d+)'))
      or tonumber(metaSrc:match('"tileCount"%s*:%s*(%d+)'))
  end
  local tm = load_lua(cache, CACHE .. "/tileset_meta.lua")
  if tm then
    meta.imageWidth = tm.imageWidth or meta.imageWidth
    meta.imageHeight = tm.imageHeight or meta.imageHeight
    meta.tilesPerRow = tm.tilesPerRow or meta.tilesPerRow
    meta.tileCount = tm.tileCount or meta.tileCount
    meta.tilePalettes = tm.tilePalettes
    meta.specialPalettes = tm.specialPalettes
    meta.tilePalettesByTileset = tm.tilePalettesByTileset
    meta.specialPalettesByTileset = tm.specialPalettesByTileset
  end
  local blocks = load_lua(cache, CACHE .. "/blocks.lua")
  local warps = load_lua(cache, CACHE .. "/warps.lua") or {}
  local layouts = {}
  local mapIds = {}
  for mapId in pairs(Versions.MAPS or {}) do
    mapIds[#mapIds + 1] = mapId
  end
  table.sort(mapIds)
  if #mapIds == 0 then
    mapIds = {
      "SEVII_ONE_ISLAND",
      "SEVII_ONE_ISLAND_KINDLE_ROAD",
      "SEVII_ONE_ISLAND_TREASURE_BEACH",
      "SEVII_ONE_ISLAND_POKECENTER",
      "SEVII_ONE_ISLAND_POKECENTER_2F",
      "SEVII_ONE_ISLAND_HARBOR",
      "SEVII_ONE_ISLAND_HOUSE1",
      "SEVII_ONE_ISLAND_HOUSE2",
    }
  end
  for _, mapId in ipairs(mapIds) do
    local L = load_lua(cache, CACHE .. "/layouts/" .. mapId .. ".lua")
    if L then layouts[mapId] = L end
  end
  local raw = cache:read(CACHE .. "/tileset.2bpp")
  if not raw then return nil, "missing tileset.2bpp" end

  local midIndex = load_lua(cache, CACHE .. "/mid_index.lua") or {}

  local native = nil
  if Extract.nativeReady(cache) then
    local LayoutNative = require("src.core.game3.layout_native")
    local NativePack = require("src.import.gba.native_pack")
    local manifest = load_lua(cache, Extract.NATIVE_ROOT .. "/manifest.lua")
    local midLayouts = {}
    if manifest and manifest.layouts then
      for mapId, info in pairs(manifest.layouts) do
        local blob = cache:read(Extract.NATIVE_ROOT .. "/" .. (info.file or ("layouts/" .. mapId .. ".mid")))
        if blob then
          local decoded = NativePack.decodeMidLayout(blob)
          if decoded then
            midLayouts[mapId] = LayoutNative.fromDecoded(decoded, mapId, info.pair)
          end
        end
      end
    end
    native = {
      manifest = manifest,
      midLayouts = midLayouts,
    }
  end

  return {
    meta = meta,
    blocks = blocks,
    warps = warps,
    layouts = layouts,
    raw2bpp = raw,
    midIndex = midIndex,
    native = native,
  }
end

--- Build one tileset def sharing the atlas; tilePalettes come from that bank.
function Register.buildTilesetDef(bundle, imagePath, tilesetId)
  tilesetId = tilesetId or "SEVII_OUTDOOR"
  local meta = bundle.meta
  local blocksList = {}
  local collisionList = {}
  local maxId = -1
  for id, def in pairs(bundle.blocks) do
    if type(id) == "number" and id > maxId then maxId = id end
  end
  for id = 0, maxId do
    local def = bundle.blocks[id]
    blocksList[id + 1] = def and def.tiles or { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    collisionList[id + 1] = def and def.collision or { 0, 0, 0, 0 }
  end
  local nTiles = meta.tileCount or 1
  local src = (meta.tilePalettesByTileset and meta.tilePalettesByTileset[tilesetId])
    or meta.tilePalettes
  local tilePalettes = {}
  for i = 1, nTiles do
    -- Unused atlas ids default to 1 (don't-care; this tileset never draws them).
    tilePalettes[i] = (src and src[i]) or 1
  end
  return {
    id = tilesetId,
    image = imagePath,
    imageWidth = meta.imageWidth,
    imageHeight = meta.imageHeight,
    tilesPerRow = meta.tilesPerRow or 16,
    blocks = blocksList,
    collision = collisionList,
    tilePalettes = tilePalettes,
  }
end

--- Inject per-pair demake ramps into specialTilesets[tilesetId].
function Register.injectSpecialPalettes(mod, bundle)
  local meta = bundle and bundle.meta
  if not meta then return end
  local byTs = meta.specialPalettesByTileset
  if not byTs and meta.specialPalettes then
    byTs = { SEVII_OUTDOOR = meta.specialPalettes, SEVII_ISLAND1 = meta.specialPalettes }
  end
  if not byTs then return end
  local data = mod.game and mod.game.data
  if not data then
    local ok, Data = pcall(require, "src.core.Data")
    if ok then data = Data end
  end
  if not data then return end
  local function ensure(tableName)
    local pals = data[tableName]
    if not pals then return end
    pals.specialTilesets = pals.specialTilesets or {}
    for tsId, special in pairs(byTs) do
      pals.specialTilesets[tsId] = special
    end
    -- Legacy alias for any leftover SEVII_ISLAND1 map refs.
    if byTs.SEVII_OUTDOOR and not pals.specialTilesets.SEVII_ISLAND1 then
      pals.specialTilesets.SEVII_ISLAND1 = byTs.SEVII_OUTDOOR
    end
  end
  ensure("gen2Palettes")
  ensure("palettes")
end

function Register.materializePng(cache, bundle)
  local ok, img = pcall(decode_tileset_image, bundle.raw2bpp, bundle.meta.imageWidth, bundle.meta.imageHeight)
  if not ok or not img then
    return nil, tostring(img)
  end
  local rel = CACHE .. "/tileset.png"
  if love and love.image and img.encode then
    local fileData = img:encode("png")
    local bytes = fileData:getString()
    cache:write(rel, bytes)
    return "mod_cache/Kanto-Reforged/" .. rel
  end
  return nil, "png encode unavailable"
end

function Register.ensureExtracted(mod, progressCb)
  local imports = mod.imports
  local cache = mod.cache
  if not imports or not cache then
    return false, "mod.imports/mod.cache unavailable"
  end
  local importId = Extract.findImport(imports)
  if not importId then
    return false, "import FireRed or LeafGreen via optional_imports to enable Sevii"
  end
  local info = imports:info(importId)
  if Extract.nativeReady(cache) and info and Extract.metaMd5Matches(cache, info.md5) then
    return true, { cached = true }
  end
  return Extract.runNativeOnly(imports, cache, progressCb)
end

--- Register per-pair tilesets + FRLG outdoor/interior maps.
function Register.apply(mod, MapsModule)
  local cache = mod.cache
  local bundle, err = Register.loadBundle(cache)
  if not bundle then return false, err end

  local imagePath = "mod_cache/Kanto-Reforged/" .. CACHE .. "/tileset.png"
  local pngOk = Register.materializePng(cache, bundle)
  if not pngOk then
    imagePath = "mod_cache/Kanto-Reforged/" .. CACHE .. "/tileset.2bpp"
  end

  local imageData = nil
  if not pngOk then
    local ok, img = pcall(decode_tileset_image, bundle.raw2bpp, bundle.meta.imageWidth, bundle.meta.imageHeight)
    if ok and img then imageData = img end
  end

  local data = mod.game and mod.game.data
  if not data then
    local ok, Data = pcall(require, "src.core.Data")
    if ok then data = Data end
  end
  if data then
    data.tilesets = data.tilesets or {}
  end

  local ids = TILESET_IDS
  if bundle.meta.specialPalettesByTileset then
    ids = {}
    for tsId in pairs(bundle.meta.specialPalettesByTileset) do
      ids[#ids + 1] = tsId
    end
    table.sort(ids)
  elseif Versions.PAIR_TILESET then
    ids = {}
    local seen = {}
    for _, tsId in pairs(Versions.PAIR_TILESET) do
      if not seen[tsId] then
        seen[tsId] = true
        ids[#ids + 1] = tsId
      end
    end
    table.sort(ids)
  end

  for _, tsId in ipairs(ids) do
    local tsDef = Register.buildTilesetDef(bundle, imagePath, tsId)
    if imageData then
      tsDef.imageData = imageData
      tsDef.image = "mod_cache/Kanto-Reforged/" .. CACHE .. "/tileset.png"
    elseif not tsDef.image then
      tsDef.image = "mod_cache/Kanto-Reforged/" .. CACHE .. "/tileset.png"
    end
    if mod.content and mod.content.tilesets and mod.content.tilesets.register then
      mod.content.tilesets:register(tsId, tsDef)
    end
    if data then
      data.tilesets[tsId] = tsDef
      if data.gen2Tilesets then
        data.gen2Tilesets[tsId] = tsDef
      end
    end
  end
  -- Legacy alias → outdoor
  if data and data.tilesets.SEVII_OUTDOOR then
    data.tilesets.SEVII_ISLAND1 = data.tilesets.SEVII_OUTDOOR
    if data.gen2Tilesets then
      data.gen2Tilesets.SEVII_ISLAND1 = data.tilesets.SEVII_OUTDOOR
    end
  end

  Register.injectSpecialPalettes(mod, bundle)

  Register._midIndex = bundle.midIndex

  -- Native FRLG mid atlas (game3 FieldView); Gen2 atlas registration stays above.
  do
    local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
    if okN and NativeTileset and NativeTileset.install then
      NativeTileset.install(cache, bundle)
    end
    local okO, OwSprites = pcall(require, "src.core.game3.ow_sprites")
    if okO and OwSprites and OwSprites.install then
      OwSprites.install(cache)
    end
  end

  if MapsModule and MapsModule.registerFromExtract then
    local ok, mapErr = pcall(MapsModule.registerFromExtract, mod, bundle)
    if not ok then
      return false, mapErr
    end
  end

  local Assets = package.loaded["src.render.Assets"]
  if Assets and Assets.flush then pcall(Assets.flush) end
  return true
end

return Register

-- Hydrate Game3 standalone data from the firered/ GBA extract cache.
-- Uses native mid layouts + warps; does not touch Sevii ferry host maps.

local Versions = require("src.import.gba.versions")
local Extract = require("src.import.gba.extract_island1")
local MapIds = require("src.core.game3.map_ids")

local Dataset = {}

local function diskFallback(rel)
  local f = io.open(rel, "rb") or io.open("data/generated/gba/" .. rel, "rb")
  if f then
    local data = f:read("*a")
    f:close()
    if type(data) == "string" and #data > 0 then return data end
  end

  local okG, GameVersion = pcall(require, "src.core.GameVersion")
  local prefix = (okG and GameVersion.cachePrefix and GameVersion.cachePrefix()) or "firered/"
  local prefixes = { prefix }
  -- Always also try firered/ for GBA extract paths (standalone Game3).
  if prefix ~= "firered/" then
    prefixes[#prefixes + 1] = "firered/"
  end
  local roots = {}
  local home = os.getenv("HOME")
  if home then
    roots[#roots + 1] = home .. "/.local/share/love/pokemon-love2d"
  end
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local sd = love.filesystem.getSaveDirectory()
    if type(sd) == "string" and sd ~= "" then
      roots[#roots + 1] = sd
      local parent = sd:match("^(.*)/[^/]+$")
      if parent then roots[#roots + 1] = parent .. "/pokemon-love2d" end
    end
  end
  for _, root in ipairs(roots) do
    for _, pfx in ipairs(prefixes) do
      for _, path in ipairs({ root .. "/" .. pfx .. rel, root .. "/" .. rel }) do
        local f = io.open(path, "rb")
        if f then
          local data = f:read("*a")
          f:close()
          if type(data) == "string" and #data > 0 then return data end
        end
      end
    end
  end
  return nil
end

local function loveCache()
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        local bytes = CacheFs.readActive(rel)
        if type(bytes) == "string" then return bytes end
      end
      if love and love.filesystem then
        local bytes = love.filesystem.read(rel)
        if type(bytes) == "string" then return bytes end
      end
      return diskFallback(rel)
    end,
    write = function(_, rel, bytes)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.write then
        return CacheFs.write(rel, bytes)
      end
      if not love or not love.filesystem then return false end
      return love.filesystem.write(rel, bytes)
    end,
    exists = function(_, rel)
      local cache = loveCache()
      return cache:read(rel) ~= nil
    end,
  }
end

--- Shared firered CacheFs-backed cache for standalone Game3 (mod.cache is nil).
function Dataset.cache()
  return loveCache()
end

local function load_lua_rel(rel)
  local cache = loveCache()
  local src = cache:read(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, val = pcall(chunk)
  if ok then return val end
  return nil
end

--- Build map defs for every FR_* (and any other) entry in native manifest / Versions.MAPS.
function Dataset.buildMaps(warps)
  warps = warps
    or load_lua_rel(Extract.CACHE_ROOT .. "/warps.lua")
    or Versions.WARPS
    or {}
  local connections = load_lua_rel(Extract.CACHE_ROOT .. "/connections.lua") or {}
  local manifest = load_lua_rel((Extract.NATIVE_ROOT or Extract.CACHE_ROOT .. "/native") .. "/manifest.lua") or {}
  local MapCatalog = require("src.import.gba.map_catalog")
  local MapSectionsExtract = require("src.import.gba.map_sections_extract")
  local Json = nil
  pcall(function() Json = require("src.link.Json") end)
  local maps = {}

  local function add(mapId, info)
    local spec = Versions.MAPS[mapId] or {}
    local pair = (info and info.pair) or spec.pair
    local tileset = pair and Versions.PAIR_TILESET and Versions.PAIR_TILESET[pair]

    -- Load map header metadata if available in map_tree cache
    local regionMapSectionId = spec.regionMapSectionId
    local showMapName = spec.showMapName
    local floorNum = spec.floorNum
    local weather = spec.weather
    local mapType = spec.mapType

    if regionMapSectionId == nil or showMapName == nil then
      -- Try loading from data/generated/gba/map_tree/maps/{slot}/header.json
      local cache = loveCache()
      local candidates = {}
      local slot = MapCatalog.slotKeyFor and MapCatalog.slotKeyFor(mapId)
      if slot then candidates[#candidates + 1] = slot end
      if spec.group ~= nil and spec.num ~= nil then
        candidates[#candidates + 1] = string.format("%d_%d", spec.group, spec.num)
      end
      -- Try lookup in FRLG_MAP_TO_FR reverse
      for k, v in pairs(Versions.FRLG_MAP_TO_FR or {}) do
        if v == mapId then
          candidates[#candidates + 1] = k:gsub(":", "_")
        end
      end
      for k, v in pairs(Versions.FRLG_MAP_TO_SEVII or {}) do
        if v == mapId then
          candidates[#candidates + 1] = k:gsub(":", "_")
        end
      end

      for _, slot in ipairs(candidates) do
        local raw = cache:read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
          or cache:read(Extract.CACHE_ROOT .. "/map_tree/maps/" .. slot .. "/header.json")
        if raw and Json and Json.decode then
          local okH, h = pcall(Json.decode, raw)
          if okH and type(h) == "table" then
            regionMapSectionId = regionMapSectionId or h.regionMapSectionId
            showMapName = showMapName or h.showMapName
            floorNum = floorNum or h.floorNum
            weather = weather or h.weather
            mapType = mapType or h.mapType
            break
          end
        end
      end
    end

    -- Fallback inference if header.json was not loaded
    if regionMapSectionId == nil then
      local secInfo = MapSectionsExtract.getInfo(nil, mapId, floorNum or 0)
      regionMapSectionId = secInfo and secInfo.secId
    end
    if showMapName == nil then
      showMapName = 0
    end

    maps[mapId] = {
      id = mapId,
      name = mapId,
      width = (info and info.width) or spec.width or 20,
      height = (info and info.height) or spec.height or 18,
      kind = spec.kind or "town",
      environment = spec.environment or "TOWN",
      pair = pair,
      tileset = tileset,
      warps = warps[mapId] or {},
      connections = connections[mapId] or {},
      regionMapSectionId = regionMapSectionId or 88,
      showMapName = (showMapName == 1 or showMapName == true) and 1 or 0,
      floorNum = tonumber(floorNum) or 0,
      weather = weather or 0,
      mapType = mapType or 0,
      native = true,
    }
  end

  if manifest.layouts then
    for mapId, info in pairs(manifest.layouts) do
      -- Prefer Fire Red maps for standalone boot; keep SEVII_* available but unused.
      add(mapId, info)
    end
  else
    for mapId, spec in pairs(Versions.MAPS or {}) do
      add(mapId, { width = spec.width, height = spec.height, pair = spec.pair })
    end
  end

  -- Fallback corridor edges if connections.lua missing (pre-v82 caches).
  if not next(connections) then
    if maps.FR_PALLET_TOWN and maps.FR_ROUTE_1 then
      maps.FR_PALLET_TOWN.connections = {
        north = { map = "FR_ROUTE_1", offset = 0 },
      }
      maps.FR_ROUTE_1.connections = {
        south = { map = "FR_PALLET_TOWN", offset = 0 },
        north = { map = "FR_VIRIDIAN_CITY", offset = -12 },
      }
    end
    if maps.FR_VIRIDIAN_CITY and maps.FR_ROUTE_1 then
      maps.FR_VIRIDIAN_CITY.connections = maps.FR_VIRIDIAN_CITY.connections or {}
      maps.FR_VIRIDIAN_CITY.connections.south = { map = "FR_ROUTE_1", offset = 12 }
    end
    if maps.FR_VIRIDIAN_CITY and maps.FR_ROUTE_2 then
      maps.FR_VIRIDIAN_CITY.connections = maps.FR_VIRIDIAN_CITY.connections or {}
      maps.FR_VIRIDIAN_CITY.connections.north = { map = "FR_ROUTE_2", offset = 12 }
      maps.FR_ROUTE_2.connections = {
        south = { map = "FR_VIRIDIAN_CITY", offset = -12 },
        north = { map = "FR_PEWTER_CITY", offset = -12 },
      }
    end
    if maps.FR_PEWTER_CITY and maps.FR_ROUTE_2 then
      maps.FR_PEWTER_CITY.connections = {
        south = { map = "FR_ROUTE_2", offset = 12 },
      }
    end
  end

  return maps
end

--- Point extract roots at the engine firered cache and install native tilesets.
function Dataset.mountExtractRoots()
  Extract.CACHE_ROOT = "data/generated/gba"
  Extract.NATIVE_ROOT = "data/generated/gba/native"
end

--- Bind LayoutNative handles onto map defs (FieldView needs midLayout).
function Dataset.attachMidLayouts(maps, cache)
  if type(maps) ~= "table" then return 0 end
  cache = cache or loveCache()
  local LayoutNative = require("src.core.game3.layout_native")
  local NativePack = require("src.import.gba.native_pack")
  local nativeRoot = Extract.NATIVE_ROOT or (Extract.CACHE_ROOT .. "/native")
  local manifest = load_lua_rel(nativeRoot .. "/manifest.lua") or {}
  local layouts = manifest.layouts or {}
  local attached = 0
  for mapId, def in pairs(maps) do
    if def and not def.midLayout then
      local info = layouts[mapId]
      local rel = nativeRoot .. "/"
        .. ((info and info.file) or ("layouts/" .. mapId .. ".mid"))
      local blob = cache:read(rel)
      if blob then
        local decoded = NativePack.decodeMidLayout(blob)
        if decoded then
          local pair = (info and info.pair) or def.pair
          def.midLayout = LayoutNative.fromDecoded(decoded, mapId, pair)
          if decoded.width and decoded.width > 0 then def.width = decoded.width end
          if decoded.height and decoded.height > 0 then def.height = decoded.height end
          if pair then def.pair = pair end
          attached = attached + 1
        end
      end
    elseif def and def.midLayout then
      attached = attached + 1
    end
  end
  return attached
end

--- Populate game.data for standalone Fire Red.
function Dataset.hydrate(game)
  Dataset.mountExtractRoots()
  local cache = loveCache()
  game.data = game.data or {}
  game.data.maps = Dataset.buildMaps()
  game.data.tilesets = game.data.tilesets or {}

  local nLayouts = Dataset.attachMidLayouts(game.data.maps, cache)

  local okS, Space = pcall(require, "src.core.game3.scripting.space")
  local nEvents = 0
  if okS and Space then
    Space.ensureBundle(nil)
    nEvents = Space.attachEventsToMaps(game.data.maps, Space.bundle) or 0
  end

  local NativeTileset = require("src.core.game3.tileset_native")
  if NativeTileset.install then
    NativeTileset.install(cache, nil)
  end
  local okO, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  if okO and OwSprites and OwSprites.install then
    OwSprites.install(cache)
  end
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects and FieldEffects.install then
    FieldEffects.install(cache)
  end

  local okPk, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okPk and Pokemon and Pokemon.install then
    Pokemon.install(cache)
  end
  local okPc, PartyChrome = pcall(require, "src.ui.game3.party_chrome")
  if okPc and PartyChrome and PartyChrome.install then
    PartyChrome.install(cache)
  end
  local okBc, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if okBc and BagChrome and BagChrome.install then
    BagChrome.install(cache)
  end
  local okMp, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
  if okMp and MapPreviewScreen and MapPreviewScreen.install then
    MapPreviewScreen.install(cache)
  end

  local Audio = require("src.core.game3.audio")
  -- Explicit firered audio root — never inherit Sevii Extract.CACHE_ROOT default.
  local audioRoot = "data/generated/gba/audio"
  local okA, errA = Audio.install(cache, { root = audioRoot })
  if not okA then
    local songs = load_lua_rel(audioRoot .. "/songs.lua")
      or load_lua_rel(Extract.CACHE_ROOT .. "/audio/songs.lua")
    if songs then
      Audio.loadMeta({ songs = songs })
    end
    print("[game3/dataset] audio install: " .. tostring(errA))
  elseif Audio._pack and Audio._pack.index and Audio._pack.index.mapSongs and game.data and game.data.maps then
    for mapId, songId in pairs(Audio._pack.index.mapSongs) do
      local def = game.data.maps[mapId]
      if def and def.music == nil then def.music = songId end
    end
  end

  -- Encounter tables need the mounted firered cache (install may have run earlier).
  local okE, Encounters = pcall(require, "src.core.game3.encounters")
  if okE and Encounters and Encounters.loadFromMod then
    Encounters.loadFromMod(nil)
  end

  local nMaps = 0
  for _ in pairs(game.data.maps) do nMaps = nMaps + 1 end
  print(string.format(
    "[game3/dataset] hydrated %d maps midLayouts=%d eventMaps=%d (start=%s)",
    nMaps, nLayouts, nEvents, tostring(MapIds.NEW_GAME_START.map)))

  return true
end

return Dataset

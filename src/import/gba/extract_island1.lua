-- Staged Island 1 extract: tilesets → maps → collide → quantize → pack → mod.cache.
-- Outdoors (SeviiIslands123) + interiors (Network Center, Harbor, Houses) share
-- one 2bpp sheet; metatile ids are namespaced by tileset pair.

local Versions = require("src.import.gba.versions")
local Rom = require("src.import.gba.rom")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local Collision = require("src.core.game3.scripting.collision")
local Quantize = require("src.import.gba.quantize")
local QuantizeLab = require("src.import.gba.quantize_lab")
local QuantizeMrf = require("src.import.gba.quantize_mrf")
local PaletteRules = require("src.import.gba.palette_rules")
local Maps = require("src.import.gba.maps")

local Extract = {}

local CachePaths = require("src.core.game3.cache_paths")
setmetatable(Extract, {
  __index = function(t, k)
    if k == "CACHE_ROOT" then return CachePaths.CACHE_ROOT end
    if k == "NATIVE_ROOT" then return CachePaths.NATIVE_ROOT end
    return rawget(t, k)
  end,
  __newindex = function(t, k, v)
    if k == "CACHE_ROOT" then CachePaths.CACHE_ROOT = v
    elseif k == "NATIVE_ROOT" then CachePaths.NATIVE_ROOT = v
    else rawset(t, k, v)
    end
  end,
})
Extract.STAGE_COUNT = 7

local function progress(cb, stage, name, cur, total)
  if cb then cb(stage, Extract.STAGE_COUNT, name, cur or 0, total or 1) end
end

local function json_escape(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function write_json(cache, rel, obj)
  local function enc(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return tostring(v) end
    if t == "string" then return '"' .. json_escape(v) .. '"' end
    if t == "table" then
      local isArray = #v > 0
      if isArray then
        local parts = {}
        for i = 1, #v do parts[i] = enc(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. enc(v[k])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
  end
  return cache:write(rel, enc(obj) .. "\n")
end

--- Pad odd FRLG grids so 2×2 pack does not clip the last row/column.
-- Outdoors: extend edge tiles (ocean/cliff continues). Indoors: black void mid
-- so the duplicated right/bottom column does not stretch walls/stairs.
local function pad_even(grid)
  local w, h = grid.width, grid.height
  local nw = w + (w % 2)
  local nh = h + (h % 2)
  if nw == w and nh == h then return grid end
  local indoor = grid.environment == "INDOOR" or grid.kind == "indoor"
  local voidCell = { mid = 0, coll = 1, elev = 0 }
  local cells = {}
  local function at(x, y)
    if indoor and (x >= w or y >= h) then
      return voidCell
    end
    local sx = math.min(x, w - 1)
    local sy = math.min(y, h - 1)
    return grid.cells[sy * w + sx + 1]
  end
  for y = 0, nh - 1 do
    for x = 0, nw - 1 do
      local c = at(x, y)
      cells[#cells + 1] = { mid = c.mid, coll = c.coll, elev = c.elev }
    end
  end
  return {
    width = nw,
    height = nh,
    cells = cells,
    map_id = grid.map_id,
    kind = grid.kind,
    pair = grid.pair,
    environment = grid.environment,
    padded_from = { width = w, height = h },
  }
end

Extract.padEven = pad_even

-- Exact-black 8×8 quads are FRLG void / silhouette (mid 0, mid 8, chamfer
-- corners). They must not enter the material codebook or steal shade slots.
local function is_exact_black_quad(buf)
  return Metatile.isExactBlackBuf(buf, 64)
end

local DYNAMIC_MIDS_BY_PAIR = {
  network = {
    0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
  pokemon_center = {
    0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
  dept_store = {
    0x28D, 0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
}

local function script_mids_by_pair(scriptBundle, grids)
  local NativePack = require("src.import.gba.native_pack")
  if not scriptBundle then return {} end
  return NativePack.scriptMidsByPair(scriptBundle.scripts, scriptBundle.events, function(mapId)
    local grid = grids[mapId]
    return grid and (grid.pair or "sevii_outdoor") or nil
  end)
end

local function unique_mids_by_pair(grids, scriptMids)
  local byPair = {}
  for _, grid in pairs(grids) do
    local pair = grid.pair or "sevii_outdoor"
    local seen = byPair[pair]
    if not seen then
      seen = {}
      byPair[pair] = seen
    end
    for _, cell in ipairs(grid.cells) do
      seen[cell.mid] = true
    end
  end
  for pair, mids in pairs(scriptMids or {}) do
    local seen = byPair[pair]
    if seen then
      for mid in pairs(mids) do seen[mid] = true end
    end
  end
  for pair, extraMids in pairs(DYNAMIC_MIDS_BY_PAIR) do
    local seen = byPair[pair]
    if seen then
      for _, mid in ipairs(extraMids) do
        seen[mid] = true
      end
    end
  end
  for pair, seen in pairs(byPair) do
    require("src.import.gba.native_pack").addDynamicMids(seen, pair)
  end
  local NativePack = require("src.import.gba.native_pack")
  local out = {}
  for pair, seen in pairs(byPair) do
    NativePack.addPcOnMids(seen)
    local list = {}
    for mid in pairs(seen) do list[#list + 1] = mid end
    table.sort(list)
    out[pair] = list
  end
  return out
end

function Extract.findImport(imports)
  for _, id in ipairs({ "firered", "leafgreen" }) do
    local info = imports:info(id)
    if info then return id, info end
  end
  return nil, nil
end

function Extract.cacheReady(cache)
  return cache and cache:exists(Extract.CACHE_ROOT .. "/meta.json")
    and Extract.nativeReady(cache)
end

function Extract.nativeReady(cache)
  if not cache then return false end
  local OwExtract = require("src.import.gba.ow_extract")
  local AnimPack = require("src.import.gba.tileset_anim_pack")
  if not cache:exists(Extract.NATIVE_ROOT .. "/manifest.lua") then return false end
  if not OwExtract.ready(cache, Extract.CACHE_ROOT) then return false end
  if not AnimPack.ready(cache, Extract.CACHE_ROOT) then return false end
  -- Dual-layer under/over atlases (NATIVE_VERSION >= 5).
  local src = cache:read(Extract.NATIVE_ROOT .. "/manifest.lua")
  if not src then return false end
  local chunk = load(src, "@native/manifest.lua", "t", {})
  local man = chunk and chunk()
  if not man or (tonumber(man.native_version) or 0) < (Versions.NATIVE_VERSION or 5) then
    return false
  end
  local checked = 0
  for pairName in pairs(man.pairs or {}) do
    if not cache:exists(Extract.NATIVE_ROOT .. "/" .. pairName .. "/mids_over.idx") then
      return false
    end
    checked = checked + 1
  end
  return checked > 0
end

function Extract.metaMd5Matches(cache, md5)
  local raw = cache:read(Extract.CACHE_ROOT .. "/meta.json")
  if not raw then return false end
  local want = Versions.identitySha1(md5) or Versions.normalizeMd5(md5)
  return want ~= nil and raw:find('"md5"%s*:%s*"' .. want .. '"', 1, false) ~= nil
end

function Extract.metaMatches(cache, md5)
  local raw = cache:read(Extract.CACHE_ROOT .. "/meta.json")
  if not raw then return false end
  local want = Versions.identitySha1(md5) or Versions.normalizeMd5(md5)
  return want ~= nil
    and raw:find('"md5"%s*:%s*"' .. want .. '"', 1, false) ~= nil
    and raw:find('"cache_version"%s*:%s*' .. tostring(Versions.CACHE_VERSION)) ~= nil
end

--- Patch meta.json cache_version / native_version in place (native-only migration).
local function bump_meta_version(cache)
  local raw = cache:read(Extract.CACHE_ROOT .. "/meta.json")
  if not raw then return end
  local updated = raw:gsub(
    '"cache_version"%s*:%s*%d+',
    '"cache_version":' .. tostring(Versions.CACHE_VERSION))
  if updated:find('"native_version"%s*:') then
    updated = updated:gsub(
      '"native_version"%s*:%s*%d+',
      '"native_version":' .. tostring(Versions.NATIVE_VERSION or 1))
  else
    updated = updated:gsub(
      '"cache_version"%s*:%s*%d+',
      '%0,"native_version":' .. tostring(Versions.NATIVE_VERSION or 1))
  end
  cache:write(Extract.CACHE_ROOT .. "/meta.json", updated)
end

--- Stable map pack order: outdoors first, then interiors.
-- Include Kanto starter + Pewter (Running Shoes / Brock) with Island 1.
local MAP_ORDER = {
  "SEVII_ONE_ISLAND",
  "SEVII_ONE_ISLAND_KINDLE_ROAD",
  "SEVII_ONE_ISLAND_TREASURE_BEACH",
  "SEVII_ONE_ISLAND_POKECENTER",
  "SEVII_ONE_ISLAND_POKECENTER_2F",
  "SEVII_ONE_ISLAND_HARBOR",
  "SEVII_ONE_ISLAND_HOUSE1",
  "SEVII_ONE_ISLAND_HOUSE2",
  "FR_PALLET_TOWN",
  "FR_ROUTE_1",
  "FR_VIRIDIAN_CITY",
  "FR_ROUTE_2",
  "FR_PLAYERS_HOUSE_1F",
  "FR_PLAYERS_HOUSE_2F",
  "FR_RIVALS_HOUSE",
  "FR_OAKS_LAB",
  "FR_PEWTER_CITY",
  "FR_PEWTER_CITY_GYM",
}

function Extract.run(imports, cache, progressCb)
  local importId, info = Extract.findImport(imports)
  if not importId then
    return false, "no FireRed/LeafGreen optional import installed"
  end
  local version, verr = Versions.lookup(info.md5)
  if not version then return false, verr end

  if Extract.cacheReady(cache) and Extract.metaMd5Matches(cache, info.md5) then
    if Extract.metaMatches(cache, info.md5) and Extract.nativeReady(cache) then
      return true, { skipped = true, md5 = info.md5 }
    end
  end

  progress(progressCb, 0, "open_rom", 0, 1)
  local rom, rerr = Rom.open(imports, importId)
  if not rom then return false, rerr end

  -- Full gMapGroups census -> CacheFS. Seeds only affect pack order (front).
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(rom, version))
  local mapOrder, byEngine = MapCatalog.allOrder(census, MAP_ORDER)
  MapCatalog.registerOrder(rom, version, mapOrder, byEngine)
  rom:clearCache()
  progress(progressCb, 0, "census", #mapOrder, #mapOrder)

  -- Collect which pairs registered maps need, load each once.
  local needed = {}
  for _, mapId in ipairs(mapOrder) do
    local spec = Versions.MAPS[mapId]
    needed[(spec and spec.pair) or "sevii_outdoor"] = true
  end
  local pairNames = {}
  for name in pairs(needed) do pairNames[#pairNames + 1] = name end
  table.sort(pairNames)

  progress(progressCb, 1, "tilesets", 0, #pairNames)
  local bundles = {}
  for i, pairName in ipairs(pairNames) do
    progress(progressCb, 1, "tilesets", i - 1, #pairNames)
    local okLoad, bundleOrErr = pcall(Tileset.loadPair, rom, version, pairName)
    if okLoad and bundleOrErr then
      bundles[pairName] = bundleOrErr
    else
      print("[extract] skip tileset pair " .. tostring(pairName) .. ": " .. tostring(bundleOrErr))
    end
  end
  rom:clearCache()

  progress(progressCb, 2, "maps", 0, 1)
  local Maps = require("src.import.gba.maps")
  local grids = {}
  local dropped = {}
  for _, mapId in ipairs(mapOrder) do
    local spec = Versions.MAPS[mapId]
    local layoutName = spec and spec.layout
    local layoutSpec = layoutName and version.layouts and version.layouts[layoutName]
    if layoutSpec and bundles[spec.pair] then
      local grid = Maps.loadGrid(rom, layoutSpec)
      grid.map_id = mapId
      grid.kind = spec.kind
      grid.pair = spec.pair
      grid.environment = spec.environment
      grids[mapId] = pad_even(grid)
    elseif spec then
      dropped[#dropped + 1] = mapId
      print("[extract] drop map " .. tostring(mapId) .. ": "
        .. (not layoutSpec and "missing layout spec" or "missing tileset pair "
           .. tostring(spec.pair)))
    end
  end
  if #dropped > 0 then
    return false, "dropped " .. #dropped .. " map(s): " .. table.concat(dropped, ",")
  end
  local borders = {}
  for _, mapId in ipairs(mapOrder) do
    if grids[mapId] then
      borders[mapId] = Maps.loadBorder(rom, version, mapId)
    end
  end
  require("src.import.gba.alt_layouts").build(rom, version, grids, borders, pad_even)
  local extractedScripts = require("src.import.gba.extract_scripts").extractFromRom(rom, version)
  local scriptMids = script_mids_by_pair(extractedScripts, grids)
  rom:clearCache()

  local midsByPair = unique_mids_by_pair(grids, scriptMids)
  local totalMids = 0
  for _, list in pairs(midsByPair) do totalMids = totalMids + #list end

  -- Build midIndex dictionary without 2bpp quantize
  local midIndex = {}
  for _, pairName in ipairs(pairNames) do
    midIndex[pairName] = {}
    local pairMids = midsByPair[pairName] or {}
    for _, mid in ipairs(pairMids) do
      local behavior = (Tileset.behaviorOf and Tileset.behaviorOf(bundles[pairName], mid)) or 0
      local coll = (Collision.fromCell and Collision.fromCell(mid, 0, behavior, "outdoor")) or 0
      midIndex[pairName][mid] = {
        tiles = { 0, 0, 0, 0 },
        coll = coll,
        behavior = behavior,
        category = "misc",
      }
    end
  end

  local miL = { "return {\n" }
  for _, pairName in ipairs(pairNames) do
    miL[#miL + 1] = ("  [%q] = {\n"):format(pairName)
    for _, mid in ipairs(midsByPair[pairName] or {}) do
      local info2 = midIndex[pairName][mid]
      miL[#miL + 1] = ("    [%d] = { tiles = {%s}, coll = %d, behavior = %d, category = %q },\n"):format(
        mid,
        table.concat(info2.tiles, ","),
        info2.coll,
        info2.behavior,
        info2.category
      )
    end
    miL[#miL + 1] = "  },\n"
  end
  miL[#miL + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/mid_index.lua", table.concat(miL))

  write_json(cache, Extract.CACHE_ROOT .. "/meta.json", {
    cache_version = Versions.CACHE_VERSION,
    native_version = Versions.NATIVE_VERSION or 5,
    md5 = Versions.normalizeMd5(info.md5),
    version_id = version.id,
    import_id = importId,
    mid_count = totalMids,
    tile_count = 0,
    block_count = 0,
    imageWidth = 0,
    imageHeight = 0,
    tilesPerRow = 16,
    maps = mapOrder,
  })

  local warps = Versions.WARPS
  local connections = {}
  do
    local ExtractMapEvents = require("src.import.gba.extract_map_events")
    local romW = assert(Rom.open(imports, importId))
    local romWarps, romConns = ExtractMapEvents.extractWarpsAndConnections(romW, version)
    romW:clearCache()
    warps = {}
    for _, mapId in ipairs(mapOrder) do
      local list = romWarps[mapId]
      if list and #list > 0 then
        for _, w in ipairs(list) do
          if not w.destMap and w.mapGroup ~= nil then
            w.destMap = MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
          end
        end
        warps[mapId] = list
      else
        warps[mapId] = Versions.WARPS[mapId] or {}
      end
    end
    connections = {}
    for _, mapId in ipairs(mapOrder) do
      local conns = romConns[mapId] or {}
      local fixed = {}
      for dir, c in pairs(conns) do
        local dest = c.map
        if (not dest or dest:match("^g%d+_m%d+$")) and c.mapGroup ~= nil then
          dest = MapCatalog.mapIdFor(c.mapGroup, c.mapNum) or dest
        elseif dest then
          dest = MapCatalog.resolve(dest) or dest
        end
        if dest then
          fixed[dir] = { map = dest, offset = tonumber(c.offset) or 0 }
        end
      end
      connections[mapId] = fixed
    end
  end

  -- Native FRLG mid atlas + pret palettes (game3 live path).
  progress(progressCb, 6, "native_pack", 0, 1)
  local NativePack = require("src.import.gba.native_pack")
  local warpCells = {}
  for mapId, list in pairs(warps or {}) do
    local set = {}
    for _, w in ipairs(list) do
      local x, y = tonumber(w.x), tonumber(w.y)
      if x and y then set[NativePack.warpKey(x, y)] = true end
    end
    warpCells[mapId] = set
  end
  NativePack.writeExtract(
    cache, Extract.CACHE_ROOT, bundles, grids, borders, pairNames, midIndex,
    Tileset.behaviorOf, Collision.fromCell, scriptMids, warpCells)

  -- OW sprites + tileset anims + encounters + audio + chrome from ROM
  do
    local rom2 = assert(Rom.open(imports, importId))
    require("src.import.gba.help_extract").writeExtract(rom2, cache)
    require("src.import.gba.quest_log_extract").writeExtract(rom2, cache)
    require("src.import.gba.object_interactions_extract").writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local midLists = {}
    for _, pairName in ipairs(pairNames) do
      midLists[pairName] = NativePack.collectMidsForPair(grids, borders, pairName, scriptMids)
    end
    local AnimPack = require("src.import.gba.tileset_anim_pack")
    AnimPack.writeExtract(rom2, cache, Extract.CACHE_ROOT, bundles, midLists, version)
    local OwExtract = require("src.import.gba.ow_extract")
    OwExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local EncExtract = require("src.import.gba.encounters_extract")
    EncExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local FxExtract = require("src.import.gba.field_effect_extract")
    FxExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    do
      local MartsExtract = require("src.import.gba.marts_extract")
      local okM, detailM = pcall(MartsExtract.run, rom2, cache, {
        cacheRoot = Extract.CACHE_ROOT,
      })
      if okM and detailM then
        print(string.format("[marts] %d lists → %s",
          detailM.listCount or 0, tostring(detailM.path)))
      end
    end
    for _, name in ipairs({ "online_ui_extract", "berry_crush_extract", "dodrio_extract", "pokemon_jump_extract" }) do
      require("src.import.gba." .. name).run(rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
    end
    rom2:clearCache()
  end

  local wl = { "return {\n" }
  for _, mapId in ipairs(mapOrder) do
    local list = warps[mapId] or {}
    wl[#wl + 1] = ("  %s = {\n"):format(mapId)
    for _, w in ipairs(list) do
      local dest = w.destMap or MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
      if dest then
        wl[#wl + 1] = ("    { x = %d, y = %d, destMap = %q, destWarp = %d },\n"):format(
          w.x, w.y, dest, w.destWarp or 1
        )
      else
        wl[#wl + 1] = ("    { x = %d, y = %d, destMap = nil, destWarp = %d, mapGroup = %d, mapNum = %d },\n"):format(
          w.x, w.y, w.destWarp or 1, w.mapGroup or 0, w.mapNum or 0
        )
      end
    end
    wl[#wl + 1] = "  },\n"
  end
  wl[#wl + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/warps.lua", table.concat(wl))

  local cl = { "return {\n" }
  for _, mapId in ipairs(mapOrder) do
    local conns = connections[mapId] or {}
    cl[#cl + 1] = ("  %s = {\n"):format(mapId)
    local dirs = {}
    for dir in pairs(conns) do dirs[#dirs + 1] = dir end
    table.sort(dirs)
    for _, dir in ipairs(dirs) do
      local c = conns[dir]
      cl[#cl + 1] = ("    %s = { map = %q, offset = %d },\n"):format(
        dir, c.map, tonumber(c.offset) or 0)
    end
    cl[#cl + 1] = "  },\n"
  end
  cl[#cl + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/connections.lua", table.concat(cl))

  -- game3 scripts/events/text/movements from ROM MapEvents + BFS
  local ExtractScripts = require("src.import.gba.extract_scripts")
  rom = assert(Rom.open(imports, importId))
  local scriptBundle = ExtractScripts.writeBundleFromRom(
    rom, cache, Extract.CACHE_ROOT, version, extractedScripts)

  -- Extract full trainer parties, AI flags, dialogs, and sprites
  do
    local TrainerExtract = require("src.import.gba.trainer_extract")
    TrainerExtract.run(rom, cache, {
      cacheRoot = Extract.CACHE_ROOT,
      scripts = scriptBundle and scriptBundle.scripts,
      text = scriptBundle and scriptBundle.text,
    })
  end

  -- Normalized map_tree mirror
  do
    local MapTreeExtract = require("src.import.gba.map_tree_extract")
    local okTree, treeDetail = MapTreeExtract.run(rom, cache, {
      version = version,
      root = Extract.CACHE_ROOT .. "/map_tree",
    })
    if not okTree then
      print("[extract] map_tree warn: " .. tostring(treeDetail))
    end
  end
  rom:clearCache()

  progress(progressCb, 7, "done", 1, 1)
  bundles = nil
  collectgarbage()
  return true, {
    md5 = info.md5,
    tile_count = 0,
    block_count = 0,
    mid_count = totalMids,
    map_count = #mapOrder,
    script_count = scriptBundle and scriptBundle.scriptCount,
    script_seeds = scriptBundle and scriptBundle.seedCount,
  }
end

function Extract.runNativeOnly(imports, cache, progressCb)
  return Extract.run(imports, cache, progressCb)
end

--- Legacy 2bpp quantize extract preserved as dormant code below:
local function _dormant_quantize_run(imports, cache, progressCb)
  local importId, info = Extract.findImport(imports)
  if not importId then
    return false, "no FireRed/LeafGreen optional import installed"
  end
  local version, verr = Versions.lookup(info.md5)
  if not version then return false, verr end

  if Extract.cacheReady(cache) and Extract.metaMd5Matches(cache, info.md5) then
    if Extract.metaMatches(cache, info.md5) and Extract.nativeReady(cache) then
      return true, { skipped = true, md5 = info.md5 }
    end
    -- Same ROM + same cache_version, but native pack incomplete → rebuild native
    -- only. cache_version bumps (map catalog / warp closure) always full-extract.
    local raw = cache:read(Extract.CACHE_ROOT .. "/meta.json") or ""
    local sameVer = raw:find('"cache_version"%s*:%s*' .. tostring(Versions.CACHE_VERSION)) ~= nil
    if sameVer then
      return Extract.runNativeOnly(imports, cache, progressCb)
    end
  end

  progress(progressCb, 0, "open_rom", 0, 1)
  local rom, rerr = Rom.open(imports, importId)
  if not rom then return false, rerr end

  -- Full gMapGroups census → CacheFS. Seeds only affect pack order (front).
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(rom, version))
  local mapOrder, byEngine = MapCatalog.allOrder(census, MAP_ORDER)
  MapCatalog.registerOrder(rom, version, mapOrder, byEngine)
  rom:clearCache()
  progress(progressCb, 0, "census", #mapOrder, #mapOrder)

  -- Collect which pairs registered maps need, load each once.
  local needed = {}
  for _, mapId in ipairs(mapOrder) do
    local spec = Versions.MAPS[mapId]
    needed[(spec and spec.pair) or "sevii_outdoor"] = true
  end
  local pairNames = {}
  for name in pairs(needed) do pairNames[#pairNames + 1] = name end
  table.sort(pairNames)

  progress(progressCb, 1, "tilesets", 0, #pairNames)
  local bundles = {}
  for i, pairName in ipairs(pairNames) do
    progress(progressCb, 1, "tilesets", i - 1, #pairNames)
    local okLoad, bundleOrErr = pcall(Tileset.loadPair, rom, version, pairName)
    if okLoad and bundleOrErr then
      bundles[pairName] = bundleOrErr
    else
      print("[extract] skip tileset pair " .. tostring(pairName) .. ": " .. tostring(bundleOrErr))
    end
  end
  rom:clearCache()

  progress(progressCb, 2, "maps", 0, 1)
  -- Load every registered map grid from ROM MapLayout pointers.
  local grids = {}
  do
    local Maps = require("src.import.gba.maps")
    for _, mapId in ipairs(mapOrder) do
      local spec = Versions.MAPS[mapId]
      local layoutName = spec and spec.layout
      local layoutSpec = layoutName and version.layouts and version.layouts[layoutName]
      if layoutSpec and bundles[spec.pair] then
        local grid = Maps.loadGrid(rom, layoutSpec)
        grid.map_id = mapId
        grid.kind = spec.kind
        grid.pair = spec.pair
        grid.environment = spec.environment
        grids[mapId] = grid
      end
    end
  end
  local borders = {}
  do
    local Maps = require("src.import.gba.maps")
    for _, mapId in ipairs(mapOrder) do
      if grids[mapId] then
        borders[mapId] = Maps.loadBorder(rom, version, mapId)
      end
    end
  end
  rom:clearCache()
  for mapId, grid in pairs(grids) do
    local spec = Versions.MAPS[mapId]
    grid.pair = spec and spec.pair or "sevii_outdoor"
    grid.environment = spec and spec.environment
    grids[mapId] = pad_even(grid)
  end

  local midsByPair = unique_mids_by_pair(grids)
  local totalMids = 0
  for _, list in pairs(midsByPair) do totalMids = totalMids + #list end

  progress(progressCb, 3, "quantize", 0, totalMids)
  local sheet = Quantize.Sheet()
  local voidTidForBorder = nil
  local PAIR_TILESET = Versions.PAIR_TILESET or {
    sevii_outdoor = "SEVII_OUTDOOR",
    network = "SEVII_NETWORK",
    house = "SEVII_HOUSE",
    harbor = "SEVII_HARBOR",
  }
  -- Per-pair palette banks (swap on warp via mapDef.tileset → specialTilesets).
  local banks = {} -- [tilesetId] = { [slot] = ramp }
  local tilePalettesByTileset = {} -- [tilesetId] = { [tileId+1] = localSlot }
  local tilesetIdList = {}
  do
    local seen = {}
    for _, tid in pairs(PAIR_TILESET) do
      if not seen[tid] then
        seen[tid] = true
        tilesetIdList[#tilesetIdList + 1] = tid
        banks[tid] = {}
        tilePalettesByTileset[tid] = {}
      end
    end
    table.sort(tilesetIdList)
  end
  local specialPals = PaletteRules.specialPalettes()
  local outdoorTs = PAIR_TILESET.sevii_outdoor or "SEVII_OUTDOOR"
  -- Outdoor LAB trial (codebook + shared-Y + MRF) kept behind this flag, but left
  -- off: it oscillates between flat trees / sand checkers and cliff+water banding.
  -- Indoor pairs stay on LAB; outdoor uses fixed special pals + Y thresholds.
  local USE_LAB_FOR_OUTDOOR = false
  -- Outdoor-only spatial MRF after unary assign (only when USE_LAB_FOR_OUTDOOR).
  local USE_OUTDOOR_MRF = true
  if not USE_LAB_FOR_OUTDOOR then
    local nSeed = math.max(8, PaletteRules.TREE_CLIFF_SLOT or 8)
    for i = 1, nSeed do
      if specialPals[i] then
        banks[outdoorTs][i] = specialPals[i]
      end
    end
  end

  -- [tilesetId][slot] = outdoor terrain family string (or nil)
  local bankSlotFamily = {}

  local function place_in_bank(tilesetId, ramp)
    local bank = banks[tilesetId]
    local bestS, bestD = nil, 1e18
    for s, existing in pairs(bank) do
      local d = QuantizeLab.rampDistance(ramp, existing)
      if d < bestD then bestS, bestD = s, d end
    end
    if bestS and bestD < QuantizeLab.NEAR_DUPE_EPS then
      return bestS
    end
    local nextSlot = 1
    while bank[nextSlot] do nextSlot = nextSlot + 1 end
    if nextSlot > Quantize.MAX_PALETTE_SLOTS then
      return bestS or 1
    end
    bank[nextSlot] = ramp
    return nextSlot
  end

  -- Outdoor: tighter near-dupe + never reuse a slot owned by another terrain family.
  local function place_in_bank_outdoor(tilesetId, ramp, primaryFam)
    local bank = banks[tilesetId]
    local famBySlot = bankSlotFamily[tilesetId]
    if not famBySlot then
      famBySlot = {}
      bankSlotFamily[tilesetId] = famBySlot
    end
    local eps = QuantizeLab.OUTDOOR_NEAR_DUPE_EPS
    local bestS, bestD = nil, 1e18
    for s, existing in pairs(bank) do
      local existingFam = famBySlot[s]
      if not primaryFam or not existingFam or existingFam == primaryFam then
        local d = QuantizeLab.rampDistance(ramp, existing)
        if d < bestD then bestS, bestD = s, d end
      end
    end
    if bestS and bestD < eps then
      if primaryFam and not famBySlot[bestS] then
        famBySlot[bestS] = primaryFam
      end
      return bestS
    end
    local nextSlot = 1
    while bank[nextSlot] do nextSlot = nextSlot + 1 end
    if nextSlot > Quantize.MAX_PALETTE_SLOTS then
      return bestS or 1
    end
    bank[nextSlot] = ramp
    if primaryFam then famBySlot[nextSlot] = primaryFam end
    return nextSlot
  end

  -- Like place_in_bank, but only merges with ramps whose shade 3 is already
  -- true black (door-mat chamfer tiles). Never absorb into gray/coral darks.
  local function place_black_locked(tilesetId, ramp)
    local bank = banks[tilesetId]
    local bestS, bestD = nil, 1e18
    for s, existing in pairs(bank) do
      local d4 = existing[4]
      if d4 and d4[1] == 0 and d4[2] == 0 and d4[3] == 0 then
        local d = QuantizeLab.rampDistance(ramp, existing)
        if d < bestD then bestS, bestD = s, d end
      end
    end
    if bestS and bestD < QuantizeLab.NEAR_DUPE_EPS then
      return bestS
    end
    local nextSlot = 1
    while bank[nextSlot] do nextSlot = nextSlot + 1 end
    if nextSlot > Quantize.MAX_PALETTE_SLOTS then
      return bestS or place_in_bank(tilesetId, ramp)
    end
    bank[nextSlot] = {
      { ramp[1][1], ramp[1][2], ramp[1][3] },
      { ramp[2][1], ramp[2][2], ramp[2][3] },
      { ramp[3][1], ramp[3][2], ramp[3][3] },
      { 0, 0, 0 },
    }
    return nextSlot
  end

  local function ensure_black_slot(tilesetId)
    local bank = banks[tilesetId]
    for s, existing in pairs(bank) do
      local ok = true
      for i = 1, 4 do
        local c = existing[i]
        if not c or c[1] ~= 0 or c[2] ~= 0 or c[3] ~= 0 then
          ok = false
          break
        end
      end
      if ok then return s end
    end
    return place_in_bank(tilesetId, {
      { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 },
    })
  end

  local function record_tile_pal(tilesetId, tileId, slot)
    tilePalettesByTileset[tilesetId][tileId + 1] = slot
  end

  -- Outdoor bpp dedupe must not share one tile id across incompatible ramps
  -- (e.g. cliff brown + roof magenta → purple cliffs when the last writer wins).
  local OUTDOOR_SLOT_FAMILY = {
    [1] = "water", [2] = "grass", [3] = "sand", [4] = "cliff",
    [5] = "front", [6] = "roof", [7] = "metal", [8] = "tree",
    [9] = "tree_cliff",
  }
  local function outdoor_intern(sheet, bpp, tilesetId, slot)
    local tid = Quantize.intern(sheet, bpp)
    local existing = tilePalettesByTileset[tilesetId][tid + 1]
    if existing and existing ~= slot then
      local fa = OUTDOOR_SLOT_FAMILY[existing]
      local fb = OUTDOOR_SLOT_FAMILY[slot]
      if fa and fb and fa ~= fb then
        tid = Quantize.internUnique(sheet, bpp)
      end
    end
    record_tile_pal(tilesetId, tid, slot)
    return tid
  end

  local midIndex = {}
  local done = 0

  -- ── Tier 1: MAP ──────────────────────────────────────────────────────────
  -- Classify every cell; remember per-mid base category and per-quad neighbour
  -- votes from the maps where that mid appears. Context only — not a force.
  local midBase = {} -- [pair][mid] = { cat, env, kind, coll, beh }
  local quadVotes = {} -- [pair][mid][q+1] = { [category]=n }
  -- Which side of a mid faces which map neighbour (cell is the mid's origin).
  local QUAD_NEIGH = {
    { { -1, 0 }, { 0, -1 } }, -- TL → W, N
    { { 1, 0 }, { 0, -1 } },  -- TR → E, N
    { { -1, 0 }, { 0, 1 } },  -- BL → W, S
    { { 1, 0 }, { 0, 1 } },   -- BR → E, S
  }

  local cellCat = {} -- [mapId] = flat array of categories
  for mapId, grid in pairs(grids) do
    local pairName = grid.pair or "sevii_outdoor"
    local bundle = bundles[pairName]
    local cats = {}
    midBase[pairName] = midBase[pairName] or {}
    for i, cell in ipairs(grid.cells) do
      local beh = Tileset.behaviorOf(bundle, cell.mid)
      local cByte, cCat = Collision.fromCell(cell.mid, cell.coll, beh, grid.kind)
      cats[i] = cCat
      if not midBase[pairName][cell.mid] then
        midBase[pairName][cell.mid] = {
          cat = cCat,
          env = grid.environment,
          kind = grid.kind,
          coll = cByte,
          behavior = beh,
        }
      end
    end
    cellCat[mapId] = cats
  end

  for mapId, grid in pairs(grids) do
    local pairName = grid.pair or "sevii_outdoor"
    local cats = cellCat[mapId]
    quadVotes[pairName] = quadVotes[pairName] or {}
    local w, h = grid.width, grid.height
    for cy = 0, h - 1 do
      for cx = 0, w - 1 do
        local idx = cy * w + cx + 1
        local mid = grid.cells[idx].mid
        quadVotes[pairName][mid] = quadVotes[pairName][mid] or { {}, {}, {}, {} }
        for q = 0, 3 do
          for _, d in ipairs(QUAD_NEIGH[q + 1]) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 0 and ny >= 0 and nx < w and ny < h then
              local ncat = cats[ny * w + nx + 1]
              local votes = quadVotes[pairName][mid][q + 1]
              votes[ncat] = (votes[ncat] or 0) + 1
            end
          end
        end
      end
    end
  end

  -- ── Tier 2 + 3: METATILE then TILE ───────────────────────────────────────
  -- Indoor: top-down material codebook → quad assign → 2bpp bake.
  local pending = {} -- outdoor items for Y-threshold pass
  local indoorPending = {} -- { pair, mid, coll, beh, category, quads = {buf,pal}×4 }
  local slotYsByPair = {}

  for _, pairName in ipairs(pairNames) do
    local bundle = bundles[pairName]
    local list = midsByPair[pairName] or {}
    slotYsByPair[pairName] = slotYsByPair[pairName] or {}
    local slotYs = slotYsByPair[pairName]
    for _, mid in ipairs(list) do
      done = done + 1
      if done % 16 == 0 then progress(progressCb, 3, "quantize", done, totalMids) end
      local base = midBase[pairName] and midBase[pairName][mid]
      local category = (base and base.cat) or "TOWN_PATH"
      local env = base and base.env
      local collByte = base and base.coll or 0
      local beh = base and base.behavior or Tileset.behaviorOf(bundle, mid)
      if not base then
        collByte, category = Collision.fromCell(mid, 0, beh, "town")
      end

      local buf, palBuf = Metatile.compositeBgr555(bundle, mid)
      local qVotes = (quadVotes[pairName] and quadVotes[pairName][mid]) or { {}, {}, {}, {} }
      local profile = PaletteRules.resolveProfile(pairName, env, {
        indoor = (env == "INDOOR") or (pairName ~= nil and pairName ~= "sevii_outdoor"),
      })

      if profile.indoor or USE_LAB_FOR_OUTDOOR then
        local quads = {}
        for q = 0, 3 do
          quads[q + 1] = {
            buf = Metatile.quadrant(buf, q),
            pal = Metatile.quadrant(palBuf, q),
          }
        end
        indoorPending[#indoorPending + 1] = {
          pair = pairName,
          mid = mid,
          coll = collByte,
          behavior = beh,
          category = category,
          quads = quads,
        }
      else
        -- Legacy outdoor Y-threshold / PaletteRules path (kept for rollback).
        local bottomIsRoof = false
        if PaletteRules.isBuildingCategory(category) then
          for q = 2, 3 do
            local qr, qg, qb = Quantize.meanRgb(Metatile.quadrant(buf, q))
            if profile.isRoofColor(qr, qg, qb) then
              bottomIsRoof = true
              break
            end
          end
        end
        local bOpts = {
          bottomIsRoof = bottomIsRoof,
          indoor = false,
          pairName = pairName,
          environment = env,
          profileId = profile.id,
          _profile = profile,
        }
        local quads = {}
        for q = 0, 3 do
          local quad = Metatile.quadrant(buf, q)
          local cat = category
          if not PaletteRules.isLocked(category)
            and Quantize.tileHueSpread(quad) >= Quantize.MIXED_HUE_SPREAD then
            cat = PaletteRules.ownCategory(category, qVotes[q + 1])
          end
          local mr, mg, mb = Quantize.meanRgb(quad)
          local slot = PaletteRules.slotForContext(cat, env, pairName, mr, mg, mb, q, bOpts)
          slot = PaletteRules.refineSlot(slot, cat, mr, mg, mb, q, bOpts)
          -- Tree tip/stump mixed with cliff: green+brown in one 8×8 → hybrid
          -- ramp (slot 9) + nearest-colour bake. Applies to TREE stumps and to
          -- CLIFF/BLOCKED mids that paint the tip onto the rock face.
          if (category == "TREE" or category == "CLIFF" or category == "COAST_CLIFF"
            or category == "BLOCKED")
            and PaletteRules.quadIsTreeCliffMix(quad, category) then
            slot = PaletteRules.TREE_CLIFF_SLOT
          end
          quads[q + 1] = { buf = quad, slot = slot, role = "slot_" .. tostring(slot) }
          if not PaletteRules.usesNearestRampBake(slot) then
            slotYs[slot] = slotYs[slot] or {}
            local pool = slotYs[slot]
            for i = 1, 64 do
              pool[#pool + 1] = Quantize.bgr555_to_y(quad[i] or 0)
            end
          end
        end
        pending[#pending + 1] = {
          pair = pairName,
          mid = mid,
          coll = collByte,
          behavior = beh,
          category = category,
          quads = quads,
          profileId = profile.id,
        }
      end
    end
  end

  local slotThreshByPair = {}
  for pairName, slotYs in pairs(slotYsByPair) do
    local slotThresh = {}
    for slot = 1, 8 do
      local t1, t2, t3 = Quantize.thresholdsFromYs(slotYs[slot])
      slotThresh[slot] = { t1, t2, t3 }
    end
    slotThreshByPair[pairName] = slotThresh
  end

  for _, pairName in ipairs(pairNames) do
    midIndex[pairName] = midIndex[pairName] or {}
  end
  for _, item in ipairs(pending) do
    local tiles4 = {}
    local slotThresh = slotThreshByPair[item.pair] or {}
    local tsId = PAIR_TILESET[item.pair] or outdoorTs
    for q = 1, 4 do
      local slot = item.quads[q].slot
      local bpp
      if PaletteRules.usesNearestRampBake(slot) then
        local ramp = banks[tsId][slot] or PaletteRules.RAMP[slot]
        bpp = Quantize.tileTo2bppAgainstRamp(item.quads[q].buf, ramp)
      else
        local th = slotThresh[slot] or { 0.25, 0.5, 0.75 }
        bpp = Quantize.tileTo2bpp(item.quads[q].buf, th[1], th[2], th[3])
      end
      tiles4[q] = outdoor_intern(sheet, bpp, tsId, slot)
    end
    midIndex[item.pair][item.mid] = {
      tiles = tiles4,
      coll = item.coll,
      behavior = item.behavior,
      category = item.category,
    }
  end
  pending = nil
  slotYsByPair = nil
  slotThreshByPair = nil

  -- Indoor top-down demake (per tileset pair, isolated palette bank):
  --   1) discover material ramps from that pair's FRLG palSlots
  --   2) merge ≤22 within the pair → place into that pair's bank only
  --   3) assign each quad to that pair's codebook → bake 2bpp against its ramp
  do
    local byPair = {}
    local pairOrder = {}
    local indoorQuadTotal = 0
    for _, item in ipairs(indoorPending) do
      local p = item.pair
      if not byPair[p] then
        byPair[p] = { items = {}, quads = {} }
        pairOrder[#pairOrder + 1] = p
      end
      byPair[p].items[#byPair[p].items + 1] = item
      for q = 1, 4 do
        if is_exact_black_quad(item.quads[q].buf) then
          indoorQuadTotal = indoorQuadTotal + 1 -- counted as void stamp work
        else
          byPair[p].quads[#byPair[p].quads + 1] = {
            buf = item.quads[q].buf,
            pal = item.quads[q].pal,
            pair = p,
            category = item.category,
          }
          indoorQuadTotal = indoorQuadTotal + 1
        end
      end
    end
    table.sort(pairOrder)

    if indoorQuadTotal > 0 then
      progress(progressCb, 3, "quantize_indoor", 0, indoorQuadTotal)
    end

    local codebooks = {} -- [pair] = { { ramp, slot, pair, frlgSlot }, ... }
    if #pairOrder > 0 then
      progress(progressCb, 3, "quantize_merge", 0, #pairOrder)
    end
    for pi, pairName in ipairs(pairOrder) do
      local tsId = PAIR_TILESET[pairName] or pairName
      local group = byPair[pairName]
      local isOutdoor = pairName == "sevii_outdoor"
      local entries = QuantizeLab.discoverMaterialEntries(group.quads, {
        -- Hue-split skip is decided per-bucket for TREE; do not blanket outdoor.
        forbidHueSplit = false,
      })
      local mergeOpts = nil
      if isOutdoor then
        mergeOpts = {
          nearDupeEps = QuantizeLab.OUTDOOR_NEAR_DUPE_EPS,
          guardTerrainFamilies = true,
        }
      end
      local merged, oldToMerged = QuantizeLab.mergeRampsToBudget(
        entries, QuantizeLab.MAX_SLOTS, mergeOpts)

      local mergedMeta = {}
      for mi = 1, #merged do
        mergedMeta[mi] = { frlgVotes = {}, frlgSlot = 0, categories = {} }
      end
      for ei, mi in pairs(oldToMerged) do
        local e = entries[ei]
        local meta = mergedMeta[mi]
        if e and meta then
          local fk = e.frlgSlot or 0
          meta.frlgVotes[fk] = (meta.frlgVotes[fk] or 0) + (e.count or 1)
          if e.categories then
            for c, n in pairs(e.categories) do
              meta.categories[c] = (meta.categories[c] or 0) + n
            end
          end
        end
      end
      for mi = 1, #merged do
        local meta = mergedMeta[mi]
        local bestF, bestFN = 0, -1
        for fk, n in pairs(meta.frlgVotes) do
          if n > bestFN or (n == bestFN and fk < bestF) then
            bestF, bestFN = fk, n
          end
        end
        meta.frlgSlot = bestF
        meta.primaryCategory = QuantizeLab.primaryCategory(meta.categories)
      end

      local codebook = {}
      for mi = 1, #merged do
        local meta = mergedMeta[mi]
        local fam = meta.primaryCategory
          and QuantizeLab.terrainFamily(meta.primaryCategory)
        local slot
        if isOutdoor then
          slot = place_in_bank_outdoor(tsId, merged[mi], fam)
        else
          slot = place_in_bank(tsId, merged[mi])
        end
        codebook[#codebook + 1] = {
          ramp = banks[tsId][slot] or merged[mi],
          slot = slot,
          pair = pairName,
          frlgSlot = (meta and meta.frlgSlot) or 0,
          categories = meta and meta.categories or nil,
          primaryCategory = meta and meta.primaryCategory or nil,
          mergedId = mi,
        }
      end
      codebooks[pairName] = codebook
      progress(progressCb, 3, "quantize_merge", pi, #pairOrder)
    end

    local indoorMids = {}
    local indoorQuadDone = 0

    local function outdoor_assign_opts(item, q)
      local buf = item.quads[q].buf
      local pal = item.quads[q].pal
      local cat = item.category or "TOWN_PATH"
      local opts = {
        preferFrlgSlot = QuantizeLab.majorityPalSlot(pal),
        frlgBias = QuantizeLab.OUTDOOR_FRLG_BIAS,
        itemCategory = cat,
        crossCatPenalty = QuantizeLab.OUTDOOR_CROSS_CAT_PENALTY,
      }
      -- Hard scope only for locked terrain families (still allows many water/sand
      -- materials tagged with that family — does not force a single ramp).
      if QuantizeLab.terrainFamily(cat) then
        opts.requireCategory = cat
      end
      if Quantize.tileHueSpread(buf) >= Quantize.MIXED_HUE_SPREAD then
        local qVotes = (quadVotes[item.pair] and quadVotes[item.pair][item.mid]
          and quadVotes[item.pair][item.mid][q]) or {}
        local own = PaletteRules.ownCategory(cat, qVotes)
        local semSlot = PaletteRules.SLOT[own]
        local seed = semSlot and PaletteRules.RAMP[semSlot]
        if seed then
          opts.preferRamp = seed
          opts.rampBias = QuantizeLab.OUTDOOR_RAMP_BIAS
        end
      end
      return opts
    end

    -- ── Indoor pairs: unary LAB bake (unchanged) ───────────────────────────
    for _, pairName in ipairs(pairOrder) do
      if pairName ~= "sevii_outdoor" then
        local tsId = PAIR_TILESET[pairName] or pairName
        local codebook = codebooks[pairName] or {}
        for _, item in ipairs(byPair[pairName].items) do
          local key = item.pair .. ":" .. tostring(item.mid)
          local bucket = indoorMids[key]
          if not bucket then
            bucket = {
              pair = item.pair,
              mid = item.mid,
              coll = item.coll,
              behavior = item.behavior,
              category = item.category,
              tiles = {},
            }
            indoorMids[key] = bucket
          end
          local voidQuads = {}
          for q = 1, 4 do
            if is_exact_black_quad(item.quads[q].buf) then
              voidQuads[q] = true
              bucket.tiles[q] = 0
              indoorQuadDone = indoorQuadDone + 1
            else
              local buf = item.quads[q].buf
              local pal = item.quads[q].pal
              local ramp, sheetSlot = QuantizeLab.resolveQuadRamp(buf, pal, codebook, pairName)
              if not sheetSlot then
                ramp = banks[tsId][place_in_bank(tsId, ramp)] or ramp
              else
                ramp = banks[tsId][sheetSlot] or ramp
              end
              local bpp, usedRamp, lockedBlack = QuantizeLab.bakeQuad(buf, ramp)
              local slot
              if lockedBlack then
                slot = place_black_locked(tsId, usedRamp)
              elseif sheetSlot then
                slot = sheetSlot
              else
                slot = place_in_bank(tsId, usedRamp)
              end
              local tid = Quantize.intern(sheet, bpp)
              record_tile_pal(tsId, tid, slot)
              bucket.tiles[q] = tid
              indoorQuadDone = indoorQuadDone + 1
            end
            if indoorQuadTotal > 0
              and (indoorQuadDone % 8 == 0 or indoorQuadDone == indoorQuadTotal) then
              progress(progressCb, 3, "quantize_indoor", indoorQuadDone, indoorQuadTotal)
            end
          end
          if next(voidQuads) then bucket.voidQuads = voidQuads end
        end
      end
    end

    -- ── Outdoor LAB continuity: assign → cohere → optional MRF → shared Y bake
    if byPair.sevii_outdoor then
      local pairName = "sevii_outdoor"
      local tsId = PAIR_TILESET[pairName] or pairName
      local codebook = codebooks[pairName] or {}
      local assigns = {} -- [mid] = { [q]=codebookIndex|false void }
      local voidByMid = {}

      for _, item in ipairs(byPair[pairName].items) do
        local mid = item.mid
        assigns[mid] = assigns[mid] or {}
        voidByMid[mid] = voidByMid[mid] or {}
        for q = 1, 4 do
          if is_exact_black_quad(item.quads[q].buf) then
            assigns[mid][q] = false
            voidByMid[mid][q] = true
          else
            local opts = outdoor_assign_opts(item, q)
            local ci = QuantizeLab.bestCodebookIndex(
              item.quads[q].buf, item.quads[q].pal, codebook, pairName, opts)
            assigns[mid][q] = ci
          end
          indoorQuadDone = indoorQuadDone + 1
          if indoorQuadTotal > 0
            and (indoorQuadDone % 8 == 0 or indoorQuadDone == indoorQuadTotal) then
            progress(progressCb, 3, "quantize_indoor", indoorQuadDone, indoorQuadTotal)
          end
        end
        -- Mid 3–1 codebook snap (void quads stay nil-equivalent via false)
        local idx = {
          assigns[mid][1] ~= false and assigns[mid][1] or nil,
          assigns[mid][2] ~= false and assigns[mid][2] or nil,
          assigns[mid][3] ~= false and assigns[mid][3] or nil,
          assigns[mid][4] ~= false and assigns[mid][4] or nil,
        }
        idx = Quantize.cohereCodebookIndices(idx)
        for q = 1, 4 do
          if assigns[mid][q] ~= false and idx[q] then
            assigns[mid][q] = idx[q]
          end
        end
      end

      if USE_OUTDOOR_MRF and #codebook > 0 then
        local midItem = {}
        for _, item in ipairs(byPair[pairName].items) do
          midItem[item.mid] = item
        end
        local placements = {}
        local ord = 0
        for mapId, grid in pairs(grids) do
          if grid.pair == pairName then
            for cy = 0, grid.height - 1 do
              for cx = 0, grid.width - 1 do
                local cell = grid.cells[cy * grid.width + cx + 1]
                local mid = cell.mid
                local a = assigns[mid]
                local item = midItem[mid]
                if a and item then
                  for q = 1, 4 do
                    if a[q] ~= false then
                      ord = ord + 1
                      local ox = (q == 2 or q == 4) and 1 or 0
                      local oy = (q >= 3) and 1 or 0
                      placements[#placements + 1] = {
                        buf = item.quads[q].buf,
                        pal = item.quads[q].pal,
                        mid = mid, q = q,
                        mapId = mapId,
                        gx = cx * 2 + ox, gy = cy * 2 + oy,
                        ord = ord,
                        category = item.category,
                      }
                    end
                  end
                end
              end
            end
          end
        end
        if #placements > 0 then
          local labels = QuantizeMrf.assignPlacements(placements, codebook, {
            pair = pairName,
            enabled = true,
          })
          local maj = QuantizeMrf.majorityPerMid(placements, labels)
          for mid, qs in pairs(maj) do
            assigns[mid] = assigns[mid] or {}
            for q, ci in pairs(qs) do
              if assigns[mid][q] ~= false then
                assigns[mid][q] = ci
              end
            end
          end
        end
      end

      -- TREE only: force one foliage material so tip/base mids share a ramp.
      -- Water/sand/cliff keep multiple materials (foam, rocks, highlights).
      do
        local midItem = {}
        for _, item in ipairs(byPair[pairName].items) do
          midItem[item.mid] = item
        end
        local treeCi = QuantizeLab.primaryCodebookForCategory(codebook, "TREE")
        if treeCi then
          for mid, a in pairs(assigns) do
            local item = midItem[mid]
            if item and item.category == "TREE" then
              for q = 1, 4 do
                if a[q] ~= false then a[q] = treeCi end
              end
            end
          end
        end
      end

      -- Pool BT.709 Y per assigned codebook index → shared shade cuts
      local matYs = {}
      for _, item in ipairs(byPair[pairName].items) do
        local a = assigns[item.mid]
        for q = 1, 4 do
          local ci = a and a[q]
          if ci and ci ~= false then
            matYs[ci] = matYs[ci] or {}
            local pool = matYs[ci]
            local buf = item.quads[q].buf
            for i = 1, 64 do
              pool[#pool + 1] = Quantize.bgr555_to_y(buf[i] or 0)
            end
          end
        end
      end
      local matThresh = {}
      for ci, ys in pairs(matYs) do
        local t1, t2, t3 = Quantize.thresholdsFromYs(ys)
        matThresh[ci] = { t1, t2, t3 }
      end

      for _, item in ipairs(byPair[pairName].items) do
        local key = item.pair .. ":" .. tostring(item.mid)
        local bucket = indoorMids[key]
        if not bucket then
          bucket = {
            pair = item.pair,
            mid = item.mid,
            coll = item.coll,
            behavior = item.behavior,
            category = item.category,
            tiles = {},
          }
          indoorMids[key] = bucket
        end
        local voidQuads = voidByMid[item.mid] or {}
        local a = assigns[item.mid] or {}
        for q = 1, 4 do
          if voidQuads[q] or a[q] == false then
            voidQuads[q] = true
            bucket.tiles[q] = 0
          else
            local ci = a[q] or 1
            local entry = codebook[ci] or codebook[1]
            local slot = entry and entry.slot or 1
            local th = matThresh[ci] or { 0.25, 0.5, 0.75 }
            local bpp = Quantize.tileTo2bpp(item.quads[q].buf, th[1], th[2], th[3])
            local tid = Quantize.intern(sheet, bpp)
            record_tile_pal(tsId, tid, slot)
            bucket.tiles[q] = tid
          end
        end
        if next(voidQuads) then bucket.voidQuads = voidQuads end
      end
    end

    for _, bucket in pairs(indoorMids) do
      midIndex[bucket.pair] = midIndex[bucket.pair] or {}
      midIndex[bucket.pair][bucket.mid] = {
        tiles = bucket.tiles,
        coll = bucket.coll,
        behavior = bucket.behavior,
        category = bucket.category,
        voidQuads = bucket.voidQuads,
      }
    end

    -- Stamp unique void tile onto every exact-black quad (and ensure mid 0).
    do
      local voidTid = Quantize.internUnique(sheet, QuantizeLab.solidBlackBpp())
      for _, tsId in ipairs(tilesetIdList) do
        record_tile_pal(tsId, voidTid, ensure_black_slot(tsId))
      end
      for pairName, indexForPair in pairs(midIndex) do
        local tsId = PAIR_TILESET[pairName] or pairName
        if banks[tsId] then
          for mid, info in pairs(indexForPair) do
            local tiles = { info.tiles[1], info.tiles[2], info.tiles[3], info.tiles[4] }
            local vq = info.voidQuads
            if mid == 0 then
              tiles = { voidTid, voidTid, voidTid, voidTid }
            elseif vq then
              for q = 1, 4 do
                if vq[q] then tiles[q] = voidTid end
              end
            end
            indexForPair[mid] = {
              tiles = tiles,
              coll = info.coll or 1,
              behavior = info.behavior or 0,
              category = info.category or "BLOCKED",
            }
          end
          if not indexForPair[0] then
            indexForPair[0] = {
              tiles = { voidTid, voidTid, voidTid, voidTid },
              coll = 1,
              behavior = 0,
              category = "BLOCKED",
            }
          end
        end
      end
      voidTidForBorder = voidTid
    end
  end
  indoorPending = nil

  progress(progressCb, 4, "pack_layouts", 0, #mapOrder)
  local blocks = {}
  local blockByKey = {}
  local nextBlock = 0
  local layouts = {}

  local function intern_block(tiles16, coll4)
    local key = table.concat(tiles16, ",") .. ";" .. table.concat(coll4, ",")
    local id = blockByKey[key]
    if id then return id end
    id = nextBlock
    nextBlock = nextBlock + 1
    blockByKey[key] = id
    blocks[id] = { tiles = tiles16, collision = coll4 }
    return id
  end

  for mi, mapId in ipairs(mapOrder) do
    progress(progressCb, 4, "pack_layouts", mi - 1, #mapOrder)
    local grid = grids[mapId]
    if grid then
      local pairName = grid.pair or "sevii_outdoor"
      local indexForPair = midIndex[pairName] or {}
      local bundle = bundles[pairName]
      local bw = math.floor(grid.width / 2)
      local bh = math.floor(grid.height / 2)
      local packed = {}
      for by = 0, bh - 1 do
        for bx = 0, bw - 1 do
          local function cell(cx, cy)
            return grid.cells[cy * grid.width + cx + 1]
          end
          local c00 = cell(bx * 2, by * 2)
          local c10 = cell(bx * 2 + 1, by * 2)
          local c01 = cell(bx * 2, by * 2 + 1)
          local c11 = cell(bx * 2 + 1, by * 2 + 1)
          local function infoFor(c)
            local beh = Tileset.behaviorOf(bundle, c.mid)
            local collByte, cat = Collision.fromCell(c.mid, c.coll, beh, grid.kind)
            local mi2 = indexForPair[c.mid]
            if mi2 then
              return { tiles = mi2.tiles, coll = collByte, category = cat }
            end
            return { tiles = { 0, 0, 0, 0 }, coll = collByte }
          end
          local i00, i10, i01, i11 = infoFor(c00), infoFor(c10), infoFor(c01), infoFor(c11)
          local tiles16 = {}
          tiles16[1] = i00.tiles[1]; tiles16[2] = i00.tiles[2]
          tiles16[5] = i00.tiles[3]; tiles16[6] = i00.tiles[4]
          tiles16[3] = i10.tiles[1]; tiles16[4] = i10.tiles[2]
          tiles16[7] = i10.tiles[3]; tiles16[8] = i10.tiles[4]
          tiles16[9] = i01.tiles[1]; tiles16[10] = i01.tiles[2]
          tiles16[13] = i01.tiles[3]; tiles16[14] = i01.tiles[4]
          tiles16[11] = i11.tiles[1]; tiles16[12] = i11.tiles[2]
          tiles16[15] = i11.tiles[3]; tiles16[16] = i11.tiles[4]
          local coll4 = { i00.coll, i10.coll, i01.coll, i11.coll }
          packed[#packed + 1] = intern_block(tiles16, coll4)
        end
      end
      local spec = Versions.MAPS[mapId]
      local env = spec and spec.environment
      layouts[mapId] = {
        width = bw,
        height = bh,
        blocks = packed,
        environment = env,
        pair = pairName,
        borderBlock = 0, -- indoor overridden after void block is interned
      }
    end
  end

  -- Beyond-edge border uses the same unique void tile as pad mid 0.
  if voidTidForBorder then
    local tiles16 = {}
    for i = 1, 16 do tiles16[i] = voidTidForBorder end
    local voidId = intern_block(tiles16, { 1, 1, 1, 1 })
    for _, layout in pairs(layouts) do
      if layout.environment == "INDOOR" then
        layout.borderBlock = voidId
      end
    end
  end

  progress(progressCb, 5, "write_cache", 0, 1)
  local raw, width, height = Quantize.sheetToRaw(sheet, 16)
  cache:write(Extract.CACHE_ROOT .. "/tileset.2bpp", raw)

  -- Fill each tileset's tilePalettes to full atlas length. Unused tile ids get
  -- slot 1 as a don't-care placeholder (this tileset never draws those tiles).
  local function filled_tile_pals(tsId)
    local src = tilePalettesByTileset[tsId] or {}
    local out = {}
    for i = 1, sheet.count do
      out[i] = src[i] or 1
    end
    return out
  end
  local function bank_to_list(bank)
    local n = 0
    for s in pairs(bank or {}) do
      if type(s) == "number" and s > n then n = s end
    end
    if n < 1 then n = 1 end
    local list = {}
    for i = 1, n do
      list[i] = bank[i] or {
        { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 },
      }
    end
    return list
  end

  local specialByTs = {}
  local tilePalByTs = {}
  for _, tsId in ipairs(tilesetIdList) do
    specialByTs[tsId] = bank_to_list(banks[tsId])
    tilePalByTs[tsId] = filled_tile_pals(tsId)
  end
  -- Legacy aliases for older readers: outdoor bank.
  local specialPalsOut = specialByTs[outdoorTs] or bank_to_list(banks[outdoorTs])
  local tilePalettes = tilePalByTs[outdoorTs] or filled_tile_pals(outdoorTs)

  write_json(cache, Extract.CACHE_ROOT .. "/meta.json", {
    cache_version = Versions.CACHE_VERSION,
    native_version = Versions.NATIVE_VERSION or 1,
    md5 = Versions.normalizeMd5(info.md5),
    version_id = version.id,
    import_id = importId,
    mid_count = totalMids,
    tile_count = sheet.count,
    block_count = nextBlock,
    imageWidth = width,
    imageHeight = height,
    tilesPerRow = 16,
    maps = mapOrder,
  })

  local function rgb_lua(c)
    return ("{%d,%d,%d}"):format(c[1] or 0, c[2] or 0, c[3] or 0)
  end
  local function ramp_lua(ramp)
    return ("{%s,%s,%s,%s}"):format(
      rgb_lua(ramp[1]), rgb_lua(ramp[2]), rgb_lua(ramp[3]), rgb_lua(ramp[4])
    )
  end
  local function write_ramp_table(lines, list)
    for i = 1, #list do
      lines[#lines + 1] = ("    [%d] = %s,\n"):format(i, ramp_lua(list[i]))
    end
  end
  local function write_int_array(lines, list)
    for i = 1, #list do
      lines[#lines + 1] = ("    %d,\n"):format(list[i])
    end
  end

  local metaLines = {
    "return {\n",
    ("  imageWidth = %d,\n"):format(width),
    ("  imageHeight = %d,\n"):format(height),
    "  tilesPerRow = 16,\n",
    ("  tileCount = %d,\n"):format(sheet.count),
    "  tilePalettes = {\n",
  }
  write_int_array(metaLines, tilePalettes)
  metaLines[#metaLines + 1] = "  },\n"
  metaLines[#metaLines + 1] = "  specialPalettes = {\n"
  write_ramp_table(metaLines, specialPalsOut)
  metaLines[#metaLines + 1] = "  },\n"
  metaLines[#metaLines + 1] = "  tilePalettesByTileset = {\n"
  for _, tsId in ipairs(tilesetIdList) do
    metaLines[#metaLines + 1] = ("    [%q] = {\n"):format(tsId)
    write_int_array(metaLines, tilePalByTs[tsId])
    metaLines[#metaLines + 1] = "    },\n"
  end
  metaLines[#metaLines + 1] = "  },\n"
  metaLines[#metaLines + 1] = "  specialPalettesByTileset = {\n"
  for _, tsId in ipairs(tilesetIdList) do
    metaLines[#metaLines + 1] = ("    [%q] = {\n"):format(tsId)
    write_ramp_table(metaLines, specialByTs[tsId])
    metaLines[#metaLines + 1] = "    },\n"
  end
  metaLines[#metaLines + 1] = "  },\n"
  metaLines[#metaLines + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/tileset_meta.lua", table.concat(metaLines))

  local bl = { "return {\n" }
  for id = 0, nextBlock - 1 do
    local b = blocks[id]
    bl[#bl + 1] = ("  [%d] = { tiles = {%s}, collision = {%s} },\n"):format(
      id,
      table.concat(b.tiles, ","),
      table.concat(b.collision, ",")
    )
  end
  bl[#bl + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/blocks.lua", table.concat(bl))

  local miL = { "return {\n" }
  for _, pairName in ipairs(pairNames) do
    miL[#miL + 1] = ("  [%q] = {\n"):format(pairName)
    for _, mid in ipairs(midsByPair[pairName] or {}) do
      local info2 = midIndex[pairName][mid]
      miL[#miL + 1] = ("    [%d] = { tiles = {%s}, coll = %d, behavior = %d, category = %q },\n"):format(
        mid,
        table.concat(info2.tiles, ","),
        info2.coll,
        info2.behavior,
        info2.category
      )
    end
    miL[#miL + 1] = "  },\n"
  end
  miL[#miL + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/mid_index.lua", table.concat(miL))

  -- Native FRLG mid atlas + pret palettes (game3 live path). Bundles still live.
  progress(progressCb, 6, "native_pack", 0, 1)
  local NativePack = require("src.import.gba.native_pack")
  NativePack.writeExtract(
    cache, Extract.CACHE_ROOT, bundles, grids, borders, pairNames, midIndex,
    Tileset.behaviorOf, Collision.fromCell)

  -- OW sprites + tileset anims from ROM (re-open; pages were cleared after tileset load).
  do
    local rom2 = assert(Rom.open(imports, importId))
    require("src.import.gba.help_extract").writeExtract(rom2, cache)
    require("src.import.gba.quest_log_extract").writeExtract(rom2, cache)
    require("src.import.gba.object_interactions_extract").writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local midLists = {}
    local NativePack = require("src.import.gba.native_pack")
    for _, pairName in ipairs(pairNames) do
      midLists[pairName] = NativePack.collectMidsForPair(grids, borders, pairName)
    end
    local AnimPack = require("src.import.gba.tileset_anim_pack")
    AnimPack.writeExtract(rom2, cache, Extract.CACHE_ROOT, bundles, midLists, version)
    local OwExtract = require("src.import.gba.ow_extract")
    OwExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local EncExtract = require("src.import.gba.encounters_extract")
    EncExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local FxExtract = require("src.import.gba.field_effect_extract")
    FxExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    do
      local MartsExtract = require("src.import.gba.marts_extract")
      local okM, detailM = pcall(MartsExtract.run, rom2, cache, {
        cacheRoot = Extract.CACHE_ROOT,
      })
      if okM and detailM then
        print(string.format("[marts] %d lists → %s",
          detailM.listCount or 0, tostring(detailM.path)))
      end
    end
    do
      local BagChromeExtract = require("src.import.gba.bag_chrome_extract")
      local okB, detailB = pcall(BagChromeExtract.run, rom2, cache, {
        cacheRoot = Extract.CACHE_ROOT,
      })
      if okB and detailB then
        print(string.format("[bag_chrome] icons=%d → %s",
          detailB.iconsBaked or 0, tostring(detailB.root)))
      elseif not okB then
        print("[bag_chrome] warn: " .. tostring(detailB))
      end
    end
    do
      local AnimExtract = require("src.import.gba.battle_anim_extract")
      local animCache = {
        write = function(_, rel, bytes)
          local path = rel
          if not path:match("^data/") then path = Extract.CACHE_ROOT .. "/" .. path end
          return cache:write(path, bytes)
        end,
        exists = function(_, rel) return (cache.exists and cache:exists(rel)) or false end,
        read   = function(_, rel) return (cache.read and cache:read(rel)) or nil end,
      }
      pcall(AnimExtract.run, rom2, animCache, { cacheRoot = Extract.CACHE_ROOT, force = true })
    end
    do
      local BattleAiExtract = require("src.import.gba.battle_ai_extract")
      BattleAiExtract.run(rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
    end
    do
      local TextChromeExtract = require("src.import.gba.text_chrome_extract")
      local okTc, errTc = pcall(TextChromeExtract.run, rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      if not okTc then print("[text_chrome] warn: " .. tostring(errTc)) end
      local MapSectionsExtract = require("src.import.gba.map_sections_extract")
      local okMs, errMs = pcall(MapSectionsExtract.run, rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      if not okMs then print("[map_sections] warn: " .. tostring(errMs)) end
      require("src.import.gba.easy_chat_extract").run(rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      local MapPreviewExtract = require("src.import.gba.map_preview_extract")
      local okMp, errMp = pcall(MapPreviewExtract.run, rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      if not okMp then print("[map_preview] warn: " .. tostring(errMp)) end
      local RegionMapExtract = require("src.import.gba.region_map_extract")
      local okRm, errRm = pcall(RegionMapExtract.run, rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      if not okRm then print("[region_map] warn: " .. tostring(errRm)) end
      local HealLocationsExtract = require("src.import.gba.heal_locations_extract")
      local okHl, errHl = pcall(HealLocationsExtract.run, rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
      if not okHl then print("[heal_locations] warn: " .. tostring(errHl)) end
    end
    rom2:clearCache()
  end

  for mapId, layout in pairs(layouts) do
    local lines = {
      "return {\n",
      ("  width = %d,\n"):format(layout.width),
      ("  height = %d,\n"):format(layout.height),
      ("  environment = %q,\n"):format(layout.environment or "INDOOR"),
      ("  pair = %q,\n"):format(layout.pair or "sevii_outdoor"),
      ("  borderBlock = %d,\n"):format(layout.borderBlock or 0),
      "  blocks = {\n",
    }
    for _, bid in ipairs(layout.blocks) do
      lines[#lines + 1] = ("    %d,\n"):format(bid)
    end
    lines[#lines + 1] = "  },\n}\n"
    cache:write(Extract.CACHE_ROOT .. "/layouts/" .. mapId .. ".lua", table.concat(lines))
  end

  local warps = Versions.WARPS
  local connections = {}
  do
    local ExtractMapEvents = require("src.import.gba.extract_map_events")
    local romW = assert(Rom.open(imports, importId))
    local romWarps, romConns = ExtractMapEvents.extractWarpsAndConnections(romW, version)
    romW:clearCache()
    -- Prefer ROM warps when present; fall back to hand table per-map.
    warps = {}
    for _, mapId in ipairs(mapOrder) do
      local list = romWarps[mapId]
      if list and #list > 0 then
        -- Resolve any leftover nil destMap via census (group:num → FR_*).
        for _, w in ipairs(list) do
          if not w.destMap and w.mapGroup ~= nil then
            w.destMap = MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
          end
        end
        warps[mapId] = list
      else
        warps[mapId] = Versions.WARPS[mapId] or {}
      end
    end
    connections = {}
    for _, mapId in ipairs(mapOrder) do
      local conns = romConns[mapId] or {}
      local fixed = {}
      for dir, c in pairs(conns) do
        local dest = c.map
        if (not dest or dest:match("^g%d+_m%d+$")) and c.mapGroup ~= nil then
          dest = MapCatalog.mapIdFor(c.mapGroup, c.mapNum) or dest
        elseif dest then
          dest = MapCatalog.resolve(dest) or dest
        end
        if dest then
          fixed[dir] = { map = dest, offset = tonumber(c.offset) or 0 }
        end
      end
      connections[mapId] = fixed
    end
  end

  local wl = { "return {\n" }
  for _, mapId in ipairs(mapOrder) do
    local list = warps[mapId] or {}
    wl[#wl + 1] = ("  %s = {\n"):format(mapId)
    for _, w in ipairs(list) do
      local dest = w.destMap or MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
      if dest then
        wl[#wl + 1] = ("    { x = %d, y = %d, destMap = %q, destWarp = %d },\n"):format(
          w.x, w.y, dest, w.destWarp or 1
        )
      else
        -- Keep ROM index slot even if dest group is outside this extract.
        wl[#wl + 1] = ("    { x = %d, y = %d, destMap = nil, destWarp = %d, mapGroup = %d, mapNum = %d },\n"):format(
          w.x, w.y, w.destWarp or 1, w.mapGroup or 0, w.mapNum or 0
        )
      end
    end
    wl[#wl + 1] = "  },\n"
  end
  wl[#wl + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/warps.lua", table.concat(wl))

  local cl = { "return {\n" }
  for _, mapId in ipairs(mapOrder) do
    local conns = connections[mapId] or {}
    cl[#cl + 1] = ("  %s = {\n"):format(mapId)
    local dirs = {}
    for dir in pairs(conns) do dirs[#dirs + 1] = dir end
    table.sort(dirs)
    for _, dir in ipairs(dirs) do
      local c = conns[dir]
      cl[#cl + 1] = ("    %s = { map = %q, offset = %d },\n"):format(
        dir, c.map, tonumber(c.offset) or 0)
    end
    cl[#cl + 1] = "  },\n"
  end
  cl[#cl + 1] = "}\n"
  cache:write(Extract.CACHE_ROOT .. "/connections.lua", table.concat(cl))

  -- game3 scripts/events/text/movements from ROM MapEvents + BFS (primary).
  local ExtractScripts = require("src.import.gba.extract_scripts")
  rom = assert(Rom.open(imports, importId))
  local scriptBundle = ExtractScripts.writeBundleFromRom(rom, cache, Extract.CACHE_ROOT, version)

  -- Extract full trainer parties, AI flags, dialogs, and sprites
  do
    local TrainerExtract = require("src.import.gba.trainer_extract")
    TrainerExtract.run(rom, cache, {
      cacheRoot = Extract.CACHE_ROOT,
      scripts = scriptBundle and scriptBundle.scripts,
      text = scriptBundle and scriptBundle.text,
    })
  end

  -- Normalized map_tree mirror (header/events/grid per slot + shared tilesets).
  do
    local MapTreeExtract = require("src.import.gba.map_tree_extract")
    local okTree, treeDetail = MapTreeExtract.run(rom, cache, {
      version = version,
      root = Extract.CACHE_ROOT .. "/map_tree",
    })
    if not okTree then
      print("[extract] map_tree warn: " .. tostring(treeDetail))
    end
  end
  rom:clearCache()

  progress(progressCb, 7, "done", 1, 1)
  bundles = nil
  collectgarbage()
  return true, {
    md5 = info.md5,
    tile_count = sheet.count,
    block_count = nextBlock,
    mid_count = totalMids,
    map_count = #mapOrder,
    script_count = scriptBundle and scriptBundle.scriptCount,
    script_seeds = scriptBundle and scriptBundle.seedCount,
  }
end

--- Rebuild native blobs only (demake cache already valid). Seconds, not minutes.
-- Uses full gMapGroups census → CacheFS (same pair set as Extract.run).
function Extract.runNativeOnly(imports, cache, progressCb)
  local importId, info = Extract.findImport(imports)
  if not importId then
    return false, "no FireRed/LeafGreen optional import installed"
  end
  local version, verr = Versions.lookup(info.md5)
  if not version then return false, verr end
  if not Extract.cacheReady(cache) or not Extract.metaMd5Matches(cache, info.md5) then
    return false, "demake cache missing — run full extract first"
  end

  progress(progressCb, 0, "open_rom", 0, 1)
  local rom, rerr = Rom.open(imports, importId)
  if not rom then return false, rerr end

  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  MapCatalog.rebuildIndex()
  local census = assert(MapTree.walk(rom, version))
  local mapOrder, byEngine = MapCatalog.allOrder(census, MAP_ORDER)
  MapCatalog.registerOrder(rom, version, mapOrder, byEngine)
  rom:clearCache()

  local needed = {}
  for _, mapId in ipairs(mapOrder) do
    local spec = Versions.MAPS[mapId]
    needed[(spec and spec.pair) or "sevii_outdoor"] = true
  end
  local pairNames = {}
  for name in pairs(needed) do pairNames[#pairNames + 1] = name end
  table.sort(pairNames)

  progress(progressCb, 1, "tilesets", 0, #pairNames)
  local bundles = {}
  for i, pairName in ipairs(pairNames) do
    progress(progressCb, 1, "tilesets", i - 1, #pairNames)
    local okLoad, bundleOrErr = pcall(Tileset.loadPair, rom, version, pairName)
    if okLoad and bundleOrErr then
      bundles[pairName] = bundleOrErr
    else
      print("[extract] skip tileset pair " .. tostring(pairName) .. ": " .. tostring(bundleOrErr))
    end
  end
  rom:clearCache()

  progress(progressCb, 2, "maps", 0, 1)
  local grids = {}
  do
    for _, mapId in ipairs(mapOrder) do
      local spec = Versions.MAPS[mapId]
      local layoutName = spec and spec.layout
      local layoutSpec = layoutName and version.layouts and version.layouts[layoutName]
      if layoutSpec and bundles[spec.pair] then
        local grid = Maps.loadGrid(rom, layoutSpec)
        grid.map_id = mapId
        grid.kind = spec.kind
        grid.pair = spec.pair
        grid.environment = spec.environment
        grids[mapId] = pad_even(grid)
      end
    end
  end
  local borders = {}
  for _, mapId in ipairs(mapOrder) do
    if grids[mapId] then
      borders[mapId] = Maps.loadBorder(rom, version, mapId)
    end
  end
  require("src.import.gba.alt_layouts").build(rom, version, grids, borders, pad_even)
  local scriptMids = script_mids_by_pair(
    require("src.import.gba.extract_scripts").extractFromRom(rom, version), grids)
  rom:clearCache()

  local midIndex = {}
  do
    local src = cache:read(Extract.CACHE_ROOT .. "/mid_index.lua")
    if src then
      local chunk = load(src, "@mid_index.lua", "t", {})
      if chunk then midIndex = chunk() or {} end
    end
  end

  progress(progressCb, 6, "native_pack", 0, 1)
  local NativePack = require("src.import.gba.native_pack")
  NativePack.writeExtract(
    cache, Extract.CACHE_ROOT, bundles, grids, borders, pairNames, midIndex,
    Tileset.behaviorOf, Collision.fromCell, scriptMids)

  do
    local rom2 = assert(Rom.open(imports, importId))
    require("src.import.gba.help_extract").writeExtract(rom2, cache)
    require("src.import.gba.quest_log_extract").writeExtract(rom2, cache)
    require("src.import.gba.object_interactions_extract").writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local midLists = {}
    for _, pairName in ipairs(pairNames) do
      midLists[pairName] = NativePack.collectMidsForPair(grids, borders, pairName, scriptMids)
    end
    local AnimPack = require("src.import.gba.tileset_anim_pack")
    AnimPack.writeExtract(rom2, cache, Extract.CACHE_ROOT, bundles, midLists, version)
    local OwExtract = require("src.import.gba.ow_extract")
    OwExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local EncExtract = require("src.import.gba.encounters_extract")
    EncExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    local FxExtract = require("src.import.gba.field_effect_extract")
    FxExtract.writeExtract(rom2, cache, Extract.CACHE_ROOT, version)
    do
      local MartsExtract = require("src.import.gba.marts_extract")
      local okM, detailM = pcall(MartsExtract.run, rom2, cache, {
        cacheRoot = Extract.CACHE_ROOT,
      })
      if okM and detailM then
        print(string.format("[marts] %d lists → %s",
          detailM.listCount or 0, tostring(detailM.path)))
      end
    end
    do
      local BagChromeExtract = require("src.import.gba.bag_chrome_extract")
      local okB, detailB = pcall(BagChromeExtract.run, rom2, cache, {
        cacheRoot = Extract.CACHE_ROOT,
      })
      if okB and detailB then
        print(string.format("[bag_chrome] icons=%d → %s",
          detailB.iconsBaked or 0, tostring(detailB.root)))
      elseif not okB then
        print("[bag_chrome] warn: " .. tostring(detailB))
      end
    end
    do
      local AnimExtract = require("src.import.gba.battle_anim_extract")
      local animCache = {
        write = function(_, rel, bytes)
          local path = rel
          if not path:match("^data/") then
            path = Extract.CACHE_ROOT .. "/" .. path
          end
          return cache:write(path, bytes)
        end,
        exists = function(_, rel) return (cache.exists and cache:exists(rel)) or false end,
        read   = function(_, rel) return (cache.read and cache:read(rel)) or nil end,
      }
      pcall(AnimExtract.run, rom2, animCache, { cacheRoot = Extract.CACHE_ROOT, force = true })
    end
    do
      local BattleAiExtract = require("src.import.gba.battle_ai_extract")
      BattleAiExtract.run(rom2, cache, { cacheRoot = Extract.CACHE_ROOT })
    end
    rom2:clearCache()
  end
  bump_meta_version(cache)

  progress(progressCb, 7, "done", 1, 1)
  bundles = nil
  collectgarbage()
  return true, { native_only = true, md5 = info.md5, pairs = #pairNames, maps = #mapOrder }
end

return Extract

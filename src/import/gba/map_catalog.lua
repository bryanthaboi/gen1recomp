-- Map identity + tileset-pair discovery from the gMapGroups / MapTree census.
-- Engine ids are FR_* (existing aliases) or FR_<PRET_NAME> derived from pret.

local Versions = require("src.import.gba.versions")

local MapCatalog = {}

local _byGroupNum = nil -- ["g:n"] = engineId
local _byPret = nil -- pretName = engineId
local _aliases = nil -- anyName = engineId
local _slotByEngine = nil -- engineId = "g_n"

local function pret_to_engine(pret)
  if type(pret) ~= "string" or pret == "" then return nil end
  -- Existing hand aliases first.
  local hand = Versions.PRET_TO_FR and Versions.PRET_TO_FR[pret]
  if hand then return hand end
  -- Route1 → Route_1, Route22 → Route_22
  local s = pret:gsub("Route(%d+)", "Route_%1")
  -- PalletTown → FR_PALLET_TOWN; ViridianCity_PokemonCenter_1F → FR_VIRIDIAN_CITY_POKEMON_CENTER_1F
  -- Only split lower→Upper (not digit→Upper) so "1F" stays "1F".
  s = s:gsub("(%l)(%u)", "%1_%2")
  s = s:gsub("-", "_"):upper()
  s = s:gsub("_+", "_")
  return "FR_" .. s
end

function MapCatalog.pretToEngine(pret)
  return pret_to_engine(pret)
end

--- Build (group,num) → engineId and pret → engineId tables from pret groups + hand FR map.
function MapCatalog.rebuildIndex()
  local groups = require("src.import.gba.map_groups_firered")
  _byGroupNum, _byPret, _aliases, _slotByEngine = {}, {}, {}, {}
  local function bindSlot(engine, key)
    if engine and key and _slotByEngine[engine] == nil then
      _slotByEngine[engine] = (key:gsub(":", "_"))
    end
  end
  for gi, info in pairs(groups.groups or {}) do
    for mi, pret in ipairs(info.maps or {}) do
      local num = mi - 1
      local key = string.format("%d:%d", gi, num)
      local engine = Versions.FRLG_MAP_TO_FR[key]
        or Versions.FRLG_MAP_TO_SEVII[key]
        or pret_to_engine(pret)
      _byGroupNum[key] = engine
      _byPret[pret] = engine
      _aliases[engine] = engine
      _aliases[pret] = engine
      _aliases[key] = engine
      bindSlot(engine, key)
    end
  end
  -- Ensure hand FR_* keys alias to themselves.
  for key, engine in pairs(Versions.FRLG_MAP_TO_FR or {}) do
    _aliases[engine] = engine
    _byGroupNum[key] = engine
    bindSlot(engine, key)
  end
  for key, engine in pairs(Versions.FRLG_MAP_TO_SEVII or {}) do
    _aliases[engine] = engine
    _byGroupNum[key] = engine
    bindSlot(engine, key)
  end
  return _byGroupNum
end

local function ensure_index()
  if not _byGroupNum then MapCatalog.rebuildIndex() end
end

function MapCatalog.mapIdFor(group, num)
  ensure_index()
  local key = string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)
  return _byGroupNum[key]
end

function MapCatalog.slotKeyFor(mapId)
  ensure_index()
  if type(mapId) ~= "string" then return nil end
  return _slotByEngine[mapId] or _slotByEngine[_aliases[mapId] or ""]
end

function MapCatalog.resolve(nameOrGroup, num)
  ensure_index()
  if num ~= nil then
    return MapCatalog.mapIdFor(nameOrGroup, num)
  end
  if type(nameOrGroup) ~= "string" then return nil end
  return _aliases[nameOrGroup] or nameOrGroup
end

function MapCatalog.isKnown(mapId)
  ensure_index()
  return _aliases[mapId] ~= nil
end

--- Match a tileset struct's tiles pointer to Versions.TILESETS name.
function MapCatalog.tilesetNameForPtr(rom, tilesetPtr)
  if not tilesetPtr or tilesetPtr == 0 then return nil end
  local MapTree = require("src.import.gba.map_tree")
  local ts = MapTree.parseTileset(rom, tilesetPtr)
  if not ts then return nil end
  local tilesOff = rom:ptrOffset(ts.tilesPtr)
  if not tilesOff then return nil end
  for name, spec in pairs(Versions.TILESETS or {}) do
    if spec.tiles == tilesOff then
      return name, ts
    end
  end
  -- Auto-register unknown tileset under a stable id.
  local id = string.format("rom_%08x", tilesetPtr)
  if not Versions.TILESETS[id] then
    local palsOff = rom:ptrOffset(ts.palettesPtr)
    local tilesBytes = nil
    if not ts.compressed and palsOff and tilesOff and palsOff > tilesOff then
      tilesBytes = palsOff - tilesOff
    end
    Versions.TILESETS[id] = {
      compressed = ts.compressed,
      secondary = ts.secondary,
      tiles = tilesOff,
      palettes = palsOff,
      metatiles = rom:ptrOffset(ts.metatilesPtr),
      attributes = rom:ptrOffset(ts.attributesPtr),
      metatile_bytes = ts.metatile_bytes,
      attr_bytes = ts.attr_bytes,
      palette_count = ts.palette_count or 16,
      tiles_bytes = tilesBytes,
    }
  end
  return id, ts
end

function MapCatalog.pairForLayout(rom, layout)
  local priName = MapCatalog.tilesetNameForPtr(rom, layout.primaryTilesetPtr)
  local secName = MapCatalog.tilesetNameForPtr(rom, layout.secondaryTilesetPtr)
  if not priName or not secName then return nil end
  -- Prefer an existing named pair.
  for pairName, pair in pairs(Versions.TILESET_PAIRS or {}) do
    if pair.primary == priName and pair.secondary == secName then
      return pairName
    end
  end
  local pairName = priName .. "__" .. secName
  if not Versions.TILESET_PAIRS[pairName] then
    Versions.TILESET_PAIRS[pairName] = { primary = priName, secondary = secName }
  end
  if not Versions.PAIR_TILESET[pairName] then
    Versions.PAIR_TILESET[pairName] = ("FR_%s"):format(pairName:upper():gsub("[^A-Z0-9]+", "_"))
  end
  return pairName
end

local function map_type_kind(mapType)
  -- pret map_types.h: 1 town, 2 city, 3 route, 4 underground, 8 indoor, …
  mapType = tonumber(mapType) or 0
  if mapType == 3 then return "route", "ROUTE" end
  if mapType == 8 or mapType == 4 or mapType == 9 then return "indoor", "INDOOR" end
  return "town", "TOWN"
end

--- Register one census entry into Versions.MAPS / MAP_HEADERS / version.layouts.
function MapCatalog.registerEntry(rom, version, entry)
  if not entry or not entry.layout or not entry.header then return nil end
  local engineId = MapCatalog.resolve(entry.group, entry.num)
    or MapCatalog.pretToEngine(entry.pretName)
    or entry.id
  local pair = MapCatalog.pairForLayout(rom, entry.layout)
  if not pair then return nil end
  local kind, env = map_type_kind(entry.header.mapType)
  local layoutName = entry.pretName or engineId
  local mapOff = rom:ptrOffset(entry.layout.mapPtr)
  Versions.MAPS[engineId] = {
    layout = layoutName,
    width = entry.layout.width,
    height = entry.layout.height,
    kind = kind,
    environment = env,
    pair = pair,
    pretName = entry.pretName,
    group = entry.group,
    num = entry.num,
  }
  Versions.MAP_HEADERS[engineId] = entry.header.headerOff
  version.layouts = version.layouts or {}
  if mapOff then
    version.layouts[layoutName] = {
      offset = mapOff,
      width = entry.layout.width,
      height = entry.layout.height,
    }
  end
  version.map_headers = Versions.MAP_HEADERS
  version.tilesets = Versions.TILESETS
  version.tileset_pairs = Versions.TILESET_PAIRS
  return engineId
end

--- Every map in the census, stable group/num order. Seeds (if given) are
-- sorted to the front so early-game maps pack first; nothing is filtered.
function MapCatalog.allOrder(census, seedIds)
  ensure_index()
  local byEngine = {}
  for _, entry in ipairs(census.maps or {}) do
    local id = MapCatalog.resolve(entry.group, entry.num)
      or MapCatalog.pretToEngine(entry.pretName)
    if id then
      entry.engineId = id
      byEngine[id] = entry
    end
  end

  local order, seen = {}, {}
  local function add(id)
    if not id or seen[id] or not byEngine[id] then return end
    seen[id] = true
    order[#order + 1] = id
  end
  for _, id in ipairs(seedIds or {}) do add(id) end

  -- Remainder in census walk order (already group/num sorted by MapTree.walk).
  for _, entry in ipairs(census.maps or {}) do
    add(entry.engineId)
  end
  return order, byEngine
end

--- Expand a seed map-id list through warps + connections until fixpoint.
-- opts.maxDepth: hop limit from seeds (default 2 — outdoor + interiors + one more).
-- Prefer MapCatalog.allOrder for a full-ROM extract into CacheFS.
function MapCatalog.expandOrder(seedIds, census, opts)
  opts = opts or {}
  local maxDepth = tonumber(opts.maxDepth) or 2
  ensure_index()
  local byEngine = {}
  for _, entry in ipairs(census.maps or {}) do
    local id = MapCatalog.resolve(entry.group, entry.num)
      or MapCatalog.pretToEngine(entry.pretName)
    if id then
      entry.engineId = id
      byEngine[id] = entry
    end
  end

  local order, seen, depthOf = {}, {}, {}
  -- Skip cable-club / link maps unless explicitly seeded (uncompressed special tilesets).
  local skipGroups = opts.skipGroups or { [0] = true }
  local function add(id, depth)
    if not id or not byEngine[id] then return end
    if seen[id] then return end
    if depth > maxDepth then return end
    local entry = byEngine[id]
    if depth > 0 and entry and skipGroups[entry.group] then return end
    seen[id] = true
    depthOf[id] = depth
    order[#order + 1] = id
  end
  for _, id in ipairs(seedIds) do add(id, 0) end

  local i = 1
  while i <= #order do
    local id = order[i]
    local entry = byEngine[id]
    local depth = depthOf[id] or 0
    if entry then
      for _, w in ipairs((entry.events and entry.events.warps) or {}) do
        local dest = w.destMap and MapCatalog.resolve(w.destMap)
          or MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
        add(dest, depth + 1)
      end
      for _, c in pairs(entry.connections or {}) do
        local dest = c.map and MapCatalog.resolve(c.map)
          or MapCatalog.mapIdFor(c.mapGroup, c.mapNum)
        add(dest, depth + 1)
      end
    end
    i = i + 1
  end
  return order, byEngine
end

--- Register every map in `order` and rewrite census warp/connection dests to engine ids.
function MapCatalog.registerOrder(rom, version, order, byEngine)
  local registered = {}
  for _, id in ipairs(order) do
    local entry = byEngine[id]
    if entry then
      local eng = MapCatalog.registerEntry(rom, version, entry)
      if eng then registered[#registered + 1] = eng end
    end
  end
  -- Normalize warp destMap on entries we registered (for warps.lua writer).
  for _, id in ipairs(registered) do
    local entry = byEngine[id]
    if entry and entry.events and entry.events.warps then
      for _, w in ipairs(entry.events.warps) do
        w.destMap = MapCatalog.mapIdFor(w.mapGroup, w.mapNum)
          or (w.destMap and MapCatalog.resolve(w.destMap))
          or w.destMap
      end
    end
    if entry and entry.connections then
      for dir, c in pairs(entry.connections) do
        c.map = MapCatalog.mapIdFor(c.mapGroup, c.mapNum)
          or (c.map and MapCatalog.resolve(c.map))
          or c.map
      end
    end
  end
  return registered
end

return MapCatalog

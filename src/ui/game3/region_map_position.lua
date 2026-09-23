local MapCatalog = require("src.import.gba.map_catalog")
local MapSectionsExtract = require("src.import.gba.map_sections_extract")

local Position = {}

-- include/constants/map_types.h:8
local MAP_TYPE_UNDERGROUND = 4
local MAP_TYPE_UNKNOWN = 7
local MAP_TYPE_INDOOR = 8
local MAP_TYPE_SECRET_BASE = 9

local function sec(id)
  return assert(MapSectionsExtract.ID_TO_SECTION[id], id)
end

local function slotNum(mapId)
  local slot = assert(MapCatalog.slotKeyFor(mapId), "no map slot for " .. tostring(mapId))
  return tonumber(slot:match("_(%d+)$"))
end

local function mapNum(pretName)
  return slotNum(assert(MapCatalog.resolve(pretName), pretName))
end

-- src/region_map.c:3174
local FIXED = {
  MAPSEC_KANTO_SAFARI_ZONE = { 12, 12 },
  MAPSEC_SILPH_CO = { 14, 6 },
  MAPSEC_POKEMON_MANSION = { 4, 14 },
  MAPSEC_POKEMON_TOWER = { 18, 6 },
  MAPSEC_POWER_PLANT = { 18, 4 },
  MAPSEC_S_S_ANNE = { 14, 9 },
  MAPSEC_POKEMON_LEAGUE = { 2, 3 },
  MAPSEC_ROCKET_HIDEOUT = { 11, 6 },
  MAPSEC_BIRTH_ISLAND = { 18, 13 },
  MAPSEC_NAVEL_ROCK = { 10, 8 },
  MAPSEC_TRAINER_TOWER_2 = { 5, 6 },
  MAPSEC_MT_EMBER = { 2, 3 },
  MAPSEC_BERRY_FOREST = { 14, 12 },
  MAPSEC_PATTERN_BUSH = { 17, 3 },
  MAPSEC_ROCKET_WAREHOUSE = { 17, 11 },
  MAPSEC_DILFORD_CHAMBER = { 9, 12 },
  MAPSEC_LIPTOO_CHAMBER = { 9, 12 },
  MAPSEC_MONEAN_CHAMBER = { 9, 12 },
  MAPSEC_RIXY_CHAMBER = { 9, 12 },
  MAPSEC_SCUFIB_CHAMBER = { 9, 12 },
  MAPSEC_TANOBY_CHAMBERS = { 9, 12 },
  MAPSEC_VIAPOIS_CHAMBER = { 9, 12 },
  MAPSEC_WEEPTH_CHAMBER = { 9, 12 },
  MAPSEC_DOTTED_HOLE = { 16, 8 },
  MAPSEC_VIRIDIAN_FOREST = { 4, 6 },
}

local function warpOrZero(warp)
  if type(warp) == "table" and warp.map then return warp end
  return { map = MapCatalog.mapIdFor(0, 0), x = 0, y = 0 }
end

-- src/region_map.c:3096
local function scaled(ctx, geometry)
  local def = ctx.def(ctx.map)
  local mapType = tonumber(def.mapType)
  local mapsec, header, x, y
  if mapType == MAP_TYPE_UNDERGROUND or mapType == MAP_TYPE_UNKNOWN then
    local warp = warpOrZero(ctx.escapeWarp)
    header = ctx.def(warp.map)
    mapsec, x, y = header.regionMapSectionId, warp.x, warp.y
  elseif mapType == MAP_TYPE_SECRET_BASE then
    local warp = warpOrZero(ctx.dynamicWarp)
    header = ctx.def(warp.map)
    mapsec, x, y = header.regionMapSectionId, warp.x, warp.y
  elseif mapType == MAP_TYPE_INDOOR then
    mapsec = def.regionMapSectionId
    local warp
    if mapsec ~= sec("MAPSEC_SPECIAL_AREA") then
      warp = warpOrZero(ctx.escapeWarp)
      header = ctx.def(warp.map)
    else
      warp = warpOrZero(ctx.dynamicWarp)
      header = ctx.def(warp.map)
      mapsec = header.regionMapSectionId
    end
    x, y = warp.x, warp.y
  else
    mapsec, header, x, y = def.regionMapSectionId, def, ctx.x, ctx.y
  end
  local dims = assert(geometry.dimensions[mapsec], "no sMapSectionDimensions row for mapsec " .. tostring(mapsec))
  local corner = assert(geometry.topLeft[mapsec], "no sMapSectionTopLeftCorners row for mapsec " .. tostring(mapsec))
  x = math.floor(tonumber(x) or 0) % 65536
  y = math.floor(tonumber(y) or 0) % 65536
  local divisor = math.floor(header.width / dims[1])
  if divisor == 0 then divisor = 1 end
  x = math.floor(x / divisor)
  if x >= dims[1] then x = dims[1] - 1 end
  divisor = math.floor(header.height / dims[2])
  if divisor == 0 then divisor = 1 end
  y = math.floor(y / divisor)
  if y >= dims[2] then y = dims[2] - 1 end
  return x + corner[1], y + corner[2]
end

-- src/region_map.c:3174 GetPlayerPositionOnRegionMap_HandleOverrides
function Position.playerCell(ctx, geometry)
  local current = ctx.def(ctx.map).regionMapSectionId
  local num = slotNum(ctx.map)
  for id, cell in pairs(FIXED) do
    if current == sec(id) then return cell[1], cell[2] end
  end
  if current == sec("MAPSEC_UNDERGROUND_PATH") then
    if num == mapNum("UndergroundPath_NorthEntrance") then return 14, 5 end
    return 14, 7
  elseif current == sec("MAPSEC_UNDERGROUND_PATH_2") then
    if num == mapNum("UndergroundPath_EastEntrance") then return 15, 6 end
    return 12, 6
  elseif current == sec("MAPSEC_ROUTE_2") then
    if num == mapNum("PalletTown") then return 4, 7 end
    if num == mapNum("CeruleanCity") then return 4, 5 end
  elseif current == sec("MAPSEC_ROUTE_21") then
    if num == mapNum("Route21_North") then return 4, 12 end
    if num == mapNum("Route21_South") then return 4, 13 end
    return 0, 0
  elseif current == sec("MAPSEC_ROUTE_5") then
    if num == mapNum("ViridianCity") then return 14, 5 end
  elseif current == sec("MAPSEC_ROUTE_6") then
    if num == mapNum("PalletTown") then return 14, 7 end
  elseif current == sec("MAPSEC_ROUTE_7") then
    if num == mapNum("PalletTown") then return 13, 6 end
  elseif current == sec("MAPSEC_ROUTE_8") then
    if num == mapNum("PalletTown") then return 15, 6 end
  end
  return scaled(ctx, geometry)
end

-- src/region_map.c:1030-1049
function Position.regionFor(mapsec, layouts)
  if mapsec < sec("MAPSEC_ONE_ISLAND") then return 0 end
  for j = 0, 2 do
    for _, m in ipairs(layouts.seviiMapsecs[j]) do
      if m == mapsec then return j + 1 end
    end
  end
  error("mapsec " .. tostring(mapsec) .. " is in no sSeviiMapsecs row")
end

return Position

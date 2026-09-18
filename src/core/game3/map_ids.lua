-- Shared Game3 map-id helpers (Fire Red FR_* and legacy Sevii SEVII_*).

local MapIds = {}

function MapIds.isGame3Map(mapId)
  if type(mapId) ~= "string" then return false end
  if mapId:sub(1, 3) == "FR_" or mapId:sub(1, 6) == "SEVII_" then
    return true
  end
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog and MapCatalog.isKnown then
    return MapCatalog.isKnown(mapId)
  end
  return false
end

-- Deprecated alias kept for moved Sevii call sites.
MapIds.isSeviiMap = MapIds.isGame3Map

MapIds.NEW_GAME_START = {
  map = "FR_PLAYERS_HOUSE_2F",
  x = 6,
  y = 6,
  facing = "down",
  -- Whiteout / heal: pret HEAL_LOCATION_PALLET_TOWN → PlayersHouse_1F (8,5) by Mom.
  healMap = "FR_PLAYERS_HOUSE_1F",
  healX = 8,
  healY = 5,
}

MapIds.PALLET_TOWN = "FR_PALLET_TOWN"
MapIds.ROUTE_1 = "FR_ROUTE_1"

return MapIds

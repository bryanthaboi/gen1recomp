-- pret heal_locations.json whiteout destinations (SetWhiteoutRespawnWarpAndHealerNpc).
-- Indices match HEAL_LOCATION_* (1-based). setrespawn stores lastHealLocation;
-- whiteout warps to respawnMap at these coords (special-cased in heal_location.c).

local HealLocations = {}

-- MAP_* → FR_* for extracted Kanto maps; Sevii centers already use SEVII_*.
local function fr_center(city)
  return "FR_" .. city .. "_POKEMON_CENTER_1F"
end

-- Whiteout standing tile in front of healer (pret heal_location.c).
-- Pallet Mom house: (8,5). Indigo/One Island specials. Else poke-center (7,4).
HealLocations.BY_ID = {
  [1] = { -- HEAL_LOCATION_PALLET_TOWN
    map = "FR_PLAYERS_HOUSE_1F",
    x = 8,
    y = 5,
    healerLocalId = 1, -- LOCALID_MOM
  },
  [2] = { map = fr_center("VIRIDIAN_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [3] = { map = fr_center("PEWTER_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [4] = { map = fr_center("CERULEAN_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [5] = { map = fr_center("LAVENDER_TOWN"), x = 7, y = 4, healerLocalId = 1 },
  [6] = { map = fr_center("VERMILION_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [7] = { map = fr_center("CELADON_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [8] = { map = fr_center("FUCHSIA_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [9] = { map = fr_center("CINNABAR_ISLAND"), x = 7, y = 4, healerLocalId = 1 },
  [10] = { -- HEAL_LOCATION_INDIGO_PLATEAU
    map = "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F",
    x = 13,
    y = 12,
    healerLocalId = 1,
  },
  [11] = { map = fr_center("SAFFRON_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [12] = { map = "FR_ROUTE4_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [13] = { map = "FR_ROUTE10_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [14] = { -- HEAL_LOCATION_ONE_ISLAND
    map = "SEVII_ONE_ISLAND_POKECENTER",
    x = 5,
    y = 4,
    healerLocalId = 1,
  },
  [15] = { map = "SEVII_TWO_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
  [16] = { map = "SEVII_THREE_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
  [17] = { map = "SEVII_FOUR_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
  [18] = { map = "SEVII_FIVE_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
  [19] = { map = "SEVII_SEVEN_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
  [20] = { map = "SEVII_SIX_ISLAND_POKECENTER", x = 7, y = 4, healerLocalId = 1 },
}

function HealLocations.get(id)
  id = tonumber(id) or 0
  return HealLocations.BY_ID[id]
end

--- Apply setrespawn / default heal onto a session (whiteout destination).
function HealLocations.applyToSession(session, id)
  local loc = HealLocations.get(id)
  if not (session and loc) then return false end
  session.healMap = loc.map
  session.healX = loc.x
  session.healY = loc.y
  session.healHealerLocalId = loc.healerLocalId
  return true
end

--- Migrate bad early defaults (bedroom 2F has no Mom).
function HealLocations.normalizeSession(session)
  if not session then return end
  if session.healMap == "FR_PLAYERS_HOUSE_2F" then
    HealLocations.applyToSession(session, 1)
  end
end

return HealLocations

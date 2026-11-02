-- pokegold data/maps/flypoints.asm:1, data/events/engine_flags.asm:75-101
local ROWS = {
  { "SPAWN_NEW_BARK", "LANDMARK_NEW_BARK_TOWN", 64 },
  { "SPAWN_CHERRYGROVE", "LANDMARK_CHERRYGROVE_CITY", 65 },
  { "SPAWN_VIOLET", "LANDMARK_VIOLET_CITY", 66 },
  { "SPAWN_AZALEA", "LANDMARK_AZALEA_TOWN", 67 },
  { "SPAWN_GOLDENROD", "LANDMARK_GOLDENROD_CITY", 69 },
  { "SPAWN_ECRUTEAK", "LANDMARK_ECRUTEAK_CITY", 71 },
  { "SPAWN_OLIVINE", "LANDMARK_OLIVINE_CITY", 70 },
  { "SPAWN_CIANWOOD", "LANDMARK_CIANWOOD_CITY", 68 },
  { "SPAWN_MAHOGANY", "LANDMARK_MAHOGANY_TOWN", 72 },
  { "SPAWN_LAKE_OF_RAGE", "LANDMARK_LAKE_OF_RAGE", 73 },
  { "SPAWN_BLACKTHORN", "LANDMARK_BLACKTHORN_CITY", 74 },
  { "SPAWN_MT_SILVER", "LANDMARK_SILVER_CAVE", 75 },
  { "SPAWN_PALLET", "LANDMARK_PALLET_TOWN", 52 },
  { "SPAWN_VIRIDIAN", "LANDMARK_VIRIDIAN_CITY", 53 },
  { "SPAWN_PEWTER", "LANDMARK_PEWTER_CITY", 54 },
  { "SPAWN_CERULEAN", "LANDMARK_CERULEAN_CITY", 55 },
  { "SPAWN_VERMILION", "LANDMARK_VERMILION_CITY", 57 },
  { "SPAWN_ROCK_TUNNEL", "LANDMARK_ROCK_TUNNEL", 56 },
  { "SPAWN_LAVENDER", "LANDMARK_LAVENDER_TOWN", 58 },
  { "SPAWN_CELADON", "LANDMARK_CELADON_CITY", 60 },
  { "SPAWN_SAFFRON", "LANDMARK_SAFFRON_CITY", 59 },
  { "SPAWN_FUCHSIA", "LANDMARK_FUCHSIA_CITY", 61 },
  { "SPAWN_CINNABAR", "LANDMARK_CINNABAR_ISLAND", 62 },
  { "SPAWN_INDIGO", "LANDMARK_INDIGO_PLATEAU", 63 },
}

local Fixture = { ROWS = ROWS }

function Fixture.rows(version)
  local shift = version == "crystal" and 1 or 0
  local out = {}
  for order, row in ipairs(ROWS) do
    out[row[1]] = { landmark = row[2], flag = row[3] + shift,
      region = order > 12 and "kanto" or "johto", order = order - 1 }
  end
  return out
end

function Fixture.bind(version)
  return require("src.world.gen2.FieldMoves").bindFlypoints(Fixture.rows(version))
end

return Fixture

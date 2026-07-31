-- Where each map's battles happen.
--
-- One authored spot per area, rather than whichever clearing happens to be
-- nearest the step the fight started on. A battle on Route 1 should look the
-- same every time it happens on Route 1 -- and, more importantly, "open
-- ground" is not the same question as "you can see the two of them": the
-- battle camera sits low and a long way back, so a hedge, a ledge lip or the
-- corner of a house anywhere along that sightline hides a Pokemon completely
-- while every cell it is standing on is perfectly walkable.
--
-- Each entry is the arena's north-west corner in map CELLS, and which of
-- BattleArena.SHAPES it is. Picked by tools/arena_pick (BattleArena.search
-- with the clearance test on, from the middle of the map) and then looked at,
-- one screenshot per map -- these are eyeballed answers, not just passing
-- ones. Grass and flowers around a mon's feet are fine and wanted; anything
-- that cuts into a body is not.
--
-- A map with no entry here falls back to the nearest-clear search at battle
-- time, so a mod that adds maps, or an entry that goes stale against an
-- edited map, degrades to the old behaviour rather than to no battle.
--
-- The entries below are generated; regenerate with
--
--   SHOT_DIR=.scratchpad/arenas \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/arena_pick.lua love .

-- `cam = "wide"` on an entry swaps the long default lens for the 44-degree
-- one (BattleCam.RIGS). Both frame the same composition -- the two mons land
-- on the same screen anchors either way -- so it is purely a choice about how
-- much of the place is in shot, at the cost of a smaller pair. Rooms the long
-- lens cannot stand back from NEED it; anywhere that simply reads better with
-- more of itself visible may ask for it.
--
-- Tall grass is never part of an arena (BattleArena.openCell rejects it), so
-- a route's spot is always its bare path rather than the field beside it --
-- grass is knee-high geometry to a Pokemon and this camera is nearly level
-- with the floor, so tufts on the mon's own tile stand between it and the
-- lens. Flowers are left alone: they are ankle height and read as ground.

return {
  -- ------- routes
  -- narrow, deliberately: the route's interior is a 3-cell-wide lane and the
  -- wide shape only fits in the western connection border, which staged every
  -- fight at the edge of the world instead of on the road
  ["ROUTE_1"] = { x = 9, y = 16, shape = "narrow" },
  ["ROUTE_2"] = { x = 1, y = 49, shape = "wide" },
  ["ROUTE_3"] = { x = 57, y = 1, shape = "wide" },
  ["ROUTE_4"] = { x = 46, y = 7, shape = "wide" },
  ["ROUTE_5"] = { x = 13, y = 24, shape = "wide" },
  ["ROUTE_6"] = { x = 5, y = 17, shape = "narrow" },
  ["ROUTE_7"] = { x = 8, y = 8, shape = "narrow" },
  ["ROUTE_8"] = { x = 25, y = 7, shape = "wide" },
  -- the whole route admits six bare wide arenas, all in the west cliff
  -- corridor; this is the best of them. A flower cluster crosses the far
  -- mon's hind legs, which the brief allows -- every alternative put a
  -- terrace through the near mon's waist, which it does not.
  ["ROUTE_9"] = { x = 1, y = 11, shape = "wide", cam = "wide" },
  ["ROUTE_10"] = { x = 7, y = 40, shape = "wide" },
  ["ROUTE_11"] = { x = 9, y = 6, shape = "wide" },
  ["ROUTE_12"] = { x = 0, y = 73, shape = "wide" },
  ["ROUTE_13"] = { x = 50, y = 8, shape = "narrow" },
  ["ROUTE_14"] = { x = 11, y = 25, shape = "wide" },
  ["ROUTE_15"] = { x = 9, y = 10, shape = "wide" },
  ["ROUTE_16"] = { x = 6, y = 10, shape = "wide" },
  ["ROUTE_17"] = { x = 14, y = 70, shape = "wide" },
  ["ROUTE_18"] = { x = 11, y = 4, shape = "wide" },

  -- ------- buildings and caves
  --
  -- Indoors the narrow shape earns its keep: a room with furniture, machinery
  -- or gravestones in it rarely holds a 3x6 clearing whose whole width is
  -- also SEEN, and giving up the apron is usually the difference between a
  -- fight in the open and one behind a console.
  ["POKEMON_MANSION_1F"] = { x = 4, y = 12, shape = "wide" },
  ["POKEMON_MANSION_2F"] = { x = 15, y = 17, shape = "wide" },
  ["POKEMON_MANSION_3F"] = { x = 23, y = 2, shape = "narrow", cam = "wide" },
  ["POKEMON_MANSION_B1F"] = { x = 19, y = 10, shape = "wide" },
  ["POKEMON_TOWER_2F"] = { x = 4, y = 7, shape = "narrow" },
  ["POKEMON_TOWER_3F"] = { x = 4, y = 6, shape = "wide" },
  -- every one of 4F's thirty candidate spots puts a gravestone through a
  -- mon; the floor below is the same tower and has the room, so the fight
  -- is shot there
  ["POKEMON_TOWER_4F"] = { map = "POKEMON_TOWER_3F", x = 4, y = 6,
                           shape = "wide" },
  ["POKEMON_TOWER_5F"] = { x = 10, y = 1, shape = "narrow" },
  ["POKEMON_TOWER_6F"] = { x = 14, y = 6, shape = "narrow" },
  ["POKEMON_TOWER_7F"] = { x = 9, y = 5, shape = "wide" },
  ["POWER_PLANT"] = { x = 18, y = 5, shape = "narrow" },
  ["ROCK_TUNNEL_1F"] = { x = 14, y = 15, shape = "wide" },
  ["ROCK_TUNNEL_B1F"] = { x = 20, y = 17, shape = "wide" },
  ["ROCKET_HIDEOUT_B1F"] = { x = 11, y = 6, shape = "narrow" },
  ["ROCKET_HIDEOUT_B2F"] = { x = 19, y = 7, shape = "narrow" },
  ["ROCKET_HIDEOUT_B3F"] = { x = 22, y = 11, shape = "narrow" },
  ["ROCKET_HIDEOUT_B4F"] = { x = 17, y = 3, shape = "narrow" },
  ["SAFARI_ZONE_CENTER"] = { x = 1, y = 8, shape = "wide" },
  ["SAFARI_ZONE_EAST"] = { x = 21, y = 8, shape = "wide" },
  ["SAFARI_ZONE_NORTH"] = { x = 19, y = 14, shape = "wide" },
  ["SAFARI_ZONE_WEST"] = { x = 18, y = 3, shape = "wide" },
  ["SEAFOAM_ISLANDS_1F"] = { x = 14, y = 7, shape = "wide" },
  ["SEAFOAM_ISLANDS_B1F"] = { x = 11, y = 1, shape = "wide" },
  ["SEAFOAM_ISLANDS_B2F"] = { x = 16, y = 2, shape = "wide" },
  ["SEAFOAM_ISLANDS_B3F"] = { x = 25, y = 7, shape = "wide" },
  ["SEAFOAM_ISLANDS_B4F"] = { x = 12, y = 6, shape = "narrow" },
  -- Silph Co is office floors partitioned into small rooms, so the long lens
  -- often lands outside the walls it is meant to be looking between; the
  -- floors that could not be framed any other way ask for the wide one.
  ["SILPH_CO_2F"] = { x = 16, y = 8, shape = "narrow" },
  ["SILPH_CO_4F"] = { x = 24, y = 2, shape = "narrow" },
  ["SILPH_CO_5F"] = { x = 16, y = 7, shape = "wide" },
  ["SILPH_CO_6F"] = { x = 10, y = 8, shape = "narrow" },
  ["SILPH_CO_7F"] = { x = 1, y = 2, shape = "wide", cam = "wide" },
  ["SILPH_CO_8F"] = { x = 8, y = 6, shape = "narrow" },
  ["SILPH_CO_9F"] = { x = 20, y = 11, shape = "wide", cam = "wide" },
  ["SS_ANNE_1F_ROOMS"] = { x = 10, y = 1, shape = "narrow", cam = "wide" },
  -- the ship is all two-cell corridors, so the wide arena shape fits nowhere
  -- aboard and the long lens always lands outside the hull
  ["SS_ANNE_2F"] = { x = 36, y = 8, shape = "narrow", cam = "wide" },
  -- these two decks are byte-identical geometry, so they take the same spot
  ["SS_ANNE_2F_ROOMS"] = { x = 11, y = 12, shape = "narrow" },
  ["SS_ANNE_B1F_ROOMS"] = { x = 11, y = 12, shape = "narrow" },
  ["SS_ANNE_BOW"] = { x = 8, y = 3, shape = "wide" },
  ["VICTORY_ROAD_2F"] = { x = 16, y = 6, shape = "wide" },
  ["VICTORY_ROAD_3F"] = { x = 20, y = 1, shape = "wide" },

  -- ------- towns and the last interiors
  ["CERULEAN_CITY"] = { x = 15, y = 16, shape = "wide" },
  ["GAME_CORNER"] = { x = 8, y = 7, shape = "wide" },
  -- the lab is ten cells by twelve, so the long lens is always off-map, and
  -- on it a desk clipped one mon and a pillar the other
  ["OAKS_LAB"] = { x = 3, y = 2, shape = "narrow", cam = "wide" },
  -- Saffron's gym is a grid of small walled cells: no wide shape exists
  -- anywhere in it, and the long lens sits inside a divider
  ["SAFFRON_GYM"] = { x = 9, y = 7, shape = "narrow", cam = "wide" },
  ["SILPH_CO_3F"] = { x = 18, y = 11, shape = "wide", cam = "wide" },
  ["SILPH_CO_10F"] = { x = 1, y = 2, shape = "wide" },
  ["SILPH_CO_11F"] = { x = 1, y = 11, shape = "wide", cam = "wide" },
  -- the upper corridor (cols 4-5, rows 1-4) is sealed at runtime by the
  -- gym's barrier, so arenas there silently fail the fit test
  ["VERMILION_GYM"] = { x = 4, y = 11, shape = "narrow" },
  ["VICTORY_ROAD_1F"] = { x = 11, y = 2, shape = "narrow" },
  ["VIRIDIAN_FOREST"] = { x = 16, y = 34, shape = "narrow" },

  -- ------- the remaining routes
  ["ROUTE_19"] = { x = 8, y = 6, shape = "narrow" },
  -- the two surf routes fight AFLOAT, in the middle of their own sea rather
  -- than on the rim of beach the land search would otherwise find
  ["ROUTE_20"] = { x = 23, y = 7, shape = "wide" },
  ["ROUTE_21"] = { x = 8, y = 46, shape = "wide" },
  ["ROUTE_22"] = { x = 35, y = 7, shape = "wide" },
  ["ROUTE_23"] = { x = 4, y = 36, shape = "wide" },
  ["ROUTE_24"] = { x = 13, y = 15, shape = "wide" },
  ["ROUTE_25"] = { x = 32, y = 2, shape = "wide", cam = "wide" },

  -- ------- caves, gyms and the Elite Four
  --
  -- None of these tilesets has a grass tile at all, so the no-grass rule
  -- constrained nothing here; what constrains them is furniture, rock
  -- pillars and how small the rooms are.
  ["AGATHAS_ROOM"] = { x = 2, y = 1, shape = "narrow", cam = "wide" },
  ["BRUNOS_ROOM"] = { x = 3, y = 1, shape = "narrow" },
  ["CELADON_GYM"] = { x = 0, y = 3, shape = "narrow" },
  ["CERULEAN_CAVE_1F"] = { x = 1, y = 7, shape = "narrow" },
  -- 2F is a maze of one-cell rock corridors; all 24 of its candidate spots
  -- hide a mon, so it borrows the floor below -- the same cave
  ["CERULEAN_CAVE_2F"] = { map = "CERULEAN_CAVE_B1F", x = 2, y = 0,
                           shape = "wide" },
  ["CERULEAN_CAVE_B1F"] = { x = 2, y = 0, shape = "wide" },
  ["CERULEAN_GYM"] = { x = 0, y = 1, shape = "narrow" },
  ["CHAMPIONS_ROOM"] = { x = 2, y = 2, shape = "narrow", cam = "wide" },
  ["CINNABAR_GYM"] = { x = 18, y = 10, shape = "narrow" },
  ["DIGLETTS_CAVE"] = { x = 19, y = 16, shape = "wide" },
  ["FIGHTING_DOJO"] = { x = 4, y = 1, shape = "narrow" },
  ["LANCES_ROOM"] = { x = 5, y = 15, shape = "wide" },
  ["LORELEIS_ROOM"] = { x = 5, y = 2, shape = "narrow" },
  ["MT_MOON_1F"] = { x = 24, y = 17, shape = "wide" },
  ["MT_MOON_B1F"] = { x = 5, y = 12, shape = "wide" },
  ["MT_MOON_B2F"] = { x = 2, y = 16, shape = "wide" },

  -- The three gyms the default rig cannot stand back from. Five blocks is
  -- further than these rooms are wide, so the eye landed outside the map and
  -- the border ring -- extruded into a cliff by this mode -- crossed the near
  -- mon wherever it stood. `cam = "wide"` swaps in the 44-degree lens (see
  -- BattleCam), which fits inside the room; the mons come out smaller and all
  -- three became stageable. It is asked for HERE, per map, so every area that
  -- does not ask keeps the long lens it was framed for.
  ["FUCHSIA_GYM"] = { x = 7, y = 6, shape = "narrow", cam = "wide" },
  ["PEWTER_GYM"] = { x = 4, y = 8, shape = "narrow", cam = "wide" },
  ["VIRIDIAN_GYM"] = { x = 10, y = 8, shape = "narrow", cam = "wide" },
}

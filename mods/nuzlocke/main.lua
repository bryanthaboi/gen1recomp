-- Nuzlocke Rules v3.27 - Battle-item enforcement fix and current Nuzlocke rules profile
return function(mod)
  local Stats = require("src.pokemon.Stats")
  local Growth = require("src.pokemon.Growth")
  local Data = require("src.core.Data")
  local catchDeniedReason
  local isTownArea
  local enemyIsShiny
  local currentGame
  local currentSave

  mod.events:on("game.ready", function(game)
      currentGame = game
      currentSave = game and game.save or currentSave
  end)

  ---------------------------------------------------------------------
  -- WORD WRAP HELPER (16 chars: safe inner width for the desc box)
  ---------------------------------------------------------------------
  local function wrapText(str, limit)
      limit = limit or 16
      local lines = {}
      local currentLine = ""

      for word in tostring(str):gmatch("%S+") do
          if #currentLine == 0 then
              currentLine = word
          elseif #currentLine + 1 + #word <= limit then
              currentLine = currentLine .. " " .. word
          else
              table.insert(lines, currentLine)
              currentLine = word
          end
      end

      if #currentLine > 0 then
          table.insert(lines, currentLine)
      end

      return lines
  end

  ---------------------------------------------------------------------
  -- ALL GEN 1 CATCHABLE ROUTES / LOCATIONS
  --
  -- These IDs intentionally match the engine's actual map IDs.
  ---------------------------------------------------------------------
  local ALL_ROUTES = {
      -- Ordered in the normal Gen 1 discovery/progression order.
      -- Optional side areas are placed where a player would naturally
      -- first encounter them rather than grouping cities, routes, or caves.
      { id = "PALLET_TOWN",      name = "Pallet Town"    },
      { id = "ROUTE_1",          name = "Route 1"        },
      { id = "VIRIDIAN_CITY",    name = "Viridian City"  },
      { id = "ROUTE_22",         name = "Route 22"       },
      { id = "ROUTE_2",          name = "Route 2"        },
      { id = "VIRIDIAN_FOREST",  name = "Virid. Forest"  },
      { id = "PEWTER_CITY",      name = "Pewter City"    },
      { id = "ROUTE_3",          name = "Route 3"        },
      { id = "MT_MOON",          name = "Mt. Moon"       },
      { id = "ROUTE_4",          name = "Route 4"        },
      { id = "CERULEAN_CITY",    name = "Cerulean City"  },
      { id = "CERULEAN_GYM",     name = "Cerulean Gym"   },
      { id = "ROUTE_24",         name = "Route 24"       },
      { id = "ROUTE_25",         name = "Route 25"       },
      { id = "ROUTE_5",          name = "Route 5"        },
      { id = "ROUTE_6",          name = "Route 6"        },
      { id = "VERMILION_CITY",   name = "Vermilion City" },
      { id = "VERMILION_HARBOR", name = "Vermilion Harbor" },
      { id = "ROUTE_11",         name = "Route 11"       },
      { id = "DIGLETT_CAVE",     name = "Diglett Cave"   },
      { id = "ROUTE_9",          name = "Route 9"        },
      { id = "ROUTE_10",         name = "Route 10"       },
      { id = "ROCK_TUNNEL",      name = "Rock Tunnel"    },
      { id = "POWER_PLANT",      name = "Power Plant"    },
      { id = "LAVENDER_TOWN",    name = "Lavender Town"  },
      { id = "POKEMON_TOWER",    name = "Pkmn Tower"     },
      { id = "ROUTE_12",         name = "Route 12"       },
      { id = "ROUTE_13",         name = "Route 13"       },
      { id = "ROUTE_14",         name = "Route 14"       },
      { id = "ROUTE_15",         name = "Route 15"       },
      { id = "FUCHSIA_CITY",     name = "Fuchsia City"   },
      { id = "SAFARI_ZONE",      name = "Safari Zone"    },
      { id = "CELADON_CITY",     name = "Celadon City"   },
      { id = "ROUTE_16",         name = "Route 16"       },
      { id = "ROUTE_17",         name = "Route 17"       },
      { id = "ROUTE_18",         name = "Route 18"       },
      { id = "ROUTE_7",          name = "Route 7"        },
      { id = "ROUTE_8",          name = "Route 8"        },
      { id = "SAFFRON_CITY",     name = "Saffron City"   },
      { id = "SILPH_CO",         name = "Silph Co."      },
      { id = "ROUTE_19",         name = "Route 19"       },
      { id = "ROUTE_20",         name = "Route 20"       },
      { id = "SEAFOAM_ISLANDS",  name = "Seafoam Isls."  },
      { id = "CINNABAR_ISLAND",  name = "Cinnabar Isl."  },
      { id = "POKEMON_MANSION",  name = "Pkmn Mansion"   },
      { id = "ROUTE_21",         name = "Route 21"       },
      { id = "ROUTE_23",         name = "Route 23"       },
      { id = "VICTORY_ROAD",     name = "Victory Road"   },
      { id = "CERULEAN_CAVE",    name = "Cerulean Cave"  },
  }

  local ROUTE_IDS = {}
  local ROUTE_NAMES = {}
  local ROUTE_ORDER = {}

  for index, route in ipairs(ALL_ROUTES) do
      ROUTE_IDS[route.id] = true
      ROUTE_NAMES[route.id] = route.name
      ROUTE_ORDER[route.id] = index
  end

  ---------------------------------------------------------------------
  -- LEGACY MAP ALIASES
  --
  -- Older versions of this mod could have stored a raw engine/text
  -- namespace identifier. Keep aliases here so upgrading a save does
  -- not throw away existing tracker information.
  ---------------------------------------------------------------------
  local MAP_ALIASES = {
      -- Text-pointer style names
      PalletTown       = "PALLET_TOWN",
      ViridianCity     = "VIRIDIAN_CITY",
      ViridianForest   = "VIRIDIAN_FOREST",
      PewterCity       = "PEWTER_CITY",
      MtMoon           = "MT_MOON",
      CeruleanCity     = "CERULEAN_CITY",
      VermilionCity    = "VERMILION_CITY",
      DiglettsCave     = "DIGLETT_CAVE",
      DiglettCave      = "DIGLETT_CAVE",
      LavenderTown     = "LAVENDER_TOWN",
      PokemonTower     = "POKEMON_TOWER",
      CeladonCity      = "CELADON_CITY",
      SafariZone       = "SAFARI_ZONE",
      FuchsiaCity      = "FUCHSIA_CITY",
      SaffronCity      = "SAFFRON_CITY",
      SilphCo          = "SILPH_CO",
      CinnabarIsland   = "CINNABAR_ISLAND",
      VictoryRoad      = "VICTORY_ROAD",
      PowerPlant       = "POWER_PLANT",
      SeafoamIslands   = "SEAFOAM_ISLANDS",
      RockTunnel       = "ROCK_TUNNEL",
      MtEmber          = "MT_EMBER",
      PokemonMansion   = "POKEMON_MANSION",
      CeruleanCave     = "CERULEAN_CAVE",
      CeruleanGym      = "CERULEAN_GYM",
      VermilionHarbor  = "VERMILION_HARBOR",

      Route1           = "ROUTE_1",
      Route2           = "ROUTE_2",
      Route3           = "ROUTE_3",
      Route4           = "ROUTE_4",
      Route5           = "ROUTE_5",
      Route6           = "ROUTE_6",
      Route7           = "ROUTE_7",
      Route8           = "ROUTE_8",
      Route9           = "ROUTE_9",
      Route10          = "ROUTE_10",
      Route11          = "ROUTE_11",
      Route12          = "ROUTE_12",
      Route13          = "ROUTE_13",
      Route14          = "ROUTE_14",
      Route15          = "ROUTE_15",
      Route16          = "ROUTE_16",
      Route17          = "ROUTE_17",
      Route18          = "ROUTE_18",
      Route19          = "ROUTE_19",
      Route20          = "ROUTE_20",
      Route21          = "ROUTE_21",
      Route22          = "ROUTE_22",
      Route23          = "ROUTE_23",
      Route24          = "ROUTE_24",
      Route25          = "ROUTE_25",
  }

  ---------------------------------------------------------------------
  -- NORMALIZE A MAP ID
  --
  -- Current engine map IDs already match ALL_ROUTES.
  -- Aliases are only for compatibility with older mod tracker data.
  ---------------------------------------------------------------------
  local function routeKey(mapId)
      if mapId == nil then
          return nil
      end

      mapId = tostring(mapId)

      if ROUTE_IDS[mapId] then
          return mapId
      end

      local alias = MAP_ALIASES[mapId]
      if alias then
          return alias
      end

      -- Unknown map IDs are intentionally accepted. This makes the tracker
      -- compatible with map/overworld mods instead of silently rejecting a
      -- perfectly valid new area just because vanilla Gen 1 never had it.
      if mapId:match("^[%w_%-]+$") then
          return mapId
      end

      return nil
  end

  ---------------------------------------------------------------------
  -- LOOKUP / DYNAMIC AREA HELPERS
  ---------------------------------------------------------------------
  local function prettyAreaName(id)
      local text = tostring(id or "")
      text = text:gsub("_+", " ")
      text = text:gsub("([a-z])([A-Z])", "%1 %2")
      text = text:gsub("([A-Z]+)([A-Z][a-z])", "%1 %2")
      text = text:gsub("(%a)(%d)", "%1 %2")
      text = text:gsub("(%d)(%a)", "%1 %2")
      text = text:gsub("%s+", " ")
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      text = text:gsub("(%w)([%w]*)", function(first, rest)
          return first:upper() .. rest:lower()
      end)
      return text
  end

  -- Explicit display overrides for map IDs whose internal names are not
  -- reliably word-separable. IDs remain unchanged for save/mod compatibility.
  local DISPLAY_NAME_OVERRIDES = {
      CERULEANMART4 = "Cerulean Mart 4",
      CeruleanMart4 = "Cerulean Mart 4",
      CERULEANMART = "Cerulean Mart",
      CERULEANHOTEL = "Cerulean Hotel",
      CeruleanHotel = "Cerulean Hotel",
      CERULEANCITYHOTEL = "Cerulean City Hotel",
      CeruleanCityHotel = "Cerulean City Hotel",
      VERMILIONMART4 = "Vermilion Mart 4",
      VermilionMart4 = "Vermilion Mart 4",
      CELADONMART4 = "Celadon Mart 4",
      CeladonMart4 = "Celadon Mart 4",
      CELADONDEPTSTORE = "Celadon Dept Store",
      CeladonDeptStore = "Celadon Dept Store",

      VIRIDIANMART = "Viridian Mart",
      ViridianMart = "Viridian Mart",
      PEWTERMART = "Pewter Mart",
      PewterMart = "Pewter Mart",
      LAVENDERMART = "Lavender Mart",
      LavenderMart = "Lavender Mart",
      FUCHSIAMART = "Fuchsia Mart",
      FuchsiaMart = "Fuchsia Mart",
      SAFFRONMART = "Saffron Mart",
      SaffronMart = "Saffron Mart",
      CINNABARMART = "Cinnabar Mart",
      CinnabarMart = "Cinnabar Mart",
      CELADONMART = "Celadon Mart",
      CeladonMart = "Celadon Mart",
      VIRIDIANCENTER = "Viridian Center",
      ViridianCenter = "Viridian Center",
      PEWTERCENTER = "Pewter Center",
      PewterCenter = "Pewter Center",
      CERULEANCENTER = "Cerulean Center",
      CeruleanCenter = "Cerulean Center",
      VERMILIONCENTER = "Vermilion Center",
      VermilionCenter = "Vermilion Center",
      LAVENDERCENTER = "Lavender Center",
      LavenderCenter = "Lavender Center",
      FUCHSIACENTER = "Fuchsia Center",
      FuchsiaCenter = "Fuchsia Center",
      CELADONCENTER = "Celadon Center",
      CeladonCenter = "Celadon Center",
      SAFFRONCENTER = "Saffron Center",
      SaffronCenter = "Saffron Center",
      CINNABARCENTER = "Cinnabar Center",
      CinnabarCenter = "Cinnabar Center",
  }

  local function formatAreaDisplayName(name, id)
      local override = DISPLAY_NAME_OVERRIDES[tostring(id or "")]
      if override then return override end
      local text = tostring(name or "")
      if text == "" then
          return prettyAreaName(id)
      end
      text = text:gsub("_+", " ")
      text = text:gsub("([a-z])([A-Z])", "%1 %2")
      text = text:gsub("([A-Z]+)([A-Z][a-z])", "%1 %2")
      text = text:gsub("(%a)(%d)", "%1 %2")
      text = text:gsub("(%d)(%a)", "%1 %2")
      text = text:gsub("%s+", " ")
      text = text:gsub("^%s+", ""):gsub("%s+$", "")

      -- Common concatenated map-name components (CeruleanMart4, etc.).
      local tokens = {
          "Department Store", "Dept Store", "Pokemon Center", "Pokemon Mart",
          "Pkmn Center", "Pkmn Mart", "PokeMart", "Poke Mart",
          "Game Corner", "GameCorner", "Silph Co", "Bike Shop", "Fishing Guru",
          "Name Rater", "Safari Zone", "Pokemon Mansion", "Pokemon Tower",
          "Cerulean Cave", "Viridian Forest", "Diglett Cave", "Rock Tunnel",
          "Power Plant", "Seafoam Islands", "Victory Road", "Mart", "Hotel",
          "Gym", "House", "Lab", "Center", "Gate", "Museum", "Shop",
          "Office", "Floor", "Cave", "Tower", "Mansion", "Harbor", "Port"
      }
      for _, token in ipairs(tokens) do
          local compact = text:gsub("%s+", ""):lower()
          local tl = token:gsub("%s+", ""):lower()
          local pos = compact:find(tl, 1, true)
          if pos and pos > 1 then
              local before = compact:sub(1, pos - 1)
              local after = compact:sub(pos + #tl)
              if after ~= "" then
                  text = before .. " " .. token .. " " .. after
              else
                  text = before .. " " .. token
              end
          end
      end
      text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if #text > 0 then
          text = text:sub(1, 1):upper() .. text:sub(2)
      end
      return text
  end

  local function registerArea(id, name)
      if not id or id == "__LEGACY__" then
          return nil
      end

      id = routeKey(id)
      if not id then
          return nil
      end

      if not ROUTE_IDS[id] then
          ROUTE_IDS[id] = true
          ROUTE_NAMES[id] = formatAreaDisplayName(name, id)
          table.insert(ALL_ROUTES, {
              id = id,
              name = ROUTE_NAMES[id]
          })
      elseif name then
          ROUTE_NAMES[id] = formatAreaDisplayName(name, id)
          for _, route in ipairs(ALL_ROUTES) do
              if route.id == id then
                  route.name = ROUTE_NAMES[id]
                  break
              end
          end
      end

      return id
  end

  local function isTrackedArea(id)
      id = routeKey(id)
      return id ~= nil and ROUTE_IDS[id] == true
  end

  local function routeName(id)
      return formatAreaDisplayName(ROUTE_NAMES[id], id)
  end

  local function discoverAreasFromTable(tbl)
      if type(tbl) ~= "table" then
          return
      end

      for rawId, def in pairs(tbl) do
          local id = rawId
          local name = nil

          if type(def) == "table" then
              id = def.id or def.mapId or def.key or rawId
              name = def.name or def.label or def.displayName or def.title
          elseif type(def) == "string" then
              id = rawId
              name = def
          end

          if type(id) == "string" then
              registerArea(id, name)
          end
      end
  end

  local function discoverAllKnownAreas(game)
      if not game then
          return
      end

      -- These are deliberately guarded: different recomp/mod builds may
      -- expose map definitions through different data containers.
      local data = game.data
      if type(data) == "table" then
          discoverAreasFromTable(data.maps)
          discoverAreasFromTable(data.mapsById)
          discoverAreasFromTable(data.mapData)
      end

      discoverAreasFromTable(game.maps)
      discoverAreasFromTable(game.mapsById)
      discoverAreasFromTable(game.mapData)

      if game.save then
          if type(game.save.visited) == "table" then
              for rawId, wasVisited in pairs(game.save.visited) do
                  if wasVisited then
                      registerArea(rawId)
                  end
              end
          end
          if game.save.player and game.save.player.map then
              registerArea(game.save.player.map)
          end
      end
  end

  ---------------------------------------------------------------------
  -- SAVE STATE HELPERS
  ---------------------------------------------------------------------
  local function caughtAreas()
      local areas = mod.save:get("caught_areas")

      if type(areas) ~= "table" then
          areas = {}
          mod.save:set("caught_areas", areas)
      end

      return areas
  end

  local function trackerLog()
      local log = mod.save:get("tracker_log")

      if type(log) ~= "table" then
          log = {}
          mod.save:set("tracker_log", log)
      end

      return log
  end

  local function syncCaughtAreasFromLog()
      local areas = caughtAreas()
      local log = trackerLog()
      local changed = false

      for key, catches in pairs(log) do
          if key ~= "__LEGACY__" and areas[key] == nil and type(catches) == "table" then
              for _, entry in ipairs(catches) do
                  if type(entry) == "table" and entry.species then
                      areas[key] = entry.species
                      changed = true
                      break
                  end
              end
          end
      end

      if changed then
          mod.save:set("caught_areas", areas)
      end
      return areas
  end

  local function visitedAreas()
      local v = mod.save:get("visited_areas")

      if type(v) ~= "table" then
          v = {}
          mod.save:set("visited_areas", v)
      end

      return v
  end

  ---------------------------------------------------------------------
  -- AREA KEY
  ---------------------------------------------------------------------
  local function areaKey(game, battle)
      if battle and battle.safari then
          return "SAFARI_ZONE"
      end

      local mapId

      if game and game.overworld and game.overworld.map then
          mapId = game.overworld.map.id
      end

      if not mapId and game and game.save and game.save.player then
          mapId = game.save.player.map
      end

      return routeKey(mapId)
  end

  ---------------------------------------------------------------------
  -- MARK AREA VISITED
  ---------------------------------------------------------------------
  local function markVisited(key)
      key = registerArea(key)

      if not isTrackedArea(key) then
          return false
      end

      local v = visitedAreas()

      if not v[key] then
          v[key] = true
          mod.save:set("visited_areas", v)
      end

      return true
  end

  ---------------------------------------------------------------------
  -- MARK AREA CAUGHT
  ---------------------------------------------------------------------
  local function markCaught(key, species)
      key = registerArea(key)

      if not isTrackedArea(key) then
          return
      end

      local areas = caughtAreas()

      if areas[key] == nil then
          areas[key] = species
          mod.save:set("caught_areas", areas)
      end
  end

  ---------------------------------------------------------------------
  -- NORMALIZE AN OLD TABLE OF MAP KEYS
  --
  -- Converts old:
  --     PalletTown = true
  --
  -- into:
  --     PALLET_TOWN = true
  ---------------------------------------------------------------------
  local function normalizeMapTable(tbl)
      if type(tbl) ~= "table" then
          return {}, true
      end

      local normalized = {}
      local changed = false

      for rawKey, value in pairs(tbl) do
          local key = routeKey(rawKey)

          if key then
              registerArea(key)
              normalized[key] = value
              if tostring(rawKey) ~= key then
                  changed = true
              end
          else
              -- Preserve unknown data rather than silently deleting it.
              normalized[rawKey] = value
          end
      end

      return normalized, changed
  end

  ---------------------------------------------------------------------
  -- NORMALIZE TRACKER LOG
  ---------------------------------------------------------------------
  local function normalizeTrackerLog(log)
      if type(log) ~= "table" then
          return {}, true
      end

      local normalized = {}
      local changed = false

      for rawKey, catches in pairs(log) do
          local key = routeKey(rawKey)

          if key then
              registerArea(key)
              normalized[key] = normalized[key] or {}

              if type(catches) == "table" then
                  for _, catch in ipairs(catches) do
                      if type(catch) == "table" then
                          table.insert(normalized[key], {
                              species = catch.species,
                              isShiny = catch.isShiny == true,
                              encounterType = catch.encounterType,
                              retroactive = catch.retroactive == true,
                              legacy = catch.legacy == true
                          })
                      end
                  end
              end

              if tostring(rawKey) ~= key then
                  changed = true
              end
          else
              -- Keep legacy/unknown tracker entries.
              normalized[rawKey] = catches
          end
      end

      return normalized, changed
  end

  ---------------------------------------------------------------------
  -- RETROACTIVE SAVE RECONSTRUCTION
  --
  -- This is deliberately best-effort.
  --
  -- The vanilla save has:
  --   save.visited       -> vanilla town/fly visitation history
  --   save.player.map    -> current location
  --   save.party         -> current party
  --   save.boxes         -> PC Pokemon
  --
  -- The engine does NOT store a historical route-travel log or a native
  -- catch-location on Pokemon. Therefore we cannot truthfully recreate
  -- every route ever walked or exact locations of old Pokemon.
  --
  -- We do, however:
  --   1. import vanilla visited-area information
  --   2. mark the current location visited
  --   3. preserve/normalize old mod tracker data
  --   4. display pre-mod Pokemon under LEGACY
  ---------------------------------------------------------------------

  local function collectLegacyMons(save)
      local mons = {}

      local function addFrom(list)
          if type(list) ~= "table" then
              return
          end

          for _, mon in ipairs(list) do
              if type(mon) == "table" and mon.species then
                  table.insert(mons, mon)
              end
          end
      end

      addFrom(save.party)

      for _, box in ipairs(save.boxes or {}) do
          addFrom(box)
      end

      if type(save.daycare) == "table" and type(save.daycare.mon) == "table" then
          addFrom({ save.daycare.mon })
      end

      return mons
  end

  local function addLegacyMonsToLog(save)
      local log = trackerLog()
      local legacy = log.__LEGACY__

      if type(legacy) ~= "table" then
          legacy = {}
      end

      local existing = {}

      for _, entry in ipairs(legacy) do
          if type(entry) == "table" then
              local species = tostring(entry.species or "")
              existing[species] = (existing[species] or 0) + 1
          end
      end

      local currentCounts = {}

      -- A Pokemon with catchLocation was caught after the tracker was active.
      -- It must never be copied into LEGACY just because it is present in the
      -- current save's party/boxes.
      for _, mon in ipairs(collectLegacyMons(save)) do
          if not mon.catchLocation then
              local species = tostring(mon.species or "")

              currentCounts[species] = (currentCounts[species] or 0) + 1

              if currentCounts[species] > (existing[species] or 0) then
                  table.insert(legacy, {
                      species = species,
                      isShiny = mon.dvs and Stats.isShiny(mon.dvs) or false,
                      legacy = true
                  })
              end
          end
      end

      -- Remove accidental legacy entries for Pokemon that the tracker already
      -- knows were caught in a real area.  This repairs saves that were loaded
      -- by an earlier version which incorrectly added current Pokemon to
      -- LEGACY.
      local knownCaught = {}
      for area, catches in pairs(log) do
          if area ~= "__LEGACY__" and type(catches) == "table" then
              for _, catch in ipairs(catches) do
                  if type(catch) == "table" and catch.species then
                      knownCaught[tostring(catch.species)] = true
                  end
              end
          end
      end

      local cleanedLegacy = {}
      for _, entry in ipairs(legacy) do
          if type(entry) == "table"
              and entry.species
              and not knownCaught[tostring(entry.species)] then
              table.insert(cleanedLegacy, entry)
          end
      end

      if #cleanedLegacy > 0 then
          log.__LEGACY__ = cleanedLegacy
      else
          log.__LEGACY__ = nil
      end

      mod.save:set("tracker_log", log)
  end

  ---------------------------------------------------------------------
  -- REBUILD TRACKER FROM AN EXISTING SAVE
  ---------------------------------------------------------------------
  local function rebuildTrackerFromSave(save)
      if type(save) ~= "table" then
          return
      end

      -------------------------------------------------------------------
      -- 1. Normalize anything already stored by older versions.
      -------------------------------------------------------------------
      local oldVisited = mod.save:get("visited_areas")

      if type(oldVisited) == "table" then
          local normalizedVisited, changed =
              normalizeMapTable(oldVisited)

          if changed then
              mod.save:set("visited_areas", normalizedVisited)
          end
      else
          mod.save:set("visited_areas", {})
      end

      local oldCaught = mod.save:get("caught_areas")

      if type(oldCaught) == "table" then
          local normalizedCaught, changed =
              normalizeMapTable(oldCaught)

          if changed then
              mod.save:set("caught_areas", normalizedCaught)
          end
      else
          mod.save:set("caught_areas", {})
      end

      local oldLog = mod.save:get("tracker_log")

      if type(oldLog) == "table" then
          local normalizedLog, changed =
              normalizeTrackerLog(oldLog)

          if changed then
              mod.save:set("tracker_log", normalizedLog)
          end
      else
          mod.save:set("tracker_log", {})
      end

      syncCaughtAreasFromLog()
      if type(mod.save:get("nuzlocke_losses")) ~= "number" then
          mod.save:set("nuzlocke_losses", 0)
      end

      -------------------------------------------------------------------
      -- 2. Discover every map definition exposed by the current build.
      -------------------------------------------------------------------
      discoverAllKnownAreas({ data = nil, save = save })

      -------------------------------------------------------------------
      -- 3. Import the vanilla save's visited table.
      --
      -- The engine itself stores vanilla town visitation in save.visited.
      -------------------------------------------------------------------
      if type(save.visited) == "table" then
          for mapId, wasVisited in pairs(save.visited) do
              if wasVisited then
                  registerArea(mapId)
                  markVisited(mapId)
              end
          end
      end

      -------------------------------------------------------------------
      -- 3. Always mark the player's current map.
      --
      -- This fixes old saves even when they have never been seen by the
      -- Nuzlocke mod before.
      -------------------------------------------------------------------
      if save.player and save.player.map then
          markVisited(save.player.map)
      end

      -------------------------------------------------------------------
      -- 4. Also use lastOutdoor/lastHeal when they refer to a tracked map.
      --
      -- These aren't a complete travel history, but they are reliable
      -- save-state evidence that the map was relevant to the playthrough.
      -------------------------------------------------------------------
      if type(save.lastOutdoor) == "table" then
          markVisited(save.lastOutdoor.id)
      end

      if type(save.lastHeal) == "table" then
          markVisited(save.lastHeal.map)
      end

      -------------------------------------------------------------------
      -- 5. Preserve any old mod catch log.
      --
      -- We intentionally DO NOT fabricate locations for old Pokemon.
      -------------------------------------------------------------------
      addLegacyMonsToLog(save)

      -------------------------------------------------------------------
      -- 6. Retroactive save compatibility.
      --
      -- If PALLET_TOWN has no caught entry yet, but the party/boxes
      -- contain a starter species, assign it now.  This handles saves
      -- that existed before v3.7 added starter tracking.
      --
      -- Similarly, any LEGACY-tagged Pokemon whose species exactly
      -- matches a known gift location is moved to that area's slot,
      -- provided that slot is still empty.
      -------------------------------------------------------------------
      local areas = caughtAreas()
      local log   = trackerLog()

      -- 6a. Starter → PALLET_TOWN
      if not areas["PALLET_TOWN"] then
          local starterSets = {
              BULBASAUR = true, CHARMANDER = true,
              SQUIRTLE = true, PIKACHU = true,
          }
          local function findStarterInList(list)
              for _, mon in ipairs(list or {}) do
                  if mon and starterSets[tostring(mon.species or ""):upper()] then
                      return mon
                  end
              end
              return nil
          end

          local starterMon = findStarterInList(save.party)
          if not starterMon then
              for _, box in ipairs(save.boxes or {}) do
                  starterMon = findStarterInList(box)
                  if starterMon then break end
              end
          end

          if starterMon then
              local sp = tostring(starterMon.species or ""):upper()
              registerArea("PALLET_TOWN")
              log["PALLET_TOWN"] = log["PALLET_TOWN"] or {}

              -- Only insert if not already in the log for this area.
              local alreadyLogged = false
              for _, entry in ipairs(log["PALLET_TOWN"]) do
                  if tostring(entry.species or ""):upper() == sp then
                      alreadyLogged = true; break
                  end
              end
              if not alreadyLogged then
                  table.insert(log["PALLET_TOWN"], {
                      species       = sp,
                      isShiny       = starterMon.dvs
                          and Stats.isShiny(starterMon.dvs) or false,
                      encounterType = "gift",
                      retroactive   = true,
                  })
              end

              areas["PALLET_TOWN"] = sp
              markVisited("PALLET_TOWN")

              -- Tag the mon so future loads don't re-assign it.
              if not starterMon.catchLocation then
                  starterMon.catchLocation = "PALLET_TOWN"
                  starterMon.encounterType = "gift"
              end
          end
      end

      -- 6b. LEGACY Pokemon that match known gift locations → move to area.
      --     Build a static gift lookup (version-neutral: try all entries).
      local staticGiftAreas = {
          MAGIKARP   = "ROUTE_4",
          HITMONCHAN = "SAFFRON_CITY",
          HITMONLEE  = "SAFFRON_CITY",
          LAPRAS     = "SILPH_CO",
          EEVEE      = "CELADON_CITY",
          OMANYTE    = "CINNABAR_ISLAND",
          KABUTO     = "CINNABAR_ISLAND",
          AERODACTYL = "CINNABAR_ISLAND",
          SCYTHER    = "CELADON_CITY",
          PORYGON    = "CELADON_CITY",
          DRATINI    = "CELADON_CITY",
          PINSIR     = "CELADON_CITY",
          JOLTEON    = "CELADON_CITY",
          VAPOREON   = "CELADON_CITY",
          FLAREON    = "CELADON_CITY",
      }

      -- Yellow-only gifts are version-gated. Older builds accidentally used
      -- these on Red/Blue and could manufacture a second CHARMANDER at Route 24.
      local rebuildVersion = "RED"
      pcall(function()
          local GameVersion = require("src.core.GameVersion")
          local v = tostring(GameVersion.get() or "RED"):upper()
          if v:find("YELLOW", 1, true) then
              rebuildVersion = "YELLOW"
          elseif v:find("BLUE", 1, true) then
              rebuildVersion = "BLUE"
          end
      end)
      if rebuildVersion == "YELLOW" then
          staticGiftAreas.BULBASAUR  = "CERULEAN_CITY"
          staticGiftAreas.CHARMANDER = "ROUTE_24"
          staticGiftAreas.SQUIRTLE   = "VERMILION_CITY"
      end
      local staticTradeAreas = {
          JYX        = "CERULEAN_CITY",
          FARFETCHD  = "VERMILION_CITY",
          MR_MIME    = "ROUTE_2",
          LICKITUNG  = "FUCHSIA_CITY",
          ELECTRODE  = "CINNABAR_ISLAND",
          GOLEM      = "CINNABAR_ISLAND",
          KANGASKHAN = "SAFARI_ZONE",
          MACHOKE    = "ROUTE_5",
      }

      local legacy = log["__LEGACY__"] or {}
      local remaining = {}
      for _, entry in ipairs(legacy) do
          if type(entry) == "table" and entry.species then
              local sp = tostring(entry.species):upper()
              local targetArea = staticGiftAreas[sp] or staticTradeAreas[sp]
              local etype      = staticGiftAreas[sp] and "gift" or "trade"

              if targetArea and not areas[targetArea] then
                  -- Move this entry from LEGACY to its known area.
                  registerArea(targetArea)
                  log[targetArea] = log[targetArea] or {}
                  local alreadyLogged = false
                  for _, e in ipairs(log[targetArea]) do
                      if tostring(e.species or ""):upper() == sp then
                          alreadyLogged = true; break
                      end
                  end
                  if not alreadyLogged then
                      table.insert(log[targetArea], {
                          species       = sp,
                          isShiny       = entry.isShiny == true,
                          encounterType = etype,
                          retroactive   = true,
                      })
                  end
                  areas[targetArea] = sp
                  markVisited(targetArea)
              else
                  table.insert(remaining, entry)
              end
          end
      end

      if #remaining > 0 then
          log["__LEGACY__"] = remaining
      else
          log["__LEGACY__"] = nil
      end

      -- Repair old bad migration data only. Red/Blue do not have a Route 24
      -- Charmander gift. Older builds could create one during migration, and
      -- older normalization could strip the retroactive marker.
      if rebuildVersion ~= "YELLOW" then
          local entries = log["ROUTE_24"]
          if type(entries) == "table" then
              local kept = {}
              for _, entry in ipairs(entries) do
                  local species = tostring(entry and entry.species or ""):upper()
                  local encounterType = tostring(entry and entry.encounterType or ""):lower()
                  local migratedCharmander =
                      species == "CHARMANDER"
                      and (entry.retroactive == true or encounterType == "gift")
                  if not migratedCharmander then
                      kept[#kept + 1] = entry
                  end
              end
              if #kept > 0 then
                  log["ROUTE_24"] = kept
              else
                  log["ROUTE_24"] = nil
                  areas["ROUTE_24"] = nil
              end
          end

          -- Red/Blue never have a Charmander gift on Route 24. Older
          -- migration code could nevertheless manufacture one. Remove every
          -- non-Pallet Charmander so the starter remains the single Charmander
          -- encounter shown by the log.
          for areaKeyValue, entries in pairs(log) do
              if areaKeyValue ~= "PALLET_TOWN" and type(entries) == "table" then
                  local kept = {}
                  for _, entry in ipairs(entries) do
                      if tostring(entry and entry.species or ""):upper() ~= "CHARMANDER" then
                          kept[#kept + 1] = entry
                      end
                  end
                  if #kept > 0 then
                      log[areaKeyValue] = kept
                  else
                      log[areaKeyValue] = nil
                      areas[areaKeyValue] = nil
                  end
              end
          end
      end

      -- De-duplicate identical species entries inside a single area. This is
      -- deliberately per-area: legitimate gift/trade species can coexist in
      -- the same city, but the same species must never be logged twice for the
      -- same encounter area.
      for areaKeyValue, entries in pairs(log) do
          if type(entries) == "table" then
              local seenSpecies = {}
              local kept = {}
              for _, entry in ipairs(entries) do
                  if type(entry) == "table" and entry.species then
                      local speciesKey = tostring(entry.species):upper()
                      if not seenSpecies[speciesKey] then
                          seenSpecies[speciesKey] = true
                          kept[#kept + 1] = entry
                      end
                  end
              end
              if #kept > 0 then
                  log[areaKeyValue] = kept
              elseif areaKeyValue ~= "__LEGACY__" then
                  log[areaKeyValue] = nil
                  areas[areaKeyValue] = nil
              end
          end
      end

      -- Re-sync the area map after the migration cleanup so a deleted bad log
      -- entry cannot leave a phantom catch on the tracker MAP.
      local normalizedAreas, areasChanged = normalizeMapTable(areas)
      if areasChanged then
          areas = normalizedAreas
      end

      mod.save:set("tracker_log",   log)
      mod.save:set("caught_areas",  areas)
  end

  ---------------------------------------------------------------------
  -- INITIAL SAVE-LOAD RECONSTRUCTION
  --
  -- save.loaded fires after the save has been restored/validated.
  -- This lets a newly installed version of the mod work with an old
  -- vanilla save that has never had Nuzlocke modData before.
  ---------------------------------------------------------------------
  mod.events:on("save.loaded", function(ev)
      if ev and ev.save then
          currentSave = ev.save
          if currentGame then currentGame.save = ev.save end
          rebuildTrackerFromSave(ev.save)
      end
  end)

  ---------------------------------------------------------------------
  -- RULE DEFINITIONS
  ---------------------------------------------------------------------
  local LEGENDARIES = {
      ARTICUNO = true,
      ZAPDOS   = true,
      MOLTRES  = true,
      MEWTWO   = true,
  }

  local MYTHICALS = {
      MEW = true,
  }

  local ruleCategories = {
      {
          title = "- CORE -",
          rules = {
              { key = "nuzlocke_enabled", name = "Nuzlocke", desc = "Master switch for all Nuzlocke rules. Toggle this off to disable everything." },
              { key = "permadeath",       name = "Permadeath", desc = "Fainted Pokemon are considered dead and removed from the party." },
              { key = "encounter_limit",  name = "1st Catch", desc = "Only the first eligible catch per area can be caught." },
              { key = "failed_encounter", name = "Failed Encounters", desc = "If ON, your first eligible wild/overworld encounter consumes the area even if you defeat it, flee, or fail to catch it. Dupes encounters do not consume the area while Dupes Clause is ON; shiny Pokemon are always allowed when Shiny Clause is ON." },
              { key = "nickname_rule",   name = "Nickname Rule", desc = "You must enter a nickname for every Pokemon you catch." },
          }
      },
      {
          title = "- CLAUSES -",
          rules = {
              { key = "dupes_mode",      name = "Dupes Clause", desc = "Previously caught duplicate families do not count as the area encounter and cannot be caught, unless shiny." },
              { key = "shiny_clause",    name = "Shiny Clause", desc = "Shiny Pokemon are always allowed as catches, even when they would otherwise violate 1st Catch or Dupes." },
          }
      },
      {
          title = "- GENERAL -",
          rules = {
              { key = "overworld_encounters", name = "Overworld", desc = "Allow Pokemon caught from overworld spawns to count as area encounters." },
              { key = "town_catches",         name = "Town Catches", desc = "Allow Pokemon caught in towns/cities to count as encounters. Pallet Town starter slot is always tracked regardless." },
              { key = "ban_legendaries",      name = "No Legend", desc = "Legendary Pokemon (Articuno, Zapdos, Moltres, Mewtwo) cannot be caught or used." },
              { key = "ban_mythicals",        name = "No Mythic", desc = "Mythical Pokemon (Mew) cannot be caught or used." },
              { key = "allow_gifts",      name = "Gift Pokemon", desc = "Gift Pokemon (Eevee, Lapras, Fossils, etc.) are allowed and consume the area slot where they were received." },
              { key = "allow_trades",     name = "In-Game Trades", desc = "In-game traded Pokemon are allowed and consume the area slot where the trade NPC lives. Version-specific trades (Red/Blue/Yellow) are all accounted for." },
          }
      },
      {
          title = "- HARDCORE -",
          rules = {
              { key = "hardcore_mode",    name = "Level Caps", desc = "Max level = next Gym Leader ace. Experience is capped automatically." },
              { key = "no_healing_items", name = "No Healing Items", desc = "Potions, Revives, and status-healing items cannot be used in battle." },
              { key = "no_battle_items",  name = "No X Items", desc = "X Attack, X Defend, and similar non-healing battle items cannot be used in battle. Poke Balls are unaffected." },
          }
      },
      {
          title = "- IRONMON -",
          rules = {
              { key = "no_shopping",     name = "No Shop", desc = "Cannot buy from Poke Marts. The clerk will politely refuse you." },
              { key = "no_poke_center",  name = "No PokeCenter", desc = "Cannot heal at Pokemon Centers. Nurse Joy will turn you away." },
              { key = "no_mom_heal",      name = "No Mom Heal", desc = "Mom cannot heal your party when you visit home. She will remind you of your rules instead." },
              { key = "whiteout_clause",  name = "Whiteout", desc = "A total party KO is survivable. The normal game whiteout sends you back without restoring dead Pokemon." },
              { key = "solo_active",      name = "Solo Only", desc = "Only one Pokemon in the active party slot. Enforced at catch time; does not block PC swaps." },
          }
      },
      {
          title = "- UI -",
          rules = {
              { key = "catch_info", name = "Catch Info", desc = "Show CATCH INFO in the party menu for Pokemon you own." },
              { key = "area_guide_enabled", name = "Area Guide", desc = "Show the second Encounter Tracker page with all catchable areas. Turn OFF to restrict the tracker to your catches only." },
          }
      },
  }


  ---------------------------------------------------------------------
  -- AREA GUIDE STATE
  --
  -- Area Guide is a normal Nuzlocke setting. The creator's mod uses
  -- mod.save for Nuzlocke state, so keep the setting there rather than
  -- using a separate storage layer that can return stale data.
  ---------------------------------------------------------------------
  local areaGuideEnabled = true

  local function loadAreaGuideState()
      local saved = mod.save:get("area_guide_enabled", nil)

      if type(saved) ~= "boolean" then
          saved = mod.save:get("route_list_all_areas", nil)
      end
      if type(saved) ~= "boolean" then
          saved = mod.save:get("show_checklist", nil)
      end

      if type(saved) == "boolean" then
          areaGuideEnabled = saved
      end

      return areaGuideEnabled
  end

  local function saveAreaGuideState(value)
      areaGuideEnabled = value == true
      mod.save:set("area_guide_enabled", areaGuideEnabled)
      return areaGuideEnabled
  end

  local SETUP_PROFILE_FILE = "nuzlocke_setup_profile.lua"

  -- Shared rules profile used by the title-screen setup and the active save.
  -- When no save is loaded yet this is the staged setup for the next save.
  -- When a save is active it mirrors that save, so both menus stay in sync.
  local pendingNewGameRules = nil
  local pendingRulesDirty = false
  local pendingNewGameRulesForNextSave = false
  -- Immutable snapshot captured at the instant NEW GAME is selected.
  -- This is deliberately separate from the live UI mirror so later save
  -- initialization cannot replace selected OFF->ON values with defaults.
  local newGameRulesSnapshot = nil
  local newGameRulesCommitPending = false
  local newGameCommitPassesRemaining = 0

  -- These keys persist the staged setup independently of the active save-rule
  -- keys.  They are declared here and used after copyRuleProfile is defined.
  local STAGED_PROFILE_KEY = "__nuzlocke_staged_new_game_profile"
  local STAGED_INTENT_KEY = "__nuzlocke_staged_new_game_intent"

  ---------------------------------------------------------------------
  -- NEW GAME STARTER SETTINGS
  -- These values are read only when a brand-new save is constructed.
  -- Existing saves are never rewritten by this hook.
  ---------------------------------------------------------------------
  mod.hooks:wrap("save.new_game", function(next, save)
      local result = next(save)
      currentSave = result or save or currentSave
      if currentGame and currentSave then currentGame.save = currentSave end

      -- Agreed defaults for a new Nuzlocke run. The player can change these
      -- in NZLCKE SETUP before starting the NEW GAME.
      local startingMoney = 0
      local startingBalls = 0
      local profile = newGameRulesSnapshot or pendingNewGameRules
      if profile then
          startingMoney = math.max(0, math.min(9999,
              tonumber(profile.starting_money) or 0))
          startingBalls = math.max(0, math.min(99,
              tonumber(profile.starting_pokeballs) or 0))
      end

      result.money = startingMoney
      result.pcItems = result.pcItems or {}
      result.pcItems.POKE_BALL = startingBalls

      return result
  end)

  local function defaultRuleValue(key)
      if key == "starting_money" then
          return 0      -- NEW GAME default; configurable in SETUP
      end
      if key == "starting_pokeballs" then
          return 0      -- NEW GAME default; placed in the room PC
      end
      if key == "nuzlocke_enabled" or key == "permadeath" then
          return true
      end
      if key == "area_guide_enabled" then
          return true
      end
      if key == "rules_locked" then
          return false
      end
      -- Core/general defaults for a new Nuzlocke run.
      -- These are the requested startup defaults; once the save exists,
      -- the active save is authoritative and in-game toggles override them.
      if key == "encounter_limit" or key == "failed_encounter" or key == "allow_gifts"
          or key == "allow_trades" or key == "catch_info" then
          return true
      end
      if key == "overworld_encounters" or key == "town_catches"
          or key == "no_healing_items" or key == "no_battle_items"
          or key == "no_mom_heal" then
          return false
      end
      return false
  end

  local function makeDefaultPreGameRules()
      local values = {}
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              values[rule.key] = defaultRuleValue(rule.key)
          end
      end
      values.starting_money = defaultRuleValue("starting_money")
      values.starting_pokeballs = defaultRuleValue("starting_pokeballs")
      return values
  end

  local function makeRulesFromCurrentSave()
      local values = makeDefaultPreGameRules()

      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              values[rule.key] =
                  mod.save:get(rule.key, defaultRuleValue(rule.key))
          end
      end

      values.area_guide_enabled = loadAreaGuideState()
      values.rules_locked =
          mod.save:get("rules_locked", defaultRuleValue("rules_locked")) == true

      return values
  end

  local function routeListShowsAll()
      return areaGuideEnabled == true
  end

  ---------------------------------------------------------------------
  -- COMMIT STAGED NEW-GAME RULES
  --
  -- NEW GAME is identified by the explicit staging flag set by the title
  -- menu. Do not inspect whether mod.save already contains rule keys: the
  -- engine may populate defaults before save.loaded, which can otherwise
  -- make valid startup selections look like they were never chosen.
  --
  -- The helper runs from BOTH save.loaded and game.ready. Whichever lifecycle
  -- event sees the staged flag first commits it; the other event simply
  -- mirrors the now-authoritative save.
  ---------------------------------------------------------------------
  local function copyRuleProfile(source)
      local copy = {}
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              local v = source and source[rule.key]
              if v == nil then v = defaultRuleValue(rule.key) end
              copy[rule.key] = (v == true)
          end
      end
      copy.area_guide_enabled = source and source.area_guide_enabled ~= false
          or defaultRuleValue("area_guide_enabled")
      copy.rules_locked = false
      copy.starting_money = math.max(0, math.min(9999,
          tonumber(source and source.starting_money) or defaultRuleValue("starting_money")))
      copy.starting_pokeballs = math.max(0, math.min(99,
          tonumber(source and source.starting_pokeballs) or defaultRuleValue("starting_pokeballs")))
      return copy
  end

  local function serializeSetupValue(v)
      if type(v) == "boolean" then
          return v and "true" or "false"
      elseif type(v) == "number" then
          return tostring(v)
      elseif type(v) == "string" then
          return string.format("%q", v)
      end
      return "nil"
  end

  local function serializeSetupProfile(profile)
      local keys = {}
      for k, _ in pairs(profile or {}) do keys[#keys + 1] = k end
      table.sort(keys)
      local out = { "return {" }
      for _, k in ipairs(keys) do
          out[#out + 1] = "[" .. string.format("%q", k) .. "]="
              .. serializeSetupValue(profile[k]) .. ","
      end
      out[#out + 1] = "}"
      return table.concat(out, "\n")
  end

  local function saveSetupProfileToDisk(profile)
      if not (love and love.filesystem and love.filesystem.write) then
          return false
      end
      local ok = love.filesystem.write(
          SETUP_PROFILE_FILE,
          serializeSetupProfile(copyRuleProfile(profile))
      )
      return ok == true
  end

  local function loadSetupProfileFromDisk()
      if not (love and love.filesystem and love.filesystem.getInfo
          and love.filesystem.read) then
          return nil
      end
      if not love.filesystem.getInfo(SETUP_PROFILE_FILE) then
          return nil
      end
      local raw = love.filesystem.read(SETUP_PROFILE_FILE)
      if type(raw) ~= "string" or raw == "" then return nil end
      local chunk = loadstring(raw)
      if not chunk then return nil end
      local ok, profile = pcall(chunk)
      if not ok or type(profile) ~= "table" then return nil end
      return copyRuleProfile(profile)
  end

  local function persistStagedProfile(profile)
      if not profile then return end
      mod.save:set(STAGED_PROFILE_KEY, copyRuleProfile(profile))
      mod.save:set(STAGED_INTENT_KEY, true)
  end

  local function loadPersistedStagedProfile()
      if mod.save:get(STAGED_INTENT_KEY, false) ~= true then
          return nil
      end
      local profile = mod.save:get(STAGED_PROFILE_KEY, nil)
      if type(profile) ~= "table" then
          return nil
      end
      return copyRuleProfile(profile)
  end

  local function clearPersistedStagedProfile()
      mod.save:set(STAGED_INTENT_KEY, false)
      mod.save:set(STAGED_PROFILE_KEY, nil)
  end

  local function saveCurrentSetupProfile()
      if not pendingNewGameRules then
          pendingNewGameRules = makeDefaultPreGameRules()
      end
      local profile = copyRuleProfile(pendingNewGameRules)
      return saveSetupProfileToDisk(profile)
  end

  local function saveCurrentInGameRules()
      if not pendingNewGameRules then
          pendingNewGameRules = makeRulesFromCurrentSave()
      end

      local profile = copyRuleProfile(pendingNewGameRules)
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              mod.save:set(rule.key, profile[rule.key] == true)
          end
      end
      saveAreaGuideState(profile.area_guide_enabled == true)
      mod.save:set("rules_locked", profile.rules_locked == true)

      pendingNewGameRules = copyRuleProfile(profile)
      pendingRulesDirty = false
      areaGuideEnabled = profile.area_guide_enabled == true
      return true
  end

  local function loadSavedSetupIntoPending()
      local profile = loadSetupProfileFromDisk()
      if profile then
          pendingNewGameRules = profile
          pendingRulesDirty = false
          return true
      end
      return false
  end

  local function stageNewGameProfile()
      -- The durable profile is the preferred source at the NEW GAME boundary.
      -- If the player changed the screen and did not press SAVE, use the live
      -- profile they are looking at; otherwise recover the explicitly saved
      -- profile from disk.
      local saved = loadSetupProfileFromDisk()
      if saved and not pendingRulesDirty then
          pendingNewGameRules = saved
      end
      pendingNewGameRules = copyRuleProfile(pendingNewGameRules or makeDefaultPreGameRules())
      newGameRulesSnapshot = copyRuleProfile(pendingNewGameRules)
      persistStagedProfile(newGameRulesSnapshot)
      pendingNewGameRulesForNextSave = true
      newGameRulesCommitPending = true
      newGameCommitPassesRemaining = 12
  end

  local function applyNewGameSnapshot()
      if not newGameRulesCommitPending or not newGameRulesSnapshot then
          return false
      end

      local profile = newGameRulesSnapshot
      local allVerified = true

      -- Explicitly write EVERY registered rule, including false values.
      -- This is the critical distinction from relying on missing save keys:
      -- an OFF selection is a real selection, not permission to use defaults.
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              local expected = profile[rule.key] == true
              mod.save:set(rule.key, expected)
          end
      end

      saveAreaGuideState(profile.area_guide_enabled == true)
      mod.save:set("rules_locked", false)

      -- Verify against the active save.  Keep the snapshot alive if another
      -- engine initialization pass overwrites it; the next lifecycle pass
      -- will stamp the same snapshot again.
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              local expected = profile[rule.key] == true
              local actual = mod.save:get(rule.key, nil)
              if actual ~= expected then
                  allVerified = false
              end
          end
      end
      local guideActual = mod.save:get("area_guide_enabled", nil)
      if guideActual ~= (profile.area_guide_enabled == true) then
          allVerified = false
      end

      if allVerified then
          newGameRulesCommitPending = false
          pendingNewGameRulesForNextSave = false
          pendingRulesDirty = false
          pendingNewGameRules = copyRuleProfile(profile)
          areaGuideEnabled = profile.area_guide_enabled == true
          newGameRulesSnapshot = nil
          newGameCommitPassesRemaining = 0
          clearPersistedStagedProfile()
          return true
      end

      return false
  end

  local function refreshRuleMirrorFromSave()
      -- Do not replace a still-pending new-game profile with the save's
      -- defaults.  That was the source of setup choices such as Level Caps
      -- and No X Items being lost when a fresh save was first loaded.
      if pendingNewGameRulesForNextSave and pendingNewGameRules then
          return
      end
      pendingNewGameRules = makeRulesFromCurrentSave()
      areaGuideEnabled = pendingNewGameRules.area_guide_enabled ~= false
      pendingRulesDirty = false
  end

  local function recoverNewGameSnapshotIfNeeded()
      if newGameRulesCommitPending and newGameRulesSnapshot then
          return true
      end
      local persisted = loadPersistedStagedProfile()
      if persisted then
          newGameRulesSnapshot = persisted
          pendingNewGameRules = copyRuleProfile(persisted)
          pendingNewGameRulesForNextSave = true
          newGameRulesCommitPending = true
          newGameCommitPassesRemaining = math.max(newGameCommitPassesRemaining, 12)
          return true
      end
      return false
  end

  ---------------------------------------------------------------------
  -- DEFINITIVE NEW-GAME COMMIT
  --
  -- The example_silly_oak mod uses intro.oak_speech.finished to write
  -- answers into mod.save.  That is the important lifecycle seam here:
  -- by the time Oak's intro has finished, the new game's mod.save exists and
  -- is the correct per-save home for Nuzlocke state.  The title-screen
  -- profile is therefore only the source configuration; this event performs
  -- the definitive transfer into the actual save.
  ---------------------------------------------------------------------
  local function commitDurableSetupProfileToActiveSave()
      local profile = loadSetupProfileFromDisk()
      if not profile then return false end

      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              mod.save:set(rule.key, profile[rule.key] == true)
          end
      end
      saveAreaGuideState(profile.area_guide_enabled == true)
      mod.save:set("rules_locked", false)

      local verified = true
      for _, cat in ipairs(ruleCategories) do
          for _, rule in ipairs(cat.rules) do
              if mod.save:get(rule.key, nil) ~= (profile[rule.key] == true) then
                  verified = false
                  break
              end
          end
          if not verified then break end
      end
      if mod.save:get("area_guide_enabled", nil) ~= (profile.area_guide_enabled == true) then
          verified = false
      end

      if verified then
          pendingNewGameRules = copyRuleProfile(profile)
          pendingNewGameRulesForNextSave = false
          pendingRulesDirty = false
          areaGuideEnabled = profile.area_guide_enabled == true
          newGameRulesSnapshot = nil
          newGameRulesCommitPending = false
          newGameCommitPassesRemaining = 0
          clearPersistedStagedProfile()
      end
      return verified
  end

  mod.events:on("intro.oak_speech.finished", function()
      -- Only consume a profile when this is a NEW GAME transition.  A
      -- CONTINUE load never runs the Oak intro, so this event cannot alter an
      -- existing save.
      commitDurableSetupProfileToActiveSave()
  end)

  mod.events:on("save.loaded", function(ev)
      if ev and ev.save then currentSave = ev.save end
      if recoverNewGameSnapshotIfNeeded() then
          applyNewGameSnapshot()
      else
          refreshRuleMirrorFromSave()
      end
  end)

  mod.events:on("game.ready", function(game)
      currentGame = game or currentGame
      currentSave = (game and game.save) or currentSave
      if recoverNewGameSnapshotIfNeeded() then
          applyNewGameSnapshot()
      else
          refreshRuleMirrorFromSave()
      end
  end)

  -- A few engine systems initialize save-backed data during the first frames
  -- after game.ready.  Re-apply the immutable NEW GAME snapshot during that
  -- short window.  This is intentionally finite and only runs for a staged
  -- brand-new game; existing saves are never touched.
  mod.events:on("world.stepped", function()
      if recoverNewGameSnapshotIfNeeded() and newGameCommitPassesRemaining > 0 then
          newGameCommitPassesRemaining = newGameCommitPassesRemaining - 1
          applyNewGameSnapshot()
      end
  end)

  ---------------------------------------------------------------------
  -- ACTIVE CHECK
  ---------------------------------------------------------------------
  local function active(game, battle)
      if mod.save:get("nuzlocke_enabled", true) == false then
          return false
      end

      if not (game and game.save) then
          return false
      end

      if battle and (battle.demo or battle.ghost) then
          return false
      end

      return true
  end

  ---------------------------------------------------------------------
  -- LEVEL CAP ENFORCEMENT
  --
  -- Gen 1's badge order is the natural progression order.  The cap is the
  -- ace level of the first badge the player has not earned yet.  This mirrors
  -- the usual Nuzlocke convention and keeps the rule independent of map order.
  ---------------------------------------------------------------------
  local LEVEL_CAPS = { 14, 21, 24, 29, 43, 43, 47, 50, 100 }
  local LEVEL_CAP_GYM_LEADERS = {
      "BROCK", "MISTY", "LT SURGE", "ERIKA",
      "KOGA", "SABRINA", "BLAINE", "GIOVANNI", "MAX"
  }

  local function currentBadgeCount(save)
      local inventory = save and save.inventory or {}
      local badges = Data.constants and Data.constants.badges or {
          { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" },
          { id = "THUNDERBADGE" }, { id = "RAINBOWBADGE" },
          { id = "SOULBADGE" }, { id = "MARSHBADGE" },
          { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
      }
      local count = 0
      for i, badge in ipairs(badges) do
          local id = badge.id or badge.item or badge.key
          if id and (inventory[id] == true or tonumber(inventory[id]) and tonumber(inventory[id]) > 0) then
              count = i
          else
              break
          end
      end
      return count
  end

  local function nextLevelCap(save)
      return LEVEL_CAPS[math.min(currentBadgeCount(save) + 1, #LEVEL_CAPS)] or 100
  end

  local function nextLevelCapInfo(save)
      local index = math.min(currentBadgeCount(save) + 1, #LEVEL_CAPS)
      return LEVEL_CAPS[index] or 100, LEVEL_CAP_GYM_LEADERS[index] or "MAX"
  end

  local function capExperienceForMon(mon, cap)
      local def = Data.pokemon and Data.pokemon[mon and mon.species]
      if not def or not cap then return nil end
      local ok, value = pcall(Growth.expForLevel, def.growthRate, cap)
      if ok then return value end
      return nil
  end

  -- Experience.apply exposes exp.gain as a public hook.  The engine's EXP
  -- hook context contains the Pokemon but not the Game/Save object, so use the
  -- save reference maintained by save.loaded/save.new_game/game.ready rather
  -- than a potentially stale game object.  The level check is authoritative:
  -- once a Pokemon is at the current cap, it gets zero EXP; below the cap, its
  -- normal EXP gain is preserved and only the amount that would cross the cap
  -- is trimmed.
  mod.hooks:wrap("exp.gain", function(next, ctx)
      if not ctx or not ctx.mon then
          return next(ctx)
      end

      if mod.save:get("hardcore_mode", false) ~= true then
          return next(ctx)
      end

      local save = currentSave or (currentGame and currentGame.save)
      local cap = nextLevelCap(save)
      if not cap then
          return next(ctx)
      end

      if (tonumber(ctx.mon.level) or 1) >= cap then
          return 0
      end

      local maxExp = capExperienceForMon(ctx.mon, cap)
      local currentExp = tonumber(ctx.mon.exp) or 0
      local gained = next(ctx)
      if not maxExp then
          return gained
      end

      local allowed = math.max(0, maxExp - currentExp)
      return math.max(0, math.min(tonumber(gained) or 0, allowed))
  end, 1000)

  local function countTrackerCatches()
      local total = 0
      for key, entries in pairs(trackerLog()) do
          if key ~= "__LEGACY__" and type(entries) == "table" then
              for _, entry in ipairs(entries) do
                  if type(entry) == "table" and entry.species then total = total + 1 end
              end
          end
      end
      return total
  end

  local function countCaughtAreas()
      local total = 0
      for key, value in pairs(caughtAreas()) do
          if key ~= "__LEGACY__" and value ~= nil then total = total + 1 end
      end
      return total
  end

  ---------------------------------------------------------------------
  -- FLAT RULE LIST
  -- MISC is deliberately NEW-GAME ONLY and is never included in active-save
  -- RULES.
  ---------------------------------------------------------------------
  local function buildFlatItemList(preGame)
      local list = {}

      table.insert(list, {
          isHeader = false,
          isControl = true,
          rule = {
              key = "rules_locked",
              name = "Lock Rules",
              desc = "Lock all Nuzlocke rules in place. The LOCK control itself can always be toggled."
          }
      })

      for _, cat in ipairs(ruleCategories) do
          table.insert(list, { isHeader = true, name = cat.title })
          for _, rule in ipairs(cat.rules) do
              table.insert(list, { isHeader = false, rule = rule })
          end
      end

      if not preGame then
          table.insert(list, {
              isHeader = false,
              isControl = true,
              isInGameSave = true,
              rule = {
                  key = "save_in_game_rules",
                  name = "Save Rules",
                  desc = "Save the current NUZLOCKE RULES to the active game save."
              }
          })
      end

      if preGame then
          table.insert(list, { isHeader = true, name = "- MISC -" })
          table.insert(list, {
              isHeader = false,
              rule = {
                  key = "starting_money", name = "Money", numeric = true, digits = 4,
                  min = 0, max = 9999,
                  desc = "Starting money for NEW GAME. You will have this money when the new game begins. Press A to edit; LEFT/RIGHT selects a digit; UP/DOWN changes it."
              }
          })
          table.insert(list, {
              isHeader = false,
              rule = {
                  key = "starting_pokeballs", name = "Poke Balls", numeric = true, digits = 2,
                  min = 0, max = 99,
                  desc = "Starting Poke Balls for NEW GAME. They are placed in the PC in your room. Press A to edit; LEFT/RIGHT selects a digit; UP/DOWN changes it."
              }
          })
          table.insert(list, {
              isHeader = false,
              isControl = true,
              isSetupSave = true,
              rule = {
                  key = "save_setup_options",
                  name = "Save Setup",
                  desc = "Save these NUZLOCKE SETUP options for the next NEW GAME. The saved profile is kept separately from your game save."
              }
          })
      end

      return list
  end

  local function getConfigValue(key, preGame)
      if preGame then
          if not pendingNewGameRules then
              pendingNewGameRules = makeDefaultPreGameRules()
          end
          return pendingNewGameRules[key]
      end

      if key == "area_guide_enabled" then
          return routeListShowsAll()
      end

      local stored = mod.save:get(key, defaultRuleValue(key))
      if key == "starting_money" or key == "starting_pokeballs" then
          return tonumber(stored) or defaultRuleValue(key)
      end
      return stored == true
  end


  local function setConfigValue(key, value, preGame)
      if key == "starting_money" then
          value = math.max(0, math.min(9999, math.floor(tonumber(value) or 0)))
      elseif key == "starting_pokeballs" then
          value = math.max(0, math.min(99, math.floor(tonumber(value) or 0)))
      else
          value = value == true
      end

      if preGame then
          if not pendingNewGameRules then
              pendingNewGameRules = makeDefaultPreGameRules()
          end
          pendingNewGameRules[key] = value
          pendingRulesDirty = true

          if key == "area_guide_enabled" then
              areaGuideEnabled = value
          end
          return
      end

      if key == "area_guide_enabled" then
          saveAreaGuideState(value)
      else
          mod.save:set(key, value)
      end


      -- Keep the title-screen representation synchronized with the active save.
      if not pendingNewGameRules then
          pendingNewGameRules = makeDefaultPreGameRules()
      end
      pendingNewGameRules[key] = value
      pendingRulesDirty = false
  end

  ---------------------------------------------------------------------
  -- SET MODE
  --
  -- Set Mode is intentionally NOT duplicated in the Nuzlocke rules.
  -- The game's native OPTIONS -> BATTLE STYLE setting is the sole source
  -- of truth.  This mod does not add a second Set Mode toggle or attempt
  -- to synchronize a duplicate setting.
  ---------------------------------------------------------------------

  ---------------------------------------------------------------------
  -- GENERIC MENU MARQUEE

  -- Keep text inside the original menu-width budget.  It waits 3 seconds
  -- before slowly scrolling back and forth.
  ---------------------------------------------------------------------
  local function marqueeText(text, width, elapsed, secondsPerStep)
      text = tostring(text or "")
      if #text <= width then
          return text
      end
      if elapsed < 3 then
          return text:sub(1, width)
      end
      local maxOffset = #text - width
      secondsPerStep = secondsPerStep or 2.4
      local step = math.floor((elapsed - 3) / secondsPerStep)
      local cycle = maxOffset * 2
      local pos = 0
      if cycle > 0 then
          local phase = step % cycle
          if phase <= maxOffset then
              pos = phase
          else
              pos = cycle - phase
          end
      end
      return text:sub(pos + 1, pos + width)
  end

  ---------------------------------------------------------------------
  -- VANILLA MENU MARQUEE
  -- The recomp's Menu already grows its box for long labels.  For our
  -- Nuzlocke entries we additionally keep the visible label inside the
  -- original 10-character menu width and scroll it after 3 seconds.
  -- Only items marked nuzlockeMarquee are affected.
  ---------------------------------------------------------------------
  do
      local Menu = require("src.ui.Menu")
      local originalMenuDraw = Menu.draw
      if not Menu.__nuzlockeMarqueePatched then
          Menu.__nuzlockeMarqueePatched = true
          function Menu:draw(...)
              local now = love.timer and love.timer.getTime
                  and love.timer.getTime() or 0
              for _, item in ipairs(self.items or {}) do
                  if item and item.nuzlockeMarquee and item.label then
                      item._nzlMarqueeTime = item._nzlMarqueeTime or now
                  end
              end

              local savedLabels = {}
              for i, item in ipairs(self.items or {}) do
                  if item and item.nuzlockeMarquee then
                      savedLabels[i] = item.label
                      local sourceLabel = item.nuzlockeMarqueeLabel or item.label
                      local elapsed = now - (item._nzlMarqueeTime or now)
                      item.label = marqueeText(sourceLabel, 10, elapsed)
                  end
              end

              originalMenuDraw(self, ...)

              for i, label in pairs(savedLabels) do
                  if self.items[i] then
                      self.items[i].label = label
                  end
              end
          end
      end
  end

  ---------------------------------------------------------------------
  -- REGISTER CONFIG SCREEN
  ---------------------------------------------------------------------
  mod.content.screens:register("NuzlockeConfigScreen", {
      new = function(game, ctx)
          local preGame = ctx and ctx.preGame == true

          if preGame and not pendingNewGameRules then
              pendingNewGameRules = loadSetupProfileFromDisk()
                  or makeDefaultPreGameRules()
          elseif not preGame then
              discoverAllKnownAreas(game)
              -- The active save is authoritative when entering the in-game menu.
              if not pendingRulesDirty then
                  pendingNewGameRules = makeRulesFromCurrentSave()
              end
              areaGuideEnabled =
                  pendingNewGameRules.area_guide_enabled ~= false
          end

          local flatItemList = buildFlatItemList(preGame)

          local self = {
              game = game,
              isOpaque = true,
              preGame = preGame,
              cursor = 1,
              scroll = 0,
              pageSize = 3,
              descScroll = 0,
              marqueeTime = 0,
              editingNumber = false,
              digitIndex = 1,
              inGameSaveFlash = 0
          }

          function self:update(dt)
              -- The title-screen setup has no active save.  Do not query or
              -- mutate save-backed map state while editing the staged setup.
              if not self.preGame then
                  local currentKey = areaKey(self.game, nil)
                  if currentKey then
                      markVisited(currentKey)
                  end
              end

              self.marqueeTime = self.marqueeTime + (dt or 0)
              if self.setupSaveFlash and self.setupSaveFlash > 0 then
                  self.setupSaveFlash = math.max(0, self.setupSaveFlash - (dt or 0))
              elseif self.setupSaveFlash and self.setupSaveFlash < 0 then
                  self.setupSaveFlash = math.min(0, self.setupSaveFlash + (dt or 0))
              end

              if self.inGameSaveFlash and self.inGameSaveFlash > 0 then
                  self.inGameSaveFlash = math.max(0, self.inGameSaveFlash - (dt or 0))
              elseif self.inGameSaveFlash and self.inGameSaveFlash < 0 then
                  self.inGameSaveFlash = math.min(0, self.inGameSaveFlash + (dt or 0))
              end

              if self.game.input:wasPressed("b") then
                  if self.editingNumber then
                      self.editingNumber = false
                      self.digitIndex = 1
                      self.descScroll = 0
                  else
                      self.game.stack:pop()
                  end
                  return
              end

              local function moveCursor(dir)
                  local target = self.cursor

                  repeat
                      target = target + dir

                      if target < 1 then
                          target = 1
                      end

                      if target > #flatItemList then
                          target = #flatItemList
                      end
                  until not flatItemList[target].isHeader

                  self.cursor = target
                  self.descScroll = 0
              end

              local function selectedItem()
                  return flatItemList[self.cursor]
              end

              local function activateControl(item)
                  if not item or not item.isControl then return false end
                  if item.isSetupSave and self.preGame then
                      local ok = saveCurrentSetupProfile()
                      self.setupSaveFlash = ok and 1.5 or -1.5
                      return true
                  end
                  if item.isInGameSave and not self.preGame then
                      local ok = saveCurrentInGameRules()
                      self.inGameSaveFlash = ok and 1.5 or -1.5
                      return true
                  end
                  if item.rule and item.rule.key == "rules_locked" then
                      local cur = getConfigValue("rules_locked", self.preGame)
                      setConfigValue("rules_locked", not cur, self.preGame)
                      return true
                  end
                  return false
              end

              local function canChangeSelected(item)
                  if not item or item.isHeader then
                      return false
                  end

                  -- The lock control is the one exception: it is always usable.
                  if item.isControl and (item.rule.key == "rules_locked"
                      or item.isInGameSave or item.isSetupSave) then
                      return true
                  end

                  return not getConfigValue("rules_locked", self.preGame)
              end

              local item = selectedItem()
              local editingAtStart = self.editingNumber

              if self.editingNumber and item and item.rule.numeric then
                  local rule = item.rule
                  local value = tonumber(getConfigValue(rule.key, true)) or rule.min
                  local digits = rule.digits or 1
                  local text = ("%0" .. tostring(digits) .. "d"):format(value)

                  if self.game.input:wasPressed("left") then
                      self.digitIndex = math.max(1, self.digitIndex - 1)
                  elseif self.game.input:wasPressed("right") then
                      self.digitIndex = math.min(digits, self.digitIndex + 1)
                  elseif self.game.input:wasPressed("up") or self.game.input:wasPressed("down") then
                      local step = self.game.input:wasPressed("up") and 1 or -1
                      local chars = {}
                      for i = 1, #text do chars[i] = tonumber(text:sub(i, i)) or 0 end
                      chars[self.digitIndex] = (chars[self.digitIndex] + step) % 10
                      local newValue = tonumber(table.concat(chars)) or 0
                      if newValue >= rule.min and newValue <= rule.max then
                          setConfigValue(rule.key, newValue, true)
                      end
                  elseif self.game.input:wasPressed("a") or self.game.input:wasPressed("select") then
                      self.editingNumber = false
                      self.digitIndex = 1
                      self.descScroll = 0
                  end

              elseif self.game.input:wasPressed("down") then
                  moveCursor(1)
              elseif self.game.input:wasPressed("up") then
                  moveCursor(-1)
              elseif self.game.input:wasPressed("right") or self.game.input:wasPressed("left") then
                  if item and item.rule and item.rule.numeric and self.preGame then
                      self.editingNumber = true
                      self.digitIndex = 1
                      self.descScroll = 0
                  elseif item and item.isControl then
                      activateControl(item)
                  elseif canChangeSelected(item) then
                      local key = item.rule.key
                      local cur = getConfigValue(key, self.preGame)
                      setConfigValue(key, not cur, self.preGame)
                  end
              elseif self.game.input:wasPressed("select") then
                  if item and not item.isHeader then
                      local descLines = wrapText(item.rule.desc, 16)
                      local maxScroll = math.max(0, #descLines - 3)
                      if maxScroll > 0 then
                          self.descScroll = (self.descScroll + 1) % (maxScroll + 1)
                      end
                  end
              end

              if self.game.input:wasPressed("a") and not editingAtStart then
                  if item and item.isControl then
                      activateControl(item)
                  elseif item and item.rule and item.rule.numeric and self.preGame then
                      self.editingNumber = true
                      self.digitIndex = 1
                      self.descScroll = 0
                  elseif canChangeSelected(item) then
                      local key = item.rule.key
                      local cur = getConfigValue(key, self.preGame)
                      setConfigValue(key, not cur, self.preGame)
                  end
              end
          end

          function self:draw()
              local Font = mod.ui.Font

              Font.drawBox(0, 0, 20, 11)
              Font.drawBox(0, 11, 20, 7)

              -- Title: centred in the 160px canvas (inner X=8..152=144px wide).
              -- "NUZLOCKE RULES" = 14 chars * ~10px = 140px => start at X=10.
              -- "NZLCKE SETUP"  = 12 chars * ~10px = 120px => start at X=20.
              local locked = getConfigValue("rules_locked", self.preGame)
              if self.preGame then
                  Font.draw("NUZLOCKE SETUP", 10, 10)
                  Font.draw("NEW GAME ONLY", 15, 22)
              else
                  Font.draw("NUZLOCKE RULES", 10, 10)
                  -- Show a lock indicator in the top-right when rules are locked.
                  if locked then
                      Font.draw("[LK]", 116, 10)
                  end
              end

              if self.cursor > self.scroll + self.pageSize then
                  self.scroll = self.cursor - self.pageSize
              end

              if self.cursor <= self.scroll then
                  self.scroll = math.max(0, self.cursor - 1)
              end

              -- List starts lower in preGame to clear the two-line header.
              local startY = self.preGame and 36 or 28

              for i = self.scroll + 1,
                  math.min(self.scroll + self.pageSize, #flatItemList) do

                  local item = flatItemList[i]
                  local drawY =
                      startY + ((i - (self.scroll + 1)) * 18)

                  if item.isHeader then
                      -- Headers at X=16 aligns with the cursor "->" start.
                      Font.draw(item.name, 16, drawY)
                  else
                      local isSelected = (i == self.cursor)
                      local key = item.rule.key
                      local val = getConfigValue(key, self.preGame)

                      -- "->" is two chars, always visible in the GB font.
                      -- Sits at X=14, just inside the left border tile (X=8).
                      if isSelected then
                          Font.draw("->", 14, drawY)
                      end

                      -- 8-char window: 8*~10px=80px, ends at X=110.
                      -- Status starts at X=116 leaving a clean 6px gap.
                      local displayName = marqueeText(
                          item.rule.name,
                          8,
                          self.marqueeTime
                      )
                      Font.draw(displayName, 30, drawY)

                      if item.isSetupSave then
                          local label = "SAVE"
                          if self.setupSaveFlash and self.setupSaveFlash > 0 then
                              label = "SAVED"
                          elseif self.setupSaveFlash and self.setupSaveFlash < 0 then
                              label = "ERROR"
                          end
                          Font.draw(label, 112, drawY)
                      elseif item.isInGameSave then
                          local label = "SAVE"
                          if self.inGameSaveFlash and self.inGameSaveFlash > 0 then
                              label = "SAVED"
                          elseif self.inGameSaveFlash and self.inGameSaveFlash < 0 then
                              label = "ERROR"
                          end
                          Font.draw(label, 112, drawY)
                      elseif item.rule.numeric then
                          local digits = item.rule.digits or 1
                          local numberText = ("%0" .. tostring(digits) .. "d"):format(tonumber(val) or item.rule.min or 0)
                          if key == "starting_money" then
                              Font.draw("$" .. numberText, 110, drawY)
                          else
                              Font.draw(numberText, 118, drawY)
                          end
                          if isSelected and self.editingNumber then
                              local prefix = key == "starting_money" and 1 or 0
                              Font.draw("^", 118 + ((self.digitIndex - 1) + prefix) * 6, drawY - 8)
                          end
                      else
                          local status = val and "ON" or "OFF"
                          Font.draw(status, 118, drawY)
                      end
                  end
              end

              local selItem = flatItemList[self.cursor]

              if selItem and not selItem.isHeader then
                  local descLines = wrapText(selItem.rule.desc, 16)
                  local maxScroll = math.max(0, #descLines - 3)

                  if self.descScroll > maxScroll then
                      self.descScroll = maxScroll
                  end

                  local startLine = self.descScroll + 1
                  -- Show up to 3 lines; third line stays clear for the
                  -- scroll arrow so it never overlaps text.
                  local endLine = math.min(#descLines, startLine + 2)

                  local descY = 94
                  for li = startLine, endLine do
                      Font.draw(descLines[li], 14, descY)
                      descY = descY + 14
                  end

                  -- Blinking down-arrow when more text exists below.
                  if self.descScroll < maxScroll then
                      local blinkOn = math.floor(self.marqueeTime / 0.8) % 2 == 0
                      if blinkOn then
                          Font.draw("v SEL", 56, 134)
                      end
                  end
              else
                  -- Help text when no rule is focused (e.g. on a header row,
                  -- which shouldn't happen with the cursor skip logic, but
                  -- show sensible hints anyway).
                  if self.editingNumber then
                      Font.draw("LR:Digit  UD:Value", 14, 96)
                      Font.draw("A:Confirm", 14, 112)
                  elseif locked then
                      Font.draw("Rules are LOCKED.", 14, 96)
                      Font.draw("A on Lock to open.", 14, 112)
                  else
                      Font.draw("A or LR: Toggle", 14, 96)
                      Font.draw("SEL: Scroll desc", 14, 110)
                      Font.draw("B: Back", 14, 124)
                  end
              end
          end

          return self
      end
  })

  ---------------------------------------------------------------------
  -- BUILD DISPLAY ROUTE LIST
  -- RouteList OFF: only visited/caught areas are shown.
  -- RouteList ON: every tracked area is shown.
  ---------------------------------------------------------------------
  local function syncCurrentArea(game)
      if not game then
          return
      end

      discoverAllKnownAreas(game)

      -- Check every save/runtime representation of the current location.
      -- Different engine paths populate these at slightly different times
      -- during map transitions, so relying on only one of them can miss a city
      -- on an older save.
      local candidates = {}

      if game.overworld and game.overworld.map then
          candidates[#candidates + 1] = game.overworld.map.id
      end

      if game.save and game.save.player then
          candidates[#candidates + 1] = game.save.player.map
      end

      if game.save and type(game.save.lastOutdoor) == "table" then
          candidates[#candidates + 1] = game.save.lastOutdoor.id
      end

      for _, rawId in ipairs(candidates) do
          local key = registerArea(rawId)
          if key then
              markVisited(key)
          end
      end
  end

  local TOWN_AREA_IDS = {
      PALLET_TOWN = true, VIRIDIAN_CITY = true, PEWTER_CITY = true,
      CERULEAN_CITY = true, VERMILION_CITY = true, LAVENDER_TOWN = true,
      FUCHSIA_CITY = true, CELADON_CITY = true, SAFFRON_CITY = true,
      CINNABAR_ISLAND = true,
  }

  local TOWN_PREFIXES = {
      "pallet", "viridian", "pewter", "cerulean", "vermillion",
      "vermilion", "lavender", "fuchsia", "celadon", "saffron",
      "cinnabar",
  }

  local TOWN_INTERIOR_WORDS = {
      "mart", "pokemart", "poke mart", "pokemon mart", "pkmn mart",
      "center", "pokemon center", "pokecenter", "poke center",
      "gym", "hotel", "house", "lab", "museum", "shop", "gate",
      "dept store", "department store", "game corner", "bike shop",
      "fishing guru", "name rater",
  }

  isTownArea = function(id, name)
      id = tostring(id or "")
      if TOWN_AREA_IDS[id] then return true end

      local text = tostring(name or id or ""):lower()
      text = text:gsub("_+", " ")
      text = text:gsub("([a-z])([A-Z])", "%1 %2"):lower()
      if text:find("city", 1, true)
          or text:find("town", 1, true)
          or text:find("village", 1, true) then
          return true
      end

      -- Treat named town/city interiors as town locations even when their
      -- individual map ID has no CITY/TOWN suffix (e.g. CeruleanMart4).
      local hasTownPrefix = false
      for _, prefix in ipairs(TOWN_PREFIXES) do
          if text:find(prefix, 1, true) == 1 then
              hasTownPrefix = true
              break
          end
      end
      if hasTownPrefix then
          for _, word in ipairs(TOWN_INTERIOR_WORDS) do
              if text:find(word, 1, true) then return true end
          end
      end

      return false
  end

  local function areaAllowedByConfig(area)
      if not area then
          return false
      end

      -- Pallet Town is the mandatory starter slot. Keep it visible on the
      -- encounter MAP even when ordinary town catches are disabled.
      if area.id == "PALLET_TOWN" and caughtAreas()["PALLET_TOWN"] ~= nil then
          return true
      end

      if isTownArea(area.id, area.name) and not mod.save:get("town_catches", false) then
          return false
      end
      return true
  end

  local function getDisplayRoutes(game)
      syncCurrentArea(game)
      local list = {}

      for _, r in ipairs(ALL_ROUTES) do
          if areaAllowedByConfig(r) then
              table.insert(list, r)
          end
      end

      table.sort(list, function(a, b)
          local ao = ROUTE_ORDER[a.id] or 999999
          local bo = ROUTE_ORDER[b.id] or 999999
          if ao == bo then
              return tostring(a.name) < tostring(b.name)
          end
          return ao < bo
      end)

      return list
  end

  ---------------------------------------------------------------------
  -- TRAINER CARD Nuzlocke status page
  --
  -- The vanilla Trainer Card remains the front page.  A flips to a live
  -- Nuzlocke status page whose rule list is read directly from mod.save.
  -- Changes made in the in-game RULES menu therefore appear immediately
  -- the next time this page is drawn.
  --
  -- MONEY intentionally stays off this page because it is already shown on
  -- the vanilla front of the Trainer Card.
  ---------------------------------------------------------------------
  mod.content.screens:register("NuzlockeTrainerCardScreen", {
      new = function(game, ctx)
          local TrainerCard = require("src.ui.TrainerCard")
          local vanilla = TrainerCard.new(game, { onCancel = nil })

          local self = {
              game = game,
              vanilla = vanilla,
              isOpaque = true,
              nuzlockeStatusPage = false,
              ruleScroll = 0,
              ruleArrowTime = 0,
          }

          local function activeRuleNames()
              -- The Trainer Card must use the exact same active-save state as
              -- the in-game Rules screen.  Never read the staged NEW GAME
              -- table here; once the save exists, mod.save is authoritative.
              local names = {}
              for _, cat in ipairs(ruleCategories) do
                  for _, rule in ipairs(cat.rules) do
                      local value = mod.save:get(rule.key, defaultRuleValue(rule.key))
                      if value == true then
                          names[#names + 1] = rule.name
                      end
                  end
              end
              return names
          end

          function self:update(dt)
              local input = self.game.input

              if input:wasPressed("a") then
                  self.nuzlockeStatusPage = not self.nuzlockeStatusPage
                  self.ruleScroll = 0
                  self.ruleArrowTime = 0
                  return
              end

              if input:wasPressed("b") then
                  self.game.stack:pop()
                  return
              end

              if self.nuzlockeStatusPage then
                  local names = activeRuleNames()
                  local visible = 2
                  local maxScroll = math.max(0, #names - visible)

                  if input:wasPressed("down") and self.ruleScroll < maxScroll then
                      self.ruleScroll = self.ruleScroll + 1
                  elseif input:wasPressed("up") and self.ruleScroll > 0 then
                      self.ruleScroll = self.ruleScroll - 1
                  end

                  -- Clamp the scroll position every update.  The arrow is
                  -- driven by the same condition used to advance the list,
                  -- so it cannot remain visible after the final rule.
                  if self.ruleScroll > maxScroll then
                      self.ruleScroll = maxScroll
                  end

                  local canScrollDown = (self.ruleScroll + visible) < #names
                  if canScrollDown then
                      self.ruleArrowTime = self.ruleArrowTime + (dt or 0)
                  else
                      self.ruleArrowTime = 0
                  end
              else
                  self.ruleScroll = 0
                  self.ruleArrowTime = 0
              end
          end

          function self:draw()
              local Font = mod.ui.Font

              if not self.nuzlockeStatusPage then
                  self.vanilla:draw()
                  -- Flip hint lives in the open band between the trainer
                  -- information/sprite area and the badge sprites.  Keep it
                  -- on the RIGHT side, clear of the WORD badges and dots.
                  Font.draw("A:NUZ", 112, 68)
                  return
              end

              love.graphics.setColor(1, 1, 1, 1)
              love.graphics.rectangle("fill", 0, 0, 160, 144)
              Font.drawBox(0, 0, 20, 18)
              Font.draw("NUZ STATUS", 28, 8)

              local caught = countTrackerCatches()
              local lost = tonumber(mod.save:get("nuzlocke_losses", 0)) or 0
              local areas = countCaughtAreas()
              local totalAreas = #getDisplayRoutes(self.game)
              local cap, leader = nextLevelCapInfo(self.game and self.game.save)

              -- Fixed rows leave a dedicated bottom navigation strip.
              -- Nothing in the rules list is allowed to occupy that strip.
              Font.draw("CAUGHT", 16, 26)
              Font.draw(("%3d"):format(caught), 108, 26)
              Font.draw("LOST", 16, 42)
              Font.draw(("%3d"):format(lost), 108, 42)
              Font.draw("AREAS", 16, 58)
              Font.draw(("%2d/%2d"):format(areas, totalAreas), 88, 58)
              Font.draw("NEXT CAP", 16, 70)
              Font.draw(cap >= 100 and "MAX" or ("LV" .. tostring(cap)), 88, 70)

              local names = activeRuleNames()
              local visible = 2
              local maxScroll = math.max(0, #names - visible)
              if self.ruleScroll > maxScroll then
                  self.ruleScroll = maxScroll
              end
              local canScrollDown = (self.ruleScroll + visible) < #names

              -- Keep the gym/rules area above a completely dedicated bottom
              -- navigation strip.  The previous layout let the second rule
              -- line run into the button prompts on real hardware scaling.
              Font.draw("NEXT CAP", 16, 80)
              Font.draw(leader, 88, 80)

              Font.draw("RULES", 16, 90)
              if #names == 0 then
                  Font.draw("NONE", 16, 100)
              else
                  for row = 1, visible do
                      local idx = self.ruleScroll + row
                      local name = names[idx]
                      if name then
                          Font.draw(marqueeText(name, 14, 0), 16, 100 + (row - 1) * 10)
                      end
                  end
              end

              -- Bottom navigation strip.  There is intentionally NO up-arrow:
              -- when the player reaches the last rule, the scroll indicator
              -- disappears completely instead of changing into another arrow.
              -- This leaves the prompts unobstructed and makes the down-arrow
              -- mean exactly one thing: more rules are available below.
              if canScrollDown then
                  local blinkOn = math.floor(self.ruleArrowTime / 0.8) % 2 == 0
                  if blinkOn then Font.draw("v", 94, 126) end
              end

              Font.draw("A:CARD", 8, 126)
              Font.draw("B:EXIT", 104, 126)
          end

          return self
      end
  })

  ---------------------------------------------------------------------
  -- TRACKER SCREEN
  ---------------------------------------------------------------------
  mod.content.screens:register("NuzlockeTrackerScreen", {
      new = function(game)
          local self = {
              game = game,
              isOpaque = true,
              tab = 1,
              scroll = 0,
              log = trackerLog(),
              logKeys = {},
              marqueeTime = 0,
              arrowTime = 0,
          }

          for k, _ in pairs(self.log) do
              table.insert(self.logKeys, k)
          end

          table.sort(self.logKeys, function(a, b)
              local ao = ROUTE_ORDER[a] or 999999
              local bo = ROUTE_ORDER[b] or 999999
              if ao == bo then return tostring(a) < tostring(b) end
              return ao < bo
          end)

          function self:update(dt)
              syncCurrentArea(self.game)

              if self.game.input:wasPressed("b") then
                  self.game.stack:pop()
                  return
              end

              local guideEnabled = mod.save:get("area_guide_enabled", true) == true
              if not guideEnabled then
                  self.tab = 1
              end

              -- A is the page toggle. It is deliberately unavailable when
              -- Area Guide is locked OFF.
              if guideEnabled and self.game.input:wasPressed("a") then
                  self.tab = (self.tab == 1) and 2 or 1
                  self.scroll = 0
                  self.marqueeTime = 0
              end

              -- Keep left/right as a convenient secondary page control only
              -- when the Area Guide is enabled.
              if guideEnabled and self.game.input:wasPressed("left") then
                  self.tab = 1
                  self.scroll = 0
                  self.marqueeTime = 0
              elseif guideEnabled and self.game.input:wasPressed("right") then
                  self.tab = 2
                  self.scroll = 0
                  self.marqueeTime = 0
              end

              local listCount = self.tab == 1
                  and #self.logKeys
                  or #getDisplayRoutes(self.game)
              local maxScroll = math.max(0, listCount - 4)

              if self.game.input:wasPressed("down") and self.scroll < maxScroll then
                  self.scroll = self.scroll + 1
                  self.marqueeTime = 0
              elseif self.game.input:wasPressed("up") and self.scroll > 0 then
                  self.scroll = self.scroll - 1
                  self.marqueeTime = 0
              end

              self.marqueeTime = self.marqueeTime + (dt or 0)

              -- The arrow has its own timer so reaching the last page makes
              -- it completely inert/invisible instead of continuing a hidden
              -- blink animation. It restarts calmly when another page exists.
              local arrowListCount = self.tab == 1
                  and #self.logKeys
                  or #getDisplayRoutes(self.game)
              local arrowMaxScroll = math.max(0, arrowListCount - 4)
              if self.scroll < arrowMaxScroll then
                  self.arrowTime = self.arrowTime + (dt or 0)
              else
                  self.arrowTime = 0
              end
          end

          function self:draw()
              syncCurrentArea(self.game)
              local Font = mod.ui.Font
              local guideEnabled = mod.save:get("area_guide_enabled", true) == true

              Font.drawBox(0, 0, 20, 18)
              -- "ENC TRACKER" = 11 chars from X=14 -> ends ~X=124, safe.
              -- Tab indicator [1]/[2] shown at right to show current page.
              Font.draw("ENC TRACKER", 14, 8)
              local tabLabel = self.tab == 1 and "[LOG]" or "[MAP]"
              Font.draw(tabLabel, 110, 8)

              local y = 26
              local listCount

              if self.tab == 1 then
                  Font.draw("AREA      CATCH", 16, y)
                  y = y + 12
                  listCount = #self.logKeys

                  for i = self.scroll + 1, math.min(self.scroll + 4, #self.logKeys) do
                      local route = self.logKeys[i]
                      local catches = self.log[route]
                      local display = {}
                      for _, c in ipairs(catches or {}) do
                          local species = c.species or "???"
                          table.insert(display, c.isShiny and ("*" .. species) or species)
                      end
                      local routeLabel = (route == "__LEGACY__") and "LEGACY" or routeName(route)
                      Font.draw(marqueeText(routeLabel, 8, self.marqueeTime), 16, y)
                      Font.draw(marqueeText(table.concat(display, ","), 7, self.marqueeTime), 96, y)
                      y = y + 18
                  end
              else
                  Font.draw("AREA      CATCH", 16, y)
                  y = y + 12
                  local areas = caughtAreas()
                  local routeList = getDisplayRoutes(self.game)
                  listCount = #routeList

                  for i = self.scroll + 1, math.min(self.scroll + 4, #routeList) do
                      local r = routeList[i]
                      local status = areas[r.id] and tostring(areas[r.id]) or "..."
                      Font.draw(marqueeText(r.name, 8, self.marqueeTime, 3.8), 16, y)
                      Font.draw(marqueeText(status, 7, self.marqueeTime), 96, y)
                      y = y + 18
                  end
              end

              local maxScroll = math.max(0, listCount - 4)
              local canScrollUp = self.scroll > 0
              local canScrollDown = self.scroll < maxScroll
              local blinkOn = math.floor(self.arrowTime / 1.0) % 2 == 0

              if canScrollUp and blinkOn then
                  Font.draw("^", 72, 18)
              end

              -- Bottom bar: navigation hints + level cap reminder.
              local cap = nextLevelCap(self.game and self.game.save)
              local capStr = cap >= 100 and "CAP:MAX" or ("CAP:" .. tostring(cap))
              Font.draw(capStr, 14, 112)
              if guideEnabled then
                  Font.draw("A:PG", 72, 112)
              end
              Font.draw("B:X", 122, 112)

              if canScrollDown and blinkOn then
                  Font.draw("v", 72, 126)
              end
          end

          return self
      end
  })

  ---------------------------------------------------------------------
  -- CATCH INFO SCREEN
  -- Uses the same compact layout as the working catch-info page, but now
  -- includes the Nuzlocke encounter type and a factual loss summary.
  ---------------------------------------------------------------------
  mod.content.screens:register("NuzlockeCatchInfoScreen", {
      new = function(game, ctx)
          local self = {
              game = game,
              isOpaque = true,
              mon = ctx and ctx.mon
          }

          function self:update(dt)
              if self.game.input:wasPressed("b")
                  or self.game.input:wasPressed("a") then
                  self.game.stack:pop()
              end
          end

          local function displayEncounterType(mon)
              local value = mon and (mon.encounterType or mon.nuzlockeEncounterType)
              if not value then return "UNKNOWN" end
              local labels = {
                  overworld = "OVERWORLD",
                  wild = "WILD",
                  town = "TOWN",
                  safari = "SAFARI",
                  grass = "GRASS",
                  surf = "SURF",
                  fishing = "FISHING",
                  old_rod = "OLD ROD",
                  good_rod = "GOOD ROD",
                  super_rod = "SUPER ROD",
                  gift = "GIFT",
                  static = "STATIC",
                  trade = "TRADE"
              }
              return labels[value] or tostring(value):upper()
          end

          function self:draw()
              local Font = mod.ui.Font
              local mon = self.mon

              Font.drawBox(0, 0, 20, 18)
              Font.draw("CATCH INFO", 24, 12)

              if not mon then
                  Font.draw("No data.", 16, 40)
                  Font.draw("A/B: BACK", 40, 122)
                  return
              end

              local label = tostring(mon.nickname or mon.species or "???")
              local loc = routeName(mon.catchLocation or "UNKNOWN")
              local encounter = displayEncounterType(mon)
              local dead = mon.nuzlockeDead == true

              Font.draw("CATCH", 16, 28)
              Font.draw(label, 16, 40)

              Font.draw("LOCATION", 16, 54)
              Font.draw(loc, 16, 66)

              Font.draw("ENCOUNTER TYPE", 16, 80)
              Font.draw(encounter, 16, 92)

              Font.draw("STATUS", 16, 106)
              Font.draw(dead and "LOST" or "ALIVE", 16, 118)

              if dead then
                  local cause = tostring(mon.deathCauseText or mon.deathCause or "BATTLE")
                  local lines = wrapText(cause, 18)
                  if lines[1] then Font.draw(lines[1], 16, 130) end
                  if lines[2] then Font.draw(lines[2], 16, 142) end
              elseif mon.dvs and Stats.isShiny(mon.dvs) then
                  Font.draw("SHINY", 88, 118)
              end

              -- A/B remains the established back control.  It is deliberately
              -- omitted when a two-line death cause reaches the bottom edge.
              if not dead or #wrapText(tostring(mon.deathCauseText or mon.deathCause or "BATTLE"), 18) < 2 then
                  Font.draw("A/B: BACK", 40, 122)
              end
          end

          return self
      end
  })

  ---------------------------------------------------------------------
  -- TITLE MENU HOOK
  -- NZLCKE SETUP must appear whenever the title screen has NO REAL SAVE.
  --
  -- IMPORTANT: game.save is an in-memory/default save object even on a
  -- completely fresh title screen, so checking game.save.player incorrectly
  -- made SETUP disappear on fresh Red/Blue starts. The engine's own title
  -- screen uses the presence of the actual save file instead.
  ---------------------------------------------------------------------
  local function hasActualSaveFile()
      local ok, info = pcall(function()
          local SaveData = require("src.core.SaveData")
          local GameVersion = require("src.core.GameVersion")
          local filename = SaveData.saveFilename(GameVersion.get())
          if love and love.filesystem and love.filesystem.getInfo then
              return love.filesystem.getInfo(filename)
          end
          return nil
      end)
      return ok and info ~= nil
  end

  mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
      local result = next(game, items)
      if type(result) ~= "table" then
          result = items
      end

      for _, item in ipairs(result) do
          -- NEW GAME: stage the pending rules for the upcoming save.
          if item and item.label == "NEW GAME" and type(item.onSelect) == "function" then
              local originalNewGame = item.onSelect
              item.onSelect = function()
                  if not pendingNewGameRules then
                      pendingNewGameRules = loadSetupProfileFromDisk()
                          or makeDefaultPreGameRules()
                  end
                  -- Save exactly what the player has configured.  The visible
                  -- SAVE SETUP control is still useful for reusing a profile
                  -- later; this automatic write also makes NEW GAME reliable
                  -- if the player forgets to press it.
                  saveSetupProfileToDisk(pendingNewGameRules)
                  stageNewGameProfile()
                  originalNewGame()
              end
          end

          -- CONTINUE: discard any staged setup so it can never override
          -- the existing save's rules.
          if item and item.label == "CONTINUE" and type(item.onSelect) == "function" then
              local originalContinue = item.onSelect
              item.onSelect = function()
                  pendingNewGameRulesForNextSave = false
                  pendingRulesDirty = false
                  newGameRulesSnapshot = nil
                  newGameRulesCommitPending = false
                  newGameCommitPassesRemaining = 0
                  clearPersistedStagedProfile()
                  originalContinue()
              end
          end
      end

      -- SETUP button only appears when there is no real save file yet.
      if not hasActualSaveFile() then
          mod.ui.insertBefore(result, "NEW GAME", {
              label = "SETUP",
              nuzlockeMarquee = true,
              nuzlockeMarqueeLabel = "NUZLOCKE SETUP",
              onSelect = function()
                  if not pendingNewGameRules or not pendingRulesDirty then
                      pendingNewGameRules = loadSetupProfileFromDisk()
                          or makeDefaultPreGameRules()
                      pendingRulesDirty = false
                  end
                  mod.ui.push(game, "NuzlockeConfigScreen", { preGame = true })
              end
          })
      end

      return result
  end)

  ---------------------------------------------------------------------
  -- START MENU HOOKS
  --
  -- IMPORTANT: build from the VANILLA result first, then modify that
  -- returned list.  Calling insertBefore() on the incoming `items` and
  -- then calling next() causes the vanilla hook to rebuild the list and
  -- silently discard our inserted entries.  That was why RULES/TRACKER
  -- disappeared in the previous build.
  ---------------------------------------------------------------------
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local result = next(game, items)
      if type(result) ~= "table" then
          result = items
      end

      -- Redirect the player's name row to our Trainer Card wrapper.
      -- Keep this in the same hook so there is only ONE start-menu hook
      -- and all of our modifications operate on the final vanilla list.
      for _, item in ipairs(result) do
          if item and item.label == (game.save and game.save.player and game.save.player.name or "RED")
              and type(item.onSelect) == "function" then
              item.onSelect = function()
                  mod.ui.push(game, "NuzlockeTrainerCardScreen")
              end
              break
          end
      end

      mod.ui.insertBefore(result, "OPTION", {
          label = "TRACKER",
          onSelect = function()
              mod.ui.push(game, "NuzlockeTrackerScreen")
          end
      })

      mod.ui.insertBefore(result, "OPTION", {
          -- Short underlying label preserves the original start-menu width.
          label = "RULES",
          nuzlockeMarquee = true,
          nuzlockeMarqueeLabel = "NUZLOCKE RULES",
          onSelect = function()
              mod.ui.push(game, "NuzlockeConfigScreen")
          end
      })

      return result
  end)

  ---------------------------------------------------------------------
  -- PARTY SUBMENU HOOK
  ---------------------------------------------------------------------
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
      if mod.save:get("nuzlocke_enabled", true) and mod.save:get("catch_info", true) and mon then
          mod.ui.insertBefore(items, "CANCEL", {
              label = "CATCH INFO",
              onSelect = function()
                  mod.ui.push(
                      game,
                      "NuzlockeCatchInfoScreen",
                      { mon = mon }
                  )
              end
          })
      end

      return next(game, items, mon, ctx)
  end)

  ---------------------------------------------------------------------
  -- BATTLE CATCH ENFORCEMENT
  --
  -- The recomp's BagMenu calls BattleState:throwBall after consuming the
  -- selected ball. Bryan's original Nuzlocke implementation intercepts
  -- this exact method, refunds the ball, displays the rejection message,
  -- and returns before vanilla capture processing.
  --
  -- We use that same engine seam for the actual first-catch / No Dupes
  -- decision. The important difference from Bryan's strict mode is that
  -- duplicate encounters NEVER consume the area's encounter in this mod.
  -- Shinies always bypass No Dupes, and bypass 1st Catch when Shiny Clause
  -- is enabled.
  ---------------------------------------------------------------------
  mod.events:on("game.ready", function(game)
      local ok, BattleState = pcall(require, "src.battle.BattleState")
      local okBag, Bag = pcall(require, "src.inventory.Bag")
      if not ok or not BattleState or not okBag or not Bag then
          return
      end

      if BattleState.__nuzlockeFinal23Patched then
          return
      end
      BattleState.__nuzlockeFinal23Patched = true

      local vanillaThrowBall = BattleState.throwBall

      -- The runtime does not reliably emit battle.ended for every normal
      -- battle in all recomp builds. Failed Encounters depends on that event,
      -- so bridge the engine's authoritative BattleState:finish seam. The
      -- nuzlocke game-over path already emits the same event later; the flag
      -- prevents a duplicate emission for that case.
      if type(BattleState.finish) == "function" and not BattleState.__nuzlockeCatchFinishPatched then
          BattleState.__nuzlockeCatchFinishPatched = true
          local vanillaCatchFinish = BattleState.finish
          BattleState.finish = function(self, ...)
              if not self.__nuzlockeCatchBattleEndedEmitted then
                  self.__nuzlockeCatchBattleEndedEmitted = true
                  local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
                  if okRuntime and Runtime and type(Runtime.emit) == "function" then
                      pcall(Runtime.emit, "battle.ended", { battle = self })
                  end
              end
              return vanillaCatchFinish(self, ...)
          end
      end

      -- The public battle.nickname hook is not present in every recomp build.
      -- Patch the engine's actual nickname-screen seam as well, so enabling
      -- Nicknames cannot silently fall through to the normal auto-skip path.
      if not BattleState.__nuzlockeNicknameScreenPatched then
          BattleState.__nuzlockeNicknameScreenPatched = true
          local vanillaAskNicknameUI = BattleState.askNicknameUI
          local okStrings, Strings = pcall(require, "src.core.Strings")

          if type(vanillaAskNicknameUI) == "function" then
              BattleState.askNicknameUI = function(self, mon)
                  if active(self and self.game, self)
                      and mod.save:get("nickname_rule", false)
                      and okStrings and Strings then
                      self.lockedBall, self.blankForAskName = nil, false
                      return self:buildScreen("NamingScreen", {
                          title = Strings("NICKNAME?"),
                          maxLen = 10,
                          onDone = function(name)
                              mon.nickname = name or "A"
                          end,
                      })
                  end
                  return vanillaAskNicknameUI(self, mon)
              end
          end
      end

      BattleState.throwBall = function(self, ball)
          local gameRef = self and self.game
          local species = self and self.enemy and self.enemy.mon
              and self.enemy.mon.species

          local reason
          local reasonOk, reasonValue = pcall(function()
              return catchDeniedReason(gameRef, self, species)
          end)
          if reasonOk then
              reason = reasonValue
          end

          if reason then
              -- BagMenu has already removed the ball. Use Bryan's exact
              -- refund mechanism and original messages.
              pcall(function()
                  Bag.add(gameRef.save, ball, 1, gameRef.data)
              end)

              local message
              if reason == "area" then
                  message = "This area already\nhas a captured\vPOKéMON!"
              elseif reason == "dupes" then
                  message = "You already have\nthis POKéMON family!"
              elseif reason == "overworld" then
                  message = "Overworld catches\nare turned OFF."
              elseif reason == "town" then
                  message = "Town catches\nare turned OFF."
              elseif reason == "legendary" then
                  message = "Legendary catches\nare turned OFF."
              elseif reason == "mythical" then
                  message = "Mythical catches\nare turned OFF."
              elseif reason == "solo" then
                  message = "Solo Only: only\none Pokemon allowed!"
              end

              -- Use the same message entry point as Bryan's implementation.
              -- If a stripped/older build does not expose say(), fall back
              -- to the queue-based API rather than touching phase/queue state.
              if message then
                  if type(self.say) == "function" then
                      self:say(message)
                  elseif type(self.sayNext) == "function" then
                      self:sayNext(message)
                  end
              end

              return
          end

          return vanillaThrowBall(self, ball)
      end
  end)

  ---------------------------------------------------------------------
  -- NICKNAME ENFORCEMENT
  --
  -- hooks:wrap("battle.nickname") fires after a successful catch,
  -- before the nickname prompt. Returning true forces the prompt to
  -- appear even when the player has auto-skip turned on. Returning
  -- false skips it. We always return true when the Nicknames rule is
  -- enabled so the player cannot avoid naming their catch.
  ---------------------------------------------------------------------
  mod.hooks:wrap("battle.nickname", function(next, battle, mon)
      if active(battle and battle.game, battle)
          and mod.save:get("nickname_rule", false) then
          -- Force the naming screen open regardless of options.
          return true
      end
      return next(battle, mon)
  end)

  -- Fallback for engine builds where battle.nickname is only a notification
  -- hook. If a caught Pokemon reaches the tracker without a custom nickname,
  -- mark it for the engine's nickname flow rather than silently accepting the
  -- species name. This does not invent a nickname; the player must supply it.
  mod.events:on("pokemon.caught", function(ev)
      if not (ev and ev.mon and ev.game) then return end
      if not active(ev.game, ev.battle) then return end
      if not mod.save:get("nickname_rule", false) then return end
      local mon = ev.mon
      if mon.nickname == nil or mon.nickname == "" or mon.nickname == mon.species then
          mon.nuzlockeNeedsNickname = true
          mon.nuzlockeNicknameRequired = true
      end
  end)

  ---------------------------------------------------------------------
  -- BATTLE ITEM ENFORCEMENT
  --
  -- The engine's current BagMenu calls ItemEffects.use(...) directly when
  -- an item is selected in battle.  There is no native battle.use_item hook
  -- at that call site, so wrapping that nonexistent hook cannot prevent the
  -- item from being applied.  Intercept ItemEffects.use instead.
  --
  -- This is deliberately done at the shared item-effect layer so it covers
  -- every battle item path (HP/status medicine, PP recovery, X items,
  -- Dire Hit, Guard Spec, etc.) without consuming the item or the turn.
  ---------------------------------------------------------------------
  local function installBattleItemGate()
      local ok, ItemEffects = pcall(require, "src.inventory.ItemEffects")
      if not ok or type(ItemEffects) ~= "table"
          or type(ItemEffects.use) ~= "function" then
          return false
      end

      -- Avoid stacking wrappers if the mod is hot-reloaded.
      if ItemEffects.__nuzlockeBattleItemGateInstalled then
          return true
      end

      local vanillaUse = ItemEffects.use

      local healingItems = {
          POTION = true, SUPER_POTION = true, HYPER_POTION = true,
          MAX_POTION = true, FULL_RESTORE = true,
          REVIVE = true, MAX_REVIVE = true,
          ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true,
          AWAKENING = true, PARLYZ_HEAL = true, FULL_HEAL = true,
          ETHER = true, MAX_ETHER = true, ELIXIR = true, MAX_ELIXIR = true,
          FRESH_WATER = true, SODA_POP = true, LEMONADE = true,
          MOOMOO_MILK = true,
      }

      local battleItems = {
          X_ATTACK = true, X_DEFEND = true, X_SPEED = true,
          X_SPECIAL = true, X_ACCURACY = true,
          DIRE_HIT = true, GUARD_SPEC = true,
      }

      ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
          if battle and active(battle.game, battle) then
              local id = tostring(itemId or ""):upper()

              -- Poké Balls remain legal and continue through battle.catch.
              local isBall = id == "POKE_BALL" or id == "GREAT_BALL"
                  or id == "ULTRA_BALL" or id == "MASTER_BALL"
                  or id == "SAFARI_BALL"

              if not isBall then
                  if mod.save:get("no_healing_items", false)
                      and healingItems[id] then
                      return "failed", {
                          "Healing items are\nbanned in battle!"
                      }
                  end

                  if mod.save:get("no_battle_items", false)
                      and battleItems[id] then
                      return "failed", {
                          "Battle items are\nbanned!"
                      }
                  end

                  -- Legacy compatibility: older saves may still contain the
                  -- former combined no_items key.
                  if mod.save:get("no_items", false) then
                      return "failed", {
                          "Items are banned\nduring battle!"
                      }
                  end
              end
          end

          return vanillaUse(data, save, itemId, target, battle, moveIndex, ow)
      end

      ItemEffects.__nuzlockeBattleItemGateInstalled = true
      return true
  end

  -- Install immediately; also retry at lifecycle points in case the engine
  -- has not loaded the inventory module yet.
  pcall(installBattleItemGate)
  mod.events:on("game.ready", function()
      pcall(installBattleItemGate)
  end)
  mod.events:on("save.loaded", function()
      pcall(installBattleItemGate)
  end)

  ---------------------------------------------------------------------
  -- NO ITEMS IN BATTLE
  -- hooks:wrap("battle.use_item") fires when the player selects an
  -- item from the Bag menu during battle. Returning false cancels
  -- the use and keeps the turn. Only healing/revival items are
  -- blocked; key items and Poke Balls are allowed.
  ---------------------------------------------------------------------
  mod.hooks:wrap("battle.use_item", function(next, battle, item)
      if not active(battle and battle.game, battle) then
          return next(battle, item)
      end

      local itemId = type(item) == "table"
          and (item.id or item.key or item.name)
          or tostring(item or "")
      local upper = tostring(itemId):upper()

      local healing = {
          "POTION", "SUPER_POTION", "HYPER_POTION", "MAX_POTION",
          "FULL_RESTORE", "FULL_HEAL", "REVIVE", "MAX_REVIVE",
          "ETHER", "MAX_ETHER", "ELIXIR", "MAX_ELIXIR",
          "FRESH_WATER", "SODA_POP", "LEMONADE", "MOOMOO_MILK",
          "ANTIDOTE", "BURN_HEAL", "ICE_HEAL", "AWAKENING",
          "PARALYZE_HEAL",
      }

      local isHealing = false
      for _, pattern in ipairs(healing) do
          if upper:find(pattern, 1, true) then
              isHealing = true
              break
          end
      end

      if isHealing and (mod.save:get("no_healing_items", false)
          or mod.save:get("no_items", false)) then
          return false, "Healing items are\nbanned in battle!"
      end

      if not isHealing and mod.save:get("no_battle_items", false) then
          -- Poke Balls are handled by battle.catch.
          if not upper:find("BALL", 1, true) then
              return false, "Battle items are\nbanned!"
          end
      end

      return next(battle, item)
  end)

  ---------------------------------------------------------------------
  -- MAP ENTRY
  --
  -- map.entered gives the actual engine map ID.
  -- via="boot" is important: an old save loaded in Pallet Town is
  -- immediately recorded without requiring the player to walk.
  ---------------------------------------------------------------------
  mod.events:on("map.entered", function(ev)
      if not ev or not ev.mapId then
          return
      end

      local key = registerArea(ev.mapId)

      if not isTrackedArea(key) then
          return
      end

      markVisited(key)
  end)

  ---------------------------------------------------------------------
  -- WORLD STEP
  -- Keep the tracker synchronized with the actual map the player is on.
  -- This is intentionally redundant with map.entered: world.stepped is a
  -- cheap, reliable fallback for connections/transitions and old saves.
  ---------------------------------------------------------------------
  mod.events:on("world.stepped", function(ev)
      if not ev or not ev.mapId then
          return
      end

      local key = registerArea(ev.mapId)
      if key then
          markVisited(key)
      end
  end)

  ---------------------------------------------------------------------
  -- OVERWORLD ENCOUNTER DETECTION
  --
  -- Different overworld-spawn mods may annotate the catch event/battle in
  -- different ways. Accept the common explicit flags first, then treat a
  -- catch with no battle object as an overworld capture. Normal wild battles
  -- remain eligible regardless of this setting.
  ---------------------------------------------------------------------
  local function isOverworldEncounter(ev)
      if not ev then
          return false
      end

      if ev.overworldEncounter == true
          or ev.overworld == true
          or ev.isOverworld == true
          or ev.encounterType == "overworld"
          or ev.source == "overworld" then
          return true
      end

      local battle = ev.battle
      if battle then
          if battle.overworldEncounter == true
              or battle.overworld == true
              or battle.isOverworld == true
              or battle.encounterType == "overworld"
              or battle.source == "overworld" then
              return true
          end
      else
          -- A capture event without a battle is treated as an overworld
          -- capture. This is useful for mods that spawn/capture Pokemon
          -- directly without constructing the vanilla wild-battle state.
          return true
      end

      return false
  end

  ---------------------------------------------------------------------
  -- VERSION DETECTION
  --
  -- Detects Red, Blue, or Yellow. Falls back to "RED" on failure.
  ---------------------------------------------------------------------
  local function getGameVersion()
      local ok, GameVersion = pcall(require, "src.core.GameVersion")
      if ok and GameVersion then
          local v = type(GameVersion.get) == "function" and GameVersion.get()
              or type(GameVersion.version) == "string" and GameVersion.version
              or tostring(GameVersion)
          if v then
              local upper = tostring(v):upper()
              if upper:find("YELLOW") or upper:find("YLW") then return "YELLOW" end
              if upper:find("BLUE")   or upper:find("BLU") then return "BLUE"   end
          end
      end
      if currentGame then
          local ver = currentGame.version
              or (currentGame.data and currentGame.data.version)
          if ver then
              local u = tostring(ver):upper()
              if u:find("YELLOW") then return "YELLOW" end
              if u:find("BLUE")   then return "BLUE"   end
          end
      end
      return "RED"
  end

  ---------------------------------------------------------------------
  -- GIFT POKEMON TABLE  (version-tagged)
  -- area = where the gift is received; takes up that slot.
  -- version: nil=all, "RB"=Red/Blue only, "YLW"=Yellow only
  ---------------------------------------------------------------------
  local GIFT_LOCATIONS = {
      { species = "MAGIKARP",   area = "ROUTE_4",         version = nil   },
      { species = "HITMONCHAN", area = "SAFFRON_CITY",    version = nil   },
      { species = "HITMONLEE",  area = "SAFFRON_CITY",    version = nil   },
      { species = "LAPRAS",     area = "SILPH_CO",        version = nil   },
      { species = "EEVEE",      area = "CELADON_CITY",    version = "RB"  },
      { species = "OMANYTE",    area = "CINNABAR_ISLAND", version = nil   },
      { species = "KABUTO",     area = "CINNABAR_ISLAND", version = nil   },
      { species = "AERODACTYL", area = "CINNABAR_ISLAND", version = nil   },
      { species = "SCYTHER",    area = "CELADON_CITY",    version = nil   },
      { species = "PORYGON",    area = "CELADON_CITY",    version = nil   },
      { species = "DRATINI",    area = "CELADON_CITY",    version = nil   },
      { species = "PINSIR",     area = "CELADON_CITY",    version = nil   },
      { species = "BULBASAUR",  area = "CERULEAN_CITY",   version = "YLW" },
      { species = "CHARMANDER", area = "ROUTE_24",        version = "YLW" },
      { species = "SQUIRTLE",   area = "VERMILION_CITY",  version = "YLW" },
      { species = "JOLTEON",    area = "CELADON_CITY",    version = "YLW" },
      { species = "VAPOREON",   area = "CELADON_CITY",    version = "YLW" },
      { species = "FLAREON",    area = "CELADON_CITY",    version = "YLW" },
  }

  local function buildGiftLookup()
      local ver = getGameVersion()
      local lookup = {}
      for _, g in ipairs(GIFT_LOCATIONS) do
          if g.version == nil
              or (g.version == "RB"  and (ver == "RED" or ver == "BLUE"))
              or (g.version == "YLW" and ver == "YELLOW") then
              lookup[g.species] = g.area
          end
      end
      return lookup
  end

  ---------------------------------------------------------------------
  -- IN-GAME TRADE TABLE  (version-tagged)
  -- gives = species you receive; area = where the NPC lives.
  ---------------------------------------------------------------------
  local TRADE_DATA = {
      { gives = "JYNX",       wants = "POLIWHIRL", area = "CERULEAN_CITY",   version = "RB"  },
      { gives = "FARFETCHD",  wants = "SPEAROW",   area = "VERMILION_CITY",  version = "RB"  },
      { gives = "MR_MIME",    wants = "CLEFAIRY",  area = "ROUTE_2",         version = "RB"  },
      { gives = "LICKITUNG",  wants = "SLOWBRO",   area = "FUCHSIA_CITY",    version = "RB"  },
      { gives = "ELECTRODE",  wants = "RHYDON",    area = "CINNABAR_ISLAND", version = "RB"  },
      { gives = "GOLEM",      wants = "GRAVELER",  area = "CINNABAR_ISLAND", version = "RB"  },
      { gives = "KANGASKHAN", wants = "PARASECT",  area = "SAFARI_ZONE",     version = "RB"  },
      { gives = "JYNX",       wants = "POLIWHIRL", area = "CERULEAN_CITY",   version = "YLW" },
      { gives = "FARFETCHD",  wants = "SPEAROW",   area = "VERMILION_CITY",  version = "YLW" },
      { gives = "MR_MIME",    wants = "CLEFAIRY",  area = "ROUTE_2",         version = "YLW" },
      { gives = "GOLEM",      wants = "GRAVELER",  area = "CINNABAR_ISLAND", version = "YLW" },
      { gives = "MACHOKE",    wants = "CUBONE",    area = "ROUTE_5",         version = "YLW" },
  }

  local function buildTradeLookup()
      local ver = getGameVersion()
      local lookup = {}
      for _, t in ipairs(TRADE_DATA) do
          if t.version == nil
              or (t.version == "RB"  and (ver == "RED" or ver == "BLUE"))
              or (t.version == "YLW" and ver == "YELLOW") then
              lookup[t.gives] = t.area
          end
      end
      return lookup
  end

  ---------------------------------------------------------------------
  -- STARTER SPECIES LOOKUP  (version-aware)
  ---------------------------------------------------------------------
  local STARTERS_BY_VERSION = {
      RED    = { BULBASAUR = true, CHARMANDER = true, SQUIRTLE = true },
      BLUE   = { BULBASAUR = true, CHARMANDER = true, SQUIRTLE = true },
      YELLOW = { PIKACHU   = true },
  }

  local function isStarterSpecies(species)
      local ver = getGameVersion()
      local starters = STARTERS_BY_VERSION[ver] or STARTERS_BY_VERSION["RED"]
      return starters[tostring(species or ""):upper()] == true
  end

  ---------------------------------------------------------------------
  -- REGISTER STARTER IN PALLET TOWN
  -- Always records the starter in PALLET_TOWN regardless of the
  -- town_catches toggle. Pallet Town is the one mandatory town slot.
  ---------------------------------------------------------------------
  local function registerStarterCatch(species, mon)
      if not species then return end
      species = tostring(species):upper()
      local area = "PALLET_TOWN"
      registerArea(area)
      markVisited(area)

      local areas = caughtAreas()
      if areas[area] then
          -- A starter can emit both received and caught events. If the slot is
          -- already registered, tag this event's mon as handled so the later
          -- pokemon.caught event cannot create a second log entry.
          if mon then
              mon.catchLocation = area
              mon.encounterType = "gift"
              mon.nuzlockeTrackerRegistered = true
          end
          return
      end

      local log = trackerLog()
      log[area] = log[area] or {}
      table.insert(log[area], {
          species       = species,
          isShiny       = mon and mon.dvs and Stats.isShiny(mon.dvs) or false,
          encounterType = "gift",
      })
      mod.save:set("tracker_log", log)
      markCaught(area, species)

      if mon then
          mon.catchLocation = area
          mon.encounterType = "gift"
          mon.nuzlockeDead  = false
          mon.nuzlockeTrackerRegistered = true
      end

      local history = mod.save:get("nuzlocke_history", {})
      if type(history) ~= "table" then history = {} end
      table.insert(history, {
          name          = (mon and (mon.nickname or mon.species)) or species,
          species       = species,
          catchLocation = area,
          encounterType = "gift",
          status        = "ALIVE",
      })
      mod.save:set("nuzlocke_history", history)
  end

  ---------------------------------------------------------------------
  -- REGISTER GIFT / TRADE CATCH IN ITS PROPER AREA
  ---------------------------------------------------------------------
  local function registerSpecialCatch(species, area, encounterType, mon)
      if not species or not area then return end
      registerArea(area)
      markVisited(area)

      local log = trackerLog()
      log[area] = log[area] or {}
      table.insert(log[area], {
          species       = species,
          isShiny       = mon and mon.dvs and Stats.isShiny(mon.dvs) or false,
          encounterType = encounterType,
      })
      mod.save:set("tracker_log", log)
      markCaught(area, species)

      if mon then
          mon.catchLocation = area
          mon.encounterType = encounterType
          mon.nuzlockeDead  = false
          mon.nuzlockeTrackerRegistered = true
      end

      local history = mod.save:get("nuzlocke_history", {})
      if type(history) ~= "table" then history = {} end
      table.insert(history, {
          name          = (mon and (mon.nickname or mon.species)) or species,
          species       = species,
          catchLocation = area,
          encounterType = encounterType,
          status        = "ALIVE",
      })
      mod.save:set("nuzlocke_history", history)
  end

  ---------------------------------------------------------------------
  -- POKEMON.RECEIVED  —  starters, gifts, trades
  --
  -- ev fields (varies by engine build):
  --   ev.mon / ev.species   — the Pokemon received
  --   ev.source             — "starter" | "gift" | "trade" | "fossil" | "prize"
  --   ev.location / ev.mapId / ev.area — where it was received
  --   ev.game               — game reference
  --
  -- Priority:
  --   1. Starter        → always PALLET_TOWN, bypasses town_catches.
  --   2. Gift (allowed) → area from GIFT_LOCATIONS or current map.
  --   3. Gift (blocked) → mon removed from party.
  --   4. Trade (allowed)→ area from TRADE_DATA or current map.
  --   5. Trade (blocked)→ mon removed from party.
  ---------------------------------------------------------------------
  mod.events:on("pokemon.received", function(ev)
      if not ev then return end
      local game    = ev.game or currentGame
      local mon     = ev.mon
      local species = tostring(ev.species or (mon and mon.species) or "")
      if species == "" then return end
      species = species:upper()

      local source = tostring(ev.source or ""):lower()

      local rawLoc = ev.location or ev.mapId or ev.area
          or (game and game.overworld and game.overworld.map
              and game.overworld.map.id)
          or (game and game.save and game.save.player
              and game.save.player.map)
      local loc = routeKey(rawLoc) or "UNKNOWN"

      -- 1. Starter (explicit flag or species+location heuristic)
      local isStarter = (source == "starter")
          or (isStarterSpecies(species)
              and (loc == "PALLET_TOWN" or loc == "UNKNOWN"))
      -- Yellow: Pikachu is always the starter regardless of location tag
      local isYellowPikachu = (getGameVersion() == "YELLOW")
          and species == "PIKACHU"
          and (source == "starter" or loc == "PALLET_TOWN" or loc == "UNKNOWN")

      if isStarter or isYellowPikachu then
          -- Nuzlocke must be active for tracking; but we still register
          -- even if the master toggle is off so the slot stays coherent.
          registerStarterCatch(species, mon)
          return
      end

      -- Only enforce gifts/trades when Nuzlocke is active.
      if not active(game, nil) then return end

      local giftLookup  = buildGiftLookup()
      local tradeLookup = buildTradeLookup()

      local isGift  = (source == "gift" or source == "fossil"
          or source == "prize" or giftLookup[species] ~= nil)
      local isTrade = (source == "trade" or tradeLookup[species] ~= nil)

      -- 2-3. Gift
      if isGift and not isTrade then
          if not mod.save:get("allow_gifts", false) then
              if mon and game and game.save and game.save.party then
                  for i = #game.save.party, 1, -1 do
                      if game.save.party[i] == mon then
                          table.remove(game.save.party, i); break
                      end
                  end
              end
              return
          end
          local giftArea = giftLookup[species] or loc
          registerSpecialCatch(species, giftArea, "gift", mon)
          return
      end

      -- 4-5. Trade
      if isTrade then
          if not mod.save:get("allow_trades", false) then
              if mon and game and game.save and game.save.party then
                  for i = #game.save.party, 1, -1 do
                      if game.save.party[i] == mon then
                          table.remove(game.save.party, i); break
                      end
                  end
              end
              return
          end
          local tradeArea = tradeLookup[species] or loc
          registerSpecialCatch(species, tradeArea, "trade", mon)
      end
  end)

  ---------------------------------------------------------------------
  -- CATCH RULE ENFORCEMENT
  ---------------------------------------------------------------------
  local function pokemonFamily(game, species)
      local found, pending = {}, { species }
      local data = game and game.data and game.data.pokemon or {}
      while #pending > 0 do
          local id = table.remove(pending)
          if id and not found[id] then
              found[id] = true
              local def = data[id]
              for _, evo in ipairs((def and def.evolutions) or {}) do
                  if evo and evo.species then pending[#pending + 1] = evo.species end
              end
              for parent, parentDef in pairs(data) do
                  for _, evo in ipairs((parentDef and parentDef.evolutions) or {}) do
                      if evo and evo.species == id then
                          pending[#pending + 1] = parent
                      end
                  end
              end
          end
      end
      return found
  end

  local function ownsFamily(game, species)
      local members = pokemonFamily(game, species)
      local function owns(mon) return mon and members[mon.species] == true end
      for _, mon in ipairs((game.save and game.save.party) or {}) do
          if owns(mon) then return true end
      end
      for _, box in ipairs((game.save and game.save.boxes) or {}) do
          for _, mon in ipairs(box or {}) do
              if owns(mon) then return true end
          end
      end
      return false
  end

  ---------------------------------------------------------------------
  -- FAILED ENCOUNTER STATE
  -- A failed eligible wild encounter consumes the area's encounter slot.
  -- Dupes encounters do not consume the slot while Dupes Clause is ON.
  ---------------------------------------------------------------------
  local function encounterStates()
      local states = mod.save:get("encounter_states")
      if type(states) ~= "table" then
          states = {}
          mod.save:set("encounter_states", states)
      end
      return states
  end

  local function getEncounterState(key)
      if not key then return nil end
      return encounterStates()[key]
  end

  local function markEncounterFailed(key, species, encounterType)
      if not key or mod.save:get("failed_encounter", true) ~= true then return end
      key = registerArea(key)
      if not isTrackedArea(key) then return end
      local states = encounterStates()
      states[key] = {
          status = "FAILED",
          species = species,
          encounterType = encounterType or "wild",
      }
      mod.save:set("encounter_states", states)
  end

  local function markEncounterCaught(key, species, encounterType)
      if not key then return end
      key = registerArea(key)
      if not isTrackedArea(key) then return end
      local states = encounterStates()
      states[key] = {
          status = "CAUGHT",
          species = species,
          encounterType = encounterType or "wild",
      }
      mod.save:set("encounter_states", states)
  end

  local activeWildEncounter = nil

  local function isTrainerBattleForNuzlocke(battle)
      if not battle then return false end
      if battle.trainerBattle == true or battle.isTrainerBattle == true then return true end
      if battle.trainer ~= nil or battle.opponentTrainer ~= nil then return true end
      if battle.opponent and type(battle.opponent) == "table" and battle.opponent.name then return true end
      return false
  end

  local function beginWildEncounter(payload)
      if not payload then return end
      local battle = payload.battle or payload
      if not battle or isTrainerBattleForNuzlocke(battle) then return end
      if not currentGame then currentGame = payload.game end
      local game = payload.game or currentGame
      if not active(game, battle) then return end

      local key = areaKey(game, battle)
      if not key then return end
      local species = battle.enemy and battle.enemy.mon and battle.enemy.mon.species
          or battle.enemy and battle.enemy.species
          or payload.species
      if type(species) ~= "string" or species == "" then return end

      local shiny = enemyIsShiny(battle)
      local shinyClause = mod.save:get("shiny_clause", false) == true
      local town = isTownArea(key, routeName(key))
      local overworld = battle.overworldEncounter == true
          or battle.overworld == true
          or battle.isOverworld == true
          or battle.encounterType == "overworld"
          or battle.source == "overworld"

      if overworld and not mod.save:get("overworld_encounters", false) then return end
      if town and not mod.save:get("town_catches", false) then return end
      if not mod.save:get("encounter_limit", false) then return end
      if mod.save:get("failed_encounter", true) ~= true then return end
      if caughtAreas()[key] ~= nil then return end

      local existing = getEncounterState(key)
      if existing and (existing.status == "FAILED" or existing.status == "CAUGHT") then return end

      if mod.save:get("dupes_mode", false) and ownsFamily(game, species)
          and not (shiny and shinyClause) then
          return
      end

      activeWildEncounter = {
          battle = battle,
          game = game,
          key = key,
          species = species,
          encounterType = overworld and "overworld" or (town and "town" or "wild"),
          resolved = false,
      }
  end

  mod.events:on("battle.started", function(payload)
      beginWildEncounter(payload)
  end)

  mod.events:on("battle.ended", function(payload)
      -- Do not rely on battle.started state surviving the battle.  The engine's
      -- authoritative finish seam emits battle.ended with the actual BattleState,
      -- so resolve the failed encounter directly from that battle.  This also
      -- works when a battle is ended by RUN, KO, or another teardown path.
      local pending = activeWildEncounter
      activeWildEncounter = nil

      local battle = payload and (payload.battle or payload)
      local game = currentGame
      if not battle or not game or not game.save then
          return
      end
      if pending and pending.battle and battle ~= pending.battle then
          pending = nil
      end
      if isTrainerBattleForNuzlocke(battle) then
          return
      end
      if mod.save:get("nuzlocke_enabled", true) ~= true
          or mod.save:get("encounter_limit", false) ~= true
          or mod.save:get("failed_encounter", true) ~= true then
          return
      end

      local key = areaKey(game, battle)
      local species = battle.enemy and battle.enemy.mon and battle.enemy.mon.species
      if not key or type(species) ~= "string" or species == "" then
          return
      end

      local shiny = enemyIsShiny(battle)
      if shiny and mod.save:get("shiny_clause", false) == true then
          return
      end

      local town = isTownArea(key, routeName(key))
      local overworld = battle.overworldEncounter == true
          or battle.overworld == true
          or battle.isOverworld == true
          or battle.encounterType == "overworld"
          or battle.source == "overworld"
      if overworld and mod.save:get("overworld_encounters", false) ~= true then
          return
      end
      if town and mod.save:get("town_catches", false) ~= true then
          return
      end
      if caughtAreas()[key] ~= nil then
          return
      end

      local state = getEncounterState(key)
      if state and (state.status == "FAILED" or state.status == "CAUGHT") then
          return
      end

      if mod.save:get("dupes_mode", false) == true
          and ownsFamily(game, species) then
          return
      end

      markEncounterFailed(key, species, overworld and "overworld"
          or (town and "town" or "wild"))
  end)

  enemyIsShiny = function(battle)
      return battle and battle.enemy and battle.enemy.mon
          and battle.enemy.mon.dvs
          and Stats.isShiny(battle.enemy.mon.dvs) == true
  end

  catchDeniedReason = function(game, battle, species)
      if not active(game, battle) then
          return nil
      end

      -- Guard: species must be a non-empty string. A nil species means the
      -- enemy slot is not populated yet (e.g. transition frames); let it
      -- through rather than incorrectly blocking the throw.
      if type(species) ~= "string" or species == "" then
          return nil
      end

      local key = areaKey(game, battle)
      if not key then
          return nil
      end

      syncCaughtAreasFromLog()

      local overworld = false
      if battle then
          overworld = battle.overworldEncounter == true
              or battle.overworld == true
              or battle.isOverworld == true
              or battle.encounterType == "overworld"
              or battle.source == "overworld"
      end

      local town = isTownArea(key, routeName(key))
      local shiny = enemyIsShiny(battle)
      local shinyClause = mod.save:get("shiny_clause", false) == true

      if overworld and not mod.save:get("overworld_encounters", false) then
          return "overworld"
      end

      if town and not mod.save:get("town_catches", false) then
          return "town"
      end

      if mod.save:get("ban_legendaries", false) and LEGENDARIES[species] then
          return "legendary"
      end

      if mod.save:get("ban_mythicals", false) and MYTHICALS[species] then
          return "mythical"
      end

      if mod.save:get("encounter_limit", false)
          and caughtAreas()[key]
          and not (shiny and shinyClause) then
          return "area"
      end

      local encounterState = getEncounterState(key)
      if mod.save:get("encounter_limit", false)
          and mod.save:get("failed_encounter", true)
          and encounterState and encounterState.status == "FAILED"
          and not (shiny and shinyClause) then
          return "area"
      end

      if mod.save:get("dupes_mode", false)
          and ownsFamily(game, species)
          and not shiny then
          return "dupes"
      end

      if mod.save:get("solo_active", false) then
          local party = game.save and game.save.party or {}
          local occupied = 0
          for _, mon in ipairs(party) do
              if mon and mon.species then occupied = occupied + 1 end
          end
          if occupied >= 1 then
              return "solo"
          end
      end

      return nil
  end

  ---------------------------------------------------------------------
  -- ENCOUNTER TYPE
  -- Stored on each Pokemon and tracker entry for Catch Info and history.
  ---------------------------------------------------------------------
  local function encounterTypeFor(ev, key)
      if isOverworldEncounter(ev) then return "overworld" end
      if ev and ev.battle and ev.battle.safari then return "safari" end
      if isTownArea(key, routeName(key)) then return "town" end
      return "wild"
  end

  ---------------------------------------------------------------------
  -- POKEMON CAUGHT
  ---------------------------------------------------------------------
  mod.events:on("pokemon.caught", function(ev)
      if not active(ev.game, ev.battle) then
          return
      end

      local key = areaKey(ev.game, ev.battle)
      if not key then return end

      local isShiny = ev.mon and Stats.isShiny(ev.mon.dvs) or false
      local encounterType = encounterTypeFor(ev, key)

      -- Starters/gifts/trades can emit both pokemon.received and
      -- pokemon.caught in the same acquisition flow. Do not log the same mon
      -- twice or overwrite its authoritative received location.
      local alreadyRegistered = ev.mon and ev.mon.nuzlockeTrackerRegistered == true
      if alreadyRegistered then
          markVisited(key)
          return
      end

      if ev.mon then
          ev.mon.catchLocation = key
          ev.mon.encounterType = encounterType
          ev.mon.nuzlockeDead = false
          ev.mon.deathCause = nil
          ev.mon.deathCauseText = nil
          ev.mon.nuzlockeTrackerRegistered = true

          local history = mod.save:get("nuzlocke_history", {})
          if type(history) ~= "table" then history = {} end
          table.insert(history, {
              name = ev.mon.nickname or ev.mon.species or ev.species or "???",
              species = ev.mon.species or ev.species,
              catchLocation = key,
              encounterType = encounterType,
              status = "ALIVE",
          })
          mod.save:set("nuzlocke_history", history)
      end

      markVisited(key)
      markEncounterCaught(key, ev.species or (ev.mon and ev.mon.species), encounterType)
      if activeWildEncounter and activeWildEncounter.key == key then
          activeWildEncounter.resolved = true
      end

      local log = trackerLog()
      log[key] = log[key] or {}

      -- Never append the same species twice to one area. This is especially
      -- important for acquisition flows where the engine can emit both a
      -- received event and a caught event on separate Pokemon tables.
      local duplicate = false
      local speciesKey = tostring(ev.species or (ev.mon and ev.mon.species) or ""):upper()
      for _, entry in ipairs(log[key]) do
          if tostring(entry and entry.species or ""):upper() == speciesKey then
              duplicate = true
              break
          end
      end

      if not duplicate then
          table.insert(log[key], {
              species = ev.species,
              isShiny = isShiny,
              encounterType = encounterType
          })
          mod.save:set("tracker_log", log)
      end

      -- Only successful eligible catches consume the area's encounter.
      if not isShiny or not mod.save:get("shiny_clause", false) then
          if mod.save:get("encounter_limit", false) then
              markCaught(key, ev.species)
          end
      end
  end)

  -- NOTE: Legendary and Mythical catch blocking is enforced entirely at the
  -- throwBall level via catchDeniedReason. The engine refunds the ball and
  -- the catch never registers, so no post-catch removal is needed here.
  -- A secondary removal would incorrectly consume the ball without refund.

  ---------------------------------------------------------------------
  -- WHITEOUT STATE
  ---------------------------------------------------------------------
  local whiteoutPending = false

  local function hasHealthyParty(game)
      local party = game and game.save and game.save.party or {}
      for _, mon in ipairs(party) do
          if mon then
              local hp = tonumber(mon.hp or mon.currentHp or mon.health)
              if hp ~= nil then
                  if hp > 0 then return true end
              elseif mon.fainted ~= true and mon.status ~= "fainted" then
                  return true
              end
          end
      end
      return false
  end

  ---------------------------------------------------------------------
  -- PERMADEATH / WHITEOUT ENFORCEMENT
  --
  -- Use BattleState:onFaint itself, following Bryan's implementation seam.
  -- This is important because the battle's own faint lifecycle is the point
  -- where the last usable party member is determined. The previous event-only
  -- implementation could lose the race with the vanilla blackout/restore
  -- flow, which is why a trainer loss could appear to revive the party.
  ---------------------------------------------------------------------
  mod.events:on("game.ready", function()
      local ok, BattleState = pcall(require, "src.battle.BattleState")
      local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
      local okScreens, Screens = pcall(require, "src.ui.Screens")
      local okSave, SaveData = pcall(require, "src.core.SaveData")
      local okVersion, GameVersion = pcall(require, "src.core.GameVersion")

      if not ok or not BattleState then return end
      if BattleState.__nuzlockeFinal25FaintPatched then return end
      BattleState.__nuzlockeFinal25FaintPatched = true

      -------------------------------------------------------------------
      -- Capture the final damaging move exactly where Gen 1 computes it.
      -- Damage.compute returns { crit = bool }, so the death record can
      -- report a real critical hit instead of guessing.
      -------------------------------------------------------------------
      if not BattleState.__nuzlockeDamagePatched then
          BattleState.__nuzlockeDamagePatched = true
          local vanillaComputeDamage = BattleState.computeDamage
          BattleState.computeDamage = function(self, user, target, move, opts)
              local damage, result = vanillaComputeDamage(self, user, target, move, opts)
              if target and target.isPlayer and tonumber(damage) and damage > 0 then
                  self.nuzlockeLastDamage = {
                      target = target,
                      attacker = user,
                      move = move and (move.name or move.id) or "UNKNOWN",
                      moveId = move and move.id,
                      critical = result and result.crit == true or false,
                  }
              end
              return damage, result
          end
      end

      -------------------------------------------------------------------
      -- Status/residual deaths are recorded before BattleState:onFaint is
      -- reached, so poison/burn/Leech Seed can be distinguished from the
      -- previous damaging move.
      -------------------------------------------------------------------
      local okStatus, StatusModule = pcall(require, "src.battle.Status")
      if okStatus and StatusModule and not StatusModule.__nuzlockeDeathStatusPatched then
          StatusModule.__nuzlockeDeathStatusPatched = true
          local vanillaResidual = StatusModule.residual
          StatusModule.residual = function(battler, opponent, battle, ...)
              local before = battler and battler.mon and tonumber(battler.mon.hp) or nil
              local result = vanillaResidual(battler, opponent, battle, ...)
              if battler and battler.isPlayer and battler.mon then
                  local after = tonumber(battler.mon.hp)
                  if before and after and before > 0 and after <= 0 then
                      local status = tostring(battler.mon.status or "")
                      local label = nil
                      if status == "POISON" or status == "PSN" or status == "BADLY_POISONED" or status == "TOX" then
                          label = "POISON"
                      elseif status == "BURN" or status == "BRN" then
                          label = "BURN"
                      elseif battler.leechSeeded then
                          label = "LEECH SEED"
                      end
                      battle.nuzlockeLastResidual = label or "STATUS DAMAGE"
                  end
              end
              return result
          end
      end

      local vanillaOnFaint = BattleState.onFaint
      BattleState.onFaint = function(self, battler)
          if not (battler and battler.isPlayer and active(self.game, self)) then
              return vanillaOnFaint(self, battler)
          end

          if mod.save:get("permadeath", true) then
              local mon = battler.mon
              if mon and not mon.nuzlockeDead then
                  local key = areaKey(self.game, self)
                  local enemy = self.enemy and self.enemy.mon
                  local enemyName = self.enemy and self.enemy.name
                  local enemySpecies = enemyName or (enemy and enemy.species) or "BATTLE"
                  local source = "Wild " .. tostring(enemySpecies)
                  local trainerName = self.trainer and self.trainer.name
                  local oppClass = tostring(self.oppClass or "")

                  if self.kind == "trainer" then
                      local upperClass = oppClass:upper()
                      if upperClass:find("RIVAL", 1, true) then
                          source = "Your Rival " .. tostring(trainerName or "BLUE") .. "'s " .. tostring(enemySpecies)
                      elseif upperClass:find("BROCK", 1, true)
                          or upperClass:find("MISTY", 1, true)
                          or upperClass:find("LT_SURGE", 1, true)
                          or upperClass:find("ERIKA", 1, true)
                          or upperClass:find("KOGA", 1, true)
                          or upperClass:find("SABRINA", 1, true)
                          or upperClass:find("BLAINE", 1, true)
                          or upperClass:find("GIOVANNI", 1, true) then
                          source = "Gym Leader " .. tostring(trainerName or oppClass) .. "'s " .. tostring(enemySpecies)
                      elseif upperClass:find("LORELEI", 1, true)
                          or upperClass:find("BRUNO", 1, true)
                          or upperClass:find("AGATHA", 1, true)
                          or upperClass:find("LANCE", 1, true) then
                          source = "Elite Four " .. tostring(trainerName or oppClass) .. "'s " .. tostring(enemySpecies)
                      elseif upperClass:find("ROCKET", 1, true) then
                          source = "Team Rocket " .. tostring(trainerName or "Trainer") .. "'s " .. tostring(enemySpecies)
                      elseif trainerName then
                          source = tostring(trainerName) .. "'s " .. tostring(enemySpecies)
                      else
                          source = "Trainer's " .. tostring(enemySpecies)
                      end
                  end

                  local damage = self.nuzlockeLastDamage
                  local causeText
                  if self.nuzlockeLastResidual then
                      causeText = tostring(mon.nickname or mon.species or "Pokemon")
                          .. " died to " .. source
                          .. " after " .. tostring(self.nuzlockeLastResidual) .. "."
                  elseif damage and damage.target == battler then
                      local moveName = tostring(damage.move or "UNKNOWN")
                      local critPrefix = damage.critical and "a critical " or ""
                      if damage.attacker == battler then
                          causeText = tostring(mon.nickname or mon.species or "Pokemon")
                              .. " died after " .. critPrefix .. moveName .. "."
                      else
                          causeText = tostring(mon.nickname or mon.species or "Pokemon")
                              .. " died to " .. source
                              .. " after " .. critPrefix .. moveName .. "."
                      end
                  else
                      causeText = tostring(mon.nickname or mon.species or "Pokemon")
                          .. " died in battle against " .. source .. "."
                  end

                  mon.nuzlockeDead = true
                  mon.deathLocation = key
                  mon.deathCause = causeText
                  mon.deathCauseText = causeText
                  mon.deathEncounterType =
                      (self.kind == "trainer") and "trainer" or "wild"
                  mon.deathOpponentSpecies = enemySpecies
                  mon.deathMove = damage and damage.move or nil
                  mon.deathCritical = damage and damage.critical == true or false
                  mon.deathStatusCondition = self.nuzlockeLastResidual

                  local history = mod.save:get("nuzlocke_history", {})
                  if type(history) ~= "table" then history = {} end
                  table.insert(history, {
                      name = mon.nickname or mon.species or "???",
                      species = mon.species,
                      catchLocation = mon.catchLocation,
                      encounterType = mon.encounterType,
                      status = "LOST",
                      deathLocation = key,
                      deathCause = causeText,
                      deathOpponentSpecies = enemySpecies,
                      deathMove = mon.deathMove,
                      deathCritical = mon.deathCritical,
                      deathStatusCondition = mon.deathStatusCondition,
                  })
                  mod.save:set("nuzlocke_history", history)

                  mod.save:set(
                      "nuzlocke_losses",
                      (tonumber(mod.save:get("nuzlocke_losses", 0)) or 0) + 1
                  )

                  mod.save:set("last_loss", {
                      name = mon.nickname or mon.species or "???",
                      species = mon.species,
                      location = key,
                      cause = cause,
                  })

                  -- Remove the dead mon before vanilla's playerMonFainted()
                  -- checks for a usable party. This prevents the normal
                  -- blackout routine from healing/restoring a dead member.
                  if self.game and self.game.save and self.game.save.party then
                      for i, partyMon in ipairs(self.game.save.party) do
                          if partyMon == mon then
                              table.remove(self.game.save.party, i)
                              break
                          end
                      end
                  end
              end

              self.nuzlockeLastDamage = nil
              self.nuzlockeLastResidual = nil

              if not mod.save:get("whiteout_clause", false)
                  and not hasHealthyParty(self.game) then
                  self.nuzlockeGameOver = true
              end
          end

          -- Preserve the engine's normal faint animation, cry, text, and
          -- battle queue. We only alter the save/party state before it runs.
          return vanillaOnFaint(self, battler)
      end

      local vanillaPlayerFainted = BattleState.playerMonFainted
      BattleState.playerMonFainted = function(self)
          if self.nuzlockeGameOver then
              self.result = "nuzlocke_game_over"
              self.afterQueue = "finish"
              -- Try every known message API in priority order.
              local msg = "All of your\nPOKeMON are dead...\nYour run is over."
              if type(self.sayNext) == "function" then
                  pcall(self.sayNext, self, msg)
              elseif type(self.say) == "function" then
                  pcall(self.say, self, msg)
              elseif type(self.message) == "function" then
                  pcall(self.message, self, msg)
              end
              return
          end
          return vanillaPlayerFainted(self)
      end

      local vanillaFinish = BattleState.finish
      BattleState.finish = function(self)
          if not self.nuzlockeGameOver then
              return vanillaFinish(self)
          end

          self.nuzlockeGameOver = nil

          if self.game and self.game.stack then
              self.game.stack:pop()
          end

          if okRuntime and Runtime then
              Runtime.emit("battle.ended", {
                  battle = self,
                  result = "nuzlocke_game_over"
              })
          end

          if okSave and okVersion and SaveData and GameVersion
              and SaveData.activeSlot then

              local version = GameVersion.get()
              local slot = SaveData.activeSlot(version)
              if slot then
                  SaveData.deleteSlot(version, slot)
              end
          end

          if okScreens and Screens then
              local ending = Screens.push(self.game, "Credits", function()
                  local musicOk, Music = pcall(require, "src.core.Music")
                  if musicOk and Music then
                      Music.stop()
                  end

                  while self.game.stack:top() do
                      self.game.stack:pop()
                  end

                  if self.game.makeTitleState then
                      self.game.stack:push(self.game:makeTitleState())
                  end
              end)

              if ending then
                  ending.phase, ending.timer = "end_wait", 0
              end
          end
      end
  end)

  ---------------------------------------------------------------------
  -- POKé MART / POKéMON CENTER ENFORCEMENT
  --
  -- Install the live command patch as soon as the command module is
  -- available, and retry on save.loaded/game.ready.  This avoids the
  -- previous failure mode where the map scripts had already cached their
  -- command resolver before the one-time game.ready patch ran.
  ---------------------------------------------------------------------
  local function installNuzlockeFieldCommandPatches()
      local okCommands, Commands = pcall(require, "src.script.Commands")
      if not okCommands or not Commands then
          return false
      end

      if Commands.__nuzlockeV315Patched then
          return true
      end

      local originalHeal = Commands.heal_party
      local originalOpenMart = Commands.open_mart
      if type(originalHeal) ~= "function" then
          return false
      end

      Commands.__nuzlockeV315Patched = true

      local function showRuleMessage(ctx, msg)
          local shown = false
          if type(Commands.show_text) == "function" then
              local ok = pcall(Commands.show_text, ctx, msg)
              shown = ok
          elseif type(Commands.text) == "function" then
              local ok = pcall(Commands.text, ctx, msg)
              shown = ok
          elseif type(Commands.message) == "function" then
              local ok = pcall(Commands.message, ctx, msg)
              shown = ok
          end

          if not shown then
              local game = ctx and (ctx.game or (ctx.env and ctx.env.game))
              if game and game.stack then
                  local okText, TextBox = pcall(require, "src.render.TextBox")
                  if okText and TextBox then
                      pcall(function()
                          game.stack:push(TextBox.new(game, msg))
                      end)
                  end
              end
          end
      end

      -- Hook callbacks run inside the hook bus's protected call, so they must
      -- not yield.  Push the TextBox directly here; the hook returns "end"
      -- and the script is finished underneath it.
      local function showRuleMessageImmediate(ctx, msg)
          local game = ctx and (ctx.game or (ctx.env and ctx.env.game))
          if not game or not game.stack then return end
          local okText, TextBox = pcall(require, "src.render.TextBox")
          if okText and TextBox then
              pcall(function()
                  game.stack:push(TextBox.new(game, msg))
              end)
          end
      end

  ---------------------------------------------------------------------
  -- AUTHORITATIVE SCRIPT-COMMAND HEAL GATE
  --
  -- The recomp's ScriptRunner resolves every script row through the live
  -- Runtime "script.command" hook.  This is more reliable than only replacing
  -- Commands.heal_party because map scripts can otherwise retain a cached
  -- function reference.  We use the map id/label to distinguish Pokémon
  -- Centers from Mom's house, since both ultimately use heal_party.
  ---------------------------------------------------------------------
  local function nuzlockeMapTag(ctx)
      local ow = ctx and ctx.overworld
      local map = ow and ow.map
      local def = map and map.def
      local parts = {
          map and map.id,
          map and map.name,
          def and def.id,
          def and def.name,
          def and def.label,
      }
      local out = {}
      for _, value in ipairs(parts) do
          if value ~= nil then
              out[#out + 1] = tostring(value):upper()
          end
      end
      return table.concat(out, " ")
  end

  local function isPokemonCenterMap(ctx)
      local tag = nuzlockeMapTag(ctx)
      return (tag:find("POKEMON", 1, true) and tag:find("CENTER", 1, true))
          or (tag:find("POKE", 1, true) and tag:find("CENTER", 1, true))
  end

  local function isMomsHouseMap(ctx)
      local tag = nuzlockeMapTag(ctx)
      return tag:find("REDS_HOUSE", 1, true) ~= nil
          or tag:find("REDSHOUSE", 1, true) ~= nil
  end

  local nuzlockeScriptHealGateInstalled = false
  local function installNuzlockeScriptHealGate()
      if nuzlockeScriptHealGateInstalled then return end
      nuzlockeScriptHealGateInstalled = true

      mod.hooks:wrap("script.command", function(next, ctx, name, args)
          -- Mom's vanilla heal script fades to white immediately before
          -- heal_party.  If healing is disabled, suppress both fades so the
          -- personalized refusal is shown on the normal room screen.
          if name == "fade"
              and mod.save:get("no_mom_heal", false) == true
              and isMomsHouseMap(ctx) then
              return
          end

          if name == "heal_party" then
              if mod.save:get("no_mom_heal", false) == true
                  and isMomsHouseMap(ctx) then
                  -- Mom's vanilla script fades to white immediately before
                  -- heal_party.  This hook runs at heal_party, so skip the
                  -- remainder and replace the heal with Mom's own message.
                  showRuleMessageImmediate(ctx,
                      "Mom: I know you need\nrest, sweetheart, but\nour Nuzlocke rules say\nI can't heal your\nPokemon right now.\nYou'll be okay!")
                  return "end"
              end

              if mod.save:get("no_poke_center", false) == true
                  and isPokemonCenterMap(ctx) then
                  showRuleMessageImmediate(ctx,
                      "Nurse Joy: I'm sorry,\nbut your Nuzlocke\nrules don't allow\nPokemon Center\nhealing right now.")
                  return "end"
              end
          end

          return next(ctx, name, args)
      end, 10000)
  end

  installNuzlockeScriptHealGate()

      local function blockedHeal(ctx)
          -- heal_party is also used by Mom, so the Center rule must only
          -- fire while the script is actually running in a Pokemon Center.
          if mod.save:get("no_poke_center", false) == true
              and isPokemonCenterMap(ctx) then
              showRuleMessage(ctx,
                  "Nurse Joy: I'm sorry,\nbut your Nuzlocke\nrules don't allow\nPokemon Center\nhealing right now.")
              return
          end
          return originalHeal(ctx)
      end

      Commands.heal_party = blockedHeal

      if type(originalOpenMart) == "function" then
          local function blockedOpenMart(ctx, textConst)
              if mod.save:get("no_shopping", false) == true then
                  showRuleMessage(ctx,
                      "Clerk: I'd love to\nhelp, but your Nuzlocke\nrules prevent shopping.\nYour wallet lives to\nfight another day!")
                  return
              end
              return originalOpenMart(ctx, textConst)
          end
          Commands.open_mart = blockedOpenMart
      end

      -- Force the resolver to return the wrapped command too.  This is the
      -- important part for map scripts that resolve command names at runtime.
      if type(Commands.resolve) == "function" then
          local originalResolve = Commands.resolve
          Commands.resolve = function(data, name)
              if name == "heal_party" then
                  return blockedHeal, Commands.meta and Commands.meta[name]
              end
              if name == "open_mart" and type(originalOpenMart) == "function" then
                  return Commands.open_mart, Commands.meta and Commands.meta[name]
              end
              return originalResolve(data, name)
          end
      end

      -- Secondary hook seams for builds that expose field healing through the
      -- public hook layer instead of the script command table.
      local function denyCenter(next, ctx, ...)
          if mod.save:get("no_poke_center", false) == true
              and isPokemonCenterMap(ctx) then
              showRuleMessage(ctx,
                  "Nurse Joy: I'm sorry,\nbut your Nuzlocke\nrules don't allow\nPokemon Center\nhealing right now.")
              return false
          end
          return next(ctx, ...)
      end

      for _, hookName in ipairs({
          "pokemon_center.heal",
          "poke_center.heal",
          "pokemon.center.heal",
          "heal_party",
          "field.heal_party"
      }) do
          pcall(mod.hooks.wrap, mod.hooks, hookName, denyCenter, 1000)
      end

      local momMsg =
          "Mom: I'd love to\nheal your Pokemon,\nbut your Nuzlocke\nrules won't let me.\nI believe in you,\nsweetheart!"
      for _, name in ipairs({ "mom_heal", "heal_mom", "mom_rest", "mom_heals" }) do
          if type(Commands[name]) == "function" then
              local originalMom = Commands[name]
              Commands[name] = function(ctx)
                  if mod.save:get("no_mom_heal", false) == true then
                      showRuleMessage(ctx, momMsg)
                      return
                  end
                  return originalMom(ctx)
              end
          end
      end

      return true
  end

  -- Try immediately and again at both lifecycle points.  The helper is
  -- idempotent, so whichever point sees Commands first performs the install.
  pcall(installNuzlockeFieldCommandPatches)
  mod.events:on("game.ready", function()
      pcall(installNuzlockeFieldCommandPatches)
  end)
  mod.events:on("save.loaded", function()
      pcall(installNuzlockeFieldCommandPatches)
  end)

end

#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_terrain_test")

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  print(string.format("%d passed, %d failed", passed, failed))
  if failed > 0 then
    print("BATTLE_TERRAIN FAIL")
    os.exit(1)
  end
  print("BATTLE_TERRAIN PASS")
  os.exit(0)
end

local BattleBg = require("src.core.game3.battle.bg")
local T = BattleBg.TERRAIN
local MT = BattleBg.MAP_TYPE
local SCENE = BattleBg.MAP_BATTLE_SCENE

print("[test] 1. BATTLE_TERRAIN ids match pret include/constants/battle.h:287")
do
  local ids = {
    GRASS = 0, LONG_GRASS = 1, SAND = 2, UNDERWATER = 3, WATER = 4,
    POND = 5, MOUNTAIN = 6, CAVE = 7, BUILDING = 8, PLAIN = 9,
    LINK = 10, GYM = 11, LEADER = 12, INDOOR_2 = 13, INDOOR_1 = 14,
    LORELEI = 15, BRUNO = 16, AGATHA = 17, LANCE = 18, CHAMPION = 19,
  }
  local n = 0
  for name, id in pairs(ids) do
    eq(T[name], id, "BATTLE_TERRAIN_" .. name)
    n = n + 1
  end
  eq(n, 20, "20 terrain ids")
end

print("[test] 2. Every sBattleTerrainTable row has its own sheet key")
do
  local Extract = require("src.import.gba.battle_chrome_extract")
  local keys = Extract.TERRAIN_KEYS or {}
  local all = {}
  for id = 0, 19 do
    if keys[id] then all[keys[id]] = true end
  end
  BattleBg.setAvailableSheets(all)
  local seen = {}
  for id = 0, 19 do
    local key = BattleBg.sheetKey(id)
    eq(key, keys[id], "terrain " .. id .. " draws its own baked sheet")
    check(seen[key] == nil, "terrain " .. id .. " sheet " .. tostring(key) .. " is not shared")
    seen[key] = id
  end
  BattleBg.setAvailableSheets(nil)
end

print("[test] 3. BattleSetup_GetTerrainId rows (pokefirered/src/battle_setup.c:466)")
do
  local MB_NORMAL = 0x00
  local MB_TALL_GRASS = 0x02
  local MB_CAVE = 0x08
  local MB_INDOOR_ENCOUNTER = 0x0B
  local MB_MOUNTAIN_TOP = 0x0C
  local MB_POND_WATER = 0x10
  local MB_FAST_WATER = 0x11
  local MB_DEEP_WATER = 0x12
  local MB_OCEAN_WATER = 0x15
  local MB_SHALLOW_WATER = 0x17
  local MB_SAND = 0x21
  local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1

  local rows = {
    { MB_TALL_GRASS, MT.ROUTE, T.GRASS, "tall grass on a route is GRASS" },
    { MB_TALL_GRASS, MT.TOWN, T.GRASS, "tall grass in a town is GRASS" },
    { MB_CYCLING_ROAD_PULL_DOWN_GRASS, MT.ROUTE, T.GRASS, "cycling road grass is GRASS" },
    { MB_TALL_GRASS, MT.UNDERGROUND, T.GRASS, "tall grass beats the map type" },
    { MB_SAND, MT.ROUTE, T.SAND, "sand is SAND" },
    { MB_SHALLOW_WATER, MT.ROUTE, T.SAND, "shallow flowing water is SAND" },
    { MB_SAND, MT.INDOOR, T.SAND, "sand beats MAP_TYPE_INDOOR" },
    { MB_CAVE, MT.UNDERGROUND, T.CAVE, "cave floor underground is CAVE" },
    { MB_NORMAL, MT.UNDERGROUND, T.CAVE, "plain floor underground is CAVE" },
    { MB_INDOOR_ENCOUNTER, MT.UNDERGROUND, T.BUILDING, "indoor encounter underground is BUILDING" },
    { MB_POND_WATER, MT.UNDERGROUND, T.POND, "surfable underground is POND" },
    { MB_NORMAL, MT.INDOOR, T.BUILDING, "indoor is BUILDING" },
    { MB_NORMAL, MT.SECRET_BASE, T.BUILDING, "secret base is BUILDING" },
    { MB_NORMAL, MT.UNDERWATER, T.UNDERWATER, "underwater map is UNDERWATER" },
    { MB_POND_WATER, MT.OCEAN_ROUTE, T.WATER, "surfable on an ocean route is WATER" },
    { MB_NORMAL, MT.OCEAN_ROUTE, T.PLAIN, "dry land on an ocean route is PLAIN" },
    { MB_DEEP_WATER, MT.ROUTE, T.WATER, "deep water is WATER" },
    { MB_FAST_WATER, MT.ROUTE, T.WATER, "fast water is WATER" },
    { MB_OCEAN_WATER, MT.ROUTE, T.WATER, "ocean water is WATER" },
    { MB_POND_WATER, MT.ROUTE, T.POND, "pond water is POND" },
    { MB_MOUNTAIN_TOP, MT.ROUTE, T.MOUNTAIN, "mountain top is MOUNTAIN" },
    { MB_NORMAL, MT.ROUTE, T.PLAIN, "bare route tile is PLAIN" },
    { MB_NORMAL, MT.NONE, T.PLAIN, "MAP_TYPE_NONE falls through to PLAIN" },
  }
  for _, row in ipairs(rows) do
    eq(BattleBg.resolveFromBehavior(row[1], nil, row[2]), row[3], row[4])
  end

  -- pokefirered/src/metatile_behavior.c:440 MetatileBehavior_IsLongGrass is FALSE in FRLG
  local sawLongGrass = false
  for beh = 0, 255 do
    for _, mt in ipairs({ MT.NONE, MT.TOWN, MT.CITY, MT.ROUTE, MT.UNDERGROUND,
      MT.UNDERWATER, MT.OCEAN_ROUTE, MT.UNKNOWN, MT.INDOOR, MT.SECRET_BASE }) do
      if BattleBg.resolveFromBehavior(beh, nil, mt) == T.LONG_GRASS then sawLongGrass = true end
    end
  end
  check(not sawLongGrass, "no behavior reaches LONG_GRASS on FRLG")
end

print("[test] 4. No behavior available falls back to the map kind")
do
  eq(BattleBg.resolveFromBehavior(nil, "cave", nil), T.CAVE, "nil behavior + cave kind is CAVE")
  eq(BattleBg.resolveFromBehavior(nil, "indoor", nil), T.BUILDING, "nil behavior + indoor kind is BUILDING")
  eq(BattleBg.resolveFromBehavior(nil, "route", nil), T.GRASS, "nil behavior + route kind is GRASS")
  eq(BattleBg.resolveFromMapKind("water"), T.WATER, "resolveFromMapKind still answers")
  eq(BattleBg.resolveFromBehavior(0x00, "cave", nil), T.CAVE, "cave kind stands in for MAP_TYPE_UNDERGROUND")
  eq(BattleBg.resolveFromBehavior(0x00, "route", nil), T.PLAIN, "route kind stands in for MAP_TYPE_ROUTE")
end

print("[test] 5. GetBattleTerrainOverride (pokefirered/src/battle_bg.c:1048)")
do
  eq(BattleBg.resolveOverride(T.CAVE, {}), T.CAVE, "no override keeps the map terrain")
  eq(BattleBg.resolveOverride(T.CAVE, { link = true }), T.LINK, "a link battle is LINK")
  eq(BattleBg.resolveOverride(T.CAVE, { trainerTower = true }), T.LINK, "a trainer tower battle is LINK")
  eq(BattleBg.resolveOverride(T.CAVE, { pokedude = true }), T.GRASS, "a pokedude battle is GRASS")
  eq(BattleBg.resolveOverride(T.CAVE, { trainer = true, trainerClass = 84 }), T.LEADER,
    "TRAINER_CLASS_LEADER is LEADER")
  eq(BattleBg.resolveOverride(T.CAVE, { trainer = true, trainerClass = 90 }), T.CHAMPION,
    "TRAINER_CLASS_CHAMPION is CHAMPION")
  eq(BattleBg.resolveOverride(T.CAVE, { trainer = true, trainerClass = 87 }), T.CAVE,
    "TRAINER_CLASS_ELITE_FOUR takes no class override")
  eq(BattleBg.resolveOverride(T.CAVE, { trainerClass = 84 }), T.CAVE,
    "a wild battle ignores the trainer class")
  eq(BattleBg.resolveOverride(T.GRASS, { mapBattleScene = SCENE.NORMAL }), T.GRASS,
    "MAP_BATTLE_SCENE_NORMAL keeps gBattleTerrain")
  local scenes = {
    { SCENE.GYM, T.GYM }, { SCENE.INDOOR_1, T.INDOOR_1 }, { SCENE.INDOOR_2, T.INDOOR_2 },
    { SCENE.LORELEI, T.LORELEI }, { SCENE.BRUNO, T.BRUNO }, { SCENE.AGATHA, T.AGATHA },
    { SCENE.LANCE, T.LANCE }, { SCENE.LINK, T.LINK },
  }
  for _, row in ipairs(scenes) do
    eq(BattleBg.resolveOverride(T.GRASS, { mapBattleScene = row[1] }), row[2],
      "map battle scene " .. row[1])
  end
  eq(BattleBg.resolveOverride(T.GRASS, { mapBattleScene = 99 }), T.PLAIN,
    "an unknown map battle scene is PLAIN")
  eq(BattleBg.resolveOverride(T.GRASS, { link = true, mapBattleScene = SCENE.GYM }), T.LINK,
    "link wins over the map battle scene")
end

print("[test] 6. A cache without a terrain's sheet degrades to the nearest one")
do
  BattleBg.setAvailableSheets({ grass = true, building = true })
  eq(BattleBg.sheetKey(T.LONG_GRASS), "grass", "long grass degrades to grass")
  eq(BattleBg.sheetKey(T.SAND), "grass", "sand degrades to grass")
  eq(BattleBg.sheetKey(T.CAVE), "building", "cave with no cave art degrades to building")
  eq(BattleBg.sheetKey(T.WATER), "grass", "water degrades to grass")
  eq(BattleBg.sheetKey(T.GRASS), "grass", "grass is drawn as grass")

  BattleBg.setAvailableSheets({ grass = true, plain = true, water = true, cave = true })
  eq(BattleBg.sheetKey(T.POND), "water", "pond degrades to water")
  eq(BattleBg.sheetKey(T.UNDERWATER), "water", "underwater degrades to water")
  eq(BattleBg.sheetKey(T.MOUNTAIN), "cave", "mountain degrades to cave")
  eq(BattleBg.sheetKey(T.BUILDING), "plain", "building degrades to plain")
  eq(BattleBg.sheetKey(T.LEADER), "grass", "leader with no indoor art ends at grass")
  eq(BattleBg.sheetKey(T.CHAMPION), "grass", "champion with no indoor art ends at grass")

  BattleBg.setAvailableSheets({})
  for id = 0, 19 do
    check(type(BattleBg.sheetKey(id)) == "string", "terrain " .. id .. " still names a sheet")
  end
  eq(BattleBg.sheetKey(255), "building", "an out of range terrain names building")

  BattleBg.setAvailableSheets(nil)
end

print("[test] 7. Battle.start resolves the terrain from the behavior it is handed")
do
  local Moves = require("src.core.game3.battle.moves")
  local ROM = {
    [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35,
      secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  }
  Moves._romLoaded = true
  Moves._rom = ROM
  Moves.loadRomPack = function()
    Moves._romLoaded = true
    Moves._rom = ROM
    return true
  end
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  local Battle = require("src.core.game3.battle")

  local function start(extra)
    Battle.abort()
    local session = {
      name = "RED",
      party = {
        { species = 1, name = "BULBASAUR", level = 10, hp = 30, maxHp = 30,
          attack = 12, defense = 12, spAtk = 12, spDef = 12, speed = 12,
          moves = { 33 }, pp = { 35 } },
      },
      dex = { seen = {}, owned = {} },
    }
    local opts = {
      headless = true,
      autoFight = false,
      wild = true,
      session = session,
      playerParty = session.party,
      rng = function(_, hi) return hi end,
      foe = { species = 16, level = 8, hp = 24, maxHp = 24,
        attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
        moves = { 33 }, pp = { 35 } },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    Battle.start(opts)
    return Battle.getState()
  end

  local st = start({ mapKind = "indoor", mapType = 4, mapBehavior = 0x08 })
  eq(st.terrain, T.CAVE, "Mt Moon: MAP_TYPE_UNDERGROUND + MB_CAVE is CAVE")
  eq(BattleBg.terrainId(), T.CAVE, "the draw path sees CAVE")
  Battle.abort()

  st = start({ mapKind = "route", mapType = 3, mapBehavior = 0x10 })
  eq(st.terrain, T.POND, "surfing a route pond is POND")
  Battle.abort()

  st = start({ mapKind = "route", mapType = 3, mapBehavior = 0x15 })
  eq(st.terrain, T.WATER, "surfing ocean water is WATER")
  Battle.abort()

  st = start({ mapKind = "route", mapType = 3, mapBehavior = 0x02 })
  eq(st.terrain, T.GRASS, "route tall grass is GRASS")
  Battle.abort()

  st = start({ mapKind = "indoor", mapType = 8, mapBehavior = 0x0B })
  eq(st.terrain, T.BUILDING, "an indoor encounter is BUILDING")
  Battle.abort()

  st = start({ mapKind = "route" })
  eq(st.terrain, T.GRASS, "the headless map kind path still resolves")
  Battle.abort()

  st = start({ mapKind = "route", mapType = 3, mapBehavior = 0x02, terrain = T.CAVE })
  eq(st.terrain, T.CAVE, "an explicit opts.terrain wins")
  Battle.abort()

  st = start({ mapKind = "indoor", mapType = 8, mapBehavior = 0x00,
    mapBattleScene = SCENE.GYM })
  eq(BattleBg.terrainId(), T.GYM, "a gym map draws the GYM background")
  eq(st.terrain, T.BUILDING, "and gBattleTerrain keeps the un-overridden id")
  Battle.abort()
end

print("[test] 8. The imported cache bakes every sheet these ids ask for")
do
  local Cache = require("tests.game3_cache")
  local root = Cache.root("meta.json")
  if not root then
    print("[skip] cache sheet check: " .. tostring(Cache.reason))
  else
    local f = io.open(root .. "/pokemon/battle/manifest.lua", "rb")
    if not f then
      print("[skip] cache sheet check: no pokemon/battle/manifest.lua in " .. root)
    else
      local src = f:read("*a")
      f:close()
      local m = assert(loadstring(src))()
      local have = m.terrains or {}
      BattleBg.setAvailableSheets(have)
      local Extract = require("src.import.gba.battle_chrome_extract")
      local fallbacks = {}
      for id = 0, 19 do
        local want = Extract.TERRAIN_KEYS[id]
        if BattleBg.sheetKey(id) ~= want then
          fallbacks[#fallbacks + 1] = string.format("%d(%s->%s)", id, tostring(want),
            tostring(BattleBg.sheetKey(id)))
        end
      end
      local list = (#fallbacks == 0) and "none" or table.concat(fallbacks, ", ")
      print("[info] terrain ids still falling back on this cache: " .. list)
      if (tonumber(m.format) or 0) >= 6 then
        check(#fallbacks == 0, "a format 6 cache bakes every terrain sheet (" .. list .. ")")
      else
        print("[skip] cache format " .. tostring(m.format) .. " predates the terrain bake")
      end
      BattleBg.setAvailableSheets(nil)
    end
  end
end

print("[test] 9. the map battle scene comes off the live map def (overworld.c:1270)")
do
  local BattleBridge = require("src.core.game3.battle_bridge")
  local CacheFs = require("src.import.CacheFs")
  local realReadActive, realRead = CacheFs.readActive, CacheFs.read
  CacheFs.readActive = function() error("mapBattleScene must not read the cache") end
  CacheFs.read = function() error("mapBattleScene must not read the cache") end

  local game = { data = { maps = {
    FR_VIRIDIAN_CITY_GYM = { battleType = SCENE.GYM },
    FR_PALLET_TOWN = { battleType = SCENE.NORMAL },
  } } }
  eq(BattleBridge.mapBattleScene("FR_VIRIDIAN_CITY_GYM", game), SCENE.GYM,
    "a gym map def hands back MAP_BATTLE_SCENE_GYM")
  eq(BattleBridge.mapBattleScene("FR_PALLET_TOWN", game), SCENE.NORMAL,
    "an outdoor map def hands back MAP_BATTLE_SCENE_NORMAL")
  eq(BattleBridge.mapBattleScene("FR_NOT_A_MAP", game), nil,
    "a map with no def has no scene")
  eq(BattleBridge.mapBattleScene(nil, game), nil, "a nil map id has no scene")

  local Runtime = require("src.core.game3.runtime")
  local realGame = Runtime._game
  Runtime._game = game
  eq(BattleBridge.mapBattleScene("FR_VIRIDIAN_CITY_GYM"), SCENE.GYM,
    "with no game argument it reads the running game's maps")
  Runtime._game = realGame

  CacheFs.readActive, CacheFs.read = realReadActive, realRead
end

finish()

-- FRLG battle background / terrain selection (pret battle_setup + battle_bg).
-- One place: map kind / opts → terrain id → baked RGBA. UI and bridge both use this.

local BattleChrome = require("src.ui.game3.battle_chrome")
local Collision = require("src.core.game3.collision")

local BattleBg = {}

-- pret include/constants/battle.h
BattleBg.TERRAIN = {
  GRASS = 0,
  LONG_GRASS = 1,
  SAND = 2,
  UNDERWATER = 3,
  WATER = 4,
  POND = 5,
  MOUNTAIN = 6,
  CAVE = 7,
  BUILDING = 8,
  PLAIN = 9,
  LINK = 10,
  GYM = 11,
  LEADER = 12,
  INDOOR_2 = 13,
  INDOOR_1 = 14,
  LORELEI = 15,
  BRUNO = 16,
  AGATHA = 17,
  LANCE = 18,
  CHAMPION = 19,
}

-- pret include/constants/map_types.h:4
BattleBg.MAP_TYPE = {
  NONE = 0,
  TOWN = 1,
  CITY = 2,
  ROUTE = 3,
  UNDERGROUND = 4,
  UNDERWATER = 5,
  OCEAN_ROUTE = 6,
  UNKNOWN = 7,
  INDOOR = 8,
  SECRET_BASE = 9,
}

-- pret include/constants/map_types.h:15
BattleBg.MAP_BATTLE_SCENE = {
  NORMAL = 0,
  GYM = 1,
  INDOOR_1 = 2,
  INDOOR_2 = 3,
  LORELEI = 4,
  BRUNO = 5,
  AGATHA = 6,
  LANCE = 7,
  LINK = 8,
}

-- pret src/battle_bg.c:602 sMapBattleSceneMapping
local SCENE_TERRAIN = {
  [BattleBg.MAP_BATTLE_SCENE.GYM] = BattleBg.TERRAIN.GYM,
  [BattleBg.MAP_BATTLE_SCENE.INDOOR_1] = BattleBg.TERRAIN.INDOOR_1,
  [BattleBg.MAP_BATTLE_SCENE.INDOOR_2] = BattleBg.TERRAIN.INDOOR_2,
  [BattleBg.MAP_BATTLE_SCENE.LORELEI] = BattleBg.TERRAIN.LORELEI,
  [BattleBg.MAP_BATTLE_SCENE.BRUNO] = BattleBg.TERRAIN.BRUNO,
  [BattleBg.MAP_BATTLE_SCENE.AGATHA] = BattleBg.TERRAIN.AGATHA,
  [BattleBg.MAP_BATTLE_SCENE.LANCE] = BattleBg.TERRAIN.LANCE,
  [BattleBg.MAP_BATTLE_SCENE.LINK] = BattleBg.TERRAIN.LINK,
}

-- pret include/constants/trainers.h:267
local TRAINER_CLASS_LEADER = 84
local TRAINER_CLASS_CHAMPION = 90

-- pret src/battle_bg.c:439 sBattleTerrainTable
local TERRAIN_SHEET = {
  [BattleBg.TERRAIN.GRASS] = "grass",
  [BattleBg.TERRAIN.LONG_GRASS] = "long_grass",
  [BattleBg.TERRAIN.SAND] = "sand",
  [BattleBg.TERRAIN.UNDERWATER] = "underwater",
  [BattleBg.TERRAIN.WATER] = "water",
  [BattleBg.TERRAIN.POND] = "pond",
  [BattleBg.TERRAIN.MOUNTAIN] = "mountain",
  [BattleBg.TERRAIN.CAVE] = "cave",
  [BattleBg.TERRAIN.BUILDING] = "building",
  [BattleBg.TERRAIN.PLAIN] = "plain",
  [BattleBg.TERRAIN.LINK] = "link",
  [BattleBg.TERRAIN.GYM] = "gym",
  [BattleBg.TERRAIN.LEADER] = "leader",
  [BattleBg.TERRAIN.INDOOR_2] = "indoor_2",
  [BattleBg.TERRAIN.INDOOR_1] = "indoor_1",
  [BattleBg.TERRAIN.LORELEI] = "lorelei",
  [BattleBg.TERRAIN.BRUNO] = "bruno",
  [BattleBg.TERRAIN.AGATHA] = "agatha",
  [BattleBg.TERRAIN.LANCE] = "lance",
  [BattleBg.TERRAIN.CHAMPION] = "champion",
}

local SHEET_DEGRADE = {
  [BattleBg.TERRAIN.GRASS] = { "plain" },
  [BattleBg.TERRAIN.LONG_GRASS] = { "grass", "plain" },
  [BattleBg.TERRAIN.SAND] = { "grass", "plain" },
  [BattleBg.TERRAIN.UNDERWATER] = { "water", "pond" },
  [BattleBg.TERRAIN.WATER] = { "pond", "grass" },
  [BattleBg.TERRAIN.POND] = { "water", "grass" },
  [BattleBg.TERRAIN.MOUNTAIN] = { "cave", "plain" },
  [BattleBg.TERRAIN.CAVE] = { "mountain", "plain" },
  [BattleBg.TERRAIN.BUILDING] = { "plain" },
  [BattleBg.TERRAIN.PLAIN] = { "building" },
  [BattleBg.TERRAIN.LINK] = { "building", "plain" },
  [BattleBg.TERRAIN.GYM] = { "building", "plain" },
  [BattleBg.TERRAIN.LEADER] = { "gym", "building" },
  [BattleBg.TERRAIN.INDOOR_2] = { "indoor_1", "building" },
  [BattleBg.TERRAIN.INDOOR_1] = { "indoor_2", "building" },
  [BattleBg.TERRAIN.LORELEI] = { "indoor_1", "indoor_2", "building" },
  [BattleBg.TERRAIN.BRUNO] = { "indoor_1", "indoor_2", "building" },
  [BattleBg.TERRAIN.AGATHA] = { "indoor_1", "indoor_2", "building" },
  [BattleBg.TERRAIN.LANCE] = { "indoor_1", "indoor_2", "building" },
  [BattleBg.TERRAIN.CHAMPION] = { "leader", "indoor_1", "building" },
}

BattleBg._terrainId = BattleBg.TERRAIN.BUILDING
BattleBg._sheets = nil

--- pret BattleSetup_GetTerrainId (simplified): indoor → BUILDING, else grass default outdoors.
function BattleBg.resolveFromMapKind(kind)
  kind = kind or "town"
  if kind == "indoor" or kind == "building" or kind == "secret_base" then
    return BattleBg.TERRAIN.BUILDING
  end
  if kind == "cave" or kind == "underground" then
    return BattleBg.TERRAIN.CAVE
  end
  if kind == "water" or kind == "ocean" then
    return BattleBg.TERRAIN.WATER
  end
  -- Routes / towns / field: tall grass battles use GRASS; default PLAIN→building tiles in pret.
  if kind == "route" or kind == "town" or kind == "city" then
    return BattleBg.TERRAIN.GRASS
  end
  return BattleBg.TERRAIN.BUILDING
end

-- pokefirered/include/constants/metatile_behaviors.h:4
local MB_TALL_GRASS = 0x02
local MB_INDOOR_ENCOUNTER = 0x0B
local MB_MOUNTAIN_TOP = 0x0C
local MB_FAST_WATER = 0x11
local MB_DEEP_WATER = 0x12
local MB_OCEAN_WATER = 0x15
local MB_SHALLOW_WATER = 0x17
local MB_SAND = 0x21
local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1

-- pokefirered/src/metatile_behavior.c:432
local function is_tall_grass(beh)
  return beh == MB_TALL_GRASS or beh == MB_CYCLING_ROAD_PULL_DOWN_GRASS
end

-- pokefirered/src/metatile_behavior.c:80
local function is_sand_or_shallow_flowing_water(beh)
  return beh == MB_SAND or beh == MB_SHALLOW_WATER
end

-- pokefirered/src/metatile_behavior.c:518
local function is_deep_water_terrain(beh)
  return (beh >= MB_FAST_WATER and beh <= MB_DEEP_WATER) or beh == MB_OCEAN_WATER
end

local KIND_MAP_TYPE = {
  town = BattleBg.MAP_TYPE.TOWN,
  city = BattleBg.MAP_TYPE.CITY,
  route = BattleBg.MAP_TYPE.ROUTE,
  cave = BattleBg.MAP_TYPE.UNDERGROUND,
  underground = BattleBg.MAP_TYPE.UNDERGROUND,
  water = BattleBg.MAP_TYPE.OCEAN_ROUTE,
  ocean = BattleBg.MAP_TYPE.OCEAN_ROUTE,
  indoor = BattleBg.MAP_TYPE.INDOOR,
  building = BattleBg.MAP_TYPE.INDOOR,
  secret_base = BattleBg.MAP_TYPE.SECRET_BASE,
}

--- pokefirered/src/battle_setup.c:466 BattleSetup_GetTerrainId
function BattleBg.resolveFromBehavior(behavior, mapKind, mapType)
  local beh = tonumber(behavior)
  if beh == nil then return BattleBg.resolveFromMapKind(mapKind) end
  local T = BattleBg.TERRAIN
  local M = BattleBg.MAP_TYPE
  local mt = tonumber(mapType) or KIND_MAP_TYPE[mapKind or "town"] or M.TOWN
  if is_tall_grass(beh) then return T.GRASS end
  if is_sand_or_shallow_flowing_water(beh) then return T.SAND end
  if mt == M.UNDERGROUND then
    if beh == MB_INDOOR_ENCOUNTER then return T.BUILDING end
    if Collision.isSurfable(beh) then return T.POND end
    return T.CAVE
  elseif mt == M.INDOOR or mt == M.SECRET_BASE then
    return T.BUILDING
  elseif mt == M.UNDERWATER then
    return T.UNDERWATER
  elseif mt == M.OCEAN_ROUTE then
    if Collision.isSurfable(beh) then return T.WATER end
    return T.PLAIN
  end
  if is_deep_water_terrain(beh) then return T.WATER end
  if Collision.isSurfable(beh) then return T.POND end
  if beh == MB_MOUNTAIN_TOP then return T.MOUNTAIN end
  return T.PLAIN
end

--- pokefirered/src/battle_bg.c:1048 GetBattleTerrainOverride
function BattleBg.resolveOverride(terrainId, opts)
  opts = opts or {}
  local T = BattleBg.TERRAIN
  local base = tonumber(terrainId) or T.PLAIN
  if opts.link or opts.trainerTower or opts.battleTower or opts.eReader then
    return T.LINK
  end
  if opts.pokedude then return T.GRASS end
  if opts.trainer then
    local cls = tonumber(opts.trainerClass)
    if cls == TRAINER_CLASS_LEADER then return T.LEADER end
    if cls == TRAINER_CLASS_CHAMPION then return T.CHAMPION end
  end
  local scene = tonumber(opts.mapBattleScene) or BattleBg.MAP_BATTLE_SCENE.NORMAL
  if scene == BattleBg.MAP_BATTLE_SCENE.NORMAL then return base end
  -- pokefirered/src/battle_bg.c:633 GetBattleTerrainByMapScene
  return SCENE_TERRAIN[scene] or T.PLAIN
end

function BattleBg.setTerrain(id)
  BattleBg._terrainId = tonumber(id) or BattleBg.TERRAIN.BUILDING
end

function BattleBg.terrainId()
  return BattleBg._terrainId
end

function BattleBg.availableSheets()
  if BattleBg._sheets then return BattleBg._sheets end
  local loaded = BattleChrome._terrains
  if type(loaded) == "table" and next(loaded) then return loaded end
  local m = BattleChrome._manifest
  local baked = type(m) == "table" and m.terrains
  if type(baked) == "table" and next(baked) then return baked end
  return nil
end

function BattleBg.setAvailableSheets(set)
  BattleBg._sheets = set
end

function BattleBg.sheetKey(id)
  id = tonumber(id) or BattleBg._terrainId
  local primary = TERRAIN_SHEET[id]
  if not primary then return "building" end
  local have = BattleBg.availableSheets()
  if not have then return primary end
  if have[primary] then return primary end
  for _, key in ipairs(SHEET_DEGRADE[id] or {}) do
    if have[key] then return key end
  end
  if have.building then return "building" end
  if have.grass then return "grass" end
  return primary
end

function BattleBg.draw(id, enemyOx, playerOx, bgOx)
  local key = BattleBg.sheetKey(id)
  return BattleChrome.drawTerrain(key, enemyOx, playerOx, bgOx)
end

return BattleBg

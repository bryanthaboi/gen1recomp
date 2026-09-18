-- FRLG battle background / terrain selection (pret battle_setup + battle_bg).
-- One place: map kind / opts → terrain id → baked RGBA. UI and bridge both use this.

local BattleChrome = require("src.ui.game3.battle_chrome")

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
}

-- Which extracted sheet to draw (building tiles + pal covers BUILDING/PLAIN for now).
local TERRAIN_SHEET = {
  [BattleBg.TERRAIN.GRASS] = "grass",
  [BattleBg.TERRAIN.LONG_GRASS] = "grass",
  [BattleBg.TERRAIN.BUILDING] = "building",
  [BattleBg.TERRAIN.PLAIN] = "building",
  [BattleBg.TERRAIN.CAVE] = "building",
}

BattleBg._terrainId = BattleBg.TERRAIN.BUILDING

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

function BattleBg.setTerrain(id)
  BattleBg._terrainId = tonumber(id) or BattleBg.TERRAIN.BUILDING
end

function BattleBg.terrainId()
  return BattleBg._terrainId
end

function BattleBg.sheetKey(id)
  id = id or BattleBg._terrainId
  return TERRAIN_SHEET[id] or "building"
end

function BattleBg.draw(id, enemyOx, playerOx, bgOx)
  local key = BattleBg.sheetKey(id)
  return BattleChrome.drawTerrain(key, enemyOx, playerOx, bgOx)
end

return BattleBg

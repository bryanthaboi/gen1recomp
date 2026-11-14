local Ids = {}

Ids.family = "frlg"

local ID = {
  BLUR = 0,
  SWIRL = 1,
  SHUFFLE = 2,
  BIG_POKEBALL = 3,
  POKEBALLS_TRAIL = 4,
  CLOCKWISE_WIPE = 5,
  RIPPLE = 6,
  WAVE = 7,
  SLICE = 8,
  WHITE_BARS_FADE = 9,
  GRID_SQUARES = 10,
  ANGLED_WIPES = 11,
  LORELEI = 12,
  BRUNO = 13,
  AGATHA = 14,
  LANCE = 15,
  BLUE = 16,
  SPIRAL = 17,
}
Ids.ID = ID

local TERRAIN = {
  NORMAL = 0,
  CAVE = 1,
  FLASH = 2,
  WATER = 3,
}
Ids.TERRAIN = TERRAIN

-- src/battle_setup.c:87
local TABLE_WILD = {
  [TERRAIN.NORMAL] = { ID.SLICE, ID.WHITE_BARS_FADE },
  [TERRAIN.CAVE]   = { ID.CLOCKWISE_WIPE, ID.GRID_SQUARES },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.WAVE, ID.RIPPLE },
}

-- src/battle_setup.c:95
local TABLE_TRAINER = {
  [TERRAIN.NORMAL] = { ID.POKEBALLS_TRAIL, ID.ANGLED_WIPES },
  [TERRAIN.CAVE]   = { ID.SHUFFLE, ID.BIG_POKEBALL },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.SWIRL, ID.RIPPLE },
}

Ids.MUGSHOT_BY_ID = {
  [ID.LORELEI] = "lorelei",
  [ID.BRUNO]   = "bruno",
  [ID.AGATHA]  = "agatha",
  [ID.LANCE]   = "lance",
  [ID.BLUE]    = "blue",
}

-- src/battle_transition.c:1849
Ids.MUGSHOT_PIC = { lorelei = 112, bruno = 113, agatha = 114, lance = 115, blue = 125 }
Ids.MUGSHOT_COORDS = {
  lorelei = { -8, 0 }, bruno = { -10, 0 }, agatha = { 0, 0 }, lance = { -32, 0 }, blue = { 0, 0 },
}
Ids.MUGSHOT_DEFAULT_PIC = 125
Ids.MUGSHOT_PLAYER_PIC = { male = 135, female = 136 }

-- pokefirered/include/constants/map_types.h:8
local MAP_TYPE_UNDERGROUND = 4
local MAP_TYPE_UNDERWATER = 5

-- pokefirered/src/battle_setup.c:517
function Ids.getTerrainByMap(opts)
  opts = opts or {}
  if (tonumber(opts.flashLevel) or 0) > 0 then return TERRAIN.FLASH end
  if opts.mapBehavior ~= nil and require("src.core.game3.collision").isSurfable(opts.mapBehavior) then
    return TERRAIN.WATER
  end
  local mapType = tonumber(opts.mapType)
  if mapType == MAP_TYPE_UNDERGROUND then return TERRAIN.CAVE end
  if mapType == MAP_TYPE_UNDERWATER then return TERRAIN.WATER end
  return TERRAIN.NORMAL
end

function Ids.pickWild(opts)
  opts = opts or {}
  local terrain = opts.terrain or Ids.getTerrainByMap(opts)
  local tableEntry = TABLE_WILD[terrain] or TABLE_WILD[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

-- pokefirered/include/constants/trainers.h:270, :273
local TRAINER_CLASS_ELITE_FOUR = 87
local TRAINER_CLASS_CHAMPION = 90
-- pokefirered/include/constants/opponents.h:416-419, :741-744 (first run, rematch)
local ELITE_FOUR_TRANSITION = {
  [410] = ID.LORELEI, [735] = ID.LORELEI,
  [411] = ID.BRUNO, [736] = ID.BRUNO,
  [412] = ID.AGATHA, [737] = ID.AGATHA,
  [413] = ID.LANCE, [738] = ID.LANCE,
}

-- pokefirered/src/battle_setup.c:624 GetTrainerBattleTransition: the Elite Four
-- and the champion are recognised by class id, never by the class's name.
function Ids.pickTrainer(opts)
  opts = opts or {}
  local tid = tonumber(opts.trainerId) or 0
  -- A Trainer Tower or e-Reader foe carries a facility class, whose numbers
  -- overlap the trainer classes (FACILITY_CLASS_LASS is 90, the champion's,
  -- pokefirered/include/constants/trainers.h:381); pret never picks their
  -- transition by class (battle_setup.c:660).
  local tClass = not (opts.trainerTower or opts.eReader) and tonumber(opts.trainerClass) or nil

  if tClass == TRAINER_CLASS_ELITE_FOUR then
    if opts.isLorelei then return ID.LORELEI end
    if opts.isBruno then return ID.BRUNO end
    if opts.isAgatha then return ID.AGATHA end
    if opts.isLance then return ID.LANCE end
    return ELITE_FOUR_TRANSITION[tid] or ID.BLUE
  end
  if tClass == TRAINER_CLASS_CHAMPION or opts.isRival or opts.isChampion then
    return ID.BLUE
  end
  if opts.isLorelei then return ID.LORELEI end
  if opts.isBruno then return ID.BRUNO end
  if opts.isAgatha then return ID.AGATHA end
  if opts.isLance then return ID.LANCE end
  if opts.isBlue then return ID.BLUE end

  local terrain = opts.terrain or Ids.getTerrainByMap(opts)
  local tableEntry = TABLE_TRAINER[terrain] or TABLE_TRAINER[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

-- pokefirered/src/battle_transition.c:708
Ids.TUNE = {
  introFades = 2,
  blurDelay = 2,
  wipeStepX = 32,
  wipeStepY = 16,
  rippleFadeAt = 41,
  rippleFadeDelay = -8,
}

return Ids

-- Renewable hidden items engine (Treasure Beach, Berry Forest, etc.)
-- pokefirered/src/renewable_hidden_items.c

local Flags = require("src.core.game3.scripting.flags")
local F = Flags.IDS

local RenewableHiddenItems = {}

local VAR_RENEWABLE_ITEM_STEP_COUNTER = 0x4023 -- pokefirered/include/constants/vars.h:40
local STEP_THRESHOLD = 1500

-- Map definitions and item tables matching pokefirered/src/renewable_hidden_items.c
local RENEWABLE_ZONES = {
  {
    name = "ROUTE20",
    group = 3, map = 36,
    mapIds = { "ROUTE_20", "FR_ROUTE_20", "LG_ROUTE_20" },
    rare = {},
    uncommon = { F.FLAG_HIDDEN_ITEM_ROUTE20_STARDUST },
    common = {},
  },
  {
    name = "ROUTE21_NORTH",
    group = 3, map = 37,
    mapIds = { "ROUTE_21_NORTH", "FR_ROUTE_21_NORTH", "LG_ROUTE_21_NORTH", "ROUTE_21" },
    rare = {},
    uncommon = { F.FLAG_HIDDEN_ITEM_ROUTE21_NORTH_PEARL },
    common = {},
  },
  {
    name = "UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL",
    group = 1, map = 31,
    mapIds = { "UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL", "FR_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL" },
    rare = { F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_ETHER },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_POTION,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_ANTIDOTE,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_PARALYZE_HEAL,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_AWAKENING,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_BURN_HEAL,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL_ICE_HEAL,
    },
    common = {},
  },
  {
    name = "UNDERGROUND_PATH_EAST_WEST_TUNNEL",
    group = 1, map = 34,
    mapIds = { "UNDERGROUND_PATH_EAST_WEST_TUNNEL", "FR_UNDERGROUND_PATH_EAST_WEST_TUNNEL" },
    rare = { F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_ETHER },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_POTION,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_ANTIDOTE,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_PARALYZE_HEAL,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_AWAKENING,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_BURN_HEAL,
      F.FLAG_HIDDEN_ITEM_UNDERGROUND_PATH_EAST_WEST_TUNNEL_ICE_HEAL,
    },
    common = {},
  },
  {
    name = "SEVEN_ISLAND_TANOBY_RUINS",
    group = 3, map = 45,
    mapIds = { "SEVII_SEVEN_ISLAND_TANOBY_RUINS", "SEVEN_ISLAND_TANOBY_RUINS", "FR_SEVEN_ISLAND_TANOBY_RUINS" },
    rare = {
      F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TANOBY_RUINS_HEART_SCALE_4,
      F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TANOBY_RUINS_HEART_SCALE,
      F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TANOBY_RUINS_HEART_SCALE_2,
      F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TANOBY_RUINS_HEART_SCALE_3,
    },
    uncommon = {},
    common = {},
  },
  {
    name = "MT_MOON_B1F",
    group = 1, map = 2,
    mapIds = { "MT_MOON_B1F", "FR_MT_MOON_B1F" },
    rare = {
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM_2,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM_3,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_BIG_MUSHROOM,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_BIG_MUSHROOM_2,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_BIG_MUSHROOM_3,
    },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM_2,
      F.FLAG_HIDDEN_ITEM_MT_MOON_B1F_TINY_MUSHROOM_3,
    },
    common = {},
  },
  {
    name = "THREE_ISLAND_BERRY_FOREST",
    group = 1, map = 109,
    mapIds = { "SEVII_THREE_ISLAND_BERRY_FOREST", "THREE_ISLAND_BERRY_FOREST", "FR_THREE_ISLAND_BERRY_FOREST" },
    rare = {
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_BLUK_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_WEPEAR_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_ORAN_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_CHERI_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_ASPEAR_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_PERSIM_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_PINAP_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_LUM_BERRY,
    },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_BLUK_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_WEPEAR_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_ORAN_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_CHERI_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_ASPEAR_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_PERSIM_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_PINAP_BERRY,
    },
    common = {
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_RAZZ_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_NANAB_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_CHESTO_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_PECHA_BERRY,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BERRY_FOREST_RAWST_BERRY,
    },
  },
  {
    name = "ONE_ISLAND_TREASURE_BEACH",
    group = 3, map = 46,
    mapIds = { "SEVII_ONE_ISLAND_TREASURE_BEACH", "ONE_ISLAND_TREASURE_BEACH", "FR_ONE_ISLAND_TREASURE_BEACH" },
    rare = {
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL_2,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_STAR_PIECE,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_BIG_PEARL,
    },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_STARDUST,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_STARDUST_2,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_PEARL,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_PEARL_2,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL_2,
    },
    common = {
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL,
      F.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL_2,
    },
  },
  {
    name = "THREE_ISLAND_BOND_BRIDGE",
    group = 3, map = 48,
    mapIds = { "SEVII_THREE_ISLAND_BOND_BRIDGE", "THREE_ISLAND_BOND_BRIDGE", "FR_THREE_ISLAND_BOND_BRIDGE" },
    rare = {},
    uncommon = {
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BOND_BRIDGE_PEARL,
      F.FLAG_HIDDEN_ITEM_THREE_ISLAND_BOND_BRIDGE_STARDUST,
    },
    common = {},
  },
  {
    name = "FOUR_ISLAND",
    group = 3, map = 5,
    mapIds = { "SEVII_FOUR_ISLAND", "FOUR_ISLAND", "FR_FOUR_ISLAND" },
    rare = {},
    uncommon = { F.FLAG_HIDDEN_ITEM_FOUR_ISLAND_PEARL },
    common = { F.FLAG_HIDDEN_ITEM_FOUR_ISLAND_ULTRA_BALL },
  },
  {
    name = "FIVE_ISLAND_MEMORIAL_PILLAR",
    group = 3, map = 51,
    mapIds = { "SEVII_FIVE_ISLAND_MEMORIAL_PILLAR", "FIVE_ISLAND_MEMORIAL_PILLAR", "FR_FIVE_ISLAND_MEMORIAL_PILLAR" },
    rare = { F.FLAG_HIDDEN_ITEM_FIVE_ISLAND_MEMORIAL_PILLAR_BIG_PEARL },
    uncommon = {},
    common = {},
  },
  {
    name = "FIVE_ISLAND_RESORT_GORGEOUS",
    group = 3, map = 52,
    mapIds = { "SEVII_FIVE_ISLAND_RESORT_GORGEOUS", "FIVE_ISLAND_RESORT_GORGEOUS", "FR_FIVE_ISLAND_RESORT_GORGEOUS" },
    rare = {
      F.FLAG_HIDDEN_ITEM_FIVE_ISLAND_RESORT_GORGEOUS_NEST_BALL,
      F.FLAG_HIDDEN_ITEM_FIVE_ISLAND_RESORT_GORGEOUS_STAR_PIECE,
    },
    uncommon = {
      F.FLAG_HIDDEN_ITEM_FIVE_ISLAND_RESORT_GORGEOUS_STARDUST,
      F.FLAG_HIDDEN_ITEM_FIVE_ISLAND_RESORT_GORGEOUS_STARDUST_2,
    },
    common = {},
  },
  {
    name = "SIX_ISLAND_OUTCAST_ISLAND",
    group = 3, map = 53,
    mapIds = { "SEVII_SIX_ISLAND_OUTCAST_ISLAND", "SIX_ISLAND_OUTCAST_ISLAND", "FR_SIX_ISLAND_OUTCAST_ISLAND" },
    rare = {
      F.FLAG_HIDDEN_ITEM_SIX_ISLAND_OUTCAST_ISLAND_STAR_PIECE,
      F.FLAG_HIDDEN_ITEM_SIX_ISLAND_OUTCAST_ISLAND_NET_BALL,
    },
    uncommon = {},
    common = {},
  },
  {
    name = "SIX_ISLAND_GREEN_PATH",
    group = 3, map = 54,
    mapIds = { "SEVII_SIX_ISLAND_GREEN_PATH", "SIX_ISLAND_GREEN_PATH", "FR_SIX_ISLAND_GREEN_PATH" },
    rare = {},
    uncommon = {},
    common = { F.FLAG_HIDDEN_ITEM_SIX_ISLAND_GREEN_PATH_ULTRA_BALL },
  },
  {
    name = "SEVEN_ISLAND_TRAINER_TOWER",
    group = 3, map = 56,
    mapIds = { "SEVII_SEVEN_ISLAND_TRAINER_TOWER", "SEVEN_ISLAND_TRAINER_TOWER", "FR_SEVEN_ISLAND_TRAINER_TOWER" },
    rare = { F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TRAINER_TOWER_BIG_PEARL },
    uncommon = { F.FLAG_HIDDEN_ITEM_SEVEN_ISLAND_TRAINER_TOWER_PEARL },
    common = {},
  },
}

RenewableHiddenItems.ZONES = RENEWABLE_ZONES

local function resolveStore(ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then return Space.store end
  local rt = package.loaded["src.core.game3.runtime"]
  local session = rt and rt.getSession and rt.getSession()
  if session and session.store then return session.store end
  if type(ctx) == "table" then
    if ctx.vars or ctx.flags then return ctx end
    if ctx.store then return ctx.store end
  end
  return nil
end

function RenewableHiddenItems.isRenewableMap(mapGroup, mapNum, mapId)
  mapGroup = tonumber(mapGroup)
  mapNum = tonumber(mapNum)
  for _, zone in ipairs(RENEWABLE_ZONES) do
    if mapGroup and mapNum and zone.group == mapGroup and zone.map == mapNum then
      return true, zone
    end
    if mapId then
      for _, mid in ipairs(zone.mapIds) do
        if mid == mapId then return true, zone end
      end
    end
  end
  return false, nil
end

--- pokefirered/src/renewable_hidden_items.c:557
function RenewableHiddenItems.onStep(ctx, mapGroup, mapNum, mapId)
  -- Requirement 1: If player is inside one of the renewable item maps, do NOT increment
  if RenewableHiddenItems.isRenewableMap(mapGroup, mapNum, mapId) then
    return false
  end

  local store = resolveStore(ctx)
  local var = tonumber(Flags.getVar(store, ctx, VAR_RENEWABLE_ITEM_STEP_COUNTER)) or 0
  if var < STEP_THRESHOLD then
    Flags.setVar(store, ctx, VAR_RENEWABLE_ITEM_STEP_COUNTER, var + 1)
  end
  return true
end

--- pokefirered/src/renewable_hidden_items.c:536
local function setAllRenewableFlags(ctx)
  local store = resolveStore(ctx)
  for _, zone in ipairs(RENEWABLE_ZONES) do
    for _, flagId in ipairs(zone.rare) do
      if flagId then Flags.setFlag(store, ctx, flagId, true) end
    end
    for _, flagId in ipairs(zone.uncommon) do
      if flagId then Flags.setFlag(store, ctx, flagId, true) end
    end
    for _, flagId in ipairs(zone.common) do
      if flagId then Flags.setFlag(store, ctx, flagId, true) end
    end
  end
end

--- pokefirered/src/renewable_hidden_items.c:587
local function sampleRenewableFlags(ctx, rngFn)
  local store = resolveStore(ctx)
  local rand = rngFn or function() return math.random(0, 99) end

  for _, zone in ipairs(RENEWABLE_ZONES) do
    local rval = rand() % 100
    local flags
    if rval >= 90 then
      flags = zone.rare
    elseif rval >= 60 then
      flags = zone.uncommon
    else
      flags = zone.common
    end

    for _, flagId in ipairs(flags) do
      if flagId then
        -- FlagClear makes the item exist/spawn on the map
        Flags.setFlag(store, ctx, flagId, false)
      end
    end
  end
end

--- pokefirered/src/renewable_hidden_items.c:566
function RenewableHiddenItems.tryRegenerate(ctx, mapGroup, mapNum, mapId, rngFn)
  local isRenewable, zone = RenewableHiddenItems.isRenewableMap(mapGroup, mapNum, mapId)
  if not isRenewable then return false end

  local store = resolveStore(ctx)
  local var = tonumber(Flags.getVar(store, ctx, VAR_RENEWABLE_ITEM_STEP_COUNTER)) or 0
  if var >= STEP_THRESHOLD then
    Flags.setVar(store, ctx, VAR_RENEWABLE_ITEM_STEP_COUNTER, 0)
    setAllRenewableFlags(ctx)
    sampleRenewableFlags(ctx, rngFn)
    return true
  end
  return false
end

return RenewableHiddenItems

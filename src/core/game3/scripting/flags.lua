-- Sevii / FRLG flag and variable store: persist narrative and story flags;
-- never persist specialVars 0x8000–0x8014.

local Ctx = require("src.core.game3.scripting.ctx")
local FlagsTable = require("src.core.game3.scripting.flags_table")
local ModRuntime = require("src.mods.Runtime")

local Flags = {}

-- Table-driven flag definitions with backwards-compatible aliases
Flags.IDS = {}
Flags.NAMES = FlagsTable.FLAGS_BY_ID or {}

for k, v in pairs(FlagsTable.FLAGS or {}) do
  Flags.IDS[k] = v
  if k:find("^FLAG_") then
    local stripped = k:sub(6)
    if not Flags.IDS[stripped] then
      Flags.IDS[stripped] = v
    end
  end
end

-- Table-driven var definitions with backwards-compatible aliases
Flags.VAR_IDS = {}
Flags.VAR_NAMES = FlagsTable.VARS_BY_ID or {}

for k, v in pairs(FlagsTable.VARS or {}) do
  Flags.VAR_IDS[k] = v
  if not Flags.IDS[k] then
    Flags.IDS[k] = v
  end
  if k:find("^VAR_") then
    local stripped = k:sub(5)
    if not Flags.VAR_IDS[stripped] then
      Flags.VAR_IDS[stripped] = v
    end
    if not Flags.IDS[stripped] then
      Flags.IDS[stripped] = v
    end
  end
end

-- pret TRAINER_FLAGS_START (FLAG_0x4FF + 1). Trainer N → flag 0x500 + N.
Flags.TRAINER_FLAGS_START = Flags.IDS.TRAINER_FLAGS_START or 0x500
Flags.TRAINER_FLAGS_END = Flags.IDS.TRAINER_FLAGS_END or 0x7FF

function Flags.trainerFlagId(trainerId)
  return Flags.TRAINER_FLAGS_START + (tonumber(trainerId) or 0)
end

function Flags.isTrainerDefeated(store, session, trainerId)
  local tId = trainerId or session
  local fid = Flags.trainerFlagId(tId)
  return Flags.getFlag(store, nil, fid)
end

function Flags.setTrainerDefeated(store, session, trainerId, on)
  local tId = trainerId
  local val = on
  if on == nil and type(session) == "number" then
    tId = session
    val = trainerId
  end
  local fid = Flags.trainerFlagId(tId)
  Flags.setFlag(store, nil, fid, val ~= false)
end

-- pret EventScript_ResetAllMapFlags (derived from event_scripts.s).
Flags.NEW_GAME_HIDE_FLAGS = FlagsTable.NEW_GAME_HIDE_FLAGS or {
  43, 44, 51, 146, 53, 54, 55, 60, 61, 161, 63, 79, 90, 163, 164, 98, 107, 162,
  140, 108, 109, 110, 111, 117, 116, 123, 124, 125, 118, 145, 151, 144, 148,
  149, 150, 153, 165, 166, 167, 168, 169, 170, 171, 172, 157, 158, 159, 160, 174,
}

Flags.NEW_GAME_RESET_VARS = FlagsTable.NEW_GAME_RESET_VARS or {}

-- Badge definitions
Flags.BADGES = FlagsTable.BADGES or {
  { num = 1, flag = 0x820, name = "BOULDER", gym = "PEWTER", fieldMove = "FLASH" },
  { num = 2, flag = 0x821, name = "CASCADE", gym = "CERULEAN", fieldMove = "CUT" },
  { num = 3, flag = 0x822, name = "THUNDER", gym = "VERMILION", fieldMove = "FLY" },
  { num = 4, flag = 0x823, name = "RAINBOW", gym = "CELADON", fieldMove = "STRENGTH" },
  { num = 5, flag = 0x824, name = "SOUL", gym = "FUCHSIA", fieldMove = "SURF" },
  { num = 6, flag = 0x825, name = "MARSH", gym = "SAFFRON", fieldMove = "ROCK_SMASH" },
  { num = 7, flag = 0x826, name = "VOLCANO", gym = "CINNABAR", fieldMove = "WATERFALL" },
  { num = 8, flag = 0x827, name = "EARTH", gym = "VIRIDIAN", fieldMove = "DIVE" },
}

local BADGE_LOOKUP = {}
for _, b in ipairs(Flags.BADGES) do
  BADGE_LOOKUP[b.num] = b
  BADGE_LOOKUP[b.name] = b
  BADGE_LOOKUP[b.name:lower()] = b
  BADGE_LOOKUP[b.name .. "BADGE"] = b
  BADGE_LOOKUP[(b.name .. "BADGE"):lower()] = b
  BADGE_LOOKUP[b.name .. "_BADGE"] = b
  BADGE_LOOKUP[(b.name .. "_BADGE"):lower()] = b
  BADGE_LOOKUP[b.fieldMove] = b
  BADGE_LOOKUP[b.fieldMove:lower()] = b
  BADGE_LOOKUP[b.flag] = b
  BADGE_LOOKUP[tostring(b.flag)] = b
  BADGE_LOOKUP[string.format("FLAG_BADGE0%d_GET", b.num)] = b
end

function Flags.badgeInfo(badgeKey)
  return BADGE_LOOKUP[badgeKey] or (type(badgeKey) == "number" and BADGE_LOOKUP[badgeKey])
end

--- Check if badge is obtained
function Flags.hasBadge(store, badgeKey)
  local info = Flags.badgeInfo(badgeKey)
  if not info then return false end
  return Flags.getFlag(store, nil, info.flag)
end

--- Set or clear a badge
function Flags.setBadge(store, badgeKey, on)
  local info = Flags.badgeInfo(badgeKey)
  if not info then return end
  Flags.setFlag(store, nil, info.flag, on ~= false)
end

--- Count total badges obtained (0..8)
function Flags.countBadges(store)
  local n = 0
  for _, b in ipairs(Flags.BADGES) do
    if Flags.getFlag(store, nil, b.flag) then
      n = n + 1
    end
  end
  return n
end

--- Get badges bitmask (bit 0 = badge 1, ..., bit 7 = badge 8)
function Flags.getBadgesMask(store)
  local mask = 0
  for _, b in ipairs(Flags.BADGES) do
    if Flags.getFlag(store, nil, b.flag) then
      local bitVal = bit and bit.lshift(1, b.num - 1) or math.pow(2, b.num - 1)
      mask = mask + bitVal
    end
  end
  return mask
end

--- Set badges from bitmask
function Flags.setBadgesMask(store, mask)
  mask = tonumber(mask) or 0
  for _, b in ipairs(Flags.BADGES) do
    local bitVal = bit and bit.lshift(1, b.num - 1) or math.pow(2, b.num - 1)
    local has = (bit and bit.band(mask, bitVal) ~= 0) or (math.floor(mask / bitVal) % 2 == 1)
    Flags.setFlag(store, nil, b.flag, has)
  end
end

function Flags.nameFor(flagId)
  flagId = tonumber(flagId) or 0
  return Flags.NAMES[flagId] or string.format("FLAG_0x%03X", flagId)
end

function Flags.varNameFor(varId)
  varId = tonumber(varId) or 0
  return Flags.VAR_NAMES[varId] or string.format("VAR_0x%04X", varId)
end

function Flags.applyNewGameHideFlags(store)
  if not store then return end
  store.flags = store.flags or {}
  for _, id in ipairs(Flags.NEW_GAME_HIDE_FLAGS) do
    store.flags[id] = true
  end
  store.vars = store.vars or {}
  for _, sv in ipairs(Flags.NEW_GAME_RESET_VARS) do
    store.vars[sv.id] = sv.value
  end
end

--- Sessions started before hide-flag seeding: hide town Oak until the
-- leave-town scene has run (VAR_MAP_SCENE_PALLET_TOWN_OAK ~= 0).
-- Do not force-hide lab Oak (43) — clearflag during the lead warp must stick.
function Flags.ensurePalletOakHidden(store)
  if not store then return end
  local sceneVar = Flags.VAR_IDS.MAP_SCENE_PALLET_TOWN_OAK or 0x4050
  local scene = Flags.getVar(store, nil, sceneVar)
  if scene ~= 0 then return end
  local hidePalletOak = Flags.IDS.HIDE_OAK_IN_PALLET_TOWN or 0x02C
  if not Flags.getFlag(store, nil, hidePalletOak) then
    Flags.setFlag(store, nil, hidePalletOak, true)
  end
end

function Flags.newStore(seed)
  local store = {
    flags = {},
    vars = {},
  }
  -- First Sevii boot: Bill street intro onFrame wants MAP_SCENE == 2.
  -- Extracted scripts advance this (e.g. to 3 after door warp).
  local seviiScene = Flags.VAR_IDS.MAP_SCENE_ONE_ISLAND_HARBOR or 0x4075
  store.vars[seviiScene] = 2
  return store
end

function Flags.loadInto(store, saved)
  if not saved then return store end
  for k, v in pairs(saved.flags or {}) do
    store.flags[tonumber(k) or k] = v and true or false
  end
  for k, v in pairs(saved.vars or {}) do
    local id = tonumber(k) or k
    if not Ctx.isSpecial(id) then
      store.vars[id] = tonumber(v) or 0
    end
  end
  return store
end

--- Snapshot for Sevii sidecar — excludes special vars.
function Flags.serialize(store)
  local flags, vars = {}, {}
  for id, v in pairs(store.flags or {}) do
    if v then flags[tostring(id)] = true end
  end
  for id, v in pairs(store.vars or {}) do
    if not Ctx.isSpecial(id) then
      vars[tostring(id)] = tonumber(v) or 0
    end
  end
  return { flags = flags, vars = vars }
end

function Flags.getFlag(store, ctx, id)
  id = tonumber(id) or (type(id) == "string" and Flags.IDS[id]) or 0
  if not store or not store.flags then return false end
  if store.flags[id] == true or store.flags[tostring(id)] == true then
    return true
  end
  if type(id) == "number" and id > 0 then
    local hexKey = string.format("0x%X", id)
    if store.flags[hexKey] == true then return true end
    local name = Flags.NAMES[id]
    if name and store.flags[name] == true then return true end
  end
  return false
end

function Flags.setFlag(store, ctx, id, on)
  id = tonumber(id) or (type(id) == "string" and Flags.IDS[id]) or 0
  if not store or not store.flags then return end
  local announce = ModRuntime.wants("flag.changed")
    and Flags.getFlag(store, ctx, id) ~= (on and true or false)
  local strId = tostring(id)
  if on then
    store.flags[id] = true
    store.flags[strId] = true
  else
    store.flags[id] = nil
    store.flags[strId] = nil
    if type(id) == "number" and id > 0 then
      local hexKey = string.format("0x%X", id)
      store.flags[hexKey] = nil
      local name = Flags.NAMES[id]
      if name then store.flags[name] = nil end
    end
  end
  if announce then
    ModRuntime.emit("flag.changed", { name = Flags.NAMES[id] or id, id = id, value = on and true or false })
  end
end

function Flags.getVar(store, ctx, id)
  id = tonumber(id) or (type(id) == "string" and Flags.VAR_IDS[id]) or 0
  if Ctx.isSpecial(id) then
    if not (ctx and ctx.specialVars) then return 0 end
    return (ctx.specialVars[id]) or 0
  end
  if not (store and store.vars) then return 0 end
  return (store.vars[id]) or 0
end

function Flags.setVar(store, ctx, id, value)
  id = tonumber(id) or (type(id) == "string" and Flags.VAR_IDS[id]) or 0
  value = tonumber(value) or 0
  if Ctx.isSpecial(id) then
    if not (ctx and ctx.specialVars) then return end
    ctx.specialVars[id] = value % 65536
  else
    if not (store and store.vars) then return end
    store.vars[id] = value % 65536
  end
end

function Flags.onMapLoad(store)
  if store and store.vars then
    Ctx.clearTemps(store.vars)
  end
  -- pret: Temp flags 0x01..0x1F are cleared on map load
  if store and store.flags then
    for fid = 0x01, 0x1F do
      Flags.setFlag(store, nil, fid, false)
    end
  end
end

return Flags

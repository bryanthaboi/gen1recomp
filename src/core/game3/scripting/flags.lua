-- Sevii / FRLG flag and variable store: persist narrative and story flags;
-- never persist specialVars 0x8000–0x8014.

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

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
Flags.NEW_GAME_HIDE_FLAGS = FlagsTable.NEW_GAME_HIDE_FLAGS

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

local function buildBadgeLookup(badges)
  local BADGE_LOOKUP = {}
  for _, b in ipairs(badges) do
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
  return BADGE_LOOKUP
end

local BADGE_LOOKUP = buildBadgeLookup(Flags.BADGES)
local badgeLookups = {}

local function activeBadges()
  local game = lazyReq("src.core.game3.profile").forSession(nil).id
  local t = Flags.forVersion(game)
  if t.BADGES == Flags.BADGES then return Flags.BADGES, BADGE_LOOKUP end
  local lookup = badgeLookups[t.game]
  if not lookup then
    lookup = buildBadgeLookup(t.BADGES)
    badgeLookups[t.game] = lookup
  end
  return t.BADGES, lookup
end

function Flags.badgeInfo(badgeKey)
  local _, lookup = activeBadges()
  return lookup[badgeKey] or (type(badgeKey) == "number" and lookup[badgeKey])
end

-- pokeemerald/src/party_menu.c:120
local EM_BADGES = {
  { num = 1, name = "STONE", gym = "RUSTBORO", fieldMove = "CUT" },
  { num = 2, name = "KNUCKLE", gym = "DEWFORD", fieldMove = "FLASH" },
  { num = 3, name = "DYNAMO", gym = "MAUVILLE", fieldMove = "ROCK_SMASH" },
  { num = 4, name = "HEAT", gym = "LAVARIDGE", fieldMove = "STRENGTH" },
  { num = 5, name = "BALANCE", gym = "PETALBURG", fieldMove = "SURF" },
  { num = 6, name = "FEATHER", gym = "FORTREE", fieldMove = "FLY" },
  { num = 7, name = "MIND", gym = "MOSSDEEP", fieldMove = "DIVE" },
  { num = 8, name = "RAIN", gym = "SOOTOPOLIS", fieldMove = "WATERFALL" },
}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function buildGenerated(game)
  local C = lazyReq("src.core.game3.constants").of(game)
  local flags, vars = C.flags, C.vars
  local ids, varIds = {}, {}
  local fkeys, vkeys = sortedKeys(flags.byName), sortedKeys(vars.byName)
  for _, k in ipairs(fkeys) do ids[k] = flags.byName[k] end
  for _, k in ipairs(vkeys) do
    varIds[k] = vars.byName[k]
    if ids[k] == nil then ids[k] = vars.byName[k] end
  end
  for _, k in ipairs(fkeys) do
    if k:find("^FLAG_") and ids[k:sub(6)] == nil then ids[k:sub(6)] = flags.byName[k] end
  end
  for _, k in ipairs(vkeys) do
    if k:find("^VAR_") then
      local s = k:sub(5)
      if varIds[s] == nil then varIds[s] = vars.byName[k] end
      if ids[s] == nil then ids[s] = vars.byName[k] end
    end
  end
  local badges = {}
  for i, b in ipairs(EM_BADGES) do
    badges[i] = {
      num = b.num, name = b.name, gym = b.gym, fieldMove = b.fieldMove,
      flag = flags.byName[string.format("FLAG_BADGE0%d_GET", b.num)],
    }
  end
  return {
    game = game,
    IDS = ids,
    VAR_IDS = varIds,
    NAMES = flags.byId.FLAG_ or {},
    VAR_NAMES = vars.byId.VAR_ or {},
    BADGES = badges,
    TRAINER_FLAGS_START = ids.TRAINER_FLAGS_START,
    TRAINER_FLAGS_END = ids.TRAINER_FLAGS_END,
    FLAGS_COUNT = ids.FLAGS_COUNT,
  }
end

local versionTables = {}

function Flags.forVersion(id)
  local game = lazyReq("src.core.game3.constants").gameKey(id)
  local t = versionTables[game]
  if t then return t end
  if game == "firered" then
    t = {
      game = game,
      IDS = Flags.IDS,
      VAR_IDS = Flags.VAR_IDS,
      NAMES = Flags.NAMES,
      VAR_NAMES = Flags.VAR_NAMES,
      BADGES = Flags.BADGES,
      TRAINER_FLAGS_START = Flags.TRAINER_FLAGS_START,
      TRAINER_FLAGS_END = Flags.TRAINER_FLAGS_END,
      FLAGS_COUNT = Flags.IDS.FLAGS_COUNT,
    }
  else
    t = buildGenerated(game)
  end
  versionTables[game] = t
  return t
end

function Flags.active(session)
  return Flags.forVersion(lazyReq("src.core.game3.constants").versionOf(session))
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
  for _, b in ipairs((activeBadges())) do
    if Flags.getFlag(store, nil, b.flag) then
      n = n + 1
    end
  end
  return n
end

--- Get badges bitmask (bit 0 = badge 1, ..., bit 7 = badge 8)
function Flags.getBadgesMask(store)
  local mask = 0
  for _, b in ipairs((activeBadges())) do
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
  for _, b in ipairs((activeBadges())) do
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
  if lazyReq("src.core.game3.profile").family() ~= "frlg" then return end
  local sceneVar = Flags.VAR_IDS.MAP_SCENE_PALLET_TOWN_OAK or 0x4050
  local scene = Flags.getVar(store, nil, sceneVar)
  if scene ~= 0 then return end
  local hidePalletOak = Flags.IDS.HIDE_OAK_IN_PALLET_TOWN or 0x02C
  if not Flags.getFlag(store, nil, hidePalletOak) then
    Flags.setFlag(store, nil, hidePalletOak, true)
  end
end

--- Repair/normalize legacy saves that missed initial hide flags.
function Flags.repairSaveState(store)
  if not store then return end
  Flags.ensurePalletOakHidden(store)

  -- Bill human in sea cottage: if helped flag (0x233) is false, human is hidden (0x033)
  if not Flags.getFlag(store, nil, 0x233) then
    Flags.setFlag(store, nil, 0x033, true)
  end

  -- Running shoes guy in Pewter: if badge 1 (0x820) is false, guy is hidden (0x092)
  if not Flags.getFlag(store, nil, 0x820) then
    Flags.setFlag(store, nil, 0x092, true)
  end

  -- Fuji in Lavender house: if rescued (0x23C) is false, Fuji in house is hidden (0x035)
  if not Flags.getFlag(store, nil, 0x23C) then
    Flags.setFlag(store, nil, 0x035, true)
  end

  -- Oak in champ room: if champion defeated (0x4BC) is false, oak in champ room is hidden (0x05A)
  if not Flags.getFlag(store, nil, 0x4BC) then
    Flags.setFlag(store, nil, 0x05A, true)
  end
end

local function repairForGame(store)
  local path = lazyReq("src.core.game3.profile").forSession(store).saveRules
  local rules = type(path) == "string" and require(path) or nil
  if rules and rules.repairSaveState then rules.repairSaveState(store) end
end

function Flags.newStore()
  return { flags = {}, vars = {} }
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
  repairForGame(store)
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
  -- src/event_data.c:235-241
  if id < 0x4000 then return id end
  if not (store and store.vars) then return 0 end
  return store.vars[id] or store.vars[tostring(id)] or 0
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
    store.vars[tostring(id)] = nil
  end
end

function Flags.onMapLoad(store, keepTemps)
  -- pokeruby/src/overworld.c:1479
  if keepTemps then
    repairForGame(store)
    return
  end
  if store and store.vars then
    Ctx.clearTemps(store.vars)
  end
  -- pret: Temp flags 0x01..0x1F are cleared on map load
  if store and store.flags then
    for fid = 0x01, 0x1F do
      Flags.setFlag(store, nil, fid, false)
    end
  end
  repairForGame(store)
end

return Flags

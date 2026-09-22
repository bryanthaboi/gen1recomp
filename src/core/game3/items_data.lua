-- FRLG item metadata loaded from extracted pack (pret items.json).
-- Falls back to minimal hardcoded rows when pack is missing.

local Strings = require("src.core.Strings")
local ItemsData = {}

ItemsData.POCKET = {
  ITEMS = "ITEMS",
  KEY_ITEMS = "KEY_ITEMS",
  POKE_BALLS = "POKE_BALLS",
  TM_CASE = "TM_CASE",
  BERRY_POUCH = "BERRY_POUCH",
}

ItemsData.POCKET_ORDER = {
  "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH",
}

-- Visible pockets in the main Bag UI (pret BAG_POCKETS_COUNT = 3).
-- TM Case and Berry Pouch are sub-containers accessed via Key Items.
ItemsData.BAG_POCKET_ORDER = {
  "ITEMS", "KEY_ITEMS", "POKE_BALLS",
}

-- English sources; callers translate with Strings() when they draw them.
ItemsData.POCKET_LABEL = {
  ITEMS = Strings.source("ITEMS"),
  KEY_ITEMS = Strings.source("KEY ITEMS"),
  POKE_BALLS = Strings.source("POKé BALLS"),
  TM_CASE = Strings.source("TM CASE"),
  BERRY_POUCH = Strings.source("BERRY POUCH"),
}

-- pret GetPocketByItemId returns 1..5
ItemsData.POCKET_RESULT = {
  ITEMS = 1,
  KEY_ITEMS = 2,
  POKE_BALLS = 3,
  TM_CASE = 4,
  BERRY_POUCH = 5,
}

ItemsData.CAPACITY = {
  ITEMS = 42,
  KEY_ITEMS = 30,
  POKE_BALLS = 13,
  TM_CASE = 58,
  BERRY_POUCH = 43,
}

-- pokefirered/include/constants/items.h:272
ItemsData.ITEM_ITEMFINDER = 261
ItemsData.ITEM_TM_CASE = 364
ItemsData.ITEM_BERRY_POUCH = 365
-- pokefirered/include/constants/items.h:434
ItemsData.ITEM_VS_SEEKER = 362
ItemsData.FIRST_TM = 289
ItemsData.LAST_TM = 338
ItemsData.FIRST_HM = 339
ItemsData.LAST_HM = 346

ItemsData._pack = nil
ItemsData._byId = nil
ItemsData._logged = false

-- Host string id → display / pocket (Sevii ferry).
ItemsData.BY_HOST = {
  MASTER_BALL = { name = "MASTER BALL", pocket = "POKE_BALLS", fieldUse = "battle", frlg = 1 },
  ULTRA_BALL = { name = "ULTRA BALL", pocket = "POKE_BALLS", fieldUse = "battle", frlg = 2 },
  GREAT_BALL = { name = "GREAT BALL", pocket = "POKE_BALLS", fieldUse = "battle", frlg = 3 },
  POKE_BALL = { name = "POKé BALL", pocket = "POKE_BALLS", fieldUse = "battle", frlg = 4 },
  POTION = { name = "POTION", pocket = "ITEMS", fieldUse = "heal", frlg = 13 },
  ANTIDOTE = { name = "ANTIDOTE", pocket = "ITEMS", fieldUse = "status", frlg = 14 },
  BURN_HEAL = { name = "BURN HEAL", pocket = "ITEMS", fieldUse = "status", frlg = 15 },
  ICE_HEAL = { name = "ICE HEAL", pocket = "ITEMS", fieldUse = "status", frlg = 16 },
  AWAKENING = { name = "AWAKENING", pocket = "ITEMS", fieldUse = "status", frlg = 17 },
  PARLYZ_HEAL = { name = "PARLYZ HEAL", pocket = "ITEMS", fieldUse = "status", frlg = 18 },
  FULL_RESTORE = { name = "FULL RESTORE", pocket = "ITEMS", fieldUse = "heal", frlg = 19 },
  MAX_POTION = { name = "MAX POTION", pocket = "ITEMS", fieldUse = "heal", frlg = 20 },
  HYPER_POTION = { name = "HYPER POTION", pocket = "ITEMS", fieldUse = "heal", frlg = 21 },
  SUPER_POTION = { name = "SUPER POTION", pocket = "ITEMS", fieldUse = "heal", frlg = 22 },
  FULL_HEAL = { name = "FULL HEAL", pocket = "ITEMS", fieldUse = "status", frlg = 23 },
  REVIVE = { name = "REVIVE", pocket = "ITEMS", fieldUse = "revive", frlg = 24 },
  MAX_REVIVE = { name = "MAX REVIVE", pocket = "ITEMS", fieldUse = "revive", frlg = 25 },
  FRESH_WATER = { name = "FRESH WATER", pocket = "ITEMS", fieldUse = "heal", frlg = 26 },
  SODA_POP = { name = "SODA POP", pocket = "ITEMS", fieldUse = "heal", frlg = 27 },
  LEMONADE = { name = "LEMONADE", pocket = "ITEMS", fieldUse = "heal", frlg = 28 },
  SUPER_REPEL = { name = "SUPER REPEL", pocket = "ITEMS", fieldUse = "repel", frlg = 83 },
  MAX_REPEL = { name = "MAX REPEL", pocket = "ITEMS", fieldUse = "repel", frlg = 84 },
  ESCAPE_ROPE = { name = "ESCAPE ROPE", pocket = "ITEMS", fieldUse = "escape", frlg = 85 },
  REPEL = { name = "REPEL", pocket = "ITEMS", fieldUse = "repel", frlg = 86 },
  X_ATTACK = { name = "X ATTACK", pocket = "ITEMS", fieldUse = "battle", frlg = 75 },
  X_DEFEND = { name = "X DEFEND", pocket = "ITEMS", fieldUse = "battle", frlg = 76 },
  X_SPEED = { name = "X SPEED", pocket = "ITEMS", fieldUse = "battle", frlg = 77 },
  X_ACCURACY = { name = "X ACCURACY", pocket = "ITEMS", fieldUse = "battle", frlg = 78 },
  X_SPECIAL = { name = "X SPECIAL", pocket = "ITEMS", fieldUse = "battle", frlg = 79 },
  POKE_DOLL = { name = "POKé DOLL", pocket = "ITEMS", fieldUse = "battle", frlg = 80 },
  RARE_CANDY = { name = "RARE CANDY", pocket = "ITEMS", fieldUse = "level", frlg = 68 },
  SUN_STONE = { name = "SUN STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 93 },
  MOON_STONE = { name = "MOON STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 94 },
  FIRE_STONE = { name = "FIRE STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 95 },
  THUNDER_STONE = { name = "THUNDER STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 96 },
  WATER_STONE = { name = "WATER STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 97 },
  LEAF_STONE = { name = "LEAF STONE", pocket = "ITEMS", fieldUse = "evo", frlg = 98 },
  ORAN_BERRY = { name = "ORAN BERRY", pocket = "BERRY_POUCH", fieldUse = "heal", frlg = 139 },
  SITRUS_BERRY = { name = "SITRUS BERRY", pocket = "BERRY_POUCH", fieldUse = "heal", frlg = 142 },
  LUM_BERRY = { name = "LUM BERRY", pocket = "BERRY_POUCH", fieldUse = "status", frlg = 141 },
  LEPPA_BERRY = { name = "LEPPA BERRY", pocket = "BERRY_POUCH", fieldUse = "pp", frlg = 138 },
  NUGGET = { name = "NUGGET", pocket = "ITEMS", fieldUse = "none", frlg = 110 },
  METEORITE = { name = "METEORITE", pocket = "KEY_ITEMS", fieldUse = "key", frlg = 280 },
  ITEMFINDER = { name = "ITEMFINDER", pocket = "KEY_ITEMS", fieldUse = "itemfinder", frlg = 261 },
  TOWN_MAP = { name = "TOWN MAP", pocket = "KEY_ITEMS", fieldUse = "map", frlg = 361 },
  BICYCLE = { name = "BICYCLE", pocket = "KEY_ITEMS", fieldUse = "bike", frlg = 360 },
  TRI_PASS = { name = "TRI-PASS", pocket = "KEY_ITEMS", fieldUse = "key", frlg = 367 },
  RAINBOW_PASS = { name = "RAINBOW PASS", pocket = "KEY_ITEMS", fieldUse = "key", frlg = 368 },
  VS_SEEKER = { name = "VS SEEKER", pocket = "KEY_ITEMS", fieldUse = "vs_seeker", frlg = 362 },
}

local FALLBACK = {
  [1] = { name = "MASTER BALL", pocket = "POKE_BALLS", fieldUse = "battle" },
  [4] = { name = "POKé BALL", pocket = "POKE_BALLS", fieldUse = "battle" },
  [13] = { name = "POTION", pocket = "ITEMS", fieldUse = "heal" },
  [261] = { name = "ITEMFINDER", pocket = "KEY_ITEMS", fieldUse = "itemfinder" },
  [362] = { name = "VS SEEKER", pocket = "KEY_ITEMS", fieldUse = "vs_seeker" },
  [364] = { name = "TM CASE", pocket = "KEY_ITEMS", fieldUse = "key" },
  [365] = { name = "BERRY POUCH", pocket = "KEY_ITEMS", fieldUse = "key" },
}

ItemsData.HEAL_AMOUNT = {
  [13] = 20, [19] = 9999, [20] = 9999, [21] = 200, [22] = 50,
  [26] = 50, [27] = 60, [28] = 80, [29] = 100,
  [139] = 10, [142] = 30,
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  MAX_POTION = 9999, FULL_RESTORE = 9999,
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
  ORAN_BERRY = 10, SITRUS_BERRY = 30,
}

ItemsData.REPEL_STEPS = {
  [86] = 100, [83] = 200, [84] = 250,
  REPEL = 100, SUPER_REPEL = 200, MAX_REPEL = 250,
}

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
    (os.getenv("HOME") or "") .. "/.local/share/love/pokemon-love2d/firered/" .. rel,
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

ItemsData._byName = nil

local GEN2_BERRY_ALIASES = {
  BERRY = 139, -- ORAN BERRY
  GOLD_BERRY = 142, -- SITRUS BERRY
  GOLDBERRY = 142,
  MYSTERYBERRY = 138, -- LEPPA BERRY
  MIRACLEBERRY = 141, -- LUM BERRY
  PSNCUREBERRY = 135, -- PECHA BERRY
  PRZCUREBERRY = 133, -- CHERI BERRY
  BURNT_BERRY = 136, -- RAWST BERRY
  ICE_BERRY = 137, -- ASPEAR BERRY
  BITTER_BERRY = 140, -- PERSIM BERRY
  MINT_BERRY = 134, -- CHESTO BERRY
}

local function build_by_name(packItems)
  local map = {}
  if type(packItems) == "table" then
    for id, it in pairs(packItems) do
      if type(it) == "table" and it.name then
        local n = it.name:upper()
        map[n] = id
        map[n:gsub("%s+", "_")] = id
        map[n:gsub("[^%w]", "")] = id
      end
    end
  end
  for k, v in pairs(GEN2_BERRY_ALIASES) do
    map[k] = v
  end
  for i = 1, 50 do
    map[string.format("TM%02d", i)] = 288 + i
    map[string.format("TM_%02d", i)] = 288 + i
    map[string.format("TM%d", i)] = 288 + i
    map[string.format("TM_%d", i)] = 288 + i
  end
  for i = 1, 8 do
    map[string.format("HM%02d", i)] = 338 + i
    map[string.format("HM_%02d", i)] = 338 + i
    map[string.format("HM%d", i)] = 338 + i
    map[string.format("HM_%d", i)] = 338 + i
  end
  return map
end

local function load_pack()
  if ItemsData._byId then return ItemsData._byId end
  local src = read_bytes("data/generated/gba/items/pack.lua")
  if src then
    local chunk = load(src, "@items/pack.lua", "t", {})
    if chunk then
      local ok, pack = pcall(chunk)
      if ok and type(pack) == "table" and type(pack.items) == "table" then
        ItemsData._pack = pack
        ItemsData._byId = pack.items
        ItemsData._byName = build_by_name(pack.items)
        if not ItemsData._logged then
          ItemsData._logged = true
          print("[game3/items] pack ready (" .. tostring(pack.count) .. ")")
        end
        return ItemsData._byId
      elseif not ok then
        if not ItemsData._loadWarned then
          ItemsData._loadWarned = true
          print("[game3/items] items pack load failed: " .. tostring(pack))
        end
      end
    end
  end
  ItemsData._byId = FALLBACK
  ItemsData._byName = build_by_name(FALLBACK)
  if not ItemsData._logged then
    ItemsData._logged = true
    print("[game3/items] pack missing — using fallback rows")
  end
  return ItemsData._byId
end

function ItemsData.ensureLoaded()
  return load_pack()
end

function ItemsData.install(_cache)
  ItemsData._pack = nil
  ItemsData._byId = nil
  ItemsData._byName = nil
  ItemsData._logged = false
  load_pack()
end

local function normalize_id(id)
  if id == nil then return nil, nil end
  local s = tostring(id)
  if s:match("^FRLG_(%d+)$") then
    return tonumber(s:match("^FRLG_(%d+)$")), s
  end
  local num = tonumber(id)
  if num then return num, tostring(num) end

  load_pack()
  local sUpper = s:upper()
  if ItemsData._byName and ItemsData._byName[sUpper] then
    return ItemsData._byName[sUpper], s
  end

  local tm = sUpper:match("^TM_?(%d+)$")
  if tm then
    local n = tonumber(tm)
    if n and n >= 1 and n <= 50 then return 288 + n, s end
  end
  local hm = sUpper:match("^HM_?(%d+)$")
  if hm then
    local n = tonumber(hm)
    if n and n >= 1 and n <= 8 then return 338 + n, s end
  end

  return nil, s
end

function ItemsData.info(id)
  if id == nil then return nil end
  local byId = load_pack()
  local num, key = normalize_id(id)
  if num and byId[num] then
    local e = byId[num]
    return {
      id = num,
      name = e.name,
      pocket = e.pocket,
      fieldUse = e.fieldUse or "none",
      price = e.price,
      holdEffect = e.holdEffect,
      holdEffectParam = e.holdEffectParam,
      description = e.description,
      battleUsage = e.battleUsage,
      fieldUseFunc = e.fieldUseFunc,
      battleUseFunc = e.battleUseFunc,
      registrability = e.registrability,
      importance = e.importance,
      secondaryId = e.secondaryId,
    }
  end
  local s = tostring(id)
  local h = ItemsData.BY_HOST[s]
  if h then
    return {
      id = s,
      name = h.name,
      pocket = h.pocket,
      fieldUse = h.fieldUse,
      frlg = h.frlg,
    }
  end
  if num then
    if num >= 289 and num <= 346 then
      local label = (num >= 339) and string.format("HM%02d", num - 338)
        or string.format("TM%02d", num - 288)
      return { id = num, name = label, pocket = "TM_CASE", fieldUse = "tm" }
    end
    if num >= 133 and num <= 175 then
      return { id = num, name = "BERRY", pocket = "BERRY_POUCH", fieldUse = "heal" }
    end
    return { id = num, name = Strings("ITEM %s", num), pocket = "ITEMS", fieldUse = "none" }
  end
  local sUpper = s:upper()
  if sUpper:find("BERRY", 1, true) then
    return { id = s, name = s:gsub("_", " "), pocket = "BERRY_POUCH", fieldUse = "heal" }
  end
  if sUpper:find("^TM%d") or sUpper:find("^HM%d") or sUpper:find("^TM_") or sUpper:find("^HM_") then
    return { id = s, name = s:gsub("_", " "), pocket = "TM_CASE", fieldUse = "tm" }
  end
  return { id = s, name = s:gsub("_", " "), pocket = "ITEMS", fieldUse = "none" }
end

function ItemsData.pocketOf(id)
  local info = ItemsData.info(id)
  return info and info.pocket or "ITEMS"
end

function ItemsData.pocketResult(id)
  local pocket = ItemsData.pocketOf(id)
  return ItemsData.POCKET_RESULT[pocket] or 1
end

function ItemsData.displayName(id)
  local info = ItemsData.info(id)
  return info and info.name or tostring(id)
end

function ItemsData.description(id)
  local info = ItemsData.info(id)
  local desc = (info and info.description) or ""
  return desc:gsub("\\n", "\n"):gsub("\\p", "\n")
end

function ItemsData.isTm(id)
  local num = tonumber(id)
  if not num then
    local n2 = select(1, normalize_id(id))
    num = n2
  end
  if not num then
    local s = tostring(id or ""):upper()
    return s:find("^TM%d+") ~= nil or s:find("^HM%d+") ~= nil
  end
  local ftm = ItemsData.FIRST_TM or 289
  local ltm = ItemsData.LAST_TM or 338
  local fhm = ItemsData.FIRST_HM or 339
  local lhm = ItemsData.LAST_HM or 346
  return (num >= ftm and num <= ltm) or (num >= fhm and num <= lhm)
end

function ItemsData.isEvolutionStone(id)
  local num = tonumber(id)
  if not num then
    local n2 = select(1, normalize_id(id))
    num = n2
  end
  if not num then
    local s = tostring(id or ""):upper()
    return s:find("STONE", 1, true) ~= nil
  end
  -- include/constants/items.h:97-102
  return num >= 93 and num <= 98
end

function ItemsData.isHm(id)
  local num = tonumber(id)
  if not num then
    local n2 = select(1, normalize_id(id))
    num = n2
  end
  return num and num >= ItemsData.FIRST_HM and num <= ItemsData.LAST_HM
end

ItemsData.FIRST_BERRY = 133
ItemsData.LAST_BERRY = 175

function ItemsData.isBerry(id)
  local num = tonumber(id)
  if not num then
    num = ItemsData.toNumericId(id)
  end
  return num and num >= ItemsData.FIRST_BERRY and num <= ItemsData.LAST_BERRY
end

--- Get 1-based Berry index (1..43) from item ID.
function ItemsData.berryNumber(id)
  local num = tonumber(id)
  if not num then
    num = ItemsData.toNumericId(id)
  end
  if num and num >= ItemsData.FIRST_BERRY and num <= ItemsData.LAST_BERRY then
    return num - ItemsData.FIRST_BERRY + 1
  end
  return nil
end

--- Get 1-based TM (1..50) or HM (1..8) index from item ID.
function ItemsData.tmNumber(id)
  local num = tonumber(id)
  if not num then
    num = ItemsData.toNumericId(id)
  end
  if num then
    if num >= ItemsData.FIRST_TM and num <= ItemsData.LAST_TM then
      return num - ItemsData.FIRST_TM + 1
    elseif num >= ItemsData.FIRST_HM and num <= ItemsData.LAST_HM then
      return num - ItemsData.FIRST_HM + 1
    end
  end
  local s = tostring(id):upper()
  local tm = s:match("TM_?(%d+)")
  if tm then return tonumber(tm) end
  local hm = s:match("HM_?(%d+)")
  if hm then return tonumber(hm) end
  return nil
end


--- Canonical bag key: prefer numeric FRLG id string.
function ItemsData.bagKey(id)
  local num = select(1, normalize_id(id))
  if num then return tostring(num) end
  local h = ItemsData.BY_HOST[tostring(id)]
  if h and h.frlg then return tostring(h.frlg) end
  return tostring(id)
end

function ItemsData.toNumericId(id)
  local num = select(1, normalize_id(id))
  if num then return num end
  local h = ItemsData.BY_HOST[tostring(id)]
  if h and h.frlg then return h.frlg end
  return nil
end

-- Refine FieldUseFunc_Medicine → heal/status/revive (pack maps all to "heal").
local STATUS_IDS = {
  [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, -- status heals
  [23] = true, -- FULL HEAL
  [32] = true, -- HEAL POWDER
  [133] = true, [134] = true, [135] = true, [136] = true, [137] = true, -- status berries
}
local REVIVE_IDS = {
  [24] = true, [25] = true, [45] = true, -- REVIVE / MAX / SACRED ASH
}
local FULL_RESTORE_IDS = { [19] = true }

--- Coarse medicine kind for field/battle use.
function ItemsData.medicineKind(id)
  local num = ItemsData.toNumericId(id) or tonumber(id)
  local host = tostring(id)
  if FULL_RESTORE_IDS[num] or host == "FULL_RESTORE" then return "full_restore" end
  if REVIVE_IDS[num] or host == "REVIVE" or host == "MAX_REVIVE" or host == "SACRED_ASH" then
    return "revive"
  end
  if STATUS_IDS[num] or host == "ANTIDOTE" or host == "FULL_HEAL"
      or host == "BURN_HEAL" or host == "ICE_HEAL" or host == "AWAKENING"
      or host == "PARLYZ_HEAL" then
    return "status"
  end
  local info = ItemsData.info(id)
  if info and info.fieldUse == "revive" then return "revive" end
  if info and info.fieldUse == "status" then return "status" end
  if info and (info.fieldUse == "heal" or info.fieldUse == "pp") then return "heal" end
  return info and info.fieldUse or "none"
end

-- include/constants/items.h:97-102
local LEVEL_IDS = { [68] = true }
local EVO_IDS = { [93] = true, [94] = true, [95] = true, [96] = true, [97] = true, [98] = true }
local VITAMIN_IDS = { [63] = true, [64] = true, [65] = true, [66] = true, [67] = true, [70] = true }
local PP_IDS = { [34] = true, [35] = true, [36] = true, [37] = true, [69] = true, [71] = true }
local ESCAPE_IDS = { [85] = true }
local REPEL_IDS = { [83] = true, [84] = true, [86] = true }
-- pokefirered/src/data/items.h:3962 FieldUseFunc_Bike
local BIKE_IDS = { [259] = true, [272] = true, [360] = true }
-- pokefirered/src/data/items.h:5492 FieldUseFunc_TownMap
local MAP_IDS = { [361] = true }
-- pokefirered/src/data/items.h:3977 FieldUseFunc_CoinCase
local COIN_CASE_IDS = { [260] = true }
-- pokefirered/src/data/items.h:5657 FieldUseFunc_PowderJar
local POWDER_JAR_IDS = { [372] = true }
-- pokefirered/src/data/items.h:3992 ItemUseOutOfBattle_Itemfinder
local ITEMFINDER_IDS = { [261] = true }
-- pokefirered/src/data/items.h:5507 FieldUseFunc_VsSeeker
local VS_SEEKER_IDS = { [362] = true }

--- Effective field-use kind (medicine refined).
function ItemsData.fieldUseKind(id)
  local num = ItemsData.toNumericId(id) or tonumber(id)
  local host = tostring(id):upper()
  if LEVEL_IDS[num] or host == "RARE_CANDY" then return "level" end
  if EVO_IDS[num] or host:find("STONE", 1, true) then return "evo" end
  if VITAMIN_IDS[num] or host == "HP_UP" or host == "PROTEIN" or host == "IRON"
      or host == "CARBOS" or host == "CALCIUM" or host == "ZINC" then
    return "vitamin"
  end
  if PP_IDS[num] or host:find("ETHER", 1, true) or host:find("ELIXIR", 1, true)
      or host == "PP_UP" or host == "PP_MAX" then
    return "pp"
  end
  if (num and num >= 289 and num <= 346) or host:find("^TM%d") or host:find("^HM%d")
      or host:find("TM_") or host:find("HM_") then
    return "tm"
  end
  if ESCAPE_IDS[num] or host == "ESCAPE_ROPE" then return "escape" end
  if REPEL_IDS[num] or host:find("REPEL", 1, true) then return "repel" end
  if COIN_CASE_IDS[num] or host == "COIN_CASE" then return "coin_case" end
  if POWDER_JAR_IDS[num] or host == "POWDER_JAR" then return "powder_jar" end
  if BIKE_IDS[num] or host:find("BIKE", 1, true) or host:find("BICYCLE", 1, true) then return "bike" end
  if MAP_IDS[num] or host == "TOWN_MAP" then return "map" end
  if ITEMFINDER_IDS[num] or host == "ITEMFINDER" then return "itemfinder" end
  if VS_SEEKER_IDS[num] or host == "VS_SEEKER" then return "vs_seeker" end

  local info = ItemsData.info(id)
  if not info then return "none" end
  if info.fieldUse == "heal" or info.fieldUse == "status" or info.fieldUse == "revive" then
    local mk = ItemsData.medicineKind(id)
    if mk == "full_restore" then return "heal" end
    return mk
  end
  if info.fieldUse == "level" then return "level" end
  if info.fieldUse == "evo" then return "evo" end
  if info.pocket == "TM_CASE" then return "tm" end
  return info.fieldUse or "none"
end

-- Back-compat for older callers.
ItemsData.BY_ID = setmetatable({}, {
  __index = function(_, k)
    local info = ItemsData.info(k)
    if not info then return nil end
    return { name = info.name, pocket = info.pocket, fieldUse = info.fieldUse }
  end,
})

return ItemsData

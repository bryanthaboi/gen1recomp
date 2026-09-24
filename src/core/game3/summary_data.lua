-- Pokémon Summary Screen Data & Mechanics.
-- Faithful replication of FRLG experience tables, natures, trainer memo logic, and move/ability descriptions.

local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local SummaryData = {}

local NATURE_KEYS = {}
for i = 0, 24 do NATURE_KEYS[i] = RomText.key("gNatureNamePointers", i) end
-- src/data/text/nature_names.h:27
SummaryData.NATURES = RomText.lazy(NATURE_KEYS)

-- Stat multipliers per nature [natureId] = { stat = 1.1 / 0.9 / 1.0 }
-- Stats: atk, def, spAtk, spDef, spd
local STAT_UP = {
  [1] = "atk", [2] = "atk", [3] = "atk", [4] = "atk",
  [5] = "def", [7] = "def", [8] = "def", [9] = "def",
  [10] = "spd", [11] = "spd", [13] = "spd", [14] = "spd",
  [15] = "spAtk", [16] = "spAtk", [17] = "spAtk", [19] = "spAtk",
  [20] = "spDef", [21] = "spDef", [22] = "spDef", [23] = "spDef",
}

local STAT_DOWN = {
  [1] = "def", [2] = "spd", [3] = "spAtk", [4] = "spDef",
  [5] = "atk", [7] = "spd", [8] = "spAtk", [9] = "spDef",
  [10] = "atk", [11] = "def", [13] = "spAtk", [14] = "spDef",
  [15] = "atk", [16] = "def", [17] = "spd", [19] = "spDef",
  [20] = "atk", [21] = "def", [22] = "spd", [23] = "spAtk",
}

function SummaryData.natureStatModifier(natureId, statKey)
  natureId = tonumber(natureId) or 0
  if STAT_UP[natureId] == statKey then
    return 1.1
  elseif STAT_DOWN[natureId] == statKey then
    return 0.9
  end
  return 1.0
end

--- Growth Rates matching pokefirered/src/data/pokemon/experience_tables.h
-- Enum order = pret GROWTH_MEDIUM_FAST..GROWTH_SLOW (species meta.growthRate from ROM).
-- Tables hardcode [0]=0, [1]=1 for every rate; formulas apply from level 2 up
-- (Medium Slow at n=1 is negative — pret stores 1).
local function calc_exp(growthRate, n)
  n = tonumber(n) or 0
  if n <= 0 then return 0 end
  if n == 1 then return 1 end
  if n > 100 then n = 100 end
  local n3 = n * n * n
  local n2 = n * n

  if growthRate == 0 then
    -- Medium Fast (CUBE(n))
    return n3
  elseif growthRate == 1 then
    -- Erratic
    if n <= 50 then
      return math.floor((100 - n) * n3 / 50)
    elseif n <= 68 then
      return math.floor((150 - n) * n3 / 100)
    elseif n <= 98 then
      return math.floor(math.floor((1911 - 10 * n) / 3) * n3 / 500)
    else
      return math.floor((160 - n) * n3 / 100)
    end
  elseif growthRate == 2 then
    -- Fluctuating
    if n <= 15 then
      return math.floor((math.floor((n + 1) / 3) + 24) * n3 / 50)
    elseif n <= 36 then
      return math.floor((n + 14) * n3 / 50)
    else
      return math.floor((math.floor(n / 2) + 32) * n3 / 50)
    end
  elseif growthRate == 3 then
    -- Medium Slow: (6 * CUBE(n)) / 5 - 15 * SQUARE(n) + 100 * n - 140
    local val = math.floor((6 * n3) / 5) - (15 * n2) + (100 * n) - 140
    return math.max(0, val)
  elseif growthRate == 4 then
    -- Fast: (4 * CUBE(n)) / 5
    return math.floor((4 * n3) / 5)
  elseif growthRate == 5 then
    -- Slow: (5 * CUBE(n)) / 4
    return math.floor((5 * n3) / 4)
  end
  return n3
end

-- Precompute tables 0..5, levels 0..100
local EXP_TABLES = {}
for g = 0, 5 do
  EXP_TABLES[g] = {}
  for lv = 0, 100 do
    EXP_TABLES[g][lv] = calc_exp(g, lv)
  end
end

function SummaryData.expForLevel(growthRate, level)
  growthRate = (tonumber(growthRate) or 0) % 6
  level = math.max(1, math.min(100, tonumber(level) or 1))
  local tbl = EXP_TABLES[growthRate]
  return tbl and tbl[level] or 0
end

--- Return experience progress struct for a Pokémon
function SummaryData.expProgress(mon, growthRate)
  growthRate = (tonumber(growthRate) or tonumber(mon and mon.growthRate) or 0) % 6
  local level = math.max(1, math.min(100, tonumber(mon and mon.level) or 1))
  local totalExp = tonumber(mon and mon.exp) or SummaryData.expForLevel(growthRate, level)

  local curLevelExp = SummaryData.expForLevel(growthRate, level)
  local nextLevelExp = (level >= 100) and curLevelExp or SummaryData.expForLevel(growthRate, level + 1)
  local expNeeded = (level >= 100) and 0 or math.max(0, nextLevelExp - totalExp)

  local barTotal = math.max(1, nextLevelExp - curLevelExp)
  local barProgress = math.max(0, math.min(barTotal, totalExp - curLevelExp))
  local pct = (level >= 100) and 1.0 or (barProgress / barTotal)

  return {
    totalExp = totalExp,
    level = level,
    curLevelExp = curLevelExp,
    nextLevelExp = nextLevelExp,
    expNeeded = expNeeded,
    expProgress = barProgress,
    levelTotalExp = barTotal,
    progressPercent = pct,
  }
end

--- Get nature ID and name from personality
function SummaryData.nature(mon)
  local p = tonumber(mon and mon.personality) or 0
  local natureId = p % 25
  return natureId, SummaryData.NATURES[natureId]
end

--- Check if shiny: ((otId ~ otSecretId) ~ (pHigh ~ pLow)) < 8
function SummaryData.isShiny(mon)
  if not mon then return false end
  if mon.isShiny ~= nil then return not not mon.isShiny end
  local p = tonumber(mon.personality) or 0
  local otId = tonumber(mon.otId) or 0
  local secretId = tonumber(mon.otSecretId) or 0

  local pHigh = bit.rshift(p, 16)
  local pLow = bit.band(p, 0xFFFF)
  local trainerXor = bit.bxor(otId, secretId)
  local pidXor = bit.bxor(pHigh, pLow)
  return bit.bxor(trainerXor, pidXor) < 8
end

--- Check gender: "M", "F", or ""
function SummaryData.gender(mon)
  if not mon then return "" end
  if mon.gender then return mon.gender end
  if mon.isEgg then return "" end
  local ratio = tonumber(mon.genderRatio)
  if not ratio then
    -- src/pokemon_summary_screen.c:2114
    local Pokemon = require("src.core.game3.pokemon")
    local g = Pokemon.gender(Pokemon.speciesOf(mon), mon.personality)
    return (g == "M" or g == "F") and g or ""
  end
  if ratio == 255 then return "" end
  if ratio == 254 then return "F" end             -- 100% female
  if ratio == 0 then return "M" end               -- 100% male
  local p = tonumber(mon.personality) or 0
  local byte = bit.band(p, 0xFF)
  return (byte >= ratio) and "M" or "F"
end

--- Status ailment code:
--- 0: None, 1: PSN, 2: PRZ, 3: SLP, 4: FRZ, 5: BRN, 6: PKRS, 7: FNT
function SummaryData.statusAilment(mon)
  if not mon then return 0 end
  local curHp = tonumber(mon.hp or mon.currentHp)
  if curHp and curHp <= 0 then return 7 end -- FNT

  local st = mon.status or mon.status1
  if type(st) == "string" then
    local s = st:upper()
    if s:find("PSN") or s:find("POISON") or s:find("TOX") then return 1 end
    if s:find("PRZ") or s:find("PAR") then return 2 end
    if s:find("SLP") or s:find("SLEEP") then return 3 end
    if s:find("FRZ") or s:find("FREEZE") or s:find("FROZEN") then return 4 end
    if s:find("BRN") or s:find("BURN") then return 5 end
    if s:find("PKRS") or s:find("POKERUS") then return 6 end
    if s:find("FNT") or s:find("FAINT") then return 7 end
  elseif type(st) == "number" then
    if bit.band(st, 0x08) ~= 0 or bit.band(st, 0x80) ~= 0 then return 1 end -- PSN / TOXIC
    if bit.band(st, 0x40) ~= 0 then return 2 end -- PRZ
    if bit.band(st, 0x07) ~= 0 then return 3 end -- SLP
    if bit.band(st, 0x20) ~= 0 then return 4 end -- FRZ
    if bit.band(st, 0x10) ~= 0 then return 5 end -- BRN
  end
  -- pokefirered/src/pokemon.c:5618 CheckPartyPokerus
  if (tonumber(mon.pokerus) or 0) % 16 ~= 0 then return 6 end
  return 0
end

local function map_sections()
  return require("src.import.gba.map_sections_extract")
end

local _sec_cache = {}
local _celadon_by_map = {}

-- pokefirered/src/region_map.c:3801 GetMapName
local function section_of(sec)
  local cached = _sec_cache[sec]
  if cached ~= nil then return cached or nil end
  local entry = false
  local info = map_sections().getInfo(sec, nil, 0)
  if type(info) == "table" and info.resolved then
    local name = info.rawName or info.name
    if type(name) == "string" and name ~= "" then entry = { id = info.id, name = name } end
  end
  _sec_cache[sec] = entry
  return entry or nil
end

-- pokefirered/src/region_map.c:3782 IsCeladonDeptStoreMapsec
local function celadon_name(sec, here)
  local cached = _celadon_by_map[here]
  if cached == nil then
    cached = false
    local info = map_sections().getInfo(sec, here, 0)
    if type(info) == "table" and info.resolved then
      local name = info.rawName or info.name
      if type(name) == "string" and name ~= "" then cached = name end
    end
    _celadon_by_map[here] = cached
  end
  return cached or nil
end

-- pokefirered/src/pokemon_summary_screen.c:2632 MapSecIsInKantoOrSevii / GetMapNameGeneric_
local function met_location_name(mon, playerState)
  local stamped = mon.metLocationName
  if type(stamped) == "string" and stamped ~= "" then return stamped end
  local sec = tonumber(mon.metLocation)
  if not sec then return nil end
  local entry = section_of(sec)
  if not entry then return nil end
  local here = playerState and playerState.map
  if entry.id == "MAPSEC_CELADON_CITY" and type(here) == "string" then
    return celadon_name(sec, here) or entry.name
  end
  return entry.name
end

local METLOC_SPECIAL_EGG = 0xFD
local METLOC_FATEFUL_ENCOUNTER = 0xFF

local function split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  return lines
end

-- src/pokemon_summary_screen.c:3243
local function held_by_ot(mon, playerState)
  if not playerState then return true end
  local pName = playerState.playerName or playerState.name
  local pId = playerState.trainerId or playerState.otId or playerState.id
  local pSecret = playerState.secretId or playerState.otSecretId
  local monOtName = mon.otName or mon.originalTrainer
  local monOtId = tonumber(mon.otId)
  local monSecret = tonumber(mon.otSecretId)
  if pName and monOtName and pName ~= monOtName then return false end
  if pId and monOtId and (bit.band(pId, 0xFFFF) ~= bit.band(monOtId, 0xFFFF)) then return false end
  if pSecret and monSecret and (bit.band(pSecret, 0xFFFF) ~= bit.band(monSecret, 0xFFFF)) then return false end
  return true
end

-- src/pokemon_summary_screen.c:5213
local function in_kanto_or_sevii(sec)
  return sec >= 88 and sec < 197
end

-- src/pokemon_summary_screen.c:5199
local function from_gba(mon)
  local game = tonumber(mon.metGame)
  return game == nil or (game >= 1 and game <= 5)
end

-- src/pokemon_summary_screen.c:2789
local function egg_origin_index(mon, heldByOt)
  if mon.isBadEgg then return 0 end
  local metLocation = tonumber(mon.metLocation) or 0
  if metLocation == METLOC_FATEFUL_ENCOUNTER or mon.fatefulEncounter == true then return 4 end
  local idx = 0
  local game = tonumber(mon.metGame)
  if game ~= nil and game ~= 4 and game ~= 5 then
    idx = 1
  elseif metLocation == METLOC_SPECIAL_EGG then
    idx = 2
  end
  if (idx == 0 or idx == 2) and not heldByOt then idx = idx + 1 end
  return idx
end

function SummaryData.eggCycles(mon)
  return tonumber(mon and (mon.eggCycles or mon.friendship)) or 40
end

-- src/pokemon_summary_screen.c:2483
local function egg_hatch_index(mon)
  if mon.isBadEgg then return 0 end
  local cycles = SummaryData.eggCycles(mon)
  if cycles <= 5 then return 3 end
  if cycles <= 10 then return 2 end
  if cycles <= 40 then return 1 end
  return 0
end

-- src/pokemon_summary_screen.c:2495
function SummaryData.eggHatchText(mon)
  if not mon then return "" end
  return RomText.at("sEggHatchTimeTexts", egg_hatch_index(mon))
end

--- Trainer Memo formatting (pokefirered/src/pokemon_summary_screen.c PokeSum_PrintTrainerMemo)
function SummaryData.formatTrainerMemo(mon, playerState, opts)
  if not mon then return { RomText.plain("gText_PokeSum_NoData") } end

  -- src/pokemon_summary_screen.c:3243
  local heldByOt = held_by_ot(mon, (opts and opts.owner) or playerState)

  if mon.isEgg then
    -- src/pokemon_summary_screen.c:2839
    return { RomText.at("sEggOriginTexts", egg_origin_index(mon, heldByOt)) }
  end

  local _, natureName = SummaryData.nature(mon)
  local rawMetLevel = tonumber(mon.metLevel)
  local hatched = rawMetLevel == 0
  local metLevel = rawMetLevel or 5
  if metLevel == 0 then metLevel = 5 end
  local metLocation = tonumber(mon.metLocation) or 0
  local fatefulMet = metLocation == METLOC_FATEFUL_ENCOUNTER
  local fatefulFlag = mon.fatefulEncounter == true

  local key
  local mapName
  if heldByOt then
    -- src/pokemon_summary_screen.c:2632
    if in_kanto_or_sevii(metLocation) or mon.metLocationName then
      mapName = met_location_name(mon, playerState)
    elseif opts and opts.enemyParty then
      -- src/pokemon_summary_screen.c:2636
      mapName = RomText.plain("gText_Somewhere")
    else
      mapName = RomText.plain("gText_PokeSum_ATrade")
    end
    if hatched then
      key = fatefulFlag and "gText_PokeSum_FatefulEncounterHatched" or "gText_PokeSum_Hatched"
    else
      key = fatefulMet and "gText_PokeSum_FatefulEncounterMet" or "gText_PokeSum_Met"
    end
  elseif not in_kanto_or_sevii(metLocation) or not from_gba(mon) then
    -- src/pokemon_summary_screen.c:2707
    key = fatefulMet and "gText_PokeSum_FatefulEncounterMet" or "gText_PokeSum_MetInATrade"
  else
    -- src/pokemon_summary_screen.c:2735
    mapName = met_location_name(mon, playerState)
    if hatched then
      key = fatefulFlag and "gText_PokeSum_ApparentlyFatefulEncounterHatched" or "gText_PokeSum_ApparentlyMet"
    else
      key = fatefulMet and "gText_PokeSum_FatefulEncounterMet" or "gText_PokeSum_ApparentlyMet"
    end
  end

  -- src/pokemon_summary_screen.c:2621
  return split_lines(RomText.plain(key, {
    dynamic = { [0] = natureName, [1] = tostring(metLevel), [2] = mapName },
  }))
end

local function load_descriptions()
  local rel = "data/generated/gba/pokemon/descriptions.lua"
  local src = assert(require("src.core.game3.dataset").cache():read(rel), rel .. " is not in the cache")
  return assert(load(src, "@" .. rel, "t", {}))()
end

local _descs = nil
local function get_descriptions()
  if not _descs then
    _descs = load_descriptions()
  end
  return _descs
end

-- Descriptions are keyed by the English name.  A translation mod renames
-- moves and abilities, so the name the caller shows is looked past: the ROM's
-- own name for that number is what the key was built from.
local function rom_name(field, id, shown)
  local Pokemon = package.loaded["src.core.game3.pokemon"]
  local english = type(Pokemon) == "table" and Pokemon._cache and Pokemon[field]
    and Pokemon[field](id)
  return english or shown
end

function SummaryData.abilityDescription(abilityId, abilityName)
  local d = get_descriptions()
  abilityName = rom_name("romAbilityName", abilityId, abilityName)
  if d and d.ABILITIES and abilityName then
    local const = "ABILITY_" .. abilityName:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    if d.ABILITIES[const] then
      return Strings(d.ABILITIES[const])
    end
  end
  -- src/data/text/abilities.h:1
  return Strings(d.ABILITIES["ABILITY_"])
end

function SummaryData.moveDescription(moveId, moveName)
  local d = get_descriptions()
  moveName = rom_name("romMoveName", moveId, moveName)
  if d and d.MOVES and moveName then
    local const = "MOVE_" .. moveName:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    if d.MOVES[const] then
      return Strings(d.MOVES[const])
    end
  end
  return "---"
end

return SummaryData

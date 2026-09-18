-- Pokémon Summary Screen Data & Mechanics.
-- Faithful replication of FRLG experience tables, natures, trainer memo logic, and move/ability descriptions.

local SummaryData = {}

-- 25 Natures in FireRed index order (personality % 25).
SummaryData.NATURES = {
  [0]  = "HARDY",
  [1]  = "LONELY",
  [2]  = "BRAVE",
  [3]  = "ADAMANT",
  [4]  = "NAUGHTY",
  [5]  = "BOLD",
  [6]  = "DOCILE",
  [7]  = "RELAXED",
  [8]  = "IMPISH",
  [9]  = "LAX",
  [10] = "TIMID",
  [11] = "HASTY",
  [12] = "SERIOUS",
  [13] = "JOLLY",
  [14] = "NAIVE",
  [15] = "MODEST",
  [16] = "MILD",
  [17] = "QUIET",
  [18] = "BASHFUL",
  [19] = "RASH",
  [20] = "CALM",
  [21] = "GENTLE",
  [22] = "SASSY",
  [23] = "CAREFUL",
  [24] = "QUIRKY",
}

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
  return natureId, SummaryData.NATURES[natureId] or "HARDY"
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
  if not ratio or ratio == 255 then return "" end -- genderless
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
  if mon.pokerus and mon.pokerus > 0 then return 6 end -- PKRS
  return 0
end

--- Trainer Memo formatting (pokefirered/src/pokemon_summary_screen.c PokeSum_PrintTrainerMemo)
function SummaryData.formatTrainerMemo(mon, playerState)
  if not mon then return { "No data" } end

  -- Egg memo
  if mon.isEgg then
    local origin = "An odd POKéMON EGG found by the\nDAY-CARE couple."
    local hatchMsg
    local cycles = tonumber(mon.eggCycles or mon.friendship) or 40
    if cycles > 40 then
      hatchMsg = "It looks like this\nEGG will take a\nlong time to hatch."
    elseif cycles > 10 then
      hatchMsg = "What will hatch\nfrom this? It will\ntake some time."
    elseif cycles > 5 then
      hatchMsg = "It occasionally\nmoves. It should\nhatch soon."
    else
      hatchMsg = "It's making sounds.\nIt's almost ready\nto hatch!"
    end
    return { origin, hatchMsg }
  end

  local _, natureName = SummaryData.nature(mon)
  local metLevel = tonumber(mon.metLevel) or 5
  if metLevel == 0 then metLevel = 5 end

  -- Dynamic Trade Check: compare OT Name, OT ID, and Secret ID against player
  local isTrade = false
  if playerState then
    local pName = playerState.playerName or playerState.name
    local pId = playerState.trainerId or playerState.otId or playerState.id
    local pSecret = playerState.secretId or playerState.otSecretId

    local monOtName = mon.otName or mon.originalTrainer
    local monOtId = tonumber(mon.otId)
    local monSecret = tonumber(mon.otSecretId)

    if pName and monOtName and pName ~= monOtName then
      isTrade = true
    elseif pId and monOtId and (bit.band(pId, 0xFFFF) ~= bit.band(monOtId, 0xFFFF)) then
      isTrade = true
    elseif pSecret and monSecret and (bit.band(pSecret, 0xFFFF) ~= bit.band(monSecret, 0xFFFF)) then
      isTrade = true
    end
  end

  local isFateful = not not (mon.fatefulEncounter or mon.metLocation == 255)
  local isHatched = (mon.metLevel == 0 or mon.hatched)

  local locName = mon.metLocationName or "PALLET TOWN"
  if isTrade then
    locName = "a trade"
  end

  local lines = {}
  local header = string.format("%s nature.", natureName)
  lines[1] = header

  if isFateful then
    if isHatched then
      lines[2] = string.format("Met in a fateful encounter\n(hatched: %s at Lv. %d).", locName, metLevel)
    else
      lines[2] = string.format("Met in a fateful encounter when\nat Lv. %d.", metLevel)
    end
  elseif isTrade then
    lines[2] = "Met in a trade."
  elseif isHatched then
    lines[2] = string.format("Hatched: %s\nat Lv. %d.", locName, metLevel)
  else
    lines[2] = string.format("Met in %s\nat Lv. %d.", locName, metLevel)
  end

  return lines
end

local function load_descriptions()
  local okG, gen = pcall(require, "data.generated.gba.pokemon.descriptions")
  if okG and gen and gen.ABILITIES then return gen end
  local okC, core = pcall(require, "src.core.game3.summary_descriptions")
  if okC and core and core.ABILITIES then return core end
  return nil
end

local _descs = nil
local function get_descriptions()
  if not _descs then
    _descs = load_descriptions()
  end
  return _descs
end

function SummaryData.abilityDescription(abilityId, abilityName)
  local d = get_descriptions()
  if d and d.ABILITIES and abilityName then
    local const = "ABILITY_" .. abilityName:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    if d.ABILITIES[const] then
      return d.ABILITIES[const]
    end
  end
  return "No special ability."
end

function SummaryData.moveDescription(moveId, moveName)
  local d = get_descriptions()
  if d and d.MOVES and moveName then
    local const = "MOVE_" .. moveName:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    if d.MOVES[const] then
      return d.MOVES[const]
    end
  end
  return "---"
end

return SummaryData

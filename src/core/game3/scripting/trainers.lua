-- Trainer party lookup + ROM-derived class/name/pic/party/dialog info for battles and overworld.

local Strings = require("src.core.Strings")
local Trainers = {}

-- Fallbacks when trainers.lua cache is missing (Oak's Lab rivals).
local SPECIES_BULBASAUR = 1
local SPECIES_CHARMANDER = 4
local SPECIES_SQUIRTLE = 7

local TRAINER_RIVAL_OAKS_LAB_SQUIRTLE = 326
local TRAINER_RIVAL_OAKS_LAB_BULBASAUR = 327
local TRAINER_RIVAL_OAKS_LAB_CHARMANDER = 328

-- Translated when a trainer is built (fallback_dialogs): this table exists
-- before any translation catalog.
local RIVAL_LAB_DIALOGS = {
  defeat = Strings.source("WHAT?\nUnbelievable!\n\nI picked the wrong POKéMON!"),
  victory = Strings.source("RIVAL: Yeah!\nAm I great or what?"),
}

local FALLBACK_TRAINERS = {
  [TRAINER_RIVAL_OAKS_LAB_SQUIRTLE] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_SQUIRTLE, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = RIVAL_LAB_DIALOGS,
  },
  [TRAINER_RIVAL_OAKS_LAB_BULBASAUR] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_BULBASAUR, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = RIVAL_LAB_DIALOGS,
  },
  [TRAINER_RIVAL_OAKS_LAB_CHARMANDER] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_CHARMANDER, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = RIVAL_LAB_DIALOGS,
  },
}

local function fallback_dialogs(fb)
  local out = {}
  for key, text in pairs(fb.dialogs or {}) do out[key] = Strings(text) end
  return out
end

Trainers._pack = nil

local function load_pack()
  if Trainers._pack then return Trainers._pack end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = okD and Dataset and Dataset.cache and Dataset.cache()
  local src
  if cache and cache.read then
    src = cache:read("data/generated/gba/trainers.lua")
  end
  if not src then
    local ok, CacheFs = pcall(require, "src.import.CacheFs")
    if ok and CacheFs and CacheFs.readActive then
      src = CacheFs.readActive("data/generated/gba/trainers.lua")
    end
  end
  if type(src) == "string" and #src > 0 then
    local chunk = load(src, "@trainers.lua", "t", {})
    if chunk then
      local ok, pack = pcall(chunk)
      if ok and type(pack) == "table" then
        Trainers._pack = pack
        return pack
      end
    end
  end
  Trainers._pack = false
  return nil
end

local function decompose_ai_flags(flags)
  flags = tonumber(flags) or 0
  return {
    checkBadMove = (flags % 2 == 1),
    checkViability = (math.floor(flags / 2) % 2 == 1),
    tryToFaint = (math.floor(flags / 4) % 2 == 1),
    setupFirstTurn = (math.floor(flags / 8) % 2 == 1),
    risky = (math.floor(flags / 16) % 2 == 1),
    preferStrongestMove = (math.floor(flags / 32) % 2 == 1),
    preferBatonPass = (math.floor(flags / 64) % 2 == 1),
    doubleBattle = (math.floor(flags / 128) % 2 == 1),
    hpAware = (math.floor(flags / 256) % 2 == 1),
    roaming = (math.floor(flags / 0x20000000) % 2 == 1),
    safari = (math.floor(flags / 0x40000000) % 2 == 1),
    firstBattle = (flags >= 0x80000000),
  }
end

function Trainers.pack()
  return load_pack() or nil
end

--- Get full trainer definition record by trainerId.
function Trainers.get(trainerId)
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local pack = load_pack()
  local row = pack and pack.trainers and pack.trainers[trainerId]
  if row then
    local classNames = pack and pack.classNames
    local class = tonumber(row.class) or 0
    local fb = FALLBACK_TRAINERS[trainerId]
    local dlgs = row.dialogs or {}
    if (not dlgs.defeat or dlgs.defeat == "") and fb and fb.dialogs and fb.dialogs.defeat then
      local fbDialogs = fallback_dialogs(fb)
      dlgs = {
        intro = dlgs.intro or fbDialogs.intro,
        defeat = dlgs.defeat or fbDialogs.defeat,
        victory = dlgs.victory or fbDialogs.victory,
      }
    end
    return {
      id = trainerId,
      class = class,
      className = row.className or (classNames and classNames[class]) or "",
      pic = tonumber(row.pic) or 0,
      name = row.name or "",
      gender = tonumber(row.gender) or 0,
      encounterMusic = tonumber(row.encounterMusic) or 0,
      doubleBattle = row.doubleBattle and true or false,
      partySize = tonumber(row.partySize) or (row.party and #row.party) or 0,
      partyFlags = tonumber(row.partyFlags) or 0,
      lastLevel = tonumber(row.lastLevel) or 1,
      aiFlags = tonumber(row.aiFlags) or 0,
      ai = decompose_ai_flags(row.aiFlags),
      items = row.items or { 0, 0, 0, 0 },
      party = row.party or {},
      dialogs = dlgs,
      scriptKey = row.scriptKey,
      introTextKey = row.introTextKey,
      defeatTextKey = row.defeatTextKey,
    }
  end

  local fb = FALLBACK_TRAINERS[trainerId]
  if fb then
    return {
      id = trainerId,
      class = fb.class,
      className = fb.className,
      pic = fb.pic,
      name = fb.name,
      gender = fb.gender or 0,
      encounterMusic = fb.encounterMusic or 0,
      doubleBattle = fb.doubleBattle,
      partySize = fb.partySize,
      lastLevel = fb.lastLevel,
      aiFlags = fb.aiFlags,
      ai = decompose_ai_flags(fb.aiFlags),
      items = fb.items,
      party = fb.party,
      dialogs = fallback_dialogs(fb),
    }
  end

  return nil
end

local GBA_CHAR = {
  [" "] = 0x00, ["é"] = 0x1B, ["&"] = 0x2D, ["+"] = 0x2E, ["!"] = 0xAB, ["?"] = 0xAC,
  ["."] = 0xAD, ["-"] = 0xAE, ["…"] = 0xB0, ["“"] = 0xB1, ["”"] = 0xB2, ["‘"] = 0xB3,
  ["’"] = 0xB4, ["'"] = 0xB4, ["♂"] = 0xB5, ["♀"] = 0xB6, [","] = 0xB8, ["/"] = 0xBA,
}

local function gba_char_sum(text)
  local sum = 0
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b = ch:byte()
    local v = GBA_CHAR[ch]
    if not v then
      if #ch == 1 and b >= 48 and b <= 57 then v = 0xA1 + (b - 48)
      elseif #ch == 1 and b >= 65 and b <= 90 then v = 0xBB + (b - 65)
      elseif #ch == 1 and b >= 97 and b <= 122 then v = 0xD5 + (b - 97)
      else v = 0 end
    end
    sum = sum + v
  end
  return sum
end

-- pokefirered/src/battle_main.c:1555
local function double_personalities(t)
  local Pokemon = require("src.core.game3.pokemon")
  local nameHash = 0
  local out = {}
  for i, m in ipairs(t.party or {}) do
    nameHash = (nameHash + gba_char_sum(t.name)) % 0x100000000
    nameHash = (nameHash + gba_char_sum(Pokemon.name(tonumber(m.species) or 0))) % 0x100000000
    out[i] = (0x80 + (nameHash * 256) % 0x100000000) % 0x100000000
  end
  return out
end
Trainers._doublePersonalities = double_personalities

--- Resolve a foe battler struct + full party for battle runtime.
-- Guarantees:
-- 1. Uniform Flat IV scaling: actualIv = (rawIv * 31) / 255 across all 6 stats
-- 2. Explicit Zero EVs across all stats (no residual player data)
-- 3. Correct custom moves and held items
function Trainers.foeFromId(trainerId)
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local t = Trainers.get(trainerId)
  if not t or not t.party or #t.party == 0 then
    return nil
  end

  local foeParty = {}
  local pers = t.doubleBattle and double_personalities(t) or {}
  for pi, m in ipairs(t.party) do
    local rawIv = tonumber(m.rawIv) or tonumber(m.iv) or 0
    local iv = tonumber(m.iv) or math.floor((rawIv * 31) / 255)
    local mon = {
      species = tonumber(m.species) or 1,
      level = tonumber(m.level) or 5,
      rawIv = rawIv,
      iv = iv,
      ivs = { hp = iv, atk = iv, def = iv, spa = iv, spd = iv, spe = iv },
      -- Trainer EVs are strictly zero
      evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
      heldItem = tonumber(m.heldItem) or nil,
      moves = m.moves,
      trainerId = trainerId,
      personality = pers[pi],
    }
    foeParty[#foeParty + 1] = mon
  end

  local lead = foeParty[1]
  return {
    species = lead.species,
    level = lead.level,
    rawIv = lead.rawIv,
    iv = lead.iv,
    ivs = lead.ivs,
    evs = lead.evs,
    heldItem = lead.heldItem,
    moves = lead.moves,
    personality = lead.personality,
    trainerId = trainerId,
    aiFlags = t.aiFlags,
    ai = t.ai,
    items = t.items,
    party = foeParty,
    trainerName = t.name,
    trainerClass = t.class,
    trainerClassName = t.className,
    trainerPic = t.pic,
    gender = t.gender,
    encounterMusic = t.encounterMusic,
    doubleBattle = t.doubleBattle,
  }
end

--- ROM-derived trainer presentation info (class / name / pic / partySize / dialogs).
-- opts.rivalName replaces placeholder "TERRY" for class RIVAL when provided.
function Trainers.info(trainerId, opts)
  opts = opts or {}
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local t = Trainers.get(trainerId)
  if not t then return nil end

  local info = {
    class = t.class,
    className = t.className,
    name = t.name,
    pic = t.pic,
    gender = t.gender,
    encounterMusic = t.encounterMusic,
    doubleBattle = t.doubleBattle,
    partySize = t.partySize or #t.party,
    lastLevel = t.lastLevel,
    aiFlags = t.aiFlags,
    ai = t.ai,
    items = t.items,
    party = t.party,
    dialogs = t.dialogs,
  }

  if info.className == "RIVAL" and opts.rivalName and opts.rivalName ~= "" then
    info.name = opts.rivalName
  end
  return info
end

--- Get dialog texts table: { intro, defeat, victory, notEnough }
function Trainers.dialogs(trainerId)
  local t = Trainers.get(trainerId)
  return t and t.dialogs or {}
end

--- FRLG intro string pieces for a trainer battle.
function Trainers.introStrings(trainerId, monName, opts)
  local info = Trainers.info(trainerId, opts) or {
    className = Strings("POKéMON TRAINER"),
    name = "",
  }
  local class = info.className or Strings("POKéMON TRAINER")
  local name = info.name or ""
  monName = monName or "POKéMON"
  if name ~= "" then
    return {
      wants = Strings("%s %s\nwould like to battle!", class, name),
      sentOut = Strings("%s %s sent\nout %s!", class, name, monName),
      info = info,
    }
  end
  return {
    wants = Strings("%s\nwould like to battle!", class),
    sentOut = Strings("%s sent\nout %s!", class, monName),
    info = info,
  }
end

--- Resolve encounter BGM song ID for a trainer (pret PlayTrainerEncounterMusic / include/constants/trainers.h & songs.h).
function Trainers.getEncounterMusic(trainerId)
  local t = Trainers.get(trainerId)
  if not t then return 285 end -- MUS_ENCOUNTER_BOY
  local musicCode = (tonumber(t.encounterMusic) or 0) % 128
  -- TRAINER_ENCOUNTER_MUSIC_FEMALE (1), GIRL (2), TWINS (9) -> MUS_ENCOUNTER_GIRL (284)
  -- TRAINER_ENCOUNTER_MUSIC_MALE (0), INTENSE (4), COOL (5), SWIMMER (8), ELITE_FOUR (10), HIKER (11), INTERVIEWER (12), RICH (13) -> MUS_ENCOUNTER_BOY (285)
  -- Default (SUSPICIOUS 3, AQUA 6, MAGMA 7, etc.) -> MUS_ENCOUNTER_ROCKET (283)
  if musicCode == 1 or musicCode == 2 or musicCode == 9 then
    return 284 -- MUS_ENCOUNTER_GIRL
  elseif musicCode == 3 or musicCode == 6 or musicCode == 7 then
    return 283 -- MUS_ENCOUNTER_ROCKET
  else
    return 285 -- MUS_ENCOUNTER_BOY
  end
end

-- pokefirered/src/pokemon.c:5850
function Trainers.getBattleMusicRole(trainerId)
  local t = Trainers.get(trainerId)
  local class = t and tonumber(t.class)
  if class == 90 then
    return "battleChampion", 299
  elseif class == 84 or class == 87 then
    return "battleGymLeader", 296
  end
  return "battleTrainer", 297
end

-- pokefirered/src/battle_main.c:3746
function Trainers.getVictoryMusicRole(trainerId)
  local t = Trainers.get(trainerId)
  local class = t and tonumber(t.class)
  if class == 84 or class == 90 then
    return "victoryGymLeader", 312
  end
  return "victoryTrainer", 310
end

return Trainers

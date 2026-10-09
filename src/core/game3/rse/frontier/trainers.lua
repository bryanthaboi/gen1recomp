local Rse = require("src.core.game3.rse.init")

local bit = rawget(_G, "bit") or require("bit")

local D = {}

D.MANIFEST = "data/generated/gba/rse/frontier/manifest.lua"
D.PACK_DIR = "data/generated/gba/frontier/"

-- pokeemerald/include/constants/battle_frontier.h:8
D.FACILITY = { TOWER = 0, DOME = 1, PALACE = 2, ARENA = 3, FACTORY = 4, PIKE = 5, PYRAMID = 6 }
D.NUM_FACILITIES = 7
-- pokeemerald/include/constants/battle_frontier.h:23
D.MODE = { SINGLES = 0, DOUBLES = 1, MULTIS = 2, LINK_MULTIS = 3 }
D.MODE_COUNT = 4
-- pokeemerald/include/constants/global.h:44
D.LVL = { L50 = 0, OPEN = 1, TENT = 2 }
D.LVL_MODE_COUNT = 2
-- pokeemerald/include/constants/battle_frontier.h:44
D.MAX_STREAK = 9999
D.MAX_BATTLE_FRONTIER_POINTS = 9999
D.FRONTIER_MAX_LEVEL_50 = 50
D.FRONTIER_MIN_LEVEL_OPEN = 60
D.STAGES_PER_CHALLENGE = 7
-- pokeemerald/include/constants/battle_tent.h:4
D.TENT_MIN_LEVEL = 30
D.TENT_STAGES_PER_CHALLENGE = 3
-- pokeemerald/include/constants/global.h:35
D.PARTY_SIZE = 3
D.DOUBLES_PARTY_SIZE = 4
D.MULTI_PARTY_SIZE = 2
D.MAX_PARTY_SIZE = 4
-- pokeemerald/include/constants/trainers.h:9
D.TRAINERS_COUNT = 300
D.TRAINER_RECORD_MIXING_FRIEND = 300
D.TRAINER_RECORD_MIXING_APPRENTICE = 400
D.TRAINER_EREADER = 500
D.TRAINER_FRONTIER_BRAIN = 1022
D.TRAINER_PLAYER = 1023
D.TRAINER_STEVEN_PARTNER = 3075
-- pokeemerald/include/constants/battle_frontier_mons.h:862
D.FRONTIER_MONS_HIGH_TIER = 849
-- pokeemerald/include/constants/battle_frontier_trainers.h:103
D.TRAINER_JILL, D.TRAINER_CHLOE, D.TRAINER_SOFIA, D.TRAINER_JAZLYN = 99, 119, 139, 159
D.TRAINER_ALISON, D.TRAINER_LAMAR, D.TRAINER_TESS = 179, 199, 219
-- pokeemerald/include/constants/battle_tent_trainers.h:97
D.NUM_BATTLE_TENT_TRAINERS = 30
-- pokeemerald/include/constants/battle_tent_mons.h:75
D.NUM_SLATEPORT_TENT_MONS = 70
-- pokeemerald/include/constants/pokemon.h:212
D.MAX_PER_STAT_IVS = 31
D.MAX_TOTAL_EVS = 510
D.MAX_FRIENDSHIP = 255
-- pokeemerald/src/frontier_util.c:2495
D.FRONTIER_BRAIN_OTID = 61226

local cache = {}

local function cacheKey(rel)
  local GameVersion = require("src.core.GameVersion")
  return tostring(GameVersion.get()) .. ":" .. rel
end

local function load(rel)
  local key = cacheKey(rel)
  local hit = cache[key]
  if hit then return hit end
  local src = require("src.core.game3.dataset").cache():read(rel)
  if type(src) ~= "string" then error("frontier: " .. rel .. " missing from the cache", 0) end
  local chunk = assert((loadstring or load)(src, "@" .. rel))
  if setfenv then setfenv(chunk, {}) end
  local t = chunk()
  cache[key] = t
  return t
end

function D.reset()
  cache = {}
end

function D.manifest()
  return load(D.MANIFEST)
end

function D.pack(name)
  return load(D.PACK_DIR .. name .. ".lua")
end

function D.constants(sess)
  local Constants = require("src.core.game3.constants")
  return Constants.of(Constants.versionOf(sess or Rse.session()))
end

function D.rng()
  return require("src.core.game3.rng")
end

-- pokeemerald/src/battle_tower.c:3328
function D.tentPack(facility)
  local tents = D.pack("tents")
  if facility == D.FACILITY.FACTORY then return tents.slateport end
  if facility == D.FACILITY.PALACE then return tents.verdanturf end
  if facility == D.FACILITY.ARENA then return tents.fallarbor end
  return nil
end

local function frontierSet()
  return { trainers = D.pack("trainers").trainers, mons = D.pack("mons").mons }
end

-- pokeemerald/src/battle_tower.c:3267
function D.highestPartyLevel(party)
  local best = 0
  for _, mon in ipairs(party or {}) do
    local sp = tonumber(mon.species or mon.speciesId) or 0
    if sp ~= 0 and not (mon.isEgg or mon.egg) then
      local lv = tonumber(mon.level) or 0
      if lv > best then best = lv end
    end
  end
  return best
end

-- pokeemerald/src/battle_tower.c:3247
function D.enemyLevel(lvlMode, party)
  if lvlMode == D.LVL.OPEN then
    local lv = D.highestPartyLevel(party)
    if lv < D.FRONTIER_MIN_LEVEL_OPEN then lv = D.FRONTIER_MIN_LEVEL_OPEN end
    return lv
  end
  return D.FRONTIER_MAX_LEVEL_50
end

-- pokeemerald/src/battle_tower.c:3233
function D.facilityPtrs(sess, facility)
  local f = sess.frontier or {}
  if f.lvlMode == D.LVL.TENT then
    local tent = D.tentPack(facility)
    local lv = D.highestPartyLevel(sess.party)
    if lv < D.TENT_MIN_LEVEL then lv = D.TENT_MIN_LEVEL end
    if tent then return { trainers = tent.trainers, mons = tent.mons }, lv end
    return frontierSet(), lv
  end
  return frontierSet(), D.enemyLevel(f.lvlMode, sess.party)
end

-- pokeemerald/src/battle_tower.c:3288
function D.fixedIvs(trainerId)
  if trainerId <= D.TRAINER_JILL then return 3 end
  if trainerId <= D.TRAINER_CHLOE then return 6 end
  if trainerId <= D.TRAINER_SOFIA then return 9 end
  if trainerId <= D.TRAINER_JAZLYN then return 12 end
  if trainerId <= D.TRAINER_ALISON then return 15 end
  if trainerId <= D.TRAINER_LAMAR then return 18 end
  if trainerId <= D.TRAINER_TESS then return 21 end
  return D.MAX_PER_STAT_IVS
end

-- pokeemerald/include/pokemon.h:292
function D.isShiny(otId, personality)
  local v = bit.bxor(bit.bxor(bit.rshift(otId, 16), bit.band(otId, 0xFFFF)),
    bit.bxor(bit.rshift(personality, 16), bit.band(personality, 0xFFFF)))
  return bit.band(v, 0xFFFF) < 8
end

local STAT_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
D.STAT_KEYS = STAT_KEYS

local function u32(v)
  v = tonumber(v) or 0
  if v < 0 then v = v + 4294967296 end
  return v % 4294967296
end

-- pokeemerald/src/pokemon.c:2195
function D.createMon(species, level, fixedIV, personality, otId, opts)
  opts = opts or {}
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryData = require("src.core.game3.summary_data")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  personality = u32(personality)
  otId = u32(otId)
  local meta = Pokemon.speciesMeta and Pokemon.speciesMeta(species)
  local growthRate = (meta and tonumber(meta.growthRate)) or 0
  local ivs = {}
  for _, k in ipairs(STAT_KEYS) do ivs[k] = fixedIV end
  local ability = Pokemon.abilityId and Pokemon.abilityId(species, personality) or 0
  local mon = {
    species = species,
    speciesId = species,
    speciesNumbering = Pokemon.NUMBERING_INTERNAL,
    name = Pokemon.name(species),
    nickname = "",
    level = level,
    metLevel = level,
    growthRate = growthRate,
    exp = SummaryData.expForLevel(growthRate, level),
    personality = personality,
    nature = Pokemon.natureId(personality),
    ivs = ivs,
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    ability = ability,
    abilityId = ability,
    abilityNum = (Pokemon.abilities(species)[2] or 0) ~= 0 and (personality % 2) or 0,
    gender = Pokemon.gender and Pokemon.gender(species, personality) or "U",
    friendship = (meta and meta.friendship) or 70,
    happiness = (meta and meta.friendship) or 70,
    otId = otId % 65536,
    otSecretId = math.floor(otId / 65536),
    otName = opts.otName or "",
    ot = opts.otName or "",
    otGender = opts.otGender or 0,
    pokeball = 4,
    pokerus = 0,
    moves = {},
    pp = {},
    maxPp = {},
  }
  if opts.moves then D.setMoves(mon, opts.moves) else
    local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
    mon.moves, mon.pp, mon.maxPp = moves or {}, pp or {}, maxPp or {}
  end
  Pokemon.applyStats(mon)
  mon.hp = mon.maxHp
  return mon
end

-- pokeemerald/src/pokemon.c:2974
function D.setMoves(mon, moves)
  local Pokemon = require("src.core.game3.pokemon")
  local out, pp, maxPp = {}, {}, {}
  for i = 1, 4 do
    local m = tonumber(moves[i]) or 0
    if m ~= 0 then
      out[#out + 1] = m
      maxPp[#out] = Pokemon.movePp(m) or 5
      pp[#out] = maxPp[#out]
    end
  end
  mon.moves, mon.pp, mon.maxPp = out, pp, maxPp
end

function D.setEvs(mon, list)
  for i, k in ipairs(STAT_KEYS) do mon.evs[k] = tonumber(list[i]) or 0 end
  local Pokemon = require("src.core.game3.pokemon")
  mon.hp = nil
  Pokemon.applyStats(mon)
  mon.hp = mon.maxHp
end

function D.setHeldItem(mon, item)
  if item == 0 then item = nil end
  mon.item, mon.heldItem = item, item
end

-- pokeemerald/src/pokemon.c:2562
function D.createMonEvSpread(species, level, nature, fixedIV, evSpread, otId)
  local Rng = D.rng()
  local personality
  repeat
    personality = u32(Rng.Random32())
  until personality % 25 == nature
  local mon = D.createMon(species, level, fixedIV, personality, otId)
  local count = 0
  for i = 0, 5 do
    if bit.band(evSpread, bit.lshift(1, i)) ~= 0 then count = count + 1 end
  end
  local evs = {}
  local amount = count > 0 and math.floor(D.MAX_TOTAL_EVS / count) or 0
  for i = 0, 5 do
    evs[i + 1] = (bit.band(evSpread, bit.lshift(1, i)) ~= 0) and amount or 0
  end
  D.setEvs(mon, evs)
  return mon
end

function D.heldItem(itemTableId)
  local items = D.pack("held_items").items
  return tonumber(items[(tonumber(itemTableId) or 0) + 1]) or 0
end

-- pokeemerald/src/battle_tower.c:1633
local function facilityMon(set, monId, level, fixedIV, otId, frustrationZeroes)
  local row = set.mons[monId]
  local mon = D.createMonEvSpread(row.species, level, row.nature, fixedIV, row.evSpread, otId)
  local friendship = D.MAX_FRIENDSHIP
  D.setMoves(mon, row.moves)
  for _, m in ipairs(row.moves) do
    if frustrationZeroes and D.isMove(m, "MOVE_FRUSTRATION") then friendship = 0 end
  end
  mon.friendship, mon.happiness = friendship, friendship
  D.setHeldItem(mon, D.heldItem(row.itemTableId))
  return mon
end
D.facilityMon = facilityMon

function D.isMove(id, name)
  return tonumber(id) == D.constants():require("moves", name)
end

local function listLen(set)
  local n = 0
  while set[n + 1] ~= nil do n = n + 1 end
  return n
end

-- pokeemerald/src/battle_tower.c:1633
function D.fillTrainerParty(sess, trainerId, firstMonId, monCount, party, opts)
  opts = opts or {}
  local facility = opts.facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  local set, level = D.facilityPtrs(sess, facility)
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local brain = D.brainParty(sess, facility, level)
    for i, mon in ipairs(brain) do party[firstMonId + i] = mon end
    return party
  end
  if trainerId >= D.TRAINERS_COUNT then
    return D.fillRecordParty(sess, trainerId, firstMonId, monCount, party, level)
  end
  local fixedIV = opts.fixedIV or D.fixedIvs(trainerId)
  local monSet = set.trainers[opts.setOwner or trainerId].monSet
  local count = listLen(monSet)
  local Rng = D.rng()
  local otId = u32(Rng.Random32())
  local chosen = {}
  local i = 0
  while i ~= monCount do
    local monId = monSet[(Rng.Random() % count) + 1]
    local ok = true
    if (level == D.FRONTIER_MAX_LEVEL_50 or level == 20) and monId > D.FRONTIER_MONS_HIGH_TIER and not opts.tent then
      ok = false
    end
    local row = set.mons[monId]
    if ok then
      for j = 1, i + firstMonId do
        local m = party[j]
        if m and tonumber(m.species) == row.species then ok = false break end
      end
    end
    if ok then
      local item = D.heldItem(row.itemTableId)
      for j = 1, i + firstMonId do
        local m = party[j]
        local held = m and (tonumber(m.heldItem) or 0) or 0
        if held ~= 0 and held == item then ok = false break end
      end
    end
    if ok then
      for j = 1, i do
        if chosen[j] == monId then ok = false break end
      end
    end
    if ok then
      chosen[i + 1] = monId
      party[i + firstMonId + 1] = facilityMon(set, monId, level, fixedIV, otId, true)
      i = i + 1
    end
  end
  return party
end

function D.fillRecordParty(sess, trainerId, firstMonId, monCount, party, level)
  local f = sess.frontier or {}
  if trainerId < D.TRAINER_RECORD_MIXING_APPRENTICE then
    local rec = f.towerRecords and f.towerRecords[trainerId - D.TRAINER_RECORD_MIXING_FRIEND + 1]
    local rows = rec and rec.party or {}
    for j = 1, monCount do
      local r = rows[j]
      if r and (tonumber(r.species) or 0) ~= 0 and (tonumber(r.level) or 0) <= level then
        party[firstMonId + j] = D.battleTowerMon(r, false, level)
      end
    end
  end
  return party
end

-- pokeemerald/src/pokemon.c:2468
function D.battleTowerMon(src, handleLevel, level)
  local lv = tonumber(src.level) or 50
  if handleLevel and level then lv = level end
  local mon = D.createMon(src.species, lv, 0, src.personality or 0, src.otId or 0, { moves = src.moves or {} })
  mon.ivs = {
    hp = src.hpIV or 0, atk = src.attackIV or 0, def = src.defenseIV or 0,
    spe = src.speedIV or 0, spa = src.spAttackIV or 0, spd = src.spDefenseIV or 0,
  }
  D.setEvs(mon, { src.hpEV, src.attackEV, src.defenseEV, src.speedEV, src.spAttackEV, src.spDefenseEV })
  D.setHeldItem(mon, tonumber(src.heldItem) or 0)
  if src.nickname and src.nickname ~= "" then mon.nickname = src.nickname end
  mon.friendship, mon.happiness = tonumber(src.friendship) or 255, tonumber(src.friendship) or 255
  return mon
end

-- pokeemerald/src/battle_tower.c:3382
function D.fillTentTrainerParty(sess, trainerId, firstMonId, monCount, party, facility)
  return D.fillTrainerParty(sess, trainerId, firstMonId, monCount, party,
    { facility = facility, fixedIV = 0, tent = true })
end

-- pokeemerald/src/frontier_util.c:2587
function D.brainSymbol(sess, facility)
  local Util = require("src.core.game3.rse.frontier.util")
  local symbol = Util.symbolCount(sess, facility)
  if symbol == 2 then
    local ap = D.manifest().brainStreakAppearances[facility + 1]
    local streak = Util.currentFacilityWinStreak(sess) + ap[4]
    if streak == ap[1] then symbol = 0
    elseif streak == ap[2] then symbol = 1
    elseif streak > ap[2] and (streak - ap[2]) % ap[3] == 0 then symbol = 1
    end
  end
  return symbol
end

-- pokeemerald/src/frontier_util.c:2497
function D.brainParty(sess, facility, level, selectedBits)
  local symbol = D.brainSymbol(sess, facility)
  local rows = D.pack("brains").mons[facility][symbol + 1]
  local Rng = D.rng()
  local out = {}
  selectedBits = selectedBits or 7
  for i = 0, D.PARTY_SIZE - 1 do
    if bit.band(selectedBits, bit.lshift(1, i)) ~= 0 then
      local row = rows[i + 1]
      local personality
      repeat
        repeat
          personality = u32(Rng.Random32())
        until not D.isShiny(D.FRONTIER_BRAIN_OTID, personality)
      until personality % 25 == row.nature
      local mon = D.createMon(row.species, level, row.fixedIV, personality, D.FRONTIER_BRAIN_OTID)
      D.setHeldItem(mon, row.heldItem)
      D.setEvs(mon, row.evs)
      local friendship = D.MAX_FRIENDSHIP
      D.setMoves(mon, row.moves)
      for _, m in ipairs(row.moves) do
        if D.isMove(m, "MOVE_FRUSTRATION") then friendship = 0 end
      end
      mon.friendship, mon.happiness = friendship, friendship
      out[#out + 1] = mon
    end
  end
  return out
end

local function trainersPack()
  return require("src.core.game3.scripting.trainers").pack() or {}
end

-- pokeemerald/src/battle_tower.c:1483
function D.facilityClass(sess, trainerId, facility)
  local f = sess.frontier or {}
  if trainerId == D.TRAINER_EREADER then
    return f.ereaderTrainer and tonumber(f.ereaderTrainer.facilityClass) or 0
  end
  if trainerId < D.TRAINERS_COUNT then
    local set = D.facilityPtrs(sess, facility or Rse.var("VAR_FRONTIER_FACILITY", sess))
    local row = set.trainers[trainerId]
    return row and row.facilityClass or 0
  end
  if trainerId < D.TRAINER_RECORD_MIXING_APPRENTICE then
    local rec = f.towerRecords and f.towerRecords[trainerId - D.TRAINER_RECORD_MIXING_FRIEND + 1]
    return rec and tonumber(rec.facilityClass) or 0
  end
  local app = sess.apprentices and sess.apprentices[trainerId - D.TRAINER_RECORD_MIXING_APPRENTICE + 1]
  local def = app and D.pack("apprentices").apprentices[tonumber(app.id) or 0]
  return def and def.facilityClass or 0
end

local function brainTrainer(sess, facility)
  local tid = D.pack("brains").trainerIds[facility + 1]
  return require("src.core.game3.scripting.trainers").get(tid)
end

-- pokeemerald/src/battle_tower.c:1514
function D.trainerName(sess, trainerId, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  local f = sess.frontier or {}
  if trainerId == D.TRAINER_EREADER then return f.ereaderTrainer and f.ereaderTrainer.name or "" end
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local t = brainTrainer(sess, facility)
    return t and t.name or ""
  end
  if trainerId == D.TRAINER_STEVEN_PARTNER then
    local C = D.constants(sess)
    local t = require("src.core.game3.scripting.trainers").get(C:require("trainers", "TRAINER_STEVEN"))
    return t and t.name or ""
  end
  if trainerId < D.TRAINERS_COUNT then
    local set = D.facilityPtrs(sess, facility)
    local row = set.trainers[trainerId]
    return row and row.name or ""
  end
  if trainerId < D.TRAINER_RECORD_MIXING_APPRENTICE then
    local rec = f.towerRecords and f.towerRecords[trainerId - D.TRAINER_RECORD_MIXING_FRIEND + 1]
    return rec and rec.name or ""
  end
  local app = sess.apprentices and sess.apprentices[trainerId - D.TRAINER_RECORD_MIXING_APPRENTICE + 1]
  local def = app and D.pack("apprentices").apprentices[tonumber(app.id) or 0]
  return def and def.name or ""
end

-- pokeemerald/src/battle_tower.c:1436
function D.opponentClass(sess, trainerId, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local t = brainTrainer(sess, facility)
    return t and t.class or 0
  end
  if trainerId == D.TRAINER_STEVEN_PARTNER then
    local C = D.constants(sess)
    local t = require("src.core.game3.scripting.trainers").get(C:require("trainers", "TRAINER_STEVEN"))
    return t and t.class or 0
  end
  local fc = D.facilityClass(sess, trainerId, facility)
  return trainersPack().facilityClassToTrainerClass[fc] or 0
end

-- pokeemerald/src/battle_tower.c:1404
function D.frontSpriteId(sess, trainerId, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local t = brainTrainer(sess, facility)
    return t and t.pic or 0
  end
  local fc = D.facilityClass(sess, trainerId, facility)
  return trainersPack().facilityClassToPic[fc] or 0
end

-- pokeemerald/src/pokemon.c:2057,4597-4605
function D.secretBaseTrainerInfo(facilityClass)
  local pack = trainersPack()
  facilityClass = tonumber(facilityClass) or 0
  return pack.facilityClassToTrainerClass and pack.facilityClassToTrainerClass[facilityClass] or 0,
    pack.facilityClassToPic and pack.facilityClassToPic[facilityClass] or 0
end

function D.className(sess, classId)
  local p = trainersPack()
  local names = p.classNames
  return names and names[classId] or ""
end

local function classIndex(list, fc)
  for i, v in ipairs(list) do
    if v == fc then return i end
  end
  return nil
end

-- pokeemerald/src/battle_tower.c:1575
function D.isFemale(sess, trainerId, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local row = D.manifest().brainObjEventGfx[facility + 1]
    return row[2] ~= 0
  end
  local fc = D.facilityClass(sess, trainerId, facility)
  return classIndex(D.pack("classes").towerFemale, fc) ~= nil
end

-- pokeemerald/src/battle_tower.c:3470
function D.facilityClassToGfx(fc)
  local classes = D.pack("classes")
  local man = D.manifest()
  local i = classIndex(classes.towerMale, fc)
  if i then return man.towerMaleGfx[i] end
  i = classIndex(classes.towerFemale, fc)
  if i then return man.towerFemaleGfx[i] end
  return D.constants():require("event_objects", "OBJ_EVENT_GFX_BOY_1")
end

-- pokeemerald/src/battle_tower.c:1258
function D.gfxId(sess, trainerId, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    return D.manifest().brainObjEventGfx[facility + 1][1]
  end
  return D.facilityClassToGfx(D.facilityClass(sess, trainerId, facility))
end

-- pokeemerald/src/battle_tower.c:1161
function D.setGfxVar(sess, trainerId, slot, facility)
  local names = { [0] = "VAR_OBJ_GFX_ID_0", [1] = "VAR_OBJ_GFX_ID_1", [15] = "VAR_OBJ_GFX_ID_E" }
  Rse.setVar(names[slot] or names[0], D.gfxId(sess, trainerId, facility), sess)
end

-- pokeemerald/src/battle_tower.c:1919
function D.speechToString(words)
  local Town = require("src.core.game3.rse.town_common")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local function lines(cols, rows)
    local out = {}
    for line in (Town.words(words or {}, cols, rows) .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
    return out
  end
  local l = lines(3, 2)
  local wide = false
  for _, line in ipairs(l) do
    if FrlgFont.measure(line) > 204 then wide = true end
  end
  if not wide then
    return { { t = "text", s = l[1] or "" }, { t = "nl" }, { t = "text", s = l[2] or "" }, { t = "eos" } }
  end
  l = lines(2, 3)
  return {
    { t = "text", s = l[1] or "" }, { t = "nl" }, { t = "text", s = l[2] or "" }, { t = "scroll" },
    { t = "text", s = l[3] or "" }, { t = "eos" },
  }
end

-- pokeemerald/src/frontier_util.c:1695
function D.trainerSpeech(sess, trainerId, which, facility)
  facility = facility or Rse.var("VAR_FRONTIER_FACILITY", sess)
  local f = sess.frontier or {}
  local keys = { [0] = "speechBefore", [1] = "speechWin", [2] = "speechLose" }
  if trainerId == D.TRAINER_FRONTIER_BRAIN then
    local symbol = D.brainSymbol(sess, facility)
    local tables = which == 2 and { "sFrontierBrainPlayerWonSilverTexts", "sFrontierBrainPlayerWonGoldTexts" }
      or { "sFrontierBrainPlayerLostSilverTexts", "sFrontierBrainPlayerLostGoldTexts" }
    local RomText = require("src.core.game3.rom_text")
    return RomText.ir(RomText.key(tables[symbol + 1], facility))
  end
  if trainerId == D.TRAINER_EREADER then
    local e = f.ereaderTrainer or {}
    local k = { [0] = "greeting", [1] = "farewellPlayerLost", [2] = "farewellPlayerWon" }
    return D.speechToString(e[k[which]])
  end
  if trainerId < D.TRAINERS_COUNT then
    local set = D.facilityPtrs(sess, facility)
    local row = set.trainers[trainerId]
    return D.speechToString(row and row[keys[which]])
  end
  if trainerId < D.TRAINER_RECORD_MIXING_APPRENTICE then
    local rec = f.towerRecords and f.towerRecords[trainerId - D.TRAINER_RECORD_MIXING_FRIEND + 1] or {}
    local k = { [0] = "greeting", [1] = "speechWon", [2] = "speechLost" }
    return D.speechToString(rec[k[which]])
  end
  local app = sess.apprentices and sess.apprentices[trainerId - D.TRAINER_RECORD_MIXING_APPRENTICE + 1] or {}
  if which == 1 then return D.speechToString(app.speechWon) end
  local def = D.pack("apprentices").apprentices[tonumber(app.id) or 0]
  return D.speechToString(def and def.speechLost)
end

-- pokeemerald/src/battle_setup.c:864
function D.specialTransition(sess, group, enemyParty)
  local man = D.manifest()
  local C = D.constants(sess)
  local enemyLevel = enemyParty and enemyParty[1] and tonumber(enemyParty[1].level) or 0
  local playerLevel = 0
  -- pokeemerald/src/battle_setup.c:721
  for _, mon in ipairs(sess.party or {}) do
    if not (mon.isEgg or mon.egg) and (tonumber(mon.species) or 0) ~= 0 and (tonumber(mon.hp) or 0) ~= 0 then
      playerLevel = tonumber(mon.level) or 0
      break
    end
  end
  local Rng = D.rng()
  local function pick(list) return list[(Rng.Random() % #list) + 1] end
  if group == "TRAINER_HILL" or group == "SECRET_BASE" or group == "E_READER" then
    return C:require("battle", enemyLevel < playerLevel and "B_TRANSITION_POKEBALLS_TRAIL" or "B_TRANSITION_BIG_POKEBALL")
  end
  if group == "B_PYRAMID" then return pick(man.transitions.pyramid) end
  if group == "B_DOME" then return pick(man.transitions.dome) end
  if Rse.var("VAR_FRONTIER_BATTLE_MODE", sess) ~= D.MODE.LINK_MULTIS then
    return pick(man.transitions.frontier)
  end
  local f = sess.frontier or {}
  local n = tonumber(f.curChallengeBattleNum) or 0
  local ids = f.trainerIds or {}
  local v = (tonumber(ids[n * 2 + 1]) or 0) + (tonumber(ids[n * 2 + 2]) or 0)
  return man.transitions.frontier[(v % #man.transitions.frontier) + 1]
end

return D

local Tower = {}

-- pokefirered/include/constants/trainer_tower.h:30
Tower.MAX_FLOORS = 8
-- pokefirered/include/constants/trainer_tower.h:32
Tower.MAX_TRAINERS_PER_FLOOR = 3
-- pokefirered/include/constants/trainer_tower.h:61
Tower.MAX_TIME = 215999
-- pokefirered/include/constants/trainer_tower.h:4
Tower.CHALLENGE_TYPE = { SINGLE = 0, DOUBLE = 1, KNOCKOUT = 2, MIXED = 3 }
Tower.NUM_CHALLENGE_TYPES = 4
-- pokefirered/include/constants/trainer_tower.h:10
Tower.CHALLENGE_STATUS = { LOST = 0, UNK = 1, NORMAL = 2 }
-- pokefirered/include/constants/trainer_tower.h:56
Tower.TEXT = { INTRO = 2, PLAYER_LOST = 3, PLAYER_WON = 4, AFTER = 5 }

-- pokefirered/include/constants/trainer_tower.h:34
Tower.FUNC = {
  INIT_FLOOR = 0,
  GET_SPEECH = 1,
  DO_BATTLE = 2,
  GET_CHALLENGE_TYPE = 3,
  CLEARED_FLOOR = 4,
  GET_FLOOR_CLEARED = 5,
  START_CHALLENGE = 6,
  GET_OWNER_STATE = 7,
  GIVE_PRIZE = 8,
  CHECK_FINAL_TIME = 9,
  RESUME_TIMER = 10,
  SET_LOST = 11,
  GET_CHALLENGE_STATUS = 12,
  GET_TIME = 13,
  SHOW_RESULTS = 14,
  CLOSE_RESULTS = 15,
  CHECK_DOUBLES = 16,
  GET_NUM_FLOORS = 17,
  SHOULD_WARP_TO_COUNTER = 18,
  ENCOUNTER_MUSIC = 19,
  GET_BEAT_CHALLENGE = 20,
}
Tower.FUNC_COUNT = 21

-- pokefirered/src/trainer_tower.c:364
Tower.PRIZE_ITEMS = {
  [0] = 63, 64, 65, 66, 67, 70, 179, 180, 185, 186, 187, 198, 199, 201, 218,
}

-- pokefirered/include/constants/event_objects.h:24
Tower.GFX_YOUNGSTER = 18
-- pokefirered/include/constants/songs.h:293
Tower.MUS_ENCOUNTER_BOY = 285

-- pokefirered/include/constants/layouts.h:286
Tower.LAYOUT_LOBBY = 297
Tower.LAYOUT_FIRST_FLOOR = 298
Tower.LAYOUT_ROOF = 306
-- pokefirered/include/constants/layouts.h:355
local LAYOUT_DOUBLES_FIRST = 366
-- pokefirered/include/constants/layouts.h:363
local LAYOUT_KNOCKOUT_FIRST = 374

-- pokefirered/include/constants/layouts.h:286
Tower.MAP_LAYOUT_ID = {
  FR_TRAINER_TOWER_LOBBY = 297,
  FR_TRAINER_TOWER_1F = 298,
  FR_TRAINER_TOWER_2F = 299,
  FR_TRAINER_TOWER_3F = 300,
  FR_TRAINER_TOWER_4F = 301,
  FR_TRAINER_TOWER_5F = 302,
  FR_TRAINER_TOWER_6F = 303,
  FR_TRAINER_TOWER_7F = 304,
  FR_TRAINER_TOWER_8F = 305,
  FR_TRAINER_TOWER_ROOF = 306,
  FR_TRAINER_TOWER_ELEVATOR = 307,
}

-- pokefirered/src/trainer_tower.c:353
local FLOOR_LAYOUTS = {}
for i = 0, Tower.MAX_FLOORS - 1 do
  FLOOR_LAYOUTS[i] = {
    [Tower.CHALLENGE_TYPE.SINGLE] = Tower.LAYOUT_FIRST_FLOOR + i,
    [Tower.CHALLENGE_TYPE.DOUBLE] = LAYOUT_DOUBLES_FIRST + i,
    [Tower.CHALLENGE_TYPE.KNOCKOUT] = LAYOUT_KNOCKOUT_FIRST + i,
  }
end
Tower.FLOOR_LAYOUTS = FLOOR_LAYOUTS

-- pokefirered/include/constants/global.h:78
Tower.PARTY_SIZE = 6
-- pokefirered/src/party_menu.c:413
Tower.SELECTED_ORDER_SIZE = 3

-- pokefirered/src/trainer_tower.c:400
local SINGLE_MON_IDXS = {
  [0] = { 0, 2 }, [1] = { 1, 3 }, [2] = { 2, 4 }, [3] = { 3, 5 },
  [4] = { 4, 1 }, [5] = { 5, 2 }, [6] = { 0, 3 }, [7] = { 1, 4 },
}
-- pokefirered/src/trainer_tower.c:412
local DOUBLE_MON_IDXS = {
  [0] = { 0, 1 }, [1] = { 1, 3 }, [2] = { 2, 0 }, [3] = { 3, 4 },
  [4] = { 4, 2 }, [5] = { 5, 2 }, [6] = { 0, 3 }, [7] = { 1, 5 },
}
-- pokefirered/src/trainer_tower.c:424
local KNOCKOUT_MON_IDXS = {
  [0] = { 0, 2, 4 }, [1] = { 1, 3, 5 }, [2] = { 2, 3, 1 }, [3] = { 3, 4, 0 },
  [4] = { 4, 1, 2 }, [5] = { 5, 0, 3 }, [6] = { 0, 5, 2 }, [7] = { 1, 4, 5 },
}
Tower.MON_IDXS = {
  [Tower.CHALLENGE_TYPE.SINGLE] = SINGLE_MON_IDXS,
  [Tower.CHALLENGE_TYPE.DOUBLE] = DOUBLE_MON_IDXS,
  [Tower.CHALLENGE_TYPE.KNOCKOUT] = KNOCKOUT_MON_IDXS,
}

-- pokefirered/src/trainer_tower_sets.c:8951
local NO_HEADER = { numFloors = Tower.MAX_FLOORS, id = 0 }

function Tower.cacheRel()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and type(Extract) == "table" and Extract.CACHE_ROOT) or "data/generated/gba"
  local okT, TowerExtract = pcall(require, "src.import.gba.trainer_tower_extract")
  local name = (okT and type(TowerExtract) == "table" and TowerExtract.CACHE_REL)
    or "trainer_tower.lua"
  return root .. "/" .. name
end

local function log(msg)
  if Tower._logged then return end
  Tower._logged = true
  print("[game3/trainer_tower] " .. tostring(msg))
end

local function log_once(key, msg)
  Tower._logKeys = Tower._logKeys or {}
  if Tower._logKeys[key] then return end
  Tower._logKeys[key] = true
  print("[game3/trainer_tower] " .. tostring(msg))
end
Tower.logOnce = log_once

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okC, cache = pcall(Dataset.cache)
    if okC and cache and cache.read then
      local okR, d = pcall(cache.read, cache, rel)
      if okR and type(d) == "string" and #d > 0 then return d end
    end
  end
  local okF, CacheFs = pcall(require, "src.import.CacheFs")
  if okF and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if type(love) == "table" and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if type(d) == "string" and #d > 0 then return d end
  end
  return nil
end

local function load_pack()
  if Tower._pack ~= nil then return Tower._pack or nil end
  local rel = Tower.cacheRel()
  local src = read_bytes(rel)
  if type(src) == "string" and #src > 0 then
    local chunk = (load or loadstring)(src, "@" .. rel, "t", {})
    local ok, pack = pcall(chunk)
    if chunk and ok and type(pack) == "table" then
      Tower._pack = pack
      return pack
    end
  end
  log("no " .. rel .. " in cache; the tower has no floor set")
  Tower._pack = false
  return nil
end

function Tower.resetPack()
  Tower._pack = nil
  Tower._header = nil
  Tower._logged = nil
  Tower._logKeys = nil
end

function Tower.setPack(pack)
  Tower.resetPack()
  Tower._pack = (type(pack) == "table") and pack or false
  return Tower._pack or nil
end

function Tower.pack()
  return load_pack()
end

-- pokefirered/src/trainer_tower.c:527
function Tower.header()
  local pack = load_pack()
  local h = pack and (pack.header or pack.localHeader)
  if type(h) ~= "table" then return NO_HEADER end
  local cached = Tower._header
  if cached and cached._src == h then return cached end
  cached = {
    numFloors = tonumber(h.numFloors) or NO_HEADER.numFloors,
    id = tonumber(h.id) or NO_HEADER.id,
    _src = h,
  }
  Tower._header = cached
  return cached
end

function Tower.normalizeMode(mode)
  mode = tonumber(mode) or 0
  -- pokefirered/src/trainer_tower.c:772
  if mode < 0 or mode >= Tower.NUM_CHALLENGE_TYPES then mode = 0 end
  return math.floor(mode)
end

-- pokefirered/src/trainer_tower.c:529
function Tower.floors(mode)
  mode = Tower.normalizeMode(mode)
  local pack = load_pack()
  local rows = pack and pack.floors and (pack.floors[mode] or pack.floors[tostring(mode)])
  if type(rows) ~= "table" or type(rows[1]) ~= "table" then
    log_once("no-floors", "gTrainerTowerFloors is not in this cache; the tower has no floor set")
    return nil
  end
  return rows
end

-- pokefirered/src/trainer_tower.c:22
function Tower.floor(mode, floorIdx)
  floorIdx = tonumber(floorIdx) or 0
  if floorIdx < 0 or floorIdx >= Tower.MAX_FLOORS then return nil end
  local rows = Tower.floors(mode)
  return rows and rows[floorIdx + 1] or nil
end

local function session_of()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end
Tower.sessionOf = session_of

-- pokefirered/include/global.h:693
local RECORD_DEFAULTS = {
  timer = 0,
  bestTime = Tower.MAX_TIME,
  floorsCleared = 0,
  spokeToOwner = false,
  receivedPrize = false,
  checkedFinalTime = false,
  hasLost = false,
  statusUnk = false,
  validated = false,
  setId = 0,
}

function Tower.newRecord()
  local rec = {}
  for key, value in pairs(RECORD_DEFAULTS) do rec[key] = value end
  return rec
end

function Tower.newState()
  local records = {}
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    records[mode + 1] = Tower.newRecord()
  end
  return { challengeId = 0, records = records, timerRunning = false }
end

local function normalize_record(rec)
  if type(rec) ~= "table" then return Tower.newRecord() end
  for key, value in pairs(RECORD_DEFAULTS) do
    local have = rec[key]
    if type(value) == "boolean" then
      rec[key] = have and true or false
    else
      rec[key] = tonumber(have) or value
    end
  end
  return rec
end

function Tower.state(session)
  session = session or session_of()
  if type(session) ~= "table" then return Tower.newState() end
  local mod = session.modData
  if type(mod) ~= "table" then
    mod = {}
    session.modData = mod
  end
  local state = session.trainerTower
  if type(state) ~= "table" then state = mod.trainerTower end
  if type(state) ~= "table" then state = Tower.newState() end
  state.challengeId = Tower.normalizeMode(state.challengeId)
  if type(state.records) ~= "table" then state.records = {} end
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    state.records[mode + 1] = normalize_record(state.records[mode + 1])
  end
  state.timerRunning = state.timerRunning and true or false
  session.trainerTower = state
  mod.trainerTower = state
  return state
end

-- pokefirered/src/trainer_tower.c:23
function Tower.record(session, mode)
  local state = Tower.state(session)
  if mode == nil then mode = state.challengeId end
  return state.records[Tower.normalizeMode(mode) + 1], state
end

function Tower.getChallengeId(session)
  return Tower.state(session).challengeId
end

-- pokefirered/src/trainer_tower.c:771
function Tower.setChallengeId(session, mode)
  local state = Tower.state(session)
  state.challengeId = Tower.normalizeMode(mode)
  return state.challengeId
end

-- pokefirered/src/trainer_tower.c:1044
function Tower.validateRecord(session, mode)
  local rec = Tower.record(session, mode)
  local id = Tower.header().id
  if rec.setId ~= id then
    rec.setId = id
    rec.bestTime = Tower.MAX_TIME
    rec.receivedPrize = false
  end
  return rec
end

-- pokefirered/src/trainer_tower.c:1077
function Tower.bestTime(session, mode)
  return tonumber(Tower.record(session, mode).bestTime) or Tower.MAX_TIME
end

-- pokefirered/src/trainer_tower.c:1082
function Tower.setBestTime(session, value, mode)
  local rec = Tower.record(session, mode)
  rec.bestTime = math.max(0, math.floor(tonumber(value) or Tower.MAX_TIME))
  return rec.bestTime
end

-- pokefirered/src/trainer_tower.c:1087
function Tower.resetResults(session)
  local state = Tower.state(session)
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    state.records[mode + 1].bestTime = Tower.MAX_TIME
  end
  return state
end

function Tower.layoutIdForMap(mapId)
  return Tower.MAP_LAYOUT_ID[mapId or ""]
end

-- pokefirered/src/trainer_tower.c:521
function Tower.floorIndexForMap(mapId)
  local layoutId = Tower.layoutIdForMap(mapId)
  if not layoutId then return nil end
  return layoutId - Tower.LAYOUT_FIRST_FLOOR
end

-- pokefirered/src/trainer_tower.c:546
function Tower.isPastFinalFloor(mapId)
  local layoutId = Tower.layoutIdForMap(mapId)
  if not layoutId then return false end
  return (layoutId - Tower.LAYOUT_LOBBY) > Tower.header().numFloors
end

-- pokefirered/src/trainer_tower.c:553
function Tower.floorLayoutFor(floorIdx, challengeType)
  local row = FLOOR_LAYOUTS[tonumber(floorIdx) or -1]
  if not row then return nil end
  return row[tonumber(challengeType) or -1]
end

-- pokefirered/src/trainer_tower.c:799
function Tower.prizeItem(session, mode)
  local state = Tower.state(session)
  if mode == nil then mode = state.challengeId end
  local floors = Tower.floors(mode)
  if not floors then return nil end
  return Tower.PRIZE_ITEMS[floors[1].prize] or Tower.PRIZE_ITEMS[0]
end

-- pokefirered/src/trainer_tower.c:485
function Tower.isTimerRunning(session)
  return Tower.state(session).timerRunning == true
end

local function stop_task()
  local id = Tower._taskId
  Tower._taskId = nil
  if not id then return end
  local okT, Task = pcall(require, "src.core.game3.task")
  if okT and Task and Task.cancel then pcall(Task.cancel, id) end
end

local function start_task()
  if Tower._taskId then return end
  local okT, Task = pcall(require, "src.core.game3.task")
  if not (okT and Task and Task.spawn) then return end
  local task = Task.spawn(function()
    local session = session_of()
    local state = session and Tower.state(session)
    if not (state and state.timerRunning) then
      Tower._taskId = nil
      return true
    end
    -- pokefirered/src/trainer_tower.c:485 SetVBlankCounter1Ptr
    local rec = state.records[state.challengeId + 1]
    rec.timer = rec.timer + 1
    return false
  end)
  Tower._taskId = task and task.id or nil
end

-- pokefirered/src/trainer_tower.c:485
function Tower.setTimerRunning(session, on)
  local state = Tower.state(session)
  state.timerRunning = on and true or false
  stop_task()
  if state.timerRunning then start_task() end
  return state.timerRunning
end

-- pokefirered/src/trainer_tower.c:769
function Tower.startChallenge(session, mode)
  local state = Tower.state(session)
  state.challengeId = Tower.normalizeMode(mode)
  Tower.validateRecord(session, state.challengeId)
  local rec = state.records[state.challengeId + 1]
  rec.validated = true
  rec.floorsCleared = 0
  rec.timer = 0
  rec.spokeToOwner = false
  rec.checkedFinalTime = false
  Tower.setTimerRunning(session, true)
  return rec
end

-- pokefirered/src/trainer_tower.c:838
function Tower.resumeTimer(session)
  local rec = Tower.record(session)
  if rec.spokeToOwner then return rec end
  if rec.timer >= Tower.MAX_TIME then
    rec.timer = Tower.MAX_TIME
    Tower.setTimerRunning(session, false)
  else
    Tower.setTimerRunning(session, true)
  end
  return rec
end

-- pokefirered/src/trainer_tower.c:888
function Tower.readTime(session)
  local rec = Tower.record(session)
  if rec.timer >= Tower.MAX_TIME then
    Tower.setTimerRunning(session, false)
    rec.timer = Tower.MAX_TIME
  end
  return rec.timer
end

-- pokefirered/src/trainer_tower.c:872
function Tower.formatTime(frames)
  frames = math.max(0, math.floor(tonumber(frames) or 0))
  local minutes = math.floor(frames / (60 * 60))
  frames = frames % (60 * 60)
  local seconds = math.floor(frames / 60)
  frames = frames % 60
  local centiseconds = math.floor(frames * 168 / 100)
  return string.format("%2d", minutes),
    string.format("%2d", seconds),
    string.format("%02d", centiseconds)
end

-- pokefirered/src/trainer_tower.c:753
function Tower.addFloorCleared(session)
  local rec = Tower.record(session)
  rec.floorsCleared = rec.floorsCleared + 1
  return rec.floorsCleared
end

-- pokefirered/src/trainer_tower.c:759
function Tower.isFloorAlreadyCleared(session, mapId)
  local layoutId = Tower.layoutIdForMap(mapId)
  if not layoutId then return true end
  local state = Tower.state(session)
  local rec = state.records[state.challengeId + 1]
  local floor = Tower.floor(state.challengeId, layoutId - Tower.LAYOUT_FIRST_FLOOR)
  local floorIdx = floor and floor.floorIdx or Tower.MAX_FLOORS
  if (layoutId - Tower.LAYOUT_FIRST_FLOOR) == rec.floorsCleared
    and (layoutId - Tower.LAYOUT_LOBBY) <= floorIdx then
    return false
  end
  return true
end

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deep_copy(v) end
  return out
end

local function save_block(session)
  if type(session) ~= "table" then return nil end
  if type(session.modData) ~= "table" then session.modData = {} end
  return session.modData
end

-- pokefirered/src/load_save.c:160
function Tower.savePlayerParty(session)
  session = session or session_of()
  local block = save_block(session)
  if not block then return nil end
  local saved = {}
  for i = 1, Tower.PARTY_SIZE do
    local mon = session.party and session.party[i]
    if mon ~= nil then saved[i] = deep_copy(mon) end
  end
  block.savedPlayerParty = saved
  session.savedPlayerParty = saved
  return saved
end

-- pokefirered/src/load_save.c:170
function Tower.loadPlayerParty(session)
  session = session or session_of()
  local block = save_block(session)
  local saved = session and (session.savedPlayerParty or (block and block.savedPlayerParty))
  if type(saved) ~= "table" then
    log_once("no-saved-party", "LoadPlayerParty with no stashed party; the party is left alone")
    return nil
  end
  local party = {}
  for i = 1, Tower.PARTY_SIZE do
    if saved[i] ~= nil then party[i] = deep_copy(saved[i]) end
  end
  session.party = party
  session.savedPlayerParty = saved
  if block then block.savedPlayerParty = saved end
  return party
end

function Tower.savedPlayerParty(session)
  session = session or session_of()
  local block = save_block(session)
  return session and (session.savedPlayerParty or (block and block.savedPlayerParty)) or nil
end

-- pokefirered/src/party_menu.c:413
function Tower.selectedOrder(session)
  session = session or session_of()
  local block = save_block(session)
  local order = session and (session.selectedOrderFromParty or (block and block.selectedOrderFromParty))
  if type(order) ~= "table" then order = {} end
  for i = 1, Tower.SELECTED_ORDER_SIZE do
    order[i] = math.floor(tonumber(order[i]) or 0)
  end
  if session then
    session.selectedOrderFromParty = order
    if block then block.selectedOrderFromParty = order end
  end
  return order
end

-- pokefirered/src/party_menu.c:5674
function Tower.battleEntryEligible(mon)
  if type(mon) ~= "table" then return false end
  local species = tonumber(mon.species or mon.speciesId) or 0
  if species == 0 or species == 412 then return false end
  if mon.isEgg or mon.egg then return false end
  -- pokefirered/src/party_menu.c:5687 CHOOSE_MONS_FOR_CABLE_CLUB_BATTLE
  if (tonumber(mon.hp) or 0) == 0 then return false end
  return true
end

-- pokefirered/src/party_menu.c:3780
function Tower.setSelectedOrder(session, picks)
  session = session or session_of()
  local order = Tower.selectedOrder(session)
  for i = 1, Tower.SELECTED_ORDER_SIZE do order[i] = 0 end
  local party = (session and session.party) or {}
  local slots = {}
  if type(picks) == "number" then
    slots[1] = math.floor(picks) + 1
  elseif type(picks) == "table" then
    for _, slot in ipairs(picks) do slots[#slots + 1] = math.floor(tonumber(slot) or 0) end
  end
  local n = 0
  for _, slot in ipairs(slots) do
    if n < Tower.SELECTED_ORDER_SIZE and slot >= 1 and slot <= Tower.PARTY_SIZE
      and Tower.battleEntryEligible(party[slot]) then
      local dup = false
      for i = 1, n do
        if order[i] == slot then dup = true end
      end
      if not dup then
        n = n + 1
        order[n] = slot
      end
    end
  end
  return order
end

-- pokefirered/src/party_menu.c:5659
function Tower.clearSelectedOrder(session)
  return Tower.setSelectedOrder(session, nil)
end

-- pokefirered/src/script_pokemon_util.c:197
function Tower.reducePartyToThree(session)
  session = session or session_of()
  if type(session) ~= "table" then return nil end
  local order = Tower.selectedOrder(session)
  local source = session.party or {}
  local party = {}
  for i = 1, Tower.SELECTED_ORDER_SIZE do
    local slot = order[i]
    if slot ~= 0 and source[slot] ~= nil then party[#party + 1] = source[slot] end
  end
  session.party = party
  return party
end

-- pokefirered/src/trainer_tower.c:1026
function Tower.partyMaxLevel(session)
  session = session or session_of()
  local top = 0
  for _, mon in ipairs((session and session.party) or {}) do
    local species = tonumber(mon.species or mon.speciesId) or 0
    if species ~= 0 and not mon.isEgg and not mon.egg then
      local level = tonumber(mon.level) or 0
      if level > top then top = level end
    end
  end
  return top
end

-- pokefirered/src/pokemon.c:1973
function Tower.battleTowerMon(src, level)
  if type(src) ~= "table" then return nil end
  local moves = {}
  for i = 1, 4 do
    local move = tonumber(src.moves and src.moves[i]) or 0
    if move ~= 0 then moves[#moves + 1] = move end
  end
  local iv = {
    hp = tonumber(src.hpIV) or 0,
    atk = tonumber(src.attackIV) or 0,
    def = tonumber(src.defenseIV) or 0,
    spe = tonumber(src.speedIV) or 0,
    spa = tonumber(src.spAttackIV) or 0,
    spd = tonumber(src.spDefenseIV) or 0,
  }
  return {
    species = tonumber(src.species) or 1,
    level = tonumber(level) or tonumber(src.level) or 5,
    heldItem = tonumber(src.heldItem),
    moves = (#moves > 0) and moves or nil,
    ppBonuses = tonumber(src.ppBonuses) or 0,
    iv = iv.hp,
    ivs = iv,
    evs = {
      hp = tonumber(src.hpEV) or 0,
      atk = tonumber(src.attackEV) or 0,
      def = tonumber(src.defenseEV) or 0,
      spe = tonumber(src.speedEV) or 0,
      spa = tonumber(src.spAttackEV) or 0,
      spd = tonumber(src.spDefenseEV) or 0,
    },
    personality = tonumber(src.personality) or 0,
    abilityNum = tonumber(src.abilityNum) or 0,
    friendship = tonumber(src.friendship) or 0,
    otId = tonumber(src.otId) or 0,
    nickname = type(src.nickname) == "string" and src.nickname or nil,
    trainerId = 0,
  }
end

-- pokefirered/src/trainer_tower.c:988
function Tower.buildEnemyParty(session, floor, trainerIdx)
  session = session or session_of()
  if type(floor) ~= "table" or type(floor.trainers) ~= "table" then return nil end
  trainerIdx = math.floor(tonumber(trainerIdx) or 0)
  local level = Tower.partyMaxLevel(session)
  local rec = Tower.record(session)
  local floorIdx = math.max(0, math.min(Tower.MAX_FLOORS - 1, rec.floorsCleared))
  local idxs = (Tower.MON_IDXS[floor.challengeType] or SINGLE_MON_IDXS)[floorIdx]
  local mons = {}
  if floor.challengeType == Tower.CHALLENGE_TYPE.DOUBLE then
    for i = 1, 2 do
      local trainer = floor.trainers[i]
      local src = trainer and trainer.mons and trainer.mons[(idxs[i] or 0) + 1]
      mons[#mons + 1] = Tower.battleTowerMon(src, level)
    end
  elseif floor.challengeType == Tower.CHALLENGE_TYPE.KNOCKOUT then
    local trainer = floor.trainers[trainerIdx + 1]
    local src = trainer and trainer.mons and trainer.mons[(idxs[trainerIdx + 1] or 0) + 1]
    mons[#mons + 1] = Tower.battleTowerMon(src, level)
  else
    local trainer = floor.trainers[trainerIdx + 1]
    for i = 1, 2 do
      local src = trainer and trainer.mons and trainer.mons[(idxs[i] or 0) + 1]
      mons[#mons + 1] = Tower.battleTowerMon(src, level)
    end
  end
  for i = #mons, 1, -1 do
    if mons[i] == nil then table.remove(mons, i) end
  end
  if #mons == 0 then return nil end
  return mons
end

-- pokefirered/src/trainer_tower.c:457
function Tower.facilityClassPic(facilityClass)
  facilityClass = tonumber(facilityClass)
  if not facilityClass then return nil end
  local pack = load_pack()
  local pics = pack and pack.facilityClassPic
  return type(pics) == "table" and tonumber(pics[facilityClass]) or nil
end

-- pokefirered/src/trainer_tower.c:733
function Tower.battleFoe(session, floor, trainerIdx)
  local mons = Tower.buildEnemyParty(session, floor, trainerIdx)
  if not mons then return nil end
  local trainer = floor.trainers[math.floor(tonumber(trainerIdx) or 0) + 1] or floor.trainers[1]
  local lead = mons[1]
  local foe = {
    party = mons,
    -- pokefirered/src/trainer_tower.c:740 TRAINER_NONE
    trainerId = 0,
    trainerName = trainer and trainer.name or nil,
    trainerClass = trainer and tonumber(trainer.facilityClass) or nil,
    -- pokefirered/src/trainer_tower.c:457 GetTrainerTowerTrainerFrontSpriteId
    trainerPicId = Tower.facilityClassPic(trainer and trainer.facilityClass),
    doubleBattle = floor.challengeType == Tower.CHALLENGE_TYPE.DOUBLE,
  }
  for _, key in ipairs({ "species", "level", "iv", "ivs", "evs", "heldItem", "moves", "personality" }) do
    foe[key] = lead[key]
  end
  return foe
end

-- pokefirered/src/battle_tower.c:1354 ValidateEReaderTrainer
function Tower.ereaderTrainer(session)
  session = session or session_of()
  local block = save_block(session)
  local trainer = session and (session.ereaderTrainer or (block and block.ereaderTrainer))
  if type(trainer) ~= "table" then return nil end
  -- pokefirered/src/battle_tower.c:1368 an all-zero record is no trainer at all
  local rows = trainer.party
  if type(rows) ~= "table" or type(rows[1]) ~= "table" then
    -- pokefirered/src/battle_tower.c:1392 ClearEReaderTrainer
    if session then session.ereaderTrainer = nil end
    if block then block.ereaderTrainer = nil end
    return nil
  end
  return trainer
end

-- pokefirered/src/battle_tower.c:927
function Tower.ereaderFoe(session)
  session = session or session_of()
  local trainer = Tower.ereaderTrainer(session)
  local rows = type(trainer) == "table" and trainer.party or nil
  if type(rows) ~= "table" then return nil end
  local mons = {}
  for i = 1, 3 do
    local mon = Tower.battleTowerMon(rows[i])
    if mon then mons[#mons + 1] = mon end
  end
  if #mons == 0 then return nil end
  local lead = mons[1]
  local foe = {
    party = mons,
    trainerId = 0,
    trainerName = trainer.name,
    trainerClass = tonumber(trainer.facilityClass),
    -- pokefirered/src/battle_tower.c:1335 GetEreaderTrainerFrontSpriteId
    trainerPicId = Tower.facilityClassPic(trainer.facilityClass),
  }
  for _, key in ipairs({ "species", "level", "iv", "ivs", "evs", "heldItem", "moves", "personality" }) do
    foe[key] = lead[key]
  end
  return foe
end

-- pokefirered/src/battle_tower.c:915
function Tower.copyHeldItems(session, toSaved)
  session = session or session_of()
  local saved = Tower.savedPlayerParty(session)
  if type(saved) ~= "table" then return false end
  local party = (session and session.party) or {}
  for i = 1, Tower.PARTY_SIZE do
    local from = toSaved and party[i] or saved[i]
    local into = toSaved and saved[i] or party[i]
    if type(from) == "table" and type(into) == "table" then
      into.heldItem = from.heldItem
    end
  end
  return true
end

-- pokefirered/src/trainer_tower.c:937
function Tower.numFloorsResult(mode)
  local header = Tower.header()
  local floors = Tower.floors(mode)
  local floorIdx = floors and floors[1].floorIdx or Tower.MAX_FLOORS
  if header.numFloors ~= floorIdx then
    return true, header.numFloors
  end
  return false, header.numFloors
end

return Tower

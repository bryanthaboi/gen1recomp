local Rse = require("src.core.game3.rse.init")
local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")

local bit = rawget(_G, "bit") or require("bit")

local Tower = {}

-- pokeemerald/include/constants/battle_tower.h:4
Tower.FUNC = {
  INIT = 0, GET_DATA = 1, SET_DATA = 2, SET_OPPONENT = 3, SET_BATTLE_WON = 4, GIVE_RIBBONS = 5, SAVE = 6,
  GET_OPPONENT_INTRO = 7, NOP = 8, NOP2 = 9, LOAD_PARTNERS = 10, PARTNER_MSG = 11, LOAD_LINK_OPPONENTS = 12,
  TRY_CLOSE_LINK = 13, SET_PARTNER_GFX = 14, SET_INTERVIEW_DATA = 15,
}
-- pokeemerald/include/constants/battle_tower.h:21
Tower.DATA = { WIN_STREAK = 1, WIN_STREAK_ACTIVE = 2, LVL_MODE = 3 }
-- pokeemerald/include/constants/battle_tower.h:26
Tower.PARTNER_MSGID = { INTRO = 0, MON1 = 1, MON2_ASK = 2, ACCEPT = 3, REJECT = 4 }
-- pokeemerald/include/constants/battle_frontier.h:36
Tower.SPECIAL_BATTLE = {
  TOWER = 0, SECRET_BASE = 1, EREADER = 2, DOME = 3, PALACE = 4, ARENA = 5, FACTORY = 6, PIKE_SINGLE = 7,
  STEVEN = 8, PIKE_DOUBLE = 9, PYRAMID = 10,
}

local F = D.FACILITY
local M = D.MODE

local function var(name, sess) return Rse.var(name, sess) end
local function specialVar(ctx, id) return Rse.specialVar(ctx, id) end
local function setResult(ctx, v) Util.setResult(ctx, v) end

local function modeLvl(sess)
  local f = Util.frontier(sess)
  return var("VAR_FRONTIER_BATTLE_MODE", sess), f.lvlMode
end

-- pokeemerald/src/battle_tower.c:2742
function Tower.currentWinStreak(sess, lvl, mode)
  local f = Util.frontier(sess)
  local v = Util.get2(f.towerWinStreaks, mode, lvl)
  if v > D.MAX_STREAK then v = D.MAX_STREAK end
  return v
end

local function streakFlag(mode, lvl)
  return D.manifest().winStreakFlags[mode + 1][lvl + 1]
end

-- pokeemerald/src/battle_tower.c:906
function Tower.init(sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  f.challengeStatus = Util.CHALLENGE_STATUS.SAVING
  f.curChallengeBattleNum = 0
  f.challengePaused = 0
  f.disableRecordBattle = 0
  Util.resetTrainerIds(sess)
  if bit.band(tonumber(f.winStreakActiveFlags) or 0, streakFlag(mode, lvl)) == 0 then
    Util.set2(f.towerWinStreaks, mode, lvl, 0)
  end
  sess.dynamicWarp = { map = sess.map, warpId = 0xFF, x = sess.x, y = sess.y }
  sess.frontierOpponentA = 0
end

-- pokeemerald/src/battle_tower.c:924
function Tower.getData(ctx, sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local which = specialVar(ctx, Util.VAR_0x8005)
  if which == Tower.DATA.WIN_STREAK then
    setResult(ctx, Tower.currentWinStreak(sess, lvl, mode))
  elseif which == Tower.DATA.WIN_STREAK_ACTIVE then
    setResult(ctx, bit.band(tonumber(f.winStreakActiveFlags) or 0, streakFlag(mode, lvl)) ~= 0 and 1 or 0)
  elseif which == Tower.DATA.LVL_MODE then
    f.towerLvlMode = f.lvlMode
  end
end

-- pokeemerald/src/battle_tower.c:945
function Tower.setData(ctx, sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local which = specialVar(ctx, Util.VAR_0x8005)
  local v = specialVar(ctx, Util.VAR_0x8006)
  if which == Tower.DATA.WIN_STREAK then
    Util.set2(f.towerWinStreaks, mode, lvl, v)
  elseif which == Tower.DATA.WIN_STREAK_ACTIVE then
    local flags = tonumber(f.winStreakActiveFlags) or 0
    if v ~= 0 then
      f.winStreakActiveFlags = bit.bor(flags, streakFlag(mode, lvl))
    else
      f.winStreakActiveFlags = bit.band(flags, bit.bnot(streakFlag(mode, lvl)))
    end
    if f.winStreakActiveFlags < 0 then f.winStreakActiveFlags = f.winStreakActiveFlags + 4294967296 end
  elseif which == Tower.DATA.LVL_MODE then
    f.towerLvlMode = f.lvlMode
  end
end

-- pokeemerald/src/battle_tower.c:2137
function Tower.saveCurrentWinStreak(sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local ws = Tower.currentWinStreak(sess, lvl, mode)
  if Util.get2(f.towerWinStreaks, mode, lvl) < ws then Util.set2(f.towerWinStreaks, mode, lvl, ws) end
end

-- pokeemerald/src/battle_tower.c:969
function Tower.setBattleWon(ctx, sess)
  local f = Util.frontier(sess)
  if sess.frontierOpponentA == D.TRAINER_EREADER then f.ereaderTrainer = {} end
  if (tonumber(f.towerNumWins) or 0) < D.MAX_STREAK then f.towerNumWins = (tonumber(f.towerNumWins) or 0) + 1 end
  f.curChallengeBattleNum = (tonumber(f.curChallengeBattleNum) or 0) + 1
  Tower.saveCurrentWinStreak(sess)
  setResult(ctx, f.curChallengeBattleNum)
end

-- pokeemerald/src/battle_tower.c:1104
function Tower.randomScaledTrainerId(challengeNum, battleNum)
  local classes = D.pack("classes")
  local Rng = D.rng()
  local range
  if challengeNum <= 7 then
    if battleNum == D.STAGES_PER_CHALLENGE - 1 then
      range = classes.trainerIdRangesHard[challengeNum + 1]
    else
      range = classes.trainerIdRanges[challengeNum + 1]
    end
  else
    range = classes.trainerIdRanges[8]
  end
  local n = range[2] - range[1] + 1
  return range[1] + (Rng.Random() % n)
end

-- pokeemerald/src/battle_tower.c:983
function Tower.chooseSpecialTrainer(sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  if var("VAR_FRONTIER_FACILITY", sess) ~= F.TOWER then return false end
  local ws = Tower.currentWinStreak(sess, lvl, mode)
  local ids = {}
  local sizes = D.manifest().towerPartySizes
  for i = 1, Util.BATTLE_TOWER_RECORD_COUNT do
    local rec = f.towerRecords[i]
    if type(rec) == "table" and next(rec) ~= nil and rec.checksumValid ~= false then
      local valid = 0
      for _, mon in ipairs(rec.party or {}) do
        if (tonumber(mon.species) or 0) ~= 0 and (tonumber(mon.level) or 0) <= D.enemyLevel(lvl, sess.party) then
          valid = valid + 1
        end
      end
      if valid >= sizes[mode + 1] and tonumber(rec.winStreak) == ws and tonumber(rec.lvlMode) == lvl then
        ids[#ids + 1] = i - 1 + D.TRAINER_RECORD_MIXING_FRIEND
      end
    end
  end
  if mode == M.SINGLES then
    local th = D.manifest().apprenticeChallengeThreshold
    for i, app in ipairs(sess.apprentices or {}) do
      if app.checksumValid == false then
        -- pokeemerald/src/battle_tower.c:3183
        app = require("src.core.game3.rse.frontier.apprentice").newSaved()
        app.language = 0
        sess.apprentices[i] = app
      end
      local q = tonumber(app.numQuestions) or 0
      if (tonumber(app.lvlMode) or 0) ~= 0 and th[q + 1] == ws and app.lvlMode - 1 == lvl then
        ids[#ids + 1] = i - 1 + D.TRAINER_RECORD_MIXING_APPRENTICE
      end
    end
  end
  if #ids == 0 then return false end
  sess.frontierOpponentA = ids[(D.rng().Random() % #ids) + 1]
  return true
end

-- pokeemerald/src/battle_tower.c:1051
function Tower.setNextOpponent(sess)
  local f = Util.frontier(sess)
  if f.lvlMode == D.LVL.TENT then
    return require("src.core.game3.rse.frontier.tents").setNextOpponent(sess)
  end
  local mode = var("VAR_FRONTIER_BATTLE_MODE", sess)
  local ws = Util.currentFacilityWinStreak(sess)
  local challengeNum = math.floor(ws / D.STAGES_PER_CHALLENGE)
  local battleNum = tonumber(f.curChallengeBattleNum) or 0
  if mode == M.MULTIS or mode == M.LINK_MULTIS then
    sess.frontierOpponentA = tonumber(f.trainerIds[battleNum * 2 + 1]) or 0
    sess.frontierOpponentB = tonumber(f.trainerIds[battleNum * 2 + 2]) or 0
    D.setGfxVar(sess, sess.frontierOpponentA, 0)
    D.setGfxVar(sess, sess.frontierOpponentB, 1)
  elseif Tower.chooseSpecialTrainer(sess) then
    D.setGfxVar(sess, sess.frontierOpponentA, 0)
    f.trainerIds[battleNum + 1] = sess.frontierOpponentA
  else
    local id
    while true do
      id = Tower.randomScaledTrainerId(challengeNum, battleNum)
      local dup = false
      for i = 1, battleNum do
        if tonumber(f.trainerIds[i]) == id then dup = true break end
      end
      if not dup then break end
    end
    sess.frontierOpponentA = id
    D.setGfxVar(sess, id, 0)
    if battleNum + 1 < D.STAGES_PER_CHALLENGE then f.trainerIds[battleNum + 1] = id end
  end
end

-- pokeemerald/src/battle_tower.c:2147
function Tower.saveBattleTowerRecord(sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local classes = D.pack("classes")
  local tid = math.floor(tonumber(sess.trainerId or sess.playerId) or 0)
  local sid = math.floor(tonumber(sess.secretId) or 0)
  local b0, b1, b2, b3 = tid % 256, math.floor(tid / 256) % 256, sid % 256, math.floor(sid / 256) % 256
  local female = sess.gender == "female" or sess.gender == "F" or sess.gender == 1
  local list = female and classes.towerFemale or classes.towerMale
  local class = list[((b0 + b1 + b2 + b3) % #list) + 1]
  local rec = {
    lvlMode = lvl,
    facilityClass = class,
    trainerId = { b0, b1, b2, b3 },
    name = tostring(sess.name or ""),
    winStreak = Tower.currentWinStreak(sess, lvl, mode),
    greeting = Util.deepCopy(sess.easyChatBattleStart or {}),
    speechWon = Util.deepCopy(sess.easyChatBattleWon or {}),
    speechLost = Util.deepCopy(sess.easyChatBattleLost or {}),
    party = {},
    language = 2,
  }
  local saved = sess.savedPlayerParty or sess.party or {}
  for i = 1, D.MAX_PARTY_SIZE do
    local slot = tonumber(f.selectedPartyMons[i]) or 0
    local mon = slot ~= 0 and (sess.party and sess.party[slot] or saved[slot]) or nil
    if mon then rec.party[i] = Tower.toBattleTowerMon(mon) end
  end
  f.towerPlayer = rec
  Tower.saveCurrentWinStreak(sess)
end

-- pokeemerald/src/pokemon.c:2596
function Tower.toBattleTowerMon(mon)
  local ivs, evs = mon.ivs or {}, mon.evs or {}
  local held = tonumber(mon.heldItem or mon.item) or 0
  if held == D.constants():require("items", "ITEM_ENIGMA_BERRY") then held = 0 end
  local otId = (tonumber(mon.otId) or 0) % 4294967296
  if mon.otSecretId ~= nil then otId = otId % 65536 + (tonumber(mon.otSecretId) or 0) % 65536 * 65536 end
  return {
    species = tonumber(mon.species) or 0, heldItem = held, moves = Util.deepCopy(mon.moves or {}),
    level = tonumber(mon.level) or 0, ppBonuses = tonumber(mon.ppBonuses) or 0,
    hpEV = evs.hp or 0, attackEV = evs.atk or 0, defenseEV = evs.def or 0, speedEV = evs.spe or 0,
    spAttackEV = evs.spa or 0, spDefenseEV = evs.spd or 0, otId = otId,
    hpIV = ivs.hp or 0, attackIV = ivs.atk or 0, defenseIV = ivs.def or 0, speedIV = ivs.spe or 0,
    spAttackIV = ivs.spa or 0, spDefenseIV = ivs.spd or 0, abilityNum = tonumber(mon.abilityNum) or 0,
    personality = tonumber(mon.personality) or 0, nickname = mon.nickname or "",
    friendship = tonumber(mon.friendship) or 0,
  }
end

-- pokeemerald/src/battle_tower.c:2194
function Tower.save(ctx, sess)
  local f = Util.frontier(sess)
  return Util.saveChallenge(sess, "VAR_TEMP_0", function()
    local mode, lvl = modeLvl(sess)
    local challengeNum = math.floor(Util.get2(f.towerWinStreaks, mode, lvl) / D.STAGES_PER_CHALLENGE)
    local status = specialVar(ctx, Util.VAR_0x8005)
    if status == 0 and (challengeNum > 1 or (tonumber(f.curChallengeBattleNum) or 0) ~= 0) then
      Tower.saveBattleTowerRecord(sess)
    end
    f.challengeStatus = status
    Rse.setVar("VAR_TEMP_0", 0, sess)
    f.challengePaused = 1
  end)
end

-- pokeemerald/src/battle_tower.c:1936
function Tower.opponentIntro(ctx, adapters, sess)
  local which = specialVar(ctx, Util.VAR_0x8005)
  local tid = which ~= 0 and sess.frontierOpponentB or sess.frontierOpponentA
  tid = tonumber(tid) or 0
  if tid >= D.TRAINER_RECORD_MIXING_APPRENTICE and tid < D.TRAINER_EREADER then
    Rse.missing("apprentice", "BufferApprenticeChallengeText", adapters and adapters.log)
    return
  end
  Util.setStringVar(ctx, adapters, 4, D.trainerSpeech(sess, tid, 0))
end

-- pokeemerald/src/battle_tower.c:2769
function Tower.giveRibbons(ctx, sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local sizes = D.manifest().towerPartySizes
  local monCount = sizes[mode + 1] or D.PARTY_SIZE
  if monCount > 3 then monCount = 3 end
  local ribbon = lvl ~= D.LVL.L50 and "victory" or "winning"
  local Ribbons = require("src.core.game3.rse.ribbons")
  local gave = false
  local counts = {}
  local saved = sess.savedPlayerParty or {}
  if Tower.currentWinStreak(sess, lvl, mode) > 55 then
    for i = 1, monCount do
      local slot = tonumber(f.selectedPartyMons[i]) or 0
      local mon = saved[slot]
      counts[i] = { slot = slot, count = 0 }
      if mon and Ribbons.get(mon, ribbon) == 0 then
        gave = true
        Ribbons.set(mon, ribbon, 1)
        counts[i].count = Ribbons.count(mon)
      end
    end
  end
  setResult(ctx, gave and 1 or 0)
  if gave then
    sess.gameStats = sess.gameStats or {}
    sess.gameStats[Util.GAME_STAT_RECEIVED_RIBBONS] = (tonumber(sess.gameStats[Util.GAME_STAT_RECEIVED_RIBBONS]) or 0) + 1
    for i = 2, monCount do
      if counts[i] and counts[i].count > counts[1].count then counts[1], counts[i] = counts[i], counts[1] end
    end
    if counts[1] and counts[1].count > Ribbons.NUM_CUTIES_RIBBONS then
      Rse.call("tv", "tryPutSpotTheCutiesOnAir", "TryPutSpotTheCutiesOnAir", nil, saved[counts[1].slot], ribbon)
    end
  end
end

-- pokeemerald/src/battle_tower.c:2671
function Tower.setInterviewData(sess)
  if var("VAR_FRONTIER_BATTLE_MODE", sess) ~= M.SINGLES then return end
  local f = Util.frontier(sess)
  local st = sess.lastFrontierBattle or {}
  local tid = tonumber(sess.frontierOpponentA) or 0
  f.towerInterview = {
    opponentName = D.trainerName(sess, tid),
    opponentLanguage = 2,
    opponentSpecies = tonumber(st.opponentSpecies) or 0,
    playerSpecies = tonumber(st.playerSpecies) or 0,
    opponentMonNickname = st.playerNickname or "",
  }
  f.towerBattleOutcome = tonumber(sess.battleOutcome) or 0
end

-- pokeemerald/src/field_specials.c:2206
function Tower.elevatorFloors(ctx, sess)
  local f = Util.frontier(sess)
  local mode = var("VAR_FRONTIER_BATTLE_MODE", sess)
  if mode == M.MULTIS and not Rse.flag("FLAG_CHOSEN_MULTI_BATTLE_NPC_PARTNER", sess) then
    Rse.setSpecialVar(ctx, Util.VAR_0x8005, 5)
    Rse.setSpecialVar(ctx, Util.VAR_0x8006, 4)
    return
  end
  local th = D.manifest().towerStreakThresholds
  for i = 1, #th - 1 do
    if th[i] > Util.get2(f.towerWinStreaks, mode, f.lvlMode) then
      Rse.setSpecialVar(ctx, Util.VAR_0x8005, 4)
      Rse.setSpecialVar(ctx, Util.VAR_0x8006, i - 1 + 5)
      return
    end
  end
  Rse.setSpecialVar(ctx, Util.VAR_0x8005, 4)
  Rse.setSpecialVar(ctx, Util.VAR_0x8006, 12)
end

-- pokeemerald/src/battle_tower.c:2946
function Tower.tryHideReporter(sess)
  local f = Util.frontier(sess)
  if f.challengeStatus == Util.CHALLENGE_STATUS.SAVING then
    Rse.call("tv", "hideBattleTowerReporter", "HideBattleTowerReporter", nil)
  end
  if Rse.flag("FLAG_CANCEL_BATTLE_ROOM_CHALLENGE", sess) then
    Rse.call("tv", "hideBattleTowerReporter", "HideBattleTowerReporter", nil)
    Rse.setFlag("FLAG_CANCEL_BATTLE_ROOM_CHALLENGE", false, sess)
  end
end

-- pokeemerald/src/battle_tower.c:2272
function Tower.loadPartners(sess)
  local f = Util.frontier(sess)
  local mode, lvl = modeLvl(sess)
  local challengeNum = math.floor(Util.get2(f.towerWinStreaks, mode, lvl) / D.STAGES_PER_CHALLENGE)
  local s1 = tonumber(sess.party[1] and sess.party[1].species) or 0
  local s2 = tonumber(sess.party[2] and sess.party[2].species) or 0
  local set = D.facilityPtrs(sess, F.TOWER)
  local ids = f.trainerIds
  local j = 0
  repeat
    local tid
    while true do
      tid = Tower.randomScaledTrainerId(challengeNum, 0)
      local clash = false
      for i = 1, j do
        if ids[i] == tid or set.trainers[ids[i]].facilityClass == set.trainers[tid].facilityClass then
          clash = true
          break
        end
      end
      if not clash then break end
    end
    ids[j + 1] = tid
    j = j + 1
  until j >= 6
  sess.frontierPartnerGfx = {}
  local r10 = 8
  for i = 0, 5 do
    local tid = ids[i + 1]
    sess.frontierPartnerGfx[i + 1] = D.gfxId(sess, tid, F.TOWER)
    for k = 0, 1 do
      local monId
      while true do
        monId = Tower.randomFrontierMonFromSet(sess, tid)
        local ok = true
        if k % 2 ~= 0 and set.mons[ids[r10]].itemTableId == set.mons[monId].itemTableId then ok = false end
        if ok then
          for q = 8, r10 - 1 do
            local sp = set.mons[ids[q + 1]].species
            if sp == set.mons[monId].species or s1 == set.mons[monId].species or s2 == set.mons[monId].species then
              ok = false
              break
            end
          end
        end
        if ok then break end
      end
      ids[r10 + 1] = monId
      r10 = r10 + 1
    end
  end
end

-- pokeemerald/src/battle_tower.c:1790
function Tower.randomFrontierMonFromSet(sess, trainerId)
  local set, level = D.facilityPtrs(sess, F.TOWER)
  local monSet = set.trainers[trainerId].monSet
  local Rng = D.rng()
  local monId
  repeat
    monId = monSet[(Rng.Random() % #monSet) + 1]
  until not ((level == D.FRONTIER_MAX_LEVEL_50 or level == 20) and monId > D.FRONTIER_MONS_HIGH_TIER)
  return monId
end

-- pokeemerald/src/battle_tower.c:2461
function Tower.partnerMessage(ctx, adapters, sess)
  local f = Util.frontier(sess)
  local k = specialVar(ctx, Util.VAR_LAST_TALKED) - 2
  local tid = tonumber(f.trainerIds[k + 1]) or 0
  local which = specialVar(ctx, Util.VAR_0x8005)
  local P = Tower.PARTNER_MSGID
  local set = D.facilityPtrs(sess, F.TOWER)
  local fc = D.facilityClass(sess, tid, F.TOWER)
  local texts
  for _, row in ipairs(D.manifest().partnerTexts) do
    if row.facilityClass == fc then texts = row.strings break end
  end
  local function monInfo(monId)
    local row = set.mons[monId]
    local Pokemon = require("src.core.game3.pokemon")
    Util.setStringVar(ctx, adapters, 1, Pokemon.moveName(row.moves[1]) or "")
    Util.setStringVar(ctx, adapters, 2, Pokemon.name(row.species))
  end
  if which == P.INTRO then
    Util.setStringVar(ctx, adapters, 1, D.trainerName(sess, tid, F.TOWER))
  elseif which == P.MON1 then
    monInfo(tonumber(f.trainerIds[8 + k * 2 + 1]))
  elseif which == P.MON2_ASK then
    monInfo(tonumber(f.trainerIds[9 + k * 2 + 1]))
  elseif which == P.ACCEPT then
    sess.frontierPartnerId = tid
    f.trainerIds[19] = f.trainerIds[8 + k * 2 + 1]
    f.trainerIds[20] = f.trainerIds[9 + k * 2 + 1]
    local ws = Util.currentFacilityWinStreak(sess)
    local challengeNum = math.floor(ws / D.STAGES_PER_CHALLENGE)
    for kk = 0, D.STAGES_PER_CHALLENGE * 2 - 1 do
      local id
      while true do
        id = Tower.randomScaledTrainerId(challengeNum, math.floor(kk / 2))
        if id ~= tid then
          local dup = false
          for j = 1, kk do
            if tonumber(f.trainerIds[j]) == id then dup = true break end
          end
          if not dup then break end
        end
      end
      f.trainerIds[kk + 1] = id
    end
    f.trainerIds[18] = tid
  end
  if texts and texts[which + 1] then
    Util.showFieldMessage(ctx, adapters, texts[which + 1].ir)
  end
end

-- pokeemerald/src/battle_tower.c:2665
function Tower.setPartnerGfx(sess)
  local f = Util.frontier(sess)
  D.setGfxVar(sess, tonumber(f.trainerIds[18]) or 0, 15, F.TOWER)
end

-- pokeemerald/src/battle_tower.c:2959
function Tower.partnerParty(sess, trainerId)
  local f = Util.frontier(sess)
  local set, level = D.facilityPtrs(sess, F.TOWER)
  local ivs = D.fixedIvs(trainerId)
  local otId = D.rng().Random32()
  local out = {}
  local name = D.trainerName(sess, trainerId, F.TOWER)
  local female = D.isFemale(sess, trainerId, F.TOWER)
  for i = 1, D.MULTI_PARTY_SIZE do
    local monId = tonumber(f.trainerIds[18 + i])
    local mon = D.facilityMon(set, monId, level, ivs, otId, true)
    mon.otName, mon.ot = name, name
    mon.otGender = female and 1 or 0
    out[i] = mon
  end
  return out
end

local function aiFlags(sess)
  local BP = require("src.core.game3.battle.profile")
  local p = BP.get(sess)
  return BP.aiBit(p, "CHECK_BAD_MOVE") + BP.aiBit(p, "TRY_TO_FAINT") + BP.aiBit(p, "CHECK_VIABILITY")
end
Tower.aiFlags = aiFlags

local function foeOf(sess, trainerId, party, facility)
  local lead = party[1] or {}
  local classId = D.opponentClass(sess, trainerId, facility)
  return {
    party = party,
    trainerName = D.trainerName(sess, trainerId, facility),
    trainerClass = classId,
    trainerClassName = D.className(sess, classId),
    trainerPicId = D.frontSpriteId(sess, trainerId, facility),
    frontierTrainerId = trainerId,
    species = lead.species, level = lead.level, ivs = lead.ivs, evs = lead.evs, item = lead.item,
    moves = lead.moves, personality = lead.personality, nature = lead.nature, ability = lead.ability,
    gender = lead.gender, pp = lead.pp,
  }
end
Tower.foeOf = foeOf

local function textPlain(ir)
  local TextIR = require("src.core.game3.scripting.text_ir")
  return TextIR.toPlain(ir, {})
end

-- pokeemerald/src/battle_tower.c:2007
function Tower.startBattle(ctx, adapters, sess, kind, opts)
  local N = require("src.core.game3.scripting.natives")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local BP = require("src.core.game3.battle.profile")
  local facility = var("VAR_FRONTIER_FACILITY", sess)
  local tid = tonumber(sess.frontierOpponentA) or 0
  local foe = foeOf(sess, tid, opts.party, facility)
  local p = BP.get(sess)
  local battleOpts = {
    wild = false,
    frontier = true,
    battleTower = kind == "tower" or nil,
    double = opts.double or nil,
    aiFlags = opts.aiFlags or aiFlags(sess),
    trainerItems = { 0, 0, 0, 0 },
    scriptedLoss = true,
    trainerName = foe.trainerName,
    trainerPicId = foe.trainerPicId,
    defeatText = textPlain(D.trainerSpeech(sess, tid, 2, facility)),
    victoryText = textPlain(D.trainerSpeech(sess, tid, 1, facility)),
    transitionId = opts.transitionId,
    song = BP.battleSong(p, { trainerClass = foe.trainerClass, frontier = true }),
    frontierTrainer = { class = foe.trainerClass, className = foe.trainerClassName, name = foe.trainerName,
      pic = foe.trainerPicId },
  }
  for k, v in pairs(opts.extra or {}) do battleOpts[k] = v end
  local tidB = opts.extra and tonumber(opts.extra.frontierOpponentB)
  if tidB and opts.double then
    -- pokeemerald/src/battle_tower.c:1620
    local foeB = foeOf(sess, tidB, {}, facility)
    battleOpts.twoOpponents = true
    battleOpts.frontierFoeHalf = opts.foeHalf or math.floor(#opts.party / 2)
    battleOpts.frontierTrainerB = { class = foeB.trainerClass, className = foeB.trainerClassName,
      name = foeB.trainerName, pic = foeB.trainerPicId }
    battleOpts.defeatTextB = textPlain(D.trainerSpeech(sess, tidB, 2, facility))
  end
  battleOpts[kind] = true
  sess.battleOutcome = 0
  return N.yieldHost(ctx, adapters, function(done)
    battleOpts.done = function(result)
      local code = N.outcome_to_code(result or "win")
      sess.battleOutcome = code
      if ctx then ctx.lastBattleOutcome = code end
      -- pokeemerald/src/battle_main.c:5228
      Util.setResult(ctx, code)
      local st = package.loaded["src.core.game3.battle"] and package.loaded["src.core.game3.battle"].getState
        and package.loaded["src.core.game3.battle"].getState()
      sess.lastFrontierBattle = {
        opponentSpecies = st and st.enemy and st.enemy.mon and st.enemy.mon.species,
        playerSpecies = st and st.player and st.player.mon and st.player.mon.species,
        playerNickname = st and st.player and st.player.mon and (st.player.mon.nickname or st.player.mon.name),
      }
      Util.onSpecialBattleEnd(sess, "frontier")
      done()
      local Space = package.loaded["src.core.game3.scripting.space"]
      if Space and Space.vm then Space.vm:tick() end
    end
    local ok, err = BattleBridge.start(Runtime and Runtime._mod, Runtime and Runtime._game, foe, battleOpts)
    if not ok then
      local msg = "[game3] frontier battle did not start (" .. tostring(err) .. ")"
      if adapters and adapters.log then adapters.log(msg) else print(msg) end
      done()
    end
  end)
end

-- pokeemerald/src/battle_tower.c:2007
function Tower.doTowerBattle(ctx, adapters, sess)
  local mode = var("VAR_FRONTIER_BATTLE_MODE", sess)
  local party = {}
  local extra = {}
  local tid = tonumber(sess.frontierOpponentA) or 0
  if mode == M.SINGLES then
    D.fillTrainerParty(sess, tid, 0, D.PARTY_SIZE, party)
  elseif mode == M.DOUBLES then
    D.fillTrainerParty(sess, tid, 0, D.DOUBLES_PARTY_SIZE, party)
  elseif mode == M.MULTIS then
    D.fillTrainerParty(sess, tid, 0, D.MULTI_PARTY_SIZE, party)
    local partyB = {}
    D.fillTrainerParty(sess, tonumber(sess.frontierOpponentB) or 0, 0, D.MULTI_PARTY_SIZE, partyB,
      { setOwner = tid })
    for _, m in ipairs(partyB) do party[#party + 1] = m end
    local partnerId = tonumber(Util.frontier(sess).trainerIds[18]) or 0
    local half = #sess.party
    for _, mon in ipairs(Tower.partnerParty(sess, partnerId)) do sess.party[#sess.party + 1] = mon end
    extra = {
      partner = true, playerHalf = half, twoOpponents = true, frontierPartner = partnerId,
      partnerName = D.trainerName(sess, partnerId, F.TOWER),
      partnerPicId = D.frontSpriteId(sess, partnerId, F.TOWER),
      frontierOpponentB = tonumber(sess.frontierOpponentB) or 0,
    }
  else
    return require("src.core.game3.link.tower_link").startBattle(ctx, adapters, sess)
  end
  return Tower.startBattle(ctx, adapters, sess, "tower", {
    party = party,
    double = mode ~= M.SINGLES,
    extra = extra,
    transitionId = D.specialTransition(sess, "B_TOWER", party),
  })
end

-- pokeemerald/include/constants/global.h:97
local PLAYER_NAME_LENGTH = 7

local function nameChar(s, i)
  return tostring(s or ""):sub(i + 1, i + 1)
end

local function idByte(rec, i)
  return tonumber(type(rec.trainerId) == "table" and rec.trainerId[i + 1]) or 0
end

-- pokeemerald/src/battle_tower.c:1311
function Tower.putNewRecord(sess, newRecord)
  local f = Util.frontier(sess)
  local records = f.towerRecords
  local count = Util.BATTLE_TOWER_RECORD_COUNT
  for i = 1, count do
    if type(records[i]) ~= "table" then records[i] = {} end
  end
  local function streak(i) return tonumber(records[i + 1].winStreak) or 0 end
  local i = 0
  while i < count do
    local rec, k, j = records[i + 1], 0, 0
    while j < 4 and idByte(rec, j) == idByte(newRecord, j) do j = j + 1 end
    if j == 4 then
      while k < PLAYER_NAME_LENGTH do
        if nameChar(rec.name, j) ~= nameChar(newRecord.name, j) then break end
        if nameChar(newRecord.name, j) == "" then
          k = PLAYER_NAME_LENGTH
          break
        end
        k = k + 1
      end
    end
    if k == PLAYER_NAME_LENGTH then break end
    i = i + 1
  end
  if i < count then
    records[i + 1] = Util.deepCopy(newRecord)
    return i
  end
  for s = 0, count - 1 do
    if streak(s) == 0 then
      records[s + 1] = Util.deepCopy(newRecord)
      return s
    end
  end
  local slotValues, slotIds = { streak(0) }, { 0 }
  for s = 1, count - 1 do
    local j = 1
    while j <= #slotValues do
      if streak(s) < slotValues[j] then
        slotValues, slotIds = { streak(s) }, { s }
        j = 1
        break
      elseif streak(s) > slotValues[j] then
        break
      end
      j = j + 1
    end
    if j == #slotValues + 1 then
      slotValues[#slotValues + 1] = streak(s)
      slotIds[#slotIds + 1] = s
    end
  end
  local pick = slotIds[(D.rng().Random() % #slotIds) + 1]
  records[pick + 1] = Util.deepCopy(newRecord)
  return pick
end

-- pokeemerald/src/record_mixing.c:1396
function Tower.mixExport(sess)
  local rec = Util.deepCopy(Util.frontier(sess).towerPlayer or {})
  return rec
end

-- pokeemerald/src/record_mixing.c:650
function Tower.mixImport(players, sess, myIndex)
  sess = sess or Rse.session()
  local MixUtil = require("src.core.game3.rse.record_mix_util")
  local partner = MixUtil.partner(players or {}, tonumber(myIndex) or 1)
  local rec = type(partner) == "table" and partner.battleTowerRecord or nil
  if type(rec) ~= "table" then return false end
  rec = Util.deepCopy(rec)
  local me = players[tonumber(myIndex) or 1]
  if type(me) == "table" then me.battleTowerRecord = rec end
  Tower.putNewRecord(sess, rec)
  return true
end

Rse.register("tower", Tower)

return Tower

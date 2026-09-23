local Std = require("src.core.game3.scripting.stdscripts")
local Tower = require("src.core.game3.trainer_tower")

local TowerNatives = {}

-- pokefirered/include/constants/vars.h:319
local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005
local VAR_0x8006 = 0x8006
-- pokefirered/include/constants/vars.h:328
local VAR_RESULT = 0x800D
-- pokefirered/include/constants/vars.h:333
local VAR_TEXT_COLOR = 0x8012
local VAR_PREV_TEXT_COLOR = 0x8013
-- pokefirered/include/constants/vars.h:9
local VAR_TEMP_1 = 0x4001
local VAR_TEMP_3 = 0x4003
-- pokefirered/include/constants/vars.h:28
local VAR_OBJ_GFX_ID_0 = 0x4010
local VAR_OBJ_GFX_ID_1 = 0x4011
local VAR_OBJ_GFX_ID_2 = 0x4012
local VAR_OBJ_GFX_ID_3 = 0x4013

-- pokefirered/include/constants/global.h:85
local MALE, FEMALE = 0, 1

-- pokefirered/include/constants/battle.h:76
local B_OUTCOME_WON, B_OUTCOME_LOST = 1, 2

-- pokefirered/include/constants/party_menu.h:59
local PARTY_MENU_TYPE_CHOOSE_MULTIPLE_MONS = 4
-- pokefirered/include/constants/party_menu.h:133
local CHOOSE_MONS_FOR_CABLE_CLUB_BATTLE = 0

-- pokefirered/src/battle_tower.c:902
local SPECIAL_BATTLE = { BATTLE_TOWER = 0, SECRET_BASE = 1, EREADER = 2 }

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

-- pokefirered/src/scrcmd.c:99
local function setResult(ctx, value)
  varSet(ctx, VAR_RESULT, value)
  return false, tonumber(value) or 0
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then pcall(adapters.setStringVar, index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

local function log(msg)
  TowerNatives._logged = TowerNatives._logged or {}
  if TowerNatives._logged[msg] then return end
  TowerNatives._logged[msg] = true
  print("[game3/tower] " .. tostring(msg))
end

local function currentFloor(session)
  local floorIdx = Tower.floorIndexForMap(session and session.map)
  if not floorIdx then return nil, nil end
  return Tower.floor(Tower.getChallengeId(session), floorIdx), floorIdx
end

local function trainerRow(floor, index)
  local rows = floor and floor.trainers
  if type(rows) ~= "table" then return nil end
  return rows[(tonumber(index) or 0) + 1]
end

-- pokefirered/src/trainer_tower.c:105
local function singlesGfxFor(facilityClass)
  local pack = Tower.pack()
  local info = pack and pack.singlesTrainerInfo
  local row = type(info) == "table" and facilityClass and info[facilityClass] or nil
  if row then return tonumber(row.objGfx) or Tower.GFX_YOUNGSTER, tonumber(row.gender) or MALE end
  -- pokefirered/src/trainer_tower.c:576
  return Tower.GFX_YOUNGSTER, MALE
end

-- pokefirered/src/trainer_tower.c:191
local function doublesGfxFor(facilityClass)
  local pack = Tower.pack()
  local info = pack and pack.doublesTrainerInfo
  local row = type(info) == "table" and facilityClass and info[facilityClass] or nil
  if row then
    return tonumber(row.objGfx1) or Tower.GFX_YOUNGSTER,
      tonumber(row.objGfx2) or Tower.GFX_YOUNGSTER,
      tonumber(row.gender1) or FEMALE,
      tonumber(row.gender2) or MALE
  end
  -- pokefirered/src/trainer_tower.c:594
  return Tower.GFX_YOUNGSTER, Tower.GFX_YOUNGSTER, MALE, MALE
end

-- pokefirered/src/trainer_tower.c:559
local function setNpcGraphics(ctx, floor)
  local challengeType = floor and floor.challengeType
  if challengeType == Tower.CHALLENGE_TYPE.SINGLE then
    local row = trainerRow(floor, 0)
    varSet(ctx, VAR_OBJ_GFX_ID_1, (singlesGfxFor(row and row.facilityClass)))
  elseif challengeType == Tower.CHALLENGE_TYPE.DOUBLE then
    local row = trainerRow(floor, 0)
    local gfx1, gfx2 = doublesGfxFor(row and row.facilityClass)
    varSet(ctx, VAR_OBJ_GFX_ID_0, gfx1)
    varSet(ctx, VAR_OBJ_GFX_ID_3, gfx2)
  elseif challengeType == Tower.CHALLENGE_TYPE.KNOCKOUT then
    local slots = { [0] = VAR_OBJ_GFX_ID_2, VAR_OBJ_GFX_ID_0, VAR_OBJ_GFX_ID_1 }
    for j = 0, Tower.MAX_TRAINERS_PER_FLOOR - 1 do
      local row = trainerRow(floor, j)
      varSet(ctx, slots[j], (singlesGfxFor(row and row.facilityClass)))
    end
  end
end

-- pokefirered/src/overworld.c:978 SetCurrentMapLayout
local function setCurrentMapLayout(layoutId, mapId)
  if not layoutId then return false end
  if layoutId == Tower.layoutIdForMap(mapId) then return true end
  local okO, Ops = pcall(require, "src.core.game3.scripting.ops_a")
  if not (okO and Ops and Ops.setMapLayout) then return false end
  local ok, applied = pcall(Ops.setMapLayout, layoutId, nil)
  if not (ok and applied) then
    log("layout " .. tostring(layoutId) .. " is not baked in this cache")
    return false
  end
  return true
end

-- pokefirered/src/trainer_tower.c:682
local function setOpponentTextColor(ctx, challengeType, facilityClass)
  local gender = MALE
  if challengeType == Tower.CHALLENGE_TYPE.DOUBLE then
    local _, _, gender1, gender2 = doublesGfxFor(facilityClass)
    gender = (varGet(ctx, VAR_TEMP_3) ~= 0) and gender2 or gender1
  else
    local _, g = singlesGfxFor(facilityClass)
    gender = g
  end
  varSet(ctx, VAR_PREV_TEXT_COLOR, varGet(ctx, VAR_TEXT_COLOR))
  varSet(ctx, VAR_TEXT_COLOR, gender)
end

-- pokefirered/src/trainer_tower.c:631
local function convertSpeech(words)
  if type(words) ~= "table" then return "" end
  return require("src.core.game3.easy_chat_text").phrase(words, 3, 2)
end

local function natives()
  return require("src.core.game3.scripting.natives")
end

local function recordsScreen()
  local ok, Screen = pcall(require, "src.ui.game3.trainer_tower_records")
  if ok and type(Screen) == "table" and Screen.show then return Screen end
  log("the trainer tower records screen could not be loaded")
  return nil
end

-- pokefirered/src/party_menu_specials.c:38, pokefirered/src/party_menu.c:6317
local function takeScreenForPartyMenu()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if not (okF and Fade and Fade.begin and Fade.MODE) then return function() end end
  local covered = not (Fade.isActive and Fade.isActive()) and (tonumber(Fade.t) or 0) >= 16
  -- pokefirered/src/party_menu.c:6329 FadeInFromBlack
  if not (covered and Fade.mode == Fade.MODE.TO_BLACK) then return function() end end
  Fade.clear()
  return function()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
end

-- pokefirered/src/trainer_tower.c:722
local function runBattle(ctx, adapters, foe, battleOpts, after)
  local N = natives()
  local outcome = B_OUTCOME_LOST
  local settled = false
  local function settle()
    if settled then return end
    settled = true
    if after then after(outcome) end
    varSet(ctx, VAR_RESULT, outcome)
  end
  if not (adapters and adapters.startTrainerBattle) then
    log("no startTrainerBattle host seam, so the battle cannot run")
    settle()
    return false
  end
  local yielded = N.yieldHost(ctx, adapters, function(done)
    adapters.startTrainerBattle(foe, function(result)
      outcome = N.outcome_to_code(result or "win")
      done()
    end, battleOpts)
  end)
  if not yielded then
    settle()
    return false
  end
  local closedPoll = ctx.nativePoll
  ctx.nativePoll = function()
    if closedPoll and not closedPoll() then return false end
    settle()
    return true
  end
  return true
end

local FUNCS = {}

-- pokefirered/src/trainer_tower.c:544 InitTrainerTowerFloor
FUNCS[Tower.FUNC.INIT_FLOOR] = function(ctx)
  local session = sessionOf()
  local mapId = session and session.map
  if Tower.isPastFinalFloor(mapId) then
    setResult(ctx, 3)
    setCurrentMapLayout(Tower.LAYOUT_ROOF, mapId)
    return false
  end
  local floor, floorIdx = currentFloor(session)
  if not floor then
    log("InitTrainerTowerFloor outside a tower floor map: " .. tostring(mapId))
    return false
  end
  setResult(ctx, floor.challengeType)
  setCurrentMapLayout(Tower.floorLayoutFor(floorIdx, floor.challengeType), mapId)
  setNpcGraphics(ctx, floor)
  return false
end

-- pokefirered/src/trainer_tower.c:651 BufferTowerOpponentSpeech
FUNCS[Tower.FUNC.GET_SPEECH] = function(ctx, adapters)
  local session = sessionOf()
  local floor = currentFloor(session)
  if not floor then return false end
  local trainerId = varGet(ctx, VAR_0x8006)
  local challengeType = floor.challengeType
  local classRow = (challengeType ~= Tower.CHALLENGE_TYPE.DOUBLE)
    and trainerRow(floor, trainerId) or trainerRow(floor, 0)
  local facilityClass = classRow and classRow.facilityClass
  local row = trainerRow(floor, trainerId)
  local which = varGet(ctx, VAR_0x8005)
  local words
  if which == Tower.TEXT.INTRO then
    setOpponentTextColor(ctx, challengeType, facilityClass)
    words = row and row.speechBefore
  elseif which == Tower.TEXT.PLAYER_LOST then
    setOpponentTextColor(ctx, challengeType, facilityClass)
    words = row and row.speechWin
  elseif which == Tower.TEXT.PLAYER_WON then
    setOpponentTextColor(ctx, challengeType, facilityClass)
    words = row and row.speechLose
  elseif which == Tower.TEXT.AFTER then
    words = row and row.speechAfter
  end
  setStringVar(ctx, adapters, 4, convertSpeech(words))
  return false
end

-- pokefirered/src/trainer_tower.c:733 DoTrainerTowerBattle
FUNCS[Tower.FUNC.DO_BATTLE] = function(ctx, adapters)
  local session = sessionOf()
  local floor = currentFloor(session)
  local foe = floor and Tower.battleFoe(session, floor, varGet(ctx, VAR_TEMP_1))
  if not foe then
    log("DoTrainerTowerBattle has no floor trainers in this cache")
    -- pokefirered/include/constants/battle.h:77 B_OUTCOME_LOST
    return setResult(ctx, B_OUTCOME_LOST)
  end
  -- pokefirered/src/trainer_tower.c:735 BATTLE_TYPE_TRAINER_TOWER
  return runBattle(ctx, adapters, foe, {
    trainerId = 0,
    double = floor.challengeType == Tower.CHALLENGE_TYPE.DOUBLE,
    trainerTower = true,
    -- pokefirered/src/battle_message.c:2066 GetTrainerTowerOpponentName
    trainerName = foe.trainerName,
    trainerPicId = foe.trainerPicId,
    -- pokefirered/src/trainer_tower.c:717 CB2_EndTrainerTowerBattle
    noWhiteout = true,
  })
end

-- pokefirered/src/trainer_tower.c:747 TrainerTowerGetChallengeType
FUNCS[Tower.FUNC.GET_CHALLENGE_TYPE] = function(ctx)
  if varGet(ctx, VAR_0x8005) ~= 0 then return false end
  local floor = currentFloor(sessionOf())
  if not floor then return false end
  return setResult(ctx, floor.challengeType)
end

-- pokefirered/src/trainer_tower.c:753 TrainerTowerAddFloorCleared
FUNCS[Tower.FUNC.CLEARED_FLOOR] = function()
  Tower.addFloorCleared(sessionOf())
  return false
end

-- pokefirered/src/trainer_tower.c:759 GetFloorAlreadyCleared
FUNCS[Tower.FUNC.GET_FLOOR_CLEARED] = function(ctx)
  local session = sessionOf()
  local cleared = Tower.isFloorAlreadyCleared(session, session and session.map)
  return setResult(ctx, cleared and 1 or 0)
end

-- pokefirered/src/trainer_tower.c:769 StartTrainerTowerChallenge
FUNCS[Tower.FUNC.START_CHALLENGE] = function(ctx)
  Tower.startChallenge(sessionOf(), varGet(ctx, VAR_0x8005))
  return false
end

-- pokefirered/src/trainer_tower.c:786 GetOwnerState
FUNCS[Tower.FUNC.GET_OWNER_STATE] = function(ctx)
  local session = sessionOf()
  Tower.setTimerRunning(session, false)
  local rec = Tower.record(session)
  local result = 0
  if rec.spokeToOwner then result = result + 1 end
  if rec.receivedPrize and rec.checkedFinalTime then result = result + 1 end
  rec.spokeToOwner = true
  return setResult(ctx, result)
end

-- pokefirered/src/trainer_tower.c:799 GiveChallengePrize
FUNCS[Tower.FUNC.GIVE_PRIZE] = function(ctx, adapters)
  local session = sessionOf()
  local rec = Tower.record(session)
  if rec.receivedPrize then return setResult(ctx, 2) end
  local itemId = Tower.prizeItem(session)
  -- pokefirered/src/trainer_tower.c:805 the bag-full branch, taken when the set is unknown
  if not itemId then return setResult(ctx, 1) end
  local Bag = require("src.core.game3.bag")
  local bag = session and session.bag
  local added = bag and Bag.add(bag, itemId, 1)
  if not added then return setResult(ctx, 1) end
  local ItemsData = require("src.core.game3.items_data")
  setStringVar(ctx, adapters, 2, ItemsData.displayName(itemId) or "")
  rec.receivedPrize = true
  return setResult(ctx, 0)
end

-- pokefirered/src/trainer_tower.c:819 CheckFinalTime
FUNCS[Tower.FUNC.CHECK_FINAL_TIME] = function(ctx)
  local session = sessionOf()
  local rec = Tower.record(session)
  local result
  if rec.checkedFinalTime then
    result = 2
  elseif Tower.bestTime(session) > rec.timer then
    Tower.setBestTime(session, rec.timer)
    result = 0
  else
    result = 1
  end
  rec.checkedFinalTime = true
  return setResult(ctx, result)
end

-- pokefirered/src/trainer_tower.c:838 TrainerTowerResumeTimer
FUNCS[Tower.FUNC.RESUME_TIMER] = function()
  Tower.resumeTimer(sessionOf())
  return false
end

-- pokefirered/src/trainer_tower.c:849 TrainerTowerSetPlayerLost
FUNCS[Tower.FUNC.SET_LOST] = function()
  Tower.record(sessionOf()).hasLost = true
  return false
end

-- pokefirered/src/trainer_tower.c:854 GetTrainerTowerChallengeStatus
FUNCS[Tower.FUNC.GET_CHALLENGE_STATUS] = function(ctx)
  local rec = Tower.record(sessionOf())
  if rec.hasLost then
    rec.hasLost = false
    return setResult(ctx, Tower.CHALLENGE_STATUS.LOST)
  end
  if rec.statusUnk then
    rec.statusUnk = false
    return setResult(ctx, Tower.CHALLENGE_STATUS.UNK)
  end
  return setResult(ctx, Tower.CHALLENGE_STATUS.NORMAL)
end

-- pokefirered/src/trainer_tower.c:888 GetCurrentTime
FUNCS[Tower.FUNC.GET_TIME] = function(ctx, adapters)
  local session = sessionOf()
  local minutes, seconds, centiseconds = Tower.formatTime(Tower.readTime(session))
  setStringVar(ctx, adapters, 1, minutes)
  setStringVar(ctx, adapters, 2, seconds)
  setStringVar(ctx, adapters, 3, centiseconds)
  return false
end

-- pokefirered/src/trainer_tower.c:899 ShowResultsBoard
FUNCS[Tower.FUNC.SHOW_RESULTS] = function(ctx)
  local Screen = recordsScreen()
  if not Screen then
    varSet(ctx, VAR_TEMP_1, 0)
    return false
  end
  Screen.show({ session = sessionOf(), kind = "board" })
  varSet(ctx, VAR_TEMP_1, Screen.BOARD_WINDOW_ID)
  return false
end

-- pokefirered/src/trainer_tower.c:924 CloseResultsBoard
FUNCS[Tower.FUNC.CLOSE_RESULTS] = function(ctx)
  local Screen = recordsScreen()
  if not Screen then return false end
  if varGet(ctx, VAR_TEMP_1) ~= Screen.BOARD_WINDOW_ID then return false end
  Screen.close()
  return false
end

-- pokefirered/src/trainer_tower.c:931 TrainerTowerGetDoublesEligiblity
FUNCS[Tower.FUNC.CHECK_DOUBLES] = function(ctx)
  local Party = require("src.core.game3.party")
  local session = sessionOf()
  return setResult(ctx, Party.monsStateToDoubles(session and session.party))
end

-- pokefirered/src/trainer_tower.c:937 TrainerTowerGetNumFloors
FUNCS[Tower.FUNC.GET_NUM_FLOORS] = function(ctx, adapters)
  local differs, numFloors = Tower.numFloorsResult(Tower.getChallengeId(sessionOf()))
  if differs then
    setStringVar(ctx, adapters, 1, tostring(numFloors))
    return setResult(ctx, 1)
  end
  return setResult(ctx, 0)
end

-- pokefirered/src/trainer_tower.c:952 ShouldWarpToCounter
FUNCS[Tower.FUNC.SHOULD_WARP_TO_COUNTER] = function(ctx)
  return setResult(ctx, 0)
end

-- pokefirered/src/trainer_tower.c:960 PlayTrainerTowerEncounterMusic
FUNCS[Tower.FUNC.ENCOUNTER_MUSIC] = function(ctx)
  local floor = currentFloor(sessionOf())
  local row = trainerRow(floor, varGet(ctx, VAR_TEMP_1))
  local pack = Tower.pack()
  local lut = pack and pack.encounterMusic
  local song = row and row.facilityClass and type(lut) == "table" and lut[row.facilityClass]
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playMapSong then
    pcall(Audio.playMapSong, tonumber(song) or Tower.MUS_ENCOUNTER_BOY)
  end
  return false
end

-- pokefirered/src/trainer_tower.c:983 HasSpokenToOwner
FUNCS[Tower.FUNC.GET_BEAT_CHALLENGE] = function(ctx)
  return setResult(ctx, Tower.record(sessionOf()).spokeToOwner and 1 or 0)
end

TowerNatives.FUNCS = FUNCS

-- pokefirered/src/party_menu.c:5651 InitChooseMonsForBattle
function TowerNatives.chooseOptions()
  return {
    menuType = PARTY_MENU_TYPE_CHOOSE_MULTIPLE_MONS,
    mode = "choose_multi",
    count = Tower.SELECTED_ORDER_SIZE,
    min = 1,
    -- pokefirered/src/party_menu.c:5687 the menu's own default is this rule
    chooseMonsBattleType = CHOOSE_MONS_FOR_CABLE_CLUB_BATTLE,
  }
end

TowerNatives.HANDLERS = {
  -- pokefirered/src/trainer_tower.c:438 CallTrainerTowerFunc
  [Std.SPECIAL.CallTrainerTowerFunc] = function(ctx, adapters)
    local index = varGet(ctx, VAR_0x8004)
    local fn = FUNCS[index]
    if not fn then
      log("CallTrainerTowerFunc index out of range: " .. tostring(index))
      return false
    end
    return fn(ctx, adapters)
  end,

  -- pokefirered/src/load_save.c:160 SavePlayerParty
  [Std.SPECIAL.SavePlayerParty] = function()
    Tower.savePlayerParty(sessionOf())
    return false
  end,

  -- pokefirered/src/load_save.c:170 LoadPlayerParty
  [Std.SPECIAL.LoadPlayerParty] = function()
    Tower.loadPlayerParty(sessionOf())
    return false
  end,

  -- pokefirered/src/script_pokemon_util.c:197 ReducePlayerPartyToThree
  [Std.SPECIAL.ReducePlayerPartyToThree] = function()
    Tower.reducePartyToThree(sessionOf())
    return false
  end,

  -- pokefirered/src/script_pokemon_util.c:152 ChooseHalfPartyForBattle
  [Std.SPECIAL.ChooseHalfPartyForBattle] = function(ctx, adapters)
    local session = sessionOf()
    Tower.clearSelectedOrder(session)
    local picked, settled = nil, false
    local restore = takeScreenForPartyMenu()
    local function settle()
      if settled then return end
      settled = true
      local order = Tower.setSelectedOrder(session, picked)
      -- pokefirered/src/script_pokemon_util.c:159 CB2_ReturnFromChooseHalfParty
      varSet(ctx, VAR_RESULT, (order[1] ~= 0) and 1 or 0)
    end
    if not (adapters and adapters.chooseParty) then
      settle()
      restore()
      return false
    end
    local yielded = natives().yieldHost(ctx, adapters, function(done)
      adapters.chooseParty(TowerNatives.chooseOptions(), function(chosen)
        picked = chosen
        restore()
        done()
      end)
    end)
    if not yielded then
      settle()
      return false
    end
    local closedPoll = ctx.nativePoll
    ctx.nativePoll = function()
      if closedPoll and not closedPoll() then return false end
      settle()
      return true
    end
    return true
  end,

  -- pokefirered/src/battle_tower.c:1354 ValidateEReaderTrainer
  [Std.SPECIAL.ValidateEReaderTrainer] = function(ctx)
    -- pokefirered/data/maps/SevenIsland_House_Room1/scripts.inc:9
    return setResult(ctx, Tower.ereaderTrainer(sessionOf()) and 0 or 1)
  end,

  -- pokefirered/src/battle_records.c:83 ShowBattleRecords
  [Std.SPECIAL.ShowBattleRecords] = function(ctx, adapters)
    local session = sessionOf()
    -- pokefirered/src/battle_records.c:136
    local kind = (varGet(ctx, VAR_0x8004) ~= 0) and "tower" or "link"
    local Screen = recordsScreen()
    -- src/battle_records.c:83, cable_club.inc:566-575
    if not Screen then
      takeScreenForPartyMenu()()
      return natives().yieldHost(ctx, adapters, function(done) done() end)
    end
    return natives().yieldHost(ctx, adapters, function(done)
      Screen.show({ session = session, kind = kind, onDone = done })
    end)
  end,

  -- pokefirered/src/battle_tower.c:895 StartSpecialBattle
  [Std.SPECIAL.StartSpecialBattle] = function(ctx, adapters)
    local session = sessionOf()
    local which = varGet(ctx, VAR_0x8004)
    local foe, after
    if which == SPECIAL_BATTLE.EREADER then
      foe = Tower.ereaderFoe(session)
      after = function(outcome)
        -- pokefirered/src/battle_tower.c:1406 PrintEReaderTrainerFarewellMessage
        local trainer = session and session.ereaderTrainer
        local words = trainer
          and ((outcome == B_OUTCOME_WON) and trainer.farewellPlayerWon or trainer.farewellPlayerLost)
        setStringVar(ctx, adapters, 4, convertSpeech(words))
      end
    elseif which == SPECIAL_BATTLE.SECRET_BASE then
      -- pokefirered/src/battle_tower.c:915
      Tower.copyHeldItems(session, true)
    end
    if not foe then
      log("StartSpecialBattle " .. tostring(which) .. " has no opponent data in this save")
      return setResult(ctx, B_OUTCOME_LOST)
    end
    -- pokefirered/src/battle_tower.c:933 BATTLE_TYPE_EREADER_TRAINER
    return runBattle(ctx, adapters, foe, {
      trainerId = 0,
      eReader = which == SPECIAL_BATTLE.EREADER,
      -- src/battle_tower.c:895-933
      battleTower = which == SPECIAL_BATTLE.BATTLE_TOWER,
      secretBase = which == SPECIAL_BATTLE.SECRET_BASE,
      -- pokefirered/src/battle_message.c:2072 CopyEReaderTrainerName5
      trainerName = foe.trainerName,
      trainerPicId = foe.trainerPicId,
      noWhiteout = true,
    }, after)
  end,
}

return TowerNatives

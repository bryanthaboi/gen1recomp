-- The Battle Tower specials: ../pokecrystal/data/events/special_pointers.asm:132-140 and
-- :150 BattleTowerAction, :152 Menu_ChallengeExplanationCancel.

local Specials = require("src.script.gen2.Specials")
local S = Specials.shared

local Bag = require("src.inventory.Bag")
local BattleTower = require("src.core.gen2.BattleTower")
local RomText = require("src.core.RomText")
local Save = require("src.core.gen2.Save")
local Strings = require("src.core.Strings")

local M = {}

local TRUE, FALSE = S.TRUE, S.FALSE
local A = BattleTower.ACTIONS

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:190-196
-- InitBattleTowerChallengeRAM.  wNrOfBeatenBattleTowerTrainers is the byte the
-- room script `readmem`s, so it is zeroed in the VM's own memory store.
local function initChallengeRam(vm)
  vm.btBattleEnded = 0
  vm.btBeaten = 0
  if vm.mem then vm.mem[BattleTower.WRAM_NR_BEATEN] = 0 end
end

-- ../pokecrystal/engine/events/battle_tower/rules.asm:57-92, the far labels
-- data/generated/rom_text.lua carries.
local RULE_FALLBACKS = {
  _ExcuseMeYoureNotReadyText =
    Strings.source("Excuse me.\nYou're not ready."),
  _OnlyThreeMonMayBeEnteredText =
    Strings.source("Only three POKéMON\nmay be entered."),
  _TheMonMustAllBeDifferentKindsText =
    Strings.source("The {STRBUF} POKéMON\nmust all be different kinds."),
  _TheMonMustNotHoldTheSameItemsText =
    Strings.source("The {STRBUF} POKéMON\nmust not hold the same items."),
  _YouCantTakeAnEggText = Strings.source("You can't take an\nEGG!"),
  _BattleTowerReturnWhenReadyText =
    Strings.source("Please return when\nyou're ready."),
}

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1157-1171
-- BattleTower_CheckSaveFileExistsAndIsYours; the running game IS the loaded
-- save here, so CompareLoadedAndSavedPlayerID can only match.
local function saveFileIsYours(vm)
  local record = S.save(vm)
  if not (record and record.version) then return FALSE end
  return Save.exists(record.version) and TRUE or FALSE
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1024-1127 and
-- :1187-1242, :1314-1447: SRAM bank 5 and WRAM bank 3 belong to the Mobile
-- System GB adapter.  A cartridge that never linked reads them as zero, and
-- these are the values that zero produces.
local MOBILE_ARMS = {
  [A.ACTION_05] = { value = 0, why = "s5_be46 is 0 until a mobile challenge" },
  [A.ACTION_06] = { why = "clears the mobile challenge bytes" },
  [A.ACTION_0C] = { why = "stamps the mobile challenge day" },
  [A.ACTION_0D] = { value = FALSE, why = "s5_aa47 is 0, so `and a / ret z`" },
  [A.ACTION_0F] = { value = 0, why = "w3_d090 is the adapter's status byte" },
  [A.ACTION_10] = { value = FALSE, why = "s5_a800 is 0, the .NoAction row" },
  [A.ACTION_16] = { why = "stamps the mobile news day" },
  [A.ACTION_17] = { value = FALSE, why = "s5_b2f9 is 0, so `and a / ret z`" },
  [A.LEVEL_CHECK] = { value = 0, why = "s5_b2fb is the stadium's max level" },
  [A.UBERS_CHECK] = { value = 0, why = "s5_b2fb is the stadium's max level" },
}

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:951-953
-- BattleTower_SaveOptions writes options.lua, which no `special` hook reaches.
local UNHOOKED_ARMS = {
  [A.SAVEOPTIONS] = "needs a saveOptions hook in World:specialHooks",
}

local ACTIONS = {}

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:978-990
ACTIONS[A.CHECK_EXPLANATION_READ] = function(vm, tower, record)
  local yours = saveFileIsYours(vm)
  S.answer(vm, yours)
  if yours == 0 then return end
  S.answer(vm, BattleTower.saveFileFlag(record,
    BattleTower.SAVEFILE_EXPLANATION))
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1001-1008
ACTIONS[A.SET_EXPLANATION_READ] = function(_vm, _tower, record)
  BattleTower.setSaveFileFlag(record, BattleTower.SAVEFILE_EXPLANATION)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:992-999
ACTIONS[A.GET_CHALLENGE_STATE] = function(vm, tower)
  S.answer(vm, tower.challenge)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1010-1012
ACTIONS[A.SAVE_AND_QUIT] = function(_vm, _tower, record)
  BattleTower.setChallengeState(record, BattleTower.SAVED_AND_LEFT)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1014-1022
ACTIONS[A.CHALLENGECANCELED] = function(_vm, _tower, record)
  BattleTower.setChallengeState(record, BattleTower.NO_CHALLENGE)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1129-1141
ACTIONS[A.SAVELEVELGROUP] = function(vm, tower)
  tower.levelGroup = math.max(0, math.floor(tonumber(vm.btLevelGroup) or 0))
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1143-1155
ACTIONS[A.LOADLEVELGROUP] = function(vm, tower)
  vm.btLevelGroup = tower.levelGroup
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1157-1171
ACTIONS[A.CHECKSAVEFILEISYOURS] = function(vm)
  S.answer(vm, saveFileIsYours(vm))
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1173-1177: the
-- pending fade is dropped and the volume goes back to full, which at both
-- call sites follows a `musicfadeout MUSIC_NONE`.
ACTIONS[A.ACTION_0A] = function(vm)
  local h = S.hooks(vm)
  if h.stopMusic then h.stopMusic() end
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1179-1185:
-- sGSBallFlag reads back as GS_BALL_AVAILABLE once the ball has been offered,
-- and the Goldenrod scene gates itself on its own event flag afterwards.
ACTIONS[A.GSBALL] = function(vm, _tower, record)
  local crystal = record and Save.crystalState(record)
  local flag = crystal and crystal.gsBall
  S.answer(vm, Save.GS_BALL_STATES[flag] and BattleTower.GS_BALL_AVAILABLE or 0)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1311-1312
-- String_MysteryJP, the OT the Mobile Stadium stamps on an Odd Egg.
local MYSTERY_OT = "\227\129\170\227\129\158\227\131\138\227\131\142"

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1244-1309: the
-- EGG_TICKET is spent only on a party egg carrying String_MysteryJP.
ACTIONS[A.EGGTICKET] = function(vm, _tower, record)
  S.answer(vm, FALSE)
  local held = record and record.inventory and record.inventory.EGG_TICKET
  if not held or held <= 0 then return end
  for _, mon in ipairs(S.party(vm)) do
    if mon.isEgg and mon.otName == MYSTERY_OT then
      mon.otName = ""
      Bag.remove(record, "EGG_TICKET", 1)
      return S.answer(vm, TRUE)
    end
  end
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1449-1461
ACTIONS[A.ACTION_11] = function(_vm, tower) tower.reentry = false end
ACTIONS[A.ACTION_12] = function(_vm, tower) tower.reentry = true end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1463-1469
ACTIONS[A.ACTION_13] = function(vm, tower)
  S.answer(vm, tower.reentry and TRUE or FALSE)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1471-1483
ACTIONS[A.ACTION_14] = function(vm, _tower, record)
  local yours = saveFileIsYours(vm)
  S.answer(vm, yours)
  if yours == 0 then return end
  S.answer(vm, BattleTower.saveFileFlag(record,
    BattleTower.SAVEFILE_REGISTERED))
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1485-1492
ACTIONS[A.ACTION_15] = function(_vm, _tower, record)
  BattleTower.setSaveFileFlag(record, BattleTower.SAVEFILE_REGISTERED)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:890-904
ACTIONS[A.RESETDATA] = function(_vm, _tower, record)
  BattleTower.resetTrainers(record)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:906-933
ACTIONS[A.GIVEREWARD] = function(vm, tower, record)
  local h = S.hooks(vm)
  local reward = tower.reward or BattleTower.FALLBACK_REWARD
  local data = S.data(vm)
  local fits = false
  if record then
    record.inventory = record.inventory or {}
    fits = BattleTower.rewardFits(Bag.slots(record, data, "ITEM"),
      Bag.capacity(data, "ITEM"), record.inventory[reward])
  end
  if not fits then reward = BattleTower.FALLBACK_REWARD end
  S.answer(vm, (h.itemIndex and h.itemIndex(reward)) or 0)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:935-949
ACTIONS[A.ACTION_1C] = function(_vm, _tower, record)
  BattleTower.setChallengeState(record, BattleTower.WON_CHALLENGE)
end
ACTIONS[A.ACTION_1D] = function(_vm, _tower, record)
  BattleTower.setChallengeState(record, BattleTower.RECEIVED_REWARD)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:955-976.
-- Specials.random answers 1..n, and `% mask` turns that into the 0..mask-1
-- byte `maskbits` leaves in a.
ACTIONS[A.CHOOSEREWARD] = function(vm, tower)
  local data = S.data(vm)
  local order = data and data.gen2Constants and data.gen2Constants.itemOrder
  tower.reward = BattleTower.rollReward(order, Specials.random)
    or BattleTower.FALLBACK_REWARD
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:852-887, the
-- jumptable `special BattleTowerAction` dispatches on wScriptVar.
M.BattleTowerAction = function(vm)
  local id = math.floor(tonumber(vm.scriptVar) or 0)
  -- ../pokecrystal/ram/sram.asm:147-172, read as the zeroes a fresh cart holds.
  local record = S.save(vm) or {}
  local tower = BattleTower.state(record)
  local run = ACTIONS[id]
  if run then return run(vm, tower, record) end
  local mobile = MOBILE_ARMS[id]
  if mobile then
    if mobile.value ~= nil then S.answer(vm, mobile.value) end
    return
  end
  if UNHOOKED_ARMS[id] then return end
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1583-1594: the
-- carry _CheckForBattleTowerRules returns means the party FAILED, and TRUE is
-- what the script's `ifnotequal FALSE` reads as "stop here".
M.CheckForBattleTowerRules = function(vm)
  local lines, failed = BattleTower.checkRules(S.party(vm))
  local data = S.data(vm)
  -- ../pokecrystal/engine/events/battle_tower/rules.asm:28-31 wStringBuffer2
  vm:setStringBuffer(BattleTower.RULE_PARTY_COUNT_TEXT)
  for _, label in ipairs(lines) do
    vm:showRaw(RomText(data, label, RULE_FALLBACKS[label] or label))
  end
  S.answer(vm, failed and TRUE or FALSE)
end

-- ../pokecrystal/mobile/mobile_5f.asm:425-468 and its MenuData at :490-495.
-- wScriptVar comes in TRUE for the English rows and leaves holding the row
-- number, or 4 for a B press.
local CHALLENGE_MENU_ROWS = {
  Strings.source("Challenge"),
  Strings.source("Explanation"),
  Strings.source("Cancel"),
}
local CHALLENGE_MENU_CANCEL = 4

-- ../pokecrystal/mobile/mobile_5f.asm:484-488 MenuHeader, `menu_coords 0, 0,
-- 14, 7` with STATICMENU_CURSOR | STATICMENU_WRAP.
local CHALLENGE_MENU_FLAGS = 0x80 + 0x20

M.Menu_ChallengeExplanationCancel = function(vm)
  local h = S.hooks(vm)
  local choice = Specials.block(vm, function(done)
    if not h.scriptMenu then return done(0) end
    h.scriptMenu({ items = CHALLENGE_MENU_ROWS, left = 0, top = 0,
      right = 14, bottom = 7, dataFlags = CHALLENGE_MENU_FLAGS, cursor = 1 },
      done)
  end)
  choice = math.floor(tonumber(choice) or 0)
  if choice < 1 or choice > #CHALLENGE_MENU_ROWS then
    return S.answer(vm, CHALLENGE_MENU_CANCEL)
  end
  S.answer(vm, choice)
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1534-1550, whose
-- first act is `farcall LoadOpponentTrainerAndPokemon`: the trainer row, the
-- three mons and the two SRAM tables that stop either repeating.  wScriptVar
-- comes in holding the object the opponent walks in as and is NOT written.
M.LoadOpponentTrainerAndPokemonWithOTSprite = function(vm)
  local record = S.save(vm)
  if not record then return end
  -- wBT_OTTrainer is WRAM bank 3, so the drawn opponent rides the VM and not
  -- the save; only the sBTTrainers slot and the two previous teams persist.
  local opponent = BattleTower.drawOpponent(
    S.data(vm), record, Specials.random)
  vm.btOpponent = opponent
  if not opponent then return end
  -- :1552-1575: BTTrainerClassSprites[class - 1] goes into the map object
  -- wScriptVar names, and GetUsedSprite loads the sheet.
  local h = S.hooks(vm)
  if h.setObjectSprite and opponent.sprite then
    h.setObjectSprite(math.floor(tonumber(vm.scriptVar) or 0), opponent.sprite)
  end
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:181-185 and the
-- RunBattleTowerTrainer arm its jumptable runs at :214-259.
--
-- The order there is: SET battle mode forced on, wInBattleTowerBattle set,
-- HealParty, ReadBTTrainerParty (which is what steps the streak counter and
-- arms the challenge), StartBattle, HealParty again, and wBattleResult into
-- wScriptVar.  A win then copies sNrOfBeatenBattleTowerTrainers into
-- wNrOfBeatenBattleTowerTrainers -- the byte the room script `readmem`s to
-- decide whether all seven are done -- and leaves `count + 1` as the digit
-- Text_NextUpOpponentNo prints.
M.BattleTowerBattle = function(vm)
  vm.btBattleEnded = 0
  local record = S.save(vm)
  local data = S.data(vm)
  local h = S.hooks(vm)
  local opponent = vm.btOpponent
  if not opponent and record then
    opponent = BattleTower.drawOpponent(data, record, Specials.random)
    vm.btOpponent = opponent
  end
  -- A cache with no `battleTower` block on trainers.lua has nobody to send
  -- out.  LOSE is the room script's own back-out arm
  -- (../pokecrystal/maps/BattleTowerBattleRoom.asm:34-37), so the challenge
  -- ends rather than looping on an opponent that never appears.
  if not (opponent and record) then
    vm.btBattleEnded = 1
    return S.answer(vm, 1)
  end
  -- :229 ReadBTTrainerParty -> CopyBTTrainer_FromBT_OT_TowBT_OTTemp (:549-570)
  local streak = BattleTower.beginBattle(record)
  -- :228 farcall HealParty, before the send-out.
  if h.healParty then h.healParty() end
  local classes = data and data.trainers and data.trainers.classes
  local class = classes and classes[opponent.classId]
  local className = (class and class.name) or opponent.classId
  local party = BattleTower.battleParty(data, opponent.rows)
  local outcome = Specials.block(vm, function(done)
    if not h.startTowerBattle then return done("lose") end
    local started = h.startTowerBattle({
      class = opponent.class,
      classId = opponent.classId,
      className = className,
      -- PlaceEnemysName prints the class then the trainer's own name, the
      -- same pair World:startScriptedBattle builds for an overworld trainer.
      name = className and (className .. " " .. opponent.name) or opponent.name,
      trainerName = opponent.name,
      party = party,
      -- wOtherTrainerClass is a real class here, so the AI weights, the two
      -- item slots and the payout all come off its own attributes row.
      attributes = class and class.attributes,
      baseMoney = class and class.baseMoney,
      items = class and class.items,
    }, done)
    if not started then done("lose") end
  end)
  -- :235 farcall HealParty, on the way out whichever way it went.
  if h.healParty then h.healParty() end
  -- :236-237 wBattleResult: WIN is 0.
  local won = outcome ~= "lose"
  S.answer(vm, won and 0 or 1)
  if won and vm.mem then
    -- :240-250
    vm.mem[BattleTower.WRAM_NR_BEATEN] = streak % 256
    vm:setStringBuffer(tostring(streak + 1))
  end
  -- :257-258 wBattleTowerBattleEnded = TRUE, which ends _BattleTowerBattle.
  vm.btBattleEnded = 1
  vm.btOpponent = nil
end

-- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:1-5, which is
-- InitBattleTowerChallengeRAM plus _BattleTowerRoomMenu
-- (../pokecrystal/mobile/mobile_46.asm:137-177).  wScriptVar leaves 0 for a
-- chosen room and $a for the cancel the desk loops back on.
M.BattleTowerRoomMenu = function(vm)
  initChallengeRam(vm)
  local h = S.hooks(vm)
  local record = S.save(vm)
  local result = Specials.block(vm, function(done)
    if not h.pushScreen then return done(nil) end
    local ok = h.pushScreen("Gen2BattleTowerMenu", {
      save = record,
      party = S.party(vm),
      rows = BattleTower.levelGroupRows(record),
      monName = h.monName,
      onDone = done,
    })
    if not ok then done(nil) end
  end)
  local group = math.floor(tonumber(result) or 0)
  if group < 1 or group > BattleTower.MAX_LEVEL_GROUP then
    -- ../pokecrystal/mobile/mobile_46.asm:4609-4610
    return S.answer(vm, 0x0a)
  end
  vm.btLevelGroup = group
  S.answer(vm, 0)
end

return M

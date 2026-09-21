-- Shared FRLG std / common scripts (not map-local). Same role as pret
-- data/scripts/pc.inc + pkmn_center_nurse.inc — one definition, every map.

local Flags = require("src.core.game3.scripting.flags")
local Opcodes = require("src.core.game3.scripting.opcodes")
local TextIR = require("src.core.game3.scripting.text_ir")

local Std = {}

local function T(ascii)
  ascii = ascii:gsub("^\n", ""):gsub("\r\n", "\n"):gsub("\n", "\\n")
  return TextIR.fromAscii(ascii)
end

-- 0-based def_special order of pokefirered/data/specials.inc
Std.SPECIAL = {
  HealPlayerParty = 0x00,
  SetUsedPkmnCenterQuestLogEvent = 0x169,
  QuestLog_StartRecordingInputsAfterDeferredEvent = 0x184,
  GetQuestLogState = 0x187,
  QuestLog_CutRecording = 0x188,
  ShowPokemonStorageSystemPC = 0x3C,
  BufferMonNickname = 0x7C, -- pokefirered/data/specials.inc:135
  IsMonOTIDNotPlayers = 0x7D, -- pokefirered/data/specials.inc:136
  ChangePokemonNickname = 0x9E, -- pokefirered/data/specials.inc:169
  ChangeBoxPokemonNickname = 0x166, -- pokefirered/data/specials.inc:369
  BrailleCursorToggle = 0x1B2, -- pokefirered/data/specials.inc:445
  SetFlavorTextFlagFromSpecialVars = 0x173, -- pokefirered/data/specials.inc:382
  UpdatePickStateFromSpecialVar8005 = 0x174, -- pokefirered/data/specials.inc:383
  ChoosePartyMon = 0x9F, -- pokefirered/data/specials.inc:170
  ChooseMonForMoveTutor = 0x18D, -- pokefirered/data/specials.inc:408
  FieldShowRegionMap = 0xFB, -- pokefirered/data/specials.inc:262 ShowTownMap
  AnimatePcTurnOn = 0xD6,
  AnimatePcTurnOff = 0xD7,
  BedroomPC = 0xF9, -- pokefirered/data/specials.inc:260
  PlayerPC = 0xFA,
  CreatePCMenu = 0x106,
  EnterHallOfFame = 0x110, -- 272 (special HallOfFame / GameClear)
  EnableNationalPokedex = 0x16F, -- pokefirered/data/specials.inc:378
  SetUnlockedPokedexFlags = 0x181, -- pokefirered/data/specials.inc:396
  IsNationalPokedexEnabled = 0x193, -- pokefirered/data/specials.inc:414
  Script_SetHelpContext = 0x17D,
  BackupHelpContext = 0x17E,
  RestoreHelpContext = 0x17F,
  SetHelpContextForMap = 0x190,
  HelpSystem_Disable = 0x198,
  HelpSystem_Enable = 0x199,
  StartMarowakBattle = 0x156, -- pokefirered/data/specials.inc:353
  Script_HasTrainerBeenFought = 0x36, -- pokefirered/data/specials.inc:65
  PlayTrainerEncounterMusic = 0x38, -- pokefirered/data/specials.inc:67
  ShouldTryRematchBattle = 0x39, -- pokefirered/data/specials.inc:68
  IsTrainerReadyForRematch = 0x3A, -- pokefirered/data/specials.inc:69
  HasEnoughMonsForDoubleBattle = 0x3D, -- pokefirered/data/specials.inc:72
  SetUpTrainerMovement = 0x13A, -- pokefirered/data/specials.inc:325
  VsSeekerResetObjectMovementAfterChargeComplete = 0x164, -- pokefirered/data/specials.inc:367
  VsSeekerFreezeObjectsAfterChargeComplete = 0x172, -- pokefirered/data/specials.inc:381
  SetBattledTrainerFlag = 0x18F, -- pokefirered/data/specials.inc:410
  ShowEasyChatScreen = 0x5F, -- 95 pokefirered/data/specials.inc:106
  ShowEasyChatMessage = 0x60, -- 96 pokefirered/data/specials.inc:107
  GetBattleOutcome = 0xB4, -- pokefirered/data/specials.inc:191
  GetLeadMonFriendship = 0xE6, -- pokefirered/data/specials.inc:241
  DaisyMassageServices = 0x197, -- pokefirered/data/specials.inc:418
  GetDaycareState = 0xB6, -- pokefirered/data/specials.inc:193
  StartOldManTutorialBattle = 0x9D, -- pokefirered/data/specials.inc:168
  StartGroudonKyogreBattle = 0x137, -- 311 (pokefirered/data/specials.inc:322)
  StartLegendaryBattle = 0x138, -- 312 (pokefirered/data/specials.inc:323)
  StartRegiBattle = 0x139, -- 313 (pokefirered/data/specials.inc:324)
  StartSouthernIslandBattle = 0x143, -- 323 (pokefirered/data/specials.inc:334)
  SetVermilionTrashCans = 0x15B, -- 347 (pokefirered/data/specials.inc:358)
  GetHeracrossSizeRecordInfo = 0x77, -- pokefirered/data/specials.inc:130
  CompareHeracrossSize = 0x78, -- pokefirered/data/specials.inc:131
  GetMagikarpSizeRecordInfo = 0x79, -- pokefirered/data/specials.inc:132
  CompareMagikarpSize = 0x7A, -- pokefirered/data/specials.inc:133
  NameRaterWasNicknameChanged = 0x7B, -- pokefirered/data/specials.inc:134
  CalculatePlayerPartyCount = 0x83, -- pokefirered/data/specials.inc:142
  CountPartyNonEggMons = 0x84, -- pokefirered/data/specials.inc:143
  CountPartyAliveNonEggMons_IgnoreVar0x8004Slot = 0x85, -- pokefirered/data/specials.inc:144
  BufferBigGuyOrBigGirlString = 0x94, -- pokefirered/data/specials.inc:159
  SetHiddenItemFlag = 0x96, -- pokefirered/data/specials.inc:161
  GetSelectedMonNicknameAndSpecies = 0xBA, -- pokefirered/data/specials.inc:197
  IsEnoughForCostInVar0x8005 = 0xC5, -- pokefirered/data/specials.inc:208
  SubtractMoneyFromVar0x8005 = 0xC6, -- pokefirered/data/specials.inc:209
  GetPokedexCount = 0xD4, -- pokefirered/data/specials.inc:223
  GetProfOaksRatingMessage = 0xD5, -- pokefirered/data/specials.inc:224
  GetRandomSlotMachineId = 0x11E, -- pokefirered/data/specials.inc:297
  IsThereRoomInAnyBoxForMorePokemon = 0x130, -- pokefirered/data/specials.inc:315
  GetPartyMonSpecies = 0x147, -- pokefirered/data/specials.inc:338
  IsSelectedMonEgg = 0x148, -- pokefirered/data/specials.inc:339
  HasAllKantoMons = 0x14F, -- pokefirered/data/specials.inc:346
  IsMonOTNameNotPlayers = 0x150, -- pokefirered/data/specials.inc:347
  DoesPartyHaveEnigmaBerry = 0x153, -- pokefirered/data/specials.inc:350
  GetStarterSpecies = 0x162, -- pokefirered/data/specials.inc:365
  SetSeenMon = 0x163, -- pokefirered/data/specials.inc:366
  ShouldShowBoxWasFullMessage = 0x165, -- pokefirered/data/specials.inc:368
  DoesPlayerPartyContainSpecies = 0x17C, -- pokefirered/data/specials.inc:391
  GetPCBoxToSendMon = 0x18A, -- pokefirered/data/specials.inc:405
  HasAtLeastOneBerry = 0x19B, -- pokefirered/data/specials.inc:422
  GetPlayerFacingDirection = 0x1AA, -- pokefirered/data/specials.inc:437
  DoDeoxysTriangleInteraction = 0x1AB, -- pokefirered/data/specials.inc:438
  ValidateSavedWonderCard = 0x180, -- pokefirered/data/specials.inc:395
  GetMysteryGiftCardStat = 0x186, -- pokefirered/data/specials.inc:401
  WonderNews_GetRewardInfo = 0x189, -- pokefirered/data/specials.inc:404
  DoSeagallopFerryScene = 0x17B, -- pokefirered/data/specials.inc:390
  DrawSeagallopDestinationMenu = 0x1A7, -- pokefirered/data/specials.inc:434
  GetSelectedSeagallopDestination = 0x1A8, -- pokefirered/data/specials.inc:435
  GetSeagallopNumber = 0x1A9, -- pokefirered/data/specials.inc:436
  IsPlayerLeftOfVermilionSailor = 0x1AD, -- pokefirered/data/specials.inc:440
  IsBadEggInParty = 0x1AE, -- pokefirered/data/specials.inc:441
  HasAllMons = 0x1B0, -- pokefirered/data/specials.inc:443
  IsPlayerNotInTrainerTowerLobby = 0x1B1, -- pokefirered/data/specials.inc:444
  CallTrainerTowerFunc = 0x194, -- pokefirered/data/specials.inc:415
  SavePlayerParty = 0x27, -- pokefirered/data/specials.inc:50
  LoadPlayerParty = 0x28, -- pokefirered/data/specials.inc:51
  ChooseHalfPartyForBattle = 0x29, -- pokefirered/data/specials.inc:52
  StartSpecialBattle = 0xEC, -- pokefirered/data/specials.inc:247
  ReducePlayerPartyToThree = 0xF8, -- pokefirered/data/specials.inc:259
  ValidateEReaderTrainer = 0xF6, -- pokefirered/data/specials.inc:257
  ChooseMonForMoveRelearner = 0xDB, -- pokefirered/data/specials.inc:230
  SelectMoveDeleterMove = 0xDC, -- pokefirered/data/specials.inc:231
  MoveDeleterForgetMove = 0xDD, -- pokefirered/data/specials.inc:232
  BufferMoveDeleterNicknameAndMove = 0xDE, -- pokefirered/data/specials.inc:233
  GetNumMovesSelectedMonHas = 0xDF, -- pokefirered/data/specials.inc:234
  TeachMoveRelearnerMove = 0xE0, -- pokefirered/data/specials.inc:235
  CheckAddCoins = 0x15E, -- pokefirered/data/specials.inc:361
  CapeBrinkGetMoveToTeachLeadPokemon = 0x1A3, -- pokefirered/data/specials.inc:430
  HasLearnedAllMovesFromCapeBrinkTutor = 0x1A4, -- pokefirered/data/specials.inc:431
  ShowBattleRecords = 0xC4, -- pokefirered/data/specials.inc:207
  PlayerPartyContainsSpeciesWithPlayerID = 0x1B4, -- pokefirered/data/specials.inc:447
  IsDodrioInParty = 0x1B6, -- pokefirered/data/specials.inc:449
  BufferUnionRoomPlayerName = 0x183, -- pokefirered/data/specials.inc:398
  ShowFieldMessageStringVar4 = 0x8D, -- pokefirered/data/specials.inc:152
  DrawWholeMapView = 0x8E, -- pokefirered/data/specials.inc:153
  Script_IsFanClubMemberFanOfPlayer = 0xA3, -- pokefirered/data/specials.inc:174
  Script_GetNumFansOfPlayerInTrainerFanClub = 0xA4, -- pokefirered/data/specials.inc:175
  Script_BufferFanClubTrainerName = 0xA5, -- pokefirered/data/specials.inc:176
  Script_TryLoseFansFromPlayTimeAfterLinkBattle = 0xA6, -- pokefirered/data/specials.inc:177
  Script_TryLoseFansFromPlayTime = 0xA7, -- pokefirered/data/specials.inc:178
  Script_SetPlayerGotFirstFans = 0xA8, -- pokefirered/data/specials.inc:179
  Script_UpdateTrainerFanClubGameClear = 0xA9, -- pokefirered/data/specials.inc:180
  Script_TryGainNewFanFromCounter = 0xAA, -- pokefirered/data/specials.inc:181
  RockSmashWildEncounter = 0xAB, -- pokefirered/data/specials.inc:182
  EnterSafariMode = 0xCD, -- pokefirered/data/specials.inc:216
  ExitSafariMode = 0xCE, -- pokefirered/data/specials.inc:217
  InitRoamer = 0x129, -- pokefirered/data/specials.inc:308
  SetIcefallCaveCrackedIceMetatiles = 0x135, -- pokefirered/data/specials.inc:320
  ShowIcefallCaveCrackedIceAttempt = 0x136, -- pokefirered/data/specials.inc:321
  ShakeScreen = 0x136, -- pokefirered/data/specials.inc:321
  SetPostgameFlagsUnusedSlot = 0x155, -- pokefirered/data/specials.inc:352
  ForcePlayerOntoBike = 0x157, -- pokefirered/data/specials.inc:354
  SampleResortGorgeousMonAndReward = 0x15D, -- pokefirered/data/specials.inc:360
  ForcePlayerToStartSurfing = 0x161, -- pokefirered/data/specials.inc:364
  Field_AskSaveTheGame = 0x5D, -- pokefirered/data/specials.inc:93
  LoadPlayerBag = 0x14B, -- pokefirered/data/specials.inc:331
  SeafoamIslandsB4F_CurrentDumpsPlayerOnLand = 0x15C, -- pokefirered/data/specials.inc:348
  UpdateTrainerCardPhotoIcons = 0x167, -- pokefirered/data/specials.inc:359
  StickerManGetBragFlags = 0x168, -- pokefirered/data/specials.inc:360
  SetWalkingIntoSignVars = 0x170, -- pokefirered/data/specials.inc:368
  DisableMsgBoxWalkaway = 0x171, -- pokefirered/data/specials.inc:380
  SetPostgameFlags = 0x19A, -- pokefirered/data/specials.inc:421
  SetDeoxysTrianglePalette = 0x1AC, -- pokefirered/data/specials.inc:439
  UpdateLoreleiDollCollection = 0x1B9, -- pokefirered/data/specials.inc:452
  CreateEnemyEventMon = 0x1BB, -- pokefirered/data/specials.inc:454
  GetElevatorFloor = 0xD8, -- pokefirered/data/specials.inc:227
  AnimateElevator = 0x111, -- pokefirered/data/specials.inc:284
  SpawnCameraObject = 0x113, -- pokefirered/data/specials.inc:286
  RemoveCameraObject = 0x114, -- pokefirered/data/specials.inc:287
  DrawElevatorCurrentFloorWindow = 0x132, -- pokefirered/data/specials.inc:317
  ListMenu = 0x158, -- pokefirered/data/specials.inc:355
  ReturnToListMenu = 0x159, -- pokefirered/data/specials.inc:356
  CloseElevatorCurrentFloorWindow = 0x160, -- pokefirered/data/specials.inc:363
  AnimateTeleporterHousing = 0x1B5, -- pokefirered/data/specials.inc:448
  AnimateTeleporterCable = 0x1B7, -- pokefirered/data/specials.inc:450
  InitElevatorFloorSelectMenuPos = 0x1B8, -- pokefirered/data/specials.inc:451
  GetInGameTradeSpeciesInfo = 0xFC, -- pokefirered/data/specials.inc:263
  CreateInGameTradePokemon = 0xFD, -- pokefirered/data/specials.inc:264
  DoInGameTradeScene = 0xFE, -- pokefirered/data/specials.inc:265
  GetTradeSpecies = 0xFF, -- pokefirered/data/specials.inc:266
  GetDaycareMonNicknames = 0xB5, -- pokefirered/data/specials.inc:192
  RejectEggFromDayCare = 0xB7, -- pokefirered/data/specials.inc:194
  GiveEggFromDaycare = 0xB8, -- pokefirered/data/specials.inc:195
  SetDaycareCompatibilityString = 0xB9, -- pokefirered/data/specials.inc:196
  StoreSelectedPokemonInDaycare = 0xBB, -- pokefirered/data/specials.inc:198
  ChooseSendDaycareMon = 0xBC, -- pokefirered/data/specials.inc:199
  ShowDaycareLevelMenu = 0xBD, -- pokefirered/data/specials.inc:200
  GetNumLevelsGainedFromDaycare = 0xBE, -- pokefirered/data/specials.inc:201
  GetDaycareCost = 0xBF, -- pokefirered/data/specials.inc:202
  TakePokemonFromDaycare = 0xC0, -- pokefirered/data/specials.inc:203
  GetDaycarePokemonCount = 0x15F, -- pokefirered/data/specials.inc:362
  PutMonInRoute5Daycare = 0x176, -- pokefirered/data/specials.inc:385
  GetCostToWithdrawRoute5DaycareMon = 0x177, -- pokefirered/data/specials.inc:386
  IsThereMonInRoute5Daycare = 0x178, -- pokefirered/data/specials.inc:387
  GetNumLevelsGainedForRoute5DaycareMon = 0x179, -- pokefirered/data/specials.inc:388
  TakePokemonFromRoute5Daycare = 0x17A, -- pokefirered/data/specials.inc:389
  -- Engine-extension specials (not cart indices) for shared primitives.
  FadeScreen = 0xF001,
  OpenNaming = 0xF002,
  PlayCry = 0xF003,
}

Std.SPECIAL_ALIASES = {
  FieldShowRegionMap = "ShowTownMap", -- pokefirered/data/specials.inc:262
  SetPostgameFlagsUnusedSlot = "SetPostgameFlags", -- pokefirered/data/specials.inc:352
}

Std.SPECIAL_ENGINE_BASE = 0xF000

Std.SPECIAL_NAME_BY_ID = {}
for name, id in pairs(Std.SPECIAL) do
  if id < Std.SPECIAL_ENGINE_BASE then
    Std.SPECIAL_NAME_BY_ID[id] = Std.SPECIAL_ALIASES[name] or name
  end
end

Std.TEXT = {
  Text_TownMap = T([[
It's a TOWN MAP.]]),
  Text_WelcomeWantToHealPkmn = T([[
Welcome to our POKéMON CENTER!\p
Would you like me to heal your
POKéMON to perfect health?]]),
  Text_TakeYourPkmnForFewSeconds = T([[
OK, may I see your POKéMON?]]),
  Text_RestoredPkmnToFullHealth = T([[
Thank you for waiting.
Your POKéMON are fully healed.]]),
  Text_WeHopeToSeeYouAgain = T([[
We hope to see you again!]]),
  Text_BootedUpPC = T([[
{PLAYER} booted up the PC.]]),
  Text_UsualPCServicesUnavailable = T([[
The usual PC services aren't
available right now…]]),
  -- obtain_item.inc (simplified host strings)
  Text_ObtainedTheX = T([[
{PLAYER} obtained
the {STR_VAR_2}!]]),
  Text_PutItemAway = T([[
{PLAYER} put away the
{STR_VAR_2} in the {STR_VAR_3}.]]),
  Text_TooBadBagFull = T([[
Too bad!
The BAG is full…]]),
  Text_FoundOneItem = T([[
{PLAYER} found one {STR_VAR_2}!]]),
  Text_FoundTMHMContainsMove = T([[
{PLAYER} found
{STR_VAR_2}!]]),
}

-- Cart EventScript_PC (simplified host path: open full storage UI).
Std.SCRIPTS = {
  EventScript_WallTownMap = {
    { op = "lockall" },
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_DEFAULT },
    { op = "fadescreen", [1] = 1 },
    { op = "special", id = Std.SPECIAL.FieldShowRegionMap },
    { op = "waitstate" },
    { op = "releaseall" },
    { op = "end" },
  },
  EventScript_PC = {
    { op = "lockall" },
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "special", id = Std.SPECIAL.AnimatePcTurnOn },
    { op = "loadword", dest = 0, value = "Text_BootedUpPC" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "special", id = Std.SPECIAL.CreatePCMenu },
    { op = "waitstate" },
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "special", id = Std.SPECIAL.AnimatePcTurnOff },
    { op = "releaseall" },
    { op = "end" },
  },
  -- Pret shape: welcome → YES/NO → take&heal (turn left → FLDEFF_POKECENTER_HEAL
  -- → turn down → HealPlayerParty) → restored → bow → goodbye.
  EventScript_PkmnCenterNurse = {
    { op = "loadword", dest = 0, value = "Text_WelcomeWantToHealPkmn" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_YESNO },
    { op = "compare_var_to_value", var = 0x800D, value = 0 },
    { op = "goto_if", cond = 1, target = "EventScript_PkmnCenterNurse_Goodbye" },
    { op = "loadword", dest = 0, value = "Text_TakeYourPkmnForFewSeconds" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "call", target = "EventScript_PkmnCenterNurse_TakeAndHealPkmn" },
    { op = "goto", target = "EventScript_PkmnCenterNurse_ReturnPkmn" },
  },
  -- pret EventScript_PkmnCenterNurse_TakeAndHealPkmn
  EventScript_PkmnCenterNurse_TakeAndHealPkmn = {
    -- WalkInPlaceFasterLeft / Down (0x2F / 0x2D) + step_end
    { op = "applymovement", localId = 0x800F, movement = { 0x2F, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "dofieldeffect", [1] = 25 },
    { op = "waitfieldeffect", [1] = 25 },
    { op = "applymovement", localId = 0x800F, movement = { 0x2D, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "special", id = Std.SPECIAL.HealPlayerParty },
    { op = "return" },
  },
  EventScript_PkmnCenterNurse_ReturnPkmn = {
    { op = "loadword", dest = 0, value = "Text_RestoredPkmnToFullHealth" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    -- nurse_joy_bow (0x5B) + delay_4 (0x1A) + step_end
    { op = "applymovement", localId = 0x800F, movement = { 0x5B, 0x1A, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "goto", target = "EventScript_PkmnCenterNurse_Goodbye" },
  },
  EventScript_PkmnCenterNurse_Goodbye = {
    { op = "loadword", dest = 0, value = "Text_WeHopeToSeeYouAgain" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_DEFAULT },
    { op = "return" },
  },
  -- Economy / item stds (pret obtain_item.inc). Pocket name → STR_VAR_3.
  EventScript_RestorePrevTextColor = { -- data/scripts/obtain_item.inc:6
    { op = "copyvar", [1] = 0x8012, [2] = 0x8013 },
    { op = "return" },
  },
  ["std:0"] = { -- STD_OBTAIN_ITEM, data/scripts/obtain_item.inc:10
    { op = "copyvar", [1] = 0x8013, [2] = 0x8012 },
    { op = "textcolor", color = 3, [1] = 3 },
    { op = "additem", [1] = 0x8000, [2] = 0x8001 },
    { op = "copyvar", [1] = 0x8007, [2] = 0x800D },
    { op = "call", target = "EventScript_ObtainItemMessage" },
    { op = "copyvar", [1] = 0x8012, [2] = 0x8013 },
    { op = "return" },
  },
  EventScript_ObtainItemMessage = {
    { op = "bufferitemname", dest = 1, src = 0x8000 }, -- STR_VAR_2
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "compare_var_to_value", var = 0x8007, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_ObtainedItem" },
    { op = "setvar", var = 0x800D, value = 0 },
    { op = "return" },
  },
  EventScript_ObtainedItem = {
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "loadword", dest = 0, value = "Text_ObtainedTheX" },
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 1 },
    { op = "return" },
  },
  EventScript_BufferPocketName = {
    { op = "compare_var_to_value", var = 0x800D, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferItemsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 2 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferKeyItemsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 3 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferPokeBallsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 4 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferTMCase" },
    { op = "compare_var_to_value", var = 0x800D, value = 5 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferBerryPouch" },
    { op = "bufferstdstring", dest = 2, src = 24 }, -- STR_VAR_3 ITEMS POCKET
    { op = "return" },
  },
  EventScript_BufferItemsPocket = {
    { op = "bufferstdstring", dest = 2, src = 24 },
    { op = "return" },
  },
  EventScript_BufferKeyItemsPocket = {
    { op = "bufferstdstring", dest = 2, src = 25 },
    { op = "return" },
  },
  EventScript_BufferPokeBallsPocket = {
    { op = "bufferstdstring", dest = 2, src = 26 },
    { op = "return" },
  },
  EventScript_BufferTMCase = {
    { op = "bufferstdstring", dest = 2, src = 27 },
    { op = "return" },
  },
  EventScript_BufferBerryPouch = {
    { op = "bufferstdstring", dest = 2, src = 28 },
    { op = "return" },
  },
  ["std:1"] = { -- STD_FIND_ITEM
    { op = "checkitemspace", [1] = 0x8000, [2] = 0x8001 },
    { op = "copyvar", [1] = 0x8007, [2] = 0x800D },
    { op = "bufferitemname", dest = 1, src = 0x8000 },
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "compare_var_to_value", var = 0x8007, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_PickUpItem" },
    { op = "loadword", dest = 0, value = "Text_TooBadBagFull" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 0 },
    { op = "return" },
  },
  EventScript_PickUpItem = {
    { op = "removeobject", [1] = 0x800F },
    { op = "additem", [1] = 0x8000, [2] = 0x8001 },
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "loadword", dest = 0, value = "Text_FoundOneItem" },
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 1 },
    { op = "return" },
  },
  ["std:2"] = { -- MSGBOX_NPC, data/scripts/std_msgbox.inc:6
    { op = "lock" },
    { op = "faceplayer" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "release" },
    { op = "return" },
  },
  ["std:3"] = { -- MSGBOX_SIGN, data/scripts/std_msgbox.inc:14
    { op = "lockall" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "releaseall" },
    { op = "return" },
  },
  ["std:4"] = { -- MSGBOX_DEFAULT, data/scripts/std_msgbox.inc:22
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:5"] = { -- MSGBOX_YESNO, data/scripts/std_msgbox.inc:27
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "yesnobox", [1] = 20, [2] = 8 },
    { op = "return" },
  },
  ["std:6"] = { -- MSGBOX_AUTOCLOSE, data/scripts/std_msgbox.inc:32
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "release" },
    { op = "return" },
  },
  ["std:8"] = { -- STD_PUT_ITEM_AWAY
    { op = "bufferitemname", dest = 1, src = 0x8000 },
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:9"] = { -- STD_RECEIVED_ITEM (msgreceiveditem)
    { op = "textcolor", color = 3, [1] = 3 }, -- data/scripts/std_msgbox.inc:30
    { op = "compare_var_to_value", var = 0x8002, value = 318 }, -- MUS_OBTAIN_KEY_ITEM
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareKeyItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 258 }, -- MUS_OBTAIN_ITEM
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 257 }, -- MUS_LEVEL_UP
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareLevelUp" },
    { op = "goto", target = "EventScript_ReceivedItemFanfareDefault" },
  },
  EventScript_ReceivedItemFanfareKeyItem = {
    { op = "playfanfare", [1] = 318 }, -- MUS_OBTAIN_KEY_ITEM
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareItem = {
    { op = "playfanfare", [1] = 258 }, -- MUS_OBTAIN_ITEM
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareLevelUp = {
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareDefault = {
    { op = "playfanfare", [1] = 0x8002 }, -- VAR_0x8002 fallback
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemShowMsg = {
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "callstd", std = 8 }, -- STD_PUT_ITEM_AWAY
    { op = "call", target = "EventScript_RestorePrevTextColor" },
    { op = "return" },
  },
}

return Std

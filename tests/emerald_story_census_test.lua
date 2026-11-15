package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function cacheRoot()
  local explicit = os.getenv("POKEPORT_EMERALD_CACHE")
  if explicit and explicit ~= "" then return explicit end
  local identity = os.getenv("POKEPORT_IDENTITY")
  local home = os.getenv("HOME")
  if not (identity and identity ~= "" and home) then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
    local root = base .. identity .. "/emerald"
    local f = io.open(root .. "/data/generated/gba/scripts/scripts.lua", "rb")
    if f then
      f:close()
      return root
    end
  end
  return nil
end

local ROOT = cacheRoot() or require("tests.game3_cache").gameDir("emerald", "scripts/scripts.lua")
if not ROOT then
  print("emerald_story_census_test: skipped (set POKEPORT_IDENTITY to an identity with an Emerald cache)")
  os.exit(0)
end

local function loadLua(rel)
  local f = io.open(ROOT .. "/" .. rel, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("emerald")

local Natives = require("src.core.game3.scripting.natives")
local C = require("src.core.game3.constants").of("emerald")
local S = "data/generated/gba/scripts/"
local scripts = assert(loadLua(S .. "scripts.lua"), "scripts.lua")
local events = assert(loadLua(S .. "events.lua"), "events.lua")

local OWNERS = {
  BattlePyramidChooseMonHeldItems = "W5 Battle Frontier",
  BattleSetup_StartRematchBattle = "W3 battle setup / trainers (B1-B3, FC)",
  BattleTowerReconnectLink = "W5 Battle Frontier",
  BufferBattleFrontierTutorMoveName = "W5 Battle Frontier",
  BufferBattleTowerElevatorFloors = "W5 Battle Frontier",
  BufferContestTrainerAndMonNames = "W4 contests (E14)",
  BufferContestWinnerMonName = "W4 contests (E14)",
  BufferContestWinnerTrainerName = "W4 contests (E14)",
  BufferDeepLinkPhrase = "W5 link",
  BufferEReaderTrainerName = "W5 e-Reader",
  BufferFavorLadyItemName = "W4 Lilycove lady (E15)",
  BufferFavorLadyPlayerName = "W4 Lilycove lady (E15)",
  BufferFavorLadyRequest = "W4 Lilycove lady (E15)",
  BufferLottoTicketNumber = "W4 lottery (E16)",
  BufferMoveDeleterNicknameAndMove = "W3 UI party menu / move tutor (UA-UD)",
  BufferQuizAuthorNameAndCheckIfLady = "W4 Lilycove lady (E15)",
  BufferQuizCorrectAnswer = "W4 Lilycove lady (E15)",
  BufferQuizPrizeItem = "W4 Lilycove lady (E15)",
  BufferQuizPrizeName = "W4 Lilycove lady (E15)",
  BufferTrendyPhraseString = "W4 Dewford trend (E8)",
  BufferUnionRoomPlayerName = "W5 link / union room",
  CallApprenticeFunction = "W5 apprentice",
  CallBattleArenaFunction = "W5 Battle Frontier",
  CallBattleDomeFunction = "W5 Battle Frontier",
  CallBattleFactoryFunction = "W5 Battle Frontier",
  CallBattlePalaceFunction = "W5 Battle Frontier",
  CallBattlePikeFunction = "W5 Battle Frontier",
  CallBattlePyramidFunction = "W5 Battle Frontier",
  CallBattleTowerFunc = "W5 Battle Frontier",
  CallFallarborTentFunction = "W5 battle tents",
  CallSlateportTentFunction = "W5 battle tents",
  CallTrainerHillFunction = "W5 trainer hill",
  CallVerdanturfTentFunction = "W5 battle tents",
  CheckInteractedWithFriendsCushionDecor = "W4 secret bases (E12)",
  CheckInteractedWithFriendsDollDecor = "W4 secret bases (E12)",
  CheckInteractedWithFriendsFurnitureBottom = "W4 secret bases (E12)",
  CheckInteractedWithFriendsFurnitureMiddle = "W4 secret bases (E12)",
  CheckInteractedWithFriendsFurnitureTop = "W4 secret bases (E12)",
  CheckInteractedWithFriendsPosterDecor = "W4 secret bases (E12)",
  CheckInteractedWithFriendsSandOrnament = "W4 secret bases (E12)",
  CheckLeadMonBeauty = "W4 contests (E14)",
  CheckLeadMonCool = "W4 contests (E14)",
  CheckLeadMonCute = "W4 contests (E14)",
  CheckLeadMonSmart = "W4 contests (E14)",
  CheckLeadMonTough = "W4 contests (E14)",
  CheckPlayerHasSecretBase = "W4 secret bases (E12)",
  ChooseItemsToTossFromPyramidBag = "W5 Battle Frontier",
  ChooseMonForMoveRelearner = "W3 UI party menu / move tutor (UA-UD)",
  ChooseMonForMoveTutor = "W5 Battle Frontier tutors",
  ChooseMonForWirelessMinigame = "W3 UI party menu / move tutor (UA-UD)",
  ChoosePartyForBattleFrontier = "W5 Battle Frontier",
  CleanupLinkRoomState = "W5 link",
  ClearAndLeaveSecretBase = "W4 secret bases (E12)",
  ClearLinkContestFlags = "W5 link",
  ClearQuizLadyPlayerAnswer = "W4 Lilycove lady (E15)",
  ClearQuizLadyQuestionAndAnswer = "W4 Lilycove lady (E15)",
  CloseBattleFrontierTutorWindow = "W5 Battle Frontier",
  CloseBattlePikeCurtain = "W5 Battle Frontier",
  CloseBattlePointsWindow = "W5 Battle Frontier",
  CloseFrontierExchangeCornerItemIconWindow = "W5 Battle Frontier",
  CloseLink = "W5 link",
  ColosseumPlayerSpotTriggered = "W5 link / cable club",
  CompareLotadSize = "W4 size records (E-misc)",
  CompareSeedotSize = "W4 size records (E-misc)",
  CopyCurSecretBaseOwnerName_StrVar1 = "W4 secret bases (E12)",
  CopyEReaderTrainerGreeting = "W5 e-Reader",
  CountPlayerMuseumPaintings = "W4 contests (E14)",
  CountPlayerTrainerStars = "W5 link trainer card",
  CreateAbnormalWeatherEvent = "FB abnormal weather (post-game)",
  CreateEnemyEventMon = "W3 queries / scripted battles",
  CreateInGameTradePokemon = "W4 in-game trades",
  DeclinedSecretBaseBattle = "W4 secret bases (E12)",
  DidFavorLadyLikeItem = "W4 Lilycove lady (E15)",
  DisplayBerryPowderVendorMenu = "W4 berry powder (E7)",
  DoBattlePyramidMonsHaveHeldItem = "W5 Battle Frontier",
  DoBerryBlending = "W4 berry blender (E13)",
  DoCableClubWarp = "W3 field warps / link rooms (FA-FC)",
  DoContestHallWarp = "W3 field warps / link rooms (FA-FC)",
  DoDeoxysRockInteraction = "W5 event islands (E26)",
  DoDomeConfetti = "W3 HoF",
  DoFallWarp = "W3 field warps / link rooms (FA-FC)",
  DoInGameTradeScene = "W4 in-game trades",
  DoLotteryCornerComputerEffect = "W4 lottery (E16)",
  DoSecretBasePCTurnOffEffect = "W4 secret bases (E12)",
  DoTrainerApproach = "W3 trainer sight (FC)",
  DoWaldaNamingScreen = "W5 Walda phrase",
  DoesPartyHaveEnigmaBerry = "W5 frontier party select",
  DoesPlayerHaveNoDecorations = "W4 Mauville trader (E10)",
  DrewSecretBaseBattle = "W4 secret bases (E12)",
  EggHatch = "W3 egg hatch UI (step_events owner)",
  EndLotteryCornerComputerEffect = "W4 lottery (E16)",
  EnterNewlyCreatedSecretBase = "W4 secret bases (E12)",
  EnterSecretBase = "W4 secret bases (E12)",
  ExitLinkRoom = "W5 link",
  FavorLadyGetPrize = "W4 Lilycove lady (E15)",
  GabbyAndTyAfterInterview = "W4 TV shows (E23)",
  GabbyAndTyBeforeInterview = "W4 TV shows (E23)",
  GabbyAndTyGetBattleNum = "W4 TV shows (E23)",
  GabbyAndTyGetLastBattleTrivia = "W4 TV shows (E23)",
  GabbyAndTyGetLastQuote = "W4 TV shows (E23)",
  GenerateContestRand = "W4 contests (E14)",
  GenerateGiddyLine = "W4 Mauville old man (E10)",
  GetAbnormalWeatherMapNameAndType = "FB abnormal weather (post-game)",
  GetBattleFrontierTutorMoveIndex = "W5 Battle Frontier",
  GetBattlePyramidHint = "W5 Battle Frontier",
  GetContestLadyCategory = "W4 Lilycove lady (E15)",
  GetContestLadyMonSpecies = "W4 Lilycove lady (E15)",
  GetContestMonCondition = "W4 contests (E14)",
  GetContestMultiplayerId = "W4 contests (E14)",
  GetContestPlayerId = "W4 contests (E14)",
  GetContestWinnerId = "W4 contests (E14)",
  GetCurSecretBaseRegistrationValidity = "W4 secret bases (E12)",
  GetDewfordHallPaintingNameIndex = "W4 Dewford trend (E8)",
  GetFavorLadyState = "W4 Lilycove lady (E15)",
  GetFirstFreePokeblockSlot = "W4 game corner (E11)",
  GetFrontierBattlePoints = "W5 Battle Frontier",
  GetGabbyAndTyLocalIds = "W4 TV shows (E23)",
  GetInGameTradeSpeciesInfo = "W4 in-game trades",
  GetLilycoveSSTidalSelection = "W3 UI script menus (UA-UD)",
  GetLinkPartnerNames = "W5 link",
  GetLotadSizeRecordInfo = "W4 size records (E-misc)",
  GetMartEmployeeObjectEventId = "W4 Lilycove lady (E15)",
  GetNumMovesSelectedMonHas = "W3 UI party menu / move tutor (UA-UD)",
  GetPokeblockFeederInFront = "W4 pokeblocks (E13)",
  GetPokeblockNameByMonNature = "W4 pokeblocks (E13)",
  GetQuizAuthor = "W4 Lilycove lady (E15)",
  GetQuizLadyState = "W4 Lilycove lady (E15)",
  GetSecretBaseNearbyMapName = "W4 secret bases (E12)",
  GetSecretBaseOwnerAndState = "W4 secret bases (E12)",
  GetSecretBaseTypeInFrontOfPlayer = "W4 secret bases (E12)",
  GetSeedotSizeRecordInfo = "W4 size records (E-misc)",
  GetSlotMachineId = "W4 game corner (E11)",
  GetTradeSpecies = "W4 in-game trades",
  GetTraderTradedFlag = "W4 Mauville trader (E10)",
  GetTrainerBattleMode = "W3 battle setup / trainers (B1-B3, FC)",
  GetTrainerFlag = "W3 battle setup / trainers (B1-B3, FC)",
  GiddyShouldTellAnotherTale = "W4 Mauville old man (E10)",
  GiveFrontierBattlePoints = "W5 Battle Frontier",
  GiveMonArtistRibbon = "W4 contests (E14)",
  GiveMonContestRibbon = "W4 contests (E14)",
  HasAllHoennMons = "W3 pokedex (UB)",
  HasAnotherPlayerGivenFavorLadyItem = "W4 Lilycove lady (E15)",
  HasAtLeastOneBerry = "W3 bag queries",
  HasBardSongBeenChanged = "W4 Mauville old man (E10)",
  HasEnoughBerryPowder = "W4 berry powder (E7)",
  HasEnoughMonsForDoubleBattle = "W5 frontier party select",
  HasHipsterTaughtWord = "W4 Mauville old man (E10)",
  HasMonWonThisContestBefore = "W4 contests (E14)",
  HasPlayerGivenContestLadyPokeblock = "W4 pokeblocks (E13)",
  HasStorytellerAlreadyRecorded = "W4 Mauville old man (E10)",
  HideContestEntryMonPic = "W4 contests (E14)",
  HipsterTryTeachWord = "W4 Mauville old man (E10)",
  InitSecretBaseVars = "W4 secret bases (E12)",
  InitUnionRoom = "W5 link / union room",
  InteractWithShieldOrTVDecoration = "W4 secret base field effects",
  InterviewAfter = "W4 TV shows (E23)",
  InterviewBefore = "W4 TV shows (E23)",
  IsContestDebugActive = "W4 contests (E14)",
  IsContestWithRSPlayer = "W4 contests (E14)",
  IsCurSecretBaseOwnedByAnotherPlayer = "W4 secret bases (E12)",
  IsDecorationCategoryFull = "W4 Mauville trader (E10)",
  IsDodrioInParty = "W4 wireless minigames",
  IsFavorLadyThresholdMet = "W4 Lilycove lady (E15)",
  IsLastMonThatKnowsSurf = "W3 UI party menu / move tutor (UA-UD)",
  IsLeadMonNicknamedOrNotEnglish = "W4 TV shows (E23)",
  IsPokemonJumpSpeciesInParty = "W4 wireless minigames",
  IsQuizAnswerCorrect = "W4 Lilycove lady (E15)",
  IsQuizLadyWaitingForChallenger = "W4 Lilycove lady (E15)",
  IsSelectedMonEgg = "W3 UI party menu / move tutor (UA-UD)",
  IsTrendyPhraseBoring = "W4 Dewford trend (E8)",
  IsWirelessAdapterConnected = "W5 link",
  IsWirelessContest = "W4 contests (E14)",
  LinkContestTryHideWirelessIndicator = "W5 link",
  LinkContestTryShowWirelessIndicator = "W5 link",
  LinkContestWaitForConnection = "W5 link",
  LinkRetireStatusWithBattleTowerPartner = "W5 Battle Frontier",
  LoadLinkContestPlayerPalettes = "W5 link",
  LoadPlayerBag = "W5 frontier party save",
  LookThroughPorthole = "W4 SS Tidal porthole (FC special scenes)",
  LostSecretBaseBattle = "W4 secret bases (E12)",
  MoveDeleterChooseMoveToForget = "W3 UI party menu / move tutor (UA-UD)",
  MoveDeleterForgetMove = "W3 UI party menu / move tutor (UA-UD)",
  MoveOutOfSecretBase = "W4 secret bases (E12)",
  MoveOutOfSecretBaseFromOutside = "W4 secret bases (E12)",
  OffsetCameraForBattle = "W5 Battle Frontier",
  OpenPokeblockCaseForContestLady = "W4 pokeblocks (E13)",
  OpenPokeblockCaseOnFeeder = "W4 pokeblocks (E13)",
  PickLotteryCornerTicket = "W4 lottery (E16)",
  PlayBardSong = "W4 Mauville old man (E10)",
  PlayRoulette = "W4 game corner (E11)",
  PlayTrainerEncounterMusic = "W3 battle setup / trainers (B1-B3, FC)",
  PlayerEnteredTradeSeat = "W5 link / cable club",
  PlayerFaceTrainerAfterBattle = "W3 trainer sight (FC)",
  PlayerNotAtTrainerHillEntrance = "W5 trainer hill",
  PrepSecretBaseBattleFlags = "W4 secret bases (E12)",
  PrintPlayerBerryPowderAmount = "W4 berry powder (E7)",
  PutAwayDecorationIteration = "W4 decorations (E12)",
  PutFanClubSpecialOnTheAir = "W4 trainer fan club (E9)",
  PutLilycoveContestLadyShowOnTheAir = "W4 TV shows (E23)",
  QuizLadyGetPlayerAnswer = "W4 Lilycove lady (E15)",
  QuizLadyPickNewQuestion = "W4 Lilycove lady (E15)",
  QuizLadyRecordCustomQuizData = "W4 Lilycove lady (E15)",
  QuizLadySetCustomQuestion = "W4 Lilycove lady (E15)",
  QuizLadySetWaitingForChallenger = "W4 Lilycove lady (E15)",
  QuizLadyShowQuizQuestion = "W4 easy chat (UI)",
  QuizLadyTakePrizeForCustomQuiz = "W4 Lilycove lady (E15)",
  RecordMixingPlayerSpotTriggered = "W5 record mixing",
  RemoveBerryPowderVendorMenu = "W4 berry powder (E7)",
  RemoveRecordsWindow = "W5 link battle records",
  RetrieveLotteryNumber = "W4 lottery (E16)",
  ReturnFromLinkRoom = "W5 link",
  RockSmashWildEncounter = "W3 wild encounters (rock smash)",
  RunUnionRoom = "W5 link / union room",
  SaveBardSongLyrics = "W4 Mauville old man (E10)",
  SaveForBattleTowerLink = "W5 Battle Frontier",
  SaveGame = "W3 save menu (UI)",
  SaveMuseumContestPainting = "W4 contests (E14)",
  ScriptMenu_CreateLilycoveSSTidalMultichoice = "W3 UI script menus (UA-UD)",
  Script_BufferContestLadyCategoryAndMonName = "W4 Lilycove lady (E15)",
  Script_ClearHeldMovement = "W5 link rooms",
  Script_DoesFavorLadyLikeItem = "W4 Lilycove lady (E15)",
  Script_FacePlayer = "W5 link rooms",
  Script_FavorLadyOpenBagMenu = "W4 Lilycove lady (E15)",
  Script_GetCurrentMauvilleMan = "W4 Mauville old man (E10)",
  Script_GetLilycoveLadyId = "W4 Lilycove lady (E15)",
  Script_QuizLadyOpenBagMenu = "W4 Lilycove lady (E15)",
  Script_ResetUnionRoomTrade = "W5 link / union room",
  Script_ShowLinkTrainerCard = "W5 link",
  Script_StorytellerDisplayStory = "W4 Mauville old man (E10)",
  Script_StorytellerInitializeRandomStat = "W4 Mauville old man (E10)",
  ScrollRankingHallRecordsWindow = "W5 Battle Frontier",
  SetBattleTowerLinkPlayerGfx = "W5 Battle Frontier",
  SetBattledOwnerFromResult = "W4 secret bases (E12)",
  SetCableClubWarp = "W5 link",
  SetContestCategoryStringVarForInterview = "W4 TV shows (E23)",
  SetContestLadyGivenPokeblock = "W4 pokeblocks (E13)",
  SetContestTrainerGfxIds = "W4 contests (E14)",
  SetDecoration = "W4 decorations (E12)",
  SetDeoxysRockPalette = "W5 event islands (E26)",
  SetEReaderTrainerGfxId = "W5 e-Reader",
  SetFavorLadyState_Complete = "W4 Lilycove lady (E15)",
  SetHipsterTaughtWord = "W4 Mauville old man (E10)",
  SetLilycoveLadyGfx = "W4 Lilycove lady (E15)",
  SetLinkContestPlayerGfx = "W5 link",
  SetMauvilleOldManObjEventGfx = "W4 Mauville old man (E10)",
  SetPlayerSecretBase = "W4 secret bases (E12)",
  SetQuizLadyState_Complete = "W4 Lilycove lady (E15)",
  SetQuizLadyState_GivePrize = "W4 Lilycove lady (E15)",
  SetSecretBaseOwnerGfxId = "W4 secret bases (E12)",
  SetTrainerFacingDirection = "W3 battle setup / trainers (B1-B3, FC)",
  SetUnlockedPokedexFlags = "W3 HoF / champion save (UI)",
  ShouldContestLadyShowGoOnAir = "W4 Lilycove lady (E15)",
  ShouldHideFanClubInterviewer = "W4 trainer fan club (E9)",
  ShouldReadyContestArtist = "W4 contests (E14)",
  ShouldShowBoxWasFullMessage = "W3 PC storage (UI)",
  ShouldTryGetTrainerScript = "W3 battle setup / trainers (B1-B3, FC)",
  ShowBattlePointsWindow = "W5 Battle Frontier",
  ShowBerryBlenderRecordWindow = "W4 berry blender (E13)",
  ShowBerryCrushRankings = "W4 wireless minigames",
  ShowContestEntryMonPic = "W4 contests (E14)",
  ShowDodrioBerryPickingRecords = "W4 wireless minigames",
  ShowEasyChatProfile = "W4 easy chat (UI)",
  ShowEasyChatScreen = "W4 easy chat (UI)",
  ShowFrontierExchangeCornerItemIconWindow = "W5 Battle Frontier",
  ShowFrontierGamblerGoMessage = "W5 Battle Frontier",
  ShowFrontierGamblerLookingMessage = "W5 Battle Frontier",
  ShowFrontierManiacMessage = "W5 Battle Frontier",
  ShowLinkBattleRecords = "W5 link",
  ShowMapNamePopup = "W5 pyramid map popup",
  ShowNatureGirlMessage = "W5 Battle Frontier",
  ShowPokemonJumpRecords = "W4 wireless minigames",
  ShowRankingHallRecordsWindow = "W5 Battle Frontier",
  ShowSecretBaseDecorationMenu = "W4 secret bases (E12)",
  ShowSecretBaseRegistryMenu = "W4 secret bases (E12)",
  ShowTrainerCantBattleSpeech = "W3 battle setup / trainers (B1-B3, FC)",
  ShowTrainerHillRecords = "W5 trainer hill",
  ShowTrainerIntroSpeech = "W3 battle setup / trainers (B1-B3, FC)",
  ShowWirelessCommunicationScreen = "W5 link",
  SpawnLinkPartnerObjectEvent = "W5 link",
  Special_ShowDiploma = "W3 UI diploma",
  StorytellerGetFreeStorySlot = "W4 game corner (E11)",
  StorytellerStoryListMenu = "W4 Mauville old man (E10)",
  StorytellerUpdateStat = "W4 Mauville old man (E10)",
  TakeBerryPowder = "W4 berry powder (E7)",
  TakeFrontierBattlePoints = "W5 Battle Frontier",
  TeachMoveRelearnerMove = "W3 move relearner (UI)",
  ToggleCurSecretBaseRegistry = "W4 secret bases (E12)",
  TraderDoDecorationTrade = "W4 Mauville trader (E10)",
  TraderMenuGetDecoration = "W4 Mauville trader (E10)",
  TraderShowDecorationMenu = "W4 Mauville trader (E10)",
  TryBattleLinkup = "W5 link",
  TryBecomeLinkLeader = "W5 link",
  TryBerryBlenderLinkup = "W5 link",
  TryBufferWaldaPhrase = "W5 Walda phrase",
  TryContestEModeLinkup = "W5 link",
  TryContestGModeLinkup = "W5 link",
  TryEnterContestMon = "W4 contests (E14)",
  TryFieldPoisonWhiteOut = "W3 field poison (step_events owner)",
  TryGetWallpaperWithWaldaPhrase = "W5 Walda phrase",
  TryHideBattleTowerReporter = "W5 Battle Frontier",
  TryJoinLinkGroup = "W5 link",
  TryPrepareSecondApproachingTrainer = "W3 trainer sight (FC)",
  TryPutLotteryWinnerReportOnAir = "W4 lottery (E16)",
  TryPutNameRaterShowOnTheAir = "W4 TV shows (E23)",
  TryPutTrainerFanClubOnAir = "W4 trainer fan club (E9)",
  TryPutTreasureInvestigatorsOnAir = "W4 TV shows (E23)",
  TryRecordMixLinkup = "W5 link",
  TrySetBattleTowerLinkType = "W5 Battle Frontier",
  TryStoreHeldItemsInPyramidBag = "W5 Battle Frontier",
  TryTradeLinkup = "W5 link",
  UpdateBattlePointsWindow = "W5 Battle Frontier",
  ValidateMixingGameLanguage = "W5 link / cable club",
  ValidateSavedWonderCard = "W5 mystery gift",
  WonSecretBaseBattle = "W4 secret bases (E12)",
}

local XA = {
  "CableCar", "CableCarWarp", "Script_DoRayquazaScene", "MauvilleGymPressSwitch", "MauvilleGymSetDefaultBarriers",
  "MauvilleGymDeactivatePuzzle", "PetalburgGymSlideOpenRoomDoors", "PetalburgGymUnlockRoomDoors",
  "FoundAbandonedShipRoom1Key", "FoundAbandonedShipRoom2Key", "FoundAbandonedShipRoom4Key", "FoundAbandonedShipRoom6Key",
  "SetRoute119Weather", "SetRoute123Weather", "LoadWallyZigzagoon", "IsStarterInParty", "TryUpdateRusturfTunnelState",
  "BufferVarsForIVRater", "LeadMonHasEffortRibbon", "GiveLeadMonEffortRibbon", "Special_AreLeadMonEVsMaxedOut",
  "SetTrickHouseNuggetFlag", "ResetTrickHouseNuggetFlag", "GetWeekCount", "FoundBlackGlasses", "ShowScrollableMultichoice",
  "Special_BeginCyclingRoadChallenge", "FinishCyclingRoadChallenge", "GetRecordedCyclingRoadResults", "UpdateCyclingRoadState",
  "MoveElevator", "SetDeptStoreFloor", "GetDeptStoreDefaultFloorChoice", "ShowDeptStoreElevatorFloorSelect",
  "CloseDeptStoreElevatorWindow", "UpdateShoalTideFlag", "IsMirageIslandPresent", "WaitWeather", "InitBirchState",
  "GetDaysUntilPacifidlogTMAvailable", "SetPacifidlogTMReceivedDay", "GetDaycareState", "ChooseSendDaycareMon",
  "StoreSelectedPokemonInDaycare", "TakePokemonFromDaycare", "GetDaycareMonNicknames", "GetNumLevelsGainedFromDaycare",
  "GetDaycareCostAndPrepareString", "SetDaycareCompatibilityString", "ShowDaycareLevelMenu", "RejectEggFromDayCare",
  "GiveEggFromDaycare", "CheckDaycareMonReceivedMail", "SavePlayerParty", "LoadPlayerParty", "StorePlayerCoordsInVars",
  "ShowFieldMessageStringVar4", "CountPartyAliveNonEggMons", "CalculatePlayerPartyCount", "IsEnoughForCostInVar0x8005",
  "SubtractMoneyFromVar0x8005", "IsPokerusInParty", "Script_FadeOutMapMusic", "LoopWingFlapSE",
  "Script_TryGainNewFanFromCounter", "UpdateTrainerFanClubGameClear", "SetChampionSaveWarp", "ScriptGetPokedexInfo",
  "ShowPokedexRatingMessage",
}

local seeds, seen, mapOf = {}, {}, {}
local function add(k, m)
  if type(k) == "string" and not seen[k] then
    seen[k] = true
    seeds[#seeds + 1] = k
    mapOf[k] = m
  end
end
for m, e in pairs(events) do
  for _, o in ipairs(e.objects or {}) do add(o.scriptKey, m) end
  for _, o in ipairs(e.bgEvents or {}) do add(o.scriptKey, m) end
  for _, o in ipairs(e.coordEvents or {}) do add(o.scriptKey, m) end
  for _, v in pairs(e.mapScripts or {}) do
    if type(v) == "string" then add(v, m) else for _, r in ipairs(v) do add(r.script, m) end end
  end
end
for k in pairs(scripts) do add(k, "?") end
local specials = {}
local i = 1
while i <= #seeds do
  local key = seeds[i]
  i = i + 1
  for _, r in ipairs(scripts[key] or {}) do
    local id
    if r.op == "special" then id = tonumber(r.id or r[1]) end
    if r.op == "specialvar" then id = tonumber(r.id or r[2]) end
    if id then specials[id] = true end
    if r.op == "callstd" or r.op == "gotostd" then add("std:" .. tostring(r.std or r[1]), mapOf[key]) end
    for _, v in pairs(r) do
      if type(v) == "string" and v:match("^g3:") and scripts[v] then add(v, mapOf[key]) end
    end
  end
end
print(string.format("emerald_story_census_test: %d scripts over every map", #seeds))

Natives.bind("emerald")
local total, unbound, byOwner = 0, {}, {}
for id in pairs(specials) do
  total = total + 1
  local name = C.specials.byId[id]
  if Natives.ALLOW["special:" .. id] == nil then
    unbound[#unbound + 1] = name
    local owner = OWNERS[name]
    check(owner ~= nil, "unbound special " .. tostring(name) .. " has a filed owner")
    if owner then byOwner[owner] = (byOwner[owner] or 0) + 1 end
  end
end
for _, n in ipairs(XA) do
  local id = C.specials.byName[n]
  check(id ~= nil and Natives.ALLOW["special:" .. id] ~= nil, "story special " .. n .. " is bound")
end
print(string.format("  %d specials used by Emerald scripts, %d bound, %d unbound", total, total - #unbound, #unbound))
local keys = {}
for o in pairs(byOwner) do keys[#keys + 1] = o end
table.sort(keys, function(a, b) return byOwner[a] > byOwner[b] end)
for _, o in ipairs(keys) do print(string.format("  %3d  %s", byOwner[o], o)) end

Natives.bind("firered")
GameVersion.set(prevVersion)
T.finish()

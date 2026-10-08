local Party = require("src.ui.game3.rs.party_menu_data")
local TextAliases = {}
for key, value in pairs(require("src.core.game3.rs.battle_text_policy").aliases) do
  TextAliases[key] = value
end
TextAliases.gText_BirchInTrouble = "gOtherText_BirchInTrouble"
TextAliases.gText_ConfirmStarterChoice = "gOtherText_DoYouChoosePoke"
TextAliases.gText_YesNo = "gOtherText_YesNoTerminating"
TextAliases.gText_HatchedFromEgg = "gOtherText_HatchedFromEgg"
TextAliases.gText_NicknameHatchPrompt = "gOtherText_NickHatchPrompt"
-- pokeruby/src/slot_machine.c:744
TextAliases.gText_YouDontHaveThreeCoins = "gOtherText_DontHaveThreeCoins"
TextAliases.gText_QuitTheGame = "gOtherText_QuitGamePrompt"
TextAliases.gText_YouveGot9999Coins = "gOtherText_MaxCoins"
TextAliases.gText_YouveRunOutOfCoins = "gOtherText_OutOfCoins"
TextAliases.gText_ReelTimeHelp = "gOtherText_ReelTime"
TextAliases.gText_SavingPlayer = "gOtherText_Player"
TextAliases.gText_SavingBadges = "gOtherText_Badges"
TextAliases.gText_SavingPokedex = "gOtherText_Pokedex"
TextAliases.gText_SavingTime = "gOtherText_PlayTime"
TextAliases.gText_ConfirmSave = "gSaveText_WouldYouLikeToSave"
TextAliases.gText_AlreadySavedFile = "gSaveText_ThereIsAlreadyAFile"
TextAliases.gText_SavingDontTurnOff = "gSaveText_DontTurnOff"
TextAliases.gText_PlayerSavedGame = "gSaveText_PlayerSavedTheGame"
TextAliases.gText_SaveError = "gSystemText_SaveErrorExchangeBackup"
for key, value in pairs(require("src.ui.game3.rs.player_pc_policy").aliases) do
  TextAliases[key] = value
end
TextAliases.gText_FlyToWhere = "gOtherText_FlyToWhere"
-- pokeruby/src/battle_party_menu.c:664
TextAliases.gText_PkmnHasNoEnergy = "gOtherText_NoEnergyLeft"
TextAliases.gText_PkmnAlreadyInBattle = "gOtherText_AlreadyBattle"
TextAliases.gText_PkmnAlreadySelected = "gOtherText_AlreadySelected"
TextAliases.gText_EggCantBattle = "gOtherText_EGGCantBattle"
TextAliases.gText_PkmnCantSwitchOut = "gOtherText_CantBeSwitched"
-- pokeruby/src/battle_party_menu.c:655
TextAliases.gText_CantSwitchWithAlly = "gOtherText_CantSwitchPokeWithYours"
TextAliases.gText_Hoenn = "gOtherText_Hoenn"
-- pokeruby/src/party_menu.c:246
TextAliases.gText_NothingToCut = "OtherText_NothingToCut"
TextAliases.gText_CantSurfHere = "OtherText_CantSurf"
TextAliases.gText_AlreadySurfing = "OtherText_AlreadySurfing"
TextAliases.gText_CantUseHere = "OtherText_CantUseThatHere"
-- pokeruby/src/party_menu.c:250
TextAliases.gText_InUseAlready_PM = "OtherText_CantUseThatHere"
TextAliases.gText_NotEnoughHp = "OtherText_NotEnoughHP"
TextAliases.gText_CantUseUntilNewBadge = "gOtherText_CantBeUsedBadge"
-- pokeruby/data/field_move_scripts.inc:10
TextAliases.Text_WantToCut = "UseCutPromptText"
TextAliases.Text_MonUsedFieldMove = "UsedCutRockSmashText"
TextAliases.Text_CantCut = "CannotUseCutText"
TextAliases.Text_WantToSmash = "UseRockSmashPromptText"
TextAliases.Text_CantSmash = "CannotUseRockSmashText"
TextAliases.Text_WantToStrength = "UseStrengthPromptText"
TextAliases.Text_MonUsedStrength = "UsedStrengthText"
TextAliases.Text_CantStrength = "CannotUseStrengthText"
TextAliases.Text_StrengthActivated = "AlreadyUsedStrengthText"
TextAliases.Text_WantToWaterfall = "UseWaterfallPromptText"
TextAliases.Text_MonUsedWaterfall = "UsedWaterfallText"
TextAliases.Text_CantWaterfall = "CannotUseWaterfallText"
TextAliases.Text_WantToDive = "UseDivePromptText"
TextAliases.Text_MonUsedDive = "UsedDiveText"
TextAliases.Text_CantDive = "CannotUseDiveText"
TextAliases.Text_WantToSurface = "UnderwaterUseDivePromptText"
TextAliases.Text_CantSurface = "UnderwaterCannotUseDiveText"
TextAliases.Text_FailSweetScent = "SweetScentNothingHereText"
-- pokeruby/src/party_menu.c:3224
TextAliases.gText_PkmnAlreadyKnows = "gOtherText_AlreadyKnows"
TextAliases.gText_PkmnCantLearnMove = "gOtherText_NotCompatible"
TextAliases.gText_PkmnNeedsToReplaceMove = "gOtherText_WantsToLearn"
-- pokeruby/src/party_menu.c:3267
TextAliases.gText_PkmnLearnedMove3 = "gOtherText_LearnedMove"
-- pokeruby/src/party_menu.c:3337
TextAliases.gText_WhichMoveToForget = "gOtherText_WhichMoveToForget2"
-- pokeruby/src/party_menu.c:3381
TextAliases.gText_12PoofForgotMove = "gOtherText_ForgetMove123_2"
-- pokeruby/src/party_menu.c:3404
TextAliases.gText_StopLearningMove2 = "gOtherText_StopTryingTo"
-- pokeruby/src/party_menu.c:3437
TextAliases.gText_MoveNotLearned = "gOtherText_DidNotLearnMove2"
-- pokeruby/src/party_menu.c:251
TextAliases.gText_RestoreWhichMove = "OtherText_RestoreWhatMove"
TextAliases.gText_BoostPp = "OtherText_BoostPP"
-- pokeruby/src/party_menu.c:3624
TextAliases.gText_PkmnBaseVar2StatIncreased = "gOtherText_WasRaised"
-- pokeruby/src/party_menu.c:3648
TextAliases.gText_MovesPPIncreased = "gOtherText_PPIncreased"
TextAliases.gText_PPWasRestored = "gOtherText_PPRestored"
-- pokeruby/src/party_menu.c:3654
TextAliases.gText_WontHaveEffect = "gOtherText_WontHaveAnyEffect"
-- pokeruby/src/party_menu.c:4037
TextAliases.gText_PkmnElevatedToLvVar2 = "gOtherText_ElevatedTo"
-- pokeruby/src/party_menu.c:3079
TextAliases.gText_PkmnNotHolding = "gOtherText_NotHoldingAnything"
-- pokeruby/src/party_menu.c:3108
TextAliases.gText_ReceivedItemFromPkmn = "gOtherText_ReceivedTheThingFrom"
-- pokeruby/src/item_menu.c:2103
TextAliases.gText_ThereIsNoPokemon = "gOtherText_NoPokemon"
-- pokeruby/src/item_use.c:151
TextAliases.gText_CantDismountBike = "gOtherText_CantGetOffBike"
-- pokeruby/src/item_use.c:603
TextAliases.gText_CoinCase = "gOtherText_Coins3"
-- pokeruby/src/item_use.c:780
TextAliases.gText_PlayerUsedVar2 = "gOtherText_UsedItem"
-- pokeruby/src/item_use.c:793
TextAliases.gText_RepelEffectsLingered = "gOtherText_RepelLingers"
-- pokeruby/src/item_use.c:819
TextAliases.gText_UsedVar2WildLured = "gOtherText_UsedFlute"
-- pokeruby/src/item_use.c:828
TextAliases.gText_UsedVar2WildRepelled = "gOtherText_UsedRepel"
for key, value in pairs(require("src.ui.game3.rs.hall_of_fame_policy").aliases) do
  TextAliases[key] = value
end
for key, value in pairs(require("src.ui.game3.rs.use_pokeblock").TEXT_ALIASES) do
  TextAliases[key] = value
end
for key, value in pairs(require("src.core.game3.scripting.natives_rs_old_man").TEXT_ALIASES) do
  TextAliases[key] = value
end
for key, value in pairs(require("src.ui.game3.rs.decoration").TEXT_ALIASES) do
  TextAliases[key] = value
end
Party.beginGiveMail = function(...)
  return require("src.ui.game3.rs.mail_give").begin(...)
end
return {
  fonts = require("src.core.game3.profiles.rs.font"),
  skins = {bag = "src.ui.game3.rs.bag_menu"},
  screens = {
    option = "src.ui.game3.rs.option_menu",
    rs_mail = "src.ui.game3.rs.mail_reader",
    rs_mail_composer = "src.ui.game3.rs.mail_composer",
    rs_trendy_phrase = "src.ui.game3.rs.trendy_phrase",
    egg_hatch = "src.ui.game3.rs.egg_hatch",
    summary = "src.ui.game3.rs.summary_menu",
    pokenav = "src.ui.game3.rs.pokenav.init",
    berry_tag = "src.ui.game3.rs.berry_tag",
    pokedex = "src.ui.game3.rs.pokedex",
    trainer_card = "src.ui.game3.rs.trainer_card",
    rs_diploma = "src.ui.game3.rs.diploma",
    berry_blender = "src.ui.game3.rs.berry_blender",
    slot_machine = "src.ui.game3.rs.slot_machine",
    roulette = "src.ui.game3.rs.roulette",
    pokeblock_case = "src.ui.game3.rs.pokeblock_case",
    use_pokeblock = "src.ui.game3.rs.use_pokeblock",
    decoration = "src.ui.game3.rs.decoration",
  },
  startMenu = "src.ui.game3.rs.start_menu_data",
  shopMenu = "src.ui.game3.rs.shop_menu",
  -- pokeruby/src/save_menu_util.c:12
  saveMenu = "rs",
  -- pokeruby/src/coins.c:16
  coinsWindow = { frameOrigin = true, text = "gOtherText_Coins2" },
  battleSpriteLayout = "rs",
  healthbox = { layout = "rs", doublesCenters = {
    [0] = { x = 159, y = 77 }, [1] = { x = 44, y = 19 },
    [2] = { x = 171, y = 102 }, [3] = { x = 32, y = 44 },
  } },
  -- pokeruby/src/battle_script_commands.c:5777
  levelUpBox = { layout = "rs", x = 12, y = 1, w = 17, h = 6,
    names = "gUnknown_0840165C", stats = { "maxHp", "spa", "atk", "spd", "def", "spe" } },
  -- pokeruby/src/field_specials.c:1099
  elevatorWindow = { left = 21, top = 1, width = 8, height = 4,
    nowOn = "gOtherText_NowOn", center = 64, titleY = 0, labelY = 16 },
  party = Party,
  contest = {
    stage = "src.ui.game3.rs.contest",
    results = "src.ui.game3.rs.contest_results",
    painting = "src.ui.game3.rs.contest_painting",
  },
  textAliases = TextAliases,
  -- pokeruby/src/text_window.c:254
  frames = {
    nativeLayout = "rs", manifest = "data/generated/gba/chrome/rs_frames.lua",
    userCount = 20, user = "data/generated/gba/chrome/user_frame_%d.rgba",
    std = "user", sign = false, fillColor = 15,
    dialogue = { path = "data/generated/gba/chrome/message_box.rgba", layout = "rs_dialogue" },
    dialogueWindow = { left = 2, top = 15, width = 26, height = 4 },
    -- pokeruby/src/text.c:3271
    arrow = { path = "data/generated/gba/chrome/fonts/down_arrow.rgba", delay = 6, period = 6, lastPage = false },
  },
}

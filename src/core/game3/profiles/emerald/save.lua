return {
  -- pokeemerald/src/new_game.c:172
  money = 3000,
  -- pokeemerald/src/player_pc.c:225
  pcItems = { { item = "ITEM_POTION", qty = 1 } },
  rivalName = false,
  -- pokeemerald/src/new_game.c:196
  resetScript = "EventScript_ResetAllMapFlags",
  -- pokeemerald/src/pokemon_size_record.c:152
  sizeRecordVars = { "VAR_SEEDOT_SIZE_RECORD", "VAR_LOTAD_SIZE_RECORD" },
  -- pokeemerald/src/pokemon_size_record.c:12
  sizeRecordDefault = 0x8000,
  waldaPhrase = { phrase = "", colors = { 0x7B35, 0x6186 }, iconId = 0, patternId = 0, unlocked = false },
  -- pokeemerald/src/naming_screen.c:727
  storage = {
    sendVar = "VAR_PC_BOX_TO_SEND_MON",
    boxFullFlag = "FLAG_SHOWN_BOX_WAS_FULL_MESSAGE",
    pcOwnerFlag = "FLAG_SYS_PC_LANETTE",
  },
  sections = {
    "rtc", "encryptionKey", "berryTrees",
    { name = "tv", module = "src.core.game3.rse.tv" },
    "decorations",
    { name = "weather", module = "src.core.game3.weather" },
    { name = "matchCall", module = "src.core.game3.rse.rematch" },
    { name = "giftRibbons", module = "src.core.game3.rse.ribbons" },
    { name = "contests", module = "src.core.game3.rse.contest_util" },
    { name = "dewfordTrends", module = "src.core.game3.rse.dewford_trend" },
    { name = "oldMan", module = "src.core.game3.rse.old_man" },
    { name = "lilycoveLady", module = "src.core.game3.rse.lilycove_lady" },
    { name = "lottery", module = "src.core.game3.rse.lottery" },
    { name = "secretBases", module = "src.core.game3.rse.secret_base" },
    { name = "pokeblocks", module = "src.core.game3.rse.pokeblock" },
    { name = "berryBlender", module = "src.core.game3.rse.berry_blender" },
    { name = "frontier", module = "src.core.game3.rse.frontier.util" },
    { name = "trainerHill", module = "src.core.game3.rse.trainer_hill" },
    { name = "apprentice", module = "src.core.game3.rse.frontier.apprentice" },
    { name = "recordMixingGift", module = "src.core.game3.rse.record_mixing_gift" },
    { name = "easyChat", module = "src.core.game3.rse.easy_chat_player" },
    { name = "recordedBattle", module = "src.core.game3.rse.recorded_battle" },
  },
}

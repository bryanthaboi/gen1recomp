return {
  id = "firered",
  label = "FireRed",
  generation = 3,
  engine = "game3",

  map = {
    prefixes = { "FR_", "SEVII_" },
    enginePrefix = "FR_",
    legacyPrefixes = { "SEVII_" },
    newGameStart = {
      map = "FR_PLAYERS_HOUSE_2F",
      x = 6,
      y = 6,
      facing = "down",
      healMap = "FR_PLAYERS_HOUSE_1F",
      healX = 8,
      healY = 5,
    },
  },

  saveRules = "src.core.game3.profiles.firered_rules",

  optionsBlock = "firered",

  font = {
    module = "src.ui.game3.frlg_font",
    widths = "data/generated/gba/chrome/fonts/latin_widths.lua",
    smallWidths = "data/generated/gba/chrome/fonts/latin_small_widths.lua",
  },

  -- pokefirered/include/constants/species.h:421-423
  species = { num = 412, egg = 412 },

  dexArea = {
    defaultKey = "kanto",
    mapGroups = "src.import.gba.map_groups_firered",
    dexMax = 151,
    stripPrefixes = { "FR_", "SEVII_" },
  },

  -- pokefirered/include/constants/flags.h:1324
  badges = {
    count = 8,
    flagBase = 0x820,
    names = {
      "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
      "SOUL", "MARSH", "VOLCANO", "EARTH",
    },
  },

  heal = { table = "firered" },

  trainers = {
    rivalIds = { squirtle = 326, bulbasaur = 327, charmander = 328 },
    fallback = { class = 81, pic = 106, name = "TERRY" },
    music = {
      encounter = {
        girlCodes = { 1, 2, 9 },
        rocketCodes = { 3, 6, 7 },
        girl = 284,
        rocket = 283,
        boy = 285,
      },
      battle = {
        championClass = 90, champion = 299,
        gymClasses = { 84, 87 }, gym = 296,
        trainer = 297,
      },
      victory = {
        gymClasses = { 84, 90 }, gym = 312,
        trainer = 310,
      },
    },
  },

  regionMap = { switchFlag = "FLAG_SYS_SEVII_MAP_123" },

  capabilities = {
    easyChat = true,
    braille = true,
    mysteryGift = true,
    unionRoom = true,
    daycare = true,
    pokecenter = true,
    marts = true,
    moveRelearner = true,
    eggs = true,
    berries = true,
    sizeRecord = true, -- pokeemerald/src/pokemon_size_record.c
    helpSystem = true,
    tmCase = true,
    fameChecker = true,
    teachyTV = true,
    vsSeeker = true,
    trainerTower = true,
    seagallop = true,
    trainerFanClub = true,
    berryPouch = true,
    sevii = true,
  },

  nativeModules = {
    "natives_corner",
    "natives_cutscene",
    "natives_daycare",
    "natives_elevator",
    "natives_events",
    "natives_fame",
    "natives_fan_club",
    "natives_gift",
    "natives_link",
    "natives_listmenu",
    "natives_moveteach",
    "natives_queries",
    "natives_seagallop",
    "natives_size_record",
    "natives_tower",
    "natives_trade",
    "natives_wireless",
  },

  extractors = {
    "region_map_extract",
    "map_sections_extract",
    "multichoice_extract",
    "heal_locations_extract",
    "door_anim_extract",
    "slot_machine_extract",
    "trade_extract",
    "link_art_extract",
    "fame_checker_extract",
    "teachy_tv_extract",
    "mystery_gift_extract",
    "trainer_tower_extract",
    "tutor_extract",
    "museum_extract",
    "move_relearner_extract",
    "egg_extract",
    "battle_anim_extract",
    "battle_ai_extract",
  },
}

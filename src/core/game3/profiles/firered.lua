return {
  id = "firered",
  label = "FireRed",
  family = "frlg",
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

  save = {
    -- pokefirered/src/naming_screen.c:732
    storage = {
      sendVar = "VAR_PC_BOX_TO_SEND_MON",
      boxFullFlag = "FLAG_SHOWN_BOX_WAS_FULL_MESSAGE",
      pcOwnerFlag = "FLAG_SYS_NOT_SOMEONES_PC",
    },
    sections = {},
  },

  -- pokefirered/include/constants/global.h:50
  bag = {
    pockets = { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" },
    visible = { "ITEMS", "KEY_ITEMS", "POKE_BALLS" },
    packPockets = {},
    -- pokefirered/include/constants/global.h:36
    capacity = { ITEMS = 42, KEY_ITEMS = 30, POKE_BALLS = 13, TM_CASE = 58, BERRY_POUCH = 43 },
    -- pokefirered/src/item_menu.c:183
    labels = {
      ITEMS = "sPocketNames[0]",
      KEY_ITEMS = "sPocketNames[1]",
      POKE_BALLS = "sPocketNames[2]",
      TM_CASE = "gText_TMCase",
      BERRY_POUCH = "gText_BerryPouch",
    },
    -- pokefirered/src/item.c:233
    containers = {
      TM_CASE = { item = "ITEM_TM_CASE" },
      BERRY_POUCH = { item = "ITEM_BERRY_POUCH", flag = "FLAG_SYS_GOT_BERRY_POUCH" },
    },
    slotMax = { default = 999 },
    splitSlots = {},
    -- pokefirered/src/item.c:495
    sortHmsFirst = { TM_CASE = true },
    sortById = {},
    -- pokefirered/include/constants/global.h:35
    pcItems = 30,
    pcSlotMax = 999,
  },

  dex = {
    regionalPrefix = 151,
    nationalMax = 386,
    -- pokefirered/src/event_data.c:107
    national = {
      flag = "FLAG_SYS_NATIONAL_DEX",
      var = "VAR_NATIONAL_DEX",
      value = 0x6258,
      requireAll = false,
    },
    registerGate = true,
    evolutionGate = true,
  },

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

  discoverNatives = true,

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
    "map_preview_extract",
    "credits_extract",
    "league_extract",
    "roamer_extract",
    "mail_extract",
  },
}

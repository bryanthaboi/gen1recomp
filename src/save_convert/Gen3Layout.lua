local L = {}

-- include/save.h:8
L.SECTOR_DATA_SIZE = 0xF80
-- include/save.h:10
L.SECTOR_SIZE = 0x1000
-- include/save.h:63
L.FOOTER = { id = 0xFF4, checksum = 0xFF6, signature = 0xFF8, counter = 0xFFC }
-- include/save.h:15
L.SIGNATURE = 0x08012025
-- include/save.h:24
L.SECTORS_PER_SLOT = 14
L.NUM_SLOTS = 2
L.NUM_SECTORS = 32
-- include/save.h:26
L.SECTOR_ID_HOF_1 = 28
L.SECTOR_ID_HOF_2 = 29
L.FLASH_SIZE = 0x20000
L.HALF_FLASH_SIZE = 0x10000
L.MAX_TRAILER = 0x3F

-- src/save.c:54
L.CHUNK_SIZES = {
  [0] = 0xF24,
  0xF80, 0xF80, 0xF80, 0xEE8,
  0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0,
}

-- src/save.c:56
L.BLOCKS = {
  { key = "sb2", first = 0, last = 0, size = 0xF24 },
  { key = "sb1", first = 1, last = 4, size = 0x3D68 },
  { key = "storage", first = 5, last = 13, size = 0x83D0 },
}

-- include/global.h:329
L.SB2 = {
  { "name", 0x000, "strFF", 8 },
  { "gender", 0x008, "u8" },
  { "specialSaveWarpFlags", 0x009, "u8" },
  { "trainerId", 0x00A, "u16" },
  { "secretId", 0x00C, "u16" },
  { "playHours", 0x00E, "u16" },
  { "playMinutes", 0x010, "u8" },
  { "playSeconds", 0x011, "u8" },
  { "playVBlanks", 0x012, "u8" },
  { "buttonMode", 0x013, "u8" },
  { "optionsWord", 0x014, "u16" },
  -- include/global.h:195
  { "dexOrder", 0x018, "u8" },
  { "dexMode", 0x019, "u8" },
  { "dexUnused", 0x01A, "u8" },
  { "dexNationalMagic", 0x01B, "u8" },
  { "unownPersonality", 0x01C, "u32" },
  { "spindaPersonality", 0x020, "u32" },
  { "dexOwned", 0x028, "bits", 52 },
  { "dexSeen", 0x05C, "bits", 52 },
  -- include/global.h:348
  { "gcnLinkFlags", 0x0A8, "u32" },
  { "frlgMarker", 0x0AC, "u32" },
  -- include/global.h:354
  { "berryPowder", 0xAF8, "u32", nil, "key32" },
  -- include/global.h:358
  { "encryptionKey", 0xF20, "u32" },
}

-- include/global.h:338
L.OPTIONS_BITS = {
  { "textSpeed", 0, 3 },
  { "frameType", 3, 5 },
  { "sound", 8, 1 },
  { "battleStyle", 9, 1 },
  { "battleScene", 10, 1 },
  { "regionMapZoom", 11, 1 },
}

-- include/global.h:392
L.WARP = { group = { 0, "s8" }, num = { 1, "s8" }, warpId = { 2, "s8" }, x = { 4, "s16" }, y = { 6, "s16" } }

-- include/global.h:761
L.SB1 = {
  { "posX", 0x0000, "s16" },
  { "posY", 0x0002, "s16" },
  { "location", 0x0004, "warp" },
  { "continueGameWarp", 0x000C, "warp" },
  { "dynamicWarp", 0x0014, "warp" },
  { "lastHealLocation", 0x001C, "warp" },
  { "escapeWarp", 0x0024, "warp" },
  { "savedMusic", 0x002C, "u16" },
  { "weather", 0x002E, "u8" },
  { "flashLevel", 0x0030, "u8" },
  { "mapLayoutId", 0x0032, "u16" },
  { "partyCount", 0x0034, "u8" },
  { "money", 0x0290, "u32", nil, "key32" },
  { "coins", 0x0294, "u16", nil, "key16" },
  { "registeredItem", 0x0296, "u16" },
  { "dexSeen1", 0x05F8, "bits", 52 },
  { "flags", 0x0EE0, "bits", 0x120 },
  { "dexSeen2", 0x3A18, "bits", 52 },
  { "rivalName", 0x3A4C, "str", 8 },
}

-- include/global.h:773
L.PARTY_OFFSET = 0x0038
L.PARTY_SIZE = 6
L.PARTY_MON_SIZE = 100
-- include/pokemon.h:133
L.PARTY_MAIL = 85

-- include/global.h:777
L.PC_ITEMS = { off = 0x0298, count = 30 }
-- include/global.h:778
L.POCKETS = {
  { key = "ITEMS", off = 0x0310, count = 42 },
  { key = "KEY_ITEMS", off = 0x03B8, count = 30 },
  { key = "POKE_BALLS", off = 0x0430, count = 13 },
  { key = "TM_CASE", off = 0x0464, count = 58 },
  { key = "BERRY_POUCH", off = 0x054C, count = 43 },
}
-- include/global.h:400
L.ITEM_SLOT_SIZE = 4

-- include/global.h:788
L.OBJECT_EVENTS = { off = 0x06A0, count = 16, size = 0x24 }
-- include/global.fieldmap.h:212
L.OBJECT_EVENT = { flags = 0x00, isPlayerByte = 0x02, graphicsId = 0x05, currentX = 0x10, currentY = 0x12, facing = 0x18 }
-- include/fieldmap.h:21
L.MAP_OFFSET = 7

-- include/global.h:791
L.VARS = { off = 0x1000, count = 256, first = 0x4000 }
-- include/global.h:792
L.GAME_STATS = { off = 0x1200, count = 64 }
-- include/global.h:794
L.EASY_CHAT_PROFILE = { off = 0x2CA0, count = 6 }

-- include/global.h:549
L.DAYCARE = { off = 0x2F80, monSize = 0x8C, stepsOff = 0x88, offspringPersonality = 0x118, stepCounter = 0x11A }
-- include/global.h:818
L.ROUTE5_DAYCARE = 0x3C98

-- include/global.h:417
L.ROAMER = {
  { "ivs", 0x00, "u32" },
  { "personality", 0x04, "u32" },
  { "species", 0x08, "u16" },
  { "hp", 0x0A, "u16" },
  { "level", 0x0C, "u8" },
  { "status", 0x0D, "u8" },
  { "active", 0x13, "u8" },
}
L.ROAMER_OFFSET = 0x30D0

-- include/pokemon_storage_system.h:44
L.STORAGE = {
  currentBox = 0x0000,
  boxes = 0x0004,
  boxNames = 0x8344,
  boxNameLength = 9,
  wallpapers = 0x83C2,
  totalBoxes = 14,
  inBox = 30,
}

-- include/pokemon.h:105
L.BOX_MON_SIZE = 80
L.BOX_MON = {
  personality = 0x00,
  otId = 0x04,
  nickname = 0x08, nicknameLength = 10,
  language = 0x12,
  flags = 0x13,
  otName = 0x14, otNameLength = 7,
  markings = 0x1B,
  checksum = 0x1C,
  unknown = 0x1E,
  secure = 0x20, secureWords = 12,
}
-- include/pokemon.h:111
L.BOX_MON_FLAGS = { isBadEgg = 0, hasSpecies = 1, isEgg = 2 }

L.SUBSTRUCT_SIZE = 12
-- include/pokemon.h:8
L.SUBSTRUCT0 = {
  { "species", 0, "u16" },
  { "heldItem", 2, "u16" },
  { "exp", 4, "u32" },
  { "ppBonuses", 8, "u8" },
  { "friendship", 9, "u8" },
  { "growthFiller", 10, "u16" },
}
-- include/pokemon.h:18
L.SUBSTRUCT1 = { moves = 0, pp = 8 }
-- include/pokemon.h:24
L.EV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
L.CONTEST_KEYS = { "cool", "beauty", "cute", "smart", "tough", "sheen" }
-- include/pokemon.h:40
L.SUBSTRUCT3 = { pokerus = 0, metLocation = 1, origins = 2, ivWord = 4, ribbons = 8 }
-- include/pokemon.h:45
L.ORIGINS_BITS = { { "metLevel", 0, 7 }, { "metGame", 7, 4 }, { "pokeball", 11, 4 }, { "otGender", 15, 1 } }
-- include/pokemon.h:50
L.IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
L.IV_EGG_BIT = 30
L.IV_ABILITY_BIT = 31
-- include/pokemon.h:64
L.RIBBON_CHAMPION_BIT = 15
-- include/pokemon.h:84
L.RIBBON_FATEFUL_BIT = 31

-- include/pokemon.h:128
L.PARTY_EXTRA = {
  { "status", 80, "u32" },
  { "level", 84, "u8" },
  { "mail", 85, "u8" },
  { "hp", 86, "u16" },
  { "maxHp", 88, "u16" },
  { "attack", 90, "u16" },
  { "defense", 92, "u16" },
  { "speed", 94, "u16" },
  { "spAtk", 96, "u16" },
  { "spDef", 98, "u16" },
}

-- src/pokemon.c:2863
L.SUBSTRUCT_ORDER = {
  [0] = { 0, 1, 2, 3 }, { 0, 1, 3, 2 }, { 0, 2, 1, 3 }, { 0, 3, 1, 2 }, { 0, 2, 3, 1 }, { 0, 3, 2, 1 },
  { 1, 0, 2, 3 }, { 1, 0, 3, 2 }, { 2, 0, 1, 3 }, { 3, 0, 1, 2 }, { 2, 0, 3, 1 }, { 3, 0, 2, 1 },
  { 1, 2, 0, 3 }, { 1, 3, 0, 2 }, { 2, 1, 0, 3 }, { 3, 1, 0, 2 }, { 2, 3, 0, 1 }, { 3, 2, 0, 1 },
  { 1, 2, 3, 0 }, { 1, 3, 2, 0 }, { 2, 1, 3, 0 }, { 3, 1, 2, 0 }, { 2, 3, 1, 0 }, { 3, 2, 1, 0 },
}

-- include/constants/battle.h:91
L.STATUS = { sleepMask = 0x7, PSN = 0x8, BRN = 0x10, FRZ = 0x20, PAR = 0x40, TOX = 0x80 }
L.STATUS_ORDER = { "PSN", "BRN", "FRZ", "PAR", "TOX" }

-- src/hall_of_fame.c:32
L.HOF = { teams = 50, monsPerTeam = 6, monSize = 20, tid = 0, personality = 4, speciesLevel = 8, nick = 10, nickLength = 10 }

-- src/event_data.c:107
L.NATIONAL_DEX = { magic = 0xB9, var = 0x404E, varValue = 0x6258, flag = 0x840 }
-- include/constants/flags.h:1378
L.FLAG_SYS_GAME_CLEAR = 0x82C
-- include/constants/flags.h:44
L.TEMP_FLAGS_END = 0x1F
-- include/constants/game_stat.h:5
L.GAME_STAT_FIRST_HOF_PLAY_TIME = 1
-- include/save_location.h:5
L.CONTINUE_GAME_WARP = 0x01
-- include/constants/global.h:110
L.FACING = { [1] = "down", [2] = "up", [3] = "left", [4] = "right" }

-- src/pokemon_storage_system_menu.c:415
L.DEFAULT_BOX_NAME = "BOX%d"
-- src/pokemon_storage_system_menu.c:420
L.DEFAULT_WALLPAPER_MOD = 4

L.EMPTY_WARP = { group = -1, num = -1, warpId = -1, x = -1, y = -1 }

-- include/constants/global.h:63
L.PLAYER_NAME_LENGTH = 7
L.POKEMON_NAME_LENGTH = 10
-- include/pokemon_storage_system.h:11
L.BOX_NAME_LENGTH = 8
-- include/constants/global.h:20
L.LANGUAGE_JAPANESE = 1
L.LANGUAGE_ENGLISH = 2
-- src/daycare.c:135
L.EGG_NICKNAME = "\x60\x6F\x8B"
-- include/global.h:790
L.FLAGS_COUNT = 0x900
-- include/constants/easy_chat.h:1091
L.EC_WORD_UNDEFINED = 0xFFFF
-- src/easy_chat.c:444
L.PORT_PROFILE_WORDS = 4
-- include/save.h:26
L.HOF_SECTORS = 2
-- include/constants/global.h:11
L.VERSION_FIRE_RED = 4
L.VERSION_LEAF_GREEN = 5
-- include/constants/heal_locations.h:11
L.HEAL_LOCATION_PALLET_TOWN = 1

-- include/global.h:524
L.MAIL = { off = 0x2CD0, count = 16, size = 36, words = 0x00, wordCount = 9, playerName = 0x12,
  playerNameLength = 8, trainerId = 0x1A, species = 0x1E, itemId = 0x20 }
-- include/constants/items.h:451
L.MAIL_NONE = 0xFF
-- src/mail_data.c:28
L.MAIL_CLEAR_SPECIES = 1
-- src/mail_data.c:167
L.MAIL_ITEM_FIRST, L.MAIL_ITEM_LAST = 121, 132
-- src/mail_data.c:41
L.MAIL_PARTY_SLOTS = 6
L.MAIL_NAME_PAD = 6
-- include/global.h:533
L.DAYCARE_MAIL = { off = 80, otName = 36, otNameLength = 8, monName = 44, monNameLength = 11 }

-- include/global.h:795
L.EASY_CHAT_BATTLE = { start = 0x2CAC, won = 0x2CB8, lost = 0x2CC4, count = 6 }
local function ecWord(group, index) return group * 512 + index end
-- src/easy_chat.c:73
L.DEFAULT_BATTLE_START_WORDS = {
  -- include/constants/easy_chat.h:507
  ecWord(0x8, 0xF),
  -- include/constants/easy_chat.h:290
  ecWord(0x5, 0x2),
  -- include/constants/easy_chat.h:467
  ecWord(0x7, 0x25),
  -- include/constants/easy_chat.h:368
  ecWord(0x6, 0x3),
  -- include/constants/easy_chat.h:247
  ecWord(0x4, 0x3),
  -- include/constants/easy_chat.h:365
  ecWord(0x6, 0x0),
}

-- include/global.h:814
L.FAME_CHECKER = { off = 0x3A54, count = 16, pickBits = 2, flavorShift = 2, flavorBits = 12, unkShift = 14 }
-- include/constants/fame_checker.h:4
L.FAMECHECKER_OAK = 0
-- include/constants/fame_checker.h:24
L.FCPICKSTATE_COLORED = 2

-- include/global.h:816
L.REGISTERED_TEXTS = { off = 0x3AD4, count = 10, size = 21 }

-- include/global.h:693
L.TRAINER_TOWER = { off = 0x3D38, count = 4, size = 12, bestTime = 4 }
-- include/constants/trainer_tower.h:61
L.TRAINER_TOWER_MAX_TIME = 215999

-- include/global.h:240
L.LINK_BATTLE_RECORDS = { off = 0xA98, count = 5, size = 16 }

-- src/event_data.c:71
L.RSE_NATIONAL_VAR, L.RSE_NATIONAL_VALUE, L.RSE_NATIONAL_FLAG = 0x403C, 0x0302, 0x838

return L

local VersionsRse = require("src.import.gba.versions_rse")

local V = VersionsRse.new("emerald")
local sym, count = V.sym, V.count

V.CACHE_VERSION = 19
V.NATIVE_VERSION = 2
V.OW_VERSION = 1
V.ANIM_VERSION = 1
V.AUDIO_VERSION = 1
V.POKEMON_VERSION = 1
V.BATTLE_MOVES_VERSION = 1
V.BATTLE_ANIMS_VERSION = 1

V.NATIVE_RENDER = true
V.OW_RENDER = true
V.TILESET_ANIM = true

V.AUDIO = {
  song_table = sym("gSongTable"),
  song_count = count("gSongTable", 8),
  cry_table = sym("gCryTable"),
  cry_count = count("gCryTable", 12),
  cry_table_reverse = sym("gCryTable_Reverse"),
}

-- pokeemerald/src/field_specials.c:2985
-- pokeemerald/data/battle_frontier/battle_frontier_exchange_corner.h:1
V.FRONTIER_EXCHANGE_CORNER = {
  decor1 = { off = sym("sFrontierExchangeCorner_Decor1.436"), count = count("sFrontierExchangeCorner_Decor1.436", 2) },
  decor2 = { off = sym("sFrontierExchangeCorner_Decor2.437"), count = count("sFrontierExchangeCorner_Decor2.437", 2) },
  vitamins = { off = sym("sFrontierExchangeCorner_Vitamins.438"), count = count("sFrontierExchangeCorner_Vitamins.438", 2) },
  holdItems = { off = sym("sFrontierExchangeCorner_HoldItems.439"), count = count("sFrontierExchangeCorner_HoldItems.439", 2) },
  tutor1 = { off = sym("sBattleFrontier_TutorMoves1"), count = count("sBattleFrontier_TutorMoves1", 2) },
  tutor2 = { off = sym("sBattleFrontier_TutorMoves2"), count = count("sBattleFrontier_TutorMoves2", 2) },
}

V.OW_GFX_POINTERS = sym("gObjectEventGraphicsInfoPointers")
V.OW_SPRITE_PALETTES = sym("event_object_movement.o:sObjectEventSpritePalettes")
V.NUM_OBJ_EVENT_GFX = count("gObjectEventGraphicsInfoPointers", 4)
-- pokeemerald/include/constants/event_objects.h:7
V.OW_PLAYER_MALE = 0
V.OW_PLAYER_MALE_BIKE = 1
V.OW_PLAYER_MALE_SURF = 2
V.OW_PLAYER_MALE_FIELD_MOVE = 3
V.OW_PLAYER_MALE_ACRO_BIKE = 63
V.OW_PLAYER_MALE_UNDERWATER = 111
V.OW_PLAYER_MALE_FISH = 137
V.OW_PLAYER_MALE_WATERING = 191
V.OW_PLAYER_MALE_DECORATING = 193
V.OW_PLAYER_FEMALE = 89
V.OW_PLAYER_FEMALE_BIKE = 90
V.OW_PLAYER_FEMALE_ACRO_BIKE = 91
V.OW_PLAYER_FEMALE_SURF = 92
V.OW_PLAYER_FEMALE_FIELD_MOVE = 93
V.OW_PLAYER_FEMALE_UNDERWATER = 112
V.OW_PLAYER_FEMALE_FISH = 138
V.OW_PLAYER_FEMALE_WATERING = 192
V.OW_PLAYER_FEMALE_DECORATING = 194

V.FONT_LATIN_NORMAL = sym("gFontNormalLatinGlyphs")
V.FONT_LATIN_WIDTHS = sym("gFontNormalLatinGlyphWidths")
V.FONT_GLYPH_BYTES = 64
V.MENU_CURSOR_GLYPH = 0xEF
V.FONTS = {
  small = { glyphs = sym("gFontSmallLatinGlyphs"), widths = sym("gFontSmallLatinGlyphWidths") },
  normal = { glyphs = sym("gFontNormalLatinGlyphs"), widths = sym("gFontNormalLatinGlyphWidths") },
  short = { glyphs = sym("gFontShortLatinGlyphs"), widths = sym("gFontShortLatinGlyphWidths") },
  narrow = { glyphs = sym("gFontNarrowLatinGlyphs"), widths = sym("gFontNarrowLatinGlyphWidths") },
  small_narrow = { glyphs = sym("gFontSmallNarrowLatinGlyphs"), widths = sym("gFontSmallNarrowLatinGlyphWidths") },
}

V.SPECIES_NAME_LENGTH = 11
V.SPECIES_NAMES = sym("gSpeciesNames")
V.NUM_SPECIES = count("gSpeciesNames", V.SPECIES_NAME_LENGTH)
V.SPECIES_INFO_SIZE = 28
V.SPECIES_INFO = sym("gSpeciesInfo")
V.DEOXYS_BASE_STATS = sym("pokemon.o:sDeoxysBaseStats")
V.SPECIES_TO_NATIONAL = sym("pokemon.o:sSpeciesToNationalPokedexNum")
V.SPECIES_TO_HOENN = sym("pokemon.o:sSpeciesToHoennPokedexNum")
V.HOENN_TO_NATIONAL = sym("pokemon.o:sHoennToNationalOrder")
V.MON_ICON_TABLE = sym("gMonIconTable")
V.MON_ICON_PAL_INDICES = sym("gMonIconPaletteIndices")
V.MON_ICON_PALETTES = sym("gMonIconPalettes")
V.MON_ICON_PAL_COUNT = count("gMonIconPaletteTable", 8)
V.MON_ICON_BYTES = 0x400
V.MON_ICON_W = 32
V.MON_ICON_H = 32
V.MON_FRONT_PIC_TABLE = sym("gMonFrontPicTable")
V.MON_STILL_FRONT_PIC_TABLE = sym("gMonStillFrontPicTable")
V.MON_BACK_PIC_TABLE = sym("gMonBackPicTable")
V.MON_PALETTE_TABLE = sym("gMonPaletteTable")
V.MON_SHINY_PALETTE_TABLE = sym("gMonShinyPaletteTable")
V.MON_FRONT_PIC_COORDS = sym("gMonFrontPicCoords")
V.MON_BACK_PIC_COORDS = sym("gMonBackPicCoords")
V.ENEMY_MON_ELEVATION = sym("gEnemyMonElevation")
V.SPINDA_SPOT_GRAPHICS = sym("gSpindaSpotGraphics")

V.ABILITY_NAME_LENGTH = 12
V.ABILITY_NAMES = sym("gAbilityNames")
V.ABILITIES_COUNT = count("gAbilityNames", V.ABILITY_NAME_LENGTH + 1)
V.ABILITY_DESCRIPTIONS = sym("gAbilityDescriptionPointers")

V.MOVE_NAME_LENGTH = 12
V.MOVE_NAMES = sym("gMoveNames")
V.MOVES_COUNT = count("gMoveNames", V.MOVE_NAME_LENGTH + 1)
V.MOVE_DESCRIPTIONS = sym("gMoveDescriptionPointers")
V.BATTLE_MOVES = sym("gBattleMoves")
V.BATTLE_MOVE_SIZE = 12
V.LEVEL_UP_LEARNSETS = sym("gLevelUpLearnsets")
-- pokeemerald/src/data/pokemon/egg_moves.h:1
V.EGG_MOVES = sym("gEggMoves")
V.EGG_MOVES_SPECIES_OFFSET = 20000
V.EGG_MOVES_TERMINATOR = 0xFFFF
V.EGG_MOVES_MAX = 16
V.EVOLUTION_TABLE = sym("gEvolutionTable")
V.EVOS_PER_MON = 5
V.EVOLUTION_ENTRY_SIZE = 8
V.TMHM_LEARNSETS = sym("gTMHMLearnsets")
V.TMHM_MOVES = sym("party_menu.o:sTMHMMoves")
V.TMHM_COUNT = count("party_menu.o:sTMHMMoves", 2)
V.TUTOR_MOVES = sym("gTutorMoves")
V.TUTOR_MOVE_COUNT = count("gTutorMoves", 2)
V.TUTOR_LEARNSETS = sym("party_menu.o:sTutorLearnsets")
V.TUTOR_LEARNSET_STRIDE = 4

V.POKEDEX_ENTRIES = sym("gPokedexEntries")
V.POKEDEX_ENTRY_SIZE = 32
V.NATIONAL_DEX_COUNT = count("gPokedexEntries", V.POKEDEX_ENTRY_SIZE) - 1
V.POKEDEX_ORDERS = {
  alphabetical = sym("gPokedexOrder_Alphabetical"),
  weight = sym("gPokedexOrder_Weight"),
  height = sym("gPokedexOrder_Height"),
}

V.ITEMS = sym("gItems")
V.ITEM_STRIDE = 44
V.ITEMS_COUNT = count("gItems", V.ITEM_STRIDE)
V.ITEM_ICON_TABLE = sym("gItemIconTable")
V.ITEM_EFFECT_TABLE = sym("gItemEffectTable")

V.TRAINERS_TABLE = sym("gTrainers")
V.TRAINER_STRIDE = 0x28
V.TRAINERS_COUNT = count("gTrainers", V.TRAINER_STRIDE)
V.TRAINER_CLASS_NAMES = sym("gTrainerClassNames")
V.TRAINER_CLASS_NAME_STRIDE = 13
V.TRAINER_CLASS_COUNT = count("gTrainerClassNames", V.TRAINER_CLASS_NAME_STRIDE)
V.TRAINER_FRONT_PIC_TABLE = sym("gTrainerFrontPicTable")
V.TRAINER_FRONT_PIC_PAL_TABLE = sym("gTrainerFrontPicPaletteTable")
V.TRAINER_PIC_COUNT = count("gTrainerFrontPicTable", 8)
V.TRAINER_BACK_PIC_TABLE = sym("gTrainerBackPicTable")
V.TRAINER_BACK_PIC_PAL_TABLE = sym("gTrainerBackPicPaletteTable")
V.TRAINER_BACK_PIC_COUNT = count("gTrainerBackPicTable", 8)
-- pokeemerald/src/data/trainer_graphics/back_pic_anims.h:119
V.TRAINER_BACK_ANIMS_TABLE = sym("gTrainerBackAnimsPtrTable")
V.TRAINER_MONEY_TABLE = sym("gTrainerMoneyTable")
V.FACILITY_CLASS_TO_PIC = sym("gFacilityClassToPicIndex")
V.FACILITY_CLASS_TO_PIC_INDEX = V.FACILITY_CLASS_TO_PIC
V.FACILITY_CLASS_TO_TRAINER_CLASS = sym("gFacilityClassToTrainerClass")
V.FACILITY_CLASS_COUNT = count("gFacilityClassToPicIndex", 1)

V.WILD_MON_HEADERS = sym("gWildMonHeaders")
V.WILD_MON_HEADER_SIZE = 20
V.WILD_MON_HEADER_COUNT = count("gWildMonHeaders", V.WILD_MON_HEADER_SIZE)

V.G_MAP_GROUPS = sym("gMapGroups")
V.NUM_MAP_GROUPS = count("gMapGroups", 4)
V.G_MAP_LAYOUTS = sym("gMapLayouts")
V.NUM_MAP_LAYOUTS = count("gMapLayouts", 4)

V.STD_SCRIPTS = sym("gStdScripts")
V.STD_SCRIPTS_COUNT = count("gStdScripts", 4)
V.SPECIALS = sym("gSpecials")
V.SPECIALS_COUNT = count("gSpecials", 4)
V.SCRIPT_CMD_TABLE = sym("gScriptCmdTable")
V.SCRIPT_CMD_COUNT = count("gScriptCmdTable", 4)
V.SPECIAL_VARS = sym("gSpecialVars")
V.SPECIAL_VARS_COUNT = count("gSpecialVars", 4)
V.STD_STRING_PTRS = sym("gStdStrings")
V.STD_STRING_COUNT = count("gStdStrings", 4)

V.MULTICHOICE_LISTS = sym("script_menu.o:sMultichoiceLists")
V.MULTICHOICE_COUNT = count("script_menu.o:sMultichoiceLists", 8)
V.S_HEAL_LOCATIONS = sym("heal_location.o:sHealLocations")
V.NUM_HEAL_LOCATIONS = count("heal_location.o:sHealLocations", 8)
V.REGION_MAP_ENTRIES = sym("gRegionMapEntries")
V.BATTLE_STRINGS_TABLE = sym("gBattleStringsTable")
V.BATTLE_STRINGS_COUNT = count("gBattleStringsTable", 4)

local ROW = {
  id = "emerald_1_0",
  game = "emerald",
  tilesets = {},
  layouts = {},
  map_headers = {},
  g_map_groups = V.G_MAP_GROUPS,
  g_map_layouts = V.G_MAP_LAYOUTS,
  num_map_groups = V.NUM_MAP_GROUPS,
  ow_gfx_pointers = V.OW_GFX_POINTERS,
  ow_sprite_palettes = V.OW_SPRITE_PALETTES,
  num_obj_event_gfx = V.NUM_OBJ_EVENT_GFX,
}

V.BY_SHA1["f3ae088181bf583e55daf962a92bb46f4f1d07b7"] = ROW

local AREAS = {
  "maps", "scripts", "data", "pokemon_gfx", "text", "ow", "field", "battle", "audio", "boot", "ui", "rse",
  "b1", "b2", "b3", "fa", "fb", "fc", "ua", "ub", "uc", "ud", "xa", "aa",
  "c1a", "c1b", "sb", "pb1", "pb2", "tv", "misc", "gc", "ma", "pn", "f1", "f2", "f3", "f4", "sav", "link", "ver",
}
for _, area in ipairs(AREAS) do
  local name = "src.import.gba.games.emerald." .. area
  local ok, frag = pcall(require, name)
  if ok then
    if type(frag) == "function" then frag(V, ROW) end
  elseif not tostring(frag):find("module '" .. name .. "' not found", 1, true) then
    error(frag, 0)
  end
end

return V

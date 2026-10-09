local VersionsRse = require("src.import.gba.versions_rse")
local Builds = require("src.import.gba.rs_builds")

local Rs = {}

local function tables(game, revision)
  local V = VersionsRse.new(game, revision.build)
  local sym, count = V.sym, V.count
  V.CACHE_VERSION = 6
  V.NATIVE_VERSION = 2
  V.OW_VERSION = 1
  V.ANIM_VERSION = 1
  V.AUDIO_VERSION = 1
  V.POKEMON_VERSION = 1
  V.BATTLE_MOVES_VERSION = 1
  V.BATTLE_ANIMS_VERSION = 1
  V.NATIVE_RENDER, V.OW_RENDER, V.TILESET_ANIM = true, true, true

  V.AUDIO = {
    song_table = sym("gSongTable"), song_count = count("gSongTable", 8),
    cry_table = sym("gCryTable"), cry_count = count("gCryTable", 12),
    cry_table_reverse = sym("gCryTable2"),
  }
  V.OW_GFX_POINTERS = sym("gObjectEventGraphicsInfoPointers")
  V.OW_SPRITE_PALETTES = sym("sObjectEventSpritePalettes")
  V.NUM_OBJ_EVENT_GFX = count("gObjectEventGraphicsInfoPointers", 4)

  -- pokeruby/include/constants/species.h:418
  V.SPECIES_NAME_LENGTH = 11
  V.SPECIES_NAMES = sym("gSpeciesNames")
  V.NUM_SPECIES = count("gSpeciesNames", V.SPECIES_NAME_LENGTH)
  V.SPECIES_INFO_SIZE = 28
  V.SPECIES_INFO = sym("gBaseStats")
  V.SPECIES_TO_NATIONAL = sym("gSpeciesToNationalPokedexNum")
  V.SPECIES_TO_HOENN = sym("gSpeciesToHoennPokedexNum")
  V.HOENN_TO_NATIONAL = sym("gHoennToNationalOrder")
  V.MON_ICON_TABLE = sym("gMonIconTable")
  V.MON_ICON_PAL_INDICES = sym("gMonIconPaletteIndices")
  V.MON_ICON_PALETTES = sym("gMonIconPalettes")
  V.MON_ICON_PAL_COUNT = count("gMonIconPaletteTable", 8)
  V.MON_ICON_BYTES, V.MON_ICON_W, V.MON_ICON_H = 0x400, 32, 32
  V.MON_FRONT_PIC_TABLE = sym("gMonFrontPicTable")
  V.MON_BACK_PIC_TABLE = sym("gMonBackPicTable")
  V.MON_PALETTE_TABLE = sym("gMonPaletteTable")
  V.MON_SHINY_PALETTE_TABLE = sym("gMonShinyPaletteTable")
  V.MON_FRONT_PIC_COORDS = sym("gMonFrontPicCoords")
  V.MON_BACK_PIC_COORDS = sym("gMonBackPicCoords")
  V.ENEMY_MON_ELEVATION = sym("gEnemyMonElevation")
  V.SPINDA_SPOT_GRAPHICS = sym("gSpindaSpotGraphics")

  V.ABILITY_NAME_LENGTH = 12
  V.ABILITY_NAMES = sym("gAbilityNames")
  V.ABILITY_DESCRIPTIONS = sym("gAbilityDescriptions")
  V.ABILITIES_COUNT = count("gAbilityDescriptions", 4)
  V.MOVE_NAME_LENGTH = 12
  V.MOVE_NAMES = sym("gMoveNames")
  V.MOVES_COUNT = count("gMoveNames", V.MOVE_NAME_LENGTH + 1)
  V.MOVE_DESCRIPTIONS = sym("gMoveDescriptions")
  V.BATTLE_MOVES = sym("gBattleMoves")
  V.BATTLE_MOVE_SIZE = 12
  V.LEVEL_UP_LEARNSETS = sym("gLevelUpLearnsets")
  V.EGG_MOVES = sym("gEggMoves")
  V.EGG_MOVES_SPECIES_OFFSET, V.EGG_MOVES_TERMINATOR, V.EGG_MOVES_MAX = 20000, 0xFFFF, 16
  V.EVOLUTION_TABLE = sym("gEvolutionTable")
  V.EVOS_PER_MON, V.EVOLUTION_ENTRY_SIZE = 5, 8
  V.TMHM_LEARNSETS = sym("gTMHMLearnsets")
  V.TMHM_MOVES = sym("TMHMMoves")
  V.TMHM_COUNT = count("TMHMMoves", 2)
  V.TUTOR_MOVE_COUNT = 0

  -- pokeruby/include/pokedex.h:33
  V.POKEDEX_ENTRIES = sym("gPokedexEntries")
  V.POKEDEX_ENTRY_SIZE = 36
  V.NATIONAL_DEX_COUNT = count("gPokedexEntries", V.POKEDEX_ENTRY_SIZE) - 1
  V.POKEDEX_ORDERS = {
    alphabetical = sym("gPokedexOrder_Alphabetical"),
    weight = sym("gPokedexOrder_Weight"), height = sym("gPokedexOrder_Height"),
  }
  V.ITEMS = sym("gItems")
  V.ITEM_STRIDE = 44
  V.ITEMS_COUNT = count("gItems", V.ITEM_STRIDE)
  V.ITEM_EFFECT_TABLE = sym("gItemEffectTable")
  V.ITEM_EFFECT_FIRST = 13
  V.ITEM_EFFECT_LAST = V.ITEM_EFFECT_FIRST + count("gItemEffectTable", 4) - 1

  -- pokeruby/include/battle.h:265
  V.TRAINERS_TABLE = sym("gTrainers")
  V.TRAINER_STRIDE = 40
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
  -- pokeruby/src/data/graphics/trainers.h:72
  V.TRAINER_BACK_PIC_COMPRESSED = true
  -- pokeruby/src/pokemon_2.c:169
  V.TRAINER_BACK_ANIMS_TABLE = sym("gUnknown_081ECACC")
  V.WILD_MON_HEADERS = sym("gWildMonHeaders")
  V.WILD_MON_HEADER_SIZE = 20
  V.WILD_MON_HEADER_COUNT = count("gWildMonHeaders", 20)
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
  V.MULTICHOICE_LISTS = sym("gMultichoiceLists")
  V.MULTICHOICE_COUNT = count("gMultichoiceLists", 8)
  V.S_HEAL_LOCATIONS = sym("heal_location.o:sHealLocations")
  V.NUM_HEAL_LOCATIONS = count("heal_location.o:sHealLocations", 8)
  V.REGION_MAP_ENTRIES = sym("gRegionMapEntries")
  V.BATTLE_STRINGS_TABLE = sym("gBattleStringsTable")
  V.BATTLE_STRINGS_COUNT = count("gBattleStringsTable", 4)
  V.INGAME_TRADES = sym("gIngameTrades")
  V.INGAME_TRADE_SIZE, V.INGAME_TRADE_COUNT = 60, count("gIngameTrades", 60)
  V.INGAME_TRADE_MAIL = sym("gIngameTradeMail")
  V.INGAME_TRADE_MAIL_COUNT = count("gIngameTradeMail", 20)
  V.BERRIES = sym("gBerries")
  V.BERRY_STRIDE, V.BERRY_COUNT = 28, count("gBerries", 28)
  V.POKEBLOCK_NAMES = sym("gPokeblockNames")
  V.POKEBLOCK_NAME_COUNT = count("gPokeblockNames", 4)
  V.CONTEST_MOVES, V.CONTEST_MOVE_STRIDE = sym("gContestMoves"), 8
  V.CONTEST_MOVES_COUNT = count("gContestMoves", 8)
  V.CONTEST_EFFECTS, V.CONTEST_EFFECT_STRIDE = sym("gContestEffects"), 4
  V.CONTEST_EFFECTS_COUNT = count("gContestEffects", 4)

  require("src.import.gba.games.rs.scripts")(V)
  require("src.import.gba.games.rs.text")(V)
  require("src.import.gba.games.rs.data")(V)
  require("src.import.gba.games.rs.pokemon_gfx")(V)
  require("src.import.gba.games.rs.text_chrome")(V)
  require("src.import.gba.games.rs.audio")(V)
  require("src.import.gba.games.rs.field")(V)
  require("src.import.gba.games.rs.battle")(V)
  require("src.import.gba.games.rs.transitions")(V)
  require("src.import.gba.games.rs.anims")(V)
  require("src.import.gba.games.rs.ui")(V)

  local ROW = {
    id = game .. "_" .. revision.label:gsub("%.", "_"), game = game,
    build = revision.build, revision = revision.label, sha1 = revision.sha1,
    tilesets = {}, layouts = {}, map_headers = {},
    g_map_groups = V.G_MAP_GROUPS, g_map_layouts = V.G_MAP_LAYOUTS,
    num_map_groups = V.NUM_MAP_GROUPS, ow_gfx_pointers = V.OW_GFX_POINTERS,
    ow_sprite_palettes = V.OW_SPRITE_PALETTES, num_obj_event_gfx = V.NUM_OBJ_EVENT_GFX,
  }
  V.BY_SHA1[revision.sha1] = ROW
  return V
end

function Rs.new(game)
  local revisions = assert(Builds[game], "unknown RS game")
  local byHash, loaded = {}, {}
  for _, revision in ipairs(revisions) do byHash[revision.sha1] = revision end
  local function resolve(identity)
    if identity == game then return revisions[1] end
    local hash = type(identity) == "string" and identity:lower():gsub("%s+", "") or nil
    return hash and byHash[hash] or nil
  end
  local function load(revision)
    local V = loaded[revision.build]
    if not V then V = tables(game, revision); loaded[revision.build] = V end
    return V
  end
  local selectedRevision = revisions[1]
  local function selected() return load(selectedRevision) end
  local facade = {}
  function facade.select(identity)
    local revision = resolve(identity)
    if not revision then error("versions(" .. game .. "): unknown identity " .. tostring(identity), 2) end
    load(revision)
    selectedRevision = revision
  end
  function facade.lookup(identity)
    local revision = resolve(identity)
    if not revision then return nil, "unsupported or unknown " .. game .. " dump SHA-1" end
    return load(revision).BY_SHA1[revision.sha1]
  end
  facade.lookupSha1 = facade.lookup
  return setmetatable(facade, {
    __index = function(_, key) return selected()[key] end,
    __newindex = function(_, key, value) selected()[key] = value end,
  })
end

return Rs

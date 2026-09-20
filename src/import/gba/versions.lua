-- Known clean US FireRed dumps → extract pointers (ROM file offsets).
-- Pointers are for FireRed USA 1.0 (SHA-1 41cb23d8…). Identity is SHA-1 only.

local Versions = {}

Versions.ROM_SIZE = 16777216
-- v53: outdoor LAB continuity — shared Y cuts, frlg bias, mid cohere, MRF.
-- v67: extract-first MapEvents + script BFS (cache is script/event source of truth)
-- v68: native FRLG mid atlas + pret map palettes (demake 2bpp still stored)
-- Text charmap $F0=':' fix lives in text_ir.lua; re-run script extract to refresh
-- cached strings (live cache was patched in-place for the yen→colon bug).
-- v72: naming keyboard 1:1 — cursor 2×2 frames, cropped KB, CLEAR row text
-- v75: restore title_screen.png composite + press_start / copyright aliases
-- v76: intro movie layout — copyright crop, GF sprite coords, scene1 frames
-- v77: GF presents center fix, scene3 gengar/bg pal, copyright x=0 crop
-- v78: scene2 PLTT slot shift, scene1 128px frames, scene3 grass 64×32
-- v79: title flames 10-frame sheet; title screen on Bg+Oam compositor
-- v80: trainer tables + battle intro back pics / party summary bar
-- v85: dual-layer native atlas (under/over) for pret BG2 sprite cover
-- v86: battle_transition ROM gfx → pokemon/battle_transition/
-- v87: standard Lua array LZ77 decompression + robust chrome extraction for Android
-- v88: authentic 1:1 FRLG trainer card composite (BG0+BG2), badges & Red/Leaf trainer pic fix
-- v89: summary base tilemaps from ROM (fix magenta bg on Android), keypad icons extracted from ROM
-- v90: fanfare audio cues, emote cues (0x62-0x66), pause menu YES/NO exit & main menu launcher exit
-- v91: ROM-native Help topics, context lists, text and chrome.
-- v93: original furniture/sign scripts and metatile interaction behaviors.
-- v99: gEggMoves → pokemon/egg_moves.lua (hidden-mon egg moves were inert).
-- v100: location preview screens (sMapPreviewScreenData artwork) + ROM-derived
--       mapsec names and sDungeonInfo dungeon descriptions.
Versions.CACHE_VERSION = 101
Versions.NATIVE_VERSION = 5
Versions.OW_VERSION = 1
Versions.ANIM_VERSION = 1
-- Audio pack (M4A banks / DirectSound samples / cries).
Versions.AUDIO_VERSION = 6
-- FireRed USA 1.0 (BPRE) — located by structural scan (entry0 ms=me=0, SE_SELECT ms=me=2).
Versions.AUDIO = {
  song_table = 0x4A32CC,   -- gSongTable file offset
  song_count = 347,        -- ids 0 .. MUS_TEACHY_TV_MENU (346)
  cry_table = 0x48C914,    -- gCryTable (ToneData × 388)
  cry_count = 388,
}
-- game3 FieldView prefers pret 4bpp path when native cache is ready.
Versions.NATIVE_RENDER = true
Versions.OW_RENDER = true
Versions.TILESET_ANIM = true

--- GBA ROM pointer → file offset, or nil if not in ROM image.
function Versions.gbaToFile(addr)
  addr = tonumber(addr)
  if not addr or addr < 0x08000000 or addr >= 0x0A000000 then return nil end
  return addr - 0x08000000
end

-- FireRed USA 1.0 overworld object graphics (pret pokefirered.sym).
Versions.OW_GFX_POINTERS = 0x39FDB0       -- gObjectEventGraphicsInfoPointers
Versions.OW_SPRITE_PALETTES = 0x3A5158    -- sObjectEventSpritePalettes
Versions.NUM_OBJ_EVENT_GFX = 152
-- pret OBJ_EVENT_GFX_RED / OBJ_EVENT_GFX_GREEN (Leaf)
Versions.OW_PLAYER_MALE = 0
Versions.OW_PLAYER_MALE_BIKE = 1
Versions.OW_PLAYER_MALE_SURF = 2
Versions.OW_PLAYER_MALE_FIELD_MOVE = 3
Versions.OW_PLAYER_MALE_FISH = 4
Versions.OW_PLAYER_FEMALE = 7
Versions.OW_PLAYER_FEMALE_BIKE = 8
Versions.OW_PLAYER_FEMALE_SURF = 9
Versions.OW_PLAYER_FEMALE_FIELD_MOVE = 10
Versions.OW_PLAYER_FEMALE_FISH = 11
-- FireRed USA 1.0 font (menu cursor = SelectorArrow2 / charmap ▶ = 0xEF).
Versions.FONT_LATIN_NORMAL = 0x1FF300       -- sFontNormalLatinGlyphs
Versions.FONT_LATIN_WIDTHS = 0x207300       -- sFontNormalLatinGlyphWidths
Versions.FONT_GLYPH_BYTES = 64              -- 0x20 u16s per latin glyph
Versions.MENU_CURSOR_GLYPH = 0xEF           -- gText_SelectorArrow2

-- Pokémon species pack (names / icons / types / stats / abilities) — FireRed USA 1.0.
Versions.POKEMON_VERSION = 3
Versions.NUM_SPECIES = 412                -- SPECIES_NONE .. last (incl. egg/forms)
Versions.SPECIES_NAMES = 0x245EE0         -- gSpeciesNames
Versions.SPECIES_NAME_LENGTH = 11         -- 10 chars + 0xFF
Versions.SPECIES_INFO = 0x254784          -- gSpeciesInfo / BaseStats (28 bytes)
Versions.SPECIES_INFO_SIZE = 28
Versions.MON_ICON_TABLE = 0x3D37A0       -- gMonIconTable
Versions.MON_ICON_PAL_INDICES = 0x3D3E80  -- gMonIconPaletteIndices
Versions.MON_ICON_PALETTES = 0x3D3740     -- gMonIconPalettes (16 colors × N)
Versions.MON_ICON_PAL_COUNT = 6
Versions.MON_ICON_BYTES = 0x400           -- 32×64 4bpp (2 frames)
Versions.MON_ICON_W = 32
Versions.MON_ICON_H = 32                  -- first frame only
-- sSpeciesToNationalPokedexNum[NUM_SPECIES-1]; SpeciesToNational uses [species-1].
Versions.SPECIES_TO_NATIONAL = 0x251FEE
-- gAbilityNames[ABILITIES_COUNT][ABILITY_NAME_LENGTH+1] (FireRed USA 1.0 file off).
Versions.ABILITY_NAMES = 0x24FC40
Versions.ABILITY_NAME_LENGTH = 12
Versions.ABILITIES_COUNT = 78
Versions.ABILITY_DESCRIPTIONS = 0x24FB08   -- gAbilityDescriptionPointers (78 pointers)

-- Moves / learnsets / evolutions / TMHM / dex (FireRed USA 1.0 file offsets).
Versions.MOVE_NAMES = 0x247094            -- gMoveNames
Versions.MOVE_NAME_LENGTH = 12            -- +1 EOS → 13-byte stride
Versions.MOVE_DESCRIPTIONS = 0x4886E8     -- gMoveDescriptionPointers (354 pointers)
Versions.LEVEL_UP_LEARNSETS = 0x25D7B4    -- gLevelUpLearnsets pointer table
-- gEggMoves (pokefirered/src/data/pokemon/egg_moves.h).  Not a pointer table:
-- one flat u16 stream of `{ species + EGG_MOVES_SPECIES_OFFSET, move…, 0xFFFF }`
-- runs, each run ended by EGG_MOVES_TERMINATOR; the table simply stops after the
-- last run, so the following symbol's data ends the scan.  Only species that
-- actually have an egg move appear, so it is sparse.
Versions.EGG_MOVES = 0x25EF0C             -- gEggMoves (FireRed USA 1.0)
Versions.EGG_MOVES_SPECIES_OFFSET = 20000
Versions.EGG_MOVES_TERMINATOR = 0xFFFF
Versions.EGG_MOVES_MAX = 16               -- per species; the ROM's real max is 8
Versions.EVOLUTION_TABLE = 0x259754       -- gEvolutionTable
Versions.EVOS_PER_MON = 5
Versions.EVOLUTION_ENTRY_SIZE = 8         -- method,u16 param,u16 target,u16 pad
Versions.TMHM_LEARNSETS = 0x252BC8        -- sTMHMLearnsets (u32 lo + u32 hi)
Versions.TMHM_MOVES = 0x45A5A4            -- sTMHMMoves[58] u16
Versions.TMHM_COUNT = 58                  -- 50 TM + 8 HM
Versions.POKEDEX_ENTRIES = 0x44E850       -- gPokedexEntries (national index)
Versions.POKEDEX_ENTRY_SIZE = 36
Versions.NATIONAL_DEX_COUNT = 386         -- Deoxys; entries are 0..386 inclusive → 387
Versions.SPECIES_TO_KANTO = 0x251EE0      -- sSpeciesToKantoPokedexNum (411 u16s)
Versions.DEX_CATEGORIES = 0x452C4C        -- gDexCategories (9 categories)
Versions.EASY_CHAT_GROUPS = 0x3ECED4       -- sEasyChatGroups (22 entries × 8 bytes)
Versions.EASY_CHAT_GROUP_COUNT = 22
Versions.POKEDEX_ORDERS = {
  alphabetical = 0x443FF2,
  weight = 0x4442F6,
  height = 0x4445FA,
  type = 0x4448FE,
}

-- Region map & location preview screens (pokefirered src/region_map.c,
-- src/map_preview_screen.c, include/map_preview_screen.h).
-- sMapPreviewScreenData[]: struct MapPreviewScreen { u8 mapsec; u8 type;
-- u16 flagId; const void *tilesptr; const void *tilemapptr; const void *palptr; }
Versions.MAP_PREVIEW_SCREEN_DATA = 0x43E9E8
Versions.MAP_PREVIEW_COUNT = 28
Versions.MAP_PREVIEW_ENTRY_SIZE = 16
Versions.MAP_PREVIEW_TYPE_CAVE = 0         -- MPS_TYPE_CAVE
Versions.MAP_PREVIEW_TYPE_FOREST = 1       -- MPS_TYPE_FOREST
-- CopyToBgTilemapBufferRect(2, tilemap, 0, 0, 32, 20) — 640 u16 = 1280 bytes.
Versions.MAP_PREVIEW_TILEMAP_W = 32
Versions.MAP_PREVIEW_TILEMAP_H = 20
-- Each entry's palptr holds 0x40 bytes (32 BGR555 colours = BG banks 13 and 14);
-- palptr + 0x40 == tilesptr for all 28 entries and tilesptr starts with its LZ77
-- header, so the palette cannot be longer. pret's MapPreview_LoadGfx asks for 3
-- banks (0x60 bytes) and so also copies that LZ77 header into bank 15, but no
-- tilemap entry in the visible area references bank 15.
Versions.MAP_PREVIEW_PALETTE_COUNT = 32
Versions.MAP_PREVIEW_PALETTE_BYTES = 0x40
Versions.MAP_PREVIEW_PALETTE_BANKS = 2
-- Tilemap entries reference banks 13 and 14 only across visible columns 0-29;
-- the sole bank-0 references sit in the off-screen padding columns 30-31.
Versions.MAP_PREVIEW_BANK_LO = 13
Versions.MAP_PREVIEW_BANK_HI = 14
-- sMapsecName_* — one 0xFF-terminated string per mapsec, ascending, contiguous.
Versions.MAPSEC_NAMES = 0x3EECFC
-- sRegionMapSectionIdToName[] — 109 pointers into the block above; usable as a
-- defensive cross-check (table[i] == offset of the i-th string).
Versions.MAPSEC_NAME_POINTERS = 0x3F1CAC
Versions.MAPSEC_FIRST = 88                 -- MAPSEC_PALLET_TOWN
Versions.MAPSEC_LAST = 196                 -- MAPSEC_SPECIAL_AREA
Versions.MAPSEC_COUNT = 109
-- sDungeonInfo[]: struct DungeonMapInfo { u32 id; const u8 *name; const u8 *desc; }
Versions.DUNGEON_INFO = 0x3F1B3C
Versions.DUNGEON_INFO_COUNT = 19
Versions.DUNGEON_INFO_ENTRY_SIZE = 12

-- Multichoice list table (FireRed USA 1.0). gMultichoiceLists (65 lists).
Versions.MULTICHOICE_LISTS = 0x3E04B0
Versions.MULTICHOICE_COUNT = 65

-- Items table (FireRed USA 1.0). 375 entries × 44 bytes stride.
Versions.ITEMS = 0x3DB028
Versions.ITEMS_COUNT = 375
Versions.ITEM_STRIDE = 44

-- Region map section names table (FireRed USA 1.0).
Versions.KANTO_MAPSEC_START = 88   -- 0x58 (MAPSEC_PALLET_TOWN)
Versions.KANTO_MAPSEC_COUNT = 109  -- 88..196 (MAPSEC_PALLET_TOWN .. MAPSEC_SPECIAL_AREA)

-- gBattleMoves (FireRed USA 1.0). Rows are 12 bytes (9-byte BattleMove + pad).
Versions.BATTLE_MOVES_VERSION = 1
Versions.BATTLE_MOVES = 0x250C04
Versions.BATTLE_MOVE_SIZE = 12
Versions.MOVES_COUNT = 355 -- MOVE_NONE .. last Gen3 move id inclusive span

-- Battle anim IR pack — ROM-native bytecode extraction (FireRed USA 1.0).
-- Addresses verified by structural scan of the ROM.
Versions.BATTLE_ANIMS_VERSION = 5
Versions.BATTLE_ANIMS = {
  -- gBattleAnims_Moves: 355 GBA pointers to bytecode scripts (one per move id 0..354).
  moves_table   = 0x1C68F4,
  move_count    = 355,
  status_table  = 0x1C6E84,
  status_count  = 9,
  general_table = 0x1C6EA8,
  general_count = 28,
  special_table = 0x1C6F18,
  special_count = 7,
  -- gBattleAnimPicTable: 289 CompressedSpriteSheet entries, stride 8 (ptr+size).
  -- pic_ptr = rom:u32(pic_table + tag_idx*8), palette = rom:u32(pal_table + tag_idx*8)
  pic_table     = 0x3ACC08,
  pal_table     = 0x3AD510,
  tag_count     = 289,       -- ANIM_SPRITES_START+0 .. ANIM_SPRITES_START+288
  sprites_start = 10000,     -- ANIM_SPRITES_START constant
  -- pokefirered/src/graphics.c:841
  substitute_pal   = 0xD2D090,
  substitute_front = 0xD2D0B4,
  substitute_back  = 0xD2D2F4,
  -- pokefirered/src/graphics.c:857
  stat_mask_gfx      = 0xD2D8F4,
  stat_mask_tilemap1 = 0xD2DB04,
  stat_mask_tilemap2 = 0xD2DC20,
  stat_mask_pal      = 0xD2DD3C,
  -- pokefirered/src/graphics.c:17
  smokescreen_gfx = 0xD0162C,
  smokescreen_pal = 0xD0170C,
  -- pokefirered/src/graphics.c:990
  muddy_water_pal = 0xE7BAB0,
  named_bgs = {
    -- pokefirered/src/graphics.c:705
    ATTRACT = { gfx = 0xD234B4, pal = 0xD23F24, map = 0xD23F4C },
    -- pokefirered/src/graphics.c:723
    SCARY_FACE_PLAYER = { gfx = 0xD24BCC, pal = 0xD24BA4, map = 0xE7F4AC },
    SCARY_FACE_OPPONENT = { gfx = 0xD24BCC, pal = 0xD24BA4, map = 0xE7F690 },
    -- pokefirered/src/graphics.c:817
    MORNING_SUN = { gfx = 0xD2A808, pal = 0xD2A8A8, map = 0xD2A8C0 },
    -- pokefirered/src/graphics.c:565
    METAL_SHINE = { gfx = 0xD1D224, pal = 0xD1D360, map = 0xD1D388 },
    -- pokefirered/src/graphics.c:870
    CURE_BUBBLES = { gfx = 0xD2DE3C, pal = 0xD2DF78, map = 0xD2DF98 },
    -- pokefirered/src/graphics.c:643
    CURSE = { gfx = 0xD2083C, map = 0xD20858, pal_white1 = true },
    -- pokefirered/src/field_weather.c:130
    FOG = { gfx_raw = 0x3C3540, gfx_size = 0x800, pal_raw = 0x3C2CE0, map = 0xE7F1F4 },
    -- pokefirered/src/graphics.c:939
    SANDSTORM = { gfx = 0xE794D0, pal_tag = "FLYING_DIRT", map = 0xE79354 },
    -- pokefirered/src/graphics.c:1055
    SURF_PLAYER = { gfx = 0xE809CC, pal = 0xE81CEC, map = 0xE81FE4 },
    SURF_OPPONENT = { gfx = 0xE809CC, pal = 0xE81CEC, map = 0xE81D14 },
  },
}

-- ANIM_TAG_* index → name string (from pokefirered/include/constants/battle_anim.h).
-- Indices not in this list are unused/reserved (false = skip extraction).
Versions.ANIM_TAG_NAMES = {
  [0]="BONE",[1]="SPARK",[2]="PENCIL",[3]="AIR_WAVE",[4]="ORB",[5]="SWORD",
  [6]="SEED",[7]="EXPLOSION_6",[8]="PINK_ORB",[9]="GUST",[10]="ICE_CUBE",
  [11]="SPARK_2",[12]="ORANGE",[13]="YELLOW_BALL",[14]="LOCK_ON",[15]="TIED_BAG",
  [16]="BLACK_SMOKE",[17]="BLACK_BALL",[18]="CONVERSION",[19]="GLASS",
  [20]="HORN_HIT",[21]="HIT",[22]="HIT_2",[23]="BLUE_SHARDS",[24]="CLOSING_EYE",
  [25]="WAVING_HAND",[26]="HIT_DUPLICATE",[27]="LEER",[28]="BLUE_BURST",
  [29]="SMALL_EMBER",[30]="GRAY_SMOKE",[31]="BLUE_STAR",[32]="BUBBLE_BURST",
  [33]="FIRE",[34]="SPINNING_FIRE",[35]="FIRE_PLUME",[36]="LIGHTNING_2",
  [37]="LIGHTNING",[38]="CLAW_SLASH_2",[39]="CLAW_SLASH",[40]="SCRATCH_3",
  [41]="SCRATCH_2",[42]="BUBBLE_BURST_2",[43]="ICE_CHUNK",[44]="GLASS_2",
  [45]="PINK_HEART_2",[46]="SAP_DRIP",[47]="SAP_DRIP_2",[48]="SPARKLE_1",
  [49]="SPARKLE_2",[50]="HUMANOID_FOOT",[51]="MONSTER_FOOT",[52]="HUMANOID_HAND",
  [53]="NOISE_LINE",[54]="YELLOW_UNK",[55]="RED_FIST",[56]="SLAM_HIT",[57]="RING",
  [58]="ROCKS",[59]="Z",[60]="YELLOW_UNK_2",[61]="AIR_SLASH",[62]="SPINNING_GREEN_ORBS",
  [63]="LEAF",[64]="FINGER",[65]="POISON_POWDER",[66]="BROWN_TRIANGLE",
  [67]="SLEEP_POWDER",[68]="STUN_SPORE",[69]="POWDER",[70]="SPARKLE_3",
  [71]="SPARKLE_4",[72]="MUSIC_NOTES",[73]="DUCK",[74]="MUD_SAND",[75]="ALERT",
  [76]="BLUE_FLAMES",[77]="BLUE_FLAMES_2",[78]="SHOCK_4",[79]="SHOCK",
  [80]="BELL_2",[81]="PINK_GLOVE",[82]="BLUE_LINES",[83]="IMPACT_3",[84]="IMPACT_2",
  [85]="RETICLE",[86]="BREATH",[87]="ANGER",[88]="SNOWBALL",[89]="VINE",
  [90]="SWORD_2",[91]="CLAPPING",[92]="RED_TUBE",[93]="AMNESIA",[94]="STRING_2",
  [95]="PENCIL_2",[96]="PETAL",[97]="BENT_SPOON",[98]="WEB",[99]="MILK_BOTTLE",
  [100]="COIN",[101]="CRACKED_EGG",[102]="HATCHED_EGG",[103]="FRESH_EGG",
  [104]="FANGS",[105]="EXPLOSION_2",[106]="EXPLOSION_3",[107]="WATER_DROPLET",
  [108]="WATER_DROPLET_2",[109]="SEED_2",[110]="SPROUT",[111]="RED_WAND",
  [112]="PURPLE_GREEN_UNK",[113]="WATER_COLUMN",[114]="MUD_UNK",[115]="RAIN_DROPS",
  [116]="FURY_SWIPES",[117]="VINE_2",[118]="TEETH",[119]="BONE_2",[120]="WHITE_BAG",
  [121]="UNKNOWN",[122]="PURPLE_CORAL",[123]="PURPLE_DROPLET",[124]="SHOCK_2",
  [125]="CLOSING_EYE_2",[126]="METAL_BALL",[127]="MONSTER_DOLL",[128]="WHIRLWIND",
  [129]="WHIRLWIND_2",[130]="EXPLOSION_4",[131]="EXPLOSION_5",[132]="TONGUE",
  [133]="SMOKE",[134]="SMOKE_2",[135]="IMPACT",[136]="CIRCLE_IMPACT",[137]="SCRATCH",
  [138]="CUT",[139]="SHARP_TEETH",[140]="RAINBOW_RINGS",[141]="ICE_CRYSTALS",
  [142]="ICE_SPIKES",[143]="HANDS_AND_FEET",[144]="MIST_CLOUD",[145]="CLAMP",
  [146]="BUBBLE",[147]="ORBS",[148]="WATER_IMPACT",[149]="WATER_ORB",
  [150]="POISON_BUBBLE",[151]="TOXIC_BUBBLE",[152]="SPIKES",[153]="HORN_HIT_2",
  [154]="AIR_WAVE_2",[155]="SMALL_BUBBLES",[156]="ROUND_SHADOW",[157]="SUNLIGHT",
  [158]="SPORE",[159]="FLOWER",[160]="RAZOR_LEAF",[161]="NEEDLE",
  [162]="WHIRLWIND_LINES",[163]="GOLD_RING",[164]="PURPLE_RING",[165]="BLUE_RING",
  [166]="GREEN_LIGHT_WALL",[167]="BLUE_LIGHT_WALL",[168]="RED_LIGHT_WALL",
  [169]="GRAY_LIGHT_WALL",[170]="ORANGE_LIGHT_WALL",[171]="BLACK_BALL_2",
  [172]="PURPLE_GAS_CLOUD",[173]="SPARK_H",[174]="YELLOW_STAR",[175]="LARGE_FRESH_EGG",
  [176]="SHADOW_BALL",[177]="LICK",[178]="VOID_LINES",[179]="STRING",
  [180]="WEB_THREAD",[181]="SPIDER_WEB",[182]="LIGHTBULB",[183]="SLASH",
  [184]="FOCUS_ENERGY",[185]="SPHERE_TO_CUBE",[186]="TENDRILS",[187]="EYE",
  [188]="WHITE_SHADOW",[189]="TEAL_ALERT",[190]="OPENING_EYE",
  [191]="ROUND_WHITE_HALO",[192]="FANG_ATTACK",[193]="PURPLE_HAND_OUTLINE",
  [194]="MOON",[195]="GREEN_SPARKLE",[196]="SPIRAL",[197]="SNORE_Z",
  [198]="EXPLOSION",[199]="NAIL",[200]="GHOSTLY_SPIRIT",[201]="WARM_ROCK",
  [202]="BREAKING_EGG",[203]="THIN_RING",[204]="PUNCH_IMPACT",[205]="BELL",
  [206]="MUSIC_NOTES_2",[207]="SPEED_DUST",[208]="TORN_METAL",[209]="THOUGHT_BUBBLE",
  [210]="MAGENTA_HEART",[211]="ELECTRIC_ORBS",[212]="CIRCLE_OF_LIGHT",
  [213]="ELECTRICITY",[214]="FINGER_2",[215]="MOVEMENT_WAVES",[216]="RED_HEART",
  [217]="RED_ORB",[218]="EYE_SPARKLE",[219]="PINK_HEART",[220]="ANGEL",
  [221]="DEVIL",[222]="SWIPE",[223]="ROOTS",[224]="ITEM_BAG",
  [225]="JAGGED_MUSIC_NOTE",[226]="POKEBALL",[227]="SPOTLIGHT",[228]="LETTER_Z",
  [229]="RAPID_SPIN",[230]="TRI_ATTACK_TRIANGLE",[231]="WISP_ORB",[232]="WISP_FIRE",
  [233]="GOLD_STARS",[234]="ECLIPSING_ORB",[235]="GRAY_ORB",[236]="BLUE_ORB",
  [237]="RED_ORB_2",[238]="PINK_PETAL",[239]="PAIN_SPLIT",[240]="CONFETTI",
  [241]="GREEN_STAR",[242]="PINK_CLOUD",[243]="SWEAT_DROP",[244]="GUARD_RING",
  [245]="PURPLE_SCRATCH",[246]="PURPLE_SWIPE",[247]="TAG_HAND",[248]="SMALL_RED_EYE",
  [249]="HOLLOW_ORB",[250]="X_SIGN",[251]="BLUEGREEN_ORB",[252]="PAW_PRINT",
  [253]="PURPLE_FLAME",[254]="RED_BALL",[255]="SMELLINGSALT_EFFECT",[256]="METEOR",
  [257]="FLAT_ROCK",[258]="MAGNIFYING_GLASS",[259]="BROWN_ORB",
  [260]="METAL_SOUND_WAVES",[261]="FLYING_DIRT",[262]="ICICLE_SPEAR",[263]="HAIL",
  [264]="GLOWY_RED_ORB",[265]="GLOWY_GREEN_ORB",[266]="GREEN_SPIKE",
  [267]="WHITE_CIRCLE_OF_LIGHT",[268]="GLOWY_BLUE_ORB",[269]="SAFARI_BAIT",
  [270]="WHITE_FEATHER",[271]="SPARKLE_6",[272]="SPLASH",[273]="SWEAT_BEAD",
  [274]="GEM_1",[275]="GEM_2",[276]="GEM_3",[277]="SLAM_HIT_2",[278]="RECYCLE",
  [279]="RED_PARTICLES",[280]="PROTECT",[281]="DIRT_MOUND",[282]="SHOCK_3",
  [283]="WEATHER_BALL",[284]="BIRD",[285]="CROSS_IMPACT",[286]="SLASH_2",
  [287]="WHIP_HIT",[288]="BLUE_RING_2",
}

Versions.ANIM_TEMPLATE_NAMES = {
  [0x083BF434] = "gWeatherBallUpSpriteTemplate",
  [0x083BF44C] = "gWeatherBallNormalDownSpriteTemplate",
  [0x083BF480] = "gSpinningSparkleSpriteTemplate",
  [0x083D4E54] = "gHorizontalLungeSpriteTemplate",
  [0x083D4E6C] = "gVerticalDipSpriteTemplate",
  [0x083D4E84] = "gSlideMonToOriginalPosSpriteTemplate",
  [0x083D4E9C] = "gSlideMonToOffsetSpriteTemplate",
  [0x083D4EB4] = "gSlideMonToOffsetAndBackSpriteTemplate",
  [0x083E2990] = "gSleepPowderParticleSpriteTemplate",
  [0x083E29A8] = "gStunSporeParticleSpriteTemplate",
  [0x083E29C0] = "gPoisonPowderParticleSpriteTemplate",
  [0x083E2A58] = "gPowerAbsorptionOrbSpriteTemplate",
  [0x083E2A70] = "gSolarBeamBigOrbSpriteTemplate",
  [0x083E2ABC] = "gStockpileAbsorptionOrbSpriteTemplate",
  [0x083E2AE8] = "gAbsorptionOrbSpriteTemplate",
  [0x083E2B00] = "gHyperBeamOrbSpriteTemplate",
  [0x083E2B34] = "gLeechSeedSpriteTemplate",
  [0x083E2B64] = "gSporeParticleSpriteTemplate",
  [0x083E2B94] = "gPetalDanceBigFlowerSpriteTemplate",
  [0x083E2BAC] = "gPetalDanceSmallFlowerSpriteTemplate",
  [0x083E2C08] = "gRazorLeafParticleSpriteTemplate",
  [0x083E2C20] = "gTwisterLeafSpriteTemplate",
  [0x083E2C50] = "gRazorLeafCutterSpriteTemplate",
  [0x083E2C7C] = "gSwiftStarSpriteTemplate",
  [0x083E2D0C] = "gConstrictBindingSpriteTemplate",
  [0x083E2D54] = "gMimicOrbSpriteTemplate",
  [0x083E2DC4] = "gIngrainRootSpriteTemplate",
  [0x083E2DDC] = "gFrenzyPlantRootSpriteTemplate",
  [0x083E2E04] = "gIngrainOrbSpriteTemplate",
  [0x083E2E88] = "gPresentSpriteTemplate",
  [0x083E2EA0] = "gKnockOffItemSpriteTemplate",
  [0x083E2ED0] = "gPresentHealParticleSpriteTemplate",
  [0x083E2EE8] = "gItemStealSpriteTemplate",
  [0x083E2F60] = "gTrickBagSpriteTemplate",
  [0x083E3024] = "gAromatherapySmallFlowerSpriteTemplate",
  [0x083E303C] = "gAromatherapyBigFlowerSpriteTemplate",
  [0x083E30A8] = "gSilverWindBigSparkSpriteTemplate",
  [0x083E30C0] = "gSilverWindMediumSparkSpriteTemplate",
  [0x083E30D8] = "gSilverWindSmallSparkSpriteTemplate",
  [0x083E3100] = "gNeedleArmSpikeSpriteTemplate",
  [0x083E3148] = "gSlamHitSpriteTemplate",
  [0x083E3160] = "gVineWhipSpriteTemplate",
  [0x083E3294] = "gCuttingSliceSpriteTemplate",
  [0x083E32AC] = "gAirCutterSliceSpriteTemplate",
  [0x083E3354] = "gProtectSpriteTemplate",
  [0x083E33B4] = "gMilkBottleSpriteTemplate",
  [0x083E33F4] = "gGrantingStarsSpriteTemplate",
  [0x083E340C] = "gSparklingStarsSpriteTemplate",
  [0x083E3500] = "gSleepLetterZSpriteTemplate",
  [0x083E3518] = "gLockOnTargetSpriteTemplate",
  [0x083E3530] = "gLockOnMoveTargetSpriteTemplate",
  [0x083E3550] = "gBowMonSpriteTemplate",
  [0x083E35A4] = "gSlashSliceSpriteTemplate",
  [0x083E35BC] = "gFalseSwipeSliceSpriteTemplate",
  [0x083E35D4] = "gFalseSwipePositionedSliceSpriteTemplate",
  [0x083E3604] = "gEndureEnergySpriteTemplate",
  [0x083E365C] = "gSharpenSphereSpriteTemplate",
  [0x083E3674] = "gOctazookaBallSpriteTemplate",
  [0x083E36A8] = "gOctazookaSmokeSpriteTemplate",
  [0x083E36EC] = "gConversionSpriteTemplate",
  [0x083E371C] = "gConversion2SpriteTemplate",
  [0x083E3734] = "gMoonSpriteTemplate",
  [0x083E3764] = "gMoonlightSparkleSpriteTemplate",
  [0x083E37A4] = "gHealingBlueStarSpriteTemplate",
  [0x083E37BC] = "gHornHitSpriteTemplate",
  [0x083E37EC] = "gSuperFangSpriteTemplate",
  [0x083E3880] = "gWavyMusicNotesSpriteTemplate",
  [0x083E38C8] = "gFastFlyingMusicNotesSpriteTemplate",
  [0x083E38E0] = "gBellyDrumHandSpriteTemplate",
  [0x083E3914] = "gSlowFlyingMusicNotesSpriteTemplate",
  [0x083E398C] = "gThoughtBubbleSpriteTemplate",
  [0x083E3A34] = "gMetronomeFingerSpriteTemplate",
  [0x083E3A4C] = "gFollowMeFingerSpriteTemplate",
  [0x083E3AC4] = "gTauntFingerSpriteTemplate",
  [0x083E3BBC] = "gKinesisZapEnergySpriteTemplate",
  [0x083E3BF8] = "gSwordsDanceBladeSpriteTemplate",
  [0x083E3C10] = "gSonicBoomSpriteTemplate",
  [0x083E3CA0] = "gSupersonicRingSpriteTemplate",
  [0x083E3CB8] = "gScreechRingSpriteTemplate",
  [0x083E3CD0] = "gMetalSoundSpriteTemplate",
  [0x083E3CE8] = "gWaterPulseRingSpriteTemplate",
  [0x083E3D00] = "gEggThrowSpriteTemplate",
  [0x083E3D50] = "gCoinThrowSpriteTemplate",
  [0x083E3D68] = "gFallingCoinSpriteTemplate",
  [0x083E3D94] = "gBulletSeedSpriteTemplate",
  [0x083E3DC8] = "gRazorWindTornadoSpriteTemplate",
  [0x083E3E08] = "gViceGripSpriteTemplate",
  [0x083E3E48] = "gGuillotineSpriteTemplate",
  [0x083E3ED0] = "gBreathPuffSpriteTemplate",
  [0x083E3F04] = "gAngerMarkSpriteTemplate",
  [0x083E3F4C] = "gPencilSpriteTemplate",
  [0x083E3F64] = "gSnoreZSpriteTemplate",
  [0x083E3F94] = "gExplosionSpriteTemplate",
  [0x083E4028] = "gSoftBoiledEggSpriteTemplate",
  [0x083E4094] = "gThinRingExpandingSpriteTemplate",
  [0x083E40C8] = "gThinRingShrinkingSpriteTemplate",
  [0x083E40E0] = "gBlendThinRingExpandingSpriteTemplate",
  [0x083E40F8] = "gHyperVoiceRingSpriteTemplate",
  [0x083E4110] = "gUproarRingSpriteTemplate",
  [0x083E41B0] = "gBellSpriteTemplate",
  [0x083E41D0] = "gHealBellMusicNoteSpriteTemplate",
  [0x083E41E8] = "gMagentaHeartSpriteTemplate",
  [0x083E4218] = "gRedHeartProjectileSpriteTemplate",
  [0x083E4230] = "gRedHeartBurstSpriteTemplate",
  [0x083E4248] = "gRedHeartRisingSpriteTemplate",
  [0x083E427C] = "gHiddenPowerOrbSpriteTemplate",
  [0x083E4294] = "gHiddenPowerOrbScatterSpriteTemplate",
  [0x083E42C8] = "gSpitUpOrbSpriteTemplate",
  [0x083E42FC] = "gEyeSparkleSpriteTemplate",
  [0x083E4320] = "gAngelSpriteTemplate",
  [0x083E4338] = "gPinkHeartSpriteTemplate",
  [0x083E4368] = "gDevilSpriteTemplate",
  [0x083E43B0] = "gFurySwipesSpriteTemplate",
  [0x083E43F8] = "gMovementWavesSpriteTemplate",
  [0x083E4430] = "gJaggedMusicNoteSpriteTemplate",
  [0x083E4484] = "gPerishSongMusicNoteSpriteTemplate",
  [0x083E449C] = "gPerishSongMusicNote2SpriteTemplate",
  [0x083E44DC] = "gGuardRingSpriteTemplate",
  [0x083E58E0] = "gWaterBubbleProjectileSpriteTemplate",
  [0x083E592C] = "gAuroraBeamRingSpriteTemplate",
  [0x083E595C] = "gHydroPumpOrbSpriteTemplate",
  [0x083E5974] = "gMudShotOrbSpriteTemplate",
  [0x083E598C] = "gSignalBeamRedOrbSpriteTemplate",
  [0x083E59A4] = "gSignalBeamGreenOrbSpriteTemplate",
  [0x083E59D0] = "gFlamethrowerFlameSpriteTemplate",
  [0x083E59E8] = "gPsywaveRingSpriteTemplate",
  [0x083E5A38] = "gHydroCannonChargeSpriteTemplate",
  [0x083E5A50] = "gHydroCannonBeamSpriteTemplate",
  [0x083E5A80] = "gWaterGunProjectileSpriteTemplate",
  [0x083E5A98] = "gWaterGunDropletSpriteTemplate",
  [0x083E5AB0] = "gSmallBubblePairSpriteTemplate",
  [0x083E5AC8] = "gSmallDriftingBubblesSpriteTemplate",
  [0x083E5B70] = "gWaterPulseBubbleSpriteTemplate",
  [0x083E5BA0] = "gWeatherBallWaterDownSpriteTemplate",
  [0x083E5BE0] = "gFireSpiralInwardSpriteTemplate",
  [0x083E5BF8] = "gFireSpreadSpriteTemplate",
  [0x083E5C70] = "gLargeFlameSpriteTemplate",
  [0x083E5C88] = "gLargeFlameScatterSpriteTemplate",
  [0x083E5CA0] = "gFirePlumeSpriteTemplate",
  [0x083E5D18] = "gSunlightRaySpriteTemplate",
  [0x083E5D4C] = "gEmberSpriteTemplate",
  [0x083E5D64] = "gEmberFlareSpriteTemplate",
  [0x083E5D7C] = "gBurnFlameSpriteTemplate",
  [0x083E5D94] = "gFireBlastRingSpriteTemplate",
  [0x083E5DE4] = "gFireBlastCrossSpriteTemplate",
  [0x083E5DFC] = "gFireSpiralOutwardSpriteTemplate",
  [0x083E5E14] = "gWeatherBallFireDownSpriteTemplate",
  [0x083E5E60] = "gEruptionFallingRockSpriteTemplate",
  [0x083E5EB4] = "gWillOWispOrbSpriteTemplate",
  [0x083E5EE4] = "gWillOWispFireSpriteTemplate",
  [0x083E5F38] = "gLightningSpriteTemplate",
  [0x083E5FC4] = "gSparkElectricitySpriteTemplate",
  [0x083E5FDC] = "gZapCannonBallSpriteTemplate",
  [0x083E6008] = "gZapCannonSparkSpriteTemplate",
  [0x083E6058] = "gThunderboltOrbSpriteTemplate",
  [0x083E6070] = "gSparkElectricityFlashingSpriteTemplate",
  [0x083E6088] = "gElectricitySpriteTemplate",
  [0x083E60B8] = "gThunderWaveSpriteTemplate",
  [0x083E61D4] = "gGrowingChargeOrbSpriteTemplate",
  [0x083E6204] = "gElectricPuffSpriteTemplate",
  [0x083E621C] = "gVoltTackleOrbSlideSpriteTemplate",
  [0x083E6290] = "gGrowingShockWaveOrbSpriteTemplate",
  [0x083E6348] = "gIceCrystalSpiralInwardLarge",
  [0x083E6360] = "gIceCrystalSpiralInwardSmall",
  [0x083E638C] = "gIceBeamInnerCrystalSpriteTemplate",
  [0x083E63A4] = "gIceBeamOuterCrystalSpriteTemplate",
  [0x083E63E0] = "gIceCrystalHitLargeSpriteTemplate",
  [0x083E63F8] = "gIceCrystalHitSmallSpriteTemplate",
  [0x083E6410] = "gSwirlingSnowballSpriteTemplate",
  [0x083E6428] = "gBlizzardIceCrystalSpriteTemplate",
  [0x083E6440] = "gPowderSnowSnowballSpriteTemplate",
  [0x083E647C] = "gIceGroundSpikeSpriteTemplate",
  [0x083E64A4] = "gMistCloudSpriteTemplate",
  [0x083E64BC] = "gSmogCloudSpriteTemplate",
  [0x083E64E8] = "gMistBallSpriteTemplate",
  [0x083E6514] = "gPoisonGasCloudSpriteTemplate",
  [0x083E65BC] = "gWeatherBallIceDownSpriteTemplate",
  [0x083E665C] = "gIceBallChunkSpriteTemplate",
  [0x083E6674] = "gIceBallImpactShardSpriteTemplate",
  [0x083E66E0] = "gKarateChopSpriteTemplate",
  [0x083E66F8] = "gJumpKickSpriteTemplate",
  [0x083E6710] = "gFistFootSpriteTemplate",
  [0x083E6728] = "gFistFootRandomPosSpriteTemplate",
  [0x083E6740] = "gCrossChopHandSpriteTemplate",
  [0x083E6758] = "gSlidingKickSpriteTemplate",
  [0x083E678C] = "gSpinningHandOrFootSpriteTemplate",
  [0x083E67C0] = "gMegaPunchKickSpriteTemplate",
  [0x083E67D8] = "gStompFootSpriteTemplate",
  [0x083E67F0] = "gDizzyPunchDuckSpriteTemplate",
  [0x083E6808] = "gBrickBreakWallSpriteTemplate",
  [0x083E6820] = "gBrickBreakWallShardSpriteTemplate",
  [0x083E6864] = "gSuperpowerOrbSpriteTemplate",
  [0x083E687C] = "gSuperpowerRockSpriteTemplate",
  [0x083E6894] = "gSuperpowerFireballSpriteTemplate",
  [0x083E68AC] = "gArmThrustHandSpriteTemplate",
  [0x083E6900] = "gRevengeSmallScratchSpriteTemplate",
  [0x083E6948] = "gRevengeBigScratchSpriteTemplate",
  [0x083E697C] = "gFocusPunchFistSpriteTemplate",
  [0x083E69AC] = "gToxicBubbleSpriteTemplate",
  [0x083E6A20] = "gSludgeProjectileSpriteTemplate",
  [0x083E6A38] = "gAcidPoisonBubbleSpriteTemplate",
  [0x083E6A50] = "gSludgeBombHitParticleSpriteTemplate",
  [0x083E6A84] = "gAcidPoisonDropletSpriteTemplate",
  [0x083E6AB8] = "gPoisonBubbleSpriteTemplate",
  [0x083E6AD0] = "gWaterBubbleSpriteTemplate",
  [0x083E6AE8] = "gEllipticalGustSpriteTemplate",
  [0x083E6B1C] = "gGustToTargetSpriteTemplate",
  [0x083E6B4C] = "gAirWaveCrescentSpriteTemplate",
  [0x083E6BB8] = "gFlyBallUpSpriteTemplate",
  [0x083E6BD0] = "gFlyBallAttackSpriteTemplate",
  [0x083E6C00] = "gFallingFeatherSpriteTemplate",
  [0x083E6C84] = "gWhirlwindLineSpriteTemplate",
  [0x083E6CD0] = "gBounceBallShrinkSpriteTemplate",
  [0x083E6CFC] = "gBounceBallLandSpriteTemplate",
  [0x083E6D40] = "gDiveBallSpriteTemplate",
  [0x083E6D7C] = "gDiveWaterSplashSpriteTemplate",
  [0x083E6D94] = "gSprayWaterDropletSpriteTemplate",
  [0x083E6DC4] = "gSkyAttackBirdSpriteTemplate",
  [0x083E6DF8] = "gPsychUpSpiralSpriteTemplate",
  [0x083E6E10] = "gLightScreenWallSpriteTemplate",
  [0x083E6E28] = "gReflectWallSpriteTemplate",
  [0x083E6E40] = "gMirrorCoatWallSpriteTemplate",
  [0x083E6E58] = "gBarrierWallSpriteTemplate",
  [0x083E6E70] = "gMagicCoatWallSpriteTemplate",
  [0x083E6EA4] = "gReflectSparkleSpriteTemplate",
  [0x083E6ED4] = "gSpecialScreenSparkleSpriteTemplate",
  [0x083E6EEC] = "gGoldRingSpriteTemplate",
  [0x083E6F8C] = "gBentSpoonSpriteTemplate",
  [0x083E6FF4] = "gQuestionMarkSpriteTemplate",
  [0x083E705C] = "gRedXSpriteTemplate",
  [0x083E7148] = "gLusterPurgeCircleSpriteTemplate",
  [0x083E71D0] = "gPsychoBoostOrbSpriteTemplate",
  [0x083E7224] = "gMegahornHornSpriteTemplate",
  [0x083E7278] = "gLeechLifeNeedleSpriteTemplate",
  [0x083E7290] = "gWebThreadSpriteTemplate",
  [0x083E72A8] = "gStringWrapSpriteTemplate",
  [0x083E72DC] = "gSpiderWebSpriteTemplate",
  [0x083E72F4] = "gLinearStingerSpriteTemplate",
  [0x083E730C] = "gPinMissileSpriteTemplate",
  [0x083E7324] = "gIcicleSpearSpriteTemplate",
  [0x083E7378] = "gTailGlowOrbSpriteTemplate",
  [0x083E73B4] = "gFallingRockSpriteTemplate",
  [0x083E73CC] = "gRockFragmentSpriteTemplate",
  [0x083E73E4] = "gSwirlingDirtSpriteTemplate",
  [0x083E7420] = "gWhirlpoolSpriteTemplate",
  [0x083E7438] = "gFireSpinSpriteTemplate",
  [0x083E7450] = "gFlyingSandCrescentSpriteTemplate",
  [0x083E74C0] = "gAncientPowerRockSpriteTemplate",
  [0x083E7508] = "gRockTombRockSpriteTemplate",
  [0x083E7548] = "gRockBlastRockSpriteTemplate",
  [0x083E7560] = "gRockScatterSpriteTemplate",
  [0x083E7578] = "gTwisterRockSpriteTemplate",
  [0x083E7590] = "gWeatherBallRockDownSpriteTemplate",
  [0x083E75C4] = "gConfuseRayBallBounceSpriteTemplate",
  [0x083E75DC] = "gConfuseRayBallSpiralSpriteTemplate",
  [0x083E7608] = "gShadowBallSpriteTemplate",
  [0x083E763C] = "gLickSpriteTemplate",
  [0x083E7680] = "gCurseNailSpriteTemplate",
  [0x083E7698] = "gCurseGhostSpriteTemplate",
  [0x083E76B0] = "gNightmareDevilSpriteTemplate",
  [0x083E772C] = "gOutrageFlameSpriteTemplate",
  [0x083E77A4] = "gDragonBreathFireSpriteTemplate",
  [0x083E77D8] = "gDragonRageFirePlumeSpriteTemplate",
  [0x083E7830] = "gDragonRageFireSpitSpriteTemplate",
  [0x083E7848] = "gDragonDanceOrbSpriteTemplate",
  [0x083E7860] = "gOverheatFlameSpriteTemplate",
  [0x083E7930] = "gSharpTeethSpriteTemplate",
  [0x083E7948] = "gClampJawSpriteTemplate",
  [0x083E7998] = "gTearDropSpriteTemplate",
  [0x083E79E8] = "gClawSlashSpriteTemplate",
  [0x083E7A28] = "gBonemerangSpriteTemplate",
  [0x083E7A40] = "gSpinningBoneSpriteTemplate",
  [0x083E7A58] = "gSandAttackDirtSpriteTemplate",
  [0x083E7A7C] = "gMudSlapMudSpriteTemplate",
  [0x083E7A94] = "gMudsportMudSpriteTemplate",
  [0x083E7AAC] = "gDirtPlumeSpriteTemplate",
  [0x083E7AC4] = "gDirtMoundSpriteTemplate",
  [0x083E7B0C] = "gConfusionDuckSpriteTemplate",
  [0x083E7B24] = "gSimplePaletteBlendSpriteTemplate",
  [0x083E7B3C] = "gComplexPaletteBlendSpriteTemplate",
  [0x083E7B88] = "gShakeMonOrTerrainSpriteTemplate",
  [0x083E7C08] = "gBasicHitSplatSpriteTemplate",
  [0x083E7C20] = "gHandleInvertHitSplatSpriteTemplate",
  [0x083E7C38] = "gWaterHitSplatSpriteTemplate",
  [0x083E7C50] = "gRandomPosHitSplatSpriteTemplate",
  [0x083E7C68] = "gMonEdgeHitSplatSpriteTemplate",
  [0x083E7C80] = "gCrossImpactSpriteTemplate",
  [0x083E7C98] = "gFlashingHitSplatSpriteTemplate",
  [0x083E7CB0] = "gPersistHitSplatSpriteTemplate",
  [0x083FEE00] = "gScratchSpriteTemplate",
  [0x083FEE18] = "gBlackSmokeSpriteTemplate",
  [0x083FEE30] = "gBlackBallSpriteTemplate",
  [0x083FEE5C] = "gOpeningEyeSpriteTemplate",
  [0x083FEE74] = "gWhiteHaloSpriteTemplate",
  [0x083FEE8C] = "gTealAlertSpriteTemplate",
  [0x083FEEE4] = "gMeanLookEyeSpriteTemplate",
  [0x083FEEFC] = "gSpikesSpriteTemplate",
  [0x083FEF30] = "gLeerSpriteTemplate",
  [0x083FEF70] = "gLetterZSpriteTemplate",
  [0x083FEFBC] = "gFangSpriteTemplate",
  [0x083FF00C] = "gSpotlightSpriteTemplate",
  [0x083FF024] = "gClappingHandSpriteTemplate",
  [0x083FF03C] = "gClappingHand2SpriteTemplate",
  [0x083FF068] = "gRapidSpinSpriteTemplate",
  [0x083FF0D8] = "gTriAttackTriangleSpriteTemplate",
  [0x083FF118] = "gEclipsingOrbSpriteTemplate",
  [0x083FF150] = "gBatonPassPokeballSpriteTemplate",
  [0x083FF168] = "gWishStarSpriteTemplate",
  [0x083FF1F8] = "gSwallowBlueOrbSpriteTemplate",
  [0x083FF26C] = "gGreenStarSpriteTemplate",
  [0x083FF2B0] = "gWeakFrustrationAngerMarkSpriteTemplate",
  [0x083FF324] = "gSweetScentPetalSpriteTemplate",
  [0x083FF370] = "gPainSplitProjectileSpriteTemplate",
  [0x083FF388] = "gFlatterConfettiSpriteTemplate",
  [0x083FF3A0] = "gFlatterSpotlightSpriteTemplate",
  [0x083FF3B8] = "gReversalOrbSpriteTemplate",
  [0x083FF46C] = "gYawnCloudSpriteTemplate",
  [0x083FF514] = "gSmokeBallEscapeCloudSpriteTemplate",
  [0x083FF5B4] = "gRoarNoiseLineSpriteTemplate",
  [0x083FF5E4] = "gAssistPawprintSpriteTemplate",
  [0x083FF644] = "gSmellingSaltsHandSpriteTemplate",
  [0x083FF674] = "gSmellingSaltExclamationSpriteTemplate",
  [0x083FF68C] = "gHelpingHandClapSpriteTemplate",
  [0x083FF6A4] = "gForesightMagnifyingGlassSpriteTemplate",
  [0x083FF6BC] = "gMeteorMashStarSpriteTemplate",
  [0x083FF6EC] = "gBlockXSpriteTemplate",
  [0x083FF764] = "gKnockOffStrikeSpriteTemplate",
  [0x083FF790] = "gRecycleSpriteTemplate",
  [0x0840C1EC] = "gSafariBaitSpriteTemplate",
  [0x0840C210] = "gSafariRockTemplate",
}

Versions.ANIM_CALLBACK_NAMES = {
  [0x08075D9D] = "SpriteOnMonPos",
  [0x08075DF5] = "TranslateAnimSpriteToTargetMonLocation",
  [0x08075E81] = "ThrowProjectile",
  [0x08075F0D] = "TravelDiagonally",
  [0x08076FD1] = "SpinningSparkle",
  [0x0807729D] = "WeatherBallUp",
  [0x08077351] = "WeatherBallDown",
  [0x080990AD] = "DoHorizontalLunge",
  [0x08099145] = "DoVerticalDip",
  [0x080991B5] = "SlideMonToOriginalPos",
  [0x080992E1] = "SlideMonToOffset",
  [0x08099395] = "SlideMonToOffsetAndBack",
  [0x080A22E9] = "MovePowderParticle",
  [0x080A2389] = "PowerAbsorptionOrb",
  [0x080A23D9] = "SolarBeamBigOrb",
  [0x080A2581] = "AbsorptionOrb",
  [0x080A25ED] = "HyperBeamOrb",
  [0x080A26F1] = "LeechSeed",
  [0x080A27D1] = "SporeParticle",
  [0x080A2921] = "PetalDanceBigFlower",
  [0x080A29ED] = "PetalDanceSmallFlower",
  [0x080A2AA5] = "RazorLeafParticle",
  [0x080A2B9D] = "TranslateLinearSingleSineWave",
  [0x080A2D11] = "MoveTwisterParticle",
  [0x080A2E29] = "ConstrictBinding",
  [0x080A3099] = "MimicOrb",
  [0x080A3169] = "IngrainRoot",
  [0x080A31ED] = "FrenzyPlantRoot",
  [0x080A3335] = "IngrainOrb",
  [0x080A3519] = "Present",
  [0x080A35F5] = "KnockOffItem",
  [0x080A3671] = "PresentHealParticle",
  [0x080A36B5] = "ItemSteal",
  [0x080A37BD] = "TrickBag",
  [0x080A4041] = "FlyingParticle",
  [0x080A4299] = "NeedleArmSpike",
  [0x080A4451] = "WhipHit",
  [0x080A44E1] = "CuttingSlice",
  [0x080A4589] = "AirCutterSlice",
  [0x080A48F1] = "Protect",
  [0x080A4ACD] = "MilkBottle",
  [0x080A4D0D] = "GrantingStars",
  [0x080A4D5D] = "SparklingStars",
  [0x080A4EF5] = "SleepLetterZ",
  [0x080A4FAD] = "LockOnTarget",
  [0x080A5299] = "LockOnMoveTarget",
  [0x080A5341] = "BowMon",
  [0x080A5941] = "SlashSlice",
  [0x080A59A9] = "FalseSwipeSlice",
  [0x080A59F1] = "FalseSwipePositionedSlice",
  [0x080A5AD9] = "EndureEnergy",
  [0x080A5B7D] = "SharpenSphere",
  [0x080A5C69] = "Conversion",
  [0x080A5D4D] = "Conversion2",
  [0x080A5EE1] = "Moon",
  [0x080A5F41] = "MoonlightSparkle",
  [0x080A6245] = "HornHit",
  [0x080A65CD] = "SuperFang",
  [0x080A66D5] = "WavyMusicNotes",
  [0x080A68B1] = "FlyingMusicNotes",
  [0x080A69B9] = "BellyDrumHand",
  [0x080A6A29] = "SlowFlyingMusicNotes",
  [0x080A6B65] = "ThoughtBubble",
  [0x080A6C09] = "MetronomeFinger",
  [0x080A6C85] = "FollowMeFinger",
  [0x080A6D91] = "TauntFinger",
  [0x080A71D9] = "KinesisZapEnergy",
  [0x080A727D] = "SwordsDanceBlade",
  [0x080A72C9] = "SonicBoomProjectile",
  [0x080A7A89] = "CoinThrow",
  [0x080A7B3D] = "FallingCoin",
  [0x080A7BC5] = "BulletSeed",
  [0x080A7D05] = "RazorWindTornado",
  [0x080A7D65] = "ViceGripPincer",
  [0x080A7E15] = "GuillotinePincer",
  [0x080A851D] = "BreathPuff",
  [0x080A85AD] = "AngerMark",
  [0x080A8A1D] = "Pencil",
  [0x080A8BC5] = "BlendThinRing",
  [0x080A8CA5] = "HyperVoiceRing",
  [0x080A8EE9] = "UproarRing",
  [0x080A8F39] = "SoftBoiledEgg",
  [0x080A97E9] = "HealBellMusicNote",
  [0x080A9861] = "MagentaHeart",
  [0x080A9B41] = "RedHeartProjectile",
  [0x080A9BC5] = "ParticleBurst",
  [0x080A9C4D] = "RedHeartRising",
  [0x080AA175] = "OrbitFast",
  [0x080AA2B1] = "OrbitScatter",
  [0x080AA37D] = "SpitUpOrb",
  [0x080AA3F1] = "EyeSparkle",
  [0x080AA409] = "Angel",
  [0x080AA509] = "PinkHeart",
  [0x080AA58D] = "Devil",
  [0x080AA6B9] = "FurySwipes",
  [0x080AA709] = "MovementWaves",
  [0x080AA839] = "JaggedMusicNote",
  [0x080AA939] = "PerishSongMusicNote2",
  [0x080AA999] = "PerishSongMusicNote",
  [0x080AAAE5] = "GuardRing",
  [0x080AAC99] = "WaterBubbleProjectile",
  [0x080AAE85] = "AuroraBeamRings",
  [0x080AB025] = "ToTargetInSinWave",
  [0x080AB169] = "HydroCannonCharge",
  [0x080AB1F9] = "HydroCannonBeam",
  [0x080AB2CD] = "WaterGunDroplet",
  [0x080AB309] = "SmallBubblePair",
  [0x080ABA79] = "SmallDriftingBubbles",
  [0x080AC625] = "WaterPulseBubble",
  [0x080AC6D9] = "WaterPulseRing",
  [0x080AC90D] = "FireSpiralInward",
  [0x080AC94D] = "FireSpread",
  [0x080AC991] = "FirePlume",
  [0x080ACA01] = "LargeFlame",
  [0x080ACBB1] = "Sunlight",
  [0x080ACBDD] = "EmberFlare",
  [0x080ACC45] = "BurnFlame",
  [0x080ACC61] = "FireRing",
  [0x080ACDA9] = "FireCross",
  [0x080ACDE9] = "FireSpiralOutward",
  [0x080AD455] = "EruptionFallingRock",
  [0x080AD541] = "WillOWispOrb",
  [0x080AD6F5] = "WillOWispFire",
  [0x080ADBED] = "Lightning",
  [0x080ADD4D] = "SparkElectricity",
  [0x080ADEB1] = "ZapCannonSpark",
  [0x080AE001] = "ThunderboltOrb",
  [0x080AE06D] = "SparkElectricityFlashing",
  [0x080AE1A1] = "Electricity",
  [0x080AE471] = "ThunderWave",
  [0x080AE71D] = "GrowingChargeOrb",
  [0x080AE775] = "ElectricPuff",
  [0x080AE7DD] = "VoltTackleOrbSlide",
  [0x080AEC81] = "GrowingShockWaveOrb",
  [0x080AF2F1] = "IcePunchSwirlingParticle",
  [0x080AF331] = "IceBeamParticle",
  [0x080AF3B9] = "IceEffectParticle",
  [0x080AF469] = "SwirlingSnowball",
  [0x080AF6D9] = "MoveParticleBeyondTarget",
  [0x080AF88D] = "WaveFromCenterOfTarget",
  [0x080AF915] = "InitSwirlingFogAnim",
  [0x080AFD4D] = "ThrowMistBall",
  [0x080AFFD5] = "InitPoisonGasCloudAnim",
  [0x080B06FD] = "InitIceBallAnim",
  [0x080B07C1] = "InitIceBallParticle",
  [0x080B08DD] = "SlideHandOrFootToTarget",
  [0x080B0929] = "JumpKick",
  [0x080B0955] = "BasicFistOrFoot",
  [0x080B09A5] = "FistOrFootRandomPos",
  [0x080B0B81] = "CrossChopHand",
  [0x080B0C29] = "SlidingKick",
  [0x080B0CED] = "SpinningKickOrPunch",
  [0x080B0D59] = "StompFoot",
  [0x080B0DF1] = "DizzyPunchDuck",
  [0x080B0E81] = "BrickBreakWall",
  [0x080B0F69] = "BrickBreakWallShard",
  [0x080B107D] = "SuperpowerOrb",
  [0x080B1189] = "SuperpowerRock",
  [0x080B12E9] = "SuperpowerFireball",
  [0x080B13F9] = "ArmThrustHit",
  [0x080B1485] = "RevengeScratch",
  [0x080B14F1] = "FocusPunchFist",
  [0x080B1621] = "SludgeProjectile",
  [0x080B16A1] = "AcidPoisonBubble",
  [0x080B1745] = "SludgeBombHitParticle",
  [0x080B17C5] = "AcidPoisonDroplet",
  [0x080B1839] = "BubbleEffect",
  [0x080B18E5] = "EllipticalGust",
  [0x080B1A1D] = "GustToTarget",
  [0x080B1AB9] = "AirWaveCrescent",
  [0x080B1BB1] = "FlyBallUp",
  [0x080B1C3D] = "FlyBallAttack",
  [0x080B1D89] = "FallingFeather",
  [0x080B2781] = "WhirlwindLine",
  [0x080B2915] = "BounceBallShrink",
  [0x080B2975] = "BounceBallLand",
  [0x080B2A09] = "DiveBall",
  [0x080B2AF5] = "DiveWaterSplash",
  [0x080B2BD9] = "SprayWaterDroplet",
  [0x080B2D65] = "SkyAttackBird",
  [0x080B2ECD] = "DefensiveWall",
  [0x080B31D1] = "WallSparkle",
  [0x080B3279] = "BentSpoon",
  [0x080B32F5] = "QuestionMark",
  [0x080B37ED] = "RedX",
  [0x080B3E85] = "PsychoBoost",
  [0x080B3FAD] = "MegahornHorn",
  [0x080B407D] = "LeechLifeNeedle",
  [0x080B4129] = "TranslateWebThread",
  [0x080B41F9] = "StringWrap",
  [0x080B42C1] = "SpiderWeb",
  [0x080B4365] = "TranslateStinger",
  [0x080B4495] = "MissileArc",
  [0x080B45D9] = "TailGlowOrb",
  [0x080B4635] = "FallingRock",
  [0x080B46F9] = "RockFragment",
  [0x080B477D] = "ParticleInVortex",
  [0x080B4AA9] = "FlyingSandCrescent",
  [0x080B4B8D] = "RaiseSprite",
  [0x080B4FE5] = "RockTomb",
  [0x080B5075] = "RockBlastRock",
  [0x080B50A1] = "RockScatter",
  [0x080B5269] = "ConfuseRayBallBounce",
  [0x080B5451] = "ConfuseRayBallSpiral",
  [0x080B563D] = "ShadowBall",
  [0x080B57F9] = "Lick",
  [0x080B664D] = "CurseNail",
  [0x080B67D5] = "GhostStatusSprite",
  [0x080B725D] = "OutrageFlame",
  [0x080B73AD] = "DragonRageFirePlume",
  [0x080B741D] = "DragonFireToTarget",
  [0x080B7449] = "DragonDanceOrb",
  [0x080B77E5] = "OverheatFlame",
  [0x080B7BD5] = "Bite",
  [0x080B7C89] = "TearDrop",
  [0x080B86B1] = "ClawSlash",
  [0x080B8B6D] = "BonemerangProjectile",
  [0x080B8C55] = "BoneHitProjectile",
  [0x080B8CC9] = "DirtScatter",
  [0x080B8D59] = "MudSportDirt",
  [0x080B9379] = "DirtPlumeParticle",
  [0x080B941D] = "DigDirtMound",
  [0x080B9905] = "ConfusionDuck",
  [0x080B99D5] = "SimplePaletteBlend",
  [0x080B9A7D] = "ComplexPaletteBlend",
  [0x080BA27D] = "ShakeMonOrBattleTerrain",
  [0x080BA561] = "HitSplatBasic",
  [0x080BA5A9] = "HitSplatPersistent",
  [0x080BA5F9] = "HitSplatHandleInvert",
  [0x080BA631] = "HitSplatRandom",
  [0x080BA6C9] = "HitSplatOnMonEdge",
  [0x080BA739] = "CrossImpact",
  [0x080BA781] = "FlashingHitSplat",
  [0x080DE2C1] = "BlackSmoke",
  [0x080DE39D] = "WhiteHalo",
  [0x080DE441] = "TealAlert",
  [0x080DE4DD] = "MeanLookEye",
  [0x080DE8B1] = "Spikes",
  [0x080DE99D] = "Leer",
  [0x080DE9D9] = "LetterZ",
  [0x080DEA99] = "Fang",
  [0x080DEB21] = "Spotlight",
  [0x080DEC91] = "ClappingHand",
  [0x080DEDBD] = "ClappingHand2",
  [0x080DEEBD] = "RapidSpin",
  [0x080DF469] = "TriAttackTriangle",
  [0x080DF581] = "BatonPassPokeball",
  [0x080DF689] = "WishStar",
  [0x080DF8F9] = "SwallowBlueOrb",
  [0x080DFEDD] = "GreenStar",
  [0x080E04E1] = "WeakFrustrationAngerMark",
  [0x080E0791] = "SweetScentPetal",
  [0x080E0A3D] = "PainSplitProjectile",
  [0x080E0C69] = "FlatterConfetti",
  [0x080E0D75] = "FlatterSpotlight",
  [0x080E0E95] = "ReversalOrb",
  [0x080E186D] = "YawnCloud",
  [0x080E1929] = "SmokeBallEscapeCloud",
  [0x080E20D5] = "RoarNoiseLine",
  [0x080E24E1] = "AssistPawprint",
  [0x080E2775] = "SmellingSaltsHand",
  [0x080E29F1] = "SmellingSaltExclamation",
  [0x080E2AB1] = "HelpingHandClap",
  [0x080E2F15] = "ForesightMagnifyingGlass",
  [0x080E321D] = "MeteorMashStar",
  [0x080E34D1] = "BlockX",
  [0x080E4335] = "KnockOffStrike",
  [0x080E43A5] = "Recycle",
  [0x080F1B3D] = "SpriteCB_SafariBaitOrRock_Init",
}

Versions.ANIM_TASK_NAMES = {
  [0x08076049] = "AlphaFadeIn",
  [0x0807616D] = "BlendMonInAndOut",
  [0x08076289] = "BlendPalInAndOutByTag",
  [0x080766B9] = "GetFrustrationPowerLevel",
  [0x08077031] = "AttackerPunchWithTrace",
  [0x080783FD] = "FrozenIceCube",
  [0x08078695] = "StatsChange",
  [0x080989F9] = "ShakeMon",
  [0x08098B1D] = "ShakeMon2",
  [0x08098CD1] = "ShakeMonInPlace",
  [0x08098E91] = "ShakeAndSinkMon",
  [0x08098F85] = "TranslateMonElliptical",
  [0x0809907D] = "TranslateMonEllipticalRespectSide",
  [0x0809949D] = "WindUpLunge",
  [0x080995FD] = "SlideOffScreen",
  [0x08099705] = "SwayMon",
  [0x080998B1] = "ScaleMonAndRestore",
  [0x08099981] = "RotateMonSpriteToSide",
  [0x08099A79] = "RotateMonToSideAndRestore",
  [0x08099BD5] = "ShakeTargetBasedOnMovePowerOrDmg",
  [0x080A2501] = "CreateSmallSolarBeamOrbs",
  [0x080A28C5] = "SporeDoubleBattle",
  [0x080A2F0D] = "ShrinkTargetCopy",
  [0x080A39C1] = "LeafBlade",
  [0x080A41C5] = "CycleMagicalLeafPal",
  [0x080A5695] = "SkullBashPosition",
  [0x080A5CD5] = "ConversionAlphaBlend",
  [0x080A5DE1] = "Conversion2AlphaBlend",
  [0x080A5FC1] = "MoonlightEndFade",
  [0x080A63B5] = "DoubleTeam",
  [0x080A65E9] = "MusicNotesRainbowBlend",
  [0x080A66A1] = "MusicNotesClearRainbowBlend",
  [0x080A70A1] = "Withdraw",
  [0x080A76F1] = "AirCutterProjectile",
  [0x080A7FB1] = "GrowAndGrayscale",
  [0x080A8075] = "Minimize",
  [0x080A8339] = "Splash",
  [0x080A84B5] = "GrowAndShrink",
  [0x080A8639] = "ThrashMoveMonHorizontal",
  [0x080A86A5] = "ThrashMoveMonVertical",
  [0x080A8875] = "SketchDrawMon",
  [0x080A917D] = "AttackerStretchAndDisappear",
  [0x080A9211] = "ExtremeSpeedImpact",
  [0x080A939D] = "ExtremeSpeedMonReappear",
  [0x080A94AD] = "SpeedDust",
  [0x080A96B5] = "LoadMusicNotesPals",
  [0x080A9761] = "FreeMusicNotesPals",
  [0x080A98B1] = "FakeOut",
  [0x080A9A21] = "StretchTargetUp",
  [0x080A9AB1] = "StretchAttackerUp",
  [0x080A9CE9] = "HeartsBackground",
  [0x080A9F11] = "ScaryFace",
  [0x080AA7C9] = "UproarDistortion",
  [0x080AAB7D] = "IsFuryCutterHitRight",
  [0x080AABA1] = "GetFuryCutterHitCount",
  [0x080AABC1] = "CreateRaindrops",
  [0x080AAF61] = "RotateAuroraRingColors",
  [0x080AB101] = "StartSinAnimTimer",
  [0x080AB38D] = "CreateSurfWave",
  [0x080ABB29] = "WaterSpoutLaunch",
  [0x080AC00D] = "WaterSpoutRain",
  [0x080AC329] = "WaterSport",
  [0x080ACEA5] = "EruptionLaunchRocks",
  [0x080AD801] = "MoveHeatWaveTargets",
  [0x080ADAA5] = "BlendBackground",
  [0x080ADAD9] = "ShakeTargetInPattern",
  [0x080AE221] = "ElectricBolt",
  [0x080AE541] = "ElectricChargingParticles",
  [0x080AE8A1] = "VoltTackleAttackerReappear",
  [0x080AEA11] = "VoltTackleBolt",
  [0x080AECE1] = "ShockWaveProgressingBolt",
  [0x080AEFA1] = "ShockWaveLightning",
  [0x080AFAE5] = "HazeScrollingFog",
  [0x080AFD81] = "MistBallFog",
  [0x080B038D] = "Hail",
  [0x080B0871] = "GetRolloutCounter",
  [0x080B1531] = "MoveSkyUppercutBg",
  [0x080B194D] = "AnimateGustTornadoPalette",
  [0x080B2869] = "DrillPeckHitSplats",
  [0x080B3419] = "MeditateStretchAttacker",
  [0x080B3481] = "Teleport",
  [0x080B3585] = "ImprisonOrbs",
  [0x080B3835] = "SkillSwap",
  [0x080B3A59] = "ExtrasensoryDistortion",
  [0x080B3C79] = "TransparentCloneGrowAndShrink",
  [0x080B4811] = "LoadSandstormBackground",
  [0x080B4BD1] = "Rollout",
  [0x080B5149] = "GetSeismicTossDamageLevel",
  [0x080B5189] = "MoveSeismicTossBg",
  [0x080B51ED] = "SeismicTossBgAccelerateDownAtEnd",
  [0x080B54E9] = "NightShadeClone",
  [0x080B58AD] = "NightmareClone",
  [0x080B5AAD] = "SpiteTargetShadow",
  [0x080B6021] = "DestinyBondWhiteShadow",
  [0x080B63B5] = "CurseStretchingBlackBg",
  [0x080B68C9] = "GrudgeFlames",
  [0x080B6BBD] = "GhostGetOut",
  [0x080B75E1] = "DragonDanceWaver",
  [0x080B78E1] = "AttackerFadeToInvisible",
  [0x080B79DD] = "AttackerFadeFromInvisible",
  [0x080B7A81] = "InitAttackerFadeFromInvisible",
  [0x080B7DA5] = "MoveAttackerMementoShadow",
  [0x080B8071] = "MoveTargetMementoShadow",
  [0x080B85B9] = "InitMementoShadow",
  [0x080B8665] = "MementoHandleBg",
  [0x080B86ED] = "MetallicShine",
  [0x080B8A75] = "SetGrayscaleOrOriginalPal",
  [0x080B8B39] = "GetIsDoomDesireHitTurn",
  [0x080B8E95] = "DigDownMovement",
  [0x080B90ED] = "DigUpMovement",
  [0x080B94B5] = "HorizontalShake",
  [0x080B97D9] = "IsPowerOver99",
  [0x080B9801] = "PositionFissureBgOnBattler",
  [0x080B9BDD] = "BlendColorCycle",
  [0x080B9CE5] = "BlendColorCycleExclude",
  [0x080B9E59] = "BlendColorCycleByTag",
  [0x080B9F6D] = "FlashAnimTagWithColor",
  [0x080BA0E9] = "InvertScreenColor",
  [0x080BA47D] = "ShakeBattleTerrain",
  [0x080BA7F9] = "BlendBattleAnimPal",
  [0x080BA83D] = "BlendBattleAnimPalExclude",
  [0x080BA935] = "SetCamouflageBlend",
  [0x080BAA21] = "BlendParticle",
  [0x080BAB39] = "HardwarePaletteFade",
  [0x080BAB99] = "TraceMonBlended",
  [0x080BACED] = "DrawFallingWhiteLinesOnAttacker",
  [0x080BB661] = "Flash",
  [0x080BB7DD] = "BlendNonAttackerPalettes",
  [0x080BB82D] = "StartSlidingBg",
  [0x080BB921] = "GetAttackerSide",
  [0x080BB94D] = "GetTargetSide",
  [0x080BB979] = "GetTargetIsAttackerPartner",
  [0x080BB9B1] = "SetAllNonAttackersInvisiblity",
  [0x080BBDF1] = "GetBattleTerrain",
  [0x080BBE11] = "AllocBackupPalBuffer",
  [0x080BBE3D] = "FreeBackupPalBuffer",
  [0x080BBE6D] = "CopyPalUnfadedToBackup",
  [0x080BBF09] = "CopyPalUnfadedFromBackup",
  [0x080BBFA5] = "CopyPalFadedToUnfaded",
  [0x080BC02D] = "IsContest",
  [0x080BC061] = "SetAnimAttackerAndTargetForEffectTgt",
  [0x080BC091] = "IsTargetSameSide",
  [0x080BC0DD] = "SetAnimTargetToBattlerTarget",
  [0x080BC0FD] = "SetAnimAttackerAndTargetForEffectAtk",
  [0x080BC12D] = "SetAttackerInvisibleWaitForSignal",
  [0x080DCE11] = "SoundTask_FireBlast",
  [0x080DCF39] = "SoundTask_LoopSEAdjustPanning",
  [0x080DD06D] = "SoundTask_PlayCryHighPitch",
  [0x080DD149] = "SoundTask_PlayDoubleCry",
  [0x080DD2F5] = "SoundTask_WaitForCry",
  [0x080DD335] = "SoundTask_PlayCryWithEcho",
  [0x080DD3DD] = "SoundTask_PlaySE1WithPanning",
  [0x080DD411] = "SoundTask_PlaySE2WithPanning",
  [0x080DD445] = "SoundTask_AdjustPanningVar",
  [0x080DE34D] = "SmokescreenImpact",
  [0x080DE6F1] = "SetPsychicBackground",
  [0x080DE7B5] = "FadeScreenToWhite",
  [0x080DEAB5] = "IsTargetPlayerSide",
  [0x080DEAF1] = "IsHealingMove",
  [0x080DEDD9] = "CreateSpotlight",
  [0x080DEE79] = "RemoveSpotlight",
  [0x080DEF9D] = "RapinSpinMonElevation",
  [0x080DF1DD] = "TormentAttacker",
  [0x080DF525] = "DefenseCurlDeformMon",
  [0x080DF849] = "StockpileDeformMon",
  [0x080DF8A1] = "SpitUpDeformMon",
  [0x080DF965] = "SwallowDeformMon",
  [0x080DF9BD] = "TransformMon",
  [0x080DFBE5] = "IsMonInvisible",
  [0x080DFC25] = "CastformGfxChange",
  [0x080DFC51] = "MorningSunLightBeam",
  [0x080E017D] = "DoomDesireLightBeam",
  [0x080E0489] = "StrongFrustrationGrowAndShrink",
  [0x080E0559] = "RockMonBackAndForth",
  [0x080E0851] = "FlailMovement",
  [0x080E0B01] = "PainSplitMovement",
  [0x080E0FB9] = "RolePlaySilhouette",
  [0x080E12F9] = "AcidArmor",
  [0x080E1705] = "DeepInhale",
  [0x080E1C49] = "SlideMonForFocusBand",
  [0x080E1D5D] = "SquishAndSweatDroplets",
  [0x080E1FC5] = "FacadeColorBlend",
  [0x080E2085] = "StatusClearedEffect",
  [0x080E21CD] = "GlareEyeDots",
  [0x080E2519] = "BarrageBall",
  [0x080E28DD] = "SmellingSaltsSquish",
  [0x080E2CE5] = "HelpingHandAttackerMovement",
  [0x080E3295] = "MonToSubstitute",
  [0x080E3665] = "OdorSleuthMovement",
  [0x080E38D9] = "GetReturnPowerLevel",
  [0x080E392D] = "SnatchOpposingMonMove",
  [0x080E3FC1] = "SnatchPartnerMove",
  [0x080E4161] = "TeeterDanceMovement",
  [0x080E44ED] = "GetWeather",
  [0x080E4541] = "SlackOffSquish",
  [0x080EF0B5] = "LoadHealthboxPalsForLevelUp",
  [0x080EF181] = "FreeHealthboxPalsForLevelUp",
  [0x080EF1A1] = "FlashHealthboxOnLevelUp",
  [0x080EF299] = "SwitchOutShrinkMon",
  [0x080EF345] = "SwitchOutBallEffect",
  [0x080EF491] = "LoadBallGfx",
  [0x080EF4B9] = "FreeBallGfx",
  [0x080EF4E1] = "IsBallBlockedByTrainerOrDodged",
  [0x080EF5AD] = "ThrowBall",
  [0x080EF6D5] = "ThrowBallSpecial",
  [0x080F1421] = "SwapMonSpriteToFromSubstitute",
  [0x080F15C9] = "SubstituteFadeToInvisible",
  [0x080F16CD] = "IsAttackerBehindSubstitute",
  [0x080F1701] = "SetTargetToEffectBattler",
  [0x080F1AE1] = "LoadBaitGfx",
  [0x080F1B15] = "FreeBaitGfx",
  [0x080F1C8D] = "SafariOrGhost_DecideAnimSides",
  [0x080F1CE5] = "SafariGetReaction",
  [0x080F1D15] = "GetTrappedMoveAnimId",
  [0x080F1D7D] = "GetBattlersFromArg",
}

Versions.BATTLE_ANIM_STATUS_NAMES = {
  [0] = "STATUS_PSN",
  [1] = "STATUS_CONFUSION",
  [2] = "STATUS_BRN",
  [3] = "STATUS_INFATUATION",
  [4] = "STATUS_SLP",
  [5] = "STATUS_PRZ",
  [6] = "STATUS_FRZ",
  [7] = "STATUS_CURSED",
  [8] = "STATUS_NIGHTMARE",
}

Versions.BATTLE_ANIM_GENERAL_NAMES = {
  [0] = "CASTFORM_CHANGE",
  [1] = "STATS_CHANGE",
  [2] = "SUBSTITUTE_FADE",
  [3] = "SUBSTITUTE_APPEAR",
  [4] = "BAIT_THROW",
  [5] = "ITEM_KNOCKOFF",
  [6] = "TURN_TRAP",
  [7] = "HELD_ITEM_EFFECT",
  [8] = "SMOKEBALL_ESCAPE",
  [9] = "FOCUS_BAND",
  [10] = "RAIN_CONTINUES",
  [11] = "SUN_CONTINUES",
  [12] = "SANDSTORM_CONTINUES",
  [13] = "HAIL_CONTINUES",
  [14] = "LEECH_SEED_DRAIN",
  [15] = "MON_HIT",
  [16] = "ITEM_STEAL",
  [17] = "SNATCH_MOVE",
  [18] = "FUTURE_SIGHT_HIT",
  [19] = "DOOM_DESIRE_HIT",
  [20] = "FOCUS_PUNCH_SETUP",
  [21] = "INGRAIN_HEAL",
  [22] = "WISH_HEAL",
  [23] = "MON_SCARED",
  [24] = "GHOST_GET_OUT",
  [25] = "SILPH_SCOPED",
  [26] = "ROCK_THROW",
  [27] = "SAFARI_REACTION",
}

Versions.BATTLE_ANIM_SPECIAL_NAMES = {
  [0] = "LVL_UP",
  [1] = "SWITCH_OUT_PLAYER_MON",
  [2] = "SWITCH_OUT_OPPONENT_MON",
  [3] = "BALL_THROW",
  [4] = "BALL_THROW_WITH_TRAINER",
  [5] = "SUBSTITUTE_TO_MON",
  [6] = "MON_TO_SUBSTITUTE",
}

-- Wild encounters (FireRed USA 1.0): gWildMonHeaders[] — 20-byte entries,
-- terminated by mapGroup/mapNum = 0xFF. Verified via Route 1 land fingerprint.
Versions.WILD_MON_HEADERS = 0x3C9CB8
Versions.WILD_MON_HEADER_SIZE = 20
Versions.LAND_WILD_COUNT = 12
Versions.WATER_WILD_COUNT = 5
Versions.ROCK_WILD_COUNT = 5
Versions.FISH_WILD_COUNT = 10

-- Field-effect graphics & palettes (FireRed USA 1.0)
Versions.FIELD_EFFECT_TALL_GRASS = 0x39A008      -- gFieldEffectObjectPic_TallGrass
Versions.FIELD_EFFECT_PAL_GENERAL_1 = 0x398FC8 -- gFieldEffectObjectPalette1
Versions.FIELD_EFFECT_PAL_GENERAL_0 = 0x398FA8 -- gFieldEffectObjectPalette0
Versions.FIELD_EFFECT_PAL_PLAYER = 0x35B968    -- gObjectEventPal_Player (surf blob, etc.)

Versions.FIELD_EFFECTS = {
  tall_grass   = { pic = 0x39A008, pal = 0x398FC8, w = 16, h = 16, frames = 5 },
  cut_grass    = { pic = 0x398648, pal = 0x398FC8, w = 8,  h = 8,  frames = 1 },
  rock_smash   = { pic = 0x398928, pal = 0x398FA8, w = 16, h = 16, frames = 4 },
  surf_blob    = { pic = 0x396B08, pal = 0x35B968, w = 32, h = 32, frames = 6 },
  fly_bird     = { pic = 0x398048, pal = 0x398FA8, w = 32, h = 32, frames = 4 },
  ripple       = { pic = 0x398BA8, pal = 0x398FA8, w = 16, h = 16, frames = 8 },
  emoticons    = { pic = 0x3C6AC8, pal = 0x35B968, w = 16, h = 16, frames = 15 },
  -- pokefirered/src/field_effect.c:326
  pokeball_glow = {
    pic = 0x3CAF90, pal = 0x3CAFB0, w = 8, h = 8, frames = 1, indexed = true,
  },
  -- pokefirered/src/field_effect.c:336
  pokemoncenter_monitor = {
    pic = 0x3CAFD0, pal = 0x3CAFB0, w = 32, h = 16, frames = 4,
  },
}

-- Battle interface chrome (FireRed USA 1.0 file offsets; LZ unless noted).
-- Healthbox pals are uncompressed INCBIN_U16 (pret graphics.c); matched to healthbox.pal.
-- Terrain grass: sBattleTerrainPalette/Tiles/Tilemap_Grass (battle_bg.c).
Versions.BATTLE_UI = {
  textbox_gfx = 0xD00000,           -- gBattleInterface_Textbox_Gfx LZ → 8192
  textbox_pal = 0xD004D8,           -- LZ → 64 (2×16 colors)
  textbox_tilemap = 0xD0051C,       -- LZ → 4096 (32×64 tiles)
  healthbox_elements = 0xD11BC4,    -- uncompressed 320×24 4bpp
  healthbox_player = 0xD1F340,      -- gHealthboxSinglesPlayerGfx LZ → 4096
  healthbox_enemy = 0xD1F604,       -- gHealthboxSinglesOpponentGfx LZ → 2048
  healthbox_doubles_player = 0xD1F794,   -- gHealthboxDoublesPlayerGfx LZ → 2048
  healthbox_doubles_opponent = 0xD1F928, -- gHealthboxDoublesOpponentGfx LZ → 2048
  healthbox_pal = 0xD11B84,         -- uncompressed 32 (gBattleInterface_Healthbox_Pal)
  healthbar_pal = 0xD11BA4,         -- uncompressed 32 (gBattleInterface_Healthbar_Pal)
  font_bold_glyphs = 0x22FC48,      -- uncompressed 8192 2bpp (sFontBoldJapaneseGlyphs, src/text.c:384)
  terrain_grass = {
    pal = 0x248400,                 -- LZ → 96 (3 banks)
    tiles = 0x24844C,               -- LZ → 3136
    tilemap = 0x2489A8,             -- LZ → 4096 (32×32)
  },
  -- Indoor / lab (MAP_TYPE_INDOOR → BATTLE_TERRAIN_BUILDING)
  terrain_building = {
    pal = 0x24DDF0,                 -- LZ → 96
    tiles = 0x24DE34,               -- LZ → 2464
    tilemap = 0x24E16C,             -- LZ → 4096
  },
  party_summary_bar = 0xE7BB04,   -- gBattleInterface_PartySummaryBar_Gfx LZ → 512
}

Versions.BALL_OPEN = {
  particle_sheets = 0x40BF48,     -- pokefirered/src/battle_anim_special.c:117
  particle_palettes = 0x40BFA8,   -- pokefirered/src/battle_anim_special.c:133
  fade_colors = 0x40C1C4,         -- pokefirered/src/battle_anim_special.c:345
  sine_table = 0x25E074,          -- pokefirered/src/trig.c:4
}

-- Battle field→battle transitions (FireRed USA 1.0; uncompressed INCBINs in
-- battle_transition.c). Fingerprinted vs pret graphics/battle_transitions/*.
Versions.BATTLE_TRANSITION = {
  big_pokeball_gfx = 0x3F87A0,       -- 32×88 4bpp (44 tiles)
  sliding_pokeball_bin = 0x3F8D20,   -- 64 B paint tile
  sliding_pokeball_gfx = 0x3F8D60,   -- 32×32 4bpp
  mugshot_banner_gfx = 0x3F8F60,     -- 120×8 4bpp
  -- unused_brendan / unused_lass at 0x3F9140 / 0x3F9940 (not extracted)
  grid_square_gfx = 0x3FA140,        -- 8×120 4bpp (15 shrink frames)
  sliding_pokeball_pal = 0x3FA638,   -- 16 colors (shared big/trail)
  mugshot_pals = {
    lorelei = 0x3FA660,
    bruno = 0x3FA680,
    agatha = 0x3FA6A0,
    lance = 0x3FA6C0,
    blue = 0x3FA6E0,
    red = 0x3FA700,    -- player male strip colors
    green = 0x3FA720,  -- player female strip colors
  },
  big_pokeball_tilemap = 0x3FA784,   -- 20×30 u16
  vsbar_tilemap = 0x3FAC34,          -- 20×32 u16
}

Versions.MON_BACK_PIC_TABLE = 0x23654C -- gMonBackPicTable
Versions.GHOST_PALETTE = 0xE93B14 -- pokefirered/src/graphics.c:1135
Versions.GHOST_FRONT_PIC = 0xE93B38 -- pokefirered/src/graphics.c:1136

-- Trainer graphics / tables (FireRed USA 1.0 file offsets).
Versions.TRAINER_FRONT_PIC_TABLE = 0x23957C
Versions.TRAINER_FRONT_PIC_PAL_TABLE = 0x239A1C
Versions.TRAINER_BACK_PIC_TABLE = 0x239FA4
Versions.TRAINER_BACK_PIC_PAL_TABLE = 0x239FD4
Versions.TRAINERS_TABLE = 0x23EAC8
Versions.TRAINER_STRIDE = 0x28
Versions.TRAINER_CLASS_NAMES = 0x23E558
Versions.TRAINER_CLASS_NAME_STRIDE = 13
Versions.TRAINER_CLASS_COUNT = 107
Versions.TRAINER_PIC_COUNT = 148
Versions.TRAINERS_COUNT = 743 -- pret NUM_TRAINERS

-- Party menu chrome (LZ-compressed; FireRed USA 1.0).
Versions.PARTY_MENU_BG_GFX = 0xE82700       -- gPartyMenuBg_Gfx
Versions.PARTY_MENU_BG_PAL = 0xE829C8       -- gPartyMenuBg_Pal
Versions.PARTY_MENU_BG_TILEMAP = 0xE82AB0   -- gPartyMenuBg_Tilemap
Versions.PARTY_MENU_BALL_GFX = 0xE82BE8     -- gPartyMenuPokeball_Gfx
Versions.PARTY_MENU_BALL_PAL = 0xE82E7C     -- gPartyMenuPokeball_Pal

-- Pokémon Summary Screen (LZ-compressed & raw; FireRed USA 1.0).
Versions.SUMMARY_BG_GFX = 0xE9A460               -- gSummaryScreen_Gfx (LZ 4bpp, 16384 bytes)
Versions.SUMMARY_BG_PAL = 0xE9B310               -- gSummaryScreen_Pal (7 banks, 224 bytes)
Versions.SUMMARY_EXP_BAR_GFX = 0xE9B3F0          -- gSummaryExpBar_Gfx (LZ 4bpp, 384 bytes)
Versions.SUMMARY_HP_BAR_GFX = 0xE9B4B8           -- gSummaryHpBar_Gfx (LZ 4bpp, 384 bytes)
Versions.SUMMARY_HP_EXP_PAL = 0xE9B578           -- gSummaryBar_Pal (32 bytes)
Versions.SUMMARY_PAGE_INFO_TILEMAP = 0xE9B598    -- gSummaryPage_Info_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_SKILLS_TILEMAP = 0xE9B750  -- gSummaryPage_Skills_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_MOVES_TILEMAP = 0xE9B950   -- gSummaryPage_Moves_Tilemap (LZ 32x32, 2048 bytes)
Versions.SUMMARY_PAGE_MOVES_INFO_TILEMAP = 0xE9BA9C -- gSummaryPage_MovesInfo_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_EGG_TILEMAP = 0xE9BBCC     -- gSummaryPage_Egg_Tilemap (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_MOVES_INFO_BASE_TILEMAP = 0x463B88 -- sBgTilemap_MovesInfoPage (LZ 32x20, 1280 bytes)
Versions.SUMMARY_PAGE_MOVES_BASE_TILEMAP = 0x463C80      -- sBgTilemap_MovesPage (LZ 32x32, 2048 bytes)
Versions.KEYPAD_ICONS_GFX = 0x1EA700                     -- gKeypadIconTiles (4bpp, 2048 bytes = 128x32)
Versions.SUMMARY_STATUS_ICONS_GFX = 0xE82EA0     -- gStatusGfx_Icons (LZ 4bpp, 1024 bytes)
Versions.SUMMARY_STATUS_ICONS_PAL = 0xE9BF28     -- gSummaryStatus_Pal (32 bytes)
Versions.SUMMARY_CURSOR_LEFT_GFX = 0x463740      -- sMoveSelectionCursor_Left_Gfx (288 bytes)
Versions.SUMMARY_CURSOR_RIGHT_GFX = 0x46386C     -- sMoveSelectionCursor_Right_Gfx (288 bytes)
Versions.SUMMARY_CURSOR_PAL = 0x463720           -- sMoveSelectionCursor_Pal (32 bytes)
Versions.SUMMARY_SHINY_STAR_GFX = 0x463B64       -- sShinyStar_Gfx (64 bytes)
Versions.SUMMARY_SHINY_STAR_PAL = 0x463B44       -- sShinyStar_Pal (32 bytes)
Versions.SUMMARY_POKERUS_GFX = 0x463B20          -- sPokerus_Gfx (64 bytes)
Versions.SUMMARY_POKERUS_PAL = 0x463B00          -- sPokerus_Pal (32 bytes)
Versions.SUMMARY_HP_BAR_YELLOW_PAL = 0x463AAC    -- sHpBar_Yellow_Pal (32 bytes)
Versions.SUMMARY_HP_BAR_RED_PAL = 0x463ACC       -- sHpBar_Red_Pal (32 bytes)
Versions.MENU_INFO_GFX = 0xE95DDC                -- gMenuInfoElements_Gfx (4bpp 128x128, 8192 bytes)
Versions.MENU_INFO_PAL = 0xE95D9C                -- gMenuInfoElements1_Pal + gMenuInfoElements2_Pal (64 bytes)

-- Bag / item-menu chrome + item icons (LZ; FireRed USA 1.0).
Versions.BAG_BG_GFX = 0xE830CC                  -- gBagBg_Gfx
Versions.BAG_BG_TILEMAP = 0xE832C0              -- gBagBg_Tilemap
Versions.BAG_BG_ITEM_PC_TILEMAP = 0xE83444      -- gBagBg_ItemPC_Tilemap
Versions.BAG_BG_PAL = 0xE835B4                  -- gBagBgPalette (3 banks)
Versions.BAG_BG_PAL_FEMALE = 0xE83604           -- gBagBgPalette_FemaleOverride
Versions.BAG_MALE_GFX = 0xE8362C                -- gBagMale_Gfx (64×256)
Versions.BAG_FEMALE_GFX = 0xE83DBC              -- gBagFemale_Gfx
Versions.BAG_SPRITE_PAL = 0xE84560              -- gBag_Pal
Versions.BAG_SWAP_GFX = 0xE84588                -- gSwapLine_Gfx
Versions.BAG_SWAP_PAL = 0xE845C8                -- gSwapLine_Pal
Versions.BAG_LIST_TILEMAP = 0x452D08            -- sItemListTilemap (raw u16 18x12)
Versions.BAG_LIST_TILES_W = 18
Versions.BAG_LIST_TILES_H = 12
Versions.BAG_LIST_BLANK_TILE = 0x02D             -- src/item_menu.c:1163
Versions.RED_ARROW_PAL = 0x463308               -- sRedArrowPal (raw 32 bytes)
Versions.RED_ARROW_OTHER_GFX = 0x463328         -- sRedArrowOtherGfx (LZ 4bpp 16x32)

-- TM Case (LZ-compressed & raw; FireRed USA 1.0).
Versions.TM_CASE_BG_GFX = 0xE845D8               -- gTMCase_Gfx (LZ 4bpp, 2912 bytes)
Versions.TM_CASE_MENU_TILEMAP = 0xE84A24         -- gTMCaseMenu_Tilemap (LZ 32x32, 2048 bytes)
Versions.TM_CASE_BG_TILEMAP = 0xE84B70           -- gTMCase_Tilemap (LZ 32x32, 2048 bytes)
Versions.TM_CASE_MENU_MALE_PAL = 0xE84CB0        -- gTMCaseMenu_Male_Pal (LZ 4 banks, 128 bytes)
Versions.TM_CASE_MENU_FEMALE_PAL = 0xE84D20      -- gTMCaseMenu_Female_Pal (LZ 4 banks, 128 bytes)
Versions.TM_CASE_DISC_GFX = 0xE84D90             -- gTMCaseDisc_Gfx (LZ 4bpp, 1024 bytes)
Versions.TM_CASE_DISC_TYPES1_PAL = 0xE84F20      -- gTMCaseDiscTypes1_Pal (LZ 16 banks, 512 bytes)
Versions.TM_CASE_DISC_TYPES2_PAL = 0xE85068      -- gTMCaseDiscTypes2_Pal (LZ 1 bank, 32 bytes)
Versions.TM_CASE_HM_GFX = 0xE99138               -- gTMCaseHM_Gfx (raw 4bpp, 96 bytes)

-- Berry Pouch (LZ-compressed; FireRed USA 1.0).
Versions.BERRY_POUCH_SPRITE_GFX = 0xE8560C       -- gBerryPouchSpriteTiles (LZ 4bpp 64x64, 2048 bytes)
Versions.BERRY_POUCH_BG_GFX = 0xE859D0           -- gBerryPouchBgGfx (LZ 4bpp, 1664 bytes)
Versions.BERRY_POUCH_BG_PAL = 0xE85BA4           -- gBerryPouchBgPals (LZ 3 banks, 96 bytes)
Versions.BERRY_POUCH_BG_PAL_FEMALE = 0xE85BF4    -- gBerryPouchBgPal0FemaleOverride (LZ 1 bank, 32 bytes)
Versions.BERRY_POUCH_SPRITE_PAL = 0xE85C1C       -- gBerryPouchSpritePalette (LZ 1 bank, 32 bytes)
Versions.BERRY_POUCH_BG_TILEMAP = 0xE85C44       -- gBerryPouchBg1Tilemap (LZ 32x32, 2048 bytes)

-- Trainer Card (LZ-compressed & raw; FireRed USA 1.0).
Versions.TRAINER_CARD_BG_TILES = 0xE991F8       -- gKantoTrainerCard_Gfx (LZ 4bpp, 6144 bytes)
Versions.TRAINER_CARD_FRONT_MAP = 0x3CC6F0      -- sKantoTrainerCardFront_Tilemap (LZ 30x20, 1200 bytes)
Versions.TRAINER_CARD_BG_MAP = 0x3CCEC8         -- sKantoTrainerCardBg_Tilemap (LZ 30x20, 1200 bytes)
Versions.TRAINER_CARD_PAL = 0xE99198            -- gKantoTrainerCardBlue_Pal (3 banks, 96 bytes)
Versions.TRAINER_CARD_FEMALE_PAL = 0x3CD2A0     -- sKantoTrainerCardFemaleBg_Pal (1 bank, 32 bytes)
Versions.TRAINER_CARD_BADGES_TILES = 0x3CD5E8   -- sKantoTrainerCardBadges_Gfx (LZ 4bpp, 1024 bytes)
Versions.TRAINER_CARD_BADGES_PAL = 0x3CD2C0     -- sKantoTrainerCardBadges_Pal (1 bank, 32 bytes)
Versions.TRAINER_PIC_RED = 135
Versions.TRAINER_PIC_LEAF = 136
Versions.SHOP_BG_GFX = 0xE85DC8                 -- gBuyMenuFrame_Gfx
Versions.SHOP_BG_TILEMAP = 0xE85EFC             -- gBuyMenuFrame_Tilemap
Versions.SHOP_BG_TM_TILEMAP = 0xE86038          -- gBuyMenuFrame_TmHmTilemap
Versions.SHOP_BG_PAL = 0xE86170                 -- gBuyMenuFrame_Pal
Versions.ITEM_ICON_TABLE = 0x3D4294             -- sItemIconTable[ITEMS_COUNT+1]
Versions.ITEMS_COUNT = 375                      -- pret ITEMS_COUNT (table rows = +1)

-- Door animation graphics (sDoorGraphics[] from field_door.c; FireRed USA 1.0 file offsets).
-- Table layout: 12 bytes/entry: u32(metatileId|isLarge<<16) | ptr_tiles | ptr_pal
-- Verified by matching known metatile-ID sequence from DOOR_ENTRIES (0x03D/0x062/0x15B...).
Versions.DOOR_GRAPHICS_TABLE = 0x35B5D8         -- sDoorGraphics[32]
Versions.DOOR_GRAPHICS_COUNT = 32               -- entries in the table

-- Title screen + Oak speech graphics (FireRed USA 1.0 file offsets).
-- Verified by matching pret .gbapal bytes + LZ sizes in local dump.
Versions.INTRO = {
  -- Oak speech pics: 64×96 8bpp; ROM stores 32-color pal, indices use bank bits.
  leaf_pal = 0x460ED4,
  leaf_tiles = 0x460F14, -- LZ → 0x1800
  red_pal = 0x4615FC,
  red_tiles = 0x46163C, -- LZ → 0x1800
  oak_pal = 0x461CD4,
  oak_tiles = 0x461D14, -- LZ → 0x1800
  rival_pal = 0x4623AC,
  rival_tiles = 0x4623EC, -- LZ → 0x1800
  platform_pal = 0x4629D0, -- 16 colors
  platform_tiles = 0x462A10, -- LZ → 0x600 (3×32×32)
  -- Title screen
  logo_pal = 0xEAB6C4, -- 256 colors
  logo_tiles = 0xEAB8C4, -- LZ → 0x4000 (8bpp)
  logo_map = 0xEAD390, -- LZ → 0x500 (32×20)
  box_pal = 0xEAD5E8, -- 16 colors
  box_tiles = 0xEAD608, -- LZ → 0x10E0 (135 tiles 4bpp)
  box_map = 0xEADEE4, -- LZ → 0x500
  copyright_pal = 0xEAE094, -- 16 colors (bg + press-start)
  copyright_tiles = 0xEAE0B4, -- LZ → 0x800
  copyright_map = 0xEAE374, -- LZ → 0x500
  -- Oak speech scene BG (verified vs pret oak_speech_bg.* LZ)
  oak_speech_bg_pal = 0x460568, -- first 16 of shared guide pal
  oak_speech_bg_tiles = 0x460CA4, -- LZ → 0x140 (10 tiles)
  oak_speech_bg_map = 0x460CE8, -- LZ → 0x500
  -- Controls guide + Pikachu intro BG (pret bg_tiles + pikachu_intro/tilemap)
  -- Shared pal is 64 colors (4 banks) packed before tiles LZ.
  guide_bg_pal = 0x460568, -- 64 colors
  guide_bg_tiles = 0x4605E8, -- LZ → 0x1400 (160 tiles)
  pikachu_intro_map = 0x460BA8, -- LZ → 0x438 (30×18)
  controls_page2_map = 0x460D94, -- 5×16 u16 uncompressed
  controls_page3_map = 0x460E34, -- 5×16 u16 uncompressed
  stdpal_2 = 0x471E2C, -- GetTextWindowPalette(2); TopBar / chrome rows
  -- Pikachu intro sprites (pret pikachu_intro/{body,ears,eyes})
  pikachu_pal = 0x4629F0, -- 16 colors
  pikachu_body = 0x462B74, -- LZ → 0x400 (32×64, 2 frames)
  pikachu_ears = 0x462D34, -- LZ → 0x200 (32×32)
  pikachu_eyes = 0x462E18, -- LZ → 0x80 (16×8)
  -- Nidoran♀ front (species 29) + poke ball for release anim
  -- gMonFrontPicTable @ 0x2350AC; gMonPaletteTable @ 0x23730C (FR USA 1.0)
  mon_front_pic_table = 0x2350AC,
  mon_palette_table = 0x23730C,
  nidoran_f_tiles = 0xD42FB8, -- LZ → 0x800 (64×64); was wrongly 0x4096CC (Bulbasaur)
  nidoran_f_pal = 0xD4321C, -- LZ → 0x20
  ball_poke_tiles = 0xD01724, -- LZ → 0x180 (16×48)
  ball_poke_pal = 0xD017E0, -- LZ → 0x20
}

-- Intro cutscene sequence assets (pokefirered/src/intro.c rodata offsets).
Versions.INTRO_MOVIE = {
  copyright_pal = 0x402260,
  copyright_tiles = 0x402280, -- LZ → 1248 bytes
  copyright_map = 0x4024E4,   -- LZ → 2048 bytes (32×32)

  gf_bg_pal = 0x402630,
  gf_bg_tiles = 0x402650,     -- LZ → 96 bytes
  gf_bg_map = 0x402668,       -- LZ → 1280 bytes (32×20)
  gf_logo_pal = 0x40270C,
  gf_text_tiles = 0x40272C,   -- LZ → 1152 bytes
  gf_logo_tiles = 0x4028F8,   -- LZ → 1024 bytes
  star_pal = 0x402A44,
  star_tiles = 0x402A64,      -- LZ → 128 bytes
  sparkles_pal = 0x402ABC,
  sparkles_small_tiles = 0x402ADC, -- LZ → 128 bytes
  sparkles_big_tiles = 0x402B2C,   -- LZ → 2048 bytes
  presents_tiles = 0x402CD4,       -- LZ → 256 bytes

  scene1_grass_pal = 0x402D34,
  scene1_grass_tiles = 0x402D54,   -- LZ → 12704 bytes
  scene1_grass_map = 0x403FE8,     -- LZ → 4096 bytes (64×32)
  scene1_bg_pal = 0x4048CC,
  scene1_bg_tiles = 0x4048EC,      -- LZ → 4352 bytes
  scene1_bg_map = 0x404F7C,        -- LZ → 4096 bytes (64×32)

  scene2_bg_pal = 0x4053B4,        -- 96 bytes (3 banks)
  scene2_bg_tiles = 0x405414,      -- LZ → 2176 bytes
  scene2_bg_map = 0x405890,        -- LZ → 4096 bytes (64×32)
  scene2_plants_pal = 0x405B08,
  scene2_plants_tiles = 0x405B28,  -- LZ → 544 bytes
  scene2_plants_map = 0x405CDC,    -- LZ → 1280 bytes (32×20)
  gengar_pal = 0x405DA4,
  scene2_gengar_close_tiles = 0x405DC4, -- LZ → 3648 bytes
  scene2_gengar_close_map = 0x40644C,   -- LZ → 2048 bytes (32×32)
  scene2_nidorino_close_pal = 0x406634,
  scene2_nidorino_close_tiles = 0x406654, -- LZ → 5440 bytes
  scene2_nidorino_close_map = 0x4071D0,   -- LZ → 2048 bytes (32×32)

  scene3_bg_pal = 0x407430,        -- 64 bytes (2 banks)
  scene3_bg_tiles = 0x407470,      -- LZ → 2784 bytes
  scene3_bg_map = 0x407A50,        -- LZ → 1280 bytes (32×20)
  scene3_gengar_anim_tiles = 0x407B9C, -- LZ → 11136 bytes
  scene3_gengar_anim_map = 0x408D98,   -- LZ → 4096 bytes (64×32)
  scene2_gengar_tiles = 0x40926C,      -- LZ → 2048 bytes (64×64)
  nidorino_pal = 0x4096AC,
  scene2_nidorino_tiles = 0x4096CC,    -- LZ → 2048 bytes (64×64)
  scene3_grass_pal = 0x409A1C,
  scene3_grass_tiles = 0x409A3C,       -- LZ → 2048 bytes (64×64)
  scene3_gengar_static_tiles = 0x409D20, -- LZ → 6144 bytes
  scene3_nidorino_tiles = 0x40A3E4,    -- LZ → 10240 bytes
  scene3_swipe_pal = 0x40B834,
  scene3_recoil_dust_pal = 0x40B854,
  scene3_swipe_tiles = 0x40B874,       -- LZ → 2560 bytes
  scene3_recoil_dust_tiles = 0x40BAE0, -- LZ → 512 bytes
}

-- Title screen particle effects (pokefirered/src/title_screen.c).
Versions.TITLE_EFFECTS = {
  border_bg_tiles = 0x3BF58C,      -- LZ → 128 bytes
  border_bg_map = 0x3BF5A8,        -- LZ → 1280 bytes
  slash_tiles = 0x3BF64C,          -- LZ → 2048 bytes
  flames_pal = 0x3BF77C,           -- 32 bytes
  flames_tiles = 0x3BF79C,         -- LZ → 1280 bytes
  blank_flames_tiles = 0x3BFA14,   -- LZ → 1280 bytes
}


-- Naming screen chrome (FireRed USA 1.0). Verified by matching pret LZ/4bpp.
Versions.NAMING = {
  keyboard_pal = 0xE97FE4, -- 16 colors
  rival_pal = 0xE98004, -- 16 colors
  menu_pal = 0xE98024, -- 6×16 banks (menu / page labels / buttons / cursor)
  menu_gfx = 0xE980E4, -- LZ → 0x600
  background_map = 0xE982BC, -- LZ → 0x500
  keyboard_upper_map = 0xE98398, -- LZ → 0x500
  keyboard_lower_map = 0xE98458, -- LZ → 0x500
  keyboard_symbols_map = 0xE98518, -- LZ → 0x500
  -- Uncompressed 4bpp sprite sheets (sequential in ROM)
  page_swap_frame = 0xE985D8, -- 0x280
  back_button = 0xE98858, -- 0x1E0
  ok_button = 0xE98A38, -- 0x1E0
  page_swap_upper = 0xE98C18, -- 0x60
  page_swap_lower = 0xE98CB8, -- 0x60
  page_swap_others = 0xE98D58, -- 0x60
  cursor = 0xE98DF8, -- 0x80
  cursor_squished = 0xE98E98, -- 0x80
  cursor_filled = 0xE98F38, -- 0x80
  page_swap_button = 0xE98FD8, -- 0x100
  input_arrow = 0xE990D8, -- 0x20
  underscore = 0xE990F8, -- 0x20
  rival_gfx = 0x38A428, -- uncompressed 0x900 (naming-screen rival bust)
}

-- General primary tileset anim frames (TilesetAnim_General).
Versions.TILESET_ANIM_GENERAL = {
  flower = { base = 0x3A73E0, stride = 0x80, count = 5, bytes = 0x80 },
  water = { base = 0x3A7674, stride = 0x600, count = 8, bytes = 0x600 },
  sand = { base = 0x3AA674, stride = 0x240, count = 8, bytes = 0x240 },
}

-- Extract tileset pair → engine tileset id (palette bank key).
Versions.PAIR_TILESET = {
  sevii_outdoor = "SEVII_OUTDOOR",
  network = "SEVII_NETWORK",
  house = "SEVII_HOUSE",
  harbor = "SEVII_HARBOR",
  pallet_outdoor = "FR_PALLET_OUTDOOR",
  player_house = "FR_PLAYER_HOUSE",
  oak_lab = "FR_OAK_LAB",
  pewter_outdoor = "FR_PEWTER_OUTDOOR",
  pewter_gym = "FR_PEWTER_GYM",
  viridian_outdoor = "FR_VIRIDIAN_OUTDOOR",
}

-- Individual tileset blobs (FireRed USA 1.0), verified by matching pret bins in ROM.
Versions.TILESETS = {
  general = {
    compressed = true,
    secondary = false,
    tiles = 0x0EA1D68,
    palettes = 0x0EA1B68,
    metatiles = 0x29F6C8,
    attributes = 0x2A1EC8,
    metatile_bytes = 10240, -- 640 mids
    attr_bytes = 2560,
    palette_count = 16,
  },
  building = {
    compressed = true,
    secondary = false,
    tiles = 0x0275294,
    palettes = 0x0277694,
    metatiles = 0x02AD7B4,
    attributes = 0x02AFFB4,
    metatile_bytes = 10240, -- 640 mids
    attr_bytes = 2560,
    palette_count = 16,
  },
  sevii_islands_123 = {
    compressed = true,
    secondary = true,
    tiles = 0x0298B70,
    palettes = 0x0299AA4,
    metatiles = 0x2CD1CC,
    attributes = 0x2CE39C,
    metatile_bytes = 4560, -- 285 mids
    attr_bytes = 1140,
    palette_count = 16,
  },
  pokemon_center = {
    compressed = true,
    secondary = true,
    tiles = 0x0277C5C,
    palettes = 0x0278CC4,
    metatiles = 0x02B3A60,
    attributes = 0x02B4A50,
    metatile_bytes = 4080, -- 255 mids
    attr_bytes = 1020,
    palette_count = 16,
  },
  generic_building_2 = {
    compressed = true,
    secondary = true,
    tiles = 0x028E5A4,
    palettes = 0x028EC70,
    metatiles = 0x02BEF14,
    attributes = 0x02BFA94,
    metatile_bytes = 2944, -- 184 mids
    attr_bytes = 736,
    palette_count = 16,
  },
  island_harbor = {
    compressed = true,
    secondary = true,
    tiles = 0x029D0E4,
    palettes = 0x029D894,
    metatiles = 0x02D1D30,
    attributes = 0x02D2220,
    metatile_bytes = 1264, -- 79 mids
    attr_bytes = 316,
    palette_count = 16,
  },
  -- Pallet Town / Route 1 secondary (petaltown / pallet_town).
  -- Sizes must match pret bins in ROM (attrs sit immediately after metatiles).
  -- Oversized metatile_bytes previously skipped real attrs → outdoor doors
  -- seeded as solid BUILDING (0x07) instead of MB_WARP_DOOR.
  pallet_town = {
    compressed = true,
    secondary = true,
    tiles = 0x026D37C,
    palettes = 0x026D7C0,
    metatiles = 0x02A28C8,
    attributes = 0x02A2E58,
    metatile_bytes = 1424, -- 89 mids
    attr_bytes = 356,
    palette_count = 16,
  },
  pewter_city = {
    compressed = true,
    secondary = true,
    tiles = 0x026E1C0,
    palettes = 0x026EAB8,
    metatiles = 0x02A3728,
    attributes = 0x02A3C18,
    metatile_bytes = 1264, -- 79 mids
    attr_bytes = 316,
    palette_count = 16,
  },
  -- Viridian City / Route 2 secondary (matched pret bins in FR 1.0 ROM).
  viridian_city = {
    compressed = true,
    secondary = true,
    tiles = 0x026D9C0,
    palettes = 0x026DFC0,
    metatiles = 0x02A2FBC,
    attributes = 0x02A35AC,
    metatile_bytes = 1520, -- 95 mids
    attr_bytes = 380,
    palette_count = 16,
  },
  pewter_gym = {
    compressed = true,
    secondary = true,
    tiles = 0x02831BC,
    palettes = 0x02839B0,
    metatiles = 0x02AAA14,
    attributes = 0x02AB064,
    metatile_bytes = 1616, -- 101 mids
    attr_bytes = 404,
    palette_count = 16,
  },
  -- Player house interior secondary.
  pretty_petals_flower_shop = {
    compressed = true,
    secondary = true,
    tiles = 0x0EA99F4,
    palettes = 0x0EA97F4,
    metatiles = 0x02B4E4C,
    attributes = 0x02B4FCC,
    metatile_bytes = 384, -- 24 mids (ROM matches pret generic_building_1)
    attr_bytes = 96,
    palette_count = 16,
  },
  -- Oak lab secondary.
  lab = {
    compressed = true,
    secondary = true,
    tiles = 0x02806EC,
    palettes = 0x0280D00,
    metatiles = 0x02B68A0,
    attributes = 0x02B7390,
    metatile_bytes = 2800, -- 175 mids
    attr_bytes = 700,
    palette_count = 16,
  },
}

-- Primary+secondary pairs used by Island 1 maps.
Versions.TILESET_PAIRS = {
  sevii_outdoor = { primary = "general", secondary = "sevii_islands_123" },
  network = { primary = "building", secondary = "pokemon_center" },
  house = { primary = "building", secondary = "generic_building_2" },
  harbor = { primary = "general", secondary = "island_harbor" },
  pallet_outdoor = { primary = "general", secondary = "pallet_town" },
  player_house = { primary = "building", secondary = "pretty_petals_flower_shop" },
  oak_lab = { primary = "building", secondary = "lab" },
  pewter_outdoor = { primary = "general", secondary = "pewter_city" },
  pewter_gym = { primary = "building", secondary = "pewter_gym" },
  viridian_outdoor = { primary = "general", secondary = "viridian_city" },
}

-- Layout geometry + which tileset pair each map uses.
Versions.MAPS = {
  SEVII_ONE_ISLAND = {
    layout = "OneIsland",
    width = 24, height = 20,
    kind = "town",
    environment = "TOWN",
    pair = "sevii_outdoor",
  },
  SEVII_ONE_ISLAND_KINDLE_ROAD = {
    layout = "OneIsland_KindleRoad",
    width = 24, height = 140,
    kind = "route",
    environment = "ROUTE",
    pair = "sevii_outdoor",
  },
  SEVII_ONE_ISLAND_TREASURE_BEACH = {
    layout = "OneIsland_TreasureBeach",
    width = 24, height = 40,
    kind = "route",
    environment = "ROUTE",
    pair = "sevii_outdoor",
  },
  -- FRLG Network Center (heal + Network Machine). Not a stock Gen1/2 Poké Center.
  SEVII_ONE_ISLAND_POKECENTER = {
    layout = "OneIsland_PokemonCenter_1F",
    width = 19, height = 11,
    kind = "indoor",
    environment = "INDOOR",
    pair = "network",
  },
  SEVII_ONE_ISLAND_POKECENTER_2F = {
    layout = "OneIsland_PokemonCenter_2F",
    width = 15, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "network",
  },
  SEVII_ONE_ISLAND_HARBOR = {
    layout = "Island_Harbor",
    width = 17, height = 13,
    kind = "indoor",
    environment = "INDOOR",
    pair = "harbor",
  },
  SEVII_ONE_ISLAND_HOUSE1 = {
    layout = "House3",
    width = 11, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  SEVII_ONE_ISLAND_HOUSE2 = {
    layout = "House3",
    width = 11, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  FR_PALLET_TOWN = {
    layout = "PalletTown",
    width = 24, height = 20,
    kind = "town",
    environment = "TOWN",
    pair = "pallet_outdoor",
  },
  FR_ROUTE_1 = {
    layout = "Route1",
    width = 24, height = 40,
    kind = "route",
    environment = "ROUTE",
    pair = "pallet_outdoor",
  },
  FR_VIRIDIAN_CITY = {
    layout = "ViridianCity",
    width = 48, height = 40,
    kind = "town",
    environment = "TOWN",
    pair = "viridian_outdoor",
  },
  FR_ROUTE_2 = {
    layout = "Route2",
    width = 24, height = 80,
    kind = "route",
    environment = "ROUTE",
    pair = "viridian_outdoor",
  },
  -- pret: 2F bedroom is 12×9; 1F living room is 13×10 (names are easy to swap).
  FR_PLAYERS_HOUSE_2F = {
    layout = "PlayersHouse_2F",
    width = 12, height = 9,
    kind = "indoor",
    environment = "INDOOR",
    pair = "player_house",
  },
  FR_PLAYERS_HOUSE_1F = {
    layout = "PlayersHouse_1F",
    width = 13, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "player_house",
  },
  FR_RIVALS_HOUSE = {
    layout = "RivalsHouse",
    width = 13, height = 10,
    kind = "indoor",
    environment = "INDOOR",
    pair = "house",
  },
  FR_OAKS_LAB = {
    layout = "OaksLab",
    width = 13, height = 14,
    kind = "indoor",
    environment = "INDOOR",
    pair = "oak_lab",
  },
  FR_PEWTER_CITY = {
    layout = "PewterCity",
    width = 48, height = 40,
    kind = "town",
    environment = "TOWN",
    pair = "pewter_outdoor",
  },
  FR_PEWTER_CITY_GYM = {
    layout = "PewterCity_Gym",
    width = 13, height = 16,
    kind = "indoor",
    environment = "INDOOR",
    pair = "pewter_gym",
  },
}

-- FireRed USA 1.0 gMapGroups (array of MapGroup* → MapHeader*).
-- Verified: group[3][0] = PalletTown MapHeader @ 0x350618.
Versions.G_MAP_GROUPS = 0x3526A8
Versions.NUM_MAP_GROUPS = 43 -- pret map_groups.json group_order length

-- FireRed USA 1.0 MapHeader file offsets (verified against local dump).
-- Legacy hand list — prefer MapTree.walk(gMapGroups) for new extract.
-- Shared layouts (House3 / Harbor / PC 2F) disambiguated by header proximity
-- to One Island Network Center (0x351B6C).
Versions.MAP_HEADERS = {
  SEVII_ONE_ISLAND = 0x350768,
  SEVII_ONE_ISLAND_KINDLE_ROAD = 0x350B04,
  SEVII_ONE_ISLAND_TREASURE_BEACH = 0x350B20,
  SEVII_ONE_ISLAND_POKECENTER = 0x351B6C,
  SEVII_ONE_ISLAND_POKECENTER_2F = 0x351B18,
  SEVII_ONE_ISLAND_HARBOR = 0x351B50,
  SEVII_ONE_ISLAND_HOUSE1 = 0x351BA4,
  SEVII_ONE_ISLAND_HOUSE2 = 0x351BC0,
  FR_PALLET_TOWN = 0x350618,
  FR_VIRIDIAN_CITY = 0x350634,
  FR_ROUTE_1 = 0x35082C,
  FR_ROUTE_2 = 0x350848,
  -- MapHeaders: 0x350D50 = 1F (Mom + 4 warps); 0x350D6C = 2F (bedroom signs + 1 warp).
  FR_PLAYERS_HOUSE_1F = 0x350D50,
  FR_PLAYERS_HOUSE_2F = 0x350D6C,
  FR_RIVALS_HOUSE = 0x350D88,
  FR_OAKS_LAB = 0x350DA4,
  FR_PEWTER_CITY = 0x350650,
  FR_PEWTER_CITY_GYM = 0x350EA0,
}

-- FireRed USA 1.0 map.bin offsets (matched against pret layout bins).
local FIRERED_10_LAYOUTS = {
  OneIsland = { offset = 0x321354, width = 24, height = 20 },
  OneIsland_KindleRoad = { offset = 0x324330, width = 24, height = 140 },
  OneIsland_TreasureBeach = { offset = 0x325D94, width = 24, height = 40 },
  OneIsland_PokemonCenter_1F = { offset = 0x33A7CC, width = 19, height = 11 },
  -- Shared Pokémon Center 2F bin (several maps); first hit is fine — identical data.
  OneIsland_PokemonCenter_2F = { offset = 0x2D59B4, width = 15, height = 10 },
  Island_Harbor = { offset = 0x343DFC, width = 17, height = 13 },
  House3 = { offset = 0x2D5BF0, width = 11, height = 9 },
  PalletTown = { offset = 0x2DD100, width = 24, height = 20 },
  Route1 = { offset = 0x2E4E4C, width = 24, height = 40 },
  ViridianCity = { offset = 0x2DD4E4, width = 48, height = 40 },
  Route2 = { offset = 0x2E55F0, width = 24, height = 80 },
  -- Verified vs pret map.bin + local FR ROM: 0x2D50FC = 1F (13×10), 0x2D5224 = 2F (12×9).
  PlayersHouse_1F = { offset = 0x2D50FC, width = 13, height = 10 },
  PlayersHouse_2F = { offset = 0x2D5224, width = 12, height = 9 },
  RivalsHouse = { offset = 0x2D5320, width = 13, height = 10 },
  OaksLab = { offset = 0x2D54FC, width = 13, height = 14 },
  PewterCity = { offset = 0x2DE408, width = 48, height = 40 },
  PewterCity_Gym = { offset = 0x2D718C, width = 13, height = 16 },
}

-- Cell-space warps (pret map.json). Engine warps are cells (Gen2 setMap x/y).
Versions.WARPS = {
  SEVII_ONE_ISLAND = {
    { x = 14, y = 5, destMap = "SEVII_ONE_ISLAND_POKECENTER", destWarp = 1 },
    { x = 19, y = 9, destMap = "SEVII_ONE_ISLAND_HOUSE1", destWarp = 1 },
    { x = 8, y = 11, destMap = "SEVII_ONE_ISLAND_HOUSE2", destWarp = 1 },
    { x = 12, y = 18, destMap = "SEVII_ONE_ISLAND_HARBOR", destWarp = 1 },
  },
  SEVII_ONE_ISLAND_POKECENTER = {
    { x = 9, y = 9, destMap = "SEVII_ONE_ISLAND", destWarp = 1 },
    { x = 1, y = 5, destMap = "SEVII_ONE_ISLAND_POKECENTER_2F", destWarp = 1 },
  },
  SEVII_ONE_ISLAND_POKECENTER_2F = {
    { x = 1, y = 6, destMap = "SEVII_ONE_ISLAND_POKECENTER", destWarp = 2 },
  },
  SEVII_ONE_ISLAND_HARBOR = {
    { x = 8, y = 2, destMap = "SEVII_ONE_ISLAND", destWarp = 4 },
  },
  SEVII_ONE_ISLAND_HOUSE1 = {
    { x = 4, y = 7, destMap = "SEVII_ONE_ISLAND", destWarp = 2 },
  },
  SEVII_ONE_ISLAND_HOUSE2 = {
    { x = 4, y = 7, destMap = "SEVII_ONE_ISLAND", destWarp = 3 },
  },
  -- destWarp is 1-based index into the destination map's warp list (pret dest_warp_id + 1).
  FR_PALLET_TOWN = {
    { x = 6, y = 7, destMap = "FR_PLAYERS_HOUSE_1F", destWarp = 2 },
    { x = 15, y = 7, destMap = "FR_RIVALS_HOUSE", destWarp = 1 },
    { x = 16, y = 13, destMap = "FR_OAKS_LAB", destWarp = 1 },
  },
  FR_ROUTE_1 = {
  },
  FR_PLAYERS_HOUSE_1F = {
    { x = 5, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 1 },
    { x = 4, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 1 },
    { x = 10, y = 2, destMap = "FR_PLAYERS_HOUSE_2F", destWarp = 1 },
    { x = 3, y = 9, destMap = "FR_PALLET_TOWN", destWarp = 1 },
  },
  FR_PLAYERS_HOUSE_2F = {
    { x = 10, y = 2, destMap = "FR_PLAYERS_HOUSE_1F", destWarp = 3 },
  },
  FR_RIVALS_HOUSE = {
    { x = 4, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
    { x = 5, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
    { x = 3, y = 8, destMap = "FR_PALLET_TOWN", destWarp = 2 },
  },
  FR_OAKS_LAB = {
    { x = 6, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
    { x = 7, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
    { x = 5, y = 12, destMap = "FR_PALLET_TOWN", destWarp = 3 },
  },
  -- Pewter outdoor warps (pret map.json; only Gym wired until other interiors extract).
  FR_PEWTER_CITY = {
    { x = 17, y = 6, destMap = "FR_PEWTER_CITY", destWarp = 1 }, -- museum stub
    { x = 25, y = 4, destMap = "FR_PEWTER_CITY", destWarp = 1 },
    { x = 15, y = 16, destMap = "FR_PEWTER_CITY_GYM", destWarp = 1 },
  },
  FR_PEWTER_CITY_GYM = {
    { x = 5, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
    { x = 6, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
    { x = 7, y = 14, destMap = "FR_PEWTER_CITY", destWarp = 3 },
  },
}

-- FireRed USA 1.0 — verified against local dump + pret bins.
local FIRERED_10 = {
  id = "firered_1_0",
  game = "firered",
  tilesets = Versions.TILESETS,
  layouts = FIRERED_10_LAYOUTS,
  map_headers = Versions.MAP_HEADERS,
  g_map_groups = Versions.G_MAP_GROUPS,
  num_map_groups = Versions.NUM_MAP_GROUPS,
  ow_gfx_pointers = Versions.OW_GFX_POINTERS,
  ow_sprite_palettes = Versions.OW_SPRITE_PALETTES,
  num_obj_event_gfx = Versions.NUM_OBJ_EVENT_GFX,
}

-- SHA-1 (lowercase) → version table. Engine identity is SHA-1 only.
Versions.BY_SHA1 = {
  ["41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"] = FIRERED_10,
  ["dd5945db9b930750cb39d00c84da8571feebf417"] = FIRERED_10,
}
-- Legacy MD5 keys retained only for error messages / migration hints.
Versions.BY_MD5 = {
  ["e26ee0d44e809351c8ce2d73c7400cdd"] = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
}

-- FRLG (mapGroup, mapNum) → Sevii host map ids (Island 1).
Versions.FRLG_MAP_TO_SEVII = {
  ["3:12"] = "SEVII_ONE_ISLAND",
  ["3:45"] = "SEVII_ONE_ISLAND_KINDLE_ROAD",
  ["3:46"] = "SEVII_ONE_ISLAND_TREASURE_BEACH",
  ["32:0"] = "SEVII_ONE_ISLAND_POKECENTER",
  ["32:1"] = "SEVII_ONE_ISLAND_POKECENTER_2F",
  ["32:2"] = "SEVII_ONE_ISLAND_HOUSE1",
  ["32:3"] = "SEVII_ONE_ISLAND_HOUSE2",
  ["32:4"] = "SEVII_ONE_ISLAND_HARBOR",
}

-- Standalone Fire Red map ids (engine Game3).
Versions.FRLG_MAP_TO_FR = {
  ["3:0"] = "FR_PALLET_TOWN",
  ["3:1"] = "FR_VIRIDIAN_CITY",
  ["3:2"] = "FR_PEWTER_CITY",
  ["3:19"] = "FR_ROUTE_1",
  ["3:20"] = "FR_ROUTE_2",
  ["4:0"] = "FR_PLAYERS_HOUSE_1F",
  ["4:1"] = "FR_PLAYERS_HOUSE_2F",
  ["4:2"] = "FR_RIVALS_HOUSE",
  ["4:3"] = "FR_OAKS_LAB",
  ["6:2"] = "FR_PEWTER_CITY_GYM",
}

-- pret map_groups.json name → existing engine id (keep save / session stable).
Versions.PRET_TO_FR = {
  PalletTown = "FR_PALLET_TOWN",
  ViridianCity = "FR_VIRIDIAN_CITY",
  PewterCity = "FR_PEWTER_CITY",
  Route1 = "FR_ROUTE_1",
  Route2 = "FR_ROUTE_2",
  PalletTown_PlayersHouse_1F = "FR_PLAYERS_HOUSE_1F",
  PalletTown_PlayersHouse_2F = "FR_PLAYERS_HOUSE_2F",
  PalletTown_RivalsHouse = "FR_RIVALS_HOUSE",
  PalletTown_ProfessorOaksLab = "FR_OAKS_LAB",
  PewterCity_Gym = "FR_PEWTER_CITY_GYM",
  OneIsland = "SEVII_ONE_ISLAND",
  OneIsland_KindleRoad = "SEVII_ONE_ISLAND_KINDLE_ROAD",
  OneIsland_TreasureBeach = "SEVII_ONE_ISLAND_TREASURE_BEACH",
  OneIsland_PokemonCenter_1F = "SEVII_ONE_ISLAND_POKECENTER",
  OneIsland_PokemonCenter_2F = "SEVII_ONE_ISLAND_POKECENTER_2F",
  OneIsland_Harbor = "SEVII_ONE_ISLAND_HARBOR",
  OneIsland_House1 = "SEVII_ONE_ISLAND_HOUSE1",
  OneIsland_House2 = "SEVII_ONE_ISLAND_HOUSE2",
}

function Versions.seviiMapFor(group, num)
  return Versions.FRLG_MAP_TO_SEVII[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
end

function Versions.frMapFor(group, num)
  local MapCatalog = require("src.import.gba.map_catalog")
  return MapCatalog.mapIdFor(group, num)
    or Versions.FRLG_MAP_TO_FR[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
    or Versions.FRLG_MAP_TO_SEVII[string.format("%d:%d", tonumber(group) or 0, tonumber(num) or 0)]
end

function Versions.mapIdFor(group, num)
  return Versions.frMapFor(group, num)
end

function Versions.normalizeSha1(sha1)
  if type(sha1) ~= "string" then return nil end
  return sha1:lower():gsub("%s+", "")
end

--- Canonical FireRed identity SHA-1 (maps legacy MD5 → SHA-1).
function Versions.identitySha1(hash)
  local key = Versions.normalizeSha1(hash)
  if not key or key == "" then return nil end
  if Versions.BY_MD5[key] and type(Versions.BY_MD5[key]) == "string" then
    return Versions.BY_MD5[key]
  end
  return key
end

-- Deprecated alias
Versions.normalizeMd5 = Versions.normalizeSha1

function Versions.lookup(sha1)
  local key = Versions.identitySha1(sha1)
  if not key or key == "" then return nil, "missing sha1" end
  local ver = Versions.BY_SHA1[key]
  if not ver then
    return nil, "unsupported or unknown FireRed dump SHA-1"
  end
  return ver
end

function Versions.lookupSha1(sha1)
  return Versions.lookup(sha1)
end

return Versions

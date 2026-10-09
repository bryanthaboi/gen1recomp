local Names = require("src.import.gba.anim_names_emerald")

local ROM_BASE = 0x08000000

local function lastIndex(t)
  local n = -1
  for k in pairs(t) do if k > n then n = k end end
  return n + 1
end

return function(V)
  local sym, count, S = V.sym, V.count, V.SYMS

  local function lz(name) return sym(name) end
  local function raw(name) return { off = sym(name), size = S.size(name) } end

  -- pokeemerald/data/battle_anim_scripts.s:18
  V.BATTLE_ANIMS = {
    moves_table = sym("gBattleAnims_Moves"),
    move_count = Names.moveCount,
    status_table = sym("gBattleAnims_StatusConditions"),
    status_count = lastIndex(Names.statusNames),
    general_table = sym("gBattleAnims_General"),
    general_count = lastIndex(Names.generalNames),
    special_table = sym("gBattleAnims_Special"),
    special_count = lastIndex(Names.specialNames),
    -- pokeemerald/src/data/battle_anim.h:1010
    pic_table = sym("gBattleAnimPicTable"),
    pal_table = sym("gBattleAnimPaletteTable"),
    tag_count = count("gBattleAnimPicTable", 8),
    -- pokeemerald/include/constants/battle_anim.h:8
    sprites_start = 10000,
    bg_table = sym("gBattleAnimBackgroundTable"),
    bg_count = count("gBattleAnimBackgroundTable", 12),
    -- pokeemerald/src/graphics.c:853
    substitute_pal = lz("gSubstituteDollPal"),
    substitute_front = lz("gSubstituteDollFrontGfx"),
    substitute_back = lz("gSubstituteDollBackGfx"),
    -- pokeemerald/src/graphics.c:869
    stat_mask_gfx = lz("gStatAnim_Gfx"),
    stat_mask_tilemap1 = lz("gStatAnim_Increase_Tilemap"),
    stat_mask_tilemap2 = lz("gStatAnim_Decrease_Tilemap"),
    stat_mask_pal = lz("gStatAnim_Defense_Pal"),
    stat_mask_pals = {
      lz("gStatAnim_Defense_Pal"), lz("gStatAnim_Attack_Pal"), lz("gStatAnim_Accuracy_Pal"),
      lz("gStatAnim_Speed_Pal"), lz("gStatAnim_Multiple_Pal"), lz("gStatAnim_Evasion_Pal"),
      lz("gStatAnim_SpAttack_Pal"), lz("gStatAnim_SpDefense_Pal"),
    },
    -- pokeemerald/src/graphics.c:17
    smokescreen_gfx = lz("gSmokescreenImpactTiles"),
    smokescreen_pal = lz("gSmokescreenImpactPalette"),
    -- pokeemerald/src/graphics.c:1035
    muddy_water_pal = lz("gBattleAnimBackgroundImageMuddyWater_Pal"),
    named_bgs = {
      -- pokeemerald/src/graphics.c:717
      ATTRACT = { gfx = lz("gBattleAnimBgImage_Attract"), pal = lz("gBattleAnimBgPalette_Attract"),
        map = lz("gBattleAnimBgTilemap_Attract") },
      -- pokeemerald/src/graphics.c:735
      SCARY_FACE_PLAYER = { gfx = lz("gBattleAnimBgImage_ScaryFace"), pal = lz("gBattleAnimBgPalette_ScaryFace"),
        map = lz("gBattleAnimBgTilemap_ScaryFacePlayer") },
      SCARY_FACE_OPPONENT = { gfx = lz("gBattleAnimBgImage_ScaryFace"), pal = lz("gBattleAnimBgPalette_ScaryFace"),
        map = lz("gBattleAnimBgTilemap_ScaryFaceOpponent") },
      -- pokeemerald/src/graphics.c:829
      MORNING_SUN = { gfx = lz("gBattleAnimMaskImage_LightBeam"), pal = lz("gBattleAnimMaskPalette_LightBeam"),
        map = lz("gBattleAnimMaskTilemap_LightBeam") },
      -- pokeemerald/src/graphics.c:577
      METAL_SHINE = { gfx = lz("gMetalShineGfx"), pal = lz("gMetalShinePalette"), map = lz("gMetalShineTilemap") },
      -- pokeemerald/src/graphics.c:881
      CURE_BUBBLES = { gfx = lz("gCureBubblesGfx"), pal = lz("gCureBubblesPal"), map = lz("gCureBubblesTilemap") },
      -- pokeemerald/src/graphics.c:655
      CURSE = { gfx = lz("gBattleAnimMaskImage_Curse"), map = lz("gBattleAnimMaskTilemap_Curse"), pal_white1 = true },
      -- pokeemerald/src/battle_anim_ice.c:1011
      FOG = { gfx_raw = sym("gWeatherFogHorizontalTiles"), gfx_size = S.size("gWeatherFogHorizontalTiles"),
        pal_raw = sym("gFogPalette"), map = lz("gBattleAnimFogTilemap") },
      -- pokeemerald/src/graphics.c:984
      SANDSTORM = { gfx = lz("gBattleAnimBgImage_Sandstorm"), pal_tag = "FLYING_DIRT",
        map = lz("gBattleAnimBgTilemap_Sandstorm") },
      -- pokeemerald/src/graphics.c:1099
      SURF_PLAYER = { gfx = lz("gBattleAnimBgImage_Surf"), pal = lz("gBattleAnimBgPalette_Surf"),
        map = lz("gBattleAnimBgTilemap_SurfPlayer") },
      SURF_OPPONENT = { gfx = lz("gBattleAnimBgImage_Surf"), pal = lz("gBattleAnimBgPalette_Surf"),
        map = lz("gBattleAnimBgTilemap_SurfOpponent") },
    },
  }

  V.ANIM_TAG_NAMES = Names.tagNames
  V.BATTLE_ANIM_STATUS_NAMES = Names.statusNames
  V.BATTLE_ANIM_GENERAL_NAMES = Names.generalNames
  V.BATTLE_ANIM_SPECIAL_NAMES = Names.specialNames
  V.ANIM_NAMES = Names

  local templates, callbacks, tasks = {}, {}, {}
  for key, canon in pairs(Names.templates) do templates[ROM_BASE + S.off(key)] = canon end
  for key, canon in pairs(Names.callbacks) do callbacks[ROM_BASE + S.funcOff(key) + 1] = canon end
  for key, canon in pairs(Names.tasks) do tasks[ROM_BASE + S.funcOff(key) + 1] = canon end
  V.ANIM_TEMPLATE_NAMES = templates
  V.ANIM_CALLBACK_NAMES = callbacks
  V.ANIM_TASK_NAMES = tasks

  -- pokeemerald/data/battle_ai_scripts.s:17
  V.BATTLE_AI_SCRIPTS_TABLE = sym("gBattleAI_ScriptsTable")
  V.BATTLE_AI_SCRIPT_COUNT = count("gBattleAI_ScriptsTable", 4)

  local function env(tiles, tilemap, pal)
    return { tiles = lz(tiles), tilemap = lz(tilemap), pal = lz(pal) }
  end

  -- pokeemerald/src/graphics.c:4
  V.BATTLE_UI = {
    layout = "rse",
    textbox_gfx = lz("gBattleTextboxTiles"),
    textbox_pal = lz("gBattleTextboxPalette"),
    textbox_tilemap = lz("gBattleTextboxTilemap"),
    -- pokeemerald/src/graphics.c:358
    healthbox_elements = sym("gHealthboxElementsGfxTable"),
    healthbox_elements_size = S.size("gHealthboxElementsGfxTable"),
    -- pokeemerald/src/graphics.c:628
    healthbox_player = lz("gHealthboxSinglesPlayerGfx"),
    healthbox_enemy = lz("gHealthboxSinglesOpponentGfx"),
    healthbox_doubles_player = lz("gHealthboxDoublesPlayerGfx"),
    healthbox_doubles_opponent = lz("gHealthboxDoublesOpponentGfx"),
    healthbox_safari = lz("gHealthboxSafariGfx"),
    -- pokeemerald/src/battle_gfx_sfx_util.c:80
    healthbox_pal = sym("gBattleInterface_BallStatusBarPal"),
    healthbar_pal = sym("gBattleInterface_BallDisplayPal"),
    font_bold_glyphs = sym("sFontBoldJapaneseGlyphs"),
    -- pokeemerald/src/battle_interface.c:640
    party_summary_bar = lz("gBattleInterface_BallStatusBarGfx"),
    -- pokeemerald/src/graphics.c:965
    window_text_pal = lz("gBattleWindowTextPalette"),
    pp_text_pal = sym("gPPTextPalette"),
    -- pokeemerald/src/battle_bg.c:602
    terrain_table = sym("sBattleEnvironmentTable"),
    terrain_count = count("sBattleEnvironmentTable", 20),
    terrain_grass = env("gBattleEnvironmentTiles_TallGrass", "gBattleEnvironmentTilemap_TallGrass",
      "gBattleEnvironmentPalette_TallGrass"),
    terrain_building = env("gBattleEnvironmentTiles_Building", "gBattleEnvironmentTilemap_Building",
      "gBattleEnvironmentPalette_Building"),
    -- pokeemerald/src/battle_bg.c:760
    scenes = {
      { key = "frontier", cfg = env("gBattleEnvironmentTiles_Building", "gBattleEnvironmentTilemap_Building",
        "gBattleEnvironmentPalette_Frontier") },
      { key = "groudon", cfg = env("gBattleEnvironmentTiles_Cave", "gBattleEnvironmentTilemap_Cave",
        "gBattleEnvironmentPalette_Groudon") },
      { key = "kyogre", cfg = env("gBattleEnvironmentTiles_Water", "gBattleEnvironmentTilemap_Water",
        "gBattleEnvironmentPalette_Kyogre") },
      { key = "rayquaza", cfg = env("gBattleEnvironmentTiles_Rayquaza", "gBattleEnvironmentTilemap_Rayquaza",
        "gBattleEnvironmentPalette_Rayquaza") },
      { key = "leader", cfg = env("gBattleEnvironmentTiles_Building", "gBattleEnvironmentTilemap_Building",
        "gBattleEnvironmentPalette_BuildingLeader") },
      { key = "champion", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumWallace") },
      { key = "gym", cfg = env("gBattleEnvironmentTiles_Building", "gBattleEnvironmentTilemap_Building",
        "gBattleEnvironmentPalette_BuildingGym") },
      { key = "magma", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumMagma") },
      { key = "aqua", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumAqua") },
      { key = "sidney", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumSidney") },
      { key = "phoebe", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumPhoebe") },
      { key = "glacia", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumGlacia") },
      { key = "drake", cfg = env("gBattleEnvironmentTiles_Stadium", "gBattleEnvironmentTilemap_Stadium",
        "gBattleEnvironmentPalette_StadiumDrake") },
    },
    -- pokeemerald/src/battle_bg.c:1174
    entry_rayquaza = { tiles = lz("gBattleEnvironmentAnimTiles_Rayquaza"),
      tilemap = lz("gBattleEnvironmentAnimTilemap_Rayquaza") },
    -- pokeemerald/src/battle_bg.c:163
    window_templates = { normal = sym("sStandardBattleWindowTemplates"), arena = sym("sBattleArenaWindowTemplates") },
    window_template_counts = {
      normal = count("sStandardBattleWindowTemplates", 8),
      arena = count("sBattleArenaWindowTemplates", 8),
    },
  }

  -- pokeemerald/src/battle_anim_throw.c:143
  V.BALL_OPEN = {
    particle_sheets = sym("sBallParticleSpriteSheets"),
    particle_palettes = sym("sBallParticlePalettes"),
    fade_colors = sym("gBallOpenFadeColors"),
    -- pokeemerald/src/trig.c:5
    sine_table = sym("gSineTable"),
    -- pokeemerald/src/pokeball.c:60
    sprite_sheets = sym("gBallSpriteSheets"),
    sprite_palettes = sym("gBallSpritePalettes"),
    open_ball_gfx = sym("gOpenPokeballGfx"),
  }

  -- pokeemerald/src/battle_transition.c:297
  V.BATTLE_TRANSITION = {
    layout = "rse",
    big_pokeball_gfx = raw("sBigPokeball_Tileset"),
    big_pokeball_tilemap = raw("sBigPokeball_Tilemap"),
    sliding_pokeball_bin = raw("sPokeballTrail_Tileset"),
    sliding_pokeball_gfx = raw("battle_transition.o:sPokeball_Gfx"),
    sliding_pokeball_pal = raw("sFieldEffectPal_Pokeball"),
    mugshot_banner_gfx = raw("sEliteFour_Tileset"),
    grid_square_gfx = raw("sShrinkingBoxTileset"),
    vsbar_tilemap = raw("sMugshotsTilemap"),
    -- pokeemerald/src/battle_transition.c:889
    mugshot_keys = { "sidney", "phoebe", "glacia", "drake", "champion" },
    mugshot_pals = {
      sidney = sym("sMugshotPal_Sidney"),
      phoebe = sym("sMugshotPal_Phoebe"),
      glacia = sym("sMugshotPal_Glacia"),
      drake = sym("sMugshotPal_Drake"),
      champion = sym("sMugshotPal_Champion"),
      male = sym("sMugshotPal_Brendan"),
      female = sym("sMugshotPal_May"),
    },
    -- pokeemerald/src/battle_transition.c:544
    mugshot_pic_ids = sym("sMugshotsTrainerPicIDsTable"),
    mugshot_rotation_scales = sym("sMugshotsOpponentRotationScales"),
    mugshot_coords = sym("sMugshotsOpponentCoords"),
    mugshot_count = count("sMugshotsTrainerPicIDsTable", 1),
    assets = {
      -- pokeemerald/src/battle_transition.c:1407
      { key = "aqua", tiles = lz("sTeamAqua_Tileset"), tilesLz = true, map = lz("sTeamAqua_Tilemap"), mapLz = true,
        pal = raw("sEvilTeam_Palette") },
      { key = "magma", tiles = lz("sTeamMagma_Tileset"), tilesLz = true, map = lz("sTeamMagma_Tilemap"), mapLz = true,
        pal = raw("sEvilTeam_Palette") },
      -- pokeemerald/src/battle_transition.c:1437
      { key = "regice", tiles = raw("sRegis_Tileset"), map = raw("sRegice_Tilemap"), pal = raw("sRegice_Palette") },
      { key = "registeel", tiles = raw("sRegis_Tileset"), map = raw("sRegisteel_Tilemap"),
        pal = raw("sRegisteel_Palette") },
      { key = "regirock", tiles = raw("sRegis_Tileset"), map = raw("sRegirock_Tilemap"), pal = raw("sRegirock_Palette") },
      -- pokeemerald/src/battle_transition.c:1548
      { key = "kyogre", tiles = lz("sKyogre_Tileset"), tilesLz = true, map = lz("sKyogre_Tilemap"), mapLz = true,
        pal = raw("sKyogre1_Palette"), pal2 = raw("sKyogre2_Palette") },
      -- pokeemerald/src/battle_transition.c:3380
      { key = "groudon", tiles = lz("sGroudon_Tileset"), tilesLz = true, map = lz("sGroudon_Tilemap"), mapLz = true,
        pal = raw("sGroudon1_Palette"), pal2 = raw("sGroudon2_Palette") },
      -- pokeemerald/src/battle_transition.c:3448
      { key = "rayquaza", tiles = raw("sRayquaza_Tileset"), map = raw("sRayquaza_Tilemap"),
        pal = raw("sRayquaza_Palette"), previewBank = 5 },
      -- pokeemerald/src/battle_transition.c:4245
      { key = "frontier_logo", tiles = lz("sFrontierLogo_Tileset"), tilesLz = true, map = lz("sFrontierLogo_Tilemap"),
        mapLz = true, pal = raw("sFrontierLogo_Palette") },
      -- pokeemerald/src/battle_transition.c:4452
      { key = "frontier_squares_filled", tiles = lz("sFrontierSquares_FilledBg_Tileset"), tilesLz = true,
        map = raw("sFrontierSquares_Tilemap"), mapW = 4, pal = raw("sFrontierSquares_Palette") },
      { key = "frontier_squares_empty", tiles = lz("sFrontierSquares_EmptyBg_Tileset"), tilesLz = true,
        map = raw("sFrontierSquares_Tilemap"), mapW = 4, pal = raw("sFrontierSquares_Palette") },
      { key = "frontier_squares_shrink1", tiles = lz("sFrontierSquares_Shrink1_Tileset"), tilesLz = true,
        map = raw("sFrontierSquares_Tilemap"), mapW = 4, pal = raw("sFrontierSquares_Palette") },
      { key = "frontier_squares_shrink2", tiles = lz("sFrontierSquares_Shrink2_Tileset"), tilesLz = true,
        map = raw("sFrontierSquares_Tilemap"), mapW = 4, pal = raw("sFrontierSquares_Palette") },
      -- pokeemerald/src/battle_transition_frontier.c:48
      { key = "frontier_logo_center", tiles = lz("sLogoCenter_Gfx"), tilesLz = true, map = lz("sLogoCenter_Tilemap"),
        mapLz = true, pal = raw("sLogo_Pal") },
      { key = "frontier_logo_circles", tiles = lz("sLogoCircles_Gfx"), tilesLz = true, sheetW = 8,
        pal = raw("sLogo_Pal") },
    },
  }

  -- pokeemerald/src/battle_script_commands.c:784
  V.BATTLE_RSE_DATA = {
    pickup_items = raw("sPickupItems"),
    rare_pickup_items = raw("sRarePickupItems"),
    pickup_probabilities = raw("sPickupProbabilities"),
    environment_to_type = raw("sEnvironmentToType"),
    -- pokeemerald/src/battle_tower.c:772
    steven_mons = raw("sStevenMons"),
    steven_mon_size = 20,
    window_templates = V.BATTLE_UI.window_templates,
    window_template_counts = V.BATTLE_UI.window_template_counts,
  }
end

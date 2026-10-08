return {
  -- pokeruby/src/field_control_avatar.c:211
  walkIntoSigns = false,
  -- pokeruby/src/event_object_movement.c:177
  inPlaceMovementTypes = true,
  -- pokeruby/src/data/object_events/object_event_anims.h:313
  runFrames = {
    {
      a = { down = 12, up = 14, left = 16, right = 16 },
      b = { down = 13, up = 15, left = 17, right = 17 },
    },
    {
      a = { down = 9, up = 10, left = 11, right = 11 },
      b = { down = 9, up = 10, left = 11, right = 11 },
    },
  },
  running = {
    flag = "FLAG_SYS_B_DASH",
    mapHeader = true,
    -- pokeruby/src/metatile_behavior.c:1293
    behaviors = {
      "NO_RUNNING", "LONG_GRASS", "HOT_SPRINGS",
      "PACIFIDLOG_VERTICAL_LOG_TOP", "PACIFIDLOG_VERTICAL_LOG_BOTTOM",
      "PACIFIDLOG_HORIZONTAL_LOG_LEFT", "PACIFIDLOG_HORIZONTAL_LOG_RIGHT",
    },
    -- pokeruby/src/bike.c:924
    evenElevation = { "FORTREE_BRIDGE" },
  },
  -- pokeruby/src/trainer_see.c:476
  emotes = {
    exclamation = { sheet = "exclamation_question_mark", frame = 0 },
    question = { sheet = "exclamation_question_mark", frame = 1 },
    heart = { sheet = "heart_icon", frame = 0 },
    frames = 60, yVelocity = -5,
  },
  -- pokeruby/src/battle_setup.c:1181
  encounterMusic = {
    prefix = "TRAINER_ENCOUNTER_MUSIC_", song = "MUS_ENCOUNTER_",
    default = "MUS_ENCOUNTER_SUSPICIOUS",
  },
  -- pokeruby/src/field_door.c:597
  doorSounds = { normal = "SE_DOOR", sliding = "SE_SLIDING_DOOR" },
  -- pokeruby/data/scripts/day_care.inc:285
  eggHatchText = "UnknownString_81B2C68",
  -- pokeruby/src/field_poison.c:81
  poisonFaintText = "fieldPoisonText_PokemonFainted",
  -- pokeruby/src/field_control_avatar.c:580
  fieldPoisonScript = "gUnknown_081A14B8",
  -- pokeruby/src/event_object_movement.c:1767
  invalidGfx = "OBJ_EVENT_GFX_LITTLE_BOY_1",
  fieldMoveScripts = true,
  -- pokeruby/src/fldeff_flash.c:111
  flashScript = "gUnknown_081B694A",
  fieldMoveGfx = {
    CUT_TREE = "OBJ_EVENT_GFX_CUTTABLE_TREE",
    ROCK_SMASH_ROCK = "OBJ_EVENT_GFX_BREAKABLE_ROCK",
    PUSHABLE_BOULDER = "OBJ_EVENT_GFX_PUSHABLE_BOULDER",
  },
}

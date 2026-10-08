return {
  -- pokeemerald/src/field_control_avatar.c:172
  walkIntoSigns = false,
  -- pokeemerald/src/event_object_movement.c:4422
  inPlaceMovementTypes = true,
  -- pokeemerald/src/data/object_events/object_event_anims.h:346
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
  -- pokeemerald/src/bike.c:1056
  running = {
    flag = "FLAG_SYS_B_DASH",
    mapHeader = true,
    -- pokeemerald/src/metatile_behavior.c:1258
    behaviors = {
      "NO_RUNNING", "LONG_GRASS", "HOT_SPRINGS",
      "PACIFIDLOG_VERTICAL_LOG_TOP", "PACIFIDLOG_VERTICAL_LOG_BOTTOM",
      "PACIFIDLOG_HORIZONTAL_LOG_LEFT", "PACIFIDLOG_HORIZONTAL_LOG_RIGHT",
    },
    -- pokeemerald/src/bike.c:905
    evenElevation = { "FORTREE_BRIDGE" },
  },
  -- pokeemerald/src/trainer_see.c:731
  emotes = {
    exclamation = { sheet = "exclamation_question_mark", frame = 0 },
    question = { sheet = "exclamation_question_mark", frame = 1 },
    heart = { sheet = "heart_icon", frame = 0 },
    frames = 60,
    yVelocity = -5,
  },
  -- pokeemerald/src/battle_setup.c:1440
  encounterMusic = {
    prefix = "TRAINER_ENCOUNTER_MUSIC_",
    song = "MUS_ENCOUNTER_",
    default = "MUS_ENCOUNTER_SUSPICIOUS",
  },
  -- pokeemerald/src/field_door.c:546
  doorSounds = { normal = "SE_DOOR", sliding = "SE_SLIDING_DOOR", arena = "SE_REPEL" },
  -- pokeemerald/data/scripts/day_care.inc:263
  eggHatchText = "Text_EggHatchHuh",
  -- pokeemerald/src/field_poison.c:76
  poisonFaintText = "gText_PkmnFainted_FldPsn",
  -- pokeemerald/src/field_control_avatar.c:551
  fieldPoisonScript = "EventScript_FieldPoison",
  -- pokeemerald/src/event_object_movement.c:1927
  invalidGfx = "OBJ_EVENT_GFX_NINJA_BOY",
  -- pokeemerald/data/scripts/field_move_scripts.inc:60
  fieldMoveScripts = true,
  -- pokeemerald/data/scripts/flash.inc:1
  flashScript = "EventScript_UseFlash",
  -- pokeemerald/include/constants/event_objects.h:89
  fieldMoveGfx = {
    CUT_TREE = "OBJ_EVENT_GFX_CUTTABLE_TREE",
    ROCK_SMASH_ROCK = "OBJ_EVENT_GFX_BREAKABLE_ROCK",
    PUSHABLE_BOULDER = "OBJ_EVENT_GFX_PUSHABLE_BOULDER",
  },
}

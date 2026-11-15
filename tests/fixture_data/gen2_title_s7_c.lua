local Fixture = {}

Fixture.gold = {
  below = {
    1,
    1,
    1,
  },
  cloudScrollEvery = 8,
  cloudY = 88,
  clouds = "assets/generated/title/clouds.png",
  cloudsGray = "assets/generated/title/clouds_gray.png",
  copyright = "assets/generated/title/copyright.png",
  copyrightSplash = "assets/generated/title/copyright_splash.png",
  generation = 2,
  hooh = "assets/generated/title/hooh.png",
  hoohBobAmplitude = 2,
  hoohBobStep = 1,
  hoohFrames = {
    "assets/generated/title/hooh_1.png",
    "assets/generated/title/hooh_2.png",
    "assets/generated/title/hooh_3.png",
    "assets/generated/title/hooh_4.png",
    "assets/generated/title/hooh_5.png",
  },
  hoohFramesGray = {
    "assets/generated/title/hooh_1_gray.png",
    "assets/generated/title/hooh_2_gray.png",
    "assets/generated/title/hooh_3_gray.png",
    "assets/generated/title/hooh_4_gray.png",
    "assets/generated/title/hooh_5_gray.png",
  },
  hoohSequence = {
    {
      1,
      10,
    },
    {
      2,
      9,
    },
    {
      3,
      10,
    },
    {
      4,
      10,
    },
    {
      3,
      9,
    },
    {
      5,
      10,
    },
  },
  hoohX = 48,
  hoohY = 56,
  image = "assets/generated/title/pokemon_logo.png",
  layout = "gold_title",
  screen = "assets/generated/title/title_screen.png",
  screenGray = "assets/generated/title/title_screen_gray.png",
  sky = {
    0.48387096774194,
    0.64516129032258,
    1,
  },
  source = "ROM:TitleScreenTilemap + TitleScreenGFX1/2/3/4, CopyrightGFX",
  timeoutFrames = 5056,
  trail = "assets/generated/title/trail.png",
  trailBobAmplitude = 2,
  trailGray = "assets/generated/title/trail_gray.png",
  trailMode = "gold",
  trailPhaseStep = 3,
  trailSpawnEvery = 4,
  trailSpawns = {
    {
      80,
      88,
    },
    {
      104,
      88,
    },
    {
      104,
      88,
    },
    {
      120,
      88,
    },
    {
      120,
      88,
    },
    {
      88,
      88,
    },
  },
  trailStepX = 4,
  trailStepY = 1,
}

Fixture.crystal = {
  below = {
    0,
    0,
    0,
  },
  copyright = "assets/generated/title/copyright.png",
  copyrightBackdrop = {
    0,
    0,
    0,
  },
  copyrightInk = {
    1,
    1,
    1,
  },
  copyrightSplash = "assets/generated/title/copyright_splash.png",
  entrance = {
    hideBelow = 136,
    lines = 80,
    scx = 112,
    step = 4,
  },
  entranceSfx = "Sfx_TitleScreenEntrance",
  gem = "assets/generated/title/crystal_gem.png",
  gemFromY = -50,
  gemGray = "assets/generated/title/crystal_gem_gray.png",
  gemStep = 2,
  gemX = 56,
  gemY = 6,
  generation = 2,
  image = "assets/generated/title/crystal_logo.png",
  layout = "crystal_title",
  palettes = {
    bg = {
      {
        {
          0,
          0,
          0,
        },
        {
          156,
          0,
          0,
        },
        {
          123,
          66,
          255,
        },
        {
          123,
          66,
          255,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          255,
          255,
          255,
        },
        {
          123,
          132,
          255,
        },
        {
          255,
          8,
          107,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          58,
          58,
          58,
        },
        {
          255,
          255,
          255,
        },
        {
          16,
          25,
          247,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          107,
          107,
          107,
        },
        {
          255,
          255,
          148,
        },
        {
          16,
          25,
          247,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          156,
          156,
          156,
        },
        {
          239,
          230,
          99,
        },
        {
          16,
          25,
          247,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          206,
          206,
          206,
        },
        {
          230,
          206,
          49,
        },
        {
          16,
          25,
          247,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          255,
          255,
          255,
        },
        {
          214,
          173,
          0,
        },
        {
          16,
          25,
          247,
        },
      },
      {
        {
          0,
          0,
          0,
        },
        {
          90,
          90,
          156,
        },
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
      },
    },
    obj = {
      {
        {
          0,
          0,
          0,
        },
        {
          82,
          0,
          123,
        },
        {
          140,
          41,
          181,
        },
        {
          156,
          74,
          255,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
      {
        {
          255,
          255,
          255,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
        {
          0,
          0,
          0,
        },
      },
    },
  },
  screen = "assets/generated/title/crystal_screen.png",
  screenGray = "assets/generated/title/crystal_screen_gray.png",
  sky = {
    0,
    0,
    0,
  },
  source = "ROM:TitleSuicuneGFX + TitleLogoGFX + TitleCrystalGFX + TitleScreenPalettes + CopyrightGFX",
  suicune = "assets/generated/title/crystal_suicune.png",
  suicuneEvery = 8,
  suicuneFrames = {
    "assets/generated/title/crystal_suicune_1.png",
    "assets/generated/title/crystal_suicune_2.png",
    "assets/generated/title/crystal_suicune_3.png",
    "assets/generated/title/crystal_suicune_4.png",
  },
  suicuneFramesGray = {
    "assets/generated/title/crystal_suicune_1_gray.png",
    "assets/generated/title/crystal_suicune_2_gray.png",
    "assets/generated/title/crystal_suicune_3_gray.png",
    "assets/generated/title/crystal_suicune_4_gray.png",
  },
  suicuneX = 48,
  suicuneY = 96,
  timeoutFrames = 4416,
  wordmark = "assets/generated/title/crystal_wordmark.png",
}

return Fixture

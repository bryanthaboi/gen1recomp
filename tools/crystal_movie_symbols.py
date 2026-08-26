"""Crystal intro-movie and title-screen symbols for the Crystal manifest.

Gold's title/intro symbols do not exist in Crystal: CrystalIntro is a different
program with its own asset set (engine/movie/intro.asm:1678-1777) and the title
composes on the fly with no tilemap (engine/movie/title.asm:364-374).
"""

# engine/movie/intro.asm:1678-1777
INTRO_SYMBOLS = [
    "IntroSuicuneRunGFX",
    "IntroPichuWooperGFX",
    "IntroBackgroundGFX",
    "IntroBackgroundTilemap",
    "IntroBackgroundAttrmap",
    "IntroBackgroundPalette",
    "IntroUnownsGFX",
    "IntroPulseGFX",
    "IntroUnownATilemap",
    "IntroUnownAAttrmap",
    "IntroUnownHITilemap",
    "IntroUnownHIAttrmap",
    "IntroUnownsTilemap",
    "IntroUnownsAttrmap",
    "IntroUnownsPalette",
    "IntroCrystalUnownsGFX",
    "IntroCrystalUnownsTilemap",
    "IntroCrystalUnownsAttrmap",
    "IntroCrystalUnownsPalette",
    "IntroSuicuneCloseGFX",
    "IntroSuicuneCloseTilemap",
    "IntroSuicuneCloseAttrmap",
    "IntroSuicuneClosePalette",
    "IntroSuicuneJumpGFX",
    "IntroSuicuneBackGFX",
    "IntroSuicuneJumpTilemap",
    "IntroSuicuneJumpAttrmap",
    "IntroSuicuneBackTilemap",
    "IntroSuicuneBackAttrmap",
    "IntroSuicunePalette",
    "IntroUnownBackGFX",
    "IntroGrass1GFX",
    "IntroGrass2GFX",
    "IntroGrass3GFX",
    "IntroGrass4GFX",
]

# Palette fades that live as local labels inside their scene routines.
# engine/movie/intro.asm:1189 (fade.pal), :1385-1388 (unown_1.pal / unown_2.pal)
INTRO_FADE_SYMBOLS = [
    "Intro_Scene24_ApplyPaletteFade.FadePals",
    "Intro_Scene20_AppearUnown.pal1",
    "Intro_Scene20_AppearUnown.pal2",
    "Intro_FadeUnownWordPals.FastFadePalettes",
    "Intro_FadeUnownWordPals.SlowFadePalettes",
]

# engine/movie/title.asm:364-374
TITLE_SYMBOLS = [
    "TitleSuicuneGFX",
    "TitleLogoGFX",
    "TitleCrystalGFX",
    "TitleScreenPalettes",
]

# engine/movie/splash.asm:344 -- replaces Gold's GameFreakLogoStarsGFX.
# The Ditto OBJ palette is a local label (engine/gfx/cgb_layouts.asm:876-893).
SPLASH_SYMBOLS = [
    "GameFreakDittoGFX",
    "GameFreakDittoPaletteFade",
    "_CGB_GamefreakLogo.GamefreakDittoPalette",
]

MOVIE_SYMBOLS = (
    INTRO_SYMBOLS + INTRO_FADE_SYMBOLS + TITLE_SYMBOLS + SPLASH_SYMBOLS)

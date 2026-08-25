"""REQUIRED_SYMBOLS delta between pokegold.sym and pokecrystal.sym.

make_gold_manifest.REQUIRED_SYMBOLS names 341 symbols by hand.  25 of them do
not exist in pokecrystal.sym: Crystal renamed the credits mons, split the
trainer-card / Pokegear / pack-pals blocks by player gender, split the two
FontsExtra tiles apart, and replaced the whole Gold/Silver intro movie and
title screen.  DROP_SYMBOLS lists those 25 and ADD_SYMBOLS the verified
replacements; the intro, title and splash names come from
crystal_movie_symbols.MOVIE_SYMBOLS (that file is the pinned CT-9 list and is
not edited here).  MOBILE_SYMBOLS is the Mobile System GB art, which no Gold
or Silver ROM carries at all.

Every name below was checked against ../pokecrystal-symbols/pokecrystal.sym.
"""

from __future__ import annotations

from crystal_movie_symbols import MOVIE_SYMBOLS

# Gold-only names, grouped by what replaces them.
DROP_SYMBOLS = frozenset({
    # engine/movie/title.asm:364-373 -- no tilemap; DrawTitleGraphic composes.
    "TitleScreenGFX1", "TitleScreenGFX2", "TitleScreenGFX3",
    "TitleScreenGFX4", "TitleScreenTilemap",
    # engine/movie/credits.asm:610-613
    "CreditsBellossomGFX", "CreditsTogepiGFX",
    "CreditsElekidGFX", "CreditsSentretGFX",
    # gfx/misc.asm:44
    "GameFreakLogoStarsGFX",
    # engine/gfx/player_gfx.asm:114,117,120,203,206
    "ChrisPicAndTrainerCardGFX",
    # engine/gfx/color.asm:1330,1333
    "PokegearPals",
    # engine/gfx/cgb_layouts.asm:818,821
    "_CGB_PackPals.PackPals",
    # gfx/font.asm:51,63
    "FontsExtra_SolidBlackAndUpArrowGFX",
    # engine/movie/intro.asm:1 -- CrystalIntro is a different program.
    "Intro_WaterGFX1", "Intro_WaterTilemap", "Intro_WaterMeta",
    "Intro_WaterGFX2",
    "Intro_GrassGFX1", "Intro_GrassTilemap", "Intro_GrassMeta",
    "Intro_GrassGFX2",
    "Intro_FireGFX1", "Intro_FireGFX2", "Intro_FireGFX3",
})

# Crystal replacements, minus the intro/title/splash ones MOVIE_SYMBOLS owns.
ADD_SYMBOLS = frozenset({
    # engine/movie/credits.asm:610-613
    "CreditsPichuGFX", "CreditsSmoochumGFX",
    "CreditsDittoGFX", "CreditsIgglybuffGFX",
    # engine/gfx/player_gfx.asm:114,117,120,203,206
    "ChrisCardPic", "KrisCardPic", "TrainerCardGFX", "ChrisPic", "KrisPic",
    # engine/gfx/color.asm:1330,1333
    "MalePokegearPals", "FemalePokegearPals",
    # engine/gfx/cgb_layouts.asm:818,821
    "_CGB_PackPals.ChrisPackPals", "_CGB_PackPals.KrisPackPals",
    # engine/events/fishing_gfx.asm:41 -- Kris' half of the fishing pose.
    "KrisFishingGFX",
    # gfx/font.asm:51,63 -- black is 1bpp at tile $60, up_arrow 2bpp at $61.
    "FontsExtra_SolidBlackGFX", "FontsExtra2_UpArrowGFX",
    # main.asm:425-448 -- the pic-animation pointer tables, absent from Gold.
    "AnimationPointers", "AnimationIdlePointers",
    "BitmasksPointers", "FramesPointers",
    "UnownAnimationPointers", "UnownAnimationIdlePointers",
    "UnownBitmasksPointers", "UnownFramesPointers",
    # engine/tilesets/tileset_anims.asm -- the five Crystal-only anim steps.
    "AnimateFountainTile",
    "ForestTreeLeftAnimation", "ForestTreeRightAnimation",
    "ForestTreeLeftAnimation2", "ForestTreeRightAnimation2",
    # engine/overworld/wildmons.asm:493-524 -- Raikou and Entei only.
    "InitRoamMons",
    # data/events/unown_walls.asm:7,15 -- the four Ruins of Alph wall words
    # and the menu box each one is drawn in.
    "UnownWalls", "MenuHeaders_UnownWalls",
    # data/battle_tower/classes.asm:6 and data/battle_tower/parties.asm:1 --
    # the Battle Tower roster, which no Gold or Silver ROM carries; the
    # sprites table is engine/events/battle_tower/battle_tower.asm:1578
    # INCLUDE "data/trainers/sprites.asm".
    "BattleTowerTrainers", "BattleTowerMons", "BTTrainerClassSprites",
    # data/battle_tower/unknown.asm:1, copied into wBT_OTTrainerData whole.
    "BattleTowerTrainerData",
    # engine/events/battle_tower/load_trainer.asm:24,112 -- the two rejection
    # loops whose `maskbits` / `cp` pair carries the sample ceiling.  Crystal
    # 1.0 and 1.1 differ only in the trainer one (:29-37), so it is read out
    # of the cart rather than written down.
    "LoadOpponentTrainerAndPokemon.resample",
    "LoadRandomBattleTowerMon.resample",
})

# Mobile System GB art, all of it present in the international v1.0 object:
# mobile/*.asm assembles there, only the menus that reach it are Japan-only.
MOBILE_SYMBOLS = frozenset({
    # mobile/mobile_5c.asm:290,293,296,753,756-771,866,874,878
    "AsciiFontGFX", "PichuAnimatedMobileGFX", "ElectroBallMobileGFX",
    "PichuBorderMobileGFX", "Stadium2N64GFX", "Stadium2N64Tilemap",
    "Stadium2N64Attrmap", "PasswordTopTilemap", "PasswordBottomTilemap",
    "PasswordShiftTilemap", "ChooseMobileCenterTilemap",
    "MobilePasswordAttrmap", "ChooseMobileCenterAttrmap",
    "MobilePasswordPalettes",
    # mobile/mobile_5e.asm:2,5,8,11,14,18,925,928,931,934,941
    "MobileCardGFX", "ChrisSilhouetteGFX", "KrisSilhouetteGFX",
    "MobileCard2GFX", "CardLargeSpriteAndFolderGFX", "CardSpriteGFX",
    "DialpadTilemap", "DialpadAttrmap", "DialpadGFX", "DialpadCursorGFX",
    "MobileCardListGFX",
    # mobile/mobile_5f.asm:84,87,91,3528,3534,3537
    "HaveWantGFX", "MobileSelectGFX", "HaveWantMap", "PokemonNewsGFX",
    "PokemonNewsTileAttrmap", "PokemonNewsPalettes",
    # mobile/mobile_5b.asm:206,209,212,215,758
    "MobileSystemSplashScreen_InitGFX.Tiles",
    "MobileSystemSplashScreen_InitGFX.Tilemap",
    "MobileSystemSplashScreen_InitGFX.Attrmap",
    "MobileSplashScreenPalettes", "MobileAdapterCheckGFX",
    # mobile/mobile_42.asm:1733-1763 and mobile/mobile_40.asm:6921,6924
    "MobileTradeSpritesGFX", "MobileTradeGFX", "MobileTradeTilemapLZ",
    "MobileTradeAttrmapLZ", "MobileCable1GFX", "MobileCable2GFX",
    "UnusedMobilePulsePalettes", "MobileTradeBGPalettes",
    "MobileTradeOB1Palettes", "MobileTradeOB2Palettes",
    "MobileAdapterPalettes", "MobileTradeLightsGFX",
    "MobileTradeLightsPalettes",
    # mobile/mobile_45_2.asm:1362,1365,1368 and
    # mobile/mobile_45_sprite_engine.asm:311
    "PichuBorderMobileOBPalettes", "PichuBorderMobileBGPalettes",
    "PichuBorderMobileTilemapAttrmap", "MobileDialingGFX",
    # mobile/mobile_12.asm:1007,1010, mobile/mobile_22.asm:518,
    # mobile/mobile_41.asm:1115, mobile/fixed_words.asm:3231
    "MobileUpArrowGFX", "MobileDownArrowGFX", "EZChatCursorGFX",
    "MobileDialingFrameGFX", "SelectStartGFX",
    # engine/menus/main_menu.asm:24 and gfx/font.asm:58
    "MobileMenuGFX", "MobilePhoneTilesGFX",
    # engine/link/mystery_gift.asm:1606,1920,1923
    "MysteryGiftGFX", "CardTradeGFX", "CardTradeSpriteGFX",
})


def crystal_required(gold_required):
    """Apply the delta to make_gold_manifest.REQUIRED_SYMBOLS."""
    gold = frozenset(gold_required)
    stale = sorted(DROP_SYMBOLS - gold)
    if stale:
        raise SystemExit(
            "crystal_symbol_deltas: DROP_SYMBOLS names that Gold no longer "
            "requires: " + ", ".join(stale))
    extra = ADD_SYMBOLS | MOBILE_SYMBOLS | set(MOVIE_SYMBOLS)
    collisions = sorted(extra & gold)
    if collisions:
        raise SystemExit(
            "crystal_symbol_deltas: ADD names already in the Gold set: "
            + ", ".join(collisions))
    return frozenset((gold - DROP_SYMBOLS) | extra)

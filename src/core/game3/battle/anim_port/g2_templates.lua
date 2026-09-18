local P = require("src.core.game3.battle.anim_port.g2_pret")
local F, J, L, E = P.F, P.J, P.L, P.END
local A, AJ, AL, AE = P.A, P.AJ, P.AL, P.AEND
local T = {}
T.gAbsorptionOrbSpriteTemplate = { tag = "ORBS", w = 16, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(8,1), E } }, affine = { { A(-5,-5,0,1), AJ(0) } }, cbName = "AbsorptionOrb" }
T.gAcidPoisonBubbleSpriteTemplate = { tag = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E } }, affine = { { A(352,352,0,0), A(-10,-10,0,10), A(10,10,0,10), AJ(0) } }, cbName = "AcidPoisonBubble" }
T.gAcidPoisonDropletSpriteTemplate = { tag = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(4,1), E } }, affine = { { A(-16,16,0,6), A(16,-16,0,6), AJ(0) } }, cbName = "AcidPoisonDroplet" }
T.gAirCutterSliceSpriteTemplate = { tag = "CUT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), E } }, affine = { { AE } }, cbName = "AirCutterSlice" }
T.gAirWaveCrescentSpriteTemplate = { tag = "AIR_WAVE_2", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(0,3,true,false), F(0,3,false,true), F(0,3,true,true), J(0) } }, affine = { { AE } }, cbName = "AirWaveCrescent" }
T.gAirWaveProjectileSpriteTemplate = { tag = "AIR_WAVE", w = 32, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "AirWaveProjectile" }
T.gAncientPowerRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(64,1), E }, { F(80,1), E } }, affine = { { AE } }, cbName = "RaiseSprite" }
T.gAngelSpriteTemplate = { tag = "ANGEL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,24), E } }, affine = { { AE } }, cbName = "Angel" }
T.gAngerMarkSpriteTemplate = { tag = "ANGER", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(11,11,0,8), A(-11,-11,0,8), AE } }, cbName = "AngerMark" }
T.gArmThrustHandSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "ArmThrustHit" }
T.gAromatherapyBigFlowerSpriteTemplate = { tag = "FLOWER", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(0,1), E } }, affine = { { A(256,256,0,0), A(0,0,4,1), AJ(1) } }, cbName = "FlyingParticle" }
T.gAromatherapySmallFlowerSpriteTemplate = { tag = "FLOWER", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(4,1), E } }, affine = { { AE } }, cbName = "FlyingParticle" }
T.gAssistPawprintSpriteTemplate = { tag = "PAW_PRINT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "AssistPawprint" }
T.gAuroraBeamRingSpriteTemplate = { tag = "RAINBOW_RINGS", w = 8, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E }, { F(4,1), E } }, affine = { { A(0,0,0,1), A(96,96,0,1), AE } }, cbName = "AuroraBeamRings" }
T.gBarrageBallSpriteTemplate = { tag = "RED_BALL", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,-4,24), AE }, { A(256,256,-64,0), A(0,0,4,24), AE } }, cbName = "SpriteCallbackDummy" }
T.gBarrierWallSpriteTemplate = { tag = "GRAY_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DefensiveWall" }
T.gBasicHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatBasic" }
T.gBatonPassPokeballSpriteTemplate = { tag = "POKEBALL", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BatonPassPokeball" }
T.gBellSpriteTemplate = { tag = "BELL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,6), F(16,6), F(32,15), F(16,6), F(0,6), F(16,6,true,false), F(32,15,true,false), F(16,6,true,false), F(0,6), F(16,6), F(32,15), F(16,6), F(0,6), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gBellyDrumHandSpriteTemplate = { tag = "PURPLE_HAND_OUTLINE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BellyDrumHand" }
T.gBentSpoonSpriteTemplate = { tag = "BENT_SPOON", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(8,60,true,false), F(16,5,true,false), F(8,5,true,false), F(0,5,true,false), F(8,22,true,false), L(0), F(16,5,true,false), F(8,5,true,false), F(0,5,true,false), F(8,5,true,false), L(1), F(8,22,true,false), F(24,3,true,false), F(32,3,true,false), F(40,22,true,false), E }, { F(8,60), F(16,5), F(8,5), F(0,5), F(8,22), L(0), F(16,5), F(8,5), F(0,5), F(8,5), L(1), F(8,22), F(24,3), F(32,3), F(40,22), E } }, affine = { { AE } }, cbName = "BentSpoon" }
T.gBlackBallSpriteTemplate = { tag = "BLACK_BALL", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ThrowProjectile" }
T.gBlackSmokeSpriteTemplate = { tag = "BLACK_SMOKE", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BlackSmoke" }
T.gBlendThinRingExpandingSpriteTemplate = { tag = "THIN_RING", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(16,16,0,30), AE }, { A(16,16,0,0), A(32,32,0,15), AE } }, cbName = "BlendThinRing" }
T.gBlizzardIceCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(8,1), E } }, affine = { { AE } }, cbName = "MoveParticleBeyondTarget" }
T.gBlockXSpriteTemplate = { tag = "X_SIGN", w = 64, h = 64, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BlockX" }
T.gBonemerangSpriteTemplate = { tag = "BONE", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,15,1), AJ(0) } }, cbName = "BonemerangProjectile" }
T.gBounceBallLandSpriteTemplate = { tag = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(160,256,0,0), AE } }, cbName = "BounceBallLand" }
T.gBounceBallShrinkSpriteTemplate = { tag = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-20,0,0,7), A(-20,-20,0,5), AE } }, cbName = "BounceBallShrink" }
T.gBreathPuffSpriteTemplate = { tag = "BREATH", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4,true,false), F(4,40,true,false), F(8,4,true,false), F(12,4,true,false), E }, { F(0,4), F(4,40), F(8,4), F(12,4), E } }, affine = { { AE } }, cbName = "BreathPuff" }
T.gBrickBreakWallShardSpriteTemplate = { tag = "TORN_METAL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BrickBreakWallShard" }
T.gBrickBreakWallSpriteTemplate = { tag = "BLUE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BrickBreakWall" }
T.gBulletSeedSpriteTemplate = { tag = "SEED", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,20,1), AJ(0) } }, cbName = "BulletSeed" }
T.gBurnFlameSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "BurnFlame" }
T.gClampJawSpriteTemplate = { tag = "CLAMP", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,1), AE }, { A(0,0,32,1), AE }, { A(0,0,64,1), AE }, { A(0,0,96,1), AE }, { A(0,0,-128,1), AE }, { A(0,0,-96,1), AE }, { A(0,0,-64,1), AE }, { A(0,0,-32,1), AE } }, cbName = "Bite" }
T.gClappingHand2SpriteTemplate = { tag = "TAG_HAND", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ClappingHand2" }
T.gClappingHandSpriteTemplate = { tag = "TAG_HAND", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ClappingHand" }
T.gClawSlashSpriteTemplate = { tag = "CLAW_SLASH", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), E }, { F(0,4,true,false), F(16,4,true,false), F(32,4,true,false), F(48,4,true,false), F(64,4,true,false), E } }, affine = { { AE } }, cbName = "ClawSlash" }
T.gCoinThrowSpriteTemplate = { tag = "COIN", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(8,1), E } }, affine = { { AE } }, cbName = "CoinThrow" }
T.gConfuseRayBallBounceSpriteTemplate = { tag = "YELLOW_BALL", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(30,30,10,5), A(-30,-30,10,5), AJ(0) } }, cbName = "ConfuseRayBallBounce" }
T.gConfuseRayBallSpiralSpriteTemplate = { tag = "YELLOW_BALL", w = 16, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ConfuseRayBallSpiral" }
T.gConfusionDuckSpriteTemplate = { tag = "DUCK", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,8), F(4,8), F(0,8,true,false), F(8,8), J(0) }, { F(0,8,true,false), F(4,8), F(0,8), F(8,8), J(0) } }, affine = { { AE } }, cbName = "ConfusionDuck" }
T.gConstrictBindingSpriteTemplate = { tag = "TENDRILS", w = 64, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,4), F(32,4), F(64,4), F(96,4), E }, { F(0,4,true,false), F(32,4,true,false), F(64,4,true,false), F(96,4,true,false), E } }, affine = { { A(256,256,0,0), A(-11,0,0,6), A(11,0,0,6), AE }, { A(-256,256,0,0), A(11,0,0,6), A(-11,0,0,6), AE } }, cbName = "ConstrictBinding" }
T.gConversion2SpriteTemplate = { tag = "CONVERSION", w = 8, h = 8, affineMode = 3, blend = true, priority = 2, anims = { { F(0,5), F(1,5), F(2,5), F(3,5), E } }, affine = { { A(512,512,0,0), AE } }, cbName = "Conversion2" }
T.gConversionSpriteTemplate = { tag = "CONVERSION", w = 8, h = 8, affineMode = 3, blend = true, priority = 2, anims = { { F(3,5), F(2,5), F(1,5), F(0,5), E } }, affine = { { A(512,512,0,0), AE } }, cbName = "Conversion" }
T.gCrossChopHandSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "CrossChopHand" }
T.gCrossImpactSpriteTemplate = { tag = "CROSS_IMPACT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "CrossImpact" }
T.gCurseGhostSpriteTemplate = { tag = "GHOSTLY_SPIRIT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "GhostStatusSprite" }
T.gCurseNailSpriteTemplate = { tag = "NAIL", w = 32, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "CurseNail" }
T.gCuttingSliceSpriteTemplate = { tag = "CUT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), E } }, affine = { { AE } }, cbName = "CuttingSlice" }
T.gDestinyBondWhiteShadowSpriteTemplate = { tag = "WHITE_SHADOW", w = 64, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DestinyBondWhiteShadow" }
T.gDevilSpriteTemplate = { tag = "DEVIL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), J(0) }, { F(16,3), J(0) } }, affine = { { AE } }, cbName = "Devil" }
T.gDirtMoundSpriteTemplate = { tag = "DIRT_MOUND", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DigDirtMound" }
T.gDirtPlumeSpriteTemplate = { tag = "MUD_SAND", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DirtPlumeParticle" }
T.gDiveBallSpriteTemplate = { tag = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-16,32,0,10), AE } }, cbName = "DiveBall" }
T.gDiveWaterSplashSpriteTemplate = { tag = "SPLASH", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DiveWaterSplash" }
T.gDizzyPunchDuckSpriteTemplate = { tag = "DUCK", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DizzyPunchDuck" }
T.gDragonBreathFireSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(16,3), F(32,3), F(48,3), J(0) }, { F(16,3,true,true), F(32,3,true,true), F(48,3,true,true), J(0) } }, affine = { { A(80,80,127,0), A(13,13,0,100), AE }, { A(80,80,0,0), A(13,13,0,100), AE } }, cbName = "DragonFireToTarget" }
T.gDragonDanceOrbSpriteTemplate = { tag = "HOLLOW_ORB", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DragonDanceOrb" }
T.gDragonRageFirePlumeSpriteTemplate = { tag = "FIRE_PLUME", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), F(64,5), E } }, affine = { { AE } }, cbName = "DragonRageFirePlume" }
T.gDragonRageFireSpitSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(16,3), F(32,3), F(48,3), J(0) }, { F(16,3), F(32,3), F(48,3), J(0) } }, affine = { { A(100,100,127,1), AE }, { A(100,100,0,1), AE } }, cbName = "DragonFireToTarget" }
T.gEclipsingOrbSpriteTemplate = { tag = "ECLIPSING_ORB", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(32,3,true,false), F(16,3,true,false), F(0,3,true,false), L(1), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gEggThrowSpriteTemplate = { tag = "LARGE_FRESH_EGG", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ThrowProjectile" }
T.gElectricChargingParticlesSpriteTemplate = { tag = "ELECTRIC_ORBS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(3,1), F(2,1), F(1,1), F(0,1), E }, { F(0,5), F(1,5), F(2,5), F(3,5), E } }, affine = { { AE } }, cbName = "SpriteCallbackDummy" }
T.gElectricPuffSpriteTemplate = { tag = "ELECTRICITY", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), E } }, affine = { { AE } }, cbName = "ElectricPuff" }
T.gElectricitySpriteTemplate = { tag = "SPARK_2", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "Electricity" }
T.gEllipticalGustSpriteTemplate = { tag = "GUST", w = 32, h = 64, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "EllipticalGust" }
T.gEmberFlareSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "EmberFlare" }
T.gEmberSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gEndureEnergySpriteTemplate = { tag = "FOCUS_ENERGY", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(8,12), F(16,4), F(24,4), E } }, affine = { { AE } }, cbName = "EndureEnergy" }
T.gEruptionFallingRockSpriteTemplate = { tag = "WARM_ROCK", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "EruptionFallingRock" }
T.gEruptionLaunchRockSpriteTemplate = { tag = "WARM_ROCK", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "EruptionLaunchRock" }
T.gExplosionSpriteTemplate = { tag = "EXPLOSION", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gEyeSparkleSpriteTemplate = { tag = "EYE_SPARKLE", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(4,4), F(8,4), F(4,4), F(0,4), E } }, affine = { { AE } }, cbName = "EyeSparkle" }
T.gFacadeSweatDropSpriteTemplate = { tag = "SWEAT_DROP", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "FacadeSweatDrop" }
T.gFallingCoinSpriteTemplate = { tag = "COIN", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(8,1), E } }, affine = { { A(0,0,10,1), AJ(0) } }, cbName = "FallingCoin" }
T.gFallingFeatherSpriteTemplate = { tag = "WHITE_FEATHER", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,0), E }, { F(16,0,true,false), E } }, affine = { { AE } }, cbName = "FallingFeather" }
T.gFallingRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(32,1), E }, { F(48,1), E }, { F(64,1), E } }, affine = { { AE } }, cbName = "FallingRock" }
T.gFalseSwipePositionedSliceSpriteTemplate = { tag = "SLASH_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), E }, { F(48,4), E } }, affine = { { AE } }, cbName = "FalseSwipePositionedSlice" }
T.gFalseSwipeSliceSpriteTemplate = { tag = "SLASH_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), E }, { F(48,4), E } }, affine = { { AE } }, cbName = "FalseSwipeSlice" }
T.gFangSpriteTemplate = { tag = "FANG_ATTACK", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(0,8), F(16,16), F(32,4), F(48,4), E } }, affine = { { A(512,512,0,0), A(-32,-32,0,8), AE } }, cbName = "Fang" }
T.gFastFlyingMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,10), E }, { F(4,10), E }, { F(8,41), E }, { F(12,10), E }, { F(16,10), E }, { F(20,10), E }, { F(0,10,false,true), E }, { F(4,10,false,true), E } }, affine = { { A(12,12,0,16), A(65524,65524,0,16), AJ(0) } }, cbName = "FlyingMusicNotes" }
T.gFireBlastCrossSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(32,6), F(48,6), J(0) } }, affine = { { AE } }, cbName = "FireCross" }
T.gFireBlastRingSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "FireRing" }
T.gFirePlumeSpriteTemplate = { tag = "FIRE_PLUME", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), F(64,5), J(0) } }, affine = { { AE } }, cbName = "FirePlume" }
T.gFireSpinSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "ParticleInVortex" }
T.gFireSpiralInwardSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,4), F(32,4), F(48,4), J(0) }, { F(16,4,true,true), F(32,4,true,true), F(48,4,true,true), J(0) } }, affine = { { AE } }, cbName = "FireSpiralInward" }
T.gFireSpiralOutwardSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "FireSpiralOutward" }
T.gFireSpreadSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,4), F(32,4), F(48,4), J(0) }, { F(16,4,true,true), F(32,4,true,true), F(48,4,true,true), J(0) } }, affine = { { AE } }, cbName = "FireSpread" }
T.gFistFootRandomPosSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "FistOrFootRandomPos" }
T.gFistFootSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "BasicFistOrFoot" }
T.gFlamethrowerFlameSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,2), F(32,2), F(48,2), J(0) } }, affine = { { AE } }, cbName = "ToTargetInSinWave" }
T.gFlashingHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "FlashingHitSplat" }
T.gFlatterConfettiSpriteTemplate = { tag = "CONFETTI", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "FlatterConfetti" }
T.gFlatterSpotlightSpriteTemplate = { tag = "SPOTLIGHT", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,384,0,0), A(16,0,0,20), AE }, { A(320,384,0,0), A(-16,0,0,19), AE } }, cbName = "FlatterSpotlight" }
T.gFlyBallAttackSpriteTemplate = { tag = "ROUND_SHADOW", w = 64, h = 64, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,50,1), AE }, { A(0,0,-40,1), AE } }, cbName = "FlyBallAttack" }
T.gFlyBallUpSpriteTemplate = { tag = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-16,32,0,10), AE } }, cbName = "FlyBallUp" }
T.gFlyingSandCrescentSpriteTemplate = { tag = "FLYING_DIRT", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "FlyingSandCrescent" }
T.gFocusPunchFistSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { A(512,512,0,0), A(-32,-32,0,8), AE } }, cbName = "FocusPunchFist" }
T.gFollowMeFingerSpriteTemplate = { tag = "FINGER", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(30,30,0,8), AE }, { A(0,0,4,11), A(0,0,-4,11), AL(2), A(-30,-30,0,8), AE } }, cbName = "FollowMeFinger" }
T.gForesightMagnifyingGlassSpriteTemplate = { tag = "MAGNIFYING_GLASS", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ForesightMagnifyingGlass" }
T.gFrenzyPlantRootSpriteTemplate = { tag = "ROOTS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,7), F(16,7), F(32,7), F(48,7), E }, { F(0,7,true,false), F(16,7,true,false), F(32,7,true,false), F(48,7,true,false), E }, { F(0,7), F(16,7), F(32,7), E }, { F(0,7,true,false), F(16,7,true,false), F(32,7,true,false), E } }, affine = { { AE } }, cbName = "FrenzyPlantRoot" }
T.gFurySwipesSpriteTemplate = { tag = "SWIPE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), E }, { F(0,4,true,false), F(16,4,true,false), F(32,4,true,false), F(48,4,true,false), E } }, affine = { { AE } }, cbName = "FurySwipes" }
T.gGlareEyeDotSpriteTemplate = { tag = "SMALL_RED_EYE", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "GlareEyeDot" }
T.gGoldRingSpriteTemplate = { tag = "GOLD_RING", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gGrantingStarsSpriteTemplate = { tag = "SPARKLE_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,7), F(16,7), F(32,7), F(48,7), F(64,7), F(80,7), F(96,7), F(112,7), J(0) } }, affine = { { AE } }, cbName = "GrantingStars" }
T.gGreenStarSpriteTemplate = { tag = "GREEN_STAR", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,6), F(4,6), J(0) }, { F(8,6), E }, { F(12,6), E } }, affine = { { AE } }, cbName = "GreenStar" }
T.gGrowingChargeOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(4,4,0,60), A(256,256,0,0), AL(0), A(-4,-4,0,5), A(4,4,0,5), AL(10), AE }, { A(16,16,0,0), A(8,8,0,30), A(256,256,0,0), A(-4,-4,0,5), A(4,4,0,5), AJ(3) }, { A(16,16,0,0), A(8,8,0,30), A(-8,-8,0,30), AE } }, cbName = "GrowingChargeOrb" }
T.gGrowingShockWaveOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(4,4,0,60), A(256,256,0,0), AL(0), A(-4,-4,0,5), A(4,4,0,5), AL(10), AE }, { A(16,16,0,0), A(8,8,0,30), A(256,256,0,0), A(-4,-4,0,5), A(4,4,0,5), AJ(3) }, { A(16,16,0,0), A(8,8,0,30), A(-8,-8,0,30), AE } }, cbName = "GrowingShockWaveOrb" }
T.gGrudgeFlameSpriteTemplate = { tag = "PURPLE_FLAME", w = 16, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,4), F(8,4), F(16,4), F(24,4), J(0) } }, affine = { { AE } }, cbName = "GrudgeFlame" }
T.gGuardRingSpriteTemplate = { tag = "GUARD_RING", w = 64, h = 32, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), AE }, { A(512,256,0,0), AE } }, cbName = "GuardRing" }
T.gGuillotineSpriteTemplate = { tag = "CUT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,2), F(16,2), F(32,1), E }, { F(0,2,true,true), F(16,2,true,true), F(32,1,true,true), E } }, affine = { { AE } }, cbName = "GuillotinePincer" }
T.gGustToTargetSpriteTemplate = { tag = "GUST", w = 32, h = 64, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(10,0,0,24), AE } }, cbName = "GustToTarget" }
T.gHandleInvertHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatHandleInvert" }
T.gHealBellMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "HealBellMusicNote" }
T.gHealingBlueStarSpriteTemplate = { tag = "BLUE_STAR", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2), F(16,2), F(32,2), F(48,3), F(64,5), F(80,3), F(96,2), F(0,2), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gHelpingHandClapSpriteTemplate = { tag = "TAG_HAND", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "HelpingHandClap" }
T.gHiddenPowerOrbScatterSpriteTemplate = { tag = "RED_ORB", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(128,128,0,0), A(8,8,0,1), AJ(1) } }, cbName = "OrbitScatter" }
T.gHiddenPowerOrbSpriteTemplate = { tag = "RED_ORB", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(128,128,0,0), A(8,8,0,1), AJ(1) } }, cbName = "OrbitFast" }
T.gHornHitSpriteTemplate = { tag = "HORN_HIT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "HornHit" }
T.gHydroCannonBeamSpriteTemplate = { tag = "WATER_ORB", w = 16, h = 16, affineMode = 3, blend = true, priority = 2, anims = { { F(0,1), F(4,1), F(8,1), F(12,1), J(0) } }, affine = { { A(336,336,0,0), AE } }, cbName = "HydroCannonBeam" }
T.gHydroCannonChargeSpriteTemplate = { tag = "WATER_ORB", w = 16, h = 16, affineMode = 3, blend = true, priority = 2, anims = { { F(0,1), F(4,1), F(8,1), F(12,1), J(0) } }, affine = { { A(3,3,10,50), A(0,0,0,10), A(-20,-20,-10,20), AE } }, cbName = "HydroCannonCharge" }
T.gHydroPumpOrbSpriteTemplate = { tag = "WATER_ORB", w = 16, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,1), F(4,1), F(8,1), F(12,1), J(0) } }, affine = { { AE } }, cbName = "ToTargetInSinWave" }
T.gHyperBeamOrbSpriteTemplate = { tag = "ORBS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(1,1), E }, { F(2,1), E }, { F(3,1), E }, { F(4,1), E }, { F(5,1), E }, { F(6,1), E } }, affine = { { AE } }, cbName = "HyperBeamOrb" }
T.gHyperVoiceRingSpriteTemplate = { tag = "THIN_RING", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(11,11,0,45), AE } }, cbName = "HyperVoiceRing" }
T.gIceBallChunkSpriteTemplate = { tag = "ICE_CHUNK", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,4), F(32,4), F(48,4), F(64,4), E } }, affine = { { A(224,224,0,0), AE }, { A(280,280,0,0), AE }, { A(336,336,0,0), AE }, { A(384,384,0,0), AE }, { A(448,448,0,0), AE } }, cbName = "InitIceBallAnim" }
T.gIceBallImpactShardSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(6,1), E } }, affine = { { AE } }, cbName = "InitIceBallParticle" }
T.gIceBeamInnerCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(4,1), E } }, affine = { { A(0,0,10,1), AJ(0) } }, cbName = "IceBeamParticle" }
T.gIceBeamOuterCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = true, priority = 2, anims = { { F(6,1), E } }, affine = { { AE } }, cbName = "IceBeamParticle" }
T.gIceCrystalHitLargeSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(4,1), E } }, affine = { { A(206,206,0,0), A(5,5,0,10), A(0,0,0,6), AE } }, cbName = "IceEffectParticle" }
T.gIceCrystalHitSmallSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 1, blend = true, priority = 2, anims = { { F(6,1), E } }, affine = { { A(206,206,0,0), A(5,5,0,10), A(0,0,0,6), AE } }, cbName = "IceEffectParticle" }
T.gIceCrystalSpiralInwardLarge = { tag = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 3, blend = true, priority = 2, anims = { { F(4,1), E } }, affine = { { A(0,0,40,1), AJ(0) } }, cbName = "IcePunchSwirlingParticle" }
T.gIceCrystalSpiralInwardSmall = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = true, priority = 2, anims = { { F(6,1), E } }, affine = { { AE } }, cbName = "IcePunchSwirlingParticle" }
T.gIceGroundSpikeSpriteTemplate = { tag = "ICE_SPIKES", w = 8, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,5), F(2,5), F(4,5), F(6,5), F(4,5), F(2,5), F(0,5), E } }, affine = { { AE } }, cbName = "WaveFromCenterOfTarget" }
T.gIcicleSpearSpriteTemplate = { tag = "ICICLE_SPEAR", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MissileArc" }
T.gIngrainOrbSpriteTemplate = { tag = "ORBS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(3,3), F(0,5), J(0) } }, affine = { { AE } }, cbName = "IngrainOrb" }
T.gIngrainRootSpriteTemplate = { tag = "ROOTS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,7), F(16,7), F(32,7), F(48,7), E }, { F(0,7,true,false), F(16,7,true,false), F(32,7,true,false), F(48,7,true,false), E }, { F(0,7), F(16,7), F(32,7), E }, { F(0,7,true,false), F(16,7,true,false), F(32,7,true,false), E } }, affine = { { AE } }, cbName = "IngrainRoot" }
T.gItemStealSpriteTemplate = { tag = "ITEM_BAG", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,30), E } }, affine = { { A(0,0,-4,10), A(0,0,4,20), A(0,0,-4,10), AE }, { A(0,0,-1,2), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,2), AE } }, cbName = "ItemSteal" }
T.gJaggedMusicNoteSpriteTemplate = { tag = "JAGGED_MUSIC_NOTE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "JaggedMusicNote" }
T.gJumpKickSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "JumpKick" }
T.gKarateChopSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "SlideHandOrFootToTarget" }
T.gKinesisZapEnergySpriteTemplate = { tag = "ALERT", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3,true,false), F(8,3,true,false), F(16,3,true,false), F(24,3,true,false), F(32,3,true,false), F(40,3,true,false), F(48,3,true,false), L(1), E } }, affine = { { AE } }, cbName = "KinesisZapEnergy" }
T.gKnockOffItemSpriteTemplate = { tag = "ITEM_BAG", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,30), E } }, affine = { { A(0,0,-4,10), A(0,0,4,20), A(0,0,-4,10), AE }, { A(0,0,-1,2), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,2), AE } }, cbName = "KnockOffItem" }
T.gKnockOffStrikeSpriteTemplate = { tag = "SLAM_HIT_2", w = 64, h = 64, affineMode = 1, blend = false, priority = 2, anims = { { F(0,4), F(64,4), E } }, affine = { { A(256,256,0,0), A(0,0,-4,8), AE }, { A(-256,256,0,0), A(0,0,4,8), AE } }, cbName = "KnockOffStrike" }
T.gLargeFlameScatterSpriteTemplate = { tag = "FIRE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), F(80,3), F(96,3), F(112,3), J(0) } }, affine = { { AE } }, cbName = "LargeFlame" }
T.gLargeFlameSpriteTemplate = { tag = "FIRE", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), F(80,3), F(96,3), F(112,3), J(0) } }, affine = { { A(50,256,0,0), A(32,0,0,7), AE } }, cbName = "LargeFlame" }
T.gLeafBladeSpriteTemplate = { tag = "LEAF", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(28,1), E }, { F(32,1), E }, { F(20,1), E }, { F(28,1,true,false), E }, { F(16,1), E }, { F(16,1,true,false), E }, { F(28,1), E } }, affine = { { AE } }, cbName = "SpriteCallbackDummy" }
T.gLeechLifeNeedleSpriteTemplate = { tag = "NEEDLE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,-33,1), AE }, { A(0,0,96,1), AE }, { A(0,0,-96,1), AE } }, cbName = "LeechLifeNeedle" }
T.gLeechSeedSpriteTemplate = { tag = "SEED", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(4,7), F(8,7), J(0) } }, affine = { { AE } }, cbName = "LeechSeed" }
T.gLeerSpriteTemplate = { tag = "LEER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), E } }, affine = { { AE } }, cbName = "Leer" }
T.gLetterZSpriteTemplate = { tag = "LETTER_Z", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,3), E } }, affine = { { A(-7,-7,-3,16), A(7,7,3,16), AJ(0) } }, cbName = "LetterZ" }
T.gLickSpriteTemplate = { tag = "LICK", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2), F(8,2), F(16,2), F(24,2), F(32,2), E } }, affine = { { AE } }, cbName = "Lick" }
T.gLightScreenWallSpriteTemplate = { tag = "GREEN_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DefensiveWall" }
T.gLightningSpriteTemplate = { tag = "LIGHTNING", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,8), F(48,5), F(64,5), E } }, affine = { { AE } }, cbName = "Lightning" }
T.gLinearStingerSpriteTemplate = { tag = "NEEDLE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateStinger" }
T.gLockOnMoveTargetSpriteTemplate = { tag = "LOCK_ON", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "LockOnMoveTarget" }
T.gLockOnTargetSpriteTemplate = { tag = "LOCK_ON", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "LockOnTarget" }
T.gLusterPurgeCircleSpriteTemplate = { tag = "WHITE_CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(4,4,0,120), AE } }, cbName = "SpriteOnMonPos" }
T.gMagentaHeartSpriteTemplate = { tag = "MAGENTA_HEART", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MagentaHeart" }
T.gMagicCoatWallSpriteTemplate = { tag = "ORANGE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DefensiveWall" }
T.gMeanLookEyeSpriteTemplate = { tag = "EYE", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(384,384,0,0), A(-32,24,0,5), A(24,-32,0,5), AJ(1) }, { A(48,48,0,0), A(32,32,0,6), AE } }, cbName = "MeanLookEye" }
T.gMegaPunchKickSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { A(256,256,0,0), A(-4,-4,20,1), AJ(1) } }, cbName = "SpinningKickOrPunch" }
T.gMegahornHornSpriteTemplate = { tag = "HORN_HIT_2", w = 32, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(256,256,30,0), AE }, { A(256,256,-99,0), AE }, { A(256,256,94,0), AE } }, cbName = "MegahornHorn" }
T.gMetalSoundSpriteTemplate = { tag = "METAL_SOUND_WAVES", w = 32, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(7,7,0,-56), AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gMeteorMashStarSpriteTemplate = { tag = "GOLD_STARS", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MeteorMashStar" }
T.gMetronomeFingerSpriteTemplate = { tag = "FINGER", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(30,30,0,8), AE }, { A(0,0,4,11), A(0,0,-4,11), AL(2), A(-30,-30,0,8), AE } }, cbName = "MetronomeFinger" }
T.gMilkBottleSpriteTemplate = { tag = "MILK_BOTTLE", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), AE }, { A(0,0,2,12), A(0,0,0,6), A(0,0,-2,24), A(0,0,0,6), A(0,0,2,12), AJ(0) } }, cbName = "MilkBottle" }
T.gMimicOrbSpriteTemplate = { tag = "ORBS", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(8,1), E } }, affine = { { A(0,0,0,0), A(48,48,0,14), AE }, { A(-16,-16,0,1), AJ(0) } }, cbName = "MimicOrb" }
T.gMiniTwinklingStarSpriteTemplate = { tag = "GOLD_STARS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MiniTwinklingStar" }
T.gMirrorCoatWallSpriteTemplate = { tag = "RED_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DefensiveWall" }
T.gMistBallSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ThrowMistBall" }
T.gMistCloudSpriteTemplate = { tag = "MIST_CLOUD", w = 32, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,8), F(8,8), J(0) } }, affine = { { AE } }, cbName = "InitSwirlingFogAnim" }
T.gMonEdgeHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatOnMonEdge" }
T.gMoonSpriteTemplate = { tag = "MOON", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "Moon" }
T.gMoonlightSparkleSpriteTemplate = { tag = "GREEN_SPARKLE", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,8), F(4,8), F(8,8), F(12,8), J(0) } }, affine = { { AE } }, cbName = "MoonlightSparkle" }
T.gMovementWavesSpriteTemplate = { tag = "MOVEMENT_WAVES", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,8), F(16,8), F(32,8), F(16,8), E }, { F(16,8,true,false), F(32,8,true,false), F(16,8,true,false), F(0,8,true,false), E } }, affine = { { AE } }, cbName = "MovementWaves" }
T.gMudShotOrbSpriteTemplate = { tag = "BROWN_ORB", w = 16, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,1), F(4,1), F(8,1), F(12,1), J(0) } }, affine = { { AE } }, cbName = "ToTargetInSinWave" }
T.gMudSlapMudSpriteTemplate = { tag = "MUD_SAND", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(1,1), E } }, affine = { { AE } }, cbName = "DirtScatter" }
T.gMudsportMudSpriteTemplate = { tag = "MUD_SAND", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MudSportDirt" }
T.gNeedleArmSpikeSpriteTemplate = { tag = "GREEN_SPIKE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "NeedleArmSpike" }
T.gNightmareDevilSpriteTemplate = { tag = "DEVIL", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "GhostStatusSprite" }
T.gOctazookaBallSpriteTemplate = { tag = "BLACK_BALL", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gOctazookaSmokeSpriteTemplate = { tag = "GRAY_SMOKE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gOpeningEyeSpriteTemplate = { tag = "OPENING_EYE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,40), F(16,8), F(32,40), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gOutrageFlameSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "OutrageFlame" }
T.gOverheatFlameSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "OverheatFlame" }
T.gPainSplitProjectileSpriteTemplate = { tag = "PAIN_SPLIT", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(4,9), F(8,5), E } }, affine = { { AE } }, cbName = "PainSplitProjectile" }
T.gPencilSpriteTemplate = { tag = "PENCIL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "Pencil" }
T.gPerishSongMusicNote2SpriteTemplate = { tag = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(0,10), E }, { F(4,10), E }, { F(8,41), E }, { F(12,10), E }, { F(16,10), E }, { F(20,10), E }, { F(0,10,false,true), E }, { F(4,10,false,true), E } }, affine = { { A(0,0,0,5), AE }, { A(0,0,-8,16), AE }, { A(0,0,8,16), AE } }, cbName = "PerishSongMusicNote2" }
T.gPerishSongMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(0,10), E }, { F(4,10), E }, { F(8,41), E }, { F(12,10), E }, { F(16,10), E }, { F(20,10), E }, { F(0,10,false,true), E }, { F(4,10,false,true), E } }, affine = { { A(0,0,0,5), AE }, { A(0,0,-8,16), AE }, { A(0,0,8,16), AE } }, cbName = "PerishSongMusicNote" }
T.gPersistHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatPersistent" }
T.gPetalDanceBigFlowerSpriteTemplate = { tag = "FLOWER", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E } }, affine = { { AE } }, cbName = "PetalDanceBigFlower" }
T.gPetalDanceSmallFlowerSpriteTemplate = { tag = "FLOWER", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(4,1), E } }, affine = { { AE } }, cbName = "PetalDanceSmallFlower" }
T.gPinMissileSpriteTemplate = { tag = "NEEDLE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "MissileArc" }
T.gPinkHeartSpriteTemplate = { tag = "PINK_HEART", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "PinkHeart" }
T.gPoisonBubbleSpriteTemplate = { tag = "POISON_BUBBLE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(0,1), E } }, affine = { { A(156,156,0,0), A(5,5,0,20), AE } }, cbName = "BubbleEffect" }
T.gPoisonGasCloudSpriteTemplate = { tag = "PURPLE_GAS_CLOUD", w = 32, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,8), F(8,8), J(0) } }, affine = { { AE } }, cbName = "InitPoisonGasCloudAnim" }
T.gPoisonPowderParticleSpriteTemplate = { tag = "POISON_POWDER", w = 8, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(2,5), F(4,5), F(6,5), F(8,5), F(10,5), F(12,5), F(14,5), J(0) } }, affine = { { AE } }, cbName = "MovePowderParticle" }
T.gPowderSnowSnowballSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(7,1), E } }, affine = { { AE } }, cbName = "MoveParticleBeyondTarget" }
T.gPowerAbsorptionOrbSpriteTemplate = { tag = "ORBS", w = 16, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(8,1), E } }, affine = { { A(-5,-5,0,1), AJ(0) } }, cbName = "PowerAbsorptionOrb" }
T.gPresentHealParticleSpriteTemplate = { tag = "GREEN_SPARKLE", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(4,4), F(8,4), F(12,4), E } }, affine = { { AE } }, cbName = "PresentHealParticle" }
T.gPresentSpriteTemplate = { tag = "ITEM_BAG", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,30), E } }, affine = { { A(0,0,-4,10), A(0,0,4,20), A(0,0,-4,10), AE }, { A(0,0,-1,2), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,2), AE } }, cbName = "Present" }
T.gProtectSpriteTemplate = { tag = "PROTECT", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "Protect" }
T.gPsychUpSpiralSpriteTemplate = { tag = "SPIRAL", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), A(-2,-2,-10,120), AE } }, cbName = "SpriteOnMonPos" }
T.gPsychoBoostOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(16,16,0,17), AL(0), A(-8,-8,0,10), A(8,8,0,10), AL(4), AL(0), A(-16,-16,0,5), A(16,16,0,5), AL(7), AE }, { A(-20,24,0,15), AE } }, cbName = "PsychoBoost" }
T.gPsywaveRingSpriteTemplate = { tag = "BLUE_RING", w = 16, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(7,7,0,-56), AE } }, cbName = "ToTargetInSinWave" }
T.gQuestionMarkSpriteTemplate = { tag = "AMNESIA", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,6), F(16,6), F(32,6), F(48,6), F(64,6), F(80,6), F(96,18), E } }, affine = { { AE } }, cbName = "QuestionMark" }
T.gRainDropSpriteTemplate = { tag = "RAIN_DROPS", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2), F(8,2), F(16,2), F(24,6), F(32,2), F(40,2), F(48,2), E } }, affine = { { AE } }, cbName = "RainDrop" }
T.gRandomPosHitSplatSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatRandom" }
T.gRapidSpinSpriteTemplate = { tag = "RAPID_SPIN", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2), F(8,2), F(16,2), J(0) } }, affine = { { AE } }, cbName = "RapidSpin" }
T.gRazorLeafCutterSpriteTemplate = { tag = "RAZOR_LEAF", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(0,3,true,false), F(0,3,true,true), F(0,3,false,true), J(0) } }, affine = { { AE } }, cbName = "TranslateLinearSingleSineWave" }
T.gRazorLeafParticleSpriteTemplate = { tag = "LEAF", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(4,5), F(8,5), F(12,5), F(16,5), F(20,5), F(16,5), F(12,5), F(8,5), F(4,5), J(0) }, { F(24,5), F(28,5), F(32,5), E } }, affine = { { AE } }, cbName = "RazorLeafParticle" }
T.gRazorWindTornadoSpriteTemplate = { tag = "GUST", w = 32, h = 64, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(4,0,0,40), AE } }, cbName = "RazorWindTornado" }
T.gRecycleSpriteTemplate = { tag = "RECYCLE", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,-4,64), AJ(0) } }, cbName = "Recycle" }
T.gRedHeartBurstSpriteTemplate = { tag = "RED_HEART", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ParticleBurst" }
T.gRedHeartProjectileSpriteTemplate = { tag = "RED_HEART", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "RedHeartProjectile" }
T.gRedHeartRisingSpriteTemplate = { tag = "RED_HEART", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "RedHeartRising" }
T.gRedXSpriteTemplate = { tag = "X_SIGN", w = 64, h = 64, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "RedX" }
T.gReflectSparkleSpriteTemplate = { tag = "SPARKLE_4", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), E } }, affine = { { AE } }, cbName = "WallSparkle" }
T.gReflectWallSpriteTemplate = { tag = "BLUE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DefensiveWall" }
T.gRevengeBigScratchSpriteTemplate = { tag = "PURPLE_SWIPE", w = 64, h = 64, affineMode = 0, blend = false, priority = 2, anims = { { F(0,6), F(64,6), E }, { F(0,6,true,true), F(64,6,true,true), E }, { F(0,6,true,false), F(64,6,true,false), E } }, affine = { { AE } }, cbName = "RevengeScratch" }
T.gRevengeSmallScratchSpriteTemplate = { tag = "PURPLE_SCRATCH", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), E }, { F(0,4,false,true), F(16,4,false,true), F(32,4,false,true), E }, { F(0,4,true,false), F(16,4,true,false), F(32,4,true,false), E } }, affine = { { AE } }, cbName = "RevengeScratch" }
T.gReversalOrbSpriteTemplate = { tag = "BLUE_ORB", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ReversalOrb" }
T.gRoarNoiseLineSpriteTemplate = { tag = "NOISE_LINE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), J(0) }, { F(32,3), F(48,3), J(0) } }, affine = { { AE } }, cbName = "RoarNoiseLine" }
T.gRockBlastRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(64,1), E }, { F(80,1), E } }, affine = { { A(0,0,-5,5), AJ(0) }, { A(0,0,5,5), AJ(0) } }, cbName = "RockBlastRock" }
T.gRockFragmentSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(32,1), E }, { F(48,1), E }, { F(64,1), E } }, affine = { { AE } }, cbName = "RockFragment" }
T.gRockScatterSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(64,1), E }, { F(80,1), E } }, affine = { { A(0,0,-5,5), AJ(0) }, { A(0,0,5,5), AJ(0) } }, cbName = "RockScatter" }
T.gRockTombRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(64,1), E }, { F(80,1), E } }, affine = { { AE } }, cbName = "RockTomb" }
T.gRolloutMudSpriteTemplate = { tag = "MUD_SAND", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "RolloutParticle" }
T.gRolloutRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "RolloutParticle" }
T.gSafariBaitSpriteTemplate = { tag = "SAFARI_BAIT", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SpriteCB_SafariBaitOrRock_Init" }
T.gSafariRockTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(64,1), E } }, affine = { { AE } }, cbName = "SpriteCB_SafariBaitOrRock_Init" }
T.gSandAttackDirtSpriteTemplate = { tag = "MUD_SAND", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "DirtScatter" }
T.gScratchSpriteTemplate = { tag = "SCRATCH", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gScreechRingSpriteTemplate = { tag = "PURPLE_RING", w = 16, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(7,7,0,-56), AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gShadowBallSpriteTemplate = { tag = "SHADOW_BALL", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,10,1), AJ(0) } }, cbName = "ShadowBall" }
T.gSharpTeethSpriteTemplate = { tag = "SHARP_TEETH", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,1), AE }, { A(0,0,32,1), AE }, { A(0,0,64,1), AE }, { A(0,0,96,1), AE }, { A(0,0,-128,1), AE }, { A(0,0,-96,1), AE }, { A(0,0,-64,1), AE }, { A(0,0,-32,1), AE } }, cbName = "Bite" }
T.gSharpenSphereSpriteTemplate = { tag = "SPHERE_TO_CUBE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,18), F(0,6), F(16,18), F(0,6), F(16,6), F(32,18), F(16,6), F(32,6), F(48,18), F(32,6), F(48,6), F(64,18), F(48,6), F(64,54), E } }, affine = { { AE } }, cbName = "SharpenSphere" }
T.gSignalBeamGreenOrbSpriteTemplate = { tag = "GLOWY_GREEN_ORB", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ToTargetInSinWave" }
T.gSignalBeamRedOrbSpriteTemplate = { tag = "GLOWY_RED_ORB", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ToTargetInSinWave" }
T.gSilverWindBigSparkSpriteTemplate = { tag = "SPARKLE_6", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), A(0,0,-10,1), AJ(1) } }, cbName = "FlyingParticle" }
T.gSilverWindMediumSparkSpriteTemplate = { tag = "SPARKLE_6", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(192,192,0,0), A(0,0,-12,1), AJ(1) } }, cbName = "FlyingParticle" }
T.gSilverWindSmallSparkSpriteTemplate = { tag = "SPARKLE_6", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(143,143,0,0), A(0,0,-15,1), AJ(1) } }, cbName = "FlyingParticle" }
T.gSkyAttackBirdSpriteTemplate = { tag = "BIRD", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SkyAttackBird" }
T.gSlamHitSpriteTemplate = { tag = "SLAM_HIT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(64,3), F(80,3), F(96,3), F(112,6), E }, { F(64,3,true,false), F(80,3,true,false), F(96,3,true,false), F(112,6,true,false), E } }, affine = { { AE } }, cbName = "WhipHit" }
T.gSlashSliceSpriteTemplate = { tag = "SLASH", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), E }, { F(48,4), E } }, affine = { { AE } }, cbName = "SlashSlice" }
T.gSleepLetterZSpriteTemplate = { tag = "LETTER_Z", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,40), E } }, affine = { { A(20,20,-30,0), A(8,8,1,24), AE }, { A(20,20,30,0), A(8,8,-1,24), AE } }, cbName = "SleepLetterZ" }
T.gSleepPowderParticleSpriteTemplate = { tag = "SLEEP_POWDER", w = 8, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(2,5), F(4,5), F(6,5), F(8,5), F(10,5), F(12,5), F(14,5), J(0) } }, affine = { { AE } }, cbName = "MovePowderParticle" }
T.gSlidingKickSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "SlidingKick" }
T.gSlowFlyingMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,10), E }, { F(4,10), E }, { F(8,41), E }, { F(12,10), E }, { F(16,10), E }, { F(20,10), E }, { F(0,10,false,true), E }, { F(4,10,false,true), E } }, affine = { { A(160,160,0,0), A(4,4,0,1), AJ(1) } }, cbName = "SlowFlyingMusicNotes" }
T.gSludgeBombHitParticleSpriteTemplate = { tag = "POISON_BUBBLE", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(8,1), E } }, affine = { { A(236,236,0,0), AE } }, cbName = "SludgeBombHitParticle" }
T.gSludgeProjectileSpriteTemplate = { tag = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E } }, affine = { { A(352,352,0,0), A(-10,-10,0,10), A(10,10,0,10), AJ(0) } }, cbName = "SludgeProjectile" }
T.gSmallBubblePairSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(12,6), F(13,6), J(0) } }, affine = { { AE } }, cbName = "SmallBubblePair" }
T.gSmallDriftingBubblesSpriteTemplate = { tag = "SMALL_BUBBLES", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SmallDriftingBubbles" }
T.gSmallWaterOrbSpriteTemplate = { tag = "GLOWY_BLUE_ORB", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SmallWaterOrb" }
T.gSmellingSaltExclamationSpriteTemplate = { tag = "SMELLINGSALT_EFFECT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SmellingSaltExclamation" }
T.gSmellingSaltsHandSpriteTemplate = { tag = "TAG_HAND", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SmellingSaltsHand" }
T.gSmogCloudSpriteTemplate = { tag = "PURPLE_GAS_CLOUD", w = 32, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,8), F(8,8), J(0) } }, affine = { { AE } }, cbName = "InitSwirlingFogAnim" }
T.gSmokeBallEscapeCloudSpriteTemplate = { tag = "PINK_CLOUD", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(128,128,0,0), A(-4,-6,0,16), A(4,6,0,16), AJ(0) }, { A(192,192,0,0), A(4,6,0,16), A(-4,-6,0,16), AJ(0) }, { A(256,256,0,0), A(4,6,0,16), A(-4,-6,0,16), AJ(0) }, { A(256,256,0,0), A(8,10,0,30), A(-8,-10,0,16), AJ(0) } }, cbName = "SmokeBallEscapeCloud" }
T.gSnoreZSpriteTemplate = { tag = "SNORE_Z", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TravelDiagonally" }
T.gSoftBoiledEggSpriteTemplate = { tag = "BREAKING_EGG", w = 32, h = 32, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,-8,2), A(0,0,8,4), A(0,0,-8,2), AJ(0) }, { A(256,256,0,0), AE }, { A(-8,4,0,8), AL(0), A(16,-8,0,8), A(-16,8,0,8), AL(1), A(256,256,0,0), A(0,0,0,15), AE } }, cbName = "SoftBoiledEgg" }
T.gSolarBeamBigOrbSpriteTemplate = { tag = "ORBS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(1,1), E }, { F(2,1), E }, { F(3,1), E }, { F(4,1), E }, { F(5,1), E }, { F(6,1), E } }, affine = { { AE } }, cbName = "SolarBeamBigOrb" }
T.gSolarBeamSmallOrbSpriteTemplate = { tag = "ORBS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(7,1), E } }, affine = { { AE } }, cbName = "SolarBeamSmallOrb" }
T.gSonicBoomSpriteTemplate = { tag = "AIR_WAVE", w = 32, h = 16, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SonicBoomProjectile" }
T.gSparkElectricityFlashingSpriteTemplate = { tag = "SPARK_2", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,20,1), AJ(0) } }, cbName = "SparkElectricityFlashing" }
T.gSparkElectricitySpriteTemplate = { tag = "SPARK_2", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SparkElectricity" }
T.gSparklingStarsSpriteTemplate = { tag = "SPARKLE_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,7), F(16,7), F(32,7), F(48,7), F(64,7), F(80,7), F(96,7), F(112,7), J(0) } }, affine = { { AE } }, cbName = "SparklingStars" }
T.gSpecialScreenSparkleSpriteTemplate = { tag = "SPARKLE_3", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(4,5), F(8,5), F(12,5), E } }, affine = { { AE } }, cbName = "WallSparkle" }
T.gSpeedDustSpriteTemplate = { tag = "SPEED_DUST", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(4,3), F(8,3), F(4,3), F(0,3), E } }, affine = { { AE } }, cbName = "SpeedDust" }
T.gSpiderWebSpriteTemplate = { tag = "SPIDER_WEB", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(6,6,0,1), AJ(1) } }, cbName = "SpiderWeb" }
T.gSpikesSpriteTemplate = { tag = "SPIKES", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "Spikes" }
T.gSpinningBoneSpriteTemplate = { tag = "BONE", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,20,1), AJ(0) } }, cbName = "BoneHitProjectile" }
T.gSpinningHandOrFootSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { F(0,1), E }, { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { A(256,256,0,0), A(-8,-8,20,1), AJ(1) } }, cbName = "SpinningKickOrPunch" }
T.gSpinningSparkleSpriteTemplate = { tag = "SPARKLE_4", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), E } }, affine = { { AE } }, cbName = "SpinningSparkle" }
T.gSpitUpOrbSpriteTemplate = { tag = "RED_ORB_2", w = 8, h = 8, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(128,128,0,0), A(8,8,0,1), AJ(1) } }, cbName = "SpitUpOrb" }
T.gSporeParticleSpriteTemplate = { tag = "SPORE", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(4,7), E } }, affine = { { AE } }, cbName = "SporeParticle" }
T.gSpotlightSpriteTemplate = { tag = "SPOTLIGHT", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,384,0,0), A(16,0,0,20), AE }, { A(320,384,0,0), A(-16,0,0,19), AE } }, cbName = "Spotlight" }
T.gSprayWaterDropletSpriteTemplate = { tag = "SWEAT_BEAD", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SprayWaterDroplet" }
T.gSpriteTemplate_EnemyShadow = { tag = "GFXTAG_SHADOW", w = 32, h = 8, affineMode = 0, blend = false, priority = 3, anims = { { E } }, affine = { { AE } }, cbName = "SpriteCB_SetInvisible" }
T.gStockpileAbsorptionOrbSpriteTemplate = { tag = "GRAY_ORB", w = 8, h = 8, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(320,320,0,0), A(-14,-14,0,1), AJ(1) } }, cbName = "PowerAbsorptionOrb" }
T.gStompFootSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,1), E }, { F(32,1), E }, { F(48,1), E }, { F(48,1,true,false), E } }, affine = { { AE } }, cbName = "StompFoot" }
T.gStringWrapSpriteTemplate = { tag = "STRING", w = 64, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "StringWrap" }
T.gStunSporeParticleSpriteTemplate = { tag = "STUN_SPORE", w = 8, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(2,5), F(4,5), F(6,5), F(8,5), F(10,5), F(12,5), F(14,5), J(0) } }, affine = { { AE } }, cbName = "MovePowderParticle" }
T.gSunlightRaySpriteTemplate = { tag = "SUNLIGHT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(80,80,0,0), A(2,2,10,1), AJ(1) } }, cbName = "Sunlight" }
T.gSuperFangSpriteTemplate = { tag = "FANG_ATTACK", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2), F(16,2), F(32,2), F(48,2), E } }, affine = { { AE } }, cbName = "SuperFang" }
T.gSuperpowerFireballSpriteTemplate = { tag = "METEOR", w = 64, h = 64, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SuperpowerFireball" }
T.gSuperpowerOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(4,4,0,64), A(-6,-6,0,8), A(6,6,0,8), AJ(2) } }, cbName = "SuperpowerOrb" }
T.gSuperpowerRockSpriteTemplate = { tag = "FLAT_ROCK", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SuperpowerRock" }
T.gSupersonicRingSpriteTemplate = { tag = "GOLD_RING", w = 16, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(32,32,0,0), A(7,7,0,-56), AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gSwallowBlueOrbSpriteTemplate = { tag = "BLUE_ORB", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SwallowBlueOrb" }
T.gSweetScentPetalSpriteTemplate = { tag = "PINK_PETAL", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(0,8), F(1,8), F(2,8), F(3,8), F(3,8,false,true), F(2,8,false,true), F(0,8,false,true), F(1,8,false,true), J(0) }, { F(0,8,true,false), F(1,8,true,false), F(2,8,true,false), F(3,8,true,false), F(3,8,true,true), F(2,8,true,true), F(0,8,true,true), F(1,8,true,true), J(0) }, { F(0,8), E } }, affine = { { AE } }, cbName = "SweetScentPetal" }
T.gSwiftStarSpriteTemplate = { tag = "YELLOW_STAR", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,0,1), AJ(0) } }, cbName = "TranslateLinearSingleSineWave" }
T.gSwirlingDirtSpriteTemplate = { tag = "MUD_SAND", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ParticleInVortex" }
T.gSwirlingSnowballSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(7,1), E } }, affine = { { AE } }, cbName = "SwirlingSnowball" }
T.gSwordsDanceBladeSpriteTemplate = { tag = "SWORD", w = 32, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,256,0,0), A(20,0,0,12), A(0,0,0,32), AE } }, cbName = "SwordsDanceBlade" }
T.gTailGlowOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(8,8,0,18), AL(0), A(-5,-5,0,8), A(5,5,0,8), AL(5), AE } }, cbName = "TailGlowOrb" }
T.gTauntFingerSpriteTemplate = { tag = "FINGER_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(0,1,true,false), E }, { F(0,4), F(16,4), F(32,4), F(16,4), F(0,4), F(16,4), F(32,4), E }, { F(0,4,true,false), F(16,4,true,false), F(32,4,true,false), F(16,4,true,false), F(0,4,true,false), F(16,4,true,false), F(32,4,true,false), E } }, affine = { { AE } }, cbName = "TauntFinger" }
T.gTealAlertSpriteTemplate = { tag = "TEAL_ALERT", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TealAlert" }
T.gTearDropSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(192,192,80,0), A(0,0,-2,8), AE }, { A(192,192,-80,0), A(0,0,2,8), AE } }, cbName = "TearDrop" }
T.gThinRingExpandingSpriteTemplate = { tag = "THIN_RING", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(16,16,0,30), AE }, { A(16,16,0,0), A(32,32,0,15), AE } }, cbName = "SpriteOnMonPos" }
T.gThinRingShrinkingSpriteTemplate = { tag = "THIN_RING", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(512,512,0,0), A(-16,-16,0,30), AE } }, cbName = "SpriteOnMonPos" }
T.gThoughtBubbleSpriteTemplate = { tag = "THOUGHT_BUBBLE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,2,true,false), F(16,2,true,false), F(32,2,true,false), F(48,2,true,false), E }, { F(0,2), F(16,2), F(32,2), F(48,2), E }, { F(48,2,true,false), F(32,2,true,false), F(16,2,true,false), F(0,2,true,false), E }, { F(48,2), F(32,2), F(16,2), F(0,2), E } }, affine = { { AE } }, cbName = "ThoughtBubble" }
T.gThunderWaveSpriteTemplate = { tag = "SPARK_H", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ThunderWave" }
T.gThunderboltOrbSpriteTemplate = { tag = "SHOCK_3", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,6), F(16,6), F(32,6), J(0) } }, affine = { { A(232,232,0,0), A(-8,-8,0,10), A(8,8,0,10), AJ(1) } }, cbName = "ThunderboltOrb" }
T.gToxicBubbleSpriteTemplate = { tag = "TOXIC_BUBBLE", w = 16, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(8,5), F(16,5), F(24,5), E } }, affine = { { AE } }, cbName = "SpriteOnMonPos" }
T.gTriAttackTriangleSpriteTemplate = { tag = "TRI_ATTACK_TRIANGLE", w = 64, h = 64, affineMode = 3, blend = false, priority = 2, anims = { { F(0,8), E } }, affine = { { A(0,0,5,40), A(0,0,10,10), A(0,0,15,10), A(0,0,20,40), AJ(0) } }, cbName = "TriAttackTriangle" }
T.gTrickBagSpriteTemplate = { tag = "ITEM_BAG", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,30), E } }, affine = { { A(0,0,0,3), AE }, { A(0,-10,0,3), A(0,-6,0,3), A(0,-2,0,3), A(0,0,0,3), A(0,2,0,3), A(0,6,0,3), A(0,10,0,3), AE }, { A(0,0,-4,10), A(0,0,4,20), A(0,0,-4,10), AE }, { A(0,0,-1,2), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,2), AE } }, cbName = "TrickBag" }
T.gTwisterLeafSpriteTemplate = { tag = "LEAF", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(4,5), F(8,5), F(12,5), F(16,5), F(20,5), F(16,5), F(12,5), F(8,5), F(4,5), J(0) }, { F(24,5), F(28,5), F(32,5), E } }, affine = { { AE } }, cbName = "MoveTwisterParticle" }
T.gTwisterRockSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(64,1), E }, { F(80,1), E } }, affine = { { A(0,0,-5,5), AJ(0) }, { A(0,0,5,5), AJ(0) } }, cbName = "MoveTwisterParticle" }
T.gUproarRingSpriteTemplate = { tag = "THIN_RING", w = 64, h = 64, affineMode = 3, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(16,16,0,30), AE }, { A(16,16,0,0), A(32,32,0,15), AE } }, cbName = "UproarRing" }
T.gViceGripSpriteTemplate = { tag = "CUT", w = 32, h = 32, affineMode = 0, blend = true, priority = 2, anims = { { F(0,3), F(16,3), F(32,20), E }, { F(0,3,true,true), F(16,3,true,true), F(32,20,true,true), E } }, affine = { { AE } }, cbName = "ViceGripPincer" }
T.gVineWhipSpriteTemplate = { tag = "WHIP_HIT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(64,3), F(80,3), F(96,3), F(112,6), E }, { F(64,3,true,false), F(80,3,true,false), F(96,3,true,false), F(112,6,true,false), E } }, affine = { { AE } }, cbName = "WhipHit" }
T.gVoltTackleBoltSpriteTemplate = { tag = "SPARK", w = 8, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,3), E }, { F(2,3), E }, { F(4,3), E }, { F(6,3), E } }, affine = { { A(256,256,64,0), AE } }, cbName = "VoltTackleBolt" }
T.gVoltTackleOrbSlideSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(16,16,0,0), A(4,4,0,60), A(256,256,0,0), AL(0), A(-4,-4,0,5), A(4,4,0,5), AL(10), AE }, { A(16,16,0,0), A(8,8,0,30), A(256,256,0,0), A(-4,-4,0,5), A(4,4,0,5), AJ(3) }, { A(16,16,0,0), A(8,8,0,30), A(-8,-8,0,30), AE } }, cbName = "VoltTackleOrbSlide" }
T.gWaterBubbleProjectileSpriteTemplate = { tag = "BUBBLE", w = 16, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(0,1), F(4,5), F(8,5), E } }, affine = { { A(-5,-5,0,10), A(5,5,0,10), AJ(0) } }, cbName = "WaterBubbleProjectile" }
T.gWaterBubbleSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(0,1), E } }, affine = { { A(156,156,0,0), A(5,5,0,20), AE } }, cbName = "BubbleEffect" }
T.gWaterGunDropletSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 3, blend = true, priority = 2, anims = { { F(4,1), E } }, affine = { { A(-16,16,0,6), A(16,-16,0,6), AJ(0) } }, cbName = "WaterGunDroplet" }
T.gWaterGunProjectileSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { F(0,1), E } }, affine = { { AE } }, cbName = "ThrowProjectile" }
T.gWaterHitSplatSpriteTemplate = { tag = "WATER_IMPACT", w = 32, h = 32, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,8), AE }, { A(216,216,0,0), A(0,0,0,8), AE }, { A(176,176,0,0), A(0,0,0,8), AE }, { A(128,128,0,0), A(0,0,0,8), AE } }, cbName = "HitSplatBasic" }
T.gWaterPulseBubbleSpriteTemplate = { tag = "SMALL_BUBBLES", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { F(8,1), E }, { F(9,1), E } }, affine = { { AE } }, cbName = "WaterPulseBubble" }
T.gWaterPulseRingBubbleSpriteTemplate = { tag = "SMALL_BUBBLES", w = 8, h = 8, affineMode = 1, blend = false, priority = 2, anims = { { F(8,1), E }, { F(9,1), E } }, affine = { { A(256,256,0,0), A(-10,-10,0,15), AE }, { A(224,224,0,0), A(-8,-8,0,15), AE } }, cbName = "WaterPulseRingBubble" }
T.gWaterPulseRingSpriteTemplate = { tag = "BLUE_RING_2", w = 16, h = 32, affineMode = 3, blend = false, priority = 2, anims = { { E } }, affine = { { A(5,5,0,10), A(-10,-10,0,10), A(10,10,0,10), A(-10,-10,0,10), A(10,10,0,10), A(-10,-10,0,10), A(10,10,0,10), AE } }, cbName = "WaterPulseRing" }
T.gWavyMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,10), E }, { F(4,10), E }, { F(8,41), E }, { F(12,10), E }, { F(16,10), E }, { F(20,10), E }, { F(0,10,false,true), E }, { F(4,10,false,true), E } }, affine = { { A(12,12,0,16), A(65524,65524,0,16), AJ(0) } }, cbName = "WavyMusicNotes" }
T.gWeakFrustrationAngerMarkSpriteTemplate = { tag = "ANGER", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "WeakFrustrationAngerMark" }
T.gWeatherBallFireDownSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,4), J(0) } }, affine = { { AE } }, cbName = "WeatherBallDown" }
T.gWeatherBallIceDownSpriteTemplate = { tag = "HAIL", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(336,336,0,0), AE } }, cbName = "WeatherBallDown" }
T.gWeatherBallNormalDownSpriteTemplate = { tag = "WEATHER_BALL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), J(0) } }, affine = { { AE } }, cbName = "WeatherBallDown" }
T.gWeatherBallRockDownSpriteTemplate = { tag = "ROCKS", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(32,1), E }, { F(48,1), E }, { F(64,1), E }, { F(80,1), E } }, affine = { { A(0,0,-5,5), AJ(0) }, { A(0,0,5,5), AJ(0) } }, cbName = "WeatherBallDown" }
T.gWeatherBallUpSpriteTemplate = { tag = "WEATHER_BALL", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), J(0) } }, affine = { { AE } }, cbName = "WeatherBallUp" }
T.gWeatherBallWaterDownSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { F(4,1), E } }, affine = { { A(336,336,0,0), A(0,0,0,15), AE } }, cbName = "WeatherBallDown" }
T.gWebThreadSpriteTemplate = { tag = "WEB_THREAD", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateWebThread" }
T.gWhirlpoolSpriteTemplate = { tag = "WATER_ORB", w = 16, h = 16, affineMode = 1, blend = true, priority = 2, anims = { { F(0,1), F(4,1), F(8,1), F(12,1), J(0) } }, affine = { { A(192,192,0,0), A(2,-3,0,5), A(-2,3,0,5), AJ(1) } }, cbName = "ParticleInVortex" }
T.gWhirlwindLineSpriteTemplate = { tag = "WHIRLWIND_LINES", w = 32, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), F(8,1), F(16,1), F(8,1,true,false), F(0,1,true,false), E } }, affine = { { AE } }, cbName = "WhirlwindLine" }
T.gWhiteHaloSpriteTemplate = { tag = "ROUND_WHITE_HALO", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "WhiteHalo" }
T.gWillOWispFireSpriteTemplate = { tag = "WISP_FIRE", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), J(0) } }, affine = { { AE } }, cbName = "WillOWispFire" }
T.gWillOWispOrbSpriteTemplate = { tag = "WISP_ORB", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(4,5), F(8,5), F(12,5), J(0) }, { F(16,5), E }, { F(20,5), E }, { F(20,5), E } }, affine = { { AE } }, cbName = "WillOWispOrb" }
T.gWishStarSpriteTemplate = { tag = "GOLD_STARS", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "WishStar" }
T.gYawnCloudSpriteTemplate = { tag = "PINK_CLOUD", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(128,128,0,0), A(-8,-8,0,8), A(8,8,0,8), AJ(0) }, { A(192,192,0,0), A(8,8,0,8), A(-8,-8,0,8), AJ(0) }, { A(256,256,0,0), A(8,8,0,8), A(-8,-8,0,8), AJ(0) } }, cbName = "YawnCloud" }
T.gZapCannonBallSpriteTemplate = { tag = "BLACK_BALL_2", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateAnimSpriteToTargetMonLocation" }
T.gZapCannonSparkSpriteTemplate = { tag = "SPARK_2", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(0,0,20,1), AJ(0) } }, cbName = "ZapCannonSpark" }
T.sBouncingMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "BouncingMusicNote" }
T.sBubbleBurstSpriteTemplate = { tag = "BUBBLE_BURST", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,10), F(4,10), F(8,10), F(12,10), F(16,26), F(16,5), F(20,5), F(24,15), E }, { F(0,10,true,false), F(4,10,true,false), F(8,10,true,false), F(12,10,true,false), F(16,26,true,false), F(16,5,true,false), F(20,5,true,false), F(24,15,true,false), E } }, affine = { { AE } }, cbName = "BubbleBurst" }
T.sCirclingFingerSpriteTemplate = { tag = "FINGER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "CirclingFinger" }
T.sCirclingMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,1), E }, { F(4,1), E }, { F(8,1), E }, { F(12,1), E }, { F(16,1), E }, { F(20,1), E }, { F(0,1,false,true), E }, { F(4,1,false,true), E }, { F(8,1,false,true), E }, { F(12,1,false,true), E } }, affine = { { AE } }, cbName = "CirclingMusicNote" }
T.sCirclingSparkleSpriteTemplate = { tag = "SPARKLE_4", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(16,3), F(32,3), F(48,3), F(64,3), J(0) } }, affine = { { AE } }, cbName = "CirclingSparkle" }
T.sElectricBoltSegmentSpriteTemplate = { tag = "SPARK", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ElectricBoltSegment" }
T.sFlashingCircleImpactSpriteTemplate = { tag = "CIRCLE_IMPACT", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "FlashingCircleImpact" }
T.sFlickeringFootSpriteTemplate = { tag = "MONSTER_FOOT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "TranslateLinearAndFlicker" }
T.sFlickeringImpactSpriteTemplate = { tag = "IMPACT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), J(0) }, { F(0,5), J(0) }, { F(0,5), J(0) } }, affine = { { AE } }, cbName = "TranslateLinearAndFlicker" }
T.sFlickeringOrbFlippedSpriteTemplate = { tag = "ORB", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(4,3), F(8,3), F(12,3), J(0) } }, affine = { { AE } }, cbName = "TranslateLinearAndFlicker_Flipped" }
T.sFlickeringOrbSpriteTemplate = { tag = "ORB", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { F(0,3), F(4,3), F(8,3), F(12,3), J(0) } }, affine = { { AE } }, cbName = "TranslateLinearAndFlicker" }
T.sFlickeringPunchSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), AE }, { A(256,256,32,0), AE }, { A(256,256,64,0), AE }, { A(256,256,96,0), AE }, { A(256,256,-128,0), AE }, { A(256,256,-96,0), AE }, { A(256,256,-64,0), AE }, { A(256,256,-32,0), AE } }, cbName = "FlickeringPunch" }
T.sFlickeringShrinkOrbSpriteTemplate = { tag = "ORB", w = 16, h = 16, affineMode = 3, blend = false, priority = 2, anims = { { F(0,15), J(0) } }, affine = { { A(96,96,0,0), A(2,2,0,1), AJ(1) } }, cbName = "TranslateLinearAndFlicker_Flipped" }
T.sFrozenIceCubeSpriteTemplate = { tag = "ICE_CUBE", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SpriteCallbackDummy" }
T.sHailParticleSpriteTemplate = { tag = "HAIL", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), AE }, { A(240,240,0,0), AE }, { A(224,224,0,0), AE } }, cbName = "HailBegin" }
T.sImprisonOrbSpriteTemplate = { tag = "HOLLOW_ORB", w = 16, h = 16, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "SpriteCallbackDummy" }
T.sMovingClampSpriteTemplate = { tag = "CLAMP", w = 64, h = 64, affineMode = 1, blend = true, priority = 2, anims = { { E } }, affine = { { A(0,0,0,1), AE }, { A(0,0,32,1), AE }, { A(0,0,64,1), AE }, { A(0,0,96,1), AE }, { A(0,0,-128,1), AE }, { A(0,0,-96,1), AE }, { A(0,0,-64,1), AE }, { A(0,0,-32,1), AE } }, cbName = "MovingClamp" }
T.sShockWaveProgressingBoltSpriteTemplate = { tag = "SPARK", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ShockWaveProgressingBolt" }
T.sSkillSwapOrbSpriteTemplate = { tag = "BLUEGREEN_ORB", w = 16, h = 16, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(-8,-8,0,8), A(8,8,0,8), AJ(0) }, { A(240,240,0,0), A(-8,-8,0,6), A(8,8,0,8), A(-8,-8,0,2), AJ(1) }, { A(208,208,0,0), A(-8,-8,0,4), A(8,8,0,8), A(-8,-8,0,4), AJ(1) }, { A(176,176,0,0), A(-8,-8,0,2), A(8,8,0,8), A(-8,-8,0,6), AJ(1) } }, cbName = "SkillSwapOrb" }
T.sSlidingHit1SpriteTemplate = { tag = "HIT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,5), E } }, affine = { { AE } }, cbName = "SlidingHit" }
T.sSlidingHit2SpriteTemplate = { tag = "HIT_2", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,4), F(16,4), F(32,4), F(48,4), F(64,5), E } }, affine = { { AE } }, cbName = "SlidingHit" }
T.sSmallExplosionSpriteTemplate = { tag = "EXPLOSION_6", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,9), F(16,3), F(32,3), F(48,3), E } }, affine = { { A(80,80,0,0), A(9,9,0,18), AE } }, cbName = "SpriteOnMonPos" }
T.sSmokescreenImpactSpriteTemplate = { tag = "TAG_SMOKESCREEN", w = 16, h = 16, affineMode = 0, blend = false, priority = 1, anims = { { F(0,4), F(4,4), F(8,4), E }, { F(0,4,true,false), F(4,4,true,false), F(8,4,true,false), E }, { F(0,4,false,true), F(4,4,false,true), F(8,4,false,true), E }, { F(0,4,true,true), F(4,4,true,true), F(8,4,true,true), E } }, affine = { { AE } }, cbName = "SpriteCB_SmokescreenImpact" }
T.sUnusedBagStealSpriteTemplate = { tag = "TIED_BAG", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedBagSteal" }
T.sUnusedBubbleThrowSpriteTemplate = { tag = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedBubbleThrow" }
T.sUnusedCirclingShockSpriteTemplate = { tag = "SHOCK", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), F(64,5), F(80,5), J(0) } }, affine = { { AE } }, cbName = "UnusedCirclingShock" }
T.sUnusedEmberFirePlumeSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(0,5), F(16,5), F(32,5), F(48,5), F(64,5), J(0) } }, affine = { { AE } }, cbName = "FirePlume" }
T.sUnusedFeatherSpriteTemplate = { tag = "WHITE_FEATHER", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { F(0,0), E }, { F(16,0,true,false), E } }, affine = { { AE } }, cbName = "UnusedFeather" }
T.sUnusedFlashingLightSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedFlashingLight" }
T.sUnusedHumanoidFootSpriteTemplate = { tag = "HUMANOID_FOOT", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedHumanoidFoot" }
T.sUnusedIceCrystalThrowSpriteTemplate = { tag = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedIceCrystalThrow" }
T.sUnusedItemBagStealSpriteTemplate = { tag = "ITEM_BAG", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "UnusedItemBagSteal" }
T.sUnusedSmallEmberSpriteTemplate = { tag = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, blend = false, priority = 2, anims = { { F(16,6), F(32,6), F(48,6), J(0) } }, affine = { { AE } }, cbName = "UnusedSmallEmber" }
T.sUnusedSpinningFistSpriteTemplate = { tag = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 1, blend = false, priority = 2, anims = { { E } }, affine = { { A(256,256,0,0), A(0,0,0,20), A(0,0,-16,60), AE } }, cbName = "UnusedSpinningFist" }
T.sUnusedStarBurstSpriteTemplate = { tag = "GOLD_STARS", w = 16, h = 16, affineMode = 0, blend = false, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "ParticleBurst" }
T.sVoidLinesSpriteTemplate = { tag = "VOID_LINES", w = 64, h = 64, affineMode = 0, blend = true, priority = 2, anims = { { E } }, affine = { { AE } }, cbName = "VoidLines" }
T._affine = {}
T._affine.DefenseCurlDeformMonAffineAnimCmds = { A(-12,20,0,8), A(12,-20,0,8), AL(2), AE }
T._affine.sAbsorptionOrbAffineAnimCmds = { A(-5,-5,0,1), AJ(0) }
T._affine.sAffineAnim_AcidPoisonDroplet = { A(-16,16,0,6), A(16,-16,0,6), AJ(0) }
T._affine.sAffineAnim_AuroraBeamRing = { A(0,0,0,1), A(96,96,0,1), AE }
T._affine.sAffineAnim_BallRotate_0 = { A(0,0,0,1), AJ(0) }
T._affine.sAffineAnim_BallRotate_3 = { A(256,256,0,0), AE }
T._affine.sAffineAnim_BallRotate_4 = { A(0,0,25,1), AJ(0) }
T._affine.sAffineAnim_BallRotate_Left = { A(0,0,3,1), AJ(0) }
T._affine.sAffineAnim_BallRotate_Right = { A(0,0,-3,1), AJ(0) }
T._affine.sAffineAnim_BasicRock_0 = { A(0,0,-5,5), AJ(0) }
T._affine.sAffineAnim_BasicRock_1 = { A(0,0,5,5), AJ(0) }
T._affine.sAffineAnim_Bite_0 = { A(0,0,0,1), AE }
T._affine.sAffineAnim_Bite_1 = { A(0,0,32,1), AE }
T._affine.sAffineAnim_Bite_2 = { A(0,0,64,1), AE }
T._affine.sAffineAnim_Bite_3 = { A(0,0,96,1), AE }
T._affine.sAffineAnim_Bite_4 = { A(0,0,-128,1), AE }
T._affine.sAffineAnim_Bite_5 = { A(0,0,-96,1), AE }
T._affine.sAffineAnim_Bite_6 = { A(0,0,-64,1), AE }
T._affine.sAffineAnim_Bite_7 = { A(0,0,-32,1), AE }
T._affine.sAffineAnim_Bonemerang = { A(0,0,15,1), AJ(0) }
T._affine.sAffineAnim_BounceBallLand = { A(160,256,0,0), AE }
T._affine.sAffineAnim_BounceBallShrink = { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-20,0,0,7), A(-20,-20,0,5), AE }
T._affine.sAffineAnim_Bubble = { A(156,156,0,0), A(5,5,0,20), AE }
T._affine.sAffineAnim_ConfuseRayBallBounce = { A(30,30,10,5), A(-30,-30,10,5), AJ(0) }
T._affine.sAffineAnim_ConstrictBinding = { A(256,256,0,0), A(-11,0,0,6), A(11,0,0,6), AE }
T._affine.sAffineAnim_ConstrictBinding_Flipped = { A(-256,256,0,0), A(11,0,0,6), A(-11,0,0,6), AE }
T._affine.sAffineAnim_DiveBall = { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-16,32,0,10), AE }
T._affine.sAffineAnim_DragonBreathFire_0 = { A(80,80,127,0), A(13,13,0,100), AE }
T._affine.sAffineAnim_DragonBreathFire_1 = { A(80,80,0,0), A(13,13,0,100), AE }
T._affine.sAffineAnim_DragonRageFire_0 = { A(100,100,127,1), AE }
T._affine.sAffineAnim_DragonRageFire_1 = { A(100,100,0,1), AE }
T._affine.sAffineAnim_FlashingSpark = { A(0,0,20,1), AJ(0) }
T._affine.sAffineAnim_FlickeringPunch_Normal = { A(256,256,0,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedBottomLeft = { A(256,256,96,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedBottomRight = { A(256,256,-96,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedLeft = { A(256,256,64,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedRight = { A(256,256,-64,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedTopLeft = { A(256,256,32,0), AE }
T._affine.sAffineAnim_FlickeringPunch_TurnedTopRight = { A(256,256,-32,0), AE }
T._affine.sAffineAnim_FlickeringPunch_UpsideDown = { A(256,256,-128,0), AE }
T._affine.sAffineAnim_FlickeringShrinkOrb = { A(96,96,0,0), A(2,2,0,1), AJ(1) }
T._affine.sAffineAnim_FlyBallAttack_0 = { A(0,0,50,1), AE }
T._affine.sAffineAnim_FlyBallAttack_1 = { A(0,0,-40,1), AE }
T._affine.sAffineAnim_FlyBallUp = { A(16,256,0,0), A(40,0,0,6), A(0,-32,0,5), A(-16,32,0,10), AE }
T._affine.sAffineAnim_FocusPunchFist = { A(512,512,0,0), A(-32,-32,0,8), AE }
T._affine.sAffineAnim_GrowingElectricOrb_0 = { A(16,16,0,0), A(4,4,0,60), A(256,256,0,0), AL(0), A(-4,-4,0,5), A(4,4,0,5), AL(10), AE }
T._affine.sAffineAnim_GrowingElectricOrb_1 = { A(16,16,0,0), A(8,8,0,30), A(256,256,0,0), A(-4,-4,0,5), A(4,4,0,5), AJ(3) }
T._affine.sAffineAnim_GrowingElectricOrb_2 = { A(16,16,0,0), A(8,8,0,30), A(-8,-8,0,30), AE }
T._affine.sAffineAnim_GustToTarget = { A(16,256,0,0), A(10,0,0,24), AE }
T._affine.sAffineAnim_HailParticle_0 = { A(256,256,0,0), AE }
T._affine.sAffineAnim_HailParticle_1 = { A(240,240,0,0), AE }
T._affine.sAffineAnim_HailParticle_2 = { A(224,224,0,0), AE }
T._affine.sAffineAnim_HitSplat_0 = { A(0,0,0,8), AE }
T._affine.sAffineAnim_HitSplat_1 = { A(216,216,0,0), A(0,0,0,8), AE }
T._affine.sAffineAnim_HitSplat_2 = { A(176,176,0,0), A(0,0,0,8), AE }
T._affine.sAffineAnim_HitSplat_3 = { A(128,128,0,0), A(0,0,0,8), AE }
T._affine.sAffineAnim_HydroCannonBeam = { A(336,336,0,0), AE }
T._affine.sAffineAnim_HydroCannonCharge = { A(3,3,10,50), A(0,0,0,10), A(-20,-20,-10,20), AE }
T._affine.sAffineAnim_IceBallChunk_0 = { A(224,224,0,0), AE }
T._affine.sAffineAnim_IceBallChunk_1 = { A(280,280,0,0), AE }
T._affine.sAffineAnim_IceBallChunk_2 = { A(336,336,0,0), AE }
T._affine.sAffineAnim_IceBallChunk_3 = { A(384,384,0,0), AE }
T._affine.sAffineAnim_IceBallChunk_4 = { A(448,448,0,0), AE }
T._affine.sAffineAnim_IceBeamInnerCrystal = { A(0,0,10,1), AJ(0) }
T._affine.sAffineAnim_IceCrystalHit = { A(206,206,0,0), A(5,5,0,10), A(0,0,0,6), AE }
T._affine.sAffineAnim_IceCrystalSpiralInwardLarge = { A(0,0,40,1), AJ(0) }
T._affine.sAffineAnim_LargeFlame = { A(50,256,0,0), A(32,0,0,7), AE }
T._affine.sAffineAnim_LeechLifeNeedle_0 = { A(0,0,-33,1), AE }
T._affine.sAffineAnim_LeechLifeNeedle_1 = { A(0,0,96,1), AE }
T._affine.sAffineAnim_LeechLifeNeedle_2 = { A(0,0,-96,1), AE }
T._affine.sAffineAnim_LusterPurgeCircle = { A(32,32,0,0), A(4,4,0,120), AE }
T._affine.sAffineAnim_MeditateStretchAttacker = { A(-8,10,0,16), A(18,-18,0,16), A(-20,16,0,8), AE }
T._affine.sAffineAnim_MegaPunchKick = { A(256,256,0,0), A(-4,-4,20,1), AJ(1) }
T._affine.sAffineAnim_MegahornHorn_0 = { A(256,256,30,0), AE }
T._affine.sAffineAnim_MegahornHorn_1 = { A(256,256,-99,0), AE }
T._affine.sAffineAnim_MegahornHorn_2 = { A(256,256,94,0), AE }
T._affine.sAffineAnim_PoisonProjectile = { A(352,352,0,0), A(-10,-10,0,10), A(10,10,0,10), AJ(0) }
T._affine.sAffineAnim_PsychUpSpiral = { A(256,256,0,0), A(-2,-2,-10,120), AE }
T._affine.sAffineAnim_PsychoBoostOrb_0 = { A(32,32,0,0), A(16,16,0,17), AL(0), A(-8,-8,0,10), A(8,8,0,10), AL(4), AL(0), A(-16,-16,0,5), A(16,16,0,5), AL(7), AE }
T._affine.sAffineAnim_PsychoBoostOrb_1 = { A(-20,24,0,15), AE }
T._affine.sAffineAnim_QuestionMark = { A(0,0,4,4), A(0,0,-4,8), A(0,0,4,4), AL(2), AE }
T._affine.sAffineAnim_ShadowBall = { A(0,0,10,1), AJ(0) }
T._affine.sAffineAnim_SkillSwapOrb_0 = { A(-8,-8,0,8), A(8,8,0,8), AJ(0) }
T._affine.sAffineAnim_SkillSwapOrb_1 = { A(240,240,0,0), A(-8,-8,0,6), A(8,8,0,8), A(-8,-8,0,2), AJ(1) }
T._affine.sAffineAnim_SkillSwapOrb_2 = { A(208,208,0,0), A(-8,-8,0,4), A(8,8,0,8), A(-8,-8,0,4), AJ(1) }
T._affine.sAffineAnim_SkillSwapOrb_3 = { A(176,176,0,0), A(-8,-8,0,2), A(8,8,0,8), A(-8,-8,0,6), AJ(1) }
T._affine.sAffineAnim_SludgeBombHit = { A(236,236,0,0), AE }
T._affine.sAffineAnim_SmallExplosion = { A(80,80,0,0), A(9,9,0,18), AE }
T._affine.sAffineAnim_SpiderWeb = { A(16,16,0,0), A(6,6,0,1), AJ(1) }
T._affine.sAffineAnim_SpinningBone = { A(0,0,20,1), AJ(0) }
T._affine.sAffineAnim_SpinningHandOrFoot = { A(256,256,0,0), A(-8,-8,20,1), AJ(1) }
T._affine.sAffineAnim_SunlightRay = { A(80,80,0,0), A(2,2,10,1), AJ(1) }
T._affine.sAffineAnim_SuperpowerOrb = { A(32,32,0,0), A(4,4,0,64), A(-6,-6,0,8), A(6,6,0,8), AJ(2) }
T._affine.sAffineAnim_TailGlowOrb = { A(16,16,0,0), A(8,8,0,18), AL(0), A(-5,-5,0,8), A(5,5,0,8), AL(5), AE }
T._affine.sAffineAnim_TearDrop_0 = { A(192,192,80,0), A(0,0,-2,8), AE }
T._affine.sAffineAnim_TearDrop_1 = { A(192,192,-80,0), A(0,0,2,8), AE }
T._affine.sAffineAnim_Teleport = { A(64,-4,0,20), A(0,0,0,-56), AE }
T._affine.sAffineAnim_ThunderboltOrb = { A(232,232,0,0), A(-8,-8,0,10), A(8,8,0,10), AJ(1) }
T._affine.sAffineAnim_Unused = { A(512,512,0,0), AE }
T._affine.sAffineAnim_UnusedSpinningFist = { A(256,256,0,0), A(0,0,0,20), A(0,0,-16,60), AE }
T._affine.sAffineAnim_Unused_0 = { A(0,0,0,1), AE }
T._affine.sAffineAnim_Unused_1 = { A(160,160,0,0), AE }
T._affine.sAffineAnim_VoltTackleBolt = { A(256,256,64,0), AE }
T._affine.sAffineAnim_WaterBubbleProjectile = { A(-5,-5,0,10), A(5,5,0,10), AJ(0) }
T._affine.sAffineAnim_WaterPulseRingBubble_0 = { A(256,256,0,0), A(-10,-10,0,15), AE }
T._affine.sAffineAnim_WaterPulseRingBubble_1 = { A(224,224,0,0), A(-8,-8,0,15), AE }
T._affine.sAffineAnim_WeatherBallIceDown = { A(336,336,0,0), AE }
T._affine.sAffineAnim_WeatherBallWaterDown = { A(336,336,0,0), A(0,0,0,15), AE }
T._affine.sAffineAnim_Whirlpool = { A(192,192,0,0), A(2,-3,0,5), A(-2,3,0,5), AJ(1) }
T._affine.sAffineAnims_StretchBattlerUp = { A(10,-13,0,10), A(-10,13,0,10), AE }
T._affine.sAffineAnims_Torment = { A(-12,8,0,4), A(20,-20,0,4), A(-8,12,0,4), AE }
T._affine.sAngerMarkAffineAnimCmds = { A(11,11,0,8), A(-11,-11,0,8), AE }
T._affine.sAnim_Unused = { A(256,0,0,0), A(0,32,0,12), A(0,-32,0,11), AE }
T._affine.sAromatherapyBigFlowerAffineAnimCmds = { A(256,256,0,0), A(0,0,4,1), AJ(1) }
T._affine.sBarrageBallAffineAnimCmds1 = { A(0,0,-4,24), AE }
T._affine.sBarrageBallAffineAnimCmds2 = { A(256,256,-64,0), A(0,0,4,24), AE }
T._affine.sBulletSeedAffineAnimCmds = { A(0,0,20,1), AJ(0) }
T._affine.sConversionAffineAnimCmds = { A(512,512,0,0), AE }
T._affine.sDeepInhaleAffineAnimCmds = { A(16,0,0,4), A(0,-3,0,16), A(4,0,0,4), A(0,0,0,24), A(-5,3,0,16), AE }
T._affine.sDummyAffineAnim = { AE }
T._affine.sFacadeSquishAffineAnimCmds = { A(-16,16,0,6), A(16,-16,0,12), A(-16,16,0,6), AE }
T._affine.sFallingBagAffineAnimCmds1 = { A(0,0,-4,10), A(0,0,4,20), A(0,0,-4,10), AE }
T._affine.sFallingBagAffineAnimCmds2 = { A(0,0,-1,2), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,4), A(0,0,-1,4), A(0,0,1,2), AE }
T._affine.sFallingCoinAffineAnimCmds = { A(0,0,10,1), AJ(0) }
T._affine.sFangAffineAnimCmds = { A(512,512,0,0), A(-32,-32,0,8), AE }
T._affine.sGrowAndShrinkAffineAnimCmds = { A(-4,-5,0,12), A(0,0,0,24), A(4,5,0,12), AE }
T._affine.sGrowingRingAffineAnimCmds = { A(32,32,0,0), A(7,7,0,-56), AE }
T._affine.sGuardRingAffineAnimCmds1 = { A(256,256,0,0), AE }
T._affine.sGuardRingAffineAnimCmds2 = { A(512,256,0,0), AE }
T._affine.sHiddenPowerOrbAffineAnimCmds = { A(128,128,0,0), A(8,8,0,1), AJ(1) }
T._affine.sHyperVoiceRingAffineAnimCmds = { A(16,16,0,0), A(11,11,0,45), AE }
T._affine.sKnockOffStrikeAffineanimCmds1 = { A(256,256,0,0), A(0,0,-4,8), AE }
T._affine.sKnockOffStrikeAffineanimCmds2 = { A(-256,256,0,0), A(0,0,4,8), AE }
T._affine.sLetterZAffineAnimCmds = { A(-7,-7,-3,16), A(7,7,3,16), AJ(0) }
T._affine.sMeanLookEyeAffineAnimCmds1 = { A(384,384,0,0), A(-32,24,0,5), A(24,-32,0,5), AJ(1) }
T._affine.sMeanLookEyeAffineAnimCmds2 = { A(48,48,0,0), A(32,32,0,6), AE }
T._affine.sMetronomeFingerAffineAnimCmds1 = { A(16,16,0,0), A(30,30,0,8), AE }
T._affine.sMetronomeFingerAffineAnimCmds2 = { A(0,0,4,11), A(0,0,-4,11), AL(2), A(-30,-30,0,8), AE }
T._affine.sMetronomeFingerAffineAnimCmds2_2 = { A(16,16,0,0), A(30,30,0,8), A(0,0,0,16), AL(0), A(0,0,4,11), A(0,0,-4,11), AL(2), A(-30,-30,0,8), AE }
T._affine.sMilkBottleAffineAnimCmds1 = { A(256,256,0,0), AE }
T._affine.sMilkBottleAffineAnimCmds2 = { A(0,0,2,12), A(0,0,0,6), A(0,0,-2,24), A(0,0,0,6), A(0,0,2,12), AJ(0) }
T._affine.sMimicOrbAffineAnimCmds1 = { A(0,0,0,0), A(48,48,0,14), AE }
T._affine.sMimicOrbAffineAnimCmds2 = { A(-16,-16,0,1), AJ(0) }
T._affine.sPerishSongMusicNoteAffineAnimCmds1 = { A(0,0,0,5), AE }
T._affine.sPerishSongMusicNoteAffineAnimCmds2 = { A(0,0,-8,16), AE }
T._affine.sPerishSongMusicNoteAffineAnimCmds3 = { A(0,0,8,16), AE }
T._affine.sPowerAbsorptionOrbAffineAnimCmds = { A(-5,-5,0,1), AJ(0) }
T._affine.sRazorWindTornadoAffineAnimCmds = { A(16,256,0,0), A(4,0,0,40), AE }
T._affine.sRecycleSpriteAffineAnimCmds = { A(0,0,-4,64), AJ(0) }
T._affine.sSilverWindBigSparkAffineAnimCmds = { A(256,256,0,0), A(0,0,-10,1), AJ(1) }
T._affine.sSilverWindMediumSparkAffineAnimCmds = { A(192,192,0,0), A(0,0,-12,1), AJ(1) }
T._affine.sSilverWindSmallSparkAffineAnimCmds = { A(143,143,0,0), A(0,0,-15,1), AJ(1) }
T._affine.sSlackOffSquishAffineAnimCmds = { A(0,16,0,4), A(-2,0,0,8), A(0,4,0,4), A(0,0,0,24), A(1,-5,0,16), AE }
T._affine.sSleepLetterZAffineAnimCmds1 = { A(20,20,-30,0), A(8,8,1,24), AE }
T._affine.sSleepLetterZAffineAnimCmds1_2 = { AL(0), A(0,0,1,24), AL(10) }
T._affine.sSleepLetterZAffineAnimCmds2 = { A(20,20,30,0), A(8,8,-1,24), AE }
T._affine.sSleepLetterZAffineAnimCmds2_2 = { AL(0), A(0,0,-1,24), AL(10) }
T._affine.sSlowFlyingMusicNotesAffineAnimCmds = { A(160,160,0,0), A(4,4,0,1), AJ(1) }
T._affine.sSmellingSaltsSquishAffineAnimCmds = { A(0,-16,0,6), A(0,16,0,6), AE }
T._affine.sSmokeBallEscapeCloudAffineAnimCmds1 = { A(128,128,0,0), A(-4,-6,0,16), A(4,6,0,16), AJ(0) }
T._affine.sSmokeBallEscapeCloudAffineAnimCmds2 = { A(192,192,0,0), A(4,6,0,16), A(-4,-6,0,16), AJ(0) }
T._affine.sSmokeBallEscapeCloudAffineAnimCmds3 = { A(256,256,0,0), A(4,6,0,16), A(-4,-6,0,16), AJ(0) }
T._affine.sSmokeBallEscapeCloudAffineAnimCmds4 = { A(256,256,0,0), A(8,10,0,30), A(-8,-10,0,16), AJ(0) }
T._affine.sSoftBoiledEggAffineAnimCmds1 = { A(0,0,-8,2), A(0,0,8,4), A(0,0,-8,2), AJ(0) }
T._affine.sSoftBoiledEggAffineAnimCmds2 = { A(256,256,0,0), AE }
T._affine.sSoftBoiledEggAffineAnimCmds3 = { A(-8,4,0,8), AL(0), A(16,-8,0,8), A(-16,8,0,8), AL(1), A(256,256,0,0), A(0,0,0,15), AE }
T._affine.sSpitUpDeformMonAffineAnimCmds = { A(0,6,0,20), A(0,0,0,20), A(0,-18,0,6), A(-18,-18,0,3), A(0,0,0,15), A(4,4,0,13), AE }
T._affine.sSpitUpOrbAffineAnimCmds = { A(128,128,0,0), A(8,8,0,1), AJ(1) }
T._affine.sSplashEffectAffineAnimCmds = { A(-6,4,0,8), A(10,-10,0,8), A(-4,6,0,8), AE }
T._affine.sSpotlightAffineAnimCmds1 = { A(0,384,0,0), A(16,0,0,20), AE }
T._affine.sSpotlightAffineAnimCmds2 = { A(320,384,0,0), A(-16,0,0,19), AE }
T._affine.sStockpileAbsorptionOrbAffineCmds = { A(320,320,0,0), A(-14,-14,0,1), AJ(1) }
T._affine.sStockpileDeformMonAffineAnimCmds = { A(8,-8,0,12), A(-16,16,0,12), A(8,-8,0,12), AL(1), AE }
T._affine.sStretchAttackerAffineAnimCmds = { A(96,-13,0,8), AE }
T._affine.sStrongFrustrationAffineAnimCmds = { A(0,-15,0,7), A(0,15,0,7), AL(2), AE }
T._affine.sSwallowDeformMonAffineAnimCmds = { A(0,6,0,20), A(0,0,0,20), A(7,-30,0,6), A(0,0,0,20), A(-2,3,0,20), AE }
T._affine.sSwiftStarAffineAnimCmds = { A(0,0,0,1), AJ(0) }
T._affine.sSwordsDanceBladeAffineAnimCmds = { A(16,256,0,0), A(20,0,0,12), A(0,0,0,32), AE }
T._affine.sThinRingExpandingAffineAnimCmds1 = { A(16,16,0,0), A(16,16,0,30), AE }
T._affine.sThinRingExpandingAffineAnimCmds2 = { A(16,16,0,0), A(32,32,0,15), AE }
T._affine.sThinRingShrinkingAffineAnimCmds = { A(512,512,0,0), A(-16,-16,0,30), AE }
T._affine.sThrashMoveMonAffineAnimCmds = { A(-10,9,0,7), A(20,-20,0,7), A(-20,20,0,7), A(10,-9,0,7), AL(2), AE }
T._affine.sTriAttackTriangleAffineAnimCmds = { A(0,0,5,40), A(0,0,10,10), A(0,0,15,10), A(0,0,20,40), AJ(0) }
T._affine.sTrickBagAffineAnimCmds1 = { A(0,0,0,3), AE }
T._affine.sTrickBagAffineAnimCmds2 = { A(0,-10,0,3), A(0,-6,0,3), A(0,-2,0,3), A(0,0,0,3), A(0,2,0,3), A(0,6,0,3), A(0,10,0,3), AE }
T._affine.sUproarAffineAnimCmds = { A(-12,8,0,4), A(20,-20,0,4), A(-8,12,0,4), AE }
T._affine.sWaterPulseRingAffineAnimCmds = { A(5,5,0,10), A(-10,-10,0,10), A(10,10,0,10), A(-10,-10,0,10), A(10,10,0,10), A(-10,-10,0,10), A(10,10,0,10), AE }
T._affine.sWavyMusicNotesAffineAnimCmds = { A(12,12,0,16), A(65524,65524,0,16), AJ(0) }
T._affine.sYawnCloudAffineAnimCmds1 = { A(128,128,0,0), A(-8,-8,0,8), A(8,8,0,8), AJ(0) }
T._affine.sYawnCloudAffineAnimCmds2 = { A(192,192,0,0), A(8,8,0,8), A(-8,-8,0,8), AJ(0) }
T._affine.sYawnCloudAffineAnimCmds3 = { A(256,256,0,0), A(8,8,0,8), A(-8,-8,0,8), AJ(0) }
return T

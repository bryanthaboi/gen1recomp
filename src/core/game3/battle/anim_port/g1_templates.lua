-- pokefirered/src/battle_anim_effects_1.c:1
local T = {}
local A = {}
A.gAnims_BasicFire = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {f=64,d=4}, {jump=0} } }
A.gAnims_SmallBubblePair = { [0] = { {f=12,d=6}, {f=13,d=6}, {jump=0} } }
A.gAnims_WaterBubble = { [0] = { {f=0,d=1}, {e=true} } }
A.gAnims_WaterMudOrb = { [0] = { {f=0,d=1}, {f=4,d=1}, {f=8,d=1}, {f=12,d=1}, {jump=0} } }
A.gDummySpriteAnimTable = { [0] = { {e=true} } }
A.gMusicNotesAnimTable = { [0] = { {f=0,d=10}, {e=true} }, [1] = { {f=4,d=10}, {e=true} }, [2] = { {f=8,d=41}, {e=true} }, [3] = { {f=12,d=10}, {e=true} }, [4] = { {f=16,d=10}, {e=true} }, [5] = { {f=20,d=10}, {e=true} }, [6] = { {f=0,d=10,v=true}, {e=true} }, [7] = { {f=4,d=10,v=true}, {e=true} } }
A.sAffineAnims_AirWaveCrescent = { [0] = { {f=0,d=3}, {f=0,d=3,h=true}, {f=0,d=3,v=true}, {f=0,d=3,h=true,v=true}, {jump=0} } }
A.sAngelSpriteAnimTable = { [0] = { {f=0,d=24}, {e=true} } }
A.sAnims_AcidPoisonDroplet = { [0] = { {f=4,d=1}, {e=true} } }
A.sAnims_AuroraBeamRing = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=4,d=1}, {e=true} } }
A.sAnims_BasicRock = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=16,d=1}, {e=true} }, [2] = { {f=32,d=1}, {e=true} }, [3] = { {f=48,d=1}, {e=true} }, [4] = { {f=64,d=1}, {e=true} }, [5] = { {f=80,d=1}, {e=true} } }
A.sAnims_BasicRock__2 = { [0] = { {f=32,d=1}, {e=true} }, [1] = { {f=48,d=1}, {e=true} }, [2] = { {f=64,d=1}, {e=true} }, [3] = { {f=80,d=1}, {e=true} } }
A.sAnims_BasicRock__4 = { [0] = { {f=64,d=1}, {e=true} }, [1] = { {f=80,d=1}, {e=true} } }
A.sAnims_BentSpoon = { [0] = { {f=8,d=60,h=true}, {f=16,d=5,h=true}, {f=8,d=5,h=true}, {f=0,d=5,h=true}, {f=8,d=22,h=true}, {loop=0}, {f=16,d=5,h=true}, {f=8,d=5,h=true}, {f=0,d=5,h=true}, {f=8,d=5,h=true}, {loop=1}, {f=8,d=22,h=true}, {f=24,d=3,h=true}, {f=32,d=3,h=true}, {f=40,d=22,h=true}, {e=true} }, [1] = { {f=8,d=60}, {f=16,d=5}, {f=8,d=5}, {f=0,d=5}, {f=8,d=22}, {loop=0}, {f=16,d=5}, {f=8,d=5}, {f=0,d=5}, {f=8,d=5}, {loop=1}, {f=8,d=22}, {f=24,d=3}, {f=32,d=3}, {f=40,d=22}, {e=true} } }
A.sAnims_BlizzardIceCrystal = { [0] = { {f=8,d=1}, {e=true} } }
A.sAnims_ClawSlash = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {f=64,d=4}, {e=true} }, [1] = { {f=0,d=4,h=true}, {f=16,d=4,h=true}, {f=32,d=4,h=true}, {f=48,d=4,h=true}, {f=64,d=4,h=true}, {e=true} } }
A.sAnims_Cloud = { [0] = { {f=0,d=20}, {jump=0} } }
A.sAnims_ConfusionDuck = { [0] = { {f=0,d=8}, {f=4,d=8}, {f=0,d=8,h=true}, {f=8,d=8}, {jump=0} }, [1] = { {f=0,d=8,h=true}, {f=4,d=8}, {f=0,d=8}, {f=8,d=8}, {jump=0} } }
A.sAnims_ConstrictBinding = { [0] = { {f=0,d=4}, {f=32,d=4}, {f=64,d=4}, {f=96,d=4}, {e=true} }, [1] = { {f=0,d=4,h=true}, {f=32,d=4,h=true}, {f=64,d=4,h=true}, {f=96,d=4,h=true}, {e=true} } }
A.sAnims_DragonBreathFire = { [0] = { {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {jump=0} }, [1] = { {f=16,d=3,h=true,v=true}, {f=32,d=3,h=true,v=true}, {f=48,d=3,h=true,v=true}, {jump=0} } }
A.sAnims_DragonRageFire = { [0] = { {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {jump=0} }, [1] = { {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {jump=0} } }
A.sAnims_DragonRageFirePlume = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=5}, {f=48,d=5}, {f=64,d=5}, {e=true} } }
A.sAnims_ElectricPuff = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {e=true} } }
A.sAnims_FallingFeather = { [0] = { {f=0,d=0}, {e=true} }, [1] = { {f=16,d=0,h=true}, {e=true} } }
A.sAnims_FireBlastCross = { [0] = { {f=32,d=6}, {f=48,d=6}, {jump=0} } }
A.sAnims_FirePlume = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=5}, {f=48,d=5}, {f=64,d=5}, {jump=0} } }
A.sAnims_FireSpiralSpread = { [0] = { {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {jump=0} }, [1] = { {f=16,d=4,h=true,v=true}, {f=32,d=4,h=true,v=true}, {f=48,d=4,h=true,v=true}, {jump=0} } }
A.sAnims_FlamethrowerFlame = { [0] = { {f=16,d=2}, {f=32,d=2}, {f=48,d=2}, {jump=0} } }
A.sAnims_FlyingRock = { [0] = { {f=32,d=1}, {e=true} }, [1] = { {f=48,d=1}, {e=true} }, [2] = { {f=64,d=1}, {e=true} } }
A.sAnims_FurySwipes = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {e=true} }, [1] = { {f=0,d=4,h=true}, {f=16,d=4,h=true}, {f=32,d=4,h=true}, {f=48,d=4,h=true}, {e=true} } }
A.sAnims_HandsAndFeet = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=16,d=1}, {e=true} }, [2] = { {f=32,d=1}, {e=true} }, [3] = { {f=48,d=1}, {e=true} }, [4] = { {f=48,d=1,h=true}, {e=true} } }
A.sAnims_HandsAndFeet__1 = { [0] = { {f=16,d=1}, {e=true} }, [1] = { {f=32,d=1}, {e=true} }, [2] = { {f=48,d=1}, {e=true} }, [3] = { {f=48,d=1,h=true}, {e=true} } }
A.sAnims_HandsAndFeet__3 = { [0] = { {f=48,d=1}, {e=true} }, [1] = { {f=48,d=1,h=true}, {e=true} } }
A.sAnims_IceBallChunk = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {f=64,d=4}, {e=true} } }
A.sAnims_IceCrystalLarge = { [0] = { {f=4,d=1}, {e=true} } }
A.sAnims_IceCrystalSmall = { [0] = { {f=6,d=1}, {e=true} } }
A.sAnims_IceGroundSpike = { [0] = { {f=0,d=5}, {f=2,d=5}, {f=4,d=5}, {f=6,d=5}, {f=4,d=5}, {f=2,d=5}, {f=0,d=5}, {e=true} } }
A.sAnims_LargeFlame = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=64,d=3}, {f=80,d=3}, {f=96,d=3}, {f=112,d=3}, {jump=0} } }
A.sAnims_Lick = { [0] = { {f=0,d=2}, {f=8,d=2}, {f=16,d=2}, {f=24,d=2}, {f=32,d=2}, {e=true} } }
A.sAnims_Lightning = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=8}, {f=48,d=5}, {f=64,d=5}, {e=true} } }
A.sAnims_MudSlapMud = { [0] = { {f=1,d=1}, {e=true} } }
A.sAnims_OutrageOverheatFire = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {f=64,d=4}, {jump=0} } }
A.sAnims_PoisonProjectile = { [0] = { {f=0,d=1}, {e=true} } }
A.sAnims_QuestionMark = { [0] = { {f=0,d=6}, {f=16,d=6}, {f=32,d=6}, {f=48,d=6}, {f=64,d=6}, {f=80,d=6}, {f=96,d=18}, {e=true} } }
A.sAnims_ReflectSparkle = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=64,d=3}, {e=true} } }
A.sAnims_RevengeBigScratch = { [0] = { {f=0,d=6}, {f=64,d=6}, {e=true} }, [1] = { {f=0,d=6,h=true,v=true}, {f=64,d=6,h=true,v=true}, {e=true} }, [2] = { {f=0,d=6,h=true}, {f=64,d=6,h=true}, {e=true} } }
A.sAnims_RevengeSmallScratch = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {e=true} }, [1] = { {f=0,d=4,v=true}, {f=16,d=4,v=true}, {f=32,d=4,v=true}, {e=true} }, [2] = { {f=0,d=4,h=true}, {f=16,d=4,h=true}, {f=32,d=4,h=true}, {e=true} } }
A.sAnims_SludgeBombHit = { [0] = { {f=8,d=1}, {e=true} } }
A.sAnims_Snowball = { [0] = { {f=7,d=1}, {e=true} } }
A.sAnims_SpecialScreenSparkle = { [0] = { {f=0,d=5}, {f=4,d=5}, {f=8,d=5}, {f=12,d=5}, {e=true} } }
A.sAnims_SpinningSparkle = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=64,d=3}, {e=true} } }
A.sAnims_ThunderboltOrb = { [0] = { {f=0,d=6}, {f=16,d=6}, {f=32,d=6}, {jump=0} } }
A.sAnims_ToxicBubble = { [0] = { {f=0,d=5}, {f=8,d=5}, {f=16,d=5}, {f=24,d=5}, {e=true} } }
A.sAnims_WaterBubbleProjectile = { [0] = { {f=0,d=1}, {f=4,d=5}, {f=8,d=5}, {e=true} } }
A.sAnims_WaterGunDroplet = { [0] = { {f=4,d=1}, {e=true} } }
A.sAnims_WaterPulseBubble = { [0] = { {f=8,d=1}, {e=true} }, [1] = { {f=9,d=1}, {e=true} } }
A.sAnims_WeatherBallNormal = { [0] = { {f=0,d=3}, {jump=0} } }
A.sAnims_WeatherBallWaterDown = { [0] = { {f=4,d=1}, {e=true} } }
A.sAnims_Whip = { [0] = { {f=64,d=3}, {f=80,d=3}, {f=96,d=3}, {f=112,d=6}, {e=true} }, [1] = { {f=64,d=3,h=true}, {f=80,d=3,h=true}, {f=96,d=3,h=true}, {f=112,d=6,h=true}, {e=true} } }
A.sAnims_WhirlwindLines = { [0] = { {f=0,d=1}, {f=8,d=1}, {f=16,d=1}, {f=8,d=1,h=true}, {f=0,d=1,h=true}, {e=true} } }
A.sAnims_WillOWispFire = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=5}, {f=48,d=5}, {jump=0} } }
A.sAnims_WillOWispOrb = { [0] = { {f=0,d=5}, {f=4,d=5}, {f=8,d=5}, {f=12,d=5}, {jump=0} }, [1] = { {f=16,d=5}, {e=true} }, [2] = { {f=20,d=5}, {e=true} }, [3] = { {f=20,d=5}, {e=true} } }
A.sBellAnimTable = { [0] = { {f=0,d=6}, {f=16,d=6}, {f=32,d=15}, {f=16,d=6}, {f=0,d=6}, {f=16,d=6,h=true}, {f=32,d=15,h=true}, {f=16,d=6,h=true}, {f=0,d=6}, {f=16,d=6}, {f=32,d=15}, {f=16,d=6}, {f=0,d=6}, {e=true} } }
A.sBreathPuffAnimTable = { [0] = { {f=0,d=4,h=true}, {f=4,d=40,h=true}, {f=8,d=4,h=true}, {f=12,d=4,h=true}, {e=true} }, [1] = { {f=0,d=4}, {f=4,d=40}, {f=8,d=4}, {f=12,d=4}, {e=true} } }
A.sCoinAnimTable = { [0] = { {f=8,d=1}, {e=true} } }
A.sConversion2AnimTable = { [0] = { {f=0,d=5}, {f=1,d=5}, {f=2,d=5}, {f=3,d=5}, {e=true} } }
A.sConversionAnimTable = { [0] = { {f=3,d=5}, {f=2,d=5}, {f=1,d=5}, {f=0,d=5}, {e=true} } }
A.sCuttingSliceAnimTable = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=5}, {f=48,d=5}, {e=true} } }
A.sDevilAnimTable = { [0] = { {f=0,d=3}, {jump=0} }, [1] = { {f=16,d=3}, {jump=0} } }
A.sEclipsingOrbAnimTable = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=32,d=3,h=true}, {f=16,d=3,h=true}, {f=0,d=3,h=true}, {loop=1}, {e=true} } }
A.sEndureEnergyAnimTable = { [0] = { {f=0,d=4}, {f=8,d=12}, {f=16,d=4}, {f=24,d=4}, {e=true} } }
A.sExplosionAnimTable = { [0] = { {f=0,d=5}, {f=16,d=5}, {f=32,d=5}, {f=48,d=5}, {e=true} } }
A.sEyeSparkleAnimTable = { [0] = { {f=0,d=4}, {f=4,d=4}, {f=8,d=4}, {f=4,d=4}, {f=0,d=4}, {e=true} } }
A.sFallingBagAnimTable = { [0] = { {f=0,d=30}, {e=true} } }
A.sFangAnimTable = { [0] = { {f=0,d=8}, {f=16,d=16}, {f=32,d=4}, {f=48,d=4}, {e=true} } }
A.sGrantingStarsAnimTable = { [0] = { {f=0,d=7}, {f=16,d=7}, {f=32,d=7}, {f=48,d=7}, {f=64,d=7}, {f=80,d=7}, {f=96,d=7}, {f=112,d=7}, {jump=0} } }
A.sGreenStarAnimTable = { [0] = { {f=0,d=6}, {f=4,d=6}, {jump=0} }, [1] = { {f=8,d=6}, {e=true} }, [2] = { {f=12,d=6}, {e=true} } }
A.sGuillotineAnimTable = { [0] = { {f=0,d=2}, {f=16,d=2}, {f=32,d=1}, {e=true} }, [1] = { {f=0,d=2,h=true,v=true}, {f=16,d=2,h=true,v=true}, {f=32,d=1,h=true,v=true}, {e=true} } }
A.sHealingBlueStarAnimTable = { [0] = { {f=0,d=2}, {f=16,d=2}, {f=32,d=2}, {f=48,d=3}, {f=64,d=5}, {f=80,d=3}, {f=96,d=2}, {f=0,d=2}, {e=true} } }
A.sIngrainOrbAnimTable = { [0] = { {f=3,d=3}, {f=0,d=5}, {jump=0} } }
A.sIngrainRootAnimTable = { [0] = { {f=0,d=7}, {f=16,d=7}, {f=32,d=7}, {f=48,d=7}, {e=true} }, [1] = { {f=0,d=7,h=true}, {f=16,d=7,h=true}, {f=32,d=7,h=true}, {f=48,d=7,h=true}, {e=true} }, [2] = { {f=0,d=7}, {f=16,d=7}, {f=32,d=7}, {e=true} }, [3] = { {f=0,d=7,h=true}, {f=16,d=7,h=true}, {f=32,d=7,h=true}, {e=true} } }
A.sKinesisZapEnergyAnimTable = { [0] = { {f=0,d=3,h=true}, {f=8,d=3,h=true}, {f=16,d=3,h=true}, {f=24,d=3,h=true}, {f=32,d=3,h=true}, {f=40,d=3,h=true}, {f=48,d=3,h=true}, {loop=1}, {e=true} } }
A.sKnockOffStrikeAnimTable = { [0] = { {f=0,d=4}, {f=64,d=4}, {e=true} } }
A.sLeafBladeAnimTable = { [0] = { {f=28,d=1}, {e=true} }, [1] = { {f=32,d=1}, {e=true} }, [2] = { {f=20,d=1}, {e=true} }, [3] = { {f=28,d=1,h=true}, {e=true} }, [4] = { {f=16,d=1}, {e=true} }, [5] = { {f=16,d=1,h=true}, {e=true} }, [6] = { {f=28,d=1}, {e=true} } }
A.sLeechSeedAnimTable = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=4,d=7}, {f=8,d=7}, {jump=0} } }
A.sLeerAnimTable = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=64,d=3}, {e=true} } }
A.sLetterZAnimTable = { [0] = { {f=0,d=3}, {e=true} } }
A.sMetronomeThroughtBubbleAnimTable = { [0] = { {f=0,d=2,h=true}, {f=16,d=2,h=true}, {f=32,d=2,h=true}, {f=48,d=2,h=true}, {e=true} }, [1] = { {f=0,d=2}, {f=16,d=2}, {f=32,d=2}, {f=48,d=2}, {e=true} }, [2] = { {f=48,d=2,h=true}, {f=32,d=2,h=true}, {f=16,d=2,h=true}, {f=0,d=2,h=true}, {e=true} }, [3] = { {f=48,d=2}, {f=32,d=2}, {f=16,d=2}, {f=0,d=2}, {e=true} } }
A.sMoonlightSparkleAnimTable = { [0] = { {f=0,d=8}, {f=4,d=8}, {f=8,d=8}, {f=12,d=8}, {jump=0} } }
A.sMovementWavesAnimTable = { [0] = { {f=0,d=8}, {f=16,d=8}, {f=32,d=8}, {f=16,d=8}, {e=true} }, [1] = { {f=16,d=8,h=true}, {f=32,d=8,h=true}, {f=16,d=8,h=true}, {f=0,d=8,h=true}, {e=true} } }
A.sOctazookaAnimTable = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=3}, {f=48,d=3}, {f=64,d=3}, {e=true} } }
A.sOpeningEyeAnimTable = { [0] = { {f=0,d=40}, {f=16,d=8}, {f=32,d=40}, {e=true} } }
A.sPainSplitAnimCmdTable = { [0] = { {f=0,d=5}, {f=4,d=9}, {f=8,d=5}, {e=true} } }
A.sPetalDanceBigFlowerAnimTable = { [0] = { {f=0,d=1}, {e=true} } }
A.sPetalDanceSmallFlowerAnimTable = { [0] = { {f=4,d=1}, {e=true} } }
A.sPowderParticlesAnimTable = { [0] = { {f=0,d=5}, {f=2,d=5}, {f=4,d=5}, {f=6,d=5}, {f=8,d=5}, {f=10,d=5}, {f=12,d=5}, {f=14,d=5}, {jump=0} } }
A.sPowerAbsorptionOrbAnimTable = { [0] = { {f=8,d=1}, {e=true} } }
A.sPresentHealParticleAnimTable = { [0] = { {f=0,d=4}, {f=4,d=4}, {f=8,d=4}, {f=12,d=4}, {e=true} } }
A.sRapidSpinAnimTable = { [0] = { {f=0,d=2}, {f=8,d=2}, {f=16,d=2}, {jump=0} } }
A.sRazorLeafCutterAnimTable = { [0] = { {f=0,d=3}, {f=0,d=3,h=true}, {f=0,d=3,h=true,v=true}, {f=0,d=3,v=true}, {jump=0} } }
A.sRazorLeafParticleAnimTable = { [0] = { {f=0,d=5}, {f=4,d=5}, {f=8,d=5}, {f=12,d=5}, {f=16,d=5}, {f=20,d=5}, {f=16,d=5}, {f=12,d=5}, {f=8,d=5}, {f=4,d=5}, {jump=0} }, [1] = { {f=24,d=5}, {f=28,d=5}, {f=32,d=5}, {e=true} } }
A.sRoarNoiseLineAnimTable = { [0] = { {f=0,d=3}, {f=16,d=3}, {jump=0} }, [1] = { {f=32,d=3}, {f=48,d=3}, {jump=0} } }
A.sScratchAnimTable = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {f=64,d=4}, {e=true} } }
A.sSharpenSphereAnimTable = { [0] = { {f=0,d=18}, {f=0,d=6}, {f=16,d=18}, {f=0,d=6}, {f=16,d=6}, {f=32,d=18}, {f=16,d=6}, {f=32,d=6}, {f=48,d=18}, {f=32,d=6}, {f=48,d=6}, {f=64,d=18}, {f=48,d=6}, {f=64,d=54}, {e=true} } }
A.sSlashSliceAnimTable = { [0] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=48,d=4}, {e=true} }, [1] = { {f=48,d=4}, {e=true} } }
A.sSleepLetterZAnimTable = { [0] = { {f=0,d=40}, {e=true} } }
A.sSolarBeamBigOrbAnimTable = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=1,d=1}, {e=true} }, [2] = { {f=2,d=1}, {e=true} }, [3] = { {f=3,d=1}, {e=true} }, [4] = { {f=4,d=1}, {e=true} }, [5] = { {f=5,d=1}, {e=true} }, [6] = { {f=6,d=1}, {e=true} } }
A.sSolarBeamSmallOrbAnimTable = { [0] = { {f=7,d=1}, {e=true} } }
A.sSporeParticleAnimTable = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=4,d=7}, {e=true} } }
A.sSpriteAnimTable_SafariRock = { [0] = { {f=64,d=1}, {e=true} } }
A.sSuperFangAnimTable = { [0] = { {f=0,d=2}, {f=16,d=2}, {f=32,d=2}, {f=48,d=2}, {e=true} } }
A.sSweetScentPetalAnimCmdTable = { [0] = { {f=0,d=8}, {f=1,d=8}, {f=2,d=8}, {f=3,d=8}, {f=3,d=8,v=true}, {f=2,d=8,v=true}, {f=0,d=8,v=true}, {f=1,d=8,v=true}, {jump=0} }, [1] = { {f=0,d=8,h=true}, {f=1,d=8,h=true}, {f=2,d=8,h=true}, {f=3,d=8,h=true}, {f=3,d=8,h=true,v=true}, {f=2,d=8,h=true,v=true}, {f=0,d=8,h=true,v=true}, {f=1,d=8,h=true,v=true}, {jump=0} }, [2] = { {f=0,d=8}, {e=true} } }
A.sTauntFingerAnimTable = { [0] = { {f=0,d=1}, {e=true} }, [1] = { {f=0,d=1,h=true}, {e=true} }, [2] = { {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {f=16,d=4}, {f=0,d=4}, {f=16,d=4}, {f=32,d=4}, {e=true} }, [3] = { {f=0,d=4,h=true}, {f=16,d=4,h=true}, {f=32,d=4,h=true}, {f=16,d=4,h=true}, {f=0,d=4,h=true}, {f=16,d=4,h=true}, {f=32,d=4,h=true}, {e=true} } }
A.sTriAttackTriangleAnimTable = { [0] = { {f=0,d=8}, {e=true} } }
A.sViceGripAnimTable = { [0] = { {f=0,d=3}, {f=16,d=3}, {f=32,d=20}, {e=true} }, [1] = { {f=0,d=3,h=true,v=true}, {f=16,d=3,h=true,v=true}, {f=32,d=20,h=true,v=true}, {e=true} } }
local F = {}
F.gAffineAnims_Bite = { [0] = { {xs=0,ys=0,r=0,d=1}, {e=true} }, [1] = { {xs=0,ys=0,r=32,d=1}, {e=true} }, [2] = { {xs=0,ys=0,r=64,d=1}, {e=true} }, [3] = { {xs=0,ys=0,r=96,d=1}, {e=true} }, [4] = { {xs=0,ys=0,r=-128,d=1}, {e=true} }, [5] = { {xs=0,ys=0,r=-96,d=1}, {e=true} }, [6] = { {xs=0,ys=0,r=-64,d=1}, {e=true} }, [7] = { {xs=0,ys=0,r=-32,d=1}, {e=true} } }
F.gAffineAnims_Droplet = { [0] = { {xs=-16,ys=16,r=0,d=6}, {xs=16,ys=-16,r=0,d=6}, {jump=0} } }
F.gAffineAnims_LusterPurgeCircle = { [0] = { {xs=32,ys=32,r=0,d=0}, {xs=4,ys=4,r=0,d=120}, {e=true} } }
F.gDummySpriteAffineAnimTable = { [0] = { {e=true} } }
F.gGrowingRingAffineAnimTable = { [0] = { {xs=32,ys=32,r=0,d=0}, {xs=7,ys=7,r=0,d=200}, {e=true} } }
F.sAbsorptionOrbAffineAnimTable = { [0] = { {xs=-5,ys=-5,r=0,d=1}, {jump=0} } }
F.sAffineAnims_AuroraBeamRing = { [0] = { {xs=0,ys=0,r=0,d=1}, {xs=96,ys=96,r=0,d=1}, {e=true} } }
F.sAffineAnims_BasicRock = { [0] = { {xs=0,ys=0,r=-5,d=5}, {jump=0} }, [1] = { {xs=0,ys=0,r=5,d=5}, {jump=0} } }
F.sAffineAnims_Bonemerang = { [0] = { {xs=0,ys=0,r=15,d=1}, {jump=0} } }
F.sAffineAnims_BounceBallLand = { [0] = { {xs=160,ys=256,r=0,d=0}, {e=true} } }
F.sAffineAnims_BounceBallShrink = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=40,ys=0,r=0,d=6}, {xs=0,ys=-32,r=0,d=5}, {xs=-20,ys=0,r=0,d=7}, {xs=-20,ys=-20,r=0,d=5}, {e=true} } }
F.sAffineAnims_Bubble = { [0] = { {xs=156,ys=156,r=0,d=0}, {xs=5,ys=5,r=0,d=20}, {e=true} } }
F.sAffineAnims_ConfuseRayBallBounce = { [0] = { {xs=30,ys=30,r=10,d=5}, {xs=-30,ys=-30,r=10,d=5}, {jump=0} } }
F.sAffineAnims_ConstrictBinding = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=-11,ys=0,r=0,d=6}, {xs=11,ys=0,r=0,d=6}, {e=true} }, [1] = { {xs=-256,ys=256,r=0,d=0}, {xs=11,ys=0,r=0,d=6}, {xs=-11,ys=0,r=0,d=6}, {e=true} } }
F.sAffineAnims_DiveBall = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=40,ys=0,r=0,d=6}, {xs=0,ys=-32,r=0,d=5}, {xs=-16,ys=32,r=0,d=10}, {e=true} } }
F.sAffineAnims_DragonBreathFire = { [0] = { {xs=80,ys=80,r=127,d=0}, {xs=13,ys=13,r=0,d=100}, {e=true} }, [1] = { {xs=80,ys=80,r=0,d=0}, {xs=13,ys=13,r=0,d=100}, {e=true} } }
F.sAffineAnims_DragonRageFire = { [0] = { {xs=100,ys=100,r=127,d=1}, {e=true} }, [1] = { {xs=100,ys=100,r=0,d=1}, {e=true} } }
F.sAffineAnims_FlashingSpark = { [0] = { {xs=0,ys=0,r=20,d=1}, {jump=0} } }
F.sAffineAnims_FlyBallAttack = { [0] = { {xs=0,ys=0,r=50,d=1}, {e=true} }, [1] = { {xs=0,ys=0,r=-40,d=1}, {e=true} } }
F.sAffineAnims_FlyBallUp = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=40,ys=0,r=0,d=6}, {xs=0,ys=-32,r=0,d=5}, {xs=-16,ys=32,r=0,d=10}, {e=true} } }
F.sAffineAnims_FocusPunchFist = { [0] = { {xs=512,ys=512,r=0,d=0}, {xs=-32,ys=-32,r=0,d=8}, {e=true} } }
F.sAffineAnims_GrowingElectricOrb = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=4,ys=4,r=0,d=60}, {xs=256,ys=256,r=0,d=0}, {loop=0}, {xs=-4,ys=-4,r=0,d=5}, {xs=4,ys=4,r=0,d=5}, {loop=10}, {e=true} }, [1] = { {xs=16,ys=16,r=0,d=0}, {xs=8,ys=8,r=0,d=30}, {xs=256,ys=256,r=0,d=0}, {xs=-4,ys=-4,r=0,d=5}, {xs=4,ys=4,r=0,d=5}, {jump=3} }, [2] = { {xs=16,ys=16,r=0,d=0}, {xs=8,ys=8,r=0,d=30}, {xs=-8,ys=-8,r=0,d=30}, {e=true} } }
F.sAffineAnims_GustToTarget = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=10,ys=0,r=0,d=24}, {e=true} } }
F.sAffineAnims_HitSplat = { [0] = { {xs=0,ys=0,r=0,d=8}, {e=true} }, [1] = { {xs=216,ys=216,r=0,d=0}, {xs=0,ys=0,r=0,d=8}, {e=true} }, [2] = { {xs=176,ys=176,r=0,d=0}, {xs=0,ys=0,r=0,d=8}, {e=true} }, [3] = { {xs=128,ys=128,r=0,d=0}, {xs=0,ys=0,r=0,d=8}, {e=true} } }
F.sAffineAnims_HydroCannonBeam = { [0] = { {xs=336,ys=336,r=0,d=0}, {e=true} } }
F.sAffineAnims_HydroCannonCharge = { [0] = { {xs=3,ys=3,r=10,d=50}, {xs=0,ys=0,r=0,d=10}, {xs=-20,ys=-20,r=-10,d=20}, {e=true} } }
F.sAffineAnims_IceBallChunk = { [0] = { {xs=224,ys=224,r=0,d=0}, {e=true} }, [1] = { {xs=280,ys=280,r=0,d=0}, {e=true} }, [2] = { {xs=336,ys=336,r=0,d=0}, {e=true} }, [3] = { {xs=384,ys=384,r=0,d=0}, {e=true} }, [4] = { {xs=448,ys=448,r=0,d=0}, {e=true} } }
F.sAffineAnims_IceBeamInnerCrystal = { [0] = { {xs=0,ys=0,r=10,d=1}, {jump=0} } }
F.sAffineAnims_IceCrystalHit = { [0] = { {xs=206,ys=206,r=0,d=0}, {xs=5,ys=5,r=0,d=10}, {xs=0,ys=0,r=0,d=6}, {e=true} } }
F.sAffineAnims_IceCrystalSpiralInwardLarge = { [0] = { {xs=0,ys=0,r=40,d=1}, {jump=0} } }
F.sAffineAnims_LargeFlame = { [0] = { {xs=50,ys=256,r=0,d=0}, {xs=32,ys=0,r=0,d=7}, {e=true} } }
F.sAffineAnims_LeechLifeNeedle = { [0] = { {xs=0,ys=0,r=-33,d=1}, {e=true} }, [1] = { {xs=0,ys=0,r=96,d=1}, {e=true} }, [2] = { {xs=0,ys=0,r=-96,d=1}, {e=true} } }
F.sAffineAnims_MegaPunchKick = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=-4,ys=-4,r=20,d=1}, {jump=1} } }
F.sAffineAnims_MegahornHorn = { [0] = { {xs=256,ys=256,r=30,d=0}, {e=true} }, [1] = { {xs=256,ys=256,r=-99,d=0}, {e=true} }, [2] = { {xs=256,ys=256,r=94,d=0}, {e=true} } }
F.sAffineAnims_PoisonProjectile = { [0] = { {xs=352,ys=352,r=0,d=0}, {xs=-10,ys=-10,r=0,d=10}, {xs=10,ys=10,r=0,d=10}, {jump=0} } }
F.sAffineAnims_PsychUpSpiral = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=-2,ys=-2,r=-10,d=120}, {e=true} } }
F.sAffineAnims_PsychoBoostOrb = { [0] = { {xs=32,ys=32,r=0,d=0}, {xs=16,ys=16,r=0,d=17}, {loop=0}, {xs=-8,ys=-8,r=0,d=10}, {xs=8,ys=8,r=0,d=10}, {loop=4}, {loop=0}, {xs=-16,ys=-16,r=0,d=5}, {xs=16,ys=16,r=0,d=5}, {loop=7}, {e=true} }, [1] = { {xs=-20,ys=24,r=0,d=15}, {e=true} } }
F.sAffineAnims_ShadowBall = { [0] = { {xs=0,ys=0,r=10,d=1}, {jump=0} } }
F.sAffineAnims_SludgeBombHit = { [0] = { {xs=236,ys=236,r=0,d=0}, {e=true} } }
F.sAffineAnims_SpiderWeb = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=6,ys=6,r=0,d=1}, {jump=1} } }
F.sAffineAnims_SpinningBone = { [0] = { {xs=0,ys=0,r=20,d=1}, {jump=0} } }
F.sAffineAnims_SpinningHandOrFoot = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=-8,ys=-8,r=20,d=1}, {jump=1} } }
F.sAffineAnims_SunlightRay = { [0] = { {xs=80,ys=80,r=0,d=0}, {xs=2,ys=2,r=10,d=1}, {jump=1} } }
F.sAffineAnims_SuperpowerOrb = { [0] = { {xs=32,ys=32,r=0,d=0}, {xs=4,ys=4,r=0,d=64}, {xs=-6,ys=-6,r=0,d=8}, {xs=6,ys=6,r=0,d=8}, {jump=2} } }
F.sAffineAnims_TailGlowOrb = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=8,ys=8,r=0,d=18}, {loop=0}, {xs=-5,ys=-5,r=0,d=8}, {xs=5,ys=5,r=0,d=8}, {loop=5}, {e=true} } }
F.sAffineAnims_TearDrop = { [0] = { {xs=192,ys=192,r=80,d=0}, {xs=0,ys=0,r=-2,d=8}, {e=true} }, [1] = { {xs=192,ys=192,r=-80,d=0}, {xs=0,ys=0,r=2,d=8}, {e=true} } }
F.sAffineAnims_ThunderboltOrb = { [0] = { {xs=232,ys=232,r=0,d=0}, {xs=-8,ys=-8,r=0,d=10}, {xs=8,ys=8,r=0,d=10}, {jump=1} } }
F.sAffineAnims_WaterBubbleProjectile = { [0] = { {xs=-5,ys=-5,r=0,d=10}, {xs=5,ys=5,r=0,d=10}, {jump=0} } }
F.sAffineAnims_WeatherBallIceDown = { [0] = { {xs=336,ys=336,r=0,d=0}, {e=true} } }
F.sAffineAnims_WeatherBallWaterDown = { [0] = { {xs=336,ys=336,r=0,d=0}, {xs=0,ys=0,r=0,d=15}, {e=true} } }
F.sAffineAnims_Whirlpool = { [0] = { {xs=192,ys=192,r=0,d=0}, {xs=2,ys=-3,r=0,d=5}, {xs=-2,ys=3,r=0,d=5}, {jump=1} } }
F.sAngerMarkAffineAnimTable = { [0] = { {xs=11,ys=11,r=0,d=8}, {xs=-11,ys=-11,r=0,d=8}, {e=true} } }
F.sAromatherapyBigFlowerAffineAnimTable = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=0,ys=0,r=4,d=1}, {jump=1} } }
F.sBulletSeedAffineAnimTable = { [0] = { {xs=0,ys=0,r=20,d=1}, {jump=0} } }
F.sConversionAffineAnimTable = { [0] = { {xs=512,ys=512,r=0,d=0}, {e=true} } }
F.sFallingBagAffineAnimTable = { [0] = { {xs=0,ys=0,r=-4,d=10}, {xs=0,ys=0,r=4,d=20}, {xs=0,ys=0,r=-4,d=10}, {e=true} }, [1] = { {xs=0,ys=0,r=-1,d=2}, {xs=0,ys=0,r=1,d=4}, {xs=0,ys=0,r=-1,d=4}, {xs=0,ys=0,r=1,d=4}, {xs=0,ys=0,r=-1,d=4}, {xs=0,ys=0,r=1,d=2}, {e=true} } }
F.sFallingCoinAffineAnimTable = { [0] = { {xs=0,ys=0,r=10,d=1}, {jump=0} } }
F.sFangAffineAnimTable = { [0] = { {xs=512,ys=512,r=0,d=0}, {xs=-32,ys=-32,r=0,d=8}, {e=true} } }
F.sGuardRingAffineAnimTable = { [0] = { {xs=256,ys=256,r=0,d=0}, {e=true} }, [1] = { {xs=512,ys=256,r=0,d=0}, {e=true} } }
F.sHiddenPowerOrbAffineAnimTable = { [0] = { {xs=128,ys=128,r=0,d=0}, {xs=8,ys=8,r=0,d=1}, {jump=1} } }
F.sHyperVoiceRingAffineAnimTable = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=11,ys=11,r=0,d=45}, {e=true} } }
F.sKnockOffStrikeAffineAnimTable = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=0,ys=0,r=-4,d=8}, {e=true} }, [1] = { {xs=-256,ys=256,r=0,d=0}, {xs=0,ys=0,r=4,d=8}, {e=true} } }
F.sLetterZAffineAnimTable = { [0] = { {xs=-7,ys=-7,r=-3,d=16}, {xs=7,ys=7,r=3,d=16}, {jump=0} } }
F.sMeanLookEyeAffineAnimTable = { [0] = { {xs=384,ys=384,r=0,d=0}, {xs=-32,ys=24,r=0,d=5}, {xs=24,ys=-32,r=0,d=5}, {jump=1} }, [1] = { {xs=48,ys=48,r=0,d=0}, {xs=32,ys=32,r=0,d=6}, {e=true} } }
F.sMetronomeFingerAffineAnimTable = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=30,ys=30,r=0,d=8}, {e=true} }, [1] = { {xs=0,ys=0,r=4,d=11}, {xs=0,ys=0,r=-4,d=11}, {loop=2}, {xs=-30,ys=-30,r=0,d=8}, {e=true} } }
F.sMilkBottleAffineAnimTable = { [0] = { {xs=256,ys=256,r=0,d=0}, {e=true} }, [1] = { {xs=0,ys=0,r=2,d=12}, {xs=0,ys=0,r=0,d=6}, {xs=0,ys=0,r=-2,d=24}, {xs=0,ys=0,r=0,d=6}, {xs=0,ys=0,r=2,d=12}, {jump=0} } }
F.sMimicOrbAffineAnimTable = { [0] = { {xs=0,ys=0,r=0,d=0}, {xs=48,ys=48,r=0,d=14}, {e=true} }, [1] = { {xs=-16,ys=-16,r=0,d=1}, {jump=0} } }
F.sMusicNotesAffineAnimTable = { [0] = { {xs=12,ys=12,r=0,d=16}, {xs=-12,ys=-12,r=0,d=16}, {jump=0} } }
F.sPerishSongMusicNoteAffineAnimTable = { [0] = { {xs=0,ys=0,r=0,d=5}, {e=true} }, [1] = { {xs=0,ys=0,r=-8,d=16}, {e=true} }, [2] = { {xs=0,ys=0,r=8,d=16}, {e=true} } }
F.sPowerAbsorptionOrbAffineAnimTable = { [0] = { {xs=-5,ys=-5,r=0,d=1}, {jump=0} } }
F.sRazorWindTornadoAffineAnimTable = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=4,ys=0,r=0,d=40}, {e=true} } }
F.sRecycleSpriteAffineAnimTable = { [0] = { {xs=0,ys=0,r=-4,d=64}, {jump=0} } }
F.sSilverWindBigSparkAffineAnimTable = { [0] = { {xs=256,ys=256,r=0,d=0}, {xs=0,ys=0,r=-10,d=1}, {jump=1} } }
F.sSilverWindMediumSparkAffineAnimTable = { [0] = { {xs=192,ys=192,r=0,d=0}, {xs=0,ys=0,r=-12,d=1}, {jump=1} } }
F.sSilverWindSmallSparkAffineAnimTable = { [0] = { {xs=143,ys=143,r=0,d=0}, {xs=0,ys=0,r=-15,d=1}, {jump=1} } }
F.sSleepLetterZAffineAnimTable = { [0] = { {xs=20,ys=20,r=-30,d=0}, {xs=8,ys=8,r=1,d=24}, {e=true} }, [1] = { {xs=20,ys=20,r=30,d=0}, {xs=8,ys=8,r=-1,d=24}, {e=true} } }
F.sSlowFlyinsMusicNotesAffineAnimTable = { [0] = { {xs=160,ys=160,r=0,d=0}, {xs=4,ys=4,r=0,d=1}, {jump=1} } }
F.sSmokeBallEscapeCloudAffineAnimTable = { [0] = { {xs=128,ys=128,r=0,d=0}, {xs=-4,ys=-6,r=0,d=16}, {xs=4,ys=6,r=0,d=16}, {jump=0} }, [1] = { {xs=192,ys=192,r=0,d=0}, {xs=4,ys=6,r=0,d=16}, {xs=-4,ys=-6,r=0,d=16}, {jump=0} }, [2] = { {xs=256,ys=256,r=0,d=0}, {xs=4,ys=6,r=0,d=16}, {xs=-4,ys=-6,r=0,d=16}, {jump=0} }, [3] = { {xs=256,ys=256,r=0,d=0}, {xs=8,ys=10,r=0,d=30}, {xs=-8,ys=-10,r=0,d=16}, {jump=0} } }
F.sSoftBoiledEggAffineAnimTable = { [0] = { {xs=0,ys=0,r=-8,d=2}, {xs=0,ys=0,r=8,d=4}, {xs=0,ys=0,r=-8,d=2}, {jump=0} }, [1] = { {xs=256,ys=256,r=0,d=0}, {e=true} }, [2] = { {xs=-8,ys=4,r=0,d=8}, {loop=0}, {xs=16,ys=-8,r=0,d=8}, {xs=-16,ys=8,r=0,d=8}, {loop=1}, {xs=256,ys=256,r=0,d=0}, {xs=0,ys=0,r=0,d=15}, {e=true} } }
F.sSpitUpOrbAffineAnimTable = { [0] = { {xs=128,ys=128,r=0,d=0}, {xs=8,ys=8,r=0,d=1}, {jump=1} } }
F.sSpotlightAffineAnimTable = { [0] = { {xs=0,ys=384,r=0,d=0}, {xs=16,ys=0,r=0,d=20}, {e=true} }, [1] = { {xs=320,ys=384,r=0,d=0}, {xs=-16,ys=0,r=0,d=19}, {e=true} } }
F.sStockpileAbsorptionOrbAffineAnimTable = { [0] = { {xs=320,ys=320,r=0,d=0}, {xs=-14,ys=-14,r=0,d=1}, {jump=1} } }
F.sSwiftStarAffineAnimTable = { [0] = { {xs=0,ys=0,r=0,d=1}, {jump=0} } }
F.sSwordsDanceBladeAffineAnimTable = { [0] = { {xs=16,ys=256,r=0,d=0}, {xs=20,ys=0,r=0,d=12}, {xs=0,ys=0,r=0,d=32}, {e=true} } }
F.sThinRingExpandingAffineAnimTable = { [0] = { {xs=16,ys=16,r=0,d=0}, {xs=16,ys=16,r=0,d=30}, {e=true} }, [1] = { {xs=16,ys=16,r=0,d=0}, {xs=32,ys=32,r=0,d=15}, {e=true} } }
F.sThinRingShrinkingAffineAnimTable = { [0] = { {xs=512,ys=512,r=0,d=0}, {xs=-16,ys=-16,r=0,d=30}, {e=true} } }
F.sTriAttackTriangleAffineAnimTable = { [0] = { {xs=0,ys=0,r=5,d=40}, {xs=0,ys=0,r=10,d=10}, {xs=0,ys=0,r=15,d=10}, {xs=0,ys=0,r=20,d=40}, {jump=0} } }
F.sTrickBagAffineAnimTable = { [0] = { {xs=0,ys=0,r=0,d=3}, {e=true} }, [1] = { {xs=0,ys=-10,r=0,d=3}, {xs=0,ys=-6,r=0,d=3}, {xs=0,ys=-2,r=0,d=3}, {xs=0,ys=0,r=0,d=3}, {xs=0,ys=2,r=0,d=3}, {xs=0,ys=6,r=0,d=3}, {xs=0,ys=10,r=0,d=3}, {e=true} }, [2] = { {xs=0,ys=0,r=-4,d=10}, {xs=0,ys=0,r=4,d=20}, {xs=0,ys=0,r=-4,d=10}, {e=true} }, [3] = { {xs=0,ys=0,r=-1,d=2}, {xs=0,ys=0,r=1,d=4}, {xs=0,ys=0,r=-1,d=4}, {xs=0,ys=0,r=1,d=4}, {xs=0,ys=0,r=-1,d=4}, {xs=0,ys=0,r=1,d=2}, {e=true} } }
F.sWaterPulseRingAffineAnimTable = { [0] = { {xs=5,ys=5,r=0,d=10}, {xs=-10,ys=-10,r=0,d=10}, {xs=10,ys=10,r=0,d=10}, {xs=-10,ys=-10,r=0,d=10}, {xs=10,ys=10,r=0,d=10}, {xs=-10,ys=-10,r=0,d=10}, {xs=10,ys=10,r=0,d=10}, {e=true} } }
F.sYawnCloudAffineAnimTable = { [0] = { {xs=128,ys=128,r=0,d=0}, {xs=-8,ys=-8,r=0,d=8}, {xs=8,ys=8,r=0,d=8}, {jump=0} }, [1] = { {xs=192,ys=192,r=0,d=0}, {xs=8,ys=8,r=0,d=8}, {xs=-8,ys=-8,r=0,d=8}, {jump=0} }, [2] = { {xs=256,ys=256,r=0,d=0}, {xs=8,ys=8,r=0,d=8}, {xs=-8,ys=-8,r=0,d=8}, {jump=0} } }
T.gAbsorptionOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 16, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.sPowerAbsorptionOrbAnimTable, affine = F.sAbsorptionOrbAffineAnimTable, cb = "AnimAbsorptionOrb" }
T.gAcidPoisonBubbleSpriteTemplate = { tag = "POISON_BUBBLE", pal = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_PoisonProjectile, affine = F.sAffineAnims_PoisonProjectile, cb = "AnimAcidPoisonBubble" }
T.gAcidPoisonDropletSpriteTemplate = { tag = "POISON_BUBBLE", pal = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_AcidPoisonDroplet, affine = F.gAffineAnims_Droplet, cb = "AnimAcidPoisonDroplet" }
T.gAirCutterSliceSpriteTemplate = { tag = "CUT", pal = "CUT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.sCuttingSliceAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimAirCutterSlice" }
T.gAirWaveCrescentSpriteTemplate = { tag = "AIR_WAVE_2", pal = "AIR_WAVE_2", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAffineAnims_AirWaveCrescent, affine = F.gDummySpriteAffineAnimTable, cb = "AnimAirWaveCrescent" }
T.gAncientPowerRockSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_BasicRock, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRaiseSprite" }
T.gAngelSpriteTemplate = { tag = "ANGEL", pal = "ANGEL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAngelSpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimAngel" }
T.gAngerMarkSpriteTemplate = { tag = "ANGER", pal = "ANGER", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAngerMarkAffineAnimTable, cb = "AnimAngerMark" }
T.gArmThrustHandSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.gDummySpriteAffineAnimTable, cb = "AnimArmThrustHit" }
T.gAromatherapyBigFlowerSpriteTemplate = { tag = "FLOWER", pal = "FLOWER", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sPetalDanceBigFlowerAnimTable, affine = F.sAromatherapyBigFlowerAffineAnimTable, cb = "AnimFlyingParticle" }
T.gAromatherapySmallFlowerSpriteTemplate = { tag = "FLOWER", pal = "FLOWER", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sPetalDanceSmallFlowerAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFlyingParticle" }
T.gAssistPawprintSpriteTemplate = { tag = "PAW_PRINT", pal = "PAW_PRINT", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimAssistPawprint" }
T.gAuroraBeamRingSpriteTemplate = { tag = "RAINBOW_RINGS", pal = "RAINBOW_RINGS", w = 8, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_AuroraBeamRing, affine = F.sAffineAnims_AuroraBeamRing, cb = "AnimAuroraBeamRings" }
T.gBarrierWallSpriteTemplate = { tag = "GRAY_LIGHT_WALL", pal = "GRAY_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDefensiveWall" }
T.gBasicHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatBasic" }
T.gBatonPassPokeballSpriteTemplate = { tag = "POKEBALL", pal = "POKEBALL", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBatonPassPokeball" }
T.gBellSpriteTemplate = { tag = "BELL", pal = "BELL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sBellAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gBellyDrumHandSpriteTemplate = { tag = "PURPLE_HAND_OUTLINE", pal = "PURPLE_HAND_OUTLINE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBellyDrumHand" }
T.gBentSpoonSpriteTemplate = { tag = "BENT_SPOON", pal = "BENT_SPOON", w = 16, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_BentSpoon, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBentSpoon" }
T.gBlackBallSpriteTemplate = { tag = "BLACK_BALL", pal = "BLACK_BALL", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThrowProjectile" }
T.gBlackSmokeSpriteTemplate = { tag = "BLACK_SMOKE", pal = "BLACK_SMOKE", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBlackSmoke" }
T.gBlendThinRingExpandingSpriteTemplate = { tag = "THIN_RING", pal = "THIN_RING", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sThinRingExpandingAffineAnimTable, cb = "AnimBlendThinRing" }
T.gBlizzardIceCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_BlizzardIceCrystal, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMoveParticleBeyondTarget" }
T.gBlockXSpriteTemplate = { tag = "X_SIGN", pal = "X_SIGN", w = 64, h = 64, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBlockX" }
T.gBonemerangSpriteTemplate = { tag = "BONE", pal = "BONE", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_Bonemerang, cb = "AnimBonemerangProjectile" }
T.gBounceBallLandSpriteTemplate = { tag = "ROUND_SHADOW", pal = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_BounceBallLand, cb = "AnimBounceBallLand" }
T.gBounceBallShrinkSpriteTemplate = { tag = "ROUND_SHADOW", pal = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_BounceBallShrink, cb = "AnimBounceBallShrink" }
T.gBowMonSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBowMon" }
T.gBreathPuffSpriteTemplate = { tag = "BREATH", pal = "BREATH", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sBreathPuffAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBreathPuff" }
T.gBrickBreakWallShardSpriteTemplate = { tag = "TORN_METAL", pal = "TORN_METAL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBrickBreakWallShard" }
T.gBrickBreakWallSpriteTemplate = { tag = "BLUE_LIGHT_WALL", pal = "BLUE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBrickBreakWall" }
T.gBulletSeedSpriteTemplate = { tag = "SEED", pal = "SEED", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sBulletSeedAffineAnimTable, cb = "AnimBulletSeed" }
T.gBurnFlameSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBurnFlame" }
T.gClampJawSpriteTemplate = { tag = "CLAMP", pal = "CLAMP", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gAffineAnims_Bite, cb = "AnimBite" }
T.gClappingHand2SpriteTemplate = { tag = "TAG_HAND", pal = "TAG_HAND", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimClappingHand2" }
T.gClappingHandSpriteTemplate = { tag = "TAG_HAND", pal = "TAG_HAND", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimClappingHand" }
T.gClawSlashSpriteTemplate = { tag = "CLAW_SLASH", pal = "CLAW_SLASH", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_ClawSlash, affine = F.gDummySpriteAffineAnimTable, cb = "AnimClawSlash" }
T.gCoinThrowSpriteTemplate = { tag = "COIN", pal = "COIN", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sCoinAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimCoinThrow" }
T.gComplexPaletteBlendSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimComplexPaletteBlend" }
T.gConfuseRayBallBounceSpriteTemplate = { tag = "YELLOW_BALL", pal = "YELLOW_BALL", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_ConfuseRayBallBounce, cb = "AnimConfuseRayBallBounce" }
T.gConfuseRayBallSpiralSpriteTemplate = { tag = "YELLOW_BALL", pal = "YELLOW_BALL", w = 16, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimConfuseRayBallSpiral" }
T.gConfusionDuckSpriteTemplate = { tag = "DUCK", pal = "DUCK", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_ConfusionDuck, affine = F.gDummySpriteAffineAnimTable, cb = "AnimConfusionDuck" }
T.gConstrictBindingSpriteTemplate = { tag = "TENDRILS", pal = "TENDRILS", w = 64, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_ConstrictBinding, affine = F.sAffineAnims_ConstrictBinding, cb = "AnimConstrictBinding" }
T.gConversion2SpriteTemplate = { tag = "CONVERSION", pal = "CONVERSION", w = 8, h = 8, affineMode = 3, objBlend = true, priority = 2, anims = A.sConversion2AnimTable, affine = F.sConversionAffineAnimTable, cb = "AnimConversion2" }
T.gConversionSpriteTemplate = { tag = "CONVERSION", pal = "CONVERSION", w = 8, h = 8, affineMode = 3, objBlend = true, priority = 2, anims = A.sConversionAnimTable, affine = F.sConversionAffineAnimTable, cb = "AnimConversion" }
T.gCrossChopHandSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet__3, affine = F.gDummySpriteAffineAnimTable, cb = "AnimCrossChopHand" }
T.gCrossImpactSpriteTemplate = { tag = "CROSS_IMPACT", pal = "CROSS_IMPACT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimCrossImpact" }
T.gCurseGhostSpriteTemplate = { tag = "GHOSTLY_SPIRIT", pal = "GHOSTLY_SPIRIT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimGhostStatusSprite" }
T.gCurseNailSpriteTemplate = { tag = "NAIL", pal = "NAIL", w = 32, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimCurseNail" }
T.gCuttingSliceSpriteTemplate = { tag = "CUT", pal = "CUT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.sCuttingSliceAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimCuttingSlice" }
T.gDevilSpriteTemplate = { tag = "DEVIL", pal = "DEVIL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sDevilAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDevil" }
T.gDirtMoundSpriteTemplate = { tag = "DIRT_MOUND", pal = "DIRT_MOUND", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDigDirtMound" }
T.gDirtPlumeSpriteTemplate = { tag = "MUD_SAND", pal = "MUD_SAND", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDirtPlumeParticle" }
T.gDiveBallSpriteTemplate = { tag = "ROUND_SHADOW", pal = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_DiveBall, cb = "AnimDiveBall" }
T.gDiveWaterSplashSpriteTemplate = { tag = "SPLASH", pal = "SPLASH", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDiveWaterSplash" }
T.gDizzyPunchDuckSpriteTemplate = { tag = "DUCK", pal = "DUCK", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDizzyPunchDuck" }
T.gDragonBreathFireSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_DragonBreathFire, affine = F.sAffineAnims_DragonBreathFire, cb = "AnimDragonFireToTarget" }
T.gDragonDanceOrbSpriteTemplate = { tag = "HOLLOW_ORB", pal = "HOLLOW_ORB", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDragonDanceOrb" }
T.gDragonRageFirePlumeSpriteTemplate = { tag = "FIRE_PLUME", pal = "FIRE_PLUME", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_DragonRageFirePlume, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDragonRageFirePlume" }
T.gDragonRageFireSpitSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_DragonRageFire, affine = F.sAffineAnims_DragonRageFire, cb = "AnimDragonFireToTarget" }
T.gEclipsingOrbSpriteTemplate = { tag = "ECLIPSING_ORB", pal = "ECLIPSING_ORB", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sEclipsingOrbAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gEggThrowSpriteTemplate = { tag = "LARGE_FRESH_EGG", pal = "LARGE_FRESH_EGG", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThrowProjectile" }
T.gElectricitySpriteTemplate = { tag = "SPARK_2", pal = "SPARK_2", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimElectricity" }
T.gElectricPuffSpriteTemplate = { tag = "ELECTRICITY", pal = "ELECTRICITY", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_ElectricPuff, affine = F.gDummySpriteAffineAnimTable, cb = "AnimElectricPuff" }
T.gEllipticalGustSpriteTemplate = { tag = "GUST", pal = "GUST", w = 32, h = 64, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimEllipticalGust" }
T.gEmberFlareSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimEmberFlare" }
T.gEmberSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gEndureEnergySpriteTemplate = { tag = "FOCUS_ENERGY", pal = "FOCUS_ENERGY", w = 16, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sEndureEnergyAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimEndureEnergy" }
T.gEruptionFallingRockSpriteTemplate = { tag = "WARM_ROCK", pal = "WARM_ROCK", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimEruptionFallingRock" }
T.gExplosionSpriteTemplate = { tag = "EXPLOSION", pal = "EXPLOSION", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sExplosionAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gEyeSparkleSpriteTemplate = { tag = "EYE_SPARKLE", pal = "EYE_SPARKLE", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sEyeSparkleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimEyeSparkle" }
T.gFallingCoinSpriteTemplate = { tag = "COIN", pal = "COIN", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sCoinAnimTable, affine = F.sFallingCoinAffineAnimTable, cb = "AnimFallingCoin" }
T.gFallingFeatherSpriteTemplate = { tag = "WHITE_FEATHER", pal = "WHITE_FEATHER", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_FallingFeather, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFallingFeather" }
T.gFallingRockSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FlyingRock, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFallingRock" }
T.gFalseSwipePositionedSliceSpriteTemplate = { tag = "SLASH_2", pal = "SLASH_2", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSlashSliceAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFalseSwipePositionedSlice" }
T.gFalseSwipeSliceSpriteTemplate = { tag = "SLASH_2", pal = "SLASH_2", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSlashSliceAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFalseSwipeSlice" }
T.gFangSpriteTemplate = { tag = "FANG_ATTACK", pal = "FANG_ATTACK", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sFangAnimTable, affine = F.sFangAffineAnimTable, cb = "AnimFang" }
T.gFastFlyingMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", pal = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gMusicNotesAnimTable, affine = F.sMusicNotesAffineAnimTable, cb = "AnimFlyingMusicNotes" }
T.gFireBlastCrossSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FireBlastCross, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFireCross" }
T.gFireBlastRingSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFireRing" }
T.gFirePlumeSpriteTemplate = { tag = "FIRE_PLUME", pal = "FIRE_PLUME", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FirePlume, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFirePlume" }
T.gFireSpinSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimParticleInVortex" }
T.gFireSpiralInwardSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FireSpiralSpread, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFireSpiralInward" }
T.gFireSpiralOutwardSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFireSpiralOutward" }
T.gFireSpreadSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FireSpiralSpread, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFireSpread" }
T.gFistFootRandomPosSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFistOrFootRandomPos" }
T.gFistFootSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.gDummySpriteAffineAnimTable, cb = "AnimBasicFistOrFoot" }
T.gFlamethrowerFlameSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FlamethrowerFlame, affine = F.gDummySpriteAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gFlashingHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimFlashingHitSplat" }
T.gFlatterConfettiSpriteTemplate = { tag = "CONFETTI", pal = "CONFETTI", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFlatterConfetti" }
T.gFlatterSpotlightSpriteTemplate = { tag = "SPOTLIGHT", pal = "SPOTLIGHT", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSpotlightAffineAnimTable, cb = "AnimFlatterSpotlight" }
T.gFlyBallAttackSpriteTemplate = { tag = "ROUND_SHADOW", pal = "ROUND_SHADOW", w = 64, h = 64, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_FlyBallAttack, cb = "AnimFlyBallAttack" }
T.gFlyBallUpSpriteTemplate = { tag = "ROUND_SHADOW", pal = "ROUND_SHADOW", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_FlyBallUp, cb = "AnimFlyBallUp" }
T.gFlyingSandCrescentSpriteTemplate = { tag = "FLYING_DIRT", pal = "FLYING_DIRT", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFlyingSandCrescent" }
T.gFocusPunchFistSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.sAffineAnims_FocusPunchFist, cb = "AnimFocusPunchFist" }
T.gFollowMeFingerSpriteTemplate = { tag = "FINGER", pal = "FINGER", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sMetronomeFingerAffineAnimTable, cb = "AnimFollowMeFinger" }
T.gForesightMagnifyingGlassSpriteTemplate = { tag = "MAGNIFYING_GLASS", pal = "MAGNIFYING_GLASS", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimForesightMagnifyingGlass" }
T.gFrenzyPlantRootSpriteTemplate = { tag = "ROOTS", pal = "ROOTS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sIngrainRootAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFrenzyPlantRoot" }
T.gFurySwipesSpriteTemplate = { tag = "SWIPE", pal = "SWIPE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FurySwipes, affine = F.gDummySpriteAffineAnimTable, cb = "AnimFurySwipes" }
T.gGoldRingSpriteTemplate = { tag = "GOLD_RING", pal = "GOLD_RING", w = 16, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gGrantingStarsSpriteTemplate = { tag = "SPARKLE_2", pal = "SPARKLE_2", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sGrantingStarsAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimGrantingStars" }
T.gGreenStarSpriteTemplate = { tag = "GREEN_STAR", pal = "GREEN_STAR", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sGreenStarAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimGreenStar" }
T.gGrowingChargeOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_GrowingElectricOrb, cb = "AnimGrowingChargeOrb" }
T.gGrowingShockWaveOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_GrowingElectricOrb, cb = "AnimGrowingShockWaveOrb" }
T.gGuardRingSpriteTemplate = { tag = "GUARD_RING", pal = "GUARD_RING", w = 64, h = 32, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sGuardRingAffineAnimTable, cb = "AnimGuardRing" }
T.gGuillotineSpriteTemplate = { tag = "CUT", pal = "CUT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.sGuillotineAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimGuillotinePincer" }
T.gGustToTargetSpriteTemplate = { tag = "GUST", pal = "GUST", w = 32, h = 64, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_GustToTarget, cb = "AnimGustToTarget" }
T.gHandleInvertHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatHandleInvert" }
T.gHealBellMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES_2", pal = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimHealBellMusicNote" }
T.gHealingBlueStarSpriteTemplate = { tag = "BLUE_STAR", pal = "BLUE_STAR", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sHealingBlueStarAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gHelpingHandClapSpriteTemplate = { tag = "TAG_HAND", pal = "TAG_HAND", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimHelpingHandClap" }
T.gHiddenPowerOrbScatterSpriteTemplate = { tag = "RED_ORB", pal = "RED_ORB", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sHiddenPowerOrbAffineAnimTable, cb = "AnimOrbitScatter" }
T.gHiddenPowerOrbSpriteTemplate = { tag = "RED_ORB", pal = "RED_ORB", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sHiddenPowerOrbAffineAnimTable, cb = "AnimOrbitFast" }
T.gHorizontalLungeSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "DoHorizontalLunge" }
T.gHornHitSpriteTemplate = { tag = "HORN_HIT", pal = "HORN_HIT", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimHornHit" }
T.gHydroCannonBeamSpriteTemplate = { tag = "WATER_ORB", pal = "WATER_ORB", w = 16, h = 16, affineMode = 3, objBlend = true, priority = 2, anims = A.gAnims_WaterMudOrb, affine = F.sAffineAnims_HydroCannonBeam, cb = "AnimHydroCannonBeam" }
T.gHydroCannonChargeSpriteTemplate = { tag = "WATER_ORB", pal = "WATER_ORB", w = 16, h = 16, affineMode = 3, objBlend = true, priority = 2, anims = A.gAnims_WaterMudOrb, affine = F.sAffineAnims_HydroCannonCharge, cb = "AnimHydroCannonCharge" }
T.gHydroPumpOrbSpriteTemplate = { tag = "WATER_ORB", pal = "WATER_ORB", w = 16, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.gAnims_WaterMudOrb, affine = F.gDummySpriteAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gHyperBeamOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sSolarBeamBigOrbAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimHyperBeamOrb" }
T.gHyperVoiceRingSpriteTemplate = { tag = "THIN_RING", pal = "THIN_RING", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sHyperVoiceRingAffineAnimTable, cb = "AnimHyperVoiceRing" }
T.gIceBallChunkSpriteTemplate = { tag = "ICE_CHUNK", pal = "ICE_CHUNK", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_IceBallChunk, affine = F.sAffineAnims_IceBallChunk, cb = "InitIceBallAnim" }
T.gIceBallImpactShardSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_IceCrystalSmall, affine = F.gDummySpriteAffineAnimTable, cb = "InitIceBallParticle" }
T.gIceBeamInnerCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalLarge, affine = F.sAffineAnims_IceBeamInnerCrystal, cb = "AnimIceBeamParticle" }
T.gIceBeamOuterCrystalSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalSmall, affine = F.gDummySpriteAffineAnimTable, cb = "AnimIceBeamParticle" }
T.gIceCrystalHitLargeSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalLarge, affine = F.sAffineAnims_IceCrystalHit, cb = "AnimIceEffectParticle" }
T.gIceCrystalHitSmallSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 1, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalSmall, affine = F.sAffineAnims_IceCrystalHit, cb = "AnimIceEffectParticle" }
T.gIceCrystalSpiralInwardLarge = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 16, affineMode = 3, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalLarge, affine = F.sAffineAnims_IceCrystalSpiralInwardLarge, cb = "AnimIcePunchSwirlingParticle" }
T.gIceCrystalSpiralInwardSmall = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_IceCrystalSmall, affine = F.gDummySpriteAffineAnimTable, cb = "AnimIcePunchSwirlingParticle" }
T.gIceGroundSpikeSpriteTemplate = { tag = "ICE_SPIKES", pal = "ICE_SPIKES", w = 8, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_IceGroundSpike, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWaveFromCenterOfTarget" }
T.gIcicleSpearSpriteTemplate = { tag = "ICICLE_SPEAR", pal = "ICICLE_SPEAR", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMissileArc" }
T.gIngrainOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sIngrainOrbAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimIngrainOrb" }
T.gIngrainRootSpriteTemplate = { tag = "ROOTS", pal = "ROOTS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sIngrainRootAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimIngrainRoot" }
T.gItemStealSpriteTemplate = { tag = "ITEM_BAG", pal = "ITEM_BAG", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sFallingBagAnimTable, affine = F.sFallingBagAffineAnimTable, cb = "AnimItemSteal" }
T.gJaggedMusicNoteSpriteTemplate = { tag = "JAGGED_MUSIC_NOTE", pal = "JAGGED_MUSIC_NOTE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimJaggedMusicNote" }
T.gJumpKickSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.gDummySpriteAffineAnimTable, cb = "AnimJumpKick" }
T.gKarateChopSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSlideHandOrFootToTarget" }
T.gKinesisZapEnergySpriteTemplate = { tag = "ALERT", pal = "ALERT", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sKinesisZapEnergyAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimKinesisZapEnergy" }
T.gKnockOffItemSpriteTemplate = { tag = "ITEM_BAG", pal = "ITEM_BAG", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sFallingBagAnimTable, affine = F.sFallingBagAffineAnimTable, cb = "AnimKnockOffItem" }
T.gKnockOffStrikeSpriteTemplate = { tag = "SLAM_HIT_2", pal = "SLAM_HIT_2", w = 64, h = 64, affineMode = 1, objBlend = false, priority = 2, anims = A.sKnockOffStrikeAnimTable, affine = F.sKnockOffStrikeAffineAnimTable, cb = "AnimKnockOffStrike" }
T.gLargeFlameScatterSpriteTemplate = { tag = "FIRE", pal = "FIRE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_LargeFlame, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLargeFlame" }
T.gLargeFlameSpriteTemplate = { tag = "FIRE", pal = "FIRE", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_LargeFlame, affine = F.sAffineAnims_LargeFlame, cb = "AnimLargeFlame" }
T.gLeechLifeNeedleSpriteTemplate = { tag = "NEEDLE", pal = "NEEDLE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_LeechLifeNeedle, cb = "AnimLeechLifeNeedle" }
T.gLeechSeedSpriteTemplate = { tag = "SEED", pal = "SEED", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sLeechSeedAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLeechSeed" }
T.gLeerSpriteTemplate = { tag = "LEER", pal = "LEER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sLeerAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLeer" }
T.gLetterZSpriteTemplate = { tag = "LETTER_Z", pal = "LETTER_Z", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sLetterZAnimTable, affine = F.sLetterZAffineAnimTable, cb = "AnimLetterZ" }
T.gLickSpriteTemplate = { tag = "LICK", pal = "LICK", w = 16, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Lick, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLick" }
T.gLightningSpriteTemplate = { tag = "LIGHTNING", pal = "LIGHTNING", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Lightning, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLightning" }
T.gLightScreenWallSpriteTemplate = { tag = "GREEN_LIGHT_WALL", pal = "GREEN_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDefensiveWall" }
T.gLinearStingerSpriteTemplate = { tag = "NEEDLE", pal = "NEEDLE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTranslateStinger" }
T.gLockOnMoveTargetSpriteTemplate = { tag = "LOCK_ON", pal = "LOCK_ON", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLockOnMoveTarget" }
T.gLockOnTargetSpriteTemplate = { tag = "LOCK_ON", pal = "LOCK_ON", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimLockOnTarget" }
T.gLusterPurgeCircleSpriteTemplate = { tag = "WHITE_CIRCLE_OF_LIGHT", pal = "WHITE_CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gAffineAnims_LusterPurgeCircle, cb = "AnimSpriteOnMonPos" }
T.gMagentaHeartSpriteTemplate = { tag = "MAGENTA_HEART", pal = "MAGENTA_HEART", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMagentaHeart" }
T.gMagicCoatWallSpriteTemplate = { tag = "ORANGE_LIGHT_WALL", pal = "ORANGE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDefensiveWall" }
T.gMeanLookEyeSpriteTemplate = { tag = "EYE", pal = "EYE", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sMeanLookEyeAffineAnimTable, cb = "AnimMeanLookEye" }
T.gMegahornHornSpriteTemplate = { tag = "HORN_HIT_2", pal = "HORN_HIT_2", w = 32, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_MegahornHorn, cb = "AnimMegahornHorn" }
T.gMegaPunchKickSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.sAffineAnims_MegaPunchKick, cb = "AnimSpinningKickOrPunch" }
T.gMetalSoundSpriteTemplate = { tag = "METAL_SOUND_WAVES", pal = "METAL_SOUND_WAVES", w = 32, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gGrowingRingAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gMeteorMashStarSpriteTemplate = { tag = "GOLD_STARS", pal = "GOLD_STARS", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMeteorMashStar" }
T.gMetronomeFingerSpriteTemplate = { tag = "FINGER", pal = "FINGER", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sMetronomeFingerAffineAnimTable, cb = "AnimMetronomeFinger" }
T.gMilkBottleSpriteTemplate = { tag = "MILK_BOTTLE", pal = "MILK_BOTTLE", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sMilkBottleAffineAnimTable, cb = "AnimMilkBottle" }
T.gMimicOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.sPowerAbsorptionOrbAnimTable, affine = F.sMimicOrbAffineAnimTable, cb = "AnimMimicOrb" }
T.gMirrorCoatWallSpriteTemplate = { tag = "RED_LIGHT_WALL", pal = "RED_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDefensiveWall" }
T.gMistBallSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThrowMistBall" }
T.gMistCloudSpriteTemplate = { tag = "MIST_CLOUD", pal = "MIST_CLOUD", w = 32, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_Cloud, affine = F.gDummySpriteAffineAnimTable, cb = "InitSwirlingFogAnim" }
T.gMonEdgeHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatOnMonEdge" }
T.gMoonlightSparkleSpriteTemplate = { tag = "GREEN_SPARKLE", pal = "GREEN_SPARKLE", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sMoonlightSparkleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMoonlightSparkle" }
T.gMoonSpriteTemplate = { tag = "MOON", pal = "MOON", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMoon" }
T.gMovementWavesSpriteTemplate = { tag = "MOVEMENT_WAVES", pal = "MOVEMENT_WAVES", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sMovementWavesAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMovementWaves" }
T.gMudShotOrbSpriteTemplate = { tag = "BROWN_ORB", pal = "BROWN_ORB", w = 16, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.gAnims_WaterMudOrb, affine = F.gDummySpriteAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gMudSlapMudSpriteTemplate = { tag = "MUD_SAND", pal = "MUD_SAND", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_MudSlapMud, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDirtScatter" }
T.gMudsportMudSpriteTemplate = { tag = "MUD_SAND", pal = "MUD_SAND", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMudSportDirt" }
T.gNeedleArmSpikeSpriteTemplate = { tag = "GREEN_SPIKE", pal = "GREEN_SPIKE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimNeedleArmSpike" }
T.gNightmareDevilSpriteTemplate = { tag = "DEVIL", pal = "DEVIL", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimGhostStatusSprite" }
T.gOctazookaBallSpriteTemplate = { tag = "BLACK_BALL", pal = "BLACK_BALL", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gOctazookaSmokeSpriteTemplate = { tag = "GRAY_SMOKE", pal = "GRAY_SMOKE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sOctazookaAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gOpeningEyeSpriteTemplate = { tag = "OPENING_EYE", pal = "OPENING_EYE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sOpeningEyeAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gOutrageFlameSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_OutrageOverheatFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimOutrageFlame" }
T.gOverheatFlameSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_OutrageOverheatFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimOverheatFlame" }
T.gPainSplitProjectileSpriteTemplate = { tag = "PAIN_SPLIT", pal = "PAIN_SPLIT", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPainSplitAnimCmdTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPainSplitProjectile" }
T.gPencilSpriteTemplate = { tag = "PENCIL", pal = "PENCIL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPencil" }
T.gPerishSongMusicNote2SpriteTemplate = { tag = "MUSIC_NOTES_2", pal = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gMusicNotesAnimTable, affine = F.sPerishSongMusicNoteAffineAnimTable, cb = "AnimPerishSongMusicNote2" }
T.gPerishSongMusicNoteSpriteTemplate = { tag = "MUSIC_NOTES_2", pal = "MUSIC_NOTES_2", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gMusicNotesAnimTable, affine = F.sPerishSongMusicNoteAffineAnimTable, cb = "AnimPerishSongMusicNote" }
T.gPersistHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatPersistent" }
T.gPetalDanceBigFlowerSpriteTemplate = { tag = "FLOWER", pal = "FLOWER", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPetalDanceBigFlowerAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPetalDanceBigFlower" }
T.gPetalDanceSmallFlowerSpriteTemplate = { tag = "FLOWER", pal = "FLOWER", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sPetalDanceSmallFlowerAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPetalDanceSmallFlower" }
T.gPinkHeartSpriteTemplate = { tag = "PINK_HEART", pal = "PINK_HEART", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPinkHeart" }
T.gPinMissileSpriteTemplate = { tag = "NEEDLE", pal = "NEEDLE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMissileArc" }
T.gPoisonBubbleSpriteTemplate = { tag = "POISON_BUBBLE", pal = "POISON_BUBBLE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_PoisonProjectile, affine = F.sAffineAnims_Bubble, cb = "AnimBubbleEffect" }
T.gPoisonGasCloudSpriteTemplate = { tag = "PURPLE_GAS_CLOUD", pal = "PURPLE_GAS_CLOUD", w = 32, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_Cloud, affine = F.gDummySpriteAffineAnimTable, cb = "InitPoisonGasCloudAnim" }
T.gPoisonPowderParticleSpriteTemplate = { tag = "POISON_POWDER", pal = "POISON_POWDER", w = 8, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPowderParticlesAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMovePowderParticle" }
T.gPowderSnowSnowballSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Snowball, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMoveParticleBeyondTarget" }
T.gPowerAbsorptionOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 16, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.sPowerAbsorptionOrbAnimTable, affine = F.sPowerAbsorptionOrbAffineAnimTable, cb = "AnimPowerAbsorptionOrb" }
T.gPresentHealParticleSpriteTemplate = { tag = "GREEN_SPARKLE", pal = "GREEN_SPARKLE", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPresentHealParticleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimPresentHealParticle" }
T.gPresentSpriteTemplate = { tag = "ITEM_BAG", pal = "ITEM_BAG", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sFallingBagAnimTable, affine = F.sFallingBagAffineAnimTable, cb = "AnimPresent" }
T.gProtectSpriteTemplate = { tag = "PROTECT", pal = "PROTECT", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimProtect" }
T.gPsychoBoostOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_PsychoBoostOrb, cb = "AnimPsychoBoost" }
T.gPsychUpSpiralSpriteTemplate = { tag = "SPIRAL", pal = "SPIRAL", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_PsychUpSpiral, cb = "AnimSpriteOnMonPos" }
T.gPsywaveRingSpriteTemplate = { tag = "BLUE_RING", pal = "BLUE_RING", w = 16, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gGrowingRingAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gQuestionMarkSpriteTemplate = { tag = "AMNESIA", pal = "AMNESIA", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_QuestionMark, affine = F.gDummySpriteAffineAnimTable, cb = "AnimQuestionMark" }
T.gRandomPosHitSplatSpriteTemplate = { tag = "IMPACT", pal = "IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatRandom" }
T.gRapidSpinSpriteTemplate = { tag = "RAPID_SPIN", pal = "RAPID_SPIN", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sRapidSpinAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRapidSpin" }
T.gRazorLeafCutterSpriteTemplate = { tag = "RAZOR_LEAF", pal = "RAZOR_LEAF", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sRazorLeafCutterAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTranslateLinearSingleSineWave" }
T.gRazorLeafParticleSpriteTemplate = { tag = "LEAF", pal = "LEAF", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sRazorLeafParticleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRazorLeafParticle" }
T.gRazorWindTornadoSpriteTemplate = { tag = "GUST", pal = "GUST", w = 32, h = 64, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sRazorWindTornadoAffineAnimTable, cb = "AnimRazorWindTornado" }
T.gRecycleSpriteTemplate = { tag = "RECYCLE", pal = "RECYCLE", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sRecycleSpriteAffineAnimTable, cb = "AnimRecycle" }
T.gRedHeartBurstSpriteTemplate = { tag = "RED_HEART", pal = "RED_HEART", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimParticleBurst" }
T.gRedHeartProjectileSpriteTemplate = { tag = "RED_HEART", pal = "RED_HEART", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRedHeartProjectile" }
T.gRedHeartRisingSpriteTemplate = { tag = "RED_HEART", pal = "RED_HEART", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRedHeartRising" }
T.gRedXSpriteTemplate = { tag = "X_SIGN", pal = "X_SIGN", w = 64, h = 64, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRedX" }
T.gReflectSparkleSpriteTemplate = { tag = "SPARKLE_4", pal = "SPARKLE_4", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_ReflectSparkle, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWallSparkle" }
T.gReflectWallSpriteTemplate = { tag = "BLUE_LIGHT_WALL", pal = "BLUE_LIGHT_WALL", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDefensiveWall" }
T.gRevengeBigScratchSpriteTemplate = { tag = "PURPLE_SWIPE", pal = "PURPLE_SWIPE", w = 64, h = 64, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_RevengeBigScratch, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRevengeScratch" }
T.gRevengeSmallScratchSpriteTemplate = { tag = "PURPLE_SCRATCH", pal = "PURPLE_SCRATCH", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_RevengeSmallScratch, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRevengeScratch" }
T.gReversalOrbSpriteTemplate = { tag = "BLUE_ORB", pal = "BLUE_ORB", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimReversalOrb" }
T.gRoarNoiseLineSpriteTemplate = { tag = "NOISE_LINE", pal = "NOISE_LINE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sRoarNoiseLineAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRoarNoiseLine" }
T.gRockBlastRockSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_BasicRock, affine = F.sAffineAnims_BasicRock, cb = "AnimRockBlastRock" }
T.gRockFragmentSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_FlyingRock, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRockFragment" }
T.gRockScatterSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_BasicRock, affine = F.sAffineAnims_BasicRock, cb = "AnimRockScatter" }
T.gRockTombRockSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_BasicRock, affine = F.gDummySpriteAffineAnimTable, cb = "AnimRockTomb" }
T.gSafariBaitSpriteTemplate = { tag = "SAFARI_BAIT", pal = "SAFARI_BAIT", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "SpriteCB_SafariBaitOrRock_Init" }
T.gSafariRockTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSpriteAnimTable_SafariRock, affine = F.gDummySpriteAffineAnimTable, cb = "SpriteCB_SafariBaitOrRock_Init" }
T.gSandAttackDirtSpriteTemplate = { tag = "MUD_SAND", pal = "MUD_SAND", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimDirtScatter" }
T.gScratchSpriteTemplate = { tag = "SCRATCH", pal = "SCRATCH", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.sScratchAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gScreechRingSpriteTemplate = { tag = "PURPLE_RING", pal = "PURPLE_RING", w = 16, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gGrowingRingAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gShadowBallSpriteTemplate = { tag = "SHADOW_BALL", pal = "SHADOW_BALL", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_ShadowBall, cb = "AnimShadowBall" }
T.gShakeMonOrTerrainSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimShakeMonOrBattleTerrain" }
T.gSharpenSphereSpriteTemplate = { tag = "SPHERE_TO_CUBE", pal = "SPHERE_TO_CUBE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSharpenSphereAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSharpenSphere" }
T.gSharpTeethSpriteTemplate = { tag = "SHARP_TEETH", pal = "SHARP_TEETH", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gAffineAnims_Bite, cb = "AnimBite" }
T.gSignalBeamGreenOrbSpriteTemplate = { tag = "GLOWY_GREEN_ORB", pal = "GLOWY_GREEN_ORB", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gSignalBeamRedOrbSpriteTemplate = { tag = "GLOWY_RED_ORB", pal = "GLOWY_RED_ORB", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimToTargetInSinWave" }
T.gSilverWindBigSparkSpriteTemplate = { tag = "SPARKLE_6", pal = "SPARKLE_6", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSilverWindBigSparkAffineAnimTable, cb = "AnimFlyingParticle" }
T.gSilverWindMediumSparkSpriteTemplate = { tag = "SPARKLE_6", pal = "SPARKLE_6", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSilverWindMediumSparkAffineAnimTable, cb = "AnimFlyingParticle" }
T.gSilverWindSmallSparkSpriteTemplate = { tag = "SPARKLE_6", pal = "SPARKLE_6", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSilverWindSmallSparkAffineAnimTable, cb = "AnimFlyingParticle" }
T.gSimplePaletteBlendSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSimplePaletteBlend" }
T.gSkyAttackBirdSpriteTemplate = { tag = "BIRD", pal = "BIRD", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSkyAttackBird" }
T.gSlamHitSpriteTemplate = { tag = "SLAM_HIT", pal = "SLAM_HIT", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Whip, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWhipHit" }
T.gSlashSliceSpriteTemplate = { tag = "SLASH", pal = "SLASH", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSlashSliceAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSlashSlice" }
T.gSleepLetterZSpriteTemplate = { tag = "LETTER_Z", pal = "LETTER_Z", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sSleepLetterZAnimTable, affine = F.sSleepLetterZAffineAnimTable, cb = "AnimSleepLetterZ" }
T.gSleepPowderParticleSpriteTemplate = { tag = "SLEEP_POWDER", pal = "SLEEP_POWDER", w = 8, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPowderParticlesAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMovePowderParticle" }
T.gSlideMonToOffsetAndBackSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "SlideMonToOffsetAndBack" }
T.gSlideMonToOffsetSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "SlideMonToOffset" }
T.gSlideMonToOriginalPosSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "SlideMonToOriginalPos" }
T.gSlidingKickSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet__1, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSlidingKick" }
T.gSlowFlyingMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", pal = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gMusicNotesAnimTable, affine = F.sSlowFlyinsMusicNotesAffineAnimTable, cb = "AnimSlowFlyingMusicNotes" }
T.gSludgeBombHitParticleSpriteTemplate = { tag = "POISON_BUBBLE", pal = "POISON_BUBBLE", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_SludgeBombHit, affine = F.sAffineAnims_SludgeBombHit, cb = "AnimSludgeBombHitParticle" }
T.gSludgeProjectileSpriteTemplate = { tag = "POISON_BUBBLE", pal = "POISON_BUBBLE", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_PoisonProjectile, affine = F.sAffineAnims_PoisonProjectile, cb = "AnimSludgeProjectile" }
T.gSmallBubblePairSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_SmallBubblePair, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSmallBubblePair" }
T.gSmallDriftingBubblesSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSmallDriftingBubbles" }
T.gSmellingSaltExclamationSpriteTemplate = { tag = "SMELLINGSALT_EFFECT", pal = "SMELLINGSALT_EFFECT", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSmellingSaltExclamation" }
T.gSmellingSaltsHandSpriteTemplate = { tag = "TAG_HAND", pal = "TAG_HAND", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSmellingSaltsHand" }
T.gSmogCloudSpriteTemplate = { tag = "PURPLE_GAS_CLOUD", pal = "PURPLE_GAS_CLOUD", w = 32, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.sAnims_Cloud, affine = F.gDummySpriteAffineAnimTable, cb = "InitSwirlingFogAnim" }
T.gSmokeBallEscapeCloudSpriteTemplate = { tag = "PINK_CLOUD", pal = "PINK_CLOUD", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSmokeBallEscapeCloudAffineAnimTable, cb = "AnimSmokeBallEscapeCloud" }
T.gSnoreZSpriteTemplate = { tag = "SNORE_Z", pal = "SNORE_Z", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTravelDiagonally" }
T.gSoftBoiledEggSpriteTemplate = { tag = "BREAKING_EGG", pal = "BREAKING_EGG", w = 32, h = 32, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSoftBoiledEggAffineAnimTable, cb = "AnimSoftBoiledEgg" }
T.gSolarBeamBigOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sSolarBeamBigOrbAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSolarBeamBigOrb" }
T.gSonicBoomSpriteTemplate = { tag = "AIR_WAVE", pal = "AIR_WAVE", w = 32, h = 16, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSonicBoomProjectile" }
T.gSparkElectricityFlashingSpriteTemplate = { tag = "SPARK_2", pal = "SPARK_2", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_FlashingSpark, cb = "AnimSparkElectricityFlashing" }
T.gSparkElectricitySpriteTemplate = { tag = "SPARK_2", pal = "SPARK_2", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSparkElectricity" }
T.gSparklingStarsSpriteTemplate = { tag = "SPARKLE_2", pal = "SPARKLE_2", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sGrantingStarsAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSparklingStars" }
T.gSpecialScreenSparkleSpriteTemplate = { tag = "SPARKLE_3", pal = "SPARKLE_3", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_SpecialScreenSparkle, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWallSparkle" }
T.gSpiderWebSpriteTemplate = { tag = "SPIDER_WEB", pal = "SPIDER_WEB", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_SpiderWeb, cb = "AnimSpiderWeb" }
T.gSpikesSpriteTemplate = { tag = "SPIKES", pal = "SPIKES", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpikes" }
T.gSpinningBoneSpriteTemplate = { tag = "BONE", pal = "BONE", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_SpinningBone, cb = "AnimBoneHitProjectile" }
T.gSpinningHandOrFootSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet, affine = F.sAffineAnims_SpinningHandOrFoot, cb = "AnimSpinningKickOrPunch" }
T.gSpinningSparkleSpriteTemplate = { tag = "SPARKLE_4", pal = "SPARKLE_4", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_SpinningSparkle, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpinningSparkle" }
T.gSpitUpOrbSpriteTemplate = { tag = "RED_ORB_2", pal = "RED_ORB_2", w = 8, h = 8, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSpitUpOrbAffineAnimTable, cb = "AnimSpitUpOrb" }
T.gSporeParticleSpriteTemplate = { tag = "SPORE", pal = "SPORE", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sSporeParticleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSporeParticle" }
T.gSpotlightSpriteTemplate = { tag = "SPOTLIGHT", pal = "SPOTLIGHT", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSpotlightAffineAnimTable, cb = "AnimSpotlight" }
T.gSprayWaterDropletSpriteTemplate = { tag = "SWEAT_BEAD", pal = "SWEAT_BEAD", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSprayWaterDroplet" }
T.gStockpileAbsorptionOrbSpriteTemplate = { tag = "GRAY_ORB", pal = "GRAY_ORB", w = 8, h = 8, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sStockpileAbsorptionOrbAffineAnimTable, cb = "AnimPowerAbsorptionOrb" }
T.gStompFootSpriteTemplate = { tag = "HANDS_AND_FEET", pal = "HANDS_AND_FEET", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_HandsAndFeet__1, affine = F.gDummySpriteAffineAnimTable, cb = "AnimStompFoot" }
T.gStringWrapSpriteTemplate = { tag = "STRING", pal = "STRING", w = 64, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimStringWrap" }
T.gStunSporeParticleSpriteTemplate = { tag = "STUN_SPORE", pal = "STUN_SPORE", w = 8, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sPowderParticlesAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMovePowderParticle" }
T.gSunlightRaySpriteTemplate = { tag = "SUNLIGHT", pal = "SUNLIGHT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_SunlightRay, cb = "AnimSunlight" }
T.gSuperFangSpriteTemplate = { tag = "FANG_ATTACK", pal = "FANG_ATTACK", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sSuperFangAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSuperFang" }
T.gSuperpowerFireballSpriteTemplate = { tag = "METEOR", pal = "METEOR", w = 64, h = 64, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSuperpowerFireball" }
T.gSuperpowerOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_SuperpowerOrb, cb = "AnimSuperpowerOrb" }
T.gSuperpowerRockSpriteTemplate = { tag = "FLAT_ROCK", pal = "FLAT_ROCK", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSuperpowerRock" }
T.gSupersonicRingSpriteTemplate = { tag = "GOLD_RING", pal = "GOLD_RING", w = 16, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gGrowingRingAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gSwallowBlueOrbSpriteTemplate = { tag = "BLUE_ORB", pal = "BLUE_ORB", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSwallowBlueOrb" }
T.gSweetScentPetalSpriteTemplate = { tag = "PINK_PETAL", pal = "PINK_PETAL", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sSweetScentPetalAnimCmdTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSweetScentPetal" }
T.gSwiftStarSpriteTemplate = { tag = "YELLOW_STAR", pal = "YELLOW_STAR", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSwiftStarAffineAnimTable, cb = "AnimTranslateLinearSingleSineWave" }
T.gSwirlingDirtSpriteTemplate = { tag = "MUD_SAND", pal = "MUD_SAND", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimParticleInVortex" }
T.gSwirlingSnowballSpriteTemplate = { tag = "ICE_CRYSTALS", pal = "ICE_CRYSTALS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Snowball, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSwirlingSnowball" }
T.gSwordsDanceBladeSpriteTemplate = { tag = "SWORD", pal = "SWORD", w = 32, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sSwordsDanceBladeAffineAnimTable, cb = "AnimSwordsDanceBlade" }
T.gTailGlowOrbSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_TailGlowOrb, cb = "AnimTailGlowOrb" }
T.gTauntFingerSpriteTemplate = { tag = "FINGER_2", pal = "FINGER_2", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sTauntFingerAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTauntFinger" }
T.gTealAlertSpriteTemplate = { tag = "TEAL_ALERT", pal = "TEAL_ALERT", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTealAlert" }
T.gTearDropSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_TearDrop, cb = "AnimTearDrop" }
T.gThinRingExpandingSpriteTemplate = { tag = "THIN_RING", pal = "THIN_RING", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sThinRingExpandingAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gThinRingShrinkingSpriteTemplate = { tag = "THIN_RING", pal = "THIN_RING", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sThinRingShrinkingAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gThoughtBubbleSpriteTemplate = { tag = "THOUGHT_BUBBLE", pal = "THOUGHT_BUBBLE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sMetronomeThroughtBubbleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThoughtBubble" }
T.gThunderboltOrbSpriteTemplate = { tag = "SHOCK_3", pal = "SHOCK_3", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_ThunderboltOrb, affine = F.sAffineAnims_ThunderboltOrb, cb = "AnimThunderboltOrb" }
T.gThunderWaveSpriteTemplate = { tag = "SPARK_H", pal = "SPARK_H", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThunderWave" }
T.gToxicBubbleSpriteTemplate = { tag = "TOXIC_BUBBLE", pal = "TOXIC_BUBBLE", w = 16, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_ToxicBubble, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSpriteOnMonPos" }
T.gTriAttackTriangleSpriteTemplate = { tag = "TRI_ATTACK_TRIANGLE", pal = "TRI_ATTACK_TRIANGLE", w = 64, h = 64, affineMode = 3, objBlend = false, priority = 2, anims = A.sTriAttackTriangleAnimTable, affine = F.sTriAttackTriangleAffineAnimTable, cb = "AnimTriAttackTriangle" }
T.gTrickBagSpriteTemplate = { tag = "ITEM_BAG", pal = "ITEM_BAG", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sFallingBagAnimTable, affine = F.sTrickBagAffineAnimTable, cb = "AnimTrickBag" }
T.gTwisterLeafSpriteTemplate = { tag = "LEAF", pal = "LEAF", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sRazorLeafParticleAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimMoveTwisterParticle" }
T.gTwisterRockSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_BasicRock__4, affine = F.sAffineAnims_BasicRock, cb = "AnimMoveTwisterParticle" }
T.gUproarRingSpriteTemplate = { tag = "THIN_RING", pal = "THIN_RING", w = 64, h = 64, affineMode = 3, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sThinRingExpandingAffineAnimTable, cb = "AnimUproarRing" }
T.gVerticalDipSpriteTemplate = { tag = nil, pal = nil, w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "DoVerticalDip" }
T.gViceGripSpriteTemplate = { tag = "CUT", pal = "CUT", w = 32, h = 32, affineMode = 0, objBlend = true, priority = 2, anims = A.sViceGripAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimViceGripPincer" }
T.gVineWhipSpriteTemplate = { tag = "WHIP_HIT", pal = "WHIP_HIT", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_Whip, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWhipHit" }
T.gVoltTackleOrbSlideSpriteTemplate = { tag = "CIRCLE_OF_LIGHT", pal = "CIRCLE_OF_LIGHT", w = 64, h = 64, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_GrowingElectricOrb, cb = "AnimVoltTackleOrbSlide" }
T.gWaterBubbleProjectileSpriteTemplate = { tag = "BUBBLE", pal = "BUBBLE", w = 16, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.sAnims_WaterBubbleProjectile, affine = F.sAffineAnims_WaterBubbleProjectile, cb = "AnimWaterBubbleProjectile" }
T.gWaterBubbleSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.gAnims_WaterBubble, affine = F.sAffineAnims_Bubble, cb = "AnimBubbleEffect" }
T.gWaterGunDropletSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 3, objBlend = true, priority = 2, anims = A.sAnims_WaterGunDroplet, affine = F.gAffineAnims_Droplet, cb = "AnimWaterGunDroplet" }
T.gWaterGunProjectileSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 0, objBlend = true, priority = 2, anims = A.gAnims_WaterBubble, affine = F.gDummySpriteAffineAnimTable, cb = "AnimThrowProjectile" }
T.gWaterHitSplatSpriteTemplate = { tag = "WATER_IMPACT", pal = "WATER_IMPACT", w = 32, h = 32, affineMode = 1, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_HitSplat, cb = "AnimHitSplatBasic" }
T.gWaterPulseBubbleSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WaterPulseBubble, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWaterPulseBubble" }
T.gWaterPulseRingSpriteTemplate = { tag = "BLUE_RING_2", pal = "BLUE_RING_2", w = 16, h = 32, affineMode = 3, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sWaterPulseRingAffineAnimTable, cb = "AnimWaterPulseRing" }
T.gWavyMusicNotesSpriteTemplate = { tag = "MUSIC_NOTES", pal = "MUSIC_NOTES", w = 16, h = 16, affineMode = 3, objBlend = false, priority = 2, anims = A.gMusicNotesAnimTable, affine = F.sMusicNotesAffineAnimTable, cb = "AnimWavyMusicNotes" }
T.gWeakFrustrationAngerMarkSpriteTemplate = { tag = "ANGER", pal = "ANGER", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWeakFrustrationAngerMark" }
T.gWeatherBallFireDownSpriteTemplate = { tag = "SMALL_EMBER", pal = "SMALL_EMBER", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.gAnims_BasicFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWeatherBallDown" }
T.gWeatherBallIceDownSpriteTemplate = { tag = "HAIL", pal = "HAIL", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_WeatherBallIceDown, cb = "AnimWeatherBallDown" }
T.gWeatherBallNormalDownSpriteTemplate = { tag = "WEATHER_BALL", pal = "WEATHER_BALL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WeatherBallNormal, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWeatherBallDown" }
T.gWeatherBallRockDownSpriteTemplate = { tag = "ROCKS", pal = "ROCKS", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_BasicRock__2, affine = F.sAffineAnims_BasicRock, cb = "AnimWeatherBallDown" }
T.gWeatherBallUpSpriteTemplate = { tag = "WEATHER_BALL", pal = "WEATHER_BALL", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WeatherBallNormal, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWeatherBallUp" }
T.gWeatherBallWaterDownSpriteTemplate = { tag = "SMALL_BUBBLES", pal = "SMALL_BUBBLES", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.sAnims_WeatherBallWaterDown, affine = F.sAffineAnims_WeatherBallWaterDown, cb = "AnimWeatherBallDown" }
T.gWebThreadSpriteTemplate = { tag = "WEB_THREAD", pal = "WEB_THREAD", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimTranslateWebThread" }
T.gWhirlpoolSpriteTemplate = { tag = "WATER_ORB", pal = "WATER_ORB", w = 16, h = 16, affineMode = 1, objBlend = true, priority = 2, anims = A.gAnims_WaterMudOrb, affine = F.sAffineAnims_Whirlpool, cb = "AnimParticleInVortex" }
T.gWhirlwindLineSpriteTemplate = { tag = "WHIRLWIND_LINES", pal = "WHIRLWIND_LINES", w = 32, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WhirlwindLines, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWhirlwindLine" }
T.gWhiteHaloSpriteTemplate = { tag = "ROUND_WHITE_HALO", pal = "ROUND_WHITE_HALO", w = 64, h = 64, affineMode = 0, objBlend = true, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWhiteHalo" }
T.gWillOWispFireSpriteTemplate = { tag = "WISP_FIRE", pal = "WISP_FIRE", w = 32, h = 32, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WillOWispFire, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWillOWispFire" }
T.gWillOWispOrbSpriteTemplate = { tag = "WISP_ORB", pal = "WISP_ORB", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sAnims_WillOWispOrb, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWillOWispOrb" }
T.gWishStarSpriteTemplate = { tag = "GOLD_STARS", pal = "GOLD_STARS", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimWishStar" }
T.gYawnCloudSpriteTemplate = { tag = "PINK_CLOUD", pal = "PINK_CLOUD", w = 32, h = 32, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sYawnCloudAffineAnimTable, cb = "AnimYawnCloud" }
T.gZapCannonBallSpriteTemplate = { tag = "BLACK_BALL_2", pal = "BLACK_BALL_2", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "TranslateAnimSpriteToTargetMonLocation" }
T.gZapCannonSparkSpriteTemplate = { tag = "SPARK_2", pal = "SPARK_2", w = 16, h = 16, affineMode = 1, objBlend = false, priority = 2, anims = A.gDummySpriteAnimTable, affine = F.sAffineAnims_FlashingSpark, cb = "AnimZapCannonSpark" }
T.gLeafBladeSpriteTemplate = { tag = "LEAF", pal = "LEAF", w = 16, h = 16, affineMode = 0, objBlend = false, priority = 2, anims = A.sLeafBladeAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "SpriteCallbackDummy" }
T.gSolarBeamSmallOrbSpriteTemplate = { tag = "ORBS", pal = "ORBS", w = 8, h = 8, affineMode = 0, objBlend = false, priority = 2, anims = A.sSolarBeamSmallOrbAnimTable, affine = F.gDummySpriteAffineAnimTable, cb = "AnimSolarBeamSmallOrb" }
return T

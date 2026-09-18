
local T = {}

local function A(list) return list end
local END = { e = true }
local AEND = { e = true }

local function frames(...)
  local out = {}
  for i, f in ipairs({ ... }) do out[i] = f end
  return out
end

local function F(img, dur, h, v) return { f = img, d = dur, h = h, v = v } end
local function J(i) return { jump = i } end
local function L(n) return { loop = n } end
local function AF(xs, ys, r, d) return { xs = xs, ys = ys, r = r, d = d % 256 } end

local OFF, NORMAL, DOUBLE = 0, 1, 3

-- pokefirered/src/battle_anim_bug.c:20
local MEGAHORN_AFF = {
  [0] = { AF(0x100, 0x100, 30, 0), AEND },
  [1] = { AF(0x100, 0x100, -99, 0), AEND },
  [2] = { AF(0x100, 0x100, 94, 0), AEND },
}
-- pokefirered/src/battle_anim_bug.c:56
local LEECH_AFF = {
  [0] = { AF(0, 0, -33, 1), AEND },
  [1] = { AF(0, 0, 96, 1), AEND },
  [2] = { AF(0, 0, -96, 1), AEND },
}
-- pokefirered/src/battle_anim_bug.c:114
local SPIDER_WEB_AFF = { [0] = { AF(0x10, 0x10, 0, 0), AF(0x6, 0x6, 0, 1), J(1) } }
-- pokefirered/src/battle_anim_bug.c:170
local TAIL_GLOW_AFF = { [0] = {
  AF(0x10, 0x10, 0, 0), AF(0x8, 0x8, 0, 18), L(0), AF(-0x5, -0x5, 0, 8), AF(0x5, 0x5, 0, 8), L(5), AEND,
} }

T.gMegahornHornSpriteTemplate = { affineMode = DOUBLE, affine = MEGAHORN_AFF }
T.gLeechLifeNeedleSpriteTemplate = { affineMode = NORMAL, affine = LEECH_AFF }
T.gWebThreadSpriteTemplate = { affineMode = OFF }
T.gStringWrapSpriteTemplate = { affineMode = OFF }
T.gSpiderWebSpriteTemplate = { affineMode = DOUBLE, affine = SPIDER_WEB_AFF, objBlend = true }
T.gLinearStingerSpriteTemplate = { affineMode = NORMAL }
T.gPinMissileSpriteTemplate = { affineMode = NORMAL }
T.gIcicleSpearSpriteTemplate = { affineMode = NORMAL }
T.gTailGlowOrbSpriteTemplate = { affineMode = NORMAL, affine = TAIL_GLOW_AFF, objBlend = true }

-- pokefirered/src/battle_anim_electric.c:37
local LIGHTNING_ANIMS = { [0] = { F(0, 5), F(16, 5), F(32, 8), F(48, 5), F(64, 5), END } }
local FLASHING_SPARK_AFF = { [0] = { AF(0, 0, 20, 1), J(0) } }
local THUNDERBOLT_ORB_ANIMS = { [0] = { F(0, 6), F(16, 6), F(32, 6), J(0) } }
local THUNDERBOLT_ORB_AFF = { [0] = { AF(0xE8, 0xE8, 0, 0), AF(-0x8, -0x8, 0, 10), AF(0x8, 0x8, 0, 10), J(1) } }
local CHARGING_PARTICLE_ANIMS = {
  [0] = { F(3, 1), F(2, 1), F(1, 1), F(0, 1), END },
  [1] = { F(0, 5), F(1, 5), F(2, 5), F(3, 5), END },
}
-- pokefirered/src/battle_anim_electric.c:294
local GROWING_ORB_AFF = {
  [0] = { AF(0x10, 0x10, 0, 0), AF(0x4, 0x4, 0, 60), AF(0x100, 0x100, 0, 0), L(0), AF(-0x4, -0x4, 0, 5), AF(0x4, 0x4, 0, 5), L(10), AEND },
  [1] = { AF(0x10, 0x10, 0, 0), AF(0x8, 0x8, 0, 30), AF(0x100, 0x100, 0, 0), AF(-0x4, -0x4, 0, 5), AF(0x4, 0x4, 0, 5), J(3) },
  [2] = { AF(0x10, 0x10, 0, 0), AF(0x8, 0x8, 0, 30), AF(-0x8, -0x8, 0, 30), AEND },
}
local ELECTRIC_PUFF_ANIMS = { [0] = { F(0, 3), F(16, 3), F(32, 3), F(48, 3), END } }
local VOLT_BOLT_ANIMS = {
  [0] = { F(0, 3), END }, [1] = { F(2, 3), END }, [2] = { F(4, 3), END }, [3] = { F(6, 3), END },
}
local VOLT_BOLT_AFF = { [0] = { AF(0x100, 0x100, 64, 0), AEND } }

T.gLightningSpriteTemplate = { affineMode = OFF, anims = LIGHTNING_ANIMS }
T.gSparkElectricitySpriteTemplate = { affineMode = NORMAL }
T.gZapCannonSparkSpriteTemplate = { affineMode = NORMAL, affine = FLASHING_SPARK_AFF }
T.gThunderboltOrbSpriteTemplate = { affineMode = NORMAL, anims = THUNDERBOLT_ORB_ANIMS, affine = THUNDERBOLT_ORB_AFF }
T.gSparkElectricityFlashingSpriteTemplate = { affineMode = NORMAL, affine = FLASHING_SPARK_AFF }
T.gElectricitySpriteTemplate = { affineMode = OFF }
T.sElectricBoltSegmentSpriteTemplate = { affineMode = OFF, tag = "SPARK", w = 8, h = 8 }
T.gThunderWaveSpriteTemplate = { affineMode = OFF, tag = "SPARK_H", w = 32, h = 16 }
T.gElectricChargingParticlesSpriteTemplate = { affineMode = OFF, anims = CHARGING_PARTICLE_ANIMS, tag = "ELECTRIC_ORBS", w = 8, h = 8 }
T.gGrowingChargeOrbSpriteTemplate = { affineMode = NORMAL, affine = GROWING_ORB_AFF, objBlend = true }
T.gElectricPuffSpriteTemplate = { affineMode = OFF, anims = ELECTRIC_PUFF_ANIMS }
T.gVoltTackleOrbSlideSpriteTemplate = { affineMode = NORMAL, affine = GROWING_ORB_AFF, objBlend = true }
T.gVoltTackleBoltSpriteTemplate = { affineMode = DOUBLE, anims = VOLT_BOLT_ANIMS, affine = VOLT_BOLT_AFF, tag = "SPARK", w = 8, h = 16 }
T.gGrowingShockWaveOrbSpriteTemplate = { affineMode = NORMAL, affine = GROWING_ORB_AFF, objBlend = true }
T.sShockWaveProgressingBoltSpriteTemplate = { affineMode = OFF, tag = "SPARK", w = 8, h = 8 }

-- pokefirered/src/battle_anim_ground.c:29
local BONEMERANG_AFF = { [0] = { AF(0, 0, 15, 1), J(0) } }
local SPINNING_BONE_AFF = { [0] = { AF(0, 0, 20, 1), J(0) } }
T.gBonemerangSpriteTemplate = { affineMode = NORMAL, affine = BONEMERANG_AFF }
T.gSpinningBoneSpriteTemplate = { affineMode = NORMAL, affine = SPINNING_BONE_AFF }
T.gSandAttackDirtSpriteTemplate = { affineMode = OFF }
T.gMudSlapMudSpriteTemplate = { affineMode = OFF, anims = { [0] = { F(1, 1), END } } }
T.gMudsportMudSpriteTemplate = { affineMode = OFF }
T.gDirtPlumeSpriteTemplate = { affineMode = OFF }
T.gDirtMoundSpriteTemplate = { affineMode = OFF }

-- pokefirered/src/battle_anim_poison.c:40
local POISON_PROJECTILE_ANIMS = {
  [0] = { F(0, 1), END },
  [1] = { F(4, 1), END },
  [2] = { F(8, 1), END },
}
local POISON_PROJECTILE_AFF = { [0] = { AF(0x160, 0x160, 0, 0), AF(-0xA, -0xA, 0, 10), AF(0xA, 0xA, 0, 10), J(0) } }
local SLUDGE_HIT_AFF = { [0] = { AF(0xEC, 0xEC, 0, 0), AEND } }
local DROPLET_AFF = { [0] = { AF(-0x10, 0x10, 0, 6), AF(0x10, -0x10, 0, 6), J(0) } }
local BUBBLE_AFF = { [0] = { AF(0x9C, 0x9C, 0, 0), AF(0x5, 0x5, 0, 20), AEND } }
T.gSludgeProjectileSpriteTemplate = { affineMode = DOUBLE, anims = POISON_PROJECTILE_ANIMS, affine = POISON_PROJECTILE_AFF }
T.gAcidPoisonBubbleSpriteTemplate = { affineMode = DOUBLE, anims = POISON_PROJECTILE_ANIMS, affine = POISON_PROJECTILE_AFF }
T.gSludgeBombHitParticleSpriteTemplate = { affineMode = NORMAL, anims = { [0] = { F(8, 1), END } }, affine = SLUDGE_HIT_AFF }
T.gAcidPoisonDropletSpriteTemplate = { affineMode = DOUBLE, anims = { [0] = { F(4, 1), END }, [1] = { F(8, 1), END } }, affine = DROPLET_AFF }
T.gPoisonBubbleSpriteTemplate = { affineMode = NORMAL, anims = POISON_PROJECTILE_ANIMS, affine = BUBBLE_AFF }
T.gWaterBubbleSpriteTemplate = { affineMode = NORMAL, anims = { [0] = { F(0, 1), END } }, affine = BUBBLE_AFF, objBlend = true }

-- pokefirered/src/battle_anim_ice.c:70
local ICE_LARGE = { [0] = { F(4, 1), END } }
local ICE_SMALL = { [0] = { F(6, 1), END } }
local SNOWBALL = { [0] = { F(7, 1), END } }
local BLIZZARD_CRYSTAL = { [0] = { F(8, 1), END } }
local ICE_SPIRAL_AFF = { [0] = { AF(0, 0, 40, 1), J(0) } }
local ICE_BEAM_INNER_AFF = { [0] = { AF(0, 0, 10, 1), J(0) } }
local ICE_HIT_AFF = { [0] = { AF(0xCE, 0xCE, 0, 0), AF(0x5, 0x5, 0, 10), AF(0, 0, 0, 6), AEND } }
local CLOUD_ANIMS = { [0] = { F(0, 8), F(8, 8), J(0) } }
local ICE_BALL_ANIMS = { [0] = { F(0, 1), END }, [1] = { F(16, 4), F(32, 4), F(48, 4), F(64, 4), END } }
local ICE_BALL_AFF = {
  [0] = { AF(0xE0, 0xE0, 0, 0), AEND },
  [1] = { AF(0x118, 0x118, 0, 0), AEND },
  [2] = { AF(0x150, 0x150, 0, 0), AEND },
  [3] = { AF(0x180, 0x180, 0, 0), AEND },
  [4] = { AF(0x1C0, 0x1C0, 0, 0), AEND },
}
local ICE_GROUND_SPIKE = { [0] = { F(0, 5), F(2, 5), F(4, 5), F(6, 5), F(4, 5), F(2, 5), F(0, 5), END } }
local HAIL_AFF = {
  [0] = { AF(0x100, 0x100, 0, 0), AEND },
  [1] = { AF(0xF0, 0xF0, 0, 0), AEND },
  [2] = { AF(0xE0, 0xE0, 0, 0), AEND },
}
T.gIceCrystalSpiralInwardLarge = { affineMode = DOUBLE, anims = ICE_LARGE, affine = ICE_SPIRAL_AFF, objBlend = true }
T.gIceCrystalSpiralInwardSmall = { affineMode = OFF, anims = ICE_SMALL, objBlend = true }
T.gIceBeamInnerCrystalSpriteTemplate = { affineMode = NORMAL, anims = ICE_LARGE, affine = ICE_BEAM_INNER_AFF, objBlend = true }
T.gIceBeamOuterCrystalSpriteTemplate = { affineMode = OFF, anims = ICE_SMALL, objBlend = true }
T.gIceCrystalHitLargeSpriteTemplate = { affineMode = NORMAL, anims = ICE_LARGE, affine = ICE_HIT_AFF, objBlend = true, tag = "ICE_CRYSTALS", w = 8, h = 16 }
T.gIceCrystalHitSmallSpriteTemplate = { affineMode = NORMAL, anims = ICE_SMALL, affine = ICE_HIT_AFF, objBlend = true }
T.gSwirlingSnowballSpriteTemplate = { affineMode = OFF, anims = SNOWBALL }
T.gBlizzardIceCrystalSpriteTemplate = { affineMode = OFF, anims = BLIZZARD_CRYSTAL }
T.gPowderSnowSnowballSpriteTemplate = { affineMode = OFF, anims = SNOWBALL }
T.gIceGroundSpikeSpriteTemplate = { affineMode = OFF, anims = ICE_GROUND_SPIKE, objBlend = true }
T.gMistCloudSpriteTemplate = { affineMode = OFF, anims = CLOUD_ANIMS, objBlend = true }
T.gSmogCloudSpriteTemplate = { affineMode = OFF, anims = CLOUD_ANIMS, objBlend = true }
T.gMistBallSpriteTemplate = { affineMode = OFF }
T.gPoisonGasCloudSpriteTemplate = { affineMode = OFF, anims = CLOUD_ANIMS, objBlend = true }
T.sHailParticleSpriteTemplate = { affineMode = NORMAL, affine = HAIL_AFF, tag = "HAIL", w = 16, h = 16 }
T.gIceBallChunkSpriteTemplate = { affineMode = DOUBLE, anims = ICE_BALL_ANIMS, affine = ICE_BALL_AFF }
T.gIceBallImpactShardSpriteTemplate = { affineMode = OFF, anims = ICE_SMALL }

-- pokefirered/src/battle_anim_rock.c:27
local FLYING_ROCK = { [0] = { F(32, 1), END }, [1] = { F(48, 1), END }, [2] = { F(64, 1), END } }
local BASIC_ROCK = {
  [0] = { F(0, 1), END }, [1] = { F(16, 1), END }, [2] = { F(32, 1), END },
  [3] = { F(48, 1), END }, [4] = { F(64, 1), END }, [5] = { F(80, 1), END },
}
local BASIC_ROCK_AFF = { [0] = { AF(0, 0, -5, 5), J(0) }, [1] = { AF(0, 0, 5, 5), J(0) } }
local WATER_MUD_ORB = { [0] = { F(0, 1), F(4, 1), F(8, 1), F(12, 1), J(0) } }
local WHIRLPOOL_AFF = { [0] = { AF(0xC0, 0xC0, 0, 0), AF(0x2, -0x3, 0, 5), AF(-0x2, 0x3, 0, 5), J(1) } }
local BASIC_FIRE = { [0] = { F(16, 4), F(32, 4), F(48, 4), F(64, 4), J(0) } }
T.gFallingRockSpriteTemplate = { affineMode = OFF, anims = FLYING_ROCK }
T.gRockFragmentSpriteTemplate = { affineMode = OFF, anims = FLYING_ROCK }
T.gSwirlingDirtSpriteTemplate = { affineMode = OFF }
T.gWhirlpoolSpriteTemplate = { affineMode = NORMAL, anims = WATER_MUD_ORB, affine = WHIRLPOOL_AFF, objBlend = true }
T.gFireSpinSpriteTemplate = { affineMode = OFF, anims = BASIC_FIRE }
T.gFlyingSandCrescentSpriteTemplate = { affineMode = OFF, priority = 1 }
T.gAncientPowerRockSpriteTemplate = { affineMode = OFF, anims = BASIC_ROCK }
T.gRolloutMudSpriteTemplate = { affineMode = OFF, tag = "MUD_SAND", w = 8, h = 8 }
T.gRolloutRockSpriteTemplate = { affineMode = OFF, tag = "ROCKS", w = 32, h = 32 }
T.gRockTombRockSpriteTemplate = { affineMode = OFF, anims = BASIC_ROCK }
T.gRockBlastRockSpriteTemplate = { affineMode = NORMAL, anims = BASIC_ROCK, affine = BASIC_ROCK_AFF }
T.gRockScatterSpriteTemplate = { affineMode = NORMAL, anims = BASIC_ROCK, affine = BASIC_ROCK_AFF }
T.gSafariRockTemplate = { affineMode = OFF, anims = { [0] = { F(64, 1), END } } }
T.gSafariBaitSpriteTemplate = { affineMode = OFF }

-- pokefirered/src/battle_anim_water.c:59
local RAIN_DROP = { [0] = { F(0, 2), F(8, 2), F(16, 2), F(24, 6), F(32, 2), F(40, 2), F(48, 2), END } }
local BUBBLE_PROJ_ANIMS = { [0] = { F(0, 1), F(4, 5), F(8, 5), END } }
local BUBBLE_PROJ_AFF = { [0] = { AF(-0x5, -0x5, 0, 10), AF(0x5, 0x5, 0, 10), J(0) } }
local AURORA_RING_ANIMS = { [0] = { F(0, 1), END }, [1] = { F(4, 1), END } }
local AURORA_RING_AFF = { [0] = { AF(0, 0, 0, 1), AF(0x60, 0x60, 0, 1), AEND } }
local FLAMETHROWER = { [0] = { F(16, 2), F(32, 2), F(48, 2), J(0) } }
-- pokefirered/src/battle_anim_effects_2.c:275
local GROWING_RING_AFF = { [0] = { AF(32, 32, 0, 0), AF(7, 7, 0, -56), AEND } }
local HYDRO_CHARGE_AFF = { [0] = { AF(0x3, 0x3, 10, 50), AF(0, 0, 0, 10), AF(-0x14, -0x14, -10, 20), AEND } }
local HYDRO_BEAM_AFF = { [0] = { AF(0x150, 0x150, 0, 0), AEND } }
local WATER_PULSE_BUBBLE = { [0] = { F(8, 1), END }, [1] = { F(9, 1), END } }
local WATER_PULSE_RING_BUBBLE_AFF = {
  [0] = { AF(0x100, 0x100, 0, 0), AF(-0xA, -0xA, 0, 15), AEND },
  [1] = { AF(0xE0, 0xE0, 0, 0), AF(-0x8, -0x8, 0, 15), AEND },
}
-- pokefirered/src/battle_anim_effects_2.c:282
local WATER_PULSE_RING_AFF = { [0] = {
  AF(5, 5, 0, 10), AF(-10, -10, 0, 10), AF(10, 10, 0, 10), AF(-10, -10, 0, 10),
  AF(10, 10, 0, 10), AF(-10, -10, 0, 10), AF(10, 10, 0, 10), AEND,
} }
T.gRainDropSpriteTemplate = { affineMode = OFF, anims = RAIN_DROP, tag = "RAIN_DROPS", w = 16, h = 32 }
T.gWaterBubbleProjectileSpriteTemplate = { affineMode = NORMAL, anims = BUBBLE_PROJ_ANIMS, affine = BUBBLE_PROJ_AFF, objBlend = true }
T.gAuroraBeamRingSpriteTemplate = { affineMode = DOUBLE, anims = AURORA_RING_ANIMS, affine = AURORA_RING_AFF }
T.gHydroPumpOrbSpriteTemplate = { affineMode = OFF, anims = WATER_MUD_ORB, objBlend = true }
T.gMudShotOrbSpriteTemplate = { affineMode = OFF, anims = WATER_MUD_ORB, objBlend = true }
T.gSignalBeamRedOrbSpriteTemplate = { affineMode = OFF }
T.gSignalBeamGreenOrbSpriteTemplate = { affineMode = OFF }
T.gFlamethrowerFlameSpriteTemplate = { affineMode = OFF, anims = FLAMETHROWER }
T.gPsywaveRingSpriteTemplate = { affineMode = DOUBLE, affine = GROWING_RING_AFF }
T.gHydroCannonChargeSpriteTemplate = { affineMode = DOUBLE, anims = WATER_MUD_ORB, affine = HYDRO_CHARGE_AFF, objBlend = true }
T.gHydroCannonBeamSpriteTemplate = { affineMode = DOUBLE, anims = WATER_MUD_ORB, affine = HYDRO_BEAM_AFF, objBlend = true }
T.gWaterGunDropletSpriteTemplate = { affineMode = DOUBLE, anims = { [0] = { F(4, 1), END } }, affine = DROPLET_AFF, objBlend = true }
T.gSmallBubblePairSpriteTemplate = { affineMode = OFF, anims = { [0] = { F(12, 6), F(13, 6), J(0) } } }
T.gSmallDriftingBubblesSpriteTemplate = { affineMode = OFF }
T.gWaterPulseBubbleSpriteTemplate = { affineMode = OFF, anims = WATER_PULSE_BUBBLE }
T.gWaterPulseRingBubbleSpriteTemplate = { affineMode = NORMAL, anims = WATER_PULSE_BUBBLE, affine = WATER_PULSE_RING_BUBBLE_AFF, tag = "SMALL_BUBBLES", w = 8, h = 8 }
T.gWaterPulseRingSpriteTemplate = { affineMode = DOUBLE, affine = WATER_PULSE_RING_AFF }

T.gSmallWaterOrbSpriteTemplate = { affineMode = OFF, tag = "GLOWY_BLUE_ORB", w = 8, h = 8 }
-- pokefirered/src/battle_anim_normal.c:133
T.gWaterHitSplatSpriteTemplate = { affineMode = NORMAL, objBlend = true, tag = "WATER_IMPACT", w = 32, h = 32, affine = {
  [0] = { AF(0, 0, 0, 8), AEND },
  [1] = { AF(0xD8, 0xD8, 0, 0), AF(0, 0, 0, 8), AEND },
  [2] = { AF(0xB0, 0xB0, 0, 0), AF(0, 0, 0, 8), AEND },
  [3] = { AF(0x80, 0x80, 0, 0), AF(0, 0, 0, 8), AEND },
} }

T.EMPTY = { affineMode = OFF }

return T

-- pret SpriteTemplate → tag + Lua callback id (named, no ROM pointers).
-- Used by extract (tag rewrite) and runtime createsprite.

local AnimTemplates = {}

-- Default sizes match common OAM shapes in battle_anim_*.c
local function T(tag, cb, w, h, opts)
  opts = opts or {}
  return {
    tag = tag,
    callback = cb,
    w = w or 32,
    h = h or 32,
    noGfx = opts.noGfx,
    anchor = opts.anchor, -- "attacker"|"target"|nil (infer from args)
  }
end

-- Keyed by full pret symbol and short name
local MAP = {
  -- Invisible helpers (move battler via task)
  gHorizontalLungeSpriteTemplate = T(nil, "HorizontalLunge", 0, 0, { noGfx = true }),
  gVerticalDipSpriteTemplate = T(nil, "VerticalDip", 0, 0, { noGfx = true }),
  gSlideMonToOffsetSpriteTemplate = T(nil, "SlideMonToOffset", 0, 0, { noGfx = true }),
  gSlideMonToOriginalPosSpriteTemplate = T(nil, "SlideMonToOriginalPos", 0, 0, { noGfx = true }),

  -- IMPACT family
  gBasicHitSplatSpriteTemplate = T("IMPACT", "HitSplatBasic", 32, 32, { anchor = "fromArgs" }),
  gHandleInvertHitSplatSpriteTemplate = T("IMPACT", "HitSplatBasic", 32, 32, { anchor = "fromArgs" }),
  gRandomPosHitSplatSpriteTemplate = T("IMPACT", "HitSplatBasic", 32, 32, { anchor = "target" }),
  gMonEdgeHitSplatSpriteTemplate = T("IMPACT", "HitSplatBasic", 32, 32, { anchor = "target" }),
  gWaterHitSplatSpriteTemplate = T("WATER_IMPACT", "HitSplatBasic", 32, 32, { anchor = "fromArgs" }),
  gCrossImpactSpriteTemplate = T("CROSS_IMPACT", "HitSplatBasic", 32, 32),

  -- Growl / Roar
  gRoarNoiseLineSpriteTemplate = T("NOISE_LINE", "RoarNoiseLine", 32, 32, { anchor = "attacker" }),

  -- Fire family (pokefirered/src/battle_anim_fire.c)
  gEmberSpriteTemplate = T("SMALL_EMBER", "TranslateAnimSpriteToTargetMonLocation", 32, 32, { anchor = "attacker" }),
  gEmberFlareSpriteTemplate = T("SMALL_EMBER", "AnimEmberFlare", 32, 32, { anchor = "target" }),
  gBurnFlameSpriteTemplate = T("SMALL_EMBER", "AnimBurnFlame", 32, 32, { anchor = "target" }),
  gFireSpiralInwardSpriteTemplate = T("SMALL_EMBER", "AnimFireSpiralInward", 32, 32, { anchor = "target" }),
  gFireSpreadSpriteTemplate = T("SMALL_EMBER", "AnimFireSpread", 32, 32, { anchor = "target" }),
  gLargeFlameSpriteTemplate = T("FIRE", "AnimLargeFlame", 32, 32, { anchor = "attacker" }),
  gLargeFlameScatterSpriteTemplate = T("FIRE", "AnimLargeFlame", 32, 32, { anchor = "attacker" }),
  gFirePlumeSpriteTemplate = T("FIRE_PLUME", "AnimFirePlume", 32, 32, { anchor = "attacker" }),
  gSunlightRaySpriteTemplate = T("SUNLIGHT", "AnimSunlight", 32, 32, { anchor = "target" }),
  gFireBlastRingSpriteTemplate = T("SMALL_EMBER", "AnimFireRing", 32, 32, { anchor = "attacker" }),
  gFireBlastCrossSpriteTemplate = T("SMALL_EMBER", "AnimFireCross", 32, 32, { anchor = "target" }),
  gFireSpiralOutwardSpriteTemplate = T("SMALL_EMBER", "AnimFireSpiralOutward", 32, 32, { anchor = "attacker" }),
  gWeatherBallFireDownSpriteTemplate = T("SMALL_EMBER", "AnimWeatherBallDown", 32, 32, { anchor = "target" }),
  gEruptionLaunchRockSpriteTemplate = T("WARM_ROCK", "AnimEruptionLaunchRock", 32, 32, { anchor = "attacker" }),
  gEruptionFallingRockSpriteTemplate = T("WARM_ROCK", "AnimEruptionFallingRock", 32, 32, { anchor = "target" }),
  gWillOWispOrbSpriteTemplate = T("WISP_ORB", "AnimWillOWispOrb", 32, 32, { anchor = "attacker" }),
  gWillOWispFireSpriteTemplate = T("WISP_FIRE", "AnimWillOWispFire", 32, 32, { anchor = "target" }),

  -- Common
  gLeerSpriteTemplate = T("LEER", "SimpleFadeOut", 32, 32, { anchor = "attacker" }),
  gMusicNotesSpriteTemplate = T("MUSIC_NOTES", "SimpleFadeOut", 16, 16),
  gConfusionDuckSpriteTemplate = T("DUCK", "SimpleFadeOut", 32, 32),
}

-- Alias without leading g
for k, v in pairs(MAP) do
  local short = k:gsub("^g", "")
  if not MAP[short] then MAP[short] = v end
end

function AnimTemplates.get(name)
  if not name then return nil end
  name = tostring(name)
  return MAP[name] or MAP[name:gsub("^g", "")] or MAP["g" .. name]
end

--- Infer ANIM_TAG file stem from tag id (IMPACT → impact, NOISE_LINE → noise_line).
function AnimTemplates.tagToFileStem(tag)
  tag = tostring(tag or ""):upper():gsub("^ANIM_TAG_", "")
  return tag:lower()
end

function AnimTemplates.tagFromLoadOrTemplate(loadTag, templateName)
  local t = AnimTemplates.get(templateName)
  if t and t.tag then return t.tag end
  if loadTag and loadTag ~= "" then return tostring(loadTag):upper():gsub("^ANIM_TAG_", "") end
  return "IMPACT"
end

AnimTemplates.MAP = MAP

return AnimTemplates

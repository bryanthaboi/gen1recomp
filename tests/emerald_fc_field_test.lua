package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("src.core.game3.se_ids").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local ROOT = "data/generated/gba/"
if not cache:read(ROOT .. "field_fc/manifest.lua") or not cache:read(ROOT .. "field_effects/objects.lua") then
  print("emerald_fc_field_test: skipped (no Emerald field_fc cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()

local function loadLua(rel)
  local src = cache:read(ROOT .. rel)
  local chunk = src and load(src, "@" .. rel, "t", {})
  return chunk and chunk()
end

local fc = loadLua("field_fc/manifest.lua")
local objects = loadLua("field_effects/objects.lua")
local tagName = objects.paletteTags

eq(fc.family, "rse", "field_fc manifest is the RSE family")
eq(tagName[fc.gfx[0].paletteTag], "gObjectEventPal_Brendan", "Brendan (gfx 0) uses the Brendan palette")
eq(tagName[fc.playerReflections[fc.gfx[0].paletteTag]], "gObjectEventPal_BrendanReflection",
  "sPlayerReflectionPaletteSets pairs Brendan with BrendanReflection")
eq(tagName[fc.playerReflections[fc.gfx[89].paletteTag]], "gObjectEventPal_MayReflection",
  "sPlayerReflectionPaletteSets pairs May with MayReflection")
eq(tagName[fc.gfx[0].reflectionTag], "gObjectEventPal_BridgeReflection", "Brendan's high-bridge reflection palette")
eq(fc.reflectionMap[2], 6, "gReflectionEffectPaletteMap NPC 1 -> slot 6")
eq(tagName[fc.slotTags[6]], "gObjectEventPal_Npc1Reflection", "slot 6 holds Npc1Reflection")
local n = 0
for _ in pairs(fc.palettes) do n = n + 1 end
check(n >= 30, "object event palettes by tag (" .. n .. ")")
eq(#fc.palettes[fc.gfx[0].paletteTag], 16, "palettes carry 16 colours")
eq(fc.gfx[0].shadow, 1, "Brendan uses SHADOW_SIZE_M")
eq(fc.gfx[0].tracks, 1, "Brendan leaves footprints (TRACKS_FOOT)")
eq(fc.gfx[1].tracks, 2, "Brendan Mach Bike leaves tire tracks (TRACKS_BIKE_TIRE)")

local radii = fc.flashRadii
eq(radii and radii[0], 200, "flash level 0 radius")
eq(radii and radii[1], 72, "flash level 1 radius")
eq(radii and radii[7], 24, "flash level 7 radius")
eq(radii and radii[8], 0, "flash level 8 is fully black")

local mt = fc.mirageTower
eq(mt and #mt.crumblePositions, 8, "eight ceiling crumble positions")
eq(mt and mt.crumblePositions[1][3], 65, "first crumble falls to y 65")
eq(mt and #mt.invisibleMetatiles, 18, "eighteen Mirage Tower metatiles vanish")
local Constants = require("src.core.game3.constants")
local C = Constants.of("emerald")
eq(mt and mt.invisibleMetatiles[1].metatile, C:require("metatile_labels", "METATILE_Mauville_DeepSand_Center"),
  "first vanishing metatile is Mauville deep sand")
eq(#(cache:read(ROOT .. "field_fc/mirage_tower_crumbles.idx") or ""), 256, "crumble sprite indices")

local gates = loadLua("rotating_gates/manifest.lua")
eq(#gates.puzzles.fortree, 8, "Fortree gym has eight rotating gates")
eq(#gates.puzzles.trick_house, 11, "Trick House puzzle 6 has eleven gates")

local byName = {}
for _, o in ipairs(objects.objects) do byName[o.name] = o end
for _, o in ipairs(objects.extras or {}) do byName[o.name] = o end
for _, name in ipairs({ "short_grass", "sand_pile", "jump_tall_grass", "jump_small_splash", "jump_big_splash",
    "bubbles", "water_surfacing", "sparkle", "small_sparkle", "ash", "ash_puff", "tree_disguise",
    "mountain_disguise", "bike_tire_tracks", "sand_pillar", "secret_power_tree", "rayquaza", "bird" }) do
  check(byName[name] and byName[name].anims and #byName[name].anims > 0, name .. " has anims in the field effect manifest")
end
eq(#byName.tree_disguise.anims, 2, "disguise sheets have the idle and reveal anims")
eq(#byName.bike_tire_tracks.anims, 9, "bike tire tracks have nine track anims")

local events = loadLua("scripts/events.lua")
local disguise, buried, berry = 0, 0, 0
for _, ev in pairs(events) do
  for _, o in ipairs(ev.objects or {}) do
    if o.movementType == 0x39 or o.movementType == 0x3A then disguise = disguise + 1 end
    if o.movementType == 0x3F then buried = buried + 1 end
    if o.movementType == 0x0C then berry = berry + 1 end
  end
end
eq(disguise, 7, "seven disguised trainers (Routes 115/119/120/123)")
eq(buried, 2, "two buried trainers on Route 113")
check(berry >= 80, "berry tree objects (" .. berry .. ")")

T.finish()

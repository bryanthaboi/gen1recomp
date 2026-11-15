package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("src.core.game3.se_ids").select("emerald")
require("src.core.game3.song_ids").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local ROOT = "data/generated/gba/"
if not cache:read(ROOT .. "field_effects/objects.lua") or not cache:read(ROOT .. "doors/manifest.lua")
    or not cache:read(ROOT .. "scripts/events.lua") then
  print("emerald_field_objects_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()

local function loadLua(rel)
  local src = cache:read(ROOT .. rel)
  local chunk = src and load(src, "@" .. rel, "t", {})
  return chunk and chunk()
end

local events = loadLua("scripts/events.lua")
local function obj(mapId, lid)
  for _, o in ipairs(events[mapId] and events[mapId].objects or {}) do
    if o.localId == lid then return o end
  end
end
local jogger = obj("EM_ROUTE101", 2)
eq(jogger and jogger.movementType, 0x47, "Route 101 localId 2 keeps MOVEMENT_TYPE_JOG_IN_PLACE_RIGHT (FR-meaning id)")
eq(jogger and jogger.sprite, nil, "Emerald objects carry no FR host sprite name")
eq(obj("EM_LITTLEROOT_TOWN", 1).movementType, 2, "Littleroot kid wanders (MOVEMENT_TYPE_WANDER_AROUND)")
local slow, raw, frOnly = 0, 0, 0
for _, ev in pairs(events) do
  for _, o in ipairs(ev.objects or {}) do
    if o.movementTypeRaw then
      raw = raw + 1
      if o.movementType == 0x100 + o.movementTypeRaw then slow = slow + 1 end
    end
    if o.movementType and o.movementType >= 0x4D and o.movementType < 0x100 then frOnly = frOnly + 1 end
  end
end
eq(frOnly, 0, "no Emerald object carries an FR raise-hand / slower-wander id")
eq(raw, 6, "six Emerald objects use walk-slowly-in-place")
eq(slow, raw, "walk-slowly-in-place is canonical 0x100 + raw")

local OwSprites = require("src.core.game3.ow_sprites")
OwSprites.install(cache)
check(OwSprites.avatars() ~= nil, "ow manifest has the avatar table")
eq(OwSprites.playerGraphicsId({ session = { gender = 0 } }), 0, "Brendan normal from sPlayerAvatarGfxIds")
eq(OwSprites.playerGraphicsId({ session = { gender = 1 } }), 89, "May normal from sPlayerAvatarGfxIds")
eq(OwSprites.avatarGraphicsId("SURFING", false), 2, "Brendan surfing")
eq(OwSprites.avatarGraphicsId("UNDERWATER", true), 112, "May underwater")
eq(OwSprites.avatarGraphicsId("WATERING", false), 191, "Brendan watering")

local FieldEffects = require("src.core.game3.field_effects")
FieldEffects._cache, FieldEffects._manifest, FieldEffects._sheets = cache, nil, {}
local grass = FieldEffects.manifestObject("tall_grass")
eq(grass and (grass.fw .. "x" .. grass.fh .. "x" .. grass.frames), "16x16x5", "tall grass sheet from the manifest")
eq(FieldEffects.manifestObject("surf_blob").frames, 3, "Emerald surf blob has three frames")
eq(FieldEffects.manifestObject("fly_bird").name, "bird", "FR fly_bird name aliases to bird")
eq(FieldEffects.manifestObject("exclamation_question_mark").frames, 2, "exclamation/question icon sheet")
eq(FieldEffects.manifestObject("heart_icon").frames, 1, "heart icon sheet")
eq(FieldEffects.manifestObject("emoticons"), nil, "no FR emoticons sheet on Emerald")
eq(FieldEffects.fldeffName(0), "FLDEFF_EXCLAMATION_MARK_ICON", "FLDEFF 0 by name")
eq(FieldEffects.fldeffName(66), "FLDEFF_MOVE_DEOXYS_ROCK", "Emerald Deoxys rock move id")

local Doors = require("src.core.game3.doors")
Doors.release()
Doors._manifestLoaded, Doors._manifest = false, nil
local entry, info = Doors.getDoorEntryAt("EM_LITTLEROOT_TOWN", 5, 8)
eq(entry and entry.tile, "littleroot", "Brendan's house door is the Littleroot door")
eq(entry and entry.file, "littleroot__petalburg.rgba", "Littleroot door baked with General/Petalburg palettes")
eq(info and info.frames, 3, "Littleroot door has three frames")
eq(entry and entry.sound, "normal", "Littleroot door plays SE_DOOR")
check(cache:read(ROOT .. "doors/" .. (entry and entry.file or "?")) ~= nil, "Littleroot door sheet exists")
local mart
for y = 0, 19 do
  for x = 0, 19 do
    local e = Doors.getDoorEntryAt("EM_OLDALE_TOWN", x, y)
    if e and e.tile == "poke_mart" then mart = x .. "," .. y end
  end
end
check(mart ~= nil, "Oldale mart door found (" .. tostring(mart) .. ")")
eq(Doors.soundFor("sliding"), require("src.core.game3.se_ids").SE_SLIDING_DOOR, "sliding door sound by name")

local TrainerSight = require("src.core.game3.trainer_sight")
local C = require("src.core.game3.constants").of("emerald")
local calvin = C:id("trainers", "TRAINER_CALVIN_1")
check(calvin ~= nil, "TRAINER_CALVIN_1 resolves")
eq(TrainerSight.encounterMusic(calvin), C:song("MUS_ENCOUNTER_MALE"), "Calvin plays MUS_ENCOUNTER_MALE")
eq(TrainerSight.encounterMusic(C:id("trainers", "TRAINER_TIANA")), C:song("MUS_ENCOUNTER_FEMALE"),
  "Tiana (F_TRAINER_FEMALE | FEMALE) plays MUS_ENCOUNTER_FEMALE")
local allen = C:id("trainers", "TRAINER_ALLEN")
eq(TrainerSight.encounterMusic(allen), C:song("MUS_ENCOUNTER_MALE"), "Allen plays MUS_ENCOUNTER_MALE")

T.finish()

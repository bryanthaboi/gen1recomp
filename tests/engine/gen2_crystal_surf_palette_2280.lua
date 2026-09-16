-- engine/overworld/player_object.asm:29-41

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local Palettes = require("src.world.gen2.Palettes")
local World = require("src.world.gen2.World")

local RED = { { 255, 0, 0 }, { 200, 0, 0 }, { 120, 0, 0 }, { 0, 0, 0 } }
local BLUE = { { 0, 0, 255 }, { 0, 0, 200 }, { 0, 0, 120 }, { 0, 0, 0 } }
local PALETTES = { objects = { DAY = { RED, BLUE } } }

-- constants/sprite_data_constants.asm:15-38
eq(Palettes.objectPaletteId({ palette = 8 }), 0, "PAL_NPC_RED drops bit 3")
eq(Palettes.objectPaletteId({ palette = 9 }), 1, "PAL_NPC_BLUE drops bit 3")
eq(Palettes.objectPaletteId(nil), nil, "no object_event, no override")

-- data/sprites/sprites.asm:92
local SURF = { paletteId = 1 }
eq(Palettes.spritePalette(PALETTES, "DAY", SURF, nil), BLUE,
   "SPRITE_SURF's own table palette is PAL_OW_BLUE")
eq(Palettes.spritePalette(PALETTES, "DAY", SURF, { palette = 8 }), RED,
   "the map object's PAL_NPC_RED outranks the sheet")

local function newWorld(version, gender)
  GameVersion.set(version)
  local world = World.new({
    data = {}, save = { engineFlags = {}, player = { gender = gender } },
  })
  world.palettes = PALETTES
  world.daytime = "DAY"
  world.testVersion = version
  return world
end

local male = newWorld("crystal", "male")
eq(male:playerObjectDef().palette, 8, "Crystal's Chris spawns PAL_NPC_RED")
local female = newWorld("crystal", "female")
eq(female:playerObjectDef().palette, 9, "Crystal's Kris spawns PAL_NPC_BLUE")
-- pokegold/engine/overworld/player_object.asm:19
local gold = newWorld("gold", "male")
eq(gold:playerObjectDef(), nil, "Gold's SpawnPlayer stamps no palette")
eq(newWorld("silver", "male"):playerObjectDef(), nil,
   "and neither does Silver's")

local function baked(world, spriteDef)
  GameVersion.set(world.testVersion)
  local entity = { spriteDef = spriteDef, sprite = {} }
  function entity.sprite:setObjPalette(colors, group)
    entity.colors, entity.group = colors, group
  end
  world.player = entity
  world:applySpritePalette(entity)
  return entity
end

local chris = baked(male, SURF)
eq(chris.colors, RED, "Chris surfs orange")
eq(chris.group, "gen2:DAY:0", "and bakes under the overridden palette id")
eq(baked(female, SURF).colors, BLUE, "Kris surfs blue")
eq(baked(gold, SURF).colors, BLUE, "Gold's surf blob stays blue")

-- data/sprites/sprites.asm:61
local PIKA = { paletteId = 0 }
eq(baked(male, PIKA).colors, RED, "Chris's Surfing Pikachu is red")
eq(baked(female, PIKA).colors, BLUE, "Kris's Surfing Pikachu is blue")

local npc = { spriteDef = SURF, def = { palette = 8 }, sprite = {} }
function npc.sprite:setObjPalette(colors) npc.colors = colors end
male:applySpritePalette(npc)
eq(npc.colors, RED, "an NPC keeps taking entity.def")

GameVersion.set("red")
T.finish("gen2_crystal_surf_palette_2280")

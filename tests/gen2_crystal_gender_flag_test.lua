-- ENGINE_PLAYER_IS_FEMALE, the Crystal engine flag `checkflag` asks at 14 map
-- sites, and the Crystal-only Surf refusal that shares the wiring.
--   luajit tests/gen2_crystal_gender_flag_test.lua
--
-- Both come in a Crystal half and a Gold half: Gold declares no such flag and
-- keeps its documented "you can Surf on top of NPCs" bug (CT-10).
-- The cache half SKIPs when no crystal cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal gender flag")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local FieldMoves = require("src.world.gen2.FieldMoves")
local GameVersion = require("src.core.GameVersion")
local Save = require("src.core.gen2.Save")
local World = require("src.world.gen2.World")

local priorVersion = GameVersion.get()

-- ------------------------------------------------- the flag id, by name

-- constants/engine_flags.asm's const block, with the badge rows at the ids a
-- real crystal cache reports and a hole where parse_const_block met a
-- const_skip.  ENGINE_PLAYER_IS_FEMALE is row 100, so flag id 99.
local CRYSTAL_ORDER = {}
CRYSTAL_ORDER[27] = "ENGINE_ZEPHYRBADGE"
CRYSTAL_ORDER[28] = "ENGINE_HIVEBADGE"
CRYSTAL_ORDER[29] = "ENGINE_PLAINBADGE"
CRYSTAL_ORDER[30] = "ENGINE_FOGBADGE"
CRYSTAL_ORDER[31] = "ENGINE_MINERALBADGE"
CRYSTAL_ORDER[32] = "ENGINE_STORMBADGE"
CRYSTAL_ORDER[33] = "ENGINE_GLACIERBADGE"
CRYSTAL_ORDER[34] = "ENGINE_RISINGBADGE"
CRYSTAL_ORDER[35] = "ENGINE_BOULDERBADGE"
CRYSTAL_ORDER[42] = "ENGINE_EARTHBADGE"
-- the hole: nothing at 43..99, which is where ipairs would stop
CRYSTAL_ORDER[100] = "ENGINE_PLAYER_IS_FEMALE"

FieldMoves.bindEngineFlags(CRYSTAL_ORDER)
eq(FieldMoves.FEMALE_FLAG, 99, "ENGINE_PLAYER_IS_FEMALE is flag 99 by NAME")
eq(FieldMoves.BADGE_FLAG[26].name, "ZEPHYR",
  "and the badge block walks past the const_skip hole")
eq(FieldMoves.BADGE_FLAG[41].name, "EARTH", "including the last Kanto row")

FieldMoves.bindEngineFlags(nil)
eq(FieldMoves.FEMALE_FLAG, nil, "Gold declares no such flag at all")
eq(FieldMoves.BADGE_FLAG[26].name, "ZEPHYR", "and keeps its own badge ids")

-- ------------------------------------------------- the flag, through World

local function flagWorld(version, gender, order)
  local game = {
    data = {},
    save = {
      version = version,
      player = { name = "CHRIS", id = 1, gender = gender, badges = {} },
      engineFlags = {},
    },
  }
  FieldMoves.bindEngineFlags(order)
  local world = World.new(game)
  world.constants = {}
  return world, game
end

do
  local world, game = flagWorld("crystal", "female", CRYSTAL_ORDER)
  check(world:engineFlag(99), "Kris answers checkflag ENGINE_PLAYER_IS_FEMALE")
  check(not (game.save.engineFlags or {})[99],
    "and it is NOT a second copy in save.engineFlags")
  game.save.player.gender = "male"
  check(not world:engineFlag(99), "Chris answers the same flag false")
  -- the write half exists only so a stray setflag cannot open a second store
  world:setEngineFlag(99, true)
  eq(game.save.player.gender, "female", "setflag writes the gender byte")
  check(not (game.save.engineFlags or {})[99], "still one store")
  world:setEngineFlag(99, false)
  eq(game.save.player.gender, "male", "and clearflag writes it back")
end

do
  local world, game = flagWorld("gold", "male", nil)
  check(not world:engineFlag(99), "Gold's flag 99 is an ordinary flag")
  world:setEngineFlag(99, true)
  check(world:engineFlag(99), "which reads back out of save.engineFlags")
  check((game.save.engineFlags or {})[99] == true, "where Gold keeps it")
  eq(game.save.player.gender, "male", "and the gender byte is untouched")
end

-- ------------------------------------------------- Save.isFemale, the seam

check(Save.isFemale({ player = { gender = "female" } }), "isFemale reads Kris")
check(not Save.isFemale({ player = { gender = "male" } }), "and not Chris")
check(not Save.isFemale({ player = {} }), "a genderless save is Chris")
check(not Save.isFemale(nil), "and so is no save at all")

-- ------------------------------------------------- Surf onto an NPC (CT-10)

local WATER = 0x29 -- pokecrystal constants/collision_constants.asm

local function surfCtx(facingObject)
  return {
    save = { player = { badges = { FOG = true } } },
    mon = { species = "LAPRAS" },
    facing = "down",
    facingColl = WATER,
    playerColl = 0x00,
    playerState = FieldMoves.PLAYER_NORMAL,
    facingObject = facingObject,
  }
end

GameVersion.set("crystal")
check(FieldMoves.surfFromMenu(surfCtx(nil)).ok,
  "Crystal surfs onto open water")
check(not FieldMoves.surfFromMenu(surfCtx({ id = "npc" })).ok,
  "and refuses onto a facing object (CheckFacingObject)")
eq(FieldMoves.surfFromMenu(surfCtx({ id = "npc" })).text,
  FieldMoves.TEXT.CANT_SURF, "with .cannotsurf's own line")

GameVersion.set("gold")
check(FieldMoves.surfFromMenu(surfCtx(nil)).ok, "Gold surfs onto open water")
check(FieldMoves.surfFromMenu(surfCtx({ id = "npc" })).ok,
  "and KEEPS the cart's bug: Surf right on top of the NPC")

GameVersion.set("silver")
check(FieldMoves.surfFromMenu(surfCtx({ id = "npc" })).ok,
  "Silver keeps it too")

-- TrySurfOW is byte-identical in both trees, so the OW path never gained the
-- check (pokecrystal engine/events/overworld.asm:484-514 vs pokegold :469-499).
GameVersion.set("crystal")
do
  local ctx = surfCtx({ id = "npc" })
  ctx.party = { { species = "LAPRAS", moves = { { id = "SURF" } } } }
  check(FieldMoves.trySurfOW(ctx).ok,
    "the A-press path is unchanged by the menu fix, even on Crystal")
end

GameVersion.set(priorVersion)
FieldMoves.bindEngineFlags(nil)
S.finish()

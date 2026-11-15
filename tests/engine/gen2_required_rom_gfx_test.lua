package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local CacheContract = require("src.import.CacheContract")
local World = require("src.world.gen2.World")
local MartMenu = require("src.ui.gen2.MartMenu")
local Breeding = require("src.core.gen2.Breeding")

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function errorOf(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return nil end
  return tostring(err):match("[%w_]+%.lua has no [%w_%. ]+")
end

local MENU_GFX = {
  emotes = {
    grassRustle = "rustle.png", jumpShadow = "shadow.png",
    cutGrass = "cut.png", fishing = "fishing.png",
    fishingFemale = "fishing_female.png",
  },
  healMachine = { sheet = "heal.png", palette = { 1, 2, 3, 4 } },
}

local function menuWorld(gfx)
  return setmetatable({ game = { data = { gen2MenuGfx = gfx } } },
    { __index = World })
end

-- data/sprites/emotes.asm:19-22
GameVersion.set("gold")
do
  local world = menuWorld(copy(MENU_GFX))
  T.check(errorOf(world.loadMenuGfx, world) == nil, "a full menu_gfx.lua loads")
  T.check(world.healMachineImage ~= nil and world.healMachinePalette ~= nil,
    "and carries the heal machine sheet and palette")
  T.check(world.grassRustleImage and world.jumpShadowImage
    and world.cutGrassImage and world.fishingSheet,
    "and every overworld emote")
end

for _, key in ipairs({ "grassRustle", "jumpShadow", "cutGrass", "fishing" }) do
  local gfx = copy(MENU_GFX)
  gfx.emotes[key] = nil
  local world = menuWorld(gfx)
  T.eq(errorOf(world.loadMenuGfx, world), "menu_gfx.lua has no emotes." .. key,
    "menu_gfx.lua without emotes." .. key .. " does not load")
end

-- ../pokecrystal/engine/events/heal_machine_anim.asm:87
for _, case in ipairs({
    { "healMachine", function(gfx) gfx.healMachine = nil end },
    { "healMachine.sheet", function(gfx) gfx.healMachine.sheet = nil end },
    { "healMachine.palette", function(gfx) gfx.healMachine.palette = nil end },
  }) do
  local gfx = copy(MENU_GFX)
  case[2](gfx)
  local world = menuWorld(gfx)
  T.eq(errorOf(world.loadMenuGfx, world), "menu_gfx.lua has no " .. case[1],
    "menu_gfx.lua without " .. case[1] .. " does not load")
end

-- ../pokecrystal/engine/events/fishing_gfx.asm:7-12
do
  local gfx = copy(MENU_GFX)
  gfx.emotes.fishingFemale = nil
  local gold = menuWorld(copy(gfx))
  T.check(errorOf(gold.loadMenuGfx, gold) == nil,
    "Gold has no Kris fishing sheet and needs none")
  GameVersion.set("crystal")
  local crystal = menuWorld(gfx)
  T.eq(errorOf(crystal.loadMenuGfx, crystal),
    "menu_gfx.lua has no emotes.fishingFemale",
    "Crystal without the Kris fishing sheet does not load")
  local full = menuWorld(copy(MENU_GFX))
  full:loadMenuGfx()
  T.eq(full.fishingSheetFemale, "fishing_female.png",
    "Crystal keeps the Kris fishing sheet")
  GameVersion.set("gold")
end

-- engine/tilesets/tileset_anims.asm:167, :197, :231, :259
local TILESETS = {
  waterFrames = "water.png", flowerFrames = "flower.png",
  flowerCgbFrames = { 2, 4 },
}
local function animWorld(defs)
  return setmetatable({ tilesets = defs }, { __index = World })
end
local PROGRAM = { frames = {
  { func = "AnimateWaterTile", tile = 0x14 },
  { func = "AnimateFlowerTile" },
  { func = "AnimateLavaBubbleTile1", tile = 0x5b, sheet = "lava.png", frames = 4 },
} }
do
  local world = animWorld(copy(TILESETS))
  local wanted = world:animLayers({ anim = PROGRAM })
  T.eq(wanted[0x14].sheet, "water.png", "the water tile draws from waterFrames")
  T.eq(wanted[0x03].sheet, "flower.png", "the flower tile from flowerFrames")
  T.eq(wanted[0x5b].sheet, "lava.png", "the lava tile from its own strip")
  T.eq(world:flowerFrameFor(0), 2, "flowerCgbFrames picks cgb_1")
  T.eq(world:flowerFrameFor(2), 4, "and cgb_2")
  T.check(world:animSheets().water ~= nil, "the border bake gets its water strip")
end
for _, key in ipairs({ "waterFrames", "flowerFrames" }) do
  local defs = copy(TILESETS)
  defs[key] = nil
  local world = animWorld(defs)
  T.eq(errorOf(world.animLayers, world, { anim = PROGRAM }),
    "tilesets.lua has no " .. key, "a tileset program without " .. key .. " errors")
  T.eq(errorOf(world.animSheets, world), "tilesets.lua has no " .. key,
    "and so does the border bake")
end
do
  local program = copy(PROGRAM)
  program.frames[3].sheet = nil
  local world = animWorld(copy(TILESETS))
  T.eq(errorOf(world.animLayers, world, { anim = program }),
    "tilesets.lua has no sheet for AnimateLavaBubbleTile1",
    "a lava row without LavaBubbleTileFrames errors")
  local defs = copy(TILESETS)
  defs.flowerCgbFrames = nil
  local bare = animWorld(defs)
  T.eq(errorOf(bare.flowerFrameFor, bare, 0), "tilesets.lua has no flowerCgbFrames",
    "a flower frame without flowerCgbFrames errors")
end

-- ../pokecrystal/engine/items/mart.asm:118-134
T.eq(errorOf(MartMenu.inventory, {}, 0), "marts.lua has no lists",
  "a marts.lua without Marts errors")
T.eq(errorOf(MartMenu.inventory, { lists = {} }, 3), "marts.lua has no list for mart 3",
  "and a mart id with no row errors")
T.eq(errorOf(MartMenu.bargainRows, { lists = {} }), "marts.lua has no bargain",
  "a marts.lua without BargainShopData errors")
T.eq(MartMenu.inventory({ lists = {}, default = { "POKE_BALL", "POTION" } }, 40)[1],
  "POKE_BALL", "an id past NUM_MARTS is DefaultMart off marts.lua")
T.eq(errorOf(MartMenu.inventory, { lists = {} }, 40), "marts.lua has no default",
  "and a marts.lua without DefaultMart errors")

-- data/pokemon/egg_moves.asm
do
  local data = { pokemon = { CHIKORITA = { id = "CHIKORITA" } }, moves = {} }
  T.eq(errorOf(Breeding.canInheritMove, data, "CHIKORITA", "VINE_WHIP", {}),
    "pokemon.lua has no eggMoves for CHIKORITA",
    "a species without EggMovePointers' list errors")
  data.pokemon.CHIKORITA.eggMoves = { "VINE_WHIP" }
  T.check(Breeding.canInheritMove(data, "CHIKORITA", "VINE_WHIP", {}),
    "and with it the egg move is inherited")
end

local function slurp(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function rootFor(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local identities = { "g1r-" .. version, "pokeport-test-caches" }
  local own = os.getenv("POKEPORT_IDENTITY")
  if own and own ~= "" then table.insert(identities, 1, own) end
  local prefix = GameVersion.cachePrefix(version)
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE",
      home .. "/.local/share/love" }) do
    for _, identity in ipairs(identities) do
      local root = base .. "/" .. identity .. "/" .. prefix
      if CacheContract.markerMatches(version,
          slurp(root .. CacheContract.MARKER_PATH)) then
        return root
      end
    end
  end
  return nil
end

local mounted = 0
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local root = rootFor(version)
  if not root then
    print("[skip] no " .. version .. " cache")
  else
    mounted = mounted + 1
    local function load(name)
      return assert(loadfile(root .. "data/generated/" .. name .. ".lua"))()
    end
    local tilesets, gfx, marts = load("tilesets"), load("menu_gfx"), load("marts")
    T.check(tilesets.waterFrames and tilesets.flowerFrames
      and tilesets.flowerCgbFrames, version .. " tilesets.lua carries the water and flower strips")
    local lavaRows, lavaSheets = 0, 0
    for _, def in pairs(tilesets) do
      for _, frame in ipairs(type(def) == "table" and def.anim
          and def.anim.frames or {}) do
        if frame.func == "AnimateLavaBubbleTile1"
            or frame.func == "AnimateLavaBubbleTile2" then
          lavaRows = lavaRows + 1
          if frame.sheet and frame.frames then lavaSheets = lavaSheets + 1 end
        end
      end
    end
    T.check(lavaRows > 0 and lavaSheets == lavaRows,
      version .. " every lava row carries LavaBubbleTileFrames")
    local e = gfx.emotes
    T.check(e.grassRustle and e.jumpShadow and e.cutGrass and e.fishing,
      version .. " menu_gfx.lua carries every overworld emote")
    T.eq(e.fishingFemale ~= nil, version == "crystal",
      version .. " carries the Kris fishing sheet only on Crystal")
    T.check(gfx.healMachine and gfx.healMachine.sheet
      and #gfx.healMachine.palette == 4, version .. " carries the heal machine")
    T.eq(#marts.lists, 34, version .. " marts.lua carries every Marts row")
    T.check(#marts.bargain > 0, version .. " and BargainShopData")
    local pokemon = load("pokemon")
    T.check(type(pokemon.BULBASAUR.eggMoves) == "table"
      and #pokemon.BULBASAUR.eggMoves > 0, version .. " pokemon.lua carries egg moves")
  end
end
if mounted == 0 then print("[skip] no Gen 2 cache for the real-cache checks") end

T.finish("gen2_required_rom_gfx_test")

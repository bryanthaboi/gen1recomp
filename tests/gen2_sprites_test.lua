-- The two halves of the Gen 2 sprite id space: OverworldSprites rows
-- (data/sprites/sprites.asm) and the mon-icon ids past them
-- (data/sprites/sprite_mons.asm, resolved by GetMonSprite in
-- engine/overworld/overworld.asm).
--
-- The second half is what the twenty small dolls, the gym Growlithes, the
-- Rocket base Voltorbs, Lugia and Ho-Oh all stand on, so a sprite table that
-- stops at SPRITE_SILVER_TROPHY means every one of those objects sets its slot
-- and then never spawns.
--
-- ROM-free: `luajit tests/gen2_sprites_test.lua`.  The decomp section SKIPs
-- with no ../pokegold beside the repo, and the cache section SKIPs (or asks
-- for a re-import) with no Gold cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 sprites")
local check, eq = S.check, S.eq

local Json = require("src.link.Json")
local Decorations = require("src.core.gen2.Decorations")
local World = require("src.world.gen2.World")

-- constants/sprite_constants.asm, the handful this file names.  The first
-- block is `const_def` with SPRITE_NONE at 0, so an id is its own 1-based
-- spriteOrder index; SPRITE_POKEMON restarts the count at $80 and SPRITE_VARS
-- at $f0.
local SPRITE_SILVER_TROPHY = 0x5f
local SPRITE_POKEMON, SPRITE_PIKACHU, SPRITE_HO_OH = 0x80, 0x8e, 0xa2
local SPRITE_VARS, SPRITE_DOLL_1 = 0xf0, 0xf1
local NUM_OVERWORLD_SPRITES, NUM_POKEMON_SPRITES = 95, 35

-- DECO_PIKACHU_DOLL, the row the reachability check below puts in the room.
local DECO_PIKACHU_DOLL = 30

-- ---- the decomp -----------------------------------------------------------
-- SpriteMons is `table_width 1`, one species per id from SPRITE_POKEMON up,
-- and it ends on `assert_table_length NUM_POKEMON_SPRITES`.  Pinning the row
-- count and PIKACHU's place in it is what says the extractor followed the
-- table rather than counted rows off the sprite constants.
local pokegold = "../pokegold"
local monsAsm = io.open(pokegold .. "/data/sprites/sprite_mons.asm", "r")
if not monsAsm then
  check(true, "no ../pokegold: SpriteMons is not pinned against the decomp (SKIP)")
else
  local species = {}
  for line in monsAsm:lines() do
    local name = line:match("^%s*db%s+([%w_]+)")
    if name then species[#species + 1] = name end
  end
  monsAsm:close()
  eq(#species, NUM_POKEMON_SPRITES,
    "sprite_mons.asm carries NUM_POKEMON_SPRITES species rows")
  eq(species[1], "UNOWN", "row 0 is UNOWN, i.e. SPRITE_UNOWN is $80")
  eq(species[SPRITE_PIKACHU - SPRITE_POKEMON + 1], "PIKACHU",
    "SPRITE_PIKACHU ($8e) is the PIKACHU row, which is the doll in the room")
  eq(species[#species], "HO_OH", "and the last row is HO_OH, id $a2")
end

-- ---- the manifest ---------------------------------------------------------
-- spriteOrder is generated from both const blocks by tools/make_gold_manifest.py,
-- so it is the one place the ids can go out of line with the ROM tables.
local manifestFile = assert(io.open("tools/rom_manifest_gold.json", "r"))
local manifest = assert(Json.decode(manifestFile:read("*a")))
manifestFile:close()

local consts = manifest.constants
local order = consts.spriteOrder
eq(#order, SPRITE_HO_OH, "spriteOrder runs to SPRITE_HO_OH, the last mon id")
eq(consts.numOverworldSprites, NUM_OVERWORLD_SPRITES,
  "and NUM_OVERWORLD_SPRITES of those rows are OverworldSprites rows")
eq(consts.spritePokemon, SPRITE_POKEMON, "SPRITE_POKEMON is $80")
eq(order[NUM_OVERWORLD_SPRITES], "SPRITE_SILVER_TROPHY",
  "the OverworldSprites half still ends on SPRITE_SILVER_TROPHY")
eq(order[SPRITE_SILVER_TROPHY], "SPRITE_SILVER_TROPHY",
  "and an id is its own index, because the block is const_def 0 past SPRITE_NONE")
eq(order[SPRITE_POKEMON], "SPRITE_UNOWN", "$80 is SPRITE_UNOWN")
eq(order[SPRITE_PIKACHU], "SPRITE_PIKACHU", "$8e is SPRITE_PIKACHU")
eq(order[SPRITE_HO_OH], "SPRITE_HO_OH", "$a2 is SPRITE_HO_OH")
for id = NUM_OVERWORLD_SPRITES + 1, SPRITE_POKEMON - 1 do
  if order[id] ~= "UNUSED" then
    check(false, ("id %d is a hole between the two blocks"):format(id))
  end
end
check(true, "the $60..$7f hole between the blocks is UNUSED rows, not a shift")
-- The list must NOT run on past the mon ids: SPRITE_DAY_CARE_MON_1 ($e0) reads
-- a breedmon species and the SPRITE_VARS block ($f0) is a slot INTO
-- wVariableSprites, so naming either would make World:resolveSprite hand back
-- a slot id as though it were something that could be drawn.
check(order[SPRITE_VARS] == nil,
  "and it stops before SPRITE_VARS, which is a slot id and not a sheet")
check(manifest.symbols.SpriteMons ~= nil,
  "SpriteMons is a required symbol, or the extractor could never read it")

-- ---- the call site --------------------------------------------------------
-- ToggleDecorationsVisibility (PLAYERS_HOUSE_2F's MAPCALLBACK_NEWMAP) writes
-- the doll's sprite byte into wVariableSprites, and World:pooledNpc then asks
-- resolveSprite for a name and the sprites table for a sheet.  Both halves are
-- driven here with the shipped spriteOrder, because a name that resolves to no
-- sheet is exactly as unspawnable as no name at all.
local world = World.new({
  save = { player = { name = "GOLD" }, decorations = {
    leftOrnament = DECO_PIKACHU_DOLL } },
})
world.constants = consts
world.sprites = { SPRITE_PIKACHU = { id = "SPRITE_PIKACHU", frames = 1 } }
world:toggleDecorationsVisibility()

local left = Decorations.OBJECT_SLOTS[2]
eq(left.slot, "leftOrnament", "the left ornament is wVariableSprites slot 1")
eq(world.variableSprites[left.sprite], SPRITE_PIKACHU,
  "the room callback fills that slot with the PIKACHU doll's sprite byte")
eq(world:resolveSprite(SPRITE_DOLL_1), "SPRITE_PIKACHU",
  "so the object's own $f1 resolves through the slot to a mon sprite name")
check(world.sprites[world:resolveSprite(SPRITE_DOLL_1)] ~= nil,
  "and pooledNpc finds a sheet for it, which is what makes the doll spawn")
check(not world.events:get(left.flag),
  "with the object's event flag cleared, so it is built at all")

-- Every doll, console and trophy an ornament slot can hold has to name a row
-- of spriteOrder; the twenty small dolls are the SPRITE_POKEMON ones.
local monDolls = 0
for decoId = 1, 52 do
  local attr = Decorations.attributes(decoId)
  if attr and attr.action == "SET_UP_DOLL" or
      (attr and attr.action == "SET_UP_CONSOLE") then
    local name = order[attr.sprite]
    check(name ~= nil and name ~= "UNUSED",
      ("%s stands on sprite id %d, which spriteOrder names"):format(
        attr.name, attr.sprite))
    if attr.sprite >= SPRITE_POKEMON then monDolls = monDolls + 1 end
  end
end
eq(monDolls, 20, "twenty of the ornaments are mon-icon sprites")

-- ---- the cache ------------------------------------------------------------
-- Same default every other gen2 suite uses, so a run with no GOLD_CACHE set
-- still reads the cache instead of skipping silently.
local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/gold-dev/gold")
local function loadCache(name)
  local chunk = loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local sprites = loadCache("sprites")
if not sprites then
  check(true, "no GOLD_CACHE: the extracted sprite rows are not checked (SKIP)")
elseif not sprites.SPRITE_PIKACHU then
  check(true,
    "cache predates the SpriteMons rows : re-import for the mon dolls (SKIP)")
else
  local rows, monRows = 0, 0
  for id in pairs(sprites) do
    rows = rows + 1
    if order[SPRITE_POKEMON] and id:match("^SPRITE_") then
      local index
      for i = SPRITE_POKEMON, SPRITE_HO_OH do
        if order[i] == id then index = i end
      end
      if index then monRows = monRows + 1 end
    end
  end
  eq(rows, NUM_OVERWORLD_SPRITES + NUM_POKEMON_SPRITES,
    "sprites.lua carries both tables, not just the OverworldSprites one")
  eq(monRows, NUM_POKEMON_SPRITES, "and all 35 of the SpriteMons ids are there")

  local doll = sprites.SPRITE_PIKACHU
  eq(doll.source, "ROM:SpriteMons[14]",
    "SPRITE_PIKACHU came off SpriteMons row 14, not an OverworldSprites row")
  eq(doll.species, "PIKACHU", "and that row's species is PIKACHU")
  eq(doll.icon, "ICON_PIKACHU",
    "which ReadMonMenuIcon turns into PIKACHU's menu icon")
  eq(doll.image, "assets/generated/icons/gen2/pikachu.png",
    "so it draws from the icon sheet extractIcons already writes")
  -- OBJECT_ACTION_BOUNCE swaps FacingStepDown0's tiles $00..$03 for
  -- FacingStepUp0's $04..$07, so both icon frames reach the map (#1748).
  if doll.frames == 1 then
    check(true, "cache predates #1748 : re-import for the mon bounce (SKIP)")
  else
    eq(doll.frames, 2, "two frames: SetFacingBounce swaps the icon's pair")
  end
  check(not doll.walker, "and a doll does not walk")
  eq(doll.paletteId, 0, "_GetSpritePalette answers 0 for every mon sprite")
  eq(doll.palette, "PAL_OW_RED", "which is PAL_OW_RED in the MapObjectPals set")

  -- The OverworldSprites half must be untouched by the new rows: it is read by
  -- index, and one row of drift would repaint every NPC in the game.
  local chris = sprites.SPRITE_CHRIS
  check(chris ~= nil and chris.walker, "SPRITE_CHRIS is still a walker")
  eq(chris.source, "ROM:OverworldSprites[0]", "and still row 0 of that table")
  eq(sprites.SPRITE_SILVER_TROPHY.source,
    ("ROM:OverworldSprites[%d]"):format(NUM_OVERWORLD_SPRITES - 1),
    "and SPRITE_SILVER_TROPHY is still its last row")

  local cacheConsts = loadCache("constants")
  if cacheConsts then
    eq(#(cacheConsts.spriteOrder or {}), SPRITE_HO_OH,
      "the cache's own spriteOrder runs to SPRITE_HO_OH too")
    eq(cacheConsts.spritePokemon, SPRITE_POKEMON,
      "and it carries SPRITE_POKEMON for the extractor to index SpriteMons by")
  end

  -- The other reason this range matters: fifty-odd map objects across
  -- pokegold name a mon sprite directly (the gym Growlithes, the Rocket base
  -- Voltorbs, Lugia, Ho-Oh), and every one of them used to extract as a bare
  -- number that pooledNpc could find no sheet for.
  local maps = loadCache("maps")
  if maps then
    local named, numbered = 0, 0
    for _, def in pairs(maps) do
      if type(def) == "table" then
        for _, obj in ipairs(def.objects or {}) do
          if type(obj.spriteId) == "number"
              and obj.spriteId >= SPRITE_POKEMON
              and obj.spriteId <= SPRITE_HO_OH then
            if type(obj.sprite) == "string" then
              named = named + 1
              check(sprites[obj.sprite] ~= nil,
                ("%s names a sheet"):format(obj.sprite))
            else
              numbered = numbered + 1
            end
          end
        end
      end
    end
    check(named >= 40,
      ("%d map objects stand on a mon sprite and now name one"):format(named))
    eq(numbered, 0, "and none of them is left as a bare id with no sheet")
  end
end

S.finish()

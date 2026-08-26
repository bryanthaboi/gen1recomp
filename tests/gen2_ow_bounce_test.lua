-- SPRITEMOVEDATA_POKEMON ($16), the row every overworld mon object stands on.
--
--   luajit tests/gen2_ow_bounce_test.lua   (ROM-free; the cache section SKIPs
--                                           without a gold cache)
--
-- data/sprites/map_objects.asm:181-187 gives the row SPRITEMOVEFN_BOUNCE and
-- OBJECT_ACTION_BOUNCE.  SetFacingBounce increments OBJECT_STEP_FRAME once a
-- frame, masks it to four bits and reads bit 3: set means FACING_STEP_UP_0,
-- clear falls into SetFacingFreezeBounce and FACING_STEP_DOWN_0
-- (engine/overworld/map_object_action.asm:184-202).  Those are tiles $00..$03
-- and $04..$07 of the mon's menu icon (data/sprites/facings.asm:43-72), i.e.
-- the two 16x16 halves of the 16x32 sheet extractIcons already writes.
--
-- Both halves of #1748 are pinned here: the animation itself, and the sheet
-- being two frames deep so the animation has a second pose to reach.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 ow bounce")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local NPC = require("src.world.gen2.Npc")
local SpriteRenderer = require("src.render.SpriteRenderer")
local World = require("src.world.gen2.World")

-- constants/map_object_constants.asm:135-151
local SPRITEMOVEDATA_STILL = 0x01
local SPRITEMOVEDATA_STANDING_DOWN = 0x06
local SPRITEMOVEDATA_POKEMON = 0x16

-- trueColor short-circuits SpriteRenderer past the OBP bake, so :draw here
-- needs no canvases (the same trick tests/gen2_big_object_test.lua uses).
local MON_SHEET = {
  id = "SPRITE_JIGGLYPUFF", frames = 2, trueColor = true,
  spriteType = "POKEMON_SPRITE", walker = false,
  image = "assets/generated/icons/gen2/jigglypuff.png",
}
local DOLL_SHEET = {
  id = "SPRITE_FAIRY", frames = 6, trueColor = true,
  spriteType = "WALKING_SPRITE", walker = true,
  image = "assets/generated/sprites/fairy.png",
}

local function build(movement, sheet)
  return NPC.new("TEST_MAP",
    { index = 1, movement = movement, x = 4, y = 4 }, sheet or MON_SHEET)
end

-- ---- the movement byte -----------------------------------------------------
eq(NPC.MOVE.POKEMON, SPRITEMOVEDATA_POKEMON,
  "SPRITEMOVEDATA_POKEMON is $16 in map_object_constants.asm")

-- Without the seam every block below it raises rather than reporting, which
-- turns a whole suite of answers into one traceback.
local HAS_BOUNCE = check(type(NPC.bounceFrame) == "function",
  "NPC:bounceFrame is the seam OBJECT_ACTION_BOUNCE draws through")
if not HAS_BOUNCE then
  NPC.bounceFrame = function() return nil end
end

do
  local mon = build(SPRITEMOVEDATA_POKEMON)
  check(mon.bouncing == true, "a $16 object is built bouncing")
  check(mon.fixedFacing == true,
    "and keeps FIXED_FACING, which the $16 row's flags1 byte carries")
  eq(mon.facing, "down", "its `db DOWN ; facing` column is DOWN")
  eq(select(1, NPC.patternFor(SPRITEMOVEDATA_POKEMON)), "stand",
    "MovementFunction_Bouncing parks it on STEP_TYPE_STANDING: no walking")
end

-- ---- eight frames down, eight frames up ------------------------------------
-- `inc a / and %00001111 / ld [hl], a / and %00001000` is a sixteen-frame
-- cycle with an eight-frame dwell on each pose, and the counter is stepped
-- BEFORE the bit is read -- so the spawn frame is pose 0 and so are the seven
-- after it.
do
  local mon = build(SPRITEMOVEDATA_POKEMON)
  eq(mon.bounceStep, 0, "OBJECT_STEP_FRAME starts at zero")
  local seen, wrong = { mon:bounceFrame() }, nil
  for i = 1, 31 do
    mon:update()
    seen[i + 1] = mon:bounceFrame()
  end
  for i = 0, 31 do
    local want = math.floor(i / 8) % 2
    if seen[i + 1] ~= want and not wrong then
      wrong = ("frame %d drew pose %s, wanted %d")
        :format(i, tostring(seen[i + 1]), want)
    end
  end
  check(wrong == nil, "two full cycles run 0,0..0,1,1..1 eight frames apiece"
    .. (wrong and (" -- " .. wrong) or ""))
  eq(seen[1], 0, "the spawn frame is FacingStepDown0, the icon's first half")
  eq(seen[9], 1, "the ninth is FacingStepUp0, its second half")
  eq(seen[17], 0, "and the seventeenth is back to the first")
  eq(mon.bounceStep, 31 % 16, "the counter wrapped at sixteen, not at eight")
end

-- ---- the frozen column -----------------------------------------------------
-- OBJECT_ACTION_BOUNCE's second entry is SetFacingFreezeBounce, which writes
-- FACING_STEP_DOWN_0 and never touches OBJECT_STEP_FRAME.  So a mon held for a
-- conversation pins its FIRST pose and resumes on the phase it left.
do
  local mon = build(SPRITEMOVEDATA_POKEMON)
  for _ = 1, 10 do mon:update() end
  eq(mon:bounceFrame(), 1, "ten frames in, the mon is on the up pose")
  eq(mon.bounceStep, 10, "with OBJECT_STEP_FRAME at 10")

  mon.frozen = true
  local pinned = true
  for _ = 1, 40 do
    mon:update()
    if mon:bounceFrame() ~= 0 then pinned = false end
  end
  check(pinned, "frozen, it holds FacingStepDown0 for the whole conversation")
  eq(mon.bounceStep, 10,
    "and SetFacingFreezeBounce leaves the step counter where it was")

  mon.frozen = false
  mon:update()
  eq(mon.bounceStep, 11, "released, the counter carries on from 10")
  eq(mon:bounceFrame(), 1, "so the bounce resumes on the phase it froze at")
end

-- ---- every other movement byte is still ------------------------------------
-- Only the $16 row carries OBJECT_ACTION_BOUNCE; the Clefairy, Charizard and
-- Pidgeot dolls are SPRITEMOVEDATA_STANDING_DOWN and take
-- OBJECT_ACTION_STAND (data/sprites/map_objects.asm:53-59).
do
  for _, movement in ipairs({ SPRITEMOVEDATA_STILL, SPRITEMOVEDATA_STANDING_DOWN,
      NPC.MOVE.WANDER, NPC.MOVE.SPINRANDOM_SLOW, NPC.MOVE.BIGDOLL }) do
    local npc = build(movement, DOLL_SHEET)
    check(not npc.bouncing,
      ("movement $%02x does not bounce"):format(movement))
    check(npc:bounceFrame() == nil,
      ("and $%02x asks for no frame override"):format(movement))
  end

  -- The other half of it: a mon SHEET on a still row stays still.  Gold has no
  -- such object, but a mod or a variablesprite slot can make one.
  local still = build(SPRITEMOVEDATA_STILL, MON_SHEET)
  for _ = 1, 40 do still:update() end
  check(still:bounceFrame() == nil,
    "a POKEMON_SPRITE sheet on a STILL row never bounces either")
end

-- ---- the frame reaches the renderer ----------------------------------------
-- NPC:draw is where the pose is spent: SpriteRenderer:draw's trailing
-- frameOverride argument.  A bounce the draw call drops looks exactly like no
-- bounce at all.
do
  local mon = build(SPRITEMOVEDATA_POKEMON)
  local doll = build(SPRITEMOVEDATA_STANDING_DOWN, DOLL_SHEET)
  local seen = {}
  local function recorder(who)
    return { draw = function(_, _, _, _, _, _, _, _, _, _, frameOverride)
      seen[who] = { override = frameOverride, count = (seen[who]
        and seen[who].count or 0) + 1 }
    end }
  end
  mon.sprite, doll.sprite = recorder("mon"), recorder("doll")

  mon:draw(0, 0, 1)
  doll:draw(0, 0, 1)
  eq(seen.mon.override, 0, "the mon's first draw overrides to frame 0")
  check(seen.doll.override == nil, "and the doll's overrides to nothing")

  for _ = 1, 8 do mon:update() end
  mon:draw(0, 0, 1)
  eq(seen.mon.override, 1, "eight frames later it overrides to frame 1")
end

-- ---- a one-frame sheet has nowhere to bounce to ----------------------------
-- SpriteRenderer builds one quad per frame and :draw only honours an override
-- it has a quad for, so the extractor half of #1748 is load bearing: with
-- `frames = 1` the up pose is simply not on the sheet.
do
  local one = SpriteRenderer.new({
    id = "ONE", frames = 1, trueColor = true, image = MON_SHEET.image }, "one")
  eq(one.frameCount, 1, "a frames = 1 def builds one quad")
  check(one.frames[1] == nil, "so there is no second frame to override to")

  local two = SpriteRenderer.new(MON_SHEET, "two")
  eq(two.frameCount, 2, "a frames = 2 def builds both")
  check(two.frames[1] ~= nil, "and frame 1 is a real quad")
  eq(two:getFrameGeometry(1).y, two.frameHeight,
    "which is the lower 16x16 of the 16x32 icon sheet")
end

-- ---- World:load repairs a stale cache --------------------------------------
-- The extractor fix only reaches a player who re-imports, and there is no
-- non-file lever that would force one.  World:load back-fills the SpriteMons
-- rows on the way past, keyed on `source` so a mod's own POKEMON_SPRITE row is
-- left exactly as the mod wrote it.
do
  local sprites = {
    SPRITE_JIGGLYPUFF = { id = "SPRITE_JIGGLYPUFF", frames = 1,
      source = "ROM:SpriteMons[20]", spriteType = "POKEMON_SPRITE",
      image = "assets/generated/icons/gen2/jigglypuff.png" },
    SPRITE_CHRIS = { id = "SPRITE_CHRIS", frames = 12, walker = true,
      source = "ROM:OverworldSprites[0]",
      image = "assets/generated/sprites/chris.png" },
    SPRITE_MOD_MON = { id = "SPRITE_MOD_MON", frames = 1,
      source = "MOD:pocket-monsters", spriteType = "POKEMON_SPRITE",
      image = "mods/pocket-monsters/mon.png" },
  }
  local world = World.new({ data = {
    gen2Maps = { TEST_MAP = { width = 1, height = 1 } },
    gen2Tilesets = {},
    gen2Sprites = sprites,
  } })
  -- load goes on to tilesets, palettes and map art this stub has none of; the
  -- back-fill sits in its first dozen lines, so let the rest fall over.
  pcall(world.load, world)
  eq(sprites.SPRITE_JIGGLYPUFF.frames, 2,
    "a pre-#1748 SpriteMons row is back-filled to two frames on load")
  eq(sprites.SPRITE_CHRIS.frames, 12,
    "an OverworldSprites row is not touched")
  eq(sprites.SPRITE_MOD_MON.frames, 1,
    "and a mod's own POKEMON_SPRITE row keeps the frame count it declared")
end

-- ---- the day-care pair -----------------------------------------------------
-- GetMonSprite's .BreedMon1 / .BreedMon2 arms have no sprites.lua row to
-- back-fill (engine/overworld/overworld.asm:279-305), so the def World builds
-- by hand has to carry the second frame itself.
do
  local world = World.new({ data = { gen2Icons = {
    species = { PIKACHU = "ICON_PIKACHU" },
    icons = { ICON_PIKACHU = {
      image = "assets/generated/icons/gen2/pikachu.png" } },
  } } })
  local def = world:breedmonSpriteDef("PIKACHU")
  check(def ~= nil, "a deposited PIKACHU builds a day-care sprite def")
  eq(def and def.frames, 2, "two frames, like every other SpriteMons row")
  eq(def and def.spriteType, "POKEMON_SPRITE", "and it is a mon sheet")
end

-- ---- the cache -------------------------------------------------------------
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
  check(true, "no GOLD_CACHE: the extracted rows are not checked (SKIP)")
else
  local monRows, thin = 0, {}
  for id, def in pairs(sprites) do
    if type(def) == "table" and type(def.source) == "string"
       and def.source:find("^ROM:SpriteMons") then
      monRows = monRows + 1
      if (def.frames or 1) < 2 then thin[#thin + 1] = id end
    end
  end
  check(monRows > 0, "the cache carries SpriteMons rows at all")
  if #thin > 0 then
    check(true, ("cache predates #1748 (%d thin rows, first %s) : World:load"
      .. " back-fills them, a re-import writes them (SKIP)")
      :format(#thin, thin[1]))
  else
    check(true, ("all %d SpriteMons rows are two frames deep"):format(monRows))
  end

  -- The objects the reporter was looking at: every $16 object on every map has
  -- to name a sheet that the bounce can actually flip.
  local maps = loadCache("maps")
  if not maps then
    check(true, "no maps.lua: the $16 objects are not checked (SKIP)")
  else
    local bouncers, slots, unresolved, oneFrame = 0, 0, {}, {}
    for mapId, def in pairs(maps) do
      if type(def) == "table" then
        for _, obj in ipairs(def.objects or {}) do
          if obj.movement == SPRITEMOVEDATA_POKEMON then
            bouncers = bouncers + 1
            if type(obj.sprite) == "number" then
              -- The day-care pair: GetMonSprite's .BreedMon arms resolve those
              -- two bytes to the deposited species' icon at spawn time, so
              -- there is no sprites.lua row for them to name.
              slots = slots + 1
            elseif not sprites[obj.sprite] then
              unresolved[#unresolved + 1] = mapId
            elseif (sprites[obj.sprite].frames or 1) < 2 then
              oneFrame[#oneFrame + 1] = mapId
            end
          end
        end
      end
    end
    check(bouncers > 0, ("the cache carries %d SPRITEMOVEDATA_POKEMON objects")
      :format(bouncers))
    check(#unresolved == 0, "every named one of them names a sheet the cache has"
      .. (unresolved[1] and (" (%s does not)"):format(unresolved[1]) or ""))
    check(slots == 2, ("and %d of them are the two day-care slots"):format(slots))
    if #oneFrame > 0 then
      check(true, ("%d of them sit on a pre-#1748 row : World:load back-fills"
        .. " them (SKIP)"):format(#oneFrame))
    else
      check(true, "and every one of those sheets is two frames deep")
    end
  end
end

S.finish()

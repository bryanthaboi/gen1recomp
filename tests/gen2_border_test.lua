-- The border block a map is surrounded by: home/map.asm LoadBlockData /
-- LoadMetatiles.  `luajit tests/gen2_border_test.lua`; also dofile'd by
-- tests/run_tests.lua.  Fixture-driven, with a final section that reads a real
-- Gold cache and SKIPs when there is none.
--
-- Three things fail differently here:
--
--   the SUBSTITUTION  block id 0 is not tileset block 0, it is the map
--                     header's border block.  Reading it literally paints
--                     whatever block 0 of the tileset happens to be.
--   the COVERAGE      the map canvas is exactly the map's own blocks, so a
--                     map smaller than the 20x18 viewport left the rest of
--                     the screen on the clear colour.  The tiled quad has to
--                     cover the view whatever the camera fraction is.
--   the CACHE KEY     the bake carries the map's palettes, so it is keyed by
--                     daytime / COLOR mode / flicker like the map canvas is,
--                     and World:dropMapImages' "<mapId>|" prefix sweep has to
--                     still reach it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 border fill")
local check, eq = S.check, S.eq

local BorderFill = require("src.world.gen2.BorderFill")
local Map = require("src.world.gen2.Map")

-- ---------------------------------------------------------------------------
-- LoadMetatiles' `ld a,[de] / and a / jr nz / ld a,[wMapBorderBlock]`
-- ---------------------------------------------------------------------------

eq(BorderFill.blockFor(0, 42), 42, "block id 0 reads as the border block")
eq(BorderFill.blockFor(nil, 42), 42, "a hole in the block list does too")
eq(BorderFill.blockFor(3, 42), 3, "any other id is itself")
eq(BorderFill.blockFor(0, 0), 0, "border block 0 stays block 0")
eq(BorderFill.blockFor(0, nil), 0, "no border block in the header is 0")

-- Out of bounds already came back as the border block, and now the inside
-- agrees with it: a 1x1 map of block 0 is the border block everywhere.
local hole = Map.new({
  id = "HOLE", width = 1, height = 1, borderBlock = 7, blocks = { 0 },
}, { collision = {} })
eq(hole:blockId(-1, 0), 7, "off the left edge is the border block")
eq(BorderFill.blockFor(hole:blockId(0, 0), hole.borderBlock), 7,
  "and so is the map's own block 0")

-- ---------------------------------------------------------------------------
-- Cache key
-- ---------------------------------------------------------------------------

local mapKey = "GOLDENROD_DEPT_STORE_ELEVATOR|DAY|gbc|1"
local borderKey = BorderFill.cacheKey(mapKey)
check(borderKey ~= mapKey, "the border bake does not share the map's entry")
check(borderKey:sub(1, #mapKey) == mapKey,
  "it keeps the daytime / COLOR / flicker key it was built under")
-- World:dropMapImages sweeps every key beginning "<mapId>|", which is what a
-- changeblock or a CUT leans on.  The border bake has to go with it.
local prefix = "GOLDENROD_DEPT_STORE_ELEVATOR|"
check(borderKey:sub(1, #prefix) == prefix,
  "dropMapImages' prefix sweep reaches the border bake")

-- ---------------------------------------------------------------------------
-- Coverage: the wrap-tiled quad over the view
-- ---------------------------------------------------------------------------

eq(BorderFill.SIZE, 32, "one block is 32 pixels")

-- 160x144 at scale 4 is the plain fit; the camera fractions are the ones a
-- walk animation actually produces (a step is 8 pixels over 8 frames at 1x).
for _, cam in ipairs({ { 0, 0 }, { 3, 5 }, { 12.5, 0.25 }, { -6.75, -3.5 } }) do
  for _, s in ipairs({ 1, 2, 4, 7 }) do
    local w, h = 640, 576
    local ix, iy, vw, vh, sx, sy =
      BorderFill.viewport(cam[1], cam[2], w, h, s)
    check(ix == math.floor(cam[1]) and iy == math.floor(cam[2]),
      "the source origin is whole texels")
    check(sx <= 0 and sy <= 0, "the quad starts at or before the screen edge")
    check(sx > -s * BorderFill.SIZE, "and no more than a block before it")
    check(sx + vw * s >= w, "the quad covers the width")
    check(sy + vh * s >= h, "the quad covers the height")
  end
end

-- A degenerate scale must not divide by zero or hand back a quad of nothing.
local _, _, vw0, vh0 = BorderFill.viewport(0, 0, 160, 144, 0)
check(vw0 > 0 and vh0 > 0, "scale 0 falls back to 1 rather than collapsing")

-- ---------------------------------------------------------------------------
-- VOID FILL (#1418): FADE / WATER / TREES / BLACK
-- ---------------------------------------------------------------------------

eq(BorderFill.voidFill, "fade", "the live fill defaults to FADE")
eq(BorderFill.voidFillLabel(), "FADE ", "and prints with a trailing space")

local johto = { id = "CHERRYGROVE_CITY", tileset = "TILESET_JOHTO",
  borderBlock = 0x35 }
local route = { id = "ROUTE_30", tileset = "TILESET_JOHTO", borderBlock = 0x05 }
local kanto = { id = "PALLET_TOWN", tileset = "TILESET_KANTO",
  borderBlock = 0x0f }
local cave = { id = "UNION_CAVE_1F", tileset = "TILESET_CAVE", borderBlock = 0x09 }
local house = { id = "PLAYERS_HOUSE_1F", tileset = "TILESET_PLAYERS_HOUSE",
  borderBlock = 0x00 }

eq(BorderFill.fillBlock(johto), 0x35, "FADE keeps Cherrygrove's water")
eq(BorderFill.fillBlock(route), 0x05, "and Route 30's trees")
eq(BorderFill.fillKey(johto), "fade|CHERRYGROVE_CITY",
  "FADE dissolves per map")
eq(BorderFill.fillKey(route) ~= BorderFill.fillKey(johto), true,
  "so the two maps are different fills")

BorderFill.setVoidFill("water")
eq(BorderFill.fillBlock(johto), 0x35, "WATER uses Cherrygrove's water block")
eq(BorderFill.fillBlock(route), 0x35, "on Route 30 too")
eq(BorderFill.fillBlock(kanto), 0x43, "and Cinnabar's water on Kanto")
eq(BorderFill.fillBlock(cave), 0x09, "but a cave keeps its own border")
eq(BorderFill.fillBlock(house), 0x00, "and so does a house")
eq(BorderFill.fillKey(johto), BorderFill.fillKey(route),
  "two Johto maps share one WATER fill")
eq(BorderFill.fillKey(johto) ~= BorderFill.fillKey(kanto), true,
  "Kanto water is a different sheet")

BorderFill.setVoidFill("trees")
eq(BorderFill.fillBlock(johto), 0x05, "TREES uses New Bark's tree wall")
eq(BorderFill.fillBlock(kanto), 0x0f, "and Pallet's on Kanto")
eq(BorderFill.fillBlock(cave), 0x09, "caves still keep their own")

BorderFill.setVoidFill("black")
eq(BorderFill.fillBlock(johto), false, "BLACK skips the tiled bake")
eq(BorderFill.fillBlock(house), false, "indoors too")
eq(BorderFill.fillKey(johto), "black", "and is one sheet everywhere")

BorderFill.setVoidFill("nope")
eq(BorderFill.voidFill, "fade", "an unknown mode falls back to FADE")
BorderFill.setVoidFill("fade")
eq(BorderFill.cycle(1), "water", "cycle steps FADE to WATER")
eq(BorderFill.cycle(1), "trees", "then TREES")
eq(BorderFill.cycle(1), "black", "then BLACK")
eq(BorderFill.cycle(1), "fade", "and wraps to FADE")
eq(BorderFill.cycle(-1), "black", "left wraps the other way")
BorderFill.applyOptions({ voidFill = "trees" })
eq(BorderFill.voidFill, "trees", "applyOptions pushes the saved mode")
BorderFill.applyOptions({})
eq(BorderFill.voidFill, "fade", "and a missing key restores FADE")

-- ---------------------------------------------------------------------------
-- The real cache: the map the bug was reported on
-- ---------------------------------------------------------------------------

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsPath = cache .. "/data/generated/maps.lua"
local mf = io.open(mapsPath, "r")
if not mf then
  check(true, "gold cache absent : fixture checks only (SKIP cache facts)")
  S.finish()
  return
end
mf:close()

local maps = assert(loadfile(mapsPath))()
local tilesets = assert(loadfile(cache .. "/data/generated/tilesets.lua"))()

-- 20x18 tiles of viewport is 5x4.5 blocks, so anything under 5 wide or 5 tall
-- shows border on at least one axis at every camera position.
local elevator = maps.GOLDENROD_DEPT_STORE_ELEVATOR
check(elevator ~= nil, "the elevator is in the cache")
eq(elevator.width, 2, "GOLDENROD_DEPT_STORE_ELEVATOR is 2 blocks wide")
eq(elevator.height, 2, "and 2 blocks tall")
check(elevator.width < 5 and elevator.height < 5,
  "which is smaller than the 20x18 viewport in both axes")

local small = 0
for _, def in pairs(maps) do
  if (def.width or 99) < 5 or (def.height or 99) < 5 then small = small + 1 end
end
check(small > 100, "and it is not alone: " .. small .. " maps need the fill")

-- Every map's border block has to resolve to a real block in its own tileset,
-- or the fill bakes nothing and the map goes back to a black surround.
local missing, checked = {}, 0
for id, def in pairs(maps) do
  local ts = def.tileset and tilesets[def.tileset]
  if ts and ts.blocks then
    checked = checked + 1
    local block = ts.blocks[BorderFill.blockFor(0, def.borderBlock) + 1]
    if type(block) ~= "table" or #block ~= 16 then
      missing[#missing + 1] = id
    end
  end
end
check(checked > 100, "checked " .. checked .. " maps against their tilesets")
eq(#missing, 0, "every border block is a 4x4 metatile in its own tileset")

S.finish()

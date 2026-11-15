-- Gen 2 GBC palette resolution (src/world/gen2/Palettes.lua).
--
-- ROM-free: the fixture below is the shape data/generated/palettes.lua has,
-- with values traceable back to pokegold so a wrong answer names the ASM it
-- disagrees with rather than just failing.

package.path = "./?.lua;" .. package.path

local Palettes = require("src.world.gen2.Palettes")
-- GbcPalette only reaches for love inside its shader accessors, so the pure
-- rBGP half below is testable exactly the way Palettes is.
local GbcPalette = require("src.render.GbcPalette")
-- Chrome.throughPalette is pure too (it is the fold printThrough draws
-- with, split out so this does not need a real shader); Font is required
-- transitively but never called down here.
love = love or {}
love.graphics = love.graphics or {}
local Chrome = require("src.ui.gen2.Chrome")

local failures = 0
local checks = 0

local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

local function checkColor(name, got, r, g, b)
  checks = checks + 1
  if not got then
    failures = failures + 1
    print(("FAIL %s: no color"):format(name))
    return
  end
  if got[1] ~= r or got[2] ~= g or got[3] ~= b then
    failures = failures + 1
    print(("FAIL %s: got %s,%s,%s want %d,%d,%d"):format(
      name, tostring(got[1]), tostring(got[2]), tostring(got[3]), r, g, b))
  end
end

-- engine/rtc/rtc.asm TimesOfDay: 0400-0959 morn, 1000-1759 day, else nite.
check("hour 0", Palettes.clockDaytime(0), "NITE")
check("hour 3", Palettes.clockDaytime(3), "NITE")
check("hour 4", Palettes.clockDaytime(4), "MORN")
check("hour 9", Palettes.clockDaytime(9), "MORN")
check("hour 10", Palettes.clockDaytime(10), "DAY")
check("hour 17", Palettes.clockDaytime(17), "DAY")
check("hour 18", Palettes.clockDaytime(18), "NITE")
check("hour 23", Palettes.clockDaytime(23), "NITE")

-- Two BG pool entries plus one shared roof pool entry, laid out the way
-- gfx/tilesets/bg_tiles.pal is: slot index 7 (1-based 7) is PAL_BG_ROOF.
local function pool(a, b, c, d)
  return { { a, a, a }, { b, b, b }, { c, c, c }, { d, d, d } }
end

local data = {
  roofSlot = 7,
  bg = {
    pool(10, 11, 12, 13),   -- 1: morn gray
    pool(20, 21, 22, 23),   -- 2
    pool(30, 31, 32, 33),   -- 3
    pool(40, 41, 42, 43),   -- 4
    pool(50, 51, 52, 53),   -- 5
    pool(60, 61, 62, 63),   -- 6
    pool(70, 71, 72, 73),   -- 7: roof
    pool(80, 81, 82, 83),   -- 8: text
    pool(90, 91, 92, 93),   -- 9: day gray
  },
  environments = {
    TOWN = {
      MORN = { 1, 2, 3, 4, 5, 6, 7, 8 },
      DAY = { 9, 2, 3, 4, 5, 6, 7, 8 },
      NITE = { 1, 2, 3, 4, 5, 6, 7, 8 },
      DARK = { 1, 2, 3, 4, 5, 6, 7, 8 },
    },
    INDOOR = {
      MORN = { 2, 2, 2, 2, 2, 2, 2, 8 },
      DAY = { 2, 2, 2, 2, 2, 2, 2, 8 },
      NITE = { 3, 3, 3, 3, 3, 3, 3, 8 },
      DARK = { 4, 4, 4, 4, 4, 4, 4, 8 },
    },
  },
  objects = {
    MORN = { pool(1, 2, 3, 4) },
    DAY = { pool(5, 6, 7, 8) },
    NITE = { pool(9, 10, 11, 12) },
    DARK = { pool(13, 14, 15, 16) },
  },
  roofs = {
    [24] = {
      mornDay = { { 100, 101, 102 }, { 110, 111, 112 } },
      nite = { { 120, 121, 122 }, { 130, 131, 132 } },
    },
  },
  pokemon = {
    CYNDAQUIL = {
      normal = { { 255, 222, 0 }, { 255, 58, 41 } },
      shiny = { { 1, 2, 3 }, { 4, 5, 6 } },
    },
  },
  trainers = { PLAYER = { { 206, 148, 99 }, { 90, 80, 70 } } },
}

local newBark = {
  id = "NEW_BARK_TOWN", group = 24, environment = "TOWN",
  palette = "PALETTE_AUTO",
}
local elmsLab = {
  id = "ELMS_LAB", group = 24, environment = "INDOOR",
  palette = "PALETTE_DAY",
}
local darkCave = {
  id = "DARK_CAVE", group = 3, environment = "CAVE",
  palette = "PALETTE_DARK",
}

-- PALETTE_AUTO follows the clock; a pinned map does not.
check("town at 2am", Palettes.daytimeFor(newBark, 2), "NITE")
check("town at noon", Palettes.daytimeFor(newBark, 12), "DAY")
check("lab pinned DAY at 2am", Palettes.daytimeFor(elmsLab, 2), "DAY")
-- PALETTE_DARK is blackout until FLASH (ReplaceTimeOfDayPals.UsedFlash).
check("dark cave", Palettes.daytimeFor(darkCave, 12), "DARK")
check("dark cave with flash", Palettes.daytimeFor(darkCave, 12, true), "NITE")

-- Slot 0 differs between morn and day, which is the whole point of the table.
local morn = Palettes.bgSet(data, newBark, "MORN")
local day = Palettes.bgSet(data, newBark, "DAY")
checkColor("town morn slot1 color0", morn[1][1], 10, 10, 10)
checkColor("town day slot1 color0", day[1][1], 90, 90, 90)

-- RoofPals overwrites PAL_BG_ROOF colors 1 and 2 only; 0 and 3 stay pooled.
checkColor("roof color0 pooled", morn[7][1], 70, 70, 70)
checkColor("roof color1 override", morn[7][2], 100, 101, 102)
checkColor("roof color2 override", morn[7][3], 110, 111, 112)
checkColor("roof color3 pooled", morn[7][4], 73, 73, 73)
local nite = Palettes.bgSet(data, newBark, "NITE")
checkColor("roof nite color1", nite[7][2], 120, 121, 122)

-- LoadMapPals only reaches the roof override for TOWN/ROUTE; indoors keeps
-- the pool entry even though the map group has roof colors.
local indoor = Palettes.bgSet(data, elmsLab, "DAY")
checkColor("indoor roof slot untouched", indoor[7][2], 21, 21, 21)

-- The pool is shared, so a mutating bug shows up as morn picking up day's
-- roof; re-resolving must give the original color back.
local mornAgain = Palettes.bgSet(data, newBark, "MORN")
checkColor("bgSet does not mutate the pool", mornAgain[7][1], 70, 70, 70)

-- An unmodeled environment falls through to the outdoor table rather than nil.
local cave = Palettes.bgSet(data, darkCave, "DARK")
check("cave falls back to outdoor", cave ~= nil, true)

-- LoadSpecialMapPalette (engine/tilesets/tileset_palettes.asm:1)
local house = {
  id = "CHERRYGROVE_HOUSE", group = 24, environment = "INDOOR",
  palette = "PALETTE_AUTO", tileset = "TILESET_HOUSE",
}
local icePath = {
  id = "ICE_PATH_1F", group = 3, environment = "CAVE",
  palette = "PALETTE_NITE", tileset = "TILESET_ICE_PATH",
}
local hallOfFame = {
  id = "HALL_OF_FAME", group = 26, environment = "INDOOR",
  palette = "PALETTE_DAY", tileset = "TILESET_ICE_PATH",
}
local crystalData = {}
for key, value in pairs(data) do crystalData[key] = value end
crystalData.specialTilesets = {
  TILESET_HOUSE = {
    pool(200, 201, 202, 203), pool(210, 211, 212, 213),
    pool(220, 221, 222, 223), pool(230, 231, 232, 233),
    pool(240, 241, 242, 243), pool(250, 251, 252, 253),
    { { 247, 230, 214 }, { 255, 156, 197 }, { 132, 107, 25 }, { 58, 58, 58 } },
    pool(190, 191, 192, 193),
  },
  TILESET_ICE_PATH = {
    pool(1, 1, 1, 1), pool(2, 2, 2, 2), pool(3, 3, 3, 3), pool(4, 4, 4, 4),
    pool(5, 5, 5, 5), pool(6, 6, 6, 6), pool(7, 7, 7, 7), pool(8, 8, 8, 8),
  },
}

local houseSet = Palettes.bgSet(crystalData, house, "DAY")
checkColor("house glass color0", houseSet[7][1], 247, 230, 214)
checkColor("house glass color1", houseSet[7][2], 255, 156, 197)
checkColor("house glass color2", houseSet[7][3], 132, 107, 25)
checkColor("house gray slot", houseSet[1][1], 200, 200, 200)
local houseNite = Palettes.bgSet(crystalData, house, "NITE")
checkColor("house glass at night", houseNite[7][2], 255, 156, 197)

-- the Hall of Fame keeps the pool (tileset_palettes.asm:26).
local icePathSet = Palettes.bgSet(crystalData, icePath, "NITE")
checkColor("ice path takes its own block", icePathSet[1][1], 1, 1, 1)
local fameSet = Palettes.bgSet(crystalData, hallOfFame, "DAY")
checkColor("hall of fame keeps the pool", fameSet[1][1], 20, 20, 20)

local plain = { id = "X", group = 24, environment = "INDOOR",
  palette = "PALETTE_DAY", tileset = "TILESET_POKECENTER" }
checkColor("an ordinary tileset is untouched",
  Palettes.bgSet(crystalData, plain, "DAY")[1][1], 20, 20, 20)
checkColor("and a cache without the table is unchanged",
  Palettes.bgSet(data, house, "DAY")[1][1], 20, 20, 20)
check("specialSet is nil without a table", Palettes.specialSet(data, house), nil)

-- Sprite palettes: paletteId is 0-based PAL_OW_*, so id 0 is entry 1.
local spr = Palettes.spritePalette(data, "DAY", { paletteId = 0 })
checkColor("sprite day pal", spr[1], 5, 5, 5)
local byName = Palettes.spritePalette(data, "NITE", { palette = "PAL_OW_RED" })
checkColor("sprite by name", byName[1], 9, 9, 9)

-- PAL_OW_EMOTE (constants/sprite_data_constants.asm:23) is id 5, the "silver"
-- row of gfx/overworld/npc_sprites.pal, and it is byte-identical in all four
-- daytime blocks (lines 7, 17, 27, 37): RGB 31,31,31 / 31,31,31 / 13,13,13 /
-- 00,00,00, which the extractor's scale5 turns into 255 / 255 / 107 / 0.
-- SpawnEmote.EmoteObject (engine/overworld/map_objects.asm:2029) puts the "!"
-- bubble on it, so the bubble's interior is WHITE at every hour -- the port
-- used to blit the raw 2bpp sheet and left it at DMG shade 1 (#505 again).
local emoteRow = { { 255, 255, 255 }, { 255, 255, 255 }, { 107, 107, 107 },
  { 0, 0, 0 } }
local emoteData = { objects = {} }
for _, when in ipairs({ "MORN", "DAY", "NITE", "DARK" }) do
  local set = {}
  for id = 1, 8 do set[id] = pool(id, id, id, id) end
  set[6] = emoteRow
  emoteData.objects[when] = set
  local got = Palettes.spritePalette(emoteData, when, { paletteId = 5 })
  checkColor("emote interior is white at " .. when, got and got[2], 255, 255, 255)
  checkColor("emote mid shade at " .. when, got and got[3], 107, 107, 107)
  checkColor("emote outline at " .. when, got and got[4], 0, 0, 0)
end

-- Pic palettes bracket the two shipped colors with white and black.
local mon = Palettes.monColors(data, "CYNDAQUIL")
checkColor("mon color0 white", mon[1], 255, 255, 255)
checkColor("mon color1", mon[2], 255, 222, 0)
checkColor("mon color2", mon[3], 255, 58, 41)
checkColor("mon color3 black", mon[4], 0, 0, 0)
local shiny = Palettes.monColors(data, "CYNDAQUIL", true)
checkColor("shiny color1", shiny[2], 1, 2, 3)
check("unknown species has no palette",
  Palettes.monColors(data, "MISSINGNO"), nil)

local trainer = Palettes.trainerColors(data, "PLAYER")
checkColor("player trainer color1", trainer[2], 206, 148, 99)

-- A cache with no palettes.lua must degrade, not crash.
check("nil data bgSet", Palettes.bgSet(nil, newBark, "DAY"), nil)
check("nil data objectSet", Palettes.objectSet(nil, "DAY"), nil)
check("nil data monColors", Palettes.monColors(nil, "CYNDAQUIL"), nil)

--------------------------------------------------------------------------
-- rBGP (src/render/GbcPalette.lua)
--------------------------------------------------------------------------
--
-- The register is four 2-bit shade indices with colour 0 in the LOW bits, and
-- CopyPals (home/palettes.asm) uses it to REORDER a palette's four entries
-- rather than to dim them.  Everything below is that reorder, with no love and
-- no shader: a byte and a palette in, the permuted palette out.

-- A palette whose entries are trivially distinguishable, so a wrong shade
-- shows up as a wrong number rather than as a near miss.
local ramp = { { 0, 0, 0 }, { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 } }

local function checkShades(name, byte, s0, s1, s2, s3)
  local got = GbcPalette.bgpShades(byte)
  check(name .. " colour 0", got[1], s0)
  check(name .. " colour 1", got[2], s1)
  check(name .. " colour 2", got[3], s2)
  check(name .. " colour 3", got[4], s3)
end

-- `dc 3, 2, 1, 0` packs colour 3 first, so the identity is %11100100.
check("BGP_IDENTITY is $e4", GbcPalette.BGP_IDENTITY, 0xe4)
checkShades("$e4", 0xe4, 0, 1, 2, 3)
checkShades("$ff", 0xff, 3, 3, 3, 3)
checkShades("$00", 0x00, 0, 0, 0, 0)
-- LoadTitleScreenPals: colours 1 and 2 swap, which is why the title sky (BG
-- colour 2) is baked at shade 1.
checkShades("$d8 title", 0xd8, 0, 2, 1, 3)

-- The identity returns the palette itself: the common case allocates nothing.
check("identity is a pass-through", GbcPalette.remap(ramp, 0xe4), ramp)
check("no byte is a pass-through", GbcPalette.remap(ramp, nil), ramp)
check("nil palette stays nil", GbcPalette.remap(nil, 0xff), nil)

-- StartTrainerBattle_Flash's .pals endpoints: `dc 3, 3, 3, 3` is every colour
-- showing shade 3, `dc 0, 0, 0, 0` every colour showing shade 0.  On a CGB
-- those are the palette's OWN entries 3 and 0, which is exactly the fact the
-- old brightness veil could not represent -- it drew them as flat black and
-- flat white for every palette alike.
local black = GbcPalette.remap(ramp, 0xff)
checkColor("$ff colour 0", black[1], 3, 3, 3)
checkColor("$ff colour 3", black[4], 3, 3, 3)
local white = GbcPalette.remap(ramp, 0x00)
checkColor("$00 colour 0", white[1], 0, 0, 0)
checkColor("$00 colour 3", white[4], 0, 0, 0)

-- `dc 3, 3, 2, 1` = $f9, the table's first row: one step darker along the
-- palette's own ramp, with colour 3 already at the bottom.
local darker = GbcPalette.remap(ramp, 0xf9)
checkColor("$f9 colour 0", darker[1], 1, 1, 1)
checkColor("$f9 colour 1", darker[2], 2, 2, 2)
checkColor("$f9 colour 2", darker[3], 3, 3, 3)
checkColor("$f9 colour 3", darker[4], 3, 3, 3)

-- `dc 2, 1, 0, 0` = $90, the light half of the same table.
local lighter = GbcPalette.remap(ramp, 0x90)
checkColor("$90 colour 0", lighter[1], 0, 0, 0)
checkColor("$90 colour 1", lighter[2], 0, 0, 0)
checkColor("$90 colour 2", lighter[3], 1, 1, 1)
checkColor("$90 colour 3", lighter[4], 2, 2, 2)

-- The title byte on a real palette: colours 1 and 2 trade places and the ends
-- stay put.
local swapped = GbcPalette.remap(mon, 0xd8)
checkColor("$d8 keeps white", swapped[1], 255, 255, 255)
checkColor("$d8 swaps 1 for 2", swapped[2], 255, 58, 41)
checkColor("$d8 swaps 2 for 1", swapped[3], 255, 222, 0)
checkColor("$d8 keeps black", swapped[4], 0, 0, 0)

-- The remap is a pure function of its inputs: the source palette is never
-- written through, which matters because bgSet hands out shared pool copies.
checkColor("remap does not mutate", mon[2], 255, 222, 0)

-- The active byte GbcPalette.use folds in.  setBgp stores the identity as nil,
-- so a screen that resets to $e4 leaves nothing standing for the next one.
check("setBgp returns the previous byte", GbcPalette.setBgp(0xff), nil)
check("setBgp stores the byte", GbcPalette.bgp, 0xff)
check("setBgp($e4) clears", GbcPalette.setBgp(0xe4), 0xff)
check("identity is stored as nil", GbcPalette.bgp, nil)

-- GbcPalette.color is the direct-read seam, so it has to take the byte too:
-- otherwise a fill behind text keeps its cart colour while the tiles over it
-- move.
GbcPalette.setBgp(0xff)
checkColor("direct read takes the byte", GbcPalette.color(mon, 1), 0, 0, 0)
GbcPalette.setBgp(nil)
checkColor("direct read without a byte", GbcPalette.color(mon, 1), 255, 255, 255)

-- Chrome.printThrough used to build its draw palette from GbcPalette.resolve
-- alone and never fold the active rBGP byte in, latent until a second screen
-- left a byte standing when chrome text drew.  Chrome.throughPalette is the
-- fold printThrough actually draws with; here with no shader involved.
GbcPalette.setBgp(0xff)
local through = Chrome.throughPalette(ramp)
checkColor("printThrough colour0 takes the byte", through[1], 3, 3, 3)
checkColor("printThrough colour3 takes the byte", through[4], 3, 3, 3)
-- engine/pokedex/pokedex.asm:2452-2461
GbcPalette.setBgp(0xd8)
local inverted = Chrome.throughPalette(mon, true)
checkColor("invert then fold keeps colour0", inverted[1], 0, 0, 0)
checkColor("invert then fold swaps 1 for 2", inverted[2], 255, 222, 0)
checkColor("invert then fold swaps 2 for 1", inverted[3], 255, 58, 41)
checkColor("invert then fold keeps colour3", inverted[4], 255, 255, 255)
GbcPalette.setBgp(nil)
-- With no byte standing, the fold is a no-op and the old un-folded behaviour
-- still holds -- the regression only shows once a second screen leaves a
-- byte set behind it.
local identity = Chrome.throughPalette(ramp)
checkColor("no byte is unfolded", identity[1], 0, 0, 0)
checkColor("no byte is unfolded end", identity[4], 3, 3, 3)

--------------------------------------------------------------------------
-- The backwards pass, for frames that are already drawn
--------------------------------------------------------------------------
--
-- A baked canvas has no shade index left in it, so the shader matches a pixel
-- to the palette entry that produced it.  remapTable is where that stops being
-- exact: two palettes can hold the same colour at different entries, and the
-- finished frame cannot say which one this pixel was.

-- One palette: the four entries are the only colours the texture can hold, so
-- there is nothing to be ambiguous about.
local src, dst, count, ambiguous = GbcPalette.remapTable({ ramp }, 0xff)
check("one palette is four colours", count, 4)
check("one palette is unambiguous", ambiguous, 0)
checkColor("src keeps entry 0", src[1], 0, 0, 0)
checkColor("dst sends entry 0 to entry 3", dst[1], 3, 3, 3)
check("the array is padded to REMAP_MAX", #src, GbcPalette.REMAP_MAX)
check("both arrays are padded alike", #dst, GbcPalette.REMAP_MAX)

-- Two palettes that share their ends -- white at entry 0 and black at entry 3,
-- which nearly every BG palette does -- dedupe to one source colour each, and
-- under a byte that leaves those two entries where they are they agree about
-- the answer.  $fc (`dc 3, 3, 3, 0`) is one of those.
local other = { { 0, 0, 0 }, { 9, 9, 9 }, { 8, 8, 8 }, { 3, 3, 3 } }
local _, _, count2, ambiguous2 = GbcPalette.remapTable({ ramp, other }, 0xfc)
check("shared ends dedupe", count2, 6)
check("shared ends agree under $fc", ambiguous2, 0)

-- The honest limit, and it is not a corner case: under $f9 entry 0 moves to
-- entry 1, and two palettes that share a white at entry 0 have DIFFERENT
-- colours at entry 1.  A finished frame cannot say which palette drew this
-- white pixel, so one answer is picked and the disagreement is counted.
local _, dst2, _, ambiguous2b = GbcPalette.remapTable({ ramp, other }, 0xf9)
check("a shared colour with two answers is ambiguous", ambiguous2b, 1)
-- First writer wins, and BG palettes are walked in slot order.
checkColor("the first palette's answer stands", dst2[1], 1, 1, 1)

-- The same thing one step over: a colour that is entry 1 of one palette and
-- entry 2 of another.  Sharing a colour is not itself ambiguity; disagreeing
-- about where the byte sends it is.
local clash = { { 5, 5, 5 }, { 7, 7, 7 }, { 1, 1, 1 }, { 3, 3, 3 } }
local _, dst3, count3, ambiguous3 = GbcPalette.remapTable({ ramp, clash }, 0xf9)
check("a colour at two entries dedupes", count3, 6)
check("a colour at two entries is ambiguous", ambiguous3, 1)
checkColor("the first entry's answer stands", dst3[2], 2, 2, 2)

-- OBJ palettes map to themselves: DmgToCgbBGPals never touches them, so their
-- colours are in the table only to keep a sprite from being matched onto a BG
-- entry and swept along with the flash.
local objOnly = { { 40, 40, 40 }, { 41, 41, 41 }, { 42, 42, 42 }, { 43, 43, 43 } }
local src4, dst4, count4 = GbcPalette.remapTable({ ramp }, 0xff, { objOnly })
check("obj colours are added", count4, 8)
checkColor("obj src", src4[5], 40, 40, 40)
checkColor("obj dst is itself", dst4[5], 40, 40, 40)

-- Nothing to match means nothing to draw through: the caller falls back.
local _, _, count5 = GbcPalette.remapTable(nil, 0xff)
check("no palettes is no table", count5, 0)

-- DMG mode collapses every palette to the four hardware shades before the
-- register sees them, which is what the hardware itself does -- and it makes
-- the backwards pass trivially exact, since there is only one palette left.
GbcPalette.setMode("dmg")
local dmg = GbcPalette.remap(GbcPalette.resolve(mon), 0xff)
checkColor("dmg $ff is hardware black", dmg[1], 0, 0, 0)
local _, _, count6, ambiguous6 = GbcPalette.remapTable({ ramp, clash }, 0xf9)
check("dmg dedupes to four shades", count6, 4)
check("dmg is unambiguous", ambiguous6, 0)
GbcPalette.setMode("gbc")

print(("gen2 palettes: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end

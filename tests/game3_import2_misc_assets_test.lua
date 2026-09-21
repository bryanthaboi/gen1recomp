#!/usr/bin/env luajit
-- src/script_menu.c:1161, src/region_map.c:790, src/learn_move.c:403,
-- src/battle_records.c:563, src/trainer_card.c:265, :1454, :1560

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local CacheContract = require("src.import.CacheContract")
local Versions = require("src.import.gba.versions")
local MuseumExtract = require("src.import.gba.museum_extract")
local MoveRelearnerExtract = require("src.import.gba.move_relearner_extract")
local TrainerTowerExtract = require("src.import.gba.trainer_tower_extract")
local TrainerCardExtract = require("src.import.gba.trainer_card_extract")
local RegionMapExtract = require("src.import.gba.region_map_extract")
local EggExtract = require("src.import.gba.egg_extract")

print("[test] 1. the ROM offsets follow pret's declaration order")
-- src/script_menu.c:647 aerodactyl tiles, palette, then kabutops tiles, palette
eq(Versions.MUSEUM_AERODACTYL_GFX, 0x3E0780, "MUSEUM_AERODACTYL_GFX is sMuseumAerodactylSprTiles")
eq(Versions.MUSEUM_AERODACTYL_GFX + 64 * 64 / 2, Versions.MUSEUM_AERODACTYL_PAL,
  "the aerodactyl palette follows its 2048-byte 64x64 sheet")
eq(Versions.MUSEUM_AERODACTYL_PAL + 32, Versions.MUSEUM_KABUTOPS_GFX,
  "the kabutops sheet follows the aerodactyl palette bank")
eq(Versions.MUSEUM_KABUTOPS_GFX + 64 * 64 / 2, Versions.MUSEUM_KABUTOPS_PAL,
  "the kabutops palette follows its sheet")
eq(Versions.MUSEUM_FOSSIL_SIZE, 64, "the fossil sprite is SPRITE_SIZE(64x64)")
-- src/learn_move.c:403, pokefirered.map:34302
eq(Versions.MOVE_RELEARNER_PAL, 0xE97DDC, "MOVE_RELEARNER_PAL is gMoveRelearner_Pal")
eq(Versions.MOVE_RELEARNER_PAL + 32, Versions.MOVE_RELEARNER_GFX,
  "gMoveRelearner_Gfx follows the one loaded palette bank")
eq(Versions.MOVE_RELEARNER_TILEMAP, 0xE97EC4, "MOVE_RELEARNER_TILEMAP is gMoveRelearner_Tilemap")
-- src/battle_records.c:37 sTiles, :38 sPalette, :39 sTilemap
eq(Versions.BATTLE_RECORDS_GFX + 0xC0, Versions.BATTLE_RECORDS_PAL,
  "sPalette follows sTiles' 0xC0 bytes")
eq(Versions.BATTLE_RECORDS_PAL + 32, Versions.BATTLE_RECORDS_TILEMAP,
  "sTilemap follows the one palette bank")
-- src/trainer_card.c:174 sKantoTrainerCardBadges_Pal, not the Hoenn bank one slot earlier
eq(Versions.TRAINER_CARD_BADGES_PAL, 0x3CD2E0, "TRAINER_CARD_BADGES_PAL is the Kanto bank")
eq(Versions.TRAINER_CARD_BADGES_PAL + 32, Versions.TRAINER_CARD_STAR_PAL,
  "sTrainerCardStar_Pal follows sKantoTrainerCardBadges_Pal")
eq(Versions.TRAINER_CARD_STAR_PAL + 32, Versions.TRAINER_CARD_STICKER_PAL1,
  "sTrainerCardStickerPal1 follows sTrainerCardStar_Pal")
for i, off in ipairs({ Versions.TRAINER_CARD_STICKER_PAL2, Versions.TRAINER_CARD_STICKER_PAL3,
  Versions.TRAINER_CARD_STICKER_PAL4 }) do
  eq(Versions.TRAINER_CARD_STICKER_PAL1 + 32 * i, off,
    "sTrainerCardStickerPal" .. (i + 1) .. " is one bank on")
end
for i, off in ipairs({ Versions.TRAINER_CARD_BRONZE_PAL, Versions.TRAINER_CARD_SILVER_PAL,
  Versions.TRAINER_CARD_GOLD_PAL }) do
  eq(Versions.TRAINER_CARD_GREEN_PAL + 0xC0 * i, off,
    "the " .. (i + 1) .. "-star palette is 0xC0 past the green one")
end
eq(Versions.TRAINER_CARD_STAR_TILE, 143, "the star is card tile 143")
-- src/daycare.c:137 sEggPalette, then the two raw 4bpp sheets
eq(Versions.EGG_PALETTE, 0x25F842, "EGG_PALETTE is sEggPalette")
eq(Versions.EGG_PALETTE + 32, Versions.EGG_HATCH_GFX, "sEggHatchTiles follows the one egg bank")
eq(Versions.EGG_HATCH_GFX + 2048, Versions.EGG_SHARD_GFX,
  "sEggShardTiles follows the four 32x32 hatch frames")
eq(EggExtract.SPECIES_EGG, 412, "the EGG is species 412, one past the last species")

print("[test] 2. the cache contract requires every new key")
local required = CacheContract.requiredFiles("firered")
local have = {}
for _, path in ipairs(required) do have[path] = true end
local WANT = {
  "data/generated/gba/museum/manifest.lua",
  "data/generated/gba/museum/kabutops.rgba",
  "data/generated/gba/museum/aerodactyl.rgba",
  "data/generated/gba/region_map/dungeon_icon_visited.rgba",
  "data/generated/gba/region_map/dungeon_icon_visited.png",
  "data/generated/gba/move_relearner/manifest.lua",
  "data/generated/gba/move_relearner/bg.rgba",
  "data/generated/gba/pokemon/egg/hatch.rgba",
  "data/generated/gba/pokemon/egg/shard.rgba",
  "data/generated/gba/pokemon/front/412.rgba",
  "data/generated/gba/trainer_tower/manifest.lua",
  "data/generated/gba/trainer_tower/records_bg.rgba",
  "data/generated/gba/trainer_card/front_0.rgba",
  "data/generated/gba/trainer_card/back_0.rgba",
  "data/generated/gba/trainer_card/back_4_female.rgba",
  "data/generated/gba/trainer_card/screen_0.rgba",
  "data/generated/gba/trainer_card/star.rgba",
  "data/generated/gba/trainer_card/stickers.rgba",
  "data/generated/gba/teachy_tv/static.rgba",
  "data/generated/gba/teachy_tv/bg3.rgba",
}
for _, path in ipairs(WANT) do
  check(have[path] == true, "the firered contract requires " .. path)
end
for _, path in ipairs(WANT) do
  local fs = {
    prefix = "",
    exists = function(candidate) return candidate ~= path end,
  }
  local complete, missing = CacheContract.allRequiredFilesExist("firered", fs)
  check(complete == false and missing == path,
    "a cache without " .. path .. " is incomplete (" .. tostring(missing) .. ")")
end

print("[test] 3. ready() refuses a half-written group, so an old cache repairs")
local written = {}
local stub = {
  write = function(_, rel, bytes) written[rel] = bytes end,
  read = function(_, rel) return written[rel] end,
  exists = function(_, rel) return written[rel] ~= nil end,
}
check(MuseumExtract.ready(stub, "x") == false, "museum ready() is false with nothing written")
written["x/museum/kabutops.rgba"] = "stub"
written["x/museum/manifest.lua"] = "stub"
check(MuseumExtract.ready(stub, "x") == false, "museum ready() is false without aerodactyl")
written["x/museum/aerodactyl.rgba"] = "stub"
check(MuseumExtract.ready(stub, "x") == true, "museum ready() accepts both fossils")

check(MoveRelearnerExtract.ready(stub, "x") == false, "relearner ready() is false with no bg")
written["x/move_relearner/bg.rgba"] = "stub"
check(MoveRelearnerExtract.ready(stub, "x") == false, "relearner ready() wants its manifest too")
written["x/move_relearner/manifest.lua"] = "stub"
check(MoveRelearnerExtract.ready(stub, "x") == true, "relearner ready() accepts the pair")

written["x/trainer_tower.lua"] = "stub"
check(TrainerTowerExtract.ready(stub, "x") == false,
  "tower ready() is false with the floor table but no records background")
written["x/trainer_tower/records_bg.rgba"] = "stub"
written["x/trainer_tower/manifest.lua"] = "stub"
check(TrainerTowerExtract.ready(stub, "x") == true, "tower ready() accepts table plus records art")

local cardCache = {}
local cardStub = {
  read = function(_, rel) return cardCache[rel] end,
}
cardCache["x/trainer_card/bg.rgba"] = string.rep("z", 240 * 160 * 4)
check(TrainerCardExtract.ready(cardStub, "x") == false,
  "card ready() is false with only the legacy bg composite")
cardCache["x/trainer_card/back_0.rgba"] = string.rep("z", 240 * 160 * 4)
cardCache["x/trainer_card/star.rgba"] = string.rep("z", 8 * 8 * 4)
check(TrainerCardExtract.ready(cardStub, "x") == false, "card ready() still wants the stickers")
cardCache["x/trainer_card/stickers.rgba"] = string.rep("z", 64 * 64 * 4)
check(TrainerCardExtract.ready(cardStub, "x") == true, "card ready() accepts the full set")

check(EggExtract.ready(stub, "x") == false, "egg ready() is false with no hatch sheet")
written["x/pokemon/egg/hatch.rgba"] = "stub"
written["x/pokemon/egg/shard.rgba"] = "stub"
written["x/pokemon/egg/manifest.lua"] = "stub"
check(EggExtract.ready(stub, "x") == false, "egg ready() also wants the SPECIES_EGG front pic")
written["x/pokemon/front/412.rgba"] = "stub"
check(EggExtract.ready(stub, "x") == true, "egg ready() accepts the whole group")

local regionFiles = {}
for _, name in ipairs(RegionMapExtract.FILES) do regionFiles[name] = true end
check(regionFiles["dungeon_icon_visited.png"] == true,
  "region_map ready() lists the visited dungeon marker")

print("[test] 4. a built cache carries the baked art")
local Cache = require("tests.game3_cache")
local root = Cache.root("museum/manifest.lua")
if not root then
  print("[skip] museum, marker, relearner, records and trainer card art: "
    .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function loadTable(rel)
  local src = readFile(rel)
  if not src then return nil end
  local chunk = (loadstring or load)(src)
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

local function pixel(blob, w, x, y)
  local o = (y * w + x) * 4
  return blob:byte(o + 1), blob:byte(o + 2), blob:byte(o + 3), blob:byte(o + 4)
end

local function distinctColors(blob)
  local seen, n = {}, 0
  for i = 1, #blob, 4 do
    local key = blob:sub(i, i + 3)
    if not seen[key] then
      seen[key] = true
      n = n + 1
    end
  end
  return n
end

local function opaquePixels(blob)
  local n = 0
  for i = 4, #blob, 4 do
    if blob:byte(i) == 255 then n = n + 1 end
  end
  return n
end

local SHEETS = {
  { "museum/kabutops.rgba", 64, 64 },
  { "museum/aerodactyl.rgba", 64, 64 },
  { "region_map/dungeon_icon.rgba", 8, 8 },
  { "region_map/dungeon_icon_visited.rgba", 8, 8 },
  { "move_relearner/bg.rgba", 240, 160 },
  { "pokemon/egg/hatch.rgba", 32, 128 },
  { "pokemon/egg/shard.rgba", 32, 8 },
  { "pokemon/front/412.rgba", 64, 64 },
  { "trainer_tower/records_bg.rgba", 240, 160 },
  { "trainer_card/front_0.rgba", 240, 160 },
  { "trainer_card/front_4_female.rgba", 240, 160 },
  { "trainer_card/back_0.rgba", 240, 160 },
  { "trainer_card/back_4.rgba", 240, 160 },
  { "trainer_card/screen_0.rgba", 240, 160 },
  { "trainer_card/star.rgba", 8, 8 },
  { "trainer_card/stickers.rgba", 64, 64 },
}
local blobs = {}
for _, sheet in ipairs(SHEETS) do
  local rel, w, h = sheet[1], sheet[2], sheet[3]
  local blob = readFile(rel)
  blobs[rel] = blob
  eq(blob and #blob or nil, w * h * 4, rel .. " is " .. w .. "x" .. h)
end

print("[test] 5. the museum fossil pictures are the cart's sprites")
-- src/script_menu.c:1173 CreateSprite(&sMuseumFossilSprTemplate), OAM colour 0 transparent
check(distinctColors(blobs["museum/kabutops.rgba"]) > 4, "the KABUTOPS fossil is painted art")
check(distinctColors(blobs["museum/aerodactyl.rgba"]) > 4, "the AERODACTYL fossil is painted art")
check(blobs["museum/kabutops.rgba"] ~= blobs["museum/aerodactyl.rgba"],
  "the two fossils are different pictures")
local _, _, _, kCorner = pixel(blobs["museum/kabutops.rgba"], 64, 0, 0)
eq(kCorner, 0, "the fossil sheet corner is transparent, as OAM index 0 is")
local kOpaque = opaquePixels(blobs["museum/kabutops.rgba"])
check(kOpaque > 500 and kOpaque < 64 * 64,
  "the KABUTOPS skeleton covers part of the 64x64 frame (" .. kOpaque .. " px)")
local museumMan = loadTable("museum/manifest.lua")
check(type(museumMan) == "table", "museum/manifest.lua loads")
if museumMan then
  eq(museumMan.width, 64, "the manifest carries the 64x64 size")
  eq(museumMan.species.kabutops, 141, "the manifest names SPECIES_KABUTOPS")
  eq(museumMan.species.aerodactyl, 142, "the manifest names SPECIES_AERODACTYL")
end

print("[test] 6. the second dungeon marker frame")
-- src/region_map.c:790 sAnim_DungeonIconVisited is ANIMCMD_FRAME(1), :795 not-visited is frame 0
check(blobs["region_map/dungeon_icon.rgba"] ~= blobs["region_map/dungeon_icon_visited.rgba"],
  "frame 1 is different art from frame 0")
local blobOpaque = opaquePixels(blobs["region_map/dungeon_icon.rgba"])
local ringOpaque = opaquePixels(blobs["region_map/dungeon_icon_visited.rgba"])
check(blobOpaque > 0 and ringOpaque > 0, "both marker frames paint pixels")
check(ringOpaque > blobOpaque,
  string.format("the visited ring covers more of the 8x8 cell than the unvisited blob (%d > %d)",
    ringOpaque, blobOpaque))
local visitedPng = readFile("region_map/dungeon_icon_visited.png")
check(type(visitedPng) == "string" and visitedPng:sub(1, 8) == "\137PNG\r\n\026\n",
  "dungeon_icon_visited.png is a PNG, which is what the Town Map loads")

print("[test] 7. the move relearner and battle records backgrounds")
-- src/learn_move.c:403, BG1 covers 19x15 tiles and leaves the rest on the backdrop
check(distinctColors(blobs["move_relearner/bg.rgba"]) > 4, "the relearner background is painted art")
local pr, pg, pb = pixel(blobs["move_relearner/bg.rgba"], 240, 8, 8)
check(pr > 100 and pg > 150 and pb > 150,
  string.format("the relearner panel is the cart's pale green (%d,%d,%d)", pr, pg, pb))
local br, bg2, bb = pixel(blobs["move_relearner/bg.rgba"], 240, 239, 159)
check(br == 0 and bg2 == 0 and bb == 0,
  "outside the 19x15 tile panel the relearner background is the backdrop colour")
local relearnerMan = loadTable("move_relearner/manifest.lua")
check(relearnerMan ~= nil and relearnerMan.width == 240 and relearnerMan.height == 160,
  "move_relearner/manifest.lua is a 240x160 sheet")
check(distinctColors(blobs["trainer_tower/records_bg.rgba"]) > 4,
  "the battle records board is painted art")
local towerMan = loadTable("trainer_tower/manifest.lua")
check(towerMan ~= nil and towerMan.recordsBg ~= nil and towerMan.recordsBg.width == 240,
  "trainer_tower/manifest.lua carries recordsBg 240x160")

print("[test] 8. the five trainer card star palettes, the star and the stickers")
-- src/trainer_card.c:1484 LoadPalette(sKantoTrainerCardPals[stars], BG_PLTT_ID(0), 3 banks)
local legacy = readFile("trainer_card/bg.rgba")
check(legacy == blobs["trainer_card/front_0.rgba"],
  "front_0 is the blue 0-star card the old bg.rgba already was")
check(readFile("trainer_card/bg_female.rgba") == readFile("trainer_card/front_0_female.rgba"),
  "front_0_female matches the old bg_female.rgba")
local seen = {}
for stars = 0, 4 do
  local blob = readFile(string.format("trainer_card/front_%d.rgba", stars))
  eq(blob and #blob or nil, 240 * 160 * 4, "front_" .. stars .. " is 240x160")
  check(seen[blob] == nil, "the " .. stars .. "-star front is its own palette")
  seen[blob] = stars
end
check(blobs["trainer_card/back_0.rgba"] ~= blobs["trainer_card/front_0.rgba"],
  "the back of the card is a different tilemap from the front")
check(blobs["trainer_card/screen_0.rgba"] ~= blobs["trainer_card/front_0.rgba"],
  "the flip screen is the bg layer alone")
-- src/trainer_card.c:1494 the female override only repaints BG bank 1
check(blobs["trainer_card/front_4_female.rgba"] ~= readFile("trainer_card/front_4.rgba"),
  "the female card differs from the male one")
-- src/trainer_card.c:1560 FillBgTilemapBufferRect(3, 143, ..., palette 4)
local starOpaque = opaquePixels(blobs["trainer_card/star.rgba"])
check(starOpaque > 8 and starOpaque < 64,
  "the star tile paints a star on transparency (" .. starOpaque .. " px)")
-- src/trainer_card.c:1450 sticker slot i is the 2x2 group at tile 4i, palettes 11..14
local stickers = blobs["trainer_card/stickers.rgba"]
local rows = {}
for p = 0, 3 do
  rows[p] = stickers:sub(p * 16 * 64 * 4 + 1, (p + 1) * 16 * 64 * 4)
end
for p = 1, 3 do
  check(rows[p] ~= rows[0], "sticker row " .. p .. " is its own palette bank")
end
local slot0 = 0
for y = 0, 15 do
  for x = 0, 15 do
    local _, _, _, a = pixel(stickers, 64, x, y)
    if a == 255 then slot0 = slot0 + 1 end
  end
end
check(slot0 > 32, "sticker slot 0 paints its 16x16 cell (" .. slot0 .. " px)")
local cardMan = loadTable("trainer_card/manifest.lua")
check(cardMan ~= nil and cardMan.starCount == 5 and cardMan.stickerSlots == 4
  and cardMan.stickerPalettes == 4,
  "trainer_card/manifest.lua carries the star and sticker metrics")

print("[test] 9. the EGG front pic, the hatch frames and the shell shards")
-- src/daycare.c:158 the four hatch anims are frames 0, 16, 32 and 48 of one sheet
local hatch = blobs["pokemon/egg/hatch.rgba"]
local hatchFrames = {}
for f = 0, 3 do hatchFrames[f] = hatch:sub(f * 32 * 32 * 4 + 1, (f + 1) * 32 * 32 * 4) end
for f = 1, 3 do
  check(hatchFrames[f] ~= hatchFrames[f - 1],
    "hatch frame " .. f .. " cracks further than frame " .. (f - 1))
end
local cracked = 0
for i = 1, #hatchFrames[0], 4 do
  if hatchFrames[0]:sub(i, i + 3) ~= hatchFrames[3]:sub(i, i + 3) then cracked = cracked + 1 end
end
check(cracked > 20,
  string.format("the last hatch frame repaints the shell with cracks (%d px differ)", cracked))
-- src/daycare.c:243 the four shard anims are single 8x8 tiles, one after the other
local shard = blobs["pokemon/egg/shard.rgba"]
local shardCells = {}
for f = 0, 3 do
  local cell, rows = 0, {}
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = pixel(shard, 32, f * 8 + x, y)
      rows[#rows + 1] = string.char(r or 0, g or 0, b or 0, a or 0)
      if a == 255 then cell = cell + 1 end
    end
  end
  check(cell > 0 and cell < 64, "shell shard " .. f .. " paints part of its tile (" .. cell .. " px)")
  shardCells[f] = table.concat(rows)
end
for f = 1, 3 do
  check(shardCells[f] ~= shardCells[f - 1], "shell shard " .. f .. " is its own piece")
end
local Pokemon = require("src.core.game3.pokemon")
eq(Pokemon.SPECIES_EGG, EggExtract.SPECIES_EGG,
  "the engine and the extractor agree on the EGG species id")
local eggPic = blobs["pokemon/front/412.rgba"]
check(distinctColors(eggPic) > 4, "the EGG front pic is painted art")
local _, _, _, eggCorner = pixel(eggPic, 64, 0, 0)
eq(eggCorner, 0, "the EGG pic corner is transparent, as pic index 0 is")
local eggMan = loadTable("pokemon/egg/manifest.lua")
check(eggMan ~= nil and eggMan.hatch ~= nil and eggMan.hatch.frames == 4
  and eggMan.hatch.sheetHeight == 128 and eggMan.shard.sheetWidth == 32,
  "pokemon/egg/manifest.lua carries both sheet layouts")

finish()

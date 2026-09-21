#!/usr/bin/env luajit
-- src/fame_checker.c:119, src/graphics.c:1117, src/mystery_gift_show_card.c:150,
-- src/trainer_tower_sets.c:8956, src/data/pokemon/tutor_learnsets.h:22

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
local FameCheckerExtract = require("src.import.gba.fame_checker_extract")
local TeachyTvExtract = require("src.import.gba.teachy_tv_extract")
local MysteryGiftExtract = require("src.import.gba.mystery_gift_extract")
local TrainerTowerExtract = require("src.import.gba.trainer_tower_extract")
local TutorExtract = require("src.import.gba.tutor_extract")
local AltLayouts = require("src.import.gba.alt_layouts")

local SHEETS = {
  { "fame_checker/bg.rgba", 240, 160 },
  { "fame_checker/0.rgba", 64, 64 },
  { "fame_checker/1.rgba", 64, 64 },
  { "fame_checker/13.rgba", 64, 64 },
  { "fame_checker/14.rgba", 64, 64 },
  { "fame_checker/cursor.rgba", 32, 32 },
  { "fame_checker/question_mark.rgba", 16, 32 },
  { "teachy_tv/screen.rgba", 240, 160 },
  { "teachy_tv/title.rgba", 240, 160 },
  { "teachy_tv/end.rgba", 240, 160 },
  { "teachy_tv/static.rgba", 32, 8 },
  { "teachy_tv/bg3.rgba", 256, 256 },
  { "mystery_gift/card_bg0.rgba", 240, 160 },
  { "mystery_gift/card_bg3.rgba", 240, 160 },
  { "mystery_gift/card_bg7.rgba", 240, 160 },
  { "mystery_gift/news_bg0.rgba", 240, 160 },
  { "mystery_gift/news_bg7.rgba", 240, 160 },
}

print("[test] 1. the ROM offsets are the symbols pret links")
eq(Versions.FAME_BG_GFX, 0xE9F260, "FAME_BG_GFX is gFameCheckerBgTiles")
eq(Versions.FAME_BG3_TILEMAP, 0xEA0700, "FAME_BG3_TILEMAP is gFameCheckerBg3Tilemap")
eq(Versions.FAME_OAK_GFX, 0x45ED80, "FAME_OAK_GFX is sOakSpriteGfx")
eq(Versions.FAME_FLAVOR_TEXT_PTRS, 0x45F6BC, "FAME_FLAVOR_TEXT_PTRS is sFameCheckerFlavorTextPointers")
eq(Versions.TEACHY_TV_GFX, 0xE86240, "TEACHY_TV_GFX is gTeachyTv_Gfx")
eq(Versions.TEACHY_TV_TITLE_TILEMAP, 0xE86D6C, "TEACHY_TV_TITLE_TILEMAP is gTeachyTvTitle_Tilemap")
-- src/teachy_tv.c:869
eq(Versions.TEACHY_TV_END_TILES, 0x479590, "TEACHY_TV_END_TILES is sBg1EndGraphic")
eq(Versions.WONDER_CARD_GRAPHICS, 0x467FB8, "WONDER_CARD_GRAPHICS is sCardGraphics")
eq(Versions.WONDER_NEWS_GRAPHICS, 0x468720, "WONDER_NEWS_GRAPHICS is sNewsGraphics")
eq(Versions.TRAINER_TOWER_FLOORS, 0x4827B4, "TRAINER_TOWER_FLOORS is gTrainerTowerFloors")
eq(Versions.TT_SINGLES_INFO, 0x479ED8, "TT_SINGLES_INFO is sSingleBattleTrainerInfo")
eq(Versions.TUTOR_LEARNSETS, 0x459B7E, "TUTOR_LEARNSETS is sTutorLearnsets")
eq(Versions.TUTOR_MOVES + Versions.TUTOR_MOVE_COUNT * 2, Versions.TUTOR_LEARNSETS,
  "sTutorMoves is 15 u16 and sTutorLearnsets follows it")

print("[test] 2. the cache contract requires every new key")
local required = CacheContract.requiredFiles("firered")
local have = {}
for _, path in ipairs(required) do have[path] = true end
local WANT = {
  "data/generated/gba/fame_checker/manifest.lua",
  "data/generated/gba/fame_checker/bg.rgba",
  "data/generated/gba/fame_checker/0.rgba",
  "data/generated/gba/fame_checker/14.rgba",
  "data/generated/gba/fame_checker/silhouette.pal",
  "data/generated/gba/fame_checker/pack.lua",
  "data/generated/gba/teachy_tv/screen.rgba",
  "data/generated/gba/teachy_tv/title.rgba",
  "data/generated/gba/teachy_tv/end.rgba",
  "data/generated/gba/mystery_gift/card_bg0.rgba",
  "data/generated/gba/mystery_gift/news_bg7.rgba",
  "data/generated/gba/trainer_tower.lua",
  "data/generated/gba/pokemon/tutor.lua",
  "data/generated/gba/native/layouts/alt_366.mid",
  "data/generated/gba/native/layouts/alt_381.mid",
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

-- src/trainer_tower.c:554 SetCurrentMapLayout(sFloorLayouts[floorIdx][challengeType])
local altIds = {}
for _, row in ipairs(AltLayouts.TOWER_ROWS) do altIds[row.id] = row end
for id = 366, 381 do
  local row = altIds[id]
  check(row ~= nil and row.width == 18 and row.height == 17,
    "alt layout " .. id .. " is a baked 18x17 Trainer Tower floor")
end

print("[test] 3. ready() refuses a half-written group")
local written = {}
local stub = {
  write = function(_, rel, bytes) written[rel] = bytes end,
  read = function(_, rel) return written[rel] end,
  exists = function(_, rel) return written[rel] ~= nil end,
}
check(FameCheckerExtract.ready(stub, "x") == false, "fame ready() is false with nothing written")
check(TeachyTvExtract.ready(stub, "x") == false, "teachy ready() is false with nothing written")
check(MysteryGiftExtract.ready(stub, "x") == false, "gift ready() is false with nothing written")
check(TrainerTowerExtract.ready(stub, "x") == false, "tower ready() is false with nothing written")
check(TutorExtract.ready(stub, "x") == false, "tutor ready() is false with nothing written")
for _, rel in ipairs({ "screen.rgba", "title.rgba", "manifest.lua" }) do
  written["x/teachy_tv/" .. rel] = "stub"
end
check(TeachyTvExtract.ready(stub, "x") == false, "teachy ready() is false without the end plate")
written["x/teachy_tv/end.rgba"] = "stub"
check(TeachyTvExtract.ready(stub, "x") == false, "teachy ready() also wants the snow and BG3 map")
written["x/teachy_tv/static.rgba"] = "stub"
written["x/teachy_tv/bg3.rgba"] = "stub"
check(TeachyTvExtract.ready(stub, "x") == true, "teachy ready() accepts a complete group")
written["x/mystery_gift/manifest.lua"] = "stub"
for i = 0, 7 do
  written["x/mystery_gift/card_bg" .. i .. ".rgba"] = "stub"
end
check(MysteryGiftExtract.ready(stub, "x") == false, "gift ready() is false with the cards but no news")
for i = 0, 7 do
  written["x/mystery_gift/news_bg" .. i .. ".rgba"] = "stub"
end
check(MysteryGiftExtract.ready(stub, "x") == true, "gift ready() accepts both background sets")

print("[test] 4. a built cache carries every baked sheet")
local Cache = require("tests.game3_cache")
local root = Cache.root("fame_checker/manifest.lua")
if not root then
  print("[skip] baked Fame Checker, Teachy TV, Mystery Gift and tower data: "
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

local blobs = {}
for _, sheet in ipairs(SHEETS) do
  local rel, w, h = sheet[1], sheet[2], sheet[3]
  local blob = readFile(rel)
  blobs[rel] = blob
  eq(blob and #blob or nil, w * h * 4, rel .. " is " .. w .. "x" .. h)
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

check(distinctColors(blobs["fame_checker/bg.rgba"]) > 4,
  "the Fame Checker page is painted art, not one flat colour")
check(distinctColors(blobs["fame_checker/0.rgba"]) > 4, "the OAK portrait is painted art")
local r, g, b = pixel(blobs["teachy_tv/screen.rgba"], 240, 0, 0)
check(r == 255 and g == 230 and b == 90,
  string.format("the Teachy TV screen corner is the cart's cream (%d,%d,%d)", r, g, b))
-- src/teachy_tv.c:118
local cutOut = 0
for i = 4, #blobs["teachy_tv/screen.rgba"], 4 do
  if blobs["teachy_tv/screen.rgba"]:byte(i) == 0 then cutOut = cutOut + 1 end
end
check(cutOut > 1000,
  "the screen frame is a cut out, its tile-0 interior transparent (" .. cutOut .. " px)")
local _, _, _, centreA = pixel(blobs["teachy_tv/screen.rgba"], 240, 120, 80)
eq(centreA, 0, "the centre of the TV frame is transparent")
-- src/teachy_tv.c:1219 TeachyTvLoadBg3Map renders Route1_Layout behind the cut out
check(distinctColors(blobs["teachy_tv/bg3.rgba"]) > 8,
  "BG3 behind the cut out is the baked Route 1 map")
local gr, gg, gb, ga = pixel(blobs["teachy_tv/bg3.rgba"], 256, 8, 120)
check(ga == 255 and gg > gr and gg > gb,
  string.format("the Route 1 grass under the TV window is green (%d,%d,%d)", gr, gg, gb))
-- src/teachy_tv.c:637 tilemapBuffer[32 * i + j] = ((Random() & 3) << 10) + 0x301F
local staticBlob = blobs["teachy_tv/static.rgba"]
check(staticBlob:sub(1, 8 * 4) ~= staticBlob:sub(8 * 4 + 1, 16 * 4),
  "the four static frames are the four flips of tile 0x1F, not one repeated cel")
local _, _, _, titleCentreA = pixel(blobs["teachy_tv/title.rgba"], 240, 120, 150)
eq(titleCentreA, 0, "the title card is a cut out too, it is BG2 over the same frame")
-- src/teachy_tv.c:1026 the end plate is 8x2 tiles at tile (20, 10)
local _, _, _, cornerA = pixel(blobs["teachy_tv/end.rgba"], 240, 0, 0)
eq(cornerA, 0, "the end plate is transparent outside its 8x2 block")
local plateOpaque = 0
for y = 80, 95 do
  for x = 160, 223 do
    local _, _, _, pa = pixel(blobs["teachy_tv/end.rgba"], 240, x, y)
    if pa == 255 then plateOpaque = plateOpaque + 1 end
  end
end
check(plateOpaque > 200, "the end plate paints its block (" .. plateOpaque .. " opaque pixels)")
check(blobs["mystery_gift/card_bg0.rgba"] ~= blobs["mystery_gift/card_bg7.rgba"],
  "wonder card backgrounds 0 and 7 are different art")
-- src/mystery_gift_show_card.c:153 bg3 reuses sCard2Gfx / sCard2Map with its own palette
check(blobs["mystery_gift/card_bg3.rgba"] ~= blobs["mystery_gift/card_bg0.rgba"],
  "wonder card 3 is card 2's tiles under its own palette")

print("[test] 5. the Fame Checker text pack decodes to the cart's strings")
local pack = loadTable("fame_checker/pack.lua")
check(type(pack) == "table", "fame_checker/pack.lua loads")
if pack then
  eq(pack.listNames[0], "OAK", "listNames[0] is gFameCheckerOakName")
  eq(pack.listNames[14], "FUJI", "listNames[14] is gFameCheckerMrFujiName")
  eq(pack.names[0], "PROF. OAK", "names[0] is gFameCheckerPersonName_ProfOak")
  eq(pack.names[15], "GIOVANNI", "names[15] is gFameCheckerPersonName_Giovanni")
  check(type(pack.quotes[0]) == "string" and pack.quotes[0]:find("{PLAYER}") ~= nil,
    "the OAK quote keeps its {PLAYER} placeholder")
  check(type(pack.flavorText[2]) == "table" and #tostring(pack.flavorText[2][0]) > 20,
    "BROCK slot 0 has flavour text")
  for p = 0, 15 do
    local rows = pack.flavorText[p]
    local locs = pack.originLocation[p]
    local objs = pack.originObject[p]
    if not (type(rows) == "table" and type(locs) == "table" and type(objs) == "table"
      and rows[5] and locs[5] and objs[5]) then
      check(false, "person " .. p .. " has six flavour texts with origins")
    end
  end
  check(true, "all sixteen people carry six flavour texts, locations and object names")
end
-- src/fame_checker.c:134 graphics/fame_checker/silhouette.gbapal is sixteen blacks
local silhouette = readFile("fame_checker/silhouette.pal")
eq(silhouette and #silhouette or nil, 16 * 3, "fame_checker/silhouette.pal is 16 colours")
check(silhouette == string.rep("\0", 48),
  "the silhouette palette is the cart's all-black bank, so a locked person is black")

local fameMan = loadTable("fame_checker/manifest.lua")
check(type(fameMan) == "table", "fame_checker/manifest.lua loads")
if fameMan then
  -- src/fame_checker.c:171 sFameCheckerTrainerPicIdxs
  eq(fameMan.trainerPic[3], 116, "trainerPic[1] is TRAINER_PIC_LEADER_BROCK")
  eq(fameMan.persons, 16, "the manifest names sixteen people")
end

print("[test] 6. the Trainer Tower set is gTrainerTowerFloors")
local tower = loadTable("trainer_tower.lua")
check(type(tower) == "table", "trainer_tower.lua loads")
if tower then
  -- src/trainer_tower_sets.c:8951
  eq(tower.header.numFloors, 8, "the local header is eight floors")
  eq(tower.header.id, 1, "the local header set id is 1")
  local floor = tower.floors[0][1]
  -- src/trainer_tower_sets.c:4793 sTrainerTowerFloor_Single_1
  eq(floor.id, 19, "singles floor 1 is set 19")
  eq(floor.floorIdx, 8, "singles floor 1 carries MAX_TRAINER_TOWER_FLOORS")
  eq(floor.challengeType, 0, "singles floor 1 is CHALLENGE_TYPE_SINGLE")
  eq(floor.prize, 14, "singles floor 1 pays TTPRIZE_UP_GRADE")
  local trainer = floor.trainers[1]
  eq(trainer.name, "ALBERTO", "the first singles trainer is ALBERTO")
  eq(trainer.facilityClass, 91, "ALBERTO is FACILITY_CLASS_SAILOR")
  eq(trainer.textColor, 5, "ALBERTO's text colour is 5")
  eq(#trainer.speechBefore, 6, "the easy chat speech is six words")
  eq(#trainer.mons, 6, "every tower trainer carries PARTY_SIZE mons")
  local mon = trainer.mons[1]
  eq(mon.species, 160, "ALBERTO leads with FERALIGATR")
  eq(mon.heldItem, 196, "FERALIGATR holds a FOCUS BAND")
  eq(mon.moves[1], 57, "its first move is SURF")
  eq(mon.moves[2], 89, "its second move is EARTHQUAKE")
  eq(mon.nickname, "FERALIGATR", "the mon carries its nickname")
  check(mon.hpIV >= 0 and mon.hpIV <= 31, "the packed IVs decode into range (" .. mon.hpIV .. ")")
  local floors = 0
  for challenge = 0, 3 do
    for i = 1, 8 do
      if tower.floors[challenge] and tower.floors[challenge][i] then floors = floors + 1 end
    end
  end
  eq(floors, 32, "all four challenge types carry eight floors")
  -- src/trainer_tower.c:105, :191
  eq(tower.singlesTrainerInfo[91].objGfx, 62, "FACILITY_CLASS_SAILOR walks as OBJ_EVENT_GFX_SAILOR")
  eq(tower.singlesTrainerInfo[91].gender, 0, "the sailor is MALE")
  eq(tower.doublesTrainerInfo[126].objGfx1, 17, "FACILITY_CLASS_TWINS is two LITTLE_GIRLs")
  eq(tower.doublesTrainerInfo[126].objGfx2, 17, "both twins use the same graphics")
  -- src/trainer_tower.c:960, :382
  eq(tower.encounterMusic[91], 285, "the sailor's encounter music is MUS_ENCOUNTER_BOY")
  eq(tower.facilityClassPic[91], 85, "FACILITY_CLASS_SAILOR draws TRAINER_PIC_SAILOR")
end

print("[test] 7. the egg groups and egg moves already in the cache are the cart's")
local meta = loadTable("pokemon/meta.lua")
local eggMoves = loadTable("pokemon/egg_moves.lua")
check(type(meta) == "table", "pokemon/meta.lua loads")
check(type(eggMoves) == "table", "pokemon/egg_moves.lua loads")
if meta and eggMoves then
  -- src/data/pokemon/species_info.h:61 .eggGroups = {EGG_GROUP_MONSTER, EGG_GROUP_GRASS}
  eq(meta[1].eggGroup1, 1, "BULBASAUR is EGG_GROUP_MONSTER")
  eq(meta[1].eggGroup2, 7, "BULBASAUR is also EGG_GROUP_GRASS")
  eq(meta[25].eggGroup1, 5, "PIKACHU is EGG_GROUP_FIELD")
  eq(meta[25].eggGroup2, 6, "PIKACHU is also EGG_GROUP_FAIRY")
  eq(meta[132].eggGroup1, 13, "DITTO is EGG_GROUP_DITTO")
  eq(meta[151].eggGroup1, 15, "MEW is EGG_GROUP_NO_EGGS_DISCOVERED")
  eq(#eggMoves[1], 8, "BULBASAUR has eight egg moves")
  eq(eggMoves[1][1], 113, "BULBASAUR's first egg move is LIGHT SCREEN")
  eq(eggMoves[4][1], 187, "CHARMANDER's first egg move is BELLY DRUM")
  check(eggMoves[25] == nil, "PIKACHU has no egg move run of its own")
end

print("[test] 8. the tutor bitfield drives the real CanLearnTutorMove")
local tutor = loadTable("pokemon/tutor.lua")
check(type(tutor) == "table", "pokemon/tutor.lua loads")
if tutor then
  -- src/data/pokemon/tutor_learnsets.h:1
  eq(tutor.moves[0], 5, "tutor 0 is MOVE_MEGA_PUNCH")
  eq(tutor.moves[14], 164, "tutor 14 is MOVE_SUBSTITUTE")
  eq(tutor.learnsets[1], 0x409A, "BULBASAUR's tutor bits are the cart's 0x409A")
  eq(tutor.learnsets[0], nil, "SPECIES_NONE has no tutor bits")
end

Cache.mount("pokemon/tutor.lua")
local MoveLearn = require("src.core.game3.move_learn")
MoveLearn.resetTutorPack()
check(MoveLearn.tutorLearnsets() ~= nil, "move_learn reads the baked tutor pack")
-- src/party_menu.c:1907 CanLearnTutorMove
check(MoveLearn.canLearnTutorMove(1, 1) == true, "BULBASAUR can learn SWORDS DANCE from the tutor")
check(MoveLearn.canLearnTutorMove(1, 0) == false, "BULBASAUR cannot learn MEGA PUNCH from the tutor")
check(MoveLearn.canLearnTutorMove(25, 11) == true, "PIKACHU can learn THUNDER WAVE from the tutor")
-- src/data/pokemon/tutor_learnsets.h:969
check(MoveLearn.canLearnTutorMove(133, 7) == true, "EEVEE can learn MIMIC from the tutor")
-- src/data/pokemon/tutor_learnsets.h:967 [SPECIES_DITTO] = 0
check(MoveLearn.canLearnTutorMove(132, 7) == false, "DITTO can learn no tutor move at all")
-- src/party_menu.c:1910 the three starter ultimate moves are hard cases, not bits
check(MoveLearn.canLearnTutorMove(3, 15) == true, "VENUSAUR can learn FRENZY PLANT")
check(MoveLearn.canLearnTutorMove(6, 15) == false, "CHARIZARD cannot learn FRENZY PLANT")

finish()

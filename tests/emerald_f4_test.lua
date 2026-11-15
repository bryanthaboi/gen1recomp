package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function has(rel)
  local src = cache and cache.read and cache:read(rel)
  return type(src) == "string"
end
for _, rel in ipairs({ "data/generated/gba/rse/pyramid/manifest.lua", "data/generated/gba/rse/trainer_hill/manifest.lua",
    "data/generated/gba/rse/event_islands/manifest.lua", "data/generated/gba/rse/apprentice/manifest.lua",
    "data/generated/gba/frontier/trainers.lua" }) do
  if not has(rel) then
    print("emerald_f4_test: skipped (no Emerald cache with " .. rel .. "; set POKEPORT_IDENTITY)")
    os.exit(0)
  end
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Runtime = require("src.core.game3.runtime")
local Rng = require("src.core.game3.rng")
local Bag = require("src.core.game3.bag")

local store = { flags = {}, vars = {} }
local Space = require("src.core.game3.scripting.space")
Space.store = store
Space.bundle = Space.ensureBundle(nil)

local sess = { version = "emerald", name = "BRENDAN", trainerId = 12345, secretId = 4321, money = 1000, party = {},
  gender = 0, bag = Bag.new(), flags = store.flags, vars = store.vars }
Runtime.getSession = function() return sess end

local Rse = require("src.core.game3.rse.init")
local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Py = require("src.core.game3.rse.frontier.pyramid")
local Hill = require("src.core.game3.rse.trainer_hill")
local Islands = require("src.core.game3.rse.event_islands")
local Ap = require("src.core.game3.rse.frontier.apprentice")

Util.newGame(sess)
Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PYRAMID, sess)

-- pokeemerald/src/battle_pyramid.c:107
local pm = Py.manifest()
eq(#pm.floorTemplates, 16, "16 floor templates (battle_pyramid.c:103)")
eq(pm.floorTemplates[1].numItems, 7, "template 0 has 7 items")
eq(pm.floorTemplates[16].numTrainers, 8, "template 15 has 8 trainers")
eq(#pm.floorTemplateOptions, 34, "34 floor template options (battle_pyramid.c:231)")
eq(#pm.pickupItems50, 20, "20 pickup rounds")
eq(pm.pickupItems50[1][1], C.items.byName.ITEM_HYPER_POTION, "round 1 pickup slot 1 is Hyper Potion")
eq(pm.pickupItems50[1][10], C.items.byName.ITEM_SACRED_ASH, "round 1 pickup slot 10 is Sacred Ash")
eq(#pm.postBattleTexts, 6, "six hint text groups")
eq(#pm.postBattleTexts[1][2], 9, "nine item-count hints per group")
eq(#pm.postBattleTexts[1][3], 8, "eight trainer-count hints per group")
eq(pm.postBattleTexts[1][2][1].name, "BattlePyramid_Text_ZeroItemsRemaining1", "item hints start at zero")
eq(#pm.wildMons50, 20, "20 level-50 wild rounds")
eq(pm.wildMons50[1][1].species, C.species.byName.SPECIES_PLUSLE, "round 1 wild mon 1 is Plusle")
eq(#pm.floorPalettes, 7, "seven floor palettes")
eq(pm.borderedSquares[1][3], -1, "square 0 has two neighbours (battle_pyramid.c:839)")
eq(#pm.shortStreakRewards, 6, "six short-streak prizes")
eq(#pm.longStreakRewards, 9, "nine long-streak prizes")

local GOLDEN = {
  { "42445 19772 51750 6328 0", "T0 0 2 0 3 1 1 0 3 0 1 0 1 2 1 0 3 0 E8 X13 [1,5,22,0] [2,5,30,0] [3,14,30,0] [4,6,21,1] [5,6,29,1] [6,15,28,1] [7,6,13,1] [8,15,12,1] [9,18,14,1] [10,31,12,1]" },
  { "12337 47931 7602 28140 0", "T1 0 1 4 1 1 2 4 4 1 3 2 1 4 4 2 2 2 E12 X1 [1,29,6,0] [2,6,12,0] [3,19,15,0] [4,30,5,1] [5,2,15,1] [6,23,14,1] [7,30,13,1] [8,2,22,1] [9,10,23,1]" },
  { "11265 56838 54810 9156 1", "T3 0 3 3 3 6 4 5 3 3 6 4 4 4 5 6 3 3 E4 X1 [1,23,31,0] [2,24,6,0] [3,31,15,0] [4,0,22,0] [5,18,30,1] [6,27,7,1] [7,26,14,1] [8,3,23,1]" },
  { "11889 55642 7747 16226 1", "T1 0 1 4 1 4 2 3 4 2 4 2 1 1 4 4 4 1 E2 X1 [1,19,15,0] [2,30,12,0] [3,14,20,0] [4,23,14,1] [5,26,15,1] [6,10,23,1] [7,22,21,1] [8,30,21,1] [9,7,30,1]" },
  { "17455 37959 54937 18907 4", "T4 0 7 6 4 5 6 7 4 5 7 5 7 6 6 5 5 5 E11 X15 [1,24,22,0] [2,28,20,0] [3,30,16,0] [4,28,16,0] [5,3,31,1] [6,31,31,1] [7,11,7,1] [8,23,6,1]" },
  { "15439 40433 23688 13507 4", "T4 0 7 4 4 7 5 5 6 7 6 5 6 4 6 4 6 4 E3 X15 [1,30,5,0] [2,25,5,0] [3,30,2,0] [4,25,2,0] [5,31,22,1] [6,15,30,1] [7,19,31,1] [8,15,6,1]" },
  { "7812 26995 65066 56045 6", "T7 0 11 7 9 14 8 13 11 10 13 14 14 13 13 12 13 13 E13 X4 [1,9,25,0] [2,13,25,0] [3,9,30,0] [4,13,30,0] [5,5,27,1] [6,15,24,1]" },
  { "41175 61027 59399 47393 2", "T11 0 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 E1 X7 [1,15,21,0] [2,7,29,0] [3,15,29,0] [4,23,29,0] [5,7,5,0] [6,15,23,1] [7,7,31,1] [8,15,31,1] [9,23,31,1]" },
  { "39354 64895 45020 58829 2", "T2 0 3 5 5 4 2 5 5 3 5 4 5 5 4 3 2 5 E13 X10 [1,18,25,0] [2,26,26,0] [3,7,2,0] [4,20,26,1] [5,24,24,1] [6,3,0,1] [7,8,0,1] [8,24,3,1]" },
  { "9594 15475 54804 21621 6", "T6 0 8 13 11 8 8 12 10 9 12 8 13 8 13 6 11 8 E5 X10 [1,9,9,0] [2,19,10,0] [3,27,8,0] [4,27,16,0] [5,12,24,0] [6,15,8,1] [7,17,10,1] [8,25,9,1]" },
  { "62141 8519 7952 40580 5", "T8 0 13 15 10 9 15 15 9 10 15 11 8 10 8 13 15 12 E4 X13 [1,14,29,0] [2,8,29,0] [3,15,25,0] [4,9,25,0] [5,15,21,0] [6,27,6,1] [7,7,23,1] [8,17,22,1] [9,25,21,1]" },
  { "60515 46591 22026 15347 3", "T4 0 5 6 4 7 7 7 7 7 7 5 6 4 7 7 7 4 E4 X2 [1,6,13,0] [2,1,13,0] [3,6,10,0] [4,1,10,0] [5,3,30,1] [6,11,30,1] [7,19,30,1] [8,11,7,1]" },
  { "7727 28600 37674 16952 5", "T6 0 13 11 6 13 7 6 12 11 9 8 8 10 9 10 6 8 E8 X15 [1,27,29,0] [2,6,13,0] [3,8,14,0] [4,21,14,0] [5,19,21,0] [6,25,30,1] [7,3,14,1] [8,11,15,1]" },
  { "19830 30403 30583 1581 3", "T6 0 12 12 11 12 10 12 6 12 13 12 11 12 8 10 7 6 E13 X6 [1,19,16,0] [2,25,17,0] [3,9,1,0] [4,25,1,0] [5,3,10,0] [6,23,18,1] [7,31,16,1] [8,15,0,1]" },
}

-- pokeemerald/src/battle_pyramid.c:1523
local realGfx, realTid = D.gfxId, Py.uniqueTrainerId
D.gfxId = function() return 7 end
Py.uniqueTrainerId = function(_, _, id) return 1000 + id end
local goldOk = 0
for _, g in ipairs(GOLDEN) do
  local r = {}
  for v in g[1]:gmatch("%d+") do r[#r + 1] = tonumber(v) end
  local f = Py.frontier(sess)
  f.pyramidRandoms = { r[1], r[2], r[3], r[4] }
  f.curChallengeBattleNum = r[5]
  local off = Py.layoutOffsets(sess)
  local en, ex = Py.entranceAndExit(sess)
  local objs = Py.loadObjectTemplates(sess)
  local parts = { "T" .. Py.floorTemplateId(sess) .. " 0" }
  for i = 1, 16 do parts[#parts + 1] = tostring(off[i]) end
  parts[#parts + 1] = "E" .. en
  parts[#parts + 1] = "X" .. ex
  for _, o in ipairs(objs) do
    parts[#parts + 1] = string.format("[%d,%d,%d,%d]", o.localId, o.x, o.y,
      (tonumber(o.graphicsId) == C.event_objects.byName.OBJ_EVENT_GFX_ITEM_BALL) and 1 or 0)
  end
  local got = table.concat(parts, " ")
  if got == g[2] then goldOk = goldOk + 1 else print("golden mismatch for " .. g[1] .. "\n  want " .. g[2] .. "\n  got  " .. got) end
end
eq(goldOk, #GOLDEN, "floor template, layout offsets, entrance/exit and object placement match pret for every golden seed")
D.gfxId, Py.uniqueTrainerId = realGfx, realTid

local f = Py.frontier(sess)
f.pyramidRandoms = { 42445, 19772, 51750, 6328 }
f.curChallengeBattleNum = 0
local def = Py.mapDef(Py.FLOOR_MAP)
local L, px, py = Py.composeLayout(sess, def.midLayout, false)
eq(L.width, 32, "composed floor is 32 metatiles wide")
local exitMid = C:require("metatile_labels", "METATILE_BattlePyramid_Exit")
local exits = 0
for y = 0, 31 do for x = 0, 31 do if L:midAt(x, y) == exitMid then exits = exits + 1 end end end
eq(exits, 1, "only the exit square keeps its exit metatile (battle_pyramid.c:1550)")
local _, exitSq = Py.entranceAndExit(sess)
local entSq = Py.entranceAndExit(sess)
check(px and math.floor(px / 8) + math.floor(py / 8) * 4 == entSq, "player starts in the entrance square")
check(entSq ~= exitSq, "entrance and exit squares differ")
do
  local sq = Py.mapDef(Py.mapIdForSquare(Py.layoutOffsets(sess)[1])).midLayout
  local saved = sq.cells[1]
  sq.cells[1] = nil
  local okHole, errHole = pcall(Py.composeLayout, sess, def.midLayout, false)
  sq.cells[1] = saved
  check(not okHole and tostring(errHole):find("has no cell", 1, true) ~= nil,
    "a pyramid square with a missing cell raises instead of drawing metatile 0")
end
Rng.SeedRng(99)
local objs = Py.loadObjectTemplates(sess)
local ids, dup = {}, false
local tpl = Py.floorTemplate(sess)
for i = 1, tpl.numTrainers do
  local tid = f.trainerIds[i]
  if ids[tid] then dup = true end
  ids[tid] = true
  check(tid >= 0 and tid < 100, "challenge 1 floor 1 trainer " .. i .. " is from 0..99")
end
check(not dup, "pyramid trainer ids are unique (battle_pyramid.c:1466)")
eq(#objs, tpl.numTrainers + tpl.numItems, "one object per trainer and item")
check(objs[1].scriptKey ~= nil and objs[1].scriptKey == (Py.scriptKey("BattlePyramid_TrainerBattle") or objs[1].scriptKey),
  "trainers run BattlePyramid_TrainerBattle")
check(objs[#objs].scriptKey ~= nil and objs[#objs].scriptKey ~= objs[1].scriptKey, "items run BattlePyramid_FindItemBall")

local ctx = { specialVars = {}, stringVars = { "", "", "" } }
local function sv(id, v) ctx.specialVars[id] = v end
sv(0x800F, tpl.numTrainers + 1)
Py.setItem(ctx, sess)
local item = ctx.specialVars[0x8000]
local found = false
for _, it in ipairs(pm.pickupItems50[1]) do if it == item then found = true end end
check(found, "pyramid_setitem picks from the round's pickup table (" .. tostring(item) .. ")")
eq(ctx.specialVars[0x8001], 1, "pyramid_setitem gives one item")
Py.hideItem(ctx, sess)
eq(Py.remainingItems(sess), tpl.numItems - 1, "HidePyramidItem moves the ball off the map (battle_pyramid.c:1054)")
eq(Py.remainingTrainers(sess), tpl.numTrainers, "no trainers battled yet")
Py.markBattled(sess, f.trainerIds[1], 1)
eq(Py.remainingTrainers(sess), tpl.numTrainers - 1, "marking a trainer battled lowers the count")
check(Py.trainerFlag(sess, 1), "trainer flag bit 0 set")
eq(objs[1].movementType, C:require("movement", "MOVEMENT_TYPE_WANDER_AROUND"), "battled trainer wanders (battle_pyramid.c:1405)")

-- pokeemerald/src/item.c:729
f.lvlMode = 0
Py.initBag(sess, 0)
check(Py.bagHas(sess, C.items.byName.ITEM_HYPER_POTION, 1), "new bag holds a Hyper Potion (battle_pyramid.c:1809)")
check(Py.bagHas(sess, C.items.byName.ITEM_ETHER, 1), "new bag holds an Ether")
for _, n in ipairs({ "ITEM_ANTIDOTE", "ITEM_BURN_HEAL", "ITEM_ICE_HEAL", "ITEM_AWAKENING", "ITEM_PARALYZE_HEAL",
  "ITEM_FULL_RESTORE", "ITEM_MAX_POTION", "ITEM_REVIVE" }) do Py.bagAdd(sess, C.items.byName[n], 1) end
check(not Py.bagHasSpace(sess, C.items.byName.ITEM_LEFTOVERS, 1), "ten distinct items fill the pyramid bag")
check(not Py.bagAdd(sess, C.items.byName.ITEM_LEFTOVERS, 1), "adding an eleventh kind fails")
check(Py.bagAdd(sess, C.items.byName.ITEM_ETHER, 98), "stacking to 99 works")
check(not Py.bagAdd(sess, C.items.byName.ITEM_ETHER, 1), "stack cap is 99")
check(Py.bagRemove(sess, C.items.byName.ITEM_HYPER_POTION, 1), "removing the potion works")
Py.compactBag(sess)
eq(Py.bagLists(sess)[1], C.items.byName.ITEM_ETHER, "CompactItems moves the next item up")
sess.party = { D.createMon(C.species.byName.SPECIES_SWAMPERT, 50, 10, 1, 1), D.createMon(C.species.byName.SPECIES_BLAZIKEN, 50, 10, 1, 1),
  D.createMon(C.species.byName.SPECIES_SCEPTILE, 50, 10, 1, 1) }
D.setHeldItem(sess.party[1], C.items.byName.ITEM_LEFTOVERS)
check(Py.monsHaveHeldItem(sess), "DoBattlePyramidMonsHaveHeldItem sees the Leftovers")
Py.tryStoreHeldItems(ctx, sess)
eq(ctx.specialVars[0x800D], 0, "held item stored into the pyramid bag")
eq(tonumber(sess.party[1].heldItem) or 0, 0, "party held item cleared")
check(Py.bagHas(sess, C.items.byName.ITEM_LEFTOVERS, 1), "Leftovers now in the pyramid bag")
eq(Py.hint(35), 5, "GetBattlePyramidHint 35 wins -> round 5 (field_specials.c:3873)")
eq(Py.hint(7 * 21), 1, "hint wraps after 20 rounds")

-- pokeemerald/src/battle_pyramid.c:1344
Util.set1(f.pyramidWinStreaks, 0, 0)
Rng.SeedRng(5)
local w = Py.generateWildMon(sess, { species = 1, level = 5 })
eq(w.species, pm.wildMons50[1][1].species, "wild slot 1 maps to the round's first pyramid mon")
check(w.level >= pm.wildMons50[1][1].lvl - 5 and w.level <= pm.wildMons50[1][1].lvl + 5, "level within +-5 of the table")
eq(w.moves[1], pm.wildMons50[1][1].moves[1], "moves come from the table")
f.pyramidRandoms = { 0x1234, 0xBEEF, 0x0F0F, 0x5A5A }
eq(Py.runMultiplier(sess), Py.floorTemplate(sess).runMultiplier, "GetPyramidRunMultiplier reads the floor template")
local runSession = { version = "emerald", map = Py.FLOOR_MAP,
  frontier = { pyramidRandoms = { 0, 0, 0, 0 }, curChallengeBattleNum = 0, lvlMode = 0 } }
local runMultiplier
for rand = 0, 99 do
  runSession.frontier.pyramidRandoms[4] = rand
  runMultiplier = Py.runMultiplier(runSession)
  if runMultiplier < 128 then break end
end
check(runMultiplier and runMultiplier < 128, "Pyramid floor data includes a reduced run multiplier")
local runOdds = math.floor(97 * runMultiplier / 100) % 256
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Engine = require("src.core.game3.battle.engine")
local function pyramidRun(roll)
  local st = State.new({ wild = true, playerParty = { { species = C.species.byName.SPECIES_SWAMPERT,
    level = 50, hp = 100, maxHp = 100, speed = 97 } },
    foeParty = { { species = C.species.byName.SPECIES_PLUSLE, level = 50, hp = 100, maxHp = 100, speed = 100 } } })
  st.player.mon.speed, st.enemy.mon.speed = 97, 100
  st.pyramid, st.session = true, runSession
  st.rng = function() return roll end
  local ad = Adapter.new(st)
  return Engine.tryFlee(st, ad)
end
eq(pyramidRun(runOdds - 1), true, "Pyramid run succeeds one point below the floor-scaled odds")
eq(pyramidRun(runOdds), false, "Pyramid run fails at the floor-scaled odds boundary")

local oldVblank, oldHillTimer = Runtime._vblankCounter or 0, Hill.state(sess).timer
Hill.setTimerRunning(sess, true)
local hillTimerBase = Hill.state(sess).timer
for _ = 1, 5 do Runtime.tickVblank(sess, true) end
Hill.syncTimer(sess)
eq(Hill.state(sess).timer, hillTimerBase + 5, "Trainer Hill VBlank timer advances while battle menus hold field input")
Hill.setTimerRunning(sess, false)
Hill.state(sess).timer = oldHillTimer
Runtime._vblankCounter = oldVblank

-- pokeemerald/src/trainer_hill.c:685
local hm = Hill.manifest()
eq(#hm.challenges, 4, "four challenge modes")
eq(hm.challenges[1].name, "sChallenge_Normal", "mode 0 is Normal")
eq(hm.challenges[1].numFloors, 4, "all modes use four floors")
eq(hm.challenges[1].floors[1].trainers[1].name, "ALAINA", "Normal 1F trainer 1 is Alaina")
eq(#hm.prizeListSets, 2, "two prize list sets")
Rse.setFlag("FLAG_SYS_GAME_CLEAR", true, sess)
local expectPrize = { "ITEM_TM11", "ITEM_ELIXIR", "ITEM_TM19", "ITEM_TM31" }
for mode = 0, 3 do
  local h = Hill.state(sess)
  h.mode = mode
  h.timer = 60 * 60 * 5
  eq(Hill.prizeItemId(sess), C.items.byName[expectPrize[mode + 1]], "mode " .. mode .. " under 12 minutes prize (trainer_hill.c:1000)")
end
Hill.state(sess).timer = 60 * 60 * 20
eq(Hill.prizeItemId(sess), C.items.byName.ITEM_GREAT_BALL, "20 minutes earns a Great Ball")
local m, s2, fr = Hill.timeParts(60 * 60 * 3 + 60 * 7 + 30)
check(m == 3 and s2 == 7 and fr == 50, "time buffer 3:07.50 (trainer_hill.c:505)")
sess.map = "EM_TRAINER_HILL_2F"
Hill.state(sess).mode = 0
local hdef = { mapId = "EM_TRAINER_HILL_2F" }
require("src.core.game3.dataset").attachMidLayouts({ EM_TRAINER_HILL_2F = hdef })
local HL = Hill.composeLayout(sess, hdef)
eq(HL.height, 21, "hill floor is 21 rows")
local fl = Hill.floor(sess)
eq(HL:midAt(3, 5 + 2), fl.map.metatiles[2 * 16 + 3 + 1] + 512, "floor metatiles come from the challenge data (trainer_hill.c:653)")
do
  local saved = fl.map.metatiles[1]
  fl.map.metatiles[1] = nil
  local okHole, errHole = pcall(Hill.composeLayout, sess, hdef)
  fl.map.metatiles[1] = saved
  check(not okHole and tostring(errHole):find("has no metatile", 1, true) ~= nil,
    "a hill floor with a missing metatile raises instead of drawing metatile 0")
  local savedRow = fl.map.collision[1]
  fl.map.collision[1] = nil
  local okRow, errRow = pcall(Hill.composeLayout, sess, hdef)
  fl.map.collision[1] = savedRow
  check(not okRow and tostring(errRow):find("has no collision row", 1, true) ~= nil,
    "a hill floor with a missing collision row raises")
  local base = hdef._hillBase
  local savedCell = base.cells[1]
  base.cells[1] = nil
  local okBase, errBase = pcall(Hill.composeLayout, sess, hdef)
  base.cells[1] = savedCell
  check(not okBase and tostring(errBase):find("has no cell", 1, true) ~= nil,
    "a hill base layout with a missing cell raises")
end
local tpls = Hill.objectTemplates(sess)
eq(#tpls, 2, "two trainers per floor")
eq(tpls[1].x, fl.map.trainerCoords[1] % 16, "trainer x from trainerCoords")
check(tpls[1].scriptKey ~= nil or not (Space.bundle and Space.bundle.labels), "hill trainers run the hill trainer script")
local hp = Hill.party(sess, 2)
eq(#hp, 3, "hill trainers field three mons (trainer_hill.c:864)")
eq(hp[1].species, fl.trainers[2].mons[4].species, "trainer 2 uses mons 3..5")
Hill.setTrainerFlag(sess, 2)
check(Hill.trainerFlag(sess, 2) and not Hill.trainerFlag(sess, 1), "SetHillTrainerFlag marks only that trainer")
sess.map = nil

-- pokeemerald/src/field_specials.c:3264
local im = Islands.manifest()
eq(#im.deoxysRockCoords, 11, "eleven rock positions")
eq(im.deoxysRockCoords[1][1], 15, "rock starts at x 15")
eq(#im.deoxysRockMaxSteps, 10, "ten step caps")
-- pokeemerald/data/mystery_gift.s:19
local giftSpecs = {
  { "aurora", "MysteryGiftScript_AuroraTicket", 3 },
  { "mystic", "MysteryGiftScript_MysticTicket", 3 },
  { "oldSeaMap", "MysteryGiftScript_OldSeaMap", 3 },
  { "surfPichu", "MysteryGiftScript_SurfPichu", 9 },
  { "battleCard", "MysteryGiftScript_BattleCard", 2 },
  { "stampCard", "MysteryGiftScript_StampCard", 1 },
  { "alteringCave", "MysteryGiftScript_AlteringCave", 2 },
}
eq(#im.gifts, #giftSpecs, "seven supported wonder card gift bundles")
local gifts, giftScripts = {}, {}
for i, spec in ipairs(giftSpecs) do
  local gift = im.gifts[i] or {}
  eq(gift.id, spec[1], "wonder card gift " .. i .. " is " .. spec[1])
  eq((gift.labels or {})[1], spec[2], spec[1] .. " starts at the original script")
  eq(#(gift.keys or {}), spec[3], spec[1] .. " carries its branch scripts")
  eq(gift.script, (gift.keys or {})[1], spec[1] .. " entry points to the first extracted script")
  gifts[spec[1]] = gift
  for j, key in ipairs(gift.keys or {}) do
    local rows = im.giftScripts[key]
    check(type(rows) == "table" and #rows > 0, spec[1] .. " branch " .. j .. " is extracted")
    giftScripts[gift.labels[j]] = rows
    for _, row in ipairs(rows or {}) do
      if row.op == "vmessage" then
        check(im.giftTexts[row[1]] ~= nil, spec[1] .. " message resolves to extracted text")
      end
    end
  end
end
local function scriptHas(rows, op, ...)
  local args = { ... }
  for _, row in ipairs(rows or {}) do
    if row.op == op then
      local same = true
      for i, value in ipairs(args) do if row[i] ~= value then same = false end end
      if same then return true end
    end
  end
  return false
end
local function givesItem(rows, item)
  for i, row in ipairs(rows or {}) do
    local quantity, give = rows[i + 1], rows[i + 2]
    if row.op == "setorcopyvar" and row[1] == C:var("VAR_0x8000") and row[2] == item
        and quantity and quantity.op == "setorcopyvar" and quantity[1] == C:var("VAR_0x8001")
        and quantity[2] == 1 and give and give.op == "callstd" and give[1] == 0 then return true end
  end
  return false
end
-- pokeemerald/data/scripts/gift_aurora_ticket.inc:14
for _, spec in ipairs({
  { "aurora", "ITEM_AURORA_TICKET", "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_RECEIVED_AURORA_TICKET" },
  { "mystic", "ITEM_MYSTIC_TICKET", "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_RECEIVED_MYSTIC_TICKET" },
  { "oldSeaMap", "ITEM_OLD_SEA_MAP", "FLAG_ENABLE_SHIP_FARAWAY_ISLAND", "FLAG_RECEIVED_OLD_SEA_MAP" },
}) do
  local rows = im.giftScripts[gifts[spec[1]].script]
  check(givesItem(rows, C:require("items", spec[2])), spec[1] .. " gives its original key item once")
  check(scriptHas(rows, "setflag", C:require("flags", spec[3])), spec[1] .. " enables its destination")
  check(scriptHas(rows, "setflag", C:require("flags", spec[4])), spec[1] .. " records receipt")
end
-- pokeemerald/data/scripts/gift_pichu.inc:30
check(scriptHas(giftScripts.SurfPichu_GiveEgg, "giveegg", C:require("species", "SPECIES_PICHU")),
  "Surf Pichu card gives a Pichu egg")
for slot = 1, 5 do
  check(scriptHas(giftScripts["SurfPichu_Slot" .. slot], "setmonmove", slot, 2, C:require("moves", "MOVE_SURF")),
    "Surf Pichu branch installs Surf in party slot " .. slot)
end
-- pokeemerald/data/scripts/gift_battle_card.inc:12
check(givesItem(giftScripts.MysteryGiftScript_BattleCard, C:require("items", "ITEM_POTION")),
  "Battle Card prize is one Potion")
-- pokeemerald/data/scripts/gift_stamp_card.inc:4
check(scriptHas(giftScripts.MysteryGiftScript_StampCard, "specialvar", C:var("VAR_0x8008"),
  C:special("GetMysteryGiftCardStat")), "Stamp Card reads the saved card's stamp limit")
-- pokeemerald/data/scripts/gift_altering_cave.inc:3
check(scriptHas(giftScripts.MysteryGiftScript_AlteringCave, "addvar", C:var("VAR_ALTERING_CAVE_WILD_SET"), 1),
  "Altering Cave card advances the encounter set")
check(scriptHas(giftScripts.MysteryGiftScript_AlteringCave, "setvar", C:var("VAR_ALTERING_CAVE_WILD_SET"), 0),
  "Altering Cave card wraps the encounter set")
Rse.setVar("VAR_DEOXYS_ROCK_LEVEL", 0, sess)
local results = {}
for i = 1, 11 do
  Rse.setVar("VAR_DEOXYS_ROCK_STEP_COUNT", 1, sess)
  results[i] = Islands.rockInteraction(sess)
end
eq(results[1], Islands.ROCK.PROGRESSED, "first touch moves the rock")
eq(Rse.var("VAR_DEOXYS_ROCK_LEVEL", sess), 10, "ten moves reach the last position")
eq(results[11], Islands.ROCK.SOLVED, "touching the rock at level 10 solves the puzzle")
eq(Islands.rockInteraction(sess), Islands.ROCK.COMPLETE, "then it stays complete")
Rse.setFlag("FLAG_DEOXYS_ROCK_COMPLETE", false, sess)
Rse.setVar("VAR_DEOXYS_ROCK_LEVEL", 3, sess)
Rse.setVar("VAR_DEOXYS_ROCK_STEP_COUNT", 50, sess)
eq(Islands.rockInteraction(sess), Islands.ROCK.FAILED, "too many steps resets the puzzle")
eq(Rse.var("VAR_DEOXYS_ROCK_LEVEL", sess), 0, "level back to 0")
sess.options = {}
check(Islands.pendingGift(sess) == nil, "no gifts while the option is off")
Islands.setEnabled(sess, true)
check(Islands.pendingGift(sess) == nil, "the option alone hands out nothing; the relay controls tickets")
eq(Rse.var("VAR_DISTRIBUTE_EON_TICKET", sess), 0, "no Eon Ticket without the relay")
local feedCards = {}
for _, b in ipairs(require("tests.fixtures.game3_gift_cards").cards("rse")) do feedCards[#feedCards + 1] = { key = b.key, card = b.card } end
Islands.applyFeed(sess, { cards = { feedCards[2] } })
eq(Islands.pendingGift(sess).id, "aurora", "a relay AURORA TICKET card is offered")
check(not Islands.eonPending(sess), "the relay feed without the Eon card leaves the Eon Ticket off")
Islands.applyFeed(sess, { cards = feedCards })
Islands.sync(sess, { offline = true })
eq(Islands.pendingGift(sess).id, "aurora", "the Aurora Ticket is the first wonder card")
eq(Rse.var("VAR_DISTRIBUTE_EON_TICKET", sess), 1, "the relay Eon Ticket raises the distribution var")
Rse.setFlag("FLAG_RECEIVED_AURORA_TICKET", true, sess)
eq(Islands.pendingGift(sess).id, "mystic", "then the Mystic Ticket")
Rse.setFlag("FLAG_RECEIVED_MYSTIC_TICKET", true, sess)
eq(Islands.pendingGift(sess).id, "oldSeaMap", "then the Old Sea Map")
Rse.setFlag("FLAG_RECEIVED_OLD_SEA_MAP", true, sess)
check(Islands.pendingGift(sess) == nil, "receiving all three tickets leaves no automatic gift pending")

-- pokeemerald/src/apprentice.c:722
local am = Ap.manifest()
eq(#am.firstMeeting, 16, "sixteen apprentices of texts")
eq(#am.validMoves, C:require("moves", "MOVE_PSYCHO_BOOST") + 1, "valid moves span every move")
sess.apprentices, sess.playerApprentice = nil, nil
Rng.SeedRng(3)
Ap.resetAll(sess)
local p = Ap.player(sess)
local init = {}
for _, v in ipairs(am.initialIds) do init[v] = true end
check(init[p.id], "first apprentice id comes from sInitialApprenticeIds")
p.lvlMode = Ap.LVL_MODE_50
Ap.shuffleSpecies(sess)
local seenArr = {}
for i = 1, 3 do
  seenArr[bit.rshift(p.speciesIds[i], 4)] = true
  seenArr[bit.band(p.speciesIds[i], 0xF)] = true
end
local distinct = 0
for _ in pairs(seenArr) do distinct = distinct + 1 end
eq(distinct, 6, "ShuffleApprenticeSpecies offers six distinct species")
p.questionsAnswered = 3
Ap.setRandomQuestionData(sess)
local counts = { [0] = 0, 0, 0, 0 }
for i = 1, Ap.MAX_QUESTIONS do counts[p.questions[i].questionId] = counts[p.questions[i].questionId] + 1 end
check(counts[1] <= 3 and counts[2] <= 5 and counts[3] <= 1, "question mix respects the limits")
local moveOk = true
for i = 1, Ap.MAX_QUESTIONS do
  local q = p.questions[i]
  if q.questionId == Ap.QID.WHICH_MOVE and (q.data == 0 or q.moveSlot > 3) then moveOk = false end
end
check(moveOk, "every which-move question has an alternate move and slot")
Ap.save(sess)
local saved = Ap.saved(sess)[1]
eq(saved.id, p.id, "SaveApprentice stores the id")
eq(saved.number, 1, "first save numbers the apprentice 1")
check(saved.party[1].species ~= 0, "saved apprentice party has species")

T.finish()

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
if not (has("data/generated/gba/frontier/trainers.lua") and has("data/generated/gba/rse/frontier/manifest.lua")) then
  print("emerald_frontier_test: skipped (no Emerald cache with rse/frontier; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Runtime = require("src.core.game3.runtime")
local Rng = require("src.core.game3.rng")

local store = { flags = {}, vars = {} }
local Space = require("src.core.game3.scripting.space")
Space.store = store

local sess = { version = "emerald", name = "BRENDAN", trainerId = 12345, secretId = 4321, money = 1000, party = {},
  gender = 0, bag = {}, flags = store.flags, vars = store.vars }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Tower = require("src.core.game3.rse.frontier.tower")
local Tents = require("src.core.game3.rse.frontier.tents")
local Rse = require("src.core.game3.rse.init")
local Natives = require("src.core.game3.scripting.natives")
local NF = require("src.core.game3.scripting.natives_frontier")

local function mon(name, level, item)
  local m = D.createMon(C.species.byName[name], level, 20, 7, 99)
  D.setHeldItem(m, item and C.items.byName[item] or 0)
  return m
end

local man = D.manifest()
eq(#man.battlePointAwards, 30, "sBattlePointAwards has 30 challenge rows (frontier_util.c:500)")
eq(man.battlePointAwards[1][1][1], 1, "tower singles challenge 1 awards 1 BP")
eq(man.battlePointAwards[3][1][3], 5, "tower multis challenge 3 awards 5 BP")
eq(man.brainStreakAppearances[1][1], 35, "Anabel appears at 35 wins (frontier_util.c:88)")
eq(man.brainStreakAppearances[1][2], 70, "gold Anabel at 70")
eq(#man.transitions.frontier, 12, "12 frontier transitions (battle_setup.c:131)")
eq(man.towerStreakThresholds[1], 7, "elevator streak thresholds start at 7 (field_specials.c:2209)")
eq(man.gamblerChallenges[4], 256, "gambler challenge 4 = FRONTIER_CHALLENGE(DOME, SINGLES)")

local banned = D.pack("banned").species
eq(#banned, 10, "ten banned species (frontier_util.c:679)")
check(Util.isBanned(C.species.byName.SPECIES_MEWTWO), "Mewtwo is banned")
check(not Util.isBanned(C.species.byName.SPECIES_SWAMPERT), "Swampert is allowed")

eq(D.fixedIvs(0), 3, "trainer 0 uses 3 IVs (battle_tower.c:3292)")
eq(D.fixedIvs(150), 12, "trainer 150 uses 12 IVs")
eq(D.fixedIvs(250), 31, "trainer 250 uses max IVs")

local function setVar(name, v) Rse.setVar(name, v, sess) end

setVar("VAR_FRONTIER_FACILITY", D.FACILITY.TOWER)
setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES)
Util.newGame(sess)
local f = Util.frontier(sess)
eq(f.trainerIds[1], 0xFFFF, "new game frontier trainerIds start at 0xFFFF")

Rng.SeedRng(0x1234)
local party = {}
D.fillTrainerParty(sess, 5, 0, 3, party)
eq(#party, 3, "FillTrainerParty builds three mons")
local species, items = {}, {}
local dupSpecies, dupItem, lvOk, ivOk = false, false, true, true
for _, m in ipairs(party) do
  if species[m.species] then dupSpecies = true end
  species[m.species] = true
  local it = tonumber(m.heldItem) or 0
  if it ~= 0 and items[it] then dupItem = true end
  items[it] = true
  if m.level ~= 50 then lvOk = false end
  if m.ivs.hp ~= 3 then ivOk = false end
end
check(not dupSpecies, "no duplicate species in a frontier party")
check(not dupItem, "no duplicate held items in a frontier party")
check(lvOk, "level-50 mode builds level 50 mons")
check(ivOk, "trainer 5 mons carry 3 fixed IVs")
local evTotal = 0
for _, v in pairs(party[1].evs) do evTotal = evTotal + v end
check(evTotal > 0 and evTotal <= 510, "EV spread applied (pokemon.c:2584)")
eq(party[1].nature, party[1].personality % 25, "nature comes from the chosen personality")

local brain = D.brainParty(sess, D.FACILITY.TOWER, 50)
eq(#brain, 3, "Anabel brings three mons")
eq(brain[1].species, C.species.byName.SPECIES_ALAKAZAM, "silver Anabel leads with Alakazam (frontier_util.c:104)")
eq(brain[1].nature, C.natures and C.natures.byName and C.natures.byName.NATURE_MODEST or 15,
  "brain mon nature matches the table")

sess.party = { mon("SPECIES_SWAMPERT", 50, "ITEM_LEFTOVERS"), mon("SPECIES_BLAZIKEN", 50),
  mon("SPECIES_SCEPTILE", 50), mon("SPECIES_MEWTWO", 70) }
local short = Util.checkPartyIneligibility(sess, D.LVL.L50)
check(not short, "three distinct legal mons pass the level-50 eligibility check")
sess.party = { mon("SPECIES_SWAMPERT", 50), mon("SPECIES_MEWTWO", 50), mon("SPECIES_BLAZIKEN", 60) }
local short2, names = Util.checkPartyIneligibility(sess, D.LVL.L50)
check(short2, "a banned mon and an over-level mon leave too few eligible")
check(type(names) == "string", "ineligibility buffers a caught-banned list string")
eq(Util.checkBattleEntries(sess, { mon("SPECIES_SWAMPERT", 50), mon("SPECIES_SWAMPERT", 50), mon("SPECIES_ABRA", 50) },
  { 1, 2, 3 }, 3), "gText_MonsCantBeSame", "two of the same species are refused (party_menu.c:5648)")

sess.party = { mon("SPECIES_SWAMPERT", 50), mon("SPECIES_BLAZIKEN", 50), mon("SPECIES_SCEPTILE", 50),
  mon("SPECIES_ZIGZAGOON", 50) }
local ctx = { specialVars = {}, stringVars = { "", "", "" } }
local function sv(id, v) ctx.specialVars[id] = v end
f.lvlMode = 0

sv(0x8004, Tower.FUNC.INIT)
require("src.core.game3.scripting.natives_tower_rse").call(ctx, nil)
eq(f.challengeStatus, Util.CHALLENGE_STATUS.SAVING, "tower_init sets CHALLENGE_STATUS_SAVING (battle_tower.c:911)")
sv(0x8004, Tower.FUNC.SET_DATA) sv(0x8005, Tower.DATA.WIN_STREAK_ACTIVE) sv(0x8006, 1)
require("src.core.game3.scripting.natives_tower_rse").call(ctx, nil)
check(Util.isWinStreakActive(sess, Util.STREAK.TOWER_SINGLES_50), "tower_set WIN_STREAK_ACTIVE sets the singles-50 flag")

for battle = 1, 7 do
  sv(0x8004, Tower.FUNC.SET_OPPONENT)
  require("src.core.game3.scripting.natives_tower_rse").call(ctx, nil)
  local tid = sess.frontierOpponentA
  if battle < 7 then
    check(tid >= 0 and tid <= 99, "challenge 1 battle " .. battle .. " draws a trainer from 0..99 (battle_tower.c:857)")
  else
    check(tid >= 100 and tid <= 119, "the seventh battle draws from the hard range 100..119 (battle_tower.c:869)")
  end
  sv(0x8004, Util.FUNC.INCREMENT_STREAK)
  NF.callUtil(ctx, nil)
  sv(0x8004, Tower.FUNC.SET_BATTLE_WON)
  require("src.core.game3.scripting.natives_tower_rse").call(ctx, nil)
end
eq(Util.get2(f.towerWinStreaks, 0, 0), 7, "seven wins make a streak of 7")
eq(ctx.specialVars[0x800D], 7, "tower_setbattlewon returns the battle number (battle_tower.c:980)")
local distinct = {}
local okDistinct = true
for i = 1, 6 do
  if distinct[f.trainerIds[i]] then okDistinct = false end
  distinct[f.trainerIds[i]] = true
end
check(okDistinct, "the first six opponents are all different trainers")
eq(sess.gameStats[Util.GAME_STAT_BATTLE_TOWER_SINGLES_STREAK], 7, "GAME_STAT_BATTLE_TOWER_SINGLES_STREAK tracks the streak")

f.battlePoints = 0
sv(0x8004, Util.FUNC.GIVE_BATTLE_POINTS)
NF.callUtil(ctx, nil)
eq(f.battlePoints, 1, "the first seven-win tower singles challenge awards 1 BP (frontier_util.c:503)")
eq(ctx.stringVars[1], "1", "the award is buffered in gStringVar1")
Util.set2(f.towerWinStreaks, 0, 0, 21)
Util.giveBattlePoints(sess, false)
eq(f.battlePoints, 1 + 3, "a 21-streak awards challenge 3's 3 BP")
Util.set2(f.towerWinStreaks, 0, 0, 7)

sv(0x8004, Util.FUNC.CHECK_AIR_TV_SHOW)
NF.callUtil(ctx, nil)
eq(Util.get2(f.towerRecordWinStreaks, 0, 0), 7, "frontier_checkairshow records the best streak (frontier_util.c:1542)")

eq(Util.brainStatus(sess), Util.BRAIN.NOT_READY, "no brain at a 7 streak")
Util.set2(f.towerWinStreaks, 0, 0, 34)
eq(Util.brainStatus(sess), Util.BRAIN.SILVER, "Anabel is up next at 34 wins (+1 offset, frontier_util.c:1662)")
Util.set2(f.towerWinStreaks, 0, 0, 7)

sv(0x8004, Util.FUNC.RESULTS_WINDOW) sv(0x8005, D.FACILITY.TOWER) sv(0x8006, D.MODE.SINGLES)
local Records = require("src.ui.game3.rse.frontier_records")
local win = Records.buildResults(sess, D.FACILITY.TOWER, D.MODE.SINGLES)
local found = false
for _, p in ipairs(win.prints) do
  if p.s:find("7", 1, true) and p.x == 132 then found = true end
end
check(found, "the tower results window prints the 7 streak at x=132 (frontier_util.c:1063)")
local hall = Util.rankingHall(sess, Util.RANKING_HALL.TOWER_SINGLES, 0)
eq(hall[1].winStreak, 7, "the ranking hall lists the player's 7-win record first")

local SaveSections = require("src.core.game3.save_sections")
local section = SaveSections.fields(Util.SAVE_FIELDS)
local out = {}
section.export(sess, out)
local LuaWriter = require("src.import.LuaWriter")
local blob = LuaWriter.encode(out)
local back = assert(load(blob, "=blob", "t", {}))()
local restored = {}
section.restore(back, restored)
eq(Util.get2(restored.frontier.towerRecordWinStreaks, 0, 0), 7, "the frontier save section round-trips the record")
eq(restored.frontier.battlePoints, f.battlePoints, "and the Battle Points")

local bytes = {}
Util.toCart(function(off, size, v)
  for i = 0, size - 1 do bytes[off + i] = math.floor(v / 256 ^ i) % 256 end
end, sess)
local cartF = Util.fromCart(function(off, size)
  local v = 0
  for i = size - 1, 0, -1 do v = v * 256 + (bytes[off + i] or 0) end
  return v
end)
eq(Util.get2(cartF.towerRecordWinStreaks, 0, 0), 7, "cart codec round-trips towerRecordWinStreaks (global.h:394 @1700)")
eq(cartF.battlePoints, f.battlePoints, "cart codec round-trips battlePoints @2156")
eq(cartF.winStreakActiveFlags, f.winStreakActiveFlags, "cart codec round-trips winStreakActiveFlags")
eq(cartF.lvlMode, f.lvlMode, "cart codec round-trips the lvlMode bitfield")

f.lvlMode = D.LVL.TENT
setVar("VAR_FRONTIER_FACILITY", D.FACILITY.FACTORY)
Tents.generateRentalMons(sess)
local rs = {}
local okRent = true
for i = 1, 6 do
  local id = f.rentalMons[i].monId
  if id == nil or id >= D.NUM_SLATEPORT_TENT_MONS then okRent = false end
end
check(okRent, "six Slateport rentals drawn from the 70 tent mons (battle_tent.c:289)")
Tents.generateOpponentMons(sess)
eq(#sess.frontierTempParty, 3, "the tent opponent gets three mons")
local tparty = Tents.factoryTentParty(sess)
eq(tparty[1].level, 30, "Slateport tent opponents are level 30 (battle_tower.c:1891)")
eq(tparty[1].ivs.hp, 0, "tent opponents have 0 IVs")
setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PALACE)
local tp = {}
D.fillTentTrainerParty(sess, 3, 0, 3, tp, D.FACILITY.PALACE)
eq(#tp, 3, "Verdanturf tent trainer gets three mons")
check(tp[1].level >= 30, "tent level is at least TENT_MIN_LEVEL")

f.verdanturfTentPrize = 0
Tents.setRandomPrize(sess, "verdanturf")
eq(f.verdanturfTentPrize, C.items.byName.ITEM_NEST_BALL, "Verdanturf prize is a Nest Ball (battle_tent.c:73)")

Natives.bind("emerald")
for _, name in ipairs({ "CallFrontierUtilFunc", "CallBattleTowerFunc", "CallVerdanturfTentFunction",
  "CallFallarborTentFunction", "CallSlateportTentFunction", "ChoosePartyForBattleFrontier", "ShowBattlePointsWindow",
  "GetFrontierBattlePoints", "TakeFrontierBattlePoints", "GiveFrontierBattlePoints", "DoSpecialTrainerBattle",
  "ScriptMenu_CreateLilycoveSSTidalMultichoice", "GetLilycoveSSTidalSelection", "SaveGame" }) do
  local id = C.specials.byName[name]
  check(id ~= nil and Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound on Emerald")
end
Natives.bind("firered")
local frId = require("src.core.game3.constants").of("firered").specials.byName.CallBattleTowerFunc
check(frId == nil or Natives.ALLOW["special:" .. frId] == nil or
  Natives.handlerFor("CallBattleTowerFunc") ~= require("src.core.game3.scripting.natives_tower_rse").BY_NAME.CallBattleTowerFunc,
  "FireRed never binds natives_tower_rse")
check(not require("src.core.game3.capabilities").nativeAllowed({ version = "firered" }, "natives_frontier"),
  "the battleFrontier capability keeps natives_frontier off FireRed")

Runtime.getSession = prevGet
GameVersion.set("firered")
T.finish("emerald_frontier_test")

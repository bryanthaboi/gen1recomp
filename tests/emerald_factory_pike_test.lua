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
if not (has("data/generated/gba/frontier/trainers.lua") and has("data/generated/gba/rse/factory/manifest.lua")
    and has("data/generated/gba/rse/pike/manifest.lua") and has("data/generated/gba/rse/frontier/manifest.lua")) then
  print("emerald_factory_pike_test: skipped (no Emerald cache with rse/factory + rse/pike; set POKEPORT_IDENTITY)")
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
  gender = 0, bag = {}, flags = store.flags, vars = store.vars, map = "EM_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY" }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Rse = require("src.core.game3.rse.init")
local Factory = require("src.core.game3.rse.frontier.factory")
local Pike = require("src.core.game3.rse.frontier.pike")
local Natives = require("src.core.game3.scripting.natives")

local function S(name) return C.species.byName[name] end
local function MV(name) return C:require("moves", name) end
local function setVar(name, v) Rse.setVar(name, v, sess) end
local function ctxWith(vars)
  local ctx = { specialVars = {} }
  function ctx:getVar(id) return self.specialVars[id] or 0 end
  function ctx:setVar(id, v) self.specialVars[id] = v end
  for id, v in pairs(vars or {}) do Rse.setSpecialVar(ctx, id, v) end
  return ctx
end
local function result(ctx) return Rse.specialVar(ctx, Util.VAR_RESULT) end

local fm = Factory.manifest()
eq(table.concat(fm.requiredMoveCounts, ","), "3,3,3,2,2,2,2", "sRequiredMoveCounts (battle_factory.c:45)")
eq(#fm.moveStyles, 7, "seven factory move-style lists (battle_factory.c:113)")
eq(fm.moveStyles[1][1], MV("MOVE_SWORDS_DANCE"), "Total Preparation starts with Swords Dance")
eq(fm.moveStyles[7][5], MV("MOVE_WEATHER_BALL"), "Depends on the Battle's Flow ends with Weather Ball")
eq(#fm.fixedIvTable, 9, "sFixedIVTable rows plus the out-of-bounds row (battle_factory.c:750)")
eq(fm.fixedIvTable[9][1], 110, "row 8 reads sInitialRentalMonRanges' first byte")
eq(#fm.rentalRanges, 16, "sInitialRentalMonRanges has 16 rows (battle_factory.c:169)")
eq(fm.rentalRanges[1][1], 110, "level-50 challenge 1 rentals start at FRONTIER_MON_GRIMER")
eq(fm.rentalRanges[1][2], 199, "and end at FRONTIER_MON_FURRET_1")
eq(Factory.fixedIV(0, false), 3, "challenge 1 IVs are 3")
eq(Factory.fixedIV(0, true), 6, "the 7th trainer of challenge 1 uses 6")
eq(Factory.fixedIV(7, false), 31, "challenge 8 uses 31")
eq(Factory.fixedIV(8, false), 110, "challenge 9 reads past the table into random IVs")
eq(Factory.fixedIV(8, true), 0, "challenge 9's last battle reads 0")
eq(Factory.fixedIV(12, false), 31, "challenges past 9 clamp to the last row")
eq(Factory.moveBattleStyle(MV("MOVE_SWORDS_DANCE")), Factory.STYLE.PREPARATION, "Swords Dance is a preparation move")
eq(Factory.moveBattleStyle(MV("MOVE_TACKLE")), Factory.STYLE.NONE, "Tackle has no style")

setVar("VAR_FRONTIER_FACILITY", D.FACILITY.FACTORY)
setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES)
Util.newGame(sess)
local f = Util.frontier(sess)
f.lvlMode = D.LVL.L50
Util.set2(f.factoryWinStreaks, 0, 0, 12)
Util.set2(f.factoryRentsCount, 0, 0, 30)
Factory.init(sess)
eq(Util.get2(f.factoryWinStreaks, 0, 0), 0, "InitFactoryChallenge clears an inactive streak (battle_factory.c:208)")
eq(Util.get2(f.factoryRentsCount, 0, 0), 0, "and the rents count")
eq(f.rentalMons[1].monId, 0xFFFF, "rental slots start empty")
eq(Factory.pastRentalsRank(sess, 0, 0), 0, "no rents -> rank 0")
Util.set2(f.factoryRentsCount, 0, 0, 22)
eq(Factory.pastRentalsRank(sess, 0, 0), 2, "22 rents -> rank 2 (battle_factory.c:868)")
Util.set2(f.factoryRentsCount, 0, 0, 0)

Rng.SeedRng(0x5eed)
Factory.generateInitialRentalMons(sess)
local mons = D.pack("mons").mons
local rOk, uniq, items = true, {}, {}
local dupItem = false
for i = 1, 6 do
  local id = f.rentalMons[i].monId
  if not (id and id >= 110 and id <= 199) then rOk = false end
  local row = mons[id]
  uniq[row.species] = (uniq[row.species] or 0) + 1
  local it = D.heldItem(row.itemTableId)
  if it ~= 0 and items[it] then dupItem = true end
  items[it] = true
end
check(rOk, "six rentals drawn from the challenge-1 level-50 range")
check(not dupItem, "rentals never share a held item")

Factory.generateOpponentMons(sess)
eq(#sess.frontierTempParty, 3, "GenerateOpponentMons picks three mons")
local clash = false
for _, id in ipairs(sess.frontierTempParty) do
  if uniq[mons[id].species] then clash = true end
end
check(not clash, "opponent mons never share a species with the rentals (battle_factory.c:341)")
check(tonumber(sess.frontierOpponentA) and f.trainerIds[1] == sess.frontierOpponentA, "opponent trainer id recorded")
local ty = Factory.opponentMostCommonType(sess)
check(ty >= 0 and ty <= Factory.NUMBER_OF_MON_TYPES, "most-common type is a type id or NUMBER_OF_MON_TYPES")
local style = Factory.opponentBattleStyle(sess)
check(style >= 0 and style <= Factory.NUM_STYLES, "battle style is a FACTORY_STYLE_* or FACTORY_NUM_STYLES")

local sel = Factory.selectableMons(sess)
eq(#sel, 6, "six selectable rentals")
eq(sel[1].mon.level, 50, "level-50 rentals are level 50 (battle_factory_screen.c:1750)")
eq(sel[1].mon.ivs.atk, 3, "challenge-1 rentals carry 3 IVs")
eq(sel[1].mon.friendship, 0, "rentals have 0 friendship")
eq(sel[1].mon.otName, "BRENDAN", "rentals carry the player's OT")
local hasReturn = false
for _, s in ipairs(sel) do
  for _, m in ipairs(s.mon.moves) do if m == MV("MOVE_RETURN") then hasReturn = true end end
end
check(not hasReturn, "SetMonMoveAvoidReturn swaps Return for Frustration (battle_factory.c:913)")

Factory.copyMonsToPlayerParty(sess, sel, { 2, 4, 6 })
eq(#sess.party, 3, "three rentals copied to the party")
eq(sess.party[1].species, sel[2].mon.species, "first pick is party slot 1")
eq(f.rentalMons[1].monId, sel[2].monId, "rentalMons[0] records the rented monId")
eq(f.rentalMons[3].personality, sel[6].mon.personality, "rentalMons[2] records personality")
eq(f.rentalMons[2].ivs, sel[4].mon.ivs.atk, "rentalMons[1] records the ATK IV")

local enemy = Factory.fillTrainerParty(sess)
eq(#enemy, 3, "FillFactoryTrainerParty builds three mons")
eq(enemy[1].level, 50, "factory opponents are level 50")
eq(enemy[1].ivs.hp, 3, "opponent IVs follow the Battle Tower streak (battle_tower.c:1834)")
eq(enemy[1].species, mons[sess.frontierTempParty[1]].species, "opponent mons come from gFrontierTempParty")
sess.frontierEnemyParty = enemy
Factory.setRentalsToOpponentParty(sess)
eq(f.rentalMons[4].monId, sess.frontierTempParty[1], "SetRentalsToOpponentParty stores the opponent monIds")
eq(f.rentalMons[5].personality, enemy[2].personality, "and personalities")

local keep = {}
for i = 1, 3 do keep[i] = { species = sess.party[i].species, personality = sess.party[i].personality } end
sess.party[1].heldItem, sess.party[1].item = nil, nil
Factory.restorePlayerPartyHeldItems(sess)
eq(tonumber(sess.party[1].heldItem) or 0, D.heldItem(mons[f.rentalMons[1].monId].itemTableId),
  "RestorePlayerPartyHeldItems puts the rental's item back")
sess.party = {}
local ctx = ctxWith({ [Util.VAR_0x8005] = 0 })
Factory.setPlayerAndOpponentParties(ctx, sess)
local same = true
for i = 1, 3 do
  if sess.party[i].species ~= keep[i].species or sess.party[i].personality ~= keep[i].personality then same = false end
end
check(same, "factory_setparties 0 rebuilds the rental party from rentalMons (battle_factory.c:428)")
eq(sess.frontierEnemyParty[1].species, enemy[1].species, "and the last opponent party")
eq(sess.party[2].ivs.spd, f.rentalMons[2].ivs, "rebuilt rentals use the saved IV for every stat")

sess.party[1].species = enemy[2].species
check(Factory.alreadyHasSameSpecies(sess, 2, 2), "Swap_AlreadyHasSameSpecies spots a clash in another slot")
check(not Factory.alreadyHasSameSpecies(sess, 2, 1), "the slot being swapped away does not count")
Factory.copySwappedMonData(sess, 3, 1)
eq(sess.party[3].species, enemy[1].species, "CopySwappedMonData puts the enemy mon in the party")
eq(sess.party[3].friendship, 0, "the swapped mon has 0 friendship")
eq(f.rentalMons[3].monId, f.rentalMons[4].monId, "the rental slot takes the opponent's monId")

eq(Factory.aiFlags(sess), 0, "challenge 1 opponents run no AI scripts (battle_factory.c:904)")
Util.set2(f.factoryWinStreaks, 0, 0, 14)
local BP = require("src.core.game3.battle.profile")
eq(Factory.aiFlags(sess), BP.aiBit(BP.get(sess), "CHECK_BAD_MOVE"), "challenge 3 uses CHECK_BAD_MOVE only")
sess.frontierOpponentA = D.TRAINER_FRONTIER_BRAIN
check(Factory.aiFlags(sess) > BP.aiBit(BP.get(sess), "CHECK_BAD_MOVE"), "Noland uses the full AI")
local brain = Factory.fillBrainParty(sess)
eq(#brain, 3, "FillFactoryBrainParty builds three mons")
eq(brain[1].friendship, 0, "Noland's mons have 0 friendship (battle_factory.c:820)")
sess.frontierOpponentA = 0
Util.set2(f.factoryWinStreaks, 0, 0, 0)

local gctx = ctxWith({ [Util.VAR_0x8005] = Factory.DATA.WIN_STREAK_ACTIVE, [Util.VAR_0x8006] = 1 })
Factory.setData(gctx, sess)
Factory.getData(gctx, sess)
eq(result(gctx), 1, "FACTORY_DATA_WIN_STREAK_ACTIVE round-trips")
local sctx = ctxWith({ [Util.VAR_0x8005] = Factory.DATA.WIN_STREAK_SWAPS, [Util.VAR_0x8006] = 5 })
Factory.setData(sctx, sess)
eq(Util.get2(f.factoryRentsCount, 0, 0), 0, "rent count only moves after factory_setswapped (battle_factory.c:260)")
Factory.setPerformedSwap(sess)
Factory.setData(sctx, sess)
eq(Util.get2(f.factoryRentsCount, 0, 0), 5, "rent count set after a swap")

f.lvlMode = D.LVL.TENT
local Tents = require("src.core.game3.rse.frontier.tents")
Tents.generateRentalMons(sess)
local tsel = Factory.selectableMons(sess)
eq(tsel[1].mon.level, 30, "Slateport tent rentals are level 30 (battle_factory_screen.c:1784)")
eq(tsel[1].mon.ivs.hp, 0, "and carry 0 IVs")
Tents.generateOpponentMons(sess)
local tp = Factory.fillTrainerParty(sess)
eq(tp[1].level, 30, "tent opponents are level 30 (battle_tower.c:1891)")
eq(Factory.aiFlags(sess), 0, "tent battles run no AI scripts (battle_factory.c:893)")
f.lvlMode = D.LVL.L50

local pm = Pike.manifest()
eq(table.concat(pm.roomTypeHints, ","), "3,3,1,0,0,2,2,1,4", "sRoomTypeHints (battle_pike.c:517)")
eq(#pm.healBeforeQueen, 6, "sNumMonsToHealBeforePikeQueen has six rows")
eq(table.concat(pm.brainStreakAppearances[D.FACILITY.PIKE + 1], ","), "28,140,56,1", "Lucy appears at 28/140")
eq(#pm.npcTable, 25, "25 pike NPCs (battle_pike.c:267)")
eq(pm.npcTable[1].graphicsId, C:require("event_objects", "OBJ_EVENT_GFX_POKEFAN_F"), "first NPC is a Pokefan")
eq(#pm.npcSpeeches, 42, "42 NPC speeches")
eq(#pm.wildHeaders, 4, "four pike wild headers")
eq(pm.wildHeaders[1].land.rate, 10, "pike wild rooms use encounter rate 10")
eq(#pm.wildHeaders[1].land.slots, 12, "12 land slots")
eq(pm.wildMons[1][1][1].species, S("SPECIES_SEVIPER"), "level-50 pike wild mon 0 is Seviper")
eq(pm.wildMons[1][1][3].species, S("SPECIES_DUSCLOPS"), "set 1 mon 2 is Dusclops")
eq(pm.wildMons[2][4][3].moves[4], MV("MOVE_ENCORE"), "open-level Wobbuffet knows Encore")

setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PIKE)
local function healthy(name, lv)
  local m = D.createMon(S(name), lv or 50, 20, 7, 99)
  m.otName = "BRENDAN"
  return m
end
sess.party = { healthy("SPECIES_SWAMPERT"), healthy("SPECIES_BLAZIKEN"), healthy("SPECIES_SCEPTILE") }
local pf = Pike.frontier(sess)
Pike.init(sess)
eq(f.curChallengeBattleNum, 0, "InitPikeChallenge resets the battle number")
f.curChallengeBattleNum = 3

pf.pikeHintedRoomType = Pike.ROOM.STATUS
pf.pikeHintedRoomIndex = 1
pf.pikeHealingRoomsDisabled = 0
local seen, bad = {}, false
for seed = 1, 200 do
  Rng.SeedRng(seed)
  local c2 = ctxWith({ [0x8007] = 0 })
  local t = Pike.nextRoomType(c2, sess)
  seen[t] = true
  if t == Pike.ROOM.STATUS or t == Pike.ROOM.HEAL_PART or t == Pike.ROOM.BRAIN then bad = true end
end
check(not bad, "the other paths never share the hinted room's hint (battle_pike.c:1040)")
check(seen[Pike.ROOM.SINGLE_BATTLE] and seen[Pike.ROOM.WILD_MONS], "other room types still come up")
pf.pikeHealingRoomsDisabled = 1
pf.pikeHintedRoomType = Pike.ROOM.NPC
bad = false
for seed = 1, 200 do
  Rng.SeedRng(seed)
  local t = Pike.nextRoomType(ctxWith({ [0x8007] = 0 }), sess)
  if t == Pike.ROOM.HEAL_FULL or t == Pike.ROOM.HEAL_PART then bad = true end
end
check(not bad, "healing rooms are skipped after a full-health exit (battle_pike.c:1063)")
pf.pikeHealingRoomsDisabled = 0
pf.pikeHintedRoomType = Pike.ROOM.WILD_MONS
eq(Pike.nextRoomType(ctxWith({ [0x8007] = 1 }), sess), Pike.ROOM.WILD_MONS, "the hinted path is the hinted room")

for i = 1, 3 do sess.party[i].status = nil end
f.curChallengeBattleNum = 11
Rng.SeedRng(77)
check(Pike.tryInflictRandomStatus(sess), "TryInflictRandomStatus finds healthy mons")
local afflicted = 0
for i = 1, 3 do if Pike.hasAilment(sess.party[i]) then afflicted = afflicted + 1 end end
check(afflicted >= 1, "status room afflicts the party (" .. afflicted .. ")")
check(Pike.roomInflictedStatus(sess) ~= nil, "pike_getstatus reports the inflicted status")
check(Pike.typePreventsStatus(S("SPECIES_SKARMORY"), Pike.STATUS1.TOXIC_POISON), "Steel types dodge toxic")
check(Pike.typePreventsStatus(S("SPECIES_PIKACHU"), Pike.STATUS1.PARALYSIS), "Electric types dodge paralysis")
check(not Pike.typePreventsStatus(S("SPECIES_PIKACHU"), Pike.STATUS1.SLEEP), "nothing dodges sleep by type")

check(not Pike.isPartyFullHealed(sess), "an afflicted party is not fully healed")
sess.party[1].hp = 1
Rng.SeedRng(3)
local healed = Pike.healOneOrTwo(sess)
check(healed == 1 or healed == 2, "HealOneOrTwoMons heals one or two (" .. healed .. ")")
require("src.core.game3.party").healAll(sess.party)
check(Pike.isPartyFullHealed(sess), "a healed party is full health (battle_pike.c:1551)")
sess.party[2].hp = 0
sess.party[3].hp = 0
check(not Pike.atLeastTwoAliveMons(sess), "two fainted mons block the double battle room")
require("src.core.game3.party").healAll(sess.party)
sess.party[2].hp = sess.party[2].maxHp

f.curChallengeBattleNum = 5
Util.set1(f.pikeWinStreaks, 0, 27)
eq(Pike.queenFightType(sess, 0), Util.BRAIN.SILVER, "27 rooms cleared: Lucy is next (battle_pike.c:1515)")
eq(Pike.queenFightType(sess, 1), Util.BRAIN.NOT_READY, "the lookahead past Lucy is not ready")
Util.set1(f.pikeWinStreaks, 0, 26)
eq(Pike.queenFightType(sess, 1), Util.BRAIN.SILVER, "one room early the hint lady warns about Lucy")
Rng.SeedRng(9)
check(Pike.setHintedRoom(sess), "SetHintedRoom picks the Brain room when Lucy is next")
eq(pf.pikeHintedRoomType, Pike.ROOM.BRAIN, "hinted room type is PIKE_ROOM_BRAIN")
Util.set1(f.pikeWinStreaks, 0, 0)
pf.pikeHealingRoomsDisabled = 1
bad = false
for seed = 1, 100 do
  Rng.SeedRng(seed)
  Pike.setHintedRoom(sess)
  if pf.pikeHintedRoomType == Pike.ROOM.HEAL_FULL or pf.pikeHintedRoomType == Pike.ROOM.HEAL_PART
      or pf.pikeHintedRoomIndex > 2 then bad = true end
end
check(not bad, "no healing hint while healing rooms are disabled")
pf.pikeHealingRoomsDisabled = 0

eq(Pike.wildMonHeaderId(sess), 0, "wild header 0 for a fresh streak")
Util.set1(f.pikeWinStreaks, 0, 20 * 14 + 1)
eq(Pike.wildMonHeaderId(sess), 1, "wild header 1 past 280 rooms (battle_pike.c:1161)")
Util.set1(f.pikeWinStreaks, 0, 0)
local enc = Pike.tryGenerateWildMon(sess, { species = S("SPECIES_MILOTIC"), level = 5, personality = 1 }, false)
eq(enc.level, 46, "level-50 Milotic is 50 - 4 (battle_pike.c:1135)")
eq(enc.moves[4], MV("MOVE_SURF"), "Milotic knows Surf")
local enc2 = Pike.tryGenerateWildMon(sess, { species = S("SPECIES_DUSCLOPS"), level = 5, personality = 1 }, false)
eq(enc2.level, 45, "Dusclops is 50 - 5")
local got
for seed = 1, 400 do
  Rng.SeedRng(seed)
  got = Pike.standardWildEncounter(sess, 1, 1)
  if got then break end
end
check(got ~= nil, "the pike wild room rolls encounters")
check(got and (got.species == S("SPECIES_SEVIPER") or got.species == S("SPECIES_MILOTIC")
  or got.species == S("SPECIES_DUSCLOPS")), "pike wild mons come from gBattlePike_1")
check(got and got.moves and #got.moves == 4, "pike wild mons get their fixed moves")

f.selectedPartyMons = { 3, 1, 2, 0 }
sess.party = { healthy("SPECIES_SWAMPERT"), healthy("SPECIES_BLAZIKEN"), healthy("SPECIES_SCEPTILE") }
D.setHeldItem(sess.party[3], C.items.byName.ITEM_LEFTOVERS)
Pike.saveHeldItems(sess)
eq(pf.pikeHeldItemsBackup[1], C.items.byName.ITEM_LEFTOVERS, "SaveMonHeldItems follows selectedPartyMons")
D.setHeldItem(sess.party[3], 0)
Pike.restoreHeldItems(sess)
eq(tonumber(sess.party[3].heldItem) or 0, C.items.byName.ITEM_LEFTOVERS, "RestoreMonHeldItems puts it back")

Pike.rt(sess).roomType = Pike.ROOM.HEAL_FULL
Pike.setupRoomObjects(sess)
eq(Rse.var("VAR_OBJ_GFX_ID_0", sess), C:require("event_objects", "OBJ_EVENT_GFX_LINK_RECEPTIONIST"),
  "full-heal room shows the receptionist (battle_pike.c:568)")
Pike.rt(sess).roomType = Pike.ROOM.STATUS
Pike.rt(sess).statusMon = Pike.STATUSMON.DUSCLOPS
Pike.setupRoomObjects(sess)
eq(Rse.var("VAR_OBJ_GFX_ID_0", sess), C:require("event_objects", "OBJ_EVENT_GFX_GENTLEMAN"), "status room gentleman")
eq(Rse.var("VAR_OBJ_GFX_ID_1", sess), C:require("event_objects", "OBJ_EVENT_GFX_DUSCLOPS"), "status room Dusclops")
f.curChallengeBattleNum = 4
Pike.clearTrainerIds(sess)
Pike.rt(sess).roomType = Pike.ROOM.DOUBLE_BATTLE
Pike.setupRoomObjects(sess)
check(sess.frontierOpponentA ~= sess.frontierOpponentB, "double battle room picks two trainers")

local cur = Pike.curtainFrameMetatiles(0, sess)
eq(#cur, 12, "the curtain covers 3x4 metatiles (field_specials.c:3827)")
eq(cur[1].metatile, C:require("metatile_labels", "METATILE_BattlePike_CurtainFrames_Start"), "frame 0 starts the strip")
eq(cur[1].x, -1, "the curtain starts one tile left of the player")
eq(cur[1].y, -3, "and three tiles up")
eq(Pike.curtainFrameMetatiles(1, sess)[1].metatile - cur[1].metatile, 32, "each frame is 4 rows of 8 further on")

Natives.bind("emerald")
for _, name in ipairs({ "CallBattleFactoryFunction", "CallBattlePikeFunction", "CloseBattlePikeCurtain" }) do
  local id = C.specials.byName[name]
  check(id ~= nil and Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound on Emerald")
end
check(Rse.system("factory") == Factory and type(Factory.selectScreen) == "function", "the factory system is registered")
check(Rse.system("pike") == Pike and type(Pike.doSpecialBattle) == "function", "the pike system is registered")
local Screens = require("src.ui.game3.screens")
eq(Screens.path("factory_select", sess), "src.ui.game3.rse.factory_select", "factory select screen row")
eq(Screens.path("factory_swap", sess), "src.ui.game3.rse.factory_swap", "factory swap screen row")
local Caps = require("src.core.game3.capabilities")
check(not Caps.nativeAllowed({ version = "firered" }, "natives_factory"), "FireRed never binds natives_factory")
check(not Caps.nativeAllowed({ version = "firered" }, "natives_pike"), "FireRed never binds natives_pike")
Natives.bind("firered")

Runtime.getSession = prevGet
GameVersion.set("firered")
T.finish("emerald_factory_pike_test")

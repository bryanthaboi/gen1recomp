#!/usr/bin/env luajit
-- pokefirered/src/load_save.c:160, src/script_pokemon_util.c:152, src/trainer_tower.c:733

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

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Ops = require("src.core.game3.scripting.ops_a")
local Bag = require("src.core.game3.bag")
local Task = require("src.core.game3.task")
local Tower = require("src.core.game3.trainer_tower")
local TowerNatives = require("src.core.game3.scripting.natives_tower")

local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store }

local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function useSession(tbl)
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return tbl end,
    isActive = function() return true end,
  }
  return tbl
end

local function mon(species, level, opts)
  opts = opts or {}
  return {
    species = species,
    speciesId = species,
    level = level,
    hp = opts.hp or (level * 2),
    maxHp = level * 2,
    moves = { 33 },
    pp = { 35 },
    maxPp = { 35 },
    isEgg = opts.isEgg or nil,
    heldItem = opts.heldItem,
    nickname = opts.nickname,
  }
end

local function newSession(map)
  return useSession({
    name = "RED",
    gender = 0,
    money = 3000,
    trainerId = 4242,
    party = {},
    bag = Bag.new(),
    map = map or "FR_TRAINER_TOWER_LOBBY",
    x = 9,
    y = 7,
    modData = {},
  })
end

local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

local function special(ctx, id, adapters)
  return Ops.dispatch({ ctx = ctx, store = store, adapters = adapters or { log = function() end },
    setPc = function() end }, { op = "special", id = id })
end

-- pokefirered/asm/macros/trainer_tower.inc:2
local function towerFunc(ctx, index, adapters, temp1)
  setVar(ctx, 0x8004, index)
  if temp1 ~= nil then setVar(ctx, 0x4001, temp1) end
  special(ctx, Std.SPECIAL.CallTrainerTowerFunc, adapters)
  return getVar(ctx, 0x800D)
end

-- pokefirered/src/trainer_tower_sets.c:8956
local function towerMon(species, moveId)
  return {
    species = species,
    heldItem = 0,
    moves = { moveId, 0, 0, 0 },
    level = 1,
    ppBonuses = 0,
    hpEV = 0, attackEV = 0, defenseEV = 0, speedEV = 0, spAttackEV = 0, spDefenseEV = 0,
    otId = 0,
    hpIV = 8, attackIV = 8, defenseIV = 8, speedIV = 8, spAttackIV = 8, spDefenseIV = 8,
    abilityNum = 0,
    personality = 7,
    nickname = "",
    friendship = 0,
  }
end

local function towerTrainer(name, base)
  local mons = {}
  for i = 1, 6 do mons[i] = towerMon(base + i, 30 + i) end
  return { name = name, facilityClass = 44, textColor = 0, mons = mons }
end

-- pokefirered/src/trainer_tower.c:529 gTrainerTowerFloors
local function installFloorPack()
  local floors = {}
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    local rows = {}
    for i = 1, Tower.MAX_FLOORS do
      rows[i] = {
        id = i,
        floorIdx = Tower.MAX_FLOORS,
        challengeType = (mode == Tower.CHALLENGE_TYPE.MIXED) and Tower.CHALLENGE_TYPE.SINGLE or mode,
        prize = 0,
        trainers = {
          towerTrainer("ALPHA", 100),
          towerTrainer("BETA", 200),
          towerTrainer("GAMMA", 300),
        },
      }
    end
    floors[mode] = rows
  end
  Tower.setPack({ header = { numFloors = Tower.MAX_FLOORS, id = 1 }, floors = floors })
end

print("[test] 1. the five party and special-battle specials are bound with pret's ids")
-- pokefirered/data/specials.inc:50
eq(Std.SPECIAL.SavePlayerParty, 0x27, "SavePlayerParty")
eq(Std.SPECIAL.LoadPlayerParty, 0x28, "LoadPlayerParty")
eq(Std.SPECIAL.ChooseHalfPartyForBattle, 0x29, "ChooseHalfPartyForBattle")
-- pokefirered/data/specials.inc:247
eq(Std.SPECIAL.StartSpecialBattle, 0xEC, "StartSpecialBattle")
-- pokefirered/data/specials.inc:259
eq(Std.SPECIAL.ReducePlayerPartyToThree, 0xF8, "ReducePlayerPartyToThree")
for _, name in ipairs({ "SavePlayerParty", "LoadPlayerParty", "ChooseHalfPartyForBattle",
  "StartSpecialBattle", "ReducePlayerPartyToThree" }) do
  check(Natives.ALLOW["special:" .. Std.SPECIAL[name]] ~= nil, name .. " reaches a handler")
end

print("[test] 2. SavePlayerParty stashes all six slots and LoadPlayerParty gives them back")
local session = newSession("FR_SEVEN_ISLAND_HOUSE_ROOM1")
local ctx = newCtx()
for i = 1, 6 do session.party[i] = mon(i, 10 + i, { nickname = "SLOT" .. i }) end
special(ctx, Std.SPECIAL.SavePlayerParty)
eq(#session.party, 6, "the live party is untouched by the stash")
session.party[1].hp = 0
session.party[6] = nil
session.party[5] = nil
eq(#session.party, 4, "the party was cut down after the stash")
special(ctx, Std.SPECIAL.LoadPlayerParty)
eq(#session.party, 6, "LoadPlayerParty restored six slots")
eq(session.party[6].nickname, "SLOT6", "slot 6 came back")
eq(session.party[1].hp, 11 * 2, "the stashed copy was not aliased to the live mon")
session.party[3].hp = 1
eq((Tower.savedPlayerParty(session) or {})[3].hp, 13 * 2,
  "editing the live party does not edit the stash")

print("[test] 3. the stash survives a save and a reload mid-flow")
local Schema = require("src.core.game3.save_schema_firered")
local saved = Schema.toSaveTable(session)
local reloaded = useSession(Schema.fromSaveTable(saved))
reloaded.party = { mon(25, 5) }
ctx = newCtx()
special(ctx, Std.SPECIAL.LoadPlayerParty)
eq(#reloaded.party, 6, "the reloaded save still restores the six stashed mons")
eq(reloaded.party[4].nickname, "SLOT4", "the stashed nicknames survived the save")

print("[test] 4. ChooseHalfPartyForBattle offers only battle-eligible mons")
session = newSession("FR_SEVEN_ISLAND_HOUSE_ROOM1")
ctx = newCtx()
session.party = {
  mon(1, 20),
  mon(4, 20, { isEgg = true }),
  mon(7, 20, { hp = 0 }),
  mon(25, 20),
  mon(133, 20),
}
local opts = TowerNatives.chooseOptions()
-- pokefirered/include/constants/party_menu.h:59
eq(opts.menuType, 4, "PARTY_MENU_TYPE_CHOOSE_MULTIPLE_MONS")
eq(opts.count, 3, "the picker asks for three slots")
eq(opts.mode, "choose_multi", "the picker runs in multi select mode")
-- pokefirered/include/constants/party_menu.h:133
eq(opts.chooseMonsBattleType, 0, "CHOOSE_MONS_FOR_CABLE_CLUB_BATTLE")
eq(opts.eligible, nil, "the eligibility rule is the menu's own, not a list the tower publishes")
local PartyMenu = require("src.ui.game3.party_menu")
opts.session = session
opts.onClose = function() end
PartyMenu.show(session.party, nil, opts)
-- pokefirered/src/party_menu.c:5674 GetBattleEntryEligibility
local function firstAction(slot) return (PartyMenu.multiActions(slot) or {})[1] end
eq(firstAction(1), "ENTER", "slot 1 can enter")
eq(firstAction(2), "SUMMARY", "the egg cannot enter")
eq(firstAction(3), "SUMMARY", "the fainted mon cannot enter")
eq(firstAction(4), "ENTER", "slot 4 can enter")
eq(firstAction(5), "ENTER", "slot 5 can enter")
PartyMenu.close()

print("[test] 5. a multi select pick fills gSelectedOrderFromParty in pick order")
local passedOpts = nil
local adaptersPick = {
  log = function() end,
  chooseParty = function(o, done)
    passedOpts = o
    done({ 5, 1 })
  end,
}
special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle, adaptersPick)
check(passedOpts ~= nil and passedOpts.count == 3, "the seam was called with the count option")
local order = Tower.selectedOrder(session)
eq(order[1], 5, "first pick is slot 5")
eq(order[2], 1, "second pick is slot 1")
eq(order[3], 0, "the third slot stays empty")
eq(getVar(ctx, 0x800D), 1, "VAR_RESULT = TRUE when the player confirmed")

print("[test] 6. ReducePlayerPartyToThree keeps the picked mons in the picked order")
special(ctx, Std.SPECIAL.SavePlayerParty)
special(ctx, Std.SPECIAL.ReducePlayerPartyToThree)
eq(#session.party, 2, "two picks leave a two mon party")
eq(session.party[1].species, 133, "the first pick leads")
eq(session.party[2].species, 1, "the second pick follows")
special(ctx, Std.SPECIAL.LoadPlayerParty)
eq(#session.party, 5, "LoadPlayerParty gave the whole party back")
eq(session.party[2].isEgg, true, "the egg came back with it")

print("[test] 7. cancelling the picker sets VAR_RESULT = FALSE and picks nothing")
ctx = newCtx()
special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle,
  { log = function() end, chooseParty = function(_, done) done(nil) end })
eq(getVar(ctx, 0x800D), 0, "VAR_RESULT = FALSE on cancel")
eq(Tower.selectedOrder(session)[1], 0, "the order was cleared")
special(ctx, Std.SPECIAL.ReducePlayerPartyToThree)
eq(#session.party, 0, "pret empties the party when no slot was chosen")
special(ctx, Std.SPECIAL.LoadPlayerParty)
eq(#session.party, 5, "and the stash puts it back")

print("[test] 8. a single select host still yields a legal one mon order")
ctx = newCtx()
special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle,
  { log = function() end, chooseParty = function(_, done) done(3) end })
eq(Tower.selectedOrder(session)[1], 4, "slot 4 (0 based 3) became the only pick")
eq(getVar(ctx, 0x800D), 1, "VAR_RESULT = TRUE for a one mon pick")

print("[test] 9. an ineligible pick is refused the way the menu refuses it")
ctx = newCtx()
special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle,
  { log = function() end, chooseParty = function(_, done) done({ 2, 3 }) end })
eq(Tower.selectedOrder(session)[1], 0, "the egg and the fainted mon were dropped")
eq(getVar(ctx, 0x800D), 0, "VAR_RESULT = FALSE when nothing eligible was picked")

print("[test] 10. the picker blocks the script until the host closes it")
ctx = newCtx()
local pending = nil
local yielded = special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle,
  { log = function() end, chooseParty = function(_, done) pending = done end })
check(yielded, "the special yielded while the party menu is open")
eq(ctx.status, "waiting", "the script is waiting")
eq(getVar(ctx, 0x800D), 0, "VAR_RESULT is not written before the pick")
pending({ 1 })
check(ctx.nativePoll(), "the poll finished once the host closed the menu")
eq(getVar(ctx, 0x800D), 1, "VAR_RESULT was written on close")

print("[test] 11. DoTrainerTowerBattle builds the floor party pret builds")
installFloorPack()
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
Task.clear()
session.party = { mon(1, 24), mon(4, 31), mon(7, 18) }
setVar(ctx, 0x8005, Tower.CHALLENGE_TYPE.SINGLE)
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, { log = function() end })
local seenFoe, seenOpts = nil, nil
local battleAdapters = {
  log = function() end,
  startTrainerBattle = function(foe, done, o)
    seenFoe, seenOpts = foe, o
    done("win")
  end,
}
eq(towerFunc(ctx, Tower.FUNC.DO_BATTLE, battleAdapters, 0), 1,
  "a won tower battle reports B_OUTCOME_WON")
check(seenFoe ~= nil, "the battle reached the host seam")
eq(#seenFoe.party, 2, "a singles floor sends two mons")
-- pokefirered/src/trainer_tower.c:401 sSingleBattleChallengeMonIdxs[0] = {0, 2}
eq(seenFoe.party[1].species, 101, "floor 1 mon index 0")
eq(seenFoe.party[2].species, 103, "floor 1 mon index 2")
-- pokefirered/src/trainer_tower.c:1026 GetPartyMaxLevel
eq(seenFoe.party[1].level, 31, "the floor mons match the player's top level")
eq(seenFoe.party[2].level, 31, "both of them")
eq(seenOpts.double, false, "a singles floor is not a double battle")
eq(seenOpts.trainerId, 0, "gTrainerBattleOpponent_A = 0")
-- pokefirered/src/trainer_tower.c:717 CB2_EndTrainerTowerBattle
eq(seenOpts.noWhiteout, true, "a tower loss goes through the script, not the white out")
eq(seenOpts.trainerTower, true, "the battle is flagged BATTLE_TYPE_TRAINER_TOWER")

print("[test] 12. the knockout and doubles floors pick the mons pret picks")
session = newSession("FR_TRAINER_TOWER_3F")
ctx = newCtx()
session.party = { mon(1, 40) }
setVar(ctx, 0x8005, Tower.CHALLENGE_TYPE.KNOCKOUT)
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, { log = function() end })
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR, { log = function() end })
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR, { log = function() end })
towerFunc(ctx, Tower.FUNC.DO_BATTLE, battleAdapters, 1)
eq(#seenFoe.party, 1, "a knockout battle is one mon")
-- pokefirered/src/trainer_tower.c:427 sKnockoutChallengeMonIdxs[2] = {2, 3, 1}
eq(seenFoe.party[1].species, 204, "floor 3, trainer 2, mon index 3")
session = newSession("FR_TRAINER_TOWER_2F")
ctx = newCtx()
session.party = { mon(1, 40), mon(4, 12) }
setVar(ctx, 0x8005, Tower.CHALLENGE_TYPE.DOUBLE)
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, { log = function() end })
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR, { log = function() end })
towerFunc(ctx, Tower.FUNC.DO_BATTLE, battleAdapters, 0)
eq(#seenFoe.party, 2, "a doubles floor sends one mon from each trainer")
-- pokefirered/src/trainer_tower.c:414 sDoubleBattleChallengeMonIdxs[1] = {1, 3}
eq(seenFoe.party[1].species, 102, "trainer 1 mon index 1")
eq(seenFoe.party[2].species, 204, "trainer 2 mon index 3")
eq(seenOpts.double, true, "a doubles floor is a double battle")

print("[test] 13. a lost tower battle routes B_OUTCOME_LOST back to the script")
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
session.party = { mon(1, 20) }
setVar(ctx, 0x8005, Tower.CHALLENGE_TYPE.SINGLE)
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, { log = function() end })
eq(towerFunc(ctx, Tower.FUNC.DO_BATTLE, {
  log = function() end,
  startTrainerBattle = function(_, done) done("lose") end,
}, 0), 2, "a lost tower battle reports B_OUTCOME_LOST")
eq(Tower.record(session).floorsCleared, 0, "a loss clears no floor")

print("[test] 14. the battle blocks the script until the battle ends")
ctx = newCtx()
local finishBattle = nil
yielded = towerFunc(ctx, Tower.FUNC.DO_BATTLE, {
  log = function() end,
  startTrainerBattle = function(_, done) finishBattle = done end,
}, 0)
eq(ctx.status, "waiting", "ttower_dobattle waits on the battle")
finishBattle("win")
check(ctx.nativePoll(), "the poll finished with the battle")
eq(getVar(ctx, 0x800D), 1, "VAR_RESULT = B_OUTCOME_WON after the battle")

print("[test] 15. with no floor data in the cache the tower loses instead of cheating")
Tower.setPack(nil)
TowerNatives._logged = {}
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
session.party = { mon(1, 20) }
setVar(ctx, 0x8005, Tower.CHALLENGE_TYPE.SINGLE)
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, { log = function() end })
local reached = false
eq(towerFunc(ctx, Tower.FUNC.DO_BATTLE, {
  log = function() end,
  startTrainerBattle = function() reached = true end,
}, 0), 2, "no floor trainers reports B_OUTCOME_LOST")
check(not reached, "and starts no battle at all")
check(TowerNatives._logged["DoTrainerTowerBattle has no floor trainers in this cache"] == true,
  "the missing gTrainerTowerFloors table is logged once")

print("[test] 16. StartSpecialBattle fights the e-reader trainer when the save holds one")
session = newSession("FR_SEVEN_ISLAND_HOUSE_ROOM2")
ctx = newCtx()
session.party = { mon(1, 30) }
TowerNatives._logged = {}
-- pokefirered/data/maps/SevenIsland_House_Room1/scripts.inc:9
special(ctx, Std.SPECIAL.ValidateEReaderTrainer, { log = function() end })
eq(getVar(ctx, 0x800D), 1, "a clean save has no e-reader trainer, so the door stays shut")
session.ereaderTrainer = { name = "EMPTY" }
special(ctx, Std.SPECIAL.ValidateEReaderTrainer, { log = function() end })
eq(getVar(ctx, 0x800D), 1, "a record with no party is an all-zero record")
eq(session.ereaderTrainer, nil, "and ClearEReaderTrainer wiped it")
setVar(ctx, 0x8004, 2)
special(ctx, Std.SPECIAL.StartSpecialBattle, { log = function() end })
eq(getVar(ctx, 0x800D), 2,
  "an empty e-reader slot reports B_OUTCOME_LOST instead of hanging on waitstate")
check(TowerNatives._logged["StartSpecialBattle 2 has no opponent data in this save"] == true,
  "the empty e-reader slot is logged once")
session.ereaderTrainer = {
  name = "READER",
  facilityClass = 44,
  party = { towerMon(150, 94), towerMon(151, 60), towerMon(144, 58) },
}
seenFoe, seenOpts = nil, nil
ctx = newCtx()
setVar(ctx, 0x8004, 2)
special(ctx, Std.SPECIAL.StartSpecialBattle, battleAdapters)
check(seenFoe ~= nil, "the e-reader battle reached the host seam")
eq(#seenFoe.party, 3, "an e-reader trainer brings three mons")
eq(seenFoe.party[1].species, 150, "the first e-reader mon")
eq(seenFoe.party[1].level, 1, "e-reader mons keep their own level")
eq(seenOpts.eReader, true, "BATTLE_TYPE_EREADER_TRAINER")
eq(getVar(ctx, 0x800D), 1, "the outcome reached VAR_RESULT")
ctx = newCtx()
special(ctx, Std.SPECIAL.ValidateEReaderTrainer, { log = function() end })
eq(getVar(ctx, 0x800D), 0, "a valid card record opens the Seven Island door")

print("[test] 17. the secret base case copies the held items into the stash first")
session = newSession("FR_PALLET_TOWN")
ctx = newCtx()
session.party = { mon(1, 10, { heldItem = 0 }), mon(4, 10, { heldItem = 0 }) }
special(ctx, Std.SPECIAL.SavePlayerParty)
session.party[1].heldItem = 172
session.party[2].heldItem = 173
setVar(ctx, 0x8004, 1)
special(ctx, Std.SPECIAL.StartSpecialBattle, { log = function() end })
-- pokefirered/src/battle_tower.c:917
eq((Tower.savedPlayerParty(session) or {})[1].heldItem, 172, "slot 1 held item reached the stash")
eq((Tower.savedPlayerParty(session) or {})[2].heldItem, 173, "slot 2 held item reached the stash")
eq(getVar(ctx, 0x800D), 2, "and with no secret base trainer the battle reports B_OUTCOME_LOST")

print("[test] 18. the tower flag survives the adapters and the bridge and reaches the engine")
local captured = nil
package.loaded["src.core.game3.battle_bridge"] = nil
local realBridge = require("src.core.game3.battle_bridge")
local bridgeStart = realBridge.start
realBridge.start = function(_, _, _, o) captured = o end
local Adapters = require("src.core.game3.scripting.adapters")
local host = Adapters.host({}, { session = session }, {})
-- pokefirered/src/trainer_tower.c:735 BATTLE_TYPE_TRAINER_TOWER
host.startTrainerBattle({ party = {}, trainerId = 0, trainerName = "ALBERTO", trainerPicId = 44 },
  function() end, { trainerId = 0, trainerTower = true, noWhiteout = true })
realBridge.start = bridgeStart
check(captured ~= nil, "the tower battle reached BattleBridge.start")
eq(captured and captured.trainerTower, true, "adapters.startTrainerBattle forwards trainerTower")
eq(captured and captured.trainerName, "ALBERTO", "and the tower opponent's name")
eq(captured and captured.trainerPicId, 44, "and its facility-class pic")

local Battle = require("src.core.game3.battle")
local towerMons = { { species = 129, level = 30, hp = 40, maxHp = 40, moves = { 33 }, pp = { 35 } } }
Battle.start({
  headless = true,
  wild = false,
  trainerId = 0,
  trainerTower = true,
  trainerName = "ALBERTO",
  trainerPicId = 44,
  playerParty = { { species = 1, level = 30, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
  foe = towerMons[1],
  foeParty = towerMons,
})
local bst = Battle.getState()
check(bst ~= nil and bst.trainerTower == true, "battle/init.lua kept BATTLE_TYPE_TRAINER_TOWER")
eq(bst and bst.trainerName, "ALBERTO", "the battle shows the tower trainer, not gTrainers[0]")
eq(bst and bst.trainerClassName, nil, "and no gTrainers[0] class name")
eq(bst and bst.trainerPicId, 44, "and the facility-class front sprite")
local BattleBg = require("src.core.game3.battle.bg")
-- pokefirered/src/battle_bg.c:1048 GetBattleTerrainOverride
eq(BattleBg.terrainId(), BattleBg.TERRAIN.LINK, "a tower battle uses TERRAIN_LINK")
if Battle.endBattle then pcall(Battle.endBattle) end

Task.clear()
Tower.resetPack()

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[pass] trainer tower party and battles")

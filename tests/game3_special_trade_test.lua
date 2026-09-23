#!/usr/bin/env luajit

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
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = { store = store, map = "FR_ROUTE_2_HOUSE", party = {}, name = "RED", trainerId = 4242 }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")

local okTrade, Trade = pcall(require, "src.core.game3.scripting.natives_trade")
local okDaycare, Daycare = pcall(require, "src.core.game3.scripting.natives_daycare")
check(okTrade, "src/core/game3/scripting/natives_trade.lua loads")
check(okDaycare, "src/core/game3/scripting/natives_daycare.lua loads")
if not (okTrade and okDaycare) then finish() end

local VAR_RESULT = 0x800D
local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005

local function newCtx()
  return { specialVars = {}, stringVars = { [1] = "", [2] = "", [3] = "" } }
end

local function getVar(ctx, id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

print("[test] 1. the four trade ids and the sixteen daycare ids are bound")
local IDS = {
  GetInGameTradeSpeciesInfo = 0xFC, CreateInGameTradePokemon = 0xFD,
  DoInGameTradeScene = 0xFE, GetTradeSpecies = 0xFF,
  GetDaycareMonNicknames = 0xB5, RejectEggFromDayCare = 0xB7,
  GiveEggFromDaycare = 0xB8, SetDaycareCompatibilityString = 0xB9,
  StoreSelectedPokemonInDaycare = 0xBB, ChooseSendDaycareMon = 0xBC,
  ShowDaycareLevelMenu = 0xBD, GetNumLevelsGainedFromDaycare = 0xBE,
  GetDaycareCost = 0xBF, TakePokemonFromDaycare = 0xC0,
  GetDaycarePokemonCount = 0x15F, PutMonInRoute5Daycare = 0x176,
  GetCostToWithdrawRoute5DaycareMon = 0x177, IsThereMonInRoute5Daycare = 0x178,
  GetNumLevelsGainedForRoute5DaycareMon = 0x179, TakePokemonFromRoute5Daycare = 0x17A,
}
for name, id in pairs(IDS) do
  eq(Std.SPECIAL[name], id, "Std.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
end
local moduleNames = {}
for _, n in ipairs(Natives.MODULE_NAMES) do moduleNames[n] = true end
check(moduleNames["natives_trade"], "discovery found natives_trade with no natives.lua edit")
check(moduleNames["natives_daycare"], "discovery found natives_daycare with no natives.lua edit")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] game3_special_trade_test needs species data: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

print("[test] 2. the in-game trade table matches pokefirered/src/data/ingame_trades.h")
eq(Trade.COUNT, 9, "nine in-game trades")
local mimien = Trade.TRADES[0]
eq(mimien.nickname, "MIMIEN", "INGAME_TRADE_MR_MIME nickname")
eq(mimien.species, 122, "INGAME_TRADE_MR_MIME offers MR. MIME")
eq(mimien.requestedSpecies, 63, "INGAME_TRADE_MR_MIME wants ABRA")
eq(mimien.otId, 1985, "INGAME_TRADE_MR_MIME otId")
eq(mimien.personality, 0x00009cae, "INGAME_TRADE_MR_MIME personality")
eq(Trade.TRADES[1].heldItem, 131, "ZYNX holds ITEM_FAB_MAIL")
eq(Trade.TRADES[2].species, 29, "the FireRed Nidoran trade offers NIDORAN_F")
eq(Trade.TRADES[2].requestedSpecies, 32, "and wants NIDORAN_M")
eq(Trade.TRADES[5].requestedSpecies, 55, "the FireRed Lickitung trade wants GOLDUCK")
eq(Trade.TRADES[6].abilityNum, 1, "ESPHERE uses the second ability slot")
eq(Trade.TRADES[8].nickname, "SEELOR", "INGAME_TRADE_SEEL nickname")

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Experience = require("src.core.game3.battle.experience")
local SummaryData = require("src.core.game3.summary_data")

local function makeMon(species, level, extra)
  local Party = require("src.core.game3.party")
  local scratch = { party = {}, name = "RED", trainerId = 4242 }
  local ok, _, mon = Party.giveMon(scratch, species, level, "")
  check(ok, "built a level " .. level .. " species " .. species .. " for the test")
  for k, v in pairs(extra or {}) do mon[k] = v end
  return mon
end

print("[test] 3. GetInGameTradeSpeciesInfo buffers both names and returns the wanted species")
local ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
local _, requested = Natives.special(ctx, Std.SPECIAL.GetInGameTradeSpeciesInfo, nil)
eq(requested, 63, "VAR_RESULT is SPECIES_ABRA")
eq(ctx.stringVars[1], Pokemon.name(63), "STR_VAR_1 is the requested species name")
eq(ctx.stringVars[2], Pokemon.name(122), "STR_VAR_2 is the offered species name")

print("[test] 4. GetTradeSpecies reads the chosen party slot and rejects eggs")
session.party = { makeMon(63, 18), makeMon(25, 12) }
ctx = newCtx()
setVar(ctx, VAR_0x8005, 0)
local _, species = Natives.special(ctx, Std.SPECIAL.GetTradeSpecies, nil)
eq(species, 63, "slot 0 is the ABRA the trade wants")
setVar(ctx, VAR_0x8005, 1)
_, species = Natives.special(ctx, Std.SPECIAL.GetTradeSpecies, nil)
eq(species, 25, "slot 1 is the PIKACHU")
session.party[2].isEgg = true
_, species = Natives.special(ctx, Std.SPECIAL.GetTradeSpecies, nil)
eq(species, 0, "an egg reads back as SPECIES_NONE")
session.party[2].isEgg = nil

print("[test] 5. CreateInGameTradePokemon builds the cart's mon at the sent mon's level")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
setVar(ctx, VAR_0x8005, 0)
Natives.special(ctx, Std.SPECIAL.CreateInGameTradePokemon, nil)
local offered = Trade._offered
check(offered ~= nil, "the offered mon exists")
eq(offered.species, 122, "the offered mon is MR. MIME")
eq(offered.level, 18, "it arrives at the level of the mon being sent")
eq(offered.nickname, "MIMIEN", "it carries the cart nickname")
eq(offered.otId, 1985, "it carries the cart otId")
eq(offered.otName, "REYLEY", "it carries the cart OT name")
eq(offered.personality, 0x00009cae, "it carries the cart personality")
eq(offered.ivs.hp, 20, "IV hp from the table")
eq(offered.ivs.spd, 22, "IV spDef from the table")
eq(offered.metLocation, 0xFE, "met location is METLOC_IN_GAME_TRADE")
local expected = Pokemon.calcStats(122, 18, offered.ivs, offered.evs, offered.personality)
eq(offered.maxHp, expected.maxHp, "stats recalculated from the fixed IVs")

print("[test] 6. DoInGameTradeScene swaps the mon after the cart's frames")
local tradeTargetCalls = {}
local Evolution = require("src.core.game3.evolution")
local realTradeTarget = Evolution.tradeTarget
Evolution.tradeTarget = function(mon, sess)
  tradeTargetCalls[#tradeTargetCalls + 1] = mon
  return realTradeTarget(mon, sess)
end

ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
setVar(ctx, VAR_0x8005, 0)
Natives.special(ctx, Std.SPECIAL.CreateInGameTradePokemon, nil)
Natives.special(ctx, Std.SPECIAL.DoInGameTradeScene, nil)
local task = ctx.stateWait
check(type(task) == "function", "DoInGameTradeScene armed a waitstate task")
eq(session.party[1].species, 63, "the ABRA is still in the party while the fade runs")
local frames = 0
while frames < 2000 and not task() do frames = frames + 1 end
check(frames > 60, "the scene held for at least the cart's fade plus hold, held " .. frames)
eq(session.party[1].species, 122, "the party slot now holds MR. MIME")
eq(session.party[1].friendship, 70, "a traded mon starts at 70 friendship")
check(session.dex and session.dex.owned and session.dex.owned[122],
  "the received species is registered as owned")
eq(#tradeTargetCalls, 1, "the trade evolution gate ran once")
eq(tradeTargetCalls[1], session.party[1], "it ran on the mon that landed in the party")
eq(ctx.stringVars[1], "MIMIEN", "STR_VAR_1 is the received mon's nickname")

print("[test] 7. the same gate evolves a mon that does trade-evolve")
Evolution.tradeTarget = realTradeTarget
local kadabra = makeMon(64, 20)
session.dex = session.dex or { seen = {}, owned = {} }
session.dex.national = true
local target = Evolution.tradeTarget(kadabra, session)
eq(target, 65, "KADABRA's trade target is ALAKAZAM")
Trade.tryTradeEvolution(kadabra, session)
eq(kadabra.species, 65, "Trade.tryTradeEvolution applied it headless")

print("[test] 8. the Route 5 daycare and the Four Island daycare are separate stores")
session.party = { makeMon(19, 5), makeMon(16, 8) }
session.modData = nil
session.daycare = nil
session.route5Daycare = nil
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.PutMonInRoute5Daycare, nil)
eq(#session.party, 1, "the party lost the deposited mon")
eq(session.party[1].species, 16, "and compacted")
local _, there = Natives.special(newCtx(), Std.SPECIAL.IsThereMonInRoute5Daycare, nil)
eq(there, 1, "IsThereMonInRoute5Daycare is TRUE")
local _, fourIsland = Natives.special(newCtx(), Std.SPECIAL.GetDaycarePokemonCount, nil)
eq(fourIsland, 0, "the Four Island daycare is still empty")
local _, state = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(state, 0, "GetDaycareState is DAYCARE_NO_MONS")

print("[test] 9. levels gained and the cost follow pret's 100 + 100 per level")
local r5 = Daycare.route5Of(session)
check(r5.mon ~= nil, "the Route 5 slot holds the mon")
eq(r5.mon.level, 5, "deposited at level 5")
local growth = Experience.growthRate(r5.mon)
local stepsFor3 = SummaryData.expForLevel(growth, 8) - SummaryData.expForLevel(growth, 5)
r5.steps = stepsFor3
ctx = newCtx()
local _, gained = Natives.special(ctx, Std.SPECIAL.GetNumLevelsGainedForRoute5DaycareMon, nil)
eq(gained, 3, "three levels gained from the accumulated steps")
eq(ctx.stringVars[2], "3", "STR_VAR_2 carries the level count")
ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.GetCostToWithdrawRoute5DaycareMon, nil)
eq(getVar(ctx, VAR_0x8005), 400, "the cost is 100 + 100 * 3")
eq(Daycare.cost(r5.mon, 0), 100, "no levels gained costs the flat 100")

print("[test] 10. taking the Route 5 mon back levels it up and returns the species")
ctx = newCtx()
local _, taken = Natives.special(ctx, Std.SPECIAL.TakePokemonFromRoute5Daycare, nil)
eq(taken, 19, "TakePokemonFromRoute5Daycare returns the species")
eq(#session.party, 2, "the mon is back in the party")
eq(session.party[2].level, 8, "it came back three levels higher")
eq(session.party[2].hp, session.party[2].maxHp, "and at full HP, as BoxMonToMon leaves it")
local _, stillThere = Natives.special(newCtx(), Std.SPECIAL.IsThereMonInRoute5Daycare, nil)
eq(stillThere, 0, "the Route 5 slot is empty again")

print("[test] 11. the Four Island daycare holds two and shifts on withdrawal")
session.party = { makeMon(19, 5), makeMon(16, 8), makeMon(10, 3) }
session.modData = nil
session.daycare = nil
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
local _, count = Natives.special(newCtx(), Std.SPECIAL.GetDaycarePokemonCount, nil)
eq(count, 2, "two mons in the Four Island daycare")
local _, twoState = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(twoState, 3, "GetDaycareState is DAYCARE_TWO_MONS")
eq(#session.party, 1, "only the third mon is left in the party")

ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.GetDaycareMonNicknames, nil)
eq(ctx.stringVars[1], Pokemon.name(19), "STR_VAR_1 is the first daycare mon")
eq(ctx.stringVars[2], Pokemon.name(16), "STR_VAR_2 is the second daycare mon")
eq(ctx.stringVars[3], "RED", "STR_VAR_3 is the first mon's OT name")

ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
local _, first = Natives.special(ctx, Std.SPECIAL.TakePokemonFromDaycare, nil)
eq(first, 19, "the first slot came back")
local dc = Daycare.stateOf(session)
eq(dc[1] and dc[1].species, 16, "slot 2 shifted down into slot 1")
check(dc[2] == nil, "slot 2 is empty")
local _, oneState = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(oneState, 2, "GetDaycareState is DAYCARE_ONE_MON")

print("[test] 12. the level menu rows carry the nickname and the level after steps")
dc = Daycare.stateOf(session)
dc.steps[1] = SummaryData.expForLevel(Experience.growthRate(dc[1]), 11)
  - SummaryData.expForLevel(Experience.growthRate(dc[1]), 8)
local rows = Daycare.levelMenuRows(dc)
eq(#rows, 3, "three rows, two mons plus EXIT")
eq(rows[1].text, Pokemon.name(16), "row 1 names the deposited mon")
eq(rows[1].tail, "Lv11", "row 1 shows the level the steps have earned")
eq(rows[3].text, "EXIT", "row 3 is EXIT")
eq(Daycare.LEVEL_MENU_LAYOUT.left, 12, "the window sits at tilemapLeft 12")
eq(Daycare.LEVEL_MENU_LAYOUT.width, 17, "and is 17 tiles wide")

print("[test] 13. the compatibility string picks pret's four lines")
local function pair(a, b, idA, idB)
  local left = makeMon(a, 20, { otId = idA })
  local right = makeMon(b, 20, { otId = idB })
  session.daycare = { left, right, steps = { 0, 0 } }
  return Daycare.compatibility(session.daycare)
end
eq(pair(132, 132, 1, 2), Daycare.PARENTS_INCOMPATIBLE, "two DITTO cannot breed")
eq(pair(144, 145, 1, 2), Daycare.PARENTS_INCOMPATIBLE, "two undiscovered-group legendaries cannot breed")
local sameSpeciesDifferentTrainer = pair(19, 19, 1, 2)
check(sameSpeciesDifferentTrainer == Daycare.PARENTS_MAX_COMPATIBILITY
  or sameSpeciesDifferentTrainer == Daycare.PARENTS_INCOMPATIBLE,
  "same species, different trainers is MAX unless the genders collide, got "
  .. tostring(sameSpeciesDifferentTrainer))
eq(Daycare.compatibilityText(Daycare.PARENTS_MAX_COMPATIBILITY),
  "The two seem to get along\nvery well.", "the MAX line")
eq(Daycare.compatibilityText(Daycare.PARENTS_INCOMPATIBLE),
  "The two prefer to play with other\nPOKéMON than each other.", "the incompatible line")

ctx = newCtx()
session.daycare = { makeMon(132, 20, { otId = 1 }), makeMon(132, 20, { otId = 2 }), steps = { 0, 0 } }
Natives.special(ctx, Std.SPECIAL.SetDaycareCompatibilityString, nil)
eq(ctx.stringVars[4], "The two prefer to play with other\nPOKéMON than each other.",
  "SetDaycareCompatibilityString writes gStringVar4")

print("[test] 14. ShowFieldMessageStringVar4 puts gStringVar4 on screen")
local shown = nil
local adapters = { openMessageStay = function(text) shown = text end }
Natives.special(ctx, Std.SPECIAL.ShowFieldMessageStringVar4, adapters)
eq(shown, ctx.stringVars[4], "the compatibility line reached the message box")
check(ctx.messageOpen == true, "the field message box is open")

print("[test] 15. GiveEggFromDaycare hands the egg over and RejectEggFromDayCare clears it")
session.party = { makeMon(19, 5) }
session.daycare = { makeMon(132, 20), makeMon(19, 20), steps = { 0, 0 }, eggPending = true }
local _, eggState = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(eggState, 1, "GetDaycareState is DAYCARE_EGG_WAITING")
-- pokefirered/src/daycare.c:1133
Natives.special(newCtx(), Std.SPECIAL.GiveEggFromDaycare, nil)
local partyCount, eggCount = 0, 0
for i = 1, 6 do
  local mon = session.party[i]
  if mon then
    partyCount = partyCount + 1
    if mon.isEgg then eggCount = eggCount + 1 end
  end
end
eq(partyCount, 2, "the egg joined the party")
eq(eggCount, 1, "and it is an egg")
local _, afterGive = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(afterGive, 3, "the pending egg is cleared, back to DAYCARE_TWO_MONS")
session.daycare.offspringPersonality = 0x1234
local _, pendingAgain = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(pendingAgain, 1, "a non-zero offspringPersonality is an egg waiting")
Natives.special(newCtx(), Std.SPECIAL.RejectEggFromDayCare, nil)
eq(session.daycare.offspringPersonality, 0, "RejectEggFromDayCare zeroes offspringPersonality")
local _, afterReject = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(afterReject, 3, "and the daycare is back to DAYCARE_TWO_MONS")

print("[test] 16. both daycare stores survive a save round trip")
local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
session = Schema.newGame({})
session.store = store
session.party = { makeMon(19, 5), makeMon(16, 9) }
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.PutMonInRoute5Daycare, nil)
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
eq(#session.party, 0, "both mons left the party")
local reloaded = Schema.fromSaveTable(SaveData.decode(SaveData.encode(Schema.toSaveTable(session))))
reloaded.store = store
session = reloaded
local _, thereAfter = Natives.special(newCtx(), Std.SPECIAL.IsThereMonInRoute5Daycare, nil)
eq(thereAfter, 1, "the Route 5 mon is still there after encode / decode")
local _, stateAfter = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(stateAfter, 2, "the Four Island mon is still there, DAYCARE_ONE_MON")
eq(Daycare.route5Of(session).mon.species, 19, "the Route 5 mon kept its species")
eq(Daycare.stateOf(session)[1].species, 16, "the Four Island mon kept its species")
eq(#session.party, 0, "and neither came back into the party")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
local _, backAfterLoad = Natives.special(ctx, Std.SPECIAL.TakePokemonFromRoute5Daycare, nil)
eq(backAfterLoad, 19, "the reloaded mon can still be withdrawn")
eq(#session.party, 1, "and lands back in the party")

print("[test] 17. the party picker gives the held screen back")
local Fade = require("src.ui.game3.fade")
local restores = 0
local realBegin = Fade.begin
Fade.begin = function(mode) restores = restores + 1; Fade.mode = mode end
Fade.active, Fade.t, Fade.mode = false, 16, Fade.MODE.TO_BLACK
local choose = { chooseParty = function(_, done) done(0) end }
Natives.choosePartyMon(newCtx(), choose, 6)
eq(Fade.t, 0, "the held black is cleared before the party menu draws")
eq(restores, 1, "and a fade is begun again when the picker closes")
eq(Fade.mode, Fade.MODE.FROM_BLACK, "the restore is FadeInFromBlack")
Fade.active, Fade.t, Fade.mode, restores = false, 16, Fade.MODE.TO_WHITE, 0
Natives.choosePartyMon(newCtx(), choose, 6)
eq(Fade.t, 16, "a held white screen is left alone")
eq(restores, 0, "and nothing fades in from black over it")
Fade.active, Fade.t, Fade.mode, restores = false, 0, Fade.MODE.FROM_BLACK, 0
Natives.choosePartyMon(newCtx(), choose, 6)
eq(Fade.t, 0, "an uncovered screen is left alone")
eq(restores, 0, "and gets no restore")
Fade.begin = realBegin

print("[test] 18. no handler in either module reaches the unknown-special log")
Natives.resetLog()
local logs = {}
local quiet = { log = function(m) logs[#logs + 1] = m end }
for _, mod in ipairs({ Trade, Daycare }) do
  for id in pairs(mod.HANDLERS) do
    local _, _, known = Natives.special(newCtx(), id, quiet)
    check(known, string.format("special 0x%X dispatches to a handler", id))
  end
end
local ListMenu = require("src.core.game3.scripting.natives_listmenu")
ListMenu.Menu.close()
eq(#logs, 0, "nothing reached the unknown-special log")

finish()

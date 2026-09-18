-- Comprehensive test suite for Game 3 Pokédex tracking, catch mechanics, and UI.

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")
local Catching = require("src.core.game3.battle.catching")
local BattleItems = require("src.core.game3.battle.items")
local Bag = require("src.core.game3.bag")
local Battle = require("src.core.game3.battle")
local Pokedex = require("src.ui.game3.pokedex")

Pokemon.install(nil)

print("[test] 1. Pokédex data structure & seen/caught tracking")
local dex = Dex.new()
assert(Dex.isSeen(dex, 1) == false, "Bulbasaur not seen initially")
assert(Dex.isCaught(dex, 1) == false, "Bulbasaur not caught initially")
assert(Dex.countSeen(dex, "kanto") == 0, "0 seen in Kanto")
assert(Dex.countCaught(dex, "kanto") == 0, "0 caught in Kanto")

-- Register encounter
local wasSeen = Dex.registerEncounter(dex, 1)
assert(wasSeen == false, "First encounter was not previously seen")
assert(Dex.isSeen(dex, 1) == true, "Bulbasaur is now seen")
assert(Dex.isCaught(dex, 1) == false, "Bulbasaur is not yet caught")
assert(Dex.countSeen(dex, "kanto") == 1, "1 seen in Kanto")
assert(Dex.countCaught(dex, "kanto") == 0, "0 caught in Kanto")

-- Second encounter returns wasSeen == true
assert(Dex.registerEncounter(dex, 1) == true, "Second encounter knows it was seen")

-- Register capture
local wasCaught = Dex.registerCapture(dex, 1)
assert(wasCaught == false, "First capture was not previously caught")
assert(Dex.isCaught(dex, 1) == true, "Bulbasaur is now caught")
assert(Dex.countSeen(dex, "kanto") == 1, "1 seen in Kanto")
assert(Dex.countCaught(dex, "kanto") == 1, "1 caught in Kanto")

-- String resolution
Dex.setSeen(dex, "CHARMANDER")
Dex.setCaught(dex, "CHARMANDER")
assert(Dex.isSeen(dex, 4) == true, "Charmander numeric is seen")
assert(Dex.isCaught(dex, 4) == true, "Charmander numeric is caught")
assert(Dex.isSeen(dex, "CHARMANDER") == true, "Charmander string is seen")
assert(Dex.isCaught(dex, "CHARMANDER") == true, "Charmander string is caught")
assert(Dex.countSeen(dex, "kanto") == 2, "2 seen in Kanto")
assert(Dex.countCaught(dex, "kanto") == 2, "2 caught in Kanto")

-- National dex tracking (e.g. Torchic = 255)
Dex.setSeen(dex, 255)
Dex.setCaught(dex, 255)
assert(Dex.countSeen(dex, "kanto") == 2, "Kanto seen count ignores Torchic (255)")
assert(Dex.countCaught(dex, "kanto") == 2, "Kanto caught count ignores Torchic (255)")
assert(Dex.countSeen(dex, "national") == 3, "National seen count includes Torchic")
assert(Dex.countCaught(dex, "national") == 3, "National caught count includes Torchic")
print("[ok] Pokédex seen/caught tracking and Kanto/National counts passed")

print("[test] 2. Catch rate calculations & ball multipliers")
local foePikachu = {
  species = 25,
  type1 = 13, -- ELECTRIC
  mon = { species = 25, level = 5, hp = 10, maxHp = 20, status = nil }
}

-- Master Ball (item 1) -> guaranteed 255 odds
local masterOdds = Catching.catchOdds(1, foePikachu, {}, { dex = dex })
assert(masterOdds == 255, "Master ball catch odds is 255")

-- Ultra Ball (item 2) vs Poké Ball (item 4)
local pokeOdds = Catching.catchOdds(4, foePikachu, {}, { dex = dex })
local ultraOdds = Catching.catchOdds(2, foePikachu, {}, { dex = dex })
assert(ultraOdds > pokeOdds, "Ultra ball has higher odds than Poké ball")
assert(math.abs(ultraOdds - pokeOdds * 2) <= 1, "Ultra ball bonus is ~2x Poké ball")

-- Status bonuses: Sleep doubles base odds
foePikachu.status = "SLP"
local sleepOdds = Catching.catchOdds(4, foePikachu, {}, { dex = dex })
assert(sleepOdds == pokeOdds * 2 or sleepOdds == 255, "Sleep status doubles catch odds")

-- Net Ball (item 6) on Water type
local foeSquirtle = {
  species = 7,
  type1 = 11, -- WATER
  mon = { species = 7, level = 5, hp = 10, maxHp = 20 }
}
local netMultWater = Catching.ballMultiplier(6, foeSquirtle, {}, { dex = dex })
assert(netMultWater == 30, "Net ball gets 3x multiplier on Water type")

-- Repeat Ball (item 9) on previously caught vs uncaught species
local repeatMultCaught = Catching.ballMultiplier(9, { species = 1, mon = { level = 5 } }, {}, { dex = dex })
assert(repeatMultCaught == 30, "Repeat ball gets 3x multiplier on caught species (Bulbasaur)")
local repeatMultUncaught = Catching.ballMultiplier(9, { species = 150, mon = { level = 70 } }, {}, { dex = dex })
assert(repeatMultUncaught == 10, "Repeat ball gets 1x on uncaught species (Mewtwo)")

-- Timer Ball (item 10) scaling with turns
local timerMultT1 = Catching.ballMultiplier(10, foePikachu, { turn = 1 }, { dex = dex })
local timerMultT15 = Catching.ballMultiplier(10, foePikachu, { turn = 15 }, { dex = dex })
local timerMultT40 = Catching.ballMultiplier(10, foePikachu, { turn = 40 }, { dex = dex })
assert(timerMultT1 == 11, "Timer ball at turn 1 is 1.1x")
assert(timerMultT15 == 25, "Timer ball at turn 15 is 2.5x")
assert(timerMultT40 == 40, "Timer ball caps at 4.0x")
print("[ok] Catch rate calculations and ball multipliers passed")

print("[test] 3. Deterministic Catch simulation & Storage (Party vs PC)")
-- Deterministic RNG mock
local mockRngPass = function(lo, hi) return lo end -- always passes threshold
local mockRngFail = function(lo, hi) return hi end -- always fails threshold

local foeCaterpie = {
  species = 10,
  mon = { species = 10, level = 3, hp = 2, maxHp = 15, moves = { 33 } }
}
local session = {
  name = "RED",
  id = 54321,
  party = { { species = 1, level = 10, hp = 30, maxHp = 30 } },
  dex = Dex.new(),
}

-- Catch Caterpie with Master Ball
local caught, shakes = Catching.tryCatch(1, foeCaterpie, {}, session, mockRngPass)
assert(caught == true, "Master ball catches Caterpie")
assert(shakes == 4, "Master ball gives 4 shakes")

-- Store Caterpie into party (< 6)
local res = Catching.storeCaught(session, foeCaterpie, 1)
assert(res.success == true, "storeCaught succeeded")
assert(res.location == "party", "Caterpie stored in party")
assert(res.firstTimeCaught == true, "First time Caterpie was caught")
assert(#session.party == 2, "Party count is now 2")
assert(session.party[2].species == 10, "Party slot 2 is Caterpie")
assert(session.party[2].pokeball == 1, "Stored with Master Ball ID")
assert(session.party[2].ot == "RED", "OT set to RED")
assert(Dex.isCaught(session.dex, 10) == true, "Caterpie marked caught in Dex")

-- Fill party to 6 Pokémon
while #session.party < 6 do
  session.party[#session.party + 1] = { species = 1, level = 5, hp = 20, maxHp = 20 }
end
assert(#session.party == 6, "Party is now full (6)")

-- Catch Pidgey (species 16) -> should go to PC
local foePidgey = {
  species = 16,
  mon = { species = 16, level = 4, hp = 5, maxHp = 18 }
}
local resPc = Catching.storeCaught(session, foePidgey, 4)
assert(resPc.location == "pc", "Pidgey transferred to PC when party is full")
assert(resPc.firstTimeCaught == true, "First time Pidgey was caught")
assert(#session.party == 6, "Party still has 6 Pokémon")
assert(session.pc == nil, "no parallel session.pc table")
assert(require("src.core.game3.storage").countTotalMons(session.storage) == 1, "PC box has 1 Pokémon")
assert(session.storage.boxes[resPc.box].mons[resPc.slot].species == 16, "PC mon is Pidgey")
assert(Dex.isCaught(session.dex, 16) == true, "Pidgey marked caught in Dex")

-- Second capture of Caterpie -> firstTimeCaught is false
local res2 = Catching.storeCaught(session, foeCaterpie, 4)
assert(res2.firstTimeCaught == false, "Second Caterpie is not firstTimeCaught")
print("[ok] Deterministic catch simulation and party/PC storage passed")

print("[test] 4. In-battle encounter & ball use")
local battleSession = {
  name = "RED",
  party = { { species = 1, level = 10, hp = 30, maxHp = 30 } },
  dex = Dex.new(),
}
local testBag = Bag.new()
Bag.add(testBag, "POKE_BALL", 2)

-- Wild battle start should mark wild opponent as SEEN
local foeRattata = { species = 19, level = 3, hp = 10, maxHp = 15 }
assert(Dex.isSeen(battleSession.dex, 19) == false, "Rattata not seen before battle")

Battle.start({
  headless = true,
  wild = true,
  playerParty = battleSession.party,
  foe = foeRattata,
  session = battleSession,
})
assert(Dex.isSeen(battleSession.dex, 19) == true, "Rattata registered as SEEN on battle start")
assert(Dex.isCaught(battleSession.dex, 19) == false, "Rattata not yet caught")

assert(BattleItems.needsPartySelect(4) == false, "Poké Ball does not need party select")
assert(BattleItems.needsPartySelect("POKE_BALL") == false, "POKE_BALL does not need party select")
assert(BattleItems.needsPartySelect(13) == true, "Potion needs party select")
assert(BattleItems.needsPartySelect("POTION") == true, "POTION needs party select")

-- BattleItems.use ball in battle
local st = Battle._st
local adapter = Battle._adapter
local useRes, msgs, endsTurn, endsBattle = BattleItems.use(st, adapter, testBag, battleSession, 4)
assert(Bag.get(testBag, "POKE_BALL") == 1, "1 Poké Ball consumed from bag")
assert(endsTurn == true, "Ball throw ends player turn")
print("[ok] In-battle encounter marking and ball usage passed")

print("[test] 5. Pokédex UI Screen lifecycle and navigation")
local mockInput = {
  _pressed = {},
  wasPressed = function(self, key) return self._pressed[key] == true end,
  press = function(self, key) self._pressed = { [key] = true } end,
  clear = function(self) self._pressed = {} end,
}

local uiDex = Dex.new()
Dex.setSeen(uiDex, 1) -- Bulbasaur (seen)
Dex.setCaught(uiDex, 1) -- Bulbasaur (caught)
Dex.setSeen(uiDex, 4) -- Charmander (seen)
Dex.setSeen(uiDex, 255) -- Torchic (seen national)

Pokedex.show(uiDex, { session = { dex = uiDex }, mode = "kanto" })
assert(Pokedex.isOpen() == true, "Pokédex is open")
assert(Pokedex.mode == "kanto", "Pokédex is in Kanto mode")
assert(Pokedex.page == "list", "Pokédex starts on list page")
assert(Pokedex.maxSpecies() == 151, "Kanto mode max species is 151")

-- Cursor down
mockInput:press("down")
Pokedex.handleInput(mockInput)
assert(Pokedex.cursor == 2, "Cursor moved to No.002 Ivysaur")

-- Press A on unseen Ivysaur -> stays on list
mockInput:press("a")
Pokedex.handleInput(mockInput)
assert(Pokedex.page == "list", "Cannot open entry for unseen Pokémon")

-- Move to No.001 Bulbasaur and press A -> opens entry
mockInput:press("up")
Pokedex.handleInput(mockInput)
assert(Pokedex.cursor == 1, "Cursor on No.001 Bulbasaur")
mockInput:press("a")
Pokedex.handleInput(mockInput)
assert(Pokedex.page == "entry", "Opens detailed entry page for Bulbasaur")

-- Press Down in entry mode -> jumps to next seen Pokémon (No.004 Charmander)
mockInput:press("down")
Pokedex.handleInput(mockInput)
assert(Pokedex.cursor == 4, "Entry view jumps directly to next seen (Charmander)")

-- Press B in entry mode -> returns to list
mockInput:press("b")
Pokedex.handleInput(mockInput)
assert(Pokedex.page == "list", "Returns to list page on B")

-- Switch to National Mode
mockInput:press("right")
Pokedex.handleInput(mockInput)
assert(Pokedex.mode == "national", "Switched to National Mode")
assert(Pokedex.maxSpecies() == 386, "National mode max species is 386")

-- Press B in list mode -> returns to mode_select
mockInput:press("b")
Pokedex.handleInput(mockInput)
assert(Pokedex.screen == "mode_select", "Returns to mode_select on B")

-- Close Pokédex from mode_select
mockInput:press("b")
Pokedex.handleInput(mockInput)
assert(Pokedex.isOpen() == false, "Pokédex is closed")

-- Test PokedexChrome data loader
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
PokedexChrome.install()
local bulbaEntry = PokedexChrome.getEntry(1)
assert(bulbaEntry ~= nil, "Bulbasaur entry exists")
assert(bulbaEntry.category == "SEED", "Bulbasaur is SEED category")
assert(bulbaEntry.categoryName == "SEED POKéMON", "Bulbasaur category name formatted")
assert(bulbaEntry.heightFormatted:find("2'04\"") ~= nil, "Bulbasaur height formatted")
assert(bulbaEntry.weightFormatted:find("15.2 lbs.") ~= nil, "Bulbasaur weight formatted")
assert(#bulbaEntry.description > 10, "Bulbasaur has description flavor text")

-- Test First-Time Caught Registration Screen
local regClosed = false
Pokedex.showRegistration(19, {
  session = { dex = uiDex },
  onDone = function() regClosed = true end,
})
assert(Pokedex.isOpen() == true, "Registration screen is open")
assert(Pokedex.mode == "registration", "Mode is registration")
assert(Pokedex._regSpecies == 19, "Registered species is Rattata (19)")

-- Press A to dismiss registration screen
mockInput:press("a")
Pokedex.handleInput(mockInput)
assert(Pokedex.isOpen() == false, "Registration screen closed on A press")
assert(regClosed == true, "onDone callback invoked")
print("[ok] Pokédex UI navigation, chrome entries, and registration view passed")

print("[test] 6. Battle Bag pocket navigation (ITEMS -> KEY_ITEMS -> POKE_BALLS) and action back-out")
local BagMenu = require("src.ui.game3.bag_menu")
local battleBag = Bag.new()
Bag.add(battleBag, "POTION", 3)
Bag.add(battleBag, "POKE_BALL", 5)

BagMenu.show(battleBag, {
  session = { party = session.party, bag = battleBag },
  battle = true,
})
assert(BagMenu.isOpen() == true, "BagMenu is open in battle")
assert(BagMenu.mode == "list", "BagMenu starts in list mode (not action mode)")
assert(BagMenu.currentPocket() == "ITEMS", "Starts on ITEMS pocket")
BagMenu.settle()

-- Swap to POKé_BALLS pocket with right arrow
mockInput:press("right")
BagMenu.handleInput(mockInput)
assert(BagMenu.currentPocket() == "KEY_ITEMS", "Swapped to KEY_ITEMS pocket")
mockInput:press("right")
BagMenu.handleInput(mockInput)
BagMenu.settle()
assert(BagMenu.currentPocket() == "POKE_BALLS", "Swapped to POKE_BALLS pocket")
assert(#BagMenu.list() == 1, "1 ball item in pocket")
assert(BagMenu.list()[1].id == 4 or BagMenu.list()[1].name == "POKé BALL", "Poke ball in list")

-- Press A on Poké Ball -> opens action mode
mockInput:press("a")
BagMenu.handleInput(mockInput)
assert(BagMenu.mode == "action", "Action mode opened for Poke Ball")

-- Press B in action mode -> backs out cleanly to list mode without closing bag
mockInput:press("b")
BagMenu.handleInput(mockInput)
assert(BagMenu.mode == "list", "Backed out to list mode on B")
assert(BagMenu.isOpen() == true, "BagMenu remains open")
assert(BagMenu.currentPocket() == "POKE_BALLS", "Still in POKE_BALLS pocket")

-- Swap back to ITEMS pocket with left arrow
mockInput:press("left")
BagMenu.handleInput(mockInput)
mockInput:press("left")
BagMenu.handleInput(mockInput)
BagMenu.settle()
assert(BagMenu.currentPocket() == "ITEMS", "Swapped back to ITEMS pocket")

-- Close bag with B in list mode
mockInput:press("b")
BagMenu.handleInput(mockInput)
BagMenu.settle()
assert(BagMenu.isOpen() == false, "BagMenu closed on B in list mode")
print("[ok] Battle bag pocket navigation and action back-out passed")

print("[test] 7. CatchSeq animation state machine, shakes & breakout vs capture")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Anim = require("src.core.game3.battle.anim")
local Task = require("src.core.game3.task")

-- Test CatchSeq with capture success (4 shakes)
Anim.reset({ headless = false })
local mockBattleSt = {
  enemy = { species = 19, mon = { species = 19, name = "RATTATA", hp = 5, maxHp = 15 } },
}
local pushedMsgs = {}
CatchSeq.begin(mockBattleSt, 4, true, 4, {
  pushMsg = function(t) pushedMsgs[#pushedMsgs + 1] = t end,
  headless = false,
  session = session,
})
assert(CatchSeq.busy() == true, "CatchSeq is busy after begin")
assert(#CatchSeq._steps == 3, "3 steps in catch sequence (msg, throw anim, success)")
assert(CatchSeq._steps[1].kind == "msg", "Step 1 is msg")
assert(CatchSeq._steps[2].kind == "throw" and CatchSeq._steps[2].data.caseId == 4, "Step 2 is the throw anim with BALL_3_SHAKES_SUCCESS")
assert(CatchSeq._steps[3].kind == "capture_success", "Step 3 is capture_success")

-- Step through tasks until completion
local safety = 0
while CatchSeq.busy() and safety < 2500 do
  safety = safety + 1
  Task.update(1 / 60)
  Anim.update(1 / 60)
  CatchSeq.update()
  if CatchSeq._waitingMsg then
    CatchSeq._waitingMsg = false
  end
end
assert(CatchSeq.busy() == false, "CatchSeq finished all animation steps")
assert(CatchSeq.result() == "catch", "Result is catch")

-- Test CatchSeq with breakout (1 shake)
Anim.reset({ headless = false })
local breakoutMsgs = {}
CatchSeq.begin(mockBattleSt, 4, false, 1, {
  pushMsg = function(t) breakoutMsgs[#breakoutMsgs + 1] = t end,
  headless = false,
  session = session,
})
assert(CatchSeq.busy() == true, "Breakout CatchSeq is busy")
assert(#CatchSeq._steps == 3, "3 steps in 1-shake breakout (msg, throw anim, breakout)")
assert(CatchSeq._steps[2].data.caseId == 1, "Step 2 throws with BALL_1_SHAKE")
assert(CatchSeq._steps[3].kind == "breakout", "Step 3 is breakout")

safety = 0
while CatchSeq.busy() and safety < 2500 do
  safety = safety + 1
  Task.update(1 / 60)
  Anim.update(1 / 60)
  CatchSeq.update()
  if CatchSeq._waitingMsg then
    CatchSeq._waitingMsg = false
  end
end
assert(CatchSeq.busy() == false, "Breakout CatchSeq finished")
assert(CatchSeq.result() == "fail_catch", "Result is fail_catch")
print("[ok] CatchSeq animation state machine, shakes & breakout vs capture passed")

print("[test] 8. LCRNG generator & catch math verification")
local Rng = require("src.core.game3.rng")
Rng.SeedRng(12345)
local r1 = Rng.Random()
local r2 = Rng.Random()
assert(r1 ~= r2, "Random advances state")

-- Verify deterministic catch rate with seeded RNG
Rng.SeedRng(42)
local odds = Catching.catchOdds(4, mockBattleSt.enemy, mockBattleSt, session)
assert(odds > 0, "Valid catch odds computed")

local caughtSeeded, shakesSeeded = Catching.tryCatch(4, mockBattleSt.enemy, mockBattleSt, session, Rng.compat)
assert(type(caughtSeeded) == "boolean", "Returns boolean caught flag")
assert(type(shakesSeeded) == "number" and shakesSeeded >= 0 and shakesSeeded <= 4, "Shakes is 0..4")
print("[ok] LCRNG generator & catch math verification passed")

print("[test] 9. Battle.update Pokédex registration input dispatch")
Battle.start({
  wild = true,
  playerParty = { { species = 25, hp = 20, maxHp = 20, level = 5, moves = { { id = 33, pp = 35 } } } },
  foe = { species = 19, level = 3, hp = 10, maxHp = 10 },
  headless = false,
  session = session,
})
assert(Battle.isActive() == true, "Battle is active")

-- Manually trigger pokedex_reg phase
local onDoneCalled = false
Pokedex.showRegistration(19, {
  session = session,
  onDone = function()
    onDoneCalled = true
    Battle._phase = "ending"
  end,
})
Battle._phase = "pokedex_reg"
assert(Pokedex.isOpen() == true, "Pokedex registration is open during battle")

-- Send A press via Battle.update
mockInput:press("a")
Battle.update(1 / 60, { input = mockInput })
assert(Pokedex.isOpen() == false, "Pokedex registration closed via Battle.update input dispatch")
assert(onDoneCalled == true, "onDone callback invoked successfully")
assert(Battle._phase == "ending", "Battle transitioned to ending phase")
print("[ok] Battle.update Pokédex registration input dispatch passed")

print("[test] all Pokédex and catch mechanics tests passed successfully!")


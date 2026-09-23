#!/usr/bin/env luajit
-- pokefirered/src/battle_main.c:2611, pokefirered/src/battle_script_commands.c:4526, pokefirered/src/battle_script_commands.c:9463, pokefirered/src/battle_script_commands.c:9497, pokefirered/src/battle_script_commands.c:9617, pokefirered/src/pokemon.c:3686, pokefirered/src/pokemon.c:3692, pokefirered/src/new_game.c:56, pokemon.c:3692

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_scenario_capture_test")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")
local Bag = require("src.core.game3.bag")
local Catching = require("src.core.game3.battle.catching")
local BattleItems = require("src.core.game3.battle.items")
local Battle = require("src.core.game3.battle")

Pokemon.install(nil)

-- battle_script_commands.c:9463
local function rigRoll(lo)
  return lo
end

local function newSession()
  return {
    name = "ASH",
    id = 4242,
    trainerId = 4242,
    party = {
      { species = 1, name = "BULBASAUR", level = 8, hp = 25, maxHp = 25, moves = { 33 }, pp = { 35 } },
    },
    dex = Dex.new(),
    bag = Bag.new(),
  }
end

local session = newSession()
Bag.add(session.bag, 4, 3)

print("[test] 1. Wild Rattata appears: battle opens and the dex marks it seen")
local okStart = Battle.start({
  wild = true,
  headless = true,
  autoFight = false,
  playerParty = session.party,
  foe = { species = 19, level = 3, hp = 6, maxHp = 15 },
  session = session,
  rng = rigRoll,
})
check(okStart == true, "the wild battle started")
check(Battle.isActive() == true, "the battle is active and waiting (not auto-run)")
local st = Battle.getState()
check(st ~= nil and st.wild == true, "battle state flags the encounter as wild")
-- battle_main.c:2611, battle_script_commands.c:4526
check(Dex.isSeen(session.dex, 19) == true, "Rattata registered as seen on encounter")
check(Dex.isCaught(session.dex, 19) == false, "Rattata is not caught yet")
check(Dex.countSeen(session.dex, "kanto") == 1, "kanto seen count is 1")
check(Dex.countCaught(session.dex, "kanto") == 0, "kanto caught count is 0")
check(st.enemy.mon.otId == 4242, "wild mon stamped with the trainer id (pokemon.c:3692 contract)")
check(type(session.secretId) == "number", "playerSecretId minted a session secret id")
check(st.enemy.mon.otSecretId == session.secretId, "the wild mon carries that secret id")
check(Catching.playerSecretId(session) == session.secretId, "playerSecretId is stable across calls")

print("[test] 2. Before throwing: ball identification and catch odds (battle_script_commands.c:9463)")
local foe = st.enemy
check(Catching.isBall(4) == true, "item 4 (POKE BALL) is a ball")
check(Catching.isBall(13) == false, "item 13 (POTION) is not a ball")
check(BattleItems.needsPartySelect(4) == false, "a ball throw needs no party target")
check(BattleItems.needsPartySelect(13) == true, "a potion asks which mon to heal")
check(Catching.ballMultiplier(2, foe, st, session) == 20, "Ultra Ball bonus is 2.0x (x10 scale)")
check(Catching.ballMultiplier(4, foe, st, session) == 10, "Poke Ball bonus is 1.0x")
check(Catching.catchOdds(1, foe, st, session) == 255, "Master Ball odds are always 255")
local curHp = foe.mon.hp
foe.mon.hp = foe.mon.maxHp
local fullOdds = Catching.catchOdds(4, foe, st, session)
foe.mon.hp = curHp
local curOdds = Catching.catchOdds(4, foe, st, session)
foe.mon.hp = 3
local lowOdds = Catching.catchOdds(4, foe, st, session)
foe.mon.hp = curHp
check(fullOdds < curOdds and curOdds < lowOdds,
  string.format("odds improve as HP drops (%d < %d < %d)", fullOdds, curOdds, lowOdds))
check(fullOdds < 255 and curOdds < 255, "under 255, so the rigged roll is what decides this throw")

print("[test] 3. Throw #1: the Poke Ball is consumed and the rigged roll holds")
check(Bag.get(session.bag, 4) == 3, "three Poke Balls in the bag before the throw")
local result1, msgs1, endsTurn, endsBattle =
  BattleItems.use(st, Battle._adapter, session.bag, session, 4)
check(result1 == "catch", "the throw caught the wild mon (got " .. tostring(result1) .. ")")
check(endsTurn == true and endsBattle == true, "a successful catch ends the turn and the battle")
check(Bag.get(session.bag, 4) == 2, "exactly one Poke Ball consumed")
local text1 = table.concat(msgs1, "\n")
check(text1:find("Gotcha", 1, true) ~= nil, "the Gotcha line was printed")
check(text1:find("added to the POK", 1, true) ~= nil,
  "the first-time catch announces the Pokedex entry (got: " .. text1:gsub("\n", " / ") .. ")")

print("[test] 4. The capture lands: dex caught + party gains the mon (battle_script_commands.c:9617)")
check(#session.party == 2, "party grew from 1 to 2")
local caughtMon = session.party[2]
check(caughtMon.species == 19, "party slot 2 holds the Rattata")
check(caughtMon.pokeball == 4, "recorded with the Poke Ball it was caught in")
check(caughtMon.ot == "ASH", "OT name is the player")
check(caughtMon.otId == 4242, "OT id is the trainer id (pokemon.c:3692)")
check(caughtMon.otSecretId == session.secretId, "OT secret id matches the session's")
check(Dex.isCaught(session.dex, 19) == true, "Rattata marked caught in the dex")
check(Dex.countCaught(session.dex, "kanto") == 1, "kanto caught count is 1")
check(Dex.registerEncounter(session.dex, 19) == true,
  "meeting it again reports it was already seen")

print("[test] 5. Second encounter: Pidgey, thrown at with the one Ultra Ball")
Battle.abort("caught")
check(Battle.isActive() == false, "the first battle is finished")
Bag.add(session.bag, 2, 1)
local okStart2 = Battle.start({
  wild = true,
  headless = true,
  autoFight = false,
  playerParty = session.party,
  foe = { species = 16, level = 4, hp = 15, maxHp = 18 },
  session = session,
  rng = rigRoll,
})
check(okStart2 == true, "the second wild battle started")
local st2 = Battle.getState()
check(Dex.isSeen(session.dex, 16) == true, "Pidgey registered as seen")
check(Dex.countSeen(session.dex, "kanto") == 2, "kanto seen count is 2")
check(Bag.get(session.bag, 2) == 1, "one Ultra Ball in the bag before the throw")
local beforeCount = #session.party
local result2, msgs2 = BattleItems.use(st2, Battle._adapter, session.bag, session, 2)
check(result2 == "catch", "the Ultra Ball caught Pidgey (got " .. tostring(result2) .. ")")
check(Bag.get(session.bag, 2) == 0, "the Ultra Ball stack is emptied (slot removed)")
check(Bag.get(session.bag, 4) == 2, "the Poke Balls are untouched")
check(#session.party == beforeCount + 1, "the party gained another mon")
local pidgey = session.party[#session.party]
check(pidgey.species == 16, "the new party slot holds Pidgey")
check(pidgey.pokeball == 2, "recorded with the Ultra Ball")
check(Dex.countCaught(session.dex, "kanto") == 2, "kanto caught count is 2")
local text2 = table.concat(msgs2, "\n")
check(text2:find("added to the POK", 1, true) ~= nil,
  "a first Pidgey still announces its dex entry (got: " .. text2:gsub("\n", " / ") .. ")")

print("[test] 6. Out of Ultra Balls: the throw is refused, nothing changes")
local result3, msgs3 = BattleItems.use(st2, Battle._adapter, session.bag, session, 2)
check(result3 == "error", "an empty pocket refuses the item (got " .. tostring(result3) .. ")")
check(table.concat(msgs3, "\n"):find("don't have", 1, true) ~= nil, "the player is told they have none")
check(#session.party == 3, "party unchanged: starter + two catches")
check(Bag.get(session.bag, 2) == 0, "still zero Ultra Balls")
check(Bag.get(session.bag, 4) == 2, "Poke Balls still untouched")
check(Dex.countCaught(session.dex, "kanto") == 2, "no phantom dex entry from the refused throw")
Battle.abort("caught")
check(Battle.isActive() == false, "battles closed down; nothing left open")

finish()

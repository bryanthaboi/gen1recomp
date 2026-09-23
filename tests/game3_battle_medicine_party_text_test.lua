#!/usr/bin/env luajit
-- pokefirered/src/party_menu.c:4464 ItemUseCB_MedicineStep
-- pokefirered/data/battle_scripts_2.s:130 BattleScript_PlayerUseItem

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_medicine_party_text_test")
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

local Bag = require("src.core.game3.bag")
local BattleItems = require("src.core.game3.battle.items")
local Pokemon = require("src.core.game3.pokemon")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local RomText = require("src.core.game3.rom_text")

Pokemon.install(nil)

local function setup()
  local bag = Bag.new()
  Bag.add(bag, 13, 1)
  Bag.add(bag, 14, 1)
  Bag.add(bag, 24, 1)
  local session = {
    name = "RED",
    bag = bag,
    party = {
      { species = 1, name = "BULBASAUR", hp = 5, maxHp = 40, moves = { 33 }, pp = { 35 } },
      { species = 25, name = "PIKACHU", hp = 30, maxHp = 30, status = "PSN", moves = { 84 }, pp = { 30 } },
      { species = 4, name = "CHARMANDER", hp = 0, maxHp = 40, moves = { 10 }, pp = { 35 } },
    },
    dex = { seen = {}, owned = {} },
  }
  local foe = State.makeBattler({ species = 16, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } }, "enemy")
  local player = State.makeBattler(session.party[1], "player", { partyIndex = 1 })
  local st = { wild = true, turn = 1, player = player, enemy = foe, playerParty = session.party }
  local said = {}
  local ad = Adapter.new(st, function(t) said[#said + 1] = t end)
  return st, ad, bag, session, said
end

local function box(key, mon, v2)
  return (RomText.box(key, { stringVars = { Pokemon.displayMonName(mon), v2 } }))
end

print("[test] 1. POTION: the party menu gets the HP text, the battle says nothing")
do
  local st, ad, bag, session, said = setup()
  local result, _, endsTurn, _, text = BattleItems.use(st, ad, bag, session, 13, 1)
  check(result == "heal" and endsTurn == true, "the POTION heals and uses the turn")
  check(#said == 0, "no battle message (got " .. tostring(said[1]) .. ")")
  local gained = (tonumber(session.party[1].hp) or 0) - 5
  check(gained > 0 and text == box("gText_PkmnHPRestoredByVar2", session.party[1], tostring(gained)),
    "party text is gText_PkmnHPRestoredByVar2 with the " .. gained .. " points it got (got " .. tostring(text) .. ")")
end

print("[test] 2. ANTIDOTE: the cure text")
do
  local st, ad, bag, session, said = setup()
  local result, _, _, _, text = BattleItems.use(st, ad, bag, session, 14, 2)
  check(result == "heal", "the ANTIDOTE cures")
  check(#said == 0, "no battle message")
  check(text == box("gText_PkmnCuredOfPoison", session.party[2]),
    "party text is gText_PkmnCuredOfPoison (got " .. tostring(text) .. ")")
end

print("[test] 3. REVIVE: the HP text with the points it came back with")
do
  local st, ad, bag, session, said = setup()
  local result, _, _, _, text = BattleItems.use(st, ad, bag, session, 24, 3)
  check(result == "heal", "the REVIVE revives")
  check(#said == 0, "no battle message")
  check(text == box("gText_PkmnHPRestoredByVar2", session.party[3], "20"),
    "party text is gText_PkmnHPRestoredByVar2 with 20 points (got " .. tostring(text) .. ")")
end

print("[test] 4. a refused use still says it won't have any effect")
do
  local st, ad, bag, session, said = setup()
  local result = BattleItems.use(st, ad, bag, session, 14, 1)
  check(result == "error", "ANTIDOTE on a healthy mon fails")
  check(#said == 1, "one refusal line")
end

local BattleText = require("src.core.game3.battle.battle_text")
local ItemUse = require("src.core.game3.item_use")
local ITEM_BLUE_FLUTE, ITEM_YELLOW_FLUTE, ITEM_RED_FLUTE = 39, 40, 41
local ITEM_GUARD_SPEC, ITEM_DIRE_HIT, ITEM_X_ATTACK, ITEM_X_SPECIAL = 73, 74, 75, 79
local ITEM_FULL_RESTORE, ITEM_PERSIM_BERRY, ITEM_LUM_BERRY = 19, 140, 141

local function stat_rose(st, b, statIndex)
  return BattleText.get("STRINGID_DEFENDERSSTATROSE", Adapter.fill(st, { def = b,
    buff1 = RomText.at("gStatNamesTable", statIndex), buff2 = BattleText.get("STRINGID_STATROSE") }))
end

local function section(fn)
  local ok, err = pcall(fn)
  if not ok then check(false, "section raised: " .. tostring(err)) end
end

print("[test] 5. X items: the stat text goes to the bag, the battle says nothing")
section(function()
  local st, ad, bag, session, said = setup()
  Bag.add(bag, ITEM_X_ATTACK, 1)
  Bag.add(bag, ITEM_X_SPECIAL, 1)
  check(BattleItems.isStatBooster(ITEM_X_ATTACK) and not BattleItems.needsPartySelect(ITEM_X_ATTACK),
    "X ATTACK is a stat booster used from the bag")
  local result, _, endsTurn, _, text = BattleItems.use(st, ad, bag, session, ITEM_X_ATTACK, nil, 0)
  check(result == "xitem" and endsTurn == true, "X ATTACK is used and takes the turn")
  check(#said == 0, "no battle message for X ATTACK (got " .. tostring(said[1]) .. ")")
  check((st.player.stages.attack or 0) == 1, "attack stage +1")
  -- pokefirered/src/pokemon.c:4991
  check(text == stat_rose(st, st.player, 1), "bag text is gText_DefendersStatRose for ATTACK (got " .. tostring(text) .. ")")
  check(not Bag.has(bag, ITEM_X_ATTACK, 1), "X ATTACK is spent")
  local _, _, _, _, spText = BattleItems.use(st, ad, bag, session, ITEM_X_SPECIAL, nil, 0)
  check(spText == stat_rose(st, st.player, 4), "X SPECIAL names SP. ATK (got " .. tostring(spText) .. ")")
  st.player.stages.attack = 6
  Bag.add(bag, ITEM_X_ATTACK, 1)
  check(not BattleItems.statBoosterHasEffect(st, ITEM_X_ATTACK, 0), "X ATTACK at +6 won't have any effect")
end)

print("[test] 6. DIRE HIT and GUARD SPEC. work from the bag")
section(function()
  local st, ad, bag, session, said = setup()
  st.playerSide = { hazards = {}, id = "player" }
  Bag.add(bag, ITEM_DIRE_HIT, 1)
  Bag.add(bag, ITEM_GUARD_SPEC, 1)
  local r1, _, _, _, t1 = BattleItems.use(st, ad, bag, session, ITEM_DIRE_HIT, nil, 0)
  check(r1 == "xitem" and st.player.focusEnergy == true, "DIRE HIT sets focus energy (got " .. tostring(r1) .. ")")
  -- pokefirered/src/pokemon.c:5001
  check(t1 == BattleText.get("STRINGID_PKMNGETTINGPUMPED", Adapter.fill(st, { atk = st.player })),
    "DIRE HIT text is gBattleText_GetPumped (got " .. tostring(t1) .. ")")
  local r2, _, _, _, t2 = BattleItems.use(st, ad, bag, session, ITEM_GUARD_SPEC, nil, 0)
  check(r2 == "xitem" and (st.playerSide and st.playerSide.expMistTurns) == 5,
    "GUARD SPEC. sets 5 turns of mist (got " .. tostring(r2) .. ")")
  -- pokefirered/src/pokemon.c:5009
  check(t2 == BattleText.get("STRINGID_PKMNSHROUDEDINMIST", Adapter.fill(st, { atk = st.player })),
    "GUARD SPEC. text is gBattleText_MistShroud (got " .. tostring(t2) .. ")")
  check(#said == 0, "no battle message")
  Bag.add(bag, ITEM_DIRE_HIT, 1)
  check(not BattleItems.statBoosterHasEffect(st, ITEM_DIRE_HIT, 0), "a second DIRE HIT won't have any effect")
end)

print("[test] 7. confusion cures: YELLOW FLUTE and PERSIM BERRY")
section(function()
  local st, ad, bag, session, said = setup()
  Bag.add(bag, ITEM_YELLOW_FLUTE, 1)
  Bag.add(bag, ITEM_PERSIM_BERRY, 1)
  session.party[1].hp = 40
  check(not BattleItems.canUseOn(st, ITEM_YELLOW_FLUTE, 1, session.party[1]), "YELLOW FLUTE on a clear head won't have any effect")
  st.player.confusionTurns = 3
  check(BattleItems.canUseOn(st, ITEM_YELLOW_FLUTE, 1, session.party[1]), "YELLOW FLUTE is offered on the confused lead")
  local result, _, _, _, text = BattleItems.use(st, ad, bag, session, ITEM_YELLOW_FLUTE, 1)
  check(result == "heal" and st.player.confusionTurns == nil, "YELLOW FLUTE snaps it out (got " .. tostring(result) .. ")")
  -- pokefirered/src/party_menu.c:4360
  check(text == box("gText_PkmnSnappedOutOfConfusion", session.party[1]),
    "party text is gText_PkmnSnappedOutOfConfusion (got " .. tostring(text) .. ")")
  -- pokefirered/src/party_menu.c:4498
  check(Bag.has(bag, ITEM_YELLOW_FLUTE, 1), "the YELLOW FLUTE is not used up")
  st.player.confusionTurns = 2
  local r2, _, _, _, t2 = BattleItems.use(st, ad, bag, session, ITEM_PERSIM_BERRY, 1)
  check(r2 == "heal" and st.player.confusionTurns == nil, "PERSIM BERRY cures confusion")
  check(t2 == box("gText_PkmnSnappedOutOfConfusion", session.party[1]), "with the same party text")
  check(not Bag.has(bag, ITEM_PERSIM_BERRY, 1), "the PERSIM BERRY is eaten")
  check(#said == 0, "no battle message")
end)

print("[test] 8. RED FLUTE, BLUE FLUTE, LUM BERRY and FULL RESTORE")
section(function()
  local st, ad, bag, session, said = setup()
  Bag.add(bag, ITEM_RED_FLUTE, 1)
  Bag.add(bag, ITEM_BLUE_FLUTE, 1)
  Bag.add(bag, ITEM_LUM_BERRY, 1)
  Bag.add(bag, ITEM_FULL_RESTORE, 1)
  st.player.expInfatuated = true
  local r1, _, _, _, t1 = BattleItems.use(st, ad, bag, session, ITEM_RED_FLUTE, 1)
  check(r1 == "heal" and not st.player.expInfatuated, "RED FLUTE cures infatuation (got " .. tostring(r1) .. ")")
  -- pokefirered/src/party_menu.c:4363
  check(t1 == box("gText_PkmnGotOverInfatuation", session.party[1]), "party text is gText_PkmnGotOverInfatuation (got " .. tostring(t1) .. ")")
  check(Bag.has(bag, ITEM_RED_FLUTE, 1), "the RED FLUTE is not used up")
  session.party[2].status = "SLP"
  session.party[2].sleep = 3
  local r2, _, _, _, t2 = BattleItems.use(st, ad, bag, session, ITEM_BLUE_FLUTE, 2)
  check(r2 == "heal" and not session.party[2].status, "BLUE FLUTE wakes the mon")
  check(t2 == box("gText_PkmnWokeUp2", session.party[2]), "party text is gText_PkmnWokeUp2")
  check(Bag.has(bag, ITEM_BLUE_FLUTE, 1), "the BLUE FLUTE is not used up")
  st.player.confusionTurns = 2
  local r3, _, _, _, t3 = BattleItems.use(st, ad, bag, session, ITEM_LUM_BERRY, 1)
  check(r3 == "heal" and st.player.confusionTurns == nil, "LUM BERRY cures a confused lead with no status (got " .. tostring(r3) .. ")")
  check(t3 == box("gText_PkmnBecameHealthy", session.party[1]), "party text is gText_PkmnBecameHealthy")
  session.party[2].hp = session.party[2].maxHp
  session.party[2].status = "PSN"
  check(BattleItems.canUseOn(st, ITEM_FULL_RESTORE, 2, session.party[2]), "FULL RESTORE is offered on a poisoned mon at full HP")
  check(#said == 0, "no battle message")
end)

print("[test] 9. the field BLUE FLUTE is not used up either")
section(function()
  local _, _, bag, session = setup()
  Bag.add(bag, ITEM_BLUE_FLUTE, 1)
  session.party[1].status = "SLP"
  session.party[1].sleep = 2
  local ok = ItemUse.useField(session, bag, ITEM_BLUE_FLUTE, 1)
  check(ok and not session.party[1].status, "BLUE FLUTE wakes the mon in the field")
  check(Bag.has(bag, ITEM_BLUE_FLUTE, 1), "and stays in the bag")
end)

if failed > 0 then
  print(failed .. " medicine party text checks failed")
  os.exit(1)
end
print("All medicine party text checks passed.")

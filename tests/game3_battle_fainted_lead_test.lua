#!/usr/bin/env luajit
-- Tests for Issue #2358: Fainted Pokemon in first slot is sent out in battle.

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

print("=== Issue #2358: Fainted Lead Pokemon Battle Tests ===")

local State = require("src.core.game3.battle.state")
local Battle = require("src.core.game3.battle")
local PartyMenu = require("src.ui.game3.party_menu")

local partyWithFaintedLead = {
  { species = 1, name = "BULBASAUR", level = 5, hp = 0, maxHp = 20, moves = { 33 }, pp = { 35 } },
  { species = 4, name = "CHARMANDER", level = 5, hp = 18, maxHp = 18, moves = { 10 }, pp = { 35 } },
  { species = 7, name = "SQUIRTLE", level = 5, hp = 22, maxHp = 22, moves = { 55 }, pp = { 30 } },
}

print("[test] 1. State.new selects first living Pokemon when lead is fainted")
local stSingle = State.new({
  wild = true,
  playerParty = partyWithFaintedLead,
  foeMon = { species = 16, name = "PIDGEY", level = 3, hp = 15, maxHp = 15, moves = { 33 }, pp = { 35 } },
})

check(stSingle.player ~= nil, "player battler created")
check(stSingle.player.partyIndex == 2, "player battler partyIndex is 2 (Charmander), not 1 (Bulbasaur)")
check(stSingle.player.mon.hp == 18, "player battler has 18 HP (living mon)")
check(not stSingle.player.fainted, "player battler is not fainted")
check(stSingle.player.species == 4, "player battler is Charmander (species 4)")
check(stSingle.enemy.participants[2] == true, "enemy participants tracking slot 2")
check(stSingle.enemy.participants[1] == nil, "enemy participants not tracking fainted slot 1")

print("[test] 2. State.new for double battle with fainted lead selects slot 2 and slot 3")
local stDouble = State.new({
  wild = false,
  double = true,
  playerParty = partyWithFaintedLead,
  foeParty = {
    { species = 19, name = "RATTATA", level = 4, hp = 12, maxHp = 12, moves = { 33 }, pp = { 35 } },
    { species = 21, name = "SPEAROW", level = 4, hp = 14, maxHp = 14, moves = { 33 }, pp = { 35 } },
  },
})

check(stDouble.player.partyIndex == 2, "double battle b0 is slot 2 (Charmander)")
check(stDouble.battlers[2] ~= nil and stDouble.battlers[2].partyIndex == 3, "double battle b2 is slot 3 (Squirtle)")
check(stDouble.absent[2] == nil, "b2 is present")

print("[test] 3. PartyMenu.battleOrder with fainted lead puts active battler first")
local order = PartyMenu.battleOrder(stSingle)
check(order[1] == 2, "battleOrder puts active slot 2 in position 1: " .. table.concat(order, ", "))

print("[test] 4. Headless Battle.start with fainted lead initializes cleanly")
local ok, err = Battle.start({
  headless = true,
  wild = true,
  playerParty = {
    { species = 1, name = "BULBASAUR", level = 5, hp = 0, maxHp = 20, moves = { 33 }, pp = { 35 } },
    { species = 25, name = "PIKACHU", level = 5, hp = 19, maxHp = 19, moves = { 84 }, pp = { 30 } },
  },
  foe = { species = 16, level = 3, hp = 10, maxHp = 10, moves = { 33 }, pp = { 35 } },
})

check(ok == true or err == nil, "Battle.start succeeded: " .. tostring(err))
local curSt = Battle.getState()
check(curSt ~= nil, "Battle state exists")
check(curSt.player.partyIndex == 2, "Active player mon in Battle is slot 2 (Pikachu)")
check(curSt.player.species == 25, "Active player mon species is Pikachu (25)")

if failed > 0 then
  print(string.format("=== FAILED: %d test(s) failed ===", failed))
  os.exit(1)
else
  print("=== ALL FAINTED LEAD TESTS PASSED ===")
end

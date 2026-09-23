#!/usr/bin/env luajit
-- Test FireRed Pokémon moveset assignment, learnsets, and battle initialization.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_moveset_assignment_test")

local Pokemon = require("src.core.game3.pokemon")
local Battle = require("src.core.game3.battle.init")
local Party = require("src.core.game3.party")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED %s: expected %s, got %s", msg or "", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_table_eq(actual, expected, msg)
  if #actual ~= #expected then
    error(string.format("FAILED %s: expected len %d, got len %d", msg or "", #expected, #actual), 2)
  end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error(string.format("FAILED %s: index %d expected %s, got %s", msg or "", i, tostring(expected[i]), tostring(actual[i])), 2)
    end
  end
end

print("--- Test 1: Pokemon.movesAtLevel for Starters & Common Species ---")
do
  -- Bulbasaur (1) at Lv 5: Tackle (33), Growl (45)
  local bMoves = Pokemon.movesAtLevel(1, 5)
  assert_table_eq(bMoves, { 33, 45 }, "Bulbasaur Lv 5 moves")

  -- Charmander (4) at Lv 5: Scratch (10), Growl (45)
  local cMoves = Pokemon.movesAtLevel(4, 5)
  assert_table_eq(cMoves, { 10, 45 }, "Charmander Lv 5 moves")

  -- Squirtle (7) at Lv 5: Tackle (33), Tail Whip (39)
  local sMoves = Pokemon.movesAtLevel(7, 5)
  assert_table_eq(sMoves, { 33, 39 }, "Squirtle Lv 5 moves")

  -- Pikachu (25) at Lv 15: Tail Whip (39), Thunder Wave (86), Quick Attack (98), Double Team (104)
  local pMoves = Pokemon.movesAtLevel(25, 15)
  assert_table_eq(pMoves, { 39, 86, 98, 104 }, "Pikachu Lv 15 moves (4 most recent, no dupes)")

  -- Ivysaur (2) at Lv 20: Leech Seed (73), Vine Whip (22), PoisonPowder (77), Sleep Powder (79)
  -- Tests that duplicate level 1/4 Growl and level 1/7 Leech Seed entries do NOT produce duplicate slots
  local iMoves = Pokemon.movesAtLevel(2, 20)
  assert_table_eq(iMoves, { 73, 22, 77, 79 }, "Ivysaur Lv 20 moves (no duplicate Growl/Leech Seed)")

  -- Pidgey (16) at Lv 9: Tackle (33), Sand-Attack (28), Gust (16)
  local pidMoves = Pokemon.movesAtLevel(16, 9)
  assert_table_eq(pidMoves, { 33, 28, 16 }, "Pidgey Lv 9 moves")

  print("ok  Pokemon.movesAtLevel produces authentic 1:1 movesets without duplicates")
end

print("--- Test 2: Wild Encounter & Default Trainer Battle Moveset Resolution ---")
do
  -- Start a wild battle against a Level 9 Pidgey with NO explicit foe.moves (standard wild encounter)
  local playerParty = {
    { species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33, 45 }, pp = { 35, 40 }, maxPp = { 35, 40 } },
  }
  local foeMon = {
    species = 16, -- Pidgey
    level = 9,
    -- moves is nil (wild encounter)
  }

  local ok, err = Battle.start({ playerName = "RED",
    wild = true,
    playerParty = playerParty,
    foe = foeMon,
    headless = true,
  })
  assert(ok, "Battle must start: " .. tostring(err))

  local st = Battle.getState()
  local enemyMon = st.enemy.mon
  assert(enemyMon, "Enemy mon must exist")
  assert_eq(#enemyMon.moves, 3, "Enemy Pidgey must know 3 moves at Lv 9")
  assert_table_eq(enemyMon.moves, { 33, 28, 16 }, "Enemy Pidgey knows Tackle, Sand-Attack, Gust (NOT just Tackle!)")
  assert_eq(enemyMon.maxPp[1], 35, "Tackle max PP")
  assert_eq(enemyMon.maxPp[2], 15, "Sand-Attack max PP")
  assert_eq(enemyMon.maxPp[3], 35, "Gust max PP")

  Battle.abort()
  print("ok  Wild battle correctly initializes authentic moves from learnsets")
end

print("--- Test 3: Custom Moves on Trainers Preserved ---")
do
  local playerParty = {
    { species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 }, maxPp = { 35 } },
  }
  local customFoe = {
    species = 25, -- Pikachu
    level = 20,
    moves = { 85, 98 }, -- Thunderbolt (85), Quick Attack (98)
  }

  local ok = Battle.start({ playerName = "RED",
    wild = false,
    trainerId = 326,
    playerParty = playerParty,
    foe = customFoe,
    headless = true,
  })
  assert(ok, "Battle must start")

  local st = Battle.getState()
  local enemyMon = st.enemy.mon
  assert_table_eq(enemyMon.moves, { 85, 98 }, "Custom trainer moves preserved")

  Battle.abort()
  print("ok  Custom trainer moves preserved")
end

print("--- Test 4: Party.giveMon gives Authentic Starting Movesets ---")
do
  local session = { party = {} }

  -- Charmander at Lv 5
  Party.giveMon(session, 4, 5, "CHARMY")
  local mon = session.party[1]
  assert(mon, "Mon must be given")
  assert_table_eq(mon.moves, { 10, 45 }, "Given Charmander has Scratch and Growl (NOT just Tackle!)")
  assert_eq(mon.pp[1], 35, "Scratch PP")
  assert_eq(mon.pp[2], 40, "Growl PP")

  print("ok  Party.giveMon gives authentic starting moves")
end

print("ALL MOVESET ASSIGNMENT TESTS PASSED!")

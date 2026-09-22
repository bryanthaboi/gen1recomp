#!/usr/bin/env luajit
-- Test suite for Game 3 Special Moves (OHKO, Fixed & Proportional Damage).
-- Run: luajit tests/game3_battle_special_moves_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_battle_special_moves_test")

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Damage = require("src.core.game3.battle.damage")
local Types = require("src.core.game3.battle.types")
local Moves = require("src.core.game3.battle.moves")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function setup_test_battle(st, rngFn)
  st.rng = rngFn or function(lo, hi)
    if lo == 1 and hi == 100 then return 1 end -- hit accuracy
    if lo and hi then return hi end
    return lo or 0
  end
  return Adapter.new(st)
end

print("=== 1. OHKO Moves (Horn Drill, Fissure, Guillotine, Sheer Cold) ===")
do
  -- Type immunity: Fissure (Ground) against Pidgey (Normal/Flying)
  local st = State.new({
    wild = true,
    playerParty = { { species = 95, level = 30, hp = 100, maxHp = 100, moves = { 90 }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Fissure
    foeMon = { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 }, -- Pidgey (Flying)
  })
  st.player.type1 = Types.ID.ROCK
  st.player.type2 = Types.ID.GROUND
  st.enemy.type1 = Types.ID.NORMAL
  st.enemy.type2 = Types.ID.FLYING
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 90, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("doesn't affect", 1, true) ~= nil, "Fissure fails against Flying-type")
  check(ad:hp(st.enemy) == 50, "Foe takes 0 damage from immune Fissure")
end

do
  -- Sturdy ability blocks OHKO
  local st = State.new({
    wild = true,
    playerParty = { { species = 127, level = 40, hp = 100, maxHp = 100, moves = { 12 }, pp = { 5 },
      attack = 60, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Guillotine
    foeMon = { species = 74, level = 30, hp = 60, maxHp = 60, moves = { 33 }, pp = { 35 },
      ability = 5, attack = 30, defense = 50, spAtk = 20, spDef = 20, speed = 20 }, -- Geodude (Sturdy = 5)
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 12, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("STURDY", 1, true) ~= nil, "Sturdy blocks OHKO")
  check(ad:hp(st.enemy) == 60, "Foe with Sturdy took 0 damage")
end

do
  -- Level check: User level < Target level fails
  local st = State.new({
    wild = true,
    playerParty = { { species = 127, level = 20, hp = 100, maxHp = 100, moves = { 32 }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Horn Drill
    foeMon = { species = 19, level = 25, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 32, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  -- pokefirered/src/battle_message.c:1112
  check(joined:find("is\nunaffected!", 1, true) ~= nil, "OHKO fails when user level < target level")
  check(ad:hp(st.enemy) == 50, "Target undamaged when attacker is lower level")
end

do
  -- OHKO Hit: Damage equal to target HP, KO message, target faints
  local st = State.new({
    wild = true,
    playerParty = { { species = 127, level = 40, hp = 100, maxHp = 100, moves = { 32 }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Horn Drill
    foeMon = { species = 19, level = 30, hp = 75, maxHp = 75, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 32, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("It's a one-hit KO!", 1, true) ~= nil, "Prints 'It's a one-hit KO!'")
  check(ad:hp(st.enemy) == 0, "Target HP reduced to 0")
  check(ad:isFainted(st.enemy) == true, "Target is fainted")
end

do
  -- Endure survives OHKO with 1 HP
  local st = State.new({
    wild = true,
    playerParty = { { species = 127, level = 40, hp = 100, maxHp = 100, moves = { 32 }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 30, hp = 75, maxHp = 75, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  st.enemy.expEnduring = true
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 32, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("ENDURED\nthe hit!", 1, true) ~= nil, "Target endured OHKO")
  check(ad:hp(st.enemy) == 1, "Target survives with exactly 1 HP")
  check(ad:isFainted(st.enemy) == false, "Target did not faint")
end

print("\n=== 2. Fixed Damage Moves (Dragon Rage, SonicBoom) ===")
do
  -- Dragon Rage deals exactly 40 HP
  local st = State.new({
    wild = true,
    playerParty = { { species = 147, level = 15, hp = 100, maxHp = 100, moves = { 82 }, pp = { 10 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 50 } }, -- Dragon Rage
    foeMon = { species = 143, level = 50, hp = 160, maxHp = 160, moves = { 33 }, pp = { 35 },
      attack = 80, defense = 100, spAtk = 80, spDef = 100, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 82, 1, ad, st, out)
  check(ad:hp(st.enemy) == 120, "Dragon Rage deals exactly 40 HP (160 -> 120)")
  local joined = table.concat(out, " || ")
  check(joined:find("critical", 1, true) == nil, "Fixed damage has no critical hit")
  check(joined:find("effective", 1, true) == nil, "Fixed damage suppresses effectiveness text")
end

do
  -- SonicBoom deals 20 HP to normal target, 0 to Ghost
  local st = State.new({
    wild = true,
    playerParty = { { species = 100, level = 20, hp = 100, maxHp = 100, moves = { 49 }, pp = { 20 },
      attack = 30, defense = 30, spAtk = 30, spDef = 30, speed = 50 } }, -- SonicBoom
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 49, 1, ad, st, out)
  check(ad:hp(st.enemy) == 30, "SonicBoom deals exactly 20 HP (50 -> 30)")

  -- SonicBoom vs Ghost-type
  st.enemy.type1 = Types.ID.GHOST
  st.enemy.type2 = nil
  local outGhost = {}
  Engine.resolveMove(st.player, st.enemy, 49, 1, ad, st, outGhost)
  check(ad:hp(st.enemy) == 30, "SonicBoom deals 0 HP to Ghost-type")
end

print("\n=== 3. Level-Based Damage (Seismic Toss, Night Shade) ===")
do
  -- Seismic Toss deals damage equal to level
  local st = State.new({
    wild = true,
    playerParty = { { species = 68, level = 43, hp = 100, maxHp = 100, moves = { 69 }, pp = { 20 },
      attack = 80, defense = 50, spAtk = 40, spDef = 50, speed = 50 } }, -- Seismic Toss
    foeMon = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 69, 1, ad, st, out)
  check(ad:hp(st.enemy) == 57, "Seismic Toss at level 43 deals exactly 43 HP (100 -> 57)")

  -- Seismic Toss vs Ghost fails
  st.enemy.type1 = Types.ID.GHOST
  local outGhost = {}
  Engine.resolveMove(st.player, st.enemy, 69, 1, ad, st, outGhost)
  check(ad:hp(st.enemy) == 57, "Seismic Toss fails against Ghost-type")
end

do
  -- Night Shade deals damage equal to level
  local st = State.new({
    wild = true,
    playerParty = { { species = 94, level = 35, hp = 100, maxHp = 100, moves = { 101 }, pp = { 15 },
      attack = 40, defense = 40, spAtk = 80, spDef = 50, speed = 80 } }, -- Night Shade
    foeMon = { species = 65, level = 30, hp = 80, maxHp = 80, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  st.enemy.type1 = Types.ID.PSYCHIC
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 101, 1, ad, st, out)
  check(ad:hp(st.enemy) == 45, "Night Shade at level 35 deals exactly 35 HP (80 -> 45)")

  -- Night Shade vs Normal fails
  st.enemy.type1 = Types.ID.NORMAL
  local outNorm = {}
  Engine.resolveMove(st.player, st.enemy, 101, 1, ad, st, outNorm)
  check(ad:hp(st.enemy) == 45, "Night Shade fails against Normal-type")
end

print("\n=== 4. Proportional & Contextual Damage (Super Fang, Endeavor, Psywave) ===")
do
  -- Super Fang cuts target current HP in half
  local st = State.new({
    wild = true,
    playerParty = { { species = 19, level = 25, hp = 100, maxHp = 100, moves = { 162 }, pp = { 10 },
      attack = 30, defense = 30, spAtk = 30, spDef = 30, speed = 50 } }, -- Super Fang
    foeMon = { species = 143, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 162, 1, ad, st, out)
  check(ad:hp(st.enemy) == 75, "Super Fang halves 150 HP -> 75 HP")

  -- Super Fang again on 75 HP -> deals floor(75 / 2) = 37 -> 38 HP remaining
  Engine.resolveMove(st.player, st.enemy, 162, 1, ad, st, out)
  check(ad:hp(st.enemy) == 38, "Super Fang halves 75 HP -> 38 HP remaining (37 damage)")
end

do
  -- Endeavor deals target HP - user HP when user HP < target HP
  local st = State.new({
    wild = true,
    playerParty = { { species = 19, level = 25, hp = 12, maxHp = 60, moves = { 283 }, pp = { 5 },
      attack = 30, defense = 30, spAtk = 30, spDef = 30, speed = 50 } }, -- Endeavor (move 283)
    foeMon = { species = 143, level = 50, hp = 80, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 283, 1, ad, st, out)
  check(ad:hp(st.enemy) == 12, "Endeavor reduces foe's 80 HP down to user's 12 HP")

  -- Endeavor fails when user HP >= target HP
  st.player.mon.hp = 80
  local outFail = {}
  Engine.resolveMove(st.player, st.enemy, 283, 1, ad, st, outFail)
  local joined = table.concat(outFail, " || ")
  check(joined:find("But it failed!", 1, true) ~= nil, "Endeavor fails when user HP >= target HP")
  check(ad:hp(st.enemy) == 12, "Foe HP unchanged on Endeavor failure")
end

do
  -- Psywave deals (level * (roll + 50) / 100)
  local st = State.new({
    wild = true,
    playerParty = { { species = 64, level = 40, hp = 100, maxHp = 100, moves = { 149 }, pp = { 15 },
      attack = 30, defense = 30, spAtk = 60, spDef = 50, speed = 50 } }, -- Psywave
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  -- Test with fixed roll 0 -> floor(40 * 50 / 100) = 20 damage
  local adMin = setup_test_battle(st, function(lo, hi)
    if lo == 0 and hi == 10 then return 0 end
    return 1
  end)
  Engine.resolveMove(st.player, st.enemy, 149, 1, adMin, st, {})
  check(adMin:hp(st.enemy) == 80, "Psywave min roll deals 0.5x level = 20 damage (100 -> 80)")

  -- Test with fixed roll 100 -> floor(40 * 150 / 100) = 60 damage
  st.enemy.mon.hp = 100
  local adMax = setup_test_battle(st, function(lo, hi)
    if lo == 0 and hi == 10 then return 10 end
    return 1
  end)
  Engine.resolveMove(st.player, st.enemy, 149, 1, adMax, st, {})
  check(adMax:hp(st.enemy) == 40, "Psywave max roll deals 1.5x level = 60 damage (100 -> 40)")
end

print("\n=== 5. One-Off Status & Utility (Rest, Haze, Mist, Substitute, False Swipe, Pay Day, Teeter Dance) ===")
do
  -- Rest: full heal, cures status, sets SLP with 2 sleep turns
  local st = State.new({
    wild = true,
    playerParty = { { species = 143, level = 30, hp = 25, maxHp = 100, moves = { 156 }, pp = { 10 },
      status = "BRN", attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 20 } }, -- Rest (156)
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 156, 1, ad, st, out)
  check(ad:hp(st.player) == 100, "Rest restores full HP (25 -> 100)")
  check(st.player.status == "SLP", "Rest inflicts SLP")
  -- pokefirered/src/battle_script_commands.c:6480
  check(st.player.sleepTurns == 3, "Rest sets STATUS1_SLEEP_TURN(3)")
  local joined = table.concat(out, " || ")
  check(joined:find("became healthy", 1, true) ~= nil, "Rest message: went to sleep and became healthy")

  -- Rest fails when already at full HP (and awake)
  local stFull = State.new({
    wild = true,
    playerParty = { { species = 143, level = 30, hp = 100, maxHp = 100, moves = { 156 }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 20 } },
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local adFull = setup_test_battle(stFull)
  local outFull = {}
  Engine.resolveMove(stFull.player, stFull.enemy, 156, 1, adFull, stFull, outFull)
  local joinedFull = table.concat(outFull, " || ")
  check(joinedFull:find("HP is full!", 1, true) ~= nil, "Rest fails when HP is full")
end

do
  -- Haze resets all stat stages for both battlers
  local st = State.new({
    wild = true,
    playerParty = { { species = 134, level = 30, hp = 100, maxHp = 100, moves = { 114 }, pp = { 30 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Haze (114)
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  st.player.stages.attack = 3
  st.player.stages.speed = 2
  st.enemy.stages.defense = -2
  st.enemy.stages.accuracy = -1
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 114, 1, ad, st, out)
  check(st.player.stages.attack == 0 and st.player.stages.speed == 0, "Player stats reset to 0")
  check(st.enemy.stages.defense == 0 and st.enemy.stages.accuracy == 0, "Enemy stats reset to 0")
  local joined = table.concat(out, " || ")
  check(joined:find("All stat changes were\neliminated!", 1, true) ~= nil, "Haze message printed")
end

do
  -- Mist protects team from stat drops
  local st = State.new({
    wild = true,
    playerParty = { { species = 134, level = 30, hp = 100, maxHp = 100, moves = { 54 }, pp = { 30 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Mist (54)
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 45 }, pp = { 40 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 }, -- Growl (45)
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 54, 1, ad, st, out)
  check(st.playerSide.expMistTurns == 5, "Mist sets 5 turns on side")

  -- Foe uses Growl against player under Mist
  local outGrowl = {}
  Engine.resolveMove(st.enemy, st.player, 45, 1, ad, st, outGrowl)
  check(st.player.stages.attack == 0, "Mist prevents Attack drop")
  local joinedGrowl = table.concat(outGrowl, " || ")
  check(joinedGrowl:find("protected\nby MIST", 1, true) ~= nil, "Mist protection message printed")
end

do
  -- Substitute: costs 25% max HP, creates decoy, absorbs damage, breaks on lethal hit
  local st = State.new({
    wild = true,
    playerParty = { { species = 25, level = 30, hp = 100, maxHp = 100, moves = { 164 }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- Substitute (164)
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 40, defense = 20, spAtk = 20, spDef = 20, speed = 20 }, -- Tackle (33)
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 164, 1, ad, st, out)
  check(ad:hp(st.player) == 75, "Substitute pays 25 HP (100 -> 75)")
  -- pokefirered/src/battle_script_commands.c:7442
  check(st.player.substituteHP == 25, "Substitute created with maxHP / 4 HP")

  -- Foe attacks Substitute with non-lethal hit
  -- Force damage = 10
  st.player.substituteHP = 20
  local outTackle = {}
  Engine.resolveMove(st.enemy, st.player, 33, 1, ad, st, outTackle)
  check(ad:hp(st.player) == 75, "Player takes NO HP loss while Substitute is active")
  local joinedTackle = table.concat(outTackle, " || ")
  check(joinedTackle:find("SUBSTITUTE took damage", 1, true) ~= nil,
    "Substitute absorbed damage")

  -- Foe breaks Substitute
  st.player.substituteHP = 1
  local outBreak = {}
  Engine.resolveMove(st.enemy, st.player, 33, 1, ad, st, outBreak)
  check(st.player.substituteHP == 0, "Substitute HP is 0 after break")
  check(ad:hp(st.player) == 75, "Player takes NO leftover damage when Substitute breaks")
  local joinedBreak = table.concat(outBreak, " || ")
  check(joinedBreak:find("SUBSTITUTE faded!", 1, true) ~= nil, "Substitute faded message printed")
end

do
  -- False Swipe: never KOs, leaves target with at least 1 HP
  local st = State.new({
    wild = true,
    playerParty = { { species = 123, level = 50, hp = 100, maxHp = 100, moves = { 206 }, pp = { 40 },
      attack = 100, defense = 50, spAtk = 50, spDef = 50, speed = 50 } }, -- False Swipe (206)
    foeMon = { species = 19, level = 5, hp = 15, maxHp = 15, moves = { 33 }, pp = { 35 },
      attack = 10, defense = 5, spAtk = 10, spDef = 5, speed = 10 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 206, 1, ad, st, out)
  check(ad:hp(st.enemy) == 1, "False Swipe leaves target with exactly 1 HP")
  check(ad:isFainted(st.enemy) == false, "Target did not faint from False Swipe")

  -- False Swipe against target already at 1 HP
  Engine.resolveMove(st.player, st.enemy, 206, 1, ad, st, {})
  check(ad:hp(st.enemy) == 1, "False Swipe against 1 HP target keeps target at 1 HP")
end

do
  -- Pay Day: damages foe and scatters coins = level * 5
  local st = State.new({
    wild = true,
    playerParty = { { species = 52, level = 24, hp = 100, maxHp = 100, moves = { 6 }, pp = { 20 },
      attack = 40, defense = 40, spAtk = 40, spDef = 40, speed = 50 } }, -- Pay Day (6)
    foeMon = { species = 19, level = 20, hp = 80, maxHp = 80, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 6, 1, ad, st, out)
  check(ad:hp(st.enemy) < 80, "Pay Day dealt damage to foe")
  check(st.payDayCoins == 24 * 5, "Pay Day scattered 120 coins (level 24 * 5)")
  local joined = table.concat(out, " || ")
  check(joined:find("Coins scattered", 1, true) ~= nil, "Coins scattered message printed")
end

do
  -- Teeter Dance confuses target
  local st = State.new({
    wild = true,
    playerParty = { { species = 327, level = 30, hp = 100, maxHp = 100, moves = { 298 }, pp = { 20 },
      attack = 40, defense = 40, spAtk = 40, spDef = 40, speed = 50 } }, -- Teeter Dance (298)
    foeMon = { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 298, 1, ad, st, out)
  check(st.enemy.confusionTurns and st.enemy.confusionTurns > 0, "Target became confused")
  local joined = table.concat(out, " || ")
  check(joined:find("became\nconfused!", 1, true) ~= nil, "Confusion message printed")
end

print("\n=== 6. Variable & Scaled Power Moves (Magnitude, Return, Frustration, Eruption, Flail, Facade, Revenge, Weather Ball, Smellingsalt, Low Kick) ===")
do
  -- Magnitude rolls and prints magnitude level
  local magId = Moves.numForName("MAGNITUDE")
  -- Test roll 0 -> Magnitude 4
  local st4 = State.new({
    wild = true,
    playerParty = { { species = 74, level = 30, hp = 100, maxHp = 100, moves = { magId }, pp = { 30 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 25, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 40, spAtk = 20, spDef = 20, speed = 20 }, -- Pikachu
  })
  local ad4 = setup_test_battle(st4, function(lo, hi)
    if lo == 0 and hi == 99 then return 2 end -- Magnitude 4
    if lo == 1 and hi == 100 then return 1 end
    if lo == 85 and hi == 100 then return 100 end
    return hi or lo or 0
  end)
  local out4 = {}
  Engine.resolveMove(st4.player, st4.enemy, magId, 1, ad4, st4, out4)
  local joined4 = table.concat(out4, " || ")
  check(joined4:find("MAGNITUDE 4!", 1, true) ~= nil, "Magnitude 4 message printed")

  -- Test roll 99 -> Magnitude 10
  local st10 = State.new({
    wild = true,
    playerParty = { { species = 74, level = 30, hp = 100, maxHp = 100, moves = { magId }, pp = { 30 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 25, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 40, spAtk = 20, spDef = 20, speed = 20 },
  })
  local ad10 = setup_test_battle(st10, function(lo, hi)
    if lo == 0 and hi == 99 then return 99 end -- Magnitude 10
    if lo == 1 and hi == 100 then return 1 end
    if lo == 85 and hi == 100 then return 100 end
    return hi or lo or 0
  end)
  local out10 = {}
  Engine.resolveMove(st10.player, st10.enemy, magId, 1, ad10, st10, out10)
  local joined10 = table.concat(out10, " || ")
  check(joined10:find("MAGNITUDE 10!", 1, true) ~= nil, "Magnitude 10 message printed")
  check(ad4:hp(st4.enemy) > ad10:hp(st10.enemy), "Magnitude 10 dealt significantly more damage than Magnitude 4")
end

do
  -- Return vs Frustration scaling with friendship
  local retId = Moves.numForName("RETURN")
  local frusId = Moves.numForName("FRUSTRATION")

  -- Max friendship (255)
  local pMonMax = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { retId, frusId }, pp = { 20, 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, friendship = 255 }
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 20, speed = 20 }

  local dmgRetMax = Damage.calc({ mon = pMonMax }, { mon = foe }, retId, { forceRoll = 100, forceCrit = false })
  local dmgFrusMax = Damage.calc({ mon = pMonMax }, { mon = foe }, frusId, { forceRoll = 100, forceCrit = false })
  check(dmgRetMax >= dmgFrusMax * 10, "Max friendship Return (pwr 102) deals much more damage than Frustration (pwr 1)")

  -- Min friendship (0)
  local pMonMin = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { retId, frusId }, pp = { 20, 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, friendship = 0 }
  local dmgRetMin = Damage.calc({ mon = pMonMin }, { mon = foe }, retId, { forceRoll = 100, forceCrit = false })
  local dmgFrusMin = Damage.calc({ mon = pMonMin }, { mon = foe }, frusId, { forceRoll = 100, forceCrit = false })
  check(dmgFrusMin >= dmgRetMin * 10, "Min friendship Frustration (pwr 102) deals much more damage than Return (pwr 1)")
end

do
  -- Eruption / Water Spout scaling with HP
  local erupId = Moves.numForName("ERUPTION")
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }

  local fullMon = { species = 157, level = 30, hp = 100, maxHp = 100, moves = { erupId }, pp = { 5 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, ability = 0 }
  local lowMon = { species = 157, level = 30, hp = 10, maxHp = 100, moves = { erupId }, pp = { 5 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, ability = 0 }

  local dmgFull = Damage.calc({ mon = fullMon }, { mon = foe }, erupId, { forceRoll = 100, forceCrit = false })
  local dmgLow = Damage.calc({ mon = lowMon }, { mon = foe }, erupId, { forceRoll = 100, forceCrit = false })
  check(dmgFull >= math.floor(dmgLow * 7), "Full HP Eruption deals ~7x-10x damage of 10% HP Eruption")
end

do
  -- Flail / Reversal scaling with remaining HP
  local flailId = Moves.numForName("FLAIL")
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }

  local fullMon = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { flailId }, pp = { 15 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }
  local lowMon = { species = 143, level = 30, hp = 2, maxHp = 100, moves = { flailId }, pp = { 15 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }

  local dmgFull = Damage.calc({ mon = fullMon }, { mon = foe }, flailId, { forceRoll = 100, forceCrit = false })
  local dmgLow = Damage.calc({ mon = lowMon }, { mon = foe }, flailId, { forceRoll = 100, forceCrit = false })
  check(dmgLow >= math.floor(dmgFull * 8), "1 HP Flail (pwr 200) deals ~10x damage of full HP Flail (pwr 20)")
end

do
  -- Facade doubles power under status and ignores burn drop
  local facadeId = Moves.numForName("FACADE")
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }

  local normalMon = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { facadeId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }
  local burnedMon = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { facadeId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, status = "BRN" }

  local dmgNorm = Damage.calc({ mon = normalMon }, { mon = foe }, facadeId, { forceRoll = 100, forceCrit = false })
  local dmgBurn = Damage.calc({ mon = burnedMon }, { mon = foe }, facadeId, { forceRoll = 100, forceCrit = false })
  local parMon = { species = 143, level = 30, hp = 100, maxHp = 100, moves = { facadeId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, status = "PAR" }
  local dmgPar = Damage.calc({ mon = parMon }, { mon = foe }, facadeId, { forceRoll = 100, forceCrit = false })
  check(dmgPar >= math.floor(dmgNorm * 1.8), "Facade doubles damage under Paralysis")
  -- pokefirered/src/pokemon.c:2539
  check(math.abs(dmgBurn - dmgNorm) <= 2, "Facade x2 is cancelled by the Gen3 burn halving")
end

do
  -- Revenge doubles power if damaged this turn
  local revId = Moves.numForName("REVENGE")
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }
  local mon = { species = 66, level = 30, hp = 100, maxHp = 100, moves = { revId }, pp = { 10 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }

  local dmgNoDmg = Damage.calc({ mon = mon, damageTakenThisTurn = 0 }, { mon = foe }, revId, { forceRoll = 100, forceCrit = false })
  local dmgHadDmg = Damage.calc({ mon = mon, damageTakenThisTurn = 25 }, { mon = foe }, revId, { forceRoll = 100, forceCrit = false })
  check(dmgHadDmg >= math.floor(dmgNoDmg * 1.8), "Revenge doubles power after taking damage this turn")
end

do
  -- Weather Ball doubles power and changes type with weather
  local wbId = Moves.numForName("WEATHER_BALL")
  local foeGrass = { species = 1, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }
  foeGrass.type1 = Types.ID.GRASS
  foeGrass.type2 = Types.ID.POISON

  local mon = { species = 351, level = 30, hp = 100, maxHp = 100, moves = { wbId }, pp = { 10 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }
  mon.type1 = Types.ID.NORMAL

  local dmgClear, infoClear = Damage.calc({ mon = mon }, foeGrass, wbId, { forceRoll = 100, forceCrit = false })
  local dmgSun, infoSun = Damage.calc({ mon = mon }, foeGrass, wbId, { weather = "sun", forceRoll = 100, forceCrit = false })

  check(infoClear.moveType == Types.ID.NORMAL or infoClear.move.type == Types.ID.NORMAL, "Weather Ball is Normal in clear weather")
  check(infoSun.moveType == Types.ID.FIRE, "Weather Ball becomes Fire type in Sunny weather")
  check(infoSun.effectiveness == 2, "Weather Ball Fire type is Super Effective against Grass")
  check(dmgSun > dmgClear * 2, "Weather Ball deals much higher damage in Sun due to 100 base power, Fire type, and Sun boost")
end

do
  -- Smellingsalt doubles power against paralyzed target and cures paralysis
  local ssId = Moves.numForName("SMELLINGSALT")
  local st = State.new({
    wild = true,
    playerParty = { { species = 127, level = 30, hp = 100, maxHp = 100, moves = { ssId }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20, status = "PAR" },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, ssId, 1, ad, st, out)
  check(ad:status(st.enemy) == nil, "Target paralysis was cured by Smellingsalt")
  local joined = table.concat(out, " || ")
  check(joined:find("healed of paralysis", 1, true) ~= nil, "Smellingsalt cure message printed")
end

do
  -- Low Kick scales with target weight
  local lkId = Moves.numForName("LOW_KICK")
  local mon = { species = 66, level = 30, hp = 100, maxHp = 100, moves = { lkId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }

  local lightFoe = { species = 19, level = 20, hp = 200, maxHp = 200, weight = 35, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 } -- 3.5kg -> power 20
  local heavyFoe = { species = 143, level = 20, hp = 200, maxHp = 200, weight = 4600, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 } -- 460.0kg -> power 120

  local dmgLight = Damage.calc({ mon = mon }, { mon = lightFoe }, lkId, { forceRoll = 100, forceCrit = false })
  local dmgHeavy = Damage.calc({ mon = mon }, { mon = heavyFoe }, lkId, { forceRoll = 100, forceCrit = false })
  check(dmgHeavy >= math.floor(dmgLight * 5), "Low Kick on Snorlax (460kg, pwr 120) deals ~6x damage of Rattata (3.5kg, pwr 20)")
end

print("\n=== 7. Retaliation, Recoil on Miss, Self-KO (Explosion, Counter, Mirror Coat, Jump Kick, Rapid Spin) ===")
do
  -- Explosion / Selfdestruct causes user to faint
  local exploId = Moves.numForName("EXPLOSION")
  local st = State.new({
    wild = true,
    playerParty = { { species = 74, level = 30, hp = 100, maxHp = 100, moves = { exploId }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, exploId, 1, ad, st, out)
  check(ad:hp(st.player) == 0, "User faints from Explosion")
  check(ad:isFainted(st.player), "User is flagged as fainted")
  check(ad:hp(st.enemy) < 100, "Enemy took damage from Explosion")
end

do
  -- Counter deals 2x physical damage taken; fails on 0 physical damage
  local counterId = Moves.numForName("COUNTER")
  local mon = { species = 127, level = 30, hp = 100, maxHp = 100, moves = { counterId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }

  local dmgFail, infoFail = Damage.calc({ mon = mon, lastPhysicalDamageTaken = 0 }, { mon = foe }, counterId)
  check(infoFail.failed == true, "Counter fails when no physical damage taken")

  local dmgSuccess, infoSuccess = Damage.calc({ mon = mon, lastPhysicalDamageTaken = 30 }, { mon = foe }, counterId)
  check(dmgSuccess == 60, "Counter deals exactly 2x (60 HP) for 30 HP physical damage taken")
end

do
  -- Mirror Coat deals 2x special damage taken; fails on 0 special damage
  local mcId = Moves.numForName("MIRROR_COAT")
  local mon = { species = 202, level = 30, hp = 100, maxHp = 100, moves = { mcId }, pp = { 20 },
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 }
  local foe = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
    attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 }

  local dmgFail, infoFail = Damage.calc({ mon = mon, lastSpecialDamageTaken = 0 }, { mon = foe }, mcId)
  check(infoFail.failed == true, "Mirror Coat fails when no special damage taken")

  local dmgSuccess, infoSuccess = Damage.calc({ mon = mon, lastSpecialDamageTaken = 25 }, { mon = foe }, mcId)
  check(dmgSuccess == 50, "Mirror Coat deals exactly 2x (50 HP) for 25 HP special damage taken")
end

do
  -- Jump Kick / Hi Jump Kick crash damage on miss (half max HP)
  local hjkId = Moves.numForName("HI_JUMP_KICK")
  local st = State.new({
    wild = true,
    playerParty = { { species = 106, level = 30, hp = 100, maxHp = 100, moves = { hjkId }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  -- Force miss
  local ad = setup_test_battle(st, function(lo, hi)
    if lo == 1 and hi == 100 then return 100 end -- miss
    return hi or lo or 0
  end)
  local full = Damage.calc(st.player, st.enemy, hjkId, { forceRoll = 100, forceCrit = false })
  -- pokefirered/src/battle_script_commands.c:6466
  local crash = math.min(50, math.max(1, math.floor(full / 2)))
  local out = {}
  Engine.resolveMove(st.player, st.enemy, hjkId, 1, ad, st, out)
  check(ad:hp(st.player) == 100 - crash, "Hi Jump Kick miss crashes for half the damage it would have dealt")
  local joined = table.concat(out, " || ")
  check(joined:find("kept going\nand crashed!", 1, true) ~= nil, "Crash message printed on miss")
end

do
  -- pokefirered/src/battle_script_commands.c:8435
  local spinId = Moves.numForName("RAPID_SPIN")
  local st = State.new({
    wild = true,
    playerParty = { { species = 7, level = 30, hp = 100, maxHp = 100, moves = { spinId }, pp = { 40 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  st.playerSide.spikes = 1
  st.player.leechSeed = true
  st.player.trapped = true
  st.player.expTrapTurns = 3
  st.player.expTrapSource = st.enemy
  st.player.expTrapMoveName = "WRAP"

  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, spinId, 1, ad, st, out)
  check(st.player.expTrapTurns == nil, "Rapid Spin freed the wrap")
  check(st.player.leechSeed == nil, "Rapid Spin removed Leech Seed")
  check(st.player.trapped == nil, "Rapid Spin removed trapping effect")
  check(st.playerSide.spikes == 0, "Rapid Spin removed Spikes in the same use")
  local joined = table.concat(out, " || ")
  local iWrap = joined:find("got free of", 1, true)
  local iSeed = joined:find("shed\nLEECH SEED!", 1, true)
  local iSpikes = joined:find("blew away\nSPIKES!", 1, true)
  check(iWrap ~= nil, "Wrap freed message printed")
  check(iSeed ~= nil, "Leech Seed shed message printed")
  check(iSpikes ~= nil, "Spikes blown away message printed")
  check(iWrap and iSeed and iSpikes and iWrap < iSeed and iSeed < iSpikes,
    "Rapid Spin frees wrap, then Leech Seed, then Spikes")
end

print("\n=== 8. Two-Turn Charging, Semi-Invulnerable, and Recharge (Solar Beam, Skull Bash, Fly, Hyper Beam) ===")
do
  -- Solarbeam charges turn 1 in clear weather, attacks turn 2
  local sbId = Moves.numForName("SOLARBEAM") or Moves.numForName("SOLAR_BEAM")
  local st = State.new({
    wild = true,
    playerParty = { { species = 1, level = 30, hp = 100, maxHp = 100, moves = { sbId }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)

  -- Turn 1
  local out1 = {}
  Engine.resolveMove(st.player, st.enemy, sbId, 1, ad, st, out1)
  local joined1 = table.concat(out1, " || ")
  check(joined1:find("took\nin sunlight!", 1, true) ~= nil, "Solarbeam charging message printed on turn 1")
  check(ad:hp(st.enemy) == 100, "Foe takes 0 damage on charge turn")
  check(st.player.twoTurnMove == sbId, "Player is flagged with twoTurnMove")

  -- Turn 2
  local out2 = {}
  Engine.resolveMove(st.player, st.enemy, sbId, 1, ad, st, out2)
  check(ad:hp(st.enemy) < 100, "Foe takes damage on unleash turn 2")
  check(st.player.twoTurnMove == nil, "twoTurnMove is cleared after unleash")
end

do
  -- Skull Bash raises defense on charge turn 1
  local sbashId = Moves.numForName("SKULL_BASH")
  local st = State.new({
    wild = true,
    playerParty = { { species = 7, level = 30, hp = 100, maxHp = 100, moves = { sbashId }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, sbashId, 1, ad, st, out)
  check((st.player.stages and st.player.stages.defense or 0) == 1, "Defense stage increased by 1 during Skull Bash charge")
end

do
  -- Fly makes user semi-invulnerable on turn 1 (attacks miss)
  local flyId = Moves.numForName("FLY")
  local tackleId = Moves.numForName("TACKLE")
  local st = State.new({
    wild = true,
    playerParty = { { species = 16, level = 30, hp = 100, maxHp = 100, moves = { flyId }, pp = { 15 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 100, maxHp = 100, moves = { tackleId }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)

  -- Player uses Fly turn 1
  local outP = {}
  Engine.resolveMove(st.player, st.enemy, flyId, 1, ad, st, outP)
  check(st.player.semiInvulnerable ~= nil, "Player is semi-invulnerable")

  -- Enemy tries to Tackle player
  local outE = {}
  Engine.resolveMove(st.enemy, st.player, tackleId, 1, ad, st, outE)
  check(ad:hp(st.player) == 100, "Enemy attack missed semi-invulnerable flyer")
end

do
  -- Hyper Beam forces recharge turn on turn 2
  local hbId = Moves.numForName("HYPER_BEAM")
  local st = State.new({
    wild = true,
    playerParty = { { species = 143, level = 30, hp = 100, maxHp = 100, moves = { hbId }, pp = { 5 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)

  -- Turn 1: Hyper Beam hits
  local out1 = {}
  Engine.resolveMove(st.player, st.enemy, hbId, 1, ad, st, out1)
  check(ad:hp(st.enemy) < 200, "Hyper Beam dealt damage to foe")
  check(st.player.expMustRecharge == true, "Player flagged to recharge next turn")

  -- Turn 2: Attempt move during recharge
  local out2 = {}
  Engine.resolveMove(st.player, st.enemy, hbId, 1, ad, st, out2)
  local joined2 = table.concat(out2, " || ")
  check(joined2:find("must\nrecharge!", 1, true) ~= nil, "Recharge message printed and action skipped")
  check(st.player.expMustRecharge == nil, "expMustRecharge cleared after recharge turn")
end

print("\n=== 9. Move Calling & Metagame (Metronome, Sleep Talk, Mirror Move) ===")
do
  -- Metronome picks a random move and executes it
  local metroId = Moves.numForName("METRONOME")
  local st = State.new({
    wild = true,
    playerParty = { { species = 35, level = 30, hp = 100, maxHp = 100, moves = { metroId }, pp = { 10 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, metroId, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("used\nMETRONOME!", 1, true) ~= nil, "Metronome user message printed")
  check(#out >= 2, "Metronome resolved a secondary move")
end

do
  -- Sleep Talk executes a known move while user is asleep
  local sleepTalkId = Moves.numForName("SLEEP_TALK")
  local emberId = Moves.numForName("EMBER")
  local st = State.new({
    wild = true,
    playerParty = { { species = 143, level = 30, hp = 100, maxHp = 100, moves = { sleepTalkId, emberId }, pp = { 10, 25 },
      status = "SLP", sleepTurns = 3,
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 19, level = 20, hp = 200, maxHp = 200, moves = { 33 }, pp = { 35 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, sleepTalkId, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("used\nSLEEP TALK!", 1, true) ~= nil, "Sleep Talk message printed while asleep")
  check(joined:find("used\nEMBER!", 1, true) ~= nil, "Sleep Talk invoked Ember")
  check(ad:hp(st.enemy) < 200, "Foe took damage from Sleep Talked move")
end

do
  -- Mirror Move copies foe's last move
  local mmId = Moves.numForName("MIRROR_MOVE")
  local emberId = Moves.numForName("EMBER")
  local st = State.new({
    wild = true,
    playerParty = { { species = 16, level = 30, hp = 100, maxHp = 100, moves = { mmId }, pp = { 20 },
      attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50 } },
    foeMon = { species = 4, level = 20, hp = 200, maxHp = 200, moves = { emberId }, pp = { 25 },
      attack = 20, defense = 50, spAtk = 20, spDef = 50, speed = 20 },
  })
  local ad = setup_test_battle(st)
  -- pokefirered/src/battle_script_commands.c:6350
  Engine.resolveMove(st.enemy, st.player, emberId, 1, ad, st, {})
  local out = {}
  Engine.resolveMove(st.player, st.enemy, mmId, 1, ad, st, out)
  local joined = table.concat(out, " || ")
  check(joined:find("used\nMIRROR MOVE!", 1, true) ~= nil, "Mirror Move user message printed")
  check(joined:find("used\nEMBER!", 1, true) ~= nil, "Mirror Move executed enemy's last move Ember")
  check(ad:hp(st.enemy) < 200, "Foe took damage from mirrored move")
end

if failed > 0 then
  print("\n[FAIL] FAILED " .. failed .. " tests")
  os.exit(1)
end
print("\n[ok] All game3 special moves tests passed successfully!")

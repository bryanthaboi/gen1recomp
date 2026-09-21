#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Moves = require("src.core.game3.battle.moves")

-- pokefirered/src/data/battle_moves.h:432
Moves._romLoaded = true
Moves._rom = {
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [35] = { effect = 42, power = 15, type = 0, accuracy = 85, pp = 20, secondaryChance = 100, target = 0, priority = 0, flags = 51 },
}

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")
local Rules = require("src.core.game3.battle.rules")
local Capabilities = require("src.core.game3.battle.capabilities")
local T = Types.ID

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function mon(o)
  return {
    species = o.species or 1, level = o.level or 50, hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, ability = 0,
    nickname = o.nickname, moves = o.moves or { 33 }, pp = { 20, 20, 20, 20 },
  }
end

local function mkRng(map)
  map = map or {}
  return function(lo, hi)
    local v = map[tostring(lo) .. "," .. tostring(hi)]
    if v ~= nil then return v end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
end

local function battle(p, e, rngMap)
  p.nickname, e.nickname = "ALPHA", "BRAVO"
  local st = State.new({ wild = true, playerParty = { mon(p) }, foeParty = { mon(e) } })
  st.player.type1, st.player.type2 = T.NORMAL, nil
  st.enemy.type1, st.enemy.type2 = T.NORMAL, nil
  st.rng = mkRng(rngMap)
  return st, Adapter.new(st)
end

local function wrap(st, ad)
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 35, 1, ad, st, out)
  return out
end

print("[test] 1. Rules.partialTrap is a single table with the capability guard")
check(type(Rules.partialTrap.active) == "function", "Rules.partialTrap.active survives module load")
check(type(Rules.partialTrap.chipAmount) == "function", "Rules.partialTrap.chipAmount survives module load")
check(type(Rules.partialTrap.rollTurns) == "function", "Rules.partialTrap.rollTurns survives module load")
check(type(Rules.partialTrap.MOVES) == "table", "Rules.partialTrap.MOVES survives module load")

-- pokefirered/src/battle_message.c:1263
local WANT = { 20, 35, 83, 128, 250, 328 }
local movesOk = #(Rules.partialTrap.MOVES or {}) == #WANT
for i = 1, #WANT do
  if (Rules.partialTrap.MOVES or {})[i] ~= WANT[i] then movesOk = false end
end
check(movesOk, "MOVES matches gTrappingMoves (Bind/Wrap/Fire Spin/Clamp/Whirlpool/Sand Tomb)")

print("[test] 2. chip and duration match pret")
eq(Rules.partialTrap.chipAmount(160), 10, "chip is maxHP/16")
eq(Rules.partialTrap.chipAmount(8), 1, "chip floors to 1")
for n = 0, 3 do
  eq(Rules.partialTrap.rollTurns(function() return n end), n + 3, "rollTurns((Random & 3) + 3) for " .. n)
end
local defaulted = Rules.partialTrap.rollTurns()
check(defaulted >= 3 and defaulted <= 6, "rollTurns with no rng stays in 3..6")

print("[test] 3. the capability guard reaches the live move and residual phases")
do
  local st, ad = battle({ speed = 99 }, { hp = 160, maxHp = 160 }, { ["0,3"] = 0 })
  Capabilities.gen3PartialTrap = false
  local ok, err = pcall(wrap, st, ad)
  local applied = st.enemy.expTrapTurns
  local afterMove = ad:hp(st.enemy)
  local okR, errR = pcall(Engine.collectResidualEvents, st, ad)
  Capabilities.gen3PartialTrap = true
  check(ok, "Wrap resolved with the capability off: " .. tostring(err))
  eq(applied, nil, "gen3PartialTrap=false never applies the trap")
  check(okR, "residual sweep ran: " .. tostring(errR))
  eq(ad:hp(st.enemy), afterMove, "gen3PartialTrap=false suppresses the trap chip")
  eq(st.enemy.expTrapTurns, nil, "no trap state is left to block escape forever")
  check(st.enemy.wrapped ~= true, "the wrapped volatile is not set either")
end

do
  local st, ad = battle({ speed = 99 }, { hp = 160, maxHp = 160 }, { ["0,3"] = 0 })
  wrap(st, ad)
  eq(st.enemy.expTrapTurns, 3, "Wrap trapped the foe for 3 turns")
end

do
  local st, ad = battle({ speed = 99 }, { hp = 160, maxHp = 160 }, { ["0,3"] = 0 })
  wrap(st, ad)
  local before = ad:hp(st.enemy)
  Engine.collectResidualEvents(st, ad)
  eq(before - ad:hp(st.enemy), 10, "gen3PartialTrap=true still chips maxHP/16")
  eq(st.enemy.expTrapTurns, 2, "trap ticks down when active")
end

print("[test] 4. Safari factors (pokefirered/src/battle_main.c:2284)")
eq(Rules.safari.BALLS, 30, "30 Safari Balls")
eq(Rules.safari.STEPS, 600, "600 step counter")
eq(Rules.safari.catchFactor(255), 20, "catchRate 255 -> catch factor 20")
eq(Rules.safari.catchFactor(45), 3, "catchRate 45 -> catch factor 3")
eq(Rules.safari.escapeFactor(0), 2, "flee rate 0 clamps the escape factor to 2")
eq(Rules.safari.escapeFactor(125), 9, "flee rate 125 -> escape factor 9")

print("[test] 5. Bait and Rock (pokefirered/src/battle_main.c:4382)")
do
  local sf = Rules.safari.newState(190, 125)
  eq(sf.catchFactor, 14, "Chansey-ish catch rate 190 -> factor 14")
  eq(sf.escapeFactor, 9, "escape factor 9")
  Rules.safari.throwRock(sf, function() return 0 end)
  eq(sf.rockCounter, 2, "rock counter is Random()%5 + 2")
  eq(sf.catchFactor, 20, "rock doubles the catch factor, capped at 20")
  eq(Rules.safari.fleeRate(sf), 90, "rock flee rate is min(escape*2,20)*5")
  Rules.safari.throwRock(sf, function() return 4 end)
  eq(sf.rockCounter, 6, "rock counter caps at 6")
  eq(Rules.safari.watchStep(sf), "angry", "mon is angry while the rock counter runs")
  eq(sf.rockCounter, 5, "watching decrements the rock counter")
end

do
  local sf = Rules.safari.newState(190, 125)
  Rules.safari.throwBait(sf, function() return 0 end)
  eq(sf.baitCounter, 2, "bait counter is Random()%5 + 2")
  eq(sf.catchFactor, 7, "bait halves the catch factor")
  eq(Rules.safari.fleeRate(sf), 10, "bait flee rate is max(escape/4,1)*5")
  eq(Rules.safari.watchStep(sf), "eating", "mon is eating while the bait counter runs")
  eq(Rules.safari.watchStep(sf), "watching", "bait counter runs out")
  Rules.safari.throwBait(sf, function() return 0 end)
  Rules.safari.throwBait(sf, function() return 0 end)
  eq(sf.catchFactor, 3, "bait floors the catch factor at 3")
  Rules.safari.throwRock(sf, function() return 0 end)
  eq(sf.baitCounter, 0, "rock clears the bait counter")
  sf.rockCounter = 1
  eq(Rules.safari.watchStep(sf), "watching", "rock counter hitting 0 restores the base catch factor")
  eq(sf.catchFactor, 14, "catch factor is recomputed from the species catch rate")
end

do
  local sf = Rules.safari.newState(190, 125)
  eq(Rules.safari.fleeRate(sf), 45, "plain flee rate is escapeFactor * 5")
  eq(Rules.safari.ballCatchRate(sf), 178, "Safari Ball catch rate is catchFactor * 1275 / 100")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("PARTIAL_TRAP_SAFARI FAIL")
  os.exit(1)
end
print("PARTIAL_TRAP_SAFARI PASS")
os.exit(0)

#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Moves = require("src.core.game3.battle.moves")

-- pokefirered/src/data/battle_moves.h:1
local ROM = {
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [57] = { effect = 0, power = 95, type = 11, accuracy = 100, pp = 15, secondaryChance = 0, target = 8, priority = 0, flags = 50 },
  [89] = { effect = 147, power = 100, type = 4, accuracy = 100, pp = 10, secondaryChance = 0, target = 32, priority = 0, flags = 50 },
  [98] = { effect = 103, power = 40, type = 0, accuracy = 100, pp = 30, secondaryChance = 0, target = 0, priority = 1, flags = 51 },
  [266] = { effect = 172, power = 0, type = 0, accuracy = 0, pp = 20, secondaryChance = 0, target = 16, priority = 3, flags = 0 },
  [270] = { effect = 176, power = 0, type = 0, accuracy = 0, pp = 20, secondaryChance = 0, target = 16, priority = 5, flags = 0 },
}
Moves._romLoaded = true
Moves._rom = ROM

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")
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

local function mon(o)
  return {
    species = o.species or 1, level = o.level or 50, hp = o.hp or 200, maxHp = o.maxHp or 200,
    attack = o.attack or 50, defense = o.defense or 50, spAtk = o.spAtk or 50, spDef = o.spDef or 50,
    speed = o.speed or 50, ability = o.ability or 0, nickname = o.nickname,
    moves = o.moves or { 33 }, pp = { 20, 20, 20, 20 },
  }
end

local function rng(lo, hi)
  if lo == 1 and hi == 100 then return 1 end
  return hi
end

local function battle(p, e)
  local party, foes = {}, {}
  for i, o in ipairs(p) do
    o.nickname = o.nickname or ("P" .. i)
    party[i] = mon(o)
  end
  for i, o in ipairs(e) do
    o.nickname = o.nickname or ("E" .. i)
    foes[i] = mon(o)
  end
  local st = State.new({ wild = false, double = true, playerParty = party, foeParty = foes })
  for id = 0, 3 do
    local b = st.battlers[id]
    if b then b.type1, b.type2 = T.NORMAL, nil end
  end
  st.rng = rng
  return st, Adapter.new(st)
end

local function hp(st, id) return tonumber(st.battlers[id].mon.hp) end

local function run_turn(st, ad, chosen)
  local actions = Engine.planTurnActions(st, ad, chosen)
  for _, act in ipairs(actions) do
    if Engine.actionRunnable(st, act) and act.kind == "move" then
      act.done = true
      Engine.resolveMove(act.user, act.target, act.move, act.slot, ad, st, {})
    end
  end
  return actions
end

print("=== state: four slots, aliases, helpers ===")
do
  local st = battle({ {}, {}, {} }, { {}, {} })
  check(st.double and st.battlersCount == 4, "double state has four battlers")
  check(st.battlers[0] == st.player and st.battlers[1] == st.enemy, "slots 0/1 alias st.player/st.enemy")
  check(st.battlers[2].partyIndex == 2 and st.battlers[3].partyIndex == 2, "slots 2/3 take the next usable mon")
  check(State.PARTNER(1) == 3 and State.OPPOSITE(2) == 3 and State.sideOf(3) == "enemy", "PARTNER/OPPOSITE/sideOf")
  check(st.battlers[1].participants[1] and st.battlers[3].participants[2], "both flanks start with both player mons sent")
end

print("=== turn order: speed and priority ===")
do
  local st, ad = battle({ { speed = 10, moves = { 33, 98 } }, { speed = 30 } }, { { speed = 40 }, { speed = 20 } })
  local order = run_turn(st, ad, {
    [0] = { kind = "move", move = 33, slot = 1, target = 1 },
    [1] = { kind = "move", move = 33, slot = 1, target = 0 },
    [2] = { kind = "move", move = 33, slot = 1, target = 1 },
    [3] = { kind = "move", move = 33, slot = 1, target = 0 },
  })
  check(table.concat(st.turnOrder, ",") == "1,2,3,0", "speed order 1,2,3,0")
  check(#order == 4, "four actions planned")
  Engine.planTurnActions(st, ad, {
    [0] = { kind = "move", move = 98, slot = 2, target = 1 },
    [1] = { kind = "move", move = 33, slot = 1, target = 0 },
    [2] = { kind = "switch", partySlot = 3 },
    [3] = { kind = "move", move = 33, slot = 1, target = 0 },
  })
  check(st.turnOrder[1] == 2 and st.turnOrder[2] == 0, "switch first, then priority move")
end

print("=== spread damage halves with two defenders ===")
do
  local st, ad = battle({ { moves = { 57 } }, {} }, { {}, {} })
  Engine.resolveMove(st.battlers[0], nil, 57, 1, ad, st, {})
  local both1, both3 = 200 - hp(st, 1), 200 - hp(st, 3)
  check(both1 > 0 and both3 > 0 and hp(st, 2) == 200, "Surf hits both foes, not the ally")
  local st2, ad2 = battle({ { moves = { 57 } }, {} }, { {}, {} })
  Engine.markAbsent(st2, 3)
  Engine.resolveMove(st2.battlers[0], nil, 57, 1, ad2, st2, {})
  local solo = 200 - hp(st2, 1)
  check(solo > both1 and math.abs(solo - 2 * both1) <= 2, "one present defender takes full damage")
end

print("=== Earthquake hits ally and foes ===")
do
  local st, ad = battle({ { moves = { 89 } }, {} }, { {}, {} })
  Engine.resolveMove(st.battlers[0], nil, 89, 1, ad, st, {})
  check(hp(st, 1) < 200 and hp(st, 2) < 200 and hp(st, 3) < 200, "Earthquake damages battlers 1, 2 and 3")
  check((200 - hp(st, 1)) == (200 - hp(st, 3)), "FOES_AND_ALLY is not halved")
  check(st.battlers[0].mon.pp[1] == 19, "PP deducted once")
end

print("=== Follow Me redirects ===")
do
  local st, ad = battle({ {}, {} }, { {}, { moves = { 266 } } })
  run_turn(st, ad, {
    [0] = { kind = "move", move = 33, slot = 1, target = 1 },
    [1] = { kind = "move", move = 33, slot = 1, target = 0 },
    [2] = { kind = "move", move = 33, slot = 1, target = 1 },
    [3] = { kind = "move", move = 266, slot = 1 },
  })
  check(hp(st, 1) == 200 and hp(st, 3) < 200, "both player attacks go into the Follow Me user")
end

print("=== Helping Hand boosts the partner ===")
do
  local st, ad = battle({ {}, { moves = { 270 } } }, { {}, {} })
  run_turn(st, ad, {
    [0] = { kind = "move", move = 33, slot = 1, target = 1 },
    [2] = { kind = "move", move = 270, slot = 1 },
  })
  local helped = 200 - hp(st, 1)
  local st2, ad2 = battle({ {}, {} }, { {}, {} })
  run_turn(st2, ad2, { [0] = { kind = "move", move = 33, slot = 1, target = 1 } })
  local plain = 200 - hp(st2, 1)
  check(st.battlers[0].expHelpingHand == true and helped > plain, "Helping Hand boosts the partner's damage")
end

print("=== Intimidate hits both foes ===")
do
  local st, ad = battle({ { ability = 22 }, {} }, { {}, {} })
  Engine.battleStartEffects(st, ad)
  check(st.battlers[1].stages.attack == -1 and st.battlers[3].stages.attack == -1, "both foes lose one Attack stage")
  check(st.battlers[2].stages.attack == 0, "ally untouched")
end

print("=== faint bookkeeping and absent slots ===")
do
  local st, ad = battle({ {}, {} }, { {}, {} })
  ad:setHp(st.battlers[3], 0)
  local fainted = Engine.faintedBattlers(st)
  check(#fainted == 1 and fainted[1] == 3, "battler 3 reported fainted")
  local pend = Engine.pendingReplacements(st)
  check(pend[1] and pend[1].noMons, "no replacement left for battler 3")
  Engine.markAbsent(st, 3)
  check(not State.isPresent(st, 3) and ad:foeOf(st.battlers[2]) == st.battlers[1], "absent flank flips foeOf")
  Engine.resolveMove(st.battlers[0], 3, 33, 1, ad, st, {})
  check(hp(st, 1) < 200, "a move aimed at an absent foe hits its partner")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

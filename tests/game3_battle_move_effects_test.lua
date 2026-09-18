#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Moves = require("src.core.game3.battle.moves")

-- pokefirered/src/data/battle_moves.h:1
local ROM = {
  [1] = { effect = 0, power = 40, type = 0, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [10] = { effect = 0, power = 40, type = 0, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [14] = { effect = 50, power = 0, type = 0, accuracy = 0, pp = 30, secondaryChance = 0, target = 16, priority = 0, flags = 8 },
  [16] = { effect = 149, power = 40, type = 2, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [18] = { effect = 28, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = -6, flags = 18 },
  [19] = { effect = 155, power = 70, type = 2, accuracy = 95, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [20] = { effect = 42, power = 15, type = 0, accuracy = 75, pp = 20, secondaryChance = 100, target = 0, priority = 0, flags = 51 },
  [23] = { effect = 150, power = 65, type = 0, accuracy = 100, pp = 20, secondaryChance = 30, target = 0, priority = 0, flags = 19 },
  [31] = { effect = 29, power = 15, type = 0, accuracy = 85, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [35] = { effect = 42, power = 15, type = 0, accuracy = 85, pp = 20, secondaryChance = 100, target = 0, priority = 0, flags = 51 },
  [37] = { effect = 27, power = 90, type = 0, accuracy = 100, pp = 20, secondaryChance = 100, target = 4, priority = 0, flags = 51 },
  [41] = { effect = 77, power = 25, type = 6, accuracy = 100, pp = 20, secondaryChance = 20, target = 0, priority = 0, flags = 18 },
  [45] = { effect = 18, power = 0, type = 0, accuracy = 100, pp = 40, secondaryChance = 0, target = 8, priority = 0, flags = 22 },
  [46] = { effect = 28, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = -6, flags = 18 },
  [47] = { effect = 1, power = 0, type = 0, accuracy = 55, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 22 },
  [50] = { effect = 86, power = 0, type = 0, accuracy = 55, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 18 },
  [52] = { effect = 4, power = 40, type = 10, accuracy = 100, pp = 25, secondaryChance = 10, target = 0, priority = 0, flags = 18 },
  [56] = { effect = 0, power = 120, type = 11, accuracy = 80, pp = 5, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [57] = { effect = 0, power = 95, type = 11, accuracy = 100, pp = 15, secondaryChance = 0, target = 8, priority = 0, flags = 50 },
  [68] = { effect = 89, power = 1, type = 1, accuracy = 100, pp = 20, secondaryChance = 0, target = 1, priority = -5, flags = 17 },
  [87] = { effect = 152, power = 120, type = 13, accuracy = 70, pp = 10, secondaryChance = 30, target = 0, priority = 0, flags = 18 },
  [89] = { effect = 147, power = 100, type = 4, accuracy = 100, pp = 10, secondaryChance = 0, target = 32, priority = 0, flags = 50 },
  [91] = { effect = 155, power = 60, type = 4, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [92] = { effect = 33, power = 0, type = 3, accuracy = 85, pp = 10, secondaryChance = 100, target = 0, priority = 0, flags = 22 },
  [98] = { effect = 103, power = 40, type = 0, accuracy = 100, pp = 30, secondaryChance = 0, target = 0, priority = 1, flags = 51 },
  [99] = { effect = 81, power = 20, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [100] = { effect = 153, power = 0, type = 14, accuracy = 0, pp = 20, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [102] = { effect = 82, power = 0, type = 0, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 2 },
  [107] = { effect = 108, power = 0, type = 0, accuracy = 0, pp = 20, secondaryChance = 0, target = 16, priority = 0, flags = 8 },
  [117] = { effect = 26, power = 1, type = 0, accuracy = 100, pp = 10, secondaryChance = 0, target = 16, priority = 0, flags = 35 },
  [129] = { effect = 17, power = 60, type = 0, accuracy = 0, pp = 20, secondaryChance = 0, target = 8, priority = 0, flags = 50 },
  [144] = { effect = 57, power = 0, type = 0, accuracy = 0, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 0 },
  [153] = { effect = 7, power = 250, type = 0, accuracy = 100, pp = 5, secondaryChance = 0, target = 32, priority = 0, flags = 50 },
  [156] = { effect = 37, power = 0, type = 14, accuracy = 0, pp = 10, secondaryChance = 0, target = 16, priority = 0, flags = 8 },
  [160] = { effect = 30, power = 0, type = 0, accuracy = 0, pp = 30, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [161] = { effect = 36, power = 80, type = 0, accuracy = 100, pp = 10, secondaryChance = 20, target = 0, priority = 0, flags = 18 },
  [166] = { effect = 95, power = 0, type = 0, accuracy = 0, pp = 1, secondaryChance = 0, target = 0, priority = 0, flags = 0 },
  [167] = { effect = 104, power = 10, type = 1, accuracy = 90, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [168] = { effect = 105, power = 40, type = 17, accuracy = 100, pp = 10, secondaryChance = 100, target = 0, priority = 0, flags = 19 },
  [173] = { effect = 92, power = 40, type = 0, accuracy = 100, pp = 15, secondaryChance = 30, target = 0, priority = 0, flags = 50 },
  [176] = { effect = 93, power = 0, type = 0, accuracy = 100, pp = 30, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [182] = { effect = 111, power = 0, type = 0, accuracy = 0, pp = 10, secondaryChance = 0, target = 16, priority = 3, flags = 0 },
  [205] = { effect = 117, power = 30, type = 5, accuracy = 90, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [210] = { effect = 119, power = 10, type = 6, accuracy = 95, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [217] = { effect = 122, power = 1, type = 0, accuracy = 90, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 18 },
  [226] = { effect = 127, power = 0, type = 0, accuracy = 0, pp = 40, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [234] = { effect = 132, power = 0, type = 0, accuracy = 0, pp = 5, secondaryChance = 0, target = 16, priority = 0, flags = 8 },
  [237] = { effect = 135, power = 1, type = 0, accuracy = 100, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [239] = { effect = 146, power = 40, type = 16, accuracy = 100, pp = 20, secondaryChance = 20, target = 8, priority = 0, flags = 50 },
  [250] = { effect = 42, power = 15, type = 11, accuracy = 70, pp = 15, secondaryChance = 100, target = 0, priority = 0, flags = 50 },
  [251] = { effect = 154, power = 10, type = 17, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [252] = { effect = 158, power = 40, type = 0, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 1, flags = 18 },
  [253] = { effect = 159, power = 50, type = 0, accuracy = 100, pp = 10, secondaryChance = 100, target = 4, priority = 0, flags = 50 },
  [254] = { effect = 160, power = 0, type = 0, accuracy = 0, pp = 10, secondaryChance = 0, target = 16, priority = 0, flags = 8 },
  [255] = { effect = 161, power = 100, type = 0, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 34 },
  [266] = { effect = 172, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 16, priority = 3, flags = 0 },
  [267] = { effect = 173, power = 0, type = 0, accuracy = 0, pp = 20, secondaryChance = 0, target = 1, priority = 0, flags = 0 },
  [271] = { effect = 177, power = 0, type = 14, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 18 },
  [274] = { effect = 180, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 1, priority = 0, flags = 0 },
  [278] = { effect = 184, power = 0, type = 0, accuracy = 100, pp = 10, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [282] = { effect = 188, power = 20, type = 17, accuracy = 100, pp = 20, secondaryChance = 100, target = 0, priority = 0, flags = 19 },
  [290] = { effect = 197, power = 70, type = 0, accuracy = 100, pp = 20, secondaryChance = 30, target = 0, priority = 0, flags = 18 },
  [291] = { effect = 155, power = 60, type = 11, accuracy = 100, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [299] = { effect = 200, power = 85, type = 10, accuracy = 90, pp = 10, secondaryChance = 10, target = 0, priority = 0, flags = 19 },
  [305] = { effect = 202, power = 50, type = 3, accuracy = 100, pp = 15, secondaryChance = 30, target = 0, priority = 0, flags = 19 },
  [327] = { effect = 207, power = 85, type = 1, accuracy = 90, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [342] = { effect = 209, power = 50, type = 3, accuracy = 100, pp = 25, secondaryChance = 10, target = 0, priority = 0, flags = 51 },
}
Moves._romLoaded = true
Moves._rom = ROM

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Damage = require("src.core.game3.battle.damage")
local Types = require("src.core.game3.battle.types")
local Rules = require("src.core.game3.battle.rules")
local Hazards = require("src.core.game3.battle.effects.hazards")
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
  local m = {
    species = o.species or 1, level = o.level or 50, hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = o.attack or 50, defense = o.defense or 50, spAtk = o.spAtk or 50, spDef = o.spDef or 50,
    speed = o.speed or 50, ability = o.ability or 0, nickname = o.nickname,
    moves = o.moves or { 33 }, pp = o.pp or { 20, 20, 20, 20 }, status = o.status,
    item = o.item, heldItem = o.item, ivs = o.ivs, gender = o.gender, friendship = o.friendship,
  }
  return m
end

local function mkRng(map)
  map = map or {}
  local cursor = {}
  return function(lo, hi)
    local key = tostring(lo) .. "," .. tostring(hi)
    local v = map[key]
    if type(v) == "table" then
      local i = (cursor[key] or 0) + 1
      cursor[key] = i
      v = v[math.min(i, #v)]
    end
    if v ~= nil then return v end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
end

local function battle(p, e, extra)
  extra = extra or {}
  p.nickname = p.nickname or "ALPHA"
  e.nickname = e.nickname or "BRAVO"
  local party = { mon(p) }
  for _, x in ipairs(extra.bench or {}) do party[#party + 1] = mon(x) end
  local foeParty = { mon(e) }
  for _, x in ipairs(extra.foeBench or {}) do foeParty[#foeParty + 1] = mon(x) end
  local st = State.new({ wild = extra.wild ~= false, playerParty = party, foeParty = foeParty })
  st.player.type1, st.player.type2 = p.type1 or T.NORMAL, p.type2
  st.enemy.type1, st.enemy.type2 = e.type1 or T.NORMAL, e.type2
  st.rng = mkRng(extra.rng)
  st.terrain = extra.terrain
  local ad = Adapter.new(st)
  return st, ad
end

local function use(st, ad, user, move, slot, opts)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, slot or 1, ad, st, out, opts)
  return table.concat(out, " || "), out
end

local function has(s, needle) return s:find(needle, 1, true) ~= nil end

print("=== multi-hit 2-5 distribution (3/8,3/8,1/8,1/8) ===")
do
  local counts = { 0, 0, 0, 0, 0 }
  for a = 0, 3 do
    for b = 0, 3 do
      local st, ad = battle({ moves = { 31 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,3"] = { a, b } } })
      local _, out = use(st, ad, st.player, 31)
      local n = #out._anim.hits
      counts[n] = counts[n] + 1
    end
  end
  check(counts[2] == 6 and counts[3] == 6 and counts[4] == 2 and counts[5] == 2,
    "setmultihitcounter 0 gives 2:6/16 3:6/16 4:2/16 5:2/16")
end

print("=== BIDE ===")
do
  local st, ad = battle({ moves = { 117 }, speed = 10 }, { moves = { 33 } })
  local txt = use(st, ad, st.player, 117)
  check(st.player.bideTurns == 2, "Bide stores for 2 turns")
  check(has(txt, "used\n"), "Bide prints attack string")
  use(st, ad, st.enemy, 33)
  local taken = 100 - ad:hp(st.player)
  check(st.player.expBideDamage == taken and taken > 0, "damage taken while biding is stored")
  txt = use(st, ad, st.player, 33)
  check(has(txt, "storing\nenergy!"), "turn 2 stores energy (locked move)")
  local foeBefore = ad:hp(st.enemy)
  txt = use(st, ad, st.player, 33)
  check(has(txt, "unleashed\nenergy!"), "turn 3 unleashes")
  check(foeBefore - ad:hp(st.enemy) == taken * 2, "Bide deals double the stored damage")
end

print("=== RAMPAGE (Thrash) ===")
do
  local st, ad = battle({ moves = { 37 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,1"] = 0 } })
  use(st, ad, st.player, 37)
  check(st.player.expRampageTurns == 2 and st.player.expLockedMove == 37, "Thrash locks for 2-3 turns")
  local pp = st.player.mon.pp[1]
  use(st, ad, st.player, 33)
  check(st.player.mon.pp[1] == pp, "continuing Thrash does not use PP and ignores chosen move")
  Engine.collectResidualEvents(st, ad)
  local events = Engine.collectResidualEvents(st, ad)
  local found = false
  for _, ev in ipairs(events) do
    for _, m in ipairs(ev.msgs) do if has(m, "confused due to fatigue") then found = true end end
  end
  check(found and (st.player.confusionTurns or 0) > 0, "Thrash ends with fatigue confusion")
end

print("=== ROAR / WHIRLWIND ===")
do
  local st, ad = battle({ moves = { 46 }, level = 50 }, { level = 40 })
  local _, out = use(st, ad, st.player, 46)
  check(st.over == true and st.result == "run", "Roar ends a wild battle")
  local ended = false
  for _, ev in ipairs(out._anim.events) do if ev.kind == "end" then ended = true end end
  check(ended, "Roar emits an end event")
  check(st.endReason == "roar", "Roar records the end reason for the battle flow")

  local st2, ad2 = battle({ moves = { 18 } }, { species = 1 }, { wild = false, foeBench = { { species = 4, nickname = "CHARLIE" } }, rng = { ["1,1"] = 1 } })
  local txt2 = use(st2, ad2, st2.player, 18)
  check(st2.enemy.partyIndex == 2, "Whirlwind drags out the other trainer mon")
  check(has(txt2, "dragged out!"), "dragged out message")

  local st3, ad3 = battle({ moves = { 18 } }, {}, { wild = false })
  local txt3 = use(st3, ad3, st3.player, 18)
  check(has(txt3, "But it failed!") and not st3.over, "Whirlwind fails with no bench")
end

print("=== CONVERSION / CONVERSION 2 ===")
do
  local st, ad = battle({ moves = { 160, 52, 57 } }, {}, { rng = { ["1,2"] = 1 } })
  local txt = use(st, ad, st.player, 160)
  check(st.player.type1 == T.FIRE and st.player.type2 == T.FIRE, "Conversion picks a move type the user lacks")
  check(has(txt, "into the FIRE type!"), "Conversion message")

  local st2, ad2 = battle({ moves = { 176 } }, { moves = { 52 } })
  use(st2, ad2, st2.enemy, 52)
  use(st2, ad2, st2.player, 176, 1)
  local _, flags = Types.typeCalc(T.FIRE, st2.player.type1, st2.player.type2)
  check(flags.notVery or flags.immune, "Conversion 2 resists the last move that hit")
end

print("=== TRI ATTACK ===")
do
  local st, ad = battle({ moves = { 161 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0, ["0,2"] = 2 } })
  use(st, ad, st.player, 161)
  check(ad:status(st.enemy) == "PAR", "Tri Attack rolled paralysis")
  local st2, ad2 = battle({ moves = { 161 } }, { hp = 999, maxHp = 999, type1 = T.FIRE }, { rng = { ["0,99"] = 0, ["0,2"] = 0 } })
  use(st2, ad2, st2.player, 161)
  check(ad2:status(st2.enemy) == nil, "Tri Attack burn roll on a Fire type does nothing")
end

print("=== TRAP (Wrap / Bind / Fire Spin / Whirlpool) ===")
do
  local st, ad = battle({ moves = { 35 } }, { hp = 160, maxHp = 160 }, { rng = { ["0,3"] = 0 } })
  local txt = use(st, ad, st.player, 35)
  check(st.enemy.expTrapTurns == 3, "Wrap sets (Random & 3) + 3 turns")
  check(has(txt, "was WRAPPED by"), "Wrap message")
  local events = Engine.collectResidualEvents(st, ad)
  local chip, anim = false, false
  for _, ev in ipairs(events) do
    if ev.phase == "partial_trap_chip" then
      chip = ev.hpChanges[1] and (ev.hpChanges[1].from - ev.hpChanges[1].to) == 10
      for _, e in ipairs(ev.events) do if e.kind == "anim" and e.name == "TURN_TRAP" then anim = true end end
    end
  end
  check(chip, "trap chip is maxHP/16")
  check(anim, "TURN_TRAP general anim recorded")
  Engine.collectResidualEvents(st, ad)
  local ev3 = Engine.collectResidualEvents(st, ad)
  local freed = false
  for _, ev in ipairs(ev3) do for _, m in ipairs(ev.msgs) do if has(m, "was freed") then freed = true end end end
  check(freed and st.enemy.expTrapTurns == nil, "trap ends with freed message")

  local st2, ad2 = battle({ moves = { 250 } }, { hp = 300, maxHp = 300 })
  st2.enemy.semiInvulnerable = "UNDERWATER"
  local _, out = use(st2, ad2, st2.player, 250)
  check(#out._anim.hits == 1, "Whirlpool hits an underwater Dive user")
end

print("=== TRANSFORM ===")
do
  local st, ad = battle({ moves = { 144 } }, { attack = 99, defense = 88, speed = 77, moves = { 52, 57 }, type1 = T.WATER })
  st.enemy.stages.attack = 2
  local party = st.playerParty[1]
  use(st, ad, st.player, 144)
  check(st.player.transformed and st.player.mon.attack == 99 and st.player.mon.defense == 88, "Transform copies stats")
  check(st.player.type1 == T.WATER and st.player.stages.attack == 2, "Transform copies types and stages")
  check(st.player.mon.moves[1] == 52 and st.player.mon.pp[1] == 5, "Transform copies moves with 5 PP")
  State.syncBattlerToParty(st.player, st.playerParty)
  check(party.moves[1] == 144 and party.attack == 50, "party mon is untouched by Transform")
end

print("=== TWINEEDLE ===")
do
  local st, ad = battle({ moves = { 41 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0 } })
  local txt, out = use(st, ad, st.player, 41)
  check(#out._anim.hits == 2 and has(txt, "Hit 2 time(s)!"), "Twineedle hits twice")
  check(ad:status(st.enemy) == "PSN", "Twineedle poison roll")
end

print("=== RAGE ===")
do
  local st, ad = battle({ moves = { 99 } }, { moves = { 33 } })
  use(st, ad, st.player, 99)
  check(st.player.rage == true, "Rage sets the rage flag")
  local txt = use(st, ad, st.enemy, 33)
  check(st.player.stages.attack == 1 and has(txt, "RAGE\nis building!"), "getting hit raises Attack")
end

print("=== MIMIC / DISABLE / SKETCH ===")
do
  local st, ad = battle({ moves = { 102, 33 } }, { moves = { 52 } })
  use(st, ad, st.enemy, 52)
  use(st, ad, st.player, 102, 1)
  check(st.player.mon.moves[1] == 52 and st.player.mon.pp[1] == 5, "Mimic copies the last move into its slot")
  State.syncBattlerToParty(st.player, st.playerParty)
  check(st.playerParty[1].moves[1] == 102, "Mimic does not persist to the party")

  local st2, ad2 = battle({ moves = { 50 } }, { moves = { 52, 33 } }, { rng = { ["0,3"] = 0 } })
  use(st2, ad2, st2.enemy, 52)
  local txt = use(st2, ad2, st2.player, 50)
  check(st2.enemy.expDisabledMove == 52 and st2.enemy.expDisableTurns == 2, "Disable disables for 2-5 turns")
  check(has(txt, "was disabled!"), "Disable message")
  local txt2 = use(st2, ad2, st2.enemy, 52)
  check(has(txt2, "is disabled!"), "disabled move is cancelled")

  local st3, ad3 = battle({ moves = { 166 } }, { moves = { 52 } })
  use(st3, ad3, st3.enemy, 52)
  use(st3, ad3, st3.player, 166, 1)
  check(st3.playerParty[1].moves[1] == 52 and st3.playerParty[1].pp[1] == 25, "Sketch permanently learns with full PP")
end

print("=== SNORE / SLEEP ===")
do
  local st, ad = battle({ moves = { 173 } }, { hp = 999, maxHp = 999 })
  local txt = use(st, ad, st.player, 173)
  check(has(txt, "But it failed!"), "Snore fails while awake")
  local st2, ad2 = battle({ moves = { 173 }, status = "SLP" }, { hp = 999, maxHp = 999 })
  st2.player.sleepTurns = 3
  local txt2, out2 = use(st2, ad2, st2.player, 173)
  check(#out2._anim.hits == 1 and has(txt2, "fast\nasleep."), "Snore hits while asleep")

  local st3, ad3 = battle({ moves = { 47 } }, {}, { rng = { ["0,3"] = 3 } })
  use(st3, ad3, st3.player, 47)
  check(ad3:status(st3.enemy) == "SLP" and st3.enemy.sleepTurns == 5, "sleep counter is (Random & 3) + 2")

  local st4, ad4 = battle({ moves = { 156 }, hp = 10 }, {})
  use(st4, ad4, st4.player, 156)
  check(st4.player.sleepTurns == 3 and ad4:hp(st4.player) == 100, "Rest sleeps for STATUS1_SLEEP_TURN(3)")
end

print("=== TRIPLE KICK ===")
do
  local st, ad = battle({ moves = { 167 }, type1 = T.FIGHTING }, { hp = 999, maxHp = 999, defense = 50 })
  local txt, out = use(st, ad, st.player, 167)
  local d1 = out._anim.hits[1].from - out._anim.hits[1].to
  local d3 = out._anim.hits[3].from - out._anim.hits[3].to
  check(#out._anim.hits == 3 and has(txt, "Hit 3 time(s)!"), "Triple Kick hits 3 times")
  check(d3 > d1 * 2, "Triple Kick power climbs 10/20/30")
  local st2, ad2 = battle({ moves = { 167 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = { 1, 100 } } })
  local _, out2 = use(st2, ad2, st2.player, 167)
  check(#out2._anim.hits == 1, "Triple Kick stops at the first miss")
end

print("=== THIEF / TRICK / KNOCK OFF / RECYCLE ===")
do
  local st, ad = battle({ moves = { 168 } }, { hp = 999, maxHp = 999, item = 200 })
  local txt, out = use(st, ad, st.player, 168)
  check(st.player.item == 200 and st.playerParty[1].item == 200 and st.enemy.item == 0, "Thief steals and keeps the item")
  local anim = false
  for _, ev in ipairs(out._anim.events) do if ev.kind == "anim" and ev.name == "ITEM_STEAL" then anim = true end end
  check(anim and has(txt, "stole\n"), "ITEM_STEAL anim + message")
  local st2, ad2 = battle({ item = 200 }, { moves = { 168 } })
  use(st2, ad2, st2.enemy, 168)
  check(st2.player.item == 200, "opponents cannot steal in regular battles")

  local st3, ad3 = battle({ moves = { 271 }, item = 198 }, { item = 200 })
  local txt3 = use(st3, ad3, st3.player, 271)
  check(st3.player.item == 200 and st3.enemy.item == 198 and st3.playerParty[1].item == 200, "Trick swaps items")
  check(has(txt3, "switched\nitems"), "Trick message")

  local st4, ad4 = battle({ moves = { 282 } }, { hp = 999, maxHp = 999, item = 200 })
  local txt4, out4 = use(st4, ad4, st4.player, 282)
  check(st4.enemy.item == 0 and st4.foeParty[1].item == 200, "Knock Off removes the item for the battle only")
  local ko = false
  for _, ev in ipairs(out4._anim.events) do if ev.kind == "anim" and ev.name == "ITEM_KNOCKOFF" then ko = true end end
  check(ko and has(txt4, "knocked off"), "ITEM_KNOCKOFF anim + message")

  local st5, ad5 = battle({ moves = { 278 } }, {})
  st5.player.expUsedHeldItem = 139
  local txt5 = use(st5, ad5, st5.player, 278)
  check(st5.player.item == 139 and has(txt5, "found\none"), "Recycle restores the used item")
end

print("=== ROLLOUT / FURY CUTTER ===")
do
  local st, ad = battle({ moves = { 205 } }, { hp = 9999, maxHp = 9999 })
  local dmg = {}
  for i = 1, 5 do
    local _, out = use(st, ad, st.player, 205)
    dmg[i] = out._anim.hits[1].from - out._anim.hits[1].to
  end
  check(dmg[2] >= dmg[1] * 2 - 2 and dmg[5] >= dmg[4] * 2 - 2, "Rollout doubles each turn")
  check(st.player.expLockedMove == nil, "Rollout unlocks after 5 turns")

  local st2, ad2 = battle({ moves = { 210 } }, { hp = 9999, maxHp = 9999 })
  use(st2, ad2, st2.player, 210)
  use(st2, ad2, st2.player, 210)
  check(st2.player.expFuryCutter == 2, "Fury Cutter counter climbs")
  st2.rng = mkRng({ ["1,100"] = 100 })
  use(st2, ad2, st2.player, 210)
  check(st2.player.expFuryCutter == 0, "Fury Cutter resets on a miss")
end

print("=== PRESENT ===")
do
  local st, ad = battle({ moves = { 217 } }, { hp = 50, maxHp = 100 }, { rng = { ["0,255"] = 250 } })
  local txt = use(st, ad, st.player, 217)
  check(ad:hp(st.enemy) == 75 and has(txt, "regained\nhealth!"), "Present heal branch restores 1/4")
  local st2, ad2 = battle({ moves = { 217 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,255"] = 0 } })
  local _, out = use(st2, ad2, st2.player, 217)
  check(#out._anim.hits == 1, "Present damage branch hits")
end

print("=== BATON PASS ===")
do
  local st, ad = battle({ moves = { 226 } }, {}, { bench = { { species = 4, nickname = "DELTA" } } })
  st.player.stages.attack = 2
  st.player.substituteHP = 20
  local txt, out = use(st, ad, st.player, 226)
  check(st.player.partyIndex == 2 and st.player.stages.attack == 2 and st.player.substituteHP == 20,
    "Baton Pass switches and keeps stages/substitute")
  local sw = false
  for _, ev in ipairs(out._anim.events) do if ev.kind == "switch" and ev.reason == "baton_pass" then sw = true end end
  check(sw and has(txt, "Go! DELTA!"), "switch event + send-out text")
  local st2, ad2 = battle({ moves = { 226 } }, {})
  check(has((use(st2, ad2, st2.player, 226)), "But it failed!"), "Baton Pass fails with no bench")
end

print("=== HIDDEN POWER ===")
do
  local ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
  local p, t = Damage.hiddenPower({ ivs = ivs })
  check(p == 70 and t == T.DARK, "all-31 IVs give 70 power Dark")
  local p0, t0 = Damage.hiddenPower({ ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } })
  check(p0 == 30 and t0 == T.FIGHTING, "all-0 IVs give 30 power Fighting")
end

print("=== semi-invulnerable interplay ===")
do
  local st, ad = battle({ moves = { 16 } }, { hp = 999, maxHp = 999 })
  local _, base = use(st, ad, st.player, 16)
  local d0 = base._anim.hits[1].from - base._anim.hits[1].to
  st.enemy.semiInvulnerable = "ON_AIR"
  local _, out = use(st, ad, st.player, 16)
  local d1 = out._anim.hits[1] and (out._anim.hits[1].from - out._anim.hits[1].to) or 0
  check(d1 >= d0 * 2 - 1, "Gust hits Fly for double damage")

  local st2, ad2 = battle({ moves = { 239 } }, { hp = 999, maxHp = 999 })
  st2.enemy.semiInvulnerable = "ON_AIR"
  local _, o2 = use(st2, ad2, st2.player, 239)
  check(#o2._anim.hits == 1, "Twister hits a Fly user")

  local st3, ad3 = battle({ moves = { 89 } }, { hp = 999, maxHp = 999 })
  st3.enemy.semiInvulnerable = "UNDERGROUND"
  local _, o3 = use(st3, ad3, st3.player, 89)
  check(#o3._anim.hits == 1, "Earthquake hits a Dig user")

  local st4, ad4 = battle({ moves = { 57 } }, { hp = 999, maxHp = 999 })
  st4.enemy.semiInvulnerable = "UNDERWATER"
  local _, o4 = use(st4, ad4, st4.player, 57)
  check(#o4._anim.hits == 1, "Surf hits a Dive user")

  local st5, ad5 = battle({ moves = { 33 } }, { hp = 999, maxHp = 999 })
  st5.enemy.semiInvulnerable = "ON_AIR"
  local txt5 = use(st5, ad5, st5.player, 33)
  check(has(txt5, "attack missed!"), "normal moves miss a Fly user")

  local st6, ad6 = battle({ moves = { 327 } }, { hp = 999, maxHp = 999 })
  st6.enemy.semiInvulnerable = "ON_AIR"
  local _, o6 = use(st6, ad6, st6.player, 327)
  check(#o6._anim.hits == 1, "Sky Uppercut hits a Fly user")

  local st7, ad7 = battle({ moves = { 87 } }, { hp = 999, maxHp = 999 })
  st7.enemy.semiInvulnerable = "ON_AIR"
  local _, o7 = use(st7, ad7, st7.player, 87)
  check(#o7._anim.hits == 1, "Thunder hits a Fly user")

  local st8, ad8 = battle({ moves = { 87 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 100 } })
  st8.weather = "RAINY"
  local _, o8 = use(st8, ad8, st8.player, 87)
  check(#o8._anim.hits == 1, "Thunder never misses in rain")
  local st9, ad9 = battle({ moves = { 87 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 51 } })
  st9.weather = "SUNNY"
  local txt9 = use(st9, ad9, st9.player, 87)
  check(has(txt9, "attack missed!"), "Thunder accuracy is 50 in sun")

  local st10, ad10 = battle({ moves = { 19 } }, { hp = 999, maxHp = 999 })
  use(st10, ad10, st10.player, 19)
  check(st10.player.semiInvulnerable == "ON_AIR", "Fly turn 1 sets ON_AIR")
  local _, o10 = use(st10, ad10, st10.player, 33)
  check(#o10._anim.hits == 1 and st10.player.semiInvulnerable == nil, "Fly turn 2 strikes and lands")
end

print("=== MINIMIZE / STOMP ===")
do
  local st, ad = battle({ moves = { 23 } }, { moves = { 107 }, hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 99 } })
  local _, a = use(st, ad, st.player, 23)
  local d0 = a._anim.hits[1].from - a._anim.hits[1].to
  use(st, ad, st.enemy, 107)
  check(st.enemy.minimized == true and st.enemy.stages.evasion == 1, "Minimize sets the minimized flag + evasion")
  st.enemy.stages.evasion = 0
  local _, b = use(st, ad, st.player, 23)
  local d1 = b._anim.hits[1].from - b._anim.hits[1].to
  check(d1 >= d0 * 2 - 1, "Stomp doubles vs a minimized target")
end

print("=== TELEPORT ===")
do
  local st, ad = battle({ moves = { 100 } }, {})
  local txt = use(st, ad, st.player, 100)
  check(st.over and has(txt, "fled from\nbattle!"), "Teleport ends a wild battle")
  local st2, ad2 = battle({ moves = { 100 } }, {}, { wild = false })
  check(has((use(st2, ad2, st2.player, 100)), "But it failed!") and not st2.over, "Teleport fails vs trainers")
end

print("=== BEAT UP ===")
do
  local st, ad = battle({ moves = { 251 } }, { hp = 999, maxHp = 999 },
    { bench = { { species = 4 }, { species = 7, status = "PSN" }, { species = 1, hp = 0 } } })
  local txt, out = use(st, ad, st.player, 251)
  check(#out._anim.hits == 2, "Beat Up strikes once per healthy, status-free party member")
  check(has(txt, "'s attack!"), "Beat Up per-member message")
end

print("=== FAKE OUT ===")
do
  local st, ad = battle({ moves = { 252 } }, { hp = 999, maxHp = 999 })
  Engine.planTurnFromActions(st, ad, { kind = "move", move = 252, slot = 1 }, { kind = "move", move = 33, slot = 1 })
  use(st, ad, st.player, 252)
  check(st.enemy.flinched == true, "Fake Out flinches on the first turn")
  Engine.planTurnFromActions(st, ad, { kind = "move", move = 252, slot = 1 }, { kind = "move", move = 33, slot = 1 })
  local txt = use(st, ad, st.player, 252)
  check(has(txt, "But it failed!"), "Fake Out fails after the first turn")
end

print("=== UPROAR ===")
do
  local st, ad = battle({ moves = { 253 } }, { hp = 999, maxHp = 999, status = "SLP", moves = { 47 } }, { rng = { ["0,3"] = 1 } })
  st.enemy.sleepTurns = 4
  local txt = use(st, ad, st.player, 253)
  check(st.player.expUproarTurns == 3 and has(txt, "caused\nan UPROAR!"), "Uproar starts for 2-5 turns")
  local events = Engine.collectResidualEvents(st, ad)
  local woke = false
  for _, ev in ipairs(events) do for _, m in ipairs(ev.msgs) do if has(m, "woke up\nin the UPROAR!") then woke = true end end end
  check(woke and ad:status(st.enemy) == nil, "Uproar wakes sleepers")
  local txt2 = use(st, ad, st.enemy, 47)
  check(ad:status(st.player) == nil and has(txt2, "can't\nsleep in an UPROAR!"), "sleep fails during an uproar")
end

print("=== STOCKPILE / SPIT UP ===")
do
  local st, ad = battle({ moves = { 255 } }, { hp = 999, maxHp = 999 })
  local txt = use(st, ad, st.player, 255)
  check(has(txt, "failed to SPIT UP"), "Spit Up fails without stockpile")
  use(st, ad, st.player, 254)
  use(st, ad, st.player, 254)
  check(st.player.expStockpile == 2 and st.player.stages.defense == 0, "Gen3 Stockpile raises no stats")
  local _, out = use(st, ad, st.player, 255)
  check(#out._anim.hits == 1 and st.player.expStockpile == 0, "Spit Up releases the stockpile")
end

print("=== FOLLOW ME / NATURE POWER / ASSIST / SECRET POWER ===")
do
  local st, ad = battle({ moves = { 266 } }, {})
  check(has((use(st, ad, st.player, 266)), "center of attention!"), "Follow Me succeeds in singles")

  local st2, ad2 = battle({ moves = { 267 } }, { hp = 999, maxHp = 999 }, { terrain = 4 })
  local txt2, out2 = use(st2, ad2, st2.player, 267)
  check(has(txt2, "NATURE POWER turned into") and out2._anim.moveId == 57 and #out2._anim.hits == 1, "Nature Power on water calls Surf")
  local st2b, ad2b = battle({ moves = { 267 } }, { hp = 999, maxHp = 999 }, { terrain = 8 })
  local _, out2b = use(st2b, ad2b, st2b.player, 267)
  check(out2b._anim.moveId == 129, "Nature Power indoors calls Swift")

  local st3, ad3 = battle({ moves = { 274 } }, { hp = 999, maxHp = 999 }, { bench = { { moves = { 52, 118 } } } })
  local _, out3 = use(st3, ad3, st3.player, 274)
  check(out3._anim.moveId == 52, "Assist calls a bench move (never Metronome)")

  local st4, ad4 = battle({ moves = { 290 } }, { hp = 999, maxHp = 999 }, { terrain = 8, rng = { ["0,99"] = 0 } })
  use(st4, ad4, st4.player, 290)
  check(ad4:status(st4.enemy) == "PAR", "Secret Power indoors paralyzes")
  local st5, ad5 = battle({ moves = { 290 } }, { hp = 999, maxHp = 999 }, { terrain = 1, rng = { ["0,99"] = 0 } })
  use(st5, ad5, st5.player, 290)
  check(ad5:status(st5.enemy) == "SLP", "Secret Power in long grass sleeps")
end

print("=== BLAZE KICK / POISON FANG / POISON TAIL / SKY UPPERCUT crit + status ===")
do
  check(Rules.crit.stage({}, Moves.get(299)) == 1, "Blaze Kick is high-crit")
  check(Rules.crit.stage({}, Moves.get(342)) == 1, "Poison Tail is high-crit")
  check(Rules.crit.stage({ expFocusEnergy = true }, Moves.get(33)) == 2, "Focus Energy adds 2 stages")
  check(Rules.crit.stage({ item = 198, expFocusEnergy = true }, Moves.get(299)) == 4, "crit stage caps at 4")
  local st, ad = battle({ moves = { 299 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0 } })
  use(st, ad, st.player, 299)
  check(ad:status(st.enemy) == "BRN", "Blaze Kick burns")
  local st2, ad2 = battle({ moves = { 305 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0 } })
  use(st2, ad2, st2.player, 305)
  check(ad2:status(st2.enemy) == "TOX", "Poison Fang badly poisons")
  local st3, ad3 = battle({ moves = { 342 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0 } })
  use(st3, ad3, st3.player, 342)
  check(ad3:status(st3.enemy) == "PSN", "Poison Tail poisons")
  local crits = 0
  for r = 0, 7 do
    if Rules.crit.roll({}, Moves.get(299), nil, function() return r end) then crits = crits + 1 end
  end
  check(crits == 1, "stage 1 crit chance is 1/8")
end

print("=== MORNING SUN weather fractions ===")
do
  local function heal(weather)
    local st, ad = battle({ moves = { 234 }, hp = 1, maxHp = 300 }, {})
    st.weather = weather
    use(st, ad, st.player, 234)
    return ad:hp(st.player) - 1
  end
  check(heal(nil) == 150, "no weather heals 1/2")
  check(heal("SUNNY") == 200, "sun heals 20/30")
  check(heal("RAINY") == 75, "other weather heals 1/4")
end

print("=== accuracy / evasion stage table ===")
do
  local st, ad = battle({ moves = { 33 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 72 } })
  st.enemy.stages.evasion = 1
  check(has((use(st, ad, st.player, 33)), "attack missed!"), "95 acc at -1 net stage misses a 72 roll (calc 71)")
  local st2, ad2 = battle({ moves = { 33 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 71 } })
  st2.enemy.stages.evasion = 1
  check(not has((use(st2, ad2, st2.player, 33)), "attack missed!"), "…and hits a 71 roll")
  local st3, ad3 = battle({ moves = { 129 } }, { hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 100 } })
  st3.enemy.stages.evasion = 6
  local _, o3 = use(st3, ad3, st3.player, 129)
  check(#o3._anim.hits == 1, "Swift (ALWAYS_HIT) ignores evasion")
end

print("=== Counter by type / Explosion defense halving ===")
do
  local st, ad = battle({ moves = { 68 }, hp = 999, maxHp = 999 }, { moves = { 52 }, hp = 999, maxHp = 999 })
  use(st, ad, st.enemy, 52)
  check(has((use(st, ad, st.player, 68)), "But it failed!"), "Counter fails after a special-type hit")
  local st2, ad2 = battle({ moves = { 68 }, hp = 999, maxHp = 999 }, { moves = { 33 }, hp = 999, maxHp = 999 })
  use(st2, ad2, st2.enemy, 33)
  local taken = 999 - ad2:hp(st2.player)
  use(st2, ad2, st2.player, 68)
  check(999 - ad2:hp(st2.enemy) == taken * 2, "Counter returns double physical damage")

  local a = { mon = mon({ attack = 100 }), type1 = T.NORMAL, stages = {} }
  local d = { mon = mon({ defense = 100 }), type1 = T.PSYCHIC, stages = {} }
  local ex = Damage.base(a, d, Moves.get(153), {})
  local plain = Damage.base(a, d, { power = 250, type = 0, effect = 0 }, {})
  check(ex > plain, "Explosion halves the target's Defense")
end

print("=== toxic counter / confusion self-hit ===")
do
  local st, ad = battle({ status = "TOX", maxHp = 160, hp = 160 }, {})
  st.player.toxicCounter = 0
  Engine.collectResidualEvents(st, ad)
  Engine.collectResidualEvents(st, ad)
  check(ad:hp(st.player) == 160 - 10 - 20, "toxic chip = floor(max/16) * counter")

  local st2, ad2 = battle({ moves = { 33 } }, {}, { rng = { ["0,1"] = 0, ["85,100"] = 100 } })
  st2.player.confusionTurns = 3
  local txt = use(st2, ad2, st2.player, 33)
  local expect = Damage.base(st2.player, st2.player, { power = 40, type = 0, effect = 0 }, { power = 40, moveType = 0 })
  check(has(txt, "hurt itself") and ad2:hp(st2.player) == 100 - expect, "confusion self-hit = 40 power typeless")
end

print("=== adapter event contract ===")
do
  local st, ad = battle({ moves = { 71 }, hp = 50 }, { hp = 999, maxHp = 999 })
  local _, out = use(st, ad, st.player, 71)
  local kinds = {}
  for _, ev in ipairs(out._anim.events) do kinds[#kinds + 1] = ev.kind end
  local seq = table.concat(kinds, ",")
  check(seq:find("msg,move,hit", 1, true) ~= nil, "used msg -> move anim -> hit")
  check(seq:find("hit,msg", 1, true) ~= nil or seq:find("hit,hp", 1, true) ~= nil, "drain follows the hit")
  local hpEv
  for _, ev in ipairs(out._anim.events) do if ev.kind == "hp" then hpEv = ev end end
  check(hpEv and hpEv.side == "player" and hpEv.to > hpEv.from, "drain heal recorded as hp event")
  check(#out._anim.heals >= 1, "legacy heals list still filled")

  local st2, ad2 = battle({ moves = { 14 } }, {})
  local _, out2 = use(st2, ad2, st2.player, 14)
  local anim
  for _, ev in ipairs(out2._anim.events) do if ev.kind == "anim" then anim = ev end end
  check(anim and anim.anim == "general" and anim.name == "STATS_CHANGE" and anim.arg == 39, "Swords Dance STATS_CHANGE arg 39 (ATK +2)")

  local st3, ad3 = battle({ moves = { 92 } }, {})
  local _, out3 = use(st3, ad3, st3.player, 92)
  local statusAnim, idxA, idxM
  for i, ev in ipairs(out3._anim.events) do
    if ev.kind == "anim" and ev.anim == "status" then statusAnim = ev; idxA = i end
    if ev.kind == "msg" and ev.text:find("badly") then idxM = i end
  end
  check(statusAnim and statusAnim.name == "POISON" and idxA < idxM, "status anim precedes the status text")
end

print("=== Quick Attack / Vital Throw priority from ROM ===")
do
  check(Moves.priority(98) == 1, "Quick Attack priority 1 from ROM")
  local st, ad = battle({ speed = 1, moves = { 98 } }, { speed = 200 })
  local acts = Engine.planTurnFromActions(st, ad, { kind = "move", move = 98, slot = 1 }, { kind = "move", move = 33, slot = 1 })
  check(acts[1].user == st.player, "priority beats speed")
end

print("=== spikes on forced switch ===")
do
  local st, ad = battle({ moves = { 18 } }, {}, { wild = false, foeBench = { { maxHp = 80, hp = 80 } } })
  Hazards.set(st.enemySide, 1)
  use(st, ad, st.player, 18)
  check(st.enemy.partyIndex == 2 and ad:hp(st.enemy) == 70, "dragged-out mon takes 1/8 Spikes")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("[FAIL] game3 battle move effects")
  os.exit(1)
end
print("[ok] game3 battle move effects")

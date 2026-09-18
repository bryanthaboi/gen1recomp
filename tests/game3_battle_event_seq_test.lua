#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Moves = require("src.core.game3.battle.moves")

-- pokefirered/src/data/battle_moves.h:1
local ROM = {
  [18] = { effect = 28, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = -6, flags = 18 },
  [19] = { effect = 155, power = 70, type = 2, accuracy = 95, pp = 15, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [45] = { effect = 18, power = 0, type = 0, accuracy = 100, pp = 40, secondaryChance = 0, target = 8, priority = 0, flags = 22 },
  [46] = { effect = 28, power = 0, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = -6, flags = 18 },
  [73] = { effect = 84, power = 0, type = 11, accuracy = 90, pp = 10, secondaryChance = 0, target = 0, priority = 0, flags = 22 },
  [164] = { effect = 79, power = 0, type = 0, accuracy = 0, pp = 10, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [226] = { effect = 127, power = 0, type = 0, accuracy = 0, pp = 40, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [264] = { effect = 170, power = 150, type = 1, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = -3, flags = 1 },
}
Moves._romLoaded = true
Moves._rom = ROM

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local AnimSeq = require("src.core.game3.battle.anim_seq")
local Anim = require("src.core.game3.battle.anim")
local Commands = require("src.core.game3.battle.commands")
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
    species = o.species or 1, level = o.level or 50, hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = o.speed or 50, ability = 0,
    nickname = o.nickname, moves = o.moves or { 33 }, pp = o.pp or { 20, 20, 20, 20 },
    status = o.status, item = o.item, heldItem = o.item,
  }
end

local function rng(lo, hi)
  if lo == 1 and hi == 100 then return 1 end
  return lo
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
  st.player.type1 = T.NORMAL
  st.enemy.type1 = T.NORMAL
  st.rng = rng
  return st, Adapter.new(st)
end

local function use(st, ad, user, move)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, 1, ad, st, out)
  return out
end

local function kinds(steps)
  local out = {}
  for _, s in ipairs(steps) do
    local k = s.kind
    if k == "anim" then k = s.data.anim .. ":" .. tostring(s.data.name) end
    out[#out + 1] = k
  end
  return table.concat(out, ",")
end

local function index_of(steps, kind, from)
  for i = from or 1, #steps do
    local k = steps[i].kind
    if k == "anim" then k = steps[i].data.anim .. ":" .. tostring(steps[i].data.name) end
    if k == kind then return i end
  end
  return nil
end

print("=== damaging hit: move -> effectiveness+blink -> hp ===")
do
  local st, ad = battle({ moves = { 33 } }, { hp = 200, maxHp = 200 })
  local out = use(st, ad, st.player, 33)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local m, fx, hp = index_of(steps, "move"), index_of(steps, "hitfx"), index_of(steps, "hp")
  check(steps[1].kind == "msg" and m and fx and hp and m < fx and fx < hp, "used msg, move, hitfx, hp in order: " .. kinds(steps))
  check(steps[fx].data.side == "enemy" and steps[fx].data.effectiveness == 1, "hitfx targets enemy with normal effectiveness")
end

print("=== stat change plays STATS_CHANGE with pret animArg ===")
do
  local st, ad = battle({ moves = { 45 } }, {})
  local out = use(st, ad, st.player, 45)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local i = index_of(steps, "general:STATS_CHANGE")
  check(i ~= nil, "Growl emits STATS_CHANGE: " .. kinds(steps))
  check(i and index_of(steps, "move") < i, "stat anim follows the move anim")
  check(i and steps[i].data.attacker == "enemy" and tonumber(steps[i].data.arg), "stat anim on the lowered battler with arg")
end

print("=== wild Roar: move -> switch_out -> end ===")
do
  local st, ad = battle({ moves = { 46 }, level = 50 }, { level = 40 })
  local out = use(st, ad, st.player, 46)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local m, so, en = index_of(steps, "move"), index_of(steps, "switch_out"), index_of(steps, "end")
  check(m and so and en and m < so and so < en, "roar drag-out then end: " .. kinds(steps))
  check(steps[so].data.side == "enemy", "roared wild mon returns to ball")
end

print("=== trainer Roar: switch_out -> switch_in -> dragged out text ===")
do
  local st, ad = battle({ moves = { 46 } }, { species = 1 }, { wild = false, foeBench = { { species = 4, nickname = "CHARLIE" } } })
  local out = use(st, ad, st.player, 46)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local so, si = index_of(steps, "switch_out"), index_of(steps, "switch_in")
  local drag
  for i, s in ipairs(steps) do if s.kind == "msg" and tostring(s.data.text):find("dragged out") then drag = i end end
  check(so and si and drag and so < si and si < drag, "drag-out order: " .. kinds(steps))
  check(si and steps[si].data.slot == 2 and steps[so].data.slot == 1, "switch carries old/new party slots")
end

print("=== Baton Pass: switch_out -> Go! text -> switch_in ===")
do
  local st, ad = battle({ moves = { 226 } }, {}, { bench = { { species = 4, nickname = "DELTA" } } })
  local out = use(st, ad, st.player, 226)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local so, si = index_of(steps, "switch_out"), index_of(steps, "switch_in")
  local go
  for i, s in ipairs(steps) do if s.kind == "msg" and tostring(s.data.text):find("Go!") then go = i end end
  check(so and si and go and so < go and go < si, "pret prints SWITCHINMON before switchinanim: " .. kinds(steps))
end

print("=== Substitute: doll specials wrap the next attack ===")
do
  local st, ad = battle({ moves = { 164, 33 } }, { hp = 300, maxHp = 300 })
  use(st, ad, st.player, 164)
  check((st.player.substituteHP or 0) > 0, "substitute up")
  local out = use(st, ad, st.player, 33)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local a, m, b = index_of(steps, "special:SUBSTITUTE_TO_MON"), index_of(steps, "move"), index_of(steps, "special:MON_TO_SUBSTITUTE")
  check(a and m and b and a < m and m < b, "SUBSTITUTE_TO_MON, move, MON_TO_SUBSTITUTE: " .. kinds(steps))
  check(steps[a].data.moveId == 33 and steps[b].data.moveId == 33, "specials know the paired move (battle scene gate)")
end

print("=== residual stream: poison status anim + hp tick ===")
do
  local st, ad = battle({ moves = { 33 }, status = "PSN" }, {})
  st.player.status = "PSN"
  local evs = Engine.collectResidualEvents(st, ad)
  local stream = {}
  for _, e in ipairs(evs) do for _, x in ipairs(e.events or {}) do stream[#stream + 1] = x end end
  local steps = AnimSeq.buildSteps(stream, {})
  local s, h = index_of(steps, "status:POISON"), index_of(steps, "hp")
  check(s and h and s < h, "poison anim precedes the hp drop: " .. kinds(steps))
  check(index_of(steps, "hitfx") == nil, "residual damage does not blink")
end

print("=== Leech Seed drain anim ===")
do
  local st, ad = battle({ moves = { 73 } }, {})
  use(st, ad, st.player, 73)
  local evs = Engine.collectResidualEvents(st, ad)
  local stream = {}
  for _, e in ipairs(evs) do for _, x in ipairs(e.events or {}) do stream[#stream + 1] = x end end
  local steps = AnimSeq.buildSteps(stream, {})
  local i = index_of(steps, "general:LEECH_SEED_DRAIN")
  check(i and steps[i].data.attacker == "enemy" and steps[i].data.target == "player", "drain from seeded enemy to seeder: " .. kinds(steps))
end

print("=== Fly turn 1 carries turn index ===")
do
  local st, ad = battle({ moves = { 19 } }, {})
  local out = use(st, ad, st.player, 19)
  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local m = index_of(steps, "move")
  check(m and steps[m].data.turn == 0 and st.player.semiInvulnerable, "fly charge anim is turn 0 and user is semi-invulnerable")
  out = use(st, ad, st.player, 19)
  steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  m = index_of(steps, "move")
  check(m and steps[m].data.turn == 1, "fly strike anim is turn 1")
end

print("=== headless playback pushes messages in stream order ===")
do
  Anim.reset({ headless = true })
  local pushed = {}
  AnimSeq.beginEvents({
    { kind = "msg", text = "A" },
    { kind = "anim", anim = "general", name = "RAIN_CONTINUES" },
    { kind = "msg", text = "B" },
    { kind = "hp", side = "enemy", from = 10, to = 5, maxHp = 10 },
    { kind = "end", result = "run", reason = "roar" },
  }, function(t) pushed[#pushed + 1] = t end)
  local guard = 0
  while not AnimSeq.update() and guard < 50 do guard = guard + 1 end
  check(table.concat(pushed, ",") == "A,B", "messages pushed in order")
  check(AnimSeq.ended() and AnimSeq.ended().reason == "roar", "end event recorded for init")
  check(Anim.present("enemy").displayHp == 5, "hp tween applied")
end

print("=== move selection restrictions (TrySetCantSelectMoveBattleScript) ===")
do
  local st = battle({ moves = { 33, 45, 46, 164 } }, { moves = { 45 } })
  st.player.expDisabledMove = 33
  check((Commands.selectionError(st, 1) or ""):find("TACKLE\nis disabled!", 1, true), "disabled move message")
  st.player.expDisabledMove = nil
  st.player.expTauntedTurns = 2
  check((Commands.selectionError(st, 2) or ""):find("after the TAUNT!", 1, true), "taunt blocks status moves")
  check(Commands.selectionError(st, 1) == nil, "taunt allows damaging moves")
  st.player.expTauntedTurns = nil
  st.player.expTormented = true
  st.player.lastMoveId = 33
  check((Commands.selectionError(st, 1) or ""):find("TORMENT", 1, true), "torment blocks repeat")
  st.player.expTormented = nil
  st.enemy.expImprison = true
  check((Commands.selectionError(st, 2) or ""):find("sealed", 1, true), "imprison seals shared move")
  st.enemy.expImprison = nil
  st.player.item = 186
  st.player.choicedMove = 46
  check((Commands.selectionError(st, 1) or ""):find("allows only", 1, true), "choice band lock message")
  check(Commands.selectionError(st, 3) == nil, "choiced move itself is allowed")
  st.player.item = nil
  st.player.mon.pp[4] = 0
  check((Commands.selectionError(st, 4) or ""):find("no PP left", 1, true), "no PP message")
  st.player.mon.pp[4] = 10
  st.player.expEncoreMove = 45
  st.player.expEncoreTurns = 2
  local act = Commands.fightShortcut(st)
  check(act and act.slot == 2, "encore skips move selection")
  st.player.expEncoreMove = nil
  st.player.mon.pp = { 0, 0, 0, 0 }
  local act2, msg = Commands.fightShortcut(st)
  check(act2 and act2.move == "STRUGGLE" and msg and msg:find("no\nmoves left!", 1, true), "all moves unusable -> Struggle")
end

print("=== headless battle: Focus Punch text at turn start, Roar ends the battle ===")
do
  package.loaded["src.core.game3.audio"] = package.loaded["src.core.game3.audio"] or setmetatable({}, {
    __index = function() return function() end end,
  })
  Moves.loadRomPack = function()
    Moves._romLoaded = true
    Moves._rom = ROM
    return true
  end
  local Battle = require("src.core.game3.battle.init")
  local Damage = require("src.core.game3.battle.damage")
  local pMon = Damage.ensureStats({ species = 1, level = 30, hp = 90, maxHp = 90, moves = { 33 }, pp = { 35 } })
  local foe = Damage.ensureStats({ species = 16, level = 30, hp = 90, maxHp = 90, moves = { 264 }, pp = { 20 } })
  Battle.start({ headless = true, autoFight = false, playerParty = { pMon }, foe = foe, wild = true })
  Battle.update(0, nil)
  local st = Battle.getState()
  st.rng = rng
  Battle._auto = true
  Battle.update(0, nil)
  for _ = 1, 4 do Battle.update(0, nil) end
  local log = require("src.core.game3.battle.ui").log()
  local fp, used
  for i, t in ipairs(log) do
    if not fp and t:find("tightening", 1, true) then fp = i end
    if not used and t:find("TACKLE", 1, true) then used = i end
  end
  check(fp and used and fp < used, "focus punch setup text before the first move")
  Battle.abort()

  local pMon2 = Damage.ensureStats({ species = 1, level = 30, hp = 90, maxHp = 90, moves = { 46 }, pp = { 20 } })
  local foe2 = Damage.ensureStats({ species = 16, level = 10, hp = 40, maxHp = 40, moves = { 33 }, pp = { 35 } })
  local result
  Battle.start({ headless = true, playerParty = { pMon2 }, foe = foe2, wild = true, onDone = function(r) result = r end })
  check(result == "run", "roar in a wild battle ends it mid-turn with run (got " .. tostring(result) .. ")")
  local sawFlee = false
  for _, t in ipairs(require("src.core.game3.battle.ui").log()) do
    if t:find("Got away safely", 1, true) then sawFlee = true end
  end
  check(not sawFlee, "no forced flee text after roar")
end

do
  -- pokefirered/src/battle_script_commands.c:3113
  local Experience = require("src.core.game3.battle.experience")
  local Damage = require("src.core.game3.battle.damage")
  local origYield = Experience.expYield
  Experience.expYield = function() return 70 end
  local a = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local b = Damage.ensureStats({ species = 7, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 }, item = 182 })
  local c = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foe = Damage.ensureStats({ species = 16, level = 14, hp = 0, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local st = State.new({ wild = true, playerParty = { a, b, c }, foeParty = { foe } })
  local out = Experience.awardFoe(st, st.enemy, { trainer = false, partyIndices = { 1 } })
  local by = {}
  for _, e in ipairs(out) do by[e.partyIndex] = e.amount end
  check(by[1] == 70, "Exp. Share: the sent-in mon gets half the pool (got " .. tostring(by[1]) .. ")")
  check(by[2] == 70, "Exp. Share: the holder gets the other half (got " .. tostring(by[2]) .. ")")
  check(by[3] == nil, "Exp. Share: a benched mon without the item gets nothing")
  Experience.expYield = origYield
end

do
  -- pokefirered/src/battle_anim_status_effects.c:455
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  Anim.reset({ headless = true })
  local vm = Anim.vm()
  vm:setBattlers("player", "player")
  vm.animArg = 15
  local AnimVm = require("src.core.game3.battle.anim_vm")
  local t = AnimVm.spawnTask(vm, "StatsChange", 5, {}, "visual")
  local frames, peak = 0, 0
  while t.active and frames < 200 do
    AnimTasks.update(vm)
    frames = frames + 1
    local m = Anim.present("player").statMask
    if m then peak = math.max(peak, m.eva) end
  end
  check(peak == 10, "ATK +1 stat mask fades to BLDALPHA 10 (got " .. tostring(peak) .. ")")
  check(frames == 2 + 20 + 20 + 20 + 1, "ATK +1 stat change runs 2 setup + 20 in + 20 hold + 20 out frames (got " .. frames .. ")")
  vm.animArg = 46
  t = AnimVm.spawnTask(vm, "StatsChange", 5, {}, "visual")
  local sharpPeak, tm = 0, nil
  while t.active and frames < 1000 do
    AnimTasks.update(vm)
    frames = frames + 1
    local m = Anim.present("player").statMask
    if m then sharpPeak = math.max(sharpPeak, m.eva); tm = m.tilemap end
  end
  check(sharpPeak == 13 and tm == 2, "ATK -2 uses the falling tilemap and BLDALPHA 13")
end

do
  -- pokefirered/src/party_menu.c:5916
  local Damage = require("src.core.game3.battle.damage")
  local p1 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local p2 = Damage.ensureStats({ species = 7, level = 10, hp = 0, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local p3 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foe = Damage.ensureStats({ species = 16, level = 14, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local st = State.new({ wild = true, playerParty = { p1, p2, p3 }, foeParty = { foe } })
  check(tostring(Commands.switchError(st, 2)):find("no energy", 1, true) ~= nil, "fainted party mon can't be sent in")
  check(tostring(Commands.switchError(st, 1)):find("already", 1, true) ~= nil, "active mon is already in battle")
  check(Commands.switchError(st, 3) == nil, "healthy bench mon can switch in")
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

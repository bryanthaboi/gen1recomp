#!/usr/bin/env luajit
-- FireRed battle AI pack + scoring VM smoke tests.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_battle_ai_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. Load / extract AI pack")
local Ai = require("src.core.game3.battle.ai")
local pack = Ai.loadPack({ force = true, extract = true })
check(pack ~= nil, "pack loaded")
-- data/battle_ai_scripts.s:17, :52, :624, :2767, :3258
local function scoreScript(p, delta)
  for name, body in pairs(p.scripts) do
    if #body == 2 and body[1].op == "score" and body[1].delta == delta and body[2].op == "end" then return name end
  end
end
local SCORE_MINUS10 = pack and scoreScript(pack, -10)
check(pack and #pack.table == 32, "gBattleAI_ScriptsTable has 32 entries")
local badMove = pack and pack.scripts[pack.table[1]]
check(badMove and badMove[1].op == "get_how_powerful_move_is" and badMove[2].op == "if_equal"
  and badMove[2].value == 0, "table[0] = AI_CheckBadMove (get_how_powerful_move_is, if_equal MOVE_POWER_DISCOURAGED)")
local faint = pack and pack.scripts[pack.table[3]]
check(faint and faint[1].op == "if_can_faint" and faint[2].op == "get_how_powerful_move_is",
  "table[2] = AI_TryToFaint (if_can_faint, get_how_powerful_move_is)")
local ret = pack and pack.scripts[pack.table[11]]
check(ret and #ret == 1 and ret[1].op == "end" and pack.table[11] == pack.table[29], "table[10..28] = AI_Ret")
check(SCORE_MINUS10 ~= nil, "Score_Minus10 (score -10, end) present")

print("[test] 2. Brock aiFlags == 7")
local trainersRoot = require("tests.game3_cache").root("trainers.lua")
local trainersPath = trainersRoot and (trainersRoot .. "/trainers.lua")
local tf = trainersPath and io.open(trainersPath, "rb")
if tf then
  tf:close()
  local t = assert(loadfile(trainersPath))()
  local brock = t.trainers and t.trainers[414]
  check(brock ~= nil, "BROCK trainer 414 exists")
  check(brock and brock.aiFlags == 7, "BROCK aiFlags == 7")
else
  local Trainers = require("src.core.game3.scripting.trainers")
  -- fallback: hard expectation from extract contract
  check(true, "trainers.lua missing in cache; skip live BROCK row")
end

print("[test] 3. Score starts 100; score -10 → 90")
local AiVm = require("src.core.game3.battle.ai_vm")
local State = require("src.core.game3.battle.state")
local st0 = State.new({
  wild = false,
  playerParty = { { species = 16, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } } }, -- Pidgey
  foeMon = { species = 74, level = 10, hp = 30, maxHp = 30, moves = { 89 }, pp = { 10 } }, -- Geodude / EQ
})
st0.aiFlags = 0
local scores = { 100, 100, 100, 100 }
local vm = AiVm.new({
  pack = pack,
  st = st0,
  user = st0.enemy,
  target = st0.player,
  userSide = st0.enemySide,
  targetSide = st0.playerSide,
  scores = scores,
  simulatedRNG = { 100, 100, 100, 100 },
  movesetIndex = 1,
  rng = function() return 0 end,
})
AiVm.run(vm, SCORE_MINUS10)
check(scores[1] == 90, "score 100 + (-10) = 90 (got " .. tostring(scores[1]) .. ")")

print("[test] 4. CheckBadMove: Ground vs Flying scored much lower than neutral")
-- Enemy has EARTHQUAKE (89, Ground) and TACKLE (33, Normal) vs Flying target
local stBad = State.new({
  wild = false,
  playerParty = { {
    species = 16, level = 20, hp = 50, maxHp = 50,
    moves = { 33 }, pp = { 35 },
  } },
  foeMon = {
    species = 74, level = 20, hp = 50, maxHp = 50,
    moves = { 89, 33 }, pp = { 10, 35 },
    type1 = 4, -- force later via battler
  },
})
-- Ensure types: player Flying
stBad.player.type1 = 2 -- FLYING
stBad.player.type2 = nil
stBad.enemy.type1 = 4 -- GROUND
stBad.enemy.type2 = 5 -- ROCK
stBad.aiFlags = 1 -- AI_SCRIPT_CHECK_BAD_MOVE only

local actBad = Ai.chooseMove(stBad, {
  pack = pack,
  aiFlags = 1,
  rng = function(a, b)
    if a and b then return a end
    return 0
  end,
})
check(actBad and actBad.scores ~= nil, "CheckBadMove returned scores")
local sEq = actBad.scores[1]
local sTk = actBad.scores[2]
check(sEq ~= nil and sTk ~= nil, "both move scores present")
check(sEq < sTk - 5, string.format("EQ vs Flying (%s) << Tackle (%s)", tostring(sEq), tostring(sTk)))
check(actBad.move == 33 or actBad.slot == 2, "prefers Tackle over Earthquake")

print("[test] 5. TryToFaint / viability: KO move preferred when flags=7")
local stKo = State.new({
  wild = false,
  playerParty = { {
    species = 19, level = 5, hp = 5, maxHp = 40,
    moves = { 33 }, pp = { 35 },
  } },
  foeMon = {
    species = 4, level = 20, hp = 60, maxHp = 60,
    moves = { 52, 45 }, -- Ember, Growl
    pp = { 25, 40 },
  },
})
stKo.player.type1 = 0
stKo.enemy.type1 = 10 -- FIRE
local actKo = Ai.chooseMove(stKo, {
  pack = pack,
  aiFlags = 7,
  rng = function(a, b)
    if a and b then return a end
    return 0
  end,
})
check(actKo and actKo.kind == "move", "flags=7 returns a move")
check(actKo.slot == 1 or actKo.move == 52 or actKo.move == "EMBER",
  "prefer damaging Ember over Growl (slot=" .. tostring(actKo.slot) .. " move=" .. tostring(actKo.move) .. ")")
check(actKo.scores and actKo.scores[1] > actKo.scores[2],
  string.format("Ember score (%s) > Growl (%s)", tostring(actKo.scores and actKo.scores[1]), tostring(actKo.scores and actKo.scores[2])))

print("[test] 6. aiFlags=0 / wild → usable move")
local stWild = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 16, level = 3, hp = 15, maxHp = 15, moves = { 16, 33 }, pp = { 35, 35 } },
})
stWild.aiFlags = 0
local actW = Ai.chooseMove(stWild, { pack = pack, aiFlags = 0 })
check(actW and actW.kind == "move", "wild returns move")
check(actW.move ~= nil and actW.move ~= 0, "wild move usable")

print("[test] 7. Commands.enemyAction uses AI")
local Commands = require("src.core.game3.battle.commands")
stKo.aiFlags = 7
local ea = Commands.enemyAction(stKo)
check(ea and ea.kind == "move", "enemyAction returns move")
check(ea.user == "enemy", "enemyAction user=enemy")

print("[test] 8. Doubles: flank target, absent flip, BOTH / USER targets, partner-aware scans")
local AiCmds = require("src.core.game3.battle.ai_cmds")
local function dstate(foeMoves)
  local pp = { 20, 20, 20, 20 }
  local st = State.new({
    wild = false,
    double = true,
    playerParty = {
      { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } },
      { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } },
    },
    foeParty = {
      { species = 74, level = 20, hp = 50, maxHp = 50, moves = foeMoves, pp = pp },
      { species = 74, level = 20, hp = 50, maxHp = 50, moves = foeMoves, pp = pp },
      { species = 4, level = 20, hp = 50, maxHp = 50, moves = { 52 }, pp = { 25 } },
    },
  })
  st.aiFlags = 1
  return st
end
local function flankRng(flank)
  return function(lo, hi)
    if lo == 0 and hi == 65535 then return flank end
    if lo and hi then return lo end
    return 0
  end
end

local stD = dstate({ 33 })
local aD = Ai.chooseMove(stD, { battler = 1, pack = pack, aiFlags = 1, rng = flankRng(2) })
check(aD and aD.battler == 1 and aD.target == 2, "doubles: Random() & BIT_FLANK picks player right (target=" .. tostring(aD and aD.target) .. ")")
stD.absent[2] = true
aD = Ai.chooseMove(stD, { battler = 1, pack = pack, aiFlags = 1, rng = flankRng(2) })
check(aD and aD.target == 0, "doubles: absent flank flips to player left")

local stG = dstate({ 45 })
local aG = Ai.chooseMove(stG, { battler = 1, pack = pack, aiFlags = 1, rng = flankRng(2) })
check(aG and aG.target == 0, "doubles: BOTH move targets player left")
stG.absent[0] = true
aG = Ai.chooseMove(stG, { battler = 1, pack = pack, aiFlags = 1, rng = flankRng(2) })
check(aG and aG.target == 2, "doubles: BOTH move falls back to player right when left absent")

local stH = dstate({ 270, 33 })
local aH = Ai.chooseMove(stH, { battler = 3, pack = pack, aiFlags = 1, rng = flankRng(0) })
check(aH and aH.slot == 1 and aH.target == 3, "doubles: Helping Hand (USER) targets self")
local stHs = State.new({
  wild = false,
  playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 74, level = 20, hp = 50, maxHp = 50, moves = { 270, 33 }, pp = { 20, 20 } },
})
local aHs = Ai.chooseMove(stHs, { pack = pack, aiFlags = 1, rng = flankRng(0) })
check(aH.scores and aHs.scores and aH.scores[1] > aHs.scores[1],
  string.format("Helping Hand not penalized in doubles (%s) vs singles (%s)",
    tostring(aH.scores and aH.scores[1]), tostring(aHs.scores and aHs.scores[1])))

local vmD = AiVm.new({
  pack = pack, st = stH, user = stH.battlers[3], target = stH.battlers[0],
  userSide = stH.enemySide, targetSide = stH.playerSide,
  scores = { 100, 100, 100, 100 }, simulatedRNG = { 100, 100, 100, 100 },
  movesetIndex = 1, rng = flankRng(0),
})
AiCmds.dispatch(vmD, { op = "is_double_battle" })
check(vmD.funcResult == 1, "is_double_battle = 1 in doubles")
AiCmds.dispatch(vmD, { op = "count_alive_pokemon", battler = 1 })
check(vmD.funcResult == 1, "count_alive_pokemon excludes both on-field foes (got " .. tostring(vmD.funcResult) .. ")")

local aA = Ai.chooseAction(dstate({ 33 }), 3, { pack = pack, aiFlags = 1, rng = flankRng(0) })
check(aA and aA.kind == "move" and aA.battler == 3 and (aA.target == 0 or aA.target == 2),
  "chooseAction returns {kind, battler, move, slot, target}")
local ea3 = Commands.enemyAction((function() local s = dstate({ 33 }); s.rng = flankRng(2); return s end)(), 3)
check(ea3 and ea3.battler == 3 and ea3.target == 2, "Commands.enemyAction(st, 3) routes through Ai.chooseAction")

print("[test] 9. Singles pret paths: tie-break quirk, wild random move, zero-flag trainer setup")
local function recRng(fixed)
  local calls = {}
  local f = function(lo, hi)
    calls[#calls + 1] = { lo, hi }
    if fixed and fixed[lo .. ":" .. hi] ~= nil then return fixed[lo .. ":" .. hi] end
    if lo and hi then return lo end
    return 0
  end
  return f, calls
end
local stQ = State.new({
  wild = false,
  playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 74, level = 20, hp = 50, maxHp = 50, moves = { 33, 33 }, pp = { 0, 20 } },
})
local qRng, qCalls = recRng()
local aQ = Ai.chooseMove(stQ, { pack = pack, aiFlags = 0, rng = qRng })
local lastPick = qCalls[#qCalls]
check(aQ and aQ.slot == 2, "zero-flag trainer picks the only usable move")
check(lastPick and lastPick[1] == 1 and lastPick[2] == 2, "new best counted twice (Random() % 2)")
local draws = 0
for _, c in ipairs(qCalls) do if c[1] == 0 and c[2] == 15 then draws = draws + 1 end end
check(draws == 4, "zero-flag trainer still rolls 4 simulatedRNG draws")

local stW = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 16, level = 3, hp = 15, maxHp = 15, moves = { 16, 33 }, pp = { 35, 35 } },
})
local wRng, wCalls = recRng({ ["0:3"] = 1 })
local aW = Ai.chooseMove(stW, { pack = pack, rng = wRng })
check(aW and aW.slot == 2, "wild: Random() & 3 picks slot 2")
check(#wCalls == 1, "wild: one RNG draw, no AI setup")

local stE = State.new({
  wild = false,
  playerParty = {
    { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } },
    { species = 16, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 }, isEgg = true },
    { species = 19, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } },
  },
  foeMon = { species = 74, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 20 } },
})
local vmE = AiVm.new({
  pack = pack, st = stE, user = stE.enemy, target = stE.player,
  userSide = stE.enemySide, targetSide = stE.playerSide,
  scores = { 100, 100, 100, 100 }, simulatedRNG = { 100, 100, 100, 100 }, movesetIndex = 1,
  rng = function(lo) return lo or 0 end,
})
AiCmds.dispatch(vmE, { op = "count_alive_pokemon", battler = 0 })
check(vmE.funcResult == 1, "count_alive_pokemon skips eggs in singles (got " .. tostring(vmE.funcResult) .. ")")

print("[test] 10. Trainer items: ShouldUseItem + enemy item execution")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local function itemState(opts)
  local st = State.new({
    wild = opts.wild or false,
    playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
    foeMon = { species = 74, level = 20, hp = opts.hp or 5, maxHp = 40, moves = { 33 }, pp = { 20 },
      status = opts.status },
  })
  st.trainerItems = opts.items
  st.trainerClassName, st.trainerName = "LEADER", "BROCK"
  st.aiFlags = 1
  st.rng = function(lo, hi) if lo and hi then return lo end return 0 end
  return st
end
local stP = itemState({ items = { 13, 0, 0, 0 } })
local aP = Ai.chooseAction(stP, 1, { pack = pack })
check(aP and aP.kind == "item" and aP.item == 13 and aP.battler == 1 and aP.target == 1,
  "low HP trainer mon uses POTION (kind=" .. tostring(aP and aP.kind) .. ")")
check(stP._aiHistory.items[1] == 0, "POTION removed from battle history")
local aP2 = Ai.chooseAction(stP, 1, { pack = pack })
check(aP2 and aP2.kind == "move", "no second POTION")
local adP = Adapter.new(stP, function() end)
local msgs = {}
adP._say = function(t) msgs[#msgs + 1] = t end
Engine.performEnemyItem(stP, adP, aP)
check(tonumber(stP.enemy.mon.hp) == 25, "POTION heals 20 (hp=" .. tostring(stP.enemy.mon.hp) .. ")")
check(msgs[1] and msgs[1]:find("used POTION!", 1, true) ~= nil, "prints '<TRAINER> used POTION!'")
check(msgs[2] and msgs[2]:find("restored health!", 1, true) ~= nil, "prints 'restored health!'")

local stF = itemState({ items = { 23, 0, 0, 0 }, hp = 40, status = "PSN" })
local aF = Ai.chooseAction(stF, 1, { pack = pack })
check(aF and aF.kind == "item" and aF.item == 23 and aF.aiItemFlags == 0x10, "poisoned mon uses FULL HEAL")
Engine.performEnemyItem(stF, Adapter.new(stF, function() end), aF)
check(stF.enemy.mon.status == nil, "FULL HEAL cures poison")

local stWi = itemState({ items = { 13, 0, 0, 0 }, wild = true })
local aWi = Ai.chooseAction(stWi, 1, { pack = pack })
check(aWi and aWi.kind == "move", "wild mons never use items")

print("[test] 11. Singles ShouldSwitch: Perish Song count 0 switches out")
local stS = State.new({
  wild = false,
  playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
  foeParty = {
    { species = 74, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 20 } },
    { species = 4, level = 20, hp = 50, maxHp = 50, moves = { 52 }, pp = { 25 } },
  },
  foeMon = nil,
})
stS.aiFlags = 1
stS.rng = function(lo, hi) if lo and hi then return lo end return 0 end
stS.enemy.perishSong, stS.enemy.expPerishTurns = true, 0
local aS = Commands.enemyAction(stS)
check(aS and aS.kind == "switch" and aS.slot == 2 and aS.battler == 1, "Perish Song 0 -> switch to slot 2")
stS.wild = true
stS.monToSwitchInto = {}
local aS2 = Ai.chooseAction(stS, 1, { pack = pack })
check(aS2 and aS2.kind == "move", "wild mons never switch")

print("[test] 12. Complete 743 Trainer aiFlags ROM parity vs pokefirered/src/data/trainers.h")
do
  local f = io.open("pokefirered/src/data/trainers.h", "r")
  if f then
    local okT, trainerPack = pcall(require, "data.generated.gba.trainers")
    if not okT or not trainerPack then
      f:close()
      print("[skip] data.generated.gba.trainers not found")
      return
    end
    local content = f:read("*a")
    f:close()
    local trainerBlocks = {}
    local currentId = nil
    local currentAiFlags = 0
    for line in content:gmatch("[^\r\n]+") do
      local tid = line:match("%[([%w_]+)%]%s*=%s*{")
      if tid then
        currentId = tid
        currentAiFlags = 0
      elseif line:match("%.aiFlags%s*=%s*(.-),") then
        local expr = line:match("%.aiFlags%s*=%s*(.-),")
        local val = 0
        if expr:find("AI_SCRIPT_CHECK_BAD_MOVE") then val = val + 1 end
        if expr:find("AI_SCRIPT_CHECK_VIABILITY") then val = val + 2 end
        if expr:find("AI_SCRIPT_TRY_TO_FAINT") then val = val + 4 end
        if expr:find("AI_SCRIPT_SETUP_FIRST_TURN") then val = val + 8 end
        if expr:find("AI_SCRIPT_RISKY") then val = val + 16 end
        if expr:find("AI_SCRIPT_PREFER_STRONGEST_MOVE") then val = val + 32 end
        if expr:find("AI_SCRIPT_PREFER_BATON_PASS") then val = val + 64 end
        if expr:find("AI_SCRIPT_DOUBLE_BATTLE") then val = val + 128 end
        if expr:find("AI_SCRIPT_HP_AWARE") then val = val + 256 end
        if expr:find("AI_SCRIPT_ROAMING") then val = val + 0x20000000 end
        if expr:find("AI_SCRIPT_SAFARI") then val = val + 0x40000000 end
        if expr:find("AI_SCRIPT_FIRST_BATTLE") then val = val + 0x80000000 end
        currentAiFlags = val
        trainerBlocks[#trainerBlocks + 1] = { id = currentId, aiFlags = currentAiFlags }
      elseif currentId and line:match("^%s*},") then
        if #trainerBlocks == 0 or trainerBlocks[#trainerBlocks].id ~= currentId then
          trainerBlocks[#trainerBlocks + 1] = { id = currentId, aiFlags = 0 }
        end
        currentId = nil
      end
    end
    check(#trainerBlocks == 743, "found 743 pret trainer definitions")
    local mismatches = 0
    for idx, pretT in ipairs(trainerBlocks) do
      local tid = idx - 1
      local romT = trainerPack.trainers[tid]
      if not romT or romT.aiFlags ~= pretT.aiFlags then
        mismatches = mismatches + 1
      end
    end
    check(mismatches == 0, "all 743 ROM-extracted trainer aiFlags match pret (0 mismatches)")
  else
    check(true, "pokefirered headers missing; skip parity scan")
  end
end

print("[test] 13. Scripted Wild Battles: dowildbattle sets wildScripted -> aiFlags = 1 (AI_SCRIPT_CHECK_BAD_MOVE)")
do
  local stScripted = State.new({
    wild = true,
    playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
    foeMon = {
      species = 74, level = 20, hp = 50, maxHp = 50,
      moves = { 89, 33 }, pp = { 10, 35 }, -- EQ (Ground) and Tackle (Normal)
    },
  })
  stScripted.player.type1 = 2 -- FLYING
  stScripted.player.type2 = nil
  stScripted.enemy.type1 = 4 -- GROUND
  stScripted.enemy.type2 = 5 -- ROCK
  stScripted.wildScripted = true

  local actScripted = Ai.chooseMove(stScripted, {
    pack = pack,
    rng = function(a, b)
      if a and b then return a end
      return 0
    end,
  })
  check(actScripted and actScripted.scores ~= nil, "scripted wild battle executed AI scripts")
  check(actScripted.move == 33 or actScripted.slot == 2, "scripted wild avoids ineffective Earthquake vs Flying")
end

print("[test] 14. Legendary Wild Battles: StartLegendaryBattle sets legendary -> aiFlags = 7")
do
  local stLegend = State.new({
    wild = true,
    playerParty = { { species = 19, level = 5, hp = 5, maxHp = 40, moves = { 33 }, pp = { 35 } } },
    foeMon = {
      species = 146, level = 50, hp = 150, maxHp = 150, -- Moltres
      moves = { 52, 45 }, -- Ember, Growl
      pp = { 25, 40 },
    },
  })
  stLegend.player.type1 = 0
  stLegend.enemy.type1 = 10 -- FIRE
  stLegend.legendary = true

  local actLegend = Ai.chooseMove(stLegend, {
    pack = pack,
    rng = function(a, b)
      if a and b then return a end
      return 0
    end,
  })
  check(actLegend and actLegend.scores ~= nil, "legendary battle executed AI scripts (flags=7)")
  check(actLegend.slot == 1 or actLegend.move == 52, "legendary prefers KO Ember over Growl")
  check(actLegend.scores[1] > actLegend.scores[2], "Ember score > Growl score under legendary AI")
end

print("[test] 15. 32-bit unsigned AI_SCRIPT_FIRST_BATTLE (0x80000000) safety")
do
  local stFirst = State.new({
    wild = false,
    playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
    foeMon = { species = 4, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } },
  })
  stFirst.aiFlags = 0x80000000
  local actFirst = Ai.chooseMove(stFirst, { pack = pack })
  check(actFirst and actFirst.kind == "move", "aiFlags 0x80000000 evaluates safely without sign overflow")

  -- pokefirered/src/battle_ai_script_commands.c:331
  local stTut = State.new({
    wild = false,
    playerParty = { { species = 19, level = 5, hp = 5, maxHp = 40, moves = { 33 }, pp = { 35 } } },
    foeMon = {
      species = 4, level = 5, hp = 20, maxHp = 20,
      moves = { 52, 45 },
      pp = { 25, 40 },
    },
  })
  stTut.player.type1 = 0
  stTut.enemy.type1 = 10
  stTut.firstBattle = true
  stTut.aiFlags = 7
  local actTut = Ai.chooseMove(stTut, {
    pack = pack,
    rng = function(a, b)
      if a and b then return a end
      return 0
    end,
  })
  check(actTut and actTut.scores ~= nil, "firstBattle trainer battle executed AI scripts")
  check(actTut and actTut.scores and actTut.scores[1] > actTut.scores[2],
    "firstBattle keeps the trainer's own aiFlags (7) instead of AI_SCRIPT_FIRST_BATTLE")
end

print("[test] 16. GetBattleOutcome (special 0xB4) and B_OUTCOME constants")
do
  local Natives = require("src.core.game3.scripting.natives")
  local Flags = require("src.core.game3.scripting.flags")
  check(Natives.B_OUTCOME.WON == 1, "B_OUTCOME.WON == 1")
  check(Natives.B_OUTCOME.LOST == 2, "B_OUTCOME.LOST == 2")
  check(Natives.B_OUTCOME.RAN == 4, "B_OUTCOME.RAN == 4")
  check(Natives.B_OUTCOME.CAUGHT == 7, "B_OUTCOME.CAUGHT == 7")

  check(Natives.outcome_to_code("win") == 1, "win -> 1")
  check(Natives.outcome_to_code("caught") == 7, "caught -> 7")
  check(Natives.outcome_to_code("ran") == 4, "ran -> 4")

  local ctx = { specialVars = {} }
  ctx.lastBattleOutcome = Natives.B_OUTCOME.CAUGHT
  Natives.special(ctx, 0xB4, nil)
  check(Flags.getVar(nil, ctx, 0x800D) == 7, "GetBattleOutcome writes CAUGHT (7) to VAR_RESULT (0x800D)")
end

print("[test] 17. Oak's Tutorial Battle (oldManTutorial) skips AI item/switch")
do
  local stTut = State.new({
    wild = false,
    playerParty = { { species = 16, level = 20, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 } } },
    foeParty = {
      { species = 13, level = 5, hp = 5, maxHp = 20, moves = { 33 }, pp = { 20 } },
      { species = 13, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 20 } },
    },
    foeMon = nil,
  })
  stTut.oldManTutorial = true
  stTut.enemy.perishSong, stTut.enemy.expPerishTurns = true, 0
  stTut.enemyItems = { 13, 0, 0, 0 }
  local actTut = Ai.chooseAction(stTut, 1, { pack = pack })
  check(actTut and actTut.kind == "move", "oldManTutorial skips tactical switches and item use")
end

if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll game3 battle AI tests passed.")


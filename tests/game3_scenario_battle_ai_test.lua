#!/usr/bin/env luajit
-- src/battle_ai_script_commands.c:299, src/battle_ai_script_commands.c:302, src/battle_ai_script_commands.c:310, src/battle_ai_script_commands.c:363, src/battle_ai_script_commands.c:371, src/battle_ai_script_commands.c:384

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local State = require("src.core.game3.battle.state")
local Ai = require("src.core.game3.battle.ai")
local AiVm = require("src.core.game3.battle.ai_vm")

if not require("tests.game3_cache").mount() then
  local Moves = require("src.core.game3.battle.moves")
  Moves._romLoaded = true
  -- src/data/battle_moves.h:432, :1160
  Moves._rom = {
    [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
    [89] = { effect = 147, power = 100, type = 4, accuracy = 100, pp = 10, secondaryChance = 0, target = 32, priority = 0, flags = 50 },
  }
  Moves.BY_NUM[33], Moves.BY_NUM[89] = "TACKLE", "EARTHQUAKE"
  Moves._numByName = { TACKLE = 33, EARTHQUAKE = 89 }
end

local function loRng(lo, hi)
  if lo and hi then return lo end
  return 0
end

local scripts = {
  SYN_KO = {
    { op = "if_can_faint", target = "SYN_TAKE" },
    { op = "score", delta = -40 },
    { op = "end" },
  },
  SYN_TAKE = { { op = "score", delta = 40 }, { op = "end" } },
  SYN_FLAT = { { op = "score", delta = -25 }, { op = "end" } },
  SYN_FLEE = { { op = "flee" } },
}
local synPack = { table = { "SYN_KO" }, data = {}, scripts = scripts }
local fleePack = { table = { "SYN_FLEE" }, data = {}, scripts = scripts }

local function aiState(opts)
  opts = opts or {}
  local st = State.new({
    wild = opts.wild and true or false,
    playerParty = { { species = 16, level = 20, hp = 10, maxHp = 40, moves = { 33 }, pp = { 35 } } },
    foeMon = {
      species = 74, level = 20, hp = 80, maxHp = 80,
      moves = { 89, 33 }, pp = { 10, 35 },
      attack = 70, defense = 60, spAtk = 40, spDef = 50, speed = 30,
    },
  })
  st.player.type1 = 2 st.player.type2 = nil
  st.enemy.type1 = 4 st.enemy.type2 = 5
  st.aiFlags = opts.aiFlags or 1
  return st
end

local function vmNew(st, scores, slot, pack)
  return AiVm.new({
    pack = pack or synPack,
    st = st, user = st.enemy, target = st.player,
    userSide = st.enemySide, targetSide = st.playerSide,
    scores = scores, simulatedRNG = { 100, 100, 100, 100 },
    movesetIndex = slot, rng = loRng,
  })
end

print("[test] 1. Synthetic pack drives the AI script VM (always runs, no ROM)")
local s = { 100, 100, 100, 100 }
AiVm.run(vmNew(aiState(), s, 2), "SYN_FLAT")
check(s[2] == 75, "score op applies its delta as scripted (100 - 25 = 75)")

local s1 = { 100, 100, 100, 100 }
AiVm.run(vmNew(aiState(), s1, 1), "SYN_KO")
check(s1[1] == 60, "if_can_faint misses (EQ is Ground-immune here) -> 100 - 40 = 60, got " .. s1[1])

local s2 = { 100, 100, 100, 100 }
AiVm.run(vmNew(aiState(), s2, 2), "SYN_KO")
check(s2[2] == 127, "if_can_faint hits (Tackle can KO) -> 140 clamped to s8 max 127, got " .. s2[2])

local s3 = { 100, 100, 100, 100 }
AiVm.run(vmNew(aiState(), s3, 3), "SYN_KO")
check(s3[3] == 0, "empty moveset slot is zeroed by AiVm.run")

local vmF = vmNew(aiState(), { 100, 100, 100, 100 }, 1)
AiVm.run(vmF, "SYN_FLEE")
check(vmF.aiAction == 0xB, string.format("flee op sets AI_ACTION_FLEE|DONE|DO_NOT_ATTACK (aiAction=0x%X)", vmF.aiAction))

print("[test] 2. Ai.chooseMove picks the fainting move on the rigged state")
local act = Ai.chooseMove(aiState(), { pack = synPack, aiFlags = 1, rng = loRng })
check(act ~= nil and act.kind == "move", "returns a move action")
check(act.slot == 2 and act.move == 33, "picks Tackle over the Ground-immune EQ (slot=" .. tostring(act.slot) .. ")")
check(act.scores[1] == 60 and act.scores[2] == 127, "decision carries the scripted scores 60 / 127")
check(act.scores[1] < act.scores[2], "lower-scoring move was not chosen")
check(act.target == nil, "singles: target trimmed from the returned action")

print("[test] 3. aiFlags gating: 0 = no scripts, nonzero = bit loop runs pack")
local a0 = Ai.chooseMove(aiState(), { pack = synPack, aiFlags = 0, rng = loRng })
check(a0 and a0.kind == "move", "flags=0 still returns a usable move")
check(a0.scores[1] == 100 and a0.scores[2] == 100, "flags=0: base scores 100 untouched (script never ran)")
check(a0.slot == 1, "flags=0: 100/100 tie broken by rigged rng -> first slot")

local a1 = Ai.chooseMove(aiState(), { pack = synPack, aiFlags = 1, rng = loRng })
check(a1.scores[1] == 60 and a1.slot == 2, "flags=1: logic slot 0 (SYN_KO) ran and changed the pick")

local a7 = Ai.chooseMove(aiState(), { pack = synPack, aiFlags = 7, rng = loRng })
check(a7.scores[1] == a1.scores[1] and a7.scores[2] == a1.scores[2] and a7.slot == a1.slot,
  "flags=7: empty table slots 1..2 skipped safely, same decision as flags=1")

local wildRnd = Ai.chooseMove(aiState({ wild = true, aiFlags = 0 }), { rng = loRng })
check(wildRnd and wildRnd.kind == "move" and wildRnd.scores[1] == 0,
  "wild + flags=0 bypasses AI entirely (random pick, scores all 0)")

print("[test] 4. Ai.chooseAction delivers the enemy's round action (wild battle)")
local stA = aiState({ wild = true })
local okBS = pcall(Ai.battleStart, stA, { rng = loRng })
check(okBS and type(stA._aiHistory) == "table", "Ai.battleStart initialises the item-use history")
local actA = Ai.chooseAction(stA, 1, { pack = synPack, aiFlags = 1, rng = loRng })
check(actA and actA.kind == "move" and actA.slot == 2,
  "wild battle: chooseAction returns the scored move (Tackle, slot 2)")
local actF = Ai.chooseAction(aiState({ wild = true }), 1, { pack = fleePack, aiFlags = 1, rng = loRng })
check(actF and actF.kind == "run", "AI_ACTION_FLEE surfaces as a kind='run' action")

print("[test] 5. Real extracted AI pack (self-skips when absent)")
local okPack, realPack = pcall(Ai.loadPack, { force = true, extract = true })
if not okPack or not realPack then
  print("[skip] real AI pack absent")
else
  -- data/battle_ai_scripts.s:17, :52, :2767
  check(type(realPack.table) == "table" and #realPack.table == 32, "gBattleAI_ScriptsTable has 32 entries")
  local badMove = realPack.scripts[realPack.table[1]]
  check(badMove and badMove[1].op == "get_how_powerful_move_is", "table[0] = AI_CheckBadMove")
  local faint = realPack.scripts[realPack.table[3]]
  check(faint and faint[1].op == "if_can_faint", "table[2] = AI_TryToFaint")
  for name, body in pairs(realPack.scripts) do
    for _, op in ipairs(body) do
      if op.target and not realPack.scripts[op.target] then
        check(false, "branch target " .. op.target .. " from " .. name .. " has a body")
      end
    end
  end
end

finish()

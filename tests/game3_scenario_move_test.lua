#!/usr/bin/env luajit
-- src/data/battle_moves.h:432, src/data/battle_moves.h:679, src/pokemon.c:2374, src/pokemon.c:2385, src/battle_script_commands.c:1122, src/battle_script_commands.c:1134, src/battle_script_commands.c:1199, src/battle_script_commands.c:1209, src/battle_script_commands.c:1557, battle_moves.h:458

package.path = "./?.lua;./?/init.lua;" .. package.path
local GameCache = require("tests.game3_cache")
if not GameCache.bundle() then
  print("[skip] game3 scenario move: " .. tostring(GameCache.reason))
  os.exit(0)
end

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
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")
local Moves = require("src.core.game3.battle.moves")
local T = Types.ID

-- battle_script_commands.c:1557
local function mkRng(map)
  map = map or {}
  return function(lo, hi)
    local key = tostring(lo) .. "," .. tostring(hi)
    if map[key] ~= nil then return map[key] end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
end

-- pokemon.c:2385
local function player(o)
  o = o or {}
  return {
    species = 1, level = 30, hp = 120, maxHp = 120,
    attack = 70, defense = 50, spAtk = 60, spDef = 50, speed = 60,
    moves = o.moves or { 33 }, pp = o.pp or { 35, 20, 20, 20 },
  }
end

local function foe(o)
  o = o or {}
  return {
    species = 1, level = 30, hp = 150, maxHp = 150,
    attack = 40, defense = 60, spAtk = 30, spDef = 55, speed = 30,
    moves = o.moves or { 33 }, pp = o.pp or { 35, 20, 20, 20 },
    ability = o.ability,
  }
end

local function round(opts)
  opts = opts or {}
  local st = State.new({
    wild = true,
    playerParty = { opts.player or player() },
    foeMon = opts.foe or foe(),
  })
  st.player.type1 = opts.ptype or T.NORMAL
  st.player.type2 = nil
  st.enemy.type1 = opts.etype or T.NORMAL
  st.enemy.type2 = nil
  st.rng = mkRng(opts.rngMap)
  return st, Adapter.new(st, function() end)
end

local function resolve(st, ad, user, moveId, slot)
  local out = {}
  local target = (user == st.player) and st.enemy or st.player
  Engine.resolveMove(user, target, moveId, slot or 1, ad, st, out)
  return out, table.concat(out, " || ")
end

print("[test] 1. Attacker uses TACKLE (33): defender loses the engine's damage")
local mv = Moves.get(33)
check(mv and mv.power == 35 and mv.accuracy == 95, "TACKLE data matches pret (power 35, acc 95)")
local st, ad = round()
local before = ad:hp(st.enemy)
local out, txt = resolve(st, ad, st.player, 33, 1)
local loss = before - ad:hp(st.enemy)
local hit = out._anim and out._anim.hits and out._anim.hits[1]
check(loss > 0, "defender HP dropped (loss=" .. loss .. ")")
check(hit ~= nil and loss == (hit.from - hit.to), "HP loss equals the engine-recorded hit amount")
check(loss == 19, "deterministic fixture damage 19 (base 13 x1.5 STAB, damage roll 100)")
check(txt:find("used\nTACKLE", 1, true) ~= nil, "attack string printed")
check(st.player.lastMove == 33, "user.lastMove bookkeeping set for the round")

print("[test] 2. Foe strikes back: the full round completes on both sides")
local pBefore = ad:hp(st.player)
local out2, txt2 = resolve(st, ad, st.enemy, 33, 1)
local pLoss = pBefore - ad:hp(st.player)
local hit2 = out2._anim and out2._anim.hits and out2._anim.hits[1]
check(pLoss > 0, "player HP dropped on the return hit (loss=" .. pLoss .. ")")
check(pLoss == 13 and hit2 ~= nil and (hit2.from - hit2.to) == 13,
  "return hit equals the engine-recorded 13")
check(st.enemy.lastMove == 33, "foe lastMove bookkeeping set")
check(txt2:find("used\nTACKLE", 1, true) ~= nil, "foe attack string printed")
check(ad:hp(st.player) < 120 and ad:hp(st.enemy) < 150, "both battlers damaged: round completed")

print("[test] 3. Type effectiveness orders damage: super > neutral > resisted")
local function emberVs(defType)
  local s, a = round({
    player = player({ moves = { 52 }, pp = { 25, 20, 20, 20 } }),
    etype = defType,
  })
  local b = a:hp(s.enemy)
  local o, t = resolve(s, a, s.player, 52, 1)
  return b - a:hp(s.enemy), o._anim.effectiveness, t
end
local dSup, eSup, tSup = emberVs(T.GRASS)
local dNeu, eNeu, tNeu = emberVs(T.NORMAL)
local dRes, eRes, tRes = emberVs(T.WATER)
check(dSup > dNeu and dNeu > dRes,
  string.format("ordering holds: super %d > neutral %d > resisted %d", dSup, dNeu, dRes))
check(dSup == 28 and dNeu == 14 and dRes == 7, "fixture damages 28 / 14 / 7 (x2 / x1 / x0.5)")
check(eSup == 2 and eNeu == 1 and eRes == 0.5, "anim effectiveness recorded 2 / 1 / 0.5")
check(tSup:find("super effective", 1, true) ~= nil, "'It's super effective!' printed")
check(tNeu:find("super effective", 1, true) == nil and tNeu:find("not very", 1, true) == nil,
  "neutral matchup prints no effectiveness line")
check(tRes:find("not very effective", 1, true) ~= nil, "'It's not very effective' printed")

print("[test] 4. PP goes down exactly 1 per use on the real consumption path")
-- battle_script_commands.c:1122
local stP, adP = round()
check(stP.player.mon.pp[1] == 35 and stP.player.mon.pp[2] == 20, "starting PP 35 / 20")
resolve(stP, adP, stP.player, 33, 1)
check(stP.player.mon.pp[1] == 34, "one landed TACKLE costs exactly 1 PP (35 -> 34)")
check(stP.player.mon.pp[2] == 20, "sibling slot untouched")
resolve(stP, adP, stP.player, 33, 1)
check(stP.player.mon.pp[1] == 33, "second use -> 33")

stP.player.mon.pp[1] = 0
local zBefore = adP:hp(stP.enemy)
local _, zTxt = resolve(stP, adP, stP.player, 33, 1)
check(zTxt:find("no PP left", 1, true) ~= nil, "zero-PP gate prints 'no PP left'")
check(adP:hp(stP.enemy) == zBefore, "zero-PP gate deals no damage")
check(stP.player.mon.pp[1] == 0, "PP stays at 0")

-- battle_script_commands.c:1134
local stQ, adQ = round({ foe = foe({ ability = "PRESSURE" }) })
resolve(stQ, adQ, stQ.player, 33, 1)
check(stQ.player.mon.pp[1] == 33, "PRESSURE target costs 2 PP (35 -> 33)")

print("[test] 5. Secondary status branch: EMBER burn sticks when rigged to proc")
-- battle_moves.h:679
local stB, adB = round({
  player = player({ moves = { 52 }, pp = { 25, 20, 20, 20 } }),
  rngMap = { ["0,99"] = 0 },
})
local _, tB = resolve(stB, adB, stB.player, 52, 1)
check(adB:status(stB.enemy) == "BRN", "rigged proc: defender's status stuck as BRN")
check(tB:find("was burned!", 1, true) ~= nil, "burn message printed")

local stN, adN = round({ player = player({ moves = { 52 }, pp = { 25, 20, 20, 20 } }) })
local _, tN = resolve(stN, adN, stN.player, 52, 1)
check(adN:status(stN.enemy) == nil, "default roll 99 > chance 10: no burn applied")
check(tN:find("was burned!", 1, true) == nil, "no burn message when the secondary fails")

finish()

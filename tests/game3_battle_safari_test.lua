#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Moves = require("src.core.game3.battle.moves")
local ROM = {
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
}
Moves._romLoaded = true
Moves._rom = ROM
Moves.loadRomPack = function()
  Moves._romLoaded = true
  Moves._rom = ROM
  return true
end

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local FOE_SPECIES = 16
local FOE_CATCH_RATE = 190
Pokemon._speciesMeta = Pokemon._speciesMeta or {}
Pokemon._speciesMeta[FOE_SPECIES] = { catchRate = FOE_CATCH_RATE }

local Rules = require("src.core.game3.battle.rules")
local Commands = require("src.core.game3.battle.commands")
local Catching = require("src.core.game3.battle.catching")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local State = require("src.core.game3.battle.state")
local AiVm = require("src.core.game3.battle.ai_vm")

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

local function new_session(balls)
  return {
    name = "RED",
    party = {
      { species = 1, name = "BULBASAUR", level = 10, hp = 30, maxHp = 30,
        attack = 12, defense = 12, spAtk = 12, spDef = 12, speed = 12,
        moves = { 33 }, pp = { 35 } },
    },
    dex = { seen = {}, owned = {} },
    safari = { active = true, balls = balls, steps = Rules.safari.STEPS },
  }
end

local function start_safari(session, rng)
  Battle.abort()
  Battle.start({
    headless = true,
    autoFight = false,
    wild = true,
    safari = true,
    session = session,
    playerParty = session.party,
    rng = rng,
    foe = { species = FOE_SPECIES, level = 8, hp = 24, maxHp = 24,
      attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
      moves = { 33 }, pp = { 35 } },
  })
  return Battle.getState()
end

local function play(action, st)
  for _ = 1, 60 do
    if Battle._phase == "command" then break end
    Battle.update(0, nil)
  end
  Ui._pendingCommand = Commands.playerAction(st, action, nil)
  for _ = 1, 12 do Battle.update(0, nil) end
end

local function log_has(text)
  for _, t in ipairs(Ui.log() or {}) do
    if tostring(t):find(text, 1, true) then return true end
  end
  return false
end

print("[test] 1. Safari state seeded from the foe's species row")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  check(st.safari == true, "st.safari set")
  check(st.safariState ~= nil, "st.safariState seeded")
  -- pokefirered/src/battle_main.c:2284
  eq(st.safariState.catchFactor, math.floor(FOE_CATCH_RATE * 100 / 1275), "catchFactor = catchRate * 100 / 1275")
  -- pokefirered/src/battle_main.c:2285
  eq(st.safariState.escapeFactor, 2, "escapeFactor floors at 2 with no flee rate in the cache")
  eq(st.safariState.baseCatchRate, FOE_CATCH_RATE, "baseCatchRate kept for the rock reset")
  eq(st.safariState.rockCounter, 0, "rockCounter starts 0")
  eq(st.safariState.baitCounter, 0, "baitCounter starts 0")
  eq(st.safariState.balls, 30, "balls carried in from session.safari")
  eq(st.aiFlags, 0x40000000, "AI_SCRIPT_SAFARI selected")
  Battle.abort()
end

print("[test] 2. Ball count carried in from a partly spent session")
do
  local session = new_session(7)
  local st = start_safari(session, function(_, hi) return hi end)
  eq(st.safariState.balls, 7, "7 balls carried in")
  Battle.abort()
end

print("[test] 3. Safari command menu is BALL / BAIT / ROCK / RUN")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  local menu = Commands.menuFor(st)
  eq(menu[1], "BALL", "slot 1 BALL")
  eq(menu[2], "BAIT", "slot 2 BAIT")
  eq(menu[3], "ROCK", "slot 3 ROCK")
  eq(menu[4], "RUN", "slot 4 RUN")
  eq(Commands.menuFor({ wild = true })[1], "FIGHT", "non-safari keeps FIGHT")
  local a1 = Commands.playerAction(st, 1, nil)
  eq(a1.kind, "safari", "slot 1 builds a safari action")
  eq(a1.action, "ball", "slot 1 action = ball")
  eq(Commands.playerAction(st, 2, nil).action, "bait", "slot 2 action = bait")
  eq(Commands.playerAction(st, 3, nil).action, "rock", "slot 3 action = rock")
  local a4 = Commands.playerAction(st, 4, nil)
  eq(a4.kind, "run", "slot 4 is a run")
  check(a4.safariRun == true, "slot 4 marked safariRun")
  Battle.abort()
end

print("[test] 4. BAIT halves the catch factor and the foe eats")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  local before = st.safariState.catchFactor
  Ui._log = {}
  play(2, st)
  -- pokefirered/src/battle_main.c:4382
  eq(st.safariState.catchFactor, math.floor(before / 2), "catchFactor halved")
  eq(st.safariState.baitCounter, 5, "baitCounter capped at 6, then the watch step ticks one off")
  eq(st.safariState.rockCounter, 0, "rockCounter cleared")
  check(log_has("threw some BAIT"), "threw some BAIT line")
  check(log_has("is eating!"), "foe is eating")
  Battle.abort()
end

print("[test] 5. BAIT floors the catch factor at 3")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  st.safariState.catchFactor = 4
  Ui._log = {}
  play(2, st)
  eq(st.safariState.catchFactor, 3, "catchFactor floored at 3")
  Battle.abort()
end

print("[test] 6. ROCK doubles the catch factor and the foe gets angry")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  local before = st.safariState.catchFactor
  Ui._log = {}
  play(3, st)
  -- pokefirered/src/battle_main.c:4398
  eq(st.safariState.catchFactor, math.min(20, before * 2), "catchFactor doubled, capped at 20")
  eq(st.safariState.rockCounter, 5, "rockCounter capped at 6, then the watch step ticks one off")
  eq(st.safariState.baitCounter, 0, "baitCounter cleared")
  check(log_has("threw a ROCK"), "threw a ROCK line")
  check(log_has("is angry!"), "foe is angry")
  Battle.abort()
end

print("[test] 7. Rock counter running out restores the base catch factor")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  st.safariState.catchFactor = 20
  st.safariState.rockCounter = 1
  Ui._log = {}
  -- pokefirered/src/battle_main.c:4334
  play(1, st)
  eq(st.safariState.rockCounter, 0, "rock counter ticked to 0")
  eq(st.safariState.catchFactor, math.floor(FOE_CATCH_RATE * 100 / 1275),
    "base catch factor restored from the species row")
  check(log_has("is watching"), "watching line once the rock counter hits 0")
  Battle.abort()
end

print("[test] 8. Safari Ball uses the safari catch rate, not the species rate")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  st.enemy.mon.hp = st.enemy.mon.maxHp
  local safariOdds = Catching.catchOdds(5, st.enemy, st, session)
  st.safariState = nil
  local speciesOdds = Catching.catchOdds(5, st.enemy, st, session)
  check(safariOdds ~= speciesOdds, "safari path differs from the species path")
  -- pokefirered/src/battle_script_commands.c:9496
  local expectRate = Rules.safari.ballCatchRate(
    Rules.safari.newState(FOE_CATCH_RATE, nil))
  eq(expectRate, math.floor(math.floor(FOE_CATCH_RATE * 100 / 1275) * 1275 / 100),
    "ballCatchRate = catchFactor * 1275 / 100")
  Battle.abort()
end

print("[test] 9. Throwing a ball spends one and writes it back to the session")
do
  local session = new_session(3)
  local st = start_safari(session, function(_, hi) return hi end)
  Ui._log = {}
  play(1, st)
  eq(st.safariState.balls, 2, "one ball spent")
  eq(session.safari.balls, 2, "session.safari.balls follows")
  check(log_has("used\nthe"), "used the SAFARI BALL line")
  Battle.abort()
end

print("[test] 10. The last ball ends the game")
do
  local session = new_session(1)
  local st = start_safari(session, function(_, hi) return hi end)
  Ui._log = {}
  play(1, st)
  eq(st.safariState.balls, 0, "no balls left")
  eq(session.safari.balls, 0, "session drained")
  -- pokefirered/data/battle_scripts_2.s:105
  check(log_has("out of\nSAFARI BALLS"), "out-of-balls announcement")
  eq(st.endReason, "no_safari_balls", "battle ends with no_safari_balls")
  Battle.abort()
end

print("[test] 11. RUN leaves with no run-odds roll")
do
  local session = new_session(30)
  local st = start_safari(session, function(_, hi) return hi end)
  Ui._log = {}
  play(4, st)
  -- pokefirered/src/battle_main.c:4415
  eq(st.endReason, "safari_run", "outcome RAN")
  eq(st.fleeAttempts, 0, "Engine.tryFlee never ran, so no run-odds roll")
  check(not log_has("Can't escape"), "no failed-escape text")
  check(not log_has("Got away safely"), "no wild-flee text")
  Battle.abort()
end

print("[test] 12. Cmd_if_random_safari_flee reads the live safari state")
do
  -- pokefirered/src/battle_ai_script_commands.c:1713
  local pack = {
    scripts = {
      AI_Safari = { { op = "if_random_safari_flee", target = "AI_Safari_Flee" }, { op = "watch" } },
      AI_Safari_Flee = { { op = "flee" } },
    },
  }
  local function run(sf, roll)
    local st = State.new({
      wild = true,
      playerParty = { { species = 1, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } } },
      foeMon = { species = FOE_SPECIES, level = 8, hp = 24, maxHp = 24, moves = { 33 }, pp = { 35 } },
    })
    st.safari = true
    st.safariState = sf
    local vm = AiVm.new({
      pack = pack, st = st, user = st.enemy, target = st.player,
      userSide = st.enemySide, targetSide = st.playerSide,
      scores = { 100, 100, 100, 100 }, simulatedRNG = { 100, 100, 100, 100 },
      rng = function() return roll end,
    })
    AiVm.run(vm, "AI_Safari")
    return vm.aiAction
  end
  local FLEE = 0x2
  local WATCH = 0x4
  local base = Rules.safari.newState(FOE_CATCH_RATE, nil)
  eq(Rules.safari.fleeRate(base), 10, "plain flee rate = escapeFactor * 5")
  check(run(base, 9) % (FLEE * 2) >= FLEE, "roll 9 < 10 flees")
  check(run(base, 10) % (FLEE * 2) < FLEE, "roll 10 does not flee")
  check(run(base, 10) % (WATCH * 2) >= WATCH, "not fleeing watches")

  local rocked = Rules.safari.newState(FOE_CATCH_RATE, nil)
  rocked.rockCounter = 3
  eq(Rules.safari.fleeRate(rocked), 20, "rock flee rate = min(escape*2,20)*5")
  check(run(rocked, 19) % (FLEE * 2) >= FLEE, "roll 19 < 20 flees after a rock")

  local baited = Rules.safari.newState(FOE_CATCH_RATE, nil)
  baited.baitCounter = 3
  eq(Rules.safari.fleeRate(baited), 5, "bait flee rate = max(escape/4,1)*5")
  check(run(baited, 5) % (FLEE * 2) < FLEE, "roll 5 does not flee after bait")
  check(run(baited, 4) % (FLEE * 2) >= FLEE, "roll 4 < 5 flees after bait")
end

print("[test] 13. The player battler is zeroed, so the party lead is not in the battle")
do
  local session = new_session(30)
  session.party[1].hp = 3
  session.party[1].status = "PSN"
  session.party[1].ability = "INTIMIDATE"
  local st = start_safari(session, function(_, hi) return hi end)
  -- pokefirered/src/battle_main.c:2565
  eq(st.player.species, 0, "the player battler species is 0")
  eq(st.player.ability, nil, "no ability")
  eq(st.player.status, nil, "no status")
  eq(st.player.mon.hp, 0, "zeroed hp")
  check(st.player.mon ~= session.party[1], "it is not the party lead's own row")
  Ui._log = {}
  play(3, st)
  play(3, st)
  -- pokefirered/src/battle_util.c:1678
  check(not log_has("INTIMIDATE"), "the lead's switch-in ability never fires")
  -- pokefirered/src/battle_util.c:1146
  eq(session.party[1].hp, 3, "the party lead takes no residual damage")
  eq(st.result, nil, "no win / lose outcome in a Safari battle")
  check(not log_has("blacked out"), "no blackout")
  Battle.abort()
end

print("[test] 14. A live enemy flee ends the battle")
do
  local session = new_session(30)
  -- pokefirered/src/battle_ai_script_commands.c:1713
  local st = start_safari(session, function(lo) return lo end)
  Ui._log = {}
  play(2, st)
  eq(st.endReason, "enemy_fled", "the foe fled on a low roll")
  eq(st.result, "run", "outcome RAN")
  check(log_has("fled!"), "wild foe fled line")
  Battle.abort()
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed == 0 then print("SAFARI_BATTLE PASS") end
os.exit(failed == 0 and 0 or 1)

require("tests.game3_cache").mountOrSkip("game3_battle_ko_turn_residuals_test")

local Battle = require("src.core.game3.battle.init")
local Commands = require("src.core.game3.battle.commands")
local Damage = require("src.core.game3.battle.damage")
local Ui = require("src.core.game3.battle.ui")

local function check(cond, msg)
  if not cond then error("[FAIL] " .. tostring(msg), 2) end
  print("[PASS] " .. tostring(msg))
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("[FAIL] %s: expected %s, got %s", tostring(msg), tostring(b), tostring(a)), 2)
  end
  print("[PASS] " .. tostring(msg))
end

local function mkRng(map)
  return function(lo, hi)
    local v = map[tostring(lo) .. "," .. tostring(hi)]
    if v ~= nil then return v end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
end

local function foe()
  return Damage.ensureStats({ species = 16, level = 2, hp = 5, maxHp = 12, moves = { 150 }, pp = { 40 } })
end

local function run(foeCount, onStart)
  local lead = Damage.ensureStats({ species = 149, level = 100, hp = 100, maxHp = 300,
    moves = { 200 }, pp = { 15 }, item = 200, heldItem = 200 })
  local bench = Damage.ensureStats({ species = 6, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 } })
  local foes = {}
  for i = 1, foeCount do foes[i] = foe() end
  local ok = Battle.start({ playerName = "RED", headless = true, autoFight = false,
    playerParty = { lead, bench }, foeParty = foes, foe = { trainerId = 326 }, wild = false,
    rng = mkRng({ ["0,1"] = 0 }) })
  check(ok, "trainer battle started")
  if onStart then onStart() end
  local snaps = {}
  for _ = 1, 400 do
    if not Battle.isActive() then break end
    Battle.update(0, nil)
    local st = Battle.getState()
    if Battle._phase == "command" and st then
      local p = st.player
      snaps[#snaps + 1] = {
        hp = tonumber(p.mon.hp), rampage = p.expRampageTurns, locked = p.expLockedMove,
        confused = p.confusionTurns, enemyIdx = st.enemy.partyIndex, log = table.concat(Ui.log() or {}, "\n"),
      }
      if #snaps >= 4 then break end
      Ui._pendingCommand = Commands.playerAction(st, 1, 1)
    end
  end
  return snaps, lead
end

print("--- Outrage KO turn still runs end-of-turn effects ---")
do
  local snaps = run(4)
  check(#snaps >= 3, "three command phases reached")
  eq(snaps[2].enemyIdx, 2, "foe sent out its second mon after the first KO")
  -- pokefirered/src/battle_util.c:953
  eq(snaps[2].rampage, 1, "rampage counter ticked down on the KO turn")
  check(snaps[2].locked ~= nil, "still locked into Outrage after turn one")
  -- pokefirered/src/battle_main.c:2953
  check(snaps[2].hp > 100, "Leftovers healed on the KO turn")
  eq(snaps[3].enemyIdx, 3, "foe sent out its third mon after the second KO")
  eq(snaps[3].rampage, nil, "rampage ended after two turns")
  eq(snaps[3].locked, nil, "Outrage lock released")
  check((snaps[3].confused or 0) > 0, "fatigue confusion set on the second KO turn")
  check(snaps[3].log:find("fatigue") ~= nil, "fatigue confusion message shown")
  Battle.abort()
end

print("--- A replaced foe does not act on the turn it comes in ---")
do
  local snaps = run(3)
  local log = (snaps[2] and snaps[2].log or ""):gsub("%s+", " ")
  local faint = log:find("fainted!", 1, true)
  check(faint ~= nil, "first foe fainted")
  local tail = log:sub(faint)
  local sendOut = tail:find("sent out", 1, true)
  local leftovers = tail:find("LEFTOVERS", 1, true)
  check(sendOut ~= nil, "second foe send-out logged")
  check(leftovers ~= nil and leftovers > sendOut, "end-of-turn effects run after the replacement comes in")
  -- pokefirered/data/battle_scripts_1.s:2886
  check(not tail:find("SPLASH", 1, true), "replacement did not act that turn")
  Battle.abort()
end

local function runParties(playerParty, foes, maxSnaps)
  local ok = Battle.start({ playerName = "RED", headless = true, autoFight = false,
    playerParty = playerParty, foeParty = foes, foe = { trainerId = 326 }, wild = false,
    rng = mkRng({ ["0,1"] = 0 }) })
  check(ok, "trainer battle started")
  local snaps = {}
  for _ = 1, 400 do
    if not Battle.isActive() then break end
    Battle.update(0, nil)
    local st = Battle.getState()
    if Battle._phase == "command" and st then
      snaps[#snaps + 1] = {
        playerIdx = st.player.partyIndex, enemyIdx = st.enemy.partyIndex,
        enemyHp = tonumber(st.enemy.mon.hp), log = table.concat(Ui.log() or {}, "\n"):gsub("%s+", " "),
      }
      if #snaps >= maxSnaps then break end
      Ui._pendingCommand = Commands.playerAction(st, 1, 1)
    end
  end
  return snaps
end

print("--- Player faint mid-turn: replacement comes in, turn still ends normally ---")
do
  local weak = Damage.ensureStats({ species = 16, level = 2, hp = 1, maxHp = 12, moves = { 33 }, pp = { 35 } })
  local bench = Damage.ensureStats({ species = 6, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 } })
  local foeA = Damage.ensureStats({ species = 19, level = 60, hp = 40, maxHp = 160, moves = { 98 }, pp = { 30 },
    item = 200, heldItem = 200 })
  local benchHp = tonumber(bench.hp)
  local snaps = runParties({ weak, bench }, { foeA, foe() }, 2)
  check(#snaps >= 2, "second command phase reached")
  eq(snaps[2].playerIdx, 2, "player replacement sent out")
  check(snaps[2].enemyHp > 40, "foe Leftovers ran on the turn the player's mon fainted")
  eq(tonumber(bench.hp), benchHp, "replacement was not attacked that turn")
  Battle.abort()
end

print("--- Mutual faint: player picks first, then foe sends out, then end of turn ---")
do
  local weak = Damage.ensureStats({ species = 16, level = 2, hp = 1, maxHp = 12, moves = { 33 }, pp = { 35 } })
  local bench = Damage.ensureStats({ species = 6, level = 50, hp = 150, maxHp = 150, moves = { 33 }, pp = { 35 } })
  local bomber = Damage.ensureStats({ species = 74, level = 60, hp = 150, maxHp = 150, moves = { 153 }, pp = { 5 } })
  local snaps = runParties({ weak, bench }, { bomber, foe() }, 2)
  check(#snaps >= 2, "second command phase reached")
  eq(snaps[2].playerIdx, 2, "player replacement sent out")
  eq(snaps[2].enemyIdx, 2, "foe replacement sent out")
  local log = snaps[2].log
  local go = log:find("CHARIZARD!", 1, true)
  local sent = log:find("sent out PIDGEY", (go or 1), true)
  -- pokefirered/src/battle_util.c:1195
  check(go ~= nil and sent ~= nil and go < sent, "player replacement before foe replacement")
  Battle.abort()
end

print("--- Final KO ends the battle without end-of-turn effects ---")
do
  local snaps, lead = run(1)
  eq(#snaps, 1, "battle ended after the only foe fainted")
  eq(Battle.isActive(), false, "battle no longer active")
  eq(tonumber(lead.hp), 100, "no Leftovers heal after the battle was decided")
end

print("ALL PASS game3_battle_ko_turn_residuals_test")

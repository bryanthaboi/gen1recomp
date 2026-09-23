-- Comprehensive unit & integration tests for Game 3 battle status effect & residual timing.

require("tests.game3_cache").requireData("game3_battle_status_timing_test")
local Battle = require("src.core.game3.battle.init")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Residuals = require("src.core.game3.battle.residuals")
local Adapter = require("src.core.game3.battle.adapter")
local Ui = require("src.core.game3.battle.ui")
local Commands = require("src.core.game3.battle.commands")
local Damage = require("src.core.game3.battle.damage")
local SwitchSeq = require("src.core.game3.battle.switch_seq")

local function check(cond, msg)
  if not cond then
    error("[FAIL] " .. tostring(msg), 2)
  end
  print("[PASS] " .. tostring(msg))
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("[FAIL] %s: expected %s, got %s", tostring(msg), tostring(b), tostring(a)), 2)
  end
  print("[PASS] " .. tostring(msg))
end

print("=== [TEST 1] Sequential Residual Events & Speed Ordering ===")
do
  -- Charizard (speed 100, player) vs Blastoise (speed 78, enemy)
  -- Both afflicted with status (Charizard: PSN, Blastoise: BRN)
  local pParty = {
    { species = 6, level = 50, hp = 100, maxHp = 100, speed = 100, status = "PSN", moves = { 33 }, pp = { 35 } },
  }
  local eParty = {
    { species = 9, level = 50, hp = 80, maxHp = 80, speed = 78, status = "BRN", moves = { 33 }, pp = { 35 } },
  }
  local st = State.new({
    wild = true,
    playerParty = pParty,
    foeParty = eParty,
  })
  local ad = Adapter.new(st, function() end)

  local events = Engine.collectResidualEvents(st, ad)
  eq(#events, 2, "collected exactly 2 discrete residual events")
  eq(events[1].target.side, "player", "event 1 resolved for faster battler (player Charizard)")
  eq(events[1].msgs[1], "CHARIZARD is hurt\nby poison!", "event 1 has correct poison text")
  eq(events[1].hpChanges[1].side, "player", "event 1 hp change is on player")
  eq(events[1].hpChanges[1].from, 100, "event 1 hp from 100")
  local pLoss = math.max(1, math.floor(ad:maxHp(st.player) / 8))
  local eLoss = math.max(1, math.floor(ad:maxHp(st.enemy) / 8))
  eq(events[1].hpChanges[1].to, 100 - pLoss, "event 1 hp to 100 - pLoss")

  eq(events[2].target.side, "enemy", "event 2 resolved for slower battler (enemy Blastoise)")
  eq(events[2].msgs[1], "Wild BLASTOISE is hurt\nby its burn!", "event 2 has correct burn text")
  eq(events[2].hpChanges[1].side, "enemy", "event 2 hp change is on enemy")
  eq(events[2].hpChanges[1].from, 80, "event 2 hp from 80")
  eq(events[2].hpChanges[1].to, 80 - eLoss, "event 2 hp to 80 - eLoss")
end

print("\n=== [TEST 2] Speed Stages Invert Residual Execution Order ===")
do
  -- Charizard (speed 100, player, stage -2 => 50) vs Blastoise (speed 78, enemy, stage 0 => 78)
  local pParty = {
    { species = 6, level = 50, hp = 100, maxHp = 100, speed = 100, status = "PSN", moves = { 33 }, pp = { 35 } },
  }
  local eParty = {
    { species = 9, level = 50, hp = 80, maxHp = 80, speed = 78, status = "BRN", moves = { 33 }, pp = { 35 } },
  }
  local st = State.new({
    wild = true,
    playerParty = pParty,
    foeParty = eParty,
  })
  st.player.stages.speed = -2
  local ad = Adapter.new(st, function() end)

  local events = Engine.collectResidualEvents(st, ad)
  eq(#events, 2, "collected 2 discrete residual events")
  eq(events[1].target.side, "enemy", "event 1 is now enemy Blastoise (faster due to player speed stage drop)")
  eq(events[2].target.side, "player", "event 2 is player Charizard")
end

print("\n=== [TEST 3] Leech Seed Discrete Event with Sapped Damage & Heal ===")
do
  local pParty = {
    { species = 1, level = 20, hp = 40, maxHp = 50, speed = 50, status = 0, moves = { 33 }, pp = { 35 } },
  }
  local eParty = {
    { species = 16, level = 20, hp = 30, maxHp = 50, speed = 60, status = 0, moves = { 33 }, pp = { 35 } },
  }
  local st = State.new({
    wild = true,
    playerParty = pParty,
    foeParty = eParty,
  })
  local ad = Adapter.new(st, function() end)
  -- Enemy is seeded by player
  st.enemy.expSeeded = true
  st.enemy.expSeedSource = st.player

  local events = Engine.collectResidualEvents(st, ad)
  eq(#events, 1, "collected 1 Leech Seed event")
  eq(events[1].phase, "leech_seed", "event phase is leech_seed")
  check(events[1].msgs[1]:find("sapped by LEECH SEED!"), "contains sapped by leech seed text")
  eq(#events[1].hpChanges, 2, "2 hp changes: enemy took loss and player healed")
  local pChange, eChange
  for _, ch in ipairs(events[1].hpChanges) do
    if ch.side == "player" then pChange = ch end
    if ch.side == "enemy" then eChange = ch end
  end
  check(pChange ~= nil and pChange.to > pChange.from, "player received healing")
  check(eChange ~= nil and eChange.to < eChange.from, "enemy took damage")
end

print("\n=== [TEST 4] Turn Execution with Residual Damage at End of Turn ===")
do
  local pMon = Damage.ensureStats({ species = 25, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  pMon.status = "PSN"

  local ok, err = Battle.start({ playerName = "RED",
    headless = true,
    autoFight = false,
    playerParty = { pMon },
    foe = foeMon,
    wild = true,
  })
  check(ok, "Battle started successfully")
  Battle.update(0, nil) -- Advance intro to command
  eq(Battle._phase, "command", "reached command phase for turn 1")

  -- Queue Tackle for player and enemy
  Battle._actions = {
    { kind = "move", user = "player", target = "enemy", move = 33, slot = 1 },
    { kind = "move", user = "enemy", target = "player", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"

  local hpBeforeResiduals = pMon.hp
  local guard = 0
  while Battle._phase == "actions" and guard < 10 do
    guard = guard + 1
    Battle.update(0, nil)
  end

  -- Turn ended: player mon took poison chip
  check(pMon.hp < hpBeforeResiduals, "player mon took poison damage at end of turn")
  eq(Battle._phase, "command", "cleanly transitioned to command phase for turn 2")
  eq(#Ui._queue, 0, "no residual messages left in Ui._queue at start of next turn")

  -- Verify Ui.log recorded the hurt by poison message during the turn
  local foundPoisonMsg = false
  for _, msg in ipairs(Ui.log() or {}) do
    if msg:find("hurt\nby poison", 1, true) then
      foundPoisonMsg = true
      break
    end
  end
  check(foundPoisonMsg, "Ui.log recorded 'hurt by poison' text during the turn")
  Battle.abort("win")
end

print("\n=== [TEST 5] Residual Faint Interrupts Flow & Triggers Switch/Party Menu ===")
do
  local pMon1 = Damage.ensureStats({ species = 25, level = 10, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local foeMon = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })

  Battle.start({ playerName = "RED",
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foe = foeMon,
    wild = true,
  })
  Battle.update(0, nil) -- Intro to command

  local st = Battle.getState()
  st.playerParty[1].hp = 1
  st.playerParty[1].status = "PSN"
  st.player.mon.hp = 1
  st.player.status = "PSN"

  -- Queue a move
  Battle._actions = {
    { kind = "move", user = "player", target = "enemy", move = 33, slot = 1 },
  }
  Battle._actionI = 1
  Battle._phase = "actions"

  local guard = 0
  while (Battle._phase == "actions" or Battle._phase == "switching") and guard < 30 do
    guard = guard + 1
    Battle.update(0, nil)
  end

  local st = Battle.getState()
  eq(st.playerParty[1].hp, 0, "playerParty[1] fainted from poison")
  -- In headless mode, handle_player_faint auto-sends out next living mon (slot 2)
  eq(st.player.partyIndex, 2, "switched to conscious slot 2 after faint")
  eq(Battle._phase, "command", "ready for command after faint replacement")
  Battle.abort("win")
end

print("\n=== [TEST 6] Mutual Faint Resolution at End of Turn ===")
do
  -- Both player and enemy have 1 HP and are poisoned; both have reserves
  local pMon1 = Damage.ensureStats({ species = 1, level = 10, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local pMon2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local fMon1 = Damage.ensureStats({ species = 16, level = 10, maxHp = 30, moves = { 33 }, pp = { 35 } })
  local fMon2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } })

  Battle.start({ playerName = "RED",
    headless = true,
    autoFight = false,
    playerParty = { pMon1, pMon2 },
    foeParty = { fMon1, fMon2 },
    trainerId = 326,
    wild = false,
  })
  Battle.update(0, nil)

  local st = Battle.getState()
  st.playerParty[1].hp = 1
  st.playerParty[1].status = "PSN"
  st.player.mon.hp = 1
  st.player.status = "PSN"
  st.foeParty[1].hp = 1
  st.foeParty[1].status = "PSN"
  st.enemy.mon.hp = 1
  st.enemy.status = "PSN"

  Battle._actions = {}
  Battle._actionI = 1
  Battle._phase = "actions"

  local guard = 0
  while (Battle._phase == "actions" or Battle._phase == "switching") and guard < 30 do
    guard = guard + 1
    Battle.update(0, nil)
  end

  eq(st.playerParty[1].hp, 0, "player slot 1 fainted")
  eq(st.foeParty[1].hp, 0, "enemy slot 1 fainted")
  check(not st.over, "battle is NOT over because both have living reserves")
  eq(st.enemy.partyIndex, 2, "enemy sent out next mon (slot 2)")
  eq(st.player.partyIndex, 2, "player sent out next mon (slot 2)")
  Battle.abort("win")
end

print("\n=== [TEST 7] Headless & Auto Battle Run to End Cleanly ===")
do
  local pParty = {
    { species = 25, level = 20, hp = 50, maxHp = 50, speed = 90, status = "PSN", moves = { 33 }, pp = { 35 } },
  }
  local eParty = {
    { species = 16, level = 5, hp = 15, maxHp = 15, speed = 30, status = "BRN", moves = { 33 }, pp = { 35 } },
  }
  Battle.start({ playerName = "RED",
    wild = true,
    playerParty = pParty,
    foeParty = eParty,
    headless = true,
    auto = true,
  })

  local res = Battle.runToEnd()
  eq(res, "win", "battle concluded with win in headless auto mode")
end

print("\nALL BATTLE STATUS & RESIDUAL TIMING TESTS PASSED CLEANLY! (100%)")

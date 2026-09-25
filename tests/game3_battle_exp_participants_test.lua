-- Unit tests for Game 3 battle experience participant tracking and distribution.
-- Covers pret parity for in-battle switches, shift switches, enemy switches, and double battles.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_exp_participants_test")
if not _G.love then _G.love = require("tests.love_stub") end

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local SwitchSeq = require("src.core.game3.battle.switch_seq")
local Experience = require("src.core.game3.battle.experience")
local Damage = require("src.core.game3.battle.damage")
local Battle = require("src.core.game3.battle.init")

local origExpYield = Experience.expYield
Experience.expYield = function(species)
  local y = origExpYield(species)
  if y and y > 0 then return y end
  return 100
end

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

print("=== 1. In-battle switch: both participants split EXP ===")
do
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2 },
    foeParty = { e1 },
    foeMon = e1,
    wild = true,
  })

  -- Slot 1 starts active. Switch to slot 2 during battle against e1.
  eq(st.enemy.participants[1], true, "slot 1 initially tracked as participant on e1")
  eq(st.enemy.participants[2], nil, "slot 2 not yet participant on e1")

  SwitchSeq.beginPlayerSwitch(st, 2, { headless = true })
  eq(st.enemy.participants[1], true, "slot 1 remained participant after switch")
  eq(st.enemy.participants[2], true, "slot 2 tracked as participant after switch")

  local awards = Experience.awardFoe(st, st.enemy, { trainer = false })
  eq(#awards, 2, "both mons received awards")
  eq(awards[1].partyIndex, 1, "award 1 goes to slot 1")
  eq(awards[2].partyIndex, 2, "award 2 goes to slot 2")
  eq(awards[1].amount, awards[2].amount, "both mons received equal split of EXP")
end

print("\n=== 2. Shift switch on enemy defeat: previous mons do NOT receive EXP for next enemy ===")
do
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p3 = Damage.ensureStats({ species = 7, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 1, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2, p3 },
    foeParty = { e1, e2 },
    foeMon = e1,
    wild = false,
  })

  -- In fight against e1, player switches from p1 to p2
  SwitchSeq.beginPlayerSwitch(st, 2, { headless = true })
  eq(st.enemy.participants[1], true, "p1 is participant on e1")
  eq(st.enemy.participants[2], true, "p2 is participant on e1")
  eq(st.enemy.participants[3], nil, "p3 is not participant on e1")

  -- e1 faints, awards given
  local awards1 = Experience.awardFoe(st, st.enemy, { trainer = true })
  eq(#awards1, 2, "p1 and p2 both received EXP for e1")

  -- Shift switch: player chooses to switch to p3 for e2
  SwitchSeq.beginShiftSwitch(st, 3, 2, { headless = true })

  eq(st.player.partyIndex, 3, "p3 is now active player mon")
  eq(st.enemy.partyIndex, 2, "e2 is now active enemy mon")
  eq(st.enemy.participants[1], nil, "p1 is NOT participant on e2")
  eq(st.enemy.participants[2], nil, "p2 is NOT participant on e2")
  eq(st.enemy.participants[3], true, "only p3 is participant on e2")

  -- e2 faints, awards given
  local awards2 = Experience.awardFoe(st, st.enemy, { trainer = true })
  eq(#awards2, 1, "only p3 receives EXP for e2")
  eq(awards2[1].partyIndex, 3, "award goes to p3")
  check(awards2[1].amount > awards1[1].amount, "p3 receives full undivided EXP for e2")
end

print("\n=== 2b. Live shift step list: player swaps before enemy, only new mon earns EXP ===")
do
  local Adapter = require("src.core.game3.battle.adapter")
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 0, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2 },
    foeParty = { e1, e2 },
    foeMon = e1,
    wild = false,
  })
  local ad = Adapter.new(st, function() end)

  eq(SwitchSeq.beginShiftSwitch(st, 2, 2, { headless = false }), true, "live shift builds a step list")
  local swaps = {}
  for _, step in ipairs(SwitchSeq._steps or {}) do
    if step.kind == "swap_data" then swaps[#swaps + 1] = step.data end
  end
  eq(#swaps, 2, "shift step list has two swap_data rows")
  eq(swaps[1].side, "player", "player swap_data runs before the enemy send-out")
  eq(swaps[2].side, "enemy", "enemy swap_data runs second")
  SwitchSeq.reset()

  for _, d in ipairs(swaps) do
    Engine.performSwitch(st, ad, d.side, d.newSlot,
      { reason = d.reason or "switch", isShift = d.isShift })
  end
  eq(st.player.partyIndex, 2, "p2 is active after live shift")
  eq(st.enemy.partyIndex, 2, "e2 is active after live shift")
  eq(st.enemy.participants[1], nil, "withdrawn p1 is NOT participant on e2 (live path)")
  eq(st.enemy.participants[2], true, "p2 is participant on e2 (live path)")

  local awards = Experience.awardFoe(st, st.enemy, { trainer = true })
  eq(#awards, 1, "only p2 receives EXP for e2 (live path)")
  eq(awards[1].partyIndex, 2, "live-path award goes to p2")
end

print("\n=== 2d. Shift switch-in effects: player Spikes before the enemy send-out, Intimidate hits the new foe ===")
do
  local Adapter = require("src.core.game3.battle.adapter")
  local Hazards = require("src.core.game3.battle.effects.hazards")
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 58, level = 10, hp = 32, maxHp = 32, exp = 1000, ability = 22 })
  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 0, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000, ability = 50 })

  local st = State.new({
    playerParty = { p1, p2 },
    foeParty = { e1, e2 },
    foeMon = e1,
    wild = false,
  })
  st.trainerClassName, st.trainerName = "YOUNGSTER", "BEN"
  local savedAd = Battle._adapter
  Battle._adapter = Adapter.new(st, function() end)
  Hazards.set(st.playerSide, 1)
  local log = {}
  SwitchSeq.beginShiftSwitch(st, 2, 2, { headless = true, pushMsg = function(text)
    log[#log + 1] = tostring(text):lower()
  end })
  Battle._adapter = savedAd

  local spikesAt, sentAt, intimAt
  for i, t in ipairs(log) do
    if t:find("spikes") then spikesAt = spikesAt or i end
    if t:find("sent") then sentAt = sentAt or i end
    if t:find("cuts") then intimAt = intimAt or i end
  end
  check(spikesAt ~= nil and sentAt ~= nil and intimAt ~= nil, "spikes, send-out and Intimidate messages pushed")
  check(spikesAt < sentAt, "player Spikes resolve before the enemy sends out")
  eq(st.player.mon.hp, 28, "player took 1/8 Spikes damage")
  check(intimAt > sentAt, "Intimidate resolves after the new foe is out")
  eq(st.enemy.stages.attack, -1, "new foe's attack cut by the shifted-in Intimidate")

  eq(SwitchSeq.beginShiftSwitch(st, 1, 2, { headless = false }), true, "live shift builds a step list")
  local entry, enemySwap = {}, nil
  for i, step in ipairs(SwitchSeq._steps or {}) do
    if step.kind == "entry_triggers" then entry[#entry + 1] = { i = i, d = step.data } end
    if step.kind == "swap_data" and step.data.side == "enemy" then enemySwap = { i = i, d = step.data } end
  end
  SwitchSeq.reset()
  eq(#entry, 2, "two entry_triggers steps")
  eq(entry[1].d.side, "player", "first entry step is the player's")
  check(entry[1].d.deferIntimidate, "player entry step defers Intimidate")
  check(entry[1].i < enemySwap.i, "player entry step runs before the enemy swap_data")
  eq(entry[2].d.side, "enemy", "second entry step is the enemy's")
  check(entry[2].i > enemySwap.i, "enemy entry step runs after the enemy swap_data")
  eq(enemySwap.d.reason, "shift", "enemy swap_data keeps reason shift")
end

print("\n=== 2c. Shift performSwitch resets sent mons even when the enemy swaps first ===")
do
  local Adapter = require("src.core.game3.battle.adapter")
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 0, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2 },
    foeParty = { e1, e2 },
    foeMon = e1,
    wild = false,
  })
  local ad = Adapter.new(st, function() end)
  Engine.performSwitch(st, ad, "enemy", 2, { reason = "switch" })
  eq(st.enemy.participants[1], true, "p1 tracked on e2 while still active")
  Engine.performSwitch(st, ad, "player", 2, { reason = "shift", isShift = true })
  eq(st.enemy.participants[1], nil, "shift switch drops p1 from e2's sent mons")
  eq(st.enemy.participants[2], true, "shift switch leaves only p2 on e2")
end

print("\n=== 3. Enemy AI switch resets participant tracking ===")
do
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2 },
    foeParty = { e1, e2 },
    foeMon = e1,
    wild = false,
  })

  -- Player switches to p2 against e1
  SwitchSeq.beginPlayerSwitch(st, 2, { headless = true })
  eq(st.enemy.participants[1], true, "p1 fought e1")
  eq(st.enemy.participants[2], true, "p2 fought e1")

  -- Opponent trainer switches e1 out for e2
  SwitchSeq.beginSendOut(st, "enemy", 2, { headless = true })
  eq(st.enemy.partyIndex, 2, "e2 is now active")
  eq(st.enemy.participants[1], nil, "p1 is NOT a participant on e2")
  eq(st.enemy.participants[2], true, "only active mon p2 is participant on e2")

  local awards = Experience.awardFoe(st, st.enemy, { trainer = true })
  eq(#awards, 1, "only p2 receives EXP for e2")
  eq(awards[1].partyIndex, 2, "award goes to p2")
end

print("\n=== 4. Double battle participant tracking across replacements ===")
do
  local p1 = Damage.ensureStats({ species = 1, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p2 = Damage.ensureStats({ species = 4, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local p3 = Damage.ensureStats({ species = 7, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local e1 = Damage.ensureStats({ species = 16, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e2 = Damage.ensureStats({ species = 19, level = 10, hp = 30, maxHp = 30, exp = 1000 })
  local e3 = Damage.ensureStats({ species = 25, level = 10, hp = 30, maxHp = 30, exp = 1000 })

  local st = State.new({
    playerParty = { p1, p2, p3 },
    foeParty = { e1, e2, e3 },
    wild = false,
    double = true,
  })

  local foe1 = State.battler(st, 1)
  local foe3 = State.battler(st, 3)
  eq(foe1.participants[1], true, "foe1 tracks p1")
  eq(foe1.participants[2], true, "foe1 tracks p2")
  eq(foe3.participants[1], true, "foe3 tracks p1")
  eq(foe3.participants[2], true, "foe3 tracks p2")

  -- Player switches battler 0 (p1) to p3
  State.updateSentPokes(st, { side = "player", partyIndex = 3 })
  eq(foe1.participants[3], true, "foe1 now tracks p3 as well")
  eq(foe3.participants[3], true, "foe3 now tracks p3 as well")

  -- foe1 faints, replacement foe3 (e3) is sent out into slot 1
  local newFoe1 = State.makeBattler(st.foeParty[3], "enemy", { state = st, partyIndex = 3, id = 1 })
  st.battlers[1] = newFoe1
  State.opponentSwitchInResetSentPokes(st, newFoe1)

  -- Currently active player mons are p2 (battler 2) and p3 (battler 0)
  st.battlers[0].partyIndex = 3
  st.battlers[2].partyIndex = 2
  State.opponentSwitchInResetSentPokes(st, newFoe1)

  eq(newFoe1.participants[1], nil, "withdrawn p1 is NOT participant on replacement newFoe1")
  eq(newFoe1.participants[2], true, "active p2 is participant on newFoe1")
  eq(newFoe1.participants[3], true, "active p3 is participant on newFoe1")
end

print("\n[ALL EXP PARTICIPANT TESTS PASSED! 100%]")

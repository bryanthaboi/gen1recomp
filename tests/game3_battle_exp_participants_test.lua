-- Unit tests for Game 3 battle experience participant tracking and distribution.
-- Covers pret parity for in-battle switches, shift switches, enemy switches, and double battles.

package.path = "./?.lua;./?/init.lua;" .. package.path
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

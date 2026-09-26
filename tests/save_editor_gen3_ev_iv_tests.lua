-- Unit tests for Save Editor Gen 3 EV and IV tracking, editing, caps, and rendering.
-- Run with: luajit tests/save_editor_gen3_ev_iv_tests.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

_G.love = require("tests.love_stub")

local MonOps = require("MonOps")
local Ops = require("Ops")
local Gen = require("Gen")
local Pokemon = require("src.core.game3.pokemon")
Pokemon._stats = { [25] = { hp = 35, atk = 55, def = 40, spe = 90, spa = 50, spd = 50 } }
Pokemon._names = { [25] = "PIKACHU" }
Pokemon._byName = { PIKACHU = 25 }
Pokemon._speciesMeta = { [25] = { growthRate = 0, genderRatio = 127 } }
Pokemon._abilities = { [25] = { 9, 0 } }
Pokemon._abilityNames = { [9] = "STATIC" }
local MonEditor = require("panels.MonEditor")
local Kit = require("Kit")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. tostring(msg))
  end
end

local function checkEq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(("FAIL: %s (got %s, want %s)"):format(tostring(msg), tostring(actual), tostring(expected)))
  end
end

print("== Save Editor Gen 3 EV / IV Tests ==")

local function freshMonG3()
  return {
    species = 25, -- Pikachu
    speciesId = 25,
    level = 50,
    personality = 0,
    ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    stats = {},
  }
end

-- 1. Single-stat EV clamping (0 .. 255)
do
  local mon = freshMonG3()
  local val = MonOps.setEv({}, mon, "spe", 252, 3)
  checkEq(val, 252, "setEv sets 252 Spe EV")
  checkEq(mon.evs.spe, 252, "mon.evs.spe updated to 252")

  -- Negative clamping
  val = MonOps.setEv({}, mon, "spe", -10, 3)
  checkEq(val, 0, "setEv clamps negative value to 0")
  checkEq(mon.evs.spe, 0, "mon.evs.spe updated to 0")

  -- Upper bound 255 clamping
  val = MonOps.setEv({}, mon, "atk", 300, 3)
  checkEq(val, 255, "setEv clamps value > 255 to 255")
  checkEq(mon.evs.atk, 255, "mon.evs.atk updated to 255")
end

-- 2. 510 Total EV Cap Enforcement
do
  local mon = freshMonG3()
  MonOps.setEv({}, mon, "atk", 255, 3)
  MonOps.setEv({}, mon, "spe", 255, 3)
  checkEq(mon.evs.atk + mon.evs.spe, 510, "two stats maxed to 510 total")

  -- Attempt to add EV to a 3rd stat when 510 total reached
  local val = MonOps.setEv({}, mon, "hp", 10, 3)
  checkEq(val, 0, "setEv returns 0 when total EV cap 510 is full")
  checkEq(mon.evs.hp, 0, "mon.evs.hp remains 0")

  -- Partial addition when close to 510
  MonOps.setEv({}, mon, "spe", 250, 3) -- total is now 255 + 250 = 505 (5 remaining)
  val = MonOps.setEv({}, mon, "hp", 20, 3)
  checkEq(val, 5, "setEv truncates to remaining capacity (5)")
  checkEq(mon.evs.hp, 5, "mon.evs.hp set to 5")
  checkEq(mon.evs.atk + mon.evs.spe + mon.evs.hp, 510, "total equals exactly 510")
end

-- 3. Clear EVs
do
  local mon = freshMonG3()
  MonOps.setEv({}, mon, "atk", 252, 3)
  MonOps.setEv({}, mon, "spe", 252, 3)
  MonOps.setEv({}, mon, "hp", 4, 3)
  MonOps.clearEvs({}, mon, 3)
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    checkEq(mon.evs[k], 0, "clearEvs zeroes " .. k)
  end
end

-- 4. IV Setting and Clamping (0 .. 31)
do
  local mon = freshMonG3()
  local val = MonOps.setIv({}, mon, "spe", 31, 3)
  checkEq(val, 31, "setIv sets 31 Spe IV")
  checkEq(mon.ivs.spe, 31, "mon.ivs.spe updated to 31")

  val = MonOps.setIv({}, mon, "spe", -5, 3)
  checkEq(val, 0, "setIv clamps negative IV to 0")
  checkEq(mon.ivs.spe, 0, "mon.ivs.spe updated to 0")

  val = MonOps.setIv({}, mon, "atk", 50, 3)
  checkEq(val, 31, "setIv clamps IV > 31 to 31")
  checkEq(mon.ivs.atk, 31, "mon.ivs.atk updated to 31")

  -- Max all IVs
  MonOps.setIv({}, mon, "hp", 0, 3)
  MonOps.setIv({}, mon, "atk", 0, 3)
  MonOps.maxIvs({}, mon, 3)
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    checkEq(mon.ivs[k], 31, "maxIvs sets " .. k .. " to 31")
  end
end

-- 5. Ops wrappers
do
  local S = {
    data = {},
    save = { version = "firered", engine = "game3", generation = 3 },
    version = "firered",
    editingMon = freshMonG3(),
  }
  local mon = S.editingMon

  Ops.setEv(S, mon, "spe", 252)
  checkEq(mon.evs.spe, 252, "Ops.setEv sets speed EV")

  Ops.clearEvs(S, mon)
  checkEq(mon.evs.spe, 0, "Ops.clearEvs clears speed EV")

  Ops.setIv(S, mon, "spa", 30)
  checkEq(mon.ivs.spa, 30, "Ops.setIv sets spAtk IV")

  Ops.maxIvs(S, mon)
  checkEq(mon.ivs.spa, 31, "Ops.maxIvs maxes spAtk IV")
end

-- 6. Real-time Stat Recalculation Impact
do
  local mon = freshMonG3()
  local baseStats = Pokemon.calcStats(25, 50, mon.ivs, mon.evs, 0)
  checkEq(baseStats.speed, 110, "Base Speed at Lv50 with 31 IV, 0 EV is 110")
  MonOps.setEv({}, mon, "spe", 252, 3)
  local boostedStats = Pokemon.calcStats(25, 50, mon.ivs, mon.evs, 0)
  checkEq(boostedStats.speed, 142, "Boosted Speed at Lv50 with 31 IV, 252 EV is 142")
  checkEq(boostedStats.speed - baseStats.speed, 32, "252 Spe EVs at Lv50 with 31 IV gives +32 Speed")

  -- With 0 IVs
  local bareStats = Pokemon.calcStats(25, 50, { spe = 0 }, { spe = 0 }, 0)
  local maxEvStats = Pokemon.calcStats(25, 50, { spe = 0 }, { spe = 252 }, 0)
  checkEq(maxEvStats.speed - bareStats.speed, 31, "252 Spe EVs at Lv50 with 0 IV gives +31 Speed")
end

-- 7. MonEditor.draw Smoke Tests (Gen 3 wide and narrow)
do
  local S = {
    data = { moves = {} },
    save = { version = "firered", engine = "game3", generation = 3 },
    version = "firered",
    editingMon = freshMonG3(),
    inspectorScroll = 0,
  }

  -- Wide mode
  local okWide, errWide = pcall(function()
    MonEditor.draw(S, Kit, 10, 10, 600, 700)
  end)
  check(okWide, "MonEditor.draw renders Gen 3 wide mode without error: " .. tostring(errWide))

  -- Narrow mode
  local okNarrow, errNarrow = pcall(function()
    MonEditor.draw(S, Kit, 10, 10, 400, 700)
  end)
  check(okNarrow, "MonEditor.draw renders Gen 3 narrow mode without error: " .. tostring(errNarrow))
end

-- 8. MonEditor.draw Smoke Tests (Gen 1 & Gen 2 non-regression)
do
  local S1 = {
    data = { moves = {}, pokemon = { PIKACHU = { name = "PIKACHU" } } },
    save = { version = "red", generation = 1 },
    version = "red",
    editingMon = { species = "PIKACHU", level = 50, dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 } },
    inspectorScroll = 0,
  }
  local okG1, errG1 = pcall(function()
    MonEditor.draw(S1, Kit, 10, 10, 500, 700)
  end)
  check(okG1, "MonEditor.draw renders Gen 1 without error: " .. tostring(errG1))

  local S2 = {
    data = { moves = {}, pokemon = { PIKACHU = { name = "PIKACHU" } } },
    save = { version = "gold", generation = 2 },
    version = "gold",
    editingMon = { species = "PIKACHU", level = 50, dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 } },
    inspectorScroll = 0,
  }
  local okG2, errG2 = pcall(function()
    MonEditor.draw(S2, Kit, 10, 10, 500, 700)
  end)
  check(okG2, "MonEditor.draw renders Gen 2 without error: " .. tostring(errG2))
end

-- 9. PP Calculation and PP Ups Formula
do
  -- Base 10: 10 + floor(10 * 0.2 * N) = 10, 12, 14, 16
  checkEq(MonOps.calcMaxPp(10, 0), 10, "Base 10 PP + 0 Ups = 10")
  checkEq(MonOps.calcMaxPp(10, 1), 12, "Base 10 PP + 1 Up = 12")
  checkEq(MonOps.calcMaxPp(10, 2), 14, "Base 10 PP + 2 Ups = 14")
  checkEq(MonOps.calcMaxPp(10, 3), 16, "Base 10 PP + 3 Ups = 16")

  -- Base 5: 5 + floor(5 * 0.2 * N) = 5, 6, 7, 8
  checkEq(MonOps.calcMaxPp(5, 0), 5, "Base 5 PP + 0 Ups = 5")
  checkEq(MonOps.calcMaxPp(5, 1), 6, "Base 5 PP + 1 Up = 6")
  checkEq(MonOps.calcMaxPp(5, 2), 7, "Base 5 PP + 2 Ups = 7")
  checkEq(MonOps.calcMaxPp(5, 3), 8, "Base 5 PP + 3 Ups = 8")

  -- Base 40: 40 + floor(40 * 0.2 * N) = 40, 48, 56, 64
  checkEq(MonOps.calcMaxPp(40, 0), 40, "Base 40 PP + 0 Ups = 40")
  checkEq(MonOps.calcMaxPp(40, 1), 48, "Base 40 PP + 1 Up = 48")
  checkEq(MonOps.calcMaxPp(40, 2), 56, "Base 40 PP + 2 Ups = 56")
  checkEq(MonOps.calcMaxPp(40, 3), 64, "Base 40 PP + 3 Ups = 64")
end

-- 10. Gen 3 PP Ups and PP Editing
do
  local mon = freshMonG3()
  mon.moves = { 85, 98, 0, 0 } -- Thunderbolt (base 15), Quick Attack (base 30)
  mon.pp = { 15, 30, 0, 0 }
  mon.maxPp = { 15, 30, 0, 0 }
  mon.ppBonusesPacked = 0

  local data = {
    moves = {
      [85] = { name = "THUNDERBOLT", pp = 15 },
      [98] = { name = "QUICK ATTACK", pp = 30 },
    }
  }

  -- Check initial PP Ups
  checkEq(MonOps.getPpUps(mon, 1), 0, "Slot 1 initial PP Ups is 0")
  checkEq(MonOps.getPpUps(mon, 2), 0, "Slot 2 initial PP Ups is 0")

  -- Set Slot 1 to 3 PP Ups (15 -> 24 max PP)
  MonOps.setPpUps(data, mon, 1, 3, 3)
  checkEq(MonOps.getPpUps(mon, 1), 3, "Slot 1 PP Ups is 3")
  checkEq(mon.maxPp[1], 24, "Slot 1 max PP updated to 24")
  checkEq(mon.ppBonusesPacked, 3, "ppBonusesPacked is 3")

  -- Set Slot 2 to 2 PP Ups (30 -> 42 max PP)
  MonOps.setPpUps(data, mon, 2, 2, 3)
  checkEq(MonOps.getPpUps(mon, 2), 2, "Slot 2 PP Ups is 2")
  checkEq(mon.maxPp[2], 42, "Slot 2 max PP updated to 42")
  -- Slot 1 has 3 in bits 0-1, Slot 2 has 2 in bits 2-3 (2 << 2 = 8): 3 | 8 = 11
  checkEq(mon.ppBonusesPacked, 11, "ppBonusesPacked packed bitfield is 11")

  -- Set current PP
  MonOps.setPp(data, mon, 1, 20, 3)
  checkEq(mon.pp[1], 20, "Slot 1 current PP set to 20")

  -- Set current PP above max PP (clamped to maxPp 24)
  MonOps.setPp(data, mon, 1, 50, 3)
  checkEq(mon.pp[1], 24, "Slot 1 current PP clamped to max 24")

  -- Set current PP below 0 (clamped to 0)
  MonOps.setPp(data, mon, 1, -5, 3)
  checkEq(mon.pp[1], 0, "Slot 1 current PP clamped to min 0")

  -- Max all PP ups
  MonOps.maxAllPpUps(data, mon, 3)
  checkEq(MonOps.getPpUps(mon, 1), 3, "Slot 1 maxed to 3 PP Ups")
  checkEq(MonOps.getPpUps(mon, 2), 3, "Slot 2 maxed to 3 PP Ups")
  checkEq(mon.maxPp[1], 24, "Slot 1 max PP is 24")
  checkEq(mon.maxPp[2], 48, "Slot 2 max PP is 48 (30 + 18)")
end

-- 11. Gen 1 / Gen 2 PP Ups and PP Editing
do
  local mon = {
    species = "PIKACHU",
    level = 50,
    moves = {
      { id = "THUNDERBOLT", pp = 15, maxPp = 15 },
      { id = "QUICK_ATTACK", pp = 30, maxPp = 30 },
    }
  }
  local data = {
    moves = {
      THUNDERBOLT = { name = "THUNDERBOLT", pp = 15 },
      QUICK_ATTACK = { name = "QUICK ATTACK", pp = 30 },
    }
  }

  checkEq(MonOps.getPpUps(mon, 1), 0, "Gen 1 slot 1 PP Ups is 0")
  MonOps.setPpUps(data, mon, 1, 3, 1)
  checkEq(MonOps.getPpUps(mon, 1), 3, "Gen 1 slot 1 PP Ups set to 3")
  checkEq(mon.moves[1].maxPp, 24, "Gen 1 slot 1 maxPp is 24")

  MonOps.setPp(data, mon, 1, 10, 1)
  checkEq(mon.moves[1].pp, 10, "Gen 1 slot 1 pp set to 10")

  MonOps.maxAllPpUps(data, mon, 1)
  checkEq(mon.moves[1].maxPp, 24, "Gen 1 slot 1 maxed to 24")
  checkEq(mon.moves[2].maxPp, 48, "Gen 1 slot 2 maxed to 48")
end

-- 12. MonEditor.draw with Moves and PP controls smoke test
do
  local S = {
    data = {
      moves = {
        [85] = { name = "THUNDERBOLT", pp = 15 },
        [98] = { name = "QUICK ATTACK", pp = 30 },
      }
    },
    save = { version = "firered", engine = "game3", generation = 3 },
    version = "firered",
    editingMon = freshMonG3(),
    inspectorScroll = 0,
  }
  S.editingMon.moves = { 85, 98, nil, nil }
  S.editingMon.pp = { 15, 30, nil, nil }
  S.editingMon.maxPp = { 15, 30, nil, nil }
  S.editingMon.ppBonusesPacked = 0

  local okWide, errWide = pcall(function()
    MonEditor.draw(S, Kit, 10, 10, 600, 700)
  end)
  check(okWide, "MonEditor.draw renders Gen 3 with moves and PP controls (wide): " .. tostring(errWide))

  local okNarrow, errNarrow = pcall(function()
    MonEditor.draw(S, Kit, 10, 10, 400, 700)
  end)
  check(okNarrow, "MonEditor.draw renders Gen 3 with moves and PP controls (narrow): " .. tostring(errNarrow))
end

print(string.format("== EV/IV/PP Tests: %d passed, %d failed ==", passed, failed))
if failed > 0 then os.exit(1) end


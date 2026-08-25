-- TruncateHL_BC (../pokegold/engine/battle/effect_commands.asm:2625,
-- ../pokecrystal/engine/battle/effect_commands.asm:2614).
--
--   luajit tests/gen2_reflect_overflow_test.lua
--
-- ROM-free.  The cart hands BattleCommand_DamageCalc one-byte stats, so a
-- 16-bit attack/defence pair is shifted right twice -- both together, so the
-- ratio survives -- and the low byte taken.  Gold runs that pass exactly once
-- and keeps whatever the low byte then holds, so Reflect or Light Screen on a
-- 512+ defence pushes the doubled value to 1024 and the truncated byte wraps
-- to 0; DamageCalc's minimum-defence check turns that into 1 and the hit caps.
-- Crystal repeats the pass until both stats fit, which is the fix CT-10 names
-- reflectOverflow.  Crystal kept the old arithmetic under LINK_COLOSSEUM; the
-- Gen 2 battle engine here has no link mode, so only the single-player halves
-- are pinned.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 reflect overflow")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local Damage = require("src.battle.gen2.Damage")

local restore = GameVersion.get()

-- One NORMAL physical hit with no type table, no STAB and the damage roll
-- pinned at 100%, so the only moving part is the truncated defence.
local function hit(version, defense, screen)
  GameVersion.set(version)
  return (Damage.calc({
    level = 50, power = 100, moveType = "NORMAL",
    attacker = { attack = 200 },
    defender = { defense = defense },
    screen = screen, variation = 100,
  }))
end

local function truncate(version, attack, defense)
  GameVersion.set(version)
  return Damage.truncateStats(attack, defense,
    GameVersion.fixes().reflectOverflow == true)
end

-- --------------------------------------------------------- the gate itself

do
  eq(GameVersion.fixes("gold").reflectOverflow, nil,
    "Gold keeps the cart's single truncation pass")
  eq(GameVersion.fixes("silver").reflectOverflow, nil,
    "Silver keeps it too")
  eq(GameVersion.fixes("crystal").reflectOverflow, true,
    "Crystal is the version that loops")
end

-- ------------------------------------------------- below the truncate line

do
  -- Both stats already fit in a byte, so TruncateHL_BC returns at once and
  -- every ordinary battle is untouched by either arm.
  local a, d = truncate("gold", 200, 100)
  eq(a, 200, "an 8-bit attack passes through")
  eq(d, 100, "an 8-bit defence passes through")
  eq(hit("gold", 100, false), 90, "Gold, defence 100, no screen")
  eq(hit("crystal", 100, false), 90, "Crystal agrees")
  eq(hit("gold", 100, true), 46, "Gold, defence 100 doubled to 200")
  eq(hit("crystal", 100, true), 46, "Crystal agrees")
end

-- ----------------------------------------- one pass, which both games share

do
  -- 511 doubled is 1022; one >>2 gives 255, which fits, so Crystal's loop
  -- never runs a second time and the two versions still agree.  This is the
  -- largest defence Reflect can double without the wrap.
  local ga, gd = truncate("gold", 200, 511 * 2)
  local ca, cd = truncate("crystal", 200, 511 * 2)
  eq(gd, 255, "1022 >> 2 is 255, the last value that fits")
  eq(ga, 50, "the attack is shifted with it, 200 >> 2")
  eq(cd, 255, "Crystal's loop exits on the same pass")
  eq(ca, 50, "and leaves the attack alone as well")
  eq(hit("gold", 511, true), 10, "Gold, defence 511 doubled")
  eq(hit("crystal", 511, true), 10, "Crystal, defence 511 doubled")
end

do
  -- A big defence with no screen cannot reach 1024 on its own (stats cap at
  -- 999), so the gate must not move any unscreened hit.
  for _, defense in ipairs({ 256, 400, 512, 700, 999 }) do
    eq(hit("gold", defense, false), hit("crystal", defense, false),
      ("defence %d without a screen is version-independent"):format(defense))
  end
  eq(hit("gold", 999, false), 10, "defence 999 unscreened, both versions")
end

-- ------------------------------------------------------------- the wrap

do
  -- 512 doubled is exactly 1024.  Gold: 1024 >> 2 = 256, low byte 0, and
  -- DamageCalc's `ld c, 1` turns that into a defence of 1.  Crystal: a second
  -- pass takes 256 -> 64 and the attack 50 -> 12.
  local ga, gd = truncate("gold", 200, 1024)
  eq(gd, 0, "Gold truncates 1024 to a defence byte of 0")
  eq(ga, 50, "Gold's attack byte after the single pass")
  local ca, cd = truncate("crystal", 200, 1024)
  eq(cd, 64, "Crystal shifts again, 256 >> 2")
  eq(ca, 12, "and the attack with it, 50 >> 2")

  -- 22 * 100 * 50 / 1 / 50 = 2200, capped to 997 + 2.
  eq(hit("gold", 512, true), 999, "Gold's Reflect caps the hit at 999")
  -- 22 * 100 * 12 / 64 / 50 = 8, + 2.
  eq(hit("crystal", 512, true), 10, "Crystal's Reflect keeps the hit at 10")
  check(hit("gold", 512, false) == 19,
    "and the same defence unscreened is 19 on both")
  check(hit("gold", 512, true) > hit("gold", 512, false),
    "Gold's Reflect makes the defender take MORE damage")
  check(hit("crystal", 512, true) < hit("crystal", 512, false),
    "Crystal's Reflect halves it, as it should")
end

do
  -- The worst case the cart can build: a 999 defence doubled to 1998.
  -- Gold: 1998 >> 2 = 499, low byte 243.  Crystal: 499 >> 2 = 124, attack 12.
  local ga, gd = truncate("gold", 200, 999 * 2)
  eq(gd, 243, "Gold wraps 499 to 243")
  eq(ga, 50, "Gold's attack byte")
  local ca, cd = truncate("crystal", 200, 999 * 2)
  eq(cd, 124, "Crystal shifts 499 to 124")
  eq(ca, 12, "and the attack to 12")
  eq(hit("gold", 999, true), 11, "Gold: Reflect on a 999 defence deals 11")
  eq(hit("crystal", 999, true), 6, "Crystal: the same hit deals 6")
  eq(hit("gold", 999, false), 10, "unscreened it is 10, so the screen HURTS")
end

-- ------------------------------------------------ the minimum-1 arms

do
  -- `ld a, c / or b / jr nz / inc c` and its hl twin: a stat that shifts down
  -- to zero is forced back to 1 before the next pass, on both versions.
  local ga, gd = truncate("gold", 3, 2000)
  eq(ga, 1, "Gold: an attack of 3 shifts to 0 and is forced to 1")
  eq(gd, 244, "Gold: 2000 >> 2 = 500, low byte 244")
  local ca, cd = truncate("crystal", 3, 2000)
  eq(ca, 1, "Crystal: the forced 1 shifts to 0 and is forced again")
  eq(cd, 125, "Crystal: 500 >> 2 = 125")
end

-- ------------------------------------------------------------- the override

do
  -- The gate is readable per call, which is where a LINK_COLOSSEUM carve-out
  -- would hang if the Gen 2 engine ever grows one.
  GameVersion.set("crystal")
  local bugged = Damage.calc({
    level = 50, power = 100, moveType = "NORMAL",
    attacker = { attack = 200 }, defender = { defense = 512 },
    screen = true, variation = 100, reflectOverflowFixed = false,
  })
  eq(bugged, 999, "Crystal forced onto the bugged arm matches Gold")
  GameVersion.set("gold")
  local fixed = Damage.calc({
    level = 50, power = 100, moveType = "NORMAL",
    attacker = { attack = 200 }, defender = { defense = 512 },
    screen = true, variation = 100, reflectOverflowFixed = true,
  })
  eq(fixed, 10, "Gold forced onto the fixed arm matches Crystal")
end

-- ------------------------------------------------------- the 999 stat cap

do
  -- ApplyStatLevelMultiplier caps at MAX_STAT_VALUE before anything doubles
  -- it (../pokecrystal/engine/battle/core.asm:6739), which is what bounds the
  -- doubled defence at 1998 rather than letting +6 stages run past it.
  eq(Damage.applyStage(999, 6), 999, "a +6 stage cannot pass 999")
  eq(Damage.applyStage(250, 6), 999, "250 x4 is 1000, capped to 999")
  eq(Damage.applyStage(249, 6), 996, "249 x4 stays below the cap")
  eq(Damage.applyStage(1, -6), 1, "and a stat never reaches 0")
end

GameVersion.set(restore)

S.finish()

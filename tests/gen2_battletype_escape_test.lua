-- TryToRunAwayFromBattle's battle-type ladder, which nothing covered:
-- ../pokecrystal/engine/battle/core.asm:3687-3694 refuses TRAP, CELEBI,
-- FORCESHINY and SUICUNE, pokegold/engine/battle/core.asm:3476-3479 only the
-- first and third, and the values themselves come from
-- ../pokecrystal/constants/battle_constants.asm:91-103.
--   luajit tests/gen2_battletype_escape_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battletype escape")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")

-- ../pokecrystal/constants/battle_constants.asm:91-103, `const_def` from 0.
local NORMAL, CANLOSE, DEBUG, TUTORIAL = 0, 1, 2, 3
local FISH, ROAMING, CONTEST, FORCESHINY = 4, 5, 6, 7
local TREE, TRAP, FORCEITEM, CELEBI, SUICUNE = 8, 9, 10, 11, 12

eq(Battle.BATTLETYPE_CANLOSE, CANLOSE, "BATTLETYPE_CANLOSE is 1")
eq(Battle.BATTLETYPE_FORCESHINY, FORCESHINY, "BATTLETYPE_FORCESHINY is 7")
eq(Battle.BATTLETYPE_TRAP, TRAP, "BATTLETYPE_TRAP is 9")
eq(Battle.BATTLETYPE_CELEBI, CELEBI, "BATTLETYPE_CELEBI is 11, after FORCEITEM")
eq(Battle.BATTLETYPE_SUICUNE, SUICUNE, "BATTLETYPE_SUICUNE is 12")

local function refuses(value)
  return Battle.noEscapeBattleType({ battleType = value }) == true
end

for _, row in ipairs({
  { NORMAL, false, "NORMAL" },
  { CANLOSE, false, "CANLOSE" },
  { DEBUG, false, "DEBUG" },
  { TUTORIAL, false, "TUTORIAL" },
  { FISH, false, "FISH" },
  { ROAMING, false, "ROAMING" },
  { CONTEST, false, "CONTEST" },
  { FORCESHINY, true, "FORCESHINY" },
  { TREE, false, "TREE" },
  { TRAP, true, "TRAP" },
  -- ../pokecrystal/maps/TinTower1F.asm:120 and pokegold's Lugia and Ho-Oh both
  -- arm FORCEITEM, which the ladder does not name: it is escapable.
  { FORCEITEM, false, "FORCEITEM" },
  { CELEBI, true, "CELEBI" },
  { SUICUNE, true, "SUICUNE" },
}) do
  local value, want, name = row[1], row[2], row[3]
  eq(refuses(value), want,
    ("%s (%d) %s escape"):format(name, value, want and "refuses" or "allows"))
end

check(refuses(nil) == false, "an unarmed battle escapes")

S.finish()

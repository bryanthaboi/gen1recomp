-- A knocked-off item must stay marked for the rest of the battle.
--
-- Regression: KNOCK_OFF only set the per-battler volatile `expKnockedOff`, which
-- dies when that battler leaves the field.  pret keeps
-- gWishFutureKnock.knockedOffMons -- one bit per party index per side -- so the
-- guard survives switch-out: a mon whose item was knocked off cannot have an
-- item stolen or swapped for the rest of the battle, even after it comes back
-- holding something else.
--
-- These drive the real effect functions; the battle-scoped state is the adapter's
-- `_st`, exactly as the engine carries it.
--   luajit tests/engine/game3_knocked_off_flag_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("game3_knocked_off_flag_test")

local Secondary = require("src.core.game3.battle.effects.secondary")
local Special = require("src.core.game3.battle.effects.special")

local failures = 0

local function adapter(st)
  return {
    _st = st,
    abilityOf = function(_, b) return b.ability end,
    hp = function(_, b) return b.hp or 100 end,
    ownSide = function() return nil end,
    foeSide = function() return nil end,
    displayName = function(_, b) return b.name or "MON" end,
    playAnim = function() end,
    say = function() end,
    sayText = function() end,
    sayFail = function() failures = failures + 1 end,
    roll = function(_, lo) return lo end,
    pushEvent = function() end,
  }
end

local function battler(side, partyIndex, item, ability)
  return {
    side = side, partyIndex = partyIndex, id = 0,
    name = side == "player" and "CHARMANDER" or "RATTATA",
    hp = 100, item = item, ability = ability,
    mon = item and { item = item, heldItem = item } or {},
  }
end

local function knock_off(st, user, target)
  return Secondary.set({ adapter = adapter(st), user = user, target = target,
                         move = { moveName = "KNOCK OFF" } },
                       "KNOCK_OFF", false, true, false)
end

local function steal(st, user, target)
  return Secondary.set({ adapter = adapter(st), user = user, target = target,
                         move = { moveName = "THIEF" } },
                       "STEAL_ITEM", false, true, false)
end

local function trick(st, user, target)
  failures = 0
  Special.trick({ adapter = adapter(st), user = user, target = target })
  return failures
end

-- 1. After a knock-off, Trick still refuses the victim once it has switched out
--    and come back holding something else.
local st = {}
knock_off(st, battler("player", 1, 0), battler("enemy", 1, 13))
local returning = battler("enemy", 1, 14)
eq(trick(st, battler("player", 1, 13), returning), 1,
   "TRICK refuses a mon knocked off earlier this battle, after switch-out")

-- 2. A different party index on the same side is unaffected.
eq(trick(st, battler("player", 1, 13), battler("enemy", 2, 14)), 0,
   "TRICK still works against a mon that was not knocked off")

-- 3. Thief also refuses when the *thief* had its own item knocked off earlier,
--    which only the battle-scoped mask can remember.  (The thief's hands are
--    empty, as they must be to steal at all.)
local st2 = {}
knock_off(st2, battler("enemy", 1, 0), battler("player", 1, 13))
check(not steal(st2, battler("player", 1, 0), battler("enemy", 1, 13)),
  "THIEF refuses after the user's own item was knocked off earlier this battle")

-- 4. Control: the same Thief works when nothing was knocked off.
local st3 = {}
check(steal(st3, battler("player", 1, 0), battler("enemy", 1, 13)),
  "THIEF still steals when no knock-off happened")

-- 5. The mask is per side: an enemy knock-off does not block the player.
local st4 = {}
knock_off(st4, battler("player", 1, 0), battler("enemy", 1, 13))
eq(trick(st4, battler("player", 1, 14), battler("enemy", 2, 13)), 0,
   "an enemy knock-off does not block the player's own party index")

T.finish("game3_knocked_off_flag_test")

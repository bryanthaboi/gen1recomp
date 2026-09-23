-- Thief and Trick must write both sides' item changes through to the party mon.
--
-- Regression: the STEAL_ITEM branch of Secondary.set and Special.trick both
-- persisted the *target* only when `target.side == "player"`.  The common case
-- (the player steals/swaps with an enemy) left the enemy's party mon holding
-- the item it no longer had, so on the next send-out the enemy held it again
-- while the player also held it -- item duplication.
--
-- persist_item resolves the party mon via State.partyMon(b) (= b._partyMon or
-- b.mon), so these drive the real effect functions with plain battler tables.
--   luajit tests/engine/game3_item_steal_trick_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("game3_item_steal_trick_test")

local Secondary = require("src.core.game3.battle.effects.secondary")
local Special = require("src.core.game3.battle.effects.special")

local failures = 0

local function adapter()
  return {
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

local function battler(side, item, ability)
  return {
    side = side,
    name = side == "player" and "CHARMANDER" or "RATTATA",
    hp = 100, item = item, ability = ability,
    mon = item and { item = item, heldItem = item } or {},
  }
end

local function thief(user, target)
  return Secondary.set({
    adapter = adapter(), user = user, target = target,
    move = { moveName = "THIEF" },
  }, "STEAL_ITEM", false, true, false)
end

local function trick(user, target)
  failures = 0
  return Special.trick({ adapter = adapter(), user = user, target = target })
end

-- 1. Thief: the player steals from an enemy.  Both party mons must agree with
--    their battlers, or the enemy's item returns on switch-out.
local user, target = battler("player", 0), battler("enemy", 13)
check(thief(user, target), "THIEF reports the steal")
eq(user.item, 13, "the thief's battler holds the stolen item")
eq(user.mon.item, 13, "the thief's party mon holds the stolen item")
eq(target.item, 0, "the victim's battler loses the item")
eq(target.mon.item, nil, "the victim's party mon loses the item (does not return on switch-out)")
eq(target.mon.heldItem, nil, "the victim's party heldItem is cleared")

-- 2. Thief still refuses STICKY_HOLD, leaving both sides intact.
local u2, t2 = battler("player", 0), battler("enemy", 13, "STICKY_HOLD")
check(not thief(u2, t2), "STICKY_HOLD refuses THIEF")
eq(t2.mon.item, 13, "STICKY_HOLD keeps the victim's party item")

-- 3. Thief still refuses when the user already holds an item.
local u3, t3 = battler("player", 14), battler("enemy", 13)
check(not thief(u3, t3), "a full-handed thief refuses")
eq(t3.mon.item, 13, "a refused steal leaves the victim's party item")

-- 4. Trick: the player swaps with an enemy.  Both mons must take the item the
--    battler now holds.
local u4, t4 = battler("player", 13), battler("enemy", 14)
trick(u4, t4)
eq(u4.item, 14, "the user's battler takes the target's item")
eq(u4.mon.item, 14, "the user's party mon takes the target's item")
eq(t4.item, 13, "the target's battler takes the user's item")
eq(t4.mon.item, 13, "the target's party mon takes the user's item (no duplication)")
eq(t4.mon.heldItem, 13, "the target's party heldItem follows the swap")

-- 5. Trick still fails when neither side holds anything.
local u5, t5 = battler("player", 0), battler("enemy", 0)
trick(u5, t5)
eq(failures, 1, "TRICK with no items on either side fails")

-- 6. One-sided Trick: the user gives its item away, so its mon must be cleared.
local u6, t6 = battler("player", 13), battler("enemy", 0)
trick(u6, t6)
eq(u6.item, 0, "the user's battler gives the item away")
eq(u6.mon.item, nil, "the user's party mon is cleared when it gives its item away")
eq(t6.item, 13, "the target's battler receives the item")
eq(t6.mon.item, 13, "the target's party mon receives the item")

T.finish("game3_item_steal_trick_test")

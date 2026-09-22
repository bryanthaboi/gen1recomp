-- pokefirered/src/battle_script_commands.c:2750,4489
-- Knock Off suppresses the battle copy across switches, preserving the party item.
--   luajit tests/engine/game3_knock_off_item_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Secondary = require("src.core.game3.battle.effects.secondary")

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local SwitchSeq = require("src.core.game3.battle.switch_seq")

local function adapter(st)
  return {
    _st = st,
    pushEvent = function() end,
    abilityOf = function(_, b) return b.ability end,
    hp = function(_, b) return b.hp or 100 end,
    ownSide = function() return nil end,
    displayName = function(_, b) return b.name or "MON" end,
    playAnim = function() end,
    say = function() end,
    roll = function(_, lo) return lo end,
  }
end

-- A battler and its party mon carrying the same item, like State.makeBattler
-- builds from held_item(mon).
local function battler(side, item, ability)
  return {
    side = side,
    name = side == "player" and "CHARMANDER" or "RATTATA",
    hp = 100, item = item, ability = ability,
    mon = item and { item = item, heldItem = item } or {},
  }
end

local function knock_off(user, target, st)
  return Secondary.set({
    adapter = adapter(st), user = user, target = target,
    move = { moveName = "KNOCK OFF" },
  }, "KNOCK_OFF", false, true, false)
end

-- 1. The party keeps the item for future battles.
local user, target = battler("enemy", 0), battler("player", 13)
check(knock_off(user, target), "KNOCK_OFF reports the item was removed")
eq(target.item, 0, "the battler's item is cleared")
eq(target.mon.item, 13, "the party retains its item")
eq(target.mon.heldItem, 13, "the heldItem alias is retained too")

-- 2. The enemy party retains its item too.
local user2, target2 = battler("player", 0), battler("enemy", 13)
knock_off(user2, target2)
eq(target2.item, 0, "the enemy battler's item is cleared")
eq(target2.mon.item, 13, "the enemy party mon retains its item")

-- 3. STICKY_HOLD refuses and must leave the item intact everywhere.
local user3, target3 = battler("enemy", 0), battler("player", 13, "STICKY_HOLD")
check(not knock_off(user3, target3), "STICKY_HOLD refuses KNOCK_OFF")
eq(target3.item, 13, "STICKY_HOLD keeps the battler item")
eq(target3.mon.item, 13, "STICKY_HOLD keeps the party item")

-- 4. A target with no item is a no-op.
local user4, target4 = battler("enemy", 0), battler("player", 0)
check(not knock_off(user4, target4), "a target with no item is a no-op")

local function mon(item)
  return { species = 4, level = 10, hp = 30, maxHp = 30,
    item = item, heldItem = item, ability = "NONE", moves = { 10 }, pp = { 35 } }
end
for _, side in ipairs({ "player", "enemy" }) do
  local party, foes = { mon(13), mon(14) }, { mon(13), mon(14) }
  local st = State.new({ playerParty = party, foeParty = foes })
  local victim = st[side]
  local foe = side == "player" and st.enemy or st.player
  local members = side == "player" and party or foes
  knock_off(foe, victim, st)
  check(State.isKnockedOff(st, victim), "the victim's party slot is marked")
  check(not State.isKnockedOff(st, foe), "the opposite side's same slot is unaffected")
  Engine.performSwitch(st, adapter(st), side, 2)
  eq(st[side].item, 14, "another party slot keeps its active item")
  Engine.performSwitch(st, adapter(st), side, 1)
  eq(st[side].item, 0, "engine switch-in suppresses the knocked-off item")
  eq(members[1].heldItem, 13, "switching preserves the party item")
  SwitchSeq.beginSendOut(st, side, 1, { headless = true })
  eq(st[side].item, 0, "presentation send-out also suppresses the item")
  if side == "player" then
    SwitchSeq.beginPlayerSwitch(st, 1, { headless = true })
    eq(st.player.item, 0, "player switch sequence suppresses the item")
  end
  SwitchSeq.beginShiftSwitch(st, 1, 1, { headless = true })
  eq(st[side].item, 0, "shift switch sequence suppresses the item")
  local fresh = State.new({ playerParty = party, foeParty = foes })
  eq(fresh[side].item, 13, "the original held item works in the next battle")
  check(not State.isKnockedOff(fresh, fresh[side]), "the new battle has no knock-off mark")
end

T.finish("game3_knock_off_item_test")

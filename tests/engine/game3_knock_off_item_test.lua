--
-- pokefirered/src/battle_script_commands.c:2730-2752, battle_script_commands.c:4489
--
--   luajit tests/engine/game3_knock_off_item_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("tests.game3_cache").stubSpeciesNames()

local BattleText = require("src.core.game3.battle.battle_text")
BattleText.get = function(id) return tostring(id) end

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
    sayText = function() end,
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

local user, target = battler("enemy", 0), battler("player", 13)
check(knock_off(user, target), "KNOCK_OFF reports the item was removed")
eq(target.item, 0, "the battler's item is cleared")
eq(target.mon.item, 13, "the party mon keeps the item for after the battle")
eq(target.mon.heldItem, 13, "heldItem is kept as well")

local user2, target2 = battler("player", 0), battler("enemy", 13)
knock_off(user2, target2)
eq(target2.item, 0, "the enemy battler's item is cleared")
eq(target2.mon.item, 13, "the enemy party mon keeps the item")

-- 3. STICKY_HOLD refuses and must leave the item intact everywhere.
local user3, target3 = battler("enemy", 0), battler("player", 13, "STICKY_HOLD")
check(not knock_off(user3, target3), "STICKY_HOLD refuses KNOCK_OFF")
eq(target3.item, 13, "STICKY_HOLD keeps the battler item")
eq(target3.mon.item, 13, "STICKY_HOLD keeps the party item")

-- 4. A target with no item is a no-op.
local user4, target4 = battler("enemy", 0), battler("player", 0)
check(not knock_off(user4, target4), "a target with no item is a no-op")

local st = {}
State.markKnockedOff(st, { side = "enemy", partyIndex = 1 })
local mon = { species = 1, level = 5, hp = 20, maxHp = 20, moves = {}, pp = {}, item = 13, heldItem = 13 }
local rebuilt = State.makeBattler(mon, "enemy", { partyIndex = 1, st = st })
eq(rebuilt.item, 0, "send-out masks the item while the knock-off mark is set")
eq(rebuilt.expKnockedOff, true, "the rebuilt battler keeps the volatile mark")
eq(mon.item, 13, "the party mon still holds the item after the send-out")
local control = State.makeBattler(mon, "enemy", { partyIndex = 1, st = {} })
eq(control.item, 13, "without the mark the send-out reads the item back")

local function fresh_mon(item)
  return { species = 4, level = 10, hp = 30, maxHp = 30,
    item = item, heldItem = item, ability = "NONE", moves = { 10 }, pp = { 35 } }
end
for _, side in ipairs({ "player", "enemy" }) do
  local party, foes = { fresh_mon(13), fresh_mon(14) }, { fresh_mon(13), fresh_mon(14) }
  local bst = State.new({ playerParty = party, foeParty = foes })
  local victim = bst[side]
  local foe = side == "player" and bst.enemy or bst.player
  local members = side == "player" and party or foes
  knock_off(foe, victim, bst)
  check(State.isKnockedOff(bst, victim), "the victim's party slot is marked")
  check(not State.isKnockedOff(bst, foe), "the opposite side's same slot is unaffected")
  Engine.performSwitch(bst, adapter(bst), side, 2)
  eq(bst[side].item, 14, "another party slot keeps its active item")
  Engine.performSwitch(bst, adapter(bst), side, 1)
  eq(bst[side].item, 0, "engine switch-in suppresses the knocked-off item")
  eq(members[1].heldItem, 13, "switching preserves the party item")
  SwitchSeq.beginSendOut(bst, side, 1, { headless = true })
  eq(bst[side].item, 0, "presentation send-out also suppresses the item")
  if side == "player" then
    SwitchSeq.beginPlayerSwitch(bst, 1, { headless = true })
    eq(bst.player.item, 0, "player switch sequence suppresses the item")
  end
  SwitchSeq.beginShiftSwitch(bst, 1, 1, { headless = true })
  eq(bst[side].item, 0, "shift switch sequence suppresses the item")
  local fresh = State.new({ playerParty = party, foeParty = foes })
  eq(fresh[side].item, 13, "the original held item works in the next battle")
  check(not State.isKnockedOff(fresh, fresh[side]), "the new battle has no knock-off mark")
end

T.finish("game3_knock_off_item_test")

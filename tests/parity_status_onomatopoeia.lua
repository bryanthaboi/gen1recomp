-- Parity: sleep/confusion onomatopoeia on status-check text
-- (core.asm CheckPlayerStatusConditions / CheckEnemyStatusConditions).
-- Self-contained: `luajit tests/parity_status_onomatopoeia.lua`; also
-- dofile'd by tests/run_tests.lua's parity_* aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity status onomatopoeia")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()
local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")

local function freshBattle()
  Game.save.party = { Pokemon.new(Data, "NIDOKING", 40) }
  return BattleState.newWild(Game, "DEWGONG", 30)
end

-- Capture queue order of anim/text rows inserted via *Next helpers.
local function capture(battle)
  local seq = {}
  battle.nextInsert = 0
  battle.queue = {}
  battle.animNext = function(_, name, isPlayer)
    seq[#seq + 1] = { kind = "anim", name = name, isPlayer = isPlayer }
  end
  battle.sayNext = function(_, text)
    seq[#seq + 1] = { kind = "text", text = text }
  end
  return seq
end

-- --- sleep: player anim-before-text, enemy text-before-anim -------------
do
  local b = freshBattle()
  b.rng = function() return 255 end
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 3
  check(b:statusInterrupt(b.player, b.enemy) == true, "sleep interrupts the turn")
  eq(#seq, 2, "sleep queues anim + text")
  eq(seq[1].kind, "anim", "player sleep: SLP_PLAYER_ANIM before text")
  eq(seq[1].name, "SLP_PLAYER_ANIM", "player sleep uses SLP_PLAYER_ANIM")
  eq(seq[1].isPlayer, true, "player sleep anim faces the player")
  check(seq[2].text:find("is fast asleep!", 1, true),
        "player sleep text follows the anim")
end

do
  local b = freshBattle()
  b.rng = function() return 255 end
  local seq = capture(b)
  b.enemy.mon.status = "SLP"
  b.enemy.sleepTurns = 3
  check(b:statusInterrupt(b.enemy, b.player) == true, "enemy sleep interrupts")
  eq(seq[1].kind, "text", "enemy sleep: FastAsleepText before anim")
  check(seq[1].text:find("Enemy ", 1, true),
        "enemy sleep text carries the Enemy prefix")
  eq(seq[2].name, "SLP_ANIM", "enemy sleep uses SLP_ANIM (enemy Z coords)")
  eq(seq[2].isPlayer, false, "enemy sleep anim faces the enemy")
end

do
  local b = freshBattle()
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 3
  check(b:preRechargeChecks(b.player, b.enemy) == true,
        "pre-recharge sleep still loses the turn")
  eq(seq[1].name, "SLP_PLAYER_ANIM",
     "pre-recharge sleep plays the same onomatopoeia")
end

-- --- confusion: text then CONF_*_ANIM (both sides) ---------------------
-- Status.beforeMove: rng(0,255) < 128 -> hurt itself; else can still move.
do
  local b = freshBattle()
  b.rng = function() return 200 end -- no self-hit
  local seq = capture(b)
  b.player.confusedTurns = 3
  b.player.mon.status = nil
  local stopped = b:statusInterrupt(b.player, b.enemy)
  check(stopped == false, "confusion can still allow a move")
  eq(seq[1].kind, "text", "player confusion: IsConfusedText before anim")
  check(seq[1].text:find("is confused!", 1, true), "player confusion text")
  eq(seq[2].name, "CONF_PLAYER_ANIM", "player confusion uses CONF_PLAYER_ANIM")
  eq(seq[2].isPlayer, true, "player confusion anim faces the player")
end

do
  local b = freshBattle()
  b.rng = function() return 0 end -- self-hit
  local seq = capture(b)
  b.computeDamage = function() return 1 end
  b.applyDamage = function() end
  b.onFaint = function() end
  b.enemy.confusedTurns = 3
  b.enemy.mon.status = nil
  local stopped = b:statusInterrupt(b.enemy, b.player)
  check(stopped == true, "confusion self-hit interrupts")
  eq(seq[1].kind, "text", "enemy confusion text first")
  check(seq[1].text:find("is confused!", 1, true), "enemy confusion text")
  eq(seq[2].name, "CONF_ANIM", "enemy confusion uses CONF_ANIM")
  eq(seq[2].isPlayer, false, "enemy confusion anim faces the enemy")
  check(seq[3] and seq[3].text:find("hurt itself", 1, true),
        "hurt-itself text follows the confusion anim")
end

-- wake stays text-only (no onomatopoeia)
do
  local b = freshBattle()
  b.rng = function() return 0 end
  local seq = capture(b)
  b.player.mon.status = "SLP"
  b.player.sleepTurns = 1
  b:statusInterrupt(b.player, b.enemy)
  eq(#seq, 1, "waking up is text-only")
  check(seq[1].text:find("woke up!", 1, true), "wake text")
end

-- Onomatopoeia must key off Status.beforeMove's own onomatopoeiaKind
-- return, never off matching English substrings in the message text:
-- BattleState:sayStatusMsg used to text-search for "is fast asleep!"/
-- "is confused!", which a translation mod's real (non-English) text for
-- these same labels would never contain. Simulate a mod overriding both
-- labels with non-English text carrying neither substring and confirm the
-- anim still plays.
do
  local b = freshBattle()
  local originalAsleep = Data.text._FastAsleepText
  local originalConfused = Data.text._IsConfusedText
  -- Restored through pcall: these are shared Data.text globals, and
  -- tests/run_tests.lua keeps the process alive after a suite raises
  -- (runSuites pcalls each file), so a check that blew up here would leave
  -- "pioupiou zzz" installed for every later parity suite.
  local ok, err = pcall(function()
    Data.text._FastAsleepText = "{USER}\npioupiou zzz"
    Data.text._IsConfusedText = "{USER}\ntourneboule"
    b.rng = function() return 255 end -- sleep: stay asleep; confusion: no self-hit
    local seq = capture(b)
    b.player.mon.status = "SLP"
    b.player.sleepTurns = 3
    b:statusInterrupt(b.player, b.enemy)
    check(seq[1] and seq[1].kind == "anim",
          "translated sleep text still plays SLP_PLAYER_ANIM")
    check(seq[1] and seq[1].name == "SLP_PLAYER_ANIM",
          "translated sleep picks the right anim")
    check(seq[2] and not seq[2].text:find("is fast asleep!", 1, true),
          "translated sleep text carries no English substring")

    seq = capture(b)
    b.player.mon.status = nil
    b.player.confusedTurns = 3
    b:statusInterrupt(b.player, b.enemy)
    check(seq[2] and seq[2].name == "CONF_PLAYER_ANIM",
          "translated confusion text still plays CONF_PLAYER_ANIM")
    check(seq[1] and not seq[1].text:find("is confused!", 1, true),
          "translated confusion text carries no English substring")
  end)
  Data.text._FastAsleepText = originalAsleep
  Data.text._IsConfusedText = originalConfused
  check(ok, "the translated-label block ran to the end: " .. tostring(err))
end

-- Confusion that does not self-hit falls through into the disabled-move
-- check and the paralysis roll below it in Status.beforeMove, either of
-- which can append one more, unrelated message after the confusion line
-- in the same call. onomatopoeiaKind/onomatopoeiaIndex must stay pinned to
-- the confusion message specifically -- not "whichever message ends up
-- last" -- or BattleState:sayStatusMsg's kind-only display (which
-- regenerates its own confusion text rather than showing msgs[i]) ends up
-- substituted for that later message, silently dropping it from the
-- screen and playing the confusion SFX a second time instead.
do
  local b = freshBattle()
  b.rng = function() return 255 end -- confusion: no self-hit
  local seq = capture(b)
  b.player.mon.status = nil
  b.player.confusedTurns = 3
  b.player.disabledSlot = 1 -- TACKLE, see freshBattle's NIDOKING moveset
  local stopped = b:statusInterrupt(b.player, b.enemy, "TACKLE")
  check(stopped == true, "a disabled selected move still interrupts")
  eq(seq[1].kind, "text", "confusion text first")
  check(seq[1].text:find("is confused!", 1, true), "confusion text shown")
  eq(seq[2].name, "CONF_PLAYER_ANIM", "confusion still plays its own anim")
  check(seq[3] and seq[3].kind == "text" and seq[3].text:find("disabled!", 1, true),
        "the disabled-move text still reaches the screen, not swallowed")
end

do
  local b = freshBattle()
  local calls = 0
  b.rng = function()
    calls = calls + 1
    return calls == 1 and 255 or 0 -- confusion: no self-hit; PAR: fully paralyzed
  end
  local seq = capture(b)
  b.player.mon.status = "PAR"
  b.player.confusedTurns = 3
  local stopped = b:statusInterrupt(b.player, b.enemy)
  check(stopped == true, "paralysis on a confused mon still interrupts")
  eq(seq[1].kind, "text", "confusion text first")
  check(seq[1].text:find("is confused!", 1, true), "confusion text shown")
  eq(seq[2].name, "CONF_PLAYER_ANIM", "confusion still plays its own anim")
  check(seq[3] and seq[3].kind == "text" and seq[3].text:find("paralyzed!", 1, true),
        "the fully-paralyzed text still reaches the screen, not swallowed")
end

-- The one rules change in this commit: PAR's own roll clears bide, thrash,
-- charge and trapping (core.asm:3459-3464), while a block that came from
-- anywhere else leaves them in place.  statusBlockedId is what tells the two
-- apart now that the "fully paralyzed" substring no longer can.
do
  local b = freshBattle()
  b.rng = function() return 0 end -- PAR: fully paralyzed
  capture(b)
  b.player.mon.status = "PAR"
  b.player.thrashTurns = 2
  b.player.bideTurns = 2
  check(b:statusInterrupt(b.player, b.enemy) == true, "full paralysis interrupts")
  check(b.player.thrashTurns == nil and b.player.bideTurns == nil,
        "and clears the volatiles it clears on the cart")
end

-- A flinch on a paralyzed battler blocks the move too, but it is not the
-- paralysis roll, so the volatiles stay: mon.status == "PAR" alone would get
-- this wrong.
do
  local b = freshBattle()
  b.rng = function() return 255 end -- PAR: not fully paralyzed
  capture(b)
  b.player.mon.status = "PAR"
  b.player.flinched = true
  b.player.thrashTurns = 2
  check(b:statusInterrupt(b.player, b.enemy) == true, "a flinch interrupts as well")
  check(b.player.thrashTurns == 2,
        "but leaves the volatiles alone, unlike the paralysis roll")
end

S.finish()

-- Game stats must survive a save/load round trip.
--
-- Regression: `session.gameStats` is written by five subsystems -- slot-machine
-- jackpots (slot_machine.lua), hatched eggs (step_events.lua), link W/L/D
-- (link/battle.lua), link trades (link/trade.lua) and the sticker-man brags that
-- read them (natives_events.lua) -- but Schema.toSaveTable never emitted it and
-- fromSaveTable never restored it, so every counter reset on Continue.
--
-- The change is additive: a save without the key loads as an empty table, so the
-- rollback is dropping the key (the counters are then lost, as they are today).
--   luajit tests/engine/game3_gamestats_persistence_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Schema = require("src.core.game3.save_schema_firered")

local session = Schema.newGame({ name = "RED" })
session.gameStats = { [13] = 4, [7] = 100, linkBattleWins = 3, linkBattleLosses = 2 }

local save = Schema.toSaveTable(session)
check(type(save.gameStats) == "table", "toSaveTable writes gameStats")
local written = type(save.gameStats) == "table" and save.gameStats or {}
eq(written[13], 4, "the hatched-egg counter is written")
eq(written[7], 100, "a numeric game-stat id is written")
eq(written.linkBattleWins, 3, "the link battle win count is written")

local restored = Schema.fromSaveTable(save)
check(type(restored.gameStats) == "table", "fromSaveTable restores gameStats")
local back = type(restored.gameStats) == "table" and restored.gameStats or {}
eq(back[13], 4, "the hatched-egg counter round-trips")
eq(back[7], 100, "a numeric game-stat id round-trips")
eq(back.linkBattleWins, 3, "named keys round-trip")
eq(back.linkBattleLosses, 2, "...for every recorded outcome")

-- An older save has no gameStats key: it must load with an empty table, and the
-- writers' own `if type(session.gameStats) ~= "table"` guards stay satisfied.
save.gameStats = nil
local old = Schema.fromSaveTable(save)
check(type(old.gameStats) == "table", "a save without gameStats loads with an empty table")

T.finish("game3_gamestats_persistence_test")

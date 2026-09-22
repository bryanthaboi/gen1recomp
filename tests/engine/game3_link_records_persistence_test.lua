-- Link battle records and trainer-card counters must survive a save.
--
-- H2 regression: link/battle.lua writes `session.linkBattleRecords` (the Record
-- Corner / fan-club table) and `session.trainerCard` (link win/loss counters),
-- and link/init.lua, trainer_fan_club.lua and trainer_tower_records.lua read
-- them -- but neither key was in the save schema, so both were wiped on Continue.
--
-- Additive: a save without the keys loads as empty tables.
--   luajit tests/engine/game3_link_records_persistence_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Schema = require("src.core.game3.save_schema_firered")

local session = Schema.newGame({ name = "RED" })
session.linkBattleRecords = {
  { name = "AAA", wins = 3, losses = 1, draws = 0 },
  { name = "BBB", wins = 1, losses = 2, draws = 1 },
}
session.trainerCard = { linkBattleWins = 5, linkBattleLosses = 2 }

local save = Schema.toSaveTable(session)
check(type(save.linkBattleRecords) == "table", "toSaveTable writes linkBattleRecords")
local wroteRecs = type(save.linkBattleRecords) == "table" and save.linkBattleRecords or {}
eq(#wroteRecs, 2, "both records are written")
eq(wroteRecs[1] and wroteRecs[1].name, "AAA", "record order is preserved")
check(type(save.trainerCard) == "table", "toSaveTable writes trainerCard")
local wroteCard = type(save.trainerCard) == "table" and save.trainerCard or {}
eq(wroteCard.linkBattleWins, 5, "trainer-card link wins are written")

local back = Schema.fromSaveTable(save)
local backRecs = type(back.linkBattleRecords) == "table" and back.linkBattleRecords or {}
local backCard = type(back.trainerCard) == "table" and back.trainerCard or {}
eq(#backRecs, 2, "records round-trip")
eq(backRecs[2] and backRecs[2].name, "BBB", "...with their order preserved")
eq(backRecs[1] and backRecs[1].wins, 3, "...and their counters")
eq(backCard.linkBattleWins, 5, "trainer-card link wins round-trip")
eq(backCard.linkBattleLosses, 2, "...and link losses")

save.linkBattleRecords, save.trainerCard = nil, nil
local old = Schema.fromSaveTable(save)
check(type(old.linkBattleRecords) == "table" and type(old.trainerCard) == "table",
  "a save without the keys loads with empty tables")

T.finish("game3_link_records_persistence_test")

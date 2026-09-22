-- The Hall of Fame induction must actually commit the save.
--
-- N-A22 regression: commit_clear_and_save() ended with
--   local okSave, SaveData = pcall(require, "src.core.game3.save")
--   if okSave and SaveData and SaveData.save then pcall(SaveData.save, session) end
-- and that module does not exist, so `okSave` was always false: the clear flag,
-- the debut timestamp and the HOF team were set in memory and never written.
--
-- N-A23 (the same fields are absent from the save schema) is pinned at the end.
--   luajit tests/engine/game3_hall_of_fame_save_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- The commit takes the engine save path through the runtime singleton, looked up
-- in package.loaded exactly as map_name_popup does -- so load it as the game does.
local RuntimeStub = { _game = nil }
package.preload["src.core.game3.runtime"] = function() return RuntimeStub end
local Runtime = require("src.core.game3.runtime")
check(Runtime == RuntimeStub, "the runtime stub is wired into package.loaded")

local HallOfFame = require("src.ui.game3.hall_of_fame")
local Schema = require("src.core.game3.save_schema_firered")

local FLAG_SYS_GAME_CLEAR = 0x82C

local function session()
  return {
    flags = {}, party = {}, trainerId = 42379,
    playTimeHours = 12, playTimeMinutes = 34, playTimeSeconds = 56,
    hofDebutHours = 12, hofDebutMinutes = 34, hofDebutSeconds = 56,
  }
end

local mon = { species = 25, level = 50, nickname = "SPARKY", otId = 42379 }

-- 1. The commit reaches the engine's save path.
local saved = 0
RuntimeStub._game = { saveGame = function() saved = saved + 1; return true end }
local s = session()
check(pcall(HallOfFame._commitClearAndSave, s, { mon }),
  "the induction commit is callable")
eq(saved, 1, "the induction commits the save (the old code called a module that does not exist)")

-- 2. The in-memory state it is responsible for is still set.
eq(s.flags[FLAG_SYS_GAME_CLEAR], true, "the game-clear flag is set")
eq(s.game_cleared, true, "the session is marked cleared")
eq(s.hasHallOfFameRecords, true, "HOF records are marked present")
eq(s.hofDebutTime, "12:34:56", "the debut timestamp is recorded")
check(type(s.hallOfFameTeams) == "table" and #s.hallOfFameTeams == 1,
  "the induction team is recorded")
local team = (type(s.hallOfFameTeams) == "table" and s.hallOfFameTeams[1]) or {}
eq(team[1] and team[1].species, 25, "...with the member species")
eq(team[1] and team[1].nickname, "SPARKY", "...and nickname")

-- 3. A throwing save is logged, not raised, and the in-memory commit stands.
local s3 = session()
RuntimeStub._game = { saveGame = function() error("simulated disk failure") end }
check(pcall(HallOfFame._commitClearAndSave, s3, { mon }),
  "a throwing save does not propagate")
eq(s3.game_cleared, true, "the in-memory commit still happened")

-- 4. With no game at all it must not raise.
local s4 = session()
RuntimeStub._game = nil
check(pcall(HallOfFame._commitClearAndSave, s4, { mon }),
  "the commit is safe when no game is available")

-- 5. N-A23: the fields the commit writes must be in the save schema.
local written = Schema.toSaveTable(s)
eq(written.hofDebutTime, "12:34:56", "the schema writes hofDebutTime")
eq(written.game_cleared, true, "the schema writes game_cleared")
eq(written.hasHallOfFameRecords, true, "the schema writes hasHallOfFameRecords")
check(type(written.hallOfFameTeams) == "table" and #written.hallOfFameTeams == 1,
  "the schema writes hallOfFameTeams")
local restored = Schema.fromSaveTable(written)
eq(restored.hofDebutTime, "12:34:56", "...and restores it")
eq(restored.game_cleared, true, "...and the cleared flag")
check(type(restored.hallOfFameTeams) == "table" and #restored.hallOfFameTeams == 1,
  "...and the teams")

T.finish("game3_hall_of_fame_save_test")

#!/usr/bin/env luajit
-- Test 5th move rendering and cursor behavior in select_move mode (learning a new move when knowing 4 moves)
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_map_sections").install()

local T = require("tests.harness")
local check = T.check
require("tests.game3_cache").stubSpeciesNames()

local Pokemon = require("src.core.game3.pokemon")
local FIXTURE_MOVES = {
  [1] = { name = "POUND", type = 0, pp = 35, power = 40, accuracy = 100 },
  [2] = { name = "KARATE CHOP", type = 1, pp = 25, power = 50, accuracy = 100 },
  [3] = { name = "DOUBLE SLAP", type = 0, pp = 10, power = 15, accuracy = 85 },
  [4] = { name = "COMET PUNCH", type = 0, pp = 15, power = 18, accuracy = 85 },
  [5] = { name = "MEGA PUNCH", type = 0, pp = 20, power = 80, accuracy = 85 },
}
local function installFixtureMoves()
  Pokemon._battleMoves = FIXTURE_MOVES
  Pokemon._moveNames = {}
  for id, m in pairs(FIXTURE_MOVES) do Pokemon._moveNames[id] = m.name end
end
local realInstall = Pokemon.install
Pokemon.install = function(...)
  realInstall(...)
  installFixtureMoves()
end
installFixtureMoves()

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end,
  playSong = function() end, stopAll = function() end,
}

local RseSummary = require("src.ui.game3.rse.summary_menu")
local SummaryMenu = require("src.ui.game3.summary_menu")

local testMon = {
  species = 25, level = 30, hp = 50, maxHp = 50,
  stats = { hp = 50, attack = 30, defense = 30, spAttack = 30, spDefense = 30, speed = 30 },
  moves = { 1, 2, 3, 4 }, pp = { 35, 25, 10, 15 },
  otName = "RED", otId = 1, personality = 1,
}

-- Test RSE moveList with moveToLearn
SummaryMenu._mode = "select_move"
SummaryMenu._moveToLearn = 5
SummaryMenu._moveCursor = 5

local rseMoves = nil
-- moveList is local to RSE summary, but we can verify RseSummary page & detail behavior
check(RseSummary.page(SummaryMenu) == RseSummary.PAGE.BATTLE_MOVES, "RSE summary page in select_move is BATTLE_MOVES")
check(RseSummary.detail(SummaryMenu) == true, "RSE summary detail in select_move is true")

-- Test FRLG summary moves_for_mon with moveToLearn
SummaryMenu.openMenu({ testMon }, 1, {
  mode = "select_move",
  moveToLearn = 5,
})

check(SummaryMenu.isOpen() == true, "Summary menu opened")
check(SummaryMenu._mode == "select_move", "Summary menu mode is select_move")
check(SummaryMenu._moveToLearn == 5, "Summary menu moveToLearn is 5")

-- Check moving down moves cursor to 5th slot
SummaryMenu._moveCursor = 4
local input = {
  wasPressed = function(self, key) return key == "down" end,
  isDown = function(self, key) return false end,
}
SummaryMenu.handleInput(input)
check(SummaryMenu._moveCursor == 5, "Moving down from slot 4 reaches slot 5")

SummaryMenu.handleInput(input)
check(SummaryMenu._moveCursor == 1, "Moving down from slot 5 wraps to slot 1")

SummaryMenu.close()
check(SummaryMenu.isOpen() == false, "Summary menu closed")

T.finish()

-- pokecrystal data/text/common_2.asm:678-681 _BattleStatWentWayUpText
-- pokecrystal home/text.asm:520 _ContTextNoPause

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local T = require("tests.harness")
local BattleState = require("src.ui.gen2.BattleState")
local Effects = require("src.battle.gen2.Effects")
local S7B = require("tests.fixture_data.gen2_rom_text_s7_b")

local data = { text = S7B.text({ ["StatNames#1"] = "ATTACK" }) }
local text = Effects.stageMessage(data, "CYNDA", "attack", 2)
T.eq(text, "CYNDA's\nATTACK\rwent way up!", "the stage line carries the no-wait scroll")

local game = { save = { options = { textSpeed = "FAST" } },
  input = { isDown = function() return false end } }
local state = setmetatable({ game = game }, { __index = BattleState })
state:showPages(text)
T.eq(state.messagePages, nil, "a no-wait scroll is not a held page")

state:syncTyper()
local seen = {}
local guard = 0
while state:syncTyper() and guard < 200 do
  local lines = state:messageLines()
  seen[#seen + 1] = table.concat(lines, "|")
  T.check(#lines <= 2, "the box never shows more than two rows")
  state.typer:tick()
  guard = guard + 1
end
local final = state:messageLines()
T.eq(final[1], "ATTACK", "the box scrolls the stat name to the top row")
T.eq(final[2], "went way up!", "and types the tail under it")
local both = false
for _, frame in ipairs(seen) do
  if frame == "CYNDA's|ATTACK" then both = true end
end
T.check(both, "the head shows both rows before the scroll")

T.finish("gen2_battle_no_wait_scroll")

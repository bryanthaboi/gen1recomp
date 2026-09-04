-- (engine/battle/core.asm:2520)
--   luajit tests/engine/ether_move_menu_2158.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ETHER move select window #2158")
local check, eq = S.check, S.eq

local ItemEffects = require("src.inventory.ItemEffects")
local SaveData = require("src.core.SaveData")

-- engine/items/item_effects.asm:2016
for _, id in ipairs({ "ETHER", "MAX_ETHER", "ELIXER", "MAX_ELIXER", "PP_UP" }) do
  eq(ItemEffects.keepsPartyMenuOpen(id), true, id .. " keeps the party menu open")
end

local src = assert(io.open("src/ui/BagMenu.lua")):read("*a")
eq(src:find("Which move?", 1, true), nil, "BagMenu no longer builds a Which move? list")
check(src:find("MoveSelectMenu", 1, true) ~= nil, "BagMenu pushes MoveSelectMenu")
check(src:find("_RestorePPWhichTechniqueText", 1, true) ~= nil,
      "and prints RestorePPWhichTechniqueText")
check(src:find("_RaisePPWhichTechniqueText", 1, true) ~= nil,
      "and RaisePPWhichTechniqueText for PP UP")

local draws
local FontStub = {
  drawBox = function(tx, ty, tw, th) draws[#draws + 1] = { "box", tx, ty, tw, th } end,
  draw = function(text, x, y) draws[#draws + 1] = { "text", text, x, y } end,
  drawCode = function(code, x, y) draws[#draws + 1] = { "code", code, x, y } end,
}
package.loaded["src.render.Font"] = FontStub
local MoveSelectMenu = require("src.ui.MoveSelectMenu")

local pressed = {}
local stack = {}
local game = {
  input = { wasPressed = function(_, b) return pressed[b] == true end },
  stack = {
    push = function(_, s) stack[#stack + 1] = s end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  },
  data = { moves = { SCRATCH = { name = "SCRATCH" }, EMBER = { name = "EMBER" } } },
}
local mon = { moves = { { id = "SCRATCH", pp = 5 }, { id = "EMBER", pp = 25 } } }

local chosen, cancelled
local menu = MoveSelectMenu.new(game, mon, "Restore PP of\nwhich technique?",
  function(i) chosen = i end, function() cancelled = true end)
stack[1] = menu

draws = {}
menu:draw()
-- engine/battle/core.asm:2526
eq(draws[1][1], "box", "the move window is a bordered box")
eq(draws[1][2], 4, "at tile column 4")
eq(draws[1][3], 7, "tile row 7")
eq(draws[1][4], 16, "16 tiles wide")
eq(draws[1][5], 6, "6 tiles tall")
-- engine/battle/core.asm:2530
eq(draws[2][2], "SCRATCH", "slot 1 name")
eq(draws[2][3], 48, "names start at x 48")
eq(draws[2][4], 64, "slot 1 on row 8")
eq(draws[3][4], 72, "slot 2 on row 9, single spaced")
-- engine/battle/misc.asm:37
eq(draws[4][2], "-", "empty slot 3 is a dash")
eq(draws[5][2], "-", "empty slot 4 is a dash")
check(not tostring(draws[2][2]):find("5"), "no PP column on the move rows")
-- engine/battle/core.asm:2535
eq(draws[6][1], "code", "cursor glyph")
eq(draws[6][3], 40, "cursor at tile column 5")
eq(draws[6][4], 64, "cursor starts on the first move")
-- engine/items/item_effects.asm:1979
eq(draws[7][2], 0, "prompt box at column 0")
eq(draws[7][3], 12, "row 12")
eq(draws[8][2], "Restore PP of", "prompt line 1")
eq(draws[8][4], 112, "on row 14")
eq(draws[9][2], "which technique?", "prompt line 2")
eq(draws[9][4], 128, "on row 16")

local terminated = MoveSelectMenu.new(game, mon,
  "Restore PP of\nwhich technique?{DONE}", function() end)
draws = {}
terminated:draw()
eq(draws[9][2], "which technique?", "the {DONE} terminator is not drawn")

-- engine/battle/core.asm:2692
pressed = { down = true }
menu:update()
eq(menu.index, 2, "down moves to slot 2")
menu:update()
eq(menu.index, 1, "and wraps past the dash slots back to slot 1")
pressed = { up = true }
menu:update()
eq(menu.index, 2, "up wraps to the last real move")

-- engine/items/item_effects.asm:1985
pressed = { b = true }
menu:update()
eq(#stack, 0, "B pops the move window")
eq(cancelled, true, "back to the party menu")

stack[1] = menu
menu.index = 2
pressed = { a = true }
menu:update()
eq(chosen, 2, "A hands back the picked slot")
eq(#stack, 0, "and pops itself first")

local empty, escaped = { moves = {} }, 0
local emptyMenu = MoveSelectMenu.new(game, empty, "Restore PP of\nwhich technique?",
  function() escaped = -1 end, function() escaped = escaped + 1 end)
stack[1] = emptyMenu
pressed = { down = true }
emptyMenu:update()
eq(#stack, 1, "an empty list ignores DOWN")
eq(emptyMenu.index, 1, "and leaves the cursor on slot 1")
pressed = { b = true }
emptyMenu:update()
eq(#stack, 0, "B pops the empty move window")
eq(escaped, 1, "and runs onCancel")

stack[1] = emptyMenu
escaped = 0
pressed = { a = true }
emptyMenu:update()
eq(#stack, 0, "A on an empty list cancels too")
eq(escaped, 1, "never reporting a picked slot")

-- engine/items/item_effects.asm:2040
local Data = {
  items = { ETHER = { name = "ETHER" } },
  moves = { SCRATCH = { name = "SCRATCH", pp = 35 }, EMBER = { name = "EMBER", pp = 25 } },
  pokemon = { CHARMANDER = { name = "CHARMANDER" } },
  text = {},
}
local save = SaveData.newGame()
local t = { species = "CHARMANDER", hp = 20, stats = { hp = 20 },
            moves = { { id = "SCRATCH", pp = 30 }, { id = "EMBER", pp = 5 } } }
eq((ItemEffects.use(Data, save, "ETHER", t, nil, 2)), "consumed", "ETHER on slot 2")
eq(t.moves[1].pp, 30, "slot 1 untouched")
eq(t.moves[2].pp, 15, "slot 2 gets +10")

S.finish()

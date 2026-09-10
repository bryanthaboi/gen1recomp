-- scripts/SilphCo7F.asm:223-252
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

package.loaded["src.core.Music"] = { play = function() end }

local story5 = require("data.scripts.story5")
local silph = story5.SILPH_CO_7F
T.check(silph ~= nil and type(silph.onStep) == "function",
  "SILPH_CO_7F has an onStep hook")

local function capture(y)
  local rows
  local probe = {
    runner = { isRunning = function() return false end,
               run = function(_, r) rows = r end },
    player = { facing = "up" },
  }
  local game = { data = {}, save = { flags = {} } }
  T.check(silph.onStep(game, probe, 3, y) == true,
    ("onStep fires on (3,%d)"):format(y))
  return rows or {}
end

local function rowsOf(rows, verb)
  local out = {}
  for i, row in ipairs(rows) do
    if row[1] == verb then out[#out + 1] = { index = i, row = row } end
  end
  return out
end

local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function replay(x, y, dirs)
  local cells = {}
  for _, d in ipairs(dirs) do
    x, y = x + D[d][1], y + D[d][2]
    cells[#cells + 1] = ("(%d,%d)"):format(x, y)
  end
  return cells, x, y
end

local WANT = {
  [2] = { dirs = { "right", "right" },
          cells = { "(4,3)", "(5,3)" } },
  [3] = { dirs = { "left", "up", "up", "right", "right", "right", "down" },
          cells = { "(2,4)", "(2,3)", "(2,2)", "(3,2)", "(4,2)", "(5,2)", "(5,3)" } },
}

for _, y in ipairs({ 2, 3 }) do
  local rows = capture(y)
  local tag = ("(3,%d)"):format(y)

  local moves = rowsOf(rows, "move_npc_to")
  T.eq(#moves, 1, tag .. ": exactly one pathfound move, the approach")
  local approach = moves[1] and moves[1].row
  T.check(approach and approach[2] == 9 and approach[3] == 3 and approach[4] == y + 1,
    tag .. (": the approach parks him on (3,%d)"):format(y + 1))

  local walks = rowsOf(rows, "walk_npc")
  T.eq(#walks, 1, tag .. ": exactly one explicit exit walk")
  local walk = walks[1] and walks[1].row
  T.check(walk and walk[2] == 9, tag .. ": the walk moves object 9, the rival")
  local dirs = walk and walk[3] or {}
  T.eq(table.concat(dirs, ","), table.concat(WANT[y].dirs, ","),
    tag .. ": exit list is " .. table.concat(WANT[y].dirs, ","))

  local cells, ex, ey = replay(3, y + 1, dirs)
  T.eq(table.concat(cells, " "), table.concat(WANT[y].cells, " "),
    tag .. ": the walk visits " .. table.concat(WANT[y].cells, " "))
  T.check(ex == 5 and ey == 3, tag .. ": the walk ends on the (5,3) teleporter")
  local bad = false
  for _, c in ipairs(cells) do
    if c == "(5,4)" or c == ("(3,%d)"):format(y) then bad = true end
  end
  T.check(not bad, tag .. ": the walk never steps on the desk or the player")
  if y == 3 then
    T.check(cells[#cells - 1] == "(5,2)", tag .. ": he arrives from (5,2), not (4,3)")
    local through43 = false
    for _, c in ipairs(cells) do if c == "(4,3)" then through43 = true end end
    T.check(not through43, tag .. ": the walk-around never uses (4,3)")
  end

  local hide = rowsOf(rows, "hide_object")[1]
  T.check(hide and walks[1] and hide.index > walks[1].index,
    tag .. ": the hide follows the walk")
end

T.finish("silph7f_rival_exit_bug2242")

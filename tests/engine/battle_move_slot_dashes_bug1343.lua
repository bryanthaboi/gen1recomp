-- engine/battle/misc.asm:37 FormatMovesString .printDashLoop

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local BattleState = require("src.battle.BattleState")
local Font = require("src.render.Font")

local realDraw, realDrawCode, realDrawBox = Font.draw, Font.drawCode, Font.drawBox
local drawn

local function stubFont()
  drawn = {}
  Font.draw = function(text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end
  Font.drawCode = function() end
  Font.drawBox = function() end
end

local function unstubFont()
  Font.draw, Font.drawCode, Font.drawBox = realDraw, realDrawCode, realDrawBox
end

-- a mon with fewer than four moves: the remaining rows must be dashes, not
-- simply absent (ipairs used to stop at the last known move).
do
  stubFont()
  local screen = setmetatable({
    phase = "moveSelect",
    player = { curMoves = { { id = "TACKLE", pp = 35 } } },
    data = { text = require("tests.fixture_data.text"), moves = { TACKLE = { name = "TACKLE", pp = 35, type = "NORMAL" } } },
    moveIndex = 1, frame = 0,
  }, { __index = BattleState })
  local ok, err = pcall(function() screen:drawTextArea() end)
  T.check(ok, "moveSelect draws without error (" .. tostring(err) .. ")")

  local rows = {}
  for _, d in ipairs(drawn) do
    if d.x == 48 and d.y >= 104 and d.y <= 128 then rows[#rows + 1] = d.text end
  end
  T.eq(#rows, 4, "all four move rows are drawn, even the unused ones")
  T.eq(rows[1], "TACKLE", "the one real move prints its name")
  T.eq(rows[2], "-", "an empty slot is a dash")
  T.eq(rows[3], "-", "so is the next one")
  T.eq(rows[4], "-", "and the last one")
  unstubFont()
end

-- a full four-move mon: no dashes anywhere.
do
  stubFont()
  local screen = setmetatable({
    phase = "moveSelect",
    player = { curMoves = {
      { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
      { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
    } },
    data = { text = require("tests.fixture_data.text"), moves = {
      TACKLE = { name = "TACKLE", pp = 35, type = "NORMAL" },
      GROWL = { name = "GROWL", pp = 40, type = "NORMAL" },
    } },
    moveIndex = 1, frame = 0,
  }, { __index = BattleState })
  screen:drawTextArea()
  local rows = {}
  for _, d in ipairs(drawn) do
    if d.x == 48 and d.y >= 104 and d.y <= 128 then rows[#rows + 1] = d.text end
  end
  T.eq(#rows, 4, "still exactly four rows")
  for i, want in ipairs({ "TACKLE", "GROWL", "TACKLE", "GROWL" }) do
    T.eq(rows[i], want, "row " .. i .. " keeps its own move name")
  end
  unstubFont()
end

-- the Mimic menu shares FormatMovesString on the cart, so it gets the same
-- dash treatment.
do
  stubFont()
  local screen = setmetatable({
    phase = "mimicSelect",
    mimicMoves = { { id = "TACKLE" }, { id = "GROWL" } },
    data = { text = require("tests.fixture_data.text"), moves = {
      TACKLE = { name = "TACKLE" }, GROWL = { name = "GROWL" },
    } },
    mimicIndex = 1, frame = 0,
  }, { __index = BattleState })
  local ok = pcall(function() screen:drawTextArea() end)
  T.check(ok, "mimicSelect draws without error")
  local rows = {}
  for _, d in ipairs(drawn) do
    if d.x == 16 and d.y >= 64 and d.y <= 88 then rows[#rows + 1] = d.text end
  end
  T.eq(rows[1], "TACKLE", "mimic row 1 is the enemy's first move")
  T.eq(rows[2], "GROWL", "mimic row 2 is its second")
  T.eq(rows[3], "-", "an enemy with fewer than four moves dashes out the rest")
  T.eq(rows[4], "-", "including the last row")
  unstubFont()
end

T.finish("battle move slot dashes bug 1343")

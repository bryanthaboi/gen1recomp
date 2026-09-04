package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local TextBox = require("src.render.TextBox")

local ARROW = Theme.moreArrow or 0xEE

local function newGame(gen)
  return {
    save = { player = {}, options = { textSpeed = "FAST" }, generation = gen },
    data = { text = {} },
    input = {
      wasPressed = function() return false end,
      isDown = function() return false end,
    },
  }
end

local captured = {}
local realDraw = Font.drawCode
Font.drawCode = function(code, x, y)
  captured[#captured + 1] = { code = code, x = x, y = y }
end

local function arrowAt(box, blink)
  box.blink = blink
  captured = {}
  box:draw()
  for _, g in ipairs(captured) do
    if g.code == ARROW then return g end
  end
  return nil
end

local red = TextBox.new(newGame(1), "A")
red.blink = 479
red:update(1 / 60)
eq(red.blink, 0, "the blink counter wraps at 480")
red.waiting = true
red.shown = {}

local g = arrowAt(red, 0)
check(g, "gen1 arrow draws on the on phase")
eq(g.x, 144, "gen1 arrow x")
-- home/text.asm:214
eq(g.y, 128, "gen1 arrow sits on the second text row, tile row 16")
eq(g.y, red.line2Y, "gen1 arrow shares the second line's row")
eq(select(2, red:arrowPos()), 128, "arrowPos agrees with the draw")
check(arrowAt(red, 29), "gen1 on through frame 29")
eq(arrowAt(red, 30), nil, "gen1 off from frame 30")
eq(arrowAt(red, 59), nil, "gen1 off through frame 59")
check(arrowAt(red, 60), "gen1 back on as the 60-frame cycle repeats")

local gold = TextBox.new(newGame(2), "A")
gold.waiting = true
gold.shown = {}

-- pokegold home/text.asm:549
g = arrowAt(gold, 0)
check(g, "gold arrow draws on the on phase")
eq(g.x, 144, "gold arrow x is tile column 18")
eq(g.y, 136, "gold arrow sits on the border row, tile row 17")
eq(select(2, gold:arrowPos()), 136, "gold arrowPos is unchanged")
-- pokegold home/joypad.asm:430
check(arrowAt(gold, 15), "gold on through frame 15")
eq(arrowAt(gold, 16), nil, "gold off from frame 16")
eq(arrowAt(gold, 31), nil, "gold off through frame 31")
check(arrowAt(gold, 32), "gold back on at frame 32")
check(arrowAt(gold, 47), "gold cadence holds later in the wrap")

Font.drawCode = realDraw
T.finish()

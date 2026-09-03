package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local TextBox = require("src.render.TextBox")

local ARROW = Theme.moreArrow or 0xEE
local CREAM = { 231, 227, 231 }

local function newGame(gen, paper)
  return {
    save = { player = {}, options = { textSpeed = "FAST" }, generation = gen },
    data = { text = {} },
    input = {
      wasPressed = function() return false end,
      isDown = function() return false end,
    },
    textboxPaper = paper and function() return paper end or nil,
  }
end

local events
local realDraw, realFill = Font.drawCode, Chrome.paletteFill
Font.drawCode = function(code, x, y)
  events[#events + 1] = { kind = "glyph", code = code, x = x, y = y }
end
Chrome.paletteFill = function(x, y, w, h, palette)
  events[#events + 1] = { kind = "fill", x = x, y = y, w = w, h = h,
                          palette = palette }
end

local function frame(box, blink)
  box.blink = blink
  events = {}
  box:draw()
  local fill, arrow
  for i, e in ipairs(events) do
    if e.kind == "fill" and e.x == 144 and e.y == 136 then fill = i end
    if e.kind == "glyph" and e.code == ARROW then arrow = i end
  end
  return fill, arrow
end

local function box(gen, paper)
  local b = TextBox.new(newGame(gen, paper), "A")
  b.waiting = true
  b.shown = {}
  return b
end

-- ../pokecrystal/home/text.asm:630
do
  local gold = box(2)
  local fill, arrow = frame(gold, 0)
  check(arrow, "gold arrow draws on the on phase")
  check(fill, "and the (18,17) border cell is painted paper first")
  check(fill and arrow and fill < arrow, "paper goes under the arrow, not over it")
  local e = fill and events[fill]
  check(e and e.w == 8 and e.h == 8, "one whole 8x8 tile")
  check(e and e.palette == Chrome.DEFAULT_BOX_PALETTE,
    "through the box's own palette")
end

-- ../pokecrystal/home/joypad.asm:458
do
  local gold = box(2)
  local fill, arrow = frame(gold, 16)
  eq(arrow, nil, "gold arrow is off from frame 16")
  eq(fill, nil, "and the border tile is left alone on the off phase")
end

do
  local gear = box(2, CREAM)
  local fill = frame(gear, 0)
  local e = fill and events[fill]
  check(e and e.palette and e.palette[1] == CREAM,
    "a pushed textbox on the Pokegear's cream paper fills the cell cream")
end

do
  local red = box(1)
  local fill, arrow = frame(red, 0)
  check(arrow, "gen1 arrow still draws")
  eq(fill, nil, "and gen1 never paints the cell (its arrow sits on the interior)")
end

Font.drawCode, Chrome.paletteFill = realDraw, realFill
T.finish()

-- Parity test: scrolling text never draws onto the box border.
--
-- pokered has no sub-tile text scroll at all: ScrollTextUpOneLine
-- (home/text.asm:283) copies the three text rows up a whole row, blanks the
-- bottom one and waits 5 frames, so a glyph is never drawn between two
-- rows, let alone below the last one.  The port slides the scroll smoothly
-- instead, and used to add that offset to both visible lines -- which put
-- the incoming line 8px low, on the box's bottom border, for the four
-- frames of the slide (#314).  Oak's Hall of Fame speech is where players
-- hit it, being one long run of `\v` conts, but every scrolled box did it.
--
-- The invariant under test is geometric, so it is checked by capturing the
-- glyph draws rather than by looking at pixels: nothing may be drawn below
-- line2Y, ever, at any point in the scroll.
--
-- Self-contained; run via `luajit tests/parity_text_scroll_bounds.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity text scroll bounds")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local TextBox = require("src.render.TextBox")

-- capture glyph placement instead of drawing it
local drawn = {}
local realDrawCode, realDrawBox = Font.drawCode, Font.drawBox
Font.drawCode = function(code, x, y) drawn[#drawn + 1] = { x = x, y = y } end
Font.drawBox = function() end

local pressed = false
local game = {
  data = Data,
  save = { options = { textSpeed = 1 } }, -- fastest typewriter, fewest frames
  input = { wasPressed = function() return pressed end,
            isDown = function() return false end },
  stack = { push = function() end, pop = function() end, top = function() end },
}

-- three lines joined by \v (cont), which is what forces the scroll; the
-- Hall of Fame speech is built out of exactly this shape
local box = TextBox.new(game, "OAK: Er-hem!\nCongratulations\vCHAMP!")
local floorY = box.line2Y

-- pokered home/text.asm:214
local arrowX, arrowY = 144, 128
do
  local px, py = box:arrowPos()
  eq(px, arrowX, "arrowPos x is hlcoord 18 (home/text.asm:214)")
  eq(py, arrowY, "arrowPos y is hlcoord 16 (home/text.asm:214)")
end

local sawScroll, sawArrow, worst = false, false, -math.huge
for _ = 1, 600 do
  -- advance past the cont wait the same way a player would
  pressed = box.waiting or false
  box:update(1 / 60)
  pressed = false
  drawn = {}
  box:draw()
  if (box.scrollPx or 0) > 0 then sawScroll = true end
  for _, g in ipairs(drawn) do
    if g.x == arrowX and g.y == arrowY then
      sawArrow = true
    elseif g.y > worst then
      worst = g.y
    end
  end
  if box.done and not box.waiting then break end
end

Font.drawCode, Font.drawBox = realDrawCode, realDrawBox

check(sawScroll, "the box really did scroll (otherwise this proves nothing)")
check(worst > -math.huge, "body glyphs were drawn")
check(worst <= floorY,
      ("no body glyph drawn below line2Y (worst y=%d, line2Y=%d)"):format(worst, floorY))
check(sawArrow, "the page-advance arrow still prints on the second text row")
eq(arrowY, floorY, "and shares that row's y")
eq(box.line1Y + 16, box.line2Y, "the two text rows stay two tiles apart")

S.finish()

-- The slot machine's menus sit where the original draws them (#1811).
--
-- The bet menu is `hlcoord 14,11 / b=5 / c=4 / TextBoxBorder`
-- (engine/slots/slot_machine.asm:83-86), i.e. a 6x7 box whose bottom edge is
-- the last row of the screen, with the multipliers at hlcoord 16,12 and the
-- cursor at wTopMenuItemX 15 (asm:77-78, :87).  "One more go?" is a
-- TWO_OPTION_MENU at hlcoord 14,12 (asm:136-138) over the YES_NO_MENU body
-- (width 4, height 3 -> a 6x5 box; data/yes_no_menu_strings.asm:10).
-- The "Want to play?" prompt is not this screen's at all: PromptUserToPlaySlots
-- asks it before LoadSlotMachineTiles (asm:9-23), so the screen opens on the
-- bet menu.
--   luajit tests/engine/slot_machine_boxes_bug1811.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Font wants a real atlas and this suite is about which box lands on which
-- row, so it records the calls instead (tests/engine/bag_item_box_bug1521.lua's
-- shape)
local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #tostring(text) * 8 end,
}
package.loaded["src.core.Sound"] = { play = function() end }
package.loaded["src.ui.SlotMachine"] = nil
local SlotMachine = require("src.ui.SlotMachine")

local game = {
  data = { field = { slotWheels = {} }, text = dofile("tests/fixture_data/text.lua") },
  save = { coins = 100 },
}

local function record(fn)
  calls = {}
  fn()
  return calls
end

local function box(list, tx, ty)
  for _, c in ipairs(list) do
    if c[1] == "box" and c[2] == tx and c[3] == ty then return c end
  end
end

local function drawn(list, text)
  for _, c in ipairs(list) do
    if c[1] == "draw" and c[2] == text then return c end
  end
end

local function cursor(list)
  for _, c in ipairs(list) do
    if c[1] == "code" and c[2] == 0xED then return c end
  end
end

local slots = SlotMachine.new(game, false)
eq(slots.stage, "bet", "the screen opens on the bet menu, not a prompt")

local bet = record(function() slots:drawBottom() end)
local betBox = box(bet, 14, 11)
check(betBox ~= nil, "the bet menu box starts at (14,11)")
eq(betBox and betBox[4], 6, "it is 6 tiles wide (c = 4)")
eq(betBox and betBox[5], 7, "and 7 tall (b = 5), down to the last row")
eq(betBox and (betBox[3] + betBox[5]), 18, "so its bottom edge is the screen bottom")
local x3 = drawn(bet, "×3")
eq(x3 and x3[3], 16 * 8, "the multipliers print at column 16")
eq(x3 and x3[4], 12 * 8, "on row 12")
local x2, x1 = drawn(bet, "×2"), drawn(bet, "×1")
eq(x2 and x2[4], 14 * 8, "×2 two rows down (engine/slots/slot_machine.asm:150-153)")
eq(x1 and x1[4], 16 * 8, "×1 two rows further")
local betCursor = cursor(bet)
eq(betCursor and betCursor[3], 15 * 8, "the cursor sits at column 15")
eq(betCursor and betCursor[4], 12 * 8, "on the ×3 row by default")

slots.stage = "onemore"
slots.yesno = 1
local more = record(function() slots:drawBottom() end)
local moreBox = box(more, 14, 12)
check(moreBox ~= nil, "the One more go? menu box starts at (14,12)")
eq(moreBox and moreBox[4], 6, "it is 6 tiles wide")
eq(moreBox and moreBox[5], 5, "and 5 tall (YES_NO_MENU 4x3)")
check(box(more, 13, 12) == nil, "and not one column left of that")
local yes, no = drawn(more, "YES"), drawn(more, "NO")
eq(yes and yes[3], 16 * 8, "YES prints at column 16")
eq(yes and yes[4], 13 * 8, "on row 13")
eq(no and no[4], 15 * 8, "NO two rows below it (engine/slots/slot_machine.asm:136-138)")
local moreCursor = cursor(more)
eq(moreCursor and moreCursor[3], 15 * 8, "its cursor sits at column 15")
eq(moreCursor and moreCursor[4], 13 * 8, "starting on YES")

slots.yesno = 2
local onNo = record(function() slots:drawBottom() end)
eq(cursor(onNo) and cursor(onNo)[4], 15 * 8, "and moves to the NO row")

local function arrow(list)
  for _, c in ipairs(list) do
    if c[1] == "code" and c[2] == 0xEE then return c end
  end
end

-- engine/slots/slot_machine.asm:631-632
slots:resolveWin({ symbol = "CHERRY", payout = 8 })
slots.flashLeft = 1
slots.flashTimer = 4
game.input = { wasPressed = function() return false end }
slots:update(1 / 60)
eq(slots.stage, "message", "the flash ends on the lined-up message")
local won = record(function() slots:drawBottom() end)
local wonArrow = arrow(won)
check(wonArrow ~= nil, "the lined-up text shows the down arrow")
eq(wonArrow and wonArrow[3], 18 * 8, "at column 18")
eq(wonArrow and wonArrow[4], 16 * 8, "on row 16")

T.finish()

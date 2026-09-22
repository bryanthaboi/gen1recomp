package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = love or require("tests.love_stub")

local Display = require("src.core.game3.display")
local HelpWindow = require("src.ui.game3.help_window")

HelpWindow.reset()

check(package.loaded["src.ui.game3.help_system"] == nil,
  "help_window does not load the L/R Help browser (help_system.lua)")

local o = HelpWindow.OUTER
eq(o.left, 0, "outer left is 0")
eq(o.top, 15, "outer top is 15 (pret src/help_message.c:13-19)")
eq(o.width, 30, "outer width is 30 tiles")
eq(o.height, 5, "outer height is 5 tiles")
eq(o.paletteNum, 15, "outer palette is 15")

local c = HelpWindow.CONTENT
eq(c.left - 1, o.left, "content is the outer rect inset one tile left")
eq(c.top - 1, o.top, "content is the outer rect inset one tile top")
eq(c.width + 2, o.width, "frame width = content + the two border tiles")
eq(c.height + 2, o.height, "frame height = content + the two border tiles")

eq(Display.COLS, o.width, "engine grid is 30 tiles wide (display.lua:10)")
eq(Display.ROWS, o.top + o.height, "engine grid is 20 rows: the window sits on the bottom 5")
eq(Display.TILE, 8, "engine tile is 8px")

-- src/help_message.c:95-98
eq(HelpWindow.TEXT_OFFSET.x, 2, "text x offset is pret's 2px")
eq(HelpWindow.TEXT_OFFSET.y, 5, "text y offset is pret's 5px")
check(c.width * 8 - HelpWindow.TEXT_OFFSET.x * 2 > 0,
  "the printable width stays positive")
check(c.top * 8 + HelpWindow.TEXT_OFFSET.y < (o.top + o.height) * 8,
  "the text baseline lands inside the outer window")

check(HelpWindow.isOpen() == false, "starts closed")
eq(HelpWindow.getText(), "", "starts with no text")
check(HelpWindow.draw() == false, "draw with nothing open is a no-op")

check(HelpWindow.show("MOVE ID: STRENGTH") == true, "show opens the window")
check(HelpWindow.isOpen() == true, "isOpen reads back open")
eq(HelpWindow.getText(), "MOVE ID: STRENGTH", "getText reads back the text")
check(HelpWindow.draw() == true, "draw renders while open (headless)")

check(HelpWindow.show("0x08012345") == true, "a pointer-looking string is accepted")
eq(HelpWindow.getText(), "0x08012345", "text is stored verbatim, never resolved here")

check(HelpWindow.show("BICYCLE") == true, "re-show is allowed")
eq(HelpWindow.getText(), "BICYCLE", "re-show replaces the text")
eq(HelpWindow.isOpen(), true, "still open after re-show")

check(HelpWindow.show(nil) == true, "show(nil) still opens")
eq(HelpWindow.getText(), "", "show(nil) means empty text, not an error")
check(HelpWindow.show(123) == true, "show(number) still opens")
eq(HelpWindow.getText(), "", "non-string text degrades to empty")

check(HelpWindow.close() == true, "close hides the window")
check(HelpWindow.isOpen() == false, "closed reads back closed")
eq(HelpWindow.getText(), "", "close clears the text")
check(HelpWindow.draw() == false, "draw after close is a no-op")

check(HelpWindow.close() == true, "closing twice is safe (pret DestroyHelpMessageWindow_ is idempotent)")

check(HelpWindow.show("AGAIN") == true, "open → close → open works")
eq(HelpWindow.getText(), "AGAIN", "the reopened window carries its text")
check(HelpWindow.draw() == true, "draw works after reopen")

HelpWindow.reset()
check(HelpWindow.isOpen() == false, "reset closes the window")
eq(HelpWindow.getText(), "", "reset clears the text")
HelpWindow.reset()
check(HelpWindow.isOpen() == false, "reset is safe to repeat")

T.finish("game3_help_window_test")

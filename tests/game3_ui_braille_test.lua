#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end
_G.love = { graphics = gfx }

local Braille = require("src.ui.game3.braille")

print("[test] 1. the glyph codes are pret's braille alphabet")
-- pokefirered/include/characters.h:285
local EXPECT = {
  A = 0x01, B = 0x05, C = 0x03, D = 0x0B, E = 0x09, F = 0x07, G = 0x0F,
  H = 0x0D, I = 0x06, J = 0x0E, K = 0x11, L = 0x15, M = 0x13, N = 0x1B,
  O = 0x19, P = 0x17, Q = 0x1F, R = 0x1D, S = 0x16, T = 0x1E, U = 0x31,
  V = 0x35, W = 0x2E, X = 0x33, Y = 0x3B, Z = 0x39,
}
local alphabetOk, lowerOk = true, true
for letter, code in pairs(EXPECT) do
  if Braille.CODE[letter] ~= code then
    alphabetOk = false
    print("      " .. letter .. " is " .. tostring(Braille.CODE[letter]) .. ", pret says " .. code)
  end
  if Braille.CODE[letter:lower()] ~= code then lowerOk = false end
end
check(alphabetOk, "A-Z carry pret's braille codes")
check(lowerOk, "lowercase encodes to the same glyph as uppercase")
eq(Braille.CODE[" "], 0x00, "space is BRAILLE_CHAR_SPACE")
eq(Braille.CODE["."], 0x2C, "period is BRAILLE_CHAR_PERIOD")
eq(Braille.CODE[","], 0x04, "comma is BRAILLE_CHAR_COMMA")
eq(Braille.CODE["?"], 0x34, "question mark is BRAILLE_CHAR_QUESTION_MARK")
eq(Braille.CODE["("], Braille.CODE[")"], "both parens share BRAILLE_CHAR_PAREN")
eq(Braille.NUM_CHARS, 0x40, "the font holds 64 dot combinations")

print("[test] 2. encoding follows the .braille directive")
-- pokefirered/data/text/braille.inc:13
local function codes(text)
  local out = {}
  for _, line in ipairs(Braille.encode(text)) do
    local row = {}
    for _, c in ipairs(line) do row[#row + 1] = c end
    out[#out + 1] = table.concat(row, ",")
  end
  return table.concat(out, "|")
end
eq(codes("CUT"), "3,49,30", "CUT encodes to C U T")
eq(codes("UP"), "49,23", "UP encodes to U P")
eq(codes("HAS MEANING"), "13,1,22,0,19,9,1,27,6,27,15", "HAS MEANING keeps its space glyph")
eq(codes("CUT\nUP"), "3,49,30|49,23", "a newline starts a second line")
eq(codes("12"), "58,1,5", "a number run is preceded by BRAILLE_CHAR_NUMBER once")
eq(codes("1 2"), "58,1,0,58,5", "the number indicator returns after a space")

print("[test] 3. the width is pret's fixed 16px advance")
-- pokefirered/src/braille_text.c:209, src/new_menu_helpers.c:121
eq(Braille.GLYPH_WIDTH, 16, "GetGlyphWidth_Braille is 16")
eq(Braille.LINE_PITCH, 18, "maxLetterHeight 16 + lineSpacing 2")
eq(Braille.width("CUT"), 48, "CUT measures 48")
eq(Braille.width("HAS MEANING"), 176, "HAS MEANING measures 176")
eq(Braille.width("CUT\nUP"), 48, "a two line string measures its widest line")
eq(Braille.width(""), 0, "an empty string measures 0")
eq(Braille.countGlyphs("HAS MEANING"), 11, "eleven glyph cells")

print("[test] 4. braille bytes the script charmap still spells are recovered")
eq(codes("\195\137"), "6", "the decoded E-acute is glyph 0x06 (I)")
eq(codes("\195\169"), "27", "the decoded e-acute is glyph 0x1B (N)")
eq(codes("+"), "46", "the decoded plus is glyph 0x2E (W)")
eq(codes("="), "53", "the decoded equals is glyph 0x35 (V)")
eq(Braille.width("\195\137?\195\169="), 64, "four recovered glyphs measure 64")

print("[test] 5. the sheet layout is row major over the baked cells")
-- pokefirered/src/braille_text.c:200
eq(Braille.sheetCols({ cols = 16, width = 256, height = 64 }, 256), 16,
  "the bake's own manifest decides the cells per row")
eq(Braille.sheetCols(nil, 128), 8, "a manifest-less 128px sheet is 8 cells wide")
eq(Braille.sheetCols({}, 256), 16, "a manifest without cols falls back to the pixel width")
local gx, gy = Braille.glyphCell(0, 16)
eq(gx .. "," .. gy, "0,0", "glyph 0 is the top left cell")
gx, gy = Braille.glyphCell(0x11, 16)
eq(gx .. "," .. gy, "16,16", "glyph 0x11 on a 16 wide sheet is row 1 column 1")
gx, gy = Braille.glyphCell(0x11, 8)
eq(gx .. "," .. gy, "16,32", "glyph 0x11 on an 8 wide sheet is row 2 column 1")
gx, gy = Braille.glyphCell(0x3F, 16)
eq(gx .. "," .. gy, "240,48", "the last glyph is the bottom right cell")

print("[test] 6. with no glyph sheet the plain text is printed instead")
eq(Braille.hasSheet(), false, "no braille sheet is baked in this tier")
local FrlgFont = require("src.ui.game3.frlg_font")
local realDraw = FrlgFont.draw
local drew = nil
FrlgFont.draw = function(text) drew = text; return 0 end
local usedGlyphs = Braille.drawText("CUT", 0, 0, {})
FrlgFont.draw = realDraw
eq(usedGlyphs, false, "drawText reports that it fell back")
eq(drew, "CUT", "the fallback printed the raw string in the ordinary font")

print("[test] 7. show opens the message box on a braille frame")
-- pokefirered/src/scrcmd.c:1558
local Message = require("src.ui.game3.message")
Braille.show("HAS MEANING", { width = 176 })
eq(Message.isOpen(), true, "braillemessage opens the box")
eq(Message.frameKind(), "braille", "the box is on the braille frame")
eq(Message._stay, true, "the box stays up for waitbuttonpress")
eq(Message._total, 11, "the page counts braille cells, not latin glyphs")
-- pokefirered/src/text_printer.c:91
eq(Message._revealed, 11, "speed 0 renders every cell on the frame it opens")
eq(Message.isTyping(), false, "the braille box never runs the typewriter")
eq(Braille.isOpen(), true, "Braille.isOpen sees its own box")

local page, seen = nil, 0
local realBrailleDraw = Braille.drawText
Braille.drawText = function(text, x, y, o)
  page, seen = text, seen + 1
  return realBrailleDraw(text, x, y, o)
end
FrlgFont.draw = function() return 0 end
Message.drawText()
Braille.drawText = realBrailleDraw
FrlgFont.draw = realDraw
eq(seen, 1, "the message box routes the page through the braille renderer")
eq(page, "HAS MEANING", "and hands it the whole line")

Message.close()
eq(Braille.isOpen(), false, "closemessage closes the braille box")

print("[test] 8. the ops chain pcall seam")
for _, fn in ipairs({ "show", "width", "encode", "countGlyphs", "drawText", "hide" }) do
  check(type(Braille[fn]) == "function", "Braille." .. fn .. " is callable")
end
check(pcall(Braille.show, nil, nil), "show tolerates a nil string")
eq(Braille.width(nil), 0, "width tolerates nil")
Braille.hide()

print("[test] 9. the BrailleCursorToggle seam")
-- pokefirered/src/field_specials.c:2478
check(Braille.cursor() == nil, "no cursor before the special asks for one")
Braille.setCursor(64 + 27, 0)
local c = Braille.cursor()
eq(c and c.x, 91, "the cursor sits at the string width plus 27")
Braille.clearCursor()
check(Braille.cursor() == nil, "the toggle clears it again")

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL BRAILLE TESTS PASSED")

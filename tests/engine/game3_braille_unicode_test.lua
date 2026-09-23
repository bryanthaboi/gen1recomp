#!/usr/bin/env luajit
-- Braille.encode draws a Unicode braille cell (U+2800-U+283F) as that very cell,
-- so a mod can hand over a European cart's braille unchanged: the braille font
-- holds every dot combination (pokefirered/include/characters.h:282), and some
-- carts use cells no Latin character spells (German ä, dots 3-4-5).

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local Braille = require("src.ui.game3.braille")

local function cell(dots)
  local bits = 0
  for d in dots:gmatch("%d") do bits = bits + 2 ^ (tonumber(d) - 1) end
  return string.char(0xE2, 0xA0, 0x80 + bits)
end

-- The standard braille alphabet, dot numbers per letter.
local LETTERS = {
  A = "1", B = "12", C = "14", D = "145", E = "15", F = "124", G = "1245", H = "125",
  I = "24", J = "245", K = "13", L = "123", M = "134", N = "1345", O = "135", P = "1234",
  Q = "12345", R = "1235", S = "234", T = "2345", U = "136", V = "1236", W = "2456",
  X = "1346", Y = "13456", Z = "1356",
}
local same = 0
for letter, dots in pairs(LETTERS) do
  if Braille.encode(cell(dots))[1][1] == Braille.encode(letter)[1][1] then same = same + 1 end
end
check(same == 26, "each Unicode letter cell is the cart's cell for that letter (" .. same .. "/26)")

local seen, distinct = {}, 0
for bits = 0, 63 do
  local code = Braille.encode(string.char(0xE2, 0xA0, 0x80 + bits))[1][1]
  if type(code) == "number" and code >= 0 and code < Braille.NUM_CHARS and not seen[code] then
    seen[code] = true
    distinct = distinct + 1
  end
end
check(distinct == 64, "the 64 Unicode cells reach the 64 cells of the font (" .. distinct .. ")")

check(Braille.encode(cell("345"))[1][1] == 0x1A, "German ä (dots 3-4-5) is drawn, which no Latin letter reaches")

local line = Braille.encode(cell("3456") .. cell("1") .. cell("12"))[1]
check(#line == 3 and line[1] == Braille.NUMBER,
  "a cart's own number sign stays one cell, with no second one added")

check(Braille.width(cell("1") .. cell("12") .. "\n" .. cell("1")) == 2 * Braille.GLYPH_WIDTH,
  "the width counts cells, not UTF-8 bytes")
local latin = Braille.encode("DIG HERE")[1]
check(#latin == 8 and latin[1] == 0x0B, "Latin text still spells as before")

-- pokefirered/src/scrcmd.c:1558 braillemessage: the script's text reaches the
-- font through TextIR.toPlain, which must keep the cells a mod's IR carries.
local TextIR = require("src.core.game3.scripting.text_ir")
local plain = TextIR.toPlain({ { t = "text", s = cell("125") .. cell("1") .. cell("136") .. cell("2345") },
  { t = "nl" }, { t = "text", s = cell("345") }, { t = "eos" } }, {})
local lines = Braille.encode(plain)
check(#lines == 2 and #lines[1] == 4 and lines[2][1] == 0x1A,
  "a mod's braille message (French HAUT, then German ä) reaches the font cell for cell")

T.finish("game3_braille_unicode_test")

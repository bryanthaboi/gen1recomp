-- pokered/constants/text_constants.asm:3
-- pokefirered/include/constants/global.h:63
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local TextClip = require("src.core.TextClip")

local E = "\195\169"
local MALE = "\226\153\130"

T.eq(TextClip.clip("ABCDEFGHIJKL", 10), "ABCDEFGHIJ", "ascii: ten characters")
T.eq(TextClip.clip("SPIKE", 10), "SPIKE", "ascii: a short name is untouched")
T.eq(TextClip.clip(E:rep(10), 10), E:rep(10), "ten multibyte characters all stay")
T.eq(TextClip.clip("A" .. E:rep(12), 10), "A" .. E:rep(9), "a cut never lands inside a character")
T.eq(TextClip.clip(MALE:rep(4), 10), MALE:rep(4), "four characters under the limit are kept whole")
T.eq(TextClip.clip("NIDO" .. MALE .. "KING" .. MALE .. "X", 10), "NIDO" .. MALE .. "KING" .. MALE,
  "a grid-legal ten with two signs")
T.eq(TextClip.clip(("<PK><MN>"):rep(6), 10), "<PK><MN><P", "angle brackets are plain characters")
T.eq(TextClip.clip("<ABCDEFGHIJKLMNOP>", 10), "<ABCDEFGHI", "an angle-bracket run is clipped like text")
T.eq(TextClip.clip(("{PK}{MN}"):rep(6), 10), ("{PK}{MN}"):rep(5), "a {PK} or {MN} ligature is one cell")
T.eq(TextClip.clip("ABCDEFGH{PK}{MN}X", 10), "ABCDEFGH{PK}{MN}", "ligatures fill the last two cells")
T.eq(TextClip.clip(("{PKMN}"):rep(6), 10), ("{PKMN}"):rep(5), "{PKMN} is two cells")
T.eq(TextClip.clip("ABCDEFGHI{PKMN}", 10), "ABCDEFGHI", "{PKMN} is never split across the limit")
T.eq(TextClip.clip("{pk}", 1), "{pk}", "tag names match the renderer case-insensitively")
T.eq(TextClip.clip("{A_BUTTON}BC", 2), "{A_BUTTON}B", "a keypad icon is one cell")
T.eq(TextClip.clip("{FOO}ABCDEFGH", 10), "{FOO}ABCDE", "an unknown brace run is plain text")
T.eq(TextClip.clip("{PK", 10), "{PK", "an unclosed brace is plain text")
T.eq(TextClip.clip("A" .. ("\128"):rep(30), 10), "A" .. ("\128"):rep(9), "stray continuation bytes are one cell each")
T.eq(TextClip.clip(E .. "\169\169", 10), E .. "\169\169", "a sequence never swallows more than its lead byte allows")
T.eq(#TextClip.spans(E .. "\169\169"), 3, "the extra continuation bytes are their own spans")
T.eq(TextClip.clip("AB\nCD\0E\tF", 10), "ABCDEF", "control characters are dropped")
T.eq(TextClip.clip("\n\r", 10), "", "a name of only control characters clips to nothing")
T.eq(TextClip.clip("ABC", 0), "", "a zero limit is empty")
T.eq(TextClip.clip("", 10), "", "an empty name stays empty")
T.eq(TextClip.clip(nil, 10), "", "a non-string is empty")
T.eq(TextClip.clip(42, 10), "", "a number is not a name")
T.eq(TextClip.clip("A\195", 10), "A\195", "a dangling lead byte is one span, not a crash")

local spans = TextClip.spans("A" .. E .. "{PKMN}<")
T.eq(#spans, 4, "spans: four pieces")
T.eq(spans[2].from .. "-" .. spans[2].to, "2-3", "spans: the multibyte span")
T.eq(spans[3].from .. "-" .. spans[3].to .. "x" .. spans[3].w, "4-9x2", "spans: the ligature span and its width")
T.eq(spans[4].from .. "-" .. spans[4].to, "10-10", "spans: a lone angle bracket")

local seen
local function perByte(s)
  seen = s
  local out = {}
  for i = 1, #s do out[i] = { from = i, to = i } end
  return out
end
T.eq(TextClip.clip("AB\nCDEF", 3, perByte), "ABC", "a caller's split decides the count")
T.eq(seen, "ABCDEF", "and sees the name with control characters already gone")

T.finish("text clip")

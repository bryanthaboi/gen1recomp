#!/usr/bin/env luajit
-- FrlgFont maps every Latin letter the FireRed ROM font draws to its
-- charmap glyph, not only the ones US text prints, and leaves the ROM
-- decode table (TextIR.CHARMAP) untouched.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local FrlgFont = require("src.ui.game3.frlg_font")
local TextIR = require("src.core.game3.scripting.text_ir")
local LATIN = FrlgFont.LATIN_GLYPHS or {}
check(FrlgFont.LATIN_GLYPHS ~= nil, "FrlgFont.LATIN_GLYPHS exists")

-- pret pokefirered/charmap.txt, Latin block: every character the table
-- must add, written out independently of FrlgFont.LATIN_GLYPHS.
local expected = {
  ["À"] = 0x01, ["Á"] = 0x02, ["Â"] = 0x03, ["Ç"] = 0x04, ["È"] = 0x05,
  ["Ê"] = 0x07, ["Ë"] = 0x08, ["Ì"] = 0x09, ["Î"] = 0x0B, ["Ï"] = 0x0C,
  ["Ò"] = 0x0D, ["Ó"] = 0x0E, ["Ô"] = 0x0F, ["Œ"] = 0x10, ["Ù"] = 0x11,
  ["Ú"] = 0x12, ["Û"] = 0x13, ["Ñ"] = 0x14, ["ß"] = 0x15, ["à"] = 0x16,
  ["á"] = 0x17, ["ç"] = 0x19, ["è"] = 0x1A, ["ê"] = 0x1C, ["ë"] = 0x1D,
  ["ì"] = 0x1E, ["î"] = 0x20, ["ï"] = 0x21, ["ò"] = 0x22, ["ó"] = 0x23,
  ["ô"] = 0x24, ["œ"] = 0x25, ["ù"] = 0x26, ["ú"] = 0x27, ["û"] = 0x28,
  ["ñ"] = 0x29, ["º"] = 0x2A, ["ª"] = 0x2B, [";"] = 0x36, ["¿"] = 0x51,
  ["¡"] = 0x52, ["Í"] = 0x5A, ["â"] = 0x68, ["í"] = 0x6F, ["▶"] = 0xEF,
  ["Ä"] = 0xF1, ["Ö"] = 0xF2, ["Ü"] = 0xF3, ["ä"] = 0xF4, ["ö"] = 0xF5,
  ["ü"] = 0xF6,
}
local count = 0
for ch, code in pairs(expected) do
  count = count + 1
  check(FrlgFont.glyphId(ch) == code, ("%s draws glyph 0x%02X"):format(ch, code))
  check(LATIN[code] == ch, ("LATIN_GLYPHS[0x%02X] is %s"):format(code, ch))
end
local listed = 0
for _ in pairs(LATIN) do listed = listed + 1 end
check(listed == count, ("LATIN_GLYPHS lists exactly the %d expected glyphs (got %d)"):format(count, listed))

local unique = {}
for code, ch in pairs(LATIN) do
  check(TextIR.CHARMAP[code] == nil, ("0x%02X is not a US decode byte"):format(code))
  check(code < 0xF7 and code ~= 0x53 and code ~= 0x54,
    ("0x%02X is not a control or ligature byte"):format(code))
  check(not unique[ch], ch .. " is listed once")
  unique[ch] = true
end

-- US text keeps drawing exactly what it drew before.
for code, ch in pairs(TextIR.CHARMAP) do
  if ch ~= " " then
    check(FrlgFont.glyphId(ch) == code, ("US %q still draws 0x%02X"):format(ch, code))
  end
end
check(FrlgFont.glyphId("é") == 0x1B, "é still draws 0x1B")
check(FrlgFont.glyphId("'") == 0xB4, "apostrophe still draws 0xB4")
check(FrlgFont.glyphId("€") == 0x00, "a character with no ROM glyph still draws blank")

-- Decoding ROM text is unchanged: 0x16 is not a US byte.
local ir = TextIR.decode({ 0x16, 0xFF })
check(ir[1] and ir[1].s == "?", "TextIR.decode still reads 0x16 as '?'")

print(("game3_latin_glyphs_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end

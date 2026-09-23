#!/usr/bin/env luajit
-- The US FireRed cart keeps its Japanese fonts (pokefirered/src/text.c:141,
-- :227); FrlgFont draws a Japanese character with them, numbered by the Japanese
-- block of pokefirered/charmap.txt, while Latin text keeps its own glyphs.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local FrlgFont = require("src.ui.game3.frlg_font")
local BASE = FrlgFont.JAPANESE_BASE

-- pokefirered/charmap.txt: あ..っ are 01-50, ア..ッ 51-A0
check(FrlgFont.glyphId("あ") == BASE + 0x01, "あ is the Japanese font's glyph 01")
check(FrlgFont.glyphId("っ") == BASE + 0x50, "っ closes the hiragana at 50")
check(FrlgFont.glyphId("ア") == BASE + 0x51, "ア opens the katakana at 51")
check(FrlgFont.glyphId("ッ") == BASE + 0xA0, "ッ closes them at A0")
check(FrlgFont.glyphId("　") == BASE + 0x00, "the full-width space is glyph 00")
check(FrlgFont.glyphId("ー") == BASE + 0xAE, "ー is AE")
check(FrlgFont.glyphId("０") == BASE + 0xA1 and FrlgFont.glyphId("９") == BASE + 0xAA,
  "full-width digits sit where the Latin digits do (A1-AA)")
check(FrlgFont.glyphId("Ｐ") == BASE + 0xCA and FrlgFont.glyphId("ｃ") == BASE + 0xD7,
  "full-width letters too (BB-EE)")
check(FrlgFont.glyphId("「") == BASE + 0xB3 and FrlgFont.glyphId("』") == BASE + 0xB2,
  "and the Japanese quotes (B1-B4)")
check(FrlgFont.glyphId("A") == 0xBB and FrlgFont.glyphId("0") == 0xA1 and FrlgFont.glyphId("é") ~= nil
  and FrlgFont.glyphId("é") < BASE, "Latin text keeps the Latin font")

-- pokefirered/src/text.c:853 a Japanese glyph advances by its width plus the
-- window's letter spacing: 1 for the normal font, whose width table gives most
-- kana 10px (text.c:1492; the small kana 9px), 0 for the small font's fixed 8px
-- (text.c:1391).  With no extracted width table the normal font falls back to 10.
check(FrlgFont.advance(FrlgFont.glyphId("あ"), { small = true }) == 8, "a small-font kana advances 8px")
check(FrlgFont.measure("ポケモン") == 44, "four normal kana advance 44px (got " .. FrlgFont.measure("ポケモン") .. ")")
-- The spacing is added once: a ROM-extracted string carries the {JPN} control
-- code (0xFC 0x15) that the engine's own spacing already keys on.
local JPN = "\252\21"
check(FrlgFont.measure(JPN .. "ポケモン", { letterSpacing = 1 }) == 44,
  "with the {JPN} code and a window spacing of 1, they still advance 44px (got "
  .. FrlgFont.measure(JPN .. "ポケモン", { letterSpacing = 1 }) .. ")")
check(FrlgFont.measure("ポケモン", { letterSpacing = 0 }) == 40,
  "and a window that asks for no spacing gets none (40px), the battle boxes' case")
check(FrlgFont.measure("POKEMON") == FrlgFont.measure("POKE") + FrlgFont.measure("MON"),
  "Latin text keeps its own advance, with no letter spacing added")

-- A name limit counts characters, and a kana is three bytes.
check(FrlgFont.truncate("フシギダネ", 10) == "フシギダネ", "a five-kana name fits a ten-character limit")
check(FrlgFont.truncate("フシギダネ", 3) == "フシギ", "and is cut between characters, never inside one")
check(FrlgFont.truncate("BULBASAUR", 7) == "BULBASA", "Latin names are cut as before")

-- pokefirered/include/constants/global.h PLAYER_NAME_LENGTH is 7 characters: the
-- continue screen keeps seven kana of the player's name, not seven bytes.
local Boot = require("src.ui.game3.boot")
local info = Boot.continueInfoFromSave({ name = "ながいなまえです", playTime = {} })
check(info and info.name == "ながいなまえで",
  "the continue screen keeps a Japanese name's first seven kana (got " .. tostring(info and info.name) .. ")")

-- The extractor reads the glyphs the way DecompressGlyph_Normal/_Small lay them out.
local TextChromeExtract = require("src.import.gba.text_chrome_extract")
local bytes = {}
local rom = { get = function(_, off) return bytes[off] or 0 end }
-- normal glyph 9 (row 1, column 1): top-left tile at 0x207500 + 0x200 + 0x20,
-- bottom-right at +0x110.  A 2bpp tile's first row is two bytes, pixel 0 in the
-- high bits of the second byte; 0x40 there sets pixel 0 to colour 1.
local g = 0x207500 + 0x200 + 0x20
bytes[g + 1] = 0x40
bytes[g + 0x110 + 1] = 0x40
local sheet = TextChromeExtract.extractJapaneseNormal(rom)
local function alpha(rgba, w, x, y) return rgba:byte((y * w + x) * 4 + 4) end
check(alpha(sheet.fgRgba, 256, 9 * 16, 0) == 255, "normal glyph 9's top-left pixel comes from its top tile")
check(alpha(sheet.fgRgba, 256, 9 * 16 + 8, 8) == 255, "and its bottom-right quarter from 0x110 bytes on")
check(alpha(sheet.fgRgba, 256, 8 * 16, 0) == 0, "while glyph 8 stays empty")
-- small glyph 17 (row 1, column 1): top tile at 0x1EF100 + 0x200 + 0x10, bottom 0x100 on
local s = 0x1EF100 + 0x200 + 0x10
bytes[s + 1] = 0x40
bytes[s + 0x100 + 1] = 0x40
local small = TextChromeExtract.extractJapaneseSmall(rom)
check(alpha(small.fgRgba, 256, 1 * 16, 16) == 255 and alpha(small.fgRgba, 256, 1 * 16, 24) == 255,
  "small glyph 17 is its top tile over the tile 0x100 bytes on")

T.finish("game3_japanese_font_test")

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Font = require("src.ui.game3.font")
local FrlgFont = require("src.ui.game3.frlg_font")

local prevVersion = GameVersion.get()

GameVersion.set("firered")
Profile.reset()
Font.reset()

check(Font.impl("firered") == FrlgFont, "firered resolves the profile-named frlg_font")
check(Font.impl(nil) == FrlgFont, "nil resolves the active game's implementation")
check(Font.active() == FrlgFont, "active() is the active game's implementation")
check(Font.impl("ruby") == FrlgFont, "an overlay-less RSE id falls back to FireRed's font")

eq(Font.CELL, FrlgFont.CELL, "CELL forwards")
eq(Font.GLYPH_HEIGHT, FrlgFont.GLYPH_HEIGHT, "GLYPH_HEIGHT forwards")
eq(Font.LINE_PITCH, FrlgFont.LINE_PITCH, "LINE_PITCH forwards")
check(Font.COLOR == FrlgFont.COLOR, "COLOR forwards by identity")
check(Font.STDPAL == FrlgFont.STDPAL, "STDPAL forwards by identity")
check(Font.COLOR_IDS == FrlgFont.COLOR_IDS, "COLOR_IDS forwards by identity")
check(Font.draw == FrlgFont.draw, "draw forwards the raw function")
check(Font.measure == FrlgFont.measure, "measure forwards the raw function")
check(Font.wrap == FrlgFont.wrap, "wrap forwards the raw function")
check(Font.drawGlyph == FrlgFont.drawGlyph, "drawGlyph forwards")
check(Font.scanTokens == FrlgFont.scanTokens, "scanTokens forwards")
check(Font.invalidate == FrlgFont.invalidate, "invalidate forwards")
check(Font.countChars == FrlgFont.countChars, "countChars forwards")
eq(Font.MAX_LETTER_WIDTH, FrlgFont.MAX_LETTER_WIDTH, "MAX_LETTER_WIDTH forwards")

local replacement = {
  CELL = 99,
  measure = function() return 42 end,
}
check(Font.register("testgame", replacement) == true, "register accepts a version + table")
check(Font.register("", replacement) == false, "register rejects an empty version")
check(Font.register("testgame", 7) == false, "register rejects a non-table")
check(Font.impl("testgame") == replacement, "a registration wins over the profile module")
eq(Font.impl("testgame").CELL, 99, "a registered table answers directly")

check(Font.register("firered", replacement) == true, "register the active game")
eq(Font.CELL, 99, "a forwarded constant follows the active registration")
check(Font.measure == replacement.measure, "a forwarded function follows the registration")

Font.reset()
check(Font.impl("firered") == replacement, "registrations survive reset")
check(Font.impl("ruby") == FrlgFont, "the FireRed fallback still answers for an overlay-less id")

check(Font.unregister("firered") == true, "unregister returns true")
Font.reset()
check(Font.impl("firered") == FrlgFont, "unregister falls back to the profile's module")
check(Font.unregister("testgame") == true, "clean up the fixture registration")

local saved = package.loaded["src.ui.game3.frlg_font"]
package.loaded["src.ui.game3.frlg_font"] = nil
Font.reset()
local loaded = Font.impl("firered")
check(loaded ~= nil, "the provider loads the profile-named module")
check(package.loaded["src.ui.game3.frlg_font"] == loaded,
  "the loaded module is the one frlg_font's path names")
package.loaded["src.ui.game3.frlg_font"] = saved or loaded

check(Font.NO_SUCH_KEY == nil, "an unknown forwarded key reads as nil")

GameVersion.set(prevVersion)
T.finish("game3_font_provider_test")

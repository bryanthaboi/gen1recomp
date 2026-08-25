-- Crystal's boot copyright card is white text on black: SplashScreen sets
-- SCGB_GAMEFREAK_LOGO before calling Copyright, so the card runs on
-- PREDEFPAL_GAMEFREAK_LOGO_BG rather than the default BGP Gold's DMG boot
-- leaves up (../pokecrystal/engine/movie/splash.asm:21-30).  The card used to
-- hardcode a white fill and Crystal shipped no extracted splash at all, so the
-- first screen of the game was blank white.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local CopyrightSplash = require("src.ui.gen2.CopyrightSplash")

local function colorsEq(got, want, message)
  T.eq(#got, 3, message .. " (three channels)")
  for index = 1, 3 do
    T.eq(got[index], want[index], message .. " channel " .. index)
  end
end

local gold = CopyrightSplash.new({}, { title = {} })
colorsEq(gold.backdrop, { 1, 1, 1 }, "Gold keeps the white card")
colorsEq(gold.ink, { 0, 0, 0 }, "Gold keeps black text")

local crystal = CopyrightSplash.new({}, {
  title = {
    copyrightBackdrop = { 0, 0, 0 },
    copyrightInk = { 1, 1, 1 },
  },
})
colorsEq(crystal.backdrop, { 0, 0, 0 }, "Crystal's card is black")
colorsEq(crystal.ink, { 1, 1, 1 }, "Crystal's text is white")

-- The extractor has to emit the image too, or the card is an empty backdrop.
local CrystalMovie = require("src.import.CrystalMovie")
T.eq(type(CrystalMovie.extractTitle), "function",
  "CrystalMovie still owns the Crystal title stage")

local CacheContract = require("src.import.CacheContract")
local required = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.crystal
local found = false
for _, path in ipairs(required) do
  if path == "assets/generated/title/copyright_splash.png" then found = true end
end
T.eq(found, true, "a Crystal cache without the splash is rebuilt")

T.finish("copyright splash backdrop")

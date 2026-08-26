package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("yellow title palette")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local TitleState = require("src.ui.TitleState")

GameVersion.set("yellow")
local prevMode = PaletteFX.mode

-- Test 1: SGB mode
PaletteFX.setMode("gbc")
local mewmonSgb = PaletteFX.pal(nil, "MEWMON")
check(mewmonSgb ~= nil, "MEWMON palette exists in SGB mode on Yellow")
-- In Yellow SGB SuperPalettes: MEWMON color 1 is Yellow {255, 247, 181}, color 2 is Red {222, 132, 132}
eq(mewmonSgb[1][1], 255, "SGB: Color 0 is white R=255")
eq(mewmonSgb[2][1], 255, "SGB: Color 1 is yellow R=255")
eq(mewmonSgb[3][1], 222, "SGB: Color 2 is red R=222")

-- Test 2: ADVANCED mode (redpp)
PaletteFX.setMode("redpp")
local mewmonAdv = PaletteFX.pal(nil, "MEWMON")
check(mewmonAdv ~= nil, "MEWMON palette exists in ADVANCED mode on Yellow")
-- Must NOT be Red++'s Mew purple {115, 33, 165}! It must be Yellow's Pikachu palette!
eq(mewmonAdv[1][1], 255, "ADVANCED: Color 0 is white R=255 (Pikachu eye sclera)")
eq(mewmonAdv[2][1], 255, "ADVANCED: Color 1 is yellow R=255 (Pikachu body)")
check(mewmonAdv[3][3] < 150, "ADVANCED: Color 2 is not purple (B < 150, red cheeks)")

-- Test 3: OG YELLOW mode (ogred on Yellow)
PaletteFX.setMode("ogred")
local mewmonOg = PaletteFX.pal(nil, "MEWMON")
check(mewmonOg ~= nil, "MEWMON palette exists in OG YELLOW mode")
eq(mewmonOg[1][1], 255, "OG YELLOW: Color 0 is white")
eq(mewmonOg[2][1], 255, "OG YELLOW: Color 1 is yellow")

-- Test 4: TitleState sgbPalettes
local fakeGame = { data = { palettes = PaletteFX.yellowPack() } }
local ts = { yellowLayout = true }
local zones = TitleState.sgbPalettes(ts, fakeGame)
check(zones ~= nil and #zones >= 3, "TitleState produces zones for Yellow")
eq(zones[1].colors, PaletteFX.pal(fakeGame.data, "LOGO2"), "Zone 1 uses LOGO2")
eq(zones[2].colors, PaletteFX.pal(fakeGame.data, "MEWMON"), "Zone 2 uses MEWMON (Pikachu yellow/red)")

PaletteFX.setMode(prevMode)
GameVersion.set("red")

S.finish()

#!/usr/bin/env luajit
-- The save window prints its stat values in one column. A translated label
-- can be wider than the English one ("DUREE JEU", "SPIELZEIT"), and the
-- column has to start past it instead of drawing over it.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local FrlgFont = require("src.ui.game3.frlg_font")
local SaveMenu = require("src.ui.game3.save_menu")

-- Widths as the FireRed ROM font gives them (sFontNormalLatinGlyphWidths).
local WIDTHS = {
  PLAYER = 36, BADGES = 36, ["POKéDEX"] = 42, TIME = 24,
  JOUEUR = 36, SPIELER = 42, ["DUREE JEU"] = 54, SPIELZEIT = 54,
}
FrlgFont.measure = function(text) return assert(WIDTHS[text], text) end

check(SaveMenu.valueX({ "PLAYER", "BADGES", "POKéDEX", "TIME" }) == 56,
  "English labels keep pret's value column")
check(SaveMenu.valueX({ "JOUEUR", "BADGES", "POKéDEX", "DUREE JEU" }) == 4 + 54 + 10,
  "a wider translated label pushes the column past it, with the English gap")
check(SaveMenu.valueX({ "SPIELER", "BADGES", "POKéDEX", "SPIELZEIT" }) == 4 + 54 + 10,
  "German's play time label pushes it too")
check(SaveMenu.valueX({ "SPIELER", "BADGES", "POKéDEX", "TIME" }) == 56,
  "a translated label that still fits leaves the column where it is")

print(("game3_save_menu_layout_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end

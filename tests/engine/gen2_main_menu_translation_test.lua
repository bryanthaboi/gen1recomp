-- Gold's title/main menu (src/ui/gen2/MainMenu.lua) drew every row label
-- (CONTINUE/NEW GAME/OPTION/EXIT GAME), the clock box's AM/PM half, and the
-- CONTINUE save-summary panel's labels (PLAYER <name>/BADGES/POKéDEX/TIME,
-- or NO SAVE FILE) as bare literals, invisible to a translation mod's
-- `strings` registry -- unlike the Gen 1 port's own title menu
-- (src/ui/TitleState.lua/StartMenu.lua), which already routes the same rows
-- through Strings(). Drives MainMenu:drawPanel()/:drawSavePanel() with a
-- mod-loaded Strings catalog and checks the translated text reaches
-- Font.draw, same technique as
-- tests/engine/gen2_naming_screen_translation_test.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local drawn
package.loaded["src.render.Font"] = {
  draw = function(text, x, y)
    drawn[#drawn + 1] = { text = text, x = x, y = y }
  end,
  drawCode = function() end,
  drawBox = function() end,
  width = function() return 0 end,
}

local MainMenu = require("src.ui.gen2.MainMenu")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua).
-- List item 1 lands at (self.x, self.y) = (2, 2); the clock box's day name
-- at (1, 14) and the hour:minute half at (4, 16); the save panel's PLAYER
-- row at (5, 2).
local FIRST_ITEM_X, FIRST_ITEM_Y = 2 * 8, 2 * 8
local CLOCK_HALF_X, CLOCK_HALF_Y = 4 * 8, 16 * 8
local PANEL_PLAYER_X, PANEL_PLAYER_Y = 5 * 8, 2 * 8

local SAVE = { player = { name = "GOLD" } }
local CLOCK = { hour = 13, minute = 5, weekday = 1 } -- 1 PM, SUNDAY

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = MainMenu.new({}, { hasSave = true, save = SAVE, clock = CLOCK })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(FIRST_ITEM_X, FIRST_ITEM_Y), "CONTINUE",
    "the title menu's first row draws in English with no mod loaded")
  T.eq(drawnAt(CLOCK_HALF_X, CLOCK_HALF_Y), " 1:05 PM",
    "and the clock box's AM/PM half")

  drawn = {}
  menu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "PLAYER GOLD",
    "the CONTINUE save-summary panel too")

  local noSaveMenu = MainMenu.new({}, { hasSave = false, save = false, clock = CLOCK })
  drawn = {}
  noSaveMenu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "NO SAVE FILE",
    "and its no-summary fallback")
end

-- ------------------------------------------------- a translation mod's turn
do
  Strings.load({
    strings = {
      ["CONTINUE"] = "CONTINUAR",
      ["NEW GAME"] = "NUEVA PARTIDA",
      ["OPTION"] = "OPCIÓN",
      ["EXIT GAME"] = "SALIR",
      ["PM"] = "PM_ES",
      ["PLAYER %s"] = "JUGADOR %s",
      ["BADGES"] = "MEDALLAS",
      ["POKéDEX"] = "POKéDEX_ES",
      ["TIME"] = "TIEMPO",
      ["NO SAVE FILE"] = "SIN PARTIDA",
    },
  })

  local menu = MainMenu.new({}, { hasSave = true, save = SAVE, clock = CLOCK })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(FIRST_ITEM_X, FIRST_ITEM_Y), "CONTINUAR",
    "a mod catalog reaches the title menu's first row")
  T.eq(drawnAt(CLOCK_HALF_X, CLOCK_HALF_Y), " 1:05 PM_ES",
    "and the clock box's AM/PM half")

  drawn = {}
  menu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "JUGADOR GOLD",
    "the save-summary panel's PLAYER row takes the mod's own word order")
  T.eq(drawnAt(5 * 8, 4 * 8), "MEDALLAS", "and BADGES")
  T.eq(drawnAt(5 * 8, 6 * 8), "POKéDEX_ES", "and POKéDEX")
  T.eq(drawnAt(5 * 8, 8 * 8), "TIEMPO", "and TIME")

  local noSaveMenu = MainMenu.new({}, { hasSave = false, save = false, clock = CLOCK })
  drawn = {}
  noSaveMenu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "SIN PARTIDA",
    "and the no-summary fallback")

  -- Module state is process-global (see tests/gen2_clock_test.lua's own
  -- note); this suite gets its own process from tests/tier_runner.lua, but
  -- leaving the catalog loaded past this point would still mistranslate
  -- every check below it in this file.
  Strings.load({})
  T.check(not Strings.active(), "the catalog is unloaded for the checks after this one")
end

T.finish("gen2_main_menu_translation_test")

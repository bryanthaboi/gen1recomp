-- engine/menus/main_menu.asm:67 MainMenu.Strings,
-- engine/menus/intro_menu.asm:409 Continue_LoadMenuHeader
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
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_c")
local CART = { text = Fixture.text() }

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua).
-- List item 1 lands at (self.x, self.y) = (2, 2); the clock box's day name
-- (5, 10) -- ../pokecrystal/engine/menus/intro_menu.asm:487 offsets it by (4,8).
local FIRST_ITEM_X, FIRST_ITEM_Y = 2 * 8, 2 * 8
local CLOCK_HALF_X, CLOCK_HALF_Y = 4 * 8, 16 * 8
local PANEL_PLAYER_X, PANEL_PLAYER_Y = 5 * 8, 10 * 8

local SAVE = { player = { name = "GOLD" } }
local CLOCK = { hour = 13, minute = 5, weekday = 1 }

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = MainMenu.new({ data = CART }, { hasSave = true, save = SAVE, clock = CLOCK })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(FIRST_ITEM_X, FIRST_ITEM_Y), "CONTINUE",
    "the title menu's first row draws in English with no mod loaded")
  T.eq(drawnAt(CLOCK_HALF_X, CLOCK_HALF_Y), "DAY 1:05",
    "and the clock box's time-of-day word")

  drawn = {}
  menu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "PLAYER GOLD",
    "the CONTINUE save-summary panel too")

  local noSaveMenu = MainMenu.new({ data = CART }, { hasSave = false, save = false,
    clock = CLOCK })
  drawn = {}
  noSaveMenu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "NO SAVE FILE",
    "and its no-summary fallback")
end

do
  local localized = { text = Fixture.text({
    ["MainMenu.Strings#1"] = "CONTINUAR",
    ["MainMenu.Strings#2"] = "NUEVA PARTIDA",
    ["MainMenu.Strings#3"] = "OPCIÓN",
    ["GetTimeOfDayString.day_string"] = "DIA_ES",
    ["Continue_LoadMenuHeader.MenuData_NoDex#1"] = "JUGADOR {PLAYER}",
    ["Continue_LoadMenuHeader.MenuData_Dex#2"] = "MEDALLAS",
    ["Continue_LoadMenuHeader.MenuData_Dex#3"] = "POKéDEX_ES",
    ["Continue_LoadMenuHeader.MenuData_Dex#4"] = "TIEMPO",
  }) }
  Strings.load({
    strings = {
      ["EXIT GAME"] = "SALIR",
      ["NO SAVE FILE"] = "SIN PARTIDA",
    },
  })

  local menu = MainMenu.new({ data = localized }, { hasSave = true, save = SAVE, clock = CLOCK })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(FIRST_ITEM_X, FIRST_ITEM_Y), "CONTINUAR",
    "a mod catalog reaches the title menu's first row")
  T.eq(drawnAt(CLOCK_HALF_X, CLOCK_HALF_Y), "DIA_ES 1:05",
    "and the clock box's time-of-day word")

  drawn = {}
  menu:drawSavePanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "JUGADOR GOLD",
    "the save-summary panel's PLAYER row takes the mod's own word order")
  T.eq(drawnAt(5 * 8, 12 * 8), "MEDALLAS", "and BADGES")
  T.eq(drawnAt(5 * 8, 14 * 8), "POKéDEX_ES", "and POKéDEX")
  T.eq(drawnAt(5 * 8, 16 * 8), "TIEMPO", "and TIME")

  local noSaveMenu = MainMenu.new({ data = localized }, { hasSave = false, save = false,
    clock = CLOCK })
  T.eq(noSaveMenu.list.items[3].label, "SALIR", "the port's EXIT GAME row stays a catalog string")
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
  T.raises(function()
    MainMenu.new({ data = { text = Fixture.without("MainMenu.Strings#1") } },
      { hasSave = true, save = SAVE, clock = CLOCK })
  end, "MainMenu.Strings#1", "a cache without the CONTINUE label is an error")
end

T.finish("gen2_main_menu_translation_test")

-- Gold's naming/keyboard screen (src/ui/gen2/NamingScreen.lua) had zero
-- Strings() calls: every prompt (YOUR NAME?/RIVAL'S NAME?/MOTHER'S NAME?/
-- BOX NAME?/NICKNAME?), the on-screen keyboard's own letters, and the
-- lower/UPPER/DEL/END bottom-row labels were bare literals, invisible to a
-- translation mod's `strings` registry (reported against a real Gold build,
-- gen1recomp#1642). The Gen 1 naming screen (src/ui/NamingScreen.lua) already
-- routes its title and every keyboard cell through Strings().
--
-- GbcPalette.available() is false headless (no real shader compiles), so
-- Chrome.printThrough already falls back to the plain, unshaded Chrome.print
-- -- this drives that path directly and checks the translated text reaches
-- Font.draw, the same technique
-- tests/engine/gen2_options_menu_translation_test.lua uses for the OPTION
-- screen.
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
}

local NamingScreen = require("src.ui.gen2.NamingScreen")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua);
-- the prompt lands at tile (5, 2), the keyboard's first cell at (2, 8).
local PROMPT_X, PROMPT_Y = 5 * 8, 2 * 8
local FIRST_CELL_X, FIRST_CELL_Y = 2 * 8, 8 * 8

-- ---------------------------------------------- vanilla: no mod catalog
do
  local screen = NamingScreen.new({}, { type = "player" })
  drawn = {}
  screen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "YOUR NAME?",
    "the player-name prompt draws in English with no mod loaded")
  T.eq(drawnAt(FIRST_CELL_X, FIRST_CELL_Y), "A",
    "and the keyboard's first cell too")
end

-- ------------------------------------------------- a translation mod's turn
do
  Strings.load({
    strings = {
      ["YOUR NAME?"] = "TON NOM?",
      ["A"] = "À",
      ["lower"] = "minusc",
      ["END"] = "FIN",
      ["%s'S"] = "DE %s",
      ["NICKNAME?"] = "SURNOM?",
    },
  })

  local screen = NamingScreen.new({}, { type = "player" })
  drawn = {}
  screen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "TON NOM?",
    "a mod catalog reaches the prompt")
  T.eq(drawnAt(FIRST_CELL_X, FIRST_CELL_Y), "À",
    "and a keyboard cell")

  -- The bottom row: lower/DEL/END at tile y = keyboardTop + bottom*2.
  local bottomY = (screen:keyboardTop() + screen:bottomRow() * 2) * 8
  T.eq(drawnAt(2 * 8, bottomY), "minusc", "the case-switch label is translated")
  T.eq(drawnAt(15 * 8, bottomY), "FIN", "and END, the way out of the screen")

  -- The nickname header: two lines, the mon name folded into the first.
  local nickScreen = NamingScreen.new({}, { type = "nickname", monName = "BULBASAUR" })
  drawn = {}
  nickScreen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "DE BULBASAUR",
    "the nickname header's first line takes the mod's own word order")
  T.eq(drawnAt(PROMPT_X, 4 * 8), "SURNOM?", "and its second line")

  -- Module state is process-global (see tests/gen2_clock_test.lua's own
  -- note); this suite gets its own process from tests/tier_runner.lua, but
  -- leaving the catalog loaded past this point would still mistranslate
  -- every check below it in this file.
  Strings.load({})
  T.check(not Strings.active(), "the catalog is unloaded for the checks after this one")
end

T.finish("gen2_naming_screen_translation_test")

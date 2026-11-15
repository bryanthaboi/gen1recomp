-- engine/menus/naming_screen.asm:119-181, data/text/name_input_chars.asm:3-31
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
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_c")

local function namingGame(text)
  return { data = require("tests.fixtures.gen2_naming").fill({ text = text or Fixture.text() }) }
end

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
  local screen = NamingScreen.new(namingGame(), { type = "player" })
  drawn = {}
  screen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "YOUR NAME?",
    "the player-name prompt draws in English with no mod loaded")
  T.eq(drawnAt(FIRST_CELL_X, FIRST_CELL_Y), "A",
    "and the keyboard's first cell too")
end

do
  local localized = Fixture.text({
    ["NamingScreenJumptable.PlayerNameString"] = "TON NOM?",
    ["NamingScreenJumptable.NicknameStrings#1"] = "_FR",
    ["NamingScreenJumptable.NicknameStrings#2"] = "SURNOM?",
    ["NameInputUpper#1"] = "À B C D E F G H I",
    ["NameInputUpper#5"] = "minus  DEL   FIN ",
  })

  local screen = NamingScreen.new(namingGame(localized), { type = "player" })
  drawn = {}
  screen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "TON NOM?",
    "the cache's .PlayerNameString is the prompt")
  T.eq(drawnAt(FIRST_CELL_X, FIRST_CELL_Y), "À",
    "and NameInputUpper#1 the first keyboard row")

  -- The bottom row: lower/DEL/END at tile y = keyboardTop + bottom*2.
  local bottomY = (screen:keyboardTop() + screen:bottomRow() * 2) * 8
  T.eq(drawnAt(2 * 8, bottomY), "minus", "the case-switch label is NameInputUpper#5's")
  T.eq(drawnAt(15 * 8, bottomY), "FIN", "and END sits where that row puts it")

  -- engine/menus/naming_screen.asm:97-106
  local nickScreen = NamingScreen.new(namingGame(localized),
    { type = "nickname", monName = "BULBASAUR" })
  drawn = {}
  nickScreen:drawPanel()
  T.eq(drawnAt(PROMPT_X, PROMPT_Y), "BULBASAUR_FR",
    "the nickname header's first line is the name then .NicknameStrings#1")
  T.eq(drawnAt(PROMPT_X, 4 * 8), "SURNOM?", "and its second line #2")

  T.raises(function()
    NamingScreen.new(namingGame(Fixture.without("NameInputUpper#5")), { type = "player" })
  end, "NameInputUpper#5", "a cache without the bottom row is an error")
  T.raises(function()
    NamingScreen.new(namingGame(Fixture.without("NamingScreenJumptable.PlayerNameString")),
      { type = "player" })
  end, "PlayerNameString", "a cache without the prompt is an error")
end

T.finish("gen2_naming_screen_translation_test")

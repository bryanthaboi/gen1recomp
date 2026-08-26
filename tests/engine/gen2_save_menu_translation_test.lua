-- Gold's SAVE screen (src/ui/gen2/SaveMenu.lua) drew every prompt ("Would
-- you like to save the game?", the overwrite/saving/saved messages), the
-- YES/NO choice, and the summary panel's labels (PLAYER <name>/BADGES/
-- POKéDEX/TIME) as bare literals, invisible to a translation mod's
-- `strings` registry -- unlike the Gen 1 port's own SAVE screen
-- (src/ui/StartMenu.lua), which already routes the same rows through
-- Strings(). Drives SaveMenu:drawPanel() directly at each phase with a
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

local SaveMenu = require("src.ui.gen2.SaveMenu")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua).
-- PLAYER row at (5, 2); the two prompt lines at (1, 14)/(1, 16); YES/NO at
-- (2, 8)/(2, 10) (YESNO_X + 2, YESNO_Y + 1 / + 3).
local PANEL_PLAYER_X, PANEL_PLAYER_Y = 5 * 8, 2 * 8
local PROMPT1_X, PROMPT1_Y = 1 * 8, 14 * 8
local PROMPT2_X, PROMPT2_Y = 1 * 8, 16 * 8
local YES_X, YES_Y = 2 * 8, 8 * 8
local NO_X, NO_Y = 2 * 8, 10 * 8

local SAVE = { player = { name = "GOLD" } }

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = SaveMenu.new({}, { save = SAVE, existed = false })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "PLAYER GOLD",
    "the summary panel draws in English with no mod loaded")
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Would you like to",
    "and the confirm prompt's first line")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "save the game?", "and its second line")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NO", "and NO")

  menu.phase = "overwrite"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "There is already a", "the overwrite prompt")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "save file. Is it", "its second line")

  menu.phase = "saving"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "SAVING… DON'T TURN", "the saving message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "OFF THE POWER.", "its second line")

  menu.phase, menu.saved = "done", true
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "GOLD saved", "the saved message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "the game.", "its second line")

  menu.phase, menu.saved = "done", false
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Could not save.", "the failed-save message")
end

-- ------------------------------------------------- a translation mod's turn
do
  Strings.load({
    strings = {
      ["PLAYER %s"] = "JOUEUR %s",
      ["BADGES"] = "BADGES_FR",
      ["POKéDEX"] = "POKéDEX_FR",
      ["TIME"] = "TEMPS",
      ["YES"] = "OUI",
      ["NO"] = "NON",
      ["Would you like to\nsave the game?"] = "Voulez-vous\nsauvegarder ?",
      ["There is already a\nsave file. Is it"] = "Un fichier existe\ndeja. Est-ce",
      ["SAVING… DON'T TURN\nOFF THE POWER."] = "SAUVEGARDE...\nN'ETEIGNEZ PAS.",
      ["%s saved\nthe game."] = "%s a sauvegarde\nla partie.",
      ["Could not save."] = "Echec de sauvegarde.",
    },
  })

  local menu = SaveMenu.new({}, { save = SAVE, existed = false })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PANEL_PLAYER_X, PANEL_PLAYER_Y), "JOUEUR GOLD",
    "the summary panel's PLAYER row takes the mod's own word order")
  T.eq(drawnAt(5 * 8, 4 * 8), "BADGES_FR", "and BADGES")
  T.eq(drawnAt(5 * 8, 6 * 8), "POKéDEX_FR", "and POKéDEX")
  T.eq(drawnAt(5 * 8, 8 * 8), "TEMPS", "and TIME")
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Voulez-vous", "the confirm prompt")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "sauvegarder ?", "its second line")
  T.eq(drawnAt(YES_X, YES_Y), "OUI", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NON", "and NO")

  menu.phase = "overwrite"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Un fichier existe", "the overwrite prompt")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "deja. Est-ce", "its second line")

  menu.phase = "saving"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "SAUVEGARDE...", "the saving message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "N'ETEIGNEZ PAS.", "its second line")

  menu.phase, menu.saved = "done", true
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "GOLD a sauvegarde",
    "the saved message folds the player name into the mod's own word order")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "la partie.", "its second line")

  menu.phase, menu.saved = "done", false
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Echec de sauvegarde.", "the failed-save message")

  -- Module state is process-global (see tests/gen2_clock_test.lua's own
  -- note); this suite gets its own process from tests/tier_runner.lua, but
  -- leaving the catalog loaded past this point would still mistranslate
  -- every check below it in this file.
  Strings.load({})
  T.check(not Strings.active(), "the catalog is unloaded for the checks after this one")
end

-- src/ui/gen2/PcMenu.lua:savePrompt() shares SaveMenu's overwrite/saving
-- prompts through SaveMenu.OVERWRITE_PROMPT_SOURCE/SAVING_PROMPT_SOURCE and
-- SaveMenu.twoLines(), rather than duplicating them -- both exported below,
-- both used by PcMenu's own translation test
-- (tests/engine/gen2_pcmenu_changebox_save_translation_test.lua). Checked
-- here that they stay callable the shape twoLines() expects: a table in,
-- one \n-joined string out with the split back on load.
do
  T.eq(SaveMenu.OVERWRITE_PROMPT_SOURCE, "There is already a\nsave file. Is it",
    "OVERWRITE_PROMPT_SOURCE stays the cart's own \\n-joined text")
  T.eq(SaveMenu.twoLines(Strings(SaveMenu.OVERWRITE_PROMPT_SOURCE))[1], "There is already a",
    "and twoLines() splits its untranslated fallback back to the first line")
  T.eq(SaveMenu.twoLines(Strings(SaveMenu.OVERWRITE_PROMPT_SOURCE))[2], "save file. Is it",
    "and its second line")
  T.eq(SaveMenu.SAVING_PROMPT_SOURCE, "SAVING… DON'T TURN\nOFF THE POWER.",
    "SAVING_PROMPT_SOURCE stays the cart's own \\n-joined text")
  T.eq(SaveMenu.twoLines(Strings(SaveMenu.SAVING_PROMPT_SOURCE))[1], "SAVING… DON'T TURN",
    "and twoLines() splits its untranslated fallback back to the first line")
  T.eq(SaveMenu.twoLines(Strings(SaveMenu.SAVING_PROMPT_SOURCE))[2], "OFF THE POWER.",
    "and its second line")
end

-- A translation with a THIRD line (a second embedded "\n") has nowhere on
-- screen to go -- drawPanel's box has room for exactly two Chrome.print
-- calls -- so it must not silently draw the literal newline byte as glyph
-- garbage on the second line, and should warn so a translator notices.
do
  Strings.load({
    strings = {
      ["Would you like to\nsave the game?"] = "Ligne un\nLigne deux\nLigne trois",
    },
  })

  local warned = {}
  require("src.core.Logger").warn = function(fmt, ...)
    warned[#warned + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
  end

  local menu = SaveMenu.new({}, { save = SAVE, existed = false })
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Ligne un", "only the first line reaches the box")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "Ligne deux\nLigne trois",
    "the rest lands in the second slot rather than vanishing")
  T.check(#warned == 1, "and a single warning is logged")

  drawn = {}
  menu:drawPanel()
  T.check(#warned == 1, "the warning does not repeat for the same text")

  require("src.core.Logger").warn = function() end
  Strings.load({})
end

T.finish("gen2_save_menu_translation_test")

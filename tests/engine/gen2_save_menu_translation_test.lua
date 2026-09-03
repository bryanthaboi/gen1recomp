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
local Typer = require("src.ui.gen2.Typer")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

local function typeOut(menu)
  for _ = 1, 600 do
    menu:update(0)
    if menu.typer and menu.typer:done() then return end
  end
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
  typeOut(menu)
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
      ["There is already a\nsave file. Is it\vOK to overwrite?"] = "Un fichier existe\ndeja. Est-ce\vOK pour ecraser?",
      ["SAVING… DON'T TURN\nOFF THE POWER."] = "SAUVEGARDE...\nN'ETEIGNEZ PAS.",
      ["%s saved\nthe game."] = "%s a sauvegarde\nla partie.",
      ["Could not save."] = "Echec de sauvegarde.",
    },
  })

  local menu = SaveMenu.new({}, { save = SAVE, existed = false })
  typeOut(menu)
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

-- src/ui/gen2/PcMenu.lua:savePages() shares SaveMenu's overwrite/saving
-- prompts through SaveMenu.OVERWRITE_PROMPT_SOURCE/SAVING_PROMPT_SOURCE and
-- SaveMenu.pagesOf(), rather than duplicating them -- both exported below,
-- both used by PcMenu's own translation test
-- (tests/engine/gen2_pcmenu_changebox_save_translation_test.lua). Checked
-- here that they stay callable the shape pagesOf() expects: one
-- \n/\v-joined string in, a list of two-line pages out.
-- ../pokecrystal/data/text/common_3.asm:202 _AlreadyASaveFileText
do
  T.eq(SaveMenu.OVERWRITE_PROMPT_SOURCE,
    "There is already a\nsave file. Is it\vOK to overwrite?",
    "OVERWRITE_PROMPT_SOURCE is the cart's whole text, cont line included")
  local pages = SaveMenu.pagesOf(Strings(SaveMenu.OVERWRITE_PROMPT_SOURCE))
  T.eq(#pages, 2, "and pagesOf() turns the cont into a second page")
  T.eq(pages[1][1], "There is already a", "page one, first line")
  T.eq(pages[1][2], "save file. Is it", "page one, second line")
  T.eq(pages[2][1], "save file. Is it", "page two scrolls the old second line up")
  T.eq(pages[2][2], "OK to overwrite?", "and prints the cont line under it")
  T.eq(SaveMenu.SAVING_PROMPT_SOURCE, "SAVING… DON'T TURN\nOFF THE POWER.",
    "SAVING_PROMPT_SOURCE stays the cart's own \\n-joined text")
  pages = SaveMenu.pagesOf(Strings(SaveMenu.SAVING_PROMPT_SOURCE))
  T.eq(#pages, 1, "a \\n-only message is a single page")
  T.eq(pages[1][1], "SAVING… DON'T TURN", "with its first line")
  T.eq(pages[1][2], "OFF THE POWER.", "and its second line")
  T.eq(SaveMenu.pagesOf("Could not save.")[1][2], nil,
    "a one-line message leaves the second slot empty")
end

-- ../pokecrystal/engine/menus/save.asm:209 SaveTheGame_yesorno
local ARROW_X, ARROW_Y = 18 * 8, 17 * 8
local function newInput()
  local input = { pressed = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

do
  local input = newInput()
  local menu = SaveMenu.new({ input = input }, { save = SAVE, existed = true })
  typeOut(menu)
  input:press("a")
  menu:update(0)
  T.eq(menu.phase, "overwrite", "YES on an existing file asks to overwrite")
  typeOut(menu)
  menu.arrowBlink = 0
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "There is already a", "page one, first line")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "save file. Is it", "page one, second line")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES on page one")
  T.eq(drawnAt(ARROW_X, ARROW_Y), "\xe2\x96\xbc", "the cont arrow blinks at (18,17)")

  input:press("a")
  menu:update(0)
  T.eq(menu.page, 2, "A turns to the cont page")

  -- ../pokecrystal/home/text.asm:520 _ContTextNoPause
  T.check(menu.pages[2].scrolled, "the cont page is tagged scrolled")
  T.eq(menu.pages[2][1], menu.pages[1][2], "its first row is page one's second line")
  T.eq(menu.typer.shown, #"save file. Is it",
    "the typer starts past the scrolled line, on the second row")
  T.eq(menu.typer.total, #"save file. Is it" + #"OK to overwrite?",
    "with only the cont line left to type")
  T.check(Typer.typing(menu), "so the cont line is still typing")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "save file. Is it",
    "the scrolled line is whole before a single tick")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y) or "", "", "and the cont row is empty")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES while the cont line types")
  for _ = 1, Typer.DELAYS.MID do menu:update(0) end
  T.eq(menu.typer.shown, #"save file. Is it" + 1,
    "the first letter delay prints the cont line's first letter")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "save file. Is it", "the scrolled line stays whole")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "O", "and the cont row types from its first letter")

  typeOut(menu)
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "save file. Is it", "page two scrolls the second line up")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "OK to overwrite?", "and prints the cont line")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "YES is up on the last page")
  T.eq(drawnAt(NO_X, NO_Y), "NO", "and NO")
  T.eq(drawnAt(ARROW_X, ARROW_Y), nil, "and the arrow is gone")
end

do
  Strings.load({
    strings = {
      ["There is already a\nsave file. Is it\vOK to overwrite?"] = "Ecraser la\nsauvegarde?",
    },
  })
  local input = newInput()
  local menu = SaveMenu.new({ input = input }, { save = SAVE, existed = true })
  typeOut(menu)
  input:press("a")
  menu:update(0)
  typeOut(menu)
  T.eq(#menu.pages, 1, "a translation without \\v is one page")
  T.check(menu:yesNoVisible(), "and its YES/NO goes straight up")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Ecraser la", "the translated first line")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "sauvegarde?", "and second")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "with YES drawn")
  Strings.load({})
end

do
  Strings.load({
    strings = {
      ["Would you like to\nsave the game?"] = "Ligne un\nLigne deux\nLigne trois",
    },
  })

  local input = newInput()
  local menu = SaveMenu.new({ input = input }, { save = SAVE, existed = false })
  typeOut(menu)
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Ligne un", "the first line reaches the box")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "Ligne deux", "and the second, without the third")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES while a page is still to come")

  input:press("a")
  menu:update(0)
  typeOut(menu)
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Ligne trois", "the third line gets its own page")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y) or "", "", "with an empty second slot")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "and YES on the last page")

  Strings.load({})
end

T.finish("gen2_save_menu_translation_test")

-- The PC's CHANGE BOX save flow (src/ui/gen2/PcMenu.lua:savePrompt()) used to
-- draw its overwrite/saving/done prompts and its YES/NO choice as bare
-- literals, invisible to a translation mod's `strings` registry, even though
-- the overwrite/saving prompts are the exact same two cart messages Gold's
-- SAVE screen (src/ui/gen2/SaveMenu.lua) already routes through Strings().
-- Same technique as tests/engine/gen2_save_menu_translation_test.lua: drives
-- PcMenu:drawPanel() directly at each save phase with a mod-loaded Strings
-- catalog and checks the translated text reaches Font.draw.
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

local PcMenu = require("src.ui.gen2.PcMenu")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua).
-- The save-prompt box sits at the same (0,12) origin SaveMenu.lua's does, so
-- its two lines print at the same (1,14)/(1,16); PcMenu's own YESNO_X/Y
-- (14,7) differ from SaveMenu's (0,7), so YES/NO print at (16,8)/(16,10).
local PROMPT1_X, PROMPT1_Y = 1 * 8, 14 * 8
local PROMPT2_X, PROMPT2_Y = 1 * 8, 16 * 8
local YES_X, YES_Y = 16 * 8, 8 * 8
local NO_X, NO_Y = 16 * 8, 10 * 8

-- One party mon so Boxes.canUsePc doesn't refuse to open the PC at all.
local SAVE = { player = { name = "GOLD" }, party = { {} } }

local function newMenu()
  return PcMenu.new({}, {
    save = SAVE,
    saveExists = false,
    writer = function() return true end,
  })
end

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = newMenu()
  menu.picking = true
  menu.pickIndex = 1
  menu.savePhase = "confirm"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "#MON BOX, data", "the confirm prompt draws in English with no mod loaded")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "will be saved. OK?", "and its second line")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NO", "and NO")

  menu.savePhase = "overwrite"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "There is already a",
    "the overwrite prompt, the same cart message SaveMenu.lua's SAVE screen shares")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "save file. Is it", "its second line")

  menu.savePhase = "saving"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "SAVING… DON'T TURN", "the saving message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "OFF THE POWER.", "its second line")

  menu.savePhase, menu.saved = "done", true
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "GOLD saved", "the saved message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "the game.", "its second line")

  menu.savePhase, menu.saved = "done", false
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Could not save.", "the failed-save message")
end

-- ------------------------------------------------- a translation mod's turn
--
-- Same catalog values as gen2_save_menu_translation_test.lua's own
-- translated block: the overwrite/saving prompts, the saved/failed messages,
-- and YES/NO are the exact same keys both screens read, so one translation
-- covers both without a PcMenu-specific fork. Only the CHANGE BOX confirm
-- prompt's key is new here.
do
  Strings.load({
    strings = {
      ["YES"] = "OUI",
      ["NO"] = "NON",
      ["#MON BOX, data\nwill be saved. OK?"] = "Les donnees de la\nBOITE seront sauv.",
      ["There is already a\nsave file. Is it"] = "Un fichier existe\ndeja. Est-ce",
      ["SAVING… DON'T TURN\nOFF THE POWER."] = "SAUVEGARDE...\nN'ETEIGNEZ PAS.",
      ["%s saved\nthe game."] = "%s a sauvegarde\nla partie.",
      ["Could not save."] = "Echec de sauvegarde.",
    },
  })

  local menu = newMenu()
  menu.picking = true
  menu.pickIndex = 1
  menu.savePhase = "confirm"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Les donnees de la", "the confirm prompt")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "BOITE seront sauv.", "its second line")
  T.eq(drawnAt(YES_X, YES_Y), "OUI", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NON", "and NO")

  menu.savePhase = "overwrite"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Un fichier existe",
    "the overwrite prompt, translated with no PcMenu-specific key")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "deja. Est-ce", "its second line")

  menu.savePhase = "saving"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "SAUVEGARDE...", "the saving message")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "N'ETEIGNEZ PAS.", "its second line")

  menu.savePhase, menu.saved = "done", true
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "GOLD a sauvegarde",
    "the saved message folds the player name into the mod's own word order")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "la partie.", "its second line")

  menu.savePhase, menu.saved = "done", false
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

T.finish("gen2_pcmenu_changebox_save_translation_test")

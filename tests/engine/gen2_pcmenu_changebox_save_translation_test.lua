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
  return input
end

local function settle(menu)
  for i = 1, 400 do
    if not (menu.typer and not menu.typer:done()) then return i - 1 end
    menu:update(0)
  end
  return 400
end

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = newMenu()
  menu.picking = true
  menu.pickIndex = 1
  menu.savePhase = "confirm"
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "When you change a", "the confirm prompt draws in English with no mod loaded")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "#MON BOX, data", "and its second line")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES before the cont page")
  menu.savePage = 2
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "#MON BOX, data", "the cont page scrolls the second line up")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "will be saved. OK?", "and prints the cont line")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NO", "and NO")
  menu.savePage = 1

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

-- ../pokecrystal/engine/menus/save.asm:39 ChangeBoxSaveGame
local ARROW_X, ARROW_Y = 18 * 8, 17 * 8
do
  local input = newInput()
  local menu = PcMenu.new({ input = input }, {
    save = SAVE,
    saveExists = true,
    writer = function() return true end,
  })
  menu.picking = true
  menu.pickIndex = 2
  menu:beginChangeBox(2)
  T.eq(menu.savePhase, "confirm", "CHANGE BOX asks to save first")
  T.check(menu.typer ~= nil and not menu.typer:done(), "and starts typing the prompt")
  T.eq(#menu:savePages(), 2, "_ChangeBoxSaveText is two pages: line, then cont")
  T.eq(menu:saveYesNoVisible(), false, "no YES/NO while it types")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "", "nothing printed before the first letter delay")
  T.eq(drawnAt(YES_X, YES_Y), nil, "and no YES box")
  for _ = 1, 6 do menu:update(0) end
  drawn = {}
  menu:drawPanel()
  local prefix = drawnAt(PROMPT1_X, PROMPT1_Y)
  T.check(prefix ~= "" and prefix ~= "When you change a"
    and ("When you change a"):sub(1, #prefix) == prefix,
    "six frames in, a prefix of the first line is up (got '" .. tostring(prefix) .. "')")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "", "and none of the second line yet")

  input:press("a")
  menu:update(0)
  T.eq(menu.savePage, 1, "A while typing does not turn the page")
  T.eq(menu.savePhase, "confirm", "nor answer")
  input.pressed = {}
  local ticks = settle(menu)
  T.check(ticks > 30, "the two-line prompt takes more than 30 frames at MID (took " .. ticks .. ")")
  T.eq(menu.savePage, 1, "page 1 once typed")
  T.eq(menu:saveYesNoVisible(), false, "still no YES/NO: the cont page waits")
  menu.arrowBlink = 0
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "When you change a", "page one, first line")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "#MON BOX, data", "page one, second line")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES on page one")
  T.eq(drawnAt(ARROW_X, ARROW_Y), "\xe2\x96\xbc", "the cont arrow blinks at (18,17)")

  input:press("a")
  menu:update(0)
  T.eq(menu.savePhase, "confirm", "A on the cont arrow turns the page rather than answering")
  T.eq(menu.savePage, 2, "to the cont page")
  T.check(menu.typer and not menu.typer:done(), "which types in turn")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "#MON BOX, data", "the scrolled line is already whole")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "", "the cont line starts empty")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES while the cont line types")
  settle(menu)
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "will be saved. OK?", "the cont line, typed")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "YES/NO goes up once it has printed")

  input:press("a")
  menu:update(0)
  T.eq(menu.savePhase, "overwrite", "YES on an existing file asks to overwrite")
  T.eq(menu.savePage, 1, "on the prompt's first page")
  T.eq(menu:saveYesNoVisible(), false, "no YES/NO while the overwrite prompt types")
  settle(menu)
  menu.arrowBlink = 0
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "There is already a", "page one, first line")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "save file. Is it", "page one, second line")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES on page one")
  T.eq(drawnAt(ARROW_X, ARROW_Y), "\xe2\x96\xbc", "the cont arrow blinks at (18,17)")

  input:press("a")
  menu:update(0)
  T.eq(menu.savePhase, "overwrite", "A turns the page rather than answering")
  T.eq(menu.savePage, 2, "to the cont page")
  settle(menu)
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "save file. Is it", "page two scrolls the second line up")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "OK to overwrite?", "and prints the cont line")
  T.eq(drawnAt(YES_X, YES_Y), "YES", "YES is up on the last page")
  T.eq(drawnAt(ARROW_X, ARROW_Y), nil, "and the arrow is gone")

  input:press("b")
  menu:update(0)
  T.eq(menu.savePhase, nil, "B on the YES/NO is NO and drops the change")
  T.eq(menu.picking, true, "with the box picker still up")
  T.eq(menu.typer, nil, "and no typer left behind for the picker")
end

-- ../pokecrystal/home/print_text.asm:1 PrintLetterDelay
-- ../pokecrystal/engine/menus/save.asm:336 SavingDontTurnOffThePower
do
  local function promptTicks(textSpeed)
    local menu = PcMenu.new({ input = newInput(), save = { options = { textSpeed = textSpeed } } }, {
      save = SAVE,
      saveExists = false,
      writer = function() return true end,
    })
    menu.picking = true
    menu.pickIndex = 2
    menu:beginChangeBox(2)
    return settle(menu), menu
  end
  local fast = promptTicks("FAST")
  local mid = promptTicks("MID")
  local slow = promptTicks("SLOW")
  T.check(fast < mid and mid < slow,
    ("the confirm prompt follows the OPTIONS text speed (%d < %d < %d)"):format(fast, mid, slow))
  T.eq(mid, fast * 3, "MID is three frames a letter to FAST's one")

  local _, menu = promptTicks("FAST")
  local input = menu.game.input
  input:press("a")
  menu:update(0)
  settle(menu)
  input:press("a")
  menu:update(0)
  T.eq(menu.savePhase, "saving", "YES with no file goes straight to SAVING")
  T.eq(menu.typer.speed, "MID", "SAVING… is pinned to MID whatever the option says")
  T.check(menu.typer and not menu.typer:done(), "and types")
  local before = menu.saveTimer
  for _ = 1, 10 do menu:update(0) end
  T.eq(menu.saveTimer, before, "the 16-frame hold does not count while the text types")
  T.eq(menu.savePhase, "saving", "so the write waits")
  settle(menu)
  for _ = 1, 16 do menu:update(0) end
  T.eq(menu.savePhase, "done", "the write lands once the message has printed and held")
  T.eq(menu.typer.speed, "MID", "'saved the game.' is pinned to MID too")
  local saveTicks = settle(menu)
  T.check(saveTicks > 0, "and types rather than appearing whole")
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "GOLD saved", "the saved message")
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
      ["When you change a\n#MON BOX, data\vwill be saved. OK?"] = "Quand vous changez\nde BOITE, donnees\vseront sauv. OK?",
      ["There is already a\nsave file. Is it\vOK to overwrite?"] = "Un fichier existe\ndeja. Est-ce\vOK pour ecraser?",
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
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "Quand vous changez", "the confirm prompt")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "de BOITE, donnees", "its second line")
  T.eq(drawnAt(YES_X, YES_Y), nil, "no YES before the translated cont page")
  menu.savePage = 2
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(PROMPT1_X, PROMPT1_Y), "de BOITE, donnees", "the cont page")
  T.eq(drawnAt(PROMPT2_X, PROMPT2_Y), "seront sauv. OK?", "its cont line")
  T.eq(drawnAt(YES_X, YES_Y), "OUI", "and YES")
  T.eq(drawnAt(NO_X, NO_Y), "NON", "and NO")
  menu.savePage = 1

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

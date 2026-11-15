-- data/text/common_2.asm:993 _StartMenuContestEndText,
-- engine/menus/menu_2.asm:154 StartMenu_PrintBugContestStatus
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
require("tests.fixture_data.gen2_engine_flags").bind("gold")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

-- Chrome.print/printWrapped go straight to Font.draw, so recording that call
-- shows exactly what reached the screen -- the technique
-- tests/engine/gen2_options_menu_translation_test.lua uses. Stubbed before
-- Chrome loads, so its own `local Font = require(...)` captures this.
local drawn
package.loaded["src.render.Font"] = {
  draw = function(text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end,
  drawCode = function() end,
  drawBox = function() end,
  width = function(text) return 8 * #tostring(text or "") end,
}

local StartMenu = require("src.ui.gen2.StartMenu")
local Specials = require("src.script.gen2.Specials")
local Strings = require("src.core.Strings")
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_c")
local CART = Fixture.text()

local function drawnText()
  local out = {}
  for _, d in ipairs(drawn) do out[#out + 1] = d.text end
  return table.concat(out, "|")
end

-- The prompt is drawn from StartMenu:draw()'s confirmContest arm; the list
-- above it is the part this suite does not care about.
local function promptText(text)
  local menu = StartMenu.new({ save = {}, data = { text = text } }, { save = {} })
  menu.phase = "confirmContest"
  menu.confirmChoice = 1
  menu.list = { draw = function() end }
  menu:beginPrompt()
  menu.typer.shown = menu.typer.total
  drawn = {}
  menu:draw()
  return drawnText()
end

-- The status box above the menu, drawn while a Contest is running. Returns
-- what reached the screen as "text@tileX" so a column can be asserted too.
local function statusBox(mon, text)
  local menu = StartMenu.new({ save = {}, data = { text = text } }, { save = {} })
  menu.contest = true
  menu.save = { bugContest = { active = true, balls = 15, caught = mon } }
  menu.list = { draw = function() end }
  drawn = {}
  menu:drawContestStatus()
  local out = {}
  for _, d in ipairs(drawn) do out[#out + 1] = d.text .. "@" .. tostring(d.x / 8) end
  return table.concat(out, "|")
end

-- StartGameCornerGame's first refusal: no coins at all.
local function coinsRefusal()
  local shown
  local vm = {
    specials = { coins = function() return 0 end,
      data = function() return { text = require("tests.fixtures.gen2_rom_text").text() } end },
    showRaw = function(_, body) shown = body end,
  }
  Specials.ALL.SlotMachine(vm)
  return shown
end

-- ------------------------------------------------ vanilla: no mod catalog
Strings.load({})
do
  local text = promptText(CART)
  T.check(text:find("Would you like to", 1, true) ~= nil,
    "the Contest prompt draws its English first line")
  T.check(text:find("end the Contest?", 1, true) ~= nil,
    "and its English second line")
  T.eq(coinsRefusal(), "You have no coins.{PROMPT}",
    "the Game Corner refusal is the cache's _NoCoinsText")

  local box = statusBox(nil, CART)
  T.check(box:find("CAUGHT@1", 1, true) ~= nil, "the status box labels draw in English")
  T.check(box:find("None@8", 1, true) ~= nil,
    "with the empty-slot placeholder in the cart's own column")
  T.check(box:find("BALLS:@1", 1, true) ~= nil, "and the ball counter's label")
end

do
  local localized = Fixture.text({
    _StartMenuContestEndText = "Voulez-vous arrê-\nter le concours?{DONE}",
    ["YesNoMenuHeader.MenuData#1"] = "OUI",
    ["YesNoMenuHeader.MenuData#2"] = "NON",
    ["StartMenu_PrintBugContestStatus.CaughtString"] = "ATTRAPE",
    ["StartMenu_PrintBugContestStatus.BallsString"] = "BALLES:",
    ["StartMenu_PrintBugContestStatus.NoneString"] = "AUCUN",
  })

  local text = promptText(localized)
  T.check(text:find("Voulez%-vous arr") ~= nil,
    "a mod catalog reaches the Contest prompt's first line")
  T.check(text:find("ter le concours?", 1, true) ~= nil,
    "and its second line, wrapped on the translated line break")
  T.check(text:find("Would you like to", 1, true) == nil,
    "with no English left on screen")
  T.eq(coinsRefusal(), "You have no coins.{PROMPT}",
    "the Game Corner refusal stays the cache's own line")

  local box = statusBox(nil, localized)
  T.check(box:find("ATTRAPE@1", 1, true) ~= nil, "the status box labels translate")
  -- ATTRAPE fills the seven tiles CAUGHT left before the cart's x=8 column,
  -- so the value moves one tile right to keep a space between them.
  T.check(box:find("AUCUN@9", 1, true) ~= nil,
    "and the placeholder starts after the label")
  T.check(not pcall(promptText, Fixture.without("_StartMenuContestEndText")),
    "a cache without the prompt is an error")
end

-- A label wider than the cart's own pushes the value right instead of being
-- drawn over by it.
do
  local box = statusBox(nil, Fixture.text({
    ["StartMenu_PrintBugContestStatus.CaughtString"] = "GEFANGEN",
    ["StartMenu_PrintBugContestStatus.BallsString"] = "BAELLE:",
    ["StartMenu_PrintBugContestStatus.NoneString"] = "KEINES",
  }))
  T.check(box:find("GEFANGEN@1", 1, true) ~= nil, "the wide label still starts at the cart's x")
  T.check(box:find("KEINES@10", 1, true) ~= nil,
    "and its value starts past it, not on top of it")
end

Strings.load({})

T.finish("gen2_contest_coins_translation_test")

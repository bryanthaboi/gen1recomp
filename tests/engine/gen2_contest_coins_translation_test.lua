-- Two Gold/Crystal texts a translation catalog could not reach.
--
-- The Bug-Catching Contest confirmation was drawn as two bare literals, one
-- per row (src/ui/gen2/StartMenu.lua), with no Strings() call at all. The
-- Game Corner's no-coins refusal (src/script/gen2/Specials.lua) was looked up
-- at runtime but its literal sat behind a plain local, so the catalog
-- harvester never saw the key and no generated catalog carried it.
--
-- This drives both draw paths with a mod-loaded catalog and checks the
-- translated text is what reaches the screen, plus the no-mod case proving
-- the English wording is unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

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

local function drawnText()
  local out = {}
  for _, d in ipairs(drawn) do out[#out + 1] = d.text end
  return table.concat(out, "|")
end

-- The prompt is drawn from StartMenu:draw()'s confirmContest arm; the list
-- above it is the part this suite does not care about.
local function promptText()
  local menu = StartMenu.new({ save = {} }, { save = {} })
  menu.phase = "confirmContest"
  menu.confirmChoice = 1
  menu.list = { draw = function() end }
  drawn = {}
  menu:draw()
  return drawnText()
end

-- The status box above the menu, drawn while a Contest is running. Returns
-- what reached the screen as "text@tileX" so a column can be asserted too.
local function statusBox(mon)
  local menu = StartMenu.new({ save = {} }, { save = {} })
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
    specials = { coins = function() return 0 end },
    showRaw = function(_, body) shown = body end,
  }
  Specials.ALL.SlotMachine(vm)
  return shown
end

-- ------------------------------------------------ vanilla: no mod catalog
Strings.load({})
do
  local text = promptText()
  T.check(text:find("Would you like to", 1, true) ~= nil,
    "the Contest prompt draws its English first line")
  T.check(text:find("end the Contest?", 1, true) ~= nil,
    "and its English second line")
  T.eq(coinsRefusal(), "You have no coins.",
    "the Game Corner refusal is unchanged in English")

  local box = statusBox(nil)
  T.check(box:find("CAUGHT@1", 1, true) ~= nil, "the status box labels draw in English")
  T.check(box:find("None@8", 1, true) ~= nil,
    "with the empty-slot placeholder in the cart's own column")
  T.check(box:find("BALLS:@1", 1, true) ~= nil, "and the ball counter's label")
end

-- ------------------------------------------------- a translation mod's turn
do
  Strings.load({
    strings = {
      -- the cart's own French wording (GoldSilver/Crystal, data/text)
      ["Would you like to\nend the Contest?"] = "Voulez-vous arrê-\nter le concours?",
      ["You have no coins."] = "Vous n'avez pas de\njetons.",
      ["YES"] = "OUI",
      ["NO"] = "NON",
      ["CAUGHT"] = "ATTRAPE",
      ["BALLS:"] = "BALLES:",
      ["contest.caught|None"] = "AUCUN",
    },
  })

  local text = promptText()
  T.check(text:find("Voulez%-vous arr") ~= nil,
    "a mod catalog reaches the Contest prompt's first line")
  T.check(text:find("ter le concours?", 1, true) ~= nil,
    "and its second line, wrapped on the translated line break")
  T.check(text:find("Would you like to", 1, true) == nil,
    "with no English left on screen")
  T.eq(coinsRefusal(), "Vous n'avez pas de\njetons.",
    "and the Game Corner refusal too")

  local box = statusBox(nil)
  T.check(box:find("ATTRAPE@1", 1, true) ~= nil, "the status box labels translate")
  -- ATTRAPE fills the seven tiles CAUGHT left before the cart's x=8 column,
  -- so the value moves one tile right to keep a space between them.
  T.check(box:find("AUCUN@9", 1, true) ~= nil,
    "and the placeholder starts after the label, with the context key applied")
end

-- A label wider than the cart's own pushes the value right instead of being
-- drawn over by it.
do
  Strings.load({ strings = { ["CAUGHT"] = "GEFANGEN", ["BALLS:"] = "BAELLE:", ["None"] = "KEINES" } })
  local box = statusBox(nil)
  T.check(box:find("GEFANGEN@1", 1, true) ~= nil, "the wide label still starts at the cart's x")
  T.check(box:find("KEINES@10", 1, true) ~= nil,
    "and its value starts past it, not on top of it")
end

Strings.load({})

T.finish("gen2_contest_coins_translation_test")

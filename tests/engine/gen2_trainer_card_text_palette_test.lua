-- TrainerCard had two palette gaps: its own text drew through flat
-- Chrome.print/cursor, fixed with a print/:cursor pair routed through
-- printThrough/cursorThrough via self:colorsAt; and drawPanel() painted
-- the screen with a flat white rectangle before anything else, leaving the
-- NAME/ID/MONEY/STATUS/BADGES interiors white, fixed by routing that fill
-- through Chrome.paletteFill.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GbcPalette = require("src.render.GbcPalette")
local TrainerCard = require("src.ui.gen2.TrainerCard")
local Strings = require("src.core.Strings")

GbcPalette.available = function() return true end
GbcPalette.setCustomRamp({ { 255, 0, 255 }, { 200, 0, 200 }, { 100, 0, 100 },
                            { 0, 0, 0 } })

local calls
local function spy(name)
  local original = GbcPalette[name]
  GbcPalette[name] = function(...)
    calls[name] = (calls[name] or 0) + 1
    return original(...)
  end
end

local function fakeCard()
  return {
    colorsAt = function() return { { 255, 255, 255 }, { 200, 0, 200 },
                                    { 100, 0, 100 }, { 0, 0, 0 } } end,
  }
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  TrainerCard.print(fakeCard(), "NAME/", 2, 2)
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "TrainerCard:print() reaches the GbcPalette seam via self:colorsAt")
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  TrainerCard.cursor(fakeCard(), 18, 15)
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "TrainerCard:cursor() reaches the GbcPalette seam via self:colorsAt")
end

-- drawPanel() painted the whole screen with a flat white rectangle before
-- drawing the card, and self:frame only draws border tiles, so panel
-- interiors stayed white regardless of the picked palette. drawCard is
-- stubbed here to isolate that base fill from the print/cursor seam
-- covered above.
do
  local fake = { styled = function() return true end, page = 1,
                 drawCard = function() end }
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  TrainerCard.drawPanel(fake)
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "TrainerCard:drawPanel()'s base fill reaches the GbcPalette seam")
end

-- engine/menus/trainer_card.asm:269 .Name_Money, :306 .Dex_PlayTime
do
  local Chrome = require("src.ui.gen2.Chrome")
  local priorPrintThrough = Chrome.printThrough
  local printed = {}
  Chrome.printThrough = function(text) printed[#printed + 1] = text end
  Strings.load({ strings = { GOLD = "INTERDIT" } })
  local card = TrainerCard.new({ data = { text = require("tests.fixture_data.gen2_rom_text_s7_c")
    .text({
      ["TrainerCard_PrintTopHalfOfCard.Name_Money"] = "NOM/\n\nARGENT",
      ["TrainerCard_Page1_PrintDexCaught_GameTime.Dex_PlayTime"] = "DEX-FR\nTEMPS",
    }) } }, {
    save = { player = { name = "GOLD", id = 7, money = 12 }, playTime = {} },
    menuGfx = { trainerCard = require("tests.fixture_data.gen2_trainer_card_s7_c").gold },
  })
  local priorQuad = love.graphics.newQuad
  love.graphics.newQuad = function(x, y, w, h)
    return { getViewport = function() return x, y, w, h end }
  end
  card:drawCard()
  love.graphics.newQuad = priorQuad
  local all = table.concat(printed, "|")
  T.check(all:find("NOM/", 1, true) and all:find("ARGENT", 1, true)
      and all:find("DEX-FR", 1, true) and all:find("TEMPS", 1, true),
    "Trainer Card's labels are the cache's .Name_Money and .Dex_PlayTime")
  T.check(all:find("GOLD", 1, true) and not all:find("INTERDIT", 1, true),
    "the player's name stays raw")
  Strings.load({})
  Chrome.printThrough = priorPrintThrough
end

do
  local text = require("tests.fixture_data.gen2_rom_text_s7_c").text()
  T.check(not pcall(TrainerCard.new, { data = { text = text } }, { save = {} }),
    "a cache without menu_gfx.trainerCard is an error")
  local partial = {}
  for k, v in pairs(require("tests.fixture_data.gen2_trainer_card_s7_c").gold) do partial[k] = v end
  partial.statusWide = nil
  T.check(not pcall(TrainerCard.new, { data = { text = text } },
    { save = {}, menuGfx = { trainerCard = partial } }),
    "and so is one missing a sheet width")
end

T.finish()

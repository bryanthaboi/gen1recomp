package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")

local function errors(label, needle, fn, ...)
  local ok, err = pcall(fn, ...)
  T.check(not ok and tostring(err):find(needle, 1, true) ~= nil,
    label .. " errors naming " .. needle .. " (got " .. tostring(ok and "no error" or err) .. ")")
end

local Credits = require("src.ui.gen2.Credits")
do
  local bare = Credits.new({ data = {} }, {})
  errors("Credits:palettes", "credits.lua has no palettes", bare.palettes, bare)
  errors("Credits:theEndImage", "credits.lua has no theEnd", bare.theEndImage, bare)
  errors("Credits:sceneSheet", "credits.lua has no scenes", bare.sceneSheet, bare)
  local partial = Credits.new({ data = {} }, { gfx = {
    palettes = { { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, { 4, 4, 4 } } },
    palettesPerScene = 1,
  } })
  errors("Credits:drawBorderStrips", "credits.lua has no border",
    partial.drawBorderStrips, partial)
  partial.borderFrame = 0
  errors("Credits:drawBanner", "credits.lua has no scenes", partial.drawBanner, partial)
  partial.shown = { { theEnd = true, x = 6, y = 8, width = 8 } }
  errors("Credits:drawText", "credits.lua has no theEnd", partial.drawText, partial)
  local noPer = Credits.new({ data = {} }, { gfx = { palettes = {} } })
  errors("Credits:palettes", "credits.lua has no palettesPerScene", noPer.palettes, noPer)
end

local Diploma = require("src.ui.gen2.Diploma")
do
  local textGame = { data = { text = require("tests.fixture_data.gen2_rom_text_s7_c").text() } }
  local bare = Diploma.new(textGame, { playerName = "GOLD", gfx = {} })
  errors("Diploma:palette", "diploma.lua has no bgPalette", bare.palette, bare)
  errors("Diploma:batch", "diploma.lua has no page1", bare.batch, bare)
  local noGfx = Diploma.new(textGame, { playerName = "GOLD" })
  errors("Diploma:draw", "diploma.lua has no bgPalette", noGfx.draw, noGfx)
end

local TradeAnim = require("src.ui.gen2.TradeAnim")
do
  local view = setmetatable({ gfx = {}, imageCache = {}, quadCache = {} },
    { __index = TradeAnim })
  errors("TradeAnim:drawTube", "trade.lua has no tube", view.drawTube, view, 0)
  errors("TradeAnim:drawBall", "trade.lua has no ball", view.drawBall, view, 80, 68, false)
  errors("TradeAnim:drawPoof", "trade.lua has no poof", view.drawPoof, view, 80, 68, 0)
  errors("TradeAnim:drawBulge", "trade.lua has no bulge", view.drawBulge, view, 80, 24, 0)
  errors("TradeAnim:drawScene", "trade.lua has no image", view.drawScene, view, 0)
end

local CardFlip = require("src.ui.gen2.CardFlip")
do
  local flip = setmetatable({ game = { data = { gen2MenuGfx = {} } } }, CardFlip)
  errors("CardFlip:sheets", "menu_gfx.lua has no cardFlip", flip.sheets, flip)
  errors("CardFlip:drawBoard", "menu_gfx.lua has no cardFlip", flip.drawBoard, flip)
  local partial = setmetatable({ game = { data = { gen2MenuGfx = { cardFlip = {
    sheet1 = "a.png", sheet2 = "b.png", sheet3 = "c.png", on = "on.png",
  } } } } }, CardFlip)
  errors("CardFlip:sheets", "menu_gfx.lua cardFlip has no off", partial.sheets, partial)
  errors("CardFlip:tilemap", "menu_gfx.lua cardFlip has no tilemap", partial.tilemap, partial)
end

local SlotMachine = require("src.ui.gen2.SlotMachine")
do
  local slots = setmetatable({ game = { data = { gen2MenuGfx = {} } },
    positions = { 0, 0, 0 }, distance = { 0, 0, 0 } }, { __index = SlotMachine })
  errors("SlotMachine:drawBackground", "menu_gfx.lua has no slots",
    slots.drawBackground, slots)
  errors("SlotMachine:drawReels", "menu_gfx.lua has no slots", slots.drawReels, slots)
  local partial = setmetatable({ game = { data = { gen2MenuGfx = { slots = {
    sheet1 = "a.png", sheet2 = "b.png", sheet3 = "c.png",
  } } } } }, { __index = SlotMachine })
  errors("SlotMachine:drawOverlays", "menu_gfx.lua slots has no tilemap",
    partial.drawOverlays, partial)
end

local BoxMenu = require("src.ui.gen2.BoxMenu")
do
  local box = BoxMenu.new({ data = { pokemon = {} } },
    { save = { party = {}, boxes = {} }, mode = "move", menuGfx = {} })
  errors("BoxMenu:panelColors", "menu_gfx.lua has no billsPc", box.panelColors, box, "EGG")
  errors("BoxMenu:drawBoxArrows", "menu_gfx.lua has no billsPc", box.drawBoxArrows, box)
  local eggless = BoxMenu.new({ data = { pokemon = {} } },
    { save = { party = {}, boxes = {} }, menuGfx = { billsPc = {
      icons = "i.png", palette = {}, orangePalette = {}, firstTile = 0x5c } } })
  errors("BoxMenu:drawEggPic", "menu_gfx.lua has no eggHatch", eggless.drawEggPic, eggless,
    { species = "EGG" })
end

local EggHatchAnim = require("src.ui.gen2.EggHatchAnim")
do
  errors("EggHatchAnim.new", "menu_gfx.lua has no eggHatch", EggHatchAnim.new,
    { data = {} }, { species = "TOGEPI" })
  errors("EggHatchAnim.new", "menu_gfx.lua eggHatch has no shell", EggHatchAnim.new,
    { data = { gen2MenuGfx = { eggHatch = { egg = "egg.png" } } } }, { species = "TOGEPI" })
end

local SummaryMenu = require("src.ui.gen2.SummaryMenu")
do
  local menu = SummaryMenu.new({ data = {} }, { mon = { species = "EGG", isEgg = true },
    save = { party = {} }, menuGfx = {} })
  errors("SummaryMenu:statsTiles", "menu_gfx.lua has no stats", menu.statsTiles, menu)
  errors("SummaryMenu:pageTile", "menu_gfx.lua has no stats", menu.pageTile, menu, 0x31, 0, 0)
  errors("SummaryMenu:drawEggPic", "menu_gfx.lua has no eggHatch", menu.drawEggPic, menu)
end

T.finish("gen2 required rom art")

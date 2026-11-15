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

local loaded = {}
package.loaded["src.render.Assets"] = {
  register = function() end,
  image = function(path)
    loaded[#loaded + 1] = path
    return {
      path = path,
      getDimensions = function() return 16, 32 end,
      getWidth = function() return 16 end,
      getHeight = function() return 32 end,
    }
  end,
}

local blits
love.graphics.newQuad = function(x, y, w, h)
  local q = { x = x, y = y, w = w, h = h }
  function q:setViewport(nx, ny, nw, nh)
    self.x, self.y, self.w, self.h = nx, ny, nw, nh
  end
  return q
end
love.graphics.draw = function(img, quad, x, y)
  if type(img) == "table" and img.path and type(quad) == "table" then
    blits[#blits + 1] = { path = img.path, qy = quad.y, x = x, y = y }
  end
end

local NamingScreen = require("src.ui.gen2.NamingScreen")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

local function render(screen)
  drawn, blits = {}, {}
  screen:drawPanel()
  return blits[1]
end

local game = {
  data = {
    gen2Icons = {
      species = { CHIKORITA = "ICON_ODDISH", MAGNEMITE = "ICON_VOLTORB" },
      icons = {
        ICON_ODDISH = { image = "icons/oddish.png" },
        ICON_VOLTORB = { image = "icons/voltorb.png" },
        ICON_EGG = { image = "icons/egg.png" },
      },
    },
    gen2Palettes = { partyMenu = { { { 1, 2, 3 }, { 4, 5, 6 } } } },
    text = require("tests.fixture_data.gen2_rom_text_s7_c").text(),
  },
}
require("tests.fixtures.gen2_naming").fill(game.data)

do
  local mon = { species = "CHIKORITA", name = "CHIKORITA", gender = "male" }
  local screen = NamingScreen.new(game, { type = "nickname", mon = mon })
  local blit = render(screen)
  T.check(blit ~= nil, "the nickname header draws the mon's party icon")
  T.eq(blit and blit.path, "icons/oddish.png", "resolved through gen2Icons")
  T.eq(blit and blit.x, 16, "icon x is 16")
  T.eq(blit and blit.y, 12, "icon y is 12 (depixel 4,4,4,0)")
  T.eq(blit and blit.qy, 0, "frame 0 first")
  T.eq(screen.iconColors, game.data.gen2Palettes.partyMenu[1],
    "the icon wears PAL_OW_RED")
  T.eq(drawnAt(8, 16), "\xe2\x99\x82", "male symbol at tile (1,2)")
  T.eq(drawnAt(5 * 8, 2 * 8), "CHIKORITA'S", "species line still drawn")

  for _ = 1, NamingScreen.ICON_FRAME_STEPS - 1 do screen:update() end
  blit = render(screen)
  T.eq(blit and blit.qy, 0, "still frame 0 one step before the swap")
  screen:update()
  blit = render(screen)
  T.eq(blit and blit.qy, 16, "frame 1 after the oamframe runs out")
  for _ = 1, NamingScreen.ICON_FRAME_STEPS do screen:update() end
  blit = render(screen)
  T.eq(blit and blit.qy, 0, "and back to frame 0")
end

do
  local mon = { species = "CHIKORITA", name = "CHIKORITA", gender = "female" }
  render(NamingScreen.new(game, { type = "nickname", mon = mon }))
  T.eq(drawnAt(8, 16), "\xe2\x99\x80", "female symbol at tile (1,2)")
end

do
  local mon = { species = "MAGNEMITE", name = "MAGNEMITE", gender = "unknown" }
  local blit = render(NamingScreen.new(game, { type = "nickname", mon = mon }))
  T.eq(drawnAt(8, 16), nil, "genderless draws nothing at tile (1,2)")
  T.eq(blit and blit.path, "icons/voltorb.png", "genderless still gets its icon")
end

do
  local mon = { species = "CHIKORITA", isEgg = true, gender = "male" }
  local blit = render(NamingScreen.new(game, { type = "nickname", mon = mon }))
  T.eq(blit and blit.path, "icons/egg.png", "an egg reads ICON_EGG")
end

do
  local screen = NamingScreen.new(game, { type = "rival", iconPath = "ow/rival.png" })
  for _ = 1, NamingScreen.ICON_FRAME_STEPS * 3 do screen:update() end
  local blit = render(screen)
  T.eq(blit and blit.path, "ow/rival.png", "iconPath callers still work")
  T.eq(blit and blit.qy, 0, "an OW sheet stays on its standing frame")
  T.eq(blit and blit.y, 16, "at its old spot")
  T.eq(drawnAt(8, 16), nil, "and no gender symbol")
end

T.finish("gen2_naming_header_2708_test")

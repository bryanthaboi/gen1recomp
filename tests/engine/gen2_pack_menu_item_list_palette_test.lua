-- PackMenu:drawList and PackGfx:draw stayed flat white/black regardless of
-- COLORS, since PackGfx only repaints its left five columns and the
-- item-list columns kept their initial bare-rectangle fill. Fixed by
-- routing that fill through Chrome.paletteFill and PackMenu's prints
-- through printThrough/cursorThrough.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GbcPalette = require("src.render.GbcPalette")
local PackGfx = require("src.ui.gen2.PackGfx")
local PackMenu = require("src.ui.gen2.PackMenu")

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

do
  -- An empty gfx.pack table (no header/background/pack-image paths): draw()
  -- still runs its header/pattern loops, they just find nothing to blit, so
  -- only the base fill itself is exercised.
  local gfx = PackGfx.new({ pack = {} })
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  gfx:draw("ITEMS")
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "PackGfx:draw()'s base fill reaches the GbcPalette seam")
end

local function fakePackMenu()
  return {
    rows = {
      { id = "POTION", name = "POTION", showCount = true, count = 1 },
    },
    scroll = 0,
    index = 1,
    switching = nil,
    gfx = PackGfx.new(nil),
    game = { data = { gen2Text = require("tests.fixtures.gen2_common_text").text() } },
    cursorAt = PackMenu.cursorAt,
    total = function() return 2 end, -- 1 row + CANCEL
  }
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  PackMenu.drawList(fakePackMenu(), 5, 4)
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "PackMenu:drawList() reaches the GbcPalette seam for item labels")
end

T.finish()

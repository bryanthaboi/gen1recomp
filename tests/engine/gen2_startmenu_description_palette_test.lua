-- StartMenu:draw drew the OPTION row's description tooltip, the "Change
-- settings" box under the list, with a raw love.graphics.rectangle at a
-- flat literal white, never touching GbcPalette. Every other box on this
-- screen already recoloured correctly with a picked COLORS palette, so
-- this one sub-region stood out as structurally white/black regardless.
--
-- No real shader runs headless, so this can't check a rendered pixel, same
-- limitation every palette test in this directory notes: force
-- GbcPalette.available() true and assert on which seam gets called, not
-- on pixels. tests/drivers/custom_ramp_probe.lua is where a real rendered
-- screen gets checked by eye.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GbcPalette = require("src.render.GbcPalette")
local StartMenu = require("src.ui.gen2.StartMenu")

local calls
local function spy(name)
  local original = GbcPalette[name]
  GbcPalette[name] = function(...)
    calls[name] = (calls[name] or 0) + 1
    return original(...)
  end
end

-- Minimal fake: draw() only needs #self.items (box height), a list stub,
-- and a current item with a desc, the same shape start_menu.asm carries
-- for every row (see StartMenu.lua's ITEMS table).
local function fakeMenu()
  return {
    items = { { id = "option" } },
    list = {
      draw = function() end,
      current = function() return { desc = { "Change", "settings" } } end,
    },
    phase = nil,
    showDescription = true,
  }
end

do
  GbcPalette.available = function() return true end
  GbcPalette.setCustomRamp({ { 255, 0, 255 }, { 200, 0, 200 }, { 100, 0, 100 },
                              { 0, 0, 0 } })
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  StartMenu.draw(fakeMenu())
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "StartMenu's description tooltip reaches the GbcPalette seam")
end

do
  GbcPalette.available = function() return false end
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  local ok = pcall(StartMenu.draw, fakeMenu())
  T.check(ok, "StartMenu:draw() does not error with no shader available")
end

-- engine/menus/start_menu.asm:223 .OptionDesc
do
  local save = { party = {}, inventory = {}, options = {} }
  local menu = StartMenu.new({ save = save, data = {
    text = require("tests.fixture_data.gen2_rom_text_s7_c").text({
      ["StartMenu.OptionDesc"] = "Modifier les\nreglages",
    }) } }, {
    save = save,
    unlocked = { pack = true },
  })
  local option
  for _, item in ipairs(menu.items) do
    if item.value == "option" then option = item end
  end
  T.check(option and option.desc[1] == "Modifier les"
      and option.desc[2] == "reglages",
    "START descriptions split the cache's whole .OptionDesc line by line")
end

T.finish()

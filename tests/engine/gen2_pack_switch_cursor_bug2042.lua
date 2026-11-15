-- ../pokecrystal/engine/menus/scrolling_menu.asm:438
-- ../pokecrystal/home/menu.asm:50

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local PackGfx = require("src.ui.gen2.PackGfx")
local PackMenu = require("src.ui.gen2.PackMenu")
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")

local function marksFor(overrides)
  local menu = {
    rows = {
      { id = "HYPER_POTION", name = "HYPER POTION" },
      { id = "FULL_HEAL", name = "FULL HEAL" },
    },
    scroll = 0,
    index = 2,
    gfx = PackGfx.new(nil),
    game = { data = { gen2Text = require("tests.fixtures.gen2_common_text").text() } },
    total = function() return 3 end,
  }
  for k, v in pairs(overrides) do menu[k] = v end
  local marks = {}
  menu.cursorAt = function(_, _, ty, hollow)
    marks[#marks + 1] = { ty = ty, hollow = hollow and true or false }
  end
  PackMenu.drawList(menu, 5, 4)
  return marks
end

-- ../pokecrystal/engine/items/pack.asm:1301
do
  local marks = marksFor({
    switching = 1,
    message = { "Where should this", "be moved to?" },
  })
  T.eq(#marks, 2, "the anchor and the moving cursor are both marked")
  T.check(marks[1].hollow, "the switch anchor keeps the hollow arrow")
  T.check(not marks[2].hollow, "the moving cursor stays solid (#2042)")
end

do
  local marks = marksFor({
    switching = 1,
    index = 3,
    message = { "Where should this", "be moved to?" },
  })
  T.eq(#marks, 2, "the anchor plus the cursor on CANCEL")
  T.check(marks[1].hollow, "the anchor is still hollow with the cursor on CANCEL")
  T.check(not marks[2].hollow, "and CANCEL's own cursor stays solid")
end

-- ../pokecrystal/engine/menus/scrolling_menu.asm:86
do
  local marks = marksFor({ submenu = { "USE", "TOSS" } })
  T.eq(#marks, 1, "only the live cursor is drawn with nothing armed")
  T.check(marks[1].hollow, "A's submenu still parks the hollow arrow")

  local msg = marksFor({ message = { "OAK: <PLAYER>!", "This isn't the time" } })
  T.check(msg[1].hollow, "and so does an ordinary PACK message")

  local plain = marksFor({})
  T.check(not plain[1].hollow, "an idle list draws the solid cursor")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:605
do
  local menu = {
    rows = {
      { id = "POTION", name = "POTION" },
      { id = "ANTIDOTE", name = "ANTIDOTE" },
    },
    scroll = 0,
    listIndex = 2,
    switching = 1,
    message = { "Where should this", "be moved to?" },
    cantToss = function() return true end,
    listTotal = function() return 3 end,
    def = function() return nil end,
    romLines = ItemPcMenu.romLines,
    data = { text = require("tests.fixture_data.gen2_rom_text_s7_e") },
  }
  local marks = {}
  local Chrome = require("src.ui.gen2.Chrome")
  local realCursor = Chrome.cursor
  Chrome.cursor = function(_, ty, hollow)
    marks[#marks + 1] = { ty = ty, hollow = hollow and true or false }
  end
  local ok, err = pcall(ItemPcMenu.drawList, menu)
  Chrome.cursor = realCursor
  T.check(ok, "the item PC list draws: " .. tostring(err))
  T.eq(#marks, 2, "its anchor and cursor are both marked")
  T.check(marks[1].hollow, "the item PC anchor is hollow")
  T.check(not marks[2].hollow, "and its moving cursor stays solid")
end

T.finish("gen2_pack_switch_cursor_bug2042")

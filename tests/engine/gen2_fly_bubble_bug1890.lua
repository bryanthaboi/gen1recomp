-- engine/pokegear/pokegear.asm:2088 (#1890)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local Pokegear = require("src.ui.gen2.Pokegear")

local tiles, texts, plates, cursors = {}, {}, 0, 0

local gear = setmetatable({
  fly = { { name = "NEW BARK TOWN" }, { name = "CHERRYGROVE CITY" } },
  flyIndex = 1,
  textData = require("tests.fixture_data.gen2_rom_text_s7_d").text(),
}, { __index = Pokegear })
gear.tile = function(_, id, tx, ty)
  tiles[#tiles + 1] = { id = id, tx = tx, ty = ty }
end
gear.text = function(_, str, tx, ty)
  texts[#texts + 1] = { str = str, tx = tx, ty = ty }
end
gear.drawPlate = function() plates = plates + 1 end

local realCursor = Chrome.cursor
Chrome.cursor = function() cursors = cursors + 1 end
gear:drawFlyBubble()
Chrome.cursor = realCursor

local function tileAt(tx, ty)
  local id
  for _, cell in ipairs(tiles) do
    if cell.tx == tx and cell.ty == ty then id = cell.id end
  end
  return id
end

check(tileAt(1, 0) == 0x30, "the top-left corner is $30")
check(tileAt(18, 0) == 0x31, "the top-right corner is $31")
check(tileAt(1, 2) == 0x32, "the bottom-left corner is $32")
check(tileAt(18, 2) == 0x33, "the bottom-right corner is $33")
check(tileAt(18, 1) == 0x34, "and the scroller is $34, the POI-red arrows")
check(tileAt(2, 0) == 0x7f and tileAt(17, 0) == 0x7f,
  "spaces run between the top corners")
check(tileAt(1, 1) == 0x7f, "row 1 is spaces under the name")
check(plates == 0, "no square plate is laid under it")
check(cursors == 0, "and no menu cursor stands in for the arrows")

check(texts[1] and texts[1].str == "Where?"
  and texts[1].tx == 2 and texts[1].ty == 0, "\"Where?\" sits at (2,0)")
check(texts[2] and texts[2].str == "NEW BARK TOWN"
  and texts[2].tx == 2 and texts[2].ty == 1, "the flypoint's name at (2,1)")

T.finish("gen2 fly bubble bug 1890")

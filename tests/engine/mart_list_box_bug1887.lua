-- engine/events/pokemart.asm (#1887)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local realFont = package.loaded["src.render.Font"]
local calls = {}
local FontStub
FontStub = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local out = {}
    for i = 1, #tostring(text) do out[i] = i end
    return out
  end,
  encode = function() return {} end,
  spansFitting = function(spans) return #spans end,
  advanceOf = function() return 8 end,
}
package.loaded["src.render.Font"] = FontStub
for _, mod in ipairs({ "src.ui.ListMenu", "src.ui.Theme", "src.ui.Menu",
                       "src.ui.ShopMenu", "src.render.TextBox" }) do
  package.loaded[mod] = nil
end
local ShopMenu = require("src.ui.ShopMenu")
local ListMenu = require("src.ui.ListMenu")

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local pressed
local game
game = {
  data = {
    text = {},
    items = {
      POKE_BALL = { name = "POKe BALL", price = 200 },
      GREAT_BALL = { name = "GREAT BALL", price = 600 },
      TOWN_MAP = { name = "TOWN MAP", price = 0, keyItem = true },
      HM_CUT = { name = "HM01", price = 0 },
      POTION = { name = "POTION", price = 300 },
    },
  },
  save = { money = 3000, inventory = {}, bagOrder = {} },
  input = {
    wasPressed = function(_, b) return pressed == b end,
    isDown = function() return false end,
  },
  stack = {
    states = {},
    push = function(self, s) self.states[#self.states + 1] = s end,
    pop = function(self) table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  },
}

local function openList(which)
  game.stack.states = {}
  local menu = ShopMenu.new(game, { "POKE_BALL", "GREAT_BALL" }, function() end)
  game.stack:push(menu)
  menu.index = which
  pressed = "a"
  menu:update(1 / 60)
  pressed = nil
  return menu, game.stack:top()
end

do
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  eq(menu.tx, 0, "BUY/SELL/QUIT sits at column 0")
  eq(menu.ty, 0, "and row 0")
  eq(menu.tw, 11, "11 tiles wide, flush with the money box at column 11")
  eq(menu.th, 7, "7 tiles tall (data/text_boxes.asm:34)")

  calls = {}
  menu:draw()
  check(found("draw", function(c)
    return c[2] == "BUY" and c[4] == 8
  end) ~= nil, "BUY prints on interior row 1 (wTopMenuItemY 1)")
  -- text_boxes.asm:35
  check(found("box", function(c)
    return c[2] == 11 and c[3] == 0 and c[4] == 9 and c[5] == 3
  end) ~= nil, "the money box is MONEY_BOX 11,0 - 19,2")
  check(found("draw", function(c)
    return c[2] == "MONEY" and c[3] == 104 and c[4] == 0
  end) ~= nil, "with MONEY captioned on its top border at column 13")
end

do
  local menu, list = openList(1)
  check(getmetatable(list) == ListMenu, "BUY opens a list menu")
  eq(list.itemBox, true, "PRICEDITEMLISTMENU draws LIST_MENU_BOX")
  eq(list.isOpaque, false, "so the mart floor and clerk keep drawing")
  eq(list.title, nil, "no BUY header row: the ROM list has no title")
  eq(list.items[#list.items].cancel, true, "the terminator's CANCEL row")
  eq(list.items[2].price, "¥600", "prices ride item.price, not the name row")

  calls = {}
  list:draw()
  check(found("box", function(c)
    return c[2] == 4 and c[3] == 2 and c[4] == 16 and c[5] == 11
  end) ~= nil, "LIST_MENU_BOX 4,2 - 19,12")
  check(found("draw", function(c)
    return c[2] == "GREAT BALL" and c[3] == 48 and c[4] == 48
  end) ~= nil, "the second name sits at (48, 48)")
  check(found("draw", function(c)
    return c[2] == "¥600" and c[4] == 56
  end) ~= nil, "its price is one tile row below the name")
  local price = found("draw", function(c) return c[2] == "¥600" end)
  if price then
    eq(price[3] + FontStub.width("¥600"), 136,
       "right-aligned through the BCD field (home/list_menu.asm:410-424)")
  end
  check(found("draw", function(c) return c[2] == "CANCEL" end) ~= nil,
        "CANCEL is a real row (home/list_menu.asm:523-528)")

  list.index = #list.items
  pressed = "a"
  list:update(1 / 60)
  pressed = nil
  eq(game.stack:top(), menu, "A on CANCEL returns to the mart menu")
end

do
  game.save.inventory = { POTION = 3, TOWN_MAP = 1, HM_CUT = 1 }
  local _, list = openList(2)
  check(getmetatable(list) == ListMenu, "SELL opens a list menu")
  eq(list.itemBox, true, "ITEMLISTMENU draws the same box")
  eq(list.title, nil, "and carries no SELL header")
  local byId = {}
  for _, it in ipairs(list.items) do
    if it.value then byId[it.value] = it end
  end
  eq(byId.POTION.count, 3, "ordinary stock keeps its quantity")
  eq(byId.TOWN_MAP.count, nil, "IsKeyItem_ skips the quantity")
  eq(byId.HM_CUT.right, nil, "and so do the HMs")
  eq(list.items[#list.items].cancel, true, "CANCEL closes the sell list too")
  game.save.inventory = {}
end

package.loaded["src.render.Font"] = realFont
for _, mod in ipairs({ "src.ui.ListMenu", "src.ui.Theme", "src.ui.Menu",
                       "src.ui.ShopMenu", "src.render.TextBox" }) do
  package.loaded[mod] = nil
end
require("src.ui.Screens").invalidate()

T.finish()

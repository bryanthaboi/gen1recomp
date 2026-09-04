-- engine/events/pokemart.asm:212-219
-- engine/events/pokemart.asm:199-206
--   luajit tests/engine/mart_bag_full_bug2162.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local function glyphs(text)
  local n = 0
  for _ in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
  end
  return n
end

local realFont = package.loaded["src.render.Font"]
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function() end,
  drawCode = function() end,
  drawBox = function() end,
  width = function(text) return glyphs(text) * 8 end,
  split = function(text)
    local out = {}
    for s in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      out[#out + 1] = s
    end
    return out
  end,
  spansFitting = function(spans, pixels)
    return math.min(#spans, math.floor(pixels / 8))
  end,
  encode = function(text) return { text } end,
  advanceOf = function() return 8 end,
}

local RELOAD = {
  "src.ui.QuantityBox", "src.ui.ShopMenu", "src.ui.ListMenu",
  "src.ui.ChoiceBox", "src.ui.Menu", "src.ui.Theme", "src.render.TextBox",
}
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end

local Bag = require("src.inventory.Bag")
local ShopMenu = require("src.ui.ShopMenu")
local TextBox = require("src.render.TextBox")

local BAG_FULL = "You can't carry\nany more items."
local NO_MONEY = "You don't have\nenough money."
local ANYTHING = "Is there anything\nelse I can do?"

local function boxText(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, " ")
end

local function newGame(money, ballCount)
  local events, stack = {}, {}
  local game
  game = {
    data = {
      items = { POKE_BALL = { name = "POKe BALL", price = 200 } },
      text = {
        _PokemartItemBagFullText = BAG_FULL,
        _PokemartNotEnoughMoneyText = NO_MONEY,
        _PokemartAnythingElseText = ANYTHING,
      },
      constants = {},
    },
    save = { money = money, inventory = {}, bagOrder = {} },
  }
  if ballCount then
    game.save.inventory.POKE_BALL = ballCount
    game.save.bagOrder = { "POKE_BALL" }
  end
  game.stack = {
    push = function(_, s)
      events[#events + 1] = { "push", s }
      stack[#stack + 1] = s
    end,
    pop = function()
      local s = table.remove(stack)
      events[#events + 1] = { "pop", s }
      return s
    end,
    top = function() return stack[#stack] end,
  }
  return game, events, stack
end

local function buyOne(game, stack)
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[1].onSelect()
  local list = stack[#stack]
  list.onChoose({ value = "POKE_BALL" })
  local qty = stack[#stack]
  game.stack:pop()
  qty.onDone(1)
  local confirm = stack[#stack]
  game.stack:pop()
  confirm.onChoose(true)
  return menu, list
end

do
  local game = newGame(3000, 99)
  eq(Bag.add(game.save, "POKE_BALL", 1, game.data), false,
     "AddItemToInventory refuses a 100th POKe BALL")
  eq(game.save.inventory.POKE_BALL, 99, "and adds nothing")
end

for _, case in ipairs({
  { name = "bag full", money = 3000, count = 99, text = BAG_FULL },
  { name = "not enough money", money = 100, count = nil, text = NO_MONEY },
}) do
  local game, events, stack = newGame(case.money, case.count)
  local menu, list = buyOne(game, stack)
  local box = stack[#stack]
  if check(getmetatable(box) == TextBox, case.name .. ": a text box is pushed") then
    check(boxText(box):find(case.text:gsub("\n", " "), 1, true) ~= nil,
          case.name .. ": the clerk's refusal is the text")
  end
  eq(stack[#stack - 1], list, case.name .. ": the list is still under the box")
  local popsBefore = 0
  for _, ev in ipairs(events) do
    if ev[1] == "push" and ev[2] == box then break end
    if ev[1] == "pop" and ev[2] == list then popsBefore = popsBefore + 1 end
  end
  eq(popsBefore, 0,
     case.name .. ": PrintText runs before LoadScreenTilesFromBuffer1")
  eq(game.save.money, case.money, case.name .. ": no money changes hands")

  game.stack:pop()
  box.onDone()
  eq(stack[#stack], nil, case.name .. ": A closes the list")
  eq(menu.footer, ANYTHING, case.name .. ": the mart menu asks again")
  eq(game.save.money, case.money, case.name .. ": money is still untouched")
end

do
  -- pokemart.asm:113
  local game, events, stack = newGame(3000)
  game.data.items.BICYCLE = { name = "BICYCLE", price = 0, keyItem = true }
  game.data.text._PokemartUnsellableItemText = "I can't put a\nprice on that."
  game.save.inventory.BICYCLE = 1
  game.save.bagOrder = { "BICYCLE" }
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[2].onSelect()
  local list = stack[#stack]
  list.onChoose({ value = "BICYCLE" })
  local box = stack[#stack]
  check(getmetatable(box) == TextBox, "unsellable: a text box is pushed")
  eq(stack[#stack - 1], list, "unsellable: the sell list is still under it")
  game.stack:pop()
  box.onDone()
  eq(stack[#stack], nil, "unsellable: A closes the sell list")
  eq(menu.footer, ANYTHING, "unsellable: the mart menu asks again")
end

do
  -- the bag-empty refusal has no list of its own (pokemart.asm:50)
  local game, _, stack = newGame(3000)
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  game.data.text._PokemartItemBagEmptyText = "You don't have\nanything to sell."
  menu.items[2].onSelect()
  local box = stack[#stack]
  check(getmetatable(box) == TextBox, "empty bag: only a text box is pushed")
  game.stack:pop()
  box.onDone()
  eq(menu.footer, ANYTHING, "empty bag: the mart menu asks again")
end

package.loaded["src.render.Font"] = realFont
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end
require("src.ui.Screens").invalidate()

T.finish()

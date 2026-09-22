-- engine/events/pokemart.asm:159-169
-- engine/events/pokemart.asm:84-91
-- home/list_menu.asm:89-91
--   luajit tests/engine/mart_price_text_bug2291.lua

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
  encode = function(text)
    local out = {}
    for s in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      out[#out + 1] = s
    end
    return out
  end,
  advanceOf = function() return 8 end,
}

local RELOAD = {
  "src.ui.QuantityBox", "src.ui.ShopMenu", "src.ui.ListMenu",
  "src.ui.ChoiceBox", "src.ui.Menu", "src.ui.Theme", "src.render.TextBox",
}
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end

local ShopMenu = require("src.ui.ShopMenu")
local TextBox = require("src.render.TextBox")
local QuantityBox = require("src.ui.QuantityBox")
local ChoiceBox = require("src.ui.ChoiceBox")

local GREET = "Take your time."
local SELL_GREET = "What would you\nlike to sell?"

local function newGame(money)
  local stack, pressed = {}, {}
  local game = {
    data = {
      items = { POKE_BALL = { name = "POKe BALL", price = 200 } },
      text = {
        _PokemartBuyingGreetingText = GREET,
        _PokemonSellingGreetingText = SELL_GREET,
        _PokemartTellBuyPriceText = "{RAM:wStringBuffer}?\nThat will be\011¥{NUM:hMoney, 3 | LEADING_ZEROES | LEFT_ALIGN}. OK?{DONE}",
        _PokemartTellSellPriceText = "I can pay you\n¥{NUM:hMoney, 3 | LEADING_ZEROES | LEFT_ALIGN} for that.{DONE}",
        _PokemartBoughtItemText = "Here you are!\nThank you!{PROMPT}",
      },
      constants = {},
    },
    save = { money = money, inventory = {}, bagOrder = {}, options = { textSpeed = 3 } },
    input = {
      wasPressed = function(_, b) return pressed[b] == true end,
      isDown = function() return false end,
    },
  }
  game.stack = {
    push = function(_, s) stack[#stack + 1] = s end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  }
  local function frame(btn)
    for k in pairs(pressed) do pressed[k] = nil end
    if btn then pressed[btn] = true end
    local top = stack[#stack]
    top:update(1 / 60)
    for k in pairs(pressed) do pressed[k] = nil end
  end
  return game, stack, frame
end

local function flat(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return out
end

do
  local game, stack, frame = newGame(3000)
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[1].onSelect()
  local list = stack[#stack]
  list.index = 1
  list.onChoose({ value = "POKE_BALL" })
  eq(list.hollowIndex, list.index, "buy: the chosen row shows the hollow cursor")
  local qty = stack[#stack]
  check(getmetatable(qty) == QuantityBox, "buy: the quantity box opens")
  qty.onDone(1)
  local box = stack[#stack]
  check(getmetatable(box) == TextBox, "buy: the price line is a typed text box, not a bare YES/NO")
  check(box.choice ~= nil, "buy: YES/NO waits on the text box")
  eq(stack[#stack - 1], qty, "buy: the quantity box stays up under the price text")
  eq(stack[#stack - 2], list, "buy: the list is under the quantity box")
  eq(list.footer, GREET, "buy: the price line is not dumped into the footer")
  local lines = flat(box)
  eq(lines[1], "POKe BALL?", "buy: the clerk names the item")
  eq(lines[2], "That will be", "buy: line 2")
  eq(lines[3], "¥200. OK?", "buy: line 3 carries the price")

  frame()
  eq(box.done, false, "buy: the price line types, it is not instant")
  eq(stack[#stack], box, "buy: no YES/NO while the line is typing")

  local sawCont = false
  for _ = 1, 300 do
    if box.waiting then sawCont = true break end
    frame()
  end
  check(sawCont, "buy: the cont line waits on the arrow")
  local vis = box:visibleText() or {}
  eq(vis[1], "POKe BALL?", "buy: arrow wait shows the item name")
  eq(vis[2], "That will be", "buy: arrow wait shows That will be")
  eq(stack[#stack], box, "buy: no YES/NO at the arrow wait")

  for _ = 1, 10 do frame() end
  frame("a")
  local pushed = false
  for _ = 1, 300 do
    if getmetatable(stack[#stack]) == ChoiceBox then pushed = true break end
    frame()
  end
  check(pushed, "buy: YES/NO opens once the text finishes")
  check(box.done, "buy: the text box is done when YES/NO opens")
  eq(stack[#stack - 1], box, "buy: YES/NO sits over the price text")
  eq(stack[#stack - 2], qty, "buy: the quantity box is still drawn under YES/NO")

  game.stack:pop()
  game.stack:pop()
  box.choice(false)
  eq(stack[#stack], list, "buy NO: the quantity box closes back to the list")
  eq(list.footer, GREET, "buy NO: the greeting is back")
end

do
  local game, stack = newGame(3000)
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[1].onSelect()
  local list = stack[#stack]
  list.onChoose({ value = "POKE_BALL" })
  local qty = stack[#stack]
  qty.onDone(2)
  local box = stack[#stack]
  game.stack:pop()
  box.choice(true)
  eq(game.save.money, 2600, "buy YES: money is paid")
  eq(game.save.inventory.POKE_BALL, 2, "buy YES: the items go in the bag")
  local bought = stack[#stack]
  check(getmetatable(bought) == TextBox and bought.choice == nil,
        "buy YES: the receipt text is up")
  eq(stack[#stack - 1], qty, "buy YES: the quantity box stays under the receipt")
  game.stack:pop()
  bought.onDone()
  eq(stack[#stack], list, "buy YES: the receipt closes back to the list")
end

do
  local game, stack = newGame(0)
  game.save.inventory.POKE_BALL = 5
  game.save.bagOrder = { "POKE_BALL" }
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[2].onSelect()
  local list = stack[#stack]
  list.index = 1
  list.onChoose(list.items[1])
  eq(list.hollowIndex, list.index, "sell: the chosen row shows the hollow cursor")
  local qty = stack[#stack]
  check(getmetatable(qty) == QuantityBox, "sell: the quantity box opens")
  qty.onDone(2)
  local box = stack[#stack]
  check(getmetatable(box) == TextBox and box.choice ~= nil,
        "sell: the price line is a typed text box with YES/NO")
  eq(stack[#stack - 1], qty, "sell: the quantity box stays up under the price text")
  eq(list.footer, SELL_GREET, "sell: the price line is not dumped into the footer")
  local lines = flat(box)
  eq(lines[1], "I can pay you", "sell: line 1")
  eq(lines[2], "¥200 for that.", "sell: line 2 carries the price")
  eq(box.done, false, "sell: the price line is not instant")
  game.stack:pop()
  box.choice(true)
  eq(stack[#stack], list, "sell YES: back to the sell list")
  eq(game.save.money, 200, "sell YES: money is paid")
  eq(game.save.inventory.POKE_BALL, 3, "sell YES: items leave the bag")
end

package.loaded["src.render.Font"] = realFont
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end
require("src.ui.Screens").invalidate()

T.finish()

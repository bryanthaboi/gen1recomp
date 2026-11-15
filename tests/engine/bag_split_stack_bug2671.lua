-- engine/items/inventory.asm:59
-- engine/events/pokemart.asm:152

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

local GameVersion = require("src.core.GameVersion")
local Bag = require("src.inventory.Bag")
local ShopMenu = require("src.ui.ShopMenu")
local TextBox = require("src.render.TextBox")
local SaveData = require("src.core.SaveData")

local BAG_FULL = "You can't carry\nany more items."
local BOUGHT = "Here you are!\nThank you!"

local function boxText(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, " ")
end

local function rowsOf(save, data)
  local out = {}
  for _, r in ipairs(Bag.rows(save, data)) do
    out[#out + 1] = r.id .. "x" .. tostring(r.count)
  end
  return table.concat(out, ",")
end

local function newGame(money, inventory, order)
  local stack = {}
  local game
  game = {
    data = {
      items = {
        X_ACCURACY = { name = "X ACCURACY", price = 950, index = 46 },
        POTION = { name = "POTION", price = 300, index = 20 },
      },
      text = setmetatable({
        _PokemartItemBagFullText = BAG_FULL,
        _PokemartBoughtItemText = BOUGHT,
      }, { __index = dofile("tests/fixture_data/text.lua") }),
      constants = {},
      field = {},
    },
    save = { money = money, inventory = inventory, bagOrder = order },
    input = {
      wasPressed = function() return false end,
      isDown = function() return false end,
    },
  }
  game.stack = {
    push = function(_, s) stack[#stack + 1] = s end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  }
  return game, stack
end

local function drain(game)
  for _ = 1, 600 do
    local top = game.stack:top()
    if not (top and top.stay and not top.stayShown) then return end
    top:update(1 / 60)
  end
end

local function fill(game, n)
  for i = 1, n do
    local id = "FILLER_" .. i
    game.save.inventory[id] = 1
    game.save.bagOrder[#game.save.bagOrder + 1] = id
  end
end

local function buy(game, stack, id, qty)
  local menu = ShopMenu.new(game, { id }, function() end)
  menu.items[1].onSelect()
  drain(game)
  local list = stack[#stack]
  list.onChoose({ value = id })
  local qtyBox = stack[#stack]
  qtyBox.onDone(qty)
  local confirm = stack[#stack]
  game.stack:pop()
  confirm.choice(true)
  return stack[#stack]
end

GameVersion.set("red")

do
  local game = newGame(0, { X_ACCURACY = 2, POTION = 5 }, { "X_ACCURACY", "POTION" })
  eq(Bag.add(game.save, "X_ACCURACY", 99, game.data), true,
     "2 + 99 X ACCURACY fits with a free slot")
  eq(game.save.inventory.X_ACCURACY, 101, "the total is 101")
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,POTIONx5,X_ACCURACYx2",
     "the first slot maxes at 99 and the overflow lands at the end")
  eq(Bag.slots(game.save, game.data), 3, "three bag slots")

  Bag.remove(game.save, "X_ACCURACY", 2, game.data, 2)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,POTIONx5",
     "tossing the overflow row removes that slot")

  Bag.add(game.save, "X_ACCURACY", 2, game.data)
  Bag.remove(game.save, "X_ACCURACY", 99, game.data, 1)
  eq(rowsOf(game.save, game.data), "POTIONx5,X_ACCURACYx2",
     "emptying the first slot keeps the later slot where it was")
end

do
  local game = newGame(0, { X_ACCURACY = 99 }, { "X_ACCURACY" })
  fill(game, 19)
  eq(Bag.add(game.save, "X_ACCURACY", 1, game.data), false,
     "a 20-slot bag refuses the overflow slot")
  eq(game.save.inventory.X_ACCURACY, 99, "and changes nothing")
  eq(#game.save.bagOrder, 20, "no slot is added")
end

do
  local game = newGame(0, { X_ACCURACY = 149 }, { "X_ACCURACY", "X_ACCURACY" })
  fill(game, 18)
  eq(Bag.add(game.save, "X_ACCURACY", 10, game.data), false,
     "a full bag refuses once the maxed first slot overflows")
  eq(game.save.inventory.X_ACCURACY, 149, "and changes nothing")
end

do
  local game, stack = newGame(104276, { X_ACCURACY = 2 }, { "X_ACCURACY" })
  local box = buy(game, stack, "X_ACCURACY", 99)
  if check(getmetatable(box) == TextBox, "mart: a text box follows the YES") then
    check(boxText(box):find("Here you are!", 1, true) ~= nil,
          "mart: the clerk hands the items over")
    check(boxText(box):find("can't carry", 1, true) == nil,
          "mart: no bag-full refusal")
  end
  eq(game.save.money, 104276 - 94050, "mart: 94050 is paid")
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,X_ACCURACYx2",
     "mart: two X ACCURACY rows")
end

do
  local game, stack = newGame(3000, { X_ACCURACY = 99 }, { "X_ACCURACY" })
  fill(game, 19)
  local box = buy(game, stack, "X_ACCURACY", 1)
  if check(getmetatable(box) == TextBox, "mart full: a text box follows the YES") then
    check(boxText(box):find("can't carry", 1, true) ~= nil,
          "mart full: the bag-full refusal")
  end
  eq(game.save.money, 3000, "mart full: no money changes hands")
end

do
  local game, stack = newGame(0, { X_ACCURACY = 101, POTION = 5 },
    { "X_ACCURACY", "POTION", "X_ACCURACY" })
  local menu = ShopMenu.new(game, {}, function() end)
  menu.items[2].onSelect()
  drain(game)
  local list = stack[#stack]
  local counts = {}
  for _, it in ipairs(list.items) do
    if not it.cancel then counts[#counts + 1] = tostring(it.count) end
  end
  eq(table.concat(counts, ","), "99,5,2", "sell list shows each slot's own count")
  list.index = 3
  list.onChoose(list.items[3])
  local qtyBox = stack[#stack]
  eq(qtyBox.max, 2, "selling from the overflow row caps at that row")
  qtyBox.onDone(2)
  local confirm = stack[#stack]
  game.stack:pop()
  confirm.choice(true)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,POTIONx5", "the sold row is gone")
  eq(game.save.money, 950, "paid half price for two")
end

do
  local game = newGame(0, { X_ACCURACY = 101, POTION = 5 },
    { "X_ACCURACY", "POTION", "X_ACCURACY" })
  local back = assert(SaveData.decode(SaveData.encode(game.save)))
  SaveData.validate(back, game.data)
  eq(rowsOf(back, game.data), "X_ACCURACYx99,POTIONx5,X_ACCURACYx2",
     "split slots survive a save round trip")
end

do
  local pc, order = { POTION = 99 }, { "POTION" }
  local data = newGame(0, {}, {}).data
  eq(Bag.addTo(pc, order, "POTION", 50, data, Bag.storeSlots(pc, data), 50), true,
     "PC deposit past 99 splits the box slot")
  eq(table.concat(order, ","), "POTION,POTION", "two box slots")
  local full, fullOrder = { POTION = 1 }, { "POTION" }
  for i = 1, 49 do
    full["FILLER_" .. i] = 1
    fullOrder[#fullOrder + 1] = "FILLER_" .. i
  end
  full.POTION = 99
  eq(Bag.addTo(full, fullOrder, "POTION", 1, data, Bag.storeSlots(full, data), 50), false,
     "a 50-slot box refuses the overflow slot")
end

do
  local game = newGame(0, { X_ACCURACY = 101, POTION = 5 },
    { "X_ACCURACY", "POTION", "X_ACCURACY" })
  Bag.remove(game.save, "X_ACCURACY", 5, game.data, 1)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx94,POTIONx5,X_ACCURACYx2",
     "tossing from the first slot leaves 94 and 2")
  eq(Bag.slots(game.save, game.data), 3, "both X ACCURACY slots stay")
  local back = assert(SaveData.decode(SaveData.encode(game.save)))
  SaveData.validate(back, game.data)
  eq(rowsOf(back, game.data), "X_ACCURACYx94,POTIONx5,X_ACCURACYx2",
     "a 94/2 split survives a save round trip")
  Bag.remove(game.save, "X_ACCURACY", 1, game.data)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx93,POTIONx5,X_ACCURACYx2",
     "a slotless remove takes from the first slot")
  Bag.add(game.save, "X_ACCURACY", 10, game.data)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,POTIONx5,X_ACCURACYx6",
     "adding tops the first slot up and carries the rest to the next")
  Bag.swap(game.save, 1, 3, game.data)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx6,POTIONx5,X_ACCURACYx99",
     "SELECT on two slots of one item moves the 99 to the second pick")
  Bag.swap(game.save, 1, 2, game.data)
  eq(rowsOf(game.save, game.data), "POTIONx5,X_ACCURACYx6,X_ACCURACYx99",
     "swapping different items keeps each slot's count")
  Bag.swap(game.save, 3, 2, game.data)
  eq(rowsOf(game.save, game.data), "POTIONx5,X_ACCURACYx99,X_ACCURACYx6",
     "the 99 follows the second pick when the sum exceeds 99")
  Bag.remove(game.save, "X_ACCURACY", 90, game.data, 2)
  Bag.swap(game.save, 2, 3, game.data)
  eq(rowsOf(game.save, game.data), "POTIONx5,X_ACCURACYx15",
     "SELECT merges two slots that fit in one")
  eq(game.save.bagStacks, nil, "a merged stack carries no per-slot list")
end

do
  local game, stack = newGame(0, { X_ACCURACY = 101, POTION = 5 },
    { "X_ACCURACY", "POTION", "X_ACCURACY" })
  local menu = ShopMenu.new(game, {}, function() end)
  menu.items[2].onSelect()
  drain(game)
  local list = stack[#stack]
  local function sellRow(row, qty)
    list.index = row
    list.onChoose(list.items[row])
    local qtyBox = stack[#stack]
    qtyBox.onDone(qty)
    local confirm = stack[#stack]
    game.stack:pop()
    confirm.choice(true)
  end
  list.scroll = 1
  sellRow(3, 1)
  eq(list.scroll, 1, "selling part of a row keeps the list scroll")
  eq(list.index, 2, "and the cursor goes to the top visible row")
  sellRow(3, 1)
  eq(rowsOf(game.save, game.data), "X_ACCURACYx99,POTIONx5", "the emptied row is gone")
  eq(list.scroll, 0, "an emptied row resets the sell list scroll")
  eq(list.index, 1, "and puts the cursor on the first row")
end

do
  GameVersion.set("gold")
  local game = newGame(0, { POTION = 99 }, { "POTION" })
  game.data.items.POTION.pocket = "ITEM"
  eq(Bag.add(game.save, "POTION", 1, game.data), false,
     "Gen 2 pockets keep one row per id")
  eq(#game.save.bagOrder, 1, "no duplicate row in Gen 2")
  GameVersion.set("red")
end

package.loaded["src.render.Font"] = realFont
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end
require("src.ui.Screens").invalidate()

T.finish()

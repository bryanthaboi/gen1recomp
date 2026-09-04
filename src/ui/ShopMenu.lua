-- Mart shop (engine/events/pokemart.asm DisplayPokemartDialogue_):
-- the BUY/SELL/QUIT menu loops until QUIT -- BUY and SELL keep it on
-- the stack underneath their list, and QUIT hands control back to the
-- caller (open_mart resumes its yielded script runner there).  Both
-- lists run in dialogue mode: the clerk speaks the real _Pokemart*
-- strings in the bottom text box with the money box top-right, then
-- the 1-99 quantity selector (DisplayChooseQuantityMenu) and a YES/NO
-- price confirm.  Key items and HMs can't be sold (.unsellableItem).

local Bag = require("src.inventory.Bag")
local ChoiceBox = require("src.ui.ChoiceBox")
local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local QuantityBox = require("src.ui.QuantityBox")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")

local ShopMenu = {}

local function txt(game, key, fallback)
  return game.data.text[key] or fallback
end

-- pokered engine/events/pokemart.asm:204
local function anythingElse(game)
  return txt(game, "_PokemartAnythingElseText",
             Strings("Is there anything\nelse I can do?"))
end

-- .returnToMainPokemartMenu -- pokered engine/events/pokemart.asm:199-206
local function refuse(game, menu, list, text)
  game.stack:push(TextBox.new(game, text, function()
    if list then list:close() end
    menu.footer = anythingElse(game)
  end))
end

local function buy(game, stock, menu)
  local items = {}
  for _, id in ipairs(stock) do
    local def = game.data.items[id]
    if def then
      table.insert(items, {
        value = id,
        label = def.name,
        price = ("¥%d"):format(def.price),
      })
    end
  end
  items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
  local greet = txt(game, "_PokemartBuyingGreetingText", "Take your time.")
  local notEnough = txt(game, "_PokemartNotEnoughMoneyText",
                        Strings("You don't have\nenough money."))
  local bagFull = txt(game, "_PokemartItemBagFullText",
                      Strings("You can't carry\nany more items."))
  local list
  list = ListMenu.new(game, nil, items, {
    dialogue = true,
    -- home/list_menu.asm:29-31
    itemBox = true,
    money = function() return game.save.money end,
    footer = greet,
    onCancel = function() menu.footer = anythingElse(game) end,
    onChoose = function(item)
      -- home/list_menu.asm:105-110, 523-528
      if item.cancel then
        list:close()
        menu.footer = anythingElse(game)
        return
      end
      local def = game.data.items[item.value]
      -- engine/events/pokemart.asm:152-156
      game.stack:push(QuantityBox.new(game, {
        max = 99,
        unitPrice = def.price,
        onDone = function(qty)
          if not qty then
            list.footer = greet
            return
          end
          local cost = qty * def.price
          -- _PokemartTellBuyPriceText + yes/no confirm
          list.footer = romText(game.data, "_PokemartTellBuyPriceText",
            "%s?\nThat will be\n¥%d. OK?", def.name, cost)
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              list.footer = greet
              return
            end
            if game.save.money < cost then
              refuse(game, menu, list, notEnough)
              return
            end
            if not Bag.add(game.save, item.value, qty, game.data) then
              refuse(game, menu, list, bagFull)
              return
            end
            game.save.money = game.save.money - cost
            -- SFX_PURCHASE drains before the receipt -- pokemart.asm:193
            game.stack:push(TextBox.new(game,
              txt(game, "_PokemartBoughtItemText",
                  Strings("Here you are!\nThank you!")),
              function() list.footer = greet end,
              { preSound = function()
                  return require("src.core.Sound").play(game.data, "Purchase")
                end }))
          end))
        end,
      }))
    end,
  })
  game.stack:push(list)
end

-- home/list_menu.asm:472-477
local function sellItems(game)
  local items = {}
  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items[id]
    local keyed = (def and def.keyItem) or id:find("^HM_") ~= nil
    table.insert(items, {
      value = id,
      label = def and def.name or id,
      count = (not keyed) and game.save.inventory[id] or nil,
    })
  end
  items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
  return items
end

local function sell(game, menu)
  -- Sell list is ITEMLISTMENU with wPrintItemPrices cleared
  -- (pokemart.asm .sellMenuLoop): name + quantity only.  Price shows
  -- in the quantity chooser.  Stuffing "xN" into the label next to a
  -- right-aligned ¥ price made long names overlap (issue #116).
  local items = sellItems(game)
  -- engine/events/pokemart.asm:50
  local greet = txt(game, "_PokemonSellingGreetingText",
                    Strings("What would you\nlike to sell?"))
  if #Bag.order(game.save) == 0 then
    refuse(game, menu, nil, txt(game, "_PokemartItemBagEmptyText",
                                Strings("You don't have\nanything to sell.")))
    return
  end
  local unsellable = txt(game, "_PokemartUnsellableItemText",
                         Strings("I can't put a\nprice on that."))
  local list
  list = ListMenu.new(game, nil, items, {
    dialogue = true,
    -- home/list_menu.asm:29-31
    itemBox = true,
    money = function() return game.save.money end,
    footer = greet,
    onCancel = function() menu.footer = anythingElse(game) end,
    onSelectKey = function(item, l)
      -- swap_items.asm:19-22
      if not item or item.cancel then return end
      if not l.swapIndex then
        l.swapIndex = l.index
        return
      end
      local order = Bag.order(game.save)
      order[l.swapIndex], order[l.index] = order[l.index], order[l.swapIndex]
      l.swapIndex = nil
      require("src.core.Sound").play(game.data, "Swap")
      l.items = sellItems(game)
    end,
    onChoose = function(item)
      -- home/list_menu.asm:105-110, 523-528
      if item.cancel then
        list:close()
        menu.footer = anythingElse(game)
        return
      end
      local def = game.data.items[item.value]
      -- only key items and HMs are unsellable (pokemart.asm IsKeyItem /
      -- IsItemHM); zero-price items like ETHER sell for ¥0.  An unknown id
      -- (nil def) has no price, so treat it as unsellable too rather than
      -- indexing nil below -- guards saves that already picked up a bogus
      -- ITEM_NONE "0" from Blue's House before that pickup was fixed (#11).
      if not def or def.keyItem or item.value:find("^HM_") then
        refuse(game, menu, list, unsellable)
        return
      end
      local unit = math.floor(def.price / 2)
      game.stack:push(QuantityBox.new(game, {
        max = game.save.inventory[item.value] or 1,
        unitPrice = unit,
        onDone = function(qty)
          if not qty then
            list.footer = greet
            return
          end
          -- _PokemartTellSellPriceText + yes/no confirm
          list.footer = romText(game.data, "_PokemartTellSellPriceText",
            "I can pay you\n¥%d for that.", unit * qty)
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              list.footer = greet
              return
            end
            game.save.money = game.save.money + unit * qty
            -- home/inventory.asm:15 AddAmountSoldToMoney sounds SFX_PURCHASE
            require("src.core.Sound").play(game.data, "Purchase")
            Bag.remove(game.save, item.value, qty)
            local left = game.save.inventory[item.value]
            if left then
              item.count = left
            else
              list:removeCurrent()
            end
            -- a sale prints nothing -- engine/events/pokemart.asm:112
            list.footer = greet
          end))
        end,
      }))
    end,
  })
  game.stack:push(list)
end

-- MONEY_BOX 11,0 (data/text_boxes.asm:35) over the greeting PrintText left
-- in the bottom box (home/text_script.asm:143)
local function drawClerk(menu)
  local game = menu.game
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(11, 0, 9, 3)
  -- data/text_boxes.asm:35
  love.graphics.rectangle("fill", 13 * 8, 0, 5 * 8, 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("MONEY"), 13 * 8, 0)
  local money = ("¥%d"):format((game.save and game.save.money) or 0)
  Font.draw(money, 152 - Font.width(money), 8)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if menu.footer then
    local flat = {}
    for _, page in ipairs(TextBox.paginate(menu.footer)) do
      for _, line in ipairs(page) do flat[#flat + 1] = line end
    end
    local y = 112
    for i = math.max(1, #flat - 1), #flat do
      Font.draw(flat[i], 8, y)
      y = y + 16
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function ShopMenu.new(game, stock, onQuit)
  -- keepOpen: the mart menu stays underneath its list so closing the
  -- list lands back here; only QUIT (or B) leaves and fires onQuit
  local menu
  -- engine/events/pokemart.asm:220 .done, reached by QUIT and by B alike
  local function farewell()
    game.stack:push(TextBox.new(game,
      txt(game, "_PokemartThankYouText", "Thank you!"), onQuit))
  end
  menu = Menu.new(game, {
    { label = Strings("BUY"), keepOpen = true, onSelect = function() buy(game, stock, menu) end },
    { label = Strings("SELL"), keepOpen = true, onSelect = function() sell(game, menu) end },
    { label = Strings("QUIT"), onSelect = farewell },
    -- data/text_boxes.asm:34
  }, { tx = 0, ty = 0, tw = 11, th = 7 })
  menu.onCancel = farewell
  menu.footer = txt(game, "_PokemartGreetingText",
                    Strings("Hi there!\nMay I help you?"))
  menu.draw = function(self)
    drawClerk(self)
    Menu.draw(self)
  end
  return menu
end

return ShopMenu

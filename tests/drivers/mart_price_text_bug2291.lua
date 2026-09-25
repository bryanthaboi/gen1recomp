-- engine/events/pokemart.asm:159-169
-- engine/events/pokemart.asm:84-91
-- home/list_menu.asm:89-91
--   POKEPORT_DRIVER=tests/drivers/mart_price_text_bug2291.lua POKEPORT_IDENTITY=bsa0922-2291 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Font = require("src.render.Font")
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local QuantityBox = require("src.ui.QuantityBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function topIs(cls) return getmetatable(top()) == cls end
  local function onStack(cls)
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == cls then return s end
    end
    return nil
  end
  local function waitFor(pred, frames)
    for _ = 1, frames or 300 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function finish()
    U.log(failures == 0 and "PASS mart_price_text_bug2291"
          or ("FAIL mart_price_text_bug2291 (" .. failures .. " failures)"))
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(600)
  end

  local ok, err = pcall(function()
    game.save.money = 3000
    game.save.inventory = game.save.inventory or {}
    Bag.add(game.save, "POKE_BALL", 5, game.data)
    U.teleport(game, "PEWTER_MART", 2, 5, "left")
    U.wait(10)

    U.tap(game, "a")
    for _ = 1, 60 do
      if topIs(Menu) then break end
      U.tap(game, "a")
      U.wait(4)
    end
    if not check("the mart menu opens", topIs(Menu)) then return end
    local menu = top()

    U.tap(game, "a")
    if not check("BUY opens the list", waitFor(function() return topIs(ListMenu) end, 300)) then return end
    local list = top()
    local itemId = list.items[list.index].value
    local def = game.data.items[itemId]
    local name = def.name
    U.wait(4)
    U.tap(game, "a")
    if not check("the quantity box opens", waitFor(function() return topIs(QuantityBox) end, 30)) then return end
    check("the chosen row shows the hollow cursor", list.hollowIndex == list.index)
    U.wait(4)
    U.tap(game, "a")
    check("the price line opens as a text box, not YES/NO",
          waitFor(function() return topIs(TextBox) end, 2) and not topIs(ChoiceBox))
    local box = top()
    check("the price text box carries the YES/NO", box.choice ~= nil)
    local lines = box.pages and box.pages[1] or {}
    check("line 1 names the item: " .. tostring(lines[1]), lines[1] == name .. "?")
    U.wait(8)
    local typed = box.shown and box.shown[1] and #box.shown[1] or 0
    check(("the item name is typing (%d of %d glyphs)"):format(typed, #Font.encode(name .. "?")),
          not box.done and typed > 0 and typed < #Font.encode(name .. "?"))
    U.shot(game, DIR .. "/2291_01_name_typing.png")

    check("the price line reaches the arrow wait",
          waitFor(function() return box.waiting and (box.preWait or 0) == 0 end, 300))
    local vis = box:visibleText() or {}
    check("arrow wait shows the item name", vis[1] == name .. "?")
    check("arrow wait shows That will be", vis[2] == "That will be")
    check("no YES/NO at the arrow wait", top() == box and not onStack(ChoiceBox))
    check("the quantity box stays up under the text", onStack(QuantityBox) ~= nil)
    check("the list row stays hollow under the text", list.hollowIndex == list.index)
    U.shot(game, DIR .. "/2291_02_name_and_cont_arrow.png")

    U.tap(game, "a")
    check("YES/NO opens after the price finishes typing",
          waitFor(function() return topIs(ChoiceBox) end, 300))
    check("the text box was done before YES/NO", box.done == true)
    local last = box:visibleText() or {}
    check("price text above YES/NO: " .. tostring(last[2]),
          last[1] == "That will be" and tostring(last[2]):find("OK?", 1, true) ~= nil)
    check("the quantity box is still drawn under YES/NO", onStack(QuantityBox) ~= nil)
    U.wait(4)
    U.shot(game, DIR .. "/2291_03_price_yesno_over_qty.png")

    U.tap(game, "b")
    check("NO returns to the buy list", waitFor(function() return top() == list end, 30))
    check("NO closes the quantity box", onStack(QuantityBox) == nil)
    check("the list cursor is filled again", waitFor(function() return list.hollowIndex == nil end, 5))
    check("NO buys nothing", game.save.money == 3000)

    U.tap(game, "b")
    if not check("B returns to BUY/SELL/QUIT", waitFor(function() return top() == menu end, 300)) then return end
    U.wait(4)
    U.tap(game, "down")
    U.wait(4)
    U.tap(game, "a")
    if not check("SELL opens the sell list", waitFor(function() return topIs(ListMenu) end, 300)) then return end
    local sellList = top()
    for _ = 1, 20 do
      local row = sellList.items[sellList.index]
      if row and row.value == "POKE_BALL" then break end
      U.tap(game, "down")
      U.wait(4)
    end
    U.wait(4)
    U.tap(game, "a")
    if not check("the sell quantity box opens", waitFor(function() return topIs(QuantityBox) end, 30)) then return end
    check("the sold row shows the hollow cursor", sellList.hollowIndex == sellList.index)
    U.wait(4)
    U.tap(game, "a")
    check("the sell price opens as a text box, not YES/NO",
          waitFor(function() return topIs(TextBox) end, 2) and not topIs(ChoiceBox))
    local sellBox = top()
    U.wait(6)
    check("the sell price is typing", sellBox.done == false)
    check("sell YES/NO opens after the text", waitFor(function() return topIs(ChoiceBox) end, 300))
    check("the sell quantity box is still drawn under YES/NO", onStack(QuantityBox) ~= nil)
    U.wait(4)
    U.shot(game, DIR .. "/2291_04_sell_yesno_over_qty.png")
    U.tap(game, "b")
    check("sell NO returns to the sell list", waitFor(function() return top() == sellList end, 30))
    check("sell NO keeps the items", (game.save.inventory.POKE_BALL or 0) == 5)
  end)
  if not ok then
    failures = failures + 1
    U.log("FAIL driver error:", tostring(err))
  end
  finish()
end

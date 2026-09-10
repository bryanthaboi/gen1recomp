-- engine/menus/start_sub_menus.asm:330-362, 424-439
-- engine/items/item_effects.asm:2547-2595
--   POKEPORT_DRIVER=tests/drivers/bag_toss_bug2247_test.lua POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local QuantityBox = require("src.ui.QuantityBox")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS bag_toss_2247" or "FAIL bag_toss_2247")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function has(class)
    for _, s in ipairs(game.stack.states) do
      if getmetatable(s) == class then return s end
    end
    return nil
  end
  local function onStack(state)
    for _, s in ipairs(game.stack.states) do
      if s == state then return true end
    end
    return false
  end
  local function boxText(box)
    local lines = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " / ")
  end
  local function waitBox(prefix)
    for _ = 1, 300 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox and top.done
         and boxText(top):find(prefix, 1, true) == 1 then
        return top
      end
      U.wait(1)
    end
    return nil
  end
  local function stepTo(state, wants, what)
    for _ = 1, 30 do
      if wants(state) then return true end
      U.tap(game, "down")
      U.wait(6)
    end
    check("found " .. what .. " in the menu", false)
    return false
  end

  U.newGame(game)
  if not check("new game reached the overworld", game.overworld ~= nil) then finish() end
  game.save.inventory = {}
  Bag.add(game.save, "GREAT_BALL", 14)
  U.teleport(game, "REDS_HOUSE_1F", 5, 5, "up")
  U.wait(20)

  U.tap(game, "start")
  U.wait(20)
  local menu = game.stack:top()
  local ITEM = Strings("ITEM")
  if not check("START opened a menu", menu and menu.items ~= nil) then finish() end
  if stepTo(menu, function(m) return m.items[m.index].label == ITEM end, "ITEM") then
    U.tap(game, "a")
    U.wait(20)
  end
  local bag = game.stack:top()
  local row
  if not check("the bag opened", bag and bag.items and bag.items[1] and bag.items[1].value ~= nil) then finish() end
  if stepTo(bag, function(b) return b.items[b.index].value == "GREAT_BALL" end, "GREAT BALL") then
    row = bag.index
    U.tap(game, "a")
    U.wait(10)
  end
  local sub = game.stack:top()
  if not check("USE/TOSS opened", getmetatable(sub) == Menu and #sub.items == 2) then finish() end
  U.tap(game, "down")
  U.wait(5)
  U.tap(game, "a")
  U.wait(10)

  check("quantity box on top", getmetatable(game.stack:top()) == QuantityBox)
  check("USE/TOSS still on the stack", onStack(sub))
  check("TOSS keeps the hollow cursor", sub.hollowIndex == 2 and sub.index == 2)
  check("shot 1", U.shot(game, DIR .. "/2247_01_toss_hollow_cursor.png"))

  U.tap(game, "a")
  local ask = waitBox("Is it OK to toss")
  if check("Is it OK to toss printed", ask ~= nil) then
    U.log("the box reads:", boxText(ask))
    check("it names GREAT BALL", boxText(ask):find("GREAT BALL", 1, true) ~= nil)
    check("it is a prompt", ask.stay and ask.stay.prompt == true)
  end
  check("no YES/NO yet", has(ChoiceBox) == nil)
  check("quantity box still up", has(QuantityBox) ~= nil)
  check("USE/TOSS still up", onStack(sub))
  check("nothing removed yet", game.save.inventory.GREAT_BALL == 14)
  U.wait(20)
  check("shot 2", U.shot(game, DIR .. "/2247_02_is_it_ok_prompt.png"))

  U.tap(game, "a")
  U.wait(5)
  check("YES/NO after A on the prompt", getmetatable(game.stack:top()) == ChoiceBox)
  check("the prompt stays under it", has(TextBox) == ask)

  U.tap(game, "a")
  local threw = waitBox("Threw away")
  if check("Threw away printed", threw ~= nil) then
    U.log("the box reads:", boxText(threw))
  end
  check("YES/NO came down", has(ChoiceBox) == nil)
  check("quantity box back on screen", has(QuantityBox) ~= nil)
  check("USE/TOSS still up", onStack(sub))
  check("the item was removed", game.save.inventory.GREAT_BALL == 13)
  check("but the list still shows x14", row and bag.items[row].count == 14)
  U.wait(20)
  check("shot 3", U.shot(game, DIR .. "/2247_03_threw_away_count_unchanged.png"))

  U.tap(game, "a")
  U.wait(10)
  check("back on the bag list", game.stack:top() == bag)
  check("no boxes left", not onStack(sub) and has(QuantityBox) == nil and has(TextBox) == nil)
  check("the list now shows x13", row and bag.items[row].count == 13)
  check("cursor still on the row", bag.index == row)
  check("shot 4", U.shot(game, DIR .. "/2247_04_list_redrawn.png"))

  finish()
end

-- home/text_script.asm:141-150
-- engine/events/pokemart.asm:7-19
-- engine/events/pokemart.asm:131-133
-- engine/events/pokemart.asm:199-206
-- engine/events/pokemart.asm:220-222
-- engine/menus/text_box.asm:168-176
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local TextBox = require("src.render.TextBox")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function states() return game.stack.states or {} end
  local function waitFor(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function typing(first)
    local t = top()
    if getmetatable(t) ~= TextBox or not t.stay or t.done then return false end
    local page = t.pages and t.pages[1] or {}
    if page[1] ~= first then return false end
    local line = t.shown and t.shown[1]
    return line ~= nil and #line >= 3 and #line < #page[1]
  end
  local function onStack(cls)
    for _, s in ipairs(states()) do
      if getmetatable(s) == cls then return s end
    end
    return nil
  end
  local function finish()
    U.log(failures == 0 and "PASS mart_clerk_typing_bug2384"
          or ("FAIL mart_clerk_typing_bug2384 (" .. failures .. " failures)"))
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(600)
  end

  local ok, err = pcall(function()
    game.save.money = 3000
    game.save.options = game.save.options or {}
    game.save.options.textSpeed = 3
    U.teleport(game, "PEWTER_MART", 2, 5, "left")
    U.wait(20)
    local ow = top()

    U.tap(game, "a")
    if not check("the greeting types in an empty box",
                 waitFor(function() return typing("Hi there!") end, 120)) then return end
    local menu = onStack(Menu)
    check("BUY/SELL/QUIT is on the stack but hidden", menu ~= nil and menu.hidden == true)
    U.still(game, DIR .. "/2384_greeting_typing.png")

    if not check("BUY/SELL/QUIT comes up after the greeting",
                 waitFor(function() return top() == menu end, 300)) then return end
    check("the menu is drawn now", menu.hidden == false)
    check("filled cursor on BUY", menu.index == 1 and menu.hollowIndex == nil)
    U.wait(4)
    U.still(game, DIR .. "/2384_menu_filled_cursor.png")

    U.tap(game, "a")
    if not check("Take your time. types before the list",
                 waitFor(function() return typing("Take your time.") end, 60)) then return end
    check("BUY goes hollow", menu.hollowIndex == 1)
    check("no list while the lead-in types", onStack(ListMenu) == nil)
    U.still(game, DIR .. "/2384_take_your_time_typing.png")

    if not check("the buy list opens after the lead-in",
                 waitFor(function() return getmetatable(top()) == ListMenu end, 300)) then return end
    U.wait(6)
    check("BUY stays hollow while the list is up", menu.hollowIndex == 1)
    U.still(game, DIR .. "/2384_buy_list_hollow_buy.png")

    U.tap(game, "b")
    if not check("anything-else types after the list closes",
                 waitFor(function() return typing("Is there anything") end, 60)) then return end
    check("BUY still hollow while it types", menu.hollowIndex == 1)
    U.still(game, DIR .. "/2384_anything_else_typing.png")

    if not check("back on BUY/SELL/QUIT",
                 waitFor(function() return top() == menu end, 300)) then return end
    check("cursor reset to BUY and filled", menu.index == 1 and menu.hollowIndex == nil)
    U.wait(4)
    U.still(game, DIR .. "/2384_back_on_buy.png")

    U.tap(game, "down")
    U.wait(4)
    U.tap(game, "down")
    U.wait(4)
    check("cursor on QUIT", menu.index == 3)
    U.tap(game, "a")
    local bye
    if not check("Thank you! goes up", waitFor(function()
      local t = top()
      if getmetatable(t) == TextBox and not t.stay then bye = t return true end
      return false
    end, 30)) then return end
    local s = states()
    check("the mart menu stays under Thank you!", s[#s - 1] == menu)
    check("QUIT is hollow under Thank you!", menu.hollowIndex == 3)
    waitFor(function() return bye.done end, 300)
    U.wait(4)
    U.still(game, DIR .. "/2384_thank_you.png")

    U.tap(game, "a")
    check("the mart closes back to the overworld",
          waitFor(function() return top() == ow end, 60))
    check("no mart screen left", onStack(Menu) == nil and onStack(ListMenu) == nil)
  end)
  if not ok then
    failures = failures + 1
    U.log("FAIL driver error:", tostring(err))
  end
  finish()
end

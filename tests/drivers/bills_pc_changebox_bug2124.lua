-- (bills_pc.asm:176)
-- "<PK><MN> BOX." (data/text/text_3.asm:30)
-- with balls.2bpp tile 0 (bills_pc.asm:118)
--   SHOT_DIR=/tmp/bug2124 POKEPORT_DRIVER=tests/drivers/bills_pc_changebox_bug2124.lua \
--   POKEPORT_IDENTITY=<a v11 cache> POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Boxes = require("src.pokemon.Boxes")
  local BoxMenu = require("src.ui.BoxMenu")
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local Theme = require("src.ui.Theme")
  local Font = require("src.render.Font")
  local Pokemon = require("src.pokemon.Pokemon")

  local pass = true
  local function check(msg, cond)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end

  local function capture()
    local drawn = {}
    local realCode, realDraw = Font.drawCode, Font.draw
    local realImage = love.graphics.draw
    Font.drawCode = function(code, x, y)
      drawn[#drawn + 1] = { kind = "code", code = code, x = x, y = y }
      return realCode(code, x, y)
    end
    Font.draw = function(s, x, y, ...)
      drawn[#drawn + 1] = { kind = "text", text = s, x = x, y = y }
      return realDraw(s, x, y, ...)
    end
    love.graphics.draw = function(img, ...)
      drawn[#drawn + 1] = { kind = "image",
        path = type(img) == "userdata" and "?" or (type(img) == "table" and img.path) }
      return realImage(img, ...)
    end
    game.stack:draw()
    Font.drawCode, Font.draw, love.graphics.draw = realCode, realDraw, realImage
    return drawn
  end
  local function sawCode(drawn, code)
    for _, d in ipairs(drawn) do
      if d.kind == "code" and d.code == code then return d end
    end
  end
  local function sawText(drawn, want)
    for _, d in ipairs(drawn) do
      if d.kind == "text" and d.text == want then return d end
    end
  end

  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  U.wait(6)

  local boxes = Boxes.ensure(game.save)
  boxes[1] = { Pokemon.new(game.data, "PIDGEY", 12) }
  boxes[3] = { Pokemon.new(game.data, "MAGIKARP", 5) }
  game.save.currentBox = 1
  game.save.party = { Pokemon.new(game.data, "CHARMANDER", 14) }
  game.stack:push(BoxMenu.new(game))
  U.wait(4)
  local bills = game.stack:top()
  check("Bill's PC menu is up", getmetatable(bills) == Menu)

  local changeIdx
  for i, item in ipairs(bills.items) do
    if tostring(item.label):find("CHANGE BOX", 1, true) then changeIdx = i end
  end
  check("CHANGE BOX is on the menu", changeIdx ~= nil)
  for _ = 2, changeIdx or 1 do U.tap(game, "down"); U.wait(2) end
  U.tap(game, "a")
  U.wait(20)

  check("CHANGE BOX asks first", getmetatable(game.stack:top()) == TextBox)
  check("the parent cursor is marked hollow under the ask",
        bills.hollowIndex == bills.index)
  do
    local drawn = capture()
    check("and the unfilled arrow is what gets drawn",
          sawCode(drawn, Theme.cursorHollow) ~= nil
          and sawCode(drawn, Theme.cursor) == nil)
  end
  U.shot(game, DIR .. "/bug2124_1_hollow_cursor.png")

  local function isPicker(s)
    return getmetatable(s) == Menu and s.kind == "pc_box_change"
  end
  for _ = 1, 60 do
    if isPicker(game.stack:top()) then break end
    U.tap(game, "a")
    U.wait(20)
  end
  check("YES opens the box picker", isPicker(game.stack:top()))
  U.wait(4)
  do
    local drawn = capture()
    check("the prompt is the two-tile <PK><MN>, not the word POKeMON",
          sawText(drawn, "<PK><MN> BOX.") ~= nil
          and sawText(drawn, "POKéMON BOX.") == nil)
    check("no {DONE} marker leaks onto the screen",
          sawText(drawn, "<PK><MN> BOX.{DONE}") == nil)
    local balls = 0
    for _, d in ipairs(drawn) do
      if d.kind == "image" then balls = balls + 1 end
    end
    check("the box markers are drawn tiles, not vectors", balls >= 2)
  end
  U.shot(game, DIR .. "/bug2124_2_change_box_list.png")

  U.tap(game, "b")
  U.wait(12)
  check("B returns to Bill's PC menu", game.stack:top() == bills)
  check("and the cursor is filled again", bills.hollowIndex == nil)
  do
    local drawn = capture()
    check("the filled arrow is back", sawCode(drawn, Theme.cursor) ~= nil)
  end
  U.shot(game, DIR .. "/bug2124_3_back_on_pc_menu.png")

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
  U.log("Look at bug2124_1_hollow_cursor.png: the arrow beside CHANGE BOX is")
  U.log("the unfilled outline, not the solid triangle.  In")
  U.log("bug2124_2_change_box_list.png the second prompt line reads with the")
  U.log("two-tile PK MN ligature and the markers beside BOX 1 and BOX 3 are")
  U.log("the cart's flat pokeball ring -- no white belt, no centre pip -- and")
  U.log("pick up colour in ADVANCED mode.")
  U.log("Shots are in " .. DIR)
end

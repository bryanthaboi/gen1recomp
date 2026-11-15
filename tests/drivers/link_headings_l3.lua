-- engine/events/hidden_events/school_blackboard.asm:9-74
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")
  local GameVersion = require("src.core.GameVersion")
  local tag = GameVersion.get()

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS link_headings_l3" or "FAIL link_headings_l3")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function waitMenu()
    for _ = 1, 60 do
      local t = game.stack:top()
      if getmetatable(t) == Menu then return t end
      U.tap(game, "a")
      U.wait(8)
    end
  end
  local function labels(menu)
    local out = {}
    for i, item in ipairs(menu.items or {}) do out[i] = item.label end
    return table.concat(out, "/")
  end

  local cart = game.data.text.HowToLinkText
  check("cache carries HowToLinkText", type(cart) == "string")
  check("HowToLinkText decodes to the four headings",
        cart == "HOW TO LINK\nCOLOSSEUM\nTRADE CENTER\nSTOP READING")

  U.teleport(game, "CELADON_MANSION_ROOF_HOUSE", 3, 1, "up")
  U.wait(10)
  local ow = game.overworld
  U.tap(game, "a")
  U.wait(20)
  local menu = waitMenu()
  if not check("the blackboard opened the heading menu", menu ~= nil) then
    finish()
  end
  check("menu rows come from HowToLinkText",
        labels(menu) == (cart or ""):gsub("\n", "/"))
  U.wait(10)
  check("heading menu shot", U.still(game,
    DIR .. "/l3_" .. tag .. "_01_link_headings_menu.png"))

  U.tap(game, "a")
  U.wait(20)
  local again = waitMenu()
  check("HOW TO LINK prints its blurb and returns to the menu",
        again ~= nil and labels(again) == labels(menu))

  for _ = 1, 3 do
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(20)
  check("STOP READING returns to the overworld", game.stack:top() == ow)
  finish()
end

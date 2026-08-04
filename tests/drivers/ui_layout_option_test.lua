-- Driver: UI LAYOUT centered vs dynamic, same moment shot twice.
--
-- Only visible when the window letterboxes, so it resizes first: at an exact
-- multiple of 160x144 there is nowhere for a docked element to dock TO.
-- Shoots the overworld dialogue box and the START menu, the two pieces the
-- option moves.
--   POKEPORT_DRIVER=tests/drivers/ui_layout_option_test.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  love.window.setMode(1000, 700)
  U.wait(30)

  -- straight into the overworld, no intro
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(40)

  local function shootBoth(tag)
    -- START menu (Menu anchors "topright")
    U.tap(game, "start")
    U.wait(45)
    U.shot(game, DIR .. ("/uilayout_%s_startmenu.png"):format(tag))
    U.tap(game, "b")
    U.wait(30)

    -- a dialogue box (TextBox anchors "bottom"): read the sign by the door
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, "UI LAYOUT check:\nthis box.", function() end))
    for _ = 1, 400 do
      local top = game.stack:top()
      if top and top.done then break end
      U.wait(2)
    end
    U.wait(30)
    U.shot(game, DIR .. ("/uilayout_%s_textbox.png"):format(tag))
    game.stack:pop()
    U.wait(20)
  end

  game.save.options.uiLayout = "centered"
  U.log("UI LAYOUT = centered (the default)")
  U.wait(20)
  shootBoth("centered")

  game.save.options.uiLayout = "dynamic"
  U.log("UI LAYOUT = dynamic")
  U.wait(20)
  shootBoth("dynamic")

  U.log("done")
  U.wait(20)
end

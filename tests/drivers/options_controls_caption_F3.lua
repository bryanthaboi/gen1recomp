local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/F3"
  local tag = GameVersion.get()
  U.wait(45)
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(10)

  local OptionsMenu = require("src.ui.OptionsMenu")
  local BindingsMenu = require("src.ui.BindingsMenu")
  local menu = OptionsMenu.new(game)
  game.stack:push(menu)
  U.wait(5)

  local ctl
  for i, row in ipairs(menu.view) do
    if row.id == "controls" then ctl = row; break end
  end
  local want = Strings("%d OPTIONS", #BindingsMenu.BUTTONS)
  local got = ctl and ctl.value and ctl.value(game)
  print(string.format("[F3] %s controls caption=%s", tag, tostring(got)))
  expect(got == want, tag .. "_controls_caption_" .. want:gsub(" ", "_"))
  U.still(game, string.format("%s/F3_%s_01_controls_card_caption.png", DIR, tag))

  if game.stack:top() == menu then game.stack:pop() end
  U.wait(2)
  love.event.quit(failed and 1 or 0)
end

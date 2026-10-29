local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3078"
  local gen2 = GameVersion.generation() == 2
  local tag = GameVersion.get()
  U.wait(45)

  local menu, window
  if gen2 then
    local world = game.world
    expect(world and world.map ~= nil, tag .. "_world_booted")
    world:warpToMapId("NEW_BARK_TOWN", 13, 7, "down")
    for _ = 1, 60 do
      if not world:busy() then break end
      U.wait(1)
    end
    U.wait(10)
    local OptionsMenu = require("src.ui.gen2.OptionsMenu")
    menu = OptionsMenu.new(game, { options = game.options })
    window = 7
  else
    U.teleport(game, "PALLET_TOWN", 5, 6, "down")
    U.wait(10)
    local OptionsMenu = require("src.ui.OptionsMenu")
    menu = OptionsMenu.new(game)
    window = require("src.ui.OptionRows").VISIBLE
  end
  game.stack:push(menu)
  U.wait(5)

  local view = menu.view or menu.rows
  local ctl
  for i, row in ipairs(view) do
    print(string.format("[3078] %s view[%d] id=%s", tag, i, tostring(row.id)))
    if row.id == "controls" and not ctl then ctl = i end
  end
  expect(ctl ~= nil and ctl <= window,
    string.format("%s_controls_on_first_page (row %s of a %d-row window)",
      tag, tostring(ctl), window))
  U.still(game, string.format("%s/3078_%s_01_options_first_page.png", DIR, tag))

  if ctl then
    for _ = 1, ctl - 1 do
      U.tap(game, "down")
      U.wait(3)
    end
    expect(menu.index == ctl, tag .. "_cursor_reaches_controls")
    expect((menu.scroll or 0) == 0, tag .. "_no_scroll_to_reach_controls")
    U.still(game, string.format("%s/3078_%s_02_cursor_on_controls.png", DIR, tag))

    U.tap(game, "a")
    U.wait(8)
    local top = game.stack:top()
    expect(top and getmetatable(top) == require("src.ui.BindingsMenu"),
      tag .. "_controls_opens_bindings_menu")
    U.still(game, string.format("%s/3078_%s_03_bindings_menu.png", DIR, tag))
    if top ~= menu then game.stack:pop() end
  end
  if game.stack:top() == menu then game.stack:pop() end
  U.wait(2)
  love.event.quit(failed and 1 or 0)
end

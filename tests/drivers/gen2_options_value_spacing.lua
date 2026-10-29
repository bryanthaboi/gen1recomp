local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "shots/gen2_options_value_spacing"
  local ver = GameVersion.get()
  local touch = os.getenv("POKEPORT_TOUCH") == "1" and "touch" or "notouch"
  local tag = ver .. "_" .. touch
  U.wait(45)

  local world = game.world
  expect(world and world.map ~= nil, tag .. "_world_booted")
  world:warpToMapId("NEW_BARK_TOWN", 13, 7, "down")
  for _ = 1, 60 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(10)

  local OptionsMenu = require("src.ui.gen2.OptionsMenu")
  local menu = OptionsMenu.new(game, { options = game.options })
  game.stack:push(menu)
  U.wait(5)
  local view = menu:visible()

  local function checkPage(label)
    local shown = menu:layout()
    local names, ok = {}, true
    for n, entry in ipairs(shown) do
      local last = entry.valueY or entry.labelY
      local nextEntry = shown[n + 1]
      if nextEntry and nextEntry.labelY - last < 2 then ok = false end
      names[#names + 1] = tostring(entry.row.id) .. "@" .. entry.labelY
        .. (entry.valueY and ("/" .. entry.valueY) or "")
    end
    print(string.format("[F4] %s %s %s", tag, label, table.concat(names, " ")))
    expect(ok, string.format("%s_%s_blank_line_between_rows", tag, label))
    return shown
  end

  local function resize(w, h)
    love.window.setMode(w, h, { resizable = true, borderless = true })
    if love.window.setPosition then love.window.setPosition(-30000, -30000) end
    U.wait(20)
  end

  for _, sz in ipairs({ { 1024, 768 }, { 1280, 720 }, { 1920, 1080 } }) do
    local w, h = sz[1], sz[2]
    resize(w, h)
    local size = w .. "x" .. h

    menu.index, menu.scroll = 1, 0
    menu:ensureVisible()
    U.wait(3)
    local shown = checkPage("first_page")
    local hasBattle = false
    for _, entry in ipairs(shown) do
      if entry.row.id == "group.battle" then hasBattle = true end
    end
    expect(hasBattle, tag .. "_battle_options_on_first_page")
    U.still(game, string.format("%s/F4_%s_%s_01_performance_value_clear_of_battle.png",
      DIR, tag, size))

    menu.index = #view
    menu:ensureVisible()
    U.wait(3)
    checkPage("last_page")
    expect(menu.scroll > 0, tag .. "_last_page_scrolled")
    U.still(game, string.format("%s/F4_%s_%s_02_last_page_values_clear.png",
      DIR, tag, size))
  end

  resize(1024, 768)
  menu.index, menu.scroll = 1, 0
  menu:ensureVisible()
  local page = menu:focusRow("musicVol")
  U.wait(3)
  expect(page ~= nil and page ~= menu, tag .. "_audio_page_opened")
  if page and page ~= menu then
    local ys, pitchOk = {}, true
    for n, entry in ipairs(page:layout()) do
      ys[#ys + 1] = entry.labelY
      if entry.labelY ~= 2 + (n - 1) * 2 then pitchOk = false end
    end
    print("[F4] " .. tag .. " audio page labels " .. table.concat(ys, ","))
    expect(pitchOk, tag .. "_audio_page_keeps_string_options_pitch")
    U.still(game, string.format("%s/F4_%s_1024x768_03_audio_page_cart_pitch.png",
      DIR, tag))
    game.stack:pop()
  end
  game.stack:pop()
  U.wait(2)
  love.event.quit(failed and 1 or 0)
end

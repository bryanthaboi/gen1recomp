local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuid_dex_toc"

-- include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
local MAX_SHOWED = 9

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/stitchuid_dex_toc.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS stitchuid_dex_toc")
    love.event.quit(0)
  else
    say("FAIL stitchuid_dex_toc failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Dex = require("src.core.game3.dex")
  local Pokedex = require("src.ui.game3.pokedex")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function sample(drawFn, w, h)
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    drawFn()
    love.graphics.setCanvas()
    local data = canvas:newImageData()
    return function(x, y)
      local r, g, b, a = data:getPixel(x, y)
      return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), math.floor(a * 255 + 0.5)
    end
  end

  -- pokefirered/src/pokedex_screen.c:1031-1035
  local function orangeInk(x0, y0, x1, y1)
    local get = sample(function() Pokedex.draw() end, 240, 160)
    local n = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b, a = get(x, y)
        if a == 255 and r > 200 and g > 100 and g < 190 and b < 110 then n = n + 1 end
      end
    end
    return n
  end

  -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:656
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_SYS_POKEDEX_GET, true)
  for _, sp in ipairs({ 1, 29, 32 }) do
    Dex.registerEncounter(session.dex, sp, session)
    Dex.registerCapture(session.dex, sp, session)
  end

  U.tap(game, "start")
  U.wait(20)
  U.tap(game, "a")
  U.wait(30)
  if not result(Pokedex.isOpen() == true, "START menu opened the POKéDEX") then return finish() end
  result(Pokedex.screen == "mode_select", "the dex opens on the table of contents")
  result(Pokedex.modeScroll == 0, "the table of contents starts unscrolled")

  -- pokefirered/src/pokedex_screen.c:319-340
  result(#Pokedex.MODES == 19, "the Kanto table of contents lists 19 rows (" .. #Pokedex.MODES .. ")")

  -- pokefirered/src/pokedex_screen.c:407-419
  local topDown = orangeInk(192, 133, 208, 149)
  local topUp = orangeInk(192, 11, 208, 27)
  local topIcon = orangeInk(168, 128, 231, 135)
  result(topDown > 20, "the down arrow is drawn at (200,141) on the first page (" .. topDown .. " px)")
  result(topUp == 0, "no up arrow at the fullyUp threshold (" .. topUp .. " px)")
  result(topIcon == 0, "no arrow inside the category icon window (" .. topIcon .. " px)")
  U.shot(game, DIR .. "/stitchuid_dex_toc_01_top.png")

  local maxScroll = #Pokedex.MODES - MAX_SHOWED
  result(maxScroll > 0, "the table of contents is longer than the 9 row window")
  for _ = 1, 40 do
    if Pokedex.modeScroll >= maxScroll then break end
    U.tap(game, "down")
    U.wait(6)
  end
  result(Pokedex.modeScroll == maxScroll, "the cursor walked the list to the end")
  U.wait(20)

  local endUp = orangeInk(192, 11, 208, 27)
  local endDown = orangeInk(192, 133, 208, 149)
  result(endUp > 20, "the up arrow is drawn at (200,19) at the end (" .. endUp .. " px)")
  result(endDown == 0, "no down arrow at the fullyDown threshold (" .. endDown .. " px)")
  U.shot(game, DIR .. "/stitchuid_dex_toc_02_bottom.png")

  -- pokefirered/src/list_menu.c:438-476
  for _ = 1, 40 do
    if Pokedex.modeScroll == 0 then break end
    U.tap(game, "up")
    U.wait(6)
  end
  result(Pokedex.modeScroll == 0,
    "walking back up from CANCEL returns the list to scroll 0 (" .. tostring(Pokedex.modeScroll) .. ")")
  U.wait(20)
  local backUp = orangeInk(192, 11, 208, 27)
  local backDown = orangeInk(192, 133, 208, 149)
  result(backUp == 0, "the up arrow is gone with the header back on screen (" .. backUp .. " px)")
  result(backDown > 20, "the down arrow is back at the top of the list (" .. backDown .. " px)")
  U.shot(game, DIR .. "/stitchuid_dex_toc_03_backtotop.png")

  for _ = 1, 20 do
    if not Pokedex.isOpen() then break end
    U.tap(game, "b")
    U.wait(10)
  end
  for _ = 1, 20 do
    if Pokedex.isOpen() then break end
    U.tap(game, "start")
    U.wait(20)
    U.tap(game, "a")
    U.wait(30)
  end
  if not result(Pokedex.isOpen() and Pokedex.modeScroll == 0,
    "reopening the dex puts the table of contents back at the top ("
      .. tostring(Pokedex.isOpen()) .. " scroll=" .. tostring(Pokedex.modeScroll) .. ")") then
    return finish()
  end

  U.tap(game, "a")
  U.wait(20)
  if not result(Pokedex.screen == "ordered_list", "NUMERICAL MODE opened the list") then
    return finish()
  end
  U.tap(game, "a")
  U.wait(30)
  result(Pokedex.screen == "data" and Pokedex.selectedSpecies == 1,
    "A on the first entry opened the BULBASAUR data page")

  -- pokefirered/src/pokedex_screen.c:2901
  local bytes, rel = PokedexChrome.footprintSource(1)
  result(rel ~= nil and rel:match("/1%.rgba$") ~= nil,
    "BULBASAUR reads footprints/1.rgba (" .. tostring(rel) .. ")")
  result(bytes ~= nil and #bytes == 16 * 16 * 4, "the footprint is a 16x16 RGBA tile")

  local get = sample(function() Pokedex.draw() end, 240, 160)
  local ink = 0
  for y = 64, 79 do
    for x = 104, 119 do
      local r, g, b, a = get(x, y)
      if a == 255 and r == 0 and g == 0 and b == 0 then ink = ink + 1 end
    end
  end
  result(ink >= 20 and ink < 256, "the BULBASAUR footprint is drawn on the page (" .. ink .. " px)")
  U.shot(game, DIR .. "/stitchuid_dex_toc_04_footprint.png")

  for _ = 1, 20 do
    if not Pokedex.isOpen() then break end
    U.tap(game, "b")
    U.wait(10)
  end

  finish()
end

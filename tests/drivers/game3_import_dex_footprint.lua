local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_dex_footprint"

-- include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import_dex_footprint")
    love.event.quit(0)
  else
    print("FAIL import_dex_footprint failures=" .. failures)
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

  PokedexChrome.install()
  local paper = PokedexChrome.getImage("paper_bg")
  result(paper ~= nil, "the cache holds paper_bg.rgba")
  if paper then
    local pw, ph = paper:getDimensions()
    result(pw == 240 and ph == 160, string.format("paper_bg is 240x160 (got %dx%d)", pw, ph))
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
  result(Pokedex.isOpen() == true, "START menu opened the POKéDEX")
  result(Pokedex.screen == "mode_select", "the dex opens on the table of contents ("
    .. tostring(Pokedex.screen) .. ")")

  local function probePaper(label)
    local screen = sample(function() Pokedex.draw() end, 240, 160)
    local function rgb(x, y)
      local r, g, b, a = screen(x, y)
      return string.format("%d,%d,%d,%d", r, g, b, a)
    end
    result(rgb(2, 4) == "99,99,99,255", label .. ": the top bar is the ROM grey bar (" .. rgb(2, 4) .. ")")
    result(rgb(2, 152) == "99,99,99,255",
      label .. ": the bottom bar is the ROM grey bar (" .. rgb(2, 152) .. ")")
    result(rgb(2, 86) == "255,255,255,255",
      label .. ": the page body is the ROM white page (" .. rgb(2, 86) .. ")")
  end

  probePaper("table of contents")
  U.shot(game, DIR .. "/import_dex_footprint_01_paper_contents.png")

  U.tap(game, "a")
  U.wait(20)
  result(Pokedex.screen == "ordered_list", "NUMERICAL MODE opened the list ("
    .. tostring(Pokedex.screen) .. ")")
  probePaper("list")
  U.shot(game, DIR .. "/import_dex_footprint_02_paper_list.png")

  U.tap(game, "a")
  U.wait(30)
  result(Pokedex.screen == "data" and Pokedex.selectedSpecies == 1 and Pokedex.dataPage == 1,
    "A on the first entry opened the BULBASAUR data page (" .. tostring(Pokedex.screen)
      .. " sp=" .. tostring(Pokedex.selectedSpecies) .. ")")

  local screen = sample(function() Pokedex.draw() end, 240, 160)
  local ink = 0
  for y = 64, 79 do
    for x = 104, 119 do
      local r, g, b, a = screen(x, y)
      if a == 255 and r == 0 and g == 0 and b == 0 then ink = ink + 1 end
    end
  end
  result(ink >= 20 and ink < 256, "the BULBASAUR footprint is drawn on the page (" .. ink .. " px)")
  U.shot(game, DIR .. "/import_dex_footprint_03_bulbasaur_footprint.png")

  local function footprintMask(sp)
    local get = sample(function() PokedexChrome.drawFootprint(sp, 0, 0) end, 16, 16)
    local bits, count = {}, 0
    for y = 0, 15 do
      for x = 0, 15 do
        local _, _, _, a = get(x, y)
        bits[#bits + 1] = (a > 0) and "1" or "0"
        if a > 0 then count = count + 1 end
      end
    end
    return table.concat(bits), count
  end

  local bulba, bulbaCount = footprintMask(1)
  result(bulbaCount == ink, "the page footprint is the cached 16x16 art (" .. bulbaCount .. " px)")
  local female, femaleCount = footprintMask(29)
  local male, maleCount = footprintMask(32)
  result(femaleCount > 0 and maleCount > 0,
    "both NIDORAN load a footprint (" .. femaleCount .. "/" .. maleCount .. ")")
  result(female ~= male, "NIDORAN♀ and NIDORAN♂ do not share one footprint")
  result(female ~= bulba, "the NIDORAN footprint is not the BULBASAUR fallback")

  U.tap(game, "b")
  U.wait(20)
  result(Pokedex.screen == "ordered_list", "B returns to the list")
  for _ = 1, 28 do
    U.tap(game, "down")
    U.wait(3)
  end
  U.tap(game, "a")
  U.wait(30)
  result(Pokedex.screen == "data" and Pokedex.selectedSpecies == 29,
    "the list walks down to NIDORAN♀ (sp=" .. tostring(Pokedex.selectedSpecies) .. ")")
  U.shot(game, DIR .. "/import_dex_footprint_04_nidoran_f_footprint.png")

  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "b")
  U.wait(20)

  finish()
end

local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pokedex_bar_colors"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS pokedex_bar_colors")
    love.event.quit(0)
  else
    print("FAIL pokedex_bar_colors failures=" .. failures)
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
  local Dex = require("src.core.game3.dex")
  local Pokedex = require("src.ui.game3.pokedex")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  for _, sp in ipairs({ 1, 4, 7, 16, 152 }) do
    Dex.registerEncounter(session.dex, sp, session)
    Dex.registerCapture(session.dex, sp, session)
  end

  local function barPixel()
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    Pokedex.draw()
    love.graphics.setCanvas()
    local data = canvas:newImageData()
    local function px(x, y)
      local r, g, b = data:getPixel(x, y)
      return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
    end
    return { px(1, 1) }, { px(1, 158) }
  end

  local function same(a, r, g, b)
    return a[1] == math.floor(r * 255 + 0.5) and a[2] == math.floor(g * 255 + 0.5) and a[3] == math.floor(b * 255 + 0.5)
  end

  -- pokefirered/src/pokedex_screen.c:927 sKantoDexPalette
  Pokedex.show(session.dex, { session = session, mode = "kanto" })
  U.wait(30)
  local kr, kg, kb = PokedexChrome.getColor("bar_kanto")
  result(kr ~= nil, "chrome.lua carries bar_kanto")
  local top, bottom = barPixel()
  result(kr and same(top, kr, kg, kb) and same(bottom, kr, kg, kb),
    string.format("Kanto list bars are palette 15 colour 15 (%d,%d,%d)", top[1], top[2], top[3]))
  U.shot(game, DIR .. "/dex_kanto_list_bars.png")
  Pokedex.close()
  U.wait(20)

  -- pokefirered/src/pokedex_screen.c:925 sNationalDexPalette
  session.national_dex_unlocked = true
  Pokedex.show(session.dex, { session = session, mode = "national" })
  U.wait(30)
  local nr, ng, nb = PokedexChrome.getColor("bar_national")
  result(nr ~= nil, "chrome.lua carries bar_national")
  top, bottom = barPixel()
  result(nr and same(top, nr, ng, nb) and same(bottom, nr, ng, nb),
    string.format("National list bars are the national palette 15 colour 15 (%d,%d,%d)", top[1], top[2], top[3]))
  U.shot(game, DIR .. "/dex_national_list_bars.png")
  Pokedex.close()
  U.wait(10)
  finish()
end

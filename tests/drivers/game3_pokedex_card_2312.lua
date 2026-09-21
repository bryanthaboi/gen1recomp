local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pokedex_card_2312"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Dex = require("src.core.game3.dex")
  local Pokedex = require("src.ui.game3.pokedex")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  local session = Runtime.getSession()

  local function sample(drawFn)
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    drawFn()
    love.graphics.setCanvas()
    local data = canvas:newImageData()
    return function(x, y)
      local r, g, b = data:getPixel(x, y)
      return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
    end
  end

  local function px(get, x, y, want, label)
    local r, g, b = get(x, y)
    result(r == want[1] and g == want[2] and b == want[3],
      string.format("%s (%d,%d) = %d,%d,%d want %d,%d,%d", label, x, y, r, g, b, want[1], want[2], want[3]))
  end

  PokedexChrome.install()
  local sheet, variant = PokedexChrome.cardSheet()
  result(sheet ~= nil, "cache holds the dex tile sheet (needs an import at CACHE_VERSION 102)")
  if sheet then
    result(variant == "kanto", "new game uses the kanto sheet")
    local function tilePx(tile, x, y)
      local o = ((math.floor(tile / 8) * 8 + y) * 64 + (tile % 8) * 8 + x) * 4
      return { sheet:byte(o + 1), sheet:byte(o + 2), sheet:byte(o + 3) }
    end
    local function differ(a, b) return a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] end
    local backdrop = tilePx(0, 0, 0)
    local gutter = tilePx(5, 4, 0)
    local border = tilePx(5, 4, 1)
    local upper = tilePx(1, 4, 4)
    local divider = tilePx(8, 4, 1)
    local lower = tilePx(2, 4, 4)
    result(differ(border, upper) and differ(border, backdrop), "card border stands out from interior and backdrop")
    result(differ(divider, border) and differ(upper, lower), "divider and the two halves are distinct")

    local dataGet = sample(PokedexChrome.drawDataCardBg)
    px(dataGet, 120, 8, backdrop, "data backdrop above card")
    px(dataGet, 120, 16, gutter, "data top gutter")
    px(dataGet, 120, 17, border, "data top border")
    px(dataGet, 120, 40, upper, "data upper interior")
    px(dataGet, 120, 89, divider, "data divider")
    px(dataGet, 120, 120, lower, "data lower interior")
    px(dataGet, 120, 141, border, "data bottom border")
    px(dataGet, 120, 152, backdrop, "data backdrop below card")
    px(dataGet, 1, 40, border, "data left border")
    px(dataGet, 237, 40, border, "data right border")

    local areaGet = sample(PokedexChrome.drawAreaCardBg)
    px(areaGet, 120, 17, border, "area top border")
    px(areaGet, 120, 89, upper, "area has no divider")
    px(areaGet, 120, 141, border, "area bottom border")
    px(areaGet, 1, 120, border, "area left border")
  end

  Dex.registerEncounter(session.dex, 19, session)
  Dex.registerCapture(session.dex, 19, session)

  local closed = 0
  Pokedex.showRegistration(19, { session = session, onDone = function() closed = closed + 1 end })
  U.wait(30)
  result(Pokedex.screen == "registration", "registration screen open")
  result(Pokedex.subScreenPrev == "category_grid", "registration header uses the habitat page")
  result(Pokedex.currentCategory == "grassland", "registration header category is grassland")
  U.shot(game, DIR .. "/2312_01_registration_card.png")

  U.tap(game, "a")
  U.wait(20)
  result(closed == 1, "registration closed through _onClose")
  result(Pokedex.isOpen() == false, "pokedex closed")

  Pokedex.show(session.dex, { session = session, mode = "kanto" })
  U.wait(20)
  Pokedex.selectedSpecies = 19
  Pokedex.screen = "data"
  Pokedex.dataPage = 1
  Pokedex.page = "entry"
  U.wait(20)
  result(Pokedex.screen == "data", "browse entry open")
  U.shot(game, DIR .. "/2312_02_browse_card.png")

  Pokedex.dataPage = 2
  U.wait(20)
  U.shot(game, DIR .. "/2312_03_area_card.png")

  Pokedex.close()
  U.wait(10)

  if fails > 0 then
    print("FAILS " .. fails)
    love.event.quit(1)
    return
  end
  love.event.quit(0)
end

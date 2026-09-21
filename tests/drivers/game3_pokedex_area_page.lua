local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pokedex_area_page"

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
  local PokedexData = require("src.core.game3.pokedex_data")
  local session = Runtime.getSession()

  local function sample(drawFn, w, h)
    local canvas = love.graphics.newCanvas(w or 240, h or 160)
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

  local mapImg = PokedexChrome.getImage("map_kanto")
  result(mapImg ~= nil, "cache holds map_kanto (needs an import at CACHE_VERSION 103)")
  if mapImg then
    local mw, mh = mapImg:getDimensions()
    result(mw == 96 and mh == 72, string.format("kanto map is 96x72 (got %dx%d)", mw, mh))
    local get = sample(function() PokedexChrome.drawMap("kanto", 0, 0) end, 96, 72)
    local opaque, colors = 0, {}
    for y = 0, 71 do
      for x = 0, 95 do
        local r, g, b, a = get(x, y)
        if a > 0 then
          opaque = opaque + 1
          colors[r * 65536 + g * 256 + b] = true
        end
      end
    end
    local distinct = 0
    for _ in pairs(colors) do distinct = distinct + 1 end
    result(opaque > 2000, "kanto map paints real pixels (" .. opaque .. ")")
    result(distinct >= 3, "kanto map has more than a flat fill (" .. distinct .. " colors)")
  end

  result(PokedexChrome.getImage("blit_wide_ellipse") ~= nil, "cache holds the AREA UNKNOWN ellipse")
  result(PokedexChrome.getImage("mini_page") ~= nil, "cache holds mini_page")
  result(PokedexChrome.getImage("cat_grassland") ~= nil, "cache holds the category icons")
  result(PokedexChrome.getImage("caught_marker") ~= nil, "cache holds the caught marker")

  local mr, mg, mb, ma = PokedexChrome.getColor("marker")
  result(mr ~= nil, "chrome.lua supplies the marker blend color")
  local eva, evb = PokedexChrome.getMarkerBlend()
  result(eva ~= nil, "chrome.lua supplies the BLDALPHA pair")
  if mr and eva and mapImg then
    result(math.floor(ma * 255 + 0.5) == 191, "marker alpha is BLDALPHA eva 12/16")
    local mapOnly = sample(function() PokedexChrome.drawMap("kanto", 0, 0) end, 96, 72)
    local maskOnly = sample(function() PokedexChrome.drawAreaMarker("MARKER_MED_H", 32, 24) end, 96, 72)
    local both = sample(function()
      PokedexChrome.drawMap("kanto", 0, 0)
      PokedexChrome.drawAreaMarker("MARKER_MED_H", 32, 24)
    end, 96, 72)
    local function to5(c) return math.floor(c * 31 / 255 + 0.5) end
    local function to8(c) return math.floor(c * 255 / 31 + 0.5) end
    local marker = { to5(mr * 255), to5(mg * 255), to5(mb * 255) }
    local seen, bad, grounds, worst = 0, 0, {}, 0
    for y = 0, 71 do
      for x = 0, 95 do
        local _, _, _, a = maskOnly(x, y)
        if a > 0 then
          seen = seen + 1
          local below = { mapOnly(x, y) }
          local got = { both(x, y) }
          grounds[below[1] * 65536 + below[2] * 256 + below[3]] = true
          for i = 1, 3 do
            -- pokefirered/src/pokedex_area_markers.c:219
            local want = to8(math.min(31, math.floor((marker[i] * eva * 16 + to5(below[i]) * evb * 16) / 16)))
            local off = math.abs(got[i] - want)
            if off > worst then worst = off end
            if off > 8 then bad = bad + 1; break end
          end
        end
      end
    end
    local groundCount = 0
    for _ in pairs(grounds) do groundCount = groundCount + 1 end
    result(seen > 0, "marker has visible pixels over the map (" .. seen .. ")")
    result(groundCount >= 2, "marker covers more than one map color (" .. groundCount .. ")")
    result(bad == 0, string.format("marker over the map matches BLDALPHA(eva, evb) (%d of %d off, worst %d)",
      bad, seen, worst))
  end

  local trainerImg = PokedexChrome.getTrainerPic("male")
  result(trainerImg ~= nil, "size page can load the RED front pic")
  if trainerImg then
    local tw, th = trainerImg:getDimensions()
    result(tw == 64 and th == 64, string.format("trainer pic is 64x64 (got %dx%d)", tw, th))
  end

  local kantoSp, seviiSp
  for sp = 1, 151 do
    local areas = PokedexData.getWildAreasForSpecies(sp)
    if #areas > 0 then
      local anyKanto, allSevii = false, true
      for _, a in ipairs(areas) do
        if PokedexData.getAreaMapKey(a) == "kanto" then anyKanto = true; allSevii = false end
      end
      if anyKanto and not kantoSp then kantoSp = sp end
      if allSevii and not seviiSp then seviiSp = sp end
    end
  end
  result(kantoSp ~= nil, "found a species with Kanto markers (" .. tostring(kantoSp) .. ")")
  result(seviiSp ~= nil, "found a Sevii-only species (" .. tostring(seviiSp) .. ")")

  local function openPage2(sp)
    Dex.registerEncounter(session.dex, sp, session)
    Dex.registerCapture(session.dex, sp, session)
    Pokedex.show(session.dex, { session = session, mode = "kanto" })
    U.wait(10)
    Pokedex.selectedSpecies = sp
    Pokedex.screen = "data"
    Pokedex.page = "entry"
    Pokedex.dataPage = 2
    U.wait(20)
  end

  if kantoSp then
    openPage2(kantoSp)
    result(Pokedex.dataPage == 2, "area page open for the Kanto species")
    U.shot(game, DIR .. "/dexarea_01_kanto_area.png")
    Pokedex.close()
    U.wait(10)
  end

  if seviiSp then
    openPage2(seviiSp)
    result(Pokedex.dataPage == 2, "area page open for the Sevii-only species")
    U.shot(game, DIR .. "/dexarea_02_sevii_area_unknown.png")
    Pokedex.close()
    U.wait(10)
  end

  openPage2(95)
  result(Pokedex.dataPage == 2, "size page open for ONIX")
  U.shot(game, DIR .. "/dexarea_03_size_pair.png")
  Pokedex.close()
  U.wait(10)

  -- pokefirered/src/pokedex_screen.c:3427
  local closed = 0
  Dex.registerEncounter(session.dex, 19, session)
  Dex.registerCapture(session.dex, 19, session)
  Pokedex.showRegistration(19, { session = session, onDone = function() closed = closed + 1 end })
  U.wait(20)
  result(Pokedex.screen == "registration", "registration screen open")
  U.tap(game, "start")
  U.wait(20)
  result(closed == 0, "START does not close the registration card")
  result(Pokedex.isOpen() == true, "registration card still open after START")
  U.shot(game, DIR .. "/dexarea_04_registration_after_start.png")
  U.tap(game, "b")
  U.wait(20)
  result(closed == 1, "B closes the registration card")
  U.wait(10)

  if fails > 0 then
    print("FAILS " .. fails)
    love.event.quit(1)
    return
  end
  print("FAILS 0")
  love.event.quit(0)
end

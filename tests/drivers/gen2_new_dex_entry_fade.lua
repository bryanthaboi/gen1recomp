-- ../pokecrystal/engine/pokedex/new_pokedex_entry.asm:22-30
-- ../pokecrystal/home/fade.asm:35-62

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Chrome = require("src.ui.gen2.Chrome")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_new_dex_entry_fade"
  local version = tostring(game.save.version)
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail ~= nil and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_new_dex_entry_fade " .. version
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  local function stats(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local winW, winH = love.graphics.getDimensions()
    local ratio = image:getWidth() / winW
    local scale = Chrome.fitScale(winW, winH)
    local ox, oy = Chrome.fitOrigin(winW, winH, scale)
    local dark, ink = 0, 0
    for py = 0, Chrome.SCREEN_H * 8 - 1 do
      for px = 0, Chrome.SCREEN_W * 8 - 1 do
        local ix = math.floor((ox + (px + 0.5) * scale) * ratio)
        local iy = math.floor((oy + (py + 0.5) * scale) * ratio)
        local r, g, b = image:getPixel(ix, iy)
        r, g, b = r * 255, g * 255, b * 255
        if r < 40 and g < 40 and b < 40 then dark = dark + 1 end
        if r < 245 or g < 245 or b < 245 then ink = ink + 1 end
      end
    end
    return dark, ink
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "world booted") then return finish() end
  game.save.engineFlags = game.save.engineFlags or {}
  game.save.engineFlags[11] = true
  game.save.inventory = { MASTER_BALL = 10 }
  game.save.party = { Mon.new(game.data, "CYNDAQUIL", 30) }
  game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
  game.save.pokedex.caught.PIDGEY = nil
  if not check(world:startBattle({ wild = Mon.new(game.data, "PIDGEY", 3) }), "battle started") then
    return finish()
  end
  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not check(screen ~= nil, "battle screen up") then return finish() end
  for _ = 1, 400 do
    if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
    U.tap(game, "a")
    U.wait(3)
  end
  screen:useItem("MASTER_BALL")

  local dex
  for _ = 1, 3000 do
    local top = game.stack:top()
    if top and top ~= screen and top.newEntry then dex = top break end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    U.wait(1)
  end
  if not check(dex ~= nil, "NewPokedexEntry screen opened") then return finish() end
  U.wait(20)
  U.tap(game, "a")
  U.wait(20)
  check(dex.page == 2, "page 2 is up")
  local page2 = dir .. "/fade_01_page2.png"
  U.still(game, page2)
  local dark0, ink0 = stats(page2)
  check((dark0 or 0) > 0, "page 2 has black ink before the fade", dark0)
  U.tap(game, "a")
  check(game.stack:top() == dex, "the second press does not leave the dex at once")

  local function shotAt(tick, name, want)
    for _ = 1, 60 do
      if not dex.closeFade or dex.closeFade >= tick then break end
      U.wait(1)
    end
    local bgp = dex:closeFadeBgp()
    check(bgp == want, ("fade frame %d is BGP $%02x"):format(tick, want), bgp)
    local path = dir .. "/" .. name
    U.still(game, path)
    return stats(path)
  end
  local dark1 = shotAt(4, "fade_02_bgp90_no_black.png", 0x90)
  check(dark1 == 0, "BGP $90 leaves no black on the dex", dark1)
  local dark2, ink2 = shotAt(12, "fade_03_bgp40_lighter.png", 0x40)
  check(dark2 == 0 and (ink2 or 0) > 0 and ink2 <= ink0, "BGP $40 is lighter still", ink2)
  local _, ink3 = shotAt(20, "fade_04_bgp00_white.png", 0x00)
  check(ink3 == 0, "BGP $00 is a white screen", ink3)

  for _ = 1, 60 do
    if game.stack:top() ~= dex then break end
    U.wait(1)
  end
  check(game.stack:top() == screen, "the dex closes after the fade")
  check(screen.captureScreen == "dexpic", "back on the front pic screen", screen.captureScreen)
  finish()
end

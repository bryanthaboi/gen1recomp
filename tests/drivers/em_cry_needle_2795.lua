local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_cry_needle_2795"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_cry_needle_2795 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function loadShot(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
end

local function needleAt(img, x, y)
  local k = math.floor(math.min(img:getWidth() / 240, img:getHeight() / 160))
  local ox, oy = (img:getWidth() - 240 * k) / 2, (img:getHeight() - 160 * k) / 2
  local r, g, b = img:getPixel(math.floor(ox + (x + 0.5) * k), math.floor(oy + (y + 0.5) * k))
  return r > 0.8 and g < 0.6 and b > 0.3 and b < 0.7
end

local function countAlong(img, x0, y0, x1, y1)
  local n = 0
  for i = 0, 10 do
    local t = i / 10
    if needleAt(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t) then n = n + 1 end
  end
  return n
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Dex = require("src.core.game3.dex")
  local Pokedex = require("src.ui.game3.rse.pokedex")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "new game session") then return finish() end
  Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 10, facing = "down" })
  U.wait(40)
  session.dex = session.dex or Dex.new()
  Dex.setSeen(session.dex, C.species.byName.SPECIES_TORCHIC)
  Dex.setCaught(session.dex, C.species.byName.SPECIES_TORCHIC)

  local function waitFn(name, limit)
    for _ = 1, limit or 600 do
      local s = Pokedex.active()
      if s and s.fn == name then return true end
      U.wait(1)
    end
    return false
  end

  Pokedex.show(session.dex, { session = session })
  local s = Pokedex.active()
  if not check(s ~= nil and waitFn("mainInput", 300), "pokedex list") then return finish() end
  for _ = 1, 20 do
    if s.list.items[s.selected] and s.list.items[s.selected].owned then break end
    U.hold(game, "down", 1)
    U.wait(20)
  end
  U.tap(game, "a")
  if not check(waitFn("infoInput", 400), "info page") then return finish() end
  U.tap(game, "right")
  U.wait(10)
  U.tap(game, "a")
  if not check(waitFn("cryInput", 400), "cry page") then return finish() end
  U.wait(60)
  check(s.cry and s.cry.needle.rotation == 32, "needle rests at MIN_NEEDLE_POS 32")
  local path = DIR .. "/2795_01_needle_rest.png"
  U.still(game, path)
  local img = loadShot(path)
  if check(img ~= nil, "shot readable") then
    local left = countAlong(img, 158, 52, 180, 74)
    local right = countAlong(img, 188, 74, 210, 52)
    print(string.format("[driver] needle pixels up-left=%d up-right=%d", left, right))
    check(left >= 8, "needle leans up-left from its foot")
    check(right <= 2, "nothing on the mirrored up-right diagonal")
  end
  finish()
end

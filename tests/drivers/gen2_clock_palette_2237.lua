-- ../pokecrystal/engine/rtc/timeset.asm:22-27
-- ../pokecrystal/engine/gfx/cgb_layouts.asm:509-521
--   POKEPORT_VERSION=crystal|gold POKEPORT_IDENTITY=<sandbox> POKEPORT_BOOT_CINEMA=1 \
--     POKEPORT_TOUCH=0 POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/gen2_clock_palette_2237.lua love .
local U = require("tests.drivers.util")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"
local VERSION = os.getenv("POKEPORT_VERSION") or "crystal"

return function(game)
  local fails = 0
  local function say(line) print("[2237] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function top() return game.stack:top() end
  local function isA(class)
    local state = top()
    return state ~= nil and getmetatable(state) == class
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function waitFor(label, pred, frames)
    for _ = 1, frames or 900 do
      if pred() then return true end
      U.wait(1)
    end
    say("FAIL stalled on " .. label .. " top=" .. tostring(top()))
    love.event.quit(1)
    return false
  end

  local function pixel(path, dx, dy)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local data = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = data:getWidth(), data:getHeight()
    local x = math.floor(w / 2 + dx)
    local y = math.floor(h / 2 + dy)
    if x < 0 or y < 0 or x >= w or y >= h then return nil end
    local r, g, b = data:getPixel(x, y)
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
  end
  local function white(path, dx, dy, label)
    local r, g, b = pixel(path, dx, dy)
    ok(r == 255 and g == 255 and b == 255,
      ("%s box fill (%s,%s,%s)"):format(label, tostring(r), tostring(g), tostring(b)))
  end

  local shots = SHOT_DIR .. "/2237_%02d_%s_white_" .. VERSION .. ".png"

  for _ = 1, 900 do
    if isA(MainMenu) then break end
    tap("start", 2)
  end
  if not waitFor("main menu", function() return isA(MainMenu) end) then return end
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")
  if not waitFor("gender or clock",
    function() return isA(GenderSelect) or isA(InitClock) end, 600) then return end
  if isA(GenderSelect) then
    waitFor("gender menu", function() return isA(GenderSelect) and top():menuOpen() end, 600)
    tap("a")
  end
  if not waitFor("clock", function() return isA(InitClock) end, 400) then return end
  local clock = top()
  waitFor("clock fade", function() return clock.fade == nil end, 400)
  for _ = 1, 40 do
    if clock.phase == "hour" then break end
    waitFor("typer", function() return clock.typer == nil or clock.typer:done() end, 600)
    tap("a", 6)
  end
  ok(clock.phase == "hour", "hour picker up")
  U.wait(20)
  local hourShot = shots:format(1, "intro_hour")
  U.shot(game, hourShot)
  white(hourShot, 0, 260, "hour prompt")
  U.wait(5)
  for _ = 1, 10 do
    if clock.phase == "confirm-hour" then break end
    waitFor("typer", function() return clock.typer == nil or clock.typer:done() end, 600)
    tap("a", 6)
  end
  waitFor("confirm", function() return clock.phase == "confirm-hour" end, 300)
  waitFor("typer2", function() return clock.typer == nil or clock.typer:done() end, 600)
  U.wait(20)
  local confirmShot = shots:format(2, "intro_confirm")
  U.shot(game, confirmShot)
  white(confirmShot, 0, 260, "confirm prompt")
  white(confirmShot, 310, 20, "YES/NO")
  local pal = InitClock.PALETTE[1]
  ok(pal[1] == 255 and pal[2] == 255 and pal[3] == 255, "PREDEFPAL_DIPLOMA colour 0 white")
  say("done fails=" .. fails)
  love.event.quit(fails == 0 and 0 or 1)
end

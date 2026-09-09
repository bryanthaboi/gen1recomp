-- Mom's SetDayOfWeek wheel drawn over the living room (#2232).
-- ../pokecrystal/engine/rtc/timeset.asm:385
-- ../pokecrystal/maps/PlayersHouse1F.asm:49
--
--   POKEPORT_VERSION=crystal POKEPORT_IDENTITY=<sandbox> POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=<dir> POKEPORT_DRIVER=tests/drivers/crystal_day_wheel_bug2232.lua love .
local U = require("tests.drivers.util")
local Chrome = require("src.ui.gen2.Chrome")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2232] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function dayWheel()
    local top = game.stack and game.stack:top()
    if top and top.mode == "day" and top.pickerBox then return top end
    return nil
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the crystal world did not boot")
    return
  end

  -- ../pokecrystal/maps/PlayersHouse1F.asm:395
  world:setMap("PLAYERS_HOUSE_1F", 7, 3, "down")
  U.wait(20)
  for _ = 1, 3 do tap("down", 8) end
  U.wait(40)
  ok(world.map and world.map.id == "PLAYERS_HOUSE_1F", "in the living room")

  local wheel
  for _ = 1, 300 do
    wheel = dayWheel()
    if wheel then break end
    tap("a", 4)
  end
  ok(wheel ~= nil, "Mom's scene reached the day-of-week wheel")
  if not wheel then return end

  local seen
  local drawPanel = wheel.drawPanel
  wheel.drawPanel = function(self)
    seen = { love.graphics.getScissor() }
    return drawPanel(self)
  end
  U.wait(3)
  wheel.drawPanel = drawPanel
  local w, h = love.graphics.getDimensions()
  local scale = Chrome.fitScale(w, h)
  local ox, oy = Chrome.fitOrigin(w, h, scale)
  ok(seen ~= nil, "the wheel drew its panel")
  if seen then
    ok(seen[1] == ox and seen[2] == oy
      and seen[3] == 160 * scale and seen[4] == 144 * scale,
      ("the wheel clips to the panel %d,%d %dx%d, got %s,%s %sx%s"):format(
        ox, oy, 160 * scale, 144 * scale,
        tostring(seen[1]), tostring(seen[2]), tostring(seen[3]), tostring(seen[4])))
  end
  U.shot(game, SHOT_DIR .. "/2232_day_wheel.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  say("the SUNDAY picker at the top right and \"What day is it?\" should both")
  say("be on screen over the living room. a bare room with Mom next to you")
  say("and nothing to answer is the bug. up/down changes the day, A confirms.")
  while true do U.wait(60) end
end

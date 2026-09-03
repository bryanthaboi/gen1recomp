local U = require("tests.drivers.util")

-- ../pokecrystal/engine/rtc/timeset.asm:385
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2138] " .. line) end
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

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  -- ../pokecrystal/maps/PlayersHouse1F.asm:395
  world:warpToMapId("PLAYERS_HOUSE_1F", 9, 1, "down")
  U.wait(30)
  ok(world.map and world.map.id == "PLAYERS_HOUSE_1F", "standing at the top of the stairs")
  for _ = 1, 3 do tap("down", 10) end
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/2138_scene_start.png")

  local wheel
  for _ = 1, 120 do
    wheel = dayWheel()
    if wheel then break end
    tap("a", 6)
  end
  if not wheel then
    say("the Mom scene did not reach SetDayOfWeek; pushing the wheel directly")
    world:setDayOfWeek(function() end)
    U.wait(10)
    wheel = dayWheel()
  end
  ok(wheel ~= nil, "the day-of-week wheel is up")
  if wheel then
    ok(wheel.isOpaque == false, "and it is an overlay, not an opaque page")
    ok(not wheel:drawsWidescreen(), "with no widescreen surround of its own")
  end
  U.wait(10)
  U.shot(game, SHOT_DIR .. "/2138_day_wheel.png")
  say("eyeball 2138_day_wheel.png: the living room, Mom and the player stay "
    .. "visible around the SUNDAY picker and the question box")

  tap("a", 20)
  U.shot(game, SHOT_DIR .. "/2138_confirm.png")
  say("eyeball 2138_confirm.png: YES/NO box at (14,7), YES on row 8, NO on row 10")
  tap("a", 30)
  ok(dayWheel() == nil, "YES pops the wheel")
  U.shot(game, SHOT_DIR .. "/2138_after.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end

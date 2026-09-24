local U = require("tests.drivers.util")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

return function(game)
  U.newGame(game)
  local o = game.save.options
  game.speedOverride = nil
  o.speedOverworld = 1
  key("1")
  expect(o.speedOverworld == 2, "red_1_bumps_overworld")
  key("kp1")
  expect(o.speedOverworld == 3, "red_numpad_1_bumps")
  game:gamepadaxis(nil, "triggerright", 1)
  game:gamepadaxis(nil, "triggerright", 0)
  expect(o.speedOverworld == 4, "red_rt_bumps")
  game:gamepadaxis(nil, "triggerleft", 1)
  game:gamepadaxis(nil, "triggerleft", 0)
  expect(o.speedOverworld == 3, "red_lt_lowers")
  expect(game:logicSpeed() == 3, "red_logic_follows_overworld")
  game.speedOverride = 1
  love.event.quit(failed and 1 or 0)
end

local U = require("tests.drivers.util")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

local function steps(game, frames)
  local n = 0
  local orig = game.fixedUpdate
  game.fixedUpdate = function(self, dt) n = n + 1; return orig(self, dt) end
  for _ = 1, frames do game:update(1 / 60) end
  game.fixedUpdate = orig
  return n
end

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  expect(game.phase == "field", "h1_field_reached")

  game.speedOverride = nil
  game.options.speedOverworld = 1
  game.options.speedMenu = 1
  love.keypressed("escape", "escape", false)
  U.wait(2)
  love.keyreleased("escape", "escape")
  U.wait(20)
  expect(require("src.ui.game3.stack").busy(), "h1_start_menu_open")
  key("1")
  expect(game.options.speedOverworld == 2 and game.options.speedMenu == 1,
    "h1_start_menu_1_bumps_overworld")
  game.speedOverride = 1
  U.still(game, ".bazinga/BSA/09-24-26-01-followup/shots/game3_speed_hotkey_h1/h1_start_menu_speed2.png")
  game.speedOverride = nil
  love.keypressed("escape", "escape", false)
  U.wait(2)
  love.keyreleased("escape", "escape")
  U.wait(30)
  expect(game:logicSpeed() == 2 and steps(game, 10) == 20, "h1_start_menu_closed_walk_2x")

  key("kp1")
  expect(game.options.speedOverworld == 3, "h1_numpad_1_bumps")

  game:gamepadaxis(nil, "triggerright", 1)
  game:gamepadaxis(nil, "triggerright", 0)
  expect(game.options.speedOverworld == 4, "h1_rt_bumps")
  game:gamepadaxis(nil, "triggerleft", 1)
  game:gamepadaxis(nil, "triggerleft", 0)
  expect(game.options.speedOverworld == 3, "h1_lt_lowers")
  game:gamepadpressed(nil, "rightshoulder")
  game:gamepadreleased(nil, "rightshoulder")
  expect(game.options.speedOverworld == 3, "h1_r_shoulder_stays_r")

  package.loaded["src.core.game3.link"].link = {}
  expect(game:logicSpeed() == 1, "h1_link_locked_1x")
  package.loaded["src.core.game3.link"].link = nil
  expect(game:logicSpeed() == 3, "h1_link_unlocked")

  game.speedOverride = 1
  love.event.quit(failed and 1 or 0)
end

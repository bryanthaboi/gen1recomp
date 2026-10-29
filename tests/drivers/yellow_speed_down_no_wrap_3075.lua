local U = require("tests.drivers.util")
local GameSpeed = require("src.core.GameSpeed")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

local function speeds(game)
  local o = game.save.options
  return o.speedOverworld, o.speedBattle, o.speedMenu
end

local function allAt(game, v)
  local a, b, c = speeds(game)
  return a == v and b == v and c == v
end

local function setAll(game, v)
  for _, c in ipairs(GameSpeed.CATEGORIES) do
    game.save.options[GameSpeed.optionKey(c)] = v
  end
end

local function pad(button)
  love.gamepadpressed(nil, button)
  U.wait(2)
  love.gamepadreleased(nil, button)
  U.wait(2)
end

local function trigger(axis)
  love.gamepadaxis(nil, axis, 1)
  U.wait(2)
  love.gamepadaxis(nil, axis, 0)
  U.wait(2)
end

return function(game)
  U.wait(45)
  expect(game.save and game.save.options ~= nil, "yellow_booted_with_options")
  game.speedOverride = nil
  setAll(game, 1)
  pad("leftshoulder")
  expect(allAt(game, 1), "yellow_speed_down_pad_at_normal_stays_normal")
  trigger("triggerleft")
  expect(allAt(game, 1), "yellow_speed_down_trigger_at_normal_stays_normal")
  love.keypressed("0", "0", false)
  love.keyreleased("0", "0")
  expect(allAt(game, 1), "yellow_key_0_at_normal_stays_normal")
  expect(game:logicSpeed() == 1, "yellow_logic_speed_normal")
  pad("rightshoulder")
  expect(allAt(game, 2), "yellow_speed_up_pad_from_normal_rises")
  trigger("triggerright")
  expect(allAt(game, 3), "yellow_speed_up_trigger_rises_again")
  pad("leftshoulder")
  expect(allAt(game, 2), "yellow_speed_down_pad_still_lowers")
  setAll(game, GameSpeed.LEVELS[#GameSpeed.LEVELS])
  pad("rightshoulder")
  expect(allAt(game, 1), "yellow_speed_up_at_top_wraps_to_normal")
  local saved = require("src.core.SaveData").loadOptions()
  expect(saved and saved.speedOverworld == 1, "yellow_speed_persists")
  game.speedOverride = 1
  love.event.quit(failed and 1 or 0)
end

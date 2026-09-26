local U = require("tests.drivers.util")
local Music = require("src.core.Music")
local function run(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/radio2485"
  local version = os.getenv("POKEPORT_VERSION") or "gen2"
  local function shot(name)
    U.wait(8)
    U.shot(game, out .. "/2485_" .. version .. "_" .. name .. ".png")
  end
  U.wait(45)
  assert(game.world and game.world.map, "Gen2 world did not boot")
  game.world:warpToMapId("GOLDENROD_CITY", 12, 20, "down")
  local ready
  for _ = 1, 600 do
    ready = not game.stack:top() and game.world.map.id == "GOLDENROD_CITY"
      and game.world:acceptsMenuInput()
    if ready then break end
    U.wait(1)
  end
  assert(ready, "Goldenrod warp did not become ready for menu input")
  game.world:setEngineFlag(4, true)
  game.world:setEngineFlag(0, true)
  game:openStartMenuItem("pokegear")
  local gear
  for _ = 1, 180 do
    local top = game.stack:top()
    if top and top.screenId == "Gen2Pokegear" then gear = top break end
    U.wait(1)
  end
  assert(gear and gear.cards, "Pokegear did not open after the menu fade")
  for i, card in ipairs(gear.cards) do
    if card.id == "radio" then gear.cardIndex = i end
  end
  assert(gear:card().id == "radio", "Radio Card not unlocked")
  gear.mode = "card"
  U.wait(4)
  assert(gear.tuningKnob == 0, "initial knob is not zero")
  for _ = 1, 8 do U.tap(game, "up") U.wait(2) end
  assert(gear.tuningKnob == 16, "eight Up presses must reach 04.5")
  assert(gear.radioShow ~= nil and gear.radio ~= nil, "04.5 did not tune")
  U.wait(10)
  local song = Music.current()
  assert(song ~= nil, "04.5 music absent")
  shot("station_04.5")
  U.tap(game, "up") U.wait(4)
  assert(gear.tuningKnob == 18 and gear:currentStation().frequency == "05.0",
    "Up skipped half-step frequency")
  assert(not gear.radio and not gear.radioShow and not gear:currentStation().name,
    "dead-air display was not cleared")
  assert(not gear.radioSong and Music.current() == nil, "dead-air music not stopped")
  print("[driver] PASS radio_2485_half_step_dead_air")
  shot("dead_air_05.0")
  U.tap(game, "down") U.wait(4)
  assert(gear.tuningKnob == 16 and gear.radioShow ~= nil, "Down did not retune 04.5")
  assert(Music.current() == song, "same-channel music did not resume")
  print("[driver] PASS radio_2485_same_channel_resume")
  shot("restored_station_04.5")
  U.tap(game, "up") U.wait(4)
  local styled = gear.styled
  gear.styled = function() return false end
  shot("plain_dead_air_05.0")
  gear.styled = styled
  for _ = 1, 45 do U.tap(game, "up") end
  assert(gear.tuningKnob == 80, "upper knob did not clamp at 80")
  for _ = 1, 45 do U.tap(game, "down") end
  assert(gear.tuningKnob == 0, "lower knob did not clamp at zero")
  print("[driver] PASS radio_2485_clamps")
end

return function(game)
  local ok, err = xpcall(function() run(game) end, debug.traceback)
  if not ok then print("[driver] FAIL radio_2485 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end

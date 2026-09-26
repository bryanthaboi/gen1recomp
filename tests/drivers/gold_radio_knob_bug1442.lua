-- Eyeball driver (#1442): the radio card's tuning knob.  PokegearRadio_Init
-- spawns SPRITE_ANIM_OBJ_RADIO_TUNING_KNOB on tile $08 and AnimateTuningKnob
-- writes wRadioTuningKnob into its XOFFSET, so a red needle stands in the dial
-- box at screen x = 72 + knob and steps with every UP/DOWN.  Before the fix the
-- card drew the dial art and nothing in it.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_SHOTS=/tmp/radioknob \
--     POKEPORT_DRIVER=tests/drivers/gold_radio_knob_bug1442.lua \
--     perl -e 'alarm 300; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
local U = require("tests.drivers.util")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("POKEPORT_SHOTS") or "/tmp/radioknob"

local function run(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  -- Goldenrod, where the card is handed out, and the two engine flags the
  -- START menu and the strip read: ENGINE_POKEGEAR and ENGINE_RADIO_CARD.
  world:warpToMapId("GOLDENROD_CITY", 12, 20, "down")
  world:setEngineFlag(4, true) -- ENGINE_POKEGEAR
  world:setEngineFlag(0, true) -- ENGINE_RADIO_CARD
  local ready
  for _ = 1, 600 do
    ready = not game.stack:top() and world.map.id == "GOLDENROD_CITY"
      and world:acceptsMenuInput()
    if ready then break end
    U.wait(1)
  end
  assert(ready, "Goldenrod warp did not become ready for menu input")

  game:openStartMenuItem("pokegear")
  local gear
  for _ = 1, 180 do
    local top = game.stack:top()
    if top and top.screenId == "Gen2Pokegear" then gear = top break end
    U.wait(1)
  end
  assert(gear and gear.cards, "the POKeGEAR did not open after the menu fade")
  gear.mode = "card"
  for index, card in ipairs(gear.cards) do
    if card.id == "radio" then gear.cardIndex = index end
  end
  assert(gear:card().id == "radio", "the RADIO card is missing from the strip")
  U.wait(5)

  for _ = 1, 8 do U.tap(game, "up") U.wait(4) end
  assert(gear:currentStation().knob == 16, "04.5 knob missing")
  U.shot(game, SHOTS .. "/1442_radio_04.5.png")
  U.log("knob", tostring(gear:currentStation().knob), "at 04.5")

  for _ = 1, 8 do U.tap(game, "up") U.wait(4) end
  assert(gear:currentStation().knob == 32, "08.5 knob missing")
  U.shot(game, SHOTS .. "/1442_radio_08.5.png")
  U.log("knob", tostring(gear:currentStation().knob), "at 08.5")

  print("[driver] PASS radio_knob_1442")
end

return function(game)
  local ok, err = xpcall(function() run(game) end, debug.traceback)
  if not ok then print("[driver] FAIL radio_knob_1442 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end

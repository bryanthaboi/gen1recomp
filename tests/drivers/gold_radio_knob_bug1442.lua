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
-- The run parks on the radio card with the knob on 08.5, so UP and DOWN move
-- the needle by hand.
local U = require("tests.drivers.util")

local SHOTS = os.getenv("POKEPORT_SHOTS") or "/tmp/radioknob"

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  -- Goldenrod, where the card is handed out, and the two engine flags the
  -- START menu and the strip read: ENGINE_POKEGEAR and ENGINE_RADIO_CARD.
  assert(world:setMap("GOLDENROD_CITY", 12, 20, "down"),
    "setMap failed for GOLDENROD_CITY")
  world:setEngineFlag(4, true) -- ENGINE_POKEGEAR
  world:setEngineFlag(0, true) -- ENGINE_RADIO_CARD
  U.wait(5)

  game:openStartMenuItem("pokegear")
  U.wait(5)
  local gear = game.stack:top()
  assert(gear and gear.cards, "the POKeGEAR did not open")
  gear.mode = "card"
  for index, card in ipairs(gear.cards) do
    if card.id == "radio" then gear.cardIndex = index end
  end
  assert(gear:card().id == "radio", "the RADIO card is missing from the strip")
  U.wait(5)

  -- 04.5, the bottom of the dial: the needle sits at the left of the box.
  U.shot(game, SHOTS .. "/01-radio-04.5.png")
  U.log("knob", tostring(gear:currentStation().knob), "at 04.5")

  U.tap(game, "up") U.wait(4)
  U.tap(game, "up") U.wait(4)
  U.shot(game, SHOTS .. "/02-radio-08.5.png")
  U.log("knob", tostring(gear:currentStation().knob), "at 08.5")

  U.log("compare 01 and 02: a red needle stands in the dial box and has",
    "moved right; UP/DOWN now walk it by hand")
  while true do
    coroutine.yield()
  end
end

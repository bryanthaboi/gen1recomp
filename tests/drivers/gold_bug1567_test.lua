-- #1567: the TM/HM pocket's row order.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1567_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1567   (default)
--
-- Nothing here can be asserted: the bug IS the order rows land in.
-- TMHM_DisplayPocketItems walks the fixed 57-byte wTMsHMs array from 1 to 57
-- and prints every non-zero slot (engine/items/tmhm.asm:341), so the cart's
-- pocket is always TM01..TM50 then HM01..HM07 no matter what the player picked
-- up first.  The port drew it from the acquisition-ordered bag list instead.
--
-- The seed is deliberately scrambled -- gold_bug1425_test.lua seeds its TMs
-- already in numeric order, which is why its screenshots never showed this.
--
-- The run ends with the PACK still open on the TM pocket, so a human takes the
-- controls exactly where the screenshots stop.
local U = require("tests.drivers.util")

local Bag = require("src.inventory.Bag")
local PackMenu = require("src.ui.gen2.PackMenu")

-- Picked up back to front: TM/HM numbers 57, 50, 51, 5, 1, 53.  TM_ROAR is the
-- one on the far side of the ITEM_C3 hole (id $c4, number 5), so it also pins
-- that the number and not the item id is what sorts.
local SEED = {
  { "HM_WATERFALL", 1 },
  { "TM_NIGHTMARE", 2 },
  { "HM_CUT", 1 },
  { "TM_ROAR", 3 },
  { "TM_DYNAMICPUNCH", 12 },
  { "HM_SURF", 1 },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1567"

  local function shot(name)
    U.wait(3)
    U.shot(game, ("%s/%s.png"):format(out, name))
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local save = game.save
  save.inventory = {}
  save.bagOrder = {}
  for _, entry in ipairs(SEED) do
    local id, count = entry[1], entry[2]
    if not (game.data.items and game.data.items[id]) then
      U.log("[driver] SKIP", id, "-- not in this cache")
    else
      save.inventory[id] = count
      table.insert(Bag.order(save), id)
    end
  end
  -- A POTION and a SUPER POTION so the ITEM pocket can be compared against the
  -- TM pocket at the end: SELECT must still arm a row over there.
  for _, entry in ipairs({ { "POTION", 5 }, { "SUPER_POTION", 2 } }) do
    if game.data.items and game.data.items[entry[1]] then
      save.inventory[entry[1]] = entry[2]
      table.insert(Bag.order(save), entry[1])
    end
  end

  U.log("[driver] pickup order:", table.concat(Bag.order(save), " "))

  local pack = PackMenu.new(game, { save = save, world = game.world,
    onClose = function() end })
  game.stack:push(pack)

  shot("00-items")            -- POTION over SUPER POTION, pickup order
  U.tap(game, "right")
  U.tap(game, "right")
  U.tap(game, "right")
  -- TM01 DYNAMICPUNCH ×12, TM05 ROAR ×03, TM50 NIGHTMARE ×02, then HM01 CUT,
  -- HM03 SURF, HM07 WATERFALL with no ×NN at all (engine/items/tmhm.asm:390).
  -- Before the fix this read HM07, TM50, HM01, TM05, TM01, HM03.
  shot("01-tmhm-numbered")

  local order = {}
  for i = 1, #pack.rows do order[i] = pack.rows[i].id end
  U.log("[driver] TM/HM rows:", table.concat(order, " "))

  -- engine/items/tmhm.asm:207 filters SELECT out of this pocket: no hollow ▷,
  -- no "Where should this be moved to?".
  U.tap(game, "select")
  shot("02-tmhm-select-ignored")
  U.tap(game, "down")
  U.tap(game, "select")
  shot("03-tmhm-select-ignored-row2")

  -- The ITEM pocket, where SELECT still arms (engine/items/pack.asm:1290).
  U.tap(game, "right")
  U.tap(game, "select")
  shot("04-items-select-arms")
  U.tap(game, "b")

  -- Back to the TM pocket for the human.
  U.tap(game, "right")
  U.tap(game, "right")
  U.tap(game, "right")
  U.log("[driver] shots in " .. out .. " -- the PACK is yours")
end

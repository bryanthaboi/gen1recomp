-- #1425 (and #1424): the PACK's ×NN column.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1425_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1425   (default)
--
-- Nothing here can be asserted: the bug IS the column a digit lands in.
-- PlaceMenuItemQuantity's `lb bc, 1, 2` (engine/menus/menu_2.asm:24) is a
-- two-digit field with the leading digit blanked, so a ×5 and a ×50 must have
-- their ones digit in the SAME column; the port printed "×5" hard against the
-- cross.  Each pocket is seeded with a one-digit and a two-digit count stacked
-- next to each other so the two rows can be read off against one another, and
-- the TM pocket is here because its rows used to print no count at all.
--
-- The run ends with the PACK still open on the TM pocket, so a human takes the
-- controls exactly where the screenshots stop.
local U = require("tests.drivers.util")

local Bag = require("src.inventory.Bag")
local PackMenu = require("src.ui.gen2.PackMenu")

-- One-digit and two-digit counts side by side in every pocket that shows one.
local SEED = {
  { "POTION", 5 },
  { "SUPER_POTION", 50 },
  { "ANTIDOTE", 1 },
  { "FULL_HEAL", 99 },
  { "POKE_BALL", 7 },
  { "GREAT_BALL", 12 },
  { "TM_DYNAMICPUNCH", 1 },
  { "TM_HEADBUTT", 3 },
  { "TM_THUNDER", 24 },
  { "HM_CUT", 1 },
  { "HM_SURF", 1 },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1425"

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

  local pack = PackMenu.new(game, { save = save, world = game.world,
    onClose = function() end })
  game.stack:push(pack)

  shot("00-items")            -- ×5 over ×50: the ones digits line up
  U.tap(game, "right")
  shot("01-balls")            -- ×7 over ×12
  U.tap(game, "right")
  shot("02-key-items")        -- no counts at all here
  U.tap(game, "right")
  shot("03-tmhm")             -- TMs carry ×NN, the two HMs carry none

  -- SELECT arms the row instead of registering it (#1427): the hollow ▷ marks
  -- TM_HEADBUTT while "Where should this be moved to?" holds the box.
  U.tap(game, "down")
  U.tap(game, "select")
  shot("04-tmhm-armed")
  U.tap(game, "up")
  shot("05-tmhm-destination")
  U.tap(game, "a")
  shot("06-tmhm-moved")       -- HEADBUTT is now the first TM row

  U.log("[driver] bag order:", table.concat(Bag.order(save), " "))

  -- Back to the ITEM pocket and into a TOSS, whose own box prints the count
  -- with leading zeros (×01, not × 1).
  U.tap(game, "left")
  U.tap(game, "left")
  U.tap(game, "left")
  U.tap(game, "a")
  U.tap(game, "down")
  U.tap(game, "down")
  U.tap(game, "a")
  shot("07-toss-quantity")

  U.log("[driver] shots in " .. out .. " -- the PACK is yours")
end

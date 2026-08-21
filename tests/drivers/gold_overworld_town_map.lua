-- Real-LÖVE assertion driver for `_TownMap`, the view-only map opened by
-- Gold/Silver wall maps and the bedroom poster.
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_overworld_town_map.lua \
--     POKEPORT_IDENTITY=<identity-with-a-gold-cache> love .
--
-- The ROM-free suite pins the special/coroutine contract.  This driver adds
-- the integration boundary it cannot cover: a booted World pushes the real
-- Gen2Pokegear screen, renders it without the MAP card, ignores A, and hands
-- control back only after B.

local U = require("tests.drivers.util")

return function(game)
  local failures = 0
  local function check(condition, message)
    if condition then
      print("[town-map] ok   " .. message)
    else
      failures = failures + 1
      print("[town-map] FAIL " .. message)
    end
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "Gen 2 world did not boot")

  -- Prove the wall-map viewer is independent of POKéGEAR ownership.
  game.save.engineFlags = {}
  local originalTop = game.stack:top()
  local completed = 0
  check(world:showTownMap(function() completed = completed + 1 end),
    "World accepts the view-only town-map request")
  U.wait(5) -- render several real frames before inspecting/closing it

  local map = game.stack:top()
  check(map ~= originalTop and map.viewMap == true,
    "the booted world pushed a view-only map screen")
  check(map.mode == "card" and map:card() and map:card().id == "map",
    "the screen opened directly on the map")
  check(#map.cards == 1 and not map.fly,
    "no POKéGEAR strip or FLY destination picker is exposed")

  U.tap(game, "a")
  U.wait(3)
  check(game.stack:top() == map and completed == 0,
    "A cannot close the wall map")

  U.tap(game, "b")
  U.wait(3)
  check(game.stack:top() == originalTop and completed == 1,
    "B closes the map and resumes its caller exactly once")

  print(failures == 0 and "PASS gold_overworld_town_map"
    or ("FAIL gold_overworld_town_map (%d)"):format(failures))
  if failures > 0 then error("gold_overworld_town_map failed", 0) end
  -- Returning lets main.lua observe the completed driver coroutine and issue
  -- the normal successful quit event after all worker cleanup is in place.
end

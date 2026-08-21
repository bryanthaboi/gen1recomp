-- Real-LÖVE smoke capture for the committed ROM-free dataset.  This is kept
-- deliberately small: its job is to prove that main.lua routes past the ROM
-- importer, Data loads the fixture, the game reaches an overworld, and a GPU
-- frame can be encoded.  Layout-specific drivers remain free to add goldens.

local U = require("tests.drivers.util")

return function(game)
  U.wait(10)
  assert(game.data and game.data.maps and game.data.maps.FIX_TOWN,
    "fixture data did not load")
  assert(game.overworld and game.stack:top() == game.overworld,
    "fixture boot did not reach the overworld")
  assert(game.overworld.map and game.overworld.map.id == "FIX_TOWN",
    "fixture boot opened the wrong map")

  local out = assert(os.getenv("SHOT_DIR"), "SHOT_DIR is required")
  assert(U.shot(game, out .. "/fixture_overworld.png"),
    "fixture screenshot was not written")
  print("fixture LOVE boot: PASS")
end

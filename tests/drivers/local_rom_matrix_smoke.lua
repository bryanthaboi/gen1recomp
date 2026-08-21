-- Real-LÖVE boot/render half of scripts/test_local_rom_matrix.sh.

local U = require("tests.drivers.util")

return function(game)
  local expected = assert(os.getenv("POKEPORT_MATRIX_VERSION"),
    "POKEPORT_MATRIX_VERSION is required")
  local GameVersion = require("src.core.GameVersion")

  U.wait(45) -- cross several update/draw frames, not merely Game:load
  assert(GameVersion.get() == expected,
    ("booted %s cache, expected %s"):format(GameVersion.get(), expected))
  assert(game and game.data, "game has no loaded cartridge data")
  local world = game.world or game.overworld
  assert(world and world.map, "game did not reach an overworld map")
  assert(world.map.id ~= nil, "overworld map has no cartridge id")

  local audio = game.data.audio
  assert(type(audio) == "table" and type(audio.cries) == "table",
    "full importer cache has no cry table")
  local cries = 0
  for _ in pairs(audio.cries) do cries = cries + 1 end
  local wantCries = GameVersion.generation() == 2 and 250 or 154
  assert(cries == wantCries,
    ("loaded %d cries, expected %d"):format(cries, wantCries))

  -- The driver is resumed before Game:update. Waiting above proves the real
  -- renderer and update loop can consume the imported tables without error.
  print("[rom-matrix] PASS " .. expected)
end

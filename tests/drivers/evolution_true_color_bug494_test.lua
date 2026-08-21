-- Driver: inspect a full-color Pokémon while it evolves (#494).  The sprite
-- is normally protected from the ADVANCED palette pass by its trueColor flag.
-- EvolutionState used the image but dropped that flag, so the full-color pic
-- was recolored as if it were a four-shade SGB sprite.
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/evolution_true_color_bug494_test.lua \
--     POKEPORT_IDENTITY=bug494 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Evolution = require("src.pokemon.Evolution")
  local Pokemon = require("src.pokemon.Pokemon")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.options = game.save.options or {}
  game.save.options.colors = "redpp"
  PaletteFX.setMode("redpp")

  -- The stock artwork is a four-shade source image.  Set the same runtime
  -- contract a full-color sprite mod uses so this driver reaches the palette
  -- boundary that #494 exposed, without turning the visual result into a test.
  local pikachu = game.data.pokemon.PIKACHU
  local raichu = game.data.pokemon.RAICHU
  check("PIKACHU and RAICHU data are available", pikachu ~= nil and raichu ~= nil)
  if not (pikachu and raichu) then return end
  pikachu.trueColor = true
  raichu.trueColor = true
  check("ADVANCED color mode is active", PaletteFX.mode == "redpp")

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  check("the overworld fixture is ready", game.overworld ~= nil)

  local mon = Pokemon.new(game.data, "PIKACHU", 20)
  game.save.party = { mon }
  Evolution.evolve(game, mon, "RAICHU")
  -- the IsEvolvingText box now holds 50+ frames before the movie (#1596)
  local top
  for _ = 1, 300 do
    top = game.stack:top()
    if top and top.screenId == "EvolutionState" then break end
    U.wait(1)
  end
  check("the evolution screen opened", top and top.screenId == "EvolutionState")
  U.log("Issue #494: true-color sprites during evolutions and trades")
  U.log("Watch this PIKACHU evolve into RAICHU in ADVANCED colors.")
  U.log("Right: both sprites keep their source colors during the flash and")
  U.log("the congratulations screen. Wrong: either sprite is recolored by")
  U.log("the surrounding four-shade palette. Press B during the flash to")
  U.log("also inspect the cancelled PIKACHU screen.")

  while true do
    coroutine.yield()
  end
end

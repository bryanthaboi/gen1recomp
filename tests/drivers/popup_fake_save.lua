-- Driver: drops a fake 3-mon party into the overworld and then gets out
-- of the way -- yields forever without ever touching input itself, so
-- real keyboard/controller play works normally from here on. This is
-- just a quick way to pop up a playable window with Pokemon already in
-- the party, not a scripted playthrough.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 77),
  }
  game.save.player.name = "bryan"

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.log("popup_fake_save: party ready, handing off to real input")

  while true do
    coroutine.yield()
  end
end

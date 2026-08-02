-- Crash catcher: play normally, and if anything throws, the message and
-- traceback are appended to cbf-crash.txt beside main.lua.
--
--   POKEPORT_DRIVER=mods/celadon_battle_facility/tests/crashlog_driver.lua love .
--
-- Exists because the facility crash reproduces for a human walking the
-- building's perimeter but not for any scripted route tried so far, and
-- LOVE's blue error screen is easy to lose. This writes the traceback to a
-- file no matter how the game was launched.
--
-- Like the sandbox it never returns: it sets up, then parks in a yield loop
-- so the controls stay yours.
local LOG = "cbf-crash.txt"

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")

  -- ------- the catcher, installed before anything else can throw

  local previous = love.errorhandler or love.errhand
  love.errorhandler = function(msg)
    local ok = pcall(function()
      local f = io.open(LOG, "a")
      if not f then return end
      local ow = game and game.overworld
      f:write(("\n==== crash %s ====\n"):format(os.date("%Y-%m-%d %H:%M:%S")))
      if ow and ow.map then
        f:write(("map: %s at (%s,%s) facing %s\n"):format(
          tostring(ow.map.id), tostring(ow.player and ow.player.cellX),
          tostring(ow.player and ow.player.cellY),
          tostring(ow.player and ow.player.facing)))
      end
      local opts = game and game.save and game.save.options or {}
      f:write(("options: colors=%s tilt=%s zoom=%s gbcfx=%s\n"):format(
        tostring(opts.colors), tostring(opts.tilt), tostring(opts.zoom),
        tostring(opts.gbcFx)))
      f:write(tostring(msg), "\n")
      f:write(debug.traceback("", 2), "\n")
      f:close()
    end)
    if not ok then print("crash logger failed") end
    if previous then return previous(msg) end
  end

  if not game.data.maps.CELADON_BATTLE_FACILITY then
    U.log("the mod is not loaded")
    while true do coroutine.yield() end
  end

  -- ------- a ready save, parked at the building's front door

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  for i = #game.save.party, 1, -1 do table.remove(game.save.party, i) end
  for _, s in ipairs({ "CHARIZARD", "BLASTOISE", "VENUSAUR",
                       "ALAKAZAM", "SNORLAX", "LAPRAS" }) do
    table.insert(game.save.party, Pokemon.new(game.data, s, 40))
  end
  Bag.add(game.save, "CBF_TOKEN", 20, game.data)

  local bucket = game.mods.modSave.celadon_battle_facility or {}
  bucket.bests = { bronze = 1, silver = 1 }
  game.mods.modSave.celadon_battle_facility = bucket

  U.teleport(game, "CELADON_CITY", 8, 22, "down")

  U.log("crash catcher armed -> " .. LOG)
  U.log("walk the perimeter; if it crashes, send me that file.")

  while true do coroutine.yield() end
end

-- Screen-rect check for a touch skin, both generations.
--
--   POKEPORT_DRIVER=tests/drivers/skin_screen_shot.lua love .
--   POKEPORT_GAME=gold POKEPORT_SKIN=my_skin POKEPORT_DRIVER=... love .
--
-- Gold's cache lives under the DEFAULT save identity, so a POKEPORT_IDENTITY
-- sandbox has to be seeded with it first or the boot hangs in the importer:
--   cp -R ~/Library/Application\ Support/LOVE/pokemon-love2d/{gold,skins} \
--         ~/Library/Application\ Support/LOVE/<identity>/
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local function env(name, fallback)
  local v = os.getenv(name)
  if v == nil or v == "" then return fallback end
  return v
end

local function tap(game, button)
  game.input.pressQueue[#game.input.pressQueue + 1] = button
  game.input.state[button] = true
  U.wait(2)
  game.input.state[button] = false
end

return function(game)
  local TouchControls = require("src.core.TouchControls")
  local out = env("POKEPORT_SHOT_DIR", ".")
  local gen2 = GameVersion.generation() == 2

  love.window.setMode(tonumber(env("POKEPORT_SHOT_W", 460)),
                      tonumber(env("POKEPORT_SHOT_H", 950)))
  local skin = env("POKEPORT_SKIN", "gb_anim")
  local ok, err = TouchControls:selectSkin(skin)
  assert(ok, "skin " .. skin .. ": " .. tostring(err))

  U.wait(60)
  if gen2 then
    local A = require("tests.drivers.gold.adapter")
    assert(game.world and game.world.map, "gold world did not boot")
    A.teleport(game, env("POKEPORT_SHOT_MAP", "NEW_BARK_TOWN"), 6, 6)
    U.wait(120)
  else
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
    U.teleport(game, env("POKEPORT_SHOT_MAP", "PALLET_TOWN"), 10, 8, "down")
    U.wait(40)
  end
  U.shot(game, out .. "/skin_world.png")

  tap(game, "start")
  U.wait(60)
  U.shot(game, out .. "/skin_menu.png")

  love.event.quit()
  while true do coroutine.yield() end
end

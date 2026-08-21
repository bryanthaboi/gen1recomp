-- #1479: TILESET_KANTO roof probe (LoadMapGroupRoof, home/map.asm:1738-1749)
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_bug1479_probe.lua love .

local U = require("tests.drivers.util")

local SPOTS = {
  { "ROUTE_28", 6, 6 },
  { "SILVER_CAVE_OUTSIDE", 10, 20 },
  { "SILVER_CAVE_OUTSIDE", 10, 8 },
  { "ROUTE_22", 10, 8 },
  { "VIRIDIAN_CITY", 10, 10 },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-kanto"
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  local failed = false
  for i, spot in ipairs(SPOTS) do
    local def = world.maps[spot[1]]
    if not def then
      U.log("FAIL no map", spot[1])
      failed = true
    else
      world:setMap(spot[1], spot[2], spot[3], "down")
      U.wait(10)
      U.shot(game, ("%s/%02d-%s.png"):format(out, i, spot[1]:lower()))
      -- home/map.asm:1738-1749: a Kanto-tileset map takes no map-group roof,
      -- so its atlas is cached under the bare tileset name.
      if def.tileset == "TILESET_KANTO" then
        for key in pairs(world.atlasCache or {}) do
          if key:find("TILESET_KANTO|", 1, true) then
            U.log("FAIL Kanto atlas took a roof:", key)
            failed = true
          end
        end
      end
      U.log("shot", spot[1], def.tileset)
    end
  end

  U.log(failed and "RESULT FAIL" or "RESULT PASS", "shots in", out)
  love.event.quit(failed and 1 or 0)
end

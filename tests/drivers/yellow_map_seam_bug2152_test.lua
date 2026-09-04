-- (../pokeyellow/engine/gfx/palettes.asm:178)
--   POKEPORT_DRIVER=tests/drivers/yellow_map_seam_bug2152_test.lua \
--   POKEPORT_IDENTITY=bsa2180 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow \
--   SHOT_DIR=/tmp/shots2152 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Zoom = require("src.render.Zoom")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots2152"

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  U.newGame(game)
  local ow = game.overworld

  U.teleport(game, "PALLET_TOWN", 10, 1, "up")
  U.wait(20)
  check("standing on the Pallet Town / Route 1 boundary",
        ow.map.id == "PALLET_TOWN")
  check("a neighbour map is resident", #ow.neighbors > 0)

  local zones = ow:sgbWorldZones()
  U.log("world zones at FIT:", zones and #zones or "none")
  check("FIT publishes one whole-view zone (BlkPacket_WholeScreen)",
        zones == nil or #zones <= 1)
  check("the boundary frame captured",
        U.shot(game, DIR .. "/seam_1_fit.png"))

  Zoom.offset = -2
  U.wait(10)
  local surveyed = ow:sgbWorldZones()
  U.log("world zones at survey zoom:", surveyed and #surveyed or "none")
  check("survey zoom keeps a zone per resident neighbour",
        surveyed == nil or #surveyed > 1)
  U.shot(game, DIR .. "/seam_2_survey.png")
  Zoom.offset = 0
  U.wait(10)

  U.teleport(game, "ROUTE_1", 10, 1, "up")
  U.wait(20)
  local lane
  for x = 0, 19 do
    if ow.map:isWalkableCell(x, 0) and ow.map:isWalkableCell(x, 1) then
      lane = x
      break
    end
  end
  check("Route 1 has a walkable lane to Viridian", lane ~= nil)
  if lane then
    U.teleport(game, "ROUTE_1", lane, 1, "up")
    U.wait(20)
    U.hold(game, "up", 120)
    U.wait(20)
  end
  U.shot(game, DIR .. "/seam_3_crossed.png")
  U.log("map after walking north:", ow.map.id)
  check("walked onto VIRIDIAN_CITY", ow.map.id == "VIRIDIAN_CITY")
  local after = ow:sgbWorldZones()
  check("the new map is also a single whole-view zone at FIT",
        after == nil or #after <= 1)

  U.log(failures == 0 and "checks clean" or (failures .. " check(s) failed above"))
  U.log("seam_1_fit.png must show ONE palette across the whole screen, with no")
  U.log("horizontal colour break above the player and no split down his sprite.")
  U.log("seam_2_survey.png is the survey zoom and SHOULD still show each town")
  U.log("and route in its own colours.  seam_3_crossed.png is Viridian after")
  U.log("the crossing, entirely in the new map's palette.")

  while true do
    coroutine.yield()
  end
end

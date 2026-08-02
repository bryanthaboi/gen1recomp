-- Driver: the Phase 1 success criterion -- walk in and back out.
--
--   POKEPORT_DRIVER=mods/celadon_battle_facility/tests/door_roundtrip_driver.lua love .
--
-- The unit suite proves the warp topology closes on paper.  This proves the
-- player can actually walk it: collision on the stamped footprint, the door
-- trigger, and the return trip landing back on Celadon's door cell.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"

  local CITY, FACILITY = "CELADON_CITY", "CELADON_BATTLE_FACILITY"
  -- the left of the two doorway cells; the footprint spans cells x 4..11
  local DOOR_X, DOOR_Y = 6, 21

  local failures = 0
  local function check(cond, msg)
    U.log(cond and "ok  " or "FAIL", msg)
    if not cond then failures = failures + 1 end
  end

  check(game.data.maps[FACILITY] ~= nil,
    "the mod is loaded (" .. FACILITY .. " exists)")
  if not game.data.maps[FACILITY] then
    U.log("driver aborted: enable the mod first (F10 manager, or mods."
      .. "celadon_battle_facility = true in options.lua)")
    return
  end

  local function settle(want)
    local ow = game.overworld
    for _ = 1, 120 do
      U.wait(1)
      if ow.map.id == want and not ow.transitioning
         and #ow.scriptMoves == 0 and not ow.player.moving then
        return true
      end
    end
    return false
  end

  -- ------- stand on the approach cell, one south of the door

  U.teleport(game, CITY, DOOR_X, DOOR_Y + 1, "up")
  local ow = game.overworld
  U.shot(game, DIR .. "/cbf_0_outside.png")
  U.log("outside:", ow.map.id, ow.player.cellX, ow.player.cellY)
  check(ow.map.id == CITY, "standing in Celadon on the approach cell")

  -- ------- in

  U.hold(game, "up", 20)
  check(settle(FACILITY), "walking up through the door enters the facility")
  U.wait(8)
  U.shot(game, DIR .. "/cbf_1_inside.png")
  U.log("inside:", ow.map.id, ow.player.cellX, ow.player.cellY)

  -- ------- and back out

  U.hold(game, "down", 20)
  check(settle(CITY), "walking down out of the doorway returns to Celadon")
  U.wait(8)
  U.shot(game, DIR .. "/cbf_2_back_outside.png")
  U.log("back outside:", ow.map.id, ow.player.cellX, ow.player.cellY)
  check(ow.player.cellX == DOOR_X and ow.player.cellY == DOOR_Y + 1,
    ("the return lands on the approach cell (%d,%d), got (%d,%d)")
      :format(DOOR_X, DOOR_Y + 1, ow.player.cellX, ow.player.cellY))

  -- ------- the building is solid, not walk-through scenery

  U.teleport(game, CITY, DOOR_X - 2, DOOR_Y + 1, "up")
  U.hold(game, "up", 24)
  U.wait(6)
  check(ow.map.id == CITY and ow.player.cellY >= DOOR_Y,
    "the footprint blocks movement instead of letting the player walk through")
  U.shot(game, DIR .. "/cbf_3_wall.png")

  U.log(failures == 0 and "DRIVER PASS" or ("DRIVER FAIL (" .. failures .. ")"))
end

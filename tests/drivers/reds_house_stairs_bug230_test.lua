-- Driver: Red's-house corner staircase warp (issue #230).
--
-- REDS_HOUSE_1F/2F share an 8x8 layout with the stairs warp on the top-right
-- corner cell (7,1); the cell to its right is the map edge (widthCells-1==7),
-- so Warp.extraCheck's facingEdge branch answers "yes" to a right-bonk.  Two
-- Gen1 invariants this driver pins:
--
--   1. The warp cell you ARRIVE on is inert until you physically step off it
--      (CheckWarpsNoCollision / the arrival-disable in the completed-step
--      path).  Holding right into the east wall while standing on (7,1) must
--      NOT re-fire the collision warp -- pre-fix it ping-ponged 1F<->2F every
--      input frame forever.
--   2. A genuine wall bonk still animates the walk cycle in place (the
--      collision path runs UpdateSprites), so player:walkPhase() must reach 1
--      during the bonk while the cell stays put.
--
-- The stairs must still warp normally once the player steps off (7,1) and
-- back onto it, so the guard cannot break legitimate staircases.
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/reds_house_stairs_bug230_test.lua \
--   POKEPORT_IDENTITY=bug230 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local function shot(name) U.shot(game, shotDir .. "/" .. name) end

  local ow
  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end
  local function settle(mapId)
    for _ = 1, 300 do
      ow = game.overworld
      if ow and ow.map.id == mapId and not ow.transitioning
         and #ow.scriptMoves == 0 and not ow.player.moving then
        break
      end
      U.wait(1)
    end
    U.wait(4)
    ow = game.overworld
  end

  -- 1) Arrive on the 2F stairs via a REAL warp so the arrival state is real
  --    (warpEntryCell set, BIT_STANDING_ON_WARP cleared by the stair tile).
  --    Teleporting straight onto (7,1) bypasses takeWarp and would
  --    never set the arrival-inert state, so the bug could not reproduce --
  --    we must walk up onto the 1F stairs and let the warp carry us.
  U.teleport(game, "REDS_HOUSE_1F", 7, 3, "up")
  settle("REDS_HOUSE_1F")
  U.hold(game, "up", 40)
  settle("REDS_HOUSE_2F")
  expect(ow.map.id == "REDS_HOUSE_2F", "arrived upstairs, map:", ow.map.id)
  expect(ow.player.cellX == 7 and ow.player.cellY == 1,
         "standing on the stairs cell (7,1), got:",
         ow.player.cellX, ow.player.cellY)
  shot("reds230_arrive.png")

  -- 2) Ping-pong guard (Fix 1) AND walk-in-place (Fix 2): hold right into the
  --    east wall for 150 frames.  Record every distinct floor id visited and
  --    whether the sprite ever animates a walk frame.
  local floors, order, seenPhase1 = {}, {}, false
  do
    local last
    for _ = 1, 150 do
      table.insert(game.input.pressQueue, "right")
      game.input.state["right"] = true
      coroutine.yield() -- Game:update runs here, processing this frame's input
      local o = game.overworld
      if o then
        if o.map.id ~= last then table.insert(order, o.map.id); last = o.map.id end
        floors[o.map.id] = true
        if o.player:walkPhase() == 1 then seenPhase1 = true end
      end
    end
    game.input.state["right"] = false
  end
  settle("REDS_HOUSE_2F")
  shot("reds230_after_hold.png")

  local distinct = 0
  for _ in pairs(floors) do distinct = distinct + 1 end
  expect(distinct == 1 and floors["REDS_HOUSE_2F"] == true,
         "no floor ping-pong during the hold; distinct floors:", distinct,
         "sequence:", table.concat(order, ">"))
  expect(ow.map.id == "REDS_HOUSE_2F", "still upstairs after the hold, map:",
         ow.map.id)
  expect(ow.player.cellX == 7 and ow.player.cellY == 1,
         "bonked in place, still at (7,1), got:",
         ow.player.cellX, ow.player.cellY)
  expect(not ow.player.moving and not ow.transitioning,
         "settled after the hold, not mid-move/transition")
  expect(seenPhase1,
         "walk-in-place: player:walkPhase() reached 1 during the bonk")

  -- 3) Anti-over-fix: the guard clears the instant the player steps off the
  --    warp cell, so stepping south (off (7,1)) then back north still takes
  --    the stairs.  The exact southern cell does not matter -- only that we
  --    leave (7,1) and that re-entering it still fires the warp.
  U.hold(game, "down", 20)
  settle("REDS_HOUSE_2F")
  expect(ow.player.cellX == 7 and ow.player.cellY >= 2,
         "stepped south off the stairs cell, got:",
         ow.player.cellX, ow.player.cellY)
  U.hold(game, "up", 40)
  settle("REDS_HOUSE_1F")
  expect(ow.map.id == "REDS_HOUSE_1F",
         "stairs still warp after stepping off and back on, map:", ow.map.id)

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed")
end

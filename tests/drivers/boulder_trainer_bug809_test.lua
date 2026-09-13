-- A trainer's walk-up must stop short of a Strength boulder, and the boulder
-- must still be pushable afterwards (#809).  TrainerWalkUpToPlayer (pokered
-- engine/overworld/trainer_sight.asm) writes dist-1 movement bytes that skip
-- collision, so the trainer used to park ON the boulder, and after that
-- IsSpriteInFrontOfPlayer (home/overworld.asm) handed TryPushingBoulder the
-- trainer instead of the rock.  POKEPORT_DRIVER=tests/drivers/boulder_trainer_bug809_test.lua POKEPORT_IDENTITY=bug809 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

-- No POKEPORT_SPEED: the sighting, the "!" bubble and the walk-up all run at
-- the normal 60 Hz logic clock so the stop-short frame is the one a player
-- would see.  The setup pushes are slow for the same reason; the run takes
-- about half a minute of real time before it hands the pad over.
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- pokered data/maps/objects/VictoryRoad3F.asm:
  --   object_event 13, 3, SPRITE_COOLTRAINER_F, STAY, RIGHT, ..., OPP_COOLTRAINER_F, 3
  --   object_event 22, 3, SPRITE_BOULDER, STAY, BOULDER_MOVEMENT_BYTE_2, ...
  -- Her header range is 4 (data/generated/trainer_headers.lua VictoryRoad3F[4]),
  -- so she spots the player anywhere on row 3 within four cells to her east and
  -- then walks dist-1 cells toward him.  Row 3 is walled at x=19, so BOULDER1
  -- cannot simply be shoved west into her sight line: it has to go down column
  -- 22 to row 6, west along row 6, and back up column 17 onto row 3.
  local MAP = "VICTORY_ROAD_3F"
  local MAP_LABEL = "VictoryRoad3F"
  local BOULDER = "VICTORYROAD3F_BOULDER1"
  local TRAINER = "VICTORYROAD3F_COOLTRAINER_F2"
  local START = { x = 22, y = 2, facing = "down" }
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local pass = true
  local function check(label, ok)
    if not ok then pass = false end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function findNpc(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- Hold `btn` until `cond` goes true or the budget runs out, then release and
  -- let any half-finished step land.  Boulder pushes need a held direction:
  -- handleInput only reaches checkBoulderPush while the player already faces
  -- that way, and TryPushingBoulder arms on one poll and moves on the next
  -- (BIT_TRIED_PUSH_BOULDER), so a single tap can never shift a rock.
  local function holdUntil(btn, cond, budget)
    local first = true
    for _ = 1, budget or 600 do
      if cond() then break end
      if first then table.insert(game.input.pressQueue, btn); first = false end
      game.input.state[btn] = true
      coroutine.yield()
    end
    game.input.state[btn] = false
    for _ = 1, 40 do
      if not game.overworld.player.moving and #game.overworld.scriptMoves == 0 then
        break
      end
      coroutine.yield()
    end
    U.wait(4) -- an input-free poll re-arms turning in place (wCheckFor180DegreeTurn)
    return cond()
  end

  U.teleport(game, MAP, START.x, START.y, START.facing)
  U.wait(10)
  local ow = game.overworld
  local rock = findNpc(ow, BOULDER)
  local trainer = findNpc(ow, TRAINER)

  check("BOULDER1 loaded on " .. MAP, rock ~= nil)
  check("COOLTRAINER_F2 loaded on " .. MAP, trainer ~= nil)
  if not (rock and trainer) then
    U.log("map objects missing; nothing to drive")
    while true do coroutine.yield() end
  end
  check("BOULDER1 starts at the asm cell (22,3)",
        rock.cellX == 22 and rock.cellY == 3)
  check("COOLTRAINER_F2 starts at the asm cell (13,3) facing right",
        trainer.cellX == 13 and trainer.cellY == 3 and trainer.facing == "right")
  check("checkBoulderPush resolves through pushableAtCell",
        type(ow.pushableAtCell) == "function")

  local header = game.data:trainerHeader(MAP_LABEL, trainer.def.index)
  local range = header and header.range or 0
  check("her sight range is 4 cells", range == 4)

  -- The whole route, so a map or tileset edit shows up here instead of as a
  -- driver that quietly wanders off.  If a cell is not walkable the boulder
  -- cannot be pushed onto it (CheckForCollisionWhenPushingBoulder reuses the
  -- player's passability check) and the run is not worth continuing.
  local ROUTE = {
    { 22, 4 }, { 22, 5 }, { 22, 6 }, { 23, 5 }, { 23, 6 },
    { 21, 6 }, { 20, 6 }, { 19, 6 }, { 18, 6 }, { 17, 6 },
    { 18, 7 }, { 17, 7 }, { 17, 5 }, { 17, 4 }, { 17, 3 },
    { 18, 4 }, { 18, 3 }, { 16, 3 }, { 16, 4 }, { 16, 2 },
  }
  local routeOk = true
  for _, c in ipairs(ROUTE) do
    if not ow.map:isWalkableCell(c[1], c[2]) then
      routeOk = false
      U.log("route cell not walkable:", c[1], c[2])
    end
  end
  check("the push route is walkable end to end", routeOk)

  -- STRENGTH is live for the map visit.  BIT_STRENGTH_ACTIVE is what
  -- TryPushingBoulder gates on -- it never re-reads badges or party moves --
  -- so setting the field-move state is the whole grant (see the comment in
  -- OverworldState:checkBoulderPush).
  ow.strengthActive = true

  -- Victory Road rolls a wild encounter on every completed step, not just in
  -- grass (wild_encounters.asm counts caves as indoor), and this run walks
  -- twenty-odd cells with an empty party.  Drop the map's table: a wild
  -- battle mid-route interrupts the push with a screen transition and has
  -- nothing to do with what is being checked.
  game.data.encounters[MAP] = nil

  if not pass then
    U.log("setup checks already failed; not driving the push")
    while true do coroutine.yield() end
  end

  local function boulderAt(x, y)
    return function() return rock.cellX == x and rock.cellY == y end
  end
  local function playerAt(x, y)
    local p = ow.player
    return function() return p.cellX == x and p.cellY == y end
  end

  -- down column 22 to row 6
  holdUntil("down", boulderAt(22, 6), 400)
  check("boulder pushed down column 22 to (22,6)", rock.cellX == 22 and rock.cellY == 6)
  -- around to its east side
  holdUntil("right", playerAt(23, 5), 120)
  holdUntil("down", playerAt(23, 6), 120)
  -- west along row 6 to the column that reaches row 3
  holdUntil("left", boulderAt(17, 6), 700)
  check("boulder pushed west along row 6 to (17,6)", rock.cellX == 17 and rock.cellY == 6)
  -- around to its south side
  holdUntil("down", playerAt(18, 7), 120)
  holdUntil("left", playerAt(17, 7), 120)
  -- up column 17 onto her row -- engine/overworld/push_boulder.asm:66
  holdUntil("up", playerAt(17, 4), 400)
  check("boulder pushed up column 17 onto row 3 at (17,3)",
        rock.cellX == 17 and rock.cellY == 3)
  if not pass then
    U.log("the boulder never reached her row; the race below cannot happen")
    while true do coroutine.yield() end
  end

  -- Step onto row 3 one cell out of range (18 - 13 = 5 > 4) so the sighting
  -- happens on the push itself and not a moment earlier.
  holdUntil("right", playerAt(18, 4), 120)
  holdUntil("up", playerAt(18, 3), 120)
  check("player waiting at (18,3), one cell outside her range",
        ow.player.cellX == 18 and ow.player.cellY == 3 and not ow.engaging)

  -- The engage lands on a battle we are not going to fight: stand in for it,
  -- record where the walk-up stopped, and mark her beaten the way winning
  -- would.  Everything the walk-up does has already happened by this point.
  local stopped
  local realEngage = ow.engageTrainer
  ow.engageTrainer = function(self, npc, onDone)
    stopped = { npc = npc, x = npc.cellX, y = npc.cellY }
    game.save.defeatedTrainers[npc.id] = true
    if onDone then onDone() end
  end

  -- One push west: the boulder lands on (16,3) and the player follows onto
  -- (17,3), four cells from her, which is the frame she spots him on.
  holdUntil("left", function() return stopped ~= nil end, 400)

  check("she spotted the player and finished her walk-up", stopped ~= nil)
  check("the boulder moved one cell west to (16,3)",
        rock.cellX == 16 and rock.cellY == 3)
  if stopped then
    U.log("she stopped at", stopped.x, stopped.y, "boulder at", rock.cellX, rock.cellY)
    check("she is not standing on the boulder cell",
          not (stopped.x == rock.cellX and stopped.y == rock.cellY))
    check("she stopped one cell short of it, at (15,3)",
          stopped.x == 15 and stopped.y == 3)
    check("the push path still finds the boulder under that cell",
          ow:pushableAtCell(rock.cellX, rock.cellY) == rock)
    check("nothing else shares the boulder's cell",
          ow:npcAtCell(rock.cellX, rock.cellY) == rock)
  end
  U.shot(game, SHOT_DIR .. "/bug809_walkup_stop.png")

  -- ...and the rock still moves.  Push it north, the one free direction left:
  -- west is her, east is the player, south is where he came from.
  holdUntil("down", playerAt(17, 4), 120)
  holdUntil("left", playerAt(16, 4), 120)
  holdUntil("up", boulderAt(16, 2), 400)
  if not check("the boulder is still pushable after the engage",
               rock.cellX == 16 and rock.cellY == 2) then
    U.log("boulder ended at", rock.cellX, rock.cellY, "player at",
          ow.player.cellX, ow.player.cellY)
  end
  holdUntil("down", playerAt(16, 4), 120)
  U.shot(game, SHOT_DIR .. "/bug809_still_pushable.png")

  ow.engageTrainer = realEngage
  U.log(pass and "ALL CHECKS PASSED" or "SOME CHECKS FAILED")

  U.log("On screen: the COOLTRAINER stands at (15,3) with a one-cell gap")
  U.log("between her and the rock, which now sits at (16,2), one row up from")
  U.log("where she stopped.  The near miss to watch for is her sprite ending")
  U.log("the walk-up on top of the rock, or standing clear of it but leaving")
  U.log("it inert: walk into the rock from any side and it should still shift")
  U.log("a cell.  Her battle was stubbed out and she is flagged as beaten;")
  U.log("re-run the driver to watch the race again from the start.")

  while true do
    coroutine.yield()
  end
end

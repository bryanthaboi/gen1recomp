-- engine/overworld/movement.asm:49
-- home/overworld.asm:108
-- scripts/OaksLab.asm:1011
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Bag = require("src.inventory.Bag")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR")
              or "/tmp/2839"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[2839] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local function finish()
    print("[2839] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILURES")))
    love.event.quit(fails == 0 and 0 or 1)
  end

  local flags = game.save.flags or {}
  game.save.flags = flags
  flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  flags.EVENT_GOT_STARTER = true
  flags.EVENT_CHOSE_SQUIRTLE = true
  flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  Bag.add(game.save, "OAKS_PARCEL", 1)
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles.OAKS_LAB = game.save.objectToggles.OAKS_LAB or {}
  game.save.objectToggles.OAKS_LAB.OAKSLAB_OAK1 = true
  game.save.objectToggles.OAKS_LAB.OAKSLAB_RIVAL = false

  U.teleport(game, "OAKS_LAB", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  local oak = ow and ow:npcByIndex(5)
  if not oak then
    ok(false, "Oak is in the lab")
    return finish()
  end
  local ox, oy = oak.cellX, oak.cellY
  U.teleport(game, "OAKS_LAB", ox - 1, oy, "right")
  U.wait(10)
  ow = game.overworld
  local p = ow.player
  ok(p.cellX == ox - 1 and p.cellY == oy, "player stands left of Oak at "
     .. (ox - 1) .. "," .. oy)

  local sawWalk = false
  for _ = 1, 22 do
    table.insert(game.input.pressQueue, "right")
    game.input.state.right = true
    coroutine.yield()
    if p:walkPhase() == 1 then sawWalk = true end
  end
  ok(not p.moving, "Oak blocks the step")
  ok(sawWalk, "the walk-in-place cycle runs while pushing into Oak")
  local clock = p.animClock or 0
  print(string.format("[2839] bump state at talk: bumpFrames=%s animClock=%d",
    tostring(p.bumpFrames), clock))

  U.tap(game, "a")
  game.input.state.right = false
  U.wait(4)
  ok(game.stack:top() ~= ow, "the A press opened Oak's parcel text")
  U.still(game, DIR .. "/2839_01_parcel_text.png")

  local badFrames, worldFrames, shotWalk, shotStand = 0, 0, false, false
  for _ = 1, 3000 do
    if not ow.runner:isRunning() and game.stack:top() == ow then break end
    if game.stack:top() == ow then
      worldFrames = worldFrames + 1
      if not p.moving and p:walkPhase() ~= 0 then
        badFrames = badFrames + 1
        if not shotWalk then
          U.still(game, DIR .. "/2839_02_walk_pose_between_boxes.png")
          shotWalk = true
        end
      elseif not shotStand and worldFrames >= 3 then
        U.still(game, DIR .. "/2839_03_standing_between_boxes.png")
        shotStand = true
      end
      coroutine.yield()
    else
      U.tap(game, "a")
      U.wait(2)
    end
  end
  print(string.format("[2839] overworld frames inside the cutscene: %d, walk-pose frames: %d",
    worldFrames, badFrames))
  ok(worldFrames > 0, "the cutscene ran overworld frames between its text boxes")
  ok(badFrames == 0, "the player holds the standing frame through the parcel cutscene")
  ok(flags.EVENT_GOT_POKEDEX == true, "the cutscene ran to the Pokedex hand-off")
  finish()
end

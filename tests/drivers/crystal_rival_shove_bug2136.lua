local U = require("tests.drivers.util")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

local EVENT_RIVAL_NEW_BARK_TOWN = 1725

return function(game)
  local fails = 0
  local function say(line) print("[2136] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map and world.vm and game.save) then
    say("FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  world.events:set(EVENT_RIVAL_NEW_BARK_TOWN, false)
  world:warpToMapId("NEW_BARK_TOWN", 3, 3, "up")
  for _ = 1, 120 do if not world:busy() then break end U.wait(1) end
  U.wait(10)
  ok(world.map and world.map.id == "NEW_BARK_TOWN", "standing under the rival")
  local rival
  for _, npc in ipairs(world.npcs or {}) do
    if npc.cellX == 3 and npc.cellY == 2 then rival = npc end
  end
  ok(rival ~= nil, "the rival is at (3,2)")
  U.shot(game, SHOT_DIR .. "/crystal_bug2136_00_before.png")

  U.tap(game, "a")
  for _ = 1, 60 do
    if world.vm:running() then break end
    U.wait(1)
  end
  ok(world.vm:running(), "talking to the rival started NewBarkTownRivalScript")

  local p = world.player
  local lowest, jumpFrames, shot, pushedTo = 0, 0, false, nil
  local facingDuringJump
  for _ = 1, 1800 do
    if not world.vm:running() then break end
    if p.jumping then
      jumpFrames = jumpFrames + 1
      lowest = math.min(lowest, p.spriteYOffset or 0)
      facingDuringJump = facingDuringJump or p.facing
      if not shot and (p.spriteYOffset or 0) <= -11 then
        shot = true
        U.shot(game, SHOT_DIR .. "/crystal_bug2136_01_airborne.png")
        say("the shot must show the player lifted off the ground with a shadow under them")
      end
    elseif p.moving and not pushedTo then
      pushedTo = p.targetY
    end
    local top = game.stack:top()
    if (world.textbox or (top and top.text)) and jumpFrames == 0 then
      U.tap(game, "a")
      U.wait(3)
    else
      U.wait(1)
    end
  end
  ok(not world.vm:running(), "the rival script ran to completion")
  ok(pushedTo == 4, "the push walks the player one cell down (target="
    .. tostring(pushedTo) .. ")")
  ok(jumpFrames > 0, "jump_step DOWN set the player jumping")
  ok(jumpFrames >= 28 and jumpFrames <= 34,
    "for one doubled step (" .. jumpFrames .. " frames)")
  ok(lowest == -12, "the arc peaks twelve pixels up (lowest=" .. lowest .. ")")
  ok(facingDuringJump == "up", "under fix_facing the player keeps facing up (facing="
    .. tostring(facingDuringJump) .. ")")
  ok(p.cellX == 3 and p.cellY == 6, "and lands at (3,6) (at "
    .. p.cellX .. "," .. p.cellY .. ")")
  ok(p.spriteYOffset == 0 and not p.jumping, "on the ground again")
  U.shot(game, SHOT_DIR .. "/crystal_bug2136_02_landed.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end

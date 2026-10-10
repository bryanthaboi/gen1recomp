-- pokeyellow scripts/OaksLab.asm:211-259
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Commands = require("src.script.Commands")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local LAB = "OAKS_LAB"
  local RIVAL = 1
  local failed = false

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function finish()
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  if not check("running the Yellow cache", GameVersion.isYellow()) then finish() end

  local flags = game.save.flags or {}
  game.save.flags = flags
  flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  flags.EVENT_GOT_STARTER = nil
  flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true

  U.teleport(game, LAB, 7, 4, "up")
  U.wait(10)
  local ow = game.overworld
  local ctx = { game = game, save = game.save, overworld = ow }
  Commands.show_object(ctx, LAB, "OAKSLAB_RIVAL")
  Commands.show_object(ctx, LAB, "OAKSLAB_OAK1")
  Commands.show_object(ctx, LAB, "OAKSLAB_EEVEE_POKE_BALL")
  U.wait(2)
  Commands.place_npc(ctx, RIVAL, 4, 3, "down")
  U.wait(2)
  local rival = ow:npcByIndex(RIVAL)
  local p = ow.player
  if not check("rival at (4,3), player at (7,4) facing up",
      rival and rival.cellX == 4 and rival.cellY == 3
      and p.cellX == 7 and p.cellY == 4 and p.facing == "up") then
    finish()
  end

  U.tap(game, "a")

  local steps, dirs, peak = {}, {}, 0
  local lx, ly = rival.cellX, rival.cellY
  local shoveTarget, shoveProgress, shoveCell
  local shot = false
  for _ = 1, 1200 do
    if rival.cellX ~= lx or rival.cellY ~= ly then
      steps[#steps + 1] = peak + 1
      dirs[#dirs + 1] = rival.cellX > lx and "right" or rival.cellX < lx and "left"
        or rival.cellY > ly and "down" or "up"
      peak = 0
      lx, ly = rival.cellX, rival.cellY
    end
    if rival.moving and not rival.marching then peak = math.max(peak, rival.progress) end
    if rival.moving and rival.targetX == 7 and rival.progress >= 6 and not shot then
      U.still(game, SHOT_DIR .. "/2821_01_rival_fast_last_step.png")
      shot = true
    end
    if p.moving and not shoveTarget then
      shoveTarget = rival.targetX and (rival.targetX .. "," .. rival.targetY) or "none"
      shoveProgress = rival.progress
      shoveCell = rival.cellX .. "," .. rival.cellY
    end
    if p.cellX == 9 and not p.moving and rival.cellX == 7 and not rival.moving then
      break
    end
    U.wait(1)
  end

  U.log("rival push step frames:", table.concat(steps, " "))
  U.log("rival push step dirs:", table.concat(dirs, " "))
  U.log("shove began with rival at", tostring(shoveCell), "heading to",
        tostring(shoveTarget), "progress", tostring(shoveProgress))
  check("rival took four steps: down, right, right, right",
        #steps == 4 and dirs[1] == "down" and dirs[2] == "right"
        and dirs[3] == "right" and dirs[4] == "right")
  check("the $00 down step is normal speed (32 frames)", steps[1] == 32)
  check("the three $07 right steps are double speed (16 frames)",
        steps[2] == 16 and steps[3] == 16 and steps[4] == 16)
  check("the PAD_RIGHT x2 shove starts as the rival begins the last byte",
        shoveCell == "6,4" and shoveTarget == "7,4" and (shoveProgress or 99) <= 2)
  check("player was shoved to (9,4)", p.cellX == 9 and p.cellY == 4)
  check("rival landed on (7,4)", rival.cellX == 7 and rival.cellY == 4)
  U.wait(10)
  U.still(game, SHOT_DIR .. "/2821_02_rival_on_ball_player_shoved.png")
  finish()
end

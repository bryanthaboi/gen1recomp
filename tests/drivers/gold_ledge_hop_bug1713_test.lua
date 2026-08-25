-- #1713: a ledge hop advanced only every other logic frame, so the whole map
-- scrolled at 30Hz in 2px lurches and the sprite bobbed against its own arc.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_ledge_hop_bug1713_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-ledge \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- jump_step is STEP_WALK (pokegold/engine/overworld/movement.asm:595-597), so
-- StepFunction_PlayerJump runs the `db 0, 2, 8, 2` StepVectors row as two
-- 8-frame beats (engine/overworld/map_objects.asm:365-381, :1163-1200) and
-- UpdateJumpPosition walks its 16-entry arc one entry a frame (:1796-1817).
-- We render at twice that resolution, so the hop owes 1px and half an arc
-- entry on every one of its 32 frames.
--
-- No POKEPORT_SPEED here on purpose: the whole subject is per-frame motion,
-- and fast-forward scales only the logic clock.
local U = require("tests.drivers.util")

local Player = require("src.world.gen2.Player")
local Permissions = require("src.world.gen2.Permissions")

-- ROUTE_30's ledge run at y=10 (data/generated/maps.lua, TILESET_JOHTO
-- collision $a3 COLL_HOP_DOWN): open ground two cells above it, a wall in
-- between, floor on the landing.  Re-derived by scanning if a re-import moves.
local MAP = "ROUTE_30"
local LEDGE = { x = 4, y = 10 }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-ledge"
  local fails, lines = 0, {}

  local function claim(ok, text)
    if not ok then fails = fails + 1 end
    lines[#lines + 1] = (ok and "PASS " or "FAIL ") .. text
    return ok
  end

  local function stop()
    for _, line in ipairs(lines) do U.log(line) end
    while true do coroutine.yield() end
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL the gold world never booted, nothing to look at")
    while true do coroutine.yield() end
  end

  claim(Player.STEP_FRAMES == 16, "a walk is 16 logic frames per cell")
  claim(type(world.tryLedgeJump) == "function",
    "World:tryLedgeJump is wired for the refused step to fall into")

  -- ---- find a ledge with room to run up to it ------------------------------
  world:setMap(MAP, LEDGE.x, LEDGE.y - 2, "down")
  U.wait(10)
  world.noWildEncounters = true
  local map = world.map

  local function hopsDown(x, y)
    if not map:inBounds(x, y) then return false end
    local facings = Permissions.ledgeFacings(map:cellCollision(x, y))
    return facings ~= nil and facings.down == true
  end
  local function walkable(x, y)
    return map:inBounds(x, y) and map:isWalkable(x, y)
  end
  -- A usable ledge: two free cells to walk down through, a refused cell in the
  -- middle (that refusal is what becomes the jump) and a free landing.
  local function usable(x, y)
    return hopsDown(x, y) and not walkable(x, y + 1) and walkable(x, y + 2)
      and walkable(x, y - 1) and walkable(x, y - 2)
  end

  local target
  if usable(LEDGE.x, LEDGE.y) then target = { x = LEDGE.x, y = LEDGE.y } end
  if not target then
    local def = world.maps[MAP]
    for y = 0, (def.height or 0) * 2 - 1 do
      for x = 0, (def.width or 0) * 2 - 1 do
        if not target and usable(x, y) then target = { x = x, y = y } end
      end
    end
  end
  claim(target ~= nil,
    ("%s still has a hop-down ledge with a run-up to it"):format(MAP))
  if not target then
    U.log("nothing to hop off; stopping rather than parking you at a wall")
    stop()
  end
  if target.x ~= LEDGE.x or target.y ~= LEDGE.y then
    U.log(("note: using the ledge at (%d,%d), not the (%d,%d) in the header")
      :format(target.x, target.y, LEDGE.x, LEDGE.y))
  end
  local START = { x = target.x, y = target.y - 2 }

  local function press(dir)
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    coroutine.yield()
  end

  -- Back to the top of the run-up.  The settle first is load bearing: a
  -- setMap on top of a hop that is still in the air carries the leftover jump
  -- into the new position and the next run measures nonsense.
  local function reset()
    game.input.state.down = false
    for _ = 1, 120 do
      if not (world.player and world.player.moving) then break end
      coroutine.yield()
    end
    world:setMap(MAP, START.x, START.y, "down")
    world.noWildEncounters = true
    U.wait(8)
  end

  -- ---- the run-up and the hop, measured ------------------------------------
  --
  -- Nobody can count pixels per frame by eye, and this is the whole bug: the
  -- per-frame travel of the camera-following position, plus the arc riding on
  -- top of it.  Every sample is "pixels travelled == frames elapsed", never a
  -- difference between two driver frames -- the fixed-step loop can run two
  -- logic steps for one yield, and a delta would read that as a lurch.
  reset()
  local p = world.player
  local hopRows, takeoff = {}, 0
  local walkSeen, walkWrong = 0, 0
  for _ = 1, 240 do
    press("down")
    if p.jumping then
      if #hopRows == 0 then takeoff = p.cellY * 16 end
      hopRows[#hopRows + 1] = { n = p.progress, py = p.py,
                                off = p.spriteYOffset or 0 }
    elseif #hopRows > 0 then
      break
    elseif p.moving and (p.progress or 0) > 0 then
      walkSeen = walkSeen + 1
      if p.py - p.cellY * 16 ~= p.progress then walkWrong = walkWrong + 1 end
    end
  end
  game.input.state.down = false

  local wrong, lurch, last = 0, 0, 0
  for _, r in ipairs(hopRows) do
    if r.py - takeoff ~= r.n then wrong = wrong + 1 end
    if r.n > last then last = r.n end
  end
  -- The old quantum, named directly: an even number of pixels on an odd frame.
  for _, r in ipairs(hopRows) do
    if (r.py - takeoff) % 2 == 0 and r.n % 2 == 1 then lurch = lurch + 1 end
  end

  claim(#hopRows > 0, "walking down into the ledge started a hop")
  claim(last >= 30,
    ("the hop ran its full 32 frames (the last one sampled was %d)")
      :format(last))
  claim(p.cellY == target.y + 2,
    ("it landed two cells down at y=%d (the player is at y=%d)")
      :format(target.y + 2, p.cellY))
  claim(p.py - takeoff == 32,
    ("and 32 pixels down, which is two cells (it moved %d)")
      :format(p.py - takeoff))
  claim(wrong == 0,
    ("on every one of the %d frames sampled the player had moved a pixel per"
     .. " frame elapsed (%d had not)"):format(#hopRows, wrong))
  claim(lurch == 0,
    ("so no frame of it stood still waiting to lurch two (%d did)")
      :format(lurch))
  claim(walkSeen > 0 and walkWrong == 0,
    ("the two ordinary steps before it move a pixel a frame too, on all %d"
     .. " frames sampled (%d wrong)"):format(walkSeen, walkWrong))

  -- The composed screen position: the camera-following py plus the sprite
  -- offset.  The armed frame is skipped because the first frame after it is
  -- the take-off, and rising there is the jump starting.
  local air, back = {}, 0
  for _, r in ipairs(hopRows) do
    if r.n >= 1 then air[#air + 1] = r.py + r.off end
  end
  for i = 2, #air do
    if air[i] < air[i - 1] then back = back + 1 end
  end
  claim(back == 0,
    ("after the take-off the sprite never reversed against its own arc"
     .. " (%d frames did)"):format(back))

  -- ---- one frame per run, so the strip really is consecutive ---------------
  --
  -- A capture costs the driver an unknown number of frames, so shooting four
  -- frames in one hop would skip some.  Four identical run-ups, each shot on a
  -- different frame, gives a strip that can be flipped through.
  -- One run-up, ending either on the frame asked for or on the landing.  The
  -- fixed-step loop can occasionally run two logic steps for one driver yield,
  -- so the shot is taken at the first frame AT OR PAST the one asked for, and
  -- the frame it actually landed on is reported rather than assumed.
  local function hopRun(frame, path)
    reset()
    local airborne = false
    for _ = 1, 240 do
      press("down")
      local pl = world.player
      if pl.jumping then
        airborne = true
        if frame and pl.progress >= frame then
          local at, py = pl.progress, pl.py
          game.input.state.down = false
          U.shot(game, path)
          return at, py
        end
      elseif airborne then
        break
      end
    end
    game.input.state.down = false
  end

  reset()
  U.shot(game, out .. "/01-standing.png")
  local strip = {}
  for i, frame in ipairs({ 12, 13, 14, 15 }) do
    local at, py = hopRun(frame, ("%s/02-strip-%d.png"):format(out, i))
    strip[#strip + 1] = { at = at or -1, py = py or -1 }
  end
  hopRun(4, out .. "/03-rising.png")
  hopRun(16, out .. "/04-peak.png")
  hopRun(28, out .. "/05-falling.png")
  hopRun()
  U.wait(20)
  U.shot(game, out .. "/06-landed.png")

  local consecutive = true
  local shown = {}
  for i, s in ipairs(strip) do
    shown[i] = ("%d"):format(s.at)
    if i > 1 and (s.at - strip[i - 1].at ~= 1
                  or s.py - strip[i - 1].py ~= 1) then
      consecutive = false
    end
  end
  claim(consecutive,
    ("the strip really is four consecutive frames, %s -- if this is FAIL the"
     .. " images are not comparable"):format(table.concat(shown, ", ")))

  for _, line in ipairs(lines) do U.log(line) end
  U.log(("%d checks, %d failed"):format(#lines, fails))
  if fails > 0 then
    U.log("something above is FAIL, so do not spend time watching the replay")
  end

  -- ---- the replay, live ----------------------------------------------------
  U.log("shots are in " .. out .. "; 02-strip-* are consecutive frames of the")
  U.log("same hop, so the ground should shift one pixel between each, and")
  U.log("03 / 04 / 05 are the rise, the top of the arc and the drop.")
  U.log("the replay walks down into the ledge three times, then hands over.")
  U.wait(120)
  for _ = 1, 3 do
    hopRun()
    U.wait(60)
  end

  U.log("two ordinary steps down, then the hop: the map should scroll at the")
  U.log("same speed through all three, and the sprite should rise, hang and")
  U.log("fall once. a stutter, a 2px lurch, or the sprite bobbing back up")
  U.log("during the rise is the old behaviour.")
  U.log("the near miss to watch for: a smooth hop that clears only one cell,")
  U.log("or one that takes twice as long as it should -- that is the two-cell")
  U.log("span applied without the doubled duration.")
  U.log("gen 1 is the reference; a Red ledge hop already looked like this.")
  while true do coroutine.yield() end
end

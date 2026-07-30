-- A connection crossing has to carry Yellow's follower, not respawn it (#427).
-- pokeyellow home/overworld.asm:648-655 sets bit 4 of
-- wPikachuOverworldStateFlags before LoadMapHeader, so pikachu_follow.asm's
-- SchedulePikachuSpawnForAfterText takes .normal_spawn_state: coords rebased,
-- sprite data left alone.  Never POKEPORT_SPEED here, the offsets are pixels.
--   POKEPORT_DRIVER=tests/drivers/pikachu_seam_bug427_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PikachuFollower = require("src.world.PikachuFollower")
  local GameVersion = require("src.core.GameVersion")
  local Map = require("src.world.Map")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  if not GameVersion.isYellow() then
    check("only Yellow has a follower; re-run with POKEPORT_VERSION=yellow", false)
    while true do coroutine.yield() end
  end

  -- pokeyellow data/maps/objects/PalletTown.asm puts no object on the town's
  -- north exit and PALLET_TOWN's north connection to ROUTE_1 carries offset 0,
  -- so the landing column is the column walked off the edge.
  local MAP = "PALLET_TOWN"
  local NORTH = "ROUTE_1"
  local COL = 10
  local START_Y = 3

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 100) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.onBike = false
  game.save.repelSteps = 9999
  game.save.player.name = "bryan"

  U.teleport(game, MAP, COL, START_Y, "up")
  U.wait(10)
  local ow = game.overworld
  local map = ow.map

  -- a usable exit column: four clear cells up to the edge, nothing standing
  -- in them, and a landing the engine's own edge read accepts (Map.defPassable
  -- is what crossConnection consults before it commits to the crossing)
  local function exitOK(cx)
    for cy = 0, START_Y do
      if not map:isWalkableCell(cx, cy) then return false end
      -- ow.npcs carries the follower too, and it is standing in this column
      local at = ow:npcAtCell(cx, cy)
      if at and not at.pikachuFollower then return false end
    end
    local p = ow.player
    local keepX = p.cellX
    p.cellX = cx
    local dest, ts, lx, ly = ow:connectionLanding("up")
    p.cellX = keepX
    return dest ~= nil and dest.id == NORTH
           and Map.defPassable(dest, ts, lx, ly, false)
  end

  if not exitOK(COL) then
    local found
    for cx = 0, map.widthCells - 1 do
      if exitOK(cx) then found = cx break end
    end
    U.log(("column %d no longer walks off the north edge; using column %s")
            :format(COL, tostring(found)))
    COL = found or COL
    U.teleport(game, MAP, COL, START_Y, "up")
    U.wait(10)
    ow = game.overworld
    map = ow.map
  end
  check(("column %d walks off %s's north edge onto %s"):format(COL, MAP, NORTH),
        exitOK(COL))

  local pika = PikachuFollower.current(ow)
  check("the follower spawned on " .. MAP, pika ~= nil)

  -- exactly one step north, then stop: the follower has to be trailing and
  -- settled, since a respawn on the cell it already occupies is invisible
  local p = ow.player
  local stopY = p.cellY - 1
  for _ = 1, 60 do
    if p.cellY <= stopY and not p.moving then break end
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    coroutine.yield()
  end
  game.input.state.up = false
  U.wait(20)
  U.log(("before the seam: player (%d, %d), follower (%s, %s)")
          :format(p.cellX, p.cellY, tostring(pika and pika.cellX),
                  tostring(pika and pika.cellY)))
  check("the follower trails one cell behind before the seam",
        pika ~= nil and pika.cellX == p.cellX and pika.cellY == p.cellY + 1)
  if U.shot(game, SHOT_DIR .. "/bug427_before_seam.png") then
    U.log("captured", SHOT_DIR .. "/bug427_before_seam.png")
  end

  -- Hold up through the crossing, sampling once per logic step (main.lua
  -- resumes the driver exactly once per Game:update).  The pixel offset
  -- between the two sprites is the measurement: a respawn loses the in-flight
  -- step, so the offset snaps even when the new instance lands on the right
  -- cell.  The mid-seam capture is armed inline instead of through U.shot so
  -- the walk keeps running while it lands.
  local samples, missing, maxJump = 0, 0, 0
  local prevX, prevY
  local crossedAt, pikaAfter
  local frames = 0
  while frames < 240 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    frames = frames + 1
    coroutine.yield()
    local npc = PikachuFollower.current(ow)
    if not npc then
      missing = missing + 1
    else
      local pl = ow.player
      local ox, oy = npc.px - pl.px, npc.py - pl.py
      if prevX then
        local jump = math.max(math.abs(ox - prevX), math.abs(oy - prevY))
        if jump > maxJump then maxJump = jump end
      end
      prevX, prevY = ox, oy
      samples = samples + 1
    end
    if not crossedAt and ow.map.def.id == NORTH then
      crossedAt = frames
      pikaAfter = npc
      game.capturePath = SHOT_DIR .. "/bug427_mid_seam.png"
    end
    if crossedAt and frames >= crossedAt + 24 then break end
  end
  game.input.state.up = false
  U.wait(30)

  check("the player crossed the seam onto " .. NORTH,
        crossedAt ~= nil and ow.map.def.id == NORTH)
  check("the follower across the seam is the same instance",
        pikaAfter ~= nil and pikaAfter == pika)
  check("it is still the same instance once the walk settles",
        PikachuFollower.current(ow) == pika)
  check(("it never dropped out of ow.npcs (%d of %d frames)")
          :format(missing, samples + missing), missing == 0 and samples > 0)
  check(("its pixel offset to the player never jumped (max %dpx)")
          :format(maxJump), maxJump <= 4)

  local settled = PikachuFollower.current(ow)
  p = ow.player
  if settled then
    U.log(("player (%d, %d) facing %s, follower (%d, %d)")
            :format(p.cellX, p.cellY, tostring(p.facing),
                    settled.cellX, settled.cellY))
  end
  check("the follower came to rest one cell behind",
        settled ~= nil and settled.cellX == p.cellX
        and settled.cellY == p.cellY + 1)
  local trail = ow.pikachuTrail
  check("the chased trail cell was rebased into the new map",
        trail ~= nil and ow.map:inBounds(trail.x, trail.y))

  local mid = io.open(SHOT_DIR .. "/bug427_mid_seam.png", "rb")
  if mid then
    mid:close()
    U.log("captured", SHOT_DIR .. "/bug427_mid_seam.png")
  else
    U.log("FAIL screenshot did not reach disk:", SHOT_DIR .. "/bug427_mid_seam.png")
  end
  if U.shot(game, SHOT_DIR .. "/bug427_after_seam.png") then
    U.log("captured", SHOT_DIR .. "/bug427_after_seam.png")
  end

  U.log("You just walked north out of Pallet onto Route 1 with Pikachu behind")
  U.log("you.  In bug427_mid_seam.png it has to be below you and mid-stride, on")
  U.log("the pixels the walk left it on; the bug put it squarely on a cell in")
  U.log("front of you instead, once per seam, which is the pop in the report.")
  U.log("Warps still respawn it behind you (walk through any door), and a")
  U.log("fainted or deposited Pikachu still leaves no follower at a seam.")

  while true do
    coroutine.yield()
  end
end

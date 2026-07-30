-- Yellow follower cadence (#424): the ledge hop deferred a player step, the
-- standing idle counters at OverworldLoop's two DelayFrames per pass, and the
-- pikapic beat timed by its own pikapic_setduration (pokeyellow engine/pikachu/
-- pikachu_follow.asm Func_fc803/Func_fcc64/Func_fcc92, home/overworld.asm:43,
-- pikachu_pic_animation.asm ExecutePikaPicAnimScript).  Never POKEPORT_SPEED:
-- it scales the logic clock alone and every number judged here is a frame count.
--   POKEPORT_DRIVER=tests/drivers/pikachu_cadence_bug424_test.lua POKEPORT_IDENTITY=bug424 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local PikachuFollower = require("src.world.PikachuFollower")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local results = {}
  local function check(label, ok)
    results[#results + 1] = { label = label, ok = ok and true or false }
    return ok
  end
  local function report()
    for _, r in ipairs(results) do U.log(r.ok and "PASS" or "FAIL", r.label) end
  end
  local function idleForever()
    while true do coroutine.yield() end
  end

  if not GameVersion.isYellow() then
    check("running the Yellow cache (POKEPORT_VERSION=yellow)", false)
    report()
    U.log("Red and Blue have no follower, no idle rolls and no pikapic box.")
    idleForever()
  end

  -- ShouldPikachuSpawn's preconditions (pikachu_follow.asm): the lab gift
  -- happened and a healthy Pikachu leads the party.  Without both there is no
  -- follower and every count below would read as the bug.
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false

  local frames = 0
  local function step(n)
    for _ = 1, n do
      coroutine.yield()
      frames = frames + 1
    end
  end

  -- ROUTE_1 (pokeyellow data/maps/objects/Route1.asm has no object near the
  -- ledge run) carries the first plain south-facing ledge; (5, 4) is the cell
  -- to hop from, re-derived below out of the cached blocks against
  -- data.field.ledges so a map edit moves the test instead of breaking it.
  local MAP = "ROUTE_1"
  local WANT = { x = 5, y = 4 }

  local function southLedge(map, cx, cy)
    if not (map:inBounds(cx, cy) and map:inBounds(cx, cy + 3)) then return false end
    -- the landing plus one more open cell below it: the queued hop only drains
    -- on the player's next step, so the ledge needs room for that step
    if not (map:isWalkableCell(cx, cy) and map:isWalkableCell(cx, cy - 1)
            and map:isWalkableCell(cx, cy + 2)
            and map:isWalkableCell(cx, cy + 3)) then
      return false
    end
    local standing, front = map:cellTile(cx, cy), map:cellTile(cx, cy + 1)
    for _, l in ipairs(game.data.field.ledges or {}) do
      if (l.tileset or "OVERWORLD") == map.def.tileset
         and l.facing == "down" and l.input == "down"
         and l.standingTile == standing and l.ledgeTile == front then
        return true
      end
    end
    return false
  end

  U.teleport(game, MAP, WANT.x, WANT.y - 1, "down")
  U.wait(20)

  local ow = game.overworld
  check("overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)
  if not ow then
    report()
    idleForever()
  end

  local hx, hy = WANT.x, WANT.y
  if not southLedge(ow.map, hx, hy) then
    for cy = 1, ow.map.heightCells - 4 do
      for cx = 0, ow.map.widthCells - 1 do
        if southLedge(ow.map, cx, cy) then hx, hy = cx, cy break end
      end
      if hx ~= WANT.x or hy ~= WANT.y then break end
    end
    U.log(("(%d, %d) is no longer a south ledge; using"):format(WANT.x, WANT.y),
          hx, hy)
    U.teleport(game, MAP, hx, hy - 1, "down")
    U.wait(20)
    ow = game.overworld
  end
  check(("a south ledge to hop at (%d, %d)"):format(hx, hy),
        southLedge(ow.map, hx, hy))

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local npc = follower()
  if not check("the follower spawned", npc ~= nil) then
    report()
    idleForever()
  end

  -- ---- the standing idle clock ----
  -- Func_fc803 reloads $20 and decrements it once per UpdateSprites call, and
  -- a standing OverworldLoop burns two DelayFrames per pass, so one counter
  -- unit is two of this port's fixed steps: the glance lands on frame 64.
  local function glanceLeft()
    local idle = npc.idle
    if idle and idle.kind == "wait" then return idle.frames end
    return nil
  end

  for _ = 1, 90 do
    if glanceLeft() then break end
    step(1)
  end
  if not check("the follower is in the standing glance state", glanceLeft() ~= nil) then
    report()
    idleForever()
  end

  local last, lastAt = glanceLeft(), frames
  -- the first change lands a partial unit after the sampling started, so it
  -- only sets the baseline: every gap measured after it is a whole unit
  local minGap, maxGap, seen, resetAt, period = 99, 0, 0, nil, nil
  for _ = 1, 300 do
    step(1)
    local now = glanceLeft()
    if now == nil then break end
    if now ~= last then
      seen = seen + 1
      local gap = frames - lastAt
      if seen > 1 then
        if gap < minGap then minGap = gap end
        if gap > maxGap then maxGap = gap end
      end
      if now > last then
        if resetAt then period = period or frames - resetAt end
        resetAt = frames
      end
      last, lastAt = now, frames
    end
  end
  check("the idle counter loses one unit every two frames, not every frame",
        minGap == 2 and maxGap == 2)
  check("a full glance takes 64 frames ($20 units), not 32", period == 64)
  U.log("idle counter gap", minGap, "to", maxGap, "frames; glance period",
        tostring(period))

  -- ---- the ledge hop, one player step late ----
  -- Func_fcc08 hands a ledge step to Func_fcc64, which appends the $5-$8 hop
  -- on the takeoff step and nothing on the landing step; Func_fcc92 cannot pop
  -- a command with nothing queued behind it, so the hop waits for the player's
  -- next step and Pikachu sits two cells back until then.
  local sawHop, hopLen = false, nil
  local function sample()
    local f = follower()
    if f and f.hopStep then
      sawHop = true
      hopLen = hopLen or f.stepFrames
    end
  end

  for _ = 1, 200 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    step(1)
    sample()
    if (ow.player.hopFrames or 0) > 0 then break end
  end
  game.input.state["down"] = false
  check("the player's ledge hop fired", (ow.player.hopFrames or 0) > 0)

  for _ = 1, 150 do
    step(1)
    sample()
  end
  npc = follower()
  check("the follower waits on the cell the player took off from",
        npc ~= nil and npc.cellX == hx and npc.cellY == hy)
  check("it does not hop while the player stands still", not sawHop)
  if npc then
    U.log("player at", ow.player.cellX, ow.player.cellY,
          "| follower waiting at", npc.cellX, npc.cellY)
  end

  -- one more player step drains the buffered hop
  for _ = 1, 120 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    step(1)
    sample()
    if ow.player.cellY > hy + 2 then break end
  end
  game.input.state["down"] = false
  for _ = 1, 120 do
    step(1)
    sample()
  end

  check("the deferred hop then ran", sawHop)
  -- Func_fc7aa jumps to Func_fca0a on the $4 movement status before it asks
  -- AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer, so a hop is never a
  -- Fast step even though its goal is two cells off
  local walkLen = ow.player.stepFramesCur or ow.player.stepFrames or 16
  check("the hop takes a full step's frames, not a halved Fast step",
        hopLen == walkLen)
  U.log("hop step frames", tostring(hopLen), "against a walk's", walkLen)
  npc = follower()
  check("the follower cleared the ledge row",
        npc ~= nil and npc.cellY > hy + 1
        and ow.map:isWalkableCell(npc.cellX, npc.cellY))

  -- ---- the pikapic beat ----
  -- happiness 255 with mood 200 is the matrix cell for emotion 20 (a heart
  -- bubble and PikaPicAnimScript20: 50 ticks, so 150 frames, with the second
  -- full-body pose up for 24 of every 40 ticks).
  game.save.pikachuHappiness = 255
  game.save.pikachuMood = 200

  local DIRS = { { "down", 0, 1 }, { "up", 0, -1 },
                 { "left", -1, 0 }, { "right", 1, 0 } }
  local function facingFollower()
    local fx, fy = ow.player:facingCell()
    return follower() ~= nil and ow:npcAtCell(fx, fy) == follower()
  end
  if not facingFollower() then
    for _, d in ipairs(DIRS) do
      if npc and npc.cellX == ow.player.cellX + d[2]
         and npc.cellY == ow.player.cellY + d[3] then
        U.tap(game, d[1])
        U.wait(6)
        break
      end
    end
  end
  check("player is facing the follower", facingFollower())

  -- a muted run sounds like a beat that never started, so say so up front
  local sfxVol = game.save.options and game.save.options.sfxVol
  U.log("save.options.sfxVol:", tostring(sfxVol))
  if (sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: the squeak cannot be heard whether or not")
    U.log("WARNING one plays. Raise it in OPTIONS before judging the sound.")
  end

  U.tap(game, "a")
  U.wait(1)
  local emote = ow.emote
  if not check("the A press raised the framed pikapic", emote ~= nil) then
    report()
    idleForever()
  end
  check("the beat runs the script's 50 ticks at three frames each",
        emote.pikaTotal == 150)
  check("its length is not the old flat 50 frame hold", emote.pikaTotal ~= 50)
  check("the pikapic marks itself skippable", emote.skippable == true)
  check("emotion 20 carries an overlay frameset", type(emote.pikaSeq) == "table")

  local lifted, grounded, liftShot = 0, 0, nil
  for _ = 1, 60 do
    if not ow.emote then break end
    local lift = PikachuFollower.picLift(ow.emote)
    if lift > 0 then
      lifted = lifted + 1
      if not liftShot then
        liftShot = SHOT_DIR .. "/bug424_pikapic_lift.png"
        if U.shot(game, liftShot) then U.log("captured", liftShot)
        else liftShot = nil end
      end
    else
      grounded = grounded + 1
    end
    step(1)
  end
  check("the pic sits on the box floor for part of the beat", grounded > 0)
  check("and rises off it for another part", lifted > 0)
  U.log("of the first 60 frames the pic was up for", lifted, "and down for",
        grounded)

  local leftWhenCut = ow.emote and ow.emote.frames or 0
  U.tap(game, "a")
  U.wait(2)
  check("A cuts the beat short (PikaPicAnimTimerAndJoypad)",
        leftWhenCut > 0 and ow.emote == nil)
  U.log("cut with", leftWhenCut, "frames still on the clock")

  report()

  -- hand the pad back one cell above the same ledge so Down replays the hop
  U.teleport(game, MAP, hx, hy - 1, "down")
  U.wait(20)

  U.log("Hold Down: Pikachu should walk up to the ledge lip and WAIT there,")
  U.log("then clear both cells in one motion on your next step, at walking")
  U.log("speed. Let go and count the first glance: about a second, not half.")
  U.log("Face it, press A: the framed pic hops inside the box for the whole")
  U.log("beat, and A or B cuts the beat off early.")

  idleForever()
end

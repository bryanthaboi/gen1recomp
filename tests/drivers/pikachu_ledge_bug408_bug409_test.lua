-- Ledge hop with the Yellow follower: one shadow under the jumper (#408)
-- and Pikachu clearing the ledge in one motion instead of stopping on it
-- (#409).  The hop cell is searched out of the loaded map's own blocks
-- against data.field.ledges (pokeyellow data/tilesets/ledge_tiles.asm), so
-- a map edit moves the test instead of breaking it.  Never add
-- POKEPORT_SPEED here: it scales only the logic clock while audio keeps its
-- own real-time accumulator, which desyncs the exact 32 frames being judged.
--   POKEPORT_DRIVER=tests/drivers/pikachu_ledge_bug408_bug409_test.lua POKEPORT_IDENTITY=bug408 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")

  local results = {}
  local function check(label, ok)
    results[#results + 1] = { label = label, ok = ok and true or false }
    return ok
  end
  local function report()
    for _, r in ipairs(results) do U.log(r.ok and "PASS" or "FAIL", r.label) end
  end

  if not GameVersion.isYellow() then
    check("running under POKEPORT_VERSION=yellow", false)
    report()
    U.log("Nothing else in this driver applies to RED/BLUE: there is no")
    U.log("follower to hop, and the four-quadrant shadow is correct there.")
    while true do coroutine.yield() end
  end

  -- ShouldPikachuSpawn's two preconditions (engine/pikachu/
  -- pikachu_follow.asm): the lab gift happened and a healthy Pikachu is in
  -- the party.  Without both, ow.npcs never gets a follower and every
  -- follower check below would read as the bug.
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false

  -- ROUTE_1 (10x18 blocks) is the first outdoor map with a plain
  -- south-facing ledge run; (5, 4) is the standing cell of one, read out of
  -- the cached blocks rather than typed from a map screenshot.  scanHop
  -- re-derives it below and this only picks the starting point.
  local MAP = "ROUTE_1"
  local WANT = { x = 5, y = 4 }

  -- data.field.ledges rows for the loaded tileset, in the shape
  -- OverworldState:checkLedgeHop matches (facing == input == the pressed
  -- direction, standing tile under the player, ledge tile in front).
  local function ledgeRows(map, dir)
    local rows = {}
    for _, l in ipairs(game.data.field.ledges or {}) do
      if (l.tileset or "OVERWORLD") == map.def.tileset
         and l.facing == dir and l.input == dir then
        rows[#rows + 1] = l
      end
    end
    return rows
  end

  local function ledgeTileSet(map)
    local set = {}
    for _, l in ipairs(game.data.field.ledges or {}) do
      if (l.tileset or "OVERWORLD") == map.def.tileset then
        set[l.ledgeTile] = true
      end
    end
    return set
  end

  -- a cell the player can hop south from, with two walkable cells above it
  -- to walk in from and a walkable landing two cells below
  local function hopCellOk(map, cx, cy)
    if not (map:inBounds(cx, cy) and map:inBounds(cx, cy + 3)) then
      return false
    end
    if not map:isWalkableCell(cx, cy) then return false end
    if not map:isWalkableCell(cx, cy + 2) then return false end
    -- one more open cell below the landing: the queued hop only drains on
    -- the player's NEXT step, so the ledge needs room to take it (#424)
    if not map:isWalkableCell(cx, cy + 3) then return false end
    if not (map:isWalkableCell(cx, cy - 1)
            and map:isWalkableCell(cx, cy - 2)) then
      return false
    end
    local standing = map:cellTile(cx, cy)
    local front = map:cellTile(cx, cy + 1)
    for _, l in ipairs(ledgeRows(map, "down")) do
      if l.standingTile == standing and l.ledgeTile == front then return true end
    end
    return false
  end

  local function scanHop(map)
    for cy = 2, map.heightCells - 3 do
      for cx = 0, map.widthCells - 1 do
        if hopCellOk(map, cx, cy) then return cx, cy end
      end
    end
    return nil
  end

  U.teleport(game, MAP, WANT.x, WANT.y - 2, "down")
  U.wait(20)

  local ow = game.overworld
  check("overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)
  if not ow then
    report()
    while true do coroutine.yield() end
  end

  local hx, hy = WANT.x, WANT.y
  if not hopCellOk(ow.map, hx, hy) then
    local sx, sy = scanHop(ow.map)
    if sx then
      U.log(("(%d, %d) is no longer a south ledge; using"):format(WANT.x, WANT.y),
            sx, sy)
      hx, hy = sx, sy
      U.teleport(game, MAP, hx, hy - 2, "down")
      U.wait(20)
      ow = game.overworld
    end
  end
  check(("a south ledge to hop at (%d, %d)"):format(hx, hy),
        hopCellOk(ow.map, hx, hy))

  local LEDGES = ledgeTileSet(ow.map)

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  check("the follower spawned", follower() ~= nil)

  -- sampled every frame from here on: the two things that only exist
  -- mid-motion.  A follower at rest on a ledge tile is #409 exactly -- it
  -- walked onto the ledge and stopped there instead of clearing it.
  local maxHop, sawHopStep, restedOnLedge = 0, false, false
  local function sample()
    local p = ow.player
    if p.hopFrames and p.hopFrames > maxHop then maxHop = p.hopFrames end
    local npc = follower()
    if not npc then return end
    if npc.hopStep then sawHopStep = true end
    if not npc.moving and LEDGES[ow.map:cellTile(npc.cellX, npc.cellY)] then
      restedOnLedge = true
    end
  end

  local function step(n)
    for _ = 1, n do
      coroutine.yield()
      sample()
    end
  end

  -- walk south into the ledge, one frame of held Down at a time, and let go
  -- the moment the hop commits so the landing cannot roll straight into a
  -- second hop
  local walked = 0
  for _ = 1, 200 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    coroutine.yield()
    sample()
    walked = walked + 1
    if ow.player.hopFrames and ow.player.hopFrames > 0 then break end
  end
  game.input.state["down"] = false

  check("the player's ledge hop actually fired", maxHop > 0)

  -- mid-arc: count the shadow quads one Player:draw puts down.  Player:draw
  -- issues its shadow copies back to back before the sprite, so the longest
  -- run of consecutive love.graphics.draw calls carrying shadowImg is that
  -- per-frame count.  Yellow's LedgeHoppingShadowOAM is two entries (dbsprite
  -- 9,11 and 10,11 OAM_XFLIP, engine/overworld/ledges.asm) mirrored into one
  -- 16x8 ellipse; RED's four-quadrant block is what #408 was leaking in.
  local shadowDraws
  local img = ow.player.shadowImg
  check("the hop shadow tile loaded", img ~= nil)
  if img then
    local real = love.graphics.draw
    local run, best = 0, 0
    love.graphics.draw = function(a, ...)
      if a == img then
        run = run + 1
        if run > best then best = run end
      else
        run = 0
      end
      return real(a, ...)
    end
    step(4)
    love.graphics.draw = real
    shadowDraws = best
    check("exactly one mirrored pair of shadow quads per frame (2 draws)",
          shadowDraws == 2)
  end

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local midShot = SHOT_DIR .. "/bug408_hop_midair.png"
  if ow.player.hopFrames and ow.player.hopFrames > 0 then
    check("mid-arc screenshot reached disk", U.shot(game, midShot) and true)
    U.log("captured", midShot, "at hopFrames", ow.player.hopFrames)
  else
    check("mid-arc screenshot reached disk", false)
    U.log("the arc was already over before the capture; no mid-air frame")
  end

  -- The hop command is buffered a step behind the player: Func_fcc64 appends
  -- nothing for the landing half of the jump, so Func_fcc92 cannot pop the
  -- hop until another command queues behind it.  Pikachu therefore walks to
  -- the cell the player took off from and waits there (#424).
  step(120)
  local waiting = follower()
  check("the follower waits on the cell the player took off from",
        waiting ~= nil and waiting.cellX == hx and waiting.cellY == hy)
  check("it has not hopped while the player stood still", not sawHopStep)

  -- one more player step drains the queued hop
  for _ = 1, 90 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    coroutine.yield()
    sample()
    if ow.player.cellY > hy + 2 then break end
  end
  game.input.state["down"] = false

  -- let the follower finish crossing (its hop is one normal step's frames
  -- with a doubled step vector, pikachu_follow.asm Func_fca0a)
  step(120)

  local npc = follower()
  check("the follower is still on the map", npc ~= nil)
  if npc then
    local tile = ow.map:cellTile(npc.cellX, npc.cellY)
    check("the follower came to rest on a walkable cell",
          ow.map:isWalkableCell(npc.cellX, npc.cellY))
    check("that cell is not a ledge tile", not LEDGES[tile])
    check("the follower ended below the ledge row", npc.cellY > hy + 1)
    check("it took the doubled hop step, not two walks", sawHopStep)
    U.log(("follower rests at (%d, %d), tile %s; player at (%d, %d)")
            :format(npc.cellX, npc.cellY, tostring(tile),
                    ow.player.cellX, ow.player.cellY))
  end
  check("the follower never stood still on a ledge tile", not restedOnLedge)

  local afterShot = SHOT_DIR .. "/bug409_after_follow.png"
  check("landing screenshot reached disk", U.shot(game, afterShot) and true)
  U.log("captured", afterShot)
  U.log("walked", walked, "frames into the ledge at", hx, hy)

  report()

  -- hand the pad back one cell short of the same ledge, so Down alone
  -- re-runs the hop as many times as the reader wants
  U.teleport(game, MAP, hx, hy - 1, "down")
  U.wait(20)

  U.log("Hold Down to hop the ledge again from here.")
  U.log("During the arc there should be one flat ellipse on the ground under")
  U.log("the player, not a taller blob with a seam across its middle.")
  U.log("Pikachu should walk up to the cell you jumped from and STAY there")
  U.log("until you take another step, then clear both cells in one motion.")
  U.log("The near misses to watch for are Pikachu hopping alongside you and")
  U.log("Pikachu pausing a beat on the ledge tile itself.")

  while true do
    coroutine.yield()
  end
end

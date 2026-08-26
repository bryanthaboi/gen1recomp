-- A ledge hop advances every logic frame, the way every other step does.
--
--   luajit tests/gen2_ledge_hop_test.lua
--
-- A hop is the engine's only two-cell move (World:tryLedgeJump, STEP_LEDGE).
-- On the cart it is jump_step, i.e. STEP_WALK (pokegold/engine/overworld/
-- movement.asm:595-597), so GetStepVector hands StepFunction_PlayerJump the
-- `db 0, 2, 8, 2` row (map_objects.asm:365-381) and .stepjump / .stepland run
-- it as two 8-frame beats: 16 frames, 2px EVERY frame, and UpdateJumpPosition
-- (:1796-1817) adds the speed to OBJECT_JUMP_HEIGHT and indexes its 16-entry
-- arc at height/2, one entry per frame.
--
-- We render Gen 2 at twice that temporal resolution (Player.STEP_FRAMES = 16
-- for one cell), so the hop is 32 frames and has to move 1px and half an arc
-- entry on every one of them.  It used to compute the sub-cell offset per CELL
-- and then scale it by the cell delta, so half the hop's frames moved nothing
-- and the other half jumped 2px -- and since the camera follows px/py, the
-- whole map scrolled at 30Hz.  The arc had the matching quantum with the
-- opposite sign, which dragged the sprite back UP the screen five times.  #1713
--
-- Self-contained: no cache, no love.  tests/drivers/gold_ledge_hop_bug1713_
-- test.lua is the half a person watches.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 ledge hop")
local check, eq = S.check, S.eq

local Player = require("src.world.gen2.Player")
local Permissions = require("src.world.gen2.Permissions")
local World = require("src.world.gen2.World")

local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                left = { -1, 0 }, right = { 1, 0 } }

-- ---- one move, frame by frame ----------------------------------------------
--
-- What the renderer reads each frame: the position the camera follows, and the
-- OBJECT_SPRITE_Y_OFFSET added on top of it.  Row 1 is the standing frame
-- before the move starts, so row i+1 is frame i.
local function playMove(dir, opts)
  opts = opts or {}
  local p = Player.new(5, 5, dir)
  local d = DELTA[dir]
  local cells = opts.jump and 2 or 1
  p.targetX, p.targetY = p.cellX + d[1] * cells, p.cellY + d[2] * cells
  p.moving = true
  p.progress = 0
  p.jumping = opts.jump or nil
  p.stepFrames = opts.stepFrames
    or (opts.jump and Player.STEP_FRAMES * 2 or Player.STEP_FRAMES)
  local rows = { { px = p.px, py = p.py, off = 0 } }
  local frames = 0
  while p.moving and frames < 200 do
    p:update()
    frames = frames + 1
    rows[#rows + 1] = { px = p.px, py = p.py, off = p.spriteYOffset or 0 }
  end
  return p, rows, frames
end

-- Per-frame change in one recorded column.
local function steps(rows, key)
  local out = {}
  for i = 2, #rows do out[i - 1] = rows[i][key] - rows[i - 1][key] end
  return out
end

local function countIf(list, fn)
  local n = 0
  for _, v in ipairs(list) do if fn(v) then n = n + 1 end end
  return n
end

-- ---- the control: an ordinary one-cell walk --------------------------------
--
-- The hop's fix must not have been bought by moving this.
do
  local p, rows, frames = playMove("down")
  eq(frames, Player.STEP_FRAMES, "a walk is 16 logic frames")
  local dy = steps(rows, "py")
  eq(countIf(dy, function(v) return v ~= 1 end), 0,
    "and every one of them moves the player exactly one pixel down")
  eq(countIf(steps(rows, "px"), function(v) return v ~= 0 end), 0,
    "with no sideways drift")
  eq(p.cellY, 6, "it lands one cell on")
  eq(p.py, 6 * 16, "on the pixel the cell says")

  -- .DoStep's STEP_BIKE arm: the same one cell in half the frames, so the
  -- per-frame advance doubles.  This is what a span applied to the wrong
  -- denominator breaks first.
  local bike, bikeRows, bikeFrames =
    playMove("right", { stepFrames = Player.STEP_FRAMES / 2 })
  eq(bikeFrames, 8, "a bike step is 8 logic frames")
  eq(countIf(steps(bikeRows, "px"), function(v) return v ~= 2 end), 0,
    "each moving two pixels, so a bike still covers one cell")
  eq(bike.cellX, 6, "and lands one cell on, not two")
end

-- ---- the hop ---------------------------------------------------------------
--
-- The bug, stated as numbers: half these frames used to move nothing and the
-- other half used to move two pixels.
local hopP, hopRows, hopFrames = playMove("down", { jump = true })
eq(hopFrames, Player.STEP_FRAMES * 2, "a ledge hop is 32 logic frames")
local hopDy = steps(hopRows, "py")
eq(countIf(hopDy, function(v) return v ~= 1 end), 0,
  "every frame of a ledge hop moves the player a pixel")
eq(countIf(hopDy, function(v) return math.abs(v) >= 2 end), 0,
  "and no frame of it moves two")
eq(countIf(steps(hopRows, "px"), function(v) return v ~= 0 end), 0,
  "a hop straight down never moves sideways")
-- The near miss: span math applied without the matching frames scaling covers
-- one cell in 32 frames instead of two.
eq(hopRows[#hopRows].py - hopRows[1].py, 32,
  "the 32 frames add up to 32 pixels, which is two cells")
eq(hopP.cellY, 7, "and the grid agrees the player crossed two cells")
eq(hopP.py, 7 * 16, "landing on the landing cell's own pixel")
eq(countIf(hopRows, function(r)
  return r.px % 1 ~= 0 or r.py % 1 ~= 0
end), 0, "and no frame leaves the player on a half pixel")

-- ---- the arc ---------------------------------------------------------------
--
-- UpdateJumpPosition's .y_offsets: -4 up to -12 and back to 0, one entry per
-- cart frame, so across our doubled step it is half an entry per frame.
do
  local off = {}
  for i = 2, #hopRows do off[#off + 1] = hopRows[i].off end
  local peak = 0
  for i = 1, #off do if off[i] < peak then peak = off[i] end end
  -- The arc rises, then falls, and changes its mind exactly once: any extra
  -- sign change in the offsets is the sprite wobbling.
  local moves = {}
  for i = 2, #off do
    local v = off[i] - off[i - 1]
    if v ~= 0 then moves[#moves + 1] = v end
  end
  local turns = 0
  for i = 2, #moves do
    if (moves[i] > 0) ~= (moves[i - 1] > 0) then turns = turns + 1 end
  end
  eq(off[1], -4, "the arc opens on the table's first entry")
  eq(peak, -12, "peaks 12 pixels up, the table's own peak")
  eq(off[#off], 0, "and is back on the ground for the landing frame")
  eq(turns, 1, "rising then falling, once, with no wobble in between")
  eq(countIf(off, function(v) return v > 0 or v < -12 end), 0,
    "and never leaves the range the table covers")

  -- The composed screen position, which is what an eye actually tracks: the
  -- camera-following py plus the sprite offset.  The first frame lifts the
  -- sprite -- that is the take-off -- and after it a hop DOWN may never go
  -- backwards.  Before the fix it did so on five frames.
  local screen, back = {}, 0
  for i = 2, #hopRows do
    screen[#screen + 1] = hopRows[i].py + hopRows[i].off
  end
  for i = 2, #screen do
    if screen[i] < screen[i - 1] then back = back + 1 end
  end
  eq(back, 0, "the arc never drags the sprite back up the screen")
  check(screen[1] < hopRows[1].py + hopRows[1].off,
    "the one time it does rise is the take-off, on the first frame")
  eq(countIf(steps(hopRows, "py"), function(v) return v ~= 1 end), 0,
    "while the map underneath scrolls one pixel a frame throughout")
end

-- A sideways hop is the same move on the other axis: Gold's $a0 is HOP_RIGHT.
for _, dir in ipairs({ "left", "right" }) do
  local p, rows, frames = playMove(dir, { jump = true })
  local want = DELTA[dir][1]
  eq(frames, 32, ("a %s hop is 32 logic frames too"):format(dir))
  eq(countIf(steps(rows, "px"), function(v) return v ~= want end), 0,
    ("and moves one pixel %s on every one of them"):format(dir))
  eq(countIf(steps(rows, "py"), function(v) return v ~= 0 end), 0,
    ("a %s hop never slides the player up or down a row"):format(dir))
  eq(p.cellX, 5 + want * 2, ("it lands two cells %s"):format(dir))
end

-- The step ends clean: nothing about the jump is left set for the next walk.
eq(hopP.moving, false, "the hop ends the step")
eq(hopP.jumping, nil, "and clears the jump")
eq(hopP.spriteYOffset, 0, "and puts the sprite back on its feet")

-- ---- the same hop, through World -------------------------------------------
--
-- Player alone cannot prove the wiring: World:tryLedgeJump is what picks the
-- two-cell target and the doubled duration (World.lua's STEP_LEDGE arm), and a
-- fix that only touched one of the two would still stutter in the game.
local COLL_FLOOR, COLL_WALL, COLL_HOP_DOWN = 0x00, 0x07, 0xa3

local function ledgeWorld(px, py, dir, coll)
  local game = {
    data = { items = {}, moves = {}, pokemon = {} },
    save = { player = { name = "GOLD", badges = {} }, party = {},
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  local cells = {}
  cells[py * 100 + px] = coll or COLL_HOP_DOWN
  local d = DELTA[dir]
  -- The refused single step, which is what turns the walk into a jump.
  cells[(py + d[2]) * 100 + (px + d[1])] = COLL_WALL
  local map
  map = {
    id = "ROUTE_29",
    width = 10, height = 10,
    def = { objects = {}, bgEvents = {}, environment = "ROUTE",
      tileset = "TILESET_JOHTO", width = 10, height = 10 },
    cellCollision = function(_, x, y)
      return cells[y * 100 + x] or COLL_FLOOR
    end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 20 and y < 20
    end,
    isWalkable = function(_, x, y)
      return map:inBounds(x, y)
        and Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
    connection = function() return nil end,
  }
  world.map = map
  world.maps = { ROUTE_29 = map.def }
  world.player = Player.new(px, py, dir)
  world.player.turnArmed = false
  world.entities = { world.player }
  world.npcs = {}
  world.encounters = {}
  world.noWildEncounters = true
  world.pollTimeOfDay = function() end
  world.updatePeople = function() end
  return world
end

check(Permissions.isLedge(COLL_HOP_DOWN), "$a3 is a ledge")
check((Permissions.ledgeFacings(COLL_HOP_DOWN) or {}).down,
  "and its row hops DOWN")

do
  local world = ledgeWorld(4, 5, "down")
  local p = world.player
  local rows, airborne = {}, false
  for _ = 1, 120 do
    world.heldDir = (not airborne) and "down" or nil
    local wasAirborne = airborne
    world:step()
    if p.jumping then airborne = true end
    if airborne then
      rows[#rows + 1] = { px = p.px, py = p.py, off = p.spriteYOffset or 0 }
    end
    if wasAirborne and not p.moving then break end
  end
  check(#rows > 0, "holding down on a ledge starts a hop")
  eq(#rows - 1, 32, "which runs the doubled 32-frame duration")
  eq(p.cellY, 7, "and lands two cells down, on the far side of the wall")
  local dy = steps(rows, "py")
  eq(countIf(dy, function(v) return v ~= 1 end), 0,
    "every frame of the in-game hop scrolls the map exactly one pixel")
  eq(rows[#rows].py - rows[1].py, 32,
    "so the whole hop is 32 pixels of travel, not 16")
  local screen, back = {}, 0
  for i = 2, #rows do screen[#screen + 1] = rows[i].py + rows[i].off end
  for i = 2, #screen do
    if screen[i] < screen[i - 1] then back = back + 1 end
  end
  eq(back, 0, "and after the take-off the sprite never reverses")
end

S.finish()

-- Whirlpool tiles force-turn the player: DoPlayerMovement's .CheckTile, the
-- CheckWhirlpoolTile arm that sits ABOVE the nybble ladder.
--
--   luajit tests/gen2_whirlpool_test.lua
--
-- COLL_WHIRLPOOL is tested first and takes PLAYERMOVEMENT_FORCE_TURN
-- (engine/overworld/player_movement.asm:117-123), which runs Script_ForcedMovement
-- (engine/events/forced_movement.asm:1-51): step_dig 16, turn_in <back>,
-- step_dig 16, turn_head <back>, step_end.  So a whirlpool is entered, whirled
-- on, and left again the way the player came, with the d-pad ignored throughout.
--
-- The port had no arm at all -- only the HI_NYBBLE_CURRENT and HI_NYBBLE_WARPS
-- ones -- so a whirlpool cell was plain water and a surfer swam straight over
-- it, past the HM06 + GLACIERBADGE gate on Route 41 and Route 27.  Two decoding
-- gaps sat under that: turn_away / turn_in / turn_waterfall all `jp TurningStep`
-- (engine/overworld/movement.asm:483-513), which is a real one-cell STEP under
-- OBJECT_ACTION_SPIN, and $4f step_dig was not modelled at all.  #1716
--
-- The whirl itself is drawing, so what is asserted here is the state the
-- drawing reads (Player.spinFrames) and the grid the player ends on.
-- tests/drivers/gold_whirlpool_forceturn_bug1716_test.lua is the other half.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 whirlpool")
local check, eq, same = S.check, S.eq, S.same

local Movement = require("src.script.gen2.Movement")
local Permissions = require("src.world.gen2.Permissions")
local World = require("src.world.gen2.World")
local Player = require("src.world.gen2.Player")
local FieldMoves = require("src.world.gen2.FieldMoves")

-- ---- the tile --------------------------------------------------------------
--
-- CheckWhirlpoolTile is the two-entry compare COLL_WHIRLPOOL $24 / COLL_WHIRLPOOL_1 $2c.
local COLL_WATER, COLL_WHIRLPOOL, COLL_WHIRLPOOL_1 = 0x29, 0x24, 0x2c

check(Permissions.isWhirlpool(COLL_WHIRLPOOL), "COLL_WHIRLPOOL $24")
check(Permissions.isWhirlpool(COLL_WHIRLPOOL_1), "COLL_WHIRLPOOL_1 $2c")
check(not Permissions.isWhirlpool(COLL_WATER), "plain water is not one")
check(not Permissions.isWhirlpool(0x33), "and neither is a waterfall")
-- The arm is above the nybble ladder, not part of it: the tile's PERMISSION is
-- still WATER_TILE, which is what lets a surfing player step onto it at all.
check(Permissions.isWater(COLL_WHIRLPOOL),
  "a whirlpool is still WATER_TILE, so .CheckSurfable lets the step happen")
eq(Permissions.currentDirection(COLL_WHIRLPOOL), nil,
  "and it is not a HI_NYBBLE_CURRENT tile")

-- ---- Script_ForcedMovement's stream ----------------------------------------
--
-- .MovementData_up is `step_dig 16 / turn_in DOWN / step_dig 16 /
-- turn_head DOWN / step_end`, i.e. every byte points BACK the way the player
-- came.  turn_head is the $00 family, turn_in the $24 one, step_dig $4f with
-- its frame count in the byte after it (macros/scripts/movement.asm:163-167).
eq(Movement.STEP_DIG, 0x4f, "$4f step_dig")
eq(Movement.STEP_DIG_FRAMES, 16, "and the 16 frames the stream asks it for")
same(Movement.forcedMovementBytes("down"),
  { 0x4f, 16, 0x24, 0x4f, 16, 0x00, 0x47 },
  "thrown DOWN: step_dig 16, turn_in DOWN, step_dig 16, turn_head DOWN, end")
same(Movement.forcedMovementBytes("up"),
  { 0x4f, 16, 0x25, 0x4f, 16, 0x01, 0x47 }, "thrown UP")
same(Movement.forcedMovementBytes("left"),
  { 0x4f, 16, 0x26, 0x4f, 16, 0x02, 0x47 }, "thrown LEFT")
same(Movement.forcedMovementBytes("right"),
  { 0x4f, 16, 0x27, 0x4f, 16, 0x03, 0x47 }, "thrown RIGHT")

-- The middle byte is the one the port used to read as a facing change, which
-- is why the bounce could not exist: turn_in never moved anybody.
for byte, dir in pairs({ [0x24] = "down", [0x25] = "up",
                         [0x26] = "left", [0x27] = "right" }) do
  local act = Movement.decodeByte(byte)
  eq(act.kind, "step", ("$%02x turn_in crosses a cell"):format(byte))
  eq(act.dir, dir, ("$%02x turn_in direction"):format(byte))
  eq(act.spin, true, ("$%02x turn_in spins on the way"):format(byte))
end
eq(Movement.decodeByte(0x20).kind, "step", "$20 turn_away is a step too")
eq(Movement.decodeByte(0x28).kind, "step", "$28 turn_waterfall as well")
-- The neighbours must not have picked the spin up.
eq(Movement.decodeByte(0x0c).spin, nil, "$0c step is a plain step")
eq(Movement.decodeByte(0x10).spin, nil, "$10 big_step too")
eq(Movement.decodeByte(0x00).kind, "turn", "$00 turn_head is still a turn")

-- ---- the step --------------------------------------------------------------
--
-- One whirlpool at (5,5) in an open pond, the way Route 41's four sit: water on
-- every side of them (data/generated/maps.lua, ROUTE_41 (22,12)).
local WHIRL_X, WHIRL_Y = 5, 5

local function whirlWorld(px, py, facing, coll)
  local game = {
    data = { items = {}, moves = {}, pokemon = {} },
    save = { player = { name = "GOLD", badges = {} }, party = {},
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  local cells = {}
  for y = 0, 9 do
    for x = 0, 9 do cells[y * 100 + x] = COLL_WATER end
  end
  cells[WHIRL_Y * 100 + WHIRL_X] = coll or COLL_WHIRLPOOL
  local map
  map = {
    id = "ROUTE_41",
    width = 5, height = 5,
    def = { objects = {}, bgEvents = {}, environment = "WATER",
      tileset = "TILESET_JOHTO", width = 5, height = 5 },
    cellCollision = function(_, x, y)
      return cells[y * 100 + x] or COLL_WATER
    end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 10 and y < 10
    end,
    isWalkable = function(_, x, y)
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
    connection = function() return nil end,
  }
  world.map = map
  world.maps = { ROUTE_41 = map.def }
  world.player = Player.new(px, py, facing)
  world.entities = { world.player }
  world.npcs = {}
  world.playerState = FieldMoves.PLAYER_SURF
  world.encounters = {}
  world.pollTimeOfDay = function() end
  -- Nothing here draws, and nothing here is about the wild roll.
  world.noWildEncounters = true
  world.updatePeople = function() end
  return world, game
end

-- Swim at the whirlpool from `dir` for `frames` with the d-pad held the whole
-- way, the way a player leaning on it does, and report what happened.
local function swimInto(dir, frames)
  local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                  left = { -1, 0 }, right = { 1, 0 } }
  local d = DELTA[dir]
  -- Two cells short of the whirlpool, so the approach is an ordinary swim.
  local world = whirlWorld(WHIRL_X - d[1] * 2, WHIRL_Y - d[2] * 2, dir)
  local p = world.player
  local r = { onWhirlpool = false, spun = false, busy = false, past = false }
  for _ = 1, frames or 220 do
    world.heldDir = dir
    world:step()
    if p.cellX == WHIRL_X and p.cellY == WHIRL_Y then r.onWhirlpool = true end
    if p.spinFrames then r.spun = true end
    if world:busy() then r.busy = true end
    -- One cell past the whirlpool, on the far side.
    if p.cellX == WHIRL_X + d[1] and p.cellY == WHIRL_Y + d[2] then
      r.past = true
    end
  end
  r.x, r.y, r.facing = p.cellX, p.cellY, p.facing
  return r, world
end

-- The cart lets the player land on the whirlpool: FORCE_TURN is answered from
-- the tile UNDERFOOT, so the step onto it happens and the bounce follows.
local BACK = { up = "down", down = "up", left = "right", right = "left" }
for _, dir in ipairs({ "up", "down", "left", "right" }) do
  local r = swimInto(dir)
  check(r.onWhirlpool,
    ("swimming %s reaches the whirlpool cell"):format(dir))
  check(not r.past,
    ("holding %s never carries the player through it"):format(dir))
  check(r.busy,
    ("the forced movement owns the world while it runs (%s)"):format(dir))
  check(r.spun,
    ("step_dig put the player under OBJECT_ACTION_SPIN (%s)"):format(dir))
  eq(r.facing, BACK[dir],
    ("turn_head leaves the player facing away from it (%s)"):format(dir))
end

-- COLL_WHIRLPOOL_1 is the same arm, not a second tile that fell through.
do
  local world = whirlWorld(WHIRL_X, WHIRL_Y + 2, "up", COLL_WHIRLPOOL_1)
  local p = world.player
  local past = false
  for _ = 1, 220 do
    world.heldDir = "up"
    world:step()
    if p.cellY < WHIRL_Y then past = true end
  end
  check(not past, "$2c force-turns exactly like $24")
end

-- The negative control, and the reason the bug was invisible: the same cell as
-- plain water is swum straight over.
do
  local world = whirlWorld(WHIRL_X, WHIRL_Y + 2, "up", COLL_WATER)
  local p = world.player
  for _ = 1, 220 do
    world.heldDir = "up"
    world:step()
  end
  check(p.cellY < WHIRL_Y, "plain water in the same cell still lets us through")
  eq(p.spinFrames, nil, "and nothing spins over it")
end

-- The turn is answered from the tile the player is STANDING on, not from a
-- neighbour: swimming past a whirlpool one cell to the side is untouched.
do
  local world = whirlWorld(WHIRL_X - 1, WHIRL_Y + 2, "up")
  local p = world.player
  for _ = 1, 220 do
    world.heldDir = "up"
    world:step()
  end
  eq(p.cellX, WHIRL_X - 1, "the column beside the whirlpool is ordinary water")
  check(p.cellY < WHIRL_Y, "and it is swum up without a bounce")
end

-- The stream is Script_ForcedMovement's own, byte for byte, and it is queued
-- through the same World:beginMovement every applymovement uses -- so the
-- freeze, the follower and the step-end bookkeeping all come along with it.
do
  local world = whirlWorld(WHIRL_X, WHIRL_Y, "up")
  check(world:runForcedMovement(), "standing on one starts the stream")
  check(world.moveState ~= nil, "through an applymovement, not a bespoke path")
  same(world.moveState.bytes, Movement.forcedMovementBytes("down"),
    "and the bytes are the ones facing UP asks for")
  check(world:busy(), "which is what closes the overworld to input")
  -- It does not start a second copy over itself.
  check(not world:runForcedMovement(), "one stream at a time")
end

S.finish()

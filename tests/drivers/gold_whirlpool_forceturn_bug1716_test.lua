-- #1716: a whirlpool tile force-turns the player instead of being swum through.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_whirlpool_forceturn_bug1716_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-whirlpool \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- DoPlayerMovement's .CheckTile runs CheckWhirlpoolTile above the nybble ladder
-- and answers PLAYERMOVEMENT_FORCE_TURN (engine/overworld/player_movement.asm
-- :117-123), which is Script_ForcedMovement: step_dig 16, turn_in <back>,
-- step_dig 16, turn_head <back>, step_end (engine/events/forced_movement.asm
-- :25-51).  turn_in `jp TurningStep`, i.e. InitStep under OBJECT_ACTION_SPIN --
-- a spinning one-cell step, not a facing change.
--
-- No POKEPORT_SPEED here on purpose: the spin, the step and the settle are what
-- is being watched, and fast-forward scales only the logic clock.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Movement = require("src.script.gen2.Movement")
local Mon = require("src.battle.gen2.Mon")
local Permissions = require("src.world.gen2.Permissions")

-- data/generated/maps.lua, ROUTE_41: four whirlpools, the first at (22,12) with
-- plain water above and below it.  Verified live below, and re-derived by
-- scanning the map if a re-import ever moves it.
local MAP = "ROUTE_41"
local WHIRL = { x = 22, y = 12 }

local DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-whirlpool"
  local fails, lines = 0, {}

  local function claim(ok, text)
    if not ok then fails = fails + 1 end
    lines[#lines + 1] = (ok and "PASS " or "FAIL ") .. text
    return ok
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL the gold world never booted, nothing to look at")
    while true do coroutine.yield() end
  end

  -- ---- the things a human's eyes cannot check ------------------------------
  --
  -- All of these fail silently and look exactly like "the fix did nothing".
  claim(Movement.decodeByte(0x24).kind == "step",
    "$24 turn_in decodes as a step, not a facing change")
  claim(Movement.decodeByte(0x24).spin == true,
    "and it carries OBJECT_ACTION_SPIN")
  claim(Movement.STEP_DIG == 0x4f and Movement.STEP_DIG_FRAMES == 16,
    "$4f step_dig is modelled, 16 frames")
  claim(type(world.runForcedMovement) == "function",
    "World:runForcedMovement exists for .CheckTile to call")
  claim(type(world.player.scriptSpin) == "function",
    "Player:scriptSpin exists for step_dig to drive")

  -- SURF but deliberately NOT WHIRLPOOL, and no GLACIERBADGE: TryWhirlpoolOW
  -- must never get a look in, or what we would be watching is the prompt.
  local badges = game.save.player.badges or {}
  game.save.player.badges = badges
  for _, badge in pairs(FieldMoves.BADGE) do badges[badge] = nil end
  badges[FieldMoves.BADGE.SURF] = true
  local swimmer = Mon.new(game.data, "LAPRAS", 30,
    { moves = { { id = "SURF" } } })
  claim(swimmer ~= nil, "a LAPRAS that knows SURF and nothing else")
  game.save.party = { swimmer }
  claim(not FieldMoves.hasBadge(game.save, FieldMoves.BADGE.WHIRLPOOL),
    "no GLACIERBADGE, so no whirlpool prompt can fire")

  -- ---- find the whirlpool --------------------------------------------------
  world:applyPlayerState(FieldMoves.PLAYER_SURF)
  world:setMap(MAP, WHIRL.x, WHIRL.y - 1, "down")
  U.wait(10)
  world.noWildEncounters = true
  local map = world.map

  local function isWhirl(x, y)
    return map:inBounds(x, y) and Permissions.isWhirlpool(map:cellCollision(x, y))
  end
  local function isOpenWater(x, y)
    return map:inBounds(x, y)
      and Permissions.isWater(map:cellCollision(x, y))
      and not Permissions.isWhirlpool(map:cellCollision(x, y))
  end

  local target, approach = nil, nil
  if isWhirl(WHIRL.x, WHIRL.y) then target = { x = WHIRL.x, y = WHIRL.y } end
  if not target then
    -- A re-import moved it; take any whirlpool on the map instead of parking
    -- the player on open sea with nothing to look at.
    local def = world.maps[MAP]
    for y = 0, (def.height or 0) * 2 - 1 do
      for x = 0, (def.width or 0) * 2 - 1 do
        if not target and isWhirl(x, y) then target = { x = x, y = y } end
      end
    end
  end
  if target then
    for _, dir in ipairs({ "down", "up", "right", "left" }) do
      local d = DELTA[dir]
      if not approach and isOpenWater(target.x - d[1], target.y - d[2]) then
        approach = { x = target.x - d[1], y = target.y - d[2], dir = dir }
      end
    end
  end
  claim(target ~= nil, ("%s still has a whirlpool tile on it"):format(MAP))
  claim(approach ~= nil, "with open water beside it to swim in from")
  if not (target and approach) then
    for _, line in ipairs(lines) do U.log(line) end
    U.log("nothing to drive; stopping here rather than faking the moment")
    while true do coroutine.yield() end
  end
  if target.x ~= WHIRL.x or target.y ~= WHIRL.y then
    U.log(("note: using the whirlpool at (%d,%d), not the (%d,%d) in the header")
      :format(target.x, target.y, WHIRL.x, WHIRL.y))
  end

  -- ---- swim into it --------------------------------------------------------
  world:setMap(MAP, approach.x, approach.y, approach.dir)
  world:applyPlayerState(FieldMoves.PLAYER_SURF)
  world.noWildEncounters = true
  U.wait(20)
  claim(FieldMoves.isSurfing(world.playerState), "on the water, on the Lapras")
  U.shot(game, out .. "/01-before.png")

  local p = world.player
  local d = DELTA[approach.dir]
  local beyond = { x = target.x + d[1], y = target.y + d[2] }
  local seen = { onWhirl = false, spun = false, busy = false, past = false }
  local shot = {}

  local function press(dir)
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    coroutine.yield()
  end

  for _ = 1, 300 do
    press(approach.dir)
    if p.cellX == target.x and p.cellY == target.y then
      seen.onWhirl = true
    end
    if p.spinFrames then seen.spun = true end
    if world:busy() then seen.busy = true end
    if p.cellX == beyond.x and p.cellY == beyond.y then seen.past = true end
    if not shot.spin and seen.onWhirl and p.spinFrames then
      shot.spin = true
      game.input.state[approach.dir] = false
      U.shot(game, out .. "/02-whirling.png")
    end
    if shot.spin and not shot.back
       and (p.cellX ~= target.x or p.cellY ~= target.y) then
      shot.back = true
      game.input.state[approach.dir] = false
      U.shot(game, out .. "/03-thrown-back.png")
    end
  end
  game.input.state[approach.dir] = false
  -- Let whatever is still running settle before reading the resting facing.
  for _ = 1, 180 do
    if not world:busy() and not p.moving then break end
    coroutine.yield()
  end
  U.shot(game, out .. "/04-settled.png")

  local BACK = { up = "down", down = "up", left = "right", right = "left" }
  claim(seen.onWhirl,
    ("the step onto the whirlpool at (%d,%d) happened -- the cart allows it")
      :format(target.x, target.y))
  claim(seen.busy, "the forced movement took the world off the d-pad")
  claim(seen.spun, "step_dig put the player under OBJECT_ACTION_SPIN")
  claim(not seen.past,
    ("300 frames of %s never reached (%d,%d) on the far side")
      :format(approach.dir:upper(), beyond.x, beyond.y))
  claim(p.cellX == approach.x and p.cellY == approach.y,
    ("the player was dragged back to (%d,%d), and is at (%d,%d)")
      :format(approach.x, approach.y, p.cellX, p.cellY))
  claim(p.facing == BACK[approach.dir],
    ("turn_head settled the facing to %s, and it is %s")
      :format(BACK[approach.dir], tostring(p.facing)))

  for _, line in ipairs(lines) do U.log(line) end
  U.log(("%d checks, %d failed"):format(#lines, fails))
  if fails > 0 then
    U.log("something above is FAIL, so do not spend time watching the replay")
  end

  -- ---- the replay, live ----------------------------------------------------
  U.log("shots are in " .. out .. "; 02 is the whirl, 03 the drag back out.")
  U.log("the replay starts in three seconds and runs on its own.")
  world:setMap(MAP, approach.x, approach.y, approach.dir)
  world:applyPlayerState(FieldMoves.PLAYER_SURF)
  world.noWildEncounters = true
  U.wait(180)
  for _ = 1, 200 do press(approach.dir) end
  game.input.state[approach.dir] = false

  U.log("the Lapras swims one cell into the whirlpool, whirls on the spot,")
  U.log("is dragged back out still whirling, and stops facing away from it.")
  U.log("a bounce with no whirl means scriptSpin never fired; a whirl that")
  U.log("never leaves the cell means $24 is still decoding as a turn.")
  U.log("the controls are yours -- the d-pad cannot cross that cell.")
  while true do coroutine.yield() end
end

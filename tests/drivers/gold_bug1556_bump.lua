-- #1556: the bump sound, which the Gen 2 port never wired.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1556_bump.lua \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1556-bump   (default)
--
-- Nothing here can be asserted by a unit test: the deliverable is the sound.
-- What the log gives a reader is the RATE, which is the half that is easy to
-- get wrong -- .BumpSound is `call CheckSFX / ret c`
-- (engine/overworld/player_movement.asm:771), a busy-channel test rather than
-- a frame counter, so a held direction re-rings only once the previous Sfx_Bump
-- has stopped.  A per-frame count means Sound.sfxBusy() is not seeing it.
--
-- Five moments, in the cart's own terms:
--   1. a wall           .CheckLandPerms carry -> .bump  (:264-265)
--   2. an NPC           .CheckNPC = 0         -> .bump  (:267-269)
--   3. a ledge hop      .TryJump's carry returns ABOVE .NotMoving (:80-81),
--                       so the hop is Sfx_JumpOverLedge and NO bump
--   4. a map connection the step is taken; silence
--   5. a map edge with no connection behind it: the border block is a wall
--
-- The run ends in the overworld so a human takes the controls where it stops.
local U = require("tests.drivers.util")

local Permissions = require("src.world.gen2.Permissions")
local Sound = require("src.core.Sound")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1556-bump"

  local heard = {}
  local realPlay = Sound.play
  Sound.play = function(data, name)
    heard[#heard + 1] = name
    return realPlay(data, name)
  end

  local function reset() heard = {} end

  -- Re-entering a map re-fires its entry script, and a held direction would
  -- feed that textbox instead of the walk.  World:busy() is the same gate the
  -- overworld's own input uses.
  local function settle()
    local calm = 0
    for _ = 1, 400 do
      if game.world:busy() then
        calm = 0
        U.tap(game, "a")
        U.wait(2)
      else
        calm = calm + 1
        if calm >= 12 then break end
        U.wait(2)
      end
    end
    U.wait(6)
  end

  local function report(label)
    local counts, order = {}, {}
    for _, name in ipairs(heard) do
      if not counts[name] then order[#order + 1] = name end
      counts[name] = (counts[name] or 0) + 1
    end
    local parts = {}
    for _, name in ipairs(order) do
      parts[#parts + 1] = ("%s x%d"):format(name, counts[name])
    end
    U.log(label, #parts > 0 and table.concat(parts, ", ") or "(silence)")
    return counts
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")

  local function walkable(map, x, y)
    return map:inBounds(x, y) and map:isWalkable(x, y)
  end

  local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                  left = { -1, 0 }, right = { 1, 0 } }

  -- A standing cell whose neighbour in `dir` is a wall.
  local function findWall(map)
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 1 do
        if walkable(map, x, y) then
          for dir, d in pairs(DELTA) do
            local nx, ny = x + d[1], y + d[2]
            if map:inBounds(nx, ny) and not map:isWalkable(nx, ny) then
              return x, y, dir
            end
          end
        end
      end
    end
  end

  -- ---- 1. a wall -----------------------------------------------------------
  assert(w:setMap("NEW_BARK_TOWN", 5, 5, "down"), "setMap NEW_BARK_TOWN")
  U.wait(5)
  local wx, wy, wdir = findWall(w.map)
  if wx then
    assert(w:setMap("NEW_BARK_TOWN", wx, wy, wdir))
    U.wait(8)
    settle()
    reset()
    U.hold(game, wdir, 90)
    U.wait(5)
    local counts = report("01 wall (" .. wdir .. ", 90 frames held):")
    U.log("   Sfx_Bump over 90 held frames:", counts.Sfx_Bump or 0,
          "-- a per-frame count here means the CheckSFX gate is not working")
    U.shot(game, out .. "/01-wall.png")
  else
    U.log("SKIP 01 wall -- no wall cell found in NEW_BARK_TOWN")
  end

  -- ---- 2. an NPC -----------------------------------------------------------
  local npc, npcDir
  for _, e in ipairs(w.entities or {}) do
    if e ~= w.player and e.cellX and not e.bigObject then
      for dir, d in pairs(DELTA) do
        local sx, sy = e.cellX - d[1], e.cellY - d[2]
        if walkable(w.map, sx, sy) then npc, npcDir = { sx, sy }, dir break end
      end
    end
    if npc then break end
  end
  if npc then
    assert(w:setMap("NEW_BARK_TOWN", npc[1], npc[2], npcDir))
    U.wait(8)
    settle()
    reset()
    U.hold(game, npcDir, 45)
    U.wait(5)
    report("02 NPC (" .. npcDir .. "):")
    U.shot(game, out .. "/02-npc.png")
  else
    U.log("SKIP 02 NPC -- no reachable NPC in NEW_BARK_TOWN")
  end

  -- ---- 3. a ledge ----------------------------------------------------------
  local ROUTES = { "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_32",
                   "ROUTE_33", "ROUTE_34", "ROUTE_35", "ROUTE_36" }
  local hopped = false
  for _, mapId in ipairs(ROUTES) do
    if w:setMap(mapId, 5, 5, "down") then
      U.wait(5)
      local map = w.map
      for y = 0, map.heightCells - 1 do
        for x = 0, map.widthCells - 1 do
          local facings = Permissions.ledgeFacings(map:cellCollision(x, y))
          if facings then
            for dir, on in pairs(facings) do
              local d = on and DELTA[dir]
              if d and walkable(map, x + d[1] * 2, y + d[2] * 2) then
                assert(w:setMap(mapId, x, y, dir))
                U.wait(8)
                settle()
                reset()
                U.hold(game, dir, 40)
                U.wait(20)
                local counts = report(
                  ("03 ledge hop (%s %s):"):format(mapId, dir))
                U.log("   want Sfx_JumpOverLedge and NO Sfx_Bump; bumps:",
                      counts.Sfx_Bump or 0)
                U.shot(game, out .. "/03-ledge.png")
                hopped = true
                break
              end
            end
          end
          if hopped then break end
        end
        if hopped then break end
      end
    end
    if hopped then break end
  end
  if not hopped then U.log("SKIP 03 ledge -- no hoppable ledge found") end

  -- ---- 4 and 5. map edges --------------------------------------------------
  assert(w:setMap("NEW_BARK_TOWN", 5, 5, "down"), "setMap NEW_BARK_TOWN")
  U.wait(5)
  local DIR_CONN = { up = "north", down = "south", left = "west",
                     right = "east" }
  local map = w.map
  local function edgeCell(dir)
    local d = DELTA[dir]
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 1 do
        if walkable(map, x, y)
           and not map:inBounds(x + d[1], y + d[2]) then
          return x, y
        end
      end
    end
  end
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    local conn = map:connection(DIR_CONN[dir])
    local ex, ey = edgeCell(dir)
    if ex then
      assert(w:setMap("NEW_BARK_TOWN", ex, ey, dir))
      U.wait(8)
      settle()
      reset()
      U.hold(game, dir, 40)
      U.wait(20)
      local counts = report(("%s edge %s (connection: %s):")
        :format(conn and "04" or "05", dir,
                tostring(conn and conn.mapId or "none")))
      U.log("   want", conn and "silence" or "Sfx_Bump", "-- bumps:",
            counts.Sfx_Bump or 0)
      U.shot(game, out .. ("/0%s-edge-%s.png"):format(conn and "4" or "5", dir))
      assert(w:setMap("NEW_BARK_TOWN", ex, ey, dir))
      U.wait(5)
    end
  end

  Sound.play = realPlay
  assert(w:setMap("NEW_BARK_TOWN", 5, 5, "down"))
  U.log("done -- the controls are yours; walk into anything")
end

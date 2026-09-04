-- engine/overworld/events.asm:494-510
-- engine/overworld/player_movement.asm:807-816
local U = require("tests.drivers.util")

local Permissions = require("src.world.gen2.Permissions")

return function(game)
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR")
    or "/tmp/talk-bump-2170"
  local fails = 0
  local function say(line) print("[2170] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen2 world did not boot")
    love.event.quit(1)
    return
  end

  world:warpToMapId("CHERRYGROVE_CITY", 20, 10, "down")
  U.wait(45)

  local DELTA = {
    left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 },
  }
  local sx, sy, dir
  for _, npc in ipairs(world.npcs or {}) do
    for d, v in pairs(DELTA) do
      local cx, cy = npc.cellX - v[1], npc.cellY - v[2]
      if Permissions.isWalkable(world.map:cellCollision(cx, cy)) then
        sx, sy, dir = cx, cy, d
        break
      end
    end
    if sx then break end
  end
  if not sx then
    say("FAIL no reachable NPC on this map")
    love.event.quit(1)
    return
  end

  world:warpToMapId("CHERRYGROVE_CITY", sx, sy, dir)
  U.wait(45)
  local p = world.player
  say("bumping " .. dir .. " into an NPC from " .. sx .. "," .. sy)

  local sawWalk = false
  for _ = 1, 40 do
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    coroutine.yield()
    if p:walkPhase() == 1 then sawWalk = true end
  end
  ok(not p.moving, "the NPC never let the step start")
  ok(sawWalk, "the walk-in-place cycle was running before the talk")

  table.insert(game.input.pressQueue, dir)
  game.input.state[dir] = true
  U.tap(game, "a")
  U.wait(2)
  game.input.state[dir] = false

  ok(world:busy(), "the A press started the conversation")
  ok(p:walkPhase() == 0, "the talk snapped the player to the standing frame")
  ok((p.bumpFrames or 0) == 0, "with the queued bump cancelled")
  U.shot(game, DIR .. "/2170-talking.png")

  local stayed = true
  for _ = 1, 60 do
    coroutine.yield()
    if world:busy() and p:walkPhase() ~= 0 then stayed = false end
  end
  ok(stayed, "and it stays standing for the whole box")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end

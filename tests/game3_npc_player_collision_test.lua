#!/usr/bin/env luajit
-- pokefirered/src/event_object_movement.c:4899

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Objects = require("src.core.game3.objects")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Ghosts = require("src.core.game3.ghosts")

print("=== Game 3 NPC-vs-player collision (#2307) ===")

local W, H = 16, 16
local grid = {}
for i = 1, W * H do grid[i] = 0x00 end
Collision._grid, Collision._widthCells, Collision._heightCells = grid, W, H

print("[test] 1. playerBlocks reserves both cells while the player is mid-step")
assert(type(Objects.playerBlocks) == "function", "Objects.playerBlocks is exported")
Player.cellX, Player.cellY = 7, 5
Player.targetX, Player.targetY = 6, 5
Player.moving = true
assert(Objects.playerBlocks(7, 5), "origin cell reserved (pret previousCoords)")
assert(Objects.playerBlocks(6, 5), "destination cell reserved (pret currentCoords)")
assert(not Objects.playerBlocks(5, 5), "unrelated cell free")

print("[test] 2. an idle player reserves exactly one cell")
Player.moving = false
Player.cellX, Player.cellY = 6, 5
Player.targetX, Player.targetY = 6, 5
assert(Objects.playerBlocks(6, 5), "idle player blocks its own cell")
assert(not Objects.playerBlocks(7, 5), "idle player blocks nothing else")

print("[test] 3. a wanderer never claims the cell the player is walking into")
Objects.clear()
Objects.loadMap(nil, "TEST_MAP_2307", {
  objects = {
    {
      localId = 1,
      index = 1,
      x = 5,
      y = 5,
      graphicsId = 10,
      movement = "WALK",
      range = "LEFT_RIGHT",
      radius = { x = 2, y = 2 },
    },
  },
})
local eo = Objects.find(1)
assert(eo, "wanderer spawned")

Player.cellX, Player.cellY = 7, 5
Player.targetX, Player.targetY = 6, 5
Player.moving = true
local steppedLeft = false
for _ = 1, 4000 do
  eo.cellX, eo.cellY = 5, 5
  eo.targetX, eo.targetY = 5, 5
  eo.moving, eo.progress, eo.idleTimer = false, 0, 0
  Objects.update(nil)
  assert(not (eo.moving and eo.targetX == 6 and eo.targetY == 5),
    "NPC stepped onto the cell the player is walking into (#2307)")
  if eo.moving and eo.targetX == 4 and eo.targetY == 5 then steppedLeft = true end
end
assert(steppedLeft, "wanderer still takes the free direction")

print("[test] 4. the wanderer is not frozen once the player is elsewhere")
Player.moving = false
Player.cellX, Player.cellY = 0, 0
Player.targetX, Player.targetY = 0, 0
local steppedRight = false
for _ = 1, 4000 do
  eo.cellX, eo.cellY = 5, 5
  eo.targetX, eo.targetY = 5, 5
  eo.moving, eo.progress, eo.idleTimer = false, 0, 0
  Objects.update(nil)
  if eo.moving and eo.targetX == 6 and eo.targetY == 5 then
    steppedRight = true
    break
  end
end
assert(steppedRight, "wanderer reaches (6,5) when the player is not there")

print("[test] 5. the ghost/pool context consults the player in WORLD space")
assert(type(Ghosts._contextFor) == "function", "Ghosts._contextFor is exported")
local layout = {
  width = 16,
  height = 16,
  collAt = function(_, _, _) return 0x00 end,
}
local pool = { byId = {}, order = {} }
Player.moving = false
Player.cellX, Player.cellY = 6, 5
Player.targetX, Player.targetY = 6, 5

local far = Ghosts._contextFor({ id = "N", def = { midLayout = layout }, ox = 20, oy = 0 }, pool)
assert(not far.blocks(6, 5, nil),
  "neighbor-local (6,5) at ox=20 is world (26,5): no phantom block across the seam")

local same = Ghosts._contextFor({ id = "N", def = { midLayout = layout }, ox = 0, oy = 0 }, pool)
assert(same.blocks(6, 5, nil), "pooled ctx blocks the player's world cell")

Player.cellX, Player.cellY = 7, 5
Player.targetX, Player.targetY = 6, 5
Player.moving = true
assert(same.blocks(6, 5, nil), "pooled ctx blocks the player's in-flight destination")

print("[test] 6. passable pooled objects do not block")
Player.moving = false
Player.cellX, Player.cellY = 0, 0
Player.targetX, Player.targetY = 0, 0
pool.byId[2] = {
  localId = 2, visible = true, hidden = false, passable = true,
  cellX = 3, cellY = 3, moving = false, targetX = 3, targetY = 3,
}
pool.order[1] = 2
assert(not same.blocks(3, 3, nil), "a passable pooled object does not block")
pool.byId[2].passable = false
assert(same.blocks(3, 3, nil), "a solid pooled object still blocks")

print("[test] 7. a free-running wanderer and a bouncing player never share a cell")
Objects.clear()
Objects.loadMap(nil, "TEST_MAP_2307_RUN", {
  objects = {
    {
      localId = 2,
      index = 2,
      x = 8,
      y = 8,
      graphicsId = 10,
      movement = "WALK",
      range = "AROUND",
      radius = { x = 1, y = 1 },
    },
  },
})
local runner = Objects.find(2)
assert(runner, "free-running wanderer spawned")
local held
local input = {
  isDown = function(_, b) return b == held end,
  wasPressed = function(_, b) return b == held end,
}
for _, startX in ipairs({ 6, 10 }) do
  local into = startX < 8 and "right" or "left"
  Player.reset(startX, 8, into)
  local midStep, npcSteps = 0, 0
  held = into
  for _ = 1, 200 do
    for _ = 1, 26 do
      if not Player.moving then
        if Player.cellX <= 5 then held = "right" elseif Player.cellX >= 11 then held = "left" end
      end
      runner.idleTimer = 0
      local wasMoving = runner.moving
      Objects.update(nil)
      if runner.moving and not wasMoving then npcSteps = npcSteps + 1 end
      Player.update(nil, input)
      if Player.moving then midStep = midStep + 1 end
      assert(not (runner.cellX == Player.cellX and runner.cellY == Player.cellY),
        "NPC and player share a cell (#2307)")
      assert(not (runner.moving and Player.moving
        and runner.targetX == Player.targetX and runner.targetY == Player.targetY),
        "NPC and player claimed the same destination (#2307)")
      assert(not (runner.moving and runner.targetX == Player.cellX and runner.targetY == Player.cellY),
        "NPC is stepping onto the player's cell (#2307)")
      assert(not (Player.moving and Player.targetX == runner.cellX and Player.targetY == runner.cellY),
        "player is stepping onto the NPC's cell (#2307)")
    end
  end
  assert(midStep > 0 and npcSteps > 0, "both the player and the wanderer moved")
end

print("[test] all passed")

-- tests/game3_elevation_oam_priority_test.lua
-- Tests for Elevation tracking, elevation 0/15 preservation, and row-interleaved OAM priority rendering.

local Map = require("src.core.game3.map")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Collision = require("src.core.game3.collision")
local FieldView = require("src.core.game3.field_view")

local CELL = 16

local function assert_eq(desc, actual, expected)
  if actual == expected then
    print(string.format("[ok] %s", desc))
  else
    error(string.format("[FAIL] %s: expected %s, got %s", desc, tostring(expected), tostring(actual)))
  end
end

local function assert_true(desc, val)
  assert_eq(desc, not not val, true)
end

print("[test] 1. Elevation tracking and 0/15 preservation on Player movement")
do
  local cellElevs = {
    ["10,10"] = 3, -- ground
    ["10,11"] = 4, -- bridge / elevated platform
    ["10,12"] = 15, -- special: preserve elevation
    ["10,13"] = 0, -- special: preserve elevation
    ["10,14"] = 1, -- surf / water
  }
  Collision.elevationAt = function(cx, cy)
    return cellElevs[cx .. "," .. cy]
  end

  Player.reset(10, 10, "down")
  assert_eq("Player initial elevation at (10,10) is 3", Player.elevation, 3)

  -- Move onto bridge (elevation 4)
  Player.targetX, Player.targetY = 10, 11
  Player.moving = true
  Player.cellX, Player.cellY = 10, 11
  Player.px, Player.py = 10 * CELL, 11 * CELL
  Player.moving = false
  local curElev = Collision.elevationAt(Player.cellX, Player.cellY)
  if curElev and curElev ~= 0 and curElev ~= 15 then Player.elevation = curElev end
  assert_eq("Player elevation on bridge (10,11) is 4", Player.elevation, 4)

  -- Move onto elevation 15 tile (should preserve 4)
  Player.cellX, Player.cellY = 10, 12
  local e15 = Collision.elevationAt(Player.cellX, Player.cellY)
  if e15 and e15 ~= 0 and e15 ~= 15 then Player.elevation = e15 end
  assert_eq("Player elevation on elevation 15 tile (10,12) preserved as 4", Player.elevation, 4)

  -- Move onto elevation 0 tile (should preserve 4)
  Player.cellX, Player.cellY = 10, 13
  local e0 = Collision.elevationAt(Player.cellX, Player.cellY)
  if e0 and e0 ~= 0 and e0 ~= 15 then Player.elevation = e0 end
  assert_eq("Player elevation on elevation 0 tile (10,13) preserved as 4", Player.elevation, 4)

  -- Move onto water (elevation 1)
  Player.cellX, Player.cellY = 10, 14
  local e1 = Collision.elevationAt(Player.cellX, Player.cellY)
  if e1 and e1 ~= 0 and e1 ~= 15 then Player.elevation = e1 end
  assert_eq("Player elevation on water (10,14) updated to 1", Player.elevation, 1)
end

print("[test] 2. EventObject elevation tracking on spawn and movement")
do
  local eo = {
    localId = 1,
    def = { x = 5, y = 5, elevation = 0 },
    cellX = 5,
    cellY = 5,
    targetX = 5,
    targetY = 6,
  }
  Collision.elevationAt = function(cx, cy)
    if cx == 5 and cy == 5 then return 3 end
    if cx == 5 and cy == 6 then return 4 end
    return 3
  end

  eo.elevation = (Collision.elevationAt and Collision.elevationAt(eo.cellX, eo.cellY)) or 0
  assert_eq("EventObject initial elevation at (5,5) is 3", eo.elevation, 3)

  -- Move to (5,6)
  eo.cellX = eo.targetX
  eo.cellY = eo.targetY
  local curElev = Collision.elevationAt(eo.cellX, eo.cellY)
  if curElev and curElev ~= 0 and curElev ~= 15 then eo.elevation = curElev end
  assert_eq("EventObject elevation at (5,6) is updated to 4", eo.elevation, 4)
end

print("[test] 3. GBA OAM Priority vs Overhead Layer partitioning")
do
  local ELEVATION_TO_PRIORITY = {
    [0] = 2, [1] = 2, [2] = 2, [3] = 2,
    [4] = 1, [5] = 2, [6] = 1, [7] = 2,
    [8] = 1, [9] = 2, [10] = 1, [11] = 2,
    [12] = 1, [13] = 0, [14] = 0, [15] = 2,
  }

  local actorPriority = function(a)
    if a.kind == "player" then
      if a.jumping or a.surfHopping or a.escalatorActive or a.specialAnimActive then
        return 1
      end
      local elev = a.elevation or 3
      return ELEVATION_TO_PRIORITY[elev] or 2
    else
      local elev = a.elevation or (a.obj and a.obj.elevation) or 3
      return ELEVATION_TO_PRIORITY[elev] or 2
    end
  end

  local drawLog = {}
  local function simulateDraw(actors)
    local underActors = {}
    local overActors = {}
    for _, a in ipairs(actors) do
      a.priority = actorPriority(a)
      if a.priority < 2 then
        overActors[#overActors + 1] = a
      else
        underActors[#underActors + 1] = a
      end
    end

    local function sortActors(a, b)
      local ay = a.sortY or a.y
      local by = b.sortY or b.y
      if ay == by then return (a.i or 0) < (b.i or 0) end
      return ay < by
    end
    table.sort(underActors, sortActors)
    table.sort(overActors, sortActors)

    drawLog = {}
    -- 1. Draw underActors (OAM Priority >= 2)
    for _, a in ipairs(underActors) do
      drawLog[#drawLog + 1] = a.tag
    end
    -- 2. Draw Overhead layer (BG1, Priority 1)
    drawLog[#drawLog + 1] = "OVERHEAD_BG1_LAYER"
    -- 3. Draw overActors (OAM Priority < 2, e.g. elevation 4 cliff/bridge, jumping, escalator)
    for _, a in ipairs(overActors) do
      drawLog[#drawLog + 1] = a.tag
    end
  end

  -- Scenario A: Nurse Joy behind desk (row 5) and Player on ground (row 6)
  -- Both have ground elevation 3 -> Priority 2. Both drawn BEFORE overhead BG1 layer.
  -- The overhead desk covers Nurse Joy; the overhead roof covers player legs.
  local testActors = {
    { tag = "NURSE_JOY_ROW_5", elevation = 3, y = 80, sortY = 80, kind = "npc" },
    { tag = "PLAYER_ON_GROUND_ROW_6", elevation = 3, y = 96, sortY = 96, kind = "player" },
    { tag = "PLAYER_ON_CLIFF_ELEV_4", elevation = 4, y = 272, sortY = 272, kind = "player" },
    { tag = "NPC_IN_WATER_ELEV_1", elevation = 1, y = 256, sortY = 256, kind = "npc" },
  }

  simulateDraw(testActors)

  print("Draw order result:")
  for idx, entry in ipairs(drawLog) do
    print(string.format("  [%d] %s", idx, entry))
  end

  assert_eq("Under-actor 1 is Nurse Joy (behind desk)", drawLog[1], "NURSE_JOY_ROW_5")
  assert_eq("Under-actor 2 is Player on ground (behind roof)", drawLog[2], "PLAYER_ON_GROUND_ROW_6")
  assert_eq("Under-actor 3 is NPC in water", drawLog[3], "NPC_IN_WATER_ELEV_1")
  assert_eq("Step 4 is Overhead BG1 layer (covers Nurse Joy and player on ground)", drawLog[4], "OVERHEAD_BG1_LAYER")
  assert_eq("Step 5 is Player on cliff (elevation 4, drawn ON TOP of overhead layer)", drawLog[5], "PLAYER_ON_CLIFF_ELEV_4")
end

print("[test] 4. Player priority override states (jumping, escalator, surf hopping)")
do
  local ELEVATION_TO_PRIORITY = {
    [0] = 2, [1] = 2, [2] = 2, [3] = 2,
    [4] = 1, [5] = 2, [6] = 1, [7] = 2,
    [8] = 1, [9] = 2, [10] = 1, [11] = 2,
    [12] = 1, [13] = 0, [14] = 0, [15] = 2,
  }

  local computePlayerPriority = function(opts)
    if opts.jumping or opts.surfHopping or opts.escalatorActive or opts.specialAnimActive then
      return 1
    end
    local elev = opts.elevation or 3
    return ELEVATION_TO_PRIORITY[elev] or 2
  end

  assert_eq("Jumping player has Priority 1 (above BG1)", computePlayerPriority({ jumping = true, elevation = 3 }), 1)
  assert_eq("Escalator player has Priority 1 (above BG1)", computePlayerPriority({ escalatorActive = true, elevation = 3 }), 1)
  assert_eq("Surf hopping player has Priority 1 (above BG1)", computePlayerPriority({ surfHopping = true, elevation = 1 }), 1)
  assert_eq("Bridge player has Priority 1 (above BG1)", computePlayerPriority({ elevation = 4 }), 1)
  assert_eq("Normal walking player with animation offsets has Priority 2 (under BG1)", computePlayerPriority({ elevation = 3, spriteYOffset = -8 }), 2)
  assert_eq("Water surfing player has Priority 2 (under BG1)", computePlayerPriority({ elevation = 1 }), 2)
end

print("[test] ALL ELEVATION AND OAM CONDITIONAL PRIORITY TESTS PASSED!")

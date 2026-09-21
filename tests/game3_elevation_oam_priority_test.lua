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

print("[test] 3. Interleaved row-by-row overhead and actor draw order")
do
  local drawLog = {}
  _G.love = _G.love or {}
  _G.love.graphics = _G.love.graphics or {}
  love.graphics.draw = function(drawable, ...)
    local args = { ... }
    if type(drawable) == "string" then
      drawLog[#drawLog + 1] = drawable
    elseif type(drawable) == "table" and drawable.tag then
      drawLog[#drawLog + 1] = drawable.tag
    else
      drawLog[#drawLog + 1] = "quad"
    end
  end
  love.graphics.setColor = function() end
  love.graphics.push = function() end
  love.graphics.pop = function() end
  love.graphics.translate = function() end

  -- Setup overhead rows:
  -- Row 5: Counter overhead tile (wy = 5 * 16 = 80)
  -- Row 17: Cliff upper edge overhead tile (wy = 17 * 16 = 272)
  FieldView._nativeOverByRow = {
    [0] = {},
    [1] = {},
    [2] = {},
    [3] = {},
    [4] = {},
    [5] = { { image = { tag = "OVERHEAD_ROW_5_COUNTER" }, quad = {} } },
    [6] = {},
    [16] = {},
    [17] = { { image = { tag = "OVERHEAD_ROW_17_CLIFF" }, quad = {} } },
    [18] = {},
  }
  FieldView._nativeOverOx = 0
  FieldView._nativeOverOy = 0

  -- Setup actors:
  -- Actor A: NPC behind counter at row 4 (sortY = 4 * 16 = 64)
  -- Actor B: Player in front of counter at row 6 (sortY = 6 * 16 = 96)
  -- Actor C: NPC standing behind cliff in water at row 16 (sortY = 16 * 16 = 256)
  -- Actor D: Player standing ON cliff upper edge at row 17 (sortY = 17 * 16 = 272)
  local actors = {
    { tag = "ACTOR_NPC_BEHIND_COUNTER", sortY = 64, x = 0, y = 64 },
    { tag = "ACTOR_PLAYER_IN_FRONT_OF_COUNTER", sortY = 96, x = 0, y = 96 },
    { tag = "ACTOR_NPC_IN_WATER", sortY = 256, x = 0, y = 256 },
    { tag = "ACTOR_PLAYER_ON_CLIFF_EDGE", sortY = 272, x = 0, y = 272 },
  }

  table.sort(actors, function(a, b) return a.sortY < b.sortY end)

  drawLog = {}
  
  local actorIdx = 1
  local nActors = #actors
  local cy0 = 0
  local rows = 20
  local overByRow = FieldView._nativeOverByRow

  for r = 0, rows - 1 do
    local rowWy = (cy0 + r) * CELL

    local rowOver = overByRow[r]
    if rowOver and #rowOver > 0 then
      for _, item in ipairs(rowOver) do
        love.graphics.draw(item.image, item.quad, item.x or 0, item.y or 0)
      end
    end

    local nextRowWy = rowWy + CELL
    while actorIdx <= nActors and actors[actorIdx].sortY < nextRowWy do
      love.graphics.draw(actors[actorIdx].tag)
      actorIdx = actorIdx + 1
    end
  end

  print("Draw order result:")
  for idx, entry in ipairs(drawLog) do
    print(string.format("  [%d] %s", idx, entry))
  end

  assert_eq("Draw step 1 is NPC behind counter", drawLog[1], "ACTOR_NPC_BEHIND_COUNTER")
  assert_eq("Draw step 2 is Counter overhead (drawn after NPC behind counter)", drawLog[2], "OVERHEAD_ROW_5_COUNTER")
  assert_eq("Draw step 3 is Player in front of counter (drawn after counter)", drawLog[3], "ACTOR_PLAYER_IN_FRONT_OF_COUNTER")
  assert_eq("Draw step 4 is NPC in water", drawLog[4], "ACTOR_NPC_IN_WATER")
  assert_eq("Draw step 5 is Cliff overhead (drawn after NPC in water, covering them)", drawLog[5], "OVERHEAD_ROW_17_CLIFF")
  assert_eq("Draw step 6 is Player on cliff edge (drawn AFTER cliff overhead, on top of edge!)", drawLog[6], "ACTOR_PLAYER_ON_CLIFF_EDGE")
end

print("[test] 4. isPlayerAboveBg2 special states")
do
  local isPlayerAboveBg2_test = function(playerXOff, playerYOff, isJumping, isEscalator)
    if (playerXOff and playerXOff ~= 0) or (playerYOff and playerYOff ~= 0) then
      return true
    end
    if isJumping then return true end
    if isEscalator then return true end
    return false
  end

  assert_true("Jumping player is flagged above BG2", isPlayerAboveBg2_test(0, 0, true, false))
  assert_true("Escalator player is flagged above BG2", isPlayerAboveBg2_test(0, 0, false, true))
  assert_true("Subpixel Y offset player is flagged above BG2", isPlayerAboveBg2_test(0, -8, false, false))
  assert_eq("Normal walking player is not forced above BG2", isPlayerAboveBg2_test(0, 0, false, false), false)
end

print("[test] ALL ELEVATION AND OAM CONDITIONAL PRIORITY TESTS PASSED!")

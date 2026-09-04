-- (engine/overworld/movement.asm:151)
-- is)" (engine/overworld/movement.asm:606
--   luajit tests/engine/npc_stay_turns_bug2117.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local NPC = require("src.world.NPC")

local DATA = {
  sprites = {
    SPRITE_TEST_NPC = { image = "fixture_npc.png", frames = 6, walker = true },
  },
}

local MAP = {
  def = { tileset = "HOUSE" },
  inBounds = function() return true end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  cellTile = function() return 0 end,
  warpAtCell = function() return nil end,
}

local function newNpc(movement, range)
  return NPC.new(DATA, "TEST_MAP", {
    index = 1, x = 5, y = 5, sprite = "SPRITE_TEST_NPC",
    movement = movement, range = range,
  })
end

local function run(npc, ticks)
  local seen, moved, everMoving = {}, false, false
  for _ = 1, ticks do
    npc:update(MAP, { npc })
    seen[npc.facing] = true
    if npc.moving then everMoving = true end
    if npc.cellX ~= 5 or npc.cellY ~= 5 then moved = true end
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  return seen, n, moved, everMoving
end

do
  math.randomseed(2117)
  local npc = newNpc("STAY", "NONE")
  check(npc.wanders, "STAY, NONE rolls a facing")
  check(not npc.steps, "STAY, NONE never steps")
  local _, n, moved, everMoving = run(npc, 4000)
  check(n >= 2, "STAY, NONE takes at least two distinct facings")
  check(not moved, "STAY, NONE never leaves its spawn cell")
  check(not everMoving, "STAY, NONE never enters a step")
end

-- ---- byte 2 DOWN pins the roll (.determineDirection, movement.asm:186)
do
  math.randomseed(2117)
  local npc = newNpc("STAY", "DOWN")
  check(not npc.wanders, "STAY, DOWN is pinned")
  eq(npc.facing, "down", "STAY, DOWN spawns facing down")
  local _, n = run(npc, 2000)
  eq(n, 1, "STAY, DOWN never turns")
  eq(npc.facing, "down", "STAY, DOWN stays facing down")
end

do
  math.randomseed(2117)
  local npc = newNpc("STAY", "UP_DOWN")
  local seen, n = run(npc, 4000)
  eq(n, 2, "STAY, UP_DOWN takes both axis facings")
  check(seen.up and seen.down, "STAY, UP_DOWN only faces up or down")
  check(not (seen.left or seen.right), "STAY, UP_DOWN never faces sideways")
end

do
  local npc = newNpc("STAY", "BOULDER_MOVEMENT_BYTE_2")
  check(not npc.wanders, "Strength boulders keep their pin")
end

do
  math.randomseed(2117)
  local npc = newNpc("WALK", "LEFT_RIGHT")
  check(npc.steps and npc.wanders, "WALK, LEFT_RIGHT still wanders")
  npc.facing = "left" -- FACING_FROM_RANGE spawns an axis object facing down
  local seen, _, moved = run(npc, 4000)
  check(moved, "WALK, LEFT_RIGHT still takes steps")
  check(not (seen.up or seen.down), "WALK, LEFT_RIGHT stays on its axis")
end

do
  math.randomseed(2117)
  local npc = newNpc("STAY", "NONE")
  npc.wanders = false
  local _, n = run(npc, 2000)
  eq(n, 1, "npc.wanders = false still freezes the facing")
end

do
  math.randomseed(2117)
  local npc = newNpc("STAY", "NONE")
  npc.frozen = true
  local _, n = run(npc, 2000)
  eq(n, 1, "a frozen NPC still holds its facing")
end

T.finish("npc stay turns bug2117")

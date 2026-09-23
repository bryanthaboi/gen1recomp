-- Tests for Renewable Hidden Items system (Treasure Beach, Berry Forest, etc.)

local Renewable = require("src.core.game3.renewable_hidden_items")
local Flags = require("src.core.game3.scripting.flags")
local FlagsTable = require("src.core.game3.scripting.flags_table")

local tests = {}

function tests.test_exclusion_zone_and_step_counter()
  local ctx = { vars = {}, flags = {} }

  -- Step in normal map (e.g. Pallet Town, group 3, map 0) -> increments counter
  Renewable.onStep(ctx, 3, 0, "PALLET_TOWN")
  assert(Flags.getVar(ctx, nil, 0x4023) == 1, "Counter should be 1 after 1 step in non-renewable map")

  Renewable.onStep(ctx, 3, 0, "PALLET_TOWN")
  assert(Flags.getVar(ctx, nil, 0x4023) == 2, "Counter should be 2 after 2 steps in non-renewable map")

  -- Step inside Treasure Beach (Group 3, Map 46) -> MUST NOT increment counter (Exclusion zone)
  Renewable.onStep(ctx, 3, 46, "SEVII_ONE_ISLAND_TREASURE_BEACH")
  assert(Flags.getVar(ctx, nil, 0x4023) == 2, "Counter must NOT increment while walking inside Treasure Beach")

  -- Step inside Berry Forest (Group 1, Map 109) -> MUST NOT increment counter
  Renewable.onStep(ctx, 1, 109, "SEVII_THREE_ISLAND_BERRY_FOREST")
  assert(Flags.getVar(ctx, nil, 0x4023) == 2, "Counter must NOT increment while walking inside Berry Forest")
end

function tests.test_regeneration_on_map_enter()
  local ctx = { vars = {}, flags = {} }

  -- Set step counter to 1499 (< 1500)
  Flags.setVar(ctx, nil, 0x4023, 1499)

  -- Enter Treasure Beach -> should NOT regenerate yet
  local regenerated = Renewable.tryRegenerate(ctx, 3, 46, "SEVII_ONE_ISLAND_TREASURE_BEACH")
  assert(not regenerated, "Should not regenerate under 1500 steps")
  assert(Flags.getVar(ctx, nil, 0x4023) == 1499, "Counter should stay 1499")

  -- Accumulate to 1500
  Flags.setVar(ctx, nil, 0x4023, 1500)

  -- Enter a non-renewable map -> should NOT regenerate
  local nonRen = Renewable.tryRegenerate(ctx, 3, 0, "PALLET_TOWN")
  assert(not nonRen, "Non-renewable map should not trigger regeneration")
  assert(Flags.getVar(ctx, nil, 0x4023) == 1500, "Counter should remain 1500 when entering non-renewable map")

  -- Test RNG roll for Rare tier (roll = 95 >= 90)
  regenerated = Renewable.tryRegenerate(ctx, 3, 46, "SEVII_ONE_ISLAND_TREASURE_BEACH", function() return 95 end)
  assert(regenerated, "Entering Treasure Beach with >= 1500 steps should trigger regeneration")
  assert(Flags.getVar(ctx, nil, 0x4023) == 0, "Step counter should reset to 0 after regeneration")

  -- In Treasure Beach rare tier: Ultra Ball, Star Piece, Big Pearl should be cleared (spawned)
  local starPieceFlag = Flags.IDS.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_STAR_PIECE
  local bigPearlFlag = Flags.IDS.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_BIG_PEARL
  assert(Flags.getFlag(ctx, nil, starPieceFlag) == false, "Rare Star Piece should be spawned (flag false)")
  assert(Flags.getFlag(ctx, nil, bigPearlFlag) == false, "Rare Big Pearl should be spawned (flag false)")

  -- Test RNG roll for Common tier (roll = 30 < 60)
  Flags.setVar(ctx, nil, 0x4023, 1500)
  Renewable.tryRegenerate(ctx, 3, 46, "SEVII_ONE_ISLAND_TREASURE_BEACH", function() return 30 end)
  -- Rare items should now be reset to hidden/collected (flag true)
  assert(Flags.getFlag(ctx, nil, starPieceFlag) == true, "Star piece should be hidden in common roll (flag true)")
  assert(Flags.getFlag(ctx, nil, bigPearlFlag) == true, "Big pearl should be hidden in common roll (flag true)")
  -- Common ultra ball should be spawned (flag false)
  local ultraBallFlag = Flags.IDS.FLAG_HIDDEN_ITEM_ONE_ISLAND_TREASURE_BEACH_ULTRA_BALL
  assert(Flags.getFlag(ctx, nil, ultraBallFlag) == false, "Common Ultra Ball should be spawned (flag false)")
end

return tests

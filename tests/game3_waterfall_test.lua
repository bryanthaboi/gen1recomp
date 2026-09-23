#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local FieldMoves = require("src.core.game3.field_moves")
local Collision = require("src.core.game3.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")

print("[test] 1. FLAG_SYS_* ids match pokefirered include/constants/flags.h")
eq(FieldMoves.SYS_FLAGS.USE_STRENGTH, 0x805, "FLAG_SYS_USE_STRENGTH is SYS_FLAGS + 0x5")
eq(FieldMoves.SYS_FLAGS.FLASH_ACTIVE, 0x806, "FLAG_SYS_FLASH_ACTIVE is SYS_FLAGS + 0x6")
eq(FieldMoves.SYS_FLAGS.WHITE_FLUTE_ACTIVE, 0x803, "FLAG_SYS_WHITE_FLUTE_ACTIVE is SYS_FLAGS + 0x3")
eq(FieldMoves.SYS_FLAGS.BLACK_FLUTE_ACTIVE, 0x804, "FLAG_SYS_BLACK_FLUTE_ACTIVE is SYS_FLAGS + 0x4")
check(FieldMoves.SYS_FLAGS.USE_STRENGTH ~= 0x804,
  "Strength does not write FLAG_SYS_BLACK_FLUTE_ACTIVE")
check(FieldMoves.SYS_FLAGS.FLASH_ACTIVE ~= 0x803,
  "Flash does not write FLAG_SYS_WHITE_FLUTE_ACTIVE")
local Encounters = require("src.core.game3.encounters")
check(Encounters ~= nil, "encounters module loads")
for _, id in ipairs({ 0x803, 0x804 }) do
  check(FieldMoves.SYS_FLAGS.USE_STRENGTH ~= id and FieldMoves.SYS_FLAGS.FLASH_ACTIVE ~= id,
    string.format("no field move collides with the flute flag %#x", id))
end

print("[test] 2. MetatileBehavior_IsWaterfall is MB_WATERFALL only")
check(type(FieldMoves.isWaterfallBehavior) == "function", "FieldMoves.isWaterfallBehavior exists")
local function isFall(beh)
  if type(FieldMoves.isWaterfallBehavior) ~= "function" then return nil end
  return FieldMoves.isWaterfallBehavior(beh)
end
check(isFall(0x13) == true, "MB_WATERFALL 0x13 is a waterfall")
check(isFall(0x21) == false, "MB_SAND 0x21 is not a waterfall")
check(isFall(0x10) == false, "MB_POND_WATER 0x10 is not a waterfall")
check(isFall(nil) == false, "an unknown behavior is not a waterfall")
check(FieldMoves.BEHAVIORS.DEEP_WATER[0x12] == true, "MB_DEEP_WATER is 0x12")

print("[test] 3. EventScript_Waterfall / EventScript_CantUseWaterfall gating")
local mon = { species = 130, moves = { 127 }, nickname = "GYARADOS" }
local function ctx(over)
  local c = {
    party = { mon },
    session = { flags = { [0x826] = true } },
    isSurfing = true,
    isFacingWaterfall = true,
    facing = "up",
  }
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

local res = FieldMoves.tryWaterfallOW(ctx())
check(res.ok == true, "surfing north at a waterfall with the Volcano Badge offers the climb")
eq(res.action, "waterfall", "the offered action is waterfall")
check(res.ask ~= nil and #res.ask > 0, "the climb asks first")
check(res.text ~= nil and res.text:find("GYARADOS", 1, true) ~= nil,
  "Text_MonUsedWaterfall names the user")

res = FieldMoves.tryWaterfallOW(ctx({ isFacingWaterfall = false }))
check(res.ok == false and res.text == nil, "a non-waterfall tile says nothing")

res = FieldMoves.tryWaterfallOW(ctx({ isSurfing = false }))
check(res.ok == false and res.text == FieldMoves.TEXT.CANT_WATERFALL,
  "standing on land at a waterfall gets Text_WallOfWaterCrashingDown")

res = FieldMoves.tryWaterfallOW(ctx({ facing = "left" }))
check(res.ok == false and res.text == FieldMoves.TEXT.CANT_WATERFALL,
  "surfing but not north gets Text_WallOfWaterCrashingDown")

res = FieldMoves.tryWaterfallOW(ctx({ session = { flags = {} } }))
check(res.ok == false and res.text == FieldMoves.TEXT.CANT_WATERFALL,
  "no Volcano Badge gets Text_WallOfWaterCrashingDown")

res = FieldMoves.tryWaterfallOW(ctx({ party = { { species = 1, moves = { 33 } } } }))
check(res.ok == false and res.text == FieldMoves.TEXT.CANT_WATERFALL,
  "no party member with WATERFALL gets Text_WallOfWaterCrashingDown")

print("[test] 4. SetUpFieldMove_Waterfall (party menu) takes the same gate")
res = FieldMoves.waterfallFromMenu(ctx({ mon = mon }))
check(res.ok == true, "the party menu entry sets up the climb")
eq(res.action, "waterfall", "the party menu entry also asks for the waterfall action")
check(res.text == nil, "FieldCallback_Waterfall shows no message of its own")
res = FieldMoves.waterfallFromMenu(ctx({ mon = mon, facing = "down" }))
check(res.ok == false, "the party menu entry refuses unless the player surfs north")

print("[test] 5. FldEff_UseWaterfall rides the player up the whole waterfall")
check(type(Field.rideWaterfall) == "function", "Field.rideWaterfall exists")
check(type(Field.updateWaterfall) == "function", "Field.updateWaterfall exists")
check(type(Field.forcedMovementPending) == "function", "Field.forcedMovementPending exists")
check(type(Field.pollMapChange) == "function", "Field.pollMapChange exists")
if type(Field.rideWaterfall) ~= "function" or type(Field.updateWaterfall) ~= "function"
  or type(Field.forcedMovementPending) ~= "function" or type(Field.pollMapChange) ~= "function" then
  print("[test] FAILED " .. failed .. " (no waterfall ride to drive)")
  os.exit(1)
end

local W, H = 5, 12
local MID_WATER, MID_FALL, MID_LAND = 1, 2, 3
local FALL_TOP, FALL_BOTTOM = 3, 6
Interaction.behaviors["waterfall_test"] = {
  [MID_WATER] = 0x10, [MID_FALL] = 0x13, [MID_LAND] = 0x00,
}
local mids = {}
local function midOf(x, y)
  if x < 0 or y < 0 or x >= W or y >= H then return MID_LAND end
  return mids[y * W + x + 1] or MID_LAND
end
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local m = MID_LAND
    if x == 2 then
      m = (y >= FALL_TOP and y <= FALL_BOTTOM) and MID_FALL or MID_WATER
    end
    mids[y * W + x + 1] = m
  end
end
Collision._mapDef = {
  pair = "waterfall_test",
  midLayout = { width = W, height = H, midAt = function(_, x, y) return midOf(x, y) end },
}
Collision._widthCells, Collision._heightCells = W, H
Collision._grid = {}
for y = 0, H - 1 do
  for x = 0, W - 1 do
    Collision._grid[y * W + x + 1] = (midOf(x, y) == MID_LAND) and 0x00 or 0x29
  end
end
eq(Collision.behavior(2, 5), 0x13, "the synthetic column reads back as MB_WATERFALL")
eq(Collision.behavior(2, 8), 0x10, "the foot of the column is plain water")

Field.running = true
Field.locked = false
Field._game = nil
Field._session = nil
Player.reset(2, FALL_BOTTOM + 1, "up")
Player.surfing = true

Field.rideWaterfall("up", 0)
check(Field.locked == true, "the climb locks player control")
local frames = 0
for _ = 1, 600 do
  Field.updateWaterfall(nil)
  Player.tick(nil)
  frames = frames + 1
  if not Field._waterfall then break end
end
eq(Player.cellY, FALL_TOP - 1, "the climb ends on the first tile above the waterfall")
check(Field.locked == false, "the climb releases player control when it ends")
check(frames > 4, "the climb was animated, not teleported (" .. frames .. " frames)")
-- pokefirered/src/field_effect.c:1650
check(frames >= 4 * 32, "the climb runs at GetWalkSlowerMovementAction speed (" .. frames .. " frames)")
check(Player.surfing == true, "the player is still surfing at the top")

print("[test] 6. ForcedMovement_PushedSouthByCurrent washes the player back down")
Player.facing = "down"
eq(Player.tryMove("down", nil, false), "step", "surfing down onto the waterfall is a normal step")
for _ = 1, 900 do
  Player.tick(nil)
  Field.updateWaterfall(nil)
  if Player.cellY > FALL_BOTTOM and not Player.moving then break end
end
eq(Player.cellY, FALL_BOTTOM + 1, "the current dumps the player below the waterfall")
check(Field._waterfall == nil, "the wash-down is not the climb task")
check(Field.locked == false, "the wash-down does not leave the field locked")

print("[test] 7. an idle surfer off the waterfall is left alone")
Player.reset(2, FALL_BOTTOM + 2, "up")
Player.surfing = true
Field.updateWaterfall(nil)
eq(Player.moving, false, "no forced step on plain water")
eq(Player.cellY, FALL_BOTTOM + 2, "the player stays put on plain water")

print("[test] 8. forced movement beats a held D-pad direction")
local held = {}
local input = {
  wasPressed = function() return false end,
  isDown = function(_, b) return held[b] == true end,
}

Player.reset(2, FALL_BOTTOM + 1, "up")
Player.surfing = true
Field.locked = false
Field._waterfall = nil
check(Field.forcedMovementPending() == false, "plain water below the fall is not a forced tile")
held = { up = true }
local minY = Player.cellY
local sawPending = false
for _ = 1, 600 do
  Player.update(nil, input)
  if Field.forcedMovementPending() then sawPending = true end
  Field.updateWaterfall(nil)
  if Player.cellY < minY then minY = Player.cellY end
end
check(sawPending, "Field.forcedMovementPending sees the waterfall while UP is held")
eq(minY, FALL_BOTTOM, "held UP never carries the player past the bottom waterfall tile")
check(Field._waterfall == nil, "no climb task was started by the D-pad alone")
held = {}
for _ = 1, 120 do
  Player.update(nil, input)
  Field.updateWaterfall(nil)
end
eq(Player.cellY, FALL_BOTTOM + 1, "releasing UP leaves the player at the foot of the waterfall")

Player.reset(2, FALL_TOP - 1, "down")
Player.surfing = true
eq(Player.tryMove("down", nil, false), "step", "the top pool lets the player step onto the fall")
held = { up = true }
local maxY = Player.cellY
for _ = 1, 900 do
  Player.update(nil, input)
  Field.updateWaterfall(nil)
  if Player.cellY > maxY then maxY = Player.cellY end
  if maxY > FALL_BOTTOM then break end
end
eq(maxY, FALL_BOTTOM + 1, "a held UP cannot resist the current once the player is on the fall")
held = {}

print("[test] 9. ClearTempFieldEventData on a map change")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local savedStore = Space.store
Space.store = { flags = {} }
local STRENGTH = FieldMoves.SYS_FLAGS.USE_STRENGTH
local WHITE = FieldMoves.SYS_FLAGS.WHITE_FLUTE_ACTIVE
local BLACK = FieldMoves.SYS_FLAGS.BLACK_FLUTE_ACTIVE
local FLASH = FieldMoves.SYS_FLAGS.FLASH_ACTIVE
local game = { data = { maps = {
  CAVE = { mapType = FieldMoves.MAP_TYPES.UNDERGROUND },
  ROUTE = { mapType = FieldMoves.MAP_TYPES.ROUTE },
} } }
Field._session = { map = "CAVE", flags = {} }
Field._tempFlagMap = "CAVE"
for _, id in ipairs({ STRENGTH, WHITE, BLACK, FLASH }) do
  Flags.setFlag(Space.store, nil, id, true)
  Field._session.flags[id] = true
end
check(Field.pollMapChange(game) == false, "staying on one map clears nothing")
check(Flags.getFlag(Space.store, nil, STRENGTH) == true, "Strength survives while the map is the same")

Field._session.map = "CAVE2"
game.data.maps.CAVE2 = { mapType = FieldMoves.MAP_TYPES.UNDERGROUND }
check(Field.pollMapChange(game) == true, "a new map id runs ClearTempFieldEventData")
check(Flags.getFlag(Space.store, nil, STRENGTH) ~= true, "FLAG_SYS_USE_STRENGTH clears on a map change")
check(Field._session.flags[STRENGTH] == nil, "the session copy of FLAG_SYS_USE_STRENGTH clears too")
check(Flags.getFlag(Space.store, nil, WHITE) ~= true, "FLAG_SYS_WHITE_FLUTE_ACTIVE clears on a map change")
check(Flags.getFlag(Space.store, nil, BLACK) ~= true, "FLAG_SYS_BLACK_FLUTE_ACTIVE clears on a map change")
-- pokefirered/src/overworld.c:803
check(Flags.getFlag(Space.store, nil, FLASH) == true, "Flash stays lit when the new map is indoors")

Field._session.map = "ROUTE"
check(Field.pollMapChange(game) == true, "warping outdoors runs ClearTempFieldEventData")
check(Flags.getFlag(Space.store, nil, FLASH) ~= true, "FLAG_SYS_FLASH_ACTIVE clears when the new map is outdoors")
Space.store = savedStore
Field._session = nil
Field._tempFlagMap = nil

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)

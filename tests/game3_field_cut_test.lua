#!/usr/bin/env luajit
-- pokefirered/src/field_specials.c:2296 CutMoveRuinValleyCheck
-- pokefirered/src/field_specials.c:2310 CutMoveOpenDottedHoleDoor
-- pokefirered/src/fldeff_cut.c:118 SetUpFieldMove_Cut

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local FieldMoves = require("src.core.game3.field_moves")

print("[test] 1. CutMoveRuinValleyCheck, ROM-free")
local RV = FieldMoves.RUIN_VALLEY
check(RV.map == "FR_SIX_ISLAND_RUIN_VALLEY", "the check is keyed on Six Island Ruin Valley")
check(RV.x == 24 and RV.y == 25 and RV.facing == "up", "at (24,25) facing north")
check(RV.flag == 0x2E3, "FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE is 0x2E3")
check(RV.doorX == 24 and RV.doorY == 24, "the door cell is map (24,24), MapGrid (31,31) less MAP_OFFSET")
check(RV.doorOpen == 0x358, "METATILE_SeviiIslands67_DottedHoleDoor_Open is 0x358")

local function rvCtx(over)
  local ctx = { mapId = RV.map, x = RV.x, y = RV.y, facing = RV.facing, session = { flags = {} } }
  for k, v in pairs(over or {}) do ctx[k] = v end
  return ctx
end

check(FieldMoves.ruinValleyCutCheck(rvCtx()) == true, "standing on the braille tile passes")
check(FieldMoves.ruinValleyCutCheck(rvCtx({ facing = "down" })) == false, "facing south fails")
check(FieldMoves.ruinValleyCutCheck(rvCtx({ x = 23 })) == false, "one cell west fails")
check(FieldMoves.ruinValleyCutCheck(rvCtx({ y = 26 })) == false, "one cell south fails")
check(FieldMoves.ruinValleyCutCheck(rvCtx({ mapId = "FR_PALLET_TOWN" })) == false,
  "another map fails")
check(FieldMoves.ruinValleyCutCheck(rvCtx({ session = { flags = { [0x2E3] = true } } })) == false,
  "the flag already set fails")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_cut_test (cache-backed sections): " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local FieldEffects = require("src.core.game3.field_effects")
local Runtime = require("src.core.game3.runtime")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {}, party = {} }
game.session = session
Runtime.session = session

local function enterMap(mapId)
  local def = game.data.maps[mapId]
  if not def then return nil end
  Field._game = game
  Field._session = session
  session.map = mapId
  Field.running = true
  Field.locked = false
  Field.clearMetatiles()
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, def)
  Objects.loadMap(game, mapId, def)
  Space.runOnLoad(mapId)
  return def
end

local function pumpVm(limit)
  local vm = Space.vm
  local n = 0
  while vm and vm:isRunning() and n < (limit or 512) do
    vm:tick()
    n = n + 1
  end
end

local function standAt(x, y, facing)
  Player.moving = false
  Player.progress = 0
  Player.surfing = false
  Player.cellX, Player.cellY = x, y
  Player.targetX, Player.targetY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.facing = facing or "down"
end

print("[test] 2. the Dotted Hole door starts shut on Six Island Ruin Valley")
local def = enterMap(RV.map)
check(def ~= nil, RV.map .. " is in the cache")
if not def then finish() end
pumpVm()
local layout = def.midLayout
check(layout:midAt(RV.doorX, RV.doorY) == 0x357,
  "(24,24) is METATILE_SeviiIslands67_DottedHoleDoor_Closed")
check(Collision.isWalkable(RV.doorX, RV.doorY) == false, "the shut door is impassable")
local warp
for _, w in ipairs(def.warps or {}) do
  if w.x == RV.doorX and w.y == RV.doorY then warp = w end
end
check(warp ~= nil and tostring(warp.destMap or warp.dest) == "FR_SIX_ISLAND_DOTTED_HOLE_1F",
  "the warp behind it leads to the Dotted Hole")

print("[test] 3. Cut on the braille tile picks the dotted-hole arm")
standAt(RV.x, RV.y, "up")
session.party = { { species = 1, level = 30, moves = { 15 }, hp = 30, maxHp = 30 } }
Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FieldMoves.BADGE_FLAGS.CUT, true)
local ctx = {
  party = session.party,
  store = Space.store,
  session = session,
  hasCuttableGrass = true,
}
local res = FieldMoves.fromMenu("CUT", ctx)
check(res ~= nil and res.ok == true, "Cut is allowed here")
check(res and res.action == "dotted_hole",
  "the action is dotted_hole, not cut_grass (got " .. tostring(res and res.action) .. ")")

standAt(RV.x, RV.y, "down")
local res2 = FieldMoves.fromMenu("CUT", ctx)
check(res2 and res2.action == "cut_grass",
  "facing south it is an ordinary Cut again (got " .. tostring(res2 and res2.action) .. ")")

print("[test] 4. executing it opens the door")
standAt(RV.x, RV.y, "up")
Field.executeFieldMove(FieldMoves.fromMenu("CUT", ctx))
check(Field.locked == true, "the field locks for the animation")
for _ = 1, 40 do FieldEffects.step() end
check(Field.locked == false, "the field unlocks when the animation ends")
local override = Field.metatileOverrideAt(RV.map, RV.doorX, RV.doorY)
check(override ~= nil and override.metatile == RV.doorOpen, "(24,24) became the open door")
check(layout:midAt(RV.doorX, RV.doorY) == RV.doorOpen, "the live layout shows the open door")
check(Collision.isWalkable(RV.doorX, RV.doorY) == true, "the doorway is now walkable")
check(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, RV.flag) == true,
  "FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE is set")
check(FieldMoves.ruinValleyCutCheck(ctx) == false, "a second Cut does not re-trigger")

print("[test] 5. the door stays open across a map reload")
enterMap("SEVII_SIX_ISLAND")
pumpVm()
local def2 = enterMap(RV.map)
pumpVm()
check(def2.midLayout:midAt(RV.doorX, RV.doorY) == RV.doorOpen,
  "ON_LOAD re-opened the door from the flag")
check(Collision.isWalkable(RV.doorX, RV.doorY) == true, "and it is still walkable")

finish()

#!/usr/bin/env luajit

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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchfield_ground_test: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Field = require("src.core.game3.field")
local Player = require("src.core.game3.player")
local Collision = require("src.core.game3.collision")
local Flags = require("src.core.game3.scripting.flags")
local FieldEffects = require("src.core.game3.field_effects")
local Audio = require("src.core.game3.audio")

local MB_PUDDLE = 0x16
local MB_SHALLOW_WATER = 0x17
local MB_HOT_SPRINGS = 0x28
local SE_PUDDLE = 63

local seCount = 0
local realPlaySe = Audio.playSe
Audio.playSe = function(id, opts)
  if id == SE_PUDDLE then seCount = seCount + 1 end
  return realPlaySe(id, opts)
end
local function sinceSe()
  local n = seCount
  seCount = 0
  return n
end

local seen = {}
local started = {}
local function sample()
  for _, anim in ipairs(FieldEffects._anims) do
    if not seen[anim] then
      seen[anim] = true
      started[anim.kind] = (started[anim.kind] or 0) + 1
    end
  end
end
local function sinceStarted(kind)
  local n = started[kind] or 0
  started[kind] = 0
  return n
end
local function clearStarted()
  started = {}
  sinceSe()
end

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {} }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local held = nil
game.input = {
  isDown = function(_, d) return d == held end,
  wasPressed = function() return false end,
}

local function frames(n)
  for _ = 1, n do
    Field.update(1 / 60)
    sample()
  end
end

local function settle()
  for _ = 1, 60 do
    if not Field.locked and not Space.vm:isRunning() then return true end
    frames(10)
  end
  return false
end

local function goTo(mapId, x, y, facing)
  held = nil
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
  local ok = settle()
  frames(2)
  return ok and Player.cellX == x and Player.cellY == y
end

local function count(kind)
  local n = 0
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == kind then n = n + 1 end
  end
  return n
end

local function walk(dir, x, y)
  held = dir
  for _ = 1, 30 do
    frames(1)
    if Player.moving then break end
  end
  held = nil
  for _ = 1, 40 do
    if not Player.moving then break end
    frames(1)
  end
  return Player.cellX == x and Player.cellY == y
end

print("[test] 1. Four Island's pond edge is a puddle block")
-- pokefirered/data/maps/FourIsland/scripts.inc:23 FourIsland_OnFrame
local VAR_MAP_SCENE_FOUR_ISLAND = 0x4086
Flags.setVar(Space.store, Space.vm and Space.vm.ctx, VAR_MAP_SCENE_FOUR_ISLAND, 1)
check(goTo("FR_FOUR_ISLAND", 20, 9, "left"),
  "Four Island settled at (20,9) with the rival scene already played")
check(Collision.behavior(20, 9) ~= MB_PUDDLE, "(20,9) is dry, behavior "
  .. string.format("0x%02X", Collision.behavior(20, 9) or 0))
for _, c in ipairs({ { 19, 9 }, { 18, 9 }, { 18, 10 } }) do
  check(Collision.behavior(c[1], c[2]) == MB_PUDDLE,
    string.format("(%d,%d) is MB_PUDDLE", c[1], c[2]))
end

print("[test] 2. stepping onto a puddle from dry land splashes once on landing")
-- pokefirered/src/event_object_movement.c:8163 GetGroundEffectFlags_Puddle
-- pokefirered/src/event_object_movement.c:5343 ShiftStillObjectEventCoords
clearStarted()
check(walk("left", 19, 9), "walked (20,9) to (19,9)")
check(sinceStarted("splash") == 1,
  "one splash, the finish step reads previous == current == MB_PUDDLE")
check(sinceStarted("ripple") == 1,
  "one ripple, MetatileBehavior_HasRipples covers MB_PUDDLE")
check(sinceSe() == 1, "and SE_PUDDLE played once")

print("[test] 3. puddle to puddle splashes on the begin step and again on the finish step")
-- pokefirered/src/event_object_movement.c:8035 and :8049
clearStarted()
check(walk("left", 18, 9), "walked (19,9) to (18,9)")
check(sinceStarted("splash") == 2, "two splashes for the one step")
check(sinceStarted("ripple") == 1, "and one ripple on landing")
check(sinceSe() == 2, "SE_PUDDLE played twice")

print("[test] 4. the splash runs sAnim_Splash_0 and stops")
-- pokefirered/src/data/field_effects/field_effect_objects.h:571
local frameLog = {}
for _ = 1, 10 do
  local f = nil
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == "splash" then f = anim.frame end
  end
  frameLog[#frameLog + 1] = tostring(f)
  frames(1)
end
check(table.concat(frameLog, ",") == "0,0,0,0,1,1,1,1,nil,nil",
  "splash frames 0,0,0,0,1,1,1,1 then gone, got " .. table.concat(frameLog, ","))

print("[test] 5. the ripple lives the 79 ticks of sAnim_Ripple")
-- pokefirered/src/data/field_effects/field_effect_objects.h:108
check(goTo("FR_FOUR_ISLAND", 20, 9, "left"), "back on dry land at (20,9)")
check(count("ripple") == 0, "no ripples left over, got " .. count("ripple"))
check(walk("left", 19, 9), "walked onto the puddle again")
local rippleAnim
for _, anim in ipairs(FieldEffects._anims) do
  if anim.kind == "ripple" then rippleAnim = anim end
end
check(rippleAnim ~= nil and rippleAnim.cx == 19 and rippleAnim.cy == 9,
  "the ripple sits on the cell that was stepped onto")
frames(79 - (rippleAnim and rippleAnim.timer or 0))
check(count("ripple") == 1, "still rippling on the 79th tick, the last frame of the anim")
frames(1)
check(count("ripple") == 0, "gone on the next tick, got " .. count("ripple"))

print("[test] 6. Route 21's sandbar wades from the first cell")
-- pokefirered/src/event_object_movement.c:8143 GetGroundEffectFlags_ShallowFlowingWater
check(goTo("FR_ROUTE_21_NORTH", 17, 24, "right"), "stood beside the Route 21 North sandbar")
check(Collision.behavior(17, 24) ~= MB_SHALLOW_WATER
  and Collision.behavior(18, 24) == MB_SHALLOW_WATER
  and Collision.behavior(18, 25) == MB_SHALLOW_WATER
  and Collision.behavior(17, 25) == MB_SHALLOW_WATER,
  "(18,24), (18,25) and (17,25) are MB_SHALLOW_WATER and (17,24) is not")
check(FieldEffects._ground.inShallowFlowingWater == false, "inShallowFlowingWater is clear")
clearStarted()
check(walk("right", 18, 24), "waded (17,24) to (18,24)")
check(sinceStarted("feet_water") == 1,
  "the finish step reads previous == current, so the first cell wades")
check(count("feet_water") == 1, "one effect is running, got " .. count("feet_water"))
check(FieldEffects._ground.inShallowFlowingWater == true, "the sticky flag is set")
frames(2)
-- pokefirered/src/field_effect_helpers.c:707 UpdateFeetInFlowingWaterFieldEffect
check(sinceSe() == 1, "SE_PUDDLE played once for the cell it started on")

print("[test] 7. wading keeps exactly one effect and replays SE_PUDDLE per cell")
clearStarted()
check(walk("down", 18, 25), "waded (18,24) to (18,25)")
check(sinceStarted("feet_water") == 0, "no second effect, the sticky flag never cleared")
check(count("feet_water") == 1, "and one is running, got " .. count("feet_water"))
check(FieldEffects._ground.inShallowFlowingWater == true, "the sticky flag stayed set")
check(sinceStarted("splash") == 0, "no splash, MB_SHALLOW_WATER is not MB_PUDDLE")
check(sinceSe() == 1, "SE_PUDDLE played once")
clearStarted()
check(walk("left", 17, 25), "waded on to (17,25)")
check(sinceStarted("feet_water") == 0, "no second effect")
check(count("feet_water") == 1, "still exactly one, got " .. count("feet_water"))
check(sinceSe() == 1, "SE_PUDDLE replayed once for the new cell")

print("[test] 8. leaving the shallow water stops it")
check(walk("left", 16, 25), "stepped off the sandbar onto (16,25)")
check(FieldEffects._ground.inShallowFlowingWater == false, "the sticky flag cleared")
check(count("feet_water") == 0, "the effect stopped, got " .. count("feet_water"))

print("[test] 9. spawning already in the water starts it, as OnSpawn does")
-- pokefirered/src/event_object_movement.c:8023 GetAllGroundEffectFlags_OnSpawn
clearStarted()
check(goTo("FR_ROUTE_21_NORTH", 18, 25, "down"), "warped straight onto a sandbar cell")
check(FieldEffects._ground.inShallowFlowingWater == true, "the sticky flag is set on arrival")
check(count("feet_water") == 1, "one effect on arrival, got " .. count("feet_water"))
check(sinceStarted("ripple") == 0, "and no ripple, that is a finish-step effect only")

print("[test] 10. Ember Spa steams from the cell the player lands on")
-- pokefirered/src/event_object_movement.c:8196 GetGroundEffectFlags_HotSprings
check(goTo("FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA", 13, 10, "down"), "stood at the spa edge")
check(Collision.behavior(13, 10) ~= MB_HOT_SPRINGS
  and Collision.behavior(13, 11) == MB_HOT_SPRINGS
  and Collision.behavior(13, 12) == MB_HOT_SPRINGS,
  "the pool cells are MB_HOT_SPRINGS and the edge is not")
clearStarted()
check(walk("down", 13, 11), "stepped into the pool")
-- pokefirered/src/event_object_movement.c:5343 ShiftStillObjectEventCoords
check(sinceStarted("hot_springs") == 1, "steam started on the first spring cell")
check(walk("down", 13, 12), "waded deeper")
check(sinceStarted("hot_springs") == 0, "no second steam effect")
check(FieldEffects._ground.inHotSprings == true, "the sticky flag is set")
check(Collision.behavior(12, 12) == MB_HOT_SPRINGS, "(12,12) is MB_HOT_SPRINGS too")
check(walk("left", 12, 12), "waded across the pool")
check(sinceStarted("hot_springs") == 0, "no second steam effect")
check(count("hot_springs") == 1, "one is running, got " .. count("hot_springs"))
check(walk("right", 13, 12) and walk("up", 13, 11), "waded back to the pool edge")
check(count("hot_springs") == 1, "still steaming, both cells are hot springs")
check(walk("up", 13, 10), "back on dry land")
check(FieldEffects._ground.inHotSprings == false, "the sticky flag cleared")
check(count("hot_springs") == 0, "the steam stopped, got " .. count("hot_springs"))
check(sinceSe() == 0, "and the spa is silent, hot springs plays no SE_PUDDLE")

print("[test] 11. a map change resets the ground effect state")
-- pokefirered/src/event_object_movement.c:1934 ResetObjectEventFldEffData
check(goTo("FR_ROUTE_21_NORTH", 18, 25, "down"), "back on the sandbar")
check(count("feet_water") == 1, "wading again")
check(goTo("FR_PALLET_TOWN", 12, 20, "down"), "warped to Pallet Town")
check(FieldEffects._ground.inShallowFlowingWater == false,
  "inShallowFlowingWater cleared by the map change")
check(count("feet_water") == 0, "and the effect stopped, got " .. count("feet_water"))

print("[test] 12. standing still costs nothing")
local anims = #FieldEffects._anims
FieldEffects.groundEffects()
collectgarbage("collect")
local before = collectgarbage("count")
for _ = 1, 20000 do FieldEffects.groundEffects() end
local perPoll = (collectgarbage("count") - before) * 1024 / 20000
check(#FieldEffects._anims == anims, "20000 polls started nothing")
check(perPoll < 1,
  "the standing poll allocates " .. string.format("%.4f", perPoll) .. " bytes per frame")

Audio.playSe = realPlaySe
done()

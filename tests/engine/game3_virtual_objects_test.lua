package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local VirtualObjects = require("src.core.game3.virtual_objects")

VirtualObjects.reset()

check(package.loaded["src.core.game3.objects"] == nil,
  "the registry does not drag in objects.lua")
check(package.loaded["src.core.game3.collision"] == nil,
  "the registry does not drag in collision (virtual objects never collide)")
eq(VirtualObjects.DIR_SOUTH, 1, "DIR_SOUTH matches pret include/constants/global.h:110")

eq(VirtualObjects.count(), 0, "starts empty")

local rec = VirtualObjects.spawn(1, 42, 6, 8, 3, 2)
check(type(rec) == "table", "spawn returns a record")
eq(rec.id, 1, "id stored")
eq(rec.graphicsId, 42, "graphicsId stored")
eq(rec.x, 6, "x stored")
eq(rec.y, 8, "y stored")
eq(rec.elevation, 3, "elevation stored")
eq(rec.direction, 2, "direction stored")
eq(VirtualObjects.count(), 1, "one live object")

-- event.inc:1346
local dflt = VirtualObjects.spawn(2, 7, 0, 0, nil, nil)
eq(dflt.elevation, 3, "default elevation is 3")
eq(dflt.direction, VirtualObjects.DIR_SOUTH, "default direction is DIR_SOUTH")
eq(VirtualObjects.count(), 2, "two live objects")

check(VirtualObjects.get(1) == rec, "get finds the record")
check(VirtualObjects.get(99) == nil, "get misses cleanly")

local list = VirtualObjects.list()
eq(#list, 2, "list returns both records")
eq(list[1].id, 1, "list preserves spawn order (first)")
eq(list[2].id, 2, "list preserves spawn order (second)")

check(VirtualObjects.turn(1, 5) == true, "turn on a live id succeeds")
eq(VirtualObjects.get(1).direction, 5, "turn updates direction")
eq(VirtualObjects.get(2).direction, VirtualObjects.DIR_SOUTH,
  "turn on one id leaves the other alone")

-- src/event_object_movement.c:9248-9257
check(VirtualObjects.turn(99, 1) == false, "turn on a missing id is a no-op")
check(VirtualObjects.turn(99, 1) == false, "still a no-op on a repeat")
check(VirtualObjects.turn(nil, 1) == false, "turn(nil) is a no-op")
eq(VirtualObjects.get(99), nil, "a missed turn creates nothing")

check(VirtualObjects.turn(2, "sideways") == true, "non-numeric direction is accepted")
eq(VirtualObjects.get(2).direction, VirtualObjects.DIR_SOUTH,
  "a non-numeric direction does not clobber the stored one")

local replaced = VirtualObjects.spawn(1, 99, 12, 14, 5, 6)
check(replaced == VirtualObjects.get(1), "re-spawning an id replaces the entry")
eq(VirtualObjects.count(), 2, "a replace does not duplicate the id")
eq(VirtualObjects.get(1).graphicsId, 99, "the replacement's graphics wins")
eq(#VirtualObjects.list(), 2, "list has no duplicate id")

local coerced = VirtualObjects.spawn("3", 1, 1, 1, 1, 1)
check(coerced ~= nil, "a numeric-string id is accepted")
check(VirtualObjects.get(3) == coerced, "and resolves to the same record")
check(VirtualObjects.turn("3", 4) == true, "turn accepts the same coercion")

eq(VirtualObjects.spawn(nil, 1, 0, 0, 1, 1), nil, "a nil id is refused")
eq(VirtualObjects.spawn("badge", 1, 0, 0, 1, 1), nil, "a non-numeric id is refused")
eq(VirtualObjects.count(), 3, "refused spawns add nothing")

VirtualObjects.clear()
eq(VirtualObjects.count(), 0, "clear empties the registry (map unload)")
eq(#VirtualObjects.list(), 0, "list is empty after clear")
check(VirtualObjects.get(1) == nil, "records are gone")
check(VirtualObjects.turn(1, 1) == false, "turn after clear is a no-op")

local fresh = VirtualObjects.spawn(1, 5, 2, 2, 3, 1)
check(fresh ~= nil, "ids are reusable after clear")
eq(VirtualObjects.count(), 1, "one object after re-spawn")
eq(#VirtualObjects.list(), 1, "no ghost entries from the pre-clear spawn")

VirtualObjects.reset()
eq(VirtualObjects.count(), 0, "reset clears everything")
VirtualObjects.reset()
eq(VirtualObjects.count(), 0, "reset is safe to repeat")

T.finish("game3_virtual_objects_test")

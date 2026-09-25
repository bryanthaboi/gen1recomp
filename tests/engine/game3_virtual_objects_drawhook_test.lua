-- src/event_object_movement.c:1719, src/event_object_movement.c:9225

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Objects = require("src.core.game3.objects")
local VirtualObjects = require("src.core.game3.virtual_objects")
local GfxIds = require("src.core.game3.scripting.gfx_ids")

local savedMap, savedOrder, savedById = Objects._mapId, Objects._order, Objects._byId
Objects._mapId = "FR_TEST_DRAWHOOK"
Objects._order = {}
Objects._byId = {}
VirtualObjects.clear()

VirtualObjects.spawn(1, 40, 5, 6, 4, 1)
local found
for _, eo in ipairs(Objects.forDraw()) do
  if eo.virtualId == 1 then found = eo end
end
check(found ~= nil, "forDraw yields the virtual object")
eq(found and found.cellX, 5, "tile x reaches the draw pass")
eq(found and found.cellY, 6, "tile y reaches the draw pass")
eq(found and found.elevation, 4, "elevation reaches the draw pass (actorPriority uses it)")
eq(found and found.facing, "down", "DIR_SOUTH maps to the down-facing sprite")
eq(found and found.graphicsId, 40, "graphicsId reaches OwSprites.draw")
eq(found and found.sprite, GfxIds.spriteFor(40), "sprite name reaches the non-OW fallback")
eq(Objects._byId[1], nil, "the registry is not in the object store (no collision)")
eq(Objects.at(5, 6), nil, "Objects.at cannot see it")

local again
for _, eo in ipairs(Objects.forDraw()) do
  if eo.virtualId == 1 then again = eo end
end
check(again == found, "forDraw reuses the draw record for an unchanged virtual object")
if jit then jit.off() end
for _ = 1, 20 do Objects.forDraw() end
collectgarbage("collect")
collectgarbage("stop")
local kb0 = collectgarbage("count")
for _ = 1, 100 do Objects.forDraw() end
local grown = collectgarbage("count") - kb0
collectgarbage("restart")
if jit then jit.on() end
check(grown < 1, "forDraw allocates nothing in steady state (" .. grown .. " KB)")

VirtualObjects.turn(1, 2)
local turned
for _, eo in ipairs(Objects.forDraw()) do
  if eo.virtualId == 1 then turned = eo end
end
eq(turned and turned.facing, "up", "turn(1, DIR_NORTH) shows on the next draw")

VirtualObjects.clear()
local gone = false
for _, eo in ipairs(Objects.forDraw()) do
  if eo.virtualId == 1 then gone = true end
end
eq(gone, false, "clear() removes it (DestroyVirtualObjects on map unload)")

Objects._mapId, Objects._order, Objects._byId = savedMap, savedOrder, savedById

T.finish("game3_virtual_objects_drawhook_test")

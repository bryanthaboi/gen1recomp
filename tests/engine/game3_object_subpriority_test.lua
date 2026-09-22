-- src/event_object_movement.c:2089-2101, src/event_object_movement.c:2104-2116, src/scrcmd.c:1122-1130

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Objects = require("src.core.game3.objects")
local Catalog = require("src.import.gba.map_catalog")

local here = Catalog.mapIdFor(0, 1)
local other = Catalog.mapIdFor(0, 2)
check(here and other and here ~= other, "the catalog resolves two distinct maps")

local savedMap = Objects._mapId
local savedById = Objects._byId
Objects._mapId = here
Objects._byId = { [7] = { localId = 7 } }

local ok = Objects.setSubpriority(7, 0, 1, 5 + 83)
eq(ok, true, "set succeeds for the current map")
eq(Objects._byId[7].fixedPriority, true, "fixedPriority is frozen")
eq(Objects._byId[7].subpriority, 88, "subpriority stores priority + 83")
Objects._byId[7].fixedClass = 1
Objects.setSubpriority(7, 0, 1, 10 + 83)
eq(Objects._byId[7].fixedClass, nil, "set nils a stale fixedClass before first observation")

local refused = Objects.setSubpriority(7, 0, 2, 7 + 83)
eq(refused, false, "a different (mapGroup, mapNum) is refused")
eq(Objects._byId[7].subpriority, 93, "the refused call left the record alone")

eq(Objects.setSubpriority(99, 0, 1, 1), false, "unknown localId: set is a no-op")
eq(Objects.resetSubpriority(99, 0, 1), false, "unknown localId: reset is a no-op")

-- event_object_movement.c:2104-2116
Objects._byId[7].fixedClass = 2
eq(Objects.resetSubpriority(7, 0, 1), true, "reset succeeds for the current map")
eq(Objects._byId[7].fixedPriority, nil, "fixedPriority dropped")
eq(Objects._byId[7].subpriority, nil, "subpriority dropped")
eq(Objects._byId[7].fixedClass, nil, "fixedClass dropped (all three per spec 5.8)")

Objects._byId = {}
eq(Objects.setSubpriority(7, 0, 1, 1), false, "no object after clear: no-op")

Objects._mapId = savedMap
Objects._byId = savedById

T.finish("game3_object_subpriority_test")

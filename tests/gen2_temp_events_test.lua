-- EVENT_TEMPORARY_UNTIL_MAP_RELOAD: HandleNewMap calls
-- ResetMapBufferEventFlags on every map load (pokegold home/map.asm), and
-- home/flag.asm shows that routine zeroing exactly ONE byte of wEventFlags --
-- flags 0-7.  Those eight are the once-per-visit latches: Bill's grandpa sets
-- flag 0 after handing over an evolution stone and refuses while it is set,
-- so a port that never clears the byte caps his whole chain at one stone per
-- save.  Kurt's house, the ship ports, Dragon's Den B1F, the National Park
-- gate, Pokecenter 2F and the link rooms ride the same byte.
--
--   GOLD_CACHE=".../gold" luajit tests/gen2_temp_events_test.lua
--
-- The clear and its ordering are ROM-free; the Bill's-house shape SKIPs
-- without a cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 temp events")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local Events = require("src.world.gen2.Events")
local Vm = require("src.script.gen2.Vm")
local Map = require("src.world.gen2.Map")

-- ---- the byte itself -------------------------------------------------------
do
  local events = Events.new()
  for id = 0, 9 do events:set(id, true) end
  events:set(800, true)
  events:resetMapBuffer()
  for id = 0, 7 do
    check(not events:get(id), ("flag %d dies with the map"):format(id))
  end
  check(events:get(8), "flag 8 is the next byte and survives")
  check(events:get(9), "so does flag 9")
  check(events:get(800), "and a story flag is untouched")
end

-- ---- the clear rides setMap, BEFORE MAPCALLBACK_NEWMAP ---------------------
-- The callback order test rig from gen2_map_callbacks_test: real setMap, the
-- love-facing bakes stubbed out.  The NEWMAP body itself checks flag 0, which
-- pins the order -- a clear that ran after the callback would read 1 here.
do
  local world = World.new({ data = {}, save = { party = {}, inventory = {} } })
  world.maps = {
    TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, tileset = "TEST",
      callbacks = {
        { callback = "MAPCALLBACK_NEWMAP", scriptKey = "newmap" },
      } },
  }
  world.tilesets = { TEST = {} }
  world.map = Map.new(world.maps.TEST_MAP, {})
  world.scripts = {
    newmap = {
      { op = "checkevent", event = 0 },
      { op = "iftrue", script = "sawset" },
      { op = "setevent", event = 600 },
      { op = "endcallback" },
    },
    sawset = { { op = "setevent", event = 601 }, { op = "endcallback" } },
  }
  world.vm = Vm.new(world.scripts, {}, world.events, {})
  world.imageFor = function() return true end
  world.rebuildNeighbors = function() end
  world.rebuildPeople = function() end
  world.applyPalettes = function() end

  for id = 0, 8 do world.events:set(id, true) end
  check(world:setMap("TEST_MAP", 0, 0, "down"), "the map loads")
  for id = 0, 7 do
    check(not world.events:get(id),
      ("setMap cleared temporary flag %d"):format(id))
  end
  check(world.events:get(8), "and left flag 8 alone")
  check(world.events:get(600), "the NEWMAP callback saw flag 0 already clear")
  check(not world.events:get(601),
    "so the clear really runs before MAPCALLBACK_NEWMAP")
end

-- ---- the cache shape this re-arms ------------------------------------------
-- BILLS_HOUSE (maps/BillsFamilysHouse.asm): the script head refuses while
-- event 0 is set, and every stone branch ends `setevent 800+n / setevent 0`.
-- With flag 0 dying on the reload above, leaving and re-entering the house
-- takes the head past its refusal to the next stone.
local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local chunk = loadfile(cache .. "/data/generated/scripts.lua")
if not chunk then
  check(true, "gold cache absent (SKIP Bill's-house shape)")
  S.finish()
  return
end
local scripts = chunk()

local head = scripts["54:547c"]
check(type(head) == "table", "the grandpa's script head extracted")
if type(head) == "table" then
  eq(head[3] and head[3].op, "checkevent", "row 3 is a checkevent")
  eq(head[3] and head[3].event, 0, "over temporary flag 0")
  eq(head[4] and head[4].op, "iftrue", "and iftrue is the refusal branch")
end
for n, key in ipairs({ "54:557f", "54:5596", "54:55ad", "54:55c4" }) do
  local rows = scripts[key]
  local latch, story
  for _, row in ipairs(rows or {}) do
    if row.op == "setevent" and row.event == 0 then latch = true end
    if row.op == "setevent" and row.event == 799 + n then story = true end
  end
  check(story, ("stone branch %d marks its stone given (%d)"):format(n, 799 + n))
  check(latch, ("and latches temporary flag 0 (%s)"):format(key))
end

S.finish()

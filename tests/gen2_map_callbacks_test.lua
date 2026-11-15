-- Map callbacks: RunMapCallback (home/map.asm) and the four places a map load
-- runs one.  `luajit tests/gen2_map_callbacks_test.lua`; also dofile'd by
-- tests/run_tests.lua.  Fixture-driven, with a final section that runs every
-- callback in a real Gold cache and SKIPs when there is none.
--
-- Three separate things are under test and they fail in different ways:
--
--   Vm:runCallback   a NESTED script run.  RunMapCallback does not check
--                    wScriptRunning, so this must work with a script parked --
--                    which is the normal case, because every warp a script
--                    takes is a map load with that script still on the stack.
--   the ORDER        HandleNewMap, then LoadBlockData, then LoadMapObjects.
--                    A TILES callback that runs after the canvas is baked
--                    paints nothing; an OBJECTS callback that runs after the
--                    people are built shows yesterday's NPC.
--   the CACHE FLUSH  a baked canvas is keyed by map and daytime and knows
--                    nothing about the blocks it was baked from, so a callback
--                    that rewrites blocks on every load needs the stale bakes
--                    dropped or it freezes on its first answer.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 map callbacks")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local World = require("src.world.gen2.World")

-- ---------------------------------------------------------------------------
-- Vm:runCallback -- ExecuteCallbackScript
-- ---------------------------------------------------------------------------

local function vmWith(scripts, hooks)
  return Vm.new(scripts, {}, Events.new(), hooks or {})
end

-- The plain case: a body that ends on `endcallback` runs to completion and the
-- VM is idle again afterwards.
do
  local flags = {}
  local vm = vmWith({
    cb = { { op = "setevent", event = 7 }, { op = "endcallback" } },
  }, { onFlagsChanged = function() flags[#flags + 1] = true end })
  check(vm:runCallback("cb"), "a callback body runs and reports it ran")
  check(vm.events:get(7), "and its setevent landed")
  check(not vm:running(), "with the VM idle again on the far side")
  check(not vm:runCallback(nil), "no script key is not a run")
  check(not vm:runCallback("nope"), "and neither is a key with no body")
end

-- Script_endcallback is ExitScriptSubroutine then StopScript: it ends the
-- CALLBACK, not the map load.  A body with commands behind it stops there.
do
  local vm = vmWith({
    cb = {
      { op = "setevent", event = 1 },
      { op = "endcallback" },
      { op = "setevent", event = 2 },
    },
  })
  vm:runCallback("cb")
  check(vm.events:get(1), "commands before endcallback run")
  check(not vm.events:get(2), "and nothing behind it does")
end

-- The case that made this a separate entry point from Vm:start.  A script is
-- parked on a text box; the map load underneath it runs a callback; the parked
-- script must still be parked, on the SAME request, and must resume where it
-- was.  Vm:start would have refused outright (`if self.busy then return
-- false`), which is what "nothing runs them yet" looked like from the inside.
do
  local resumeText
  local vm = vmWith({
    parent = {
      { op = "writetext", text = "A" },
      { op = "setevent", event = 20 },
      { op = "end" },
    },
    cb = { { op = "setevent", event = 21 }, { op = "endcallback" } },
  }, {
    showText = function(_, onDone) resumeText = onDone end,
  })
  vm:start("parent")
  check(vm:running(), "the parent script is up")
  check(vm.pending and vm.pending.kind == "text", "and parked on its text box")
  local parked = vm.pending
  check(vm:runCallback("cb"), "a callback runs with a script already parked")
  check(vm.events:get(21), "the callback's own command landed")
  check(not vm.events:get(20),
    "and the parent did NOT run on past the box it is waiting on")
  check(vm:running(), "the parent is still up")
  eq(vm.pending, parked, "parked on the very same request")
  resumeText()
  check(vm.events:get(20), "and resuming it picks up where it left off")
  check(not vm:running(), "then ends normally")
end

-- A callback cannot block: ScriptEvents runs inside the map load, with no frame
-- to come back on.  Nothing reachable from an extracted callback yields, so
-- this is a guard rather than a behaviour -- but if one ever does, the parent's
-- parked frame must survive it untouched.
do
  local vm = vmWith({
    parent = { { op = "writetext", text = "A" }, { op = "end" } },
    bad = { { op = "writetext", text = "B" }, { op = "endcallback" } },
  }, { showText = function() end })
  vm:start("parent")
  local parked = vm.pending
  check(not vm:runCallback("bad"), "a blocking callback reports failure")
  eq(vm.pending, parked, "and leaves the parent's request alone")
  check(vm:running(), "with the parent still running")
  eq(vm.blockedCallbacks["bad"], "text", "the ledger names what it blocked on")
end

-- ---------------------------------------------------------------------------
-- World:mapCallbackScript / World:runMapCallback
-- ---------------------------------------------------------------------------

local function callbackWorld(callbacks, scripts)
  local world = World.new({ data = {}, save = { party = {}, inventory = {} } })
  world.maps = {
    TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
      callbacks = callbacks },
  }
  world.map = { id = "TEST_MAP", def = world.maps.TEST_MAP,
    width = 2, height = 2 }
  world.map.blocks = world.maps.TEST_MAP.blocks
  world.scripts = scripts or {}
  -- Only the hooks these checks reach; World:load builds the real table.
  world.vm = Vm.new(world.scripts, {}, world.events, {
    changeBlock = function(bx, by, block)
      return world:changeBlock(bx, by, block)
    end,
    appear = function(id) world:appearObject(id) end,
    disappear = function(id) world:disappearObject(id) end,
  })
  return world
end

do
  local world = callbackWorld({
    { callback = "MAPCALLBACK_TILES", scriptKey = "first" },
    { callback = "MAPCALLBACK_TILES", scriptKey = "second" },
    { callback = "MAPCALLBACK_NEWMAP", scriptKey = "new" },
  }, {
    first = { { op = "setevent", event = 1 }, { op = "endcallback" } },
    second = { { op = "setevent", event = 2 }, { op = "endcallback" } },
    new = { { op = "setevent", event = 3 }, { op = "endcallback" } },
  })
  eq(world:mapCallbackScript("MAPCALLBACK_TILES"), "first",
    ".FindCallback takes the FIRST row of a type")
  eq(world:mapCallbackScript("MAPCALLBACK_NEWMAP"), "new",
    "and matches on the type, not on the order")
  check(world:mapCallbackScript("MAPCALLBACK_SPRITES") == nil,
    "a type this map has no row for is nil, not the next row along")
  check(world:runMapCallback("MAPCALLBACK_TILES"), "and it runs")
  check(world.events:get(1) and not world.events:get(2),
    "only the first row of the type")
  check(not world:runMapCallback("MAPCALLBACK_OBJECTS"),
    "a map with no callback of that type is a no-op, not an error")
end

-- A map with no callback list at all -- 284 of Gold's 368 maps -- must not
-- cost anything or throw.
do
  local world = callbackWorld(nil, {})
  check(world:mapCallbackScript("MAPCALLBACK_NEWMAP") == nil,
    "a map with no callbacks answers nil")
  check(not world:runMapCallback("MAPCALLBACK_NEWMAP"), "and runs nothing")
end

-- ---------------------------------------------------------------------------
-- The order inside a map load
-- ---------------------------------------------------------------------------

-- MapSetupScript_Warp reads HandleNewMap, LoadBlockData, LoadMapObjects, in
-- that order, and each of the three carries one callback.  setMap is a single
-- call here, so the order has to be asserted out loud.
do
  local world = callbackWorld({
    { callback = "MAPCALLBACK_OBJECTS", scriptKey = "objects" },
    { callback = "MAPCALLBACK_TILES", scriptKey = "tiles" },
    { callback = "MAPCALLBACK_NEWMAP", scriptKey = "newmap" },
  }, {
    newmap = { { op = "setevent", event = 1 }, { op = "endcallback" } },
    tiles = { { op = "changeblock", args = { 0, 0, 9 } },
      { op = "endcallback" } },
    objects = { { op = "setevent", event = 2 }, { op = "endcallback" } },
  })
  local order = {}
  local newMapCell
  world.tilesets = { TEST = {} }
  world.maps.TEST_MAP.tileset = "TEST"
  -- Stub out everything setMap does with love: the ORDER is the subject, and a
  -- headless suite has no canvas to bake into.
  local Map = require("src.world.gen2.Map")
  world.imageFor = function() order[#order + 1] = "bake" return true end
  world.rebuildNeighbors = function() end
  world.rebuildPeople = function() order[#order + 1] = "people" end
  world.applyPalettes = function() end
  world.noteFlypoint = function() end
  local realRun = World.runMapCallback
  world.runMapCallback = function(self, kind)
    order[#order + 1] = kind
    if kind == "MAPCALLBACK_NEWMAP" then
      newMapCell = self.player and (self.player.cellX .. "," .. self.player.cellY)
    end
    return realRun(self, kind)
  end
  world.map = Map.new(world.maps.TEST_MAP, {})
  check(world:setMap("TEST_MAP", 3, 3, "down"), "the map loads")
  eq(table.concat(order, " "),
    "MAPCALLBACK_NEWMAP MAPCALLBACK_TILES bake MAPCALLBACK_OBJECTS people",
    "HandleNewMap, then LoadBlockData, then LoadMapObjects")
  check(world.events:get(1) and world.events:get(2),
    "and both bodies really ran")
  eq(world.maps.TEST_MAP.blocks[1], 9,
    "the TILES callback's changeblock is in the buffer BEFORE the bake")
  -- data/maps/setup_scripts.asm:99-106: GetWarpDestCoords before HandleNewMap.
  eq(newMapCell, "3,3",
    "the NEWMAP callback reads the DESTINATION coords, not the map it left")
end

-- ---------------------------------------------------------------------------
-- Route16AlwaysOnBikeCallback
-- ---------------------------------------------------------------------------

-- maps/Route16.asm:7-17.  The callback is two coordinate tests and nothing
-- else: YCOORD < 5 or XCOORD > 13 takes .CanWalk, everything else `setflag
-- ENGINE_ALWAYS_ON_BIKE`.  It carries no `checkitem` -- the BICYCLE refusal is
-- the gatehouse's own coord event (maps/Route16Gate.asm:16-29, :69-70) -- so
-- both arms below run on a save with an empty PACK.
do
  local Bike = require("src.world.gen2.Bike")
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local Map = require("src.world.gen2.Map")

  local function route16At(cx, cy)
    local world = callbackWorld({
      { callback = "MAPCALLBACK_NEWMAP", scriptKey = "bike" },
    }, {
      -- The extracted body, opcode for opcode: VAR_YCOORD $13, VAR_XCOORD $12.
      bike = {
        { op = "readvar", var = 0x13 },
        { op = "ifless", value = 5, script = "walk" },
        { op = "readvar", var = 0x12 },
        { op = "ifgreater", value = 13, script = "walk" },
        { op = "setflag", flag = Bike.ENGINE_ALWAYS_ON_BIKE },
        { op = "endcallback" },
      },
      walk = {
        { op = "clearflag", flag = Bike.ENGINE_ALWAYS_ON_BIKE },
        { op = "endcallback" },
      },
    })
    world.maps.TEST_MAP.environment = "ROUTE"
    world.maps.TEST_MAP.width, world.maps.TEST_MAP.height = 10, 10
    world.tilesets = { TEST = {} }
    world.maps.TEST_MAP.tileset = "TEST"
    world.imageFor = function() return true end
    world.rebuildNeighbors = function() end
    world.rebuildPeople = function() end
    world.applyPalettes = function() end
    world.vm = Vm.new(world.scripts, {}, world.events, {
      readVar = function(id) return world:readVar(id) end,
      setEngineFlag = function(flag, value) world:setEngineFlag(flag, value) end,
    })
    world.map = Map.new(world.maps.TEST_MAP, {})
    check(world:setMap("TEST_MAP", cx, cy, "down"), "the map loads")
    return world
  end

  -- warp_event 9, 6 (maps/Route16.asm:36): the Cycling Road side of the gate.
  local road = route16At(9, 6)
  check(road:alwaysOnBike(),
    "arriving west of the gate sets ENGINE_ALWAYS_ON_BIKE")
  -- .CheckForcedBiking (engine/overworld/map_setup.asm:112-120) reads the flag
  -- and nothing else: no BICYCLE is consulted, on the cart or here.
  eq(road.playerState, FieldMoves.PLAYER_BIKE, "and the load mounts the bike")

  -- warp_event 14, 6 (maps/Route16.asm:34): the gatehouse doorway, one cell
  -- past the XCOORD test.  Read off the map being LEFT this is the road arm,
  -- which is the whole reason the coords are written before HandleNewMap.
  local gate = route16At(14, 6)
  check(not gate:alwaysOnBike(), "arriving at the gate doorway takes .CanWalk")
  eq(gate.playerState, FieldMoves.PLAYER_NORMAL, "and nothing mounts")

  -- The YCOORD arm, north of the fork: `ifless 5, .CanWalk` on its own.
  local north = route16At(9, 4)
  check(not north:alwaysOnBike(), "and so does anything north of YCOORD 5")
end

-- ---------------------------------------------------------------------------
-- The baked canvas has to follow the blocks
-- ---------------------------------------------------------------------------

do
  local world = callbackWorld(nil, {})
  world.mapImages = {
    ["TEST_MAP|DAY|gbc|1"] = "a", ["TEST_MAP|NITE|gbc|1"] = "b",
    ["OTHER_MAP|DAY|gbc|1"] = "c",
  }
  world:dropMapImages("TEST_MAP")
  check(world.mapImages["TEST_MAP|DAY|gbc|1"] == nil, "both bakes of the map")
  check(world.mapImages["TEST_MAP|NITE|gbc|1"] == nil, "go, daytime and all")
  eq(world.mapImages["OTHER_MAP|DAY|gbc|1"], "c",
    "and the neighbours' keep theirs -- only the edited map's are stale")

  -- restoreBlocks is LoadMapAttributes' refill.  Putting the blocks back
  -- without dropping the bake left a CUT tree cut for the session, and would
  -- have frozen every MAPCALLBACK_TILES map on whichever answer it baked first.
  world.blockEdits = { TEST_MAP = { [1] = 5 } }
  world.maps.TEST_MAP.blocks[1] = 99
  world.mapImages["TEST_MAP|DAY|gbc|1"] = "stale"
  check(world:restoreBlocks(), "restoreBlocks reports it restored something")
  eq(world.maps.TEST_MAP.blocks[1], 5, "the original block is back")
  check(world.mapImages["TEST_MAP|DAY|gbc|1"] == nil,
    "and the bake taken off the edited blocks went with it")
end

-- ---------------------------------------------------------------------------
-- readvar VAR_WEEKDAY
-- ---------------------------------------------------------------------------

-- GetWeekday reads wCurDay, SUNDAY 0 .. SATURDAY 6 -- the same numbering
-- os.date("%w") uses.  39 of the 40 readvar sites reachable from a callback are
-- this one, and every one of them was taking the SUNDAY arm.
do
  local world = callbackWorld(nil, {})
  world.clockDay = 2
  eq(world:weekday(), 2, "clockDay pins the day")
  world.clockDay = 9
  eq(world:weekday(), 2, "and wraps into the week")
  world.clockDay = nil
  local today = tonumber(os.date("%w")) or 0
  eq(world:weekday(), today, "unpinned, it is the host clock's day")
  check(world:weekday() >= 0 and world:weekday() <= 6, "in SUNDAY..SATURDAY")
end

-- ---------------------------------------------------------------------------
-- Every callback in a real cache
-- ---------------------------------------------------------------------------

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsPath = cache .. "/data/generated/maps.lua"
local mf = io.open(mapsPath, "r")
if not mf then
  check(true, "gold cache absent : fixture checks only (SKIP cache facts)")
  S.finish()
  return
end
mf:close()

local maps = assert(loadfile(mapsPath))()
local scripts = assert(loadfile(cache .. "/data/generated/scripts.lua"))()
local constants = assert(loadfile(cache .. "/data/generated/constants.lua"))()

local byType, rows = {}, {}
for id, def in pairs(maps) do
  for _, cb in ipairs(def.callbacks or {}) do
    byType[cb.callback] = (byType[cb.callback] or 0) + 1
    rows[#rows + 1] = { map = id, kind = cb.callback, key = cb.scriptKey }
  end
end
check(#rows > 0, "the cache carries map callbacks at all")
-- The census, so a re-import that loses a whole type fails here rather than by
-- a door quietly staying open.  MAPCALLBACK_SPRITES has no user in Gold.
eq(byType.MAPCALLBACK_NEWMAP, 39, "39 MAPCALLBACK_NEWMAP")
eq(byType.MAPCALLBACK_OBJECTS, 24, "24 MAPCALLBACK_OBJECTS")
eq(byType.MAPCALLBACK_TILES, 19, "19 MAPCALLBACK_TILES")
eq(byType.MAPCALLBACK_CMDQUEUE, 2, "2 MAPCALLBACK_CMDQUEUE")
check(byType.MAPCALLBACK_SPRITES == nil,
  "and no MAPCALLBACK_SPRITES, which no Gold map declares")

local missing = 0
for _, row in ipairs(rows) do
  if not (row.key and scripts[row.key]) then missing = missing + 1 end
end
eq(missing, 0, "every callback row names a body the cache carries")

-- Run all of them.  A callback is a script, and the one thing that must hold
-- for all 84 is that each completes inside the map load: no yield, no unknown
-- opcode, no bad byte.  The hooks are counters rather than a World, so this
-- checks the BODIES rather than the wiring -- the wiring is the order check
-- above and tests/drivers/gold_map_callbacks.lua.
do
  local blocks, appears, disappears = 0, 0, 0
  local vm = Vm.new(scripts, {}, Events.new(), {
    specialOrder = constants.specialOrder,
    specials = {},
    -- VAR_WEEKDAY, so the day-of-week arms are exercised rather than all
    -- taking SUNDAY the way an unanswered readvar makes them.
    readVar = function(id) return id == 0x0b and 2 or 0 end,
    changeBlock = function() blocks = blocks + 1 return true end,
    appear = function() appears = appears + 1 end,
    disappear = function() disappears = disappears + 1 end,
  })
  local ran = 0
  for _, row in ipairs(rows) do
    if vm:runCallback(row.key) then ran = ran + 1 end
  end
  eq(ran, #rows, "all " .. #rows .. " callback bodies run to completion")
  local blocked = {}
  for key in pairs(vm.blockedCallbacks) do blocked[#blocked + 1] = key end
  eq(#blocked, 0,
    "none of them blocks: " .. table.concat(blocked, ", "))
  local unknown = {}
  for op in pairs(vm.unknownOps) do unknown[#unknown + 1] = op end
  table.sort(unknown)
  eq(#unknown, 0,
    "and none reaches an unimplemented opcode: " .. table.concat(unknown, ", "))
  eq(#vm.badBytes, 0, "with no extractor `unknown` row inside one")
  check(blocks > 0, "the run really repainted blocks (" .. blocks .. ")")
  check(appears > 0 and disappears > 0,
    ("and moved objects (%d appear, %d disappear)"):format(appears, disappears))
end

-- The named ones, so the census above cannot pass on the wrong rows.
do
  local function kindOf(mapId, kind)
    for _, cb in ipairs((maps[mapId] or {}).callbacks or {}) do
      if cb.callback == kind then return scripts[cb.scriptKey] end
    end
    return nil
  end
  local function ops(body)
    local out = {}
    for _, c in ipairs(body or {}) do out[#out + 1] = c.op end
    return table.concat(out, ",")
  end

  -- NewBarkTownFlypointCallback: `setflag ENGINE_FLYPOINT_NEW_BARK` is the
  -- cart's own way of banking a fly point.
  check(ops(kindOf("NEW_BARK_TOWN", "MAPCALLBACK_NEWMAP")):find("setflag"),
    "New Bark's NEWMAP callback is the flypoint flag")
  -- Route31CheckMomCallCallback queues Mom's worried call, which is a whole
  -- phone conversation nothing could reach while the callbacks were dead.
  check(ops(kindOf("ROUTE_31", "MAPCALLBACK_NEWMAP"))
    :find("checkevent") ~= nil, "Route 31's NEWMAP callback checks the egg quest")
  -- BrunosRoomDoorsCallback: the entrance sealing behind you and the exit
  -- opening after the battle.  Both `iffalse`s jump FORWARD over their own
  -- changeblock into the next test, so both sit in the body itself rather than
  -- behind a branch -- which is why the whole callback is five commands.
  local bruno = kindOf("BRUNOS_ROOM", "MAPCALLBACK_TILES")
  local brunoBlocks = 0
  for _, c in ipairs(bruno or {}) do
    if c.op == "changeblock" then brunoBlocks = brunoBlocks + 1 end
  end
  eq(brunoBlocks, 2, "Bruno's room walls itself in with two changeblocks")
  check(ops(bruno):find("checkevent"),
    "and it opens on EVENT_BRUNOS_ROOM_ENTRANCE_CLOSED")
  -- GoldenrodUndergroundCheckDayOfWeekCallback: seven arms off VAR_WEEKDAY.
  check(ops(kindOf("GOLDENROD_UNDERGROUND", "MAPCALLBACK_OBJECTS"))
    :find("readvar"), "the Goldenrod underground reads the weekday")

  -- Route16AlwaysOnBikeCallback (maps/Route16.asm:7-17), read off the cache:
  -- VAR_YCOORD $13 then VAR_XCOORD $12, and no `checkitem` anywhere in it.
  local r16 = kindOf("ROUTE_16", "MAPCALLBACK_NEWMAP")
  eq(ops(r16), "readvar,ifless,readvar,ifgreater,setflag,endcallback",
    "Route 16's NEWMAP callback is the coordinate test")
  local vars = {}
  for _, c in ipairs(r16 or {}) do
    if c.op == "readvar" then vars[#vars + 1] = c.var end
  end
  eq(table.concat(vars, ","), "19,18", "VAR_YCOORD first, then VAR_XCOORD")
  -- Route17AlwaysOnBikeCallback (maps/Route17.asm:13-16): the sibling, with no
  -- coordinate test at all -- ALWAYS_ON_BIKE and DOWNHILL, unconditionally.
  eq(ops(kindOf("ROUTE_17", "MAPCALLBACK_NEWMAP")),
    "setflag,setflag,endcallback", "Route 17 forces the bike and the downhill")

  -- maps/Route16Gate.asm:69-70: the BICYCLE gate is the gatehouse's two coord
  -- events, which is what keeps a bikeless player off the road the callback
  -- above mounts unconditionally.
  local gateEvents = (maps.ROUTE_16_GATE or {}).coordEvents or {}
  eq(#gateEvents, 2, "the Route 16 gatehouse carries its two coord events")
  local checks = 0
  for _, ev in ipairs(gateEvents) do
    if ops(scripts[ev.scriptKey]):find("checkitem") then checks = checks + 1 end
  end
  eq(checks, 2, "and both are the checkitem BICYCLE refusal")
end

S.finish()

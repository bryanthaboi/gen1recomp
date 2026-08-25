-- The Cycling Road: the START poll the forced roll used to swallow (#1718) and
-- the ALWAYS_ON_BIKE flag SURF never saw (#1749).
--
--   luajit tests/gen2_cycling_road_test.lua
--
-- Route17AlwaysOnBikeCallback sets ENGINE_ALWAYS_ON_BIKE and ENGINE_DOWNHILL on
-- MAPCALLBACK_NEWMAP (maps/Route17.asm:13-16), and DOWNHILL is what makes
-- .GetDPad read an empty pad as DOWN: the player is stepping on every single
-- frame of that road.
--
-- #1718: the port gated START on "not moving", which on Route 17 is never --
-- stepBody lands the step and queues the next one inside the SAME tick.  The
-- cart refuses only on PLAYERMOVEMENT_CONTINUE; a QUEUED step answers
-- PLAYERMOVEMENT_FINISH (player_movement.asm:459-461), whose arm is `xor a /
-- ld c, a / ret` (events.asm:761-779), so CheckMenuOW still runs there
-- (events.asm:485-498).  That landing frame comes round once in eight, so the
-- other half of the fix is Game2's joypad latch (events.asm:193-199, :215-231);
-- it needs a real Input and is driven by
-- tests/drivers/gold_cycling_road_bug1718_1749_test.lua.
--
-- #1749: both surf entry points already refused on ctx.alwaysOnBike
-- (engine/events/overworld.asm:350-352, :513-515), but World:fieldContext never
-- set the field, so neither refusal was reachable.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 cycling road")
local check, eq = S.check, S.eq

local Bike = require("src.world.gen2.Bike")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Permissions = require("src.world.gen2.Permissions")
local Player = require("src.world.gen2.Player")
local World = require("src.world.gen2.World")

-- constants/collision_constants.asm
local COLL_LAND, COLL_WATER = 0x00, 0x29

check(Permissions.isLand(COLL_LAND), "COLL_FLOOR $00 is a LAND_TILE")
check(Permissions.isWater(COLL_WATER), "COLL_WATER $29 is a WATER_TILE")

-- ---- the gate: World:acceptsMenuInput, OWPlayerInput's preamble (#1718) ----
--
-- The shipped methods, over a world carrying only the fields they read.
local function gate(w)
  w.busy = World.busy
  w.playerCollision = World.playerCollision
  return World.acceptsMenuInput(w)
end

eq(gate({ player = { moving = false } }), true,
  "standing still: PLAYERMOVEMENT_FINISH, so CheckMenuOW runs")
eq(gate({ player = { moving = true }, stepFinished = false }),
  false, "mid-step: PLAYERMOVEMENT_CONTINUE, and OWPlayerInput returns")
eq(gate({ player = { moving = true }, stepFinished = true }),
  true, "the frame the step lands reads it again, whatever was queued on top")

-- stepFinished opens ONE arm and must not reach past it.
eq(gate({ player = { moving = true }, stepFinished = true, battleActive = true }),
  false, "a battle still refuses on the landing frame")
eq(gate({ player = { moving = true }, stepFinished = true, textbox = {} }),
  false, "an open text box still refuses on the landing frame")
eq(gate({ player = { moving = true }, stepFinished = true, mapSetup = {} }),
  false, "and so does a map setup script")
eq(gate({ player = { moving = true }, stepFinished = true, fieldMove = {} }),
  false, "and a field move's tail")
eq(gate({ player = { moving = false },
          vm = { running = function() return true end } }),
  false, "wScriptRunning refuses even standing still (events.asm:238-243)")

-- CheckStandingOnIce's carry, the arm that sits below the movement one.
do
  local COLL_ICE = 0x23
  check(Permissions.isIce(COLL_ICE), "COLL_ICE $23")
  local iced = {
    player = { moving = false, cellX = 1, cellY = 1 },
    stepFinished = true,
    turningDirection = "down",
    map = { cellCollision = function() return COLL_ICE end },
  }
  eq(gate(iced), false, "a latched slide on ice refuses")
  iced.turningDirection = nil
  eq(gate(iced), true, "and lets go once the latch clears")
end

-- ---- .GetDPad and .DoStep on a DOWNHILL map --------------------------------

eq(Bike.forcedDirection(nil, true), "down",
  "no direction held on the Cycling Road is a step DOWN")
eq(Bike.forcedDirection("up", true), "up", "a held direction still wins")
eq(Bike.forcedDirection(nil, false), nil, "and off the road, nothing")
eq(Bike.stepFrames(FieldMoves.PLAYER_BIKE, "down", true, Player.STEP_FRAMES), 8,
  "the roll is a STEP_BIKE cell: half a walk")
eq(Bike.stepFrames(FieldMoves.PLAYER_BIKE, "left", true, Player.STEP_FRAMES), 16,
  "and every other direction gets the walking duration back")

-- ---- the roll: 24 ticks of Route 17, #1718's premise -----------------------
--
-- One iteration of Game2's fixed step over a real Player.

local openRoad = {
  inBounds = function() return true end,
  isWalkable = function() return true end,
}

local function tick(w)
  -- Game2's fixed step asks first, with last tick's stepFinished still up.
  local accepts = gate(w)
  -- What the port asked before the fix, counted off the same run.
  local standing = not w.player.moving
  local p = w.player
  w.stepFinished = false
  w.stepFinished = p:update()
  if not p.moving then
    local dir = Bike.forcedDirection(nil, true)
    p.stepFrames = Bike.stepFrames(
      FieldMoves.PLAYER_BIKE, dir, true, Player.STEP_FRAMES)
    p:tryMove(dir, openRoad, nil)
  end
  return accepts, standing
end

do
  local w = { player = Player.new(9, 36, "down") }
  local polled, idle, gaps, run = {}, 0, 0, 0
  for n = 1, 24 do
    local accepts, standing = tick(w)
    if accepts then
      polled[#polled + 1] = n
      if run > gaps then gaps = run end
      run = 0
    else
      run = run + 1
    end
    if standing then idle = idle + 1 end
  end

  -- The direct proof of the premise.
  eq(idle, 1, "the forced roll leaves the player standing on tick 1 and never again")
  eq(w.player.moving, true, "and it is still rolling 24 ticks later")
  eq(w.player.cellY > 36, true, "having actually travelled down the road")

  eq(#polled, 3, "the landing frame comes round three times in 24 ticks")
  eq(table.concat(polled, ","), "1,10,18",
    "tick 1, then one poll per 8-frame bike step")
  eq(gaps, 8, "eight refused ticks between polls -- one press in eight lands")
end

-- ---- ALWAYS_ON_BIKE reaches the field-move context (#1749) -----------------
--
-- The bug is the wiring, so the flag comes through the shipped
-- World:alwaysOnBike -> World:engineFlag pair off a real save table.

local function surfMon()
  return { species = "LAPRAS", moves = { "SURF" } }
end

-- A road cell facing water: with the flag clear this ctx surfs.
local function fieldSelf(onBike, badge)
  local coll = {}
  local map = {
    width = 8, height = 8,
    def = { blocks = {}, environment = "ROUTE", tileset = "TILESET_KANTO" },
    cellCollision = function(_, cx, cy) return coll[cy * 16 + cx] or COLL_LAND end,
  }
  for i = 1, 64 do map.def.blocks[i] = 1 end
  -- water in the cell the player faces, land under their feet
  coll[36 * 16 + 10] = COLL_WATER
  local save = {
    party = { surfMon() },
    player = { badges = { FOG = badge ~= false or nil } },
    engineFlags = { [Bike.ENGINE_ALWAYS_ON_BIKE] = onBike or nil },
  }
  return {
    player = Player.new(9, 36, "right"),
    map = map,
    playerState = FieldMoves.PLAYER_BIKE,
    game = { save = save },
    engineFlags = World.engineFlags,
    engineFlag = World.engineFlag,
    alwaysOnBike = World.alwaysOnBike,
    blockIndexAt = World.blockIndexAt,
    escapeRopeTarget = function() return nil end,
    facingObject = function() return nil end,
    hour = function() return 12 end,
  }
end

eq(World.fieldContext(fieldSelf(true)).alwaysOnBike, true,
  "fieldContext carries ALWAYS_ON_BIKE onto the road")
eq(World.fieldContext(fieldSelf(false)).alwaysOnBike, false,
  "and reports it clear everywhere else")

do
  -- The ctx really is surfable, or the refusals below pass for the wrong reason.
  local ctx = World.fieldContext(fieldSelf(false), surfMon())
  eq(ctx.facing, "right", "facing the water")
  check(Permissions.isWater(ctx.facingColl), "and the faced cell is water")
  local menu = FieldMoves.surfFromMenu(ctx)
  eq(menu.ok, true, "flag clear: the PACK's SURF goes through")
  local ow = FieldMoves.trySurfOW(ctx)
  eq(ow.ok, true, "flag clear: the A press offers to SURF")
  eq(ow.ask, FieldMoves.TEXT.ASK_SURF, "with the usual prompt")
end

do
  local ctx = World.fieldContext(fieldSelf(true), surfMon())
  -- .FailSurf: MenuTextboxBackup on CantSurfText, so the menu refusal TALKS.
  local menu = FieldMoves.surfFromMenu(ctx)
  eq(menu.ok, false, "on the road the menu refuses")
  eq(menu.text, FieldMoves.TEXT.CANT_SURF, "with CantSurfText")
  -- TrySurfOW's arm is `.quit`: xor a, no script and no text at all.
  local ow = FieldMoves.trySurfOW(ctx)
  eq(ow.ok, false, "and the A press refuses")
  eq(ow.took, nil, "silently -- .quit queues no script")
  eq(ow.text, nil, "and prints nothing")
end

do
  -- CheckBadge runs ABOVE the ALWAYS_ON_BIKE test.
  local ctx = World.fieldContext(fieldSelf(true, false), surfMon())
  local menu = FieldMoves.surfFromMenu(ctx)
  eq(menu.text, FieldMoves.TEXT.BADGE_REQUIRED,
    "no FOGBADGE still outranks the road (engine/events/overworld.asm:347-352)")
end

-- ---- the real Route 17, when a cache is around -----------------------------
--
-- Pins the coordinates the driver walks to, so a map edit fails here instead
-- of parking a human at a wall.

local cache = os.getenv("GOLD_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsPath = cache .. "/data/generated/maps.lua"
local mf = io.open(mapsPath, "r")
if not mf then
  check(true, "gold cache absent : fixture checks only (SKIP cache facts)")
  S.finish()
  return
end
mf:close()

local Map = require("src.world.gen2.Map")
local maps = assert(loadfile(mapsPath))()
local tilesets = assert(loadfile(cache .. "/data/generated/tilesets.lua"))()
local scripts = assert(loadfile(cache .. "/data/generated/scripts.lua"))()

do
  local def = maps.ROUTE_17
  check(def ~= nil, "the cache carries ROUTE_17")
  local ops = {}
  for _, cb in ipairs(def.callbacks or {}) do
    if cb.callback == "MAPCALLBACK_NEWMAP" then
      for _, cmd in ipairs(scripts[cb.scriptKey] or {}) do
        ops[#ops + 1] = cmd.op
      end
    end
  end
  eq(table.concat(ops, ","), "setflag,setflag,endcallback",
    "Route17AlwaysOnBikeCallback is the two unconditional setflags")

  local map = Map.new(def, tilesets[def.tileset])
  -- The lane the driver rides: x=9 is road, x=10 is the water beside it, and
  -- the four bikers stand at (4,17) (16,32) (3,53) (6,80), well clear of it.
  for cy = 36, 48 do
    check(Permissions.isLand(map:cellCollision(9, cy)),
      "ROUTE_17 (9," .. cy .. ") is road")
    check(Permissions.isWater(map:cellCollision(10, cy)),
      "ROUTE_17 (10," .. cy .. ") is water")
  end
  for _, obj in ipairs(def.objects or {}) do
    check(not (obj.x == 9 and obj.y >= 34 and obj.y <= 50),
      "no object parked in the driver's lane")
  end
end

S.finish()

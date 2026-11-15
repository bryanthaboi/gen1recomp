-- Does the Gold bot route describe a world that actually exists?
--
--   luajit tests/gold_route_validate_test.lua
--
-- tests/drivers/gold/route.lua is hand-authored from the asm-walk documents,
-- which were themselves written by reading a pokegold checkout.  Two independent
-- transcriptions sit between the cart and this route, and every coordinate in it
-- is a chance for one of them to have slipped.  Finding that out four hours into
-- a run -- when the bot is stood in a doorway that is one cell left of where the
-- route says -- is the failure mode this test exists to prevent.  Everything it
-- checks costs milliseconds and is checked against the EXTRACTED CACHE, i.e.
-- against the same data the running bot will path over.
--
-- Checked per row: the op is known and carries the fields that op needs; the map
-- constant exists; a `warp` cell really is a warp and really leads to `to`; an
-- `edge` direction really is a connection to `to`; a `talk`/`battle` target
-- really has an object, bg event or warp on it; and every `expect` names a real
-- EVENT_*/ENGINE_* flag rather than a plausible-looking typo.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gold route validation")
local check, eq = S.check, S.eq

local route = dofile("tests/drivers/gold/route.lua")
local FlagIds = require("src.core.gen2.FlagIds")
local EventFlagOrder = require("tests.fixture_data.gen2_event_flag_order")
local names = { events = FlagIds.events({ eventFlagOrder = EventFlagOrder.gs }), engine = {} }
for _, name in pairs(require("src.save_convert.data.gen2_engine_flags").gs) do
  names.engine[name] = true
end

check(#route > 0, "the route has rows at all")

-- ---------------------------------------------------------------------------
-- Shape checks : no cache needed
-- ---------------------------------------------------------------------------

local REQUIRED = {
  travel = {},
  walk   = { "x", "y" },
  warp   = { "x", "y", "to" },
  edge   = { "dir", "to" },
  talk   = { "x", "y" },
  battle = {},                 -- x/y optional: a `talk` battle names its NPC,
                               -- a sight-line one names the cell to walk onto
  grind  = { "level" },
  heal   = {},
  teach  = { "move" },
  field  = { "move", "x", "y" },
  settle = {},
  catch  = { "species" },
  manual = { "why" },
  check  = { "expect" },
  -- `wander` walks about on one map waiting for something to be DELIVERED (a
  -- phone call), so it names no coordinate and its oracle may be a flag being
  -- cleared rather than set.
  wander = {},
  -- `push` names the boulder's cell and which way to shove it; `press` is a
  -- raw direction list for an ice floor, where no cell can be aimed at.
  push   = { "x", "y", "dir" },
  press  = { "dirs" },
  -- `buy` names a Mart's map and what to take off the shelf; the price and the
  -- money check are the engine's.
  buy    = { "item" },
  -- `elevator` reads the panel at (x, y), picks `floor` off the scrolling
  -- menu, and leaves through the door at (doorX, doorY); `to` is the floor
  -- the door must land on.
  elevator = { "x", "y", "floor", "doorX", "doorY", "to" },
}

local seenIds = {}
local badShape = 0
for i, row in ipairs(route) do
  local where = ("row %d (%s)"):format(i, tostring(row.id))
  if not row.id then
    badShape = badShape + 1
    print("  " .. where .. ": missing id")
  elseif seenIds[row.id] then
    badShape = badShape + 1
    print("  " .. where .. ": duplicate id")
  end
  seenIds[row.id or i] = true

  local spec = REQUIRED[row.op]
  if not spec then
    badShape = badShape + 1
    print(("  %s: unknown op %q"):format(where, tostring(row.op)))
  else
    for _, field in ipairs(spec) do
      if row[field] == nil then
        badShape = badShape + 1
        print(("  %s: op %s needs %s"):format(where, row.op, field))
      end
    end
  end
  if not row.map then
    badShape = badShape + 1
    print("  " .. where .. ": missing map")
  end
  for _, field in ipairs({ "expect", "expectClear" }) do
    local name = row[field]
    if name and not (names.events[name] or names.engine[name]) then
      badShape = badShape + 1
      print(("  %s: %s %q is not a known EVENT_*/ENGINE_* name")
        :format(where, field, tostring(name)))
    end
  end
end
eq(badShape, 0, "every row is well-formed and every expect names a real flag")

-- ---------------------------------------------------------------------------
-- Geometry checks : need a Gold cache
-- ---------------------------------------------------------------------------

local cache = os.getenv("GOLD_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsPath = cache .. "/data/generated/maps.lua"
local mf = io.open(mapsPath, "r")
if not mf then
  check(true, "gold cache absent : shape checked, geometry SKIPPED")
  S.finish()
  return
end
mf:close()

local maps = assert(loadfile(mapsPath))()

-- Extracted connections are keyed by compass word; the route writes some rows
-- with the walk direction instead, because that is how the asm-walk phrases
-- them ("walk north out of the map").  Accept both spellings rather than make
-- the route remember which map used which.
local DIR_ALIAS = {
  up = "north", down = "south", left = "west", right = "east",
  north = "north", south = "south", west = "west", east = "east",
}

local function connectionOf(def, dir)
  local conns = def.connections or {}
  local want = DIR_ALIAS[dir] or dir
  for key, conn in pairs(conns) do
    local norm = DIR_ALIAS[key] or key
    if norm == want then return conn end
  end
  return nil
end

local function warpAt(def, x, y)
  for i, w in ipairs(def.warps or {}) do
    if w.x == x and w.y == y then return w, i end
  end
  return nil
end

-- Anything a `talk` can legitimately aim at: an NPC/item-ball object, a sign or
-- hidden item, or -- for the handful of rows that talk to something standing on
-- a door -- a warp.
local function targetAt(def, x, y)
  for _, o in ipairs(def.objects or {}) do
    if o.x == x and o.y == y then return "object" end
  end
  for _, b in ipairs(def.bgEvents or {}) do
    if b.x == x and b.y == y then return "bg" end
  end
  if warpAt(def, x, y) then return "warp" end
  return nil
end

local problems = 0
local function bad(row, msg)
  problems = problems + 1
  print(("  %s [%s %s]: %s")
    :format(tostring(row.id), row.op, tostring(row.map), msg))
end

for _, row in ipairs(route) do
  local def = maps[row.map]
  if not def then
    bad(row, "no such map in the cache")
  else
    -- Every explicit cell must be inside the map.  Cells are 2x the block
    -- dimensions (src/world/gen2/Map.lua).
    if row.x and row.y then
      local w, h = def.width * 2, def.height * 2
      if row.x < 0 or row.y < 0 or row.x >= w or row.y >= h then
        bad(row, ("(%d,%d) is outside the %dx%d cell grid")
          :format(row.x, row.y, w, h))
      end
    end

    if row.op == "warp" then
      local warp = warpAt(def, row.x, row.y)
      if not warp then
        bad(row, ("no warp at (%d,%d)"):format(row.x, row.y))
      elseif warp.destMap ~= row.to then
        bad(row, ("warp at (%d,%d) leads to %s, route says %s")
          :format(row.x, row.y, tostring(warp.destMap), tostring(row.to)))
      end

    elseif row.op == "edge" then
      local conn = connectionOf(def, row.dir)
      if not conn then
        bad(row, ("no %s connection"):format(tostring(row.dir)))
      elseif conn.mapId ~= row.to then
        bad(row, ("%s connection leads to %s, route says %s")
          :format(tostring(row.dir), tostring(conn.mapId), tostring(row.to)))
      end

    elseif row.op == "talk" or (row.op == "battle" and row.talk) then
      if not targetAt(def, row.x, row.y) then
        bad(row, ("nothing to talk to at (%d,%d)"):format(row.x, row.y))
      end
    end
  end
end

eq(problems, 0, "every route coordinate matches the extracted cache")

-- A route that reached the last badge but never named the map it happens on is
-- a route that quietly stopped short.
local sawOlivineGym = false
for _, row in ipairs(route) do
  if row.map == "OLIVINE_GYM" then sawOlivineGym = true end
end
check(sawOlivineGym, "the route reaches OLIVINE_GYM")

S.finish()

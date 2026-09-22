package.path = "./?.lua;./?/init.lua;" .. package.path
require("src.core.GameVersion").set("firered")
local Cache = require("tests.game3_cache")
assert(Cache.mount("scripts/events.lua", { native = true }), Cache.reason)
local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Map = require("src.core.game3.map")
local Runtime = require("src.core.game3.runtime")
local Field = require("src.core.game3.field")
local Ghosts = require("src.core.game3.ghosts")
local Objects = require("src.core.game3.objects")
local Space = require("src.core.game3.scripting.space")
local game = { data = {}, save = {}, session = { flags = {}, vars = {} } }
Dataset.hydrate(game)
local Behaviors = require("src.core.game3.scripting.interaction_scripts").behaviors
Runtime.session = game.session
Field._game, Field._session, Field.running = game, game.session, true
Space.runEnterScripts = function() end
Space.vm = nil
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end
local function setup(map, x, y, dir, surfing)
  Ghosts.clear()
  Map.load(nil, game, map, { x = x, y = y, facing = dir })
  game.session = Runtime.getSession()
  game.session.x, game.session.y = Player.cellX, Player.cellY
  Field.locked = false
  Player.surfing, Player.elevation = surfing, surfing and 1 or 3
end
local function finishStep()
  Player._onStepDone = function() end
  for _ = 1, 32 do
    if not Player.moving then break end
    Player.tick(game)
  end
end
local routes = {
  { "FR_PALLET_TOWN", 9, 19, "down", "FR_ROUTE_21_NORTH", 9, 0 },
  { "FR_ROUTE_21_NORTH", 9, 0, "up", "FR_PALLET_TOWN", 9, 19 },
  { "FR_ROUTE_19", 0, 49, "left", "FR_ROUTE_20", 119, 9 },
  { "FR_ROUTE_20", 119, 9, "right", "FR_ROUTE_19", 0, 49 },
}
for _, r in ipairs(routes) do
  setup(r[1], r[2], r[3], r[4], true)
  local status = Player.tryMove(r[4], game, false)
  check(status == "connection", "surf_crosses_" .. r[1] .. "_to_" .. r[5])
  finishStep()
  check(Map.current == r[5] and Player.cellX == r[6] and Player.cellY == r[7]
    and Player.surfing and Player.elevation == 1 and not Player.dismounting
    and game.session.map == r[5] and game.session.x == r[6] and game.session.y == r[7]
    and game.save.position.map == r[5] and game.save.position.x == r[6]
    and game.save.position.y == r[7], "surf_landing_state_" .. r[5])
end

local function def(coll, elevation, behavior)
  local layout = { width = 2, height = 2, pair = "surf_test", _coll = coll, _elev = elevation, _mid = behavior }
  function layout:collAt() return self._coll end
  function layout:elevAt() return self._elev end
  function layout:midAt() return self._mid end
  function layout:collArray() return { self._coll, self._coll, self._coll, self._coll } end
  return { width = 2, height = 2, midLayout = layout, pair = "surf_test", objects = {}, warps = {}, connections = {} }
end
Behaviors.surf_test = setmetatable({}, { __index = function(_, mid) return mid end })
local source, dest = def(0x29, 1, 0x15), def(0x29, 1, 0x15)
source.connections.south = { map = "FR_SURF_TEST_DEST", offset = 0 }
game.data.maps.FR_SURF_TEST_SOURCE, game.data.maps.FR_SURF_TEST_DEST = source, dest
local function synthetic(surfing)
  dest.midLayout._coll, dest.midLayout._elev, dest.midLayout._mid = 0x29, 1, 0x15
  source.midLayout._coll, source.midLayout._elev, source.midLayout._mid = 0x29, 1, 0x15
  dest.objects = {}
  setup("FR_SURF_TEST_SOURCE", 0, 1, "down", surfing ~= false)
end
local function refuse(label)
  local oldMap, oldX, oldY, oldElev, oldSurf = Map.current, Player.cellX, Player.cellY, Player.elevation, Player.surfing
  local saveMap, saveX, saveY = game.save.position.map, game.save.position.x, game.save.position.y
  check(Player.tryMove("down", game, false) == "blocked"
    and Map.current == oldMap and Player.cellX == oldX and Player.cellY == oldY
    and Player.elevation == oldElev and Player.surfing == oldSurf and not Player.moving
    and game.session.map == oldMap and game.session.x == oldX and game.session.y == oldY
    and game.save.position.map == saveMap and game.save.position.x == saveX and game.save.position.y == saveY,
    label)
end
synthetic(false); refuse("foot_cannot_cross_into_water")
for _, coll in ipairs({ 0x07, 0xff, 0xA0, 0xA2 }) do
  synthetic(); dest.midLayout._coll = coll
  refuse("surf_rejects_solid_or_ledge_" .. coll)
end
synthetic(); source.midLayout._mid = 0x33; refuse("source_leave_direction_blocks_seam")
synthetic(); dest.midLayout._mid = 0x32; refuse("destination_enter_direction_blocks_seam")
synthetic(); dest.midLayout._elev = 4; refuse("water_elevation_mismatch_blocks_seam")
synthetic(); dest.midLayout._coll, dest.midLayout._elev, dest.midLayout._mid = 0, 4, 0
refuse("surf_cannot_dismount_at_wrong_elevation")
for _, moving in ipairs({ false, true }) do
  synthetic()
  local pool = Objects.spawnFromDefs({ { localId = 1, x = moving and 1 or 0, y = 0 } }, dest)
  pool.byId[1].moving, pool.byId[1].targetX, pool.byId[1].targetY = moving, 0, 0
  Ghosts._pools.FR_SURF_TEST_DEST = pool
  refuse(moving and "inflight_neighbor_occupancy_blocks_seam" or "current_neighbor_occupancy_blocks_seam")
end
synthetic()
Ghosts._pools.FR_SURF_TEST_DEST = nil
dest.objects = { { localId = 1, x = 0, y = 0 } }
refuse("unloaded_neighbor_template_blocks_seam")
for _, state in ipairs({ "hidden", "passable", "invisible" }) do
  synthetic()
  local pool = Objects.spawnFromDefs({ { localId = 1, x = 0, y = 0 } }, dest)
  if state == "invisible" then pool.byId[1].visible = false else pool.byId[1][state] = true end
  Ghosts._pools.FR_SURF_TEST_DEST = pool
  check(Player.tryMove("down", game, false) == "connection", state .. "_neighbor_does_not_block")
  finishStep()
end
for _, behavior in ipairs({ 0x16, 0x17 }) do
  synthetic(); dest.midLayout._coll, dest.midLayout._mid = 0, behavior
  check(Player.tryMove("down", game, false) == "connection", "elevation1_shallow_water_seam_" .. behavior)
  finishStep()
  check(Player.surfing and Player.elevation == 1, "shallow_water_retains_surf_" .. behavior)
end
synthetic(); dest.midLayout._coll, dest.midLayout._elev, dest.midLayout._mid = 0, 3, 0
check(Player.tryMove("down", game, false) == "connection" and Player.dismounting
  and Player.surfing and Player.elevation == 1, "dismount_seam_preserves_inflight_surf_and_elevation")
finishStep()
check(not Player.surfing and not Player.dismounting and Player.elevation == 3,
  "dismount_seam_finishes_on_land")
synthetic(false); dest.midLayout._coll, dest.midLayout._elev, dest.midLayout._mid = 0, 3, 0
check(Player.tryMove("down", game, false) == "connection", "ordinary_land_connection_still_works")
finishStep()
check(not Player.surfing, "ordinary_land_connection_does_not_enable_surf")
os.exit(failures == 0 and 0 or 1)

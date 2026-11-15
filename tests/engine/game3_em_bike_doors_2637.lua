package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
require("src.core.GameVersion").set("emerald")
local session = { version = "emerald", map = "EM_TEST", party = {}, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end, uiBusy = function() return false end,
}
package.loaded["src.core.game3.audio"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["src.core.game3.step_events"] = { onStepTaken = function() end }
package.loaded["src.core.game3.encounters"] = { onStep = function() end }
local entered, exit
package.loaded["src.core.game3.warp"] = {
  isBusy = function() return entered ~= nil or exit ~= nil end,
  startDoorEntrance = function(_, _, dest) entered = dest end,
  startDoorExit = function(_, _, dest) exit = dest end,
}
package.loaded["src.core.game3.doors"] = {
  getDoorEntryAt = function(_, x, y) if x == 3 and y == 2 then return {} end end,
}
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Bike = require("src.core.game3.bike")
local MB = require("src.core.game3.mb")
local Layout = require("src.core.game3.layout_native")
local cells = {}
for i = 1, 49 do cells[i] = { mid = 0, coll = 0, elev = 3 } end
-- pokeemerald/src/event_object_movement.c:4663
cells[2 * 7 + 3 + 1] = { mid = 1, coll = 7, elev = 0 }
local map = { kind = "town", pair = "test", midLayout = Layout.fromDecoded({ width = 7, height = 7, cells = cells }, "EM_TEST", "test"),
  warps = { { x = 3, y = 2, destMap = "EM_CENTER", destX = 3, destY = 7 } } }
local game = { data = { maps = { EM_TEST = map, EM_CENTER = { kind = "indoor" } } } }
require("src.core.game3.scripting.interaction_scripts").behaviors.test = { [0] = MB.require("NORMAL"), [1] = MB.require("WARP_DOOR") }
Field._game, Field._session, Field.locked = game, session, false
local function input(dir, b)
  return { isDown = function(_, k) return k == dir or (k == "b" and b == true) end,
    wasPressed = function() return false end }
end
local function reset(kind, x, y, facing)
  entered, exit = nil, nil
  Collision.bindMap(game, "EM_TEST", map)
  Player.reset(x, y, facing)
  Player.biking, Player.bikeType = false, nil
  Bike.rse(session).getOnOff(kind, session)
end
local function step(dir)
  Player.update(game, input(dir))
  while Player.moving do Player.tick(game) end
end
T.check(Bike.rse({ version = "firered" }) == nil, "FRLG bicycle controller preserved")
for _, kind in ipairs({ "mach", "acro" }) do
  reset(kind, 2, 3, "right")
  step("right")
  T.eq(Player.cellX, 3, kind .. " moving approach reached south of door")
  Player.update(game, input("up"))
  T.check(not Player.moving, kind .. " changed heading cannot enter unclaimed solid door")
  T.eq(Player.cellY, 3, kind .. " stays south of door")
  T.eq(entered, nil, kind .. " changed heading does not bypass facing gate")
  while Player.action do Player.tick(game) end
  Player.update(game, input("up"))
  T.eq(entered, "EM_CENTER", kind .. " next north input dispatches actual Player door trigger")
  reset(kind, 3, 3, "up")
  Player.update(game, input("up"))
  T.eq(entered, "EM_CENTER", kind .. " straight approach dispatches door")
  reset(kind, 2, 2, "right")
  Player.update(game, input("right"))
  T.check(not Player.moving, kind .. " side approach cannot occupy animated door")
end
reset("acro", 2, 3, "right")
step("right")
Player.update(game, input("up", true))
T.check(not Player.moving and Player.cellY == 3, "Acro wheelie transition cannot bypass animated door collision")
reset("acro", 3, 3, "up")
Player.update(game, input("up", true))
T.eq(entered, "EM_CENTER", "Acro B-held straight approach preserves door trigger")
reset("mach", 3, 5, "up")
step("up")
step("up")
Player.update(game, input(nil))
T.check(not Player.moving, "Mach coast cannot occupy solid animated door")
T.eq(entered, nil, "Mach release does not open door without held input")
while Player.action do Player.tick(game) end
Player.update(game, input("up"))
T.eq(entered, "EM_CENTER", "Mach held north enters after coast collision")
local exitCells = {}
for i = 1, 49 do exitCells[i] = { mid = 0, coll = 0, elev = 3 } end
exitCells[2 * 7 + 3 + 1] = { mid = 2, coll = 0, elev = 3 }
require("src.core.game3.scripting.interaction_scripts").behaviors.test[2] = MB.require("SOUTH_ARROW_WARP")
local exitMap = { kind = "indoor", pair = "test",
  midLayout = Layout.fromDecoded({ width = 7, height = 7, cells = exitCells }, "EM_TEST_EXIT", "test"),
  warps = { { x = 3, y = 2, destMap = "EM_TEST", destX = 3, destY = 2 } } }
game.data.maps.EM_CENTER = exitMap
for _, kind in ipairs({ "mach", "acro" }) do
  reset(kind, 3, 2, "down")
  Collision.bindMap(game, "EM_CENTER", exitMap)
  Player.update(game, input("down"))
  T.eq(exit, "EM_TEST", kind .. " exit mat dispatch preserved")
end
T.finish("game3_em_bike_doors_2637")

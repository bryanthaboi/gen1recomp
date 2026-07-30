-- Regression: the first completed step after a warp still checks for a warp
-- under the player's feet (#265).  home/overworld.asm:391 CheckWarpsNoCollision
-- runs on EVERY completed step with no first-step-after-a-warp counter, so the
-- arrival disable is POSITIONAL (the cell you came in on is inert until you
-- leave it), which is what warpEntryCell models.  The two STAND-STILL triggers
-- answer to BIT_STANDING_ON_WARP instead, which the departing tile decides and
-- the warp carries over: cleared by a staircase (#230), kept by a door tile so
-- an exit mat works on the tile you land on (#378).  Both are asserted here.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.SEAFOAM_ISLANDS_B3F) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local MapLoader = require("src.world.MapLoader")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local Warp = require("src.world.Warp")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity warp after warp step")
local check, eq = S.check, S.eq

-- ---- ground truth: two ladders one cell apart ----------------------------
local b3 = MapLoader.load(Data, "SEAFOAM_ISLANDS_B3F")
eq(b3:cellTile(25, 3), 0x1A, "B3F (25,3) is a CAVERN ladder tile")
eq(b3:cellTile(25, 4), 0x18, "B3F (25,4) is the other CAVERN ladder tile")
local up = Warp.onArrive(b3, 25, 3)
local down = Warp.onArrive(b3, 25, 4)
check(up ~= nil, "(25,3) carries a warp")
check(down ~= nil, "(25,4) carries a warp")
eq(up and up.def.destMap, "SEAFOAM_ISLANDS_B2F", "(25,3) climbs back to B2F")
eq(down and down.def.destMap, "SEAFOAM_ISLANDS_B4F", "(25,4) drops to B4F")

local reds2 = MapLoader.load(Data, "REDS_HOUSE_2F")
eq(reds2:cellTile(7, 1), 0x1A, "REDS_HOUSE_2F (7,1) is the staircase warp tile")
eq(reds2.def.width * 2, 8, "REDS_HOUSE_2F is 8 cells wide, so x=7 is the east edge")

-- ---- live engine ---------------------------------------------------------
Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

-- Reproduce a warp ARRIVAL without running the fade: startWarpTo sets exactly
-- these two fields once setMap has placed the player (OverworldController.lua,
-- inside the Transition callback).  takeWarp is stubbed per instance so the
-- assertion is which warp the engine decided to take, with no Transition to pump.
local function arriveOn(mapId, x, y, facing, standingOnWarp)
  Input:reset()
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, x, y, facing or "down")
  local ow = Game.stack:top()
  ow.player.moving = false
  ow.player.turnTimer = 0
  ow.warpEntryCell = { x = x, y = y }
  -- BIT_STANDING_ON_WARP is whatever the tile we LEFT made it: a door tile
  -- leaves it set, a stair/ladder tile clears it, and the map change does not
  -- touch wMovementFlags.
  ow.standingOnWarp = standingOnWarp and true or false
  ow.taken = nil
  ow.takeWarp = function(self, def) self.taken = def end
  return ow
end

-- Walk one cell the way Player:update would leave things, then run the
-- completed-step handler.
local function stepTo(ow, x, y, facing)
  local p = ow.player
  p.facing = facing or p.facing
  p.cellX, p.cellY = x, y
  p.px, p.py = x * 16, y * 16
  p.moving = false
  ow:onStepComplete()
end

-- The reported case: down the B2F ladder onto (25,3), then one press of DOWN
-- onto the adjacent ladder at (25,4).
do
  local ow = arriveOn("SEAFOAM_ISLANDS_B3F", 25, 3, "down")
  check(ow.warpEntryCell ~= nil, "the cell just arrived on is inert")
  stepTo(ow, 25, 4, "down")
  check(ow.taken ~= nil, "the step onto (25,4) fires a warp")
  eq(ow.taken and ow.taken.destMap, "SEAFOAM_ISLANDS_B4F",
     "and it is the ladder down to B4F")
  check(ow.warpEntryCell == nil, "the arrival record is cleared by that step")
end

-- The arrival cell stays inert while you stand on it, even if a scripted nudge
-- re-runs the step handler there.  That is warpEntryCell's job.
do
  local ow = arriveOn("SEAFOAM_ISLANDS_B3F", 25, 3, "down")
  stepTo(ow, 25, 3, "down")
  check(ow.taken == nil, "standing on the arrival ladder does not re-fire it")
  eq(ow.warpEntryCell and ow.warpEntryCell.x, 25, "the entry cell is remembered")
  eq(ow.warpEntryCell and ow.warpEntryCell.y, 3, "at the arrival row")
end

-- Once you have left it, that cell is live again (a real second visit).
do
  local ow = arriveOn("SEAFOAM_ISLANDS_B3F", 25, 3, "down")
  stepTo(ow, 25, 2, "up")
  check(ow.taken == nil, "stepping onto a plain floor cell warps nowhere")
  check(ow.warpEntryCell == nil, "leaving clears the entry record")
  stepTo(ow, 25, 3, "down")
  check(ow.taken ~= nil, "coming back onto the ladder now takes it")
  eq(ow.taken and ow.taken.destMap, "SEAFOAM_ISLANDS_B2F", "back up to B2F")
end

-- #230 must not come back: the staircase tile ($1A/$1C, a warp tile that is
-- not a door tile) clears BIT_STANDING_ON_WARP on the step that takes it, so
-- the two STAND-STILL triggers stay shut on arrival.  Red's house 2F staircase
-- is on the map's east edge, so pushing into that edge has to bonk, not bounce.
do
  local ow = arriveOn("REDS_HOUSE_2F", 7, 1, "down", false)
  check(ow:canCollisionWarp() == false,
        "the staircase arrival leaves BIT_STANDING_ON_WARP clear")
  check(ow:checkEdgeExit("right") == false,
        "pushing east off the map edge from it does not warp (#230)")
  Input.state.right = true
  Input.pressed = {}
  for _ = 1, 30 do
    ow.player.turnTimer = 0
    ow:handleInput()
    ow.player:update()
  end
  check(ow.taken == nil, "holding RIGHT into the edge never fires the staircase")
  eq(ow.player.cellX, 7, "and the player has not moved")
  eq(ow.player.cellY, 1, "in either axis")
  Input:reset()

  -- the same from the blocked-step path: north of (7,1) is solid wall
  Input.state.up = true
  Input.pressed = {}
  for _ = 1, 30 do
    ow.player.turnTimer = 0
    ow:handleInput()
    ow.player:update()
  end
  check(ow.taken == nil, "bonking the wall from the arrival cell does not warp")
  Input:reset()
end

-- #378: the exit mat you warped IN on is NOT inert for the collision paths.
-- REDS_HOUSE_1F's mat (2,7) is tile $14 -- neither a door tile nor a warp tile,
-- so nothing clears the flag that Pallet Town's door tile ($1B, a door tile)
-- set on the way in, and the first press of DOWN walks straight back outside.
do
  local reds1 = MapLoader.load(Data, "REDS_HOUSE_1F")
  eq(reds1:cellTile(2, 7), 0x14, "REDS_HOUSE_1F (2,7) is the exit mat tile")
  check(not reds1:isWarpTileCell(2, 7), "the mat is not a warp-activating tile")
  eq(reds1.def.height * 2, 8,
     "REDS_HOUSE_1F is 8 cells tall, so y=7 is the south edge")

  local ow = arriveOn("REDS_HOUSE_1F", 2, 7, "down", true)
  check(ow:checkEdgeExit("down") == true,
        "pressing DOWN on the mat just arrived on exits the house (#378)")
  eq(ow.taken and ow.taken.destMap, "LAST_MAP", "back out the way we came")
end

S.finish()

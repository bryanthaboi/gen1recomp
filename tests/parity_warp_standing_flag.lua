-- Regression: BIT_STANDING_ON_WARP is decided by the tile you LEAVE and is
-- carried across the warp, so the exit mat you land on works on that same tile
-- (#378).  ClearVariablesOnEnterMap (engine/overworld/clear_variables.asm)
-- never touches wMovementFlags, and IsPlayerStandingOnDoorTileOrWarpTile
-- (engine/overworld/player_state.asm) only clears the bit for a
-- warp-activating tile that is NOT a door tile -- which is why a house door
-- ($1B) leaves it set for the mat inside and a staircase ($1A/$1C) clears it
-- (#230).  This file pins the flag itself: how it is derived, that a map
-- change preserves it, and what each of the two collision paths then does.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.REDS_HOUSE_1F) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local MapLoader = require("src.world.MapLoader")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity warp standing flag")
local check, eq = S.check, S.eq

-- ---- ground truth: the three tiles that decide the flag -------------------
-- data/tilesets/door_tile_ids.asm .OverworldDoorTileIDs lists $1B; REDS_HOUSE_1
-- has no door entry and .RedsHouse1WarpTileIDs is $1A/$1C; POKECENTER has
-- neither list.  pokered data/maps/objects/{PalletTown,RedsHouse1F,
-- ViridianPokecenter}.asm give the warp cells.
local pallet = MapLoader.load(Data, "PALLET_TOWN")
eq(pallet:cellTile(5, 5), 0x1B, "Red's front door in Pallet Town is tile $1B")
check(pallet:isDoorTileCell(5, 5), "$1B is a door tile, so the flag stays set")
local doorWarp = pallet:warpAtCell(5, 5)
eq(doorWarp and doorWarp.def.destMap, "REDS_HOUSE_1F", "and it leads inside")

local reds1 = MapLoader.load(Data, "REDS_HOUSE_1F")
eq(reds1:cellTile(2, 7), 0x14, "the exit mat inside is tile $14")
check(reds1:warpAtCell(2, 7) ~= nil, "the mat cell carries a warp entry")
check(not reds1:isWarpTileCell(2, 7),
      "but it is neither a door nor a warp-activating tile, so nothing clears")
eq(reds1.heightCells, 8, "the map is 8 cells tall, so the mat row is the edge")
check(reds1:isWarpTileCell(7, 1) and not reds1:isDoorTileCell(7, 1),
      "the staircase at (7,1) is a warp tile and not a door tile")

local center = MapLoader.load(Data, "VIRIDIAN_POKECENTER")
eq(center:cellTile(3, 7), 0x1C, "the Poke Center mat is tile $1C")
check(center:warpAtCell(3, 7) ~= nil, "the mat cell carries a warp entry")
check(not center:isWarpTileCell(3, 7),
      "POKECENTER lists no warp tiles, so $1C does not clear the flag here")
eq(center.heightCells, 8, "and its mat row is the south edge too")

-- ---- live engine ---------------------------------------------------------
Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

-- Boot the overworld somewhere with no fade to pump.  takeWarp is stubbed per
-- boot so the assertion is which warp the engine decided to take.
local function bootOn(mapId, x, y, facing)
  Input:reset()
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, x, y, facing or "down")
  local ow = Game.stack:top()
  ow.player.moving = false
  ow.player.turnTimer = 0
  ow.taken = nil
  ow.takeWarp = function(self, def) self.taken = def end
  return ow
end

-- A loaded save standing on the mat can still walk out: enter() re-derives the
-- flag the way MapEntryAfterBattle's IsPlayerStandingOnWarp does.
do
  local ow = bootOn("REDS_HOUSE_1F", 2, 7, "down")
  check(ow:canCollisionWarp(), "a save loaded on the mat has the flag set")
  check(ow:checkEdgeExit("down"), "so DOWN on the mat leaves the house")
  eq(ow.taken and ow.taken.destMap, "LAST_MAP", "out to the map we came from")
end

-- The same derivation on a staircase clears it, so a save loaded upstairs
-- cannot be bounced back down by pushing into the east edge (#230).
do
  local ow = bootOn("REDS_HOUSE_2F", 7, 1, "down")
  check(ow:canCollisionWarp() == false,
        "a save loaded on the staircase has the flag clear")
  check(ow:checkEdgeExit("right") == false, "pushing east off the edge bonks")
  check(ow.taken == nil, "and takes no warp")
end

-- The whole of #378: walk onto the door tile outside, warp in, and the flag the
-- door set is still there on the mat.  setMap is the map change startWarpTo
-- performs, and it must leave the flag alone.
do
  local ow = bootOn("PALLET_TOWN", 5, 6, "up")
  check(ow:canCollisionWarp() == false, "the grass south of the door is inert")
  local p = ow.player
  p.cellX, p.cellY, p.facing = 5, 5, "up"
  p.px, p.py = 5 * 16, 5 * 16
  ow:onStepComplete()
  check(ow:canCollisionWarp(), "the completed step onto the door sets the flag")
  eq(ow.taken and ow.taken.destMap, "REDS_HOUSE_1F", "and takes us inside")

  ow.taken = nil
  ow:setMap("REDS_HOUSE_1F", 2, 7, "down", { via = "warp" })
  ow.warpEntryCell = { x = 2, y = 7 }
  check(ow:canCollisionWarp(), "the map change does not clear the flag")
  check(ow:checkEdgeExit("down"),
        "so the first press of DOWN on the arrival mat exits (#378)")
  eq(ow.taken and ow.taken.destMap, "LAST_MAP", "straight back to Pallet Town")
end

-- A Poke Center mat is the same shape with a different tile: its $1C is not in
-- any warp-tile list, so the door outside decides and the exit works on arrival.
do
  local ow = bootOn("VIRIDIAN_POKECENTER", 3, 7, "down")
  check(ow:canCollisionWarp(), "the Center mat keeps the flag the door set")
  check(ow:checkEdgeExit("down"), "DOWN on it walks back out to Viridian")
  eq(ow.taken and ow.taken.destMap, "LAST_MAP", "by the LAST_MAP warp")
end

-- The stand-still collision path reads the same flag: north of the staircase
-- cell is solid wall, and bonking it must never fire the stairs.
do
  local ow = bootOn("REDS_HOUSE_2F", 7, 1, "down")
  Input.state.up = true
  Input.pressed = {}
  for _ = 1, 30 do
    ow.player.turnTimer = 0
    ow:handleInput()
    ow.player:update()
  end
  check(ow.taken == nil, "the blocked step into the wall warps nowhere")
  eq(ow.player.cellX, 7, "and the player has not moved")
  eq(ow.player.cellY, 1, "in either axis")
  Input:reset()
end

S.finish()

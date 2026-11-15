-- The BICYCLE: BikeFunction (engine/events/overworld.asm), the PLAYER_BIKE
-- half of DoPlayerMovement (engine/overworld/player_movement.asm), the map
-- load's CheckUpdatePlayerSprite (engine/overworld/map_setup.asm) and the
-- bike shop's phone call (maps/GoldenrodBikeShop.asm ->
-- engine/overworld/events.asm DoBikeStep).
--
-- DoBikeStep was already written and running in src/world/gen2/StepEvents.lua
-- and could never fire, because nothing put the player in PLAYER_BIKE and
-- nothing set the flag the clerk sets.  Both ends live here.
--
-- love-free: every routine takes the map environment, the collision under the
-- player and the current wPlayerState as plain values, so the whole decision
-- tree is testable without a world.
--
-- The three scripts BikeFunction queues are built here too, in the shape
-- src/world/gen2/HiddenItems.lua uses: a `hiddenitem` pickup and a BICYCLE
-- mount are both hand-assembled command lists for the same VM.

local FieldMoves = require("src.world.gen2.FieldMoves")
local Permissions = require("src.world.gen2.Permissions")

local EngineFlags = require("src.core.gen2.EngineFlags")
local Bike = EngineFlags.expose({}, {
  "ENGINE_BIKE_SHOP_CALL_ENABLED", "ENGINE_STRENGTH_ACTIVE",
  "ENGINE_ALWAYS_ON_BIKE", "ENGINE_DOWNHILL",
})

-- engine/overworld/variables.asm .VarActionTable, and wPlayerState as
-- VAR_MOVEMENT writes it raw.  Script_GetOnBike is `loadvar VAR_MOVEMENT,
-- PLAYER_BIKE`, so the mount is literally one variable write plus a sprite
-- reload.
Bike.VAR_MOVEMENT = 0x08
Bike.PLAYER_NORMAL_ID = 0
Bike.PLAYER_BIKE_ID = 1

-- MUSIC_BICYCLE.  .GetOnBike does not use the outdoor-song override machinery
-- Gen 1 has: it fades the current song out, plays this one and writes it into
-- wMapMusic, so the bike theme IS the map's music until the map changes or the
-- player gets off (`special PlayMapMusic`).
Bike.MUSIC_BICYCLE = "Music_Bicycle"

-- StepVectors (engine/overworld/map_objects.asm): a normal step is 8 frames of
-- 2 pixels and a fast step 4 frames of 4, so the bike is exactly half the
-- duration of a walk.  The port walks a 16-pixel cell in 16 frames, so the
-- ratio is what carries over rather than the count.
function Bike.stepFramesFor(walkFrames)
  return math.max(1, math.floor((walkFrames or 16) / 2))
end

-- .CheckEnvironment's first half: CheckOutdoorMap (ROUTE or TOWN), plus CAVE
-- and GATE by name.  INDOOR, ENVIRONMENT_5 and DUNGEON are the three that
-- refuse -- which is why you cannot ride inside a Gym but can ride through
-- Union Cave and the Route 32 gatehouse.
local RIDEABLE_ENVIRONMENT = {
  TOWN = true, ROUTE = true, CAVE = true, GATE = true,
}

function Bike.environmentAllows(environment)
  return RIDEABLE_ENVIRONMENT[environment] == true
end

-- .CheckEnvironment in full: the environment, then GetPlayerTilePermission
-- `and $f` -- the tile the player is STANDING on has to be a plain LAND_TILE.
-- CollisionPermissionTable calls doors and stairs LAND, so the tiles this
-- actually rejects are water and walls: it is the gate that stops a bike being
-- got on mid-surf.
function Bike.canUseHere(environment, collision)
  if not Bike.environmentAllows(environment) then return false end
  return Permissions.isLand(collision)
end

-- .TryBike.  Three answers plus a nil, in the cart's own order:
--
--   nil             .CannotUseBike -- `ld a, $0`, so wFieldMoveSucceeded is 0
--                   and the PACK prints OakThisIsntTheTimeText and stays open.
--   "mount"         PLAYER_NORMAL and the environment allows it.
--   "dismount"      PLAYER_BIKE, and wBikeFlags' ALWAYS_ON_BIKE is clear.
--   "cant_get_off"  PLAYER_BIKE on a forced stretch (the Cycling Road's
--                   ENGINE_ALWAYS_ON_BIKE).  Still returns 1 on the cart, so
--                   the PACK closes and the refusal prints in the overworld.
--
-- A surfing player falls through every `cp` and lands on .CannotUseBike, which
-- is why nil covers PLAYER_SURF without a test of its own.
function Bike.tryBike(ctx)
  ctx = ctx or {}
  local state = ctx.state or FieldMoves.PLAYER_NORMAL
  if FieldMoves.isBiking(state) or state == Bike.PLAYER_BIKE_ID or state == 1 then
    if ctx.alwaysOnBike then return "cant_get_off" end
    return "dismount"
  end
  if not Bike.canUseHere(ctx.environment, ctx.collision) then return nil end
  if state == FieldMoves.PLAYER_NORMAL or state == Bike.PLAYER_NORMAL_ID or state == 0 then return "mount" end
  return nil
end

-- CheckUpdatePlayerSprite (engine/overworld/map_setup.asm), run on every map
-- load, in the cart's own order:
--
--   .CheckForcedBiking          ALWAYS_ON_BIKE puts the player ON the bike,
--                               whatever they walked in as, and wins outright.
--   .CheckSurfing               CheckOnWater reads the tile the player is
--                               STANDING on: a load that lands on water is a
--                               surfing load, and one that already was keeps
--                               the sprite it had.
--   .ResetSurfingOrBikingState  the two ways the state is taken away: surfing
--                               and NOT on water (the arm above has already
--                               failed by the time this one runs), or riding
--                               into an INDOOR, ENVIRONMENT_5 or DUNGEON map.
--
-- `onWater` is CheckOnWater's answer.  nil means the caller could not read the
-- tile at all -- a world with no map up yet -- and the two surf arms are
-- skipped rather than guessed at, because guessing wrong either strands a
-- player on land aboard a Lapras or drops them into the sea on foot.
function Bike.mapSetupState(state, environment, alwaysOnBike, onWater)
  if alwaysOnBike then return FieldMoves.PLAYER_BIKE end
  if onWater ~= nil then
    if onWater then
      if FieldMoves.isSurfing(state) then return state end
      return FieldMoves.PLAYER_SURF
    end
    if FieldMoves.isSurfing(state) then return FieldMoves.PLAYER_NORMAL end
  end
  if state ~= FieldMoves.PLAYER_BIKE then return state end
  if environment == "INDOOR" or environment == "ENVIRONMENT_5"
      or environment == "DUNGEON" then
    return FieldMoves.PLAYER_NORMAL
  end
  return state
end

-- .GetDPad: on a DOWNHILL map (the Cycling Road), a frame with no direction
-- held is a frame moving DOWN -- the bike rolls on its own.  A held direction,
-- any held direction, wins.
function Bike.forcedDirection(dir, downhill)
  if dir then return dir end
  if downhill then return "down" end
  return nil
end

-- .DoStep's pick between STEP_BIKE and STEP_WALK.  .BikeCheck is what makes it
-- a bike step at all, and the DOWNHILL exception is the cart's own: coasting
-- across a slope is SLOWER than coasting down it, so every direction but DOWN
-- gets the walking duration back.
function Bike.stepFrames(state, dir, downhill, walkFrames)
  walkFrames = walkFrames or 16
  if state ~= FieldMoves.PLAYER_BIKE then return walkFrames end
  if downhill and dir ~= "down" then return walkFrames end
  return Bike.stepFramesFor(walkFrames)
end

-- ------------------------------------------------------------ the scripts
--
-- engine/events/overworld.asm:1600
--
-- {STRBUF} is wStringBuffer2, which _DoItemEffect filled with the item's name
-- before it ever reached BikeFunction; `getitemname` is that same fill here.
local TEXT_GOT_ON_BIKE = "_GotOnBikeText"
local TEXT_GOT_OFF_BIKE = "_GotOffBikeText"
local TEXT_CANT_GET_OFF = "_CantGetOffBikeText"

local romLine = FieldMoves.line

-- Script_GetOnBike and Script_GetOffBike, which are the same six commands with
-- a different PLAYER_* byte and a `special PlayMapMusic` on the way out (the
-- bike theme was written into wMapMusic on the way in, so only the dismount
-- has to put the map's own song back).
--
-- The cart's `refreshmap` and `special UpdateTimePals` are dropped for the same
-- reason HiddenItems.itemfinderScript drops them: both repair the tilemap and
-- the palettes the PACK overwrote, and the port draws the PACK as a state over
-- an untouched world.  The `opentext` in front is the mirror of that: the cart
-- inherits the PACK's open text box and this port's queued script does not, so
-- it opens one of its own, exactly as the itemfinder script does.
--
-- `specialId(name)` resolves a special by LABEL through the cache's own
-- specialOrder; a nil answer just leaves that line out rather than dispatching
-- some other special by a counted index.
local function stateScript(item, varValue, text, specialId, restoreMusic, silent, data)
  local script = {}
  if not silent then
    -- .CheckIfRegistered: with wUsingItemWithSelect set, the cart swaps in
    -- Script_GetOnBike_Register / Script_GetOffBike_Register, which are the
    -- same state change with the line and the box taken out -- a SELECT press
    -- gets on the bike with no text at all.
    script[#script + 1] = { op = "opentext" }
    script[#script + 1] = { op = "getitemname", item = item }
  end
  script[#script + 1] = { op = "loadvar", args = { Bike.VAR_MOVEMENT, varValue } }
  if not silent then
    script[#script + 1] = { op = "rawtext", text = romLine(data, text) }
    script[#script + 1] = { op = "waitbutton" }
    script[#script + 1] = { op = "closetext" }
  end
  local update = specialId and specialId("UpdatePlayerSprite")
  if update then script[#script + 1] = { op = "special", id = update } end
  if restoreMusic then
    local play = specialId and specialId("PlayMapMusic")
    if play then script[#script + 1] = { op = "special", id = play } end
  end
  script[#script + 1] = { op = "end" }
  return script
end

function Bike.mountScript(item, specialId, silent, data)
  return stateScript(item, Bike.PLAYER_BIKE_ID, TEXT_GOT_ON_BIKE,
    specialId, false, silent, data)
end

function Bike.dismountScript(item, specialId, silent, data)
  return stateScript(item, Bike.PLAYER_NORMAL_ID, TEXT_GOT_OFF_BIKE,
    specialId, true, silent, data)
end

-- Script_CantGetOffBike: no loadvar at all, so wPlayerState is left exactly as
-- it was and the player is still riding when the box closes.
function Bike.cantGetOffScript(data)
  return {
    { op = "opentext" },
    { op = "rawtext", text = romLine(data, TEXT_CANT_GET_OFF) },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "end" },
  }
end

return Bike

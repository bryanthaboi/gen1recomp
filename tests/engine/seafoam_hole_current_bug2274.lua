package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {
  FIX_ROUTE = { { x = 4, y = 6, mode = "surf" } },
} }
Data.field.seafoam = {
  FIX_ROUTE = {
    currentsDisabledByEvents = { "EVENT_FIX_CURRENT_PLUGGED" },
    currents = { { x = 4, y = 6, moves = { { dir = "down", count = 2 } } } },
  },
}

local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local Music      = require("src.core.Music")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local stack = Game.stack

local ow
local surfMusicEarly, surfMusicLate = 0, 0
Music.playMap = function(_, _, _, surfing)
  if not surfing or not ow then return end
  if ow.transitioning or ow.holeArrive or ow.spinArrive or stack:top() ~= ow then
    surfMusicEarly = surfMusicEarly + 1
  else
    surfMusicLate = surfMusicLate + 1
  end
end

local function newOW()
  stack:push(OW, "FIX_TOWN", 5, 6, "down")
  local o = stack:top()
  Game.overworld = o
  return o
end

ow = newOW()
ow.player.surfing = true
ow:fallThroughHole("FIX_ROUTE", 4, 6, "up")

local mid
local earlySurf, earlyMoves, dropFrames, badDrop = 0, 0, 0, 0
local landedSurfing
local slideFrames, slideSpin = 0, 0
local finalY
local spinEndedAt, surfAt, currentAt
for tick = 1, 500 do
  stack:update()
  local p = ow.player
  if ow.map.id == "FIX_ROUTE" then
    if not mid then
      mid = { surfing = p.surfing, moves = #ow.scriptMoves }
    end
    if dropFrames > 0 and not p.spinning and not spinEndedAt then spinEndedAt = tick end
    if p.surfing and not surfAt then surfAt = tick end
    if #ow.scriptMoves > 0 and not currentAt then currentAt = tick end
    local landing = ow.transitioning or ow.holeArrive or ow.spinArrive
                    or stack:top() ~= ow
    if landing then
      if p.surfing then earlySurf = earlySurf + 1 end
      if #ow.scriptMoves > 0 or p.cellY ~= 6 then earlyMoves = earlyMoves + 1 end
      if p.spinning then
        dropFrames = dropFrames + 1
        local _, _, _, facing, phase, flip = p:pose()
        if facing ~= "down" or phase ~= 1 or flip ~= true then
          badDrop = badDrop + 1
        end
      end
    else
      if landedSurfing == nil then landedSurfing = p.surfing end
      if #ow.scriptMoves > 0 or p.moving then
        slideFrames = slideFrames + 1
        if p.spinning or ow.spinnerSliding then slideSpin = slideSpin + 1 end
      elseif slideFrames > 0 then
        finalY = p.cellY
        break
      end
    end
  end
end

check(mid ~= nil, "the hole fall reaches the destination map")
eq(mid and mid.surfing, false, "the dungeon warp lands on foot, not surfing")
eq(mid and mid.moves, 0, "the current is not armed at the warp midpoint")
eq(earlySurf, 0, "no surf sprite through the hold and the drop")
eq(earlyMoves, 0, "the current never moves the player before the landing")
eq(surfMusicEarly, 0, "no surf music before the landing")
check(dropFrames > 0, "the drop animation ran (" .. dropFrames .. " frames)")
eq(badDrop, 0, "the drop keeps image index 3 (walking down, flipped), no rotation")
eq(landedSurfing, true, "SURF mounts once the drop lands")
-- engine/overworld/player_animations.asm:329
eq(surfAt, spinEndedAt, "SURF mounts on the frame the drop's last step lands")
eq(currentAt, spinEndedAt, "the current is armed on that same frame")
check(surfMusicLate > 0, "surf music starts after the landing")
check(slideFrames > 0, "the current slides the player after the landing")
eq(slideSpin, 0, "the current does not spin the sprite")
eq(finalY, 8, "the current carried the player two cells south")

do
  local o = newOW()
  o:runSpinnerMoves({ { dir = "down", count = 1 } }, 1)
  eq(o.player.spinning, true, "a spinner arrow still spins the sprite")
  eq(o.spinnerSliding, true, "a spinner arrow still freezes tile animation")
end

do
  local o = newOW()
  o.arriveWarp = "teleport"
  o:startWarpTo("FIX_ROUTE", 4, 6, "down")
  for _ = 1, 200 do
    stack:update()
    if o.player.spinDrop then break end
  end
  check(o.player.spinDrop == true, "a teleport arrival arms its spin-down")
  eq(o.player.spinImageIndex, nil, "a teleport arrival keeps its own spin")
  eq(o.pendingEnterMapTail, nil, "a teleport arrival does not defer EnterMap")
end

T.finish("seafoam_hole_current_bug2274")

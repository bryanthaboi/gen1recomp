-- data/maps/setup_scripts.asm:48, :89, :117; engine/overworld/events.asm:993

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

love = require("tests.love_stub")

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setLooping() end
function Source:setVolume(v) self.volume = v end
function Source:setPitch() end
function Source:setFilter() end
function Source:getDuration() return 1 end

love.audio = {
  newSource = function(file, mode)
    return setmetatable({ file = file, mode = mode }, Source)
  end,
}

local Music = require("src.core.Music")
local World = require("src.world.gen2.World")

local DATA = { audio = {
  runtime = true,
  generation = 2,
  songs = {
    Music_Bicycle = { file = "bicycle.wav" },
    Music_Route30 = { file = "route30.wav" },
    Music_DarkCave = { file = "darkcave.wav" },
  },
  musicOrder = { "Music_Route30", "Music_DarkCave" },
} }

local MAPS = {
  ROUTE_30 = { music = 0x80, environment = "ROUTE" },
  DARK_CAVE = { music = 0x81, environment = "CAVE" },
}

-- the MAPSETUP_* bytes World:runMapSetup threads down (constants/map_setup_constants.asm)
local WARP, DOOR, FALL = 0xf1, 0xf5, 0xf6
local CONTINUE, TRAIN, BADWARP = 0xf2, 0xf9, 0xfb

local function newWorld(state)
  local world = World.new({ data = DATA, save = { engineFlags = {} } })
  world.maps = MAPS
  world.playerState = state or "bike"
  Music.stop()
  return world
end

local function settle()
  for _ = 1, 8 * Music.MAP_FADE do Music.update(DATA) end
end

local world = newWorld()
world:setMapMusic("ROUTE_30", false, WARP)
eq(Music.current(), "Music_Bicycle", "a WARP-class load is PlayMapMusicBike")
world.setupMethod = DOOR
world:setMapMusic("DARK_CAVE", false)
settle()
eq(Music.current(), "Music_DarkCave",
   "a walked warp fades to the destination's own song while biking")
eq(Music.mapSong(), "Music_DarkCave",
   "FadeToMapMusic overwrites wMapMusic on a door load too")

Music.stop()
world:restoreMapMusic()
eq(Music.current(), "Music_DarkCave", "a restore after it replays the map song")

-- engine/overworld/events.asm:836 (Dig / Escape Rope) and the pit fall share
-- MapSetupScript_Door's body (setup_scripts.asm:97-101)
for _, method in ipairs({ FALL, TRAIN, BADWARP }) do
  world = newWorld()
  world.setupMethod = method
  world:setMapMusic("DARK_CAVE", false)
  settle()
  eq(Music.current(), "Music_DarkCave",
     ("setup %02x takes FadeToMapMusic"):format(method))
end

-- the rows that really do restart the theme (setup_scripts.asm:48, :154, :175)
for _, method in ipairs({ WARP, CONTINUE }) do
  world = newWorld()
  world.setupMethod = method
  world:setMapMusic("DARK_CAVE", false)
  settle()
  eq(Music.current(), "Music_Bicycle",
     ("setup %02x keeps PlayMapMusicBike"):format(method))
end

world = newWorld()
world.setupMethod = DOOR
world:setMapMusic("ROUTE_30", true)
settle()
eq(Music.current(), "Music_Route30", "a connection crossing still fades across")

world = newWorld()
world:setMapMusic("DARK_CAVE", false)
eq(Music.current(), "Music_Bicycle", "an unmethoded load defaults to WARP")

world = newWorld("normal")
world.setupMethod = DOOR
world:setMapMusic("DARK_CAVE", false)
settle()
eq(Music.current(), "Music_DarkCave", "on foot a door load plays the map song")

world = newWorld()
local seen
world:runMapSetup(DOOR, function()
  seen = world.setupMethod
  return true
end)
world.mapSetup.load()
eq(seen, DOOR, "runMapSetup publishes its method for the load it wraps")
eq(world.setupMethod, nil, "and takes it back down again")

T.finish("gen2_bike_warp_music_bug2286")

-- data/maps/setup_scripts.asm:48

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
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
    Music_CherrygroveCity = { file = "cherrygrove.wav" },
  },
  musicOrder = { "Music_Route30", "Music_CherrygroveCity" },
} }

local MAPS = {
  ROUTE_30 = { music = 0x80, environment = "ROUTE" },
  CHERRYGROVE_CITY = { music = 0x81, environment = "TOWN" },
}

local function newWorld()
  local world = World.new({ data = DATA, save = { engineFlags = {} } })
  world.maps = MAPS
  world.playerState = "bike"
  Music.stop()
  return world
end

local world = newWorld()
eq(world:mapMusicSong("ROUTE_30"), "Music_Route30", "route song resolves")

world:setMapMusic("ROUTE_30", false)
eq(Music.current(), "Music_Bicycle", "a warp-class load re-asserts the bike theme")
eq(Music.mapSong(), "Music_Bicycle", "PlayMapMusicBike writes wMapMusic")

world:setMapMusic("CHERRYGROVE_CITY", true)
for _ = 1, 8 * Music.MAP_FADE do Music.update(DATA) end
eq(Music.current(), "Music_CherrygroveCity",
   "a connection crossing fades to the destination's own song while biking")
eq(Music.mapSong(), "Music_CherrygroveCity",
   "FadeToMapMusic overwrites wMapMusic, so a battle restores the map song")

Music.stop()
world:restoreMapMusic()
eq(Music.current(), "Music_CherrygroveCity",
   "RestartMapMusic replays wMapMusic, not the bike theme")

world = newWorld()
world:setMapMusic("ROUTE_30", false)
world:setMapMusic("ROUTE_30", true)
for _ = 1, 8 * Music.MAP_FADE do Music.update(DATA) end
eq(Music.current(), "Music_Route30",
   "crossing off the bike-theme map still lands on the route song")

world = newWorld()
world.playerState = "normal"
world:setMapMusic("ROUTE_30", false)
eq(Music.current(), "Music_Route30", "on foot a warp load plays the map song")
world:setMapMusic("ROUTE_30", true)
eq(Music.current(), "Music_Route30",
   "crossing into a map with the same song is a no-op (cp e / jr z, .done)")

local Runtime = require("src.mods.Runtime")
local hooks = require("src.mods.Hooks").new()
Runtime.install(require("src.mods.Events").new(), hooks)
local reasons = {}
hooks:wrap("music.select", function(nextLink, song, ctx)
  reasons[#reasons + 1] = ctx.reason
  return nextLink(song, ctx)
end, nil, "bug1975")

world = newWorld()
world:setMapMusic("ROUTE_30", false)
Music.stop()
world:restoreMapMusic()
eq(Music.current(), "Music_Bicycle", "a restore while biking replays the theme")
eq(reasons[#reasons], "bike", "and a mod still reads it as the bike reason")

world.playerState = "normal"
world:setMapMusic("ROUTE_30", false)
Music.stop()
world:restoreMapMusic()
eq(reasons[#reasons], "map", "on foot the restore is a plain map restore")

T.finish("gen2_bike_connection_music_bug1975")

-- ..(home/audio.asm ln 9)
-- ..(home/fade_audio.asm ln 36)
--   luajit tests/engine/map_music_fade.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
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

local made = {} -- file -> the last source built for it
love.audio = {
  newSource = function(file, mode)
    made[file] = setmetatable({ file = file, mode = mode }, Source)
    return made[file]
  end,
}

local Music = require("src.core.Music")

local data = { audio = {
  songs = {
    Music_Pallet = { file = "pallet.wav" },
    Music_Routes1 = { file = "routes1.wav" },
    Music_Pewter = { file = "pewter.wav" },
  },
  mapSongs = {
    PALLET_TOWN = "Music_Pallet",
    ROUTE_1 = "Music_Routes1",
    PEWTER_CITY = "Music_Pewter",
  },
} }

local function frames(n)
  for _ = 1, n do Music.update(data) end
end

local function playing()
  for file, src in pairs(made) do
    if src.playing then return file end
  end
  return "(silence)"
end

local FADE = 7 * Music.MAP_FADE -- 7 volume levels x 10 frames

Music.stop()
Music.playMap(data, "PALLET_TOWN", false, false, Music.MAP_FADE)
eq(playing(), "pallet.wav", "the first map after boot starts at once")

local fullVolume = made["pallet.wav"].volume

Music.playMap(data, "ROUTE_1", false, false, Music.MAP_FADE)
eq(playing(), "pallet.wav", "the new theme waits while the old one fades")
frames(FADE - 1)
eq(playing(), "pallet.wav", "still fading one frame short of silence")
check(made["pallet.wav"].volume < fullVolume,
  "the old theme has been ramped down by then")
frames(1)
eq(playing(), "routes1.wav", "the queued theme takes over after 7 * 10 frames")

eq(made["routes1.wav"].volume, fullVolume,
  "the new theme starts at full volume, not where the ramp ended")

Music.playMap(data, "ROUTE_1", false, false, Music.MAP_FADE)
eq(playing(), "routes1.wav", "the same theme keeps playing")
frames(FADE)
eq(playing(), "routes1.wav", "and no fade was armed for it")

Music.playMap(data, "PALLET_TOWN", false, false, Music.MAP_FADE)
frames(3 * Music.MAP_FADE)
Music.playMap(data, "PEWTER_CITY", false, false, Music.MAP_FADE)
eq(playing(), "routes1.wav", "the retargeted fade keeps ramping the old theme")
frames(4 * Music.MAP_FADE)
eq(playing(), "pewter.wav", "the ramp lands on the newest map's theme")

Music.playMap(data, "PALLET_TOWN", false, false)
eq(playing(), "pallet.wav", "a fadeless map cue swaps immediately")

T.finish("map_music_fade")

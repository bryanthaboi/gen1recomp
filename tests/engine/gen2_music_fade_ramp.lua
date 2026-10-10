-- pokecrystal audio/engine.asm:603-705 FadeMusic
-- pokecrystal engine/overworld/map_setup.asm:191-197 ForceMapMusic
-- pokecrystal home/audio.asm:294 FadeInToMusic
-- pokecrystal home/audio.asm:308-322 FadeToMapMusic
--   luajit tests/engine/gen2_music_fade_ramp.lua

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

local made = {}
love.audio = {
  newSource = function(file, mode)
    made[file] = setmetatable({ file = file, mode = mode }, Source)
    return made[file]
  end,
}

local Music = require("src.core.Music")

local data = { audio = {
  generation = 2,
  songs = {
    Music_NewBarkTown = { file = "newbark.wav" },
    Music_Route29 = { file = "route29.wav" },
    Music_Bicycle = { file = "bike.wav" },
  },
  mapSongs = { NEW_BARK_TOWN = "Music_NewBarkTown", ROUTE_29 = "Music_Route29" },
} }

local function playing()
  for file, src in pairs(made) do
    if src.playing then return file end
  end
  return "(silence)"
end

local function levelOf(file, full)
  local v = made[file].volume
  for level = 0, 7 do
    if math.abs(v - full * level / 7) < 1e-6 then return level end
  end
  return "?"
end

local function trace(file, full, frames)
  local out = {}
  for _ = 1, frames do
    Music.update(data)
    out[#out + 1] = tostring(levelOf(file, full))
  end
  return table.concat(out, " ")
end

local function pending(song)
  return { data = data, song = song, loop = true, ctx = { reason = "test" } }
end

Music.stop()
Music.play(data, "Music_NewBarkTown", true)
local full = made["newbark.wav"].volume
Music.fadeOut(4, pending("Music_Route29"))
eq(playing(), "newbark.wav", "the old song keeps playing while the ramp runs")
eq(levelOf("newbark.wav", full), 7, "at full volume until the first update")
eq(trace("newbark.wav", full, 5), "6 6 6 6 6",
  "the first drop is immediate and level 6 holds control + 1 frames")
eq(trace("newbark.wav", full, 5), "5 5 5 5 5", "level 5 for another 5")
local levels = trace("newbark.wav", full, 25)
eq(levels, "4 4 4 4 4 3 3 3 3 3 2 2 2 2 2 1 1 1 1 1 0 0 0 0 0",
  "levels 4..0 each hold control + 1 frames")
eq(playing(), "newbark.wav", "level 0 is still the old song")
Music.update(data)
eq(playing(), "route29.wav",
  "the queued song starts 1 + 7 * (control + 1) = 36 frames after the write")
eq(made["route29.wav"].volume, full, "at MAX_VOLUME")
check(Music.fadeLevel() == nil, "and the fade is cleared")

Music.fadeOut(2, pending("Music_NewBarkTown"))
eq(trace("route29.wav", full, 5), "6 6 6 5 5", "two drops at control 2 by frame 5")
Music.fadeOut(10, nil)
eq(trace("route29.wav", full, 2), "5 4",
  "a rewrite of wMusicFade keeps wVolume and the count in flight")
local fr = 0
while playing() == "route29.wav" and fr < 200 do
  Music.update(data)
  fr = fr + 1
end
eq(playing(), "(silence)", "MUSIC_NONE at the bottom plays nothing")
eq(fr, 5 * 11, "five more levels of control 10 after that drop")

Music.stop()
Music.play(data, "Music_NewBarkTown", true)
Music.fadeIn(4)
Music.update(data)
check(Music.fadeLevel() == nil, "FadeInToMusic at MAX_VOLUME ends on its first update")
eq(made["newbark.wav"].volume, full, "without touching the volume")
Music.fadeOut(8, pending("Music_Route29"))
eq(trace("newbark.wav", full, 5), "7 7 7 7 6",
  "the next fade waits out the 4 frames FadeInToMusic left in wMusicFadeCount")
eq(trace("newbark.wav", full, 9), "6 6 6 6 6 6 6 6 5",
  "then holds each level control + 1 frames")

Music.stop()
Music.play(data, "Music_Bicycle", true)
Music.fadeIn(8, 0)
eq(made["bike.wav"].volume, 0, "MinVolume before the song is heard")
eq(trace("bike.wav", full, 10), "1 1 1 1 1 1 1 1 1 2",
  "the first step up is immediate, then one level per control + 1 frames")
trace("bike.wav", full, 9 * 5)
eq(levelOf("bike.wav", full), 7, "MAX_VOLUME 1 + 6 * 9 frames in")
check(Music.fadeLevel() ~= nil, "the fade is still armed")
trace("bike.wav", full, 9)
check(Music.fadeLevel() == nil, "and clears one period after reaching it")

Music.stop()
Music.play(data, "Music_Bicycle", true)
Music.setMapSong("Music_Bicycle")
Music.fadeOut(1, pending("Music_Route29"))
trace("bike.wav", full, 1 + 7 * 2 - 1)
eq(playing(), "bike.wav", "still the bike theme a frame before the bottom")
Music.update(data)
eq(playing(), "route29.wav", "the queued song starts")
eq(made["route29.wav"].volume, 0, "at volume 0")
eq(trace("route29.wav", full, 8), "1 2 3 4 5 6 7 7",
  "and climbs one level a frame")
check(Music.fadeLevel() == nil, "then the fade clears")
Music.setMapSong(nil)

local function framesUntilPlaying(limit)
  local n = 0
  while playing() == "(silence)" and n < limit do
    Music.update(data)
    n = n + 1
  end
  return n
end

Music.stop()
for _, src in pairs(made) do src.playing = false end
Music.fadeOut(4, pending("Music_Route29"))
eq(playing(), "(silence)", "a fade requested over MUSIC_NONE does not start the song at once")
eq(framesUntilPlaying(200), 1 + 7 * 5,
  "it waits out the whole ramp under silence, 1 + 7 * (control + 1) frames")
eq(playing(), "route29.wav", "then the queued song starts")

Music.stop()
for _, src in pairs(made) do src.playing = false end
Music.playMap(data, "NEW_BARK_TOWN", nil, nil, 8)
eq(playing(), "(silence)", "FadeToMapMusic from a silent map holds the new theme")
eq(framesUntilPlaying(200), 1 + 7 * 9, "for the full wMusicFade 8 ramp")
eq(playing(), "newbark.wav", "then the map theme starts")
eq(made["newbark.wav"].volume, full, "at MAX_VOLUME")
Music.setMapSong(nil)

T.finish("gen2_music_fade_ramp")

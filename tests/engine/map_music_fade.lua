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

-- home/fade_audio.asm:12-45
local FADE = 8 * (Music.MAP_FADE + 1)

Music.stop()
Music.playMap(data, "PALLET_TOWN", false, false, Music.MAP_FADE)
eq(playing(), "pallet.wav", "the first map after boot starts at once")

local fullVolume = made["pallet.wav"].volume

Music.playMap(data, "ROUTE_1", false, false, Music.MAP_FADE)
eq(playing(), "pallet.wav", "the new theme waits while the old one fades")
frames(Music.MAP_FADE)
eq(made["pallet.wav"].volume, fullVolume,
  "the first level holds for control frames")
frames(1)
check(made["pallet.wav"].volume < fullVolume
  and math.abs(made["pallet.wav"].volume - fullVolume * 6 / 7) < 1e-6,
  "frame control + 1 drops one level")
for level = 5, 0, -1 do
  frames(Music.MAP_FADE + 1)
  check(math.abs(made["pallet.wav"].volume - fullVolume * level / 7) < 1e-6,
    "level " .. level .. " after another control + 1 frames")
end
eq(playing(), "pallet.wav", "the old theme stays at volume 0 for one period")
frames(Music.MAP_FADE)
eq(playing(), "pallet.wav", "still fading one frame short of silence")
frames(1)
eq(playing(), "routes1.wav",
  "the queued theme takes over after 8 * (control + 1) frames")

eq(made["routes1.wav"].volume, fullVolume,
  "the new theme starts at full volume, not where the ramp ended")

Music.playMap(data, "ROUTE_1", false, false, Music.MAP_FADE)
eq(playing(), "routes1.wav", "the same theme keeps playing")
frames(FADE)
eq(playing(), "routes1.wav", "and no fade was armed for it")

Music.playMap(data, "PALLET_TOWN", false, false, Music.MAP_FADE)
frames(3 * (Music.MAP_FADE + 1))
Music.playMap(data, "PEWTER_CITY", false, false, Music.MAP_FADE)
eq(playing(), "routes1.wav", "the retargeted fade keeps ramping the old theme")
frames(FADE - 3 * (Music.MAP_FADE + 1))
eq(playing(), "pewter.wav", "the ramp lands on the newest map's theme")

Music.playMap(data, "PALLET_TOWN", false, false)
eq(playing(), "pallet.wav", "a fadeless map cue swaps immediately")

local data2 = { audio = {
  generation = 2,
  songs = {
    Music_NewBark = { file = "newbark.wav" },
    Music_Route29 = { file = "route29.wav" },
  },
  mapSongs = { NEW_BARK_TOWN = "Music_NewBark", ROUTE_29 = "Music_Route29" },
} }
-- pokecrystal audio/engine.asm:603-669, home/audio.asm:319
Music.stop()
Music.playMap(data2, "NEW_BARK_TOWN", false, false)
local full2 = made["newbark.wav"].volume
Music.playMap(data2, "ROUTE_29", false, false, 8)
Music.update(data2)
check(math.abs(made["newbark.wav"].volume - full2 * 6 / 7) < 1e-6,
  "Gen 2 drops the first level on the first frame")
for _ = 1, 8 do Music.update(data2) end
check(math.abs(made["newbark.wav"].volume - full2 * 6 / 7) < 1e-6,
  "Gen 2 holds each level control + 1 frames")
Music.update(data2)
check(math.abs(made["newbark.wav"].volume - full2 * 5 / 7) < 1e-6,
  "and drops on the next")
for _ = 1, 7 * 9 - 10 do Music.update(data2) end
eq(playing(), "newbark.wav", "Gen 2 still fading one frame short of 1 + 7 * 9")
eq(made["newbark.wav"].volume, 0, "at level 0")
Music.update(data2)
eq(playing(), "route29.wav", "Gen 2 switches after 1 + 7 * (control + 1) frames")
eq(made["route29.wav"].volume, full2, "at full volume")

T.finish("map_music_fade")

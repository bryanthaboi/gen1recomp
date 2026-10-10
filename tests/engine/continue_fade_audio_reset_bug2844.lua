-- home/fade_audio.asm:12-35

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

local current
local resets = 0
local fakeChip = {
  playMusic = function()
    current = setmetatable({ playing = true }, Source)
    return current
  end,
  currentSource = function() return current end,
  rebuildPlayback = function()
    current = setmetatable({ playing = true }, Source)
    resets = resets + 1
    return true
  end,
  stopMusic = function() current = nil end,
  update = function() end,
  ensureMusicPlaying = function() end,
  holdMusic = function() end,
  awaitingFirstBuffer = function() return false end,
  applyOptions = function() return false end,
  setStereo = function() end,
}
package.loaded["src.core.ChipAudio"] = fakeChip

local Music = require("src.core.Music")

local mixCalls = 0
love.audio = {
  newSource = function() return setmetatable({}, Source) end,
  setMixWithSystem = function()
    mixCalls = mixCalls + 1
    fakeChip.rebuildPlayback()
    Music.onDeviceReset()
    return true
  end,
}

local data = { audio = {
  songs = {
    Music_TitleScreen = { chip = true },
    Music_PalletTown = { chip = true },
  },
  mapSongs = { PALLET_TOWN = "Music_PalletTown" },
} }

local opts = { audioMode = "both", musicVol = 7, musicFilter = 0 }

Music.applyOptions(opts)
Music.play(data, "Music_TitleScreen")
local title = current
eq(Music.current(), "Music_TitleScreen", "title theme playing")

mixCalls, resets = 0, 0
Music.applyOptions(opts)
eq(mixCalls, 0, "CONTINUE re-applying the same options sends no setMixWithSystem")
eq(resets, 0, "so the playing title stream is not rebuilt mid-song")
check(current == title, "the title keeps its queued stream")

local full = current.volume
Music.playMap(data, "PALLET_TOWN", false, false, Music.MAP_FADE)
eq(Music.current(), "Music_TitleScreen", "title fades before the map theme")
for _ = 1, 3 * (Music.MAP_FADE + 1) do Music.update(data) end
local faded = current.volume
check(faded < full, "fade has lowered the title volume")

fakeChip.rebuildPlayback()
Music.onDeviceReset()
check(math.abs(current.volume - faded) < 1e-9,
  "a device reset mid-fade keeps the faded level")

T.finish("continue_fade_audio_reset_bug2844")

-- engine/movie/hall_of_fame.asm:1
-- scripts/HallOfFame.asm:24
-- home/fade.asm:26
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Music = require("src.core.Music")
local PaletteFX = require("src.render.PaletteFX")
local Transition = require("src.render.Transition")
local GameVersion = require("src.core.GameVersion")
local HallOfFame = require("src.ui.HallOfFame")

GameVersion.set("red")
Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
Data.audio.songs.Music_HallOfFame = Data.audio.songs.Music_HallOfFame or {}

local realPlay, realFade = Music.play, Music.fadeOut
local plays, fadeAt = {}, nil
local frame = 0
Music.play = function(_, song) plays[#plays + 1] = { song = song, frame = frame } end
Music.fadeOut = function() fadeAt = fadeAt or frame end

local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local game = { data = Data, save = save }

local hof = HallOfFame.new(game, function() end)
T.eq(hof.phase, "intro", "induction opens on the fade, not the back pic sweep")
T.check(not hof.isOpaque, "the map stays drawn under the fade")
T.eq(#plays, 0, "Music_HallOfFame waits for the fade and the pause")

local shades = {}
local backAt
for f = 1, 200 do
  frame = f
  hof:update(1 / 60)
  if hof.phase == "intro" then
    PaletteFX.setShadeMap(nil)
    hof:draw()
    shades[f] = PaletteFX.shadeMap()
  elseif not backAt then
    backAt = f
    break
  end
end

T.eq(fadeAt, 4, "HoFFadeOutScreenAndMusic fades the music after Delay3")
T.eq(shades[3], nil, "Delay3 leaves the palette alone")
T.eq(shades[4], Transition.shadeMapFor(0x90), "fade step 1 on frame 4")
T.eq(shades[11], Transition.shadeMapFor(0x90), "fade step 1 holds 8 frames")
T.eq(shades[12], Transition.shadeMapFor(0x40), "fade step 2 on frame 12")
T.eq(shades[20], Transition.shadeMapFor(0x00), "fade step 3 on frame 20")
T.check(hof.isOpaque, "the screen is cleared to white after the fade")
T.eq(backAt, 3 + 24 + 100, "100 DelayFrames of white before the first mon")
T.eq(hof.phase, "back", "the back pic sweep starts after the pause")
T.eq(hof.scrollX, 160, "the back pic enters from the right edge")
T.eq(plays[1] and plays[1].song, "Music_HallOfFame", "hall of fame theme starts")
T.eq(plays[1] and plays[1].frame, backAt, "theme starts with the sweep, after the pause")

Music.play, Music.fadeOut = realPlay, realFade
PaletteFX.setShadeMap(nil)

T.finish()

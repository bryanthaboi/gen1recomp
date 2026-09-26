package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local S = require("tests.harness").suite("gen2 radio tuning #2485")
local Pokegear = require("src.ui.gen2.Pokegear")
local Music = require("src.core.Music")
local Chrome = require("src.ui.gen2.Chrome")
local input = { pressed = {} }
function input:wasPressed(key)
  local value = self.pressed[key]
  self.pressed[key] = nil
  return value or false
end
local game = { input = input, data = {},
  save = { pokegearFlags = { radio = true } } }
local opts = { clock = { hour = 14, minute = 0, weekday = 1 } }
local gear = Pokegear.new(game, opts)
for i, card in ipairs(gear.cards) do
  if card.id == "radio" then gear.cardIndex = i end
end
gear.mode = "card"
local function press(key)
  input.pressed = { [key] = true }
  gear:update(0)
end
local oldPlay, oldStop = Music.play, Music.stop
local playing, plays, stops = nil, 0, 0
Music.play = function(_, song) playing = song; plays = plays + 1 end
Music.stop = function() playing = nil; stops = stops + 1 end
local expected = { [16] = "OAKS_POKEMON_TALK", [28] = "POKEMON_MUSIC",
  [32] = "LUCKY_CHANNEL" }
S.eq(gear.tuningKnob, 0, "initial_knob_zero")
gear:update(0)
for knob = 0, 80, 2 do
  S.eq(gear.tuningKnob, knob, "all_41_positions_knob_" .. knob)
  local row = gear:currentStation()
  S.eq(row.knob, knob, "exact_knob_" .. knob)
  S.eq(row.frequency, ("%04.1f"):format((knob + 2) / 4), "frequency_" .. knob)
  S.eq(row.station, expected[knob], "exact_station_" .. knob)
  S.eq(gear.radioShow, expected[knob], "show_" .. knob)
  press("up")
end
S.eq(gear.tuningKnob, 80, "upper_clamp")
for knob = 78, 0, -2 do
  press("down")
  S.eq(gear.tuningKnob, knob, "reverse_tuning_" .. knob)
end
press("down")
S.eq(gear.tuningKnob, 0, "lower_clamp")
for _ = 1, 8 do press("up") end
S.eq(gear:currentStation().frequency, "04.5", "station_frequency")
local song, before = playing, plays
S.check(song ~= nil, "station_music_started")
press("up")
S.eq(gear:currentStation().frequency, "05.0", "half_step_dead_air")
S.eq(gear.radio, nil, "dead_air_clears_dialogue")
S.eq(gear:currentStation().name, nil, "dead_air_clears_name")
S.eq(gear.radioSong, nil, "dead_air_clears_song_memory")
S.eq(playing, nil, "dead_air_silences_music")
S.eq(gear.radioMusicPlaying, "enterMap", "dead_air_exit_handoff")
press("down")
S.eq(playing, song, "same_station_music_resumes")
S.eq(plays, before + 1, "same_station_music_replayed")
press("up")
local text, saved = {}, {}
for _, name in ipairs({ "box", "print", "cursor", "textbox" }) do
  saved[name] = Chrome[name]
  Chrome[name] = name == "print" and function(value) text[#text + 1] = value end
    or function() end
end
gear:drawPlain()
for name, fn in pairs(saved) do Chrome[name] = fn end
S.check(table.concat(text, "|"):find("05.0", 1, true) ~= nil,
  "plain_renderer_intermediate_frequency")
S.check(table.concat(text, "|"):find("04.5", 1, true) == nil,
  "plain_renderer_has_no_preset_list")
S.eq(Pokegear.new(game, opts).tuningKnob, 18, "reopen_retains_knob")
game.save = { pokegearFlags = { radio = true } }
S.eq(Pokegear.new(game, opts).tuningKnob, 0, "new_save_resets_knob")
local xs = {}
gear.loadArrowSheet = function() end
gear.arrow = { available = function() return true end,
  draw = function(_, _, x) xs[#xs + 1] = x end }
gear:drawTuningKnob()
S.eq(xs[1], (72 + 18) / 8, "styled_needle_intermediate_position")
Music.play, Music.stop = oldPlay, oldStop
S.finish()

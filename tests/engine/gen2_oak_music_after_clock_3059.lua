-- ../pokegold/engine/rtc/timeset.asm:13-18
-- ../pokegold/engine/menus/intro_menu.asm:494-500
-- ../pokecrystal/engine/menus/init_gender.asm:60-65
--   luajit tests/engine/gen2_oak_music_after_clock_3059.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Music = require("src.core.Music")
local Screens = require("src.ui.Screens")
local FieldMoves = require("src.world.gen2.FieldMoves")
local OakSpeech = require("src.ui.gen2.OakSpeech")

local played, fades, pushed = {}, {}, {}
local realPlay, realFade, realPush = Music.play, Music.fadeOut, Screens.push
Music.play = function(_, song) played[#played + 1] = song end
Music.fadeOut = function(control) fades[#fades + 1] = control end
Screens.push = function(game, id, opts)
  local inst = { id = id, opts = opts }
  pushed[#pushed + 1] = inst
  game.stack:push(inst)
  return inst
end

local function newGame(crystal)
  local game = { save = { player = { name = "GOLD" } } }
  game.data = {
    audio = { runtime = true },
    tokens = require("src.render.TextBox").TOKENS,
    gen2Sprites = crystal
      and { [FieldMoves.STATE_SPRITE_FEMALE.normal] = 1 } or nil,
    text = require("tests.fixture_data.gen2_rom_text_s7_c").text(nil, crystal and "crystal" or nil),
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    wasPressed = function() return false end,
    isDown = function() return false end,
  }
  return game
end

local function route30Played()
  for _, song in ipairs(played) do
    if song == "Music_Route30" then return true end
  end
  return false
end

local function reset()
  played, fades, pushed = {}, {}, {}
end

do
  reset()
  local game = newGame(false)
  local speech = OakSpeech.new(game, { data = require("tests.fixtures.gen2_oak_speech")
    .data({ music = "Music_Route30" }) })
  speech.autoConfirm = true
  speech:enter()
  eq(pushed[1] and pushed[1].id, "Gen2InitClock",
    "gold: the speech opens on InitClock")
  check(not route30Played(),
    "gold: no Route 30 theme while the clock is being set")
  eq(fades[1], 0x10, "gold: InitClock fades the menu music out at $10")
  pushed[1].opts.onDone()
  check(route30Played(), "gold: Route 30 starts once the time is confirmed")
end

do
  reset()
  local game = newGame(true)
  local speech = OakSpeech.new(game, { data = require("tests.fixtures.gen2_oak_speech")
    .data({ music = "Music_Route30" }) })
  speech.autoConfirm = true
  speech:enter()
  eq(pushed[1] and pushed[1].id, "Gen2GenderSelect",
    "crystal: the gender select comes first")
  check(not route30Played(), "crystal: silent during the gender select")
  eq(fades[1], 0x10, "crystal: InitGenderScreen fades the menu music at $10")
  pushed[1].opts.onDone("male")
  eq(pushed[2] and pushed[2].id, "Gen2InitClock",
    "crystal: InitClock follows the gender select")
  check(not route30Played(),
    "crystal: still silent while the clock is being set")
  pushed[2].opts.onDone()
  check(route30Played(), "crystal: Route 30 starts once the time is confirmed")
end

do
  reset()
  local game = newGame(false)
  local speech = OakSpeech.new(game, { data = require("tests.fixtures.gen2_oak_speech")
    .data({ music = "Music_Route30" }) })
  speech.autoConfirm = true
  local base = OakSpeech.buildSteps
  speech.buildSteps = function(self)
    local steps = base(self)
    table.insert(steps, 1, { id = "mod_pre", kind = "fn",
      run = function(_, done) done() end })
    return steps
  end
  speech:enter()
  eq(pushed[1] and pushed[1].id, "Gen2InitClock",
    "mod step first: InitClock still opens")
  eq(played[1], "Music_Route30", "mod step first: theme starts at the mod step")
  eq(fades[1], 0x10, "mod step first: InitClock fades the theme out at $10")
  pushed[1].opts.onDone()
  eq(#played, 2, "mod step first: Route 30 restarts once the time is confirmed")
end

Music.play, Music.fadeOut, Screens.push = realPlay, realFade, realPush

T.finish("gen2_oak_music_after_clock_3059")

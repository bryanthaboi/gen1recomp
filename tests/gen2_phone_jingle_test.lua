--   luajit tests/gen2_phone_jingle_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 phone jingle")
local check = S.check

if not _G.love then _G.love = require("tests.love_stub") end
require("src.core.Logger").warn = function() end

local playing = {}
local Source = {}
Source.__index = Source
function Source:play() playing[self] = true end
function Source:stop() playing[self] = nil end
function Source:isPlaying() return playing[self] == true end
function Source:setVolume() end
function Source:setPitch() end
love.audio = { newSource = function(file) return setmetatable({ file = file }, Source) end }

package.loaded["src.core.Sound"] = nil
local Sound = require("src.core.Sound")
local ChoiceBox = require("src.ui.ChoiceBox")
local TextBox = require("src.render.TextBox")

local order = {}
for i = 1, 0x94 do order[i] = "Sfx_Pad" .. i end
order[0x08 + 1] = "Sfx_ReadText2"
order[0x45 + 1] = "Sfx_GotSafariBalls"
order[0x93 + 1] = "Sfx_RegisterPhoneNumber"
local gold = { audio = { fanfares = {}, sfxOrder = order, sfx = {
  Sfx_ReadText2 = { file = "sfx/readtext2.wav", generation = 2 },
  Sfx_GotSafariBalls = { file = "sfx/safari.wav", generation = 2 },
  Sfx_RegisterPhoneNumber = { file = "sfx/phone.wav", generation = 2 },
} } }

local function reset()
  for src in pairs(playing) do playing[src] = nil end
  Sound.waitSfxDone()
end

-- pokegold engine/events/std_scripts.asm:568
do
  reset()
  local pressed = "a"
  local game = { data = gold, stack = { pop = function() end, push = function() end },
    input = { wasPressed = function(_, k) return k == pressed end } }
  ChoiceBox.new(game, function() end):update(1 / 60)
  check(Sound.sfxBusy(), "the YES press beep is on the sfx channels")
  Sound.dropPressSfx()
  check(Sound.play(gold, "Sfx_RegisterPhoneNumber") ~= nil,
    "playsound SFX_REGISTER_PHONE_NUMBER after a YES press is not gated out by the click")

  reset()
  pressed = "b"
  ChoiceBox.new(game, function() end):update(1 / 60)
  check(Sound.sfxBusy(), "the NO press beep is on the sfx channels")
  Sound.dropPressSfx()
  check(Sound.play(gold, "Sfx_RegisterPhoneNumber") ~= nil,
    "a playsound after a NO press is not gated out by the click")
end

-- pokegold maps/Route35NationalParkGate.asm:145-146
do
  reset()
  local press = false
  local game = {
    data = gold,
    save = { generation = 2, version = "gold", options = { textSpeed = 1 } },
    input = { wasPressed = function(_, k) return press and (k == "a") end,
              isDown = function() return false end },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
  local box = TextBox.new(game, "<PLAYER>'s #MON\nwere left with the\vCONTEST HELPER.")
  local sawWait = false
  for _ = 1, 600 do
    if box.waiting and (box.preWait or 0) <= 0 then
      sawWait = true
      press = true
      box:update(1 / 60)
      press = false
      break
    end
    box:update(1 / 60)
  end
  check(sawWait, "the cont line stopped on its button wait")
  check(Sound.sfxBusy(), "the cont press beep is on the sfx channels")
  Sound.dropPressSfx()
  check(Sound.play(gold, "Sfx_GotSafariBalls") ~= nil,
    "a playsound after a cont press is not gated out by the click")
end

S.finish()

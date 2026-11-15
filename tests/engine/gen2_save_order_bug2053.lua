-- ../pokecrystal/engine/menus/save.asm:242 SavedTheGame
--   luajit tests/engine/gen2_save_order_bug2053.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check
love = love or require("tests.love_stub")

local Save = require("src.core.gen2.Save")
local Sound = require("src.core.Sound")
local SaveMenu = require("src.ui.gen2.SaveMenu")

local function newInput()
  local input = { pressed = {}, held = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown(button) return self.held[button] == true end
  return input
end

local order = {}
order[SaveMenu.SFX_SAVE + 1] = "Sfx_Save"

local log = {}
local realPlay, realBusy, realDone = Sound.play, Sound.sfxBusy, Sound.waitSfxDone
Sound.play = function(_, name) log[#log + 1] = "sfx:" .. tostring(name) end
Sound.sfxBusy = function() return false end
Sound.waitSfxDone = function() end

local input = newInput()
local save = Save.newGame({ playerName = "GOLD", trainerId = 1 })
save.options = save.options or {}
save.options.textSpeed = "FAST"
local game = {
  input = input, save = save,
  data = { audio = { sfxOrder = order, sfx = { Sfx_Save = true } },
    text = require("tests.fixture_data.gen2_rom_text_s7_c").text() },
}

local done = nil
local menu = SaveMenu.new(game, {
  save = save, existed = false,
  writer = function() log[#log + 1] = "write" return true end,
  onDone = function(saved) done = saved end,
})

local frames = 0
local function frame()
  menu:update(0)
  frames = frames + 1
end

frame()
for _ = 1, 400 do
  if menu.typer:done() then break end
  frame()
end
input:press("a")
frame()
eq(menu.phase, "saving", "YES opens SavingDontTurnOffThePower")

for _ = 1, 400 do
  if menu.typer:done() then break end
  frame()
end
eq(#log, 0, "nothing is written while the SAVING line is still printing")
while menu.timer < SaveMenu.SAVING_FRAMES - 1 do frame() end
eq(#log, 0, "and not before the sixteenth DelayFrame")
frame()
eq(log[1], "write", "the write lands on it")
eq(#log, 1, "with no SFX_SAVE of its own")
eq(menu.phase, "saving", "the SAVING page is still up")

while menu.timer < SaveMenu.SAVING_FRAMES + SaveMenu.SAVED_GAP_FRAMES - 1 do
  frame()
end
eq(menu.phase, "saving", "the 32-frame gap holds that page")
frame()
eq(menu.phase, "done", "then the saved line comes up")
eq(#log, 1, "still no chime")

local typing, early = 0, false
for _ = 1, 400 do
  if menu.typer:done() then break end
  frame()
  typing = typing + 1
  if not menu.typer:done() and #log > 1 then early = true end
end
check(typing > 0, "the saved line prints a glyph at a time")
check(not early, "and rings nothing while it is printing")

eq(log[2], "sfx:Sfx_Save", "SFX_SAVE rings AFTER the line, not at the write")
eq(done, nil, "and the box is still up")
eq(menu.timer, 0, "the 30-frame tail has not started")

for _ = 1, SaveMenu.SAVED_TAIL_FRAMES - 1 do frame() end
eq(done, nil, "the 30-frame tail runs from the chime")
frame()
eq(done, true, "and then the save menu closes")

Sound.play, Sound.sfxBusy, Sound.waitSfxDone = realPlay, realBusy, realDone

do
  local busy = true
  local play2, busy2, done2 = Sound.play, Sound.sfxBusy, Sound.waitSfxDone
  Sound.play = function() end
  Sound.sfxBusy = function() return busy end
  Sound.waitSfxDone = function() end
  local closed = nil
  local m2 = SaveMenu.new(game, {
    save = save, existed = false,
    writer = function() return true end,
    onDone = function(saved) closed = saved end,
  })
  m2.phase, m2.saved, m2.rang = "done", true, true
  m2:enterPhase("done")
  m2.saved, m2.rang = true, true
  for _ = 1, 200 do
    if m2.typer:done() then break end
    m2:update(0)
  end
  for _ = 1, 120 do m2:update(0) end
  eq(closed, nil, "a chime still on the channels holds the 30 frames back")
  busy = false
  for _ = 1, SaveMenu.SAVED_TAIL_FRAMES do m2:update(0) end
  eq(closed, true, "and they run once WaitSFX comes back")
  Sound.play, Sound.sfxBusy, Sound.waitSfxDone = play2, busy2, done2
end

T.finish("gen2_save_order_bug2053")

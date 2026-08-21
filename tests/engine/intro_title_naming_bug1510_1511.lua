-- Title -> main menu handoff (#1510) and the Oak-intro naming layout (#1511):
-- title.asm .finishedWaiting, oak_speech2.asm ChoosePlayerName
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local SaveData = require("src.core.SaveData")
local Menu = require("src.ui.Menu")
local NamingScreen = require("src.ui.NamingScreen")
local OakSpeech = require("src.ui.OakSpeech")
local TitleState = require("src.ui.TitleState")

local function newStack()
  local stack = { states = {} }
  function stack:push(state, ...)
    table.insert(self.states, state)
    if type(state.enter) == "function" then state:enter(...) end
  end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function newGame()
  return {
    data = Data,
    save = SaveData.newGame(),
    stack = newStack(),
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
end

local function run(state, frames)
  for _ = 1, frames do
    if state.game.stack:top() ~= state then return end
    state:update(1 / 60)
  end
end

-- ------------------------------------------------- #1510: title -> menu

local game = newGame()
local title = TitleState.new(game, {})
game.stack:push(title)

title:toMenu()
local flash = game.stack:top()
T.check(flash ~= title, "START pushes a state before the menu")
T.eq(flash.isOpaque, true, "GBPalWhiteOutWithDelay3 covers the title art")
T.check(not title.menuOpen, "the title is still drawing itself mid-blink")

run(flash, 60)
local menu = game.stack:top()
T.check(getmetatable(menu) == Menu, "the blink hands off to the main menu")
T.eq(title.menuOpen, true, "MainMenu's ClearScreen takes the title art down")
T.eq(menu.tx, 0, "the CONTINUE / NEW GAME box is still at hlcoord 0,0")

-- OPTION returns to .mainMenuLoop, so its row must not close the box
local option
for _, item in ipairs(menu.items) do
  if item.label == "OPTION" then option = item end
end
T.check(option ~= nil and option.keepOpen == true,
        "OPTION keeps the main menu on the stack")

-- B: DisplayTitleScreen opens with GBPalWhiteOut
T.check(type(menu.onCancel) == "function", "the main menu cancels back out")
game.stack:pop()
menu.onCancel()
local back = game.stack:top()
T.eq(back.isOpaque, true, "backing out blinks white too")
T.eq(title.menuOpen, true, "the title art stays down until the blink ends")
run(back, 60)
T.eq(title.menuOpen, false, "and comes back once the blink is over")
T.eq(game.stack:top(), title, "leaving the menu lands back on the title")
-- main_menu.asm:70 jumps back to DisplayTitleScreen: the whole cinematic reruns
T.eq(title.phase, "drop", "cancel reruns the boot cinematic from the logo drop")

-- a stranded menuOpen (an onSelect that handed control straight back) may
-- not leave a blank white title behind
title.menuOpen = true
title:update(1 / 60)
T.eq(title.menuOpen, false, "a stranded menuOpen clears on the next update")

-- .finishedWaiting: PlayCry then WaitForSoundToFinish before the white-out
-- (engine/movie/title.asm:241-243)
while title.phase ~= "loop" do title:updateSequence() end
game.input.wasPressed = function(_, b) return b == "start" end
title:update(1 / 60)
game.input.wasPressed = function() return false end
T.eq(title.phase, "exitCry", "START waits out the cry before the white-out")
T.eq(game.stack:top(), title, "no flash is pushed on the cry frame")
run(title, 10)
T.check(game.stack:top() ~= title, "the flash follows once the cry is done")

-- ------------------------------------------- #1511: the intro NAME box

local ngame = newGame()
local naming = NamingScreen.new(ngame, {
  presets = { "RED", "ASH", "JACK" }, introBox = true,
})
ngame.stack:push(naming)
local box = ngame.stack:top()
T.check(getmetatable(box) == Menu, "the preset list is a bordered menu")
-- DisplayIntroNameTextBox: TextBoxBorder at hlcoord 0,0 with b=$a, c=$9
T.eq(box.tx, 0, "the name box starts at column 0")
T.eq(box.ty, 0, "the name box starts at row 0")
T.eq(box.tw, 11, "c=$9 plus both border columns is 11 tiles wide")
T.eq(box.th, 12, "b=$a plus both border rows is 12 tiles tall")
T.eq(box.title, "NAME", "the NAME label rides the box's top border")
T.eq(box.itemY, 2, "wTopMenuItemY 2: the list is anchored down from the top")
T.eq(box.cancelable, false, "there is no way out of the naming choice")

-- every other NamingScreen caller keeps the old preset box
local plain = NamingScreen.new(newGame(), { presets = { "RED" } })
local pgame = plain.game
pgame.stack:push(plain)
T.eq(pgame.stack:top().tx, 4, "a non-intro preset list is unchanged")
T.eq(pgame.stack:top().title, nil, "and carries no header")

-- ------------------------------------------ #1511: the pic slide + box

local steps = OakSpeech.defaultSteps({})
local byId = {}
for _, step in ipairs(steps) do byId[step.id] = step end
-- oak_speech.asm:86-91 MovePicLeft, then a text_end box that stays up
T.eq(byId.ask_player_name.reveal, "wipe", "the player pic wipes in")
T.eq(byId.ask_player_name.stay, true, "and its question box stays on screen")
T.eq(byId.ask_rival_name.reveal, "fade", "the rival pic fades in")
T.eq(byId.ask_rival_name.stay, true, "and its box stays on screen too")

local sgame = newGame()
local speech = OakSpeech.new(sgame, function() end)
sgame.stack:push(speech)
speech.steps = steps
speech.step = 0
speech:runStep(byId.name_player)
local slide = sgame.stack:top()
T.check(slide ~= speech, "the name beat slides the pic before the box opens")
T.eq(speech.picSlide, 0, "the slide starts where the pic already sat")
-- six tiles, one per Delay3
run(slide, 6 * 3)
T.eq(speech.picSlide, 48, "OakSpeechSlidePicRight ends six tiles across")
T.check(sgame.stack:top() ~= slide, "the slide pops itself when it lands")

-- ------------------------------------- #1511: the question box stays up

local fgame = newGame()
local flow = OakSpeech.new(fgame, function() end)
fgame.stack:push(flow)
flow.steps = OakSpeech.defaultSteps(flow)
for i, step in ipairs(flow.steps) do
  if step.id == "ask_player_name" then flow.step = i - 1 end
end
flow:advance()
local function pump(frames)
  for _ = 1, frames do
    local top = fgame.stack:top()
    if top.update then top:update(1 / 60) end
    if getmetatable(fgame.stack:top()) == Menu then return end
  end
end
pump(400)
-- _IntroducePlayerText ends in `prompt` (text_2.asm:1730): arrowed A wait
T.check(getmetatable(fgame.stack:top()) ~= Menu,
        "the question box waits for A before the name list")
T.check(fgame.stack:top() == flow.holdBox and flow.holdBox.done,
        "the typed-out question box is on top, waiting for the press")
fgame.input.wasPressed = function(_, b) return b == "a" end
fgame.stack:top():update(1 / 60)
fgame.input.wasPressed = function() return false end
pump(400)
T.check(getmetatable(fgame.stack:top()) == Menu, "A opens the preset list")
T.eq(fgame.stack.states[2], flow.holdBox,
     "IntroducePlayerText's box is still on the stack under the name list")
T.check(flow.holdBox.stayShown == true,
        "prompt-then-hold: the box stays up after the press (home/text.asm:434)")

local preset = fgame.stack:top()
preset.index = 2
fgame.input.wasPressed = function(_, b) return b == "a" end
preset:update(1 / 60)
fgame.input.wasPressed = function() return false end
T.eq(fgame.save.player.name, "RED", "picking a preset names the player")
T.eq(flow.holdBox, nil, "and takes the question box down with the list")
-- 13-frame ClearScreenArea / DelayFrames beat, then six tiles of slide
-- (oak_speech2.asm:69-78)
run(fgame.stack:top(), 13 + 6 * 3)
T.eq(flow.picSlide, 0, "OakSpeechSlidePicLeft puts the pic back")

T.finish("intro_title_naming_bug1510_1511")

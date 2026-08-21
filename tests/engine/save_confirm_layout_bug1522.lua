-- SAVE confirmation layout (#1522): PrintSaveScreenText's own box and
-- SaveTheGame_YesOrNo's TWO_OPTION_MENU at hlcoord 0, 7
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local SaveData = require("src.core.SaveData")
local StartMenu = require("src.ui.StartMenu")
local ChoiceBox = require("src.ui.ChoiceBox")

local function newStack()
  local stack = { states = {} }
  function stack:push(state) table.insert(self.states, state) end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = newStack(),
  input = { wasPressed = function() return false end,
            isDown = function() return false end },
}
game.save.player.name = "RED"
game.save.playTime = 3 * 3600 + 7 * 60

local menu = StartMenu.new(game)
local save
for _, item in ipairs(menu.items) do
  if item.label == "SAVE" then save = item end
end
T.check(save ~= nil, "the start menu lists SAVE")

save.onSelect()
-- PrintSaveScreenText ends `ld c, 30 / jp DelayFrames`: the bare panel
-- holds 30 frames before the prompt (main_menu.asm:404-405)
T.eq(#game.stack.states, 1, "the panel shows alone first")
for _ = 1, 30 do game.stack:top().update() end
T.eq(#game.stack.states, 2, "the panel and the prompt are two separate states")
local panel, prompt = game.stack.states[1], game.stack.states[2]
T.check(type(panel.draw) == "function" and not panel.isTextBox,
        "the info panel is its own drawn state, not a TextBox page")
T.check(prompt.isTextBox == true, "the prompt is the dialogue box on top")
T.eq(#prompt.pages, 1, "the prompt is one page: no \\f-merged info panel")
T.check(prompt.pages[1][1]:find("Would you like to"),
        "the prompt page is WouldYouLikeToSaveText")

-- save.asm:188 hlcoord 0, 7
T.eq(prompt.choiceBox.tx, 0, "the save Yes/No box sits at column 0 (left)")
T.eq(prompt.choiceBox.ty, 7, "the save Yes/No box sits at row 7")
T.eq(prompt.choiceBox, require("src.ui.Theme").saveBox,
     "the geometry routes through Theme so field.theme can restyle it")
local choice = ChoiceBox.new(game, function() end, { box = prompt.choiceBox })
T.eq(choice.tx, 0, "ChoiceBox honours the save-specific left placement")

-- answering NO takes the panel back down with the prompt
prompt.done = true
prompt:update(1 / 60)
local yesno = game.stack:top()
T.check(getmetatable(yesno) == ChoiceBox, "the prompt pushes the Yes/No box")
T.eq(yesno.tx, 0, "the pushed Yes/No box is the left-hand one")
game.stack:pop()
game.stack:pop()
prompt.choice(false)
T.eq(#game.stack.states, 0, "declining closes the info panel too")

T.finish("save_confirm_layout_bug1522")

-- "Which move should be forgotten?",  replaces a move when a Pokémon with
-- four moves learns a new one (engine/pokemon/learn_move.asm).  Opens
-- with the TryingToLearnText "Delete an older move...?" YES/NO; HM moves
-- can't be forgotten; B gives up on the new move.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local romText = require("src.core.RomText")

local MoveLearnMenu = {}
MoveLearnMenu.__index = MoveLearnMenu

local CURSOR = 0xED

-- data/moves/hm_moves.asm (IsMoveHM)
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
}

function MoveLearnMenu.new(game, mon, newMoveId, onDone, learnedSound)
  local self = setmetatable({}, MoveLearnMenu)
  self.game = game
  self.mon = mon
  self.newMoveId = newMoveId
  self.onDone = onDone
  self.learnedSound = learnedSound or "Get_Item1"
  self.index = 1
  -- forget-list UI only after TryingToLearn YES (learn_move.asm .loop)
  self.selecting = false
  return self
end

function MoveLearnMenu:monName()
  return self.mon.nickname or self.game.data.pokemon[self.mon.species].name
end

-- TryingToLearnText + yes/no (learn_move.asm TryingToLearn): NO offers
-- AbandonLearning, whose own NO loops back here (DontAbandonLearning).
-- Use TextBox opts.choice so YES/NO overlays the still-visible prompt;
-- pushing ChoiceBox from onDone pops the text first and leaves YES/NO
-- on "Which move should be forgotten?" (#173).
function MoveLearnMenu:enter()
  local TextBox = require("src.render.TextBox")
  local game = self.game
  local mdef = game.data.moves[self.newMoveId]
  local name = self:monName()
  self.selecting = false
  -- _TryingToLearnText is the whole exchange in pokered, delete prompt
  -- included, so the extracted line carries all four slots at once
  game.stack:push(TextBox.new(game,
    romText(game.data, "_TryingToLearnText",
      "%s is\ntrying to learn\v%s!\fBut, %s\ncan't learn more\vthan 4 moves!\f"
      .. "Delete an older\nmove to make room\vfor %s?",
      name, mdef.name, name, mdef.name),
    nil, {
      choice = function(yes)
        if yes then
          self:askForget()
        else
          self:confirmAbandon()
        end
      end,
    }))
end

-- engine/pokemon/learn_move.asm:119-123
function MoveLearnMenu:askForget()
  local TextBox = require("src.render.TextBox")
  local game = self.game
  self.selecting = false
  local text = romText(game.data, "_WhichMoveToForgetText",
    "Which move should\nbe forgotten?")
  self.forgetPrompt = TextBox.strip(text)
  local box
  box = TextBox.new(game, text, nil, { stay = {
    onShown = function()
      if game.stack:top() == box then game.stack:pop() end
      -- engine/pokemon/learn_move.asm:142
      self.index = 1
      self.selecting = true
    end,
  } })
  game.stack:push(box)
end

function MoveLearnMenu:update(dt)
  if not self.selecting then return end
  local input = self.game.input
  -- wMaxMenuItem = wNumMovesMinusOne, no CANCEL row
  -- engine/pokemon/learn_move.asm:144 (#1686)
  local n = #self.mon.moves
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or n
  elseif input:wasPressed("down") then
    self.index = self.index < n and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self:confirmAbandon()
  elseif input:wasPressed("a") then
    local old = self.mon.moves[self.index]
    if HM_MOVES[old.id] then
      -- HMCantDeleteText, then back to the forget list
      -- engine/pokemon/learn_move.asm:177-181
      local TextBox = require("src.render.TextBox")
      self.selecting = false
      self.game.stack:push(TextBox.new(self.game,
        romText(self.game.data, "_HMCantDeleteText",
          "HM techniques\ncan't be deleted!"),
        function() self:askForget() end))
      return
    end
    local mdef = self.game.data.moves[self.newMoveId]
    self.mon.moves[self.index] = { id = self.newMoveId, pp = mdef.pp }
    self.forgot = self.game.data.moves[old.id].name
    self:finish(true)
  end
end

-- AbandonLearning (learn_move.asm): "Abandon learning MOVE?" YES/NO
-- before giving up; NO returns to the TryingToLearn prompt
-- (DontAbandonLearning)
function MoveLearnMenu:confirmAbandon()
  local TextBox = require("src.render.TextBox")
  local game = self.game
  local mdef = game.data.moves[self.newMoveId]
  self.selecting = false
  game.stack:push(TextBox.new(game,
    romText(game.data, "_AbandonLearningText",
      "Abandon learning\n%s?", mdef.name), nil, {
      choice = function(yes)
        if yes then self:finish(false) else self:enter() end
      end,
    }))
end

function MoveLearnMenu:finish(learned)
  local TextBox = require("src.render.TextBox")
  local game = self.game
  local name = self:monName()
  local mdef = game.data.moves[self.newMoveId]
  self.selecting = false
  game.stack:pop()
  local msg
  local opts
  if learned then
    require("src.world.PikachuFollower")
      .onMoveLearned(game.save, self.mon, self.newMoveId)
    -- pokered pages this as four texts in a row; _ForgotAndText carries
    -- the "And..." tail.  Each text_pause holds the box, and the first one
    -- is followed by SFX_SWAP (engine/pokemon/learn_move.asm:208-222).
    msg = romText(game.data, "_OneTwoAndText", "1, 2 and...")
      .. TextBox.PAUSE
      .. romText(game.data, "_PoofText", " Poof!")
      .. TextBox.PAUSE
      .. romText(game.data, "_ForgotAndText",
           "\f%s forgot\n%s!\fAnd...", name, self.forgot)
      .. "\f" .. romText(game.data, "_LearnedMove1Text",
           "%s learned\n%s!", name, mdef.name)
    opts = { pauseSounds = { "Swap" }, auto = { sound = function()
      return require("src.core.Sound").play(game.data, self.learnedSound)
    end, wait = true } }
  else
    msg = romText(game.data, "_DidNotLearnText",
      "%s\ndid not learn\v%s!", name, mdef.name)
  end
  game.stack:push(TextBox.new(game, msg, function()
    if self.onDone then self.onDone(learned) end
  end, opts))
end

function MoveLearnMenu:draw()
  if not self.selecting then return end
  -- TextBoxBorder 4,7 b=4 c=14; PlaceString 6,8; cursor 5,8
  -- engine/pokemon/learn_move.asm:123-140 (#1686)
  -- engine/pokemon/learn_move.asm:121
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local prompt = self.forgetPrompt or Strings("Which move should\nbe forgotten?")
  local first, rest = prompt:match("^(.-)\n(.*)$")
  Font.draw(first or prompt, 8, 14 * 8)
  if rest then Font.draw(rest, 8, 16 * 8) end
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(4, 7, 16, 6)
  love.graphics.setColor(0, 0, 0, 1)
  for i, mv in ipairs(self.mon.moves) do
    Font.draw(self.game.data.moves[mv.id].name, 48, (7 + i) * 8)
  end
  Font.drawCode(CURSOR, 40, (7 + self.index) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return MoveLearnMenu

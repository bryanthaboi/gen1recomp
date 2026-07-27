-- YES/NO choice box (InitYesNoTextBoxParameters: above the text box, right).

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")

local ChoiceBox = {}
ChoiceBox.__index = ChoiceBox

function ChoiceBox.new(game, onChoose, opts)
  local self = setmetatable({}, ChoiceBox)
  self.game = game
  self.onChoose = onChoose
  -- some of the original's prompts start on NO (e.g. release)
  self.index = (opts and opts.defaultNo) and 2 or 1
  -- BIT_NO_MENU_BUTTON_SOUND: PC-session prompts stay silent
  self.noSound = (opts and opts.noSound) or false
  local box = Theme.choiceBox
  self.tx = (opts and opts.tx) or box.tx
  self.ty = (opts and opts.ty) or box.ty
  self.tw = (opts and opts.tw) or box.tw
  self.th = (opts and opts.th) or box.th
  return self
end

function ChoiceBox:update(dt)
  local input = self.game.input
  if input:wasPressed("up") or input:wasPressed("down") then
    self.index = self.index == 1 and 2 or 1
  elseif input:wasPressed("a") then
    -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on A and B alike
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    self.onChoose(self.index == 1)
  elseif input:wasPressed("b") then
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    self.onChoose(false)
  end
end

function ChoiceBox:draw()
  local tx, ty, tw, th = self.tx, self.ty, self.tw, self.th
  Font.drawBox(tx, ty, tw, th)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("YES"), (tx + 2) * 8, (ty + 1) * 8)
  Font.draw(Strings("NO"), (tx + 2) * 8, (ty + 3) * 8)
  Font.drawCode(Theme.cursor, (tx + 1) * 8,
                (ty + (self.index == 1 and 1 or 3)) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return ChoiceBox

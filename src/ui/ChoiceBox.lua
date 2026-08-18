-- YES/NO choice box (InitYesNoTextBoxParameters: above the text box, right).

local Font = require("src.render.Font")
local UIVisibility = require("src.battle.UIVisibility")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")
local Timing = require("src.core.Timing")

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
  -- Only a choice box sitting on top of an ANCHORED dialogue box rides the
  -- anchor with it (TextBox passes it).  A bare one -- the battle's switch
  -- offer, a shop or PC confirm -- belongs over the screen that pushed it,
  -- and docking it to the window edge instead tears it off that screen by
  -- however far the letterbox sits from the edge.
  self.anchor = opts and opts.anchor or nil
  local box = (opts and opts.box) or Theme.choiceBox
  self.tx = (opts and opts.tx) or box.tx
  self.ty = (opts and opts.ty) or box.ty
  self.tw = (opts and opts.tw) or box.tw
  self.th = (opts and opts.th) or box.th
  -- TwoOptionMenuStrings rows carry their own labels and a "blank line
  -- before first menu item?" flag (data/yes_no_menu_strings.asm:8-16)
  self.labels = (opts and opts.labels) or { "YES", "NO" }
  self.firstItem = (opts and opts.firstItem) or box.firstItem or 1
  return self
end

function ChoiceBox:update(dt)
  local input = self.game.input
  -- Both branches of DisplayTwoOptionMenu hold 15 frames with the menu still
  -- on screen before TwoOptionMenu_RestoreScreenTiles hands control back
  -- (engine/menus/text_box.asm:322-323, :333-334).
  if self.pending ~= nil then
    self.holdFrames = self.holdFrames - 1
    if self.holdFrames <= 0 then
      local yes = self.pending
      self.pending = nil
      self.game.stack:pop()
      self.onChoose(yes)
    end
    return
  end
  if input:wasPressed("up") or input:wasPressed("down") then
    self.index = self.index == 1 and 2 or 1
  elseif input:wasPressed("a") then
    -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on A and B alike
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.pending = (self.index == 1)
    self.holdFrames = Timing.YES_NO_ANSWER
  elseif input:wasPressed("b") then
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    -- .choseSecondMenuItem writes wCurrentMenuItem = 1 before the hold, so
    -- the cursor visibly snaps to NO for those 15 frames
    self.index = 2
    self.pending = false
    self.holdFrames = Timing.YES_NO_ANSWER
  end
end

function ChoiceBox:draw()
  if not UIVisibility.bottomVisible(self, false) then return end
  local tx, ty, tw, th = self.tx, self.ty, self.tw, self.th
  -- rides the same bottom anchor as the dialogue box it sits above, so the
  -- pair travels together (the anchor keeps each element's gap from the edge)
  local r = self.anchor and self.game and self.game.renderer
  if r and r.setUIAnchor then
    r:setUIAnchor(tx * 8, ty * 8, tw * 8, th * 8, self.anchor)
  end
  -- pokegold home/menu.asm YesNoBox: font-page tiles take the screen's own
  -- BG palette 0 colour 0, same as TextBox.lua's paper fold.
  local paper = self.game and self.game.textboxPaper and self.game:textboxPaper()
  Font.drawBox(tx, ty, tw, th, paper)
  love.graphics.setColor(0, 0, 0, 1)
  -- <NEXT> advances 2 * SCREEN_WIDTH -- home/text.asm:64
  local row = self.firstItem
  Font.draw(Strings(self.labels[1]), (tx + 2) * 8, (ty + row) * 8)
  Font.draw(Strings(self.labels[2]), (tx + 2) * 8, (ty + row + 2) * 8)
  Font.drawCode(Theme.cursor, (tx + 1) * 8,
                (ty + row + (self.index == 1 and 0 or 2)) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return ChoiceBox

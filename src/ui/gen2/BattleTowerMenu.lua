-- ../pokecrystal/mobile/mobile_46.asm:137-177 _BattleTowerRoomMenu and the
-- jumptable at :625-641 it drives.

local BattleTower = require("src.core.gen2.BattleTower")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local RomText = require("src.core.RomText")
local Sound = require("src.core.Sound")

local BattleTowerMenu = {}
BattleTowerMenu.__index = BattleTowerMenu
BattleTowerMenu.isOpaque = false

-- ../pokecrystal/mobile/mobile_46.asm:3854-3858 MenuHeader_119cf7,
-- `menu_coords 12, 7, SCREEN_WIDTH - 1, TEXTBOX_Y - 1`.
local PICK_X, PICK_Y, PICK_W, PICK_H = 12, 7, 8, 5
-- ../pokecrystal/mobile/mobile_46.asm:1178-1183, :1222 and :1147
local ROW_X, ROW_Y = 13, 9
local ARROW_X, UP_Y, DOWN_Y = 16, 8, 10

-- ../pokecrystal/mobile/mobile_46.asm:4635-4639 MenuHeader_11a2de and
-- :4516-4530 BattleTowerRoomMenu2_PlaceYesNoMenu.
local YN_X, YN_Y, YN_W, YN_H = 14, 7, 6, 5
local YN_TEXT_X, YES_Y, NO_Y = 16, 8, 10

-- ../pokecrystal/constants/text_constants.asm:25-32, the box SpeechTextbox
-- fills at ../pokecrystal/mobile/mobile_46.asm:5267.
local SAY_X, SAY_Y, SAY_W, SAY_H = 0, 12, 18, 4
local SAY_TEXT_X, SAY_TEXT_Y = 1, 14

-- ../pokecrystal/mobile/mobile_46.asm:3803-3813, `ld a, $80 / ld [wcd50]`
-- counted down one per frame before the menu restarts.
local MESSAGE_FRAMES = 0x80

-- ../pokecrystal/mobile/mobile_46.asm:4609-4610, the code
-- BattleTowerRoomMenu_Cleanup (:512-513) copies into wScriptVar.  The chosen
-- room is a separate byte (w3_d800 at :1285), so onDone answers the level
-- group and nil for the cancel.
BattleTowerMenu.CANCELLED = 0x0a

-- ../pokecrystal/mobile/mobile_46.asm:5488
local PICK_TEXT = "Text_WhatLevelDoYouWantToChallenge"
-- ../pokecrystal/mobile/mobile_46.asm:5459
local TOPS_TEXT = "Text_PartyMonTopsThisLevel"
-- ../pokecrystal/mobile/mobile_46.asm:5464
local UBER_TEXT = "Text_UberRestriction"
-- ../pokecrystal/mobile/mobile_46.asm:5473
local QUIT_TEXT = "Text_CancelBattleRoomChallenge"
-- ../pokecrystal/constants/charmap.asm:89 and :192, tiles $61 and $ee.
local UP_ARROW = "\xe2\x96\xb2"
local DOWN_ARROW = "\xe2\x96\xbc"

-- ../pokecrystal/mobile/mobile_46.asm:4623, :4626
local YES_LABEL = "String_11a2cf"
local NO_LABEL = "String_11a2d3"

function BattleTowerMenu:text(label)
  return CommonText.plain(RomText(self.data, label, nil))
end

-- ../pokecrystal/mobile/mobile_46.asm:1159-1165, :3869
function BattleTowerMenu:rowLabel(index)
  local list = #self.rows > 4 and "Strings_L10ToL100" or "Strings_Ll0ToL40"
  return self:text(list .. "#" .. (2 * index - 1))
end

-- opts: save, party, rows (BattleTower.levelGroupRows), monName,
--       onDone(levelGroup) with nil for the cancel
function BattleTowerMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BattleTowerMenu)
  self.game = game
  self.data = (game and game.data) or {}
  self.save = opts.save or (game and game.save)
  self.party = opts.party or (self.save and self.save.party) or {}
  self.rows = opts.rows or BattleTower.levelGroupRows(self.save)
  self.monName = opts.monName
  self.onDone = opts.onDone
  -- `ld a, $1 / ld [wcd4f], a` (../pokecrystal/mobile/mobile_46.asm:1152-1153)
  self.cursor = 1
  self.phase = "pick"
  self.message = self:text(PICK_TEXT)
  return self
end

function BattleTowerMenu:wantsFillScale() return true end

function BattleTowerMenu:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

-- The last row is CANCEL (../pokecrystal/mobile/mobile_46.asm:1160, :1165).
function BattleTowerMenu:rowCount()
  return #self.rows + 1
end

function BattleTowerMenu:finish(group)
  if self.done then return end
  self.done = true
  local game = self.game
  if game and game.stack and game.stack:top() == self then game.stack:pop() end
  if self.onDone then self.onDone(group) end
end

-- ../pokecrystal/mobile/mobile_46.asm:3794-3816: the refusal is printed, held
-- for $80 frames and the menu restarts at jumptable index 0.
function BattleTowerMenu:refuse(text)
  self.phase = "message"
  -- ../pokecrystal/home/text.asm:479 Paragraph
  self.pages = {}
  for page in (tostring(text) .. "\f"):gmatch("(.-)\f") do
    self.pages[#self.pages + 1] = page
  end
  if #self.pages == 0 then self.pages[1] = tostring(text) end
  self.page = 1
  self.message = self.pages[1]
  self.wait = MESSAGE_FRAMES
end

-- ../pokecrystal/mobile/mobile_46.asm:1258-1286 `.a_button`
function BattleTowerMenu:confirm()
  local row = self.rows[self.cursor]
  if not row then
    -- ../pokecrystal/mobile/mobile_46.asm:1291-1303 `.asm_118a3c`
    self.phase = "quit"
    self.message = self:text(QUIT_TEXT)
    self.yes = true
    return
  end
  if BattleTower.levelCheck(self.party, row.group) then
    return self:refuse(self:text(TOPS_TEXT))
  end
  local uber = BattleTower.ubersCheck(self.party, row.group)
  if uber then
    local name = (self.monName and self.monName(uber)) or uber
    return self:refuse(CommonText.plain(RomText(self.data, UBER_TEXT, nil, name)))
  end
  self:finish(row.group)
end

-- ../pokecrystal/mobile/mobile_46.asm:1240-1256: UP walks the level up and
-- rolls over to the first row, DOWN walks it back and rolls over to CANCEL.
function BattleTowerMenu:updatePick()
  local input = self.game and self.game.input
  if not input then return end
  local count = self:rowCount()
  if input:wasPressed("up") then
    self.cursor = (self.cursor < count) and self.cursor + 1 or 1
  elseif input:wasPressed("down") then
    self.cursor = (self.cursor > 1) and self.cursor - 1 or count
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    self:confirm()
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    self.phase = "quit"
    self.message = self:text(QUIT_TEXT)
    self.yes = true
  end
end

-- ../pokecrystal/mobile/mobile_46.asm:4535-4621
-- BattleTowerRoomMenu2_UpdateYesNoMenu.
function BattleTowerMenu:updateQuit()
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") then
    self.yes = true
  elseif input:wasPressed("down") then
    self.yes = false
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    if self.yes then return self:finish(nil) end
    self.phase = "pick"
    self.message = self:text(PICK_TEXT)
    self.cursor = 1
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    self.phase = "pick"
    self.message = self:text(PICK_TEXT)
    self.cursor = 1
  end
end

function BattleTowerMenu:update(_dt)
  if self.done then return end
  if self.phase == "message" then
    if self.pages and self.page < #self.pages then
      local input = self.game and self.game.input
      if input and (input:wasPressed("a") or input:wasPressed("b")) then
        self.page = self.page + 1
        self.message = self.pages[self.page]
      end
      return
    end
    self.wait = (self.wait or 0) - 1
    if self.wait > 0 then return end
    self.phase = "pick"
    self.message = self:text(PICK_TEXT)
    self.cursor = 1
    return
  end
  if self.phase == "quit" then return self:updateQuit() end
  return self:updatePick()
end

function BattleTowerMenu:drawPanel()
  Chrome.textbox(SAY_X, SAY_Y, SAY_W, SAY_H)
  -- ../pokecrystal/home/text.asm:473-477 LineChar
  Chrome.printWrapped(self.message, SAY_TEXT_X, SAY_TEXT_Y, SAY_W, 2, 2)
  if self.phase == "message" then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if self.phase == "quit" then
    Chrome.box(YN_X, YN_Y, YN_W, YN_H)
    Chrome.print(self:text(YES_LABEL), YN_TEXT_X, YES_Y)
    Chrome.print(self:text(NO_LABEL), YN_TEXT_X, NO_Y)
    Chrome.cursor(YN_TEXT_X - 1, self.yes and YES_Y or NO_Y)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  Chrome.box(PICK_X, PICK_Y, PICK_W, PICK_H)
  Chrome.print(self:rowLabel(self.cursor), ROW_X, ROW_Y)
  Chrome.print(UP_ARROW, ARROW_X, UP_Y)
  Chrome.print(DOWN_ARROW, ARROW_X, DOWN_Y)
  love.graphics.setColor(1, 1, 1, 1)
end

function BattleTowerMenu:draw()
  self:drawPanel()
end

return BattleTowerMenu

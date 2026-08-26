-- ../pokecrystal/mobile/mobile_46.asm:137-177 _BattleTowerRoomMenu and the
-- jumptable at :625-641 it drives.

local BattleTower = require("src.core.gen2.BattleTower")
local Chrome = require("src.ui.gen2.Chrome")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

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

-- ../pokecrystal/mobile/mobile_46.asm:5488-5491
local PICK_TEXT = Strings.source("What level do you\nwant to challenge?")
-- ../pokecrystal/mobile/mobile_46.asm:5459-5462
local TOPS_TEXT = Strings.source("A party POKéMON\ntops this level.")
-- ../pokecrystal/mobile/mobile_46.asm:5464-5471
local UBER_TEXT = Strings.source(
  "%s may go\nonly to BATTLE\nROOMS that are\nLv.70 or higher.")
-- ../pokecrystal/mobile/mobile_46.asm:5473-5476
local QUIT_TEXT = Strings.source("Cancel your BATTLE\nROOM challenge?")
-- ../pokecrystal/constants/charmap.asm:89 and :192, tiles $61 and $ee.
local UP_ARROW = "\xe2\x96\xb2"
local DOWN_ARROW = "\xe2\x96\xbc"

-- ../pokecrystal/mobile/mobile_46.asm:3880 and :4623-4627
local CANCEL_LABEL = Strings.source("CANCEL")
local YES_LABEL = Strings.source("YES")
local NO_LABEL = Strings.source("NO")

-- ../pokecrystal/mobile/mobile_46.asm:3869-3879 Strings_L10ToL100, six tiles
-- a row.
function BattleTowerMenu.levelLabel(group)
  return string.format(" L:%-3d", group * 10):sub(1, 6)
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
  self.message = PICK_TEXT
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
  self.message = text
  self.wait = MESSAGE_FRAMES
end

-- ../pokecrystal/mobile/mobile_46.asm:1258-1286 `.a_button`
function BattleTowerMenu:confirm()
  local row = self.rows[self.cursor]
  if not row then
    -- ../pokecrystal/mobile/mobile_46.asm:1291-1303 `.asm_118a3c`
    self.phase = "quit"
    self.message = QUIT_TEXT
    self.yes = true
    return
  end
  if BattleTower.levelCheck(self.party, row.group) then
    return self:refuse(TOPS_TEXT)
  end
  local uber = BattleTower.ubersCheck(self.party, row.group)
  if uber then
    local name = (self.monName and self.monName(uber)) or uber
    return self:refuse(string.format(UBER_TEXT, name))
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
    self.message = QUIT_TEXT
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
    self.message = PICK_TEXT
    self.cursor = 1
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    self.phase = "pick"
    self.message = PICK_TEXT
    self.cursor = 1
  end
end

function BattleTowerMenu:update(_dt)
  if self.done then return end
  if self.phase == "message" then
    self.wait = (self.wait or 0) - 1
    if self.wait > 0 then return end
    self.phase = "pick"
    self.message = PICK_TEXT
    self.cursor = 1
    return
  end
  if self.phase == "quit" then return self:updateQuit() end
  return self:updatePick()
end

function BattleTowerMenu:drawPanel()
  Chrome.textbox(SAY_X, SAY_Y, SAY_W, SAY_H)
  Chrome.printWrapped(self.message, SAY_TEXT_X, SAY_TEXT_Y, SAY_W, SAY_H)
  if self.phase == "message" then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if self.phase == "quit" then
    Chrome.box(YN_X, YN_Y, YN_W, YN_H)
    Chrome.print(YES_LABEL, YN_TEXT_X, YES_Y)
    Chrome.print(NO_LABEL, YN_TEXT_X, NO_Y)
    Chrome.cursor(YN_TEXT_X - 1, self.yes and YES_Y or NO_Y)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  Chrome.box(PICK_X, PICK_Y, PICK_W, PICK_H)
  local row = self.rows[self.cursor]
  Chrome.print(row and BattleTowerMenu.levelLabel(row.group) or CANCEL_LABEL,
    ROW_X, ROW_Y)
  Chrome.print(UP_ARROW, ARROW_X, UP_Y)
  Chrome.print(DOWN_ARROW, ARROW_X, DOWN_Y)
  love.graphics.setColor(1, 1, 1, 1)
end

function BattleTowerMenu:draw()
  self:drawPanel()
end

return BattleTowerMenu

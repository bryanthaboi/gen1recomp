-- The MAILBOX in the player's PC: _PlayerMailBoxMenu and MailboxPC
-- (engine/pokemon/mail.asm).
--
-- InitMail runs first and answers z when sMailboxCount is 0, which is the one
-- branch that never opens a menu at all -- an empty MAILBOX is
-- _EmptyMailboxText and nothing else.
--
-- Layout, from the two headers:
--   .TopMenuHeader  menu_coords 8, 1, 18, 10 -- a scrolling menu, four rows,
--                   each printed by MailboxPC_PrintMailAuthor, i.e. the
--                   AUTHOR of the letter and not its message
--   .SubMenuHeader  menu_coords 0, 0, 13, 9 with STATICMENU_CURSOR, so its
--                   four labels start at (2,2) and step two rows
--
-- The submenu's four rows are .Jumptable's four routines:
--
--   READ MAIL    ReadMailMessage, which is the Gen2MailRead screen
--   PUT IN PACK  "message will be lost. OK?" -> ReceiveItem, then
--                DeleteMailFromPC.  The letter is destroyed and the
--                STATIONERY goes back in the bag, which is why the question
--                is asked before the bag is even checked
--   ATTACH MAIL  the party list, refusing an EGG and a mon that is already
--                holding anything, then MoveMailFromPCToParty.  The cart
--                LOOPS on both refusals (`jr .try_again`) rather than backing
--                out, so the list comes straight back up
--   CANCEL       `ret`
--
-- Drawn over whatever opened the PC, so this state is not opaque.

local Bag = require("src.inventory.Bag")
local Breeding = require("src.core.gen2.Breeding")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Mail = require("src.core.gen2.Mail")
local RomText = require("src.core.RomText")
local Screens = require("src.ui.Screens")
local Typer = require("src.ui.gen2.Typer")

local MailboxMenu = {}
MailboxMenu.__index = MailboxMenu
MailboxMenu.isOpaque = false

local LIST_X, LIST_Y, LIST_W, LIST_H = 8, 1, 11, 10
-- InitScrollingMenu lays its rows two inside the box's corner and steps two.
local ROW_X, ROW_Y, ROW_STEP = LIST_X + 2, LIST_Y + 2, 2
local VISIBLE_ROWS = 4

local SUB_X, SUB_Y, SUB_W, SUB_H = 0, 0, 14, 10
local SUB_LABEL_X, SUB_LABEL_Y = SUB_X + 2, SUB_Y + 2

local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5
local DOWN_ARROW = "\xe2\x96\xbc"
local ARROW_X, ARROW_Y = 18, 17

-- engine/pokemon/mail.asm:561
local SUB_ENTRIES = {
  { id = "read", rom = "MailboxPC.SubMenuData#1" },
  { id = "pack", rom = "MailboxPC.SubMenuData#2" },
  { id = "attach", rom = "MailboxPC.SubMenuData#3" },
  { id = "cancel", rom = "MailboxPC.SubMenuData#4" },
}

local LABELS = {
  empty = "_EmptyMailboxText",
  messageLost = "_MailMessageLostText",
  packFull = "_MailPackFullText",
  putAway = "_MailClearedPutAwayText",
  alreadyHolding = "_MailAlreadyHoldingItemText",
  egg = "_MailEggText",
  moved = "_MailMovedFromBoxText",
}

MailboxMenu.LABELS = LABELS
MailboxMenu.SUB_ENTRIES = SUB_ENTRIES

-- opts: save, text (text.lua), onClose()
function MailboxMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MailboxMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.textData = opts.text or (game and game.world and game.world.text)
  self.TEXT = CommonText.texts(self.textData, LABELS)
  self.onClose = opts.onClose
  -- wCurMessageIndex / wCurMessageScrollPosition, both reset by MailboxPC
  -- before its loop.
  self.index = 1
  self.scroll = 0
  self.submenu = nil
  self.message = nil
  self.confirm = nil
  self.picking = false
  -- InitMail's z branch: no menu, one line, gone.
  if Mail.mailboxCount(self.save) == 0 then
    self:say(self.TEXT.empty, function() self:close() end)
  end
  return self
end

function MailboxMenu:box()
  return Mail.mailbox(self.save)
end

function MailboxMenu:count()
  return Mail.mailboxCount(self.save)
end

function MailboxMenu:selected()
  return self:box()[self.index]
end

function MailboxMenu:close()
  if self.onClose then self.onClose() end
end

function MailboxMenu:say(list, onDone)
  self.message = { pages = list or {}, page = 1, onDone = onDone }
end

function MailboxMenu:ask(list, onYes, onNo)
  self.confirm = { pages = list or {}, page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
end

function MailboxMenu:clampIndex()
  local total = self:count()
  if total == 0 then
    self.index, self.scroll = 1, 0
    return
  end
  if self.index > total then self.index = total end
  if self.index < 1 then self.index = 1 end
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, total - VISIBLE_ROWS)))
end

-- ------------------------------------------------------------- submenu rows

function MailboxMenu:readMail()
  local game = self.game
  local entry = self:selected()
  if not (game and game.stack and entry) then return end
  self.picking = true
  Screens.push(game, "Gen2MailRead", {
    entry = entry,
    onClose = function()
      game.stack:pop()
      self.picking = false
      self.submenu = nil
    end,
  })
end

-- .PutInPack.  The yes/no comes first, then ReceiveItem -- and only a bag that
-- accepted the stationery gets as far as DeleteMailFromPC, so a full PACK
-- leaves the letter in the MAILBOX intact.
function MailboxMenu:putInPack()
  self:ask(self.TEXT.messageLost, function()
    local entry = self:selected()
    if not entry then
      self.submenu = nil
      return
    end
    local data = self.game and self.game.data
    if not Bag.add(self.save, entry.type, 1, data) then
      return self:say(self.TEXT.packFull, function() self.submenu = nil end)
    end
    Mail.deleteFromPc(self.save, self.index)
    self:clampIndex()
    self:say(self.TEXT.putAway, function()
      self.submenu = nil
      if self:count() == 0 then
        -- The next .loop calls InitMail again, which now answers z.
        self:say(self.TEXT.empty, function() self:close() end)
      end
    end)
  end, function()
    -- `ret c`: the question was the whole thing.
    self.submenu = nil
  end)
end

-- .AttachMail's loop.  Both refusals go back to the party list rather than out
-- of the submenu, which is exactly what `jr .try_again` does.
function MailboxMenu:attachMail()
  local game = self.game
  if not (game and game.stack) then
    self.submenu = nil
    return
  end
  self.picking = true
  Screens.push(game, "Gen2PartyMenu", {
    save = self.save,
    party = self.save.party,
    prompt = "choose",
    onChoose = function(slot, mon)
      game.stack:pop()
      self.picking = false
      if Breeding.isEgg(mon) then
        return self:say(self.TEXT.egg, function() self:attachMail() end)
      end
      if mon and mon.item then
        return self:say(self.TEXT.alreadyHolding,
          function() self:attachMail() end)
      end
      if not Mail.moveFromPcToParty(self.save, self.index, slot) then
        self.submenu = nil
        return
      end
      self:clampIndex()
      self:say(self.TEXT.moved, function()
        self.submenu = nil
        if self:count() == 0 then
          self:say(self.TEXT.empty, function() self:close() end)
        end
      end)
    end,
    onCancel = function()
      game.stack:pop()
      self.picking = false
      -- `.exit2` -> CloseSubmenu: back to the letter list, not out of the PC.
      self.submenu = nil
    end,
  })
end

function MailboxMenu:chooseSub()
  local entry = SUB_ENTRIES[self.submenu.index]
  if not entry then return end
  if entry.id == "read" then return self:readMail() end
  if entry.id == "pack" then return self:putInPack() end
  if entry.id == "attach" then return self:attachMail() end
  self.submenu = nil
end

-- ------------------------------------------------------------------ update

function MailboxMenu:updateMessage(input)
  Typer.step(self)
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  local message = self.message
  if message.page < #message.pages then
    message.page = message.page + 1
    return
  end
  self.message = nil
  if message.onDone then message.onDone() end
end

function MailboxMenu:updateConfirm(input)
  Typer.step(self)
  local confirm = self.confirm
  if confirm.page < #confirm.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      confirm.page = confirm.page + 1
    end
    return
  end
  if input:wasPressed("up") or input:wasPressed("down") then
    confirm.choice = confirm.choice == 1 and 2 or 1
    return
  end
  if input:wasPressed("b") then
    self.confirm = nil
    if confirm.onNo then confirm.onNo() end
    return
  end
  if input:wasPressed("a") then
    local yes = confirm.choice == 1
    self.confirm = nil
    if yes then
      if confirm.onYes then confirm.onYes() end
    elseif confirm.onNo then
      confirm.onNo()
    end
  end
end

function MailboxMenu:updateSubmenu(input)
  local total = #SUB_ENTRIES
  if input:wasPressed("up") then
    self.submenu.index = self.submenu.index > 1 and self.submenu.index - 1
      or total
  elseif input:wasPressed("down") then
    self.submenu.index = self.submenu.index < total and self.submenu.index + 1
      or 1
  elseif input:wasPressed("a") then
    self:chooseSub()
  elseif input:wasPressed("b") then
    self.submenu = nil
  end
end

function MailboxMenu:update(_dt)
  if self.picking then return end
  local input = self.game and self.game.input
  if not input then return end
  if self.message then return self:updateMessage(input) end
  if self.confirm then return self:updateConfirm(input) end
  if self.submenu then return self:updateSubmenu(input) end

  local total = self:count()
  if total == 0 then return self:close() end
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
    self:clampIndex()
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
    self:clampIndex()
  elseif input:wasPressed("a") then
    self.submenu = { index = 1 }
  elseif input:wasPressed("b") then
    -- .exit: PAD_B out of the scrolling menu ends _PlayerMailBoxMenu.
    self:close()
  end
end

-- -------------------------------------------------------------------- draw

function MailboxMenu:drawTextBox(lines)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function MailboxMenu:drawYesNo(choice)
  local data = self.game and self.game.data
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  -- home/menu.asm:473
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#1"), YESNO_X + 2, YESNO_Y + 1)
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#2"), YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

function MailboxMenu:drawList()
  Chrome.box(LIST_X, LIST_Y, LIST_W, LIST_H)
  local box = self:box()
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local entry = box[i]
    if entry then
      local ty = ROW_Y + (row - 1) * ROW_STEP
      if i == self.index then Chrome.cursor(ROW_X - 1, ty) end
      -- MailboxPC_PrintMailAuthor copies NAME_LENGTH - 1 bytes out of the
      -- struct's Author field and terminates it; a blank author draws a blank
      -- row rather than the message.
      Chrome.print(entry.author or "", ROW_X, ty)
    end
  end
end

function MailboxMenu:drawSubmenu()
  local data = self.game and self.game.data
  Chrome.box(SUB_X, SUB_Y, SUB_W, SUB_H)
  for row, entry in ipairs(SUB_ENTRIES) do
    local ty = SUB_LABEL_Y + (row - 1) * 2
    if row == self.submenu.index then Chrome.cursor(SUB_LABEL_X - 1, ty) end
    Chrome.print(RomText(data, entry.rom), SUB_LABEL_X, ty)
  end
end

function MailboxMenu:drawPanel()
  if self.message then
    self:drawTextBox(self.message.pages[self.message.page])
    if self.message.page < #self.message.pages
      and Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if self.confirm then
    self:drawTextBox(self.confirm.pages[self.confirm.page])
    if self.confirm.page >= #self.confirm.pages then
      self:drawYesNo(self.confirm.choice)
    elseif Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  self:drawList()
  if self.submenu then self:drawSubmenu() end
  love.graphics.setColor(1, 1, 1, 1)
end

function MailboxMenu:draw()
  self:drawPanel()
end

return MailboxMenu

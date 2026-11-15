-- MonMailAction (engine/pokemon/mon_menu.asm): the READ / TAKE / QUIT menu the
-- party submenu's MAIL row opens.
--
-- It is drawn OVER the party list rather than replacing it -- MENU_BACKUP_TILES
-- with `menu_coords 9, 10, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1` -- so this
-- state is not opaque and the list underneath keeps drawing.
--
-- TAKE is the interesting half, and its two questions are asked in this order
-- for a reason: "Send the removed MAIL to your PC?" comes FIRST, and only
-- saying no to it drops into "The MAIL will lose its message. OK?".  So the
-- destructive answer is two deliberate presses away, and the mailbox being
-- full (.MailboxFull) ends the whole thing rather than falling through to the
-- bag.
--
--   READ  ReadPartyMonMail, which is the Gen2MailRead screen
--   TAKE  yes -> SendMailToPC     -> _MailSentToPCText / _MailboxFullText
--         no  -> ReceiveItemFromPokemon on the mail ITEM
--                                 -> _MailDetachedText / _MailNoSpaceText
--   QUIT  `ld a, $3`, i.e. redraw the list and stay in it

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Mail = require("src.core.gen2.Mail")
local RomText = require("src.core.RomText")
local Screens = require("src.ui.Screens")
local Typer = require("src.ui.gen2.Typer")

local MailMenu = {}
MailMenu.__index = MailMenu
-- Drawn over the party list; see the header.
MailMenu.isOpaque = false

-- .MenuHeader: menu_coords 9, 10, 19, 17.  GetMenuTextStartCoord with
-- STATICMENU_CURSOR and no NO_TOP_SPACING puts the first label at
-- (left + 2, top + 2) and steps two rows, with the cursor one column left.
local MENU_X, MENU_Y, MENU_W, MENU_H = 9, 10, 11, 8
local MENU_LABEL_X, MENU_LABEL_Y = MENU_X + 2, MENU_Y + 2

-- The shared speech box and YES/NO box, at the coordinates every Gold screen
-- draws them at (Textbox `lb bc, 4, 18` at (0,12); YesNoBox at (14,7)).
local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5
local DOWN_ARROW = "\xe2\x96\xbc"
local ARROW_X, ARROW_Y = 18, 17

-- engine/pokemon/mon_menu.asm:552
local ENTRIES = {
  { id = "read", rom = "MonMailAction.MenuData#1" },
  { id = "take", rom = "MonMailAction.MenuData#2" },
  { id = "quit", rom = "MonMailAction.MenuData#3" },
}

local LABELS = {
  askSendToPc = "_MailAskSendToPCText",
  mailboxFull = "_MailboxFullText",
  sentToPc = "_MailSentToPCText",
  loseMessage = "_MailLoseMessageText",
  detached = "_MailDetachedText",
  noSpace = "_MailNoSpaceText",
}

local FILL = {
  detached = function(name) return { name } end,
}

MailMenu.LABELS = LABELS
MailMenu.ENTRIES = ENTRIES

-- opts: save, slot (the party index the list landed on), text (text.lua),
-- onClose()
function MailMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MailMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.slot = opts.slot or 1
  self.textData = opts.text or (game and game.world and game.world.text)
  self.TEXT = CommonText.texts(self.textData, LABELS, FILL)
  self.onClose = opts.onClose
  self.index = 1
  self.message = nil
  self.confirm = nil
  self.reading = false
  return self
end

function MailMenu:mon()
  return self.save and self.save.party and self.save.party[self.slot]
end

function MailMenu:monName()
  local mon = self:mon()
  if not mon then return "#MON" end
  return mon.nickname or mon.name or mon.species or "#MON"
end

function MailMenu:close()
  if self.onClose then self.onClose() end
end

function MailMenu:say(list, onDone)
  self.message = { pages = list or {}, page = 1, onDone = onDone }
end

function MailMenu:ask(list, onYes, onNo)
  self.confirm = { pages = list or {}, page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
end

-- .read: ReadPartyMonMail over the party list.  The read screen is opaque and
-- full-page, so it goes on the stack rather than being drawn from here.
function MailMenu:read()
  local game = self.game
  if not (game and game.stack) then return self:close() end
  self.reading = true
  Screens.push(game, "Gen2MailRead", {
    entry = Mail.get(self.save, self.slot),
    onClose = function()
      game.stack:pop()
      self.reading = false
      -- `ld a, $0` returns to the party list rather than staying in the menu.
      self:close()
    end,
  })
end

-- .take: the first question.
function MailMenu:take()
  self:ask(self.TEXT.askSendToPc, function() self:sendToPc() end,
    function() self:removeToBag() end)
end

function MailMenu:sendToPc()
  if not Mail.sendToPc(self.save, self.slot) then
    return self:say(self.TEXT.mailboxFull, function() self:close() end)
  end
  self:say(self.TEXT.sentToPc, function() self:close() end)
end

-- .RemoveMailToBag: the second question, then ReceiveItemFromPokemon.  The
-- item only leaves the mon once the bag has actually taken it, which is why a
-- full bag prints _MailNoSpaceText and the letter is still on the mon
-- afterwards.
function MailMenu:removeToBag()
  self:ask(self.TEXT.loseMessage, function()
    local mon = self:mon()
    if not (mon and Mail.monHoldsMail(mon)) then return self:close() end
    local data = self.game and self.game.data
    if not Bag.add(self.save, mon.item, 1, data) then
      return self:say(self.TEXT.noSpace, function() self:close() end)
    end
    local name = self:monName()
    mon.item = nil
    Mail.clear(self.save, self.slot)
    self:say(self.TEXT.detached(name), function() self:close() end)
  end, function()
    -- `jr c, .done`: saying no here leaves everything alone.
    self:close()
  end)
end

function MailMenu:choose()
  local entry = ENTRIES[self.index]
  if not entry then return end
  if entry.id == "read" then return self:read() end
  if entry.id == "take" then return self:take() end
  self:close()
end

function MailMenu:updateMessage(input)
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

function MailMenu:updateConfirm(input)
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

function MailMenu:update(_dt)
  -- The read screen is on top of the stack; it owns input until it pops.
  if self.reading then return end
  local input = self.game and self.game.input
  if not input then return end
  if self.message then return self:updateMessage(input) end
  if self.confirm then return self:updateConfirm(input) end

  local total = #ENTRIES
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") then
    -- `jp c, .done`: B is QUIT.
    self:close()
  end
end

function MailMenu:drawTextBox(lines)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function MailMenu:drawYesNo(choice)
  local data = self.game and self.game.data
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  -- home/menu.asm:473
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#1"), YESNO_X + 2, YESNO_Y + 1)
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#2"), YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

function MailMenu:drawPanel()
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
  local data = self.game and self.game.data
  Chrome.box(MENU_X, MENU_Y, MENU_W, MENU_H)
  for row, entry in ipairs(ENTRIES) do
    local ty = MENU_LABEL_Y + (row - 1) * 2
    if row == self.index then Chrome.cursor(MENU_LABEL_X - 1, ty) end
    Chrome.print(RomText(data, entry.rom), MENU_LABEL_X, ty)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function MailMenu:draw()
  self:drawPanel()
end

return MailMenu

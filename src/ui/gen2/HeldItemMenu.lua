-- GiveTakePartyMonItem (engine/pokemon/mon_menu.asm): the GIVE / TAKE menu the
-- party submenu's ITEM row opens, and the two routines behind it.
--
-- It is here because MAIL cannot be reached without it.  Attaching a letter to
-- a mon is GivePartyItem -> ComposeMailMessage and nothing else on the cart --
-- the PACK has no "use" for mail (ItemAttributes gives it ITEMMENU_NOUSE in
-- both menus), the MAILBOX only ever MOVES a letter that already exists, and
-- `givepokemail` is one scripted gift on Route 35.  So the compose keyboard's
-- only door is this one.
--
-- Drawn over the party list (`menu_coords 12, 12, SCREEN_WIDTH - 1,
-- SCREEN_HEIGHT - 1`), so this state is not opaque.
--
--   GIVE  .GiveItem: DepositSellPack, then
--         - a KEY_ITEM or an untossable item is ItemCantHeldText and the PACK
--           comes straight back (`jr .next` -> `.loop`)
--         - an empty-handed mon takes it (GiveItemToPokemon), and if the item
--           is MAIL the compose keyboard opens on top (GivePartyItem's
--           `farcall ItemIsMail / call ComposeMailMessage`)
--         - a mon already holding MAIL is refused with
--           _PokemonRemoveMailText, BEFORE the swap question is asked -- so
--           there is no way to knock a letter off a mon by accident
--         - anything else is the swap question
--   TAKE  TakePartyItem: the item goes back to the bag, or
--         _ItemStorageFullText when it will not fit
--
-- An EGG never gets here at all: GiveTakePartyMonItem's first two lines are
-- `cp EGG / jr z, .cancel`.

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Mail = require("src.core.gen2.Mail")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")

local HeldItemMenu = {}
HeldItemMenu.__index = HeldItemMenu
HeldItemMenu.isOpaque = false

-- GiveTakeItemMenuData: menu_coords 12, 12, 19, 17, STATICMENU_CURSOR and no
-- NO_TOP_SPACING, so GIVE is at (14,14) and TAKE two rows under it.
local MENU_X, MENU_Y, MENU_W, MENU_H = 12, 12, 8, 6
local MENU_LABEL_X, MENU_LABEL_Y = MENU_X + 2, MENU_Y + 2

local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5
local DOWN_ARROW = "\xe2\x96\xbc"
local ARROW_X, ARROW_Y = 18, 17

local ENTRIES = {
  { id = "give", label = Strings.source("GIVE") },
  { id = "take", label = Strings.source("TAKE") },
}

local function page(...) return { ... } end
local function pages(...) return { ... } end

-- data/text/common_2.asm.  The {STRBUF} markers are text_ram fields, spliced
-- here rather than being part of the string.
local TEXT = {
  hold = function(mon, item)
    return pages(page(("Made %s"):format(mon), ("hold %s."):format(item)))
  end,
  removeMail = pages(page("Please remove the", "MAIL first.")),
  notHolding = function(mon)
    return pages(page(("%s isn't"):format(mon), "holding anything."))
  end,
  storageFull = pages(page("Item storage space", "full.")),
  tookItem = function(item, mon)
    return pages(page(("Took %s"):format(item), ("from %s."):format(mon)))
  end,
  askSwap = function(mon, item)
    return pages(
      page(("%s is"):format(mon), "already holding"),
      page(("%s."):format(item), "Switch items?"))
  end,
  swapped = function(mon, old, new)
    return pages(
      page(("Took %s's"):format(mon), ("%s and"):format(old)),
      page("made it hold", ("%s."):format(new)))
  end,
  cantHold = pages(page("This item can't be", "held.")),
}

local LABELS = {
  hold = "_PokemonHoldItemText",
  removeMail = "_PokemonRemoveMailText",
  notHolding = "_PokemonNotHoldingText",
  storageFull = "_ItemStorageFullText",
  tookItem = "_PokemonTookItemText",
  askSwap = "_PokemonAskSwapItemText",
  swapped = "_PokemonSwapItemText",
  cantHold = "_ItemCantHeldText",
}

-- Each formatted entry's markers, in the order the ASM string names them.
local FILL = {
  hold = function(mon, item) return { mon, item } end,
  notHolding = function(mon) return { mon } end,
  tookItem = function(item, mon) return { item, mon } end,
  askSwap = function(mon, item) return { mon, item } end,
  swapped = function(mon, old, new) return { mon, old, new } end,
}

HeldItemMenu.TEXT = TEXT
HeldItemMenu.LABELS = LABELS
HeldItemMenu.ENTRIES = ENTRIES

local function extractedText(text)
  local out = setmetatable({}, { __index = TEXT })
  for key, label in pairs(LABELS) do
    local list = CommonText.of(text, label)
    if list then
      local fill = FILL[key]
      if fill then
        out[key] = function(...) return CommonText.fill(list, fill(...)) end
      else
        out[key] = list
      end
    end
  end
  return out
end

-- opts: save, slot, items (items.lua), text (text.lua), onClose()
function HeldItemMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, HeldItemMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.slot = opts.slot or 1
  self.items = opts.items or (game and game.data and game.data.items)
  self.textData = opts.text or (game and game.world and game.world.text)
  self.TEXT = extractedText(self.textData)
  self.onClose = opts.onClose
  self.index = 1
  self.busy = false
  return self
end

function HeldItemMenu:mon()
  return self.save and self.save.party and self.save.party[self.slot]
end

function HeldItemMenu:monName()
  local mon = self:mon()
  if not mon then return "#MON" end
  return mon.nickname or mon.name or mon.species or "#MON"
end

function HeldItemMenu:itemName(id)
  local def = id and self.items and self.items[id]
  return (def and def.name) or id or "?"
end

function HeldItemMenu:close()
  if self.onClose then self.onClose() end
end

-- home/menu.asm:793
function HeldItemMenu:playSfx(name)
  local data = self.game and self.game.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then Sound.play(data, name) end
end

-- home/menu.asm:348
function HeldItemMenu:say(list, onDone)
  Typer.say(self, list, onDone)
end

function HeldItemMenu:ask(list, onYes, onNo)
  self.confirm = { pages = list or {}, page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
  Typer.begin(self, self.confirm)
end

-- ------------------------------------------------------------------- GIVE

-- .GiveItem's `cp KEY_ITEM_POCKET` and CheckTossableItem: a key item or an
-- item whose attributes forbid tossing cannot be held, and the PACK reopens
-- rather than the menu closing.
function HeldItemMenu:canHold(itemId)
  local def = itemId and self.items and self.items[itemId]
  if def and def.pocket == "KEY_ITEM" then return false end
  if def and def.canToss == false then return false end
  return true
end

function HeldItemMenu:openPack()
  local game = self.game
  if not (game and game.stack) then return self:close() end
  self.busy = true
  Screens.push(game, "Gen2PackMenu", {
    save = self.save,
    -- DepositSellPack: the PACK is a chooser here, so a field item must not
    -- run its effect on the way past.
    give = true,
    onChoose = function(itemId)
      game.stack:pop()
      self.busy = false
      self:giveItem(itemId)
    end,
    onClose = function()
      game.stack:pop()
      self.busy = false
      -- `.quit`: backing out of the PACK ends the whole GIVE.
      self:close()
    end,
  })
end

-- TryGiveItemToPartymon, in its own order.
function HeldItemMenu:giveItem(itemId)
  local mon = self:mon()
  if not (mon and itemId) then return self:close() end
  if not self:canHold(itemId) then
    return self:say(self.TEXT.cantHold, function() self:openPack() end)
  end
  local held = mon.item
  if held and Mail.isMail(held) then
    -- .please_remove_mail: a `ret`, so the whole GIVE ends here.
    return self:say(self.TEXT.removeMail, function() self:close() end)
  end
  if not held then
    Bag.remove(self.save, itemId, 1)
    mon.item = itemId
    local name = self:itemName(itemId)
    return self:say(self.TEXT.hold(self:monName(), name), function()
      self:composeIfMail(itemId)
    end)
  end
  -- .already_holding_item: the swap question, then ReceiveItemFromPokemon for
  -- the old one.  A bag that cannot take it back puts the old item straight
  -- back on the mon (.bag_full), so nothing is ever destroyed.
  self:ask(self.TEXT.askSwap(self:monName(), self:itemName(held)), function()
    Bag.remove(self.save, itemId, 1)
    if not Bag.add(self.save, held, 1, self.game and self.game.data) then
      Bag.add(self.save, itemId, 1, self.game and self.game.data)
      return self:say(self.TEXT.storageFull, function() self:close() end)
    end
    mon.item = itemId
    self:say(self.TEXT.swapped(self:monName(), self:itemName(held),
      self:itemName(itemId)), function() self:composeIfMail(itemId) end)
  end, function() self:close() end)
end

-- GivePartyItem's tail: `ld d, a / farcall ItemIsMail / call
-- ComposeMailMessage`.  The keyboard has no cancel -- the item is already on
-- the mon by the time it opens -- so an empty message is a blank letter, not
-- a refusal.
function HeldItemMenu:composeIfMail(itemId)
  if not Mail.isMail(itemId) then return self:close() end
  local game = self.game
  if not (game and game.stack) then return self:close() end
  self.busy = true
  Screens.push(game, "Gen2MailCompose", {
    onDone = function(message)
      game.stack:pop()
      self.busy = false
      Mail.compose(self.save, self.slot, message, self:mon(), itemId)
      self:close()
    end,
  })
end

-- ------------------------------------------------------------------- TAKE

function HeldItemMenu:takeItem()
  local mon = self:mon()
  if not mon then return self:close() end
  local held = mon.item
  if not held then
    return self:say(self.TEXT.notHolding(self:monName()),
      function() self:close() end)
  end
  if not Bag.add(self.save, held, 1, self.game and self.game.data) then
    return self:say(self.TEXT.storageFull, function() self:close() end)
  end
  mon.item = nil
  -- Taking a mail item back leaves no letter behind it: the struct has nowhere
  -- to live once the stationery is gone.  The MAIL row's own TAKE is the path
  -- that asks about the PC first (src/ui/gen2/MailMenu.lua); this one is only
  -- reachable for a mon that is NOT holding mail, because the submenu shows
  -- MAIL instead of ITEM in that case.
  Mail.clear(self.save, self.slot)
  self:say(self.TEXT.tookItem(self:itemName(held), self:monName()),
    function() self:close() end)
end

function HeldItemMenu:choose()
  local entry = ENTRIES[self.index]
  if not entry then return end
  if entry.id == "give" then return self:openPack() end
  self:takeItem()
end

-- ------------------------------------------------------------------ update

function HeldItemMenu:updateMessage(input)
  Typer.step(self)
  if Typer.typing(self) then return end
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  -- home/joypad.asm:392
  self:playSfx("Sfx_ReadText2")
  local message = self.message
  if message.page < #message.pages then
    Typer.turn(self, message)
    return
  end
  self.message = nil
  self.typer = nil
  if message.onDone then message.onDone() end
end

function HeldItemMenu:updateConfirm(input)
  Typer.step(self)
  if Typer.typing(self) then return end
  local confirm = self.confirm
  if confirm.page < #confirm.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:playSfx("Sfx_ReadText2")
      Typer.turn(self, confirm)
    end
    return
  end
  if input:wasPressed("up") or input:wasPressed("down") then
    confirm.choice = confirm.choice == 1 and 2 or 1
    return
  end
  if input:wasPressed("b") then
    -- home/menu.asm:520
    self:playSfx("Sfx_ReadText2")
    self.confirm = nil
    self.typer = nil
    if confirm.onNo then confirm.onNo() end
    return
  end
  if input:wasPressed("a") then
    -- home/menu.asm:520
    self:playSfx("Sfx_ReadText2")
    local yes = confirm.choice == 1
    self.confirm = nil
    self.typer = nil
    if yes then
      if confirm.onYes then confirm.onYes() end
    elseif confirm.onNo then
      confirm.onNo()
    end
  end
end

function HeldItemMenu:update(_dt)
  -- The PACK or the keyboard is on top of the stack; it owns input.
  if self.busy then return end
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
    -- home/menu.asm:381
    self:playSfx("Sfx_ReadText2")
    self:choose()
  elseif input:wasPressed("b") then
    -- home/menu.asm:381
    self:playSfx("Sfx_ReadText2")
    self:close()
  end
end

-- -------------------------------------------------------------------- draw

function HeldItemMenu:drawTextBox(lines)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function HeldItemMenu:drawYesNo(choice)
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  Chrome.print(Strings("YES"), YESNO_X + 2, YESNO_Y + 1)
  Chrome.print(Strings("NO"), YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

function HeldItemMenu:drawPanel()
  if self.message then
    self:drawTextBox(Typer.text(self, self.message.pages[self.message.page]))
    if self.message.page < #self.message.pages
      and not Typer.typing(self) and Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if self.confirm then
    self:drawTextBox(Typer.text(self, self.confirm.pages[self.confirm.page]))
    if Typer.typing(self) then
      love.graphics.setColor(1, 1, 1, 1)
      return
    end
    if self.confirm.page >= #self.confirm.pages then
      self:drawYesNo(self.confirm.choice)
    elseif Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  Chrome.box(MENU_X, MENU_Y, MENU_W, MENU_H)
  for row, entry in ipairs(ENTRIES) do
    local ty = MENU_LABEL_Y + (row - 1) * 2
    if row == self.index then Chrome.cursor(MENU_LABEL_X - 1, ty) end
    Chrome.print(Strings(entry.label), MENU_LABEL_X, ty)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function HeldItemMenu:draw()
  self:drawPanel()
end

return HeldItemMenu

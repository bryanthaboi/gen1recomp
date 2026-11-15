-- The in-game trade conversation (engine/events/npc_trade.asm NPCTrade).
--
-- NPCTrade is a straight line, and its ORDER is the whole of it:
--
--   1. the trade's flag is already set  -> TRADE_DIALOG_AFTER, and stop.  This
--      is checked before the intro, so a completed trade never asks again.
--   2. TRADE_DIALOG_INTRO, then YesNoBox.  A no is TRADE_DIALOG_CANCEL.
--   3. SelectTradeOrDayCareMon with PARTYMENUACTION_GIVE_MON.  Backing out of
--      the party list is the SAME TRADE_DIALOG_CANCEL.
--   4. the picked mon's species against NPCTRADE_GIVEMON, then
--      CheckTradeGender.  Either miss is TRADE_DIALOG_WRONG.
--   5. set the flag, NPCTradeCableText, DoNPCTrade, the trade animation,
--      TradedForText, RestartMapMusic, TRADE_DIALOG_COMPLETE.
--
-- The lines come out of the cache: PrintTradeText indexes TradeTexts by dialog
-- and then by the row's own TRADE_DIALOGSET_*, so the three NPC personalities
-- share one script and differ only in wording.  {STRBUF} is the mon name the
-- line splices in -- GetTradeMonNames puts the mon you GET in wStringBuffer2
-- and the one you GIVE in wMonOrItemNameBuffer, and appends ♂/♀ to the first
-- when the row wants a particular gender.
--
-- Step 5's `predef TradeAnimation` -- the cable-and-ball sequence -- is
-- Gen2TradeAnim, pushed between DoNPCTrade and TradedForText the way NPCTrade
-- runs it.  DoNPCTrade has already happened by then and nothing about the
-- outcome depends on it, so the screen can be skipped and its onDone is the
-- only thing that carries the conversation on.

local Chrome = require("src.ui.gen2.Chrome")
local NpcTrade = require("src.core.gen2.NpcTrade")
local Screens = require("src.ui.Screens")
local RomText = require("src.core.RomText")
local Sound = require("src.core.Sound")
local Typer = require("src.ui.gen2.Typer")

local TradeMenu = {}
TradeMenu.__index = TradeMenu
TradeMenu.isOpaque = false

-- The shared speech box: `lb bc, 4, 18` at (0,12), text at (1,14) with the
-- second line two rows down.
local BOX_X, BOX_Y, BOX_W, BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2
local ARROW_X, ARROW_Y = 18, 17

-- InitYesNoTextBoxParameters' default: a 6x5 box at (14,7), YES at (16,8) and
-- NO at (16,10) with the cursor column at 15.
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

local GENDER_GLYPH = {
  TRADE_GENDER_MALE = "\xe2\x99\x82",
  TRADE_GENDER_FEMALE = "\xe2\x99\x80",
}

-- The markers the extractor writes for the cart's own text controls: `para`
-- ($51) starts a new page, `cont` ($55) scrolls one line so the new page opens
-- on the previous last one, and `line` / `next` ($4f / $4e) is the second line
-- of the page it is in.  Named rather than spelled inline so the string gate
-- does not read them as player-visible text.
local PAGE, SCROLL, LINE = "\f", "\v", "\n"
local SEPARATORS = "([^" .. LINE .. PAGE .. SCROLL .. "]*)([" ..
  LINE .. PAGE .. SCROLL .. "])"

-- Split a decoded text stream into pages of up to two lines.
function TradeMenu.paginate(body)
  body = require("src.core.gen2.CommonText").plain(body)
  local pages, current = {}, {}
  local function flush(scroll)
    if #current > 0 then pages[#pages + 1] = current end
    current = scroll and { current[#current] or "" } or {}
    if scroll then current.scrolled = true end
  end
  for chunk, sep in (tostring(body or "") .. PAGE):gmatch(SEPARATORS) do
    current[#current + 1] = chunk
    if sep == PAGE then flush(false)
    elseif sep == SCROLL then flush(true) end
  end
  if #pages == 0 then pages[1] = { tostring(body or "") } end
  return pages
end

-- GetTradeMonNames fills three of the cart's six string buffers:
--
--   wStringBuffer1        the mon you HAND OVER, with the row's ♂/♀ appended
--                         when it wants a particular gender
--   wStringBuffer2        the mon you GET
--   wMonOrItemNameBuffer  the mon you hand over again, without the glyph
--
-- This port has ONE shared buffer, so the extractor writes all three as the
-- same `{STRBUF}` and records which was which alongside the text
-- (events.tradeBuffers).  A line like the collector's intro names two
-- different ones -- "do you have DROWZEE?" then "for my MACHOP?" -- so filling
-- them in order out of that list is what keeps the two mons from swapping.
--
-- With no buffer list the fallback is wStringBuffer1, the commonest of the
-- three and the right answer for every single-marker line.
function TradeMenu.fill(body, row, data, buffers)
  local function speciesName(id)
    local def = data and data.pokemon and data.pokemon[id]
    return (def and def.name) or id or "#MON"
  end
  local give, get = speciesName(row and row.give), speciesName(row and row.get)
  local byBuffer = {
    wStringBuffer1 = give .. (GENDER_GLYPH[row and row.gender] or ""),
    wStringBuffer2 = get,
    wMonOrItemNameBuffer = give,
  }
  local n = 0
  return (tostring(body or ""):gsub("{STRBUF}", function()
    n = n + 1
    return byBuffer[(buffers or {})[n] or "wStringBuffer1"]
      or byBuffer.wStringBuffer1
  end))
end

-- opts: trade (the NPC_TRADE_* id), save, eventTables, onClose
function TradeMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TradeMenu)
  self.game = game
  self.data = (game and game.data) or {}
  self.save = opts.save or (game and game.save)
  self.eventTables = opts.eventTables or {}
  self.id = tonumber(opts.trade) or 0
  self.onClose = opts.onClose
  self.row = NpcTrade.row(self.eventTables, self.id)
  if not self.row then
    self:close()
  elseif NpcTrade.done(self.save, self.id) then
    self:say(NpcTrade.DIALOG_AFTER, function() self:close() end)
  else
    self:ask(NpcTrade.DIALOG_INTRO,
      function() self:openParty() end,
      function() self:refuse(NpcTrade.DIALOG_CANCEL) end)
  end
  return self
end

function TradeMenu:wantsFillScale() return true end

function TradeMenu:tradeText(label, set)
  local texts = self.eventTables.tradeTexts
  if type(texts) ~= "table" then error("events.lua has no tradeTexts", 3) end
  local body = texts[label]
  if set ~= nil then body = type(body) == "table" and body[set] or nil end
  if type(body) ~= "string" then
    error(("events.lua tradeTexts has no %s %s"):format(
      tostring(label), tostring(set or "")), 3)
  end
  return body
end

function TradeMenu:lineFor(dialog)
  local set = self.row and self.row.dialog
  local body = self:tradeText(dialog, set)
  local bufRow = (self.eventTables.tradeBuffers or {})[dialog]
  local buffers = bufRow and set and bufRow[set]
  return TradeMenu.paginate(
    self:expand(TradeMenu.fill(body, self.row, self.data, buffers)))
end

function TradeMenu:say(dialog, onDone)
  Typer.say(self, self:lineFor(dialog), onDone)
end

-- TradedForText is the one line here that names something other than the two
-- mons: it opens on {PLAYER}.  The shared TextBox resolves that token for a
-- speech box, but this screen prints through Chrome, so the same substitution
-- has to happen before the text reaches the tile grid -- otherwise the braces
-- go looking for glyphs that do not exist.
function TradeMenu:expand(body)
  local game = self.game
  if not (game and game.save) then return body end
  local ok, out = pcall(require("src.render.TextBox").substitute, game, body)
  return ok and out or body
end

function TradeMenu:sayRaw(body, buffers, onDone)
  self.message = {
    pages = TradeMenu.paginate(
      self:expand(TradeMenu.fill(body, self.row, self.data, buffers))),
    page = 1, onDone = onDone,
  }
  Typer.begin(self, self.message)
end

function TradeMenu:ask(dialog, onYes, onNo)
  self.confirm = { pages = self:lineFor(dialog), page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
  Typer.begin(self, self.confirm)
end

function TradeMenu:refuse(dialog)
  self:say(dialog, function() self:close() end)
end

function TradeMenu:close()
  if self.closed then return end
  self.closed = true
  if self.onClose then self.onClose() end
end

function TradeMenu:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function TradeMenu:openParty()
  local game = self.game
  if not (game and game.stack) then
    return self:refuse(NpcTrade.DIALOG_CANCEL)
  end
  self.picking = true
  Screens.push(game, "Gen2PartyMenu", {
    party = self.save and self.save.party,
    prompt = "choose",
    onChoose = function(index)
      game.stack:pop()
      self.picking = false
      self:chose(index)
    end,
    onCancel = function()
      game.stack:pop()
      self.picking = false
      self:refuse(NpcTrade.DIALOG_CANCEL)
    end,
  })
end

function TradeMenu:chose(index)
  local mon = self.save and self.save.party and self.save.party[index]
  local refusal = NpcTrade.check(self.row, mon)
  if refusal then return self:refuse(refusal) end
  -- The flag is set BEFORE the swap, and the cable line before that.
  NpcTrade.markDone(self.save, self.id)
  local bufs = self.eventTables.tradeBuffers or {}
  -- NPCTradeCableText is a bare PrintText (engine/events/npc_trade.asm:37-41):
  -- nothing rings under the cable line.  The sounds all belong to the
  -- animation past it (SFX_GIVE_TRADEMON / SFX_GET_TRADEMON).
  self:sayRaw(self:tradeText("NPCTradeCableText"),
    bufs.NPCTradeCableText,
    function()
      local given, received =
        NpcTrade.perform(self.data, self.save, self.row, index)
      self:playAnim(given, received, function()
        self:sayRaw(self:tradeText("TradedForText"),
          bufs.TradedForText,
          function() self:refuse(NpcTrade.DIALOG_COMPLETE) end)
      end)
    end)
end

-- `predef TradeAnimation`.  It is a whole screen of its own, so it goes on the
-- stack; with no stack to push onto (a headless test) the conversation just
-- carries on, which is what makes the animation skippable in the first place.
function TradeMenu:playAnim(given, received, onDone)
  local game = self.game
  if not (game and game.stack and given) then return onDone() end
  self.animating = true
  Screens.push(game, "Gen2TradeAnim", {
    row = self.row,
    given = given,
    received = received,
    save = self.save,
    eventTables = self.eventTables,
    onDone = function()
      game.stack:pop()
      self.animating = false
      onDone()
    end,
  })
end

function TradeMenu:updateMessage(input)
  Typer.step(self)
  if Typer.typing(self) then return end
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  local message = self.message
  if message.page < #message.pages then
    Typer.turn(self, message)
    return
  end
  self.message = nil
  if message.onDone then message.onDone() end
end

function TradeMenu:updateConfirm(input)
  local confirm = self.confirm
  Typer.step(self)
  if Typer.typing(self) then return end
  if confirm.page < #confirm.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      Typer.turn(self, confirm)
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

function TradeMenu:update(_dt)
  if self.picking or self.animating then return end
  local input = self.game and self.game.input
  if not input then return end
  if self.message then return self:updateMessage(input) end
  if self.confirm then return self:updateConfirm(input) end
end

function TradeMenu:drawTextBox(lines)
  Chrome.box(BOX_X, BOX_Y, BOX_W, BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function TradeMenu:drawYesNo(choice)
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  local data = self.game and self.game.data
  -- home/menu.asm:473
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#1"), YESNO_X + 2, YESNO_Y + 1)
  Chrome.print(RomText(data, "YesNoMenuHeader.MenuData#2"), YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

function TradeMenu:draw()
  local typed = not Typer.typing(self)
  if self.message then
    self:drawTextBox(Typer.text(self, self.message.pages[self.message.page]))
    if typed and self.message.page < #self.message.pages and Typer.arrowOn(self) then
      Chrome.print("\xe2\x96\xbc", ARROW_X, ARROW_Y)
    end
  elseif self.confirm then
    self:drawTextBox(Typer.text(self, self.confirm.pages[self.confirm.page]))
    if typed and self.confirm.page >= #self.confirm.pages then
      self:drawYesNo(self.confirm.choice)
    elseif typed and Typer.arrowOn(self) then
      Chrome.print("\xe2\x96\xbc", ARROW_X, ARROW_Y)
    end
  else
    self:drawTextBox(nil)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return TradeMenu

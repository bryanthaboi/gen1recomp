-- The Game Corner's three prize counters, and the coin case they all read.
--
-- Unlike the slot machine and card flip, these are not engine screens on the
-- cart: each counter is a MAP SCRIPT that opens a static menu, and the whole
-- transaction is script commands the VM already has opcodes for.  The three
-- kinds are:
--
--   coins   GameCornerCoinVendorScript (engine/events/std_scripts.asm) -- the
--           attendant who sells 50 coins for ¥1000 and 500 for ¥10000
--   item    the TM counters (CeladonGameCornerPrizeRoomTMVendor,
--           GoldenrodGameCornerTMVendorScript)
--   mon     the Pokemon counters (CeladonGameCornerPokemonVendor,
--           GoldenrodGameCornerPrizeMonVendorScript)
--
-- Because of that this module is NOT a stack state the game ever pushes and
-- carries no src/ui/Screens.lua id: talking to a vendor runs the extracted
-- script through src/script/gen2/Vm.lua, which has every opcode the three
-- counters use.  What is still read from here is the coin case at the top,
-- which the slot machine and card flip share.
--
-- The rest is kept as a transcription of the counters' own tables, because the
-- ORDER of the checks is what a player notices and what a test can pin down.
-- Those orders are NOT the same:
--
--   item counter  coins are checked, then the player is asked, and only then
--                 is the PACK asked for room, so a full bag is discovered
--                 AFTER saying yes
--   mon counter   coins are checked, then the PARTY is checked, and only then
--                 is the player asked -- a full party never gets the question
--   coin counter  the case is checked for room FIRST and the wallet second, so
--                 a full case is reported even when you could not afford it
--
-- Coordinates are transcribed, never eyeballed.  Every counter's menu header is
-- `menu_coords 0, 2, W, TEXTBOX_Y - 1` (the coin vendor's is `0, 4, 15, 11`)
-- with STATICMENU_CURSOR and no STATICMENU_NO_TOP_SPACING, so
-- GetMenuTextStartCoord (home/menu.asm) puts the first label at box + 1 for the
-- border, + 1 more row for the top spacing and + 1 more column for the cursor:
-- (2,4) for the prize counters, (2,6) for the coin vendor, cursor in column 1,
-- labels two rows apart (PlaceMenuStrings adds 2 * SCREEN_WIDTH per item).
--
-- DisplayCoinCaseBalance (engine/menus/menu_2.asm) is the little box every
-- counter's loop re-prints: Textbox at (11,0) with a 7x1 interior, "COIN" at
-- (12,0) -- yes, in the border row -- and the four-digit count at (13,1).

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local CoinCase = require("src.core.gen2.CoinCase")
local CommonText = require("src.core.gen2.CommonText")
local Font = require("src.render.Font")
local Save = require("src.core.gen2.Save")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local PrizeMenu = {}
PrizeMenu.__index = PrizeMenu
PrizeMenu.isOpaque = true

-- --------------------------------------------------------------- coin case
--
-- engine/events/money.asm GiveCoins / TakeCoins / CheckCoins now live in
-- src/core/gen2/CoinCase.lua: the slot machine and card flip read the same
-- case, and neither of those is a prize counter, so the case is model, not
-- menu.  These names stay here as aliases because they are this module's
-- public API and the coin vendor counter is still the thing that calls them.
PrizeMenu.MAX_COINS = CoinCase.MAX_COINS
PrizeMenu.coins = CoinCase.coins
PrizeMenu.giveCoins = CoinCase.giveCoins
PrizeMenu.takeCoins = CoinCase.takeCoins
PrizeMenu.HAVE_MORE = CoinCase.HAVE_MORE
PrizeMenu.HAVE_AMOUNT = CoinCase.HAVE_AMOUNT
PrizeMenu.HAVE_LESS = CoinCase.HAVE_LESS
PrizeMenu.checkCoins = CoinCase.checkCoins

local function money(save)
  local player = save and save.player
  return (player and player.money) or 0
end

local function setMoney(save, amount)
  local player = save and save.player
  if not player then return end
  player.money = math.max(0, math.min(math.floor(amount or 0), Save.MAX_MONEY))
end

-- ---------------------------------------------------------------- counters
--
-- Prices are the map scripts' own EQU block, kept as the constants they are
-- named after so a reader can find them in the .asm.
--
-- CeladonGameCornerPrizeRoom.asm:
--   TM32 1500  TM29 3500  TM15 7500
--   MR.MIME 3333  EEVEE 6666  PORYGON 9999
-- GoldenrodGameCorner.asm:
--   TM25 5500  TM14 5500  TM38 5500
--   ABRA 200  SANDSHREW 700  EKANS 700  DRATINI 2100
--
-- The Goldenrod Pokemon counter branches on `checkver`: Gold sells EKANS where
-- Silver sells SANDSHREW, which is the only version difference in the room.
-- The item/mon counters keep name and cost as separate fields (rather than
-- one hand-padded label) and `priceRight` says which tile column the price's
-- last digit lands on, so a translated name of a different length than the
-- English original still leaves the price column right-aligned (#1642-adjacent:
-- a translated name used to shift or overlap the padded price that followed it
-- in the same literal).
PrizeMenu.COUNTERS = {
  CELADON_TM = {
    kind = "item",
    menu = { x = 0, y = 2, w = 16, h = 10 },
    priceRight = 13,
    prizes = {
      { id = "TM_DOUBLE_TEAM", name = Strings.source("TM32"), cost = 1500 },
      { id = "TM_PSYCHIC_M",   name = Strings.source("TM29"), cost = 3500 },
      { id = "TM_HYPER_BEAM",  name = Strings.source("TM15"), cost = 7500 },
    },
  },
  CELADON_MON = {
    kind = "mon",
    menu = { x = 0, y = 2, w = 18, h = 10 },
    priceRight = 16,
    prizes = {
      { id = "MR__MIME", name = Strings.source("MR.MIME"), cost = 3333, level = 15 },
      { id = "EEVEE",    name = Strings.source("EEVEE"),   cost = 6666, level = 15 },
      { id = "PORYGON",  name = Strings.source("PORYGON"), cost = 9999, level = 20 },
    },
  },
  GOLDENROD_TM = {
    kind = "item",
    menu = { x = 0, y = 2, w = 16, h = 10 },
    priceRight = 13,
    prizes = {
      { id = "TM_THUNDER",    name = Strings.source("TM25"), cost = 5500 },
      { id = "TM_BLIZZARD",   name = Strings.source("TM14"), cost = 5500 },
      { id = "TM_FIRE_BLAST", name = Strings.source("TM38"), cost = 5500 },
    },
  },
  GOLDENROD_MON = {
    kind = "mon",
    menu = { x = 0, y = 2, w = 18, h = 10 },
    priceRight = 16,
    prizes = {
      { id = "ABRA",    name = Strings.source("ABRA"),    cost = 200,  level = 10 },
      { id = "EKANS",   name = Strings.source("EKANS"),   cost = 700,  level = 10,
        silver = { id = "SANDSHREW", name = Strings.source("SANDSHREW") } },
      { id = "DRATINI", name = Strings.source("DRATINI"), cost = 2100, level = 10 },
    },
  },
  -- GameCornerCoinVendorScript's own menu: `menu_coords 0, 4, 15, TEXTBOX_Y - 1`
  -- and only two entries plus CANCEL.  `checkcoins MAX_COINS - 50` with
  -- HAVE_MORE meaning "full" is how the cart asks whether 50 more will fit.
  COIN_VENDOR = {
    kind = "coins",
    menu = { x = 0, y = 4, w = 16, h = 8 },
    prizes = {
      { amount = 50,  cost = 1000,
        label = Strings.source(" 50 :  \xc2\xa51000") },
      { amount = 500, cost = 10000,
        label = Strings.source("500 : \xc2\xa510000") },
    },
  },
}

-- ------------------------------------------------------------------- text
--
-- The Celadon room and the Goldenrod room use DIFFERENT wording for the same
-- five beats, and the coin vendor a third set again.  All three are transcribed
-- from the map scripts / data/text/std_text.asm; none are in the cache's
-- text.lua, because no script bytecode the extractor walks points at them.
local function sourcedPages(source, ...)
  local args = { ... }
  local rendered = #args > 0 and source:format(unpack(args)) or source
  local value = CommonText.pages(rendered)
  value.source, value.args = source, args
  return value
end

local function sourcedPage(source, ...)
  local value = sourcedPages(source, ...)
  local first = value[1] or {}
  first.source, first.args = value.source, value.args
  return first
end

local function localizedPages(value)
  if not (value and value.source) then return value or {} end
  local translated = #value.args > 0
    and Strings(value.source, unpack(value.args)) or Strings(value.source)
  return CommonText.pages(translated) or {}
end

local function localizedPage(value)
  if not (value and value.source) then return value or {} end
  return localizedPages(value)[1] or {}
end

PrizeMenu.TEXTS = {
  CELADON = {
    -- gs.CeladonGameCornerPrizeRoom.CeladonPrizeRoom_PrizeVendorIntroText:
    -- <PARA> then <LINE> then <CONT> -- the last transition scrolls, it does
    -- not clear to a fresh page.
    intro = sourcedPages(Strings.source(
      "Welcome!\fWe exchange your\ncoins for fabulous\vprizes!")),
    which = sourcedPage(Strings.source("Which prize would\nyou like?")),
    confirm = function(name)
      return sourcedPages(Strings.source("OK, so you wanted\na %s?"), name)
    end,
    hereYouGo = sourcedPages(Strings.source("Here you go!")),
    notEnoughCoins = sourcedPages(Strings.source(
      "You don't have\nenough coins.")),
    noRoom = sourcedPages(Strings.source("You have no room\nfor it.")),
    comeAgain = sourcedPages(Strings.source(
      "Oh. Please come\nback with coins!")),
    noCoinCase = sourcedPages(Strings.source(
      "Oh? You don't have\na COIN CASE.")),
  },
  GOLDENROD = {
    -- gs.GoldenrodGameCorner.GoldenrodGameCornerPrizeVendorIntroText: same
    -- <PARA>/<LINE>/<CONT> shape as Celadon's above.
    intro = sourcedPages(Strings.source(
      "Welcome!\fWe exchange your\ngame coins for\vfabulous prizes!")),
    which = sourcedPage(Strings.source("Which prize would\nyou like?")),
    confirm = function(name)
      return sourcedPages(Strings.source("%s.\nIs that right?"), name)
    end,
    hereYouGo = sourcedPages(Strings.source("Here you go!")),
    notEnoughCoins = sourcedPages(Strings.source(
      "Sorry! You need\nmore coins.")),
    noRoom = sourcedPages(Strings.source(
      "Sorry. You can't\ncarry any more.")),
    -- gs.GoldenrodGameCorner.GoldenrodGameCornerPrizeVendorQuitText:
    -- <LINE> then <CONT>, a scroll, not a fresh page.
    comeAgain = sourcedPages(Strings.source(
      "OK. Please save\nyour coins and\vcome again!")),
    noCoinCase = sourcedPages(Strings.source(
      "Oh? You don't have\na COIN CASE.")),
  },
  COIN_VENDOR = {
    intro = sourcedPages(Strings.source("Welcome to the\nGAME CORNER.")),
    which = sourcedPage(Strings.source("Do you need some\ngame coins?")),
    bought = {
      [50] = sourcedPages(Strings.source("Thank you!\nHere are 50 coins.")),
      [500] = sourcedPages(Strings.source(
        "Thank you! Here\nare 500 coins.")),
    },
    notEnoughMoney = sourcedPages(Strings.source(
      "You don't have\nenough money.")),
    caseFull = sourcedPages(Strings.source(
      "Whoops! Your COIN\nCASE is full.")),
    comeAgain = sourcedPages(Strings.source(
      "No coins for you?\nCome again!")),
    -- gs.std_text.CoinVendor_NoCoinCaseText: <LINE>, <PARA>, <LINE>, <CONT> --
    -- only the last transition scrolls.
    noCoinCase = sourcedPages(Strings.source(
      "Do you need game\ncoins?\fOh, you don't have\na COIN CASE for\vyour coins.")),
  },
}

-- --------------------------------------------------------- pure purchase
--
-- Everything a counter refuses, decided without a screen so a test can drive
-- it.  Returns "ok" or the reason, and never mutates.
--
-- PARTY_LENGTH is 6 (constants/pokemon_data_constants.asm); `readvar
-- VAR_PARTYCOUNT / ifequal PARTY_LENGTH` is the mon counter's room check.
PrizeMenu.PARTY_LENGTH = Save.PARTY_SIZE

PrizeMenu.canAfford = CoinCase.canAfford

-- The room check, split out because the two prize kinds ask different
-- questions and ask them at different points in the conversation.
function PrizeMenu.hasRoom(save, counter, prize, data)
  if counter.kind == "mon" then
    return #((save and save.party) or {}) < PrizeMenu.PARTY_LENGTH
  end
  if counter.kind == "coins" then
    -- `checkcoins MAX_COINS - amount / ifequal HAVE_MORE` -- strictly more than
    -- the headroom is a full case, exactly the headroom still fits.
    return PrizeMenu.checkCoins(save, PrizeMenu.MAX_COINS - prize.amount)
      ~= PrizeMenu.HAVE_MORE
  end
  -- giveitem's own failure: AddItemToInventory refuses when the pocket is full
  -- or the stack would pass 99.  Bag.add is that routine, so ask it directly
  -- against a scratch copy rather than reimplementing the rule.
  local inv = (save and save.inventory) or {}
  local scratch = { inventory = {} }
  for id, count in pairs(inv) do scratch.inventory[id] = count end
  return Bag.add(scratch, prize.id, 1, data or {}) == true
end

-- The whole refusal ladder for one counter, in the cart's order.
-- Returns "ok", "coins", "room", or "money" (the coin vendor only).
function PrizeMenu.check(save, counter, prize, data)
  if counter.kind == "coins" then
    if not PrizeMenu.hasRoom(save, counter, prize, data) then return "room" end
    if money(save) < prize.cost then return "money" end
    return "ok"
  end
  if not PrizeMenu.canAfford(save, prize.cost) then return "coins" end
  if counter.kind == "mon"
      and not PrizeMenu.hasRoom(save, counter, prize, data) then
    return "room"
  end
  return "ok"
end

-- The transaction itself, once the player has said yes.  Item counters do the
-- giveitem BEFORE the takecoins, so a bag that turns out to be full costs
-- nothing; that ordering is what makes "room" a possible answer here too.
function PrizeMenu.buy(save, counter, prize, data, where, game)
  if counter.kind == "coins" then
    local reason = PrizeMenu.check(save, counter, prize, data)
    if reason ~= "ok" then return reason end
    PrizeMenu.giveCoins(save, prize.amount)
    setMoney(save, money(save) - prize.cost)
    return "ok"
  end
  if not PrizeMenu.canAfford(save, prize.cost) then return "coins" end
  if counter.kind == "mon" then
    if not PrizeMenu.hasRoom(save, counter, prize, data) then return "room" end
    local Mon = require("src.battle.gen2.Mon")
    -- ../pokecrystal/engine/pokemon/move_mon.asm:1619
    local species, level, nickname = require("src.core.gen2.Gift").beforeGive(data,
      { game = game, save = save, world = game and game.world }, prize.id, prize.level)
    local mon = Mon.new(data, species, level, { nickname = nickname })
    if not mon then return "room" end
    save.party = save.party or {}
    -- The prize is a `givepoke`, so it takes AddPartyMon's stamp (move_mon.asm:143-149).
    Mon.stampOT(save, mon)
    -- ../pokecrystal/engine/pokemon/move_mon.asm:1761-1773
    local Catching = require("src.battle.gen2.Catching")
    local stamp = { version = save.version, save = save, data = data }
    if type(where) == "table" then
      for key, value in pairs(where) do
        if stamp[key] == nil then stamp[key] = value end
      end
    end
    Catching.stampCaughtData(mon, stamp)
    save.party[#save.party + 1] = mon
    -- `special GameCornerPrizeMonCheckDex` right before the givepoke: the prize
    -- mon is registered as seen and caught even though it never appeared in a
    -- battle.
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[species] = true
    save.pokedex.caught[species] = true
    PrizeMenu.takeCoins(save, prize.cost)
    return "ok"
  end
  if not Bag.add(save, prize.id, 1, data or {}) then return "room" end
  PrizeMenu.takeCoins(save, prize.cost)
  return "ok"
end

-- ------------------------------------------------------------------ layout
local COIN_BOX_X, COIN_BOX_Y, COIN_BOX_W, COIN_BOX_H = 11, 0, 9, 3
local COIN_LABEL_X, COIN_LABEL_Y = 12, 0
local COIN_VALUE_X, COIN_VALUE_Y = 13, 1

local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2

-- YesNoBox: `lb bc, SCREEN_WIDTH - 6, 7` puts a 6x5 box at (14,7), and
-- YesNoMenuHeader carries STATICMENU_CURSOR | STATICMENU_NO_TOP_SPACING, so YES
-- lands at (16,8) and NO at (16,10) with the cursor in column 15.
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

local SFX_TRANSACTION = "Sfx_Transaction"

-- ------------------------------------------------------------------ screen
function PrizeMenu:wantsFillScale() return true end
function PrizeMenu:drawsWidescreen() return true end

-- opts: save, counter (a COUNTERS key or a table), texts (a TEXTS key),
--       version ("gold"/"silver"), data, hasCoinCase (defaults to the bag),
function PrizeMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PrizeMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.data = opts.data or (game and game.data)
  self.where = opts.where
  self.onClose = opts.onClose
  local counter = opts.counter or "CELADON_TM"
  self.counter = type(counter) == "table" and counter
    or PrizeMenu.COUNTERS[counter] or PrizeMenu.COUNTERS.CELADON_TM
  local textKey = opts.texts
    or (self.counter.kind == "coins" and "COIN_VENDOR" or "CELADON")
  self.text = PrizeMenu.TEXTS[textKey] or PrizeMenu.TEXTS.CELADON
  self.version = opts.version or (self.save and self.save.version) or "gold"
  self:buildPrizes()
  self.index = 1
  -- `checkitem COIN_CASE / iffalse` is the very first thing after the intro.
  if opts.hasCoinCase ~= nil then
    self.hasCoinCase = opts.hasCoinCase
  else
    local inv = (self.save and self.save.inventory) or {}
    self.hasCoinCase = (inv.COIN_CASE or 0) > 0
  end
  self:say(self.text.intro, function()
    if not self.hasCoinCase then
      self:say(self.text.noCoinCase, function() self:close() end)
    else
      self:enterMenu()
    end
  end)
  return self
end

-- The Goldenrod mon counter's `checkver` swap, applied once at construction so
-- the menu rows and the purchase agree.
function PrizeMenu:buildPrizes()
  local silver = self.version == "silver"
  local out = {}
  for i, prize in ipairs(self.counter.prizes) do
    if silver and prize.silver then
      local swapped = {}
      for k, v in pairs(prize) do swapped[k] = v end
      swapped.id = prize.silver.id
      swapped.name = prize.silver.name
      swapped.silver = nil
      out[i] = swapped
    else
      out[i] = prize
    end
  end
  -- Every counter's menu data ends with a literal CANCEL row.
  out[#out + 1] = { cancel = true, label = Strings.source("CANCEL") }
  self.prizes = out
end

function PrizeMenu:say(list, onDone)
  self.message = { pages = localizedPages(list), page = 1, onDone = onDone }
end

function PrizeMenu:ask(list, onYes, onNo)
  self.confirm = { pages = localizedPages(list), page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
end

function PrizeMenu:enterMenu()
  self.phase = "menu"
  -- `db 1 ; default option`: the cursor is back on the first prize every pass
  -- through the loop.
  self.index = 1
  self.message = nil
end

function PrizeMenu:close()
  if self.onClose then self.onClose() end
end

function PrizeMenu:cancel()
  self:say(self.text.comeAgain, function() self:close() end)
end

function PrizeMenu:sfx(name)
  if self.data then Sound.play(self.data, name) end
end

function PrizeMenu:prizeName(prize)
  if self.counter.kind == "coins" then
    return ("%d coins"):format(prize.amount)
  end
  local items = self.data and self.data.items
  local mons = self.data and self.data.pokemon
  local def = (self.counter.kind == "mon" and mons or items)
  local entry = def and def[prize.id]
  return (entry and entry.name) or prize.id
end

function PrizeMenu:refuse(reason)
  local text = self.text
  if reason == "coins" then
    self:say(text.notEnoughCoins, function() self:close() end)
  elseif reason == "money" then
    self:say(text.notEnoughMoney, function() self:close() end)
  elseif reason == "room" then
    self:say(text.noRoom or text.caseFull, function() self:close() end)
  end
end

function PrizeMenu:choose()
  local prize = self.prizes[self.index]
  if not prize or prize.cancel then
    self:cancel()
    return
  end
  -- The pre-confirm ladder: coins first for a prize counter, room first for the
  -- coin vendor.  A refusal here ends the conversation, it does not loop.
  local reason = PrizeMenu.check(self.save, self.counter, prize, self.data)
  if reason ~= "ok" then
    self:refuse(reason)
    return
  end
  if self.counter.kind == "coins" then
    -- The coin vendor never asks; it buys straight off the menu.
    self:complete(prize)
    return
  end
  self:ask(self.text.confirm(self:prizeName(prize)),
    function() self:complete(prize) end,
    function() self:cancel() end)
end

-- ../pokecrystal/engine/pokemon/caught_data.asm:177-193
function PrizeMenu:caughtWhere()
  if self.where then return self.where end
  local world = self.game and self.game.world
  if not (world and world.caughtDataOpts) then return nil end
  return world:caughtDataOpts()
end

function PrizeMenu:complete(prize)
  local reason = PrizeMenu.buy(self.save, self.counter, prize, self.data,
    self:caughtWhere(), self.game)
  if reason ~= "ok" then
    self:refuse(reason)
    return
  end
  self:sfx(SFX_TRANSACTION)
  local bought = self.text.bought and self.text.bought[prize.amount]
  self:say(bought or self.text.hereYouGo, function() self:enterMenu() end)
end

function PrizeMenu:updateMessage(input)
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  local message = self.message
  if message.page < #message.pages then
    message.page = message.page + 1
    return
  end
  self.message = nil
  if message.onDone then message.onDone() end
end

function PrizeMenu:updateConfirm(input)
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

function PrizeMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.confirm then
    self:updateConfirm(input)
    return
  end
  if self.message then
    self:updateMessage(input)
    return
  end
  if self.phase ~= "menu" then return end
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.prizes
  elseif input:wasPressed("down") then
    self.index = self.index < #self.prizes and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self:cancel()
  elseif input:wasPressed("a") then
    self:choose()
  end
end

-- ------------------------------------------------------------------- draw
function PrizeMenu:drawCoinBox()
  Chrome.textbox(COIN_BOX_X, COIN_BOX_Y, COIN_BOX_W - 2, COIN_BOX_H - 2)
  Chrome.print(Strings("COIN"), COIN_LABEL_X, COIN_LABEL_Y)
  Chrome.print(Chrome.number(PrizeMenu.coins(self.save), 4, true),
    COIN_VALUE_X, COIN_VALUE_Y)
end

-- Glyph-aware (Font.split), so a multi-byte UTF-8 character or a <PK><MN>
-- macro is never cut mid-sequence: a translated name longer than the tile
-- budget before the price column would otherwise overlap or run into the
-- price digits Chrome.print draws right after it.
local function clampToTiles(text, maxTiles)
  local spans = Font.split(text)
  if #spans <= maxTiles then return text end
  -- maxTiles can land inside a macro's multi-glyph expansion (Font.split's
  -- "#" -> POKé, four spans that all share one source byte's `to`); cutting
  -- there with text:sub would still copy the whole source byte, which
  -- re-expands to all four glyphs on the next Font.split and overshoots the
  -- budget. Back up to the last span whose source byte the next span does
  -- NOT share, so an in-progress expansion is dropped whole rather than
  -- included whole past its budget.
  local cut = maxTiles
  while cut > 0 and spans[cut].to == spans[cut + 1].to do
    cut = cut - 1
  end
  if cut == 0 then return "" end
  return text:sub(1, spans[cut].to)
end

function PrizeMenu:drawPanel()
  Chrome.clear()
  self:drawCoinBox()
  if self.phase == "menu" or self.confirm then
    local menu = self.counter.menu
    Chrome.textbox(menu.x, menu.y, menu.w - 2, menu.h - 2)
    for i, prize in ipairs(self.prizes) do
      local ty = menu.y + 2 + (i - 1) * 2
      if i == self.index then Chrome.cursor(menu.x + 1, ty) end
      if prize.name then
        local priceText = tostring(prize.cost)
        -- -2, not -1: leaves at least one blank tile between the name and
        -- the price, same as the original hand-padded literals always did.
        local nameBudget = self.counter.priceRight - #priceText - 2
        Chrome.print(clampToTiles(Strings(prize.name), nameBudget), menu.x + 2, ty)
        Chrome.print(priceText, menu.x + self.counter.priceRight - #priceText + 1, ty)
      else
        Chrome.print(Strings(prize.label), menu.x + 2, ty)
      end
    end
  end
  local lines = nil
  if self.confirm then
    lines = self.confirm.pages[self.confirm.page]
  elseif self.message then
    lines = self.message.pages[self.message.page]
  elseif self.phase == "menu" then
    lines = localizedPage(self.text.which)
  end
  if lines then
    Chrome.textbox(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W - 2, TEXT_BOX_H - 2)
    for i, line in ipairs(lines) do
      Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
    end
  end
  if self.confirm and self.confirm.page >= #self.confirm.pages then
    Chrome.textbox(YESNO_X, YESNO_Y, YESNO_W - 2, YESNO_H - 2)
    Chrome.print(Strings("YES"), YESNO_X + 2, YESNO_Y + 1)
    Chrome.print(Strings("NO"), YESNO_X + 2, YESNO_Y + 3)
    Chrome.cursor(YESNO_X + 1, YESNO_Y + 1 + (self.confirm.choice - 1) * 2)
  end
end

function PrizeMenu:draw()
  self:drawPanel()
end

function PrizeMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return PrizeMenu

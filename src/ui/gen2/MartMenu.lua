-- Gen 2 POKeMART: the whole clerk conversation (engine/items/mart.asm).
--
-- `pokemart dialog_id, mart_id` (macros/scripts/events.asm) is a BLOCKING
-- script command.  Script_pokemart farcalls OpenMartDialog, which runs the top
-- menu, the buy list and the sell list to completion before the script's next
-- byte is read, so this screen owns the stack while it is up and the VM is
-- parked on its resume exactly the way it is for a battle.
--
-- Four dialog kinds share one buy list (MartTypeDialogs):
--   MARTTYPE_STANDARD  MartDialog   BUY / SELL / QUIT, StandardMart's loop
--   MARTTYPE_BITTER    HerbShop     intro -> BuyMenu -> come again
--   MARTTYPE_BARGAIN   BargainShop  one of each item, at its own prices
--   MARTTYPE_PHARMACY  Pharmacist   intro -> BuyMenu -> come again
-- Only STANDARD sells: SellMenu is reached from its top menu and nowhere else.
--
-- The screen is transcribed from the ASM's own coordinates rather than laid
-- out by eye, because that is what makes it land on the 8px grid:
--
--   MenuHeader_BuySell      menu_coords 0, 0, 11, 8 -- a 12x9 box.  Its flags
--                           are STATICMENU_CURSOR with no
--                           STATICMENU_NO_TOP_SPACING, so GetMenuTextStartCoord
--                           derives BUY at (2,2) with the cursor column at 1,
--                           and the three labels are two rows apart.
--   MoneyTopRightMenuHeader menu_coords 11, 0, 19, 2 -- a 9x3 box, and
--                           PlaceMoneyTextbox writes the amount at
--                           MenuBoxCoord2Tile + SCREEN_WIDTH + 1 = (12,1)
--   MenuHeader_Buy          menu_coords 1, 3, 19, 11 -- a 19x9 rect holding 4
--                           entries of two rows.  BuyMenuLoop copies that
--                           header and calls ScrollingMenu; it never calls
--                           InitScrollingMenu or MenuBox, so the rect is NOT
--                           a framed window.  ScrollingMenu_UpdateDisplay
--                           calls ClearWholeMenuBox on it (spaces, no border)
--                           and starts printing at (2,4); PlaceMenuItemName
--                           prints the name there and .PrintBCDPrices is
--                           handed that origin plus the menu's own width (8)
--                           plus SCREEN_WIDTH, so the price lands at (10,5).
--                           The ▲ sits on the rect's top right (19,3) and
--                           the ▼ on its bottom right (19,11).
--   UpdateItemDescription   Textbox (0,12) interior 18x4 -- a 20x6 box -- with
--                           the description at (1,14)
--   BuyItem_MenuHeader      menu_coords 7, 15, 19, 17 -- a 13x3 box, and
--   SellItem_MenuHeader     the same box.  BuySellToss_UpdateQuantityDisplay
--                           writes '×' at (8,16) and two leading-zero digits
--                           after it; BuySell_DisplaySubtotal's `inc hl` then
--                           puts the running total at (12,16).
--   YesNoBox                `lb bc, SCREEN_WIDTH - 6, 7` -- a 6x5 box at
--                           (14,7).  YesNoMenuHeader sets STATICMENU_CURSOR and
--                           STATICMENU_NO_TOP_SPACING, so YES is at (16,8) and
--                           NO at (16,10), cursor column 15.
--   MoneyBottomLeftMenuHeader
--                           menu_coords 0, 11, 8, 13 -- a 9x3 box with the
--                           amount at (1,12).  The sell flow's two money boxes
--                           are both this rect: PlaceMoneyAtTopLeftOfTextbox
--                           offsets the top-right header by lb de, 0, 11, which
--                           lands on exactly these coordinates.
--
-- Every string below is transcribed literally from data/text/common_2.asm and
-- paired with its pokegold label in LABELS.  Nothing in the ROM's script
-- bytecode points at any of them -- the clerk's lines are printed by the
-- engine, not by a `writetext` -- so the extractor seeds its text walker at
-- the block by name (RomExtractorGen2's NAMED_TEXT) and this screen prefers
-- the cache's own characters, falling back to the transcription for a cache
-- built before that seed.

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")

-- PlayTransactionSound (engine/items/mart.asm): `call WaitSFX` then
-- SFX_TRANSACTION.  Both tills ring it -- the buy flow at BuyMenuLoop's
-- .proceed, just before TakeMoney and MARTTEXT_HERE_YOU_GO, and the sell flow
-- right after MartBoughtText -- so it is the money changing hands rather than
-- either message.  Named the pokegold way; Sound.GEN2_ALIASES is what maps the
-- shared UI's own "Purchase" onto this same label.
local SFX_TRANSACTION = "Sfx_Transaction"

local MartMenu = {}
MartMenu.__index = MartMenu
-- The top menu overlays the mart (StandardMart .HowMayIHelpYou /
-- .AnythingElse: LoadStandardMenuHeader + PrintText).  BuyMenu is
-- FadeToMenu + BlankScreen, so enterBuy shadows this for the list.
MartMenu.isOpaque = false

-- constants/mart_constants.asm.  The `pokemart` macro emits this as one byte
-- ahead of the word mart id, and MartTypeDialogs is indexed by it.
local MART_TYPES = { [0] = "STANDARD", [1] = "BITTER", [2] = "BARGAIN",
  [3] = "PHARMACY" }
local NUM_MARTS = 34 -- constants/mart_constants.asm, MART_UNDERGROUND is 33

-- GetMart: an id at or past NUM_MARTS is not a mart at all and the clerk sells
-- DefaultMart instead (data/items/marts.asm).
local DEFAULT_MART = { "POKE_BALL", "POTION" }

-- MAX_ITEM_STACK, the ceiling StandardMartAskPurchaseQuantity loads into
-- wItemQuantity before the selector runs.
local MAX_ITEM_STACK = 99

-- ---------------------------------------------------------------- layout
local TOP_BOX_X, TOP_BOX_Y, TOP_BOX_W, TOP_BOX_H = 0, 0, 12, 9
local TOP_LABEL_X, TOP_LABEL_Y, TOP_SPACING = 2, 2, 2

local MONEY_BOX_X, MONEY_BOX_Y, MONEY_BOX_W, MONEY_BOX_H = 11, 0, 9, 3
local MONEY_X, MONEY_Y = 12, 1

local MONEY_LOW_BOX_X, MONEY_LOW_BOX_Y = 0, 11
local MONEY_LOW_X, MONEY_LOW_Y = 1, 12

local LIST_BOX_X, LIST_BOX_Y, LIST_BOX_W, LIST_BOX_H = 1, 3, 19, 9
local LIST_X, LIST_Y, LIST_SPACING = 2, 4, 2
local PRICE_X = LIST_X + 8 -- wMenuData_ScrollingMenuWidth
local VISIBLE_ROWS = 4     -- MenuHeader_Buy's `db 4, 8 ; rows, columns`
local ARROW_X = LIST_BOX_X + LIST_BOX_W - 1
local ARROW_UP_Y, ARROW_DOWN_Y = LIST_BOX_Y, LIST_BOX_Y + LIST_BOX_H - 1

local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
-- TEXTBOX_INNERY is TEXTBOX_Y + 2 and LineChar (`line`, $4f) targets
-- TEXTBOX_INNERY + 2, so a text box's two lines are TWO rows apart -- which is
-- also where <NEXT> ($4e, SCREEN_WIDTH * 2) puts an item description's second
-- line.  One rule covers both.
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2

local QTY_BOX_X, QTY_BOX_Y, QTY_BOX_W, QTY_BOX_H = 7, 15, 13, 3
local QTY_X, QTY_Y = 8, 16
local QTY_PRICE_X = 12

local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

-- charmap.asm: × is the quantity glyph, ¥ the currency one, and ▲ / ▼ are the
-- scrolling menu's own arrow tiles (font codes $61 and $ee).
local TIMES = "\xc3\x97"
local YEN = "\xc2\xa5"
local UP_ARROW = "\xe2\x96\xb2"
local DOWN_ARROW = "\xe2\x96\xbc"

-- PrintNum with PRINTNUM_MONEY and without PRINTNUM_LEADINGZEROS
-- (home/print_num.asm .PrintYen): the ¥ is emitted just before the FIRST
-- significant digit rather than at a fixed column, and the field is six digits
-- wide -- so the string is always seven tiles and the yen sign floats.
-- PrintBCDNumber, which the buy list's prices go through, prints the same
-- shape: a leading zero becomes a space and still advances the pointer.
local function moneyText(amount)
  local digits = ("%06d"):format(math.max(0, math.floor(amount or 0)))
  local first = digits:find("[1-9]") or #digits
  return (" "):rep(first - 1) .. YEN .. digits:sub(first)
end
MartMenu.moneyText = moneyText

-- ----------------------------------------------------------------- text
--
-- A "page" is one screenful of the speech text box: up to two lines, `line`
-- rows apart.  A `para` in the ASM starts a new page; a `cont` scrolls one
-- line, which shows as a page whose first line is the previous page's second.
local function pages(...) return { ... } end
local function page(...) return { ... } end

local TEXTS = {
  -- MartDialog / StandardMart (engine/items/mart.asm).
  STANDARD = {
    welcome   = page("Welcome! How may I", "help you?"),   -- MartWelcomeText
    askMore   = page("Can I do anything", "else for you?"), -- MartAskMoreText
    comeAgain = pages(page("Please come again!")),
    howMany   = page("How many?"),
    thanks    = pages(page("Here you are.", "Thank you!")),
    noMoney   = pages(page("You don't have", "enough money.")),
    packFull  = pages(page("You can't carry", "any more items.")),
    -- MartFinalPriceText: the quantity and the total are text_decimal, which
    -- sets PRINTNUM_LEFTALIGN, so neither is padded; the ¥ is a literal in the
    -- string rather than PrintNum's floating one.
    finalPrice = function(qty, name, total)
      return pages(page(("%d %s(S)"):format(qty, name),
        ("will be %s%d."):format(YEN, total)))
    end,
  },
  -- HerbShop (MARTTYPE_BITTER): the Goldenrod Underground herb lady.
  BITTER = {
    intro = pages(
      page("Hello, dear."),
      page("I sell inexpensive", "herbal medicine."),
      page("They're good, but", "a trifle bitter."),
      -- `#` is the four-tile POKé compression byte, which the extractor
      -- expands everywhere else in the cache; spelled out it is the same
      -- sixteen columns.
      page("Your POKéMON may", "not like them."),
      page("Hehehehe…")),
    comeAgain = pages(page("Come again, dear.", "Hehehehe…")),
    howMany   = page("How many?"),
    thanks    = pages(page("Thank you, dear.", "Hehehehe…")),
    noMoney   = pages(page("Hehehe… You don't", "have the money.")),
    packFull  = pages(page("Oh? Your PACK is", "full, dear.")),
    finalPrice = function(qty, name, total)
      return pages(page(("%d %s(S)"):format(qty, name),
        ("will be %s%d."):format(YEN, total)))
    end,
  },
  -- BargainShop (MARTTYPE_BARGAIN): one of each item, at prices carried by
  -- BargainShopData rather than by ItemAttributes.
  BARGAIN = {
    intro = pages(
      page("Hiya! Care to see", "some bargains?"),
      page("I sell rare items", "that nobody else"),
      page("carries--but only", "one of each item.")),
    comeAgain = pages(page("Come by again", "sometime.")),
    thanks    = pages(page("Thanks.")),
    noMoney   = pages(page("Uh-oh, you're", "short on funds.")),
    packFull  = pages(page("Uh-oh, your PACK", "is chock-full.")),
    -- `cont` scrolls the box one line instead of clearing it, so the second
    -- page opens on the first page's second line.
    soldOut = pages(
      page("You bought that", "already. I'm all"),
      page("already. I'm all", "sold out of it.")),
    finalPrice = function(_qty, name, total)
      return pages(page(("%s costs"):format(name),
        ("%s%d. Want it?"):format(YEN, total)))
    end,
  },
  -- Pharmacist (MARTTYPE_PHARMACY): Cianwood.
  PHARMACY = {
    intro     = pages(page("What's up? Need", "some medicine?")),
    comeAgain = pages(page("All right.", "See you around.")),
    howMany   = page("How many?"),
    thanks    = pages(page("Thanks much!")),
    noMoney   = pages(page("Huh? That's not", "enough money.")),
    packFull  = pages(page("You don't have any", "more space.")),
    finalPrice = function(qty, name, total)
      return pages(page(("%d %s(S)"):format(qty, name),
        ("will cost %s%d."):format(YEN, total)))
    end,
  },
}

-- SellMenu's own strings.  Only MARTTYPE_STANDARD ever reaches them.
local SELL_TEXTS = {
  cantBuy    = pages(page("Sorry, I can't buy", "that from you.")),
  howMany    = page("How many?"),
  -- MartSellPriceText's `para` is a real page break, and the YES/NO box comes
  -- up on the second page without a further press.
  price = function(total)
    return pages(page("I can pay you", ("%s%d."):format(YEN, total)),
      page("Is that OK?"))
  end,
  bought = function(name, total)
    return pages(page(("Got %s%d for"):format(YEN, total),
      ("%s(S)."):format(name)))
  end,
}

MartMenu.MART_TYPES = MART_TYPES
MartMenu.TEXTS = TEXTS

-- ...and the data/text/common_2.asm label behind each of those entries.
-- Nothing in the ROM's bytecode points at any of them -- the clerk's lines are
-- printed by engine/items/mart.asm itself -- so the extractor seeds its text
-- walker at the whole block by name (RomExtractorGen2's NAMED_TEXT) and this
-- screen prefers the cache's own characters.  The transcriptions above are
-- what a cache built before that seed falls back to.
local LABELS = {
  STANDARD = {
    welcome = "_MartWelcomeText", askMore = "_MartAskMoreText",
    comeAgain = "_MartComeAgainText", howMany = "_MartHowManyText",
    thanks = "_MartThanksText", noMoney = "_MartNoMoneyText",
    packFull = "_MartPackFullText", finalPrice = "_MartFinalPriceText",
  },
  BITTER = {
    intro = "_HerbShopLadyIntroText", comeAgain = "_HerbalLadyComeAgainText",
    howMany = "_HerbalLadyHowManyText", thanks = "_HerbalLadyThanksText",
    noMoney = "_HerbalLadyNoMoneyText", packFull = "_HerbalLadyPackFullText",
    finalPrice = "_HerbalLadyFinalPriceText",
  },
  BARGAIN = {
    intro = "_BargainShopIntroText", comeAgain = "_BargainShopComeAgainText",
    thanks = "_BargainShopThanksText", noMoney = "_BargainShopNoFundsText",
    packFull = "_BargainShopPackFullText", soldOut = "_BargainShopSoldOutText",
    finalPrice = "_BargainShopFinalPriceText",
  },
  PHARMACY = {
    intro = "_PharmacyIntroText", comeAgain = "_PharmacyComeAgainText",
    howMany = "_PharmacyHowManyText", thanks = "_PharmacyThanksText",
    noMoney = "_PharmacyNoMoneyText", packFull = "_PharmacyPackFullText",
    finalPrice = "_PharmacyFinalPriceText",
  },
  SELL = {
    cantBuy = "_MartCantBuyText", howMany = "_MartSellHowManyText",
    price = "_MartSellPriceText", bought = "_MartBoughtText",
  },
}

MartMenu.LABELS = LABELS

-- The three entries that are ONE screenful of lines rather than a list of
-- pages, because they sit under a menu instead of paging: the welcome line
-- the BUY/SELL/QUIT box opens over, the one it reopens over, and the "How
-- many?" prompt the quantity box sits under.
local SINGLE_PAGE = { welcome = true, askMore = true, howMany = true }

-- The formatted entries, keyed by LABEL rather than by entry name, because
-- the markers come in the string's order and the bargain shop names its item
-- FIRST ("X costs ¥N. Want it?") where the other three clerks lead with the
-- quantity.
local FILL = {
  _MartFinalPriceText = function(qty, name, total)
    return { qty, name, total }
  end,
  _HerbalLadyFinalPriceText = function(qty, name, total)
    return { qty, name, total }
  end,
  _PharmacyFinalPriceText = function(qty, name, total)
    return { qty, name, total }
  end,
  _BargainShopFinalPriceText = function(_qty, name, total)
    return { name, total }
  end,
  _MartSellPriceText = function(total) return { total } end,
  _MartBoughtText = function(name, total) return { total, name } end,
}

-- One dialog's table with every entry the cache carries replaced by the
-- extracted string.  Anything missing falls through the metatable to the
-- transcription, so a partial cache is a mix rather than a hole.
local function extractedText(text, base, labels)
  local out = setmetatable({}, { __index = base })
  for key, label in pairs(labels or {}) do
    local list = CommonText.of(text, label)
    if list then
      local fill = FILL[label]
      if fill then
        out[key] = function(...) return CommonText.fill(list, fill(...)) end
      elseif SINGLE_PAGE[key] then
        out[key] = list[1]
      else
        out[key] = list
      end
    end
  end
  return out
end

-- data/generated/marts.lua is what the ROM extractor will write out of `Marts`
-- (data/items/marts.asm): `lists` is a 1-based array in MART_* order, each
-- entry an array of item ids, and `bargain` is BargainShopData's own
-- item/price rows.  A flat top-level array is accepted too, because that is
-- the shape items.lua uses and an extractor may well write it the same way.
--
-- Nothing is guessed when the table is absent: an id inside the table's range
-- with no row falls back to DefaultMart the way GetMart does, and a missing
-- table leaves the shelf empty rather than inventing stock.
function MartMenu.inventory(marts, martId)
  martId = martId or 0
  if martId >= NUM_MARTS then return DEFAULT_MART end
  if type(marts) ~= "table" then return {} end
  local lists = marts.lists or marts
  local list = lists[martId + 1]
  if type(list) ~= "table" then return DEFAULT_MART end
  return list
end

-- BargainShopData is loaded by BargainShop itself, not by the mart id, so the
-- opcode's mart id is ignored for MARTTYPE_BARGAIN.
function MartMenu.bargainRows(marts)
  local rows = type(marts) == "table" and marts.bargain
  if type(rows) ~= "table" then return {} end
  return rows
end

-- opts: save, items (items.lua), marts (marts.lua), martType (MARTTYPE_*
-- number or name), martId (number), text (text.lua, for the extracted
-- strings), onClose()
function MartMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MartMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.items = opts.items or (game and game.data and game.data.items)
  self.marts = opts.marts or (game and game.data and game.data.gen2Marts)
  -- The dialog byte, or the MARTTYPE_* name spelled out (which is what a test
  -- reads more clearly).  Anything unrecognised is MartDialog, the way
  -- MartTypeDialogs' jumptable would land on entry 0.
  local kind = opts.martType or 0
  if type(kind) == "string" then
    self.martType = TEXTS[kind] and kind or "STANDARD"
  else
    self.martType = MART_TYPES[kind] or "STANDARD"
  end
  self.martId = opts.martId or 0
  self.onClose = opts.onClose
  -- text.lua rides on the world, the way the Pokegear's phone strings do: the
  -- mart is opened by a script running on a map and never without one.
  self.textData = opts.text or (game and game.world and game.world.text)
  self.text = extractedText(self.textData,
    TEXTS[self.martType], LABELS[self.martType])
  self.sellText = extractedText(self.textData, SELL_TEXTS, LABELS.SELL)
  self.index = 1
  self.scroll = 0
  self:buildEntries()
  if self.martType == "STANDARD" then
    -- .HowMayIHelpYou prints into the speech box and returns TOPMENU without
    -- waiting: the welcome line is still on screen under the BUY/SELL/QUIT
    -- menu, which is what the mart looks like on the cart.
    self.phase = "top"
    self.topLines = self.text.welcome
    self.topIndex = 1
  else
    -- HerbShop / BargainShop / Pharmacist: intro, then straight into BuyMenu.
    self.phase = "intro"
    self:say(self.text.intro, function() self:enterBuy() end)
  end
  return self
end

-- The shelf.  A standard mart prices each row out of ItemAttributes
-- (GetMartItemPrice -> GetItemPrice); the bargain shop carries its own price
-- per row and sells one of each, tracked by wBargainShopFlags.
function MartMenu:buildEntries()
  local entries = {}
  if self.martType == "BARGAIN" then
    local sold = (self.save and self.save.bargainShop) or {}
    for _, row in ipairs(MartMenu.bargainRows(self.marts)) do
      local id = row.item or row.id or row[1]
      local def = id and self.items and self.items[id]
      entries[#entries + 1] = {
        id = id,
        name = (def and def.name) or id or "?",
        price = row.price or row[2] or 0,
        soldOut = sold[id] == true,
      }
    end
  else
    for _, id in ipairs(MartMenu.inventory(self.marts, self.martId)) do
      local def = self.items and self.items[id]
      entries[#entries + 1] = {
        id = id,
        name = (def and def.name) or id,
        price = (def and def.price) or 0,
      }
    end
  end
  self.entries = entries
end

-- ----------------------------------------------------------------- money
function MartMenu:money()
  local player = self.save and self.save.player
  return (player and player.money) or 0
end

-- GiveMoney clamps at MaxMoney and TakeMoney clamps at zero
-- (engine/events/money.asm); one clamp covers both directions.
function MartMenu:setMoney(amount)
  local player = self.save and self.save.player
  if not player then return end
  player.money = math.max(0, math.min(math.floor(amount or 0), Save.MAX_MONEY))
end

-- BuySell_MultiplyPrice: the running total is unit * quantity.
function MartMenu.buyPrice(unit, qty)
  return (unit or 0) * (qty or 1)
end

-- Sell_HalvePrice shifts the 24-bit PRODUCT right once, so the halving happens
-- after the multiply -- selling two of an odd-priced item is not the same as
-- twice half its price, and this is the half a player notices.
function MartMenu.sellPrice(unit, qty)
  return math.floor((unit or 0) * (qty or 1) / 2)
end

-- ---------------------------------------------------------------- overlays
--
-- `say` is PrintText plus the JoyWaitAorB that follows it everywhere in
-- mart.asm: the box holds until a button, and multi-page strings advance a
-- page per press.
function MartMenu:say(list, onDone)
  self.message = { pages = list or {}, page = 1, onDone = onDone }
end

function MartMenu:updateMessage(input)
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  local message = self.message
  if message.page < #message.pages then
    message.page = message.page + 1
    return
  end
  self.message = nil
  if message.onDone then message.onDone() end
end

-- MartConfirmPurchase / the sell flow's YesNoBox.  The prompt's last page is
-- the one the box sits on; earlier pages advance on a press first.
function MartMenu:ask(list, onYes, onNo)
  self.confirm = { pages = list or {}, page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
end

function MartMenu:updateConfirm(input)
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

-- ---------------------------------------------------------------- top menu
local TOP_ITEMS = { "BUY", "SELL", "QUIT" }

-- .TopMenu copies MenuHeader_BuySell fresh every pass, and its `db 1 ; default
-- option` means the cursor is back on BUY each time the loop returns here.
function MartMenu:enterTop(lines)
  self.phase = "top"
  self.topLines = lines or self.text.askMore
  self.topIndex = 1
end

function MartMenu:updateTop(input)
  if input:wasPressed("up") then
    self.topIndex = self.topIndex > 1 and self.topIndex - 1 or #TOP_ITEMS
    return
  elseif input:wasPressed("down") then
    self.topIndex = self.topIndex < #TOP_ITEMS and self.topIndex + 1 or 1
    return
  elseif input:wasPressed("b") then
    self:quit()
    return
  elseif input:wasPressed("a") then
    if self.topIndex == 1 then
      self:enterBuy()
    elseif self.topIndex == 2 then
      self:enterSell()
    else
      self:quit()
    end
  end
end

-- .Quit: the come-again line, then STANDARDMART_EXIT.
function MartMenu:quit()
  self.phase = "outro"
  self:say(self.text.comeAgain, function()
    if self.onClose then self.onClose() end
  end)
end

-- ---------------------------------------------------------------- buy list
--
-- BuyMenu resets wMenuCursorPositionBackup / wMenuScrollPositionBackup on
-- entry and restores them around every purchase, so the cursor survives a sale
-- but not a trip back through the top menu.
function MartMenu:enterBuy()
  self.phase = "buy"
  self.index = 1
  self.scroll = 0
  -- BuyMenu (engine/items/mart.asm): `call FadeToMenu / farcall BlankScreen`.
  -- BlankScreen fills the tilemap with spaces and the palettes with white, so
  -- the mart must not keep drawing in the letterbox under the list.
  self.isOpaque = (self.phase == "buy")
end

function MartMenu:total()
  return #self.entries + 1 -- the -1 terminator draws as CANCEL
end

function MartMenu:isCancel()
  return self.index > #self.entries
end

function MartMenu:selected()
  return self.entries[self.index]
end

function MartMenu:ensureVisible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, self:total() - VISIBLE_ROWS)))
end

function MartMenu:updateBuy(input)
  -- _2DMENU_EXIT_UP / _2DMENU_EXIT_DOWN with .d_up refusing to move at scroll
  -- zero: the buy list does NOT wrap the way the PACK's does.
  if input:wasPressed("up") then
    if self.index > 1 then
      self.index = self.index - 1
      self:ensureVisible()
    end
    return
  elseif input:wasPressed("down") then
    if self.index < self:total() then
      self.index = self.index + 1
      self:ensureVisible()
    end
    return
  elseif input:wasPressed("b") then
    self:leaveBuy()
    return
  elseif input:wasPressed("a") then
    -- .a_button treats a -1 selection as B, so A on CANCEL leaves the list.
    if self:isCancel() then
      self:leaveBuy()
    else
      self:offerToBuy()
    end
  end
end

-- BuyMenu returns into StandardMart .Buy, which falls through to
-- .AnythingElse; the other three dialog kinds end on their come-again line.
function MartMenu:leaveBuy()
  -- CloseSubmenu restores the map before .AnythingElse / the come-again line.
  self.isOpaque = nil
  if self.martType == "STANDARD" then
    self:enterTop(self.text.askMore)
  else
    self:quit()
  end
end

function MartMenu:offerToBuy()
  local entry = self:selected()
  if not entry then return end
  if self.martType == "BARGAIN" then
    -- BargainShopAskPurchaseQuantity: one of each, no quantity selector, and a
    -- CHECK_FLAG on wBargainShopFlags ahead of everything else.
    if entry.soldOut then
      self:say(self.text.soldOut)
      return
    end
    self.qtyItem = entry
    self.qty = 1
    self.qtyMax = 1
    self:confirmPurchase()
    return
  end
  self.qtyItem = entry
  self.qty = 1
  self.qtyMax = MAX_ITEM_STACK
  self.phase = "buyQuantity"
end

function MartMenu:confirmPurchase()
  local entry = self.qtyItem
  local total = MartMenu.buyPrice(entry.price, self.qty)
  self:ask(self.text.finalPrice(self.qty, entry.name, total),
    function() self:completePurchase(total) end,
    function() self:cancelPurchase() end)
end

-- .cancel simply redraws the speech box and drops back into the buy loop with
-- the cursor where it was, so this keeps index/scroll.
function MartMenu:cancelPurchase()
  self.phase = "buy"
end

-- PlayTransactionSound.  A driver can run this screen with no audio table at
-- all, so a missing one is silence rather than an error.
function MartMenu:playTransaction()
  local data = self.game and self.game.data
  if data then Sound.play(data, SFX_TRANSACTION) end
end

-- BuyMenuLoop's order matters: money is compared BEFORE the bag is asked for
-- room, so a broke player is told about the money and never about the PACK.
function MartMenu:completePurchase(total)
  local entry = self.qtyItem
  if self:money() < total then
    self.phase = "buy"
    self:say(self.text.noMoney)
    return
  end
  local ok = Bag.add(self.save, entry.id, self.qty,
    self.game and self.game.data)
  if not ok then
    self.phase = "buy"
    self:say(self.text.packFull)
    return
  end
  if self.martType == "BARGAIN" then
    -- FlagAction SET_FLAG on wBargainShopFlags.  The cart mirrors this into
    -- DAILYFLAGS1_GOLDENROD_UNDERGROUND_BARGAIN on the way out so the stock
    -- comes back with the day; the daily rollover is not modelled here, so the
    -- flag simply lives on the save.
    self.save.bargainShop = self.save.bargainShop or {}
    self.save.bargainShop[entry.id] = true
    entry.soldOut = true
  end
  -- .proceed's order: the bargain flag, PlayTransactionSound, TakeMoney, and
  -- only then MARTTEXT_HERE_YOU_GO.  The till rings on the money moving, not
  -- on the clerk's line.
  self:playTransaction()
  self:setMoney(self:money() - total)
  self.phase = "buy"
  self:say(self.text.thanks)
end

-- --------------------------------------------------------- quantity picker
--
-- BuySellToss_InterpretJoypad (engine/items/buy_sell_toss.asm).  Up and down
-- WRAP through the ends; left and right step by ten and CLAMP instead -- left
-- past 1 lands on 1, right past the ceiling lands on the ceiling.
function MartMenu:quantityStep(delta)
  local n = self.qty + delta
  if delta == 1 then
    if n > self.qtyMax then n = 1 end
  elseif delta == -1 then
    if n < 1 then n = self.qtyMax end
  elseif delta > 0 then
    if n > self.qtyMax then n = self.qtyMax end
  else
    if n <= 0 then n = 1 end
  end
  self.qty = n
end

function MartMenu:updateQuantity(input, onAccept, onCancel)
  if input:wasPressed("up") then
    self:quantityStep(1)
  elseif input:wasPressed("down") then
    self:quantityStep(-1)
  elseif input:wasPressed("right") then
    self:quantityStep(10)
  elseif input:wasPressed("left") then
    self:quantityStep(-10)
  elseif input:wasPressed("b") then
    onCancel()
  elseif input:wasPressed("a") then
    onAccept()
  end
end

-- --------------------------------------------------------------- sell flow
--
-- SellMenu opens DepositSellPack -- the PACK itself, in a mode where A means
-- "sell this" rather than "use this".  `world = {}` is a world with no
-- useFieldItem, so PackMenu:useSelected falls straight through to onChoose and
-- no field effect can fire from inside a shop.
--
-- The PACK is held rather than stacked, so this is Screens.build, not
-- Screens.push: same id, same registry lookup and same mod-screen degrade, but
-- the mart keeps drawing and updating it itself.
function MartMenu:enterSell()
  self.phase = "sell"
  self.pack = Screens.build(self.game, "Gen2PackMenu", {
    save = self.save,
    items = self.items,
    world = {},
    onChoose = function(itemId, count) self:offerToSell(itemId, count) end,
    onClose = function() self:leaveSell() end,
  })
end

function MartMenu:leaveSell()
  self.pack = nil
  self:enterTop(self.text.askMore)
end

-- .TryToSellItem: CheckItemMenu's field-menu value routes everything the PACK
-- can hold to .try_sell, and _CheckTossableItem is the real gate -- a CANT_TOSS
-- item (every KEY ITEM, and the HMs) gets MartCantBuyText and nothing else.
function MartMenu:offerToSell(itemId, count)
  local def = self.items and self.items[itemId]
  if not def or def.canToss == false then
    self:say(self.sellText.cantBuy)
    return
  end
  -- Nothing in stock is not a sale: the PACK only lists rows it holds, and a
  -- zero count would otherwise walk the selector's ceiling down to nothing.
  if (count or 0) < 1 then
    self:say(self.sellText.cantBuy)
    return
  end
  -- ScrollingMenu's .a_button copies the row's own quantity into
  -- wItemQuantity, so the selector's ceiling is how many you hold.
  -- The unit price is the item's own ItemAttributes price: GetItemPrice is
  -- what SelectQuantityToSell halves AND what the buy list's
  -- GetMartItemPrice charges, so a TM sells for exactly half of what the
  -- Goldenrod/Celadon TM shelves ask for it, and half of its hidden price
  -- (usually ¥1,500) anywhere else (issue #1243).
  self.qtyItem = { id = itemId, name = def.name or itemId,
    price = def.price or 0 }
  self.qty = 1
  self.qtyMax = count
  self.phase = "sellQuantity"
end

function MartMenu:confirmSale()
  local total = MartMenu.sellPrice(self.qtyItem.price, self.qty)
  self:ask(self.sellText.price(total),
    function() self:completeSale(total) end,
    function() self.phase = "sell" end)
end

function MartMenu:completeSale(total)
  local entry = self.qtyItem
  self:setMoney(self:money() + total)
  Bag.remove(self.save, entry.id, self.qty)
  if self.pack then self.pack:rebuild() end
  self.phase = "sell"
  -- The sell side calls PlayTransactionSound after MartBoughtText rather than
  -- before it, but both land on the same frame here: the say() only queues the
  -- page the update loop draws.
  self:playTransaction()
  self:say(self.sellText.bought(entry.name, total))
end

-- ----------------------------------------------------------------- update
function MartMenu:update(dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.message then
    self:updateMessage(input)
    return
  end
  if self.confirm then
    self:updateConfirm(input)
    return
  end
  local phase = self.phase
  if phase == "top" then
    self:updateTop(input)
  elseif phase == "buy" then
    self:updateBuy(input)
  elseif phase == "buyQuantity" then
    self:updateQuantity(input,
      function() self:confirmPurchase() end,
      function() self.phase = "buy" end)
  elseif phase == "sell" then
    if self.pack then self.pack:update(dt) end
  elseif phase == "sellQuantity" then
    self:updateQuantity(input,
      function() self:confirmSale() end,
      function() self.phase = "sell" end)
  end
end

-- ------------------------------------------------------------------- draw
function MartMenu:drawTextBox(lines)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function MartMenu:drawMoneyBox()
  Chrome.box(MONEY_BOX_X, MONEY_BOX_Y, MONEY_BOX_W, MONEY_BOX_H)
  Chrome.print(moneyText(self:money()), MONEY_X, MONEY_Y)
end

-- PlaceMoneyBottomLeft / PlaceMoneyAtTopLeftOfTextbox land on the same rect.
function MartMenu:drawMoneyBoxLow()
  Chrome.box(MONEY_LOW_BOX_X, MONEY_LOW_BOX_Y, MONEY_BOX_W, MONEY_BOX_H)
  Chrome.print(moneyText(self:money()), MONEY_LOW_X, MONEY_LOW_Y)
end

function MartMenu:drawTopMenu()
  Chrome.box(TOP_BOX_X, TOP_BOX_Y, TOP_BOX_W, TOP_BOX_H)
  for i, label in ipairs(TOP_ITEMS) do
    local ty = TOP_LABEL_Y + (i - 1) * TOP_SPACING
    if i == self.topIndex then Chrome.cursor(TOP_LABEL_X - 1, ty) end
    Chrome.print(label, TOP_LABEL_X, ty)
  end
end

-- The description under the buy list.  A TM prints the MOVE's description on
-- the cart (PrintItemDescription branches at TM01 into PrintMoveDescription),
-- which is the same rule the PACK follows.
function MartMenu:description()
  local entry = self:selected()
  if not entry then return nil end
  local def = self.items and self.items[entry.id]
  if def and def.teaches then
    local moves = self.game and self.game.data and self.game.data.moves
    local moveDef = moves and moves[def.teaches]
    if moveDef and moveDef.description then return moveDef.description end
  end
  return def and def.description or nil
end

-- The bottom visible entry's price row is MenuHeader_Buy's last line
-- (entry row 10 + SCREEN_WIDTH = 11).  A GB glyph REPLACES the tile it
-- prints over, so white under the seven money tiles first is that
-- replacement.  On a BlankScreen field it is white over white.
local function printPriceOpaque(amount, ty)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", PRICE_X * 8, ty * 8, 7 * 8, 8)
  G.setColor(0, 0, 0, 1)
  Chrome.print(moneyText(amount), PRICE_X, ty)
end

function MartMenu:drawBuyList()
  -- ScrollingMenu_UpdateDisplay (engine/menus/scrolling_menu.asm) calls
  -- ClearWholeMenuBox, not MenuBox: the MenuHeader_Buy rect is a cleared
  -- field, not a framed window.  BlankScreen already filled the tilemap
  -- with spaces, so the names just land on white.
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local ty = LIST_Y + (row - 1) * LIST_SPACING
    if i <= #self.entries then
      local entry = self.entries[i]
      if i == self.index then Chrome.cursor(LIST_X - 1, ty) end
      Chrome.print(entry.name, LIST_X, ty)
      printPriceOpaque(entry.price, ty + 1)
    elseif i == self:total() then
      if i == self.index then Chrome.cursor(LIST_X - 1, ty) end
      Chrome.print("CANCEL", LIST_X, ty)
    end
  end
  -- SCROLLINGMENU_DISPLAY_ARROWS: the ▲ only appears once the list has been
  -- scrolled, but the ▼ is written every pass whether or not there is more
  -- below it.
  if self.scroll > 0 then
    Chrome.print(UP_ARROW, ARROW_X, ARROW_UP_Y)
  end
  Chrome.print(DOWN_ARROW, ARROW_X, ARROW_DOWN_Y)
end

function MartMenu:drawDescription()
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  if self:isCancel() then return end
  local description = self:description()
  if not description then return end
  -- The extractor leaves the description's own '<NEXT>' in place, and $4e
  -- steps SCREEN_WIDTH * 2 from the line's start (home/text.asm
  -- NextLineChar) -- which is the TEXT_LINE both rows already use.  '\n'
  -- covers hand-written data.
  local first, second = description:match("^(.-)<NEXT>(.*)$")
  if not first then first, second = description:match("^(.-)\n(.*)$") end
  Chrome.print(first or description, TEXT_X, TEXT_Y)
  if second then Chrome.print(second, TEXT_X, TEXT_Y + TEXT_LINE) end
end

function MartMenu:drawQuantityBox(total)
  Chrome.box(QTY_BOX_X, QTY_BOX_Y, QTY_BOX_W, QTY_BOX_H)
  Chrome.print(TIMES, QTY_X, QTY_Y)
  -- `lb bc, PRINTNUM_LEADINGZEROS | 1, 2`: two digits, zero padded.
  Chrome.print(Chrome.number(self.qty, 2, true), QTY_X + 1, QTY_Y)
  Chrome.print(moneyText(total), QTY_PRICE_X, QTY_Y)
end

function MartMenu:drawYesNo(choice)
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  Chrome.print("YES", YESNO_X + 2, YESNO_Y + 1)
  Chrome.print("NO", YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

-- Whatever the overlays sit on top of.
function MartMenu:drawUnder()
  local phase = self.phase
  if phase == "top" then
    self:drawTopMenu()
    self:drawTextBox(self.topLines)
  elseif phase == "buy" or phase == "buyQuantity" then
    -- BlankScreen (engine/overworld/player_object.asm): the whole tilemap
    -- is spaces before PlaceMoneyTopRight / the scrolling list / the
    -- description textbox go down.  Only those last two are framed.
    Chrome.clear()
    self:drawMoneyBox()
    self:drawBuyList()
    self:drawDescription()
  elseif phase == "sell" or phase == "sellQuantity" then
    if self.pack then self.pack:drawPanel() end
  end
end

function MartMenu:drawPanel()
  self:drawUnder()

  if self.phase == "buyQuantity" and not (self.message or self.confirm) then
    -- StandardMartAskPurchaseQuantity prints MARTTEXT_HOW_MANY first, then the
    -- selector is drawn over the bottom of that box.
    self:drawTextBox(self.text.howMany)
    self:drawQuantityBox(MartMenu.buyPrice(self.qtyItem.price, self.qty))
  elseif self.phase == "sellQuantity" and not (self.message or self.confirm) then
    self:drawTextBox(self.sellText.howMany)
    -- .okay_to_sell prints the question, THEN drops the money box on its top
    -- left corner, so the box wins where they overlap.
    self:drawMoneyBoxLow()
    self:drawQuantityBox(MartMenu.sellPrice(self.qtyItem.price, self.qty))
  end

  if self.message then
    self:drawTextBox(self.message.pages[self.message.page])
    -- LoadBlinkingCursor puts the ▼ at hlcoord 18, 17 while a `para` waits.
    if self.message.page < #self.message.pages then
      Chrome.print(DOWN_ARROW, 18, 17)
    end
  elseif self.confirm then
    self:drawTextBox(self.confirm.pages[self.confirm.page])
    if self.confirm.page >= #self.confirm.pages then
      self:drawYesNo(self.confirm.choice)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function MartMenu:draw()
  self:drawPanel()
end

return MartMenu

-- Mom spends the money she is saving for you.
--
-- engine/events/mom_phone.asm, with data/items/mom_phone.asm beside it.  This
-- is the other end of Bank of Mom: the quarter WinTrainerBattle skims off
-- every won trainer battle (src/battle/gen2/Prize.lua) piles up in
-- wMomsMoney, and MomTriesToBuySomething is what she does with it.  Nothing
-- else in the game spends her savings.
--
-- Two shopping lists, and they behave completely differently:
--
--   MomItems_2 is a LADDER, walked once in order by wWhichMomItem.  Each row
--     carries the savings balance that unlocks it, so the four DOLLS -- the
--     only way a Gold player gets a CHARMANDER, CLEFAIRY or PIKACHU doll or
--     the BIG SNORLAX at all -- arrive at 10000, 30000, 50000 and 100000
--     saved.  A row is bought once and the index moves on.
--   MomItems_1 is a RANDOM consolation buy that fires only when the savings
--     land EXACTLY on a multiple of MOM_MONEY (2300) that
--     wMomItemTriggerBalance has not already passed.  It never advances
--     wWhichMomItem, so it cannot cost the player a rung of the ladder.
--
-- love-free and save-shaped: takes the Gold save (src/core/gen2/Save.lua) and
-- the event bitfield (src/world/gen2/Events.lua), so World, and the tests,
-- drive the same routine.

local Strings = require("src.core.Strings")
local Decorations = require("src.core.gen2.Decorations")

local MomShopping = {}

-- constants/misc_constants.asm.
local MOM_MONEY = 2300
MomShopping.MOM_MONEY = MOM_MONEY

-- constants/misc_constants.asm again; the same cap Prize and Save carry.
local MAX_MONEY = 999999

-- The `momitem kind` const_def 1 block at the top of mom_phone.asm.
local MOM_ITEM, MOM_DOLL = 1, 2

-- wNumPCItems: PC_ITEM_CAPACITY stacks of at most 99, which is what
-- ReceiveItem enforces for the PC list the way it does for the bag.
local PC_ITEM_CAPACITY = 50
local MAX_STACK = 99

-- data/items/mom_phone.asm, both tables verbatim and in order.  `trigger` is
-- MOMITEM_TRIGGER, `cost` MOMITEM_COST, `kind` MOMITEM_KIND and `item` is
-- MOMITEM_ITEM -- an item id for a MOM_ITEM row and a DECO_* id for a
-- MOM_DOLL one, because Mom_GiveItemOrDoll reaches the doll through
-- DecorationFlagAction_c, which takes the decoration itself rather than a
-- DECOFLAG_*.  The DECO numbers are the same ones
-- src/core/gen2/Decorations.lua indexes its ATTRIBUTES table by.
local function momitem(trigger, cost, kind, item)
  return { trigger = trigger, cost = cost, kind = kind, item = item }
end

local DECO_BIG_SNORLAX_DOLL = 26
local DECO_PIKACHU_DOLL = 30
local DECO_CLEFAIRY_DOLL = 32
local DECO_CHARMANDER_DOLL = 35

MomShopping.ITEMS_1 = {
  momitem(0, 600, MOM_ITEM, "SUPER_POTION"),
  momitem(0, 90, MOM_ITEM, "ANTIDOTE"),
  momitem(0, 180, MOM_ITEM, "POKE_BALL"),
  momitem(0, 450, MOM_ITEM, "ESCAPE_ROPE"),
  momitem(0, 500, MOM_ITEM, "GREAT_BALL"),
}

MomShopping.ITEMS_2 = {
  momitem(900, 600, MOM_ITEM, "SUPER_POTION"),
  momitem(4000, 270, MOM_ITEM, "REPEL"),
  momitem(7000, 600, MOM_ITEM, "SUPER_POTION"),
  momitem(10000, 1800, MOM_DOLL, DECO_CHARMANDER_DOLL),
  momitem(15000, 3000, MOM_ITEM, "MOON_STONE"),
  momitem(19000, 600, MOM_ITEM, "SUPER_POTION"),
  momitem(30000, 4800, MOM_DOLL, DECO_CLEFAIRY_DOLL),
  momitem(40000, 900, MOM_ITEM, "HYPER_POTION"),
  momitem(50000, 8000, MOM_DOLL, DECO_PIKACHU_DOLL),
  momitem(100000, 22800, MOM_DOLL, DECO_BIG_SNORLAX_DOLL),
}

-- data/text/common_1.asm, transcribed the way Specials' MOM_TEXT transcribes
-- the bank's own bank.  Mom never names what she bought, in either script.
-- `cont` folds into the same `\n` as `line`.
local MOM_HI = Strings.source("Hi, {PLAYER}!\nHow are you?")
local FOUND_AN_ITEM = Strings.source(
  "I found a useful\nitem shopping, so")
local FOUND_A_DOLL = Strings.source(
  "While shopping\ntoday, I saw this\nadorable doll, so")
local BOUGHT_WITH_YOUR_MONEY = Strings.source(
  "I bought it with\nyour money. Sorry!")
local ITS_IN_PC = Strings.source("It's in your PC.\nYou'll like it!")
local ITS_IN_YOUR_ROOM = Strings.source("It's in your room.\nYou'll love it!")

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- wWhichMomItem and wMomItemTriggerBalance, both seeded by NewGame
-- (engine/menus/intro_menu.asm): the ladder starts at its first rung and the
-- consolation threshold starts at MOM_MONEY.  Filled in lazily so a save made
-- before this existed gets the same two defaults rather than an unlocked
-- ladder.
function MomShopping.state(save)
  local mom = save and save.mom
  if type(mom) ~= "table" then return nil end
  if mom.whichItem == nil then mom.whichItem = 0 end
  if mom.triggerBalance == nil then mom.triggerBalance = MOM_MONEY end
  return mom
end

local function savedMoney(save)
  local mom = save and save.mom
  return (mom and mom.savedMoney) or 0
end

--------------------------------------------------------------------------
-- CheckBalance_MomItem2
--------------------------------------------------------------------------

-- Answers the row Mom is about to buy, as { row, set }: set 2 is the ladder
-- and set 1 the random consolation buy.  nil is the routine's `xor a / ret`,
-- i.e. she buys nothing this time.
--
-- `random(n)` returns 0..n-1, the way RandomRange does; injected so the test
-- is deterministic.
function MomShopping.pick(save, random)
  local mom = MomShopping.state(save)
  if not mom then return nil end
  local saved = savedMoney(save)

  -- `cp (MomItems_2.End - MomItems_2) / MOMITEM_SIZE / jr nc, .nope`: a
  -- ladder that has run out falls through to the consolation test rather
  -- than reading off the end of the table.
  local row = MomShopping.ITEMS_2[mom.whichItem + 1]
  if row and saved >= row.trigger then
    return { row = row, set = 2 }
  end

  -- .check_have_2300, which is a WHILE and not an IF: the balance is walked
  -- up in MOM_MONEY steps until it reaches or passes the savings, and only an
  -- EXACT landing buys anything.  Overshooting is `.less_than`, which returns
  -- with no carry and leaves the balance where the walk left it -- so the
  -- next call starts from the rung above and the same 2300 cannot pay twice.
  while mom.triggerBalance < saved do
    mom.triggerBalance = mom.triggerBalance + MOM_MONEY
  end
  if mom.triggerBalance ~= saved then return nil end
  mom.triggerBalance = mom.triggerBalance + MOM_MONEY
  local roll = 0
  if random then roll = math.floor(random(#MomShopping.ITEMS_1) or 0) end
  return { row = MomShopping.ITEMS_1[roll + 1], set = 1 }
end

--------------------------------------------------------------------------
-- Mom_GiveItemOrDoll
--------------------------------------------------------------------------

-- The PC half of ReceiveItem, over save.pcItems.  Returns false for a full
-- PC, which is the no-carry Mom_GiveItemOrDoll passes straight back up: the
-- purchase does not happen and nothing is deducted.
local function receiveItemToPc(save, id, data)
  if type(save) ~= "table" then return false end
  save.pcItems = save.pcItems or {}
  local pc = save.pcItems
  local held = pc[id] or 0
  local cap = (data and data.field and data.field.pcItemCap) or PC_ITEM_CAPACITY
  local function stacksFor(n) return math.ceil((n or 0) / MAX_STACK) end
  local used = 0
  for _, count in pairs(pc) do used = used + stacksFor(count) end
  -- engine/items/items.asm:156 PutItemInPocket
  if used + stacksFor(held + 1) - stacksFor(held) > cap then return false end
  pc[id] = held + 1
  return true
end

--------------------------------------------------------------------------
-- MomTriesToBuySomething
--------------------------------------------------------------------------

-- opts:
--   events        the src/world/gen2/Events.lua bitfield, for a doll's flag
--   data          the cache, for the PC's stack cap
--   random(n)     0..n-1, RandomRange
--   phoneService  GetMapPhoneService: false on a map with no reception, and
--                 the routine `ret`s before it looks at the balance at all
--
-- Returns the purchase, or nil.  A purchase is
-- { kind = "item" | "doll", item, cost, set, saved }, and MomShopping.pages
-- turns it into the four lines the phone call speaks.
function MomShopping.tryBuy(save, opts)
  opts = opts or {}
  if opts.phoneService == false then return nil end
  local mom = MomShopping.state(save)
  if not mom then return nil end

  -- wWhichMomItemSet is cleared before the balance check and only written by
  -- the consolation arm, which is what makes .ASMFunction's `and a / jr nz`
  -- advance wWhichMomItem for a LADDER buy alone.
  local pick = MomShopping.pick(save, opts.random)
  if not (pick and pick.row) then return nil end
  local row = pick.row

  if row.kind == MOM_DOLL then
    -- DecorationFlagAction_c with b = SET_FLAG, and the arm ends `scf`: a
    -- doll cannot fail, there is nowhere for it to not fit.
    Decorations.give(opts.events, row.item)
  elseif not receiveItemToPc(save, row.item, opts.data) then
    return nil
  end

  -- MomBuysItem_DeductFunds: TakeMoney out of wMomsMoney, which floors at
  -- zero rather than borrowing.
  mom.savedMoney = math.max(0, math.min(savedMoney(save), MAX_MONEY) - row.cost)
  if pick.set == 2 then mom.whichItem = mom.whichItem + 1 end

  return {
    kind = (row.kind == MOM_DOLL) and "doll" or "item",
    item = row.item,
    cost = row.cost,
    set = pick.set,
    saved = mom.savedMoney,
  }
end

-- Mom_GetScriptPointer's two scripts, .ItemScript and .DollScript: four
-- writetexts each, differing only in the middle line and the last.
--
-- The SOURCE strings, not looked-up ones: the caller feeds them to `rawtext`,
-- which is where the Strings lookup happens (src/script/gen2/Vm.lua).  A
-- module-level template resolved here would freeze the English before
-- Strings.load has a catalog, which is exactly what Strings.source exists to
-- avoid.
function MomShopping.pages(purchase)
  if not purchase then return {} end
  if purchase.kind == "doll" then
    return { MOM_HI, FOUND_A_DOLL, BOUGHT_WITH_YOUR_MONEY, ITS_IN_YOUR_ROOM }
  end
  return { MOM_HI, FOUND_AN_ITEM, BOUGHT_WITH_YOUR_MONEY, ITS_IN_PC }
end

return MomShopping

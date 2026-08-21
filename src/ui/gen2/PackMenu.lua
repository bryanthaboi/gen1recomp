-- Gen 2 PACK: four pockets instead of Gen 1's one bag.
--
-- constants/item_data_constants.asm orders them ITEM, KEY_ITEM, BALL, TM_HM,
-- and each item's own ItemAttributes row says which pocket it lives in -- so
-- the flat id->count inventory the engine already keeps is bucketed here at
-- draw time rather than stored four ways.
--
-- Left/right switch pockets, up/down scroll the list, A selects, B closes.
-- A TM/HM row shows the move it teaches (attributes carry `teaches`), which is
-- the whole reason the TM pocket is readable at all -- the item names are just
-- "TM01".."HM07".

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local PackGfx = require("src.ui.gen2.PackGfx")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")

local PackMenu = {}
PackMenu.__index = PackMenu
PackMenu.isOpaque = true

-- ItemsPocketMenuHeader (engine/items/pack.asm): menu_coords 7, 1, 19, 11 --
-- so the list body starts one row and one column inside that box, five rows of
-- two, with the quantity on each entry's second line.
local LIST_X = 8
local LIST_Y = 2
local LIST_SPACING = 2

-- Display order and titles.  The cart shows the pocket name in a tab strip
-- across the top; these are the strings it uses.
local POCKETS = {
  { id = "ITEM", label = "ITEMS" },
  { id = "BALL", label = "POKé BALLS" },
  { id = "KEY_ITEM", label = "KEY ITEMS" },
  { id = "TM_HM", label = "TM/HM" },
}

-- Five item rows fit under the tab strip, two lines each.
local VISIBLE_ROWS = 5

-- The item submenu (.ItemBallsKey_LoadSubmenu, engine/items/pack.asm:243).
-- A on a row does NOT use the item on the cart: it opens a menu whose rows are
-- picked from the item's own ITEMATTR_PERMISSIONS bits and its field-menu
-- nibble, and the six headers between MenuHeader_UsableKeyItem and
-- MenuHeader_HoldableItem are every combination of them:
--
--   CAN toss + CAN select + usable      USE / GIVE / TOSS / SEL / QUIT
--   CAN toss + CAN select + NOUSE             GIVE / TOSS / SEL / QUIT
--   CAN toss + cant select + usable     USE / GIVE / TOSS / QUIT
--   CAN toss + cant select + NOUSE            GIVE / TOSS / QUIT
--   cant toss + cant select             USE / QUIT
--   cant toss + CAN select              USE / SEL / QUIT
--
-- (the labels read backwards against the header names -- _CheckTossableItem
-- and CheckSelectableItem both answer NON-zero for the item that CANNOT, so
-- pack.asm's `.tossable` arm is the untossable one.)  The TM/HM pocket has a
-- pair of its own, .MenuHeader1 / .MenuHeader2 at pack.asm:160.
--
-- Without this menu a TOSS is unreachable and the PACK is a one-verb screen,
-- which is what "the pack only offers USE" is.
local SUBMENU_LABEL = {
  use = "USE", give = "GIVE", toss = "TOSS", sel = "SEL", quit = "QUIT",
}

-- _AskThrowAwayText / _AskQuantityThrowAwayText / _ThrewAwayText
-- (data/text/common_2.asm), the three lines TossMenu prints in order.
local TOSS_HOW_MANY = { "Throw away how", "many?" }

-- _AskItemMoveText (data/text/common_2.asm:322), printed while wSwitchItem
-- holds a row and the cursor is looking for its new home.
local ASK_ITEM_MOVE = { "Where should this", "be moved to?" }

-- _YouDontHaveAMonText and .AnEggCantHoldAnItemText, GiveItem's two refusals.
local NO_POKEMON = { "You don't have a", "#MON!" }
local EGG_CANT_HOLD = { "An EGG can't hold", "an item." }

-- The PACK's cursor bytes.  Every pocket menu restores its own cursor and
-- scroll before ScrollingMenu and writes them back after -- `ld a,
-- [wItemsPocketCursor] / ld [wMenuCursorPosition], a` ... `ld a, [wMenuCursorY]
-- / ld [wItemsPocketCursor], a` (engine/items/pack.asm:76), and the same pair
-- for wKeyItemsPocketCursor, wBallsPocketCursor and wTMHMPocketCursor -- while
-- InitPackBuffers opens the PACK on wLastPocket, which Pack's own exit path
-- stored.  They are WRAM, not save data: they last for the session and must not
-- survive a reload, and CleanUpBattleRAM is the only thing that clears them
-- (engine/battle/core.asm:7994, which pointedly leaves the TM/HM pair in place).
local function cursorStore(game)
  if not game then return nil end
  local mem = game.packCursor
  if not mem then
    mem = { cursor = {}, scroll = {} }
    game.packCursor = mem
  end
  return mem
end

-- OakThisIsntTheTimeText (data/text/common_2.asm), as the three rows it
-- prints: `text` / `line` / `cont`.  On the cart that is a two-row text box
-- that scrolls once; the PACK's description box here is four rows tall, so all
-- three fit at once and nothing has to scroll.  {PLAYER} is filled in from the
-- save, the way TextBox fills it everywhere else.
local OAK_THIS_ISNT_THE_TIME = {
  "OAK: {PLAYER}!",
  "This isn't the",
  "time to use that!",
}

-- RepelUsedEarlierIsStillInEffectText (data/text/common_3.asm): static, and
-- names REPEL no matter which of the three repel items is the one actually
-- still ticking down -- the cart never reads the active item back out to
-- print it.
local REPEL_STILL_ACTIVE = {
  "The REPEL used",
  "earlier is still",
  "in effect.",
}

function PackMenu:wantsFillScale() return true end
function PackMenu:drawsWidescreen() return true end

-- opts: save, items (items.lua), onChoose(itemId, count), onClose(),
-- pocket (starting pocket id), world (the overworld a field item acts on;
-- defaults to game.world, which is where Game2 keeps it),
-- give (DepositSellPack: the PACK is a CHOOSER, so selecting a row hands the
-- id back instead of running the item's field effect),
-- battle (BattlePack rather than the field Pack: a different jumptable, which
-- dispatches on the item's BATTLE menu nibble and never runs a field effect)
function PackMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PackMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.items = opts.items or (game and game.data and game.data.items)
  -- Bag.order / Bag.move read `.items` off an injectable data table, and the
  -- one this screen draws from is not always the Data singleton.
  self.bagData = { items = self.items }
  self.world = opts.world or (game and game.world)
  self.onChoose = opts.onChoose
  self.onClose = opts.onClose
  -- DepositSellPack rather than the PACK's own UseItem: a chooser must not run
  -- a rod or the ITEMFINDER on the way past (src/ui/gen2/HeldItemMenu.lua).
  self.give = opts.give and true or false
  self.battle = opts.battle and true or false
  self.cursorStore = cursorStore(game)
  self.pocketIndex = 1
  -- wLastPocket, unless the caller names one: DepositSellInitPackBuffers writes
  -- ITEM_POCKET over it, so an explicit pocket still wins.
  local startPocket = opts.pocket
    or (self.cursorStore and self.cursorStore.pocket)
  if startPocket then
    for i, p in ipairs(POCKETS) do
      if p.id == startPocket then self.pocketIndex = i break end
    end
  end
  self:restoreCursor()
  -- The cart's own PACK tiles, when the cache has them.
  self.gfx = PackGfx.new(game and game.data and game.data.gen2MenuGfx)
  self:rebuild()
  return self
end

function PackMenu:pocket()
  return POCKETS[self.pocketIndex]
end

-- The pair of loads each pocket menu runs before ScrollingMenu.  rebuild()
-- clamps the row afterwards, so a pocket that shrank while the PACK was closed
-- lands on its last entry rather than past it.
function PackMenu:restoreCursor()
  local mem = self.cursorStore
  local pocketId = self:pocket().id
  self.index = (mem and mem.cursor[pocketId]) or 1
  self.scroll = (mem and mem.scroll[pocketId]) or 0
end

-- And the pair of stores after it, plus Pack's `.done` writing wCurPocket into
-- wLastPocket.
function PackMenu:storeCursor()
  local mem = self.cursorStore
  if not mem then return end
  local pocketId = self:pocket().id
  mem.cursor[pocketId] = self.index
  mem.scroll[pocketId] = self.scroll
  mem.pocket = pocketId
end

-- Which pocket an item belongs to.  Items imported before attributes existed
-- have no `pocket`; treat those as general items rather than dropping them,
-- so an older cache still shows a full bag.
function PackMenu:pocketOf(itemId)
  local def = self.items and self.items[itemId]
  return (def and def.pocket) or "ITEM"
end

-- The name on the row.  An inventory key with no ItemAttributes row behind it
-- (an older cache, a mod's own item, a driver seeding an id that is not in
-- items.lua) still has to draw something a person can read, so the id stands
-- in for the name with its underscores opened out.
function PackMenu.label(itemId, def)
  if def and def.name then return def.name end
  return (tostring(itemId):gsub("_", " "))
end

-- TMHMPocket (engine/items/tmhm.asm) writes GetMoveName's string under the
-- TM's own name, so the second line of a TM row is the MOVE's name and not the
-- constant the attributes row carries.
function PackMenu:moveLabel(moveId)
  if not moveId then return nil end
  local moves = self.game and self.game.data and self.game.data.moves
  local def = moves and moves[moveId]
  return (def and def.name) or (tostring(moveId):gsub("_", " "))
end

function PackMenu:rebuild()
  local pocket = self:pocket().id
  local rows = {}
  local save = self.save
  local inventory = (save and save.inventory) or {}
  -- Row order IS wBagItems' order, which is what SELECT rewrites.
  local order = (save and save.inventory)
    and Bag.order(save, self.bagData) or {}
  for _, itemId in ipairs(order) do
    local raw = inventory[itemId]
    -- A count that is not a number at all (a hand-written save, a mod, an old
    -- migration) counts as one rather than raising out of the draw.
    local count = tonumber(raw) or (raw and 1) or 0
    if count > 0 and self:pocketOf(itemId) == pocket then
      local def = self.items and self.items[itemId]
      rows[#rows + 1] = {
        id = itemId,
        count = count,
        name = PackMenu.label(itemId, def),
        teaches = self:moveLabel(def and def.teaches),
        tmNumber = def and def.tmNumber,
        -- A KEY_ITEM never shows one, and engine/items/tmhm.asm:390 skips the
        -- count for an HM only -- a TM prints ×NN like any other stack.
        showCount = pocket == "ITEM" or pocket == "BALL"
          or (pocket == "TM_HM" and tostring(itemId):sub(1, 3) ~= "HM_"),
      }
    end
  end
  self.rows = rows
  self.index = math.min(self.index, #rows + 1)
  if self.index < 1 then self.index = 1 end
  self:ensureVisible()
end

function PackMenu:total()
  return #self.rows + 1 -- CANCEL
end

function PackMenu:isCancel()
  return self.index > #self.rows
end

function PackMenu:ensureVisible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, self:total() - VISIBLE_ROWS)))
end

function PackMenu:switchPocket(delta)
  -- The pocket being left keeps its own cursor and scroll; the one being
  -- entered restores its own (pack.asm:76).
  self:storeCursor()
  self.pocketIndex = (self.pocketIndex - 1 + delta) % #POCKETS + 1
  self:restoreCursor()
  self:rebuild()
  self:storeCursor()
end

-- The player name OakThisIsntTheTimeText addresses, same fallback the SAVE
-- screen uses when a driver runs without a named save.
function PackMenu:playerName()
  return (self.save and self.save.player and self.save.player.name) or "GOLD"
end

-- .Field (engine/items/pack.asm UseItem): a field-usable item runs its effect,
-- and only a NON-ZERO wItemEffectSucceeded sets PACKSTATE_QUITRUNSCRIPT --
-- which quits the PACK, and with it the START menu it was opened from, so the
-- script the effect queued can run in the overworld.  A zero drops into .Oak
-- instead, which prints inside the PACK and leaves it exactly where it was.
function PackMenu:exitToField()
  self:storeCursor()
  local stack = self.game and self.game.stack
  if stack and stack.clear then
    stack:clear()
  elseif self.onClose then
    -- No clear on this stack (a test harness, or a screen pushed on its own):
    -- at least give the pack back.
    self.onClose()
  end
end

-- Whether this pack is BattlePack (engine/items/pack.asm:627) rather than the
-- field Pack.  The two are separate jumptables: nothing opened over a battle
-- may reach a field effect, so the live overworld's own flag counts as well as
-- the caller saying so.
function PackMenu:inBattle()
  if self.battle then return true end
  return (self.world and self.world.battleActive) and true or false
end

-- A on a row.  A field item the world claims never reaches onChoose: the world
-- has already run its effect, and all that is left is which of UseItem's two
-- endings the PACK takes.
function PackMenu:useSelected()
  local row = self.rows[self.index]
  if not row then return end
  -- ScrollingMenu has returned by the time a row is acted on, so the pocket's
  -- cursor bytes are already written back before the submenu opens.
  self:storeCursor()
  if self.give then
    if self.onChoose then self.onChoose(row.id, row.count) end
    return
  end
  -- BattlePack's .Use dispatches on the item's BATTLE menu nibble, and the
  -- first four entries of its .ItemFunctionJumptable are all .Oak: a battle-
  -- NOUSE item prints OakThisIsntTheTimeText inside the pack and goes nowhere.
  -- Everything else is handed to the screen that opened this one
  -- (src/ui/gen2/BattleState.lua), which owns the balls, the X items and the
  -- party-target heals.  The FIELD jumptable is not on this path at all.
  if self:inBattle() then
    local def = self.items and self.items[row.id]
    if def and def.battleMenu == "ITEMMENU_NOUSE" then
      self.message = OAK_THIS_ISNT_THE_TIME
      return
    end
    if self.onChoose then
      self.staleRows = true
      self.onChoose(row.id, row.count)
    end
    return
  end
  local world = self.world
  local result, extra = nil, nil
  if world and world.useFieldItem then result, extra = world:useFieldItem(row.id) end
  if result then
    if result == "nowhere" then
      self.message = OAK_THIS_ISNT_THE_TIME
    elseif result == "coin_case" then
      -- _CoinCaseCountText (data/text/common_3.asm:336): "Coins:" then the
      -- count, text_decimal 4 digits with PRINTNUM_LEFTALIGN_F so no padding.
      self.message = { "Coins:", tostring(extra or 0) }
    elseif result == "repel_used" then
      -- ItemUsedText (data/text/common_3.asm): "<PLAYER> used the\n<ITEM>."
      -- World already wrote the counter and took the item out of the bag, so
      -- the row list is rebuilt under the message the way a TOSS would.
      self.message = { Strings("{PLAYER} used the"), row.name .. "." }
      self:rebuild()
    elseif result == "repel_active" then
      self.message = REPEL_STILL_ACTIVE
    elseif result == "trophy_sent" then
      -- _SentTrophyHomeText (data/text/common_3.asm).  Two pages on the cart
      -- with sound_dex_fanfare_50_79 between them; the PACK's box here holds
      -- all four rows at once, the way OAK_THIS_ISNT_THE_TIME's three fit.
      -- World has already set the decoration's flag and taken the box.
      self.message = { "There was a trophy", "inside!",
                       "{PLAYER} sent the", "trophy home." }
      self:rebuild()
    else
      self:exitToField()
    end
    return
  end
  -- UseItem's FIELD-pack tail (engine/items/tmhm.asm:73): a TM/HM row opens
  -- the party to teach, and a field-NOUSE item -- an X ATTACK or a POKé DOLL
  -- used from the field PACK -- prints OakThisIsntTheTimeText and goes
  -- nowhere (UseItem's jumptable's first four entries are all .Oak).  Both
  -- checks live behind `world.useFieldItem` on purpose: DepositSellPack (the
  -- mart's SELL, the item PC's DEPOSIT) is a chooser whose jumptable is four
  -- ScrollingMenus and never reaches tmhm.asm, so a TM picked there hands
  -- its row to onChoose like every other item instead of opening the teach
  -- party.  The battle pack returned above, and the catch tutorial's DUDE
  -- pack carries a stub world with no useFieldItem at all -- its POKE BALL
  -- is field-NOUSE and must still reach the throw.
  if world and world.useFieldItem then
    local def = self.items and self.items[row.id]
    if def and def.teaches then
      self:openTeachParty(row)
      return
    end
    if def and def.fieldMenu == "ITEMMENU_NOUSE" then
      self.message = OAK_THIS_ISNT_THE_TIME
      return
    end
  end
  if self.onChoose then
    -- The .Party flow runs OVER this pack and UseDisposableItem spends the
    -- item out from under the row list; rebuild on the first frame the pack
    -- owns again, which is UseItem .Party's own Pack_InitGFX redraw.
    self.staleRows = true
    self.onChoose(row.id, row.count)
  end
end

-- ------------------------------------------------------------- the submenu

-- Whether A on a row opens the item submenu.  Three packs on the cart skip it
-- and hand their row straight back, and all three are here:
--
--   DepositSellPack (pack.asm:931) -- the mart's SELL, the item PC's DEPOSIT
--     and HeldItemMenu's GIVE.  Its jumptable is four ScrollingMenus and
--     nothing else, which is why `give` and the empty-world callers answer
--     their chooser directly.
--   TutorialPack (pack.asm:1068) -- the DUDE's pack, same shape.
--   BattlePack (pack.asm:627) -- this one DOES have a submenu on the cart
--     (ItemSubmenu, USE / QUIT or QUIT alone), but it can neither toss, give
--     nor register, so the row it would add over this port's direct dispatch
--     is a second A press on the way to the same item effect.  The field
--     PACK is the one this bug is about; see src/ui/gen2/BattleState.lua for
--     the battle side.
--
-- The test is the world rather than a flag because that is what already tells
-- a field PACK from a chooser here: MartMenu:enterSell and
-- ItemPcMenu:enterDeposit both pass `world = {}` precisely so no field effect
-- can fire, and Game2's START-menu PACK passes the real overworld.
function PackMenu:hasSubmenu()
  if self.give then return false end
  if self:inBattle() then return false end
  local world = self.world
  return (world and world.useFieldItem) and true or false
end

-- ITEMATTR_PERMISSIONS' two bits and the field-menu nibble, as the cart reads
-- them.  An id with no attributes row at all (an older cache, a mod's item)
-- counts as tossable and unusable-for-SEL, which is the same lean the sell
-- gate and ItemPcMenu:cantToss take.
function PackMenu:submenuRows(itemId)
  local def = self.items and self.items[itemId]
  local canToss = not (def and def.canToss == false)
  local canSelect = def ~= nil and def.canSelect == true
  local usable = not (def and def.fieldMenu == "ITEMMENU_NOUSE")
  local rows = {}
  local function add(id) rows[#rows + 1] = id end
  if self:pocket().id == "TM_HM" then
    -- .TMHMPocketMenu's own pair: an HM cannot be tossed and gets USE / QUIT,
    -- a TM gets USE / GIVE / QUIT.  Neither has a TOSS row.
    add("use")
    if canToss then add("give") end
    add("quit")
    return rows
  end
  if not canToss then
    -- MenuHeader_UnusableItem / MenuHeader_UnusableKeyItem: the untossable arm
    -- never looks at the menu nibble, so a key item always offers USE.
    add("use")
    if canSelect then add("sel") end
    add("quit")
    return rows
  end
  if usable then add("use") end
  add("give")
  add("toss")
  if canSelect then add("sel") end
  add("quit")
  return rows
end

function PackMenu:openSubmenu()
  local row = self.rows[self.index]
  if not row then return end
  -- ScrollingMenu has returned by the time the submenu opens, so the pocket's
  -- cursor bytes are written back first (pack.asm:76).
  self:storeCursor()
  self.submenu = {
    row = row,
    rows = self:submenuRows(row.id),
    index = 1, -- `db 1 ; default option`
  }
end

function PackMenu:closeSubmenu()
  self.submenu = nil
end

function PackMenu:chooseSubmenu()
  local menu = self.submenu
  if not menu then return end
  local id = menu.rows[menu.index]
  local row = menu.row
  if id == "quit" then
    -- QuitItemSubmenu: a bare `ret`, back to the pocket list.
    self:closeSubmenu()
  elseif id == "use" then
    self:closeSubmenu()
    self:useSelected()
  elseif id == "sel" then
    self:closeSubmenu()
    self:registerSelected()
  elseif id == "toss" then
    self:closeSubmenu()
    self:tossItem(row)
  elseif id == "give" then
    self:closeSubmenu()
    self:giveItem(row)
  end
end

-- ------------------------------------------------------------------- TOSS

-- BuySellToss_InterpretJoypad (engine/items/buy_sell_toss.asm): up and down
-- wrap through the ends, left and right step by ten and clamp.  The same
-- stepper src/ui/gen2/ItemPcMenu.lua uses, because it is the same loop.
local function qtyStep(qty, max, delta)
  local n = qty + delta
  if delta == 1 then
    if n > max then n = 1 end
  elseif delta == -1 then
    if n < 1 then n = max end
  elseif delta > 0 then
    if n > max then n = max end
  else
    if n <= 0 then n = 1 end
  end
  return n
end

-- TossMenu (engine/items/pack.asm:477): "Throw away how many?" over
-- SelectQuantityToToss, then the count in a yes/no, then TossItem and
-- "Threw away <ITEM>(S)."  Backing out of either question is `jr c, .finish`
-- -- the item is untouched and the PACK is exactly where it was.
function PackMenu:tossItem(row)
  if not row then return end
  self.message = TOSS_HOW_MANY
  self.qtyState = {
    row = row,
    qty = 1,
    max = row.count or 1,
  }
end

function PackMenu:confirmToss()
  local state = self.qtyState
  if not state then return end
  self.qtyState = nil
  local row, qty = state.row, state.qty
  self.confirm = {
    prompt = { ("Throw away %d"):format(qty), row.name .. "(S)?" },
    -- YesNoBox opens on YES; B and NO are the same `jr c, .finish`.
    choice = 1,
    onYes = function()
      Bag.remove(self.save, row.id, qty)
      self:rebuild()
      self.message = { "Threw away", row.name .. "(S)." }
    end,
  }
end

-- ------------------------------------------------------------------- GIVE

-- GiveItem (engine/items/pack.asm:562): the party list under
-- PARTYMENUACTION_GIVE_ITEM ("To which <PK><MN>?"), an EGG refused with
-- .AnEggCantHoldAnItemText, and everything else handed to
-- TryGiveItemToPartymon -- which is exactly what the party's own GIVE row runs
-- (src/ui/gen2/HeldItemMenu.lua), so the two doors share one routine rather
-- than each growing a copy of the swap question and the mail keyboard.
function PackMenu:giveItem(row)
  local game = self.game
  local party = (self.save and self.save.party) or {}
  if #party == 0 then
    self.message = NO_POKEMON
    return
  end
  if not (game and game.stack) then return end
  if not pcall(Screens.get, game, "Gen2PartyMenu") then return end
  Screens.push(game, "Gen2PartyMenu", {
    save = self.save,
    prompt = "toWhich",
    onChoose = function(slot) self:giveToSlot(slot, row) end,
    onCancel = function()
      -- `.finish` / PartyMenuSelect's carry: back to the PACK.
      game.stack:pop()
      self:rebuild()
    end,
  })
end

function PackMenu:giveToSlot(slot, row)
  local game = self.game
  local mon = self.save and self.save.party and self.save.party[slot]
  if not (mon and game and game.stack) then return end
  if not pcall(Screens.get, game, "Gen2HeldItemMenu") then return end
  -- The GIVE/TAKE menu's own machinery, opened past its two rows: it already
  -- owns the text box over the party list, the swap question and the mail
  -- keyboard, and this is the same TryGiveItemToPartymon call its GIVE row
  -- makes.
  local held = Screens.build(game, "Gen2HeldItemMenu", {
    save = self.save,
    slot = slot,
    items = self.items,
    onClose = function()
      game.stack:pop()
      self:rebuild()
    end,
  })
  game.stack:push(held)
  if mon.isEgg then
    -- `cp EGG / jr nz, .give`: the refusal prints over the party list, which
    -- stays up (`jr .loop`) for another pick.
    held:say({ EGG_CANT_HOLD }, function() game.stack:pop() end)
    return
  end
  held:giveItem(row.id)
end

-- engine/items/tmhm.asm:73
function PackMenu:openTeachParty(row)
  local game = self.game
  local party = (self.save and self.save.party) or {}
  if #party == 0 then
    self.message = NO_POKEMON
    return
  end
  if not (game and game.stack) then return end
  if not pcall(Screens.get, game, "Gen2PartyMenu") then return end
  local def = self.items and self.items[row.id]
  local moveId = def and def.teaches
  local moves = game.data and game.data.moves
  local moveDef = moves and moves[moveId]
  local moveName = (moveDef and moveDef.name) or moveId
  self.staleRows = true
  Screens.push(game, "Gen2PartyMenu", {
    save = self.save,
    prompt = "teach",
    tmhm = { move = moveId },
    onCancel = function()
      game.stack:pop()
      self:rebuild()
    end,
    onChoose = function(_slot, mon)
      game.stack:pop()
      local species = game.data and game.data.pokemon
        and game.data.pokemon[mon.species]
      local allowed = false
      for _, id in ipairs((species and species.tmhm) or {}) do
        if id == moveId then allowed = true end
      end
      if not allowed then
        if game.say then
          game:say(("%s can't learn %s!"):format(
            require("src.battle.gen2.Mon").displayName(mon), moveName))
        end
        return
      end
      for _, move in ipairs(mon.moves or {}) do
        if move.id == moveId then
          if game.say then
            game:say(("%s already knows %s!"):format(
              require("src.battle.gen2.Mon").displayName(mon), moveName))
          end
          return
        end
      end
      if not game.learnMoveOn then return end
      game:learnMoveOn(mon, moveId, function(learned)
        if not learned then return end
        if tostring(row.id):sub(1, 3) == "HM_" then return end
        require("src.core.gen2.Happiness").change(mon, "LEARNMOVE")
        if game.consumeItem then game:consumeItem(row.id) end
        self:rebuild()
      end)
    end,
  })
end

function PackMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.staleRows then
    self.staleRows = nil
    self:rebuild()
  end
  -- Pack_PrintTextNoScroll ends on a `prompt`, so the message holds the PACK
  -- until a button clears it and the list is untouchable underneath.  The
  -- quantity selector is the one thing drawn OVER a message rather than under
  -- it: "Throw away how many?" is printed and SelectQuantityToToss runs on top
  -- of it, so that pair is stepped before the message is cleared.
  if self.qtyState then
    self:updateQuantity(input)
    return
  end
  -- engine/items/pack.asm:1237 Pack_InterpretJoypad .switching_item
  if self.switching then
    self:updateSwitch(input)
    return
  end
  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.message = nil
    end
    return
  end
  if self.confirm then
    self:updateConfirm(input)
    return
  end
  if self.submenu then
    self:updateSubmenu(input)
    return
  end
  if input:wasPressed("left") then
    self:switchPocket(-1)
    return
  elseif input:wasPressed("right") then
    self:switchPocket(1)
    return
  elseif input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or self:total()
    self:ensureVisible()
    return
  elseif input:wasPressed("down") then
    self.index = self.index < self:total() and self.index + 1 or 1
    self:ensureVisible()
    return
  elseif input:wasPressed("b") then
    self:storeCursor()
    if self.onClose then self.onClose() end
    return
  elseif input:wasPressed("a") then
    if self:isCancel() then
      self:storeCursor()
      if self.onClose then self.onClose() end
    elseif self:hasSubmenu() then
      -- Pack_InterpretJoypad's A falls through to .ItemBallsKey_LoadSubmenu:
      -- the row is chosen, not used.
      self:openSubmenu()
    else
      self:useSelected()
    end
    return
  elseif input:wasPressed("select") then
    self:armSwitch()
    return
  end
end

-- engine/items/pack.asm:1290 Pack_InterpretJoypad .select
function PackMenu:armSwitch()
  if self:isCancel() then return end
  if not self.rows[self.index] then return end
  self.switching = self.index
  self.message = ASK_ITEM_MOVE
end

-- `.switching_item` (engine/items/pack.asm:1297): A or SELECT places, B backs
-- out, and left/right cannot leave the pocket mid-move.
function PackMenu:updateSwitch(input)
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or self:total()
    self:ensureVisible()
  elseif input:wasPressed("down") then
    self.index = self.index < self:total() and self.index + 1 or 1
    self:ensureVisible()
  elseif input:wasPressed("a") or input:wasPressed("select") then
    self:placeSwitch()
  elseif input:wasPressed("b") then
    self:endSwitch()
  end
end

-- engine/items/pack.asm:1307 .place_insert / .end_switch
function PackMenu:placeSwitch()
  local from = self.switching
  local row = self.rows[from]
  if row and not self:isCancel() and self.index ~= from then
    Bag.move(self.save, row.id, self:pocket().id, self.index, self.bagData)
    self:rebuild()
    self:storeCursor()
  end
  self:endSwitch()
end

function PackMenu:endSwitch()
  self.switching = nil
  self.message = nil
end

-- VerticalMenu over the submenu rows: up/down wrap, A picks, B is the carry
-- that ExitMenu answers with (`ret c`), which is QUIT by another name.
function PackMenu:updateSubmenu(input)
  local menu = self.submenu
  local total = #menu.rows
  if input:wasPressed("up") then
    menu.index = menu.index > 1 and menu.index - 1 or total
  elseif input:wasPressed("down") then
    menu.index = menu.index < total and menu.index + 1 or 1
  elseif input:wasPressed("a") then
    self:chooseSubmenu()
  elseif input:wasPressed("b") then
    self:closeSubmenu()
  end
end

-- Toss_Sell_Loop: the count is stepped until A takes it or B backs out, and
-- backing out is the whole toss cancelled.
function PackMenu:updateQuantity(input)
  local state = self.qtyState
  if input:wasPressed("up") then
    state.qty = qtyStep(state.qty, state.max, 1)
  elseif input:wasPressed("down") then
    state.qty = qtyStep(state.qty, state.max, -1)
  elseif input:wasPressed("right") then
    state.qty = qtyStep(state.qty, state.max, 10)
  elseif input:wasPressed("left") then
    state.qty = qtyStep(state.qty, state.max, -10)
  elseif input:wasPressed("a") then
    self.message = nil
    self:confirmToss()
  elseif input:wasPressed("b") then
    self.qtyState = nil
    self.message = nil
  end
end

-- YesNoBox: up/down flip, A takes the highlighted row, B is NO.
function PackMenu:updateConfirm(input)
  local confirm = self.confirm
  if input:wasPressed("up") or input:wasPressed("down") then
    confirm.choice = confirm.choice == 1 and 2 or 1
  elseif input:wasPressed("b") then
    self.confirm = nil
    if confirm.onNo then confirm.onNo() end
  elseif input:wasPressed("a") then
    local yes = confirm.choice == 1
    self.confirm = nil
    if yes then
      if confirm.onYes then confirm.onYes() end
    elseif confirm.onNo then
      confirm.onNo()
    end
  end
end

-- RegisterItem (engine/items/pack.asm), the submenu's SEL row and its ONLY
-- door -- the cart's SELECT is the bag's own item shuffle (see armSwitch).
-- World:registerItem re-runs CheckSelectableItem's gate (TM/HM and anything
-- CANT_SELECT_F refuses), so it cannot register what the cart would not.
function PackMenu:registerSelected()
  if self:isCancel() then return end
  local row = self.rows[self.index]
  if not row then return end
  -- BattlePack shares Pack_InterpretJoypad, whose SELECT arm is the bag's own
  -- item shuffle rather than the field pack's item submenu, so nothing over a
  -- battle registers anything.
  local world = not self:inBattle() and self.world or nil
  local ok = world and world.registerItem and world:registerItem(row.id)
  if ok then
    -- RegisteredItemText: "Registered the\n<item>."
    self.message = { Strings("Registered the"), row.name .. "." }
  else
    -- CantRegisterText: "You can't register\nthat item."
    self.message = { Strings("You can't register"), Strings("that item.") }
  end
end

-- A TM or HM's `move` is what it teaches; the extractor carries it on the item
-- record, and moves.lua carries that move's own description.
function PackMenu:moveOf(itemId)
  local def = itemId and self.items and self.items[itemId]
  -- The extractor calls it `teaches`.
  return def and def.teaches or nil
end

-- The description under the list.  A TM shows the MOVE's description rather
-- than the item's -- which is what the cart's TM pocket does, and the whole
-- reason move descriptions are worth extracting.
function PackMenu:description()
  if self:isCancel() then return nil end
  local row = self.rows[self.index]
  if not row then return nil end
  local moveId = self:moveOf(row.id)
  if moveId then
    local moves = self.game and self.game.data and self.game.data.moves
    local moveDef = moves and moves[moveId]
    if moveDef and moveDef.description then return moveDef.description end
  end
  local def = self.items and self.items[row.id]
  return def and def.description or nil
end

-- The list, description and cursor, on top of whatever chrome was drawn.
--
-- PlaceMenuItemQuantity (engine/menus/menu_2.asm:10) writes the ×N one row
-- DOWN and one column RIGHT of the name -- the quantity is the entry's second
-- line, not a right-aligned column, which is why every PACK row is two tiles
-- tall.  Its `lb bc, 1, 2` is a TWO-digit field with the leading digit blanked,
-- so the ones digit sits at name + 3 whether the count is 5 or 50.
--
-- ScrollingMenu_PlaceCursor (engine/menus/scrolling_menu.asm:438) marks the
-- row SELECT armed with the hollow ▷ while the solid ▶ goes on looking.
function PackMenu:drawList(listX, listY)
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local ty = listY + (row - 1) * LIST_SPACING
    if i <= #self.rows then
      local entry = self.rows[i]
      if i == self.index then
        Chrome.cursor(listX - 1, ty)
      elseif i == self.switching then
        Chrome.cursor(listX - 1, ty, true)
      end
      Chrome.print(entry.name, listX, ty)
      if entry.teaches then
        -- The TM pocket puts the move the TM teaches on that second line, and
        -- its count at listX + 9 (engine/items/tmhm.asm:392) -- on the LABEL's
        -- line here, since the move name owns the one below it.
        Chrome.print(entry.teaches, listX + 1, ty + 1)
        if entry.showCount then
          Chrome.print("\xc3\x97" .. Chrome.number(entry.count, 2),
            listX + 9, ty)
        end
      elseif entry.showCount then
        Chrome.print("\xc3\x97" .. Chrome.number(entry.count, 2),
          listX + 1, ty + 1)
      end
    elseif i == self:total() then
      if i == self.index then Chrome.cursor(listX - 1, ty) end
      Chrome.print("CANCEL", listX, ty)
    end
  end
end

function PackMenu:drawDescription(ty)
  -- Pack_PrintTextNoScroll writes over the same box the description lives in,
  -- so while a message is up it IS the box's contents.  TossMenu's yes/no
  -- (AskQuantityThrowAwayText through MenuTextbox) is the same box: the
  -- question is printed there and the YES/NO window opens over the list.
  local lines = self.message or (self.confirm and self.confirm.prompt)
  if lines then
    local name = self:playerName()
    for i, line in ipairs(lines) do
      Chrome.print((line:gsub("{PLAYER}", name)), 1, ty + i - 2)
    end
    return
  end
  local description = self:description()
  if not description then return end
  -- Item descriptions join their two lines with the '<NEXT>' the extractor
  -- leaves in place, and $4e steps SCREEN_WIDTH * 2 from the line's own
  -- start (home/text.asm NextLineChar) -- TWO rows, the same metric every
  -- text box uses.  PrintItemDescription writes them from decoord 1, 14, so
  -- the second line is row 16.  '\n' covers hand-written data.
  local first, second = description:match("^(.-)<NEXT>(.*)$")
  if not first then first, second = description:match("^(.-)\n(.*)$") end
  Chrome.print(first or description, 1, ty)
  if second then Chrome.print(second, 1, ty + 2) end
end

-- The submenu box.  Every one of the seven headers is `menu_coords 0, top,
-- SCREEN_WIDTH - 14, TEXTBOX_Y - 1` -- the left six columns, growing UPWARD
-- from the description box so its bottom edge never moves.  The five-row
-- header is the one exception, reaching one row further down (TEXTBOX_Y), so
-- the bottom is 12 there and 11 otherwise; either way the first label sits one
-- row inside (STATICMENU_NO_TOP_SPACING) with the cursor a column left of it.
function PackMenu:drawSubmenu()
  local menu = self.submenu
  local count = #menu.rows
  local bottom = count >= 5 and 12 or 11
  local top = bottom - count * 2
  Chrome.box(0, top, 7, bottom - top + 1)
  for i, id in ipairs(menu.rows) do
    local ty = top + 1 + (i - 1) * 2
    if i == menu.index then Chrome.cursor(1, ty) end
    Chrome.print(SUBMENU_LABEL[id] or id, 2, ty)
  end
end

-- engine/items/buy_sell_toss.asm:133 BuySellToss_UpdateQuantityDisplay
function PackMenu:drawQuantity()
  Chrome.box(15, 9, 5, 3)
  Chrome.print("\xc3\x97" .. Chrome.number(self.qtyState.qty, 2, true), 16, 10)
end

-- YesNoBox's own coords, the same box every other Gen 2 screen here draws.
function PackMenu:drawYesNo()
  Chrome.box(14, 7, 6, 5)
  Chrome.print("YES", 16, 8)
  Chrome.print("NO", 16, 10)
  Chrome.cursor(15, self.confirm.choice == 1 and 8 or 10)
end

function PackMenu:drawOverlays()
  if self.submenu then self:drawSubmenu() end
  if self.qtyState then self:drawQuantity() end
  if self.confirm then self:drawYesNo() end
end

function PackMenu:drawPanel()
  if self.gfx:available() then
    -- Pack_InitGFX's screen: the header strip, the patterned left column, the
    -- bag picture for this pocket and the pocket plaque, then Textbox at
    -- (0,12) for the item description.
    self.gfx:draw(self:pocket().id)
    Chrome.box(0, PackGfx.DESCRIPTION_Y, 20, 6)
    self:drawList(LIST_X, LIST_Y)
    self:drawDescription(PackGfx.DESCRIPTION_Y + 2)
    self:drawOverlays()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- No pack tiles in the cache (an import from before the pack stage): plain
  -- boxes, the layout this screen shipped with.
  Chrome.clear()
  Chrome.box(0, 0, 20, 3)
  Chrome.print(self:pocket().label, 2, 1)
  Chrome.box(0, 3, 20, 12)
  self:drawList(2, 4)
  Chrome.box(0, 12, 20, 6)
  self:drawDescription(14)
  self:drawOverlays()
  love.graphics.setColor(1, 1, 1, 1)
end

function PackMenu:draw()
  self:drawPanel()
end

function PackMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

PackMenu.POCKETS = POCKETS

return PackMenu

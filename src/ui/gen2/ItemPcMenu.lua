-- The player's item PC: _PlayersPC and the three item rows behind it
-- (engine/events/pokecenter_pc.asm PlayerWithdrawItemMenu /
-- PlayerDepositItemMenu / PlayerTossItemMenu), plus TossItemFromPC
-- (engine/pokemon/mon_menu.asm).  Both of the cart's callers land here:
--
--   PlayersPC        PLAYERSPC_NORMAL -- the <PLAYER>'s PC row of the
--                    Pokecenter's whose-PC menu (src/ui/gen2/CenterPcMenu.lua):
--                    WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / MAIL BOX /
--                    LOG OFF
--   _PlayersHousePC  PLAYERSPC_HOUSE -- the bedroom PC's whole screen: the
--                    boot sound and PlayersPCTurnOnText first, DECORATION on
--                    the list, TURN OFF instead of LOG OFF, and the answer
--                    carried back out (TRUE only when a decoration moved) so
--                    PlayersHousePCScript can take its `.Warp` arm
--
-- The menu's rows run through the ui.pc.items hook -- the same name and the
-- same (game, items) payload the Gen 1 PC uses
-- (src/world/OverworldController.lua openPC) -- with the exit row appended
-- after it, the way that site appends LOG OFF.
--
-- Items live on save.pcItems, the id -> count map ReceiveItem's PC half
-- already writes (src/core/gen2/MomShopping.lua receiveItemToPc): fifty
-- distinct stacks of at most 99, like wPCItems.  DEPOSIT opens the PACK as a
-- chooser held by this screen, exactly the arrangement the mart's sell flow
-- uses (src/ui/gen2/MartMenu.lua enterSell), because DepositSellPack is the
-- same routine on the cart.

local Bag = require("src.inventory.Bag")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Logger = require("src.core.Logger")
local PcItems = require("src.core.gen2.PcItems")
local RomText = require("src.core.RomText")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")
local WaitPlaySFX = require("src.ui.gen2.WaitPlaySFX")

local ItemPcMenu = {}
ItemPcMenu.__index = ItemPcMenu
-- ../pokecrystal/engine/events/pokecenter_pc.asm:231
ItemPcMenu.isOpaque = false

-- ../pokecrystal/engine/events/pokecenter_pc.asm:330
local CLEARS_SCREEN = { withdraw = true, deposit = true, toss = true }

-- MAX_PC_ITEMS stacks of at most MAX_ITEM_STACK (constants/item_constants.asm),
-- the same pair src/core/gen2/MomShopping.lua enforces for Mom's deliveries.
local PC_ITEM_CAPACITY = 50
local MAX_STACK = 99

local function stacksFor(n) return math.ceil((n or 0) / MAX_STACK) end

-- PlayersPCMenuData .PlayersPCMenuPointers strings, verbatim.  .WhichPC picks
-- which rows a caller sees: PLAYERSPC_NORMAL ends on LOG OFF, PLAYERSPC_HOUSE
-- carries DECORATION and ends on TURN OFF.
local ENTRIES = {
  { id = "withdraw", romLabel = "PlayersPCMenuData.WithdrawItem", builtin = true },
  { id = "deposit", romLabel = "PlayersPCMenuData.DepositItem", builtin = true },
  { id = "toss", romLabel = "PlayersPCMenuData.TossItem", builtin = true },
  { id = "mailbox", romLabel = "PlayersPCMenuData.MailBox", builtin = true },
}
local LOG_OFF = {
  id = "logoff", romLabel = "PlayersPCMenuData.LogOff", builtin = true,
}
local DECORATION = {
  id = "decoration", romLabel = "PlayersPCMenuData.Decoration", builtin = true,
}
local TURN_OFF = {
  id = "turnoff", romLabel = "PlayersPCMenuData.TurnOff", builtin = true,
}

local TEXT = {
  turnedOn = "_PlayersPCTurnOnText",
  noBagRoom = "_PlayersPCNoRoomWithdrawText",
  withdrew = "_PlayersPCWithdrewItemsText",
  withdrawHowMany = "_PlayersPCHowManyWithdrawText",
  noPcRoom = "_PlayersPCNoRoomDepositText",
  deposited = "_PlayersPCDepositItemsText",
  noItems = "_PlayersPCNoItemsText",
  depositHowMany = "_PlayersPCHowManyDepositText",
  tooImportant = "_ItemsTooImportantText",
  tossHowMany = "_ItemsTossOutHowManyText",
  throwAway = "_ItemsThrowAwayText",
  discarded = "_ItemsDiscardedText",
  whatDo = "_PlayersPCAskWhatDoText",
}

-- engine/menus/scrolling_menu.asm:408
local SCROLL_CANCEL = "ScrollingMenu_UpdateDisplay.CancelString"
-- home/menu.asm:438-439
local YES_LABEL, NO_LABEL = "YesNoMenuHeader.MenuData#1", "YesNoMenuHeader.MenuData#2"

function ItemPcMenu:romLines(label, ...)
  local body = CommonText.plain(RomText(self.data, label, nil, ...))
  local lines = {}
  for line in (body .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

function ItemPcMenu:romPages(label, ...)
  return { self:romLines(label, ...) }
end

-- ui.pc.items identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

-- PCItemsJoypad's ScrollingMenu is `db 4, 8 ; rows, columns`.
local VISIBLE_ROWS = 4

-- .PCItemsMenuData is menu_coords 4, 1 (engine/events/pokecenter_pc.asm:641),
-- and ScrollingMenu_UpdateDisplay (engine/menus/scrolling_menu.asm:359) adds
local LIST_X = 5

-- charmap.asm: the quantity glyph.
local TIMES = "\xc3\x97"

function ItemPcMenu:wantsFillScale() return true end

function ItemPcMenu:setPhase(phase)
  self.phase = phase
  self.isOpaque = CLEARS_SCREEN[phase] or false
end

-- opts: save, items (items.lua), house (PLAYERSPC_HOUSE: boot text,
--       DECORATION row, TURN OFF), events (wEventFlags, for the decoration
--       menu), onClose(changedDecorations)
function ItemPcMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, ItemPcMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.items = opts.items or (game and game.data and game.data.items)
  self.data = game and game.data
  self.onClose = opts.onClose
  self.house = opts.house and true or false
  self.events = opts.events
  -- wChangedDecorations, carried out so `special PlayersHousePC` can answer
  -- TRUE and PlayersHousePCScript can take its `.Warp` arm.
  self.changedDecorations = false
  if self.save then self.save.pcItems = self.save.pcItems or {} end
  local entries = {}
  for i, entry in ipairs(ENTRIES) do entries[i] = entry end
  if self.house then entries[#entries + 1] = DECORATION end
  -- Same hook name and same (game, items) payload as the Gen 1 PC menu
  -- (src/world/OverworldController.lua openPC), so one mod source can add a
  -- row to both generations' PCs.  Unguarded, like that site: the list is
  -- built once per session, not per frame.  A hook that answers with anything
  -- but a table is degraded to the vanilla list.
  local hooked = Runtime.call("ui.pc.items", sameItems, game, entries)
  if type(hooked) == "table" then
    entries = hooked
  else
    Logger.error("ui.pc.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  -- LOG OFF / TURN OFF is appended AFTER the hook, exactly as the Gen 1 site
  -- appends LOG OFF: a mod cannot orphan the way out of the PC.
  entries[#entries + 1] = self.house and TURN_OFF or LOG_OFF
  self.entries = entries
  self.index = 1
  self:setPhase("menu")
  self.rows = {}
  self.listIndex = 1
  self.scroll = 0
  self.message = nil
  self.qtyState = nil
  self.confirm = nil
  if self.house then
    -- _PlayersHousePC: PC_PlayBootSound, then PlayersPCTurnOnText.
    self:playPcSfx("Sfx_BootPc")
    self:say(self:romPages(TEXT.turnedOn))
  end
  return self
end

function ItemPcMenu:playSfx(name)
  local data = self.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then
    Sound.play(data, name)
  end
end

-- engine/events/pokecenter_pc.asm:200
function ItemPcMenu:playPcSfx(name)
  Sound.waitSfxDone()
  self:playSfx(name)
end

-- engine/events/pokecenter_pc.asm:195
function ItemPcMenu:playPcSfxTwice(name)
  self:playPcSfx(name)
  self.repeatSfx = WaitPlaySFX.arm(name)
end

function ItemPcMenu:tickRepeatSfx()
  local pending = self.repeatSfx
  if not pending then return false end
  if WaitPlaySFX.waiting(pending, self.game) then return true end
  self.repeatSfx = nil
  self:playPcSfx(pending.name)
  return false
end

function ItemPcMenu:playerName()
  local player = self.save and self.save.player
  return (player and player.name) or "GOLD"
end

-- A queue of text pages, each a list of lines; A or B turns them, and the last
-- one runs onDone.  The item PC's messages never log off by themselves, which
-- is _PlayersPC's `.loop`: a refusal drops back into the same menu.
function ItemPcMenu:say(pages, onDone)
  Typer.say(self, pages, onDone, { expand = function(line)
    return (line:gsub("{PLAYER}", self:playerName()))
  end })
end

function ItemPcMenu:close()
  -- _PlayersHousePC plays PC_PlayShutdownSound only on the unchanged arm;
  -- `.changed_deco_tiles` leaves for the map reload without it.
  if self.house and not self.changedDecorations then
    self:playPcSfx("Sfx_ShutDownPc")
  end
  if self.onClose then self.onClose(self.changedDecorations) end
end

-- ---------------------------------------------------------------- the items

function ItemPcMenu:def(id)
  return self.items and self.items[id]
end

-- _CheckTossableItem: KEY ITEMs and HMs answer non-zero.  The extractor
-- carries that as `canToss = false`; an id with no attributes row counts as
-- tossable, the way the PACK's sell gate treats it.
function ItemPcMenu:cantToss(id)
  local def = self:def(id)
  return def ~= nil and def.canToss == false
end

-- engine/events/pokecenter_pc.asm:647
function ItemPcMenu:rebuild()
  local pc = (self.save and self.save.pcItems) or {}
  local order = self.save and PcItems.order(self.save, self.items) or {}
  local rows = {}
  for slot = 1, #order do
    local id = order[slot]
    local count = pc[id] or 0
    if count > 0 then
      local def = self:def(id)
      local remaining = count
      while remaining > 0 do
        local n = math.min(remaining, MAX_STACK)
        rows[#rows + 1] = {
          id = id, count = n,
          name = (def and def.name) or id,
          slot = slot,
        }
        remaining = remaining - n
      end
    end
  end
  self.rows = rows
  if self.listIndex > #rows + 1 then self.listIndex = #rows + 1 end
  if self.listIndex < 1 then self.listIndex = 1 end
  self:ensureVisible()
end

function ItemPcMenu:listTotal()
  return #self.rows + 1 -- CANCEL
end

function ItemPcMenu:ensureVisible()
  if self.listIndex <= self.scroll then
    self.scroll = self.listIndex - 1
  elseif self.listIndex > self.scroll + VISIBLE_ROWS then
    self.scroll = self.listIndex - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, self:listTotal() - VISIBLE_ROWS)))
end

-- ReceiveItem over wPCItems: the add tops up every existing stack of that id
-- and spills the rest into a new one, so it only needs a free stack when the
-- room in place is short.  False is the no-carry the deposit turns into
-- _PlayersPCNoRoomDepositText.
-- engine/items/items.asm:156 PutItemInPocket
function ItemPcMenu:pcAdd(id, qty)
  local pc = self.save.pcItems
  local held = pc[id] or 0
  local used = 0
  for _, count in pairs(pc) do used = used + stacksFor(count) end
  local need = stacksFor(held + qty) - stacksFor(held)
  if used + need > PC_ITEM_CAPACITY then return false end
  pc[id] = held + qty
  return true
end

function ItemPcMenu:pcRemove(id, qty)
  local pc = self.save.pcItems
  local held = (pc[id] or 0) - qty
  pc[id] = held > 0 and held or nil
end

-- HasNoItems (engine/pokemon/mon_menu.asm): every pocket, TM/HMs included --
-- which the flat inventory answers in one walk.  Badges share the table but
-- are not bag items.
local function bagIsEmpty(save)
  for id, count in pairs((save and save.inventory) or {}) do
    if (count or 0) > 0 and not Bag.isBadge(id) then return false end
  end
  return true
end

-- BuySellToss_InterpretJoypad (engine/items/buy_sell_toss.asm): up and down
-- wrap through the ends, left and right step by ten and clamp.
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

-- prompt is the two lines under the selector; onAccept(qty) commits.
function ItemPcMenu:askQuantity(max, prompt, onAccept)
  self.qtyState = { qty = 1, max = max, prompt = prompt, onAccept = onAccept }
end

-- ------------------------------------------------------------ the three rows

function ItemPcMenu:withdraw(row, qty)
  -- PlayerWithdrawItemMenu .withdraw: ReceiveItem into the bag first; only a
  -- carry tosses the stack out of the PC.
  if not Bag.add(self.save, row.id, qty, self.data) then
    self:say(self:romPages(TEXT.noBagRoom))
    return
  end
  self:pcRemove(row.id, qty)
  self:rebuild()
  self:say(self:romPages(TEXT.withdrew, qty, row.name))
end

function ItemPcMenu:chooseWithdraw()
  local row = self.rows[self.listIndex]
  if not row then
    self:setPhase("menu")
    return
  end
  -- .Submenu: an item without a quantity attribute (a KEY ITEM in the PC) is
  -- always x1; everything else asks _PlayersPCHowManyWithdrawText.
  if self:cantToss(row.id) then
    self:withdraw(row, 1)
    return
  end
  self:askQuantity(row.count,
    self:romLines(TEXT.withdrawHowMany),
    function(qty) self:withdraw(row, qty) end)
end

function ItemPcMenu:deposit(id, name, qty)
  if not self:pcAdd(id, qty) then
    self:say(self:romPages(TEXT.noPcRoom))
    return
  end
  Bag.remove(self.save, id, qty)
  if self.pack then self.pack:rebuild() end
  self:say(self:romPages(TEXT.deposited, qty, name))
end

function ItemPcMenu:enterDeposit()
  -- .CheckItemsInBag: an empty bag never opens the PACK.
  if bagIsEmpty(self.save) then
    self:say(self:romPages(TEXT.noItems))
    return
  end
  self:setPhase("deposit")
  -- DepositSellPack: the PACK as a chooser, held and drawn by this screen the
  -- way the mart holds its sell PACK.  `world = {}` keeps field items inert.
  self.pack = Screens.build(self.game, "Gen2PackMenu", {
    save = self.save,
    items = self.items,
    world = {},
    onChoose = function(id, count) self:offerToDeposit(id, count) end,
    onClose = function() self:leaveDeposit() end,
  })
end

function ItemPcMenu:leaveDeposit()
  self.pack = nil
  self:setPhase("menu")
end

function ItemPcMenu:offerToDeposit(id, count)
  if (count or 0) < 1 then return end
  local def = self:def(id)
  local name = (def and def.name) or id
  -- .DepositItem (engine/events/pokecenter_pc.asm:504): an item with no
  -- quantity is always x1 and never reaches .AskQuantity.
  if self:cantToss(id) then
    self:deposit(id, name, 1)
    return
  end
  self:askQuantity(count,
    self:romLines(TEXT.depositHowMany),
    function(qty) self:deposit(id, name, qty) end)
end

function ItemPcMenu:chooseToss()
  local row = self.rows[self.listIndex]
  if not row then
    self:setPhase("menu")
    return
  end
  -- TossItemFromPC .key_item -> .CantToss.
  if self:cantToss(row.id) then
    self:say(self:romPages(TEXT.tooImportant))
    return
  end
  self:askQuantity(row.count,
    self:romLines(TEXT.tossHowMany, row.name),
    function(qty)
      -- .ItemsThrowAwayText's yes/no sits between the count and the toss.
      self.confirm = {
        prompt = self:romLines(TEXT.throwAway, qty, row.name),
        choice = 1,
        onYes = function()
          self:pcRemove(row.id, qty)
          self:rebuild()
          self:say(self:romPages(TEXT.discarded, row.name))
        end,
      }
    end)
end

-- ------------------------------------------------------------------ the menu

function ItemPcMenu:choose()
  local entry = self.entries[self.index]
  if not entry then return end
  local game = self.game
  if entry.id == "withdraw" or entry.id == "toss" then
    self:setPhase(entry.id)
    self.listIndex = 1
    self.scroll = 0
    -- engine/events/pokecenter_pc.asm:569
    self.switching = nil
    self:rebuild()
    return
  end
  if entry.id == "deposit" then
    self:enterDeposit()
    return
  end
  if entry.id == "mailbox" then
    if not (game and game.stack) then return end
    Screens.push(game, "Gen2MailboxMenu", {
      save = self.save,
      onClose = function() game.stack:pop() end,
    })
    return
  end
  if entry.id == "decoration" then
    if not (game and game.stack) then return end
    Screens.push(game, "Gen2DecorationMenu", {
      save = self.save,
      events = self.events,
      onDone = function(changed)
        self.changedDecorations = self.changedDecorations or changed or false
        game.stack:pop()
      end,
    })
    return
  end
  -- logoff / turnoff: PlayerLogOffMenu serves both rows.
  self:close()
end


-- engine/events/pokecenter_pc.asm:622
-- engine/items/switch_items.asm:27
function ItemPcMenu:armSwitch()
  if not self.rows[self.listIndex] then return end
  self.switching = self.listIndex
end

-- engine/events/pokecenter_pc.asm:604
function ItemPcMenu:updateSwitch(input)
  if input:wasPressed("up") then
    self.listIndex = self.listIndex > 1 and self.listIndex - 1
      or self:listTotal()
    self:ensureVisible()
  elseif input:wasPressed("down") then
    self.listIndex = self.listIndex < self:listTotal() and self.listIndex + 1
      or 1
    self:ensureVisible()
  elseif input:wasPressed("a") or input:wasPressed("select") then
    self:placeSwitch()
  elseif input:wasPressed("b") then
    -- engine/events/pokecenter_pc.asm:615
    self.switching = nil
  end
end

-- engine/events/pokecenter_pc.asm:620
-- engine/items/switch_items.asm:12
function ItemPcMenu:placeSwitch()
  local held = self.rows[self.switching]
  local target = self.rows[self.listIndex]
  self:playPcSfxTwice("Sfx_SwitchPokemon")
  if not target then return end
  if held and self.save and target.slot ~= held.slot then
    PcItems.move(self.save, held.id, target.slot, self.items)
    self:rebuild()
  end
  self.switching = nil
end

-- ------------------------------------------------------------------- update

function ItemPcMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  -- engine/events/pokecenter_pc.asm:195
  if self:tickRepeatSfx() then return end

  if self.message then
    Typer.step(self)
    if Typer.typing(self) then return end
    if input:wasPressed("a") or input:wasPressed("b") then
      local m = self.message
      if m.page < #m.pages then
        Typer.turn(self, m)
        return
      end
      self.message = nil
      if m.onDone then m.onDone() end
    end
    return
  end

  if self.qtyState then
    local q = self.qtyState
    if input:wasPressed("up") then
      q.qty = qtyStep(q.qty, q.max, 1)
    elseif input:wasPressed("down") then
      q.qty = qtyStep(q.qty, q.max, -1)
    elseif input:wasPressed("right") then
      q.qty = qtyStep(q.qty, q.max, 10)
    elseif input:wasPressed("left") then
      q.qty = qtyStep(q.qty, q.max, -10)
    elseif input:wasPressed("b") then
      self.qtyState = nil
    elseif input:wasPressed("a") then
      self.qtyState = nil
      q.onAccept(q.qty)
    end
    return
  end

  if self.confirm then
    local c = self.confirm
    if input:wasPressed("up") or input:wasPressed("down") then
      c.choice = c.choice == 1 and 2 or 1
    elseif input:wasPressed("b") then
      -- home/menu.asm:345
      self:playSfx("Sfx_ReadText2")
      self.confirm = nil
      if c.onNo then c.onNo() end
    elseif input:wasPressed("a") then
      self:playSfx("Sfx_ReadText2")
      self.confirm = nil
      if c.choice == 1 then
        if c.onYes then c.onYes() end
      elseif c.onNo then
        c.onNo()
      end
    end
    return
  end

  if self.phase == "deposit" then
    if self.pack then
      self.pack:update(_dt)
    else
      self:setPhase("menu")
    end
    return
  end

  if self.phase == "withdraw" or self.phase == "toss" then
    if self.switching then
      self:updateSwitch(input)
      return
    end
    if input:wasPressed("up") then
      self.listIndex = self.listIndex > 1 and self.listIndex - 1
        or self:listTotal()
      self:ensureVisible()
    elseif input:wasPressed("down") then
      self.listIndex = self.listIndex < self:listTotal() and self.listIndex + 1
        or 1
      self:ensureVisible()
    elseif input:wasPressed("b") then
      -- engine/menus/scrolling_menu.asm:24
      self:playSfx("Sfx_ReadText2")
      self:setPhase("menu")
      self.switching = nil
    elseif input:wasPressed("a") then
      self:playSfx("Sfx_ReadText2")
      if self.phase == "withdraw" then
        self:chooseWithdraw()
      else
        self:chooseToss()
      end
    elseif input:wasPressed("select") then
      self:armSwitch()
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.entries
  elseif input:wasPressed("down") then
    self.index = self.index < #self.entries and self.index + 1 or 1
  elseif input:wasPressed("a") then
    -- home/menu.asm:476
    self:playSfx("Sfx_ReadText2")
    self:choose()
  elseif input:wasPressed("b") then
    -- DoNthMenu's carry is `.turn_off`.
    self:playSfx("Sfx_ReadText2")
    self:close()
  end
end

-- --------------------------------------------------------------------- draw

function ItemPcMenu:drawBottomLines(lines)
  Chrome.box(0, 12, 20, 6)
  if not lines then return end
  local name = self:playerName()
  local startY = #lines >= 3 and 13 or 14
  for i, line in ipairs(lines) do
    Chrome.print((line:gsub("{PLAYER}", name)), 1, startY + (i - 1) * 2)
  end
end

function ItemPcMenu:drawList()
  Chrome.box(0, 0, 20, 12)
  -- engine/events/pokecenter_pc.asm:628 .a_1 -> home/menu.asm:50
  -- engine/events/pokecenter_pc.asm:605 .moving_stuff_around
  local picked = not self.switching
    and (self.message or self.qtyState or self.confirm) and true or false
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local ty = row * 2
    if i <= #self.rows then
      local entry = self.rows[i]
      -- home/menu.asm:50
      if i == self.listIndex then
        Chrome.cursor(LIST_X - 1, ty, picked)
      elseif i == self.switching then
        Chrome.cursor(LIST_X - 1, ty, true)
      end
      Chrome.print(entry.name, LIST_X, ty)
      -- PlaceMenuItemQuantity (engine/menus/menu_2.asm:18, :24)
      if not self:cantToss(entry.id) then
        Chrome.print(TIMES .. Chrome.number(entry.count, 2), LIST_X + 9, ty + 1)
      end
    elseif i == self:listTotal() then
      if i == self.listIndex then Chrome.cursor(LIST_X - 1, ty, picked) end
      Chrome.print(self:romLines(SCROLL_CANCEL)[1], LIST_X, ty)
    end
  end
  -- UpdateItemDescription under the list.
  local row = self.rows[self.listIndex]
  local def = row and self:def(row.id)
  local description = def and def.description
  if description then
    local first, second = description:match("^(.-)<NEXT>(.*)$")
    if not first then first, second = description:match("^(.-)\n(.*)$") end
    Chrome.box(0, 12, 20, 6)
    Chrome.print(first or description, 1, 14)
    if second then Chrome.print(second, 1, 16) end
  else
    Chrome.box(0, 12, 20, 6)
  end
end

function ItemPcMenu:drawPanel()
  -- ../pokecrystal/engine/pokemon/bills_pc_top.asm:231
  if self.isOpaque then Chrome.clear() end

  if self.phase == "deposit" and self.pack then
    self.pack:drawPanel()
  elseif self.phase == "withdraw" or self.phase == "toss" then
    self:drawList()
  else
    -- _PlayersPCAskWhatDoText, printed under the list the whole time.  The
    -- box goes down first: the menu window overlays it where the house's
    -- six-row list runs past row 12, the way the cart's windows stack.
    self:drawBottomLines(self:romLines(TEXT.whatDo))
    -- PlayersPCMenuData is menu_coords 0, 0, 15, 12; the house list is one
    -- row taller than that box, so size it to the entries.
    Chrome.box(0, 0, 16, math.max(12, #self.entries * 2 + 2))
    for i, entry in ipairs(self.entries) do
      local ty = i * 2
      if i == self.index then Chrome.cursor(1, ty) end
      local label = entry.label
      if entry.romLabel then
        label = self:romLines(entry.romLabel)[1]
      elseif entry.builtin then
        label = Strings(label)
      end
      Chrome.print(label, 2, ty)
    end
  end

  if self.qtyState then
    local q = self.qtyState
    self:drawBottomLines(q.prompt)
    -- engine/items/buy_sell_toss.asm:205 TossItem_MenuHeader, :133
    Chrome.box(15, 9, 5, 3)
    Chrome.print(TIMES, 16, 10)
    Chrome.print(Chrome.number(q.qty, 2, true), 17, 10)
  elseif self.confirm then
    self:drawBottomLines(self.confirm.prompt)
    Chrome.box(14, 7, 6, 5)
    Chrome.print(self:romLines(YES_LABEL)[1], 16, 8)
    Chrome.print(self:romLines(NO_LABEL)[1], 16, 10)
    Chrome.cursor(15, self.confirm.choice == 1 and 8 or 10)
  elseif self.message then
    self:drawBottomLines(
      Typer.text(self, self.message.pages[self.message.page]))
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function ItemPcMenu:draw()
  self:drawPanel()
end

ItemPcMenu.ENTRIES = ENTRIES
ItemPcMenu.PC_ITEM_CAPACITY = PC_ITEM_CAPACITY

return ItemPcMenu

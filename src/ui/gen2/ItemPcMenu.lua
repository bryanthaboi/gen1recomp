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
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")

local ItemPcMenu = {}
ItemPcMenu.__index = ItemPcMenu
ItemPcMenu.isOpaque = true

-- MAX_PC_ITEMS stacks of at most MAX_ITEM_STACK (constants/item_constants.asm),
-- the same pair src/core/gen2/MomShopping.lua enforces for Mom's deliveries.
local PC_ITEM_CAPACITY = 50
local MAX_STACK = 99

-- PlayersPCMenuData .PlayersPCMenuPointers strings, verbatim.  .WhichPC picks
-- which rows a caller sees: PLAYERSPC_NORMAL ends on LOG OFF, PLAYERSPC_HOUSE
-- carries DECORATION and ends on TURN OFF.
local ENTRIES = {
  { id = "withdraw", label = "WITHDRAW ITEM" },
  { id = "deposit", label = "DEPOSIT ITEM" },
  { id = "toss", label = "TOSS ITEM" },
  { id = "mailbox", label = "MAIL BOX" },
}
local LOG_OFF = { id = "logoff", label = "LOG OFF" }
local DECORATION = { id = "decoration", label = "DECORATION" }
local TURN_OFF = { id = "turnoff", label = "TURN OFF" }

-- ui.pc.items identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

-- PCItemsJoypad's ScrollingMenu is `db 4, 8 ; rows, columns`.
local VISIBLE_ROWS = 4

-- charmap.asm: the quantity glyph.
local TIMES = "\xc3\x97"

function ItemPcMenu:wantsFillScale() return true end
function ItemPcMenu:drawsWidescreen() return true end

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
  self.phase = "menu"
  self.rows = {}
  self.listIndex = 1
  self.scroll = 0
  self.message = nil
  self.qtyState = nil
  self.confirm = nil
  if self.house then
    -- _PlayersHousePC: PC_PlayBootSound, then PlayersPCTurnOnText.
    self:playSfx("Sfx_BootPc")
    self:say({ { "{PLAYER} turned on", "the PC." } })
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

function ItemPcMenu:playerName()
  local player = self.save and self.save.player
  return (player and player.name) or "GOLD"
end

-- A queue of text pages, each a list of lines; A or B turns them, and the last
-- one runs onDone.  The item PC's messages never log off by themselves, which
-- is _PlayersPC's `.loop`: a refusal drops back into the same menu.
function ItemPcMenu:say(pages, onDone)
  self.message = { pages = pages, page = 1, onDone = onDone }
end

function ItemPcMenu:close()
  -- _PlayersHousePC plays PC_PlayShutdownSound only on the unchanged arm;
  -- `.changed_deco_tiles` leaves for the map reload without it.
  if self.house and not self.changedDecorations then
    self:playSfx("Sfx_ShutDownPc")
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

function ItemPcMenu:rebuild()
  local pc = (self.save and self.save.pcItems) or {}
  local rows = {}
  for id, count in pairs(pc) do
    if (count or 0) > 0 then
      local def = self:def(id)
      rows[#rows + 1] = {
        id = id, count = count,
        name = (def and def.name) or id,
        index = def and def.index or math.huge,
      }
    end
  end
  -- wPCItems keeps acquisition order; without that recorded, item id order is
  -- the stable choice, the same sort the PACK uses.
  table.sort(rows, function(a, b)
    if a.index ~= b.index then return a.index < b.index end
    return a.id < b.id
  end)
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

-- ReceiveItem over wPCItems: a new id needs one of the fifty stacks, a grown
-- one may not pass 99.  False is the no-carry the deposit turns into
-- _PlayersPCNoRoomDepositText.
function ItemPcMenu:pcAdd(id, qty)
  local pc = self.save.pcItems
  local held = pc[id] or 0
  if held == 0 then
    local stacks = 0
    for _, count in pairs(pc) do
      if (count or 0) > 0 then stacks = stacks + 1 end
    end
    if stacks >= PC_ITEM_CAPACITY then return false end
  end
  if held + qty > MAX_STACK then return false end
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
    self:say({ { "There's no room", "for more items." } })
    return
  end
  self:pcRemove(row.id, qty)
  self:rebuild()
  self:say({ { ("Withdrew %d"):format(qty), row.name .. "(S)." } })
end

function ItemPcMenu:chooseWithdraw()
  local row = self.rows[self.listIndex]
  if not row then
    self.phase = "menu"
    return
  end
  -- .Submenu: an item without a quantity attribute (a KEY ITEM in the PC) is
  -- always x1; everything else asks _PlayersPCHowManyWithdrawText.
  if self:cantToss(row.id) then
    self:withdraw(row, 1)
    return
  end
  self:askQuantity(row.count,
    { "How many do you", "want to withdraw?" },
    function(qty) self:withdraw(row, qty) end)
end

function ItemPcMenu:deposit(id, name, qty)
  if not self:pcAdd(id, qty) then
    self:say({ { "There's no room to", "store items." } })
    return
  end
  Bag.remove(self.save, id, qty)
  if self.pack then self.pack:rebuild() end
  self:say({ { ("Deposited %d"):format(qty), name .. "(S)." } })
end

function ItemPcMenu:enterDeposit()
  -- .CheckItemsInBag: an empty bag never opens the PACK.
  if bagIsEmpty(self.save) then
    self:say({ { "No items here!" } })
    return
  end
  self.phase = "deposit"
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
  self.phase = "menu"
end

function ItemPcMenu:offerToDeposit(id, count)
  -- .TryDepositItem's `.no_toss` arm is a bare ret: a KEY ITEM or HM stays in
  -- the bag with no message at all.
  if self:cantToss(id) then return end
  if (count or 0) < 1 then return end
  local def = self:def(id)
  local name = (def and def.name) or id
  self:askQuantity(count,
    { "How many do you", "want to deposit?" },
    function(qty) self:deposit(id, name, qty) end)
end

function ItemPcMenu:chooseToss()
  local row = self.rows[self.listIndex]
  if not row then
    self.phase = "menu"
    return
  end
  -- TossItemFromPC .key_item -> .CantToss.
  if self:cantToss(row.id) then
    self:say({ { "That's too impor-", "tant to toss out!" } })
    return
  end
  self:askQuantity(row.count,
    { "Toss out how many", row.name .. "(S)?" },
    function(qty)
      -- .ItemsThrowAwayText's yes/no sits between the count and the toss.
      self.confirm = {
        prompt = { ("Throw away %d"):format(qty), row.name .. "(S)?" },
        choice = 1,
        onYes = function()
          self:pcRemove(row.id, qty)
          self:rebuild()
          self:say({ { "Discarded", row.name .. "(S)." } })
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
    self.phase = entry.id
    self.listIndex = 1
    self.scroll = 0
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

-- ------------------------------------------------------------------- update

function ItemPcMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      local m = self.message
      if m.page < #m.pages then
        m.page = m.page + 1
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
      self.confirm = nil
      if c.onNo then c.onNo() end
    elseif input:wasPressed("a") then
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
      self.phase = "menu"
    end
    return
  end

  if self.phase == "withdraw" or self.phase == "toss" then
    if input:wasPressed("up") then
      self.listIndex = self.listIndex > 1 and self.listIndex - 1
        or self:listTotal()
      self:ensureVisible()
    elseif input:wasPressed("down") then
      self.listIndex = self.listIndex < self:listTotal() and self.listIndex + 1
        or 1
      self:ensureVisible()
    elseif input:wasPressed("b") then
      self.phase = "menu"
    elseif input:wasPressed("a") then
      if self.phase == "withdraw" then
        self:chooseWithdraw()
      else
        self:chooseToss()
      end
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.entries
  elseif input:wasPressed("down") then
    self.index = self.index < #self.entries and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") then
    -- DoNthMenu's carry is `.turn_off`.
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
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local ty = row * 2
    if i <= #self.rows then
      local entry = self.rows[i]
      if i == self.listIndex then Chrome.cursor(5, ty) end
      Chrome.print(entry.name, 6, ty)
      -- PlaceMenuItemQuantity (engine/menus/menu_2.asm:24): the xNN is the
      -- entry's second line, right-aligned in a blank-padded 2-digit field.
      Chrome.print(TIMES .. Chrome.number(entry.count, 2), 7, ty + 1)
    elseif i == self:listTotal() then
      if i == self.listIndex then Chrome.cursor(5, ty) end
      Chrome.print("CANCEL", 6, ty)
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
  Chrome.clear()

  if self.phase == "deposit" and self.pack then
    self.pack:drawPanel()
  elseif self.phase == "withdraw" or self.phase == "toss" then
    self:drawList()
  else
    -- _PlayersPCAskWhatDoText, printed under the list the whole time.  The
    -- box goes down first: the menu window overlays it where the house's
    -- six-row list runs past row 12, the way the cart's windows stack.
    self:drawBottomLines({ "What do you want", "to do?" })
    -- PlayersPCMenuData is menu_coords 0, 0, 15, 12; the house list is one
    -- row taller than that box, so size it to the entries.
    Chrome.box(0, 0, 16, math.max(12, #self.entries * 2 + 2))
    for i, entry in ipairs(self.entries) do
      local ty = i * 2
      if i == self.index then Chrome.cursor(1, ty) end
      Chrome.print(entry.label, 2, ty)
    end
  end

  if self.qtyState then
    local q = self.qtyState
    self:drawBottomLines(q.prompt)
    Chrome.box(7, 15, 13, 3)
    Chrome.print(TIMES, 8, 16)
    Chrome.print(Chrome.number(q.qty, 2, true), 9, 16)
  elseif self.confirm then
    self:drawBottomLines(self.confirm.prompt)
    Chrome.box(14, 7, 6, 5)
    Chrome.print("YES", 16, 8)
    Chrome.print("NO", 16, 10)
    Chrome.cursor(15, self.confirm.choice == 1 and 8 or 10)
  elseif self.message then
    self:drawBottomLines(self.message.pages[self.message.page])
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function ItemPcMenu:draw()
  self:drawPanel()
end

function ItemPcMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(math.floor((winW - 160 * scale) / 2),
    math.floor((winH - 144 * scale) / 2))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

ItemPcMenu.ENTRIES = ENTRIES
ItemPcMenu.PC_ITEM_CAPACITY = PC_ITEM_CAPACITY

return ItemPcMenu
